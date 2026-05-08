# Internal utilities: parse data dictionaries and manage the incremental manifest

IPEDS_SURVEYS <- c("ic", "completions", "grad_rates")
IPEDS_START_YEAR <- 2010L

# Map survey name to its data dictionary CSV filename
.dict_file <- function(survey) {
  switch(survey,
    ic          = "institutional_characteristics.csv",
    completions = "completions.csv",
    grad_rates  = "grad_rates.csv",
    stop(sprintf("Unknown survey '%s'. Must be one of: %s",
                 survey, paste(IPEDS_SURVEYS, collapse = ", ")))
  )
}


#' Parse a survey's data dictionary
#'
#' Reads the bundled CSV data dictionary for a given survey, filters to
#' year >= 2000, and returns a tidy tibble of variable mappings.
#'
#' Columns returned:
#'   survey, year, source_table, download_url, var, alias, source_table_candidates
#'
#' `source_table_candidates` is a list-column of character vectors -- some
#' source_table values encode two case variants separated by "/" (e.g.
#' "C2004_A/c2004_a"). Both are surfaced so the reader can try each.
#'
#' @param survey Character. One of "ic", "completions", "grad_rates".
#' @keywords internal
parse_ipeds_dictionary <- function(survey) {
  path <- system.file("extdata", .dict_file(survey), package = "cori.data.ipeds")

  # Fall back to the local inst/extdata/ directory during development
  if (!nzchar(path)) {
    path <- file.path("inst", "extdata", .dict_file(survey))
  }
  if (!file.exists(path)) {
    stop(sprintf("Dictionary file not found: %s", path))
  }

  df <- utils::read.csv(path, stringsAsFactors = FALSE)

  # Normalise column names -- IC dict lacks unit_of_analysis
  if (!"unit_of_analysis" %in% names(df)) {
    df$unit_of_analysis <- NA_character_
  }

  df <- df[df$year >= IPEDS_START_YEAR, ]

  df$survey          <- survey
  df$download_url    <- df$download_table_url

  # Split "UPPER/lower" source_table into a list of candidates
  df$source_table_candidates <- strsplit(df$source_table, "/", fixed = TRUE)

  df[, c("survey", "year", "source_table", "source_table_candidates",
         "download_url", "var", "alias", "description", "unit_of_analysis")]
}


#' Get the unique downloadable vintages for a survey
#'
#' Returns one row per (year, source_table) -- i.e., one row per ZIP download
#' unit. The `source_table_candidates` column lists all filename variants to
#' try inside the ZIP.
#'
#' @param survey Character. One of "ic", "completions", "grad_rates".
#' @keywords internal
get_ipeds_vintages <- function(survey) {
  dict <- parse_ipeds_dictionary(survey)

  vintages <- unique(dict[, c("survey", "year", "source_table",
                              "source_table_candidates", "download_url")])
  vintages[order(vintages$year), ]
}


#' Get the var -> alias mapping for a specific vintage
#'
#' @param survey Character.
#' @param source_table Character. Exact source_table value from the dictionary.
#' @param year Integer.
#' @return Named character vector: names are raw IPEDS var names (uppercase),
#'   values are snake_case aliases.
#' @keywords internal
get_ipeds_col_map <- function(survey, source_table, year) {
  dict <- parse_ipeds_dictionary(survey)
  rows <- dict[dict$source_table == source_table & dict$year == year, ]

  if (nrow(rows) == 0) {
    stop(sprintf("No dictionary entries for survey=%s, source_table=%s, year=%d",
                 survey, source_table, year))
  }

  # Return named vector: UPPER_VAR_NAME = "alias"
  col_map <- rows$alias
  names(col_map) <- toupper(rows$var)
  col_map
}


# -----------------------------------------------------------------------------
# Manifest -- tracks which (survey x source_table x year) combos are processed
# -----------------------------------------------------------------------------

.manifest_s3_key <- function(s3_path_prefix) {
  paste0(s3_path_prefix, "data_processed/_MANIFEST.csv")
}

