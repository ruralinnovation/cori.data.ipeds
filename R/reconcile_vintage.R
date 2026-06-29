# Historic reconciliation layer
#
# These functions sit between data_raw (untouched NCES parquet) and
# data_institution (codebook-renamed, analysis-ready parquet).
#
# Each reconciler accepts a raw data frame and a year, applies all known
# era-specific fixes, and returns a data frame ready for codebook renaming.
#
# Responsibilities:
#   - Normalize column names that changed across eras (e.g. CARNEGIE -> C00CARNEGIE)
#   - Convert IPEDS negative sentinel codes (-1, -2, -3) to NA
#   - Zero-pad identifier columns (UNITID, COUNTYCD)
#   - Ensure expected columns exist (add NA column if a vintage lacks it)
#   - Warn on unexpected values for known break points
#
# Responsibilities explicitly NOT here:
#   - Canonical renaming (COUNTYCD -> county_fips) -- that is process_institution.R
#   - Aggregation or filtering -- that is process_institution.R / process_county.R
#   - Download or parquet I/O -- that is write_raw_to_s3.R


# Known era break points ------------------------------------------------------

# CARNEGIE was renamed C00CARNEGIE in 2024 HD file.
# Values are identical -- only the column name changed.
.IC_CARNEGIE_RENAME_YEAR <- 2024L

# COUNTYCD, LATITUDE, LONGITUD were added to HD files in 2009.
# This package starts at 2010 so they should always be present,
# but we guard defensively.
.IC_GEO_AVAILABLE_YEAR <- 2009L

# Doctoral AWLEVEL codes changed in 2009 (9/10/11 -> 17/18/19).
# Package starts at 2010 so pre-revision codes should never appear,
# but we warn if they do.
.DOCTORAL_CODES_OLD <- c(9L, 10L, 11L)
.DOCTORAL_CODES_NEW <- c(17L, 18L, 19L)


# Public reconcilers ----------------------------------------------------------

#' Reconcile a raw IC/HD vintage data frame
#'
#' Applies all known era-specific fixes to a raw IC data frame loaded from
#' \code{data_raw}. Returns a data frame with consistent column names and
#' clean values ready for codebook renaming in \code{process_institution.R}.
#'
#' Known era fixes applied:
#' \itemize{
#'   \item 2024+: \code{C00CARNEGIE} normalised to \code{CARNEGIE}
#'   \item All years: IPEDS sentinel codes (-1, -2, -3) converted to NA
#'   \item All years: \code{UNITID} zero-padded to 6 digits
#'   \item All years: \code{COUNTYCD} zero-padded to 5 digits (after sentinel removal)
#'   \item All years: geo columns (\code{COUNTYCD}, \code{COUNTYNM},
#'     \code{LATITUDE}, \code{LONGITUD}) added as NA if absent
#' }
#'
#' @param df Data frame. Raw IC data loaded from \code{data_raw} parquet.
#' @param year Integer. Vintage year.
#' @return Data frame with reconciled column names and values.
#' @keywords internal
reconcile_ic_vintage <- function(df, year) {

  # -- 2024+: C00CARNEGIE -> CARNEGIE -----------------------------------------
  # NCES renamed the Carnegie classification column in the 2024 HD file.
  # Normalise to CARNEGIE so the codebook mapping only needs one source name.
  if (year >= .IC_CARNEGIE_RENAME_YEAR) {
    df <- .rename_if_present(df, from = "C00CARNEGIE", to = "CARNEGIE")
  }

  # -- Sentinel codes -> NA ---------------------------------------------------
  # IPEDS uses -1, -2, -3 as not-applicable / not-available / suppressed.
  # Convert to NA before any downstream logic touches the values.
  df <- .replace_sentinel_codes(df)

  # -- UNITID: zero-pad to 6 digits ------------------------------------------
  df <- .pad_unitid(df)

  # -- COUNTYCD: zero-pad to 5 digits ----------------------------------------
  # Must happen after sentinel removal so negative integers are already NA.
  df <- .pad_county_fips(df, col = "COUNTYCD")

  # -- Geo columns: ensure present (defensive guard for pre-2009 data) --------
  # COUNTYCD, COUNTYNM, LATITUDE, LONGITUD were added to HD in 2009.
  # Package starts at 2010 but we guard in case of backfill attempts.
  for (col in c("COUNTYCD", "COUNTYNM", "LATITUDE", "LONGITUD")) {
    if (!col %in% names(df)) {
      warning(sprintf(
        "reconcile_ic_vintage: column %s missing for year %d -- adding as NA",
        col, year
      ))
      df[[col]] <- NA
    }
  }

  df
}


#' Reconcile a raw completions vintage data frame
#'
#' Applies all known era-specific fixes to a raw completions data frame loaded
#' from \code{data_raw}.
#'
#' Known era fixes applied:
#' \itemize{
#'   \item All years: IPEDS sentinel codes converted to NA
#'   \item All years: \code{UNITID} zero-padded to 6 digits
#'   \item All years: race/demographic count columns not present in a given
#'     vintage are added as \code{NA_integer_} for schema consistency
#'   \item 2010+: warns if pre-revision doctoral AWLEVEL codes (9/10/11) are
#'     found (should not appear for years >= 2010)
#' }
#'
#' @param df Data frame. Raw completions data loaded from \code{data_raw}.
#' @param year Integer. Vintage year.
#' @return Data frame with reconciled column names and values.
#' @keywords internal
reconcile_completions_vintage <- function(df, year) {

  # -- Sentinel codes -> NA ---------------------------------------------------
  df <- .replace_sentinel_codes(df)

  # -- UNITID: zero-pad to 6 digits ------------------------------------------
  df <- .pad_unitid(df)

  # -- Warn if pre-2009 doctoral codes appear ---------------------------------
  if ("AWLEVEL" %in% names(df)) {
    old_doc <- df$AWLEVEL[!is.na(df$AWLEVEL) & df$AWLEVEL %in% .DOCTORAL_CODES_OLD]
    if (length(old_doc) > 0) {
      warning(sprintf(
        "reconcile_completions_vintage: pre-2009 doctoral AWLEVEL codes (%s) found in year %d. Expected 17/18/19 for years >= 2010. Check source data.",
        paste(unique(old_doc), collapse = ", "), year
      ))
    }
  }

  # -- Race/demographic columns: ensure consistent schema --------------------
  # The set of race/ethnicity count columns expanded over time.
  # Add any missing columns as NA so bind_rows across vintages works cleanly.
  df <- .ensure_columns(df, .COMPLETIONS_RACE_COLS, fill = NA_integer_)

  df
}


