# Write processed IPEDS data to S3 -- year-partitioned, manifest-driven


# Datasets written per year ---------------------------------------------------

# The four parquet files written per year
.IPEDS_DATASETS <- c(
  "ic_institution",
  "completions_institution",
  "grad_rates_institution",
  "county"
)


#' Return the latest processed year from S3
#'
#' Reads the \code{_LATEST} pointer from S3. Returns \code{NULL} if no
#' data has been written yet.
#'
#' @param s3_bucket Character. Default: \code{"cori.data.ipeds"}.
#' @param s3_path_prefix Character. Default: \code{""}.
#' @keywords internal
latest_ipeds_vintage <- function(s3_bucket      = "cori.data.ipeds",
                                  s3_path_prefix = "") {
  url <- sprintf(
    "https://s3.us-east-1.amazonaws.com/%s/%sdata_processed/_LATEST",
    s3_bucket, s3_path_prefix
  )
  tryCatch(
    as.integer(readLines(url(url), n = 1L, warn = FALSE)),
    error = function(e) NULL
  )
}


#' Write processed IPEDS data to S3
#'
#' Orchestrates the full write pipeline for one or more years. For each year,
#' writes up to four parquet files:
#' \itemize{
#'   \item \code{ic_institution} -- wide format institutional characteristics
#'   \item \code{completions_institution} -- wide format completions by CIP/level
#'   \item \code{grad_rates_institution} -- wide format graduation rate records
#'   \item \code{county} -- 6-column tidy combining all three surveys
#' }
#'
#' Incremental by default: checks the manifest and skips any
#' (year, dataset) combinations already written. The county parquet is
#' written only after all three institution-level surveys complete for
#' that year. Set \code{overwrite = TRUE} to force reprocessing.
#'
#' @param years Integer vector. Years to process. Default: 2010 to current year.
#' @param surveys Character vector. Surveys to include in county output.
#'   Default: all three.
#' @param staging_dir Character. Local staging directory. Default:
#'   \code{"data/ipeds"}.
#' @param s3_bucket Character. Default: \code{"cori.data.ipeds"}.
#' @param s3_path_prefix Character. Optional prefix for test writes, e.g.
#'   \code{"test/"}. Default: \code{""}.
#' @param overwrite Logical. If \code{TRUE}, reprocess and overwrite existing
#'   S3 files. Default: \code{FALSE}.
#' @param sync_to_s3 Logical. Upload to S3. Set \code{FALSE} for local-only
#'   testing. Default: \code{TRUE}.
#'
#' @return Invisibly returns a data frame summarising what was written.
#' @keywords internal
write_ipeds_processed_to_s3 <- function(
    years          = IPEDS_START_YEAR:as.integer(format(Sys.Date(), "%Y")),
    surveys        = c("ic", "completions", "grad_rates"),
    staging_dir    = "data/ipeds",
    s3_bucket      = "cori.data.ipeds",
    s3_path_prefix = "",
    overwrite      = FALSE,
    sync_to_s3     = TRUE
) {
  manifest  <- get_ipeds_manifest(s3_bucket, s3_path_prefix)
  written   <- list()

  for (yr in years) {
    message(sprintf("\n--- Year %d ---", yr))

    done <- .manifest_done(manifest, yr)

    # ---- Institution-level datasets ----------------------------------------

    if ("ic" %in% surveys) {
      if (overwrite || !"ic_institution" %in% done) {
        result <- .write_inst_dataset(
          dataset     = "ic_institution",
          pull_fn     = function() pull_ipeds_institutions(years = yr, staging_dir = staging_dir),
          year        = yr,
          staging_dir = staging_dir,
          s3_bucket   = s3_bucket,
          s3_path_prefix = s3_path_prefix,
          sync_to_s3  = sync_to_s3
        )
        manifest <- .append_manifest(manifest, result)
        written  <- c(written, list(result))
      } else {
        message(sprintf("  ic_institution %d: already in manifest, skipping", yr))
      }
    }

    if ("completions" %in% surveys) {
      if (overwrite || !"completions_institution" %in% done) {
        result <- .write_inst_dataset(
          dataset     = "completions_institution",
          pull_fn     = function() pull_ipeds_completions_inst(years = yr, staging_dir = staging_dir),
          year        = yr,
          staging_dir = staging_dir,
          s3_bucket   = s3_bucket,
          s3_path_prefix = s3_path_prefix,
          sync_to_s3  = sync_to_s3
        )
        manifest <- .append_manifest(manifest, result)
        written  <- c(written, list(result))
      } else {
        message(sprintf("  completions_institution %d: already in manifest, skipping", yr))
      }
    }

    if ("grad_rates" %in% surveys) {
      if (overwrite || !"grad_rates_institution" %in% done) {
        result <- .write_inst_dataset(
          dataset     = "grad_rates_institution",
          pull_fn     = function() pull_ipeds_grad_rates_inst(years = yr, staging_dir = staging_dir),
          year        = yr,
          staging_dir = staging_dir,
          s3_bucket   = s3_bucket,
          s3_path_prefix = s3_path_prefix,
          sync_to_s3  = sync_to_s3
        )
        manifest <- .append_manifest(manifest, result)
        written  <- c(written, list(result))
      } else {
        message(sprintf("  grad_rates_institution %d: already in manifest, skipping", yr))
      }
    }

    # ---- County dataset (only after all three surveys complete) -------------

    done_now <- .manifest_done(manifest, yr)
    inst_datasets <- paste0(surveys, "_institution")
    all_inst_done <- all(inst_datasets %in% done_now)

    if (all_inst_done && (overwrite || !"county" %in% done_now)) {
      result <- .write_county_dataset(
        year        = yr,
        surveys     = surveys,
        staging_dir = staging_dir,
        s3_bucket   = s3_bucket,
        s3_path_prefix = s3_path_prefix,
        sync_to_s3  = sync_to_s3
      )
      manifest <- .append_manifest(manifest, result)
      written  <- c(written, list(result))
    } else if ("county" %in% done_now && !overwrite) {
      message(sprintf("  county %d: already in manifest, skipping", yr))
    } else if (!all_inst_done) {
      message(sprintf("  county %d: skipping -- not all surveys complete", yr))
    }
  }

  # ---- Update manifest and _LATEST on S3 ------------------------------------

  if (length(written) > 0) {
    update_ipeds_manifest(
      new_rows       = do.call(rbind, written),
      s3_bucket      = s3_bucket,
      s3_path_prefix = s3_path_prefix,
      staging_dir    = staging_dir
    )

    if (sync_to_s3) {
      latest_year <- max(manifest$year[manifest$dataset == "county"], na.rm = TRUE)
      if (is.finite(latest_year)) .write_latest(latest_year, staging_dir, s3_bucket, s3_path_prefix)
    }
  }

  invisible(do.call(rbind, written))
}


