# Orchestrate the full IPEDS ETL pipeline
#
# Three-layer incremental pipeline:
#   Layer 1: data_raw        -- untouched NCES parquet (write_raw_to_s3.R)
#   Layer 2: data_institution -- codebook-renamed, geo-attached parquet
#   Layer 3: data_county     -- tidy county aggregations parquet
#
# Each layer is skipped if already written (unless overwrite = TRUE).
# Historic years are never reprocessed once written.
#
# S3 layout:
#   s3://{bucket}/data_raw/survey={survey}/year={year}/part-0.parquet
#   s3://{bucket}/data_institution/survey={survey}/year={year}/part-0.parquet
#   s3://{bucket}/data_county/year={year}/part-0.parquet


# Institution layer -----------------------------------------------------------

#' Write processed institution-level data for one year to S3
#'
#' Reads from local raw parquet, processes all three surveys via
#' \code{process_ipeds_institution_all()}, writes one parquet per survey
#' locally, then uploads to S3. Skips if already written.
#'
#' @param year Integer.
#' @param staging_dir Character. Default: \code{"data/ipeds"}.
#' @param s3_bucket Character. Default: \code{"cori.data.ipeds"}.
#' @param s3_path_prefix Character. Default: \code{""}.
#' @param overwrite Logical. Default: \code{FALSE}.
#' @param sync_to_s3 Logical. Default: \code{TRUE}.
#'
#' @return Invisibly returns a data frame summarising what was written.
#' @keywords internal
write_ipeds_institution_to_s3 <- function(
    year,
    staging_dir    = "data/ipeds",
    s3_bucket      = "cori.data.ipeds",
    s3_path_prefix = "",
    overwrite      = FALSE,
    sync_to_s3     = TRUE
) {
  codebook    <- load_codebook()
  inst_list   <- NULL
  results     <- list()

  for (sv in IPEDS_SURVEYS) {
    local_dir  <- file.path(staging_dir, "s3_institution",
                            sprintf("survey=%s", sv),
                            sprintf("year=%d",   year))
    local_path <- file.path(local_dir, "part-0.parquet")

    if (!overwrite && file.exists(local_path)) {
      message(sprintf("  institution %s %d: already written locally, skipping", sv, year))
      results <- c(results, list(.manifest_row(sv, year, "institution", local_path)))
      next
    }

    # Process all three surveys together once (shares geo lookup)
    if (is.null(inst_list)) {
      message(sprintf("  Processing institution data for %d...", year))
      inst_list <- tryCatch(
        process_ipeds_institution_all(year, staging_dir, codebook),
        error = function(e) {
          message(sprintf("  ERROR: institution %d: %s", year, e$message))
          NULL
        }
      )
      if (is.null(inst_list)) break
    }

    df <- inst_list[[sv]]
    if (is.null(df)) {
      message(sprintf("  institution %s %d: no data, skipping", sv, year))
      next
    }

    dir.create(local_dir, recursive = TRUE, showWarnings = FALSE)
    .write_parquet(df, local_path)
    message(sprintf("  institution %s %d: %s rows written", sv, year,
                    format(nrow(df), big.mark = ",")))

    if (sync_to_s3) {
      s3_uri <- sprintf("s3://%s/%sdata_institution/survey=%s/year=%d/",
                        s3_bucket, s3_path_prefix, sv, year)
      .s3_upload(local_path, s3_uri)
    }

    results <- c(results, list(.manifest_row(sv, year, "institution", local_path)))
  }

  invisible(do.call(rbind, results))
}


# County layer ----------------------------------------------------------------

#' Write processed county-level data for one year to S3
#'
#' Reads institution-level parquets (written by \code{write_ipeds_institution_to_s3()}),
#' derives county aggregations, writes one parquet per year, uploads to S3.
#' Skips if already written.
#'
#' @param year Integer.
#' @param staging_dir Character. Default: \code{"data/ipeds"}.
#' @param s3_bucket Character. Default: \code{"cori.data.ipeds"}.
#' @param s3_path_prefix Character. Default: \code{""}.
#' @param overwrite Logical. Default: \code{FALSE}.
#' @param sync_to_s3 Logical. Default: \code{TRUE}.
#'
#' @return Invisibly returns a one-row manifest data frame.
#' @keywords internal
write_ipeds_county_to_s3 <- function(
    year,
    staging_dir    = "data/ipeds",
    s3_bucket      = "cori.data.ipeds",
    s3_path_prefix = "",
    overwrite      = FALSE,
    sync_to_s3     = TRUE
) {
  local_dir  <- file.path(staging_dir, "s3_county", sprintf("year=%d", year))
  local_path <- file.path(local_dir, "part-0.parquet")

  if (!overwrite && file.exists(local_path)) {
    message(sprintf("  county %d: already written locally, skipping", year))
    return(invisible(.manifest_row("county", year, "county", local_path)))
  }

  # Load institution parquets for this year
  inst_list <- .read_institution_local(year, staging_dir)
  if (is.null(inst_list)) {
    message(sprintf("  county %d: no institution data found, skipping", year))
    return(invisible(NULL))
  }

  message(sprintf("  Deriving county data for %d...", year))
  county <- tryCatch(
    process_ipeds_county(inst_list),
    error = function(e) {
      message(sprintf("  ERROR: county %d: %s", year, e$message))
      NULL
    }
  )

  if (is.null(county) || nrow(county) == 0) {
    message(sprintf("  county %d: no county rows produced, skipping", year))
    return(invisible(NULL))
  }

  dir.create(local_dir, recursive = TRUE, showWarnings = FALSE)
  .write_parquet(county, local_path)
  message(sprintf("  county %d: %s rows written", year,
                  format(nrow(county), big.mark = ",")))

  if (sync_to_s3) {
    s3_uri <- sprintf("s3://%s/%sdata_county/year=%d/",
                      s3_bucket, s3_path_prefix, year)
    .s3_upload(local_path, s3_uri)
  }

  invisible(.manifest_row("county", year, "county", local_path))
}