.manifest_s3_url <- function(s3_bucket, s3_path_prefix) {
  sprintf(
    "https://s3.us-east-1.amazonaws.com/%s/%s",
    s3_bucket,
    .manifest_s3_key(s3_path_prefix)
  )
}


#' Read the processing manifest from S3
#'
#' Returns a data frame with columns: year, dataset, processed_at, row_count.
#' Returns an empty data frame if the manifest does not yet exist.
#'
#' @param s3_bucket Character.
#' @param s3_path_prefix Character. Default \code{""}.
#' @keywords internal
get_ipeds_manifest <- function(s3_bucket = "cori.data.ipeds", s3_path_prefix = "") {
  url <- .manifest_s3_url(s3_bucket, s3_path_prefix)

  manifest <- tryCatch(
    utils::read.csv(url(url), stringsAsFactors = FALSE),
    error = function(e) NULL
  )

  if (is.null(manifest)) {
    message("No manifest found at S3 -- treating all vintages as unprocessed.")
    return(data.frame(
      year         = integer(0),
      dataset      = character(0),
      processed_at = character(0),
      row_count    = integer(0),
      stringsAsFactors = FALSE
    ))
  }

  manifest
}


#' Update the manifest with newly processed vintages and re-upload to S3
#'
#' @param new_rows Data frame with columns: year, dataset, processed_at,
#'   row_count.
#' @param s3_bucket Character.
#' @param s3_path_prefix Character. Default \code{""}.
#' @param staging_dir Character. Local staging directory. Default
#'   \code{"data/ipeds"}.
#' @keywords internal
update_ipeds_manifest <- function(new_rows,
                                  s3_bucket      = "cori.data.ipeds",
                                  s3_path_prefix = "",
                                  staging_dir    = "data/ipeds") {
  existing <- get_ipeds_manifest(s3_bucket, s3_path_prefix)

  # Drop any existing rows that are being overwritten
  existing <- existing[
    !paste(existing$year, existing$dataset) %in%
      paste(new_rows$year, new_rows$dataset),
  ]

  updated <- rbind(existing, new_rows)
  updated  <- updated[order(updated$year, updated$dataset), ]

  # Write locally then upload
  local_path <- file.path(staging_dir, "_MANIFEST.csv")
  dir.create(staging_dir, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(updated, local_path, row.names = FALSE)

  s3_key <- .manifest_s3_key(s3_path_prefix)
  s3_uri <- sprintf("s3://%s/%s", s3_bucket, s3_key)
  exit_code <- base::system2("aws", args = c("s3", "cp", local_path, s3_uri))
  if (exit_code != 0) stop(sprintf("Failed to upload manifest to %s", s3_uri))

  message(sprintf("Manifest updated: %d total vintages recorded.", nrow(updated)))
  invisible(updated)
}


#' Identify which vintages still need to be processed
#'
#' Diffs the full dictionary universe against the manifest and returns
#' only the (survey x source_table x year) combos not yet processed.
#'
#' @param surveys Character vector. Surveys to check. Default: all three.
#' @param years Integer vector. Years to check. Default: 2000 to current year.
#' @param s3_bucket Character.
#' @param s3_path_prefix Character.
#' @keywords internal
get_ipeds_unprocessed <- function(
    surveys        = IPEDS_SURVEYS,
    years          = IPEDS_START_YEAR:as.integer(format(Sys.Date(), "%Y")),
    s3_bucket      = "cori.data.ipeds",
    s3_path_prefix = ""
) {
  all_vintages <- do.call(rbind, lapply(surveys, get_ipeds_vintages))
  all_vintages <- all_vintages[all_vintages$year %in% years, ]

  manifest <- get_ipeds_manifest(s3_bucket, s3_path_prefix)

  if (nrow(manifest) == 0) return(all_vintages)

  processed_keys <- paste(manifest$survey, manifest$source_table, manifest$year)
  candidate_keys <- paste(all_vintages$survey, all_vintages$source_table, all_vintages$year)

  all_vintages[!candidate_keys %in% processed_keys, ]
}
