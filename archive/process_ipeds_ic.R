# Process institutional characteristics: institution and county level outputs

# Sector code mappings --------------------------------------------------------

# Sector codes where the institution is publicly funded
PUBLIC_SECTOR_CODES    <- c(1L, 4L, 7L)
# Sector codes for private nonprofit
NONPROFIT_SECTOR_CODES <- c(2L, 5L, 8L)
# Sector codes for private for-profit
FORPROFIT_SECTOR_CODES <- c(3L, 6L, 9L)
# Sector codes for 4-year or above
FOURYEAR_SECTOR_CODES  <- c(1L, 2L, 3L)
# Sector codes for 2-year
TWOYEAR_SECTOR_CODES   <- c(4L, 5L, 6L)
# Administrative units and not-applicable — excluded from institution counts
EXCLUDED_SECTOR_CODES  <- c(0L, 99L)


# Institution-level -----------------------------------------------------------

#' Pull institution-level characteristics for one or more years
#'
#' Returns cleaned IC data with decoded binary flag columns. One row per
#' institution per year. All institutions are included in this wide table
#' regardless of degree-granting status; county-level aggregations are
#' restricted to degree-granting institutions separately.
#'
#' @param years Integer vector. Default: 2010 to current year.
#' @param staging_dir Character. Default: \code{"data/ipeds"}.
#'
#' @return Data frame: unitid, inst_name, county_fips, st_abbr, city,
#'   zipcode, latitude, longitude, sector_code, is_public, is_nonprofit,
#'   is_forprofit, is_4yr, is_2yr, is_degree_granting, is_hbcu, is_tribal,
#'   carnegie_classification_code, urbanization_level_code, year.
pull_ipeds_institutions <- function(
    years       = IPEDS_START_YEAR:as.integer(format(Sys.Date(), "%Y")),
    staging_dir = "data/ipeds"
) {
  result <- lapply(years, function(yr) {
    raw <- read_ipeds_ic_raw(yr, staging_dir)

    raw$is_public         <- as.integer(raw$sector_code %in% PUBLIC_SECTOR_CODES)
    raw$is_nonprofit      <- as.integer(raw$sector_code %in% NONPROFIT_SECTOR_CODES)
    raw$is_forprofit      <- as.integer(raw$sector_code %in% FORPROFIT_SECTOR_CODES)
    raw$is_4yr            <- as.integer(raw$sector_code %in% FOURYEAR_SECTOR_CODES)
    raw$is_2yr            <- as.integer(raw$sector_code %in% TWOYEAR_SECTOR_CODES)
    raw$is_degree_granting <- as.integer(raw$degree_granting_status_code == 1)
    raw$is_hbcu           <- as.integer(raw$hbcu_code == 1)
    raw$is_tribal         <- as.integer(raw$tribal_college_code == 1)

    # county_fips only present from 2009 — ensure column exists
    if (!"county_fips" %in% names(raw)) raw$county_fips <- NA_character_
    if (!"latitude"    %in% names(raw)) raw$latitude    <- NA_real_
    if (!"longitude"   %in% names(raw)) raw$longitude   <- NA_real_

    keep <- c(
      "unitid", "inst_name", "county_fips", "st_abbr", "city", "zipcode",
      "latitude", "longitude",
      "sector_code", "is_public", "is_nonprofit", "is_forprofit",
      "is_4yr", "is_2yr", "is_degree_granting", "is_hbcu", "is_tribal",
      "carnegie_classification_code", "urbanization_level_code", "year"
    )
    raw[, intersect(keep, names(raw))]
  })

  do.call(rbind, result)
}


# County-level helpers --------------------------------------------------------

# Internal: get the IC data for a year filtered to real institutions
# with county_fips available. Returns NULL for years < 2009.
.ic_county_base <- function(year, staging_dir) {
  raw <- read_ipeds_ic_raw(year, staging_dir)

  if (!"county_fips" %in% names(raw) || all(is.na(raw$county_fips))) {
    return(NULL)
  }

  # Drop administrative units / not-applicable
  raw <- raw[!raw$sector_code %in% EXCLUDED_SECTOR_CODES, ]
  raw <- raw[!is.na(raw$county_fips) & nzchar(raw$county_fips), ]

  # Compute degree-granting flag before filtering
  raw$is_degree_granting <- as.integer(raw$degree_granting_status_code == 1)

  # County aggregations are restricted to degree-granting institutions only.
  # Non-degree-granting entities (e.g. professional development orgs, hair
  # schools) are retained in the wide institution table but excluded here.
  raw <- raw[raw$is_degree_granting == 1, ]

  raw$is_public         <- as.integer(raw$sector_code %in% PUBLIC_SECTOR_CODES)
  raw$is_nonprofit      <- as.integer(raw$sector_code %in% NONPROFIT_SECTOR_CODES)
  raw$is_forprofit      <- as.integer(raw$sector_code %in% FORPROFIT_SECTOR_CODES)
  raw$is_4yr            <- as.integer(raw$sector_code %in% FOURYEAR_SECTOR_CODES)
  raw$is_2yr            <- as.integer(raw$sector_code %in% TWOYEAR_SECTOR_CODES)
  raw$is_hbcu           <- as.integer(raw$hbcu_code == 1)
  raw$is_tribal         <- as.integer(raw$tribal_college_code == 1)

  raw
}