# Full pipeline ---------------------------------------------------------------

#' Run the full IPEDS ETL pipeline for a range of years
#'
#' Runs all three layers (raw → institution → county) for each year in order.
#' Each layer skips already-written vintages unless \code{overwrite = TRUE}.
#'
#' @param years Integer vector. Default: 2010 to current year.
#' @param staging_dir Character.
#' @param s3_bucket Character.
#' @param s3_path_prefix Character.
#' @param overwrite Logical. Reprocess even if already written. Default: \code{FALSE}.
#' @param sync_to_s3 Logical. Upload to S3 after writing locally. Default: \code{TRUE}.
#' @param layers Character vector. Which layers to run. Default: all three.
#'
#' @return Invisibly returns a manifest data frame.
#' @export
write_ipeds_all <- function(
    years          = IPEDS_START_YEAR:IPEDS_END_YEAR,
    staging_dir    = "data/ipeds",
    s3_bucket      = "cori.data.ipeds",
    s3_path_prefix = "",
    overwrite      = FALSE,
    sync_to_s3     = TRUE,
    layers         = c("raw", "institution", "county")
) {
  results <- list()

  for (yr in years) {
    message(sprintf("\n=== Year %d ===", yr))

    if ("raw" %in% layers) {
      r <- tryCatch(
        write_ipeds_raw_batch(
          years          = yr,
          staging_dir    = staging_dir,
          s3_bucket      = s3_bucket,
          s3_path_prefix = s3_path_prefix,
          overwrite      = overwrite,
          sync_to_s3     = sync_to_s3
        ),
        error = function(e) {
          message(sprintf("  ERROR: raw %d: %s", yr, e$message))
          NULL
        }
      )
      if (!is.null(r)) results <- c(results, list(r))
    }

    if ("institution" %in% layers) {
      r <- tryCatch(
        write_ipeds_institution_to_s3(
          year           = yr,
          staging_dir    = staging_dir,
          s3_bucket      = s3_bucket,
          s3_path_prefix = s3_path_prefix,
          overwrite      = overwrite,
          sync_to_s3     = sync_to_s3
        ),
        error = function(e) {
          message(sprintf("  ERROR: institution %d: %s", yr, e$message))
          NULL
        }
      )
      if (!is.null(r)) results <- c(results, list(r))
    }

    if ("county" %in% layers) {
      r <- tryCatch(
        write_ipeds_county_to_s3(
          year           = yr,
          staging_dir    = staging_dir,
          s3_bucket      = s3_bucket,
          s3_path_prefix = s3_path_prefix,
          overwrite      = overwrite,
          sync_to_s3     = sync_to_s3
        ),
        error = function(e) {
          message(sprintf("  ERROR: county %d: %s", yr, e$message))
          NULL
        }
      )
      if (!is.null(r)) results <- c(results, list(r))
    }
  }

  invisible(do.call(rbind, Filter(Negate(is.null), results)))
}


# Internal helpers ------------------------------------------------------------

# Read the three institution parquets for a year from local staging.
# Returns a named list (ic, completions, grad_rates) or NULL if none found.
.read_institution_local <- function(year, staging_dir) {
  out <- list()
  for (sv in IPEDS_SURVEYS) {
    path <- .institution_local_path(sv, year, staging_dir)
    if (file.exists(path)) {
      out[[sv]] <- .read_parquet_local(path)
    }
  }
  if (length(out) == 0) NULL else out
}

# Write a data frame to parquet via DuckDB.
.write_parquet <- function(df, path) {
  # Sanitize character columns to valid UTF-8.
  chr_cols <- names(df)[sapply(df, is.character)]
  for (col in chr_cols) {
    df[[col]] <- iconv(df[[col]], from = "", to = "UTF-8", sub = "\uFFFD")
  }
  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  DBI::dbWriteTable(con, "df", df, overwrite = TRUE)
  DBI::dbExecute(con, sprintf("COPY df TO '%s' (FORMAT 'parquet')", path))
}

# Upload a local file to S3 via the AWS CLI.
.s3_upload <- function(local_path, s3_uri) {
  exit_code <- base::system2("aws", args = c("s3", "cp", local_path, s3_uri))
  if (exit_code != 0) {
    stop(sprintf("AWS CLI upload failed: %s -> %s", local_path, s3_uri))
  }
}

# Build a one-row manifest data frame.
.manifest_row <- function(survey, year, layer, local_path) {
  data.frame(
    survey       = survey,
    year         = as.integer(year),
    layer        = layer,
    processed_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    local_path   = local_path,
    stringsAsFactors = FALSE
  )
}
