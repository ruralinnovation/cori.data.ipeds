# Write raw IPEDS data to S3
#
# Reads NCES CSV files exactly as published -- no column renaming, no value
# transformation -- and writes them to S3 as parquet under data_raw/.
#
# S3 layout:
#   s3://{bucket}/data_raw/survey={survey}/year={year}/part-0.parquet
#
# The only additions to the raw data are:
#   - `year`   (integer) -- vintage year, derivable from the S3 path but
#              included for portability when reading a single file directly
#
# All column names are original NCES uppercase (UNITID, COUNTYCD, CARNEGIE,
# C00CARNEGIE, AWLEVEL, etc.). All values are original including IPEDS sentinel
# codes (-1, -2, -3). Reconciliation happens downstream in reconcile_vintage().


# URL and filename patterns per survey ----------------------------------------

# NCES data download URLs follow a predictable pattern.
# IC data lives in the HD (Header) file, not the IC (programs) file.
# Completions splits across two files we use: C{year}_A is awards by program
# (one row per institution x CIP x award level x major number) and C{year}_C
# is the completer headcount (one row per institution x award level category).
.raw_download_url <- function(survey, year) {
  table <- .raw_table_name(survey, year)
  sprintf("https://nces.ed.gov/ipeds/datacenter/data/%s.zip", table)
}

# Primary table name used in the ZIP filename and download URL.
.raw_table_name <- function(survey, year) {
  switch(survey,
    institutional_characteristics = sprintf("HD%d",   year),
    completions                   = sprintf("C%d_A",  year),
    completers                    = sprintf("C%d_C",  year),
    grad_rates                    = sprintf("GR%d",   year),
    stop(sprintf("Unknown survey '%s'", survey))
  )
}

# Candidate CSV base filenames inside the ZIP (tried in order; _rv preferred).
.raw_csv_candidates <- function(survey, year) {
  table <- .raw_table_name(survey, year)
  c(tolower(table), table)
}


# Normalise NCES column names so a codebook entry can match them.
#
# Three things in the source files break a naive match:
#   - mixed case in earlier vintages
#   - trailing spaces (CNRALW in completions, GRNRALW in grad rates, every
#     year; DFRCGID in HD2010)
#   - a UTF-8 byte-order mark, which NCES began shipping on some 2023+ files.
#     Left in place the BOM becomes part of the first column name, so nothing
#     matches UNITID and .select_codebook_columns() silently drops it --
#     which is exactly how the completers county aggregation came back empty
#     for 2023 and 2024. The BOM can arrive as the character U+FEFF, as the
#     raw bytes EF BB BF, or already escaped to the literal text
#     "<ef><bb><bf>" depending on the read path, so rather than matching each
#     form we strip any leading non-alphanumeric characters. Every NCES
#     column name is alphanumeric, so this cannot remove anything real.
.normalize_nces_names <- function(x) {
  x <- toupper(trimws(x))
  # DuckDB escapes invalid UTF-8 bytes to visible text when it writes parquet,
  # so a BOM can also reach us as the literal "<EF><BB><BF>". Strip that form
  # first: the general rule below would stop at the "E" and leave a remnant.
  x <- sub("^(<EF><BB><BF>)+", "", x)
  sub("^[^A-Z0-9]+", "", x)
}


# Core raw read ---------------------------------------------------------------

#' Read a raw IPEDS CSV for one survey vintage
#'
#' Downloads (if not cached) and reads the NCES CSV with no transformation.
#' Column names are original NCES uppercase. Values are original including
#' IPEDS sentinel codes. Adds a \code{year} column.
#'
#' @param survey Character. One of \code{"institutional_characteristics"}, \code{"completions"},
#'   \code{"grad_rates"}.
#' @param year Integer. Vintage year.
#' @param staging_dir Character. Local staging directory.
#'   Default: \code{"data/ipeds"}.
#'
#' @return Data frame: original NCES columns plus \code{year}.
#' @keywords internal
read_ipeds_raw <- function(survey, year, staging_dir = "data/ipeds") {
  url        <- .raw_download_url(survey, year)
  candidates <- .raw_csv_candidates(survey, year)

  download_ipeds(survey, year, url, staging_dir)
  extract_dir <- unzip_ipeds(survey, year, staging_dir)
  csv_path    <- resolve_ipeds_csv(extract_dir, candidates)

  df <- .read_csv_safe(csv_path)

  names(df) <- .normalize_nces_names(names(df))

  # Add year as the only metadata column
  df$year <- as.integer(year)

  df
}