# Internal helpers ------------------------------------------------------------

# Which datasets are already written for a given year (from current manifest)
.manifest_done <- function(manifest, year) {
  if (nrow(manifest) == 0) return(character(0))
  manifest$dataset[manifest$year == year]
}

# Append a single result row to the in-memory manifest
.append_manifest <- function(manifest, result_row) {
  key <- paste(result_row$year, result_row$dataset)
  existing_key <- paste(manifest$year, manifest$dataset)
  manifest <- manifest[!existing_key %in% key, ]
  rbind(manifest, result_row)
}


# Write one institution-level parquet and return a manifest row
.write_inst_dataset <- function(dataset, pull_fn, year, staging_dir,
                                 s3_bucket, s3_path_prefix, sync_to_s3) {
  message(sprintf("  Pulling %s %d...", dataset, year))
  df <- pull_fn()

  n <- nrow(df)
  message(sprintf("  %s %d: %s rows", dataset, year, format(n, big.mark = ",")))

  local_path <- .write_parquet_local(df, year, dataset, staging_dir)

  if (sync_to_s3) {
    s3_uri <- sprintf("s3://%s/%sdata_processed/year=%d/%s/",
                      s3_bucket, s3_path_prefix, year, dataset)
    .upload_to_s3(local_path, s3_uri)
  }

  data.frame(
    year         = as.integer(year),
    dataset      = dataset,
    processed_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    row_count    = as.integer(n),
    stringsAsFactors = FALSE
  )
}


