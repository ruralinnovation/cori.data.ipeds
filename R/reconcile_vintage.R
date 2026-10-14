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
#   - Warn on unexpected values for known break points
#
# Responsibilities explicitly NOT here:
#   - Canonical renaming (COUNTYCD -> geoid) -- that is process_institution.R
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

# Doctoral AWLEVEL codes changed in 2008: C2007_A still reports a single
# "Doctor's degrees" code 9, and C2008_A reports 17/18/19. Codes 10 and 11
# were first-professional degree and first-professional certificate, folded
# into the same revision. Package starts at 2010 so none of the three should
# ever appear, but we warn if they do.
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
  df <- .pad_geoid(df, col = "COUNTYCD")

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
#'   \item All years: \code{CIPCODE} restored to the canonical zero-padded
#'     \code{"xx.xxxx"} string
#'   \item 2010+: warns if pre-2008 doctoral AWLEVEL codes (9/10/11) are
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

  # -- CIPCODE: restore the canonical "xx.xxxx" string -----------------------
  df <- .pad_cipcode(df)

  # -- Warn if pre-2009 doctoral codes appear ---------------------------------
  if ("AWLEVEL" %in% names(df)) {
    old_doc <- df$AWLEVEL[!is.na(df$AWLEVEL) & df$AWLEVEL %in% .DOCTORAL_CODES_OLD]
    if (length(old_doc) > 0) {
      warning(sprintf(
        "reconcile_completions_vintage: pre-2008 doctoral AWLEVEL codes (%s) found in year %d. Expected 17/18/19 for years >= 2008. Check source data.",
        paste(unique(old_doc), collapse = ", "), year
      ))
    }
  }

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

  df
}


#' Reconcile a raw completers vintage data frame
#'
#' Applies all known era-specific fixes to a raw completers data frame
#' (NCES \code{C{year}_C}) loaded from \code{data_raw}.
#'
#' Known era fixes applied:
#' \itemize{
#'   \item All years: IPEDS sentinel codes converted to NA
#'   \item All years: \code{UNITID} zero-padded to 6 digits
#' }
#'
#' \code{AWLEVELC} is left as NCES reports it. Its degree-level codes
#' (3, 5, 7, 9) are stable across every published vintage, but its
#' certificate-level codes are not: code 1 appears 2012-2019 and is replaced
#' by codes 11 and 12 from 2020. County aggregations therefore use the
#' degree-level codes only.
#'
#' @param df Data frame. Raw completers data loaded from \code{data_raw}.
#' @param year Integer. Vintage year.
#' @return Data frame with reconciled column names and values.
#' @keywords internal
reconcile_completers_vintage <- function(df, year) {

  # -- Sentinel codes -> NA ---------------------------------------------------
  df <- .replace_sentinel_codes(df)

  # -- UNITID: zero-pad to 6 digits ------------------------------------------
  df <- .pad_unitid(df)

  df
}


# Dispatch helper -------------------------------------------------------------

#' Reconcile any survey vintage
#'
#' Dispatches to the appropriate per-survey reconciler.
#'
#' @param survey Character. One of \code{"institutional_characteristics"},
#'   \code{"completions"}, \code{"completers"}, \code{"grad_rates"}.
#' @param df Data frame. Raw data for the vintage.
#' @param year Integer. Vintage year.
#' @return Reconciled data frame.
#' @keywords internal
reconcile_vintage <- function(survey, df, year) {
  switch(survey,
    institutional_characteristics = reconcile_ic_vintage(df, year),
    completions                   = reconcile_completions_vintage(df, year),
    completers                    = reconcile_completers_vintage(df, year),
    grad_rates                    = reconcile_gr_vintage(df, year),
    stop(sprintf("Unknown survey '%s'", survey))
  )
}


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

# Format CIPCODE as the canonical zero-padded "xx.xxxx" string.
#
# NCES quotes this column in the source CSV, but utils::read.csv type-converts
# it to numeric anyway, which silently drops the leading zero on the 01-09 CIP
# families: 01.0000 becomes 1 and 09.0702 becomes 9.0702. Any join against the
# NCES CIP-SOC crosswalk then fails for those families while appearing to work
# for 10 and above. A CIP code is always two digits and four decimals, so
# sprintf restores the original string losslessly.
#
# Must run after .replace_sentinel_codes() so missing values are already NA.
.pad_cipcode <- function(df, col = "CIPCODE") {
  if (col %in% names(df)) {
    df[[col]] <- ifelse(
      is.na(df[[col]]),
      NA_character_,
      sprintf("%07.4f", as.numeric(df[[col]]))
    )
  }
  df
}

# Zero-pad a county FIPS column to 5 characters.
# Assumes sentinel codes have already been replaced with NA.
.pad_geoid <- function(df, col = "COUNTYCD") {
  if (col %in% names(df)) {
    df[[col]] <- ifelse(
      is.na(df[[col]]),
      NA_character_,
      stringr::str_pad(as.character(df[[col]]), width = 5, side = "left", pad = "0")
    )
  }
  df
}
