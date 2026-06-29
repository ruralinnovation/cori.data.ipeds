# Shared internal read engine used by all three survey-specific read_*_raw functions


#' Read and normalise a single IPEDS vintage
#'
#' Core logic shared by \code{read_ipeds_ic_raw()},
#' \code{read_ipeds_completions_raw()}, and \code{read_ipeds_gr_raw()}.
#'
#' Steps:
#'   1. Look up the vintage in the data dictionary
#'   2. Download and unzip (skip if already present)
#'   3. Resolve the correct CSV (prefer _rv revised file)
#'   4. Read with encoding fallback (UTF-8 -> latin1)
#'   5. Select and rename columns per the dictionary var->alias map
#'   6. Warn about dictionary vars missing from the file
#'   7. Add \code{year} as integer and \code{survey} as character
#'
#' @param survey Character. One of \code{"ic"}, \code{"completions"},
#'   \code{"grad_rates"}.
#' @param year Integer.
#' @param staging_dir Character.
#' @keywords internal
.read_ipeds_vintage <- function(survey, year, staging_dir = "data/ipeds") {

  # -- 1. Dictionary lookup --------------------------------------------------
  vintages <- get_ipeds_vintages(survey)
  v        <- vintages[vintages$year == year, ]

  if (nrow(v) == 0) {
    stop(sprintf(
      "No dictionary entry for survey='%s', year=%d. ",
      survey, year
    ))
  }

  candidates <- v$source_table_candidates[[1]]

  # -- 2. Download + unzip ---------------------------------------------------
  download_ipeds(survey, year, v$download_url, staging_dir)
  extract_dir <- unzip_ipeds(survey, year, staging_dir)

  # -- 3. Resolve CSV --------------------------------------------------------
  csv_path <- resolve_ipeds_csv(extract_dir, candidates)

  # -- 4. Read with encoding fallback ----------------------------------------
  df <- .read_csv_safe(csv_path)

  # -- 5. Select + rename columns --------------------------------------------
  col_map <- get_ipeds_col_map(survey, v$source_table, year)

  # Normalise both sides to uppercase for case-insensitive matching
  names(df) <- toupper(names(df))

  available   <- intersect(names(col_map), names(df))
  missing_vars <- setdiff(names(col_map), names(df))

  if (length(missing_vars) > 0) {
    warning(sprintf(
      "%s %d: %d dictionary var(s) not found in CSV and will be skipped: %s",
      toupper(survey), year, length(missing_vars),
      paste(missing_vars, collapse = ", ")
    ))
  }

  df <- df[, available, drop = FALSE]
  names(df) <- col_map[available]

  # -- 6. Add year + survey --------------------------------------------------
  df$year   <- as.integer(year)
  df$survey <- survey

  # Coerce unitid to character, zero-padded to 6 digits
  if ("unitid" %in% names(df)) {
    df$unitid <- stringr::str_pad(as.character(df$unitid), 6, side = "left", pad = "0")
  }

  # Coerce county_fips to character, zero-padded to 5 digits.
  # IPEDS uses negative integers (-1, -2, -3) as missing/not-applicable codes --
  # convert those to NA before padding so they don't produce values like "000-2".
  if ("county_fips" %in% names(df)) {
    fips <- suppressWarnings(as.integer(df$county_fips))
    df$county_fips <- ifelse(
      !is.na(fips) & fips < 0,
      NA_character_,
      stringr::str_pad(as.character(df$county_fips), 5, side = "left", pad = "0")
    )
  }

  df
}


#' Read a CSV with UTF-8 encoding, falling back to latin1 on failure
#'
#' Older IPEDS files (pre-2010) often use latin1 encoding. This helper
#' tries UTF-8 first and silently retries with latin1 if parsing fails.
#'
#' @param path Character. Full path to the CSV file.
#' @keywords internal
.read_csv_safe <- function(path) {
  old_timeout <- getOption("timeout")
  on.exit(options(timeout = old_timeout), add = TRUE)
  options(timeout = 600)

  df <- tryCatch(
    utils::read.csv(path, stringsAsFactors = FALSE, na.strings = c("", ".", "NA")),
    error = function(e) NULL,
    warning = function(w) {
      # Incomplete final line warnings are common in IPEDS -- suppress them
      if (grepl("incomplete final line", conditionMessage(w))) {
        suppressWarnings(
          utils::read.csv(path, stringsAsFactors = FALSE, na.strings = c("", ".", "NA"))
        )
      } else {
        NULL
      }
    }
  )

  if (is.null(df)) {
    message(sprintf("UTF-8 read failed for %s -- retrying with latin1", basename(path)))
    df <- utils::read.csv(
      path,
      stringsAsFactors = FALSE,
      fileEncoding     = "latin1",
      na.strings       = c("", ".", "NA")
    )
  }

  df
}