# Pull all county pull_* functions for all surveys, bind, write parquet
.write_county_dataset <- function(year, surveys, staging_dir,
                                   s3_bucket, s3_path_prefix, sync_to_s3) {
  message(sprintf("  Building county %d...", year))

  county_parts <- list()

  if ("ic" %in% surveys) {
    message("    IC county pull_*...")
    ic_parts <- list(
      pull_inst_count(years = year,           staging_dir = staging_dir),
      pull_public_inst_count(years = year,    staging_dir = staging_dir),
      pull_nonprofit_inst_count(years = year, staging_dir = staging_dir),
      pull_fouryear_inst_count(years = year,  staging_dir = staging_dir),
      pull_twoyear_inst_count(years = year,   staging_dir = staging_dir),
      pull_hbcu_count(years = year,           staging_dir = staging_dir),
      pull_tribal_count(years = year,         staging_dir = staging_dir)
    )
    county_parts <- c(county_parts, Filter(Negate(is.null), ic_parts))
  }

  if ("completions" %in% surveys) {
    message("    Completions county pull_*...")
    comp_parts <- list(
      pull_count_degrees_total(years = year,    staging_dir = staging_dir),
      pull_share_degrees_assoc(years = year,    staging_dir = staging_dir),
      pull_share_degrees_bach(years = year,     staging_dir = staging_dir),
      pull_share_degrees_masters(years = year,  staging_dir = staging_dir),
      pull_share_degrees_doctoral(years = year, staging_dir = staging_dir),
      pull_share_degrees_men(years = year,      staging_dir = staging_dir),
      pull_share_degrees_women(years = year,    staging_dir = staging_dir)
    )
    county_parts <- c(county_parts, Filter(Negate(is.null), comp_parts))
  }

  if ("grad_rates" %in% surveys) {
    message("    Grad rates county pull_*...")
    gr_parts <- list(
      pull_grad_rate_150pct(years = year,  staging_dir = staging_dir),
      pull_transfer_out_rate(years = year, staging_dir = staging_dir)
    )
    county_parts <- c(county_parts, Filter(Negate(is.null), gr_parts))
  }

  county <- do.call(rbind, county_parts)
  n      <- nrow(county)
  message(sprintf("  county %d: %s rows", year, format(n, big.mark = ",")))

  local_path <- .write_parquet_local(county, year, "county", staging_dir)

  if (sync_to_s3) {
    s3_uri <- sprintf("s3://%s/%sdata_processed/year=%d/county/",
                      s3_bucket, s3_path_prefix, year)
    .upload_to_s3(local_path, s3_uri)
  }

  data.frame(
    year         = as.integer(year),
    dataset      = "county",
    processed_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    row_count    = as.integer(n),
    stringsAsFactors = FALSE
  )
}


# Write a data frame to a local parquet file via DuckDB.
# Returns the path to the written file.
.write_parquet_local <- function(df, year, dataset, staging_dir) {
  out_dir <- file.path(staging_dir, "s3_processed",
                       sprintf("year=%d", year), dataset)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  out_file <- file.path(out_dir, "part-0.parquet")

  # DuckDB requires valid UTF-8. Sanitize all character columns before writing --
  # IPEDS institution names and addresses sometimes contain latin1 characters.
  chr_cols <- names(df)[sapply(df, is.character)]
  for (col in chr_cols) {
    df[[col]] <- iconv(df[[col]], from = "", to = "UTF-8", sub = "\uFFFD")
  }

  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  DBI::dbWriteTable(con, "df", df, overwrite = TRUE)
  DBI::dbExecute(con, sprintf("COPY df TO '%s' (FORMAT 'parquet')", out_file))

  out_file
}


# Upload a local file to an S3 URI via AWS CLI.
.upload_to_s3 <- function(local_path, s3_uri) {
  message(sprintf("    Uploading to %s...", s3_uri))
  exit_code <- base::system2(
    "aws", args = c("s3", "cp", local_path, s3_uri)
  )
  if (exit_code != 0) {
    stop(sprintf("AWS CLI upload failed: %s -> %s", local_path, s3_uri))
  }
}


# Write the _LATEST pointer file to S3
.write_latest <- function(latest_year, staging_dir, s3_bucket, s3_path_prefix) {
  local_path <- file.path(staging_dir, "s3_processed", "_LATEST")
  writeLines(as.character(latest_year), local_path)
  s3_uri <- sprintf("s3://%s/%sdata_processed/_LATEST", s3_bucket, s3_path_prefix)
  .upload_to_s3(local_path, s3_uri)
  message(sprintf("_LATEST updated to: %s", latest_year))
}
