# Download IPEDS ZIP files from NCES


#' Download a single IPEDS ZIP file from NCES
#'
#' Downloads the ZIP for a given survey vintage. Skips the download if the
#' file already exists locally. The URL comes directly from the data
#' dictionary — no URL construction needed.
#'
#' @param survey Character. One of \code{"ic"}, \code{"completions"},
#'   \code{"grad_rates"}.
#' @param year Integer. Survey year.
#' @param download_url Character. Full URL to the NCES ZIP file (from the
#'   data dictionary \code{download_url} column).
#' @param staging_dir Character. Root staging directory.
#'   Default: \code{"data/ipeds"}.
#'
#' @return Invisibly returns the local path to the downloaded ZIP.
#' @keywords internal
download_ipeds <- function(survey,
                           year,
                           download_url,
                           staging_dir = "data/ipeds") {

  zip_dir  <- file.path(staging_dir, survey, as.character(year))
  zip_path <- file.path(zip_dir, paste0(survey, "_", year, ".zip"))

  dir.create(zip_dir, recursive = TRUE, showWarnings = FALSE)

  if (file.exists(zip_path) && file.info(zip_path)$size > 0) {
    message(sprintf("Already downloaded: %s", zip_path))
    return(invisible(zip_path))
  }

  old_timeout <- getOption("timeout")
  on.exit(options(timeout = old_timeout), add = TRUE)
  options(timeout = 600)

  message(sprintf("Downloading %s %d from NCES...", toupper(survey), year))

  tryCatch(
    utils::download.file(download_url, zip_path, mode = "wb", quiet = FALSE),
    error = function(e) {
      # Remove partial download before surfacing the error
      if (file.exists(zip_path)) file.remove(zip_path)
      stop(sprintf(
        "Failed to download %s %d:\n  URL: %s\n  Error: %s",
        survey, year, download_url, conditionMessage(e)
      ))
    }
  )

  invisible(zip_path)
}


#' Unzip a downloaded IPEDS ZIP into its staging directory
#'
#' Extracts the ZIP into \code{staging_dir/{survey}/{year}/extracted/}.
#' Skips extraction if the directory is non-empty (guards against re-extracting
#' after a clean download). Deletes and re-creates the extraction directory if
#' it exists but is empty (indicates a prior failed extraction).
#'
#' @param survey Character.
#' @param year Integer.
#' @param staging_dir Character. Default: \code{"data/ipeds"}.
#'
#' @return Invisibly returns the path to the extraction directory.
#' @keywords internal
unzip_ipeds <- function(survey, year, staging_dir = "data/ipeds") {

  zip_path   <- file.path(staging_dir, survey, as.character(year),
                          paste0(survey, "_", year, ".zip"))
  extract_dir <- file.path(staging_dir, survey, as.character(year), "extracted")

  if (!file.exists(zip_path)) {
    stop(sprintf(
      "ZIP not found: %s\nRun download_ipeds() first.", zip_path
    ))
  }

  # Non-empty extraction dir → already done
  already_extracted <- dir.exists(extract_dir) &&
    length(list.files(extract_dir, recursive = TRUE)) > 0

  if (already_extracted) {
    message(sprintf("Already extracted: %s", extract_dir))
    return(invisible(extract_dir))
  }

  # Empty dir from a prior failed extraction → clean slate
  if (dir.exists(extract_dir)) unlink(extract_dir, recursive = TRUE)

  dir.create(extract_dir, recursive = TRUE, showWarnings = FALSE)
  message(sprintf("Extracting %s %d...", toupper(survey), year))
  utils::unzip(zip_path, exdir = extract_dir)

  invisible(extract_dir)
}


#' Resolve the correct CSV file path inside an extracted IPEDS ZIP
#'
#' IPEDS ZIPs sometimes include both a revised file (\code{*_rv.csv}) and an
#' original (\code{*_a.csv}). The revised file is always preferred when present.
#' Some years encode two possible filenames in the dictionary
#' (\code{source_table_candidates}); this function tries each in turn.
#'
#' @param extract_dir Character. Path to the extracted ZIP contents.
#' @param source_table_candidates Character vector. One or more candidate
#'   base filenames (without extension) to search for.
#'
#' @return Character. Full path to the resolved CSV file.
#' @keywords internal
resolve_ipeds_csv <- function(extract_dir, source_table_candidates) {

  all_csvs <- list.files(extract_dir, pattern = "\\.csv$",
                          full.names = TRUE, recursive = TRUE,
                          ignore.case = TRUE)

  if (length(all_csvs) == 0) {
    stop(sprintf("No CSV files found in: %s", extract_dir))
  }

  # Prefer _rv (revised) over _a (original) across all candidates
  for (candidate in source_table_candidates) {
    rv_match <- all_csvs[grepl(
      paste0("^", candidate, "_rv\\.csv$"),
      basename(all_csvs),
      ignore.case = TRUE
    )]
    if (length(rv_match) > 0) {
      message(sprintf("Using revised file: %s", basename(rv_match[1])))
      return(rv_match[1])
    }
  }

  # Fall back to the base candidate filename
  for (candidate in source_table_candidates) {
    base_match <- all_csvs[grepl(
      paste0("^", candidate, "\\.csv$"),
      basename(all_csvs),
      ignore.case = TRUE
    )]
    if (length(base_match) > 0) return(base_match[1])
  }

  stop(sprintf(
    "Could not find a CSV matching candidates [%s] in: %s\nFiles present: %s",
    paste(source_table_candidates, collapse = ", "),
    extract_dir,
    paste(basename(all_csvs), collapse = ", ")
  ))
}