# S3 write --------------------------------------------------------------------

#' Write raw IPEDS data for one survey vintage to S3
#'
#' Reads the NCES CSV via \code{read_ipeds_raw()}, writes it as parquet
#' locally, then uploads to S3. Skips if already written unless
#' \code{overwrite = TRUE}.
#'
#' @param survey Character.
#' @param year Integer.
#' @param staging_dir Character. Default: \code{"data/ipeds"}.
#' @param s3_bucket Character. Default: \code{"cori.data.ipeds"}.
#' @param s3_path_prefix Character. Default: \code{""}.
#' @param overwrite Logical. Default: \code{FALSE}.
#' @param sync_to_s3 Logical. Set \code{FALSE} for local-only testing.
#'   Default: \code{TRUE}.
#'
#' @return Invisibly returns a one-row manifest data frame.
#' @keywords internal
write_ipeds_raw_to_s3 <- function(
    survey,
    year,
    staging_dir    = "data/ipeds",
    s3_bucket      = "cori.data.ipeds",
    s3_path_prefix = "",
    overwrite      = FALSE,
    sync_to_s3     = TRUE
) {
  local_dir  <- file.path(staging_dir, "s3_raw",
                           sprintf("survey=%s", survey),
                           sprintf("year=%d",   year))
  local_path <- file.path(local_dir, "part-0.parquet")

  if (!overwrite && file.exists(local_path)) {
    message(sprintf("  raw %s %d: already written locally, skipping", survey, year))
  } else {
    message(sprintf("  Reading raw %s %d...", survey, year))
    df <- read_ipeds_raw(survey, year, staging_dir)

    n <- nrow(df)
    message(sprintf("  raw %s %d: %s rows, %d cols",
                    survey, year, format(n, big.mark = ","), ncol(df) - 1L))

    dir.create(local_dir, recursive = TRUE, showWarnings = FALSE)
    .write_parquet(df, local_path)
  }

  if (sync_to_s3) {
    s3_uri <- sprintf("s3://%s/%sdata_raw/survey=%s/year=%d/",
                      s3_bucket, s3_path_prefix, survey, year)
    message(sprintf("  Uploading raw %s %d to S3...", survey, year))
    .s3_upload(local_path, s3_uri)
  }

  invisible(.manifest_row(survey, year, "raw", local_path))
}


#' Write raw IPEDS data for multiple surveys and years to S3
#'
#' Loops over all combinations of surveys and years, calling
#' \code{write_ipeds_raw_to_s3()} for each. Skips already-written vintages
#' unless \code{overwrite = TRUE}.
#'
#' @param years Integer vector. Default: 2010 to current year.
#' @param surveys Character vector. Default: all three surveys.
#' @param staging_dir Character.
#' @param s3_bucket Character.
#' @param s3_path_prefix Character.
#' @param overwrite Logical.
#' @param sync_to_s3 Logical.
#'
#' @return Invisibly returns a data frame summarising what was written.
#' @keywords internal
write_ipeds_raw_batch <- function(
    years          = IPEDS_START_YEAR:IPEDS_END_YEAR,
    surveys        = IPEDS_SURVEYS,
    staging_dir    = "data/ipeds",
    s3_bucket      = "cori.data.ipeds",
    s3_path_prefix = "",
    overwrite      = FALSE,
    sync_to_s3     = TRUE
) {
  results <- list()

  for (yr in years) {
    message(sprintf("\n--- Year %d ---", yr))
    for (sv in surveys) {
      result <- tryCatch(
        write_ipeds_raw_to_s3(
          survey         = sv,
          year           = yr,
          staging_dir    = staging_dir,
          s3_bucket      = s3_bucket,
          s3_path_prefix = s3_path_prefix,
          overwrite      = overwrite,
          sync_to_s3     = sync_to_s3
        ),
        error = function(e) {
          message(sprintf("  ERROR: raw %s %d: %s", sv, yr, e$message))
          NULL
        }
      )
      if (!is.null(result)) results <- c(results, list(result))
    }
  }

  invisible(do.call(rbind, results))
}