#' Reconcile a raw graduation rates vintage data frame
#'
#' Applies all known era-specific fixes to a raw grad rates data frame loaded
#' from \code{data_raw}.
#'
#' Known era fixes applied:
#' \itemize{
#'   \item All years: IPEDS sentinel codes converted to NA
#'   \item All years: \code{UNITID} zero-padded to 6 digits
#'   \item All years: race/demographic count columns not present in a given
#'     vintage are added as \code{NA_integer_} for schema consistency
#' }
#'
#' @param df Data frame. Raw grad rates data loaded from \code{data_raw}.
#' @param year Integer. Vintage year.
#' @return Data frame with reconciled column names and values.
#' @keywords internal
reconcile_gr_vintage <- function(df, year) {

  # -- Sentinel codes -> NA ---------------------------------------------------
  df <- .replace_sentinel_codes(df)

  # -- UNITID: zero-pad to 6 digits ------------------------------------------
  df <- .pad_unitid(df)

  # -- Race/demographic columns: ensure consistent schema --------------------
  df <- .ensure_columns(df, .GR_RACE_COLS, fill = NA_integer_)

  df
}


# Dispatch helper -------------------------------------------------------------

#' Reconcile any survey vintage
#'
#' Dispatches to the appropriate per-survey reconciler.
#'
#' @param survey Character. One of \code{"institutional_characteristics"}, \code{"completions"},
#'   \code{"grad_rates"}.
#' @param df Data frame. Raw data for the vintage.
#' @param year Integer. Vintage year.
#' @return Reconciled data frame.
#' @keywords internal
reconcile_vintage <- function(survey, df, year) {
  switch(survey,
    institutional_characteristics = reconcile_ic_vintage(df, year),
    completions                   = reconcile_completions_vintage(df, year),
    grad_rates                    = reconcile_gr_vintage(df, year),
    stop(sprintf("Unknown survey '%s'", survey))
  )
}


# Known demographic column sets -----------------------------------------------

# Race/ethnicity count columns in the completions survey.
# Not all columns exist in all vintages; missing ones are filled with NA.
.COMPLETIONS_RACE_COLS <- c(
  "CAIANM", "CAIANW",   # American Indian / Alaska Native
  "CASIAM", "CASIAW",   # Asian
  "CBKAAM", "CBKAAW",   # Black or African American
  "CHISPM", "CHISPW",   # Hispanic
  "CNHPIM", "CNHPIW",   # Native Hawaiian / Pacific Islander
  "CWHITM", "CWHITW",   # White
  "C2MORM", "C2MORW",   # Two or more races
  "CUNKM",  "CUNKW",    # Race unknown
  "CNRALM", "CNRALW"    # Non-resident alien
)

# Race/ethnicity count columns in the grad rates survey.
.GR_RACE_COLS <- c(
  "GRAIANT",             # American Indian / Alaska Native total
  "GRASIAT",             # Asian total
  "GBKAAT",              # Black or African American total
  "GHISPT",              # Hispanic total
  "GNHPIT",              # Native Hawaiian / Pacific Islander total
  "GWHITT",              # White total
  "G2MORT",              # Two or more races total
  "GUNKT",               # Race unknown total
  "GNRALT"               # Non-resident alien total
)


# Internal helpers ------------------------------------------------------------

# Rename a column if it exists; no-op otherwise.
.rename_if_present <- function(df, from, to) {
  if (from %in% names(df)) {
    names(df)[names(df) == from] <- to
  }
  df
}

# Replace IPEDS sentinel codes (-1, -2, -3) with NA across all numeric columns.
.replace_sentinel_codes <- function(df) {
  sentinel <- c(-1L, -2L, -3L)
  for (col in names(df)) {
    if (is.numeric(df[[col]])) {
      df[[col]][df[[col]] %in% sentinel] <- NA
    }
  }
  df
}

# Zero-pad UNITID to 6 characters.
.pad_unitid <- function(df) {
  if ("UNITID" %in% names(df)) {
    df$UNITID <- stringr::str_pad(
      as.character(df$UNITID), width = 6, side = "left", pad = "0"
    )
  }
  df
}

# Zero-pad a county FIPS column to 5 characters.
# Assumes sentinel codes have already been replaced with NA.
.pad_county_fips <- function(df, col = "COUNTYCD") {
  if (col %in% names(df)) {
    df[[col]] <- ifelse(
      is.na(df[[col]]),
      NA_character_,
      stringr::str_pad(as.character(df[[col]]), width = 5, side = "left", pad = "0")
    )
  }
  df
}

# Ensure a set of columns exists in df, filling missing ones with `fill`.
.ensure_columns <- function(df, cols, fill = NA) {
  missing <- setdiff(cols, names(df))
  if (length(missing) > 0) {
    df[missing] <- fill
  }
  df
}
