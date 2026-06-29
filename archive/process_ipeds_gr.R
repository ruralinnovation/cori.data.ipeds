# Process graduation rates: institution and county level outputs

# CHRTSTAT (grad_rate_cat) codes ----------------------------------------------

# Adjusted cohort = revised cohort minus exclusions (denominator)
GR_ADJUSTED_COHORT   <- 12L
# Completers within 150% of normal time (numerator for primary grad rate)
GR_COMPLETERS_150PCT <- 13L
# Transfer-out students
GR_TRANSFER_OUT      <- 20L

# Cohort type codes
# 1 = Full-time, first-time bachelor's degree-seeking (primary cohort)
# 2 = Full-time, first-time at less-than-4-year institutions
# 3 = Part-time, first-time
# 4 = Full-time, first-time (all degree/certificate-seeking)
GR_PRIMARY_COHORT <- 1L


# Institution-level -----------------------------------------------------------

#' Pull institution-level graduation rate data for one or more years
#'
#' Returns one row per institution / CHRTSTAT category / cohort type / year.
#' Joins to IC for \code{county_fips}. Only degree-granting institutions
#' will have a county_fips value (others will be \code{NA}).
#'
#' Analysts working with this data should filter to \code{grad_rate_cat == 12}
#' for adjusted cohort sizes and \code{grad_rate_cat == 13} for completers
#' within 150\% of normal time. Use \code{cohort == 1} for the primary
#' full-time, first-time bachelor's degree-seeking cohort.
#'
#' @param years Integer vector. Default: 2010 to current year.
#' @param staging_dir Character. Default: \code{"data/ipeds"}.
#'
#' @return Data frame: unitid, county_fips, grad_rate_cat, cohort, year,
#'   count_total_students, count_men, count_women, demographic count columns.
pull_ipeds_grad_rates_inst <- function(
    years       = IPEDS_START_YEAR:as.integer(format(Sys.Date(), "%Y")),
    staging_dir = "data/ipeds"
) {
  result <- lapply(years, function(yr) {
    raw    <- read_ipeds_gr_raw(yr, staging_dir)
    lookup <- .ic_unitid_county_lookup(yr, staging_dir)

    raw <- merge(raw, lookup, by = "unitid", all.x = TRUE)

    if (!"county_fips" %in% names(raw)) raw$county_fips <- NA_character_

    raw
  })

  .bind_rows_flexible(result)
}


# County-level ----------------------------------------------------------------

#' Pull 150\% graduation rate per county per year
#'
#' Calculates the graduation rate (completers within 150\% of normal time
#' divided by adjusted cohort) for the primary full-time, first-time
#' bachelor's degree-seeking cohort (\code{cohort == 1}). Aggregates to
#' the county level as a cohort-weighted average.
#'
#' Requires IC county_fips — available from 2009. Returns \code{NULL} for
#' years where the geographic link is unavailable.
#'
#' @param years Integer vector.
#' @param staging_dir Character.
#' @return 5-column tidy data frame (geoid, year, variable, value, agg_var).
#'   \code{agg_var} = sum of adjusted cohort sizes in the county (use as
#'   weight when averaging across counties).
pull_grad_rate_150pct <- function(
    years       = IPEDS_START_YEAR:as.integer(format(Sys.Date(), "%Y")),
    staging_dir = "data/ipeds"
) {
  result <- lapply(years, function(yr) {
    raw    <- read_ipeds_gr_raw(yr, staging_dir)
    lookup <- .ic_unitid_county_lookup(yr, staging_dir)
    if (is.null(lookup)) return(NULL)

    raw <- merge(raw, lookup, by = "unitid")
    raw <- raw[!is.na(raw$county_fips) & raw$cohort == GR_PRIMARY_COHORT, ]

    if (nrow(raw) == 0) return(NULL)

    # Pivot cohort (denominator) and completers (numerator) into wide form
    denom <- raw[raw$grad_rate_cat == GR_ADJUSTED_COHORT,
                 c("unitid", "county_fips", "count_total_students")]
    numer <- raw[raw$grad_rate_cat == GR_COMPLETERS_150PCT,
                 c("unitid", "count_total_students")]

    if (nrow(denom) == 0 || nrow(numer) == 0) return(NULL)

    names(denom)[3] <- "cohort_size"
    names(numer)[2] <- "completers"

    inst <- merge(denom, numer, by = "unitid")

    # Drop institutions with zero or missing cohort
    inst <- inst[!is.na(inst$cohort_size) & inst$cohort_size > 0, ]
    if (nrow(inst) == 0) return(NULL)

    # Aggregate to county: sum numerators and denominators separately,
    # then compute the county-level weighted rate
    co_denom <- stats::aggregate(cohort_size ~ county_fips, data = inst,
                                  FUN = sum, na.rm = TRUE)
    co_numer <- stats::aggregate(completers  ~ county_fips, data = inst,
                                  FUN = sum, na.rm = TRUE)

    co <- merge(co_denom, co_numer, by = "county_fips")
    co$value    <- co$completers / co$cohort_size
    co$geoid    <- co$county_fips
    co$year     <- as.integer(yr)
    co$variable <- "grad_rate_150pct"
    co$agg_var  <- co$cohort_size
    co$survey   <- "grad_rates"

    co[, c("geoid", "year", "variable", "value", "agg_var", "survey")]
  })

  do.call(rbind, Filter(Negate(is.null), result))
}


#' Pull transfer-out rate per county per year
#'
#' Transfer-out students divided by adjusted cohort, aggregated to county.
#' Uses the primary cohort (\code{cohort == 1}).
#'
#' @inheritParams pull_grad_rate_150pct
pull_transfer_out_rate <- function(
    years       = IPEDS_START_YEAR:as.integer(format(Sys.Date(), "%Y")),
    staging_dir = "data/ipeds"
) {
  result <- lapply(years, function(yr) {
    raw    <- read_ipeds_gr_raw(yr, staging_dir)
    lookup <- .ic_unitid_county_lookup(yr, staging_dir)
    if (is.null(lookup)) return(NULL)

    raw <- merge(raw, lookup, by = "unitid")
    raw <- raw[!is.na(raw$county_fips) & raw$cohort == GR_PRIMARY_COHORT, ]

    denom <- raw[raw$grad_rate_cat == GR_ADJUSTED_COHORT,
                 c("unitid", "county_fips", "count_total_students")]
    numer <- raw[raw$grad_rate_cat == GR_TRANSFER_OUT,
                 c("unitid", "count_total_students")]

    if (nrow(denom) == 0 || nrow(numer) == 0) return(NULL)

    names(denom)[3] <- "cohort_size"
    names(numer)[2] <- "transfers"

    inst <- merge(denom, numer, by = "unitid")
    inst <- inst[!is.na(inst$cohort_size) & inst$cohort_size > 0, ]
    if (nrow(inst) == 0) return(NULL)

    co_denom <- stats::aggregate(cohort_size ~ county_fips, data = inst,
                                  FUN = sum, na.rm = TRUE)
    co_numer <- stats::aggregate(transfers   ~ county_fips, data = inst,
                                  FUN = sum, na.rm = TRUE)

    co <- merge(co_denom, co_numer, by = "county_fips")
    co$value    <- co$transfers / co$cohort_size
    co$geoid    <- co$county_fips
    co$year     <- as.integer(yr)
    co$variable <- "transfer_out_rate"
    co$agg_var  <- co$cohort_size
    co$survey   <- "grad_rates"

    co[, c("geoid", "year", "variable", "value", "agg_var", "survey")]
  })

  do.call(rbind, Filter(Negate(is.null), result))
}
