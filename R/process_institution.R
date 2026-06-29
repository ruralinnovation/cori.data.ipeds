# Process institution-level IPEDS data
#
# Reads from data_raw (local parquet), applies reconcile_vintage(), applies
# the codebook renaming, attaches lat/long to completions and grad rates,
# and returns analysis-ready data frames for writing to data_institution/.
#
# Three outputs per year (one parquet each):
#
#   ic           -- one row per institution; canonical names; derived flag cols
#   completions  -- one row per institution x CIP x award level; lat/long attached
#   grad_rates   -- one row per institution x cohort type x status; lat/long attached
#
# Derived flag columns added to IC output (not in raw data):
#   is_public, is_nonprofit, is_forprofit
#   is_4yr, is_2yr
#   is_degree_granting, is_hbcu, is_tribal


# Sector code groupings (mirrors archived process_ipeds_ic.R) ----------------

.PUBLIC_SECTORS    <- c(1L, 4L, 7L)
.NONPROFIT_SECTORS <- c(2L, 5L, 8L)
.FORPROFIT_SECTORS <- c(3L, 6L, 9L)
.FOURYEAR_SECTORS  <- c(1L, 2L, 3L)
.TWOYEAR_SECTORS   <- c(4L, 5L, 6L)
.EXCLUDED_SECTORS  <- c(0L, 99L)


# Codebook loading ------------------------------------------------------------

#' Load the opinionated codebook
#'
#' Reads \code{inst/extdata/codebook.csv} (installed package) or falls back
#' to the local development path. Returns a data frame.
#'
#' @keywords internal
load_codebook <- function() {
  path <- system.file("extdata", "codebook.csv", package = "cori.data.ipeds")
  if (!nzchar(path)) path <- file.path("inst", "extdata", "codebook.csv")
  if (!file.exists(path)) stop("codebook.csv not found")
  utils::read.csv(path, stringsAsFactors = FALSE)
}


# Codebook mapping ------------------------------------------------------------

#' Apply codebook renaming to a reconciled data frame
#'
#' Renames columns from their NCES uppercase names to canonical snake_case
#' names as defined in the codebook. Columns not in the codebook are left
#' unchanged (they remain available in the output but are not renamed).
#'
#' @param df Data frame. Reconciled raw data (output of \code{reconcile_vintage()}).
#' @param survey Character. Survey name used to filter the codebook.
#' @param codebook Data frame. Output of \code{load_codebook()}.
#'
#' @return Data frame with codebook columns renamed to canonical names.
#' @keywords internal
apply_codebook_mapping <- function(df, survey, codebook) {
  # Apply mappings for this survey AND cross-survey variables (level = "both")
  # e.g. unitid and county_fips appear in all three surveys but are defined
  # under survey = "ic" with level = "both" in the codebook.
  cb <- codebook[
    (codebook$survey == survey | codebook$level == "both") &
    nzchar(codebook$nces_var),
  ]

  for (i in seq_len(nrow(cb))) {
    nces_name <- cb$nces_var[i]
    canonical <- cb$variable[i]
    if (nces_name %in% names(df)) {
      names(df)[names(df) == nces_name] <- canonical
    }
  }

  df
}


# Main processor --------------------------------------------------------------

#' Process one IPEDS survey vintage to institution level
#'
#' Reads the raw parquet for the given survey and year, applies
#' \code{reconcile_vintage()}, applies the codebook renaming, attaches
#' lat/long from IC (for completions and grad rates), and returns the
#' processed data frame.
#'
#' @param survey Character. One of \code{"ic"}, \code{"completions"},
#'   \code{"grad_rates"}.
#' @param year Integer. Vintage year.
#' @param staging_dir Character. Local staging directory.
#'   Default: \code{"data/ipeds"}.
#' @param codebook Data frame or \code{NULL}. Pass a pre-loaded codebook to
#'   avoid repeated disk reads when processing multiple surveys. If
#'   \code{NULL}, the codebook is loaded automatically.
#' @param geo_lookup Data frame or \code{NULL}. Pre-built unitid -> geo
#'   lookup from the processed IC data for this year. If \code{NULL} and
#'   survey is not \code{"ic"}, geo is looked up automatically from the
#'   local IC raw parquet.
#'
#' @return Processed data frame with canonical column names and lat/long.
#' @keywords internal
process_ipeds_institution <- function(survey,
                                      year,
                                      staging_dir = "data/ipeds",
                                      codebook    = NULL,
                                      geo_lookup  = NULL) {
  if (is.null(codebook)) codebook <- load_codebook()

  # Read from local raw parquet
  raw_path <- .raw_local_path(survey, year, staging_dir)
  if (!file.exists(raw_path)) {
    message(sprintf("  Skipping %s %d: raw parquet not found (NCES may not have released it yet)",
                    survey, year))
    return(NULL)
  }

  df <- .read_parquet_local(raw_path)

  # Reconcile era-specific issues
  df <- reconcile_vintage(survey, df, year)

  # Apply codebook renaming
  df <- apply_codebook_mapping(df, survey, codebook)

  # Survey-specific post-processing
  if (survey == "ic") {
    df <- .post_process_ic(df)
  } else {
    # Attach geo from IC for non-IC surveys
    if (is.null(geo_lookup)) {
      geo_lookup <- .build_geo_lookup(year, staging_dir, codebook)
    }
    df <- .attach_geo(df, geo_lookup)
  }

  df
}