# Internal: aggregate a binary flag column to a county-level count variable.
# Returns a 6-column tidy data frame (includes survey).
.ic_flag_to_county <- function(base, flag_col, variable_name) {
  agg <- stats::aggregate(
    base[[flag_col]],
    by   = list(geoid = base$county_fips, year = base$year),
    FUN  = sum,
    na.rm = TRUE
  )
  names(agg)[3] <- "value"
  agg$variable <- variable_name
  agg$agg_var  <- NA_real_
  agg$survey   <- "ic"
  agg[, c("geoid", "year", "variable", "value", "agg_var", "survey")]
}


# County-level pull_* functions -----------------------------------------------

#' Pull total institution count per county per year
#' @param years Integer vector.
#' @param staging_dir Character.
#' @return 5-column tidy data frame (geoid, year, variable, value, agg_var).
pull_inst_count <- function(
    years       = IPEDS_START_YEAR:as.integer(format(Sys.Date(), "%Y")),
    staging_dir = "data/ipeds"
) {
  result <- lapply(years, function(yr) {
    base <- .ic_county_base(yr, staging_dir)
    if (is.null(base)) return(NULL)
    base$one <- 1L
    .ic_flag_to_county(base, "one", "inst_count")
  })
  do.call(rbind, Filter(Negate(is.null), result))
}


#' Pull public institution count per county per year
#' @inheritParams pull_inst_count
pull_public_inst_count <- function(
    years       = IPEDS_START_YEAR:as.integer(format(Sys.Date(), "%Y")),
    staging_dir = "data/ipeds"
) {
  result <- lapply(years, function(yr) {
    base <- .ic_county_base(yr, staging_dir)
    if (is.null(base)) return(NULL)
    .ic_flag_to_county(base, "is_public", "public_inst_count")
  })
  do.call(rbind, Filter(Negate(is.null), result))
}


#' Pull private nonprofit institution count per county per year
#' @inheritParams pull_inst_count
pull_nonprofit_inst_count <- function(
    years       = IPEDS_START_YEAR:as.integer(format(Sys.Date(), "%Y")),
    staging_dir = "data/ipeds"
) {
  result <- lapply(years, function(yr) {
    base <- .ic_county_base(yr, staging_dir)
    if (is.null(base)) return(NULL)
    .ic_flag_to_county(base, "is_nonprofit", "nonprofit_inst_count")
  })
  do.call(rbind, Filter(Negate(is.null), result))
}


#' Pull four-year institution count per county per year
#' @inheritParams pull_inst_count
pull_fouryear_inst_count <- function(
    years       = IPEDS_START_YEAR:as.integer(format(Sys.Date(), "%Y")),
    staging_dir = "data/ipeds"
) {
  result <- lapply(years, function(yr) {
    base <- .ic_county_base(yr, staging_dir)
    if (is.null(base)) return(NULL)
    .ic_flag_to_county(base, "is_4yr", "fouryear_inst_count")
  })
  do.call(rbind, Filter(Negate(is.null), result))
}


#' Pull two-year institution count per county per year
#' @inheritParams pull_inst_count
pull_twoyear_inst_count <- function(
    years       = IPEDS_START_YEAR:as.integer(format(Sys.Date(), "%Y")),
    staging_dir = "data/ipeds"
) {
  result <- lapply(years, function(yr) {
    base <- .ic_county_base(yr, staging_dir)
    if (is.null(base)) return(NULL)
    .ic_flag_to_county(base, "is_2yr", "twoyear_inst_count")
  })
  do.call(rbind, Filter(Negate(is.null), result))
}


#' Pull HBCU count per county per year
#' @inheritParams pull_inst_count
pull_hbcu_count <- function(
    years       = IPEDS_START_YEAR:as.integer(format(Sys.Date(), "%Y")),
    staging_dir = "data/ipeds"
) {
  result <- lapply(years, function(yr) {
    base <- .ic_county_base(yr, staging_dir)
    if (is.null(base)) return(NULL)
    .ic_flag_to_county(base, "is_hbcu", "hbcu_count")
  })
  do.call(rbind, Filter(Negate(is.null), result))
}


#' Pull tribal college count per county per year
#' @inheritParams pull_inst_count
pull_tribal_count <- function(
    years       = IPEDS_START_YEAR:as.integer(format(Sys.Date(), "%Y")),
    staging_dir = "data/ipeds"
) {
  result <- lapply(years, function(yr) {
    base <- .ic_county_base(yr, staging_dir)
    if (is.null(base)) return(NULL)
    .ic_flag_to_county(base, "is_tribal", "tribal_count")
  })
  do.call(rbind, Filter(Negate(is.null), result))
}


#' Pull degree-granting institution count per county per year
#' @inheritParams pull_inst_count
pull_degree_granting_count <- function(
    years       = IPEDS_START_YEAR:as.integer(format(Sys.Date(), "%Y")),
    staging_dir = "data/ipeds"
) {
  result <- lapply(years, function(yr) {
    base <- .ic_county_base(yr, staging_dir)
    if (is.null(base)) return(NULL)
    .ic_flag_to_county(base, "is_degree_granting", "degree_granting_count")
  })
  do.call(rbind, Filter(Negate(is.null), result))
}