#' Process all three surveys for a single year
#'
#' Convenience wrapper that processes IC first (to build the geo lookup),
#' then completions and grad rates. Returns a named list of three data frames.
#'
#' @param year Integer.
#' @param staging_dir Character.
#' @param codebook Data frame or \code{NULL}.
#'
#' @return Named list with elements \code{ic}, \code{completions},
#'   \code{grad_rates}.
#' @keywords internal
process_ipeds_institution_all <- function(year,
                                           staging_dir = "data/ipeds",
                                           codebook    = NULL) {
  if (is.null(codebook)) codebook <- load_codebook()

  message(sprintf("  Processing IC %d...", year))
  ic <- process_ipeds_institution("ic", year, staging_dir, codebook)

  # Build geo lookup once from the processed IC data
  geo_lookup <- .geo_lookup_from_ic(ic)

  message(sprintf("  Processing completions %d...", year))
  comp <- process_ipeds_institution("completions", year, staging_dir,
                                    codebook, geo_lookup)

  message(sprintf("  Processing grad_rates %d...", year))
  gr <- process_ipeds_institution("grad_rates", year, staging_dir,
                                  codebook, geo_lookup)

  list(ic = ic, completions = comp, grad_rates = gr)
}


# IC post-processing ----------------------------------------------------------

# Add derived boolean flag columns and select final column order.
.post_process_ic <- function(df) {

  # Derived flags from sector_code
  if ("sector_code" %in% names(df)) {
    df$is_public      <- as.integer(df$sector_code %in% .PUBLIC_SECTORS)
    df$is_nonprofit   <- as.integer(df$sector_code %in% .NONPROFIT_SECTORS)
    df$is_forprofit   <- as.integer(df$sector_code %in% .FORPROFIT_SECTORS)
    df$is_4yr         <- as.integer(df$sector_code %in% .FOURYEAR_SECTORS)
    df$is_2yr         <- as.integer(df$sector_code %in% .TWOYEAR_SECTORS)
  }

  # Derived flags from code columns
  if ("degree_granting_status_code" %in% names(df)) {
    df$is_degree_granting <- as.integer(df$degree_granting_status_code == 1L)
  }
  if ("hbcu_code" %in% names(df)) {
    df$is_hbcu   <- as.integer(df$hbcu_code == 1L)
  }
  if ("tribal_college_code" %in% names(df)) {
    df$is_tribal <- as.integer(df$tribal_college_code == 1L)
  }

  df
}


# Geo helpers -----------------------------------------------------------------

# Build a unitid -> geo lookup data frame from a processed IC data frame.
.geo_lookup_from_ic <- function(ic_df) {
  geo_cols <- intersect(
    c("unitid", "county_fips", "st_abbr", "latitude", "longitude"),
    names(ic_df)
  )
  lookup <- unique(ic_df[, geo_cols, drop = FALSE])
  lookup[!duplicated(lookup$unitid), ]
}

# Build geo lookup by reading and processing the IC raw parquet for a year.
.build_geo_lookup <- function(year, staging_dir, codebook) {
  ic <- process_ipeds_institution("ic", year, staging_dir, codebook)
  .geo_lookup_from_ic(ic)
}

# Join geo columns from lookup onto a non-IC data frame.
.attach_geo <- function(df, geo_lookup) {
  if (!"unitid" %in% names(df) || nrow(geo_lookup) == 0) return(df)

  merge(df, geo_lookup, by = "unitid", all.x = TRUE)
}


# Local I/O helpers -----------------------------------------------------------

.raw_local_path <- function(survey, year, staging_dir) {
  file.path(staging_dir, "s3_raw",
            sprintf("survey=%s", survey),
            sprintf("year=%d",   year),
            "part-0.parquet")
}

.institution_local_path <- function(survey, year, staging_dir) {
  file.path(staging_dir, "s3_institution",
            sprintf("survey=%s", survey),
            sprintf("year=%d",   year),
            "part-0.parquet")
}

.read_parquet_local <- function(path) {
  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  DBI::dbGetQuery(con, sprintf("SELECT * FROM read_parquet('%s')", path))
}
