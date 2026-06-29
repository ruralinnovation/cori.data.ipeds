# Process completions: institution and county level outputs

# Award level code groupings --------------------------------------------------

# Ed level codes that map to associate degrees (2-year)
ASSOC_LEVELS   <- c(2L, 3L)
# Ed level codes that map to bachelor's degrees
BACH_LEVELS    <- c(5L)
# Ed level codes that map to master's degrees
MASTERS_LEVELS <- c(7L)
# Ed level codes that map to doctoral degrees (research + professional practice).
# IPEDS uses codes 17/18/19 in the post-2009 revised completions survey.
# Earlier scheme used 9/10/11 but our start year (2010) uses the new codes.
DOCTORAL_LEVELS <- c(17L, 18L, 19L)

# All tracked degree levels — defines the denominator for county share variables.
# Excludes sub-baccalaureate certificates (1, 4), postbaccalaureate certificates
# (6), and post-master's certificates (8) so that the four shares sum to exactly 1.
TRACKED_DEGREE_LEVELS <- c(ASSOC_LEVELS, BACH_LEVELS, MASTERS_LEVELS, DOCTORAL_LEVELS)


# Institution-level -----------------------------------------------------------

#' Pull institution-level completions data for one or more years
#'
#' Returns one row per institution / CIP code / award level / year. Joins
#' to IC to attach \code{county_fips}. All award levels are included in the
#' wide output; county aggregations restrict to \code{TRACKED_DEGREE_LEVELS}.
#'
#' Note: IPEDS award level codes changed in 2009 -- doctoral degrees moved
#' from codes 9/10/11 to 17/18/19. This package covers 2010 onward so only
#' the post-2009 codes (17/18/19) will appear.
#'
#' @param years Integer vector. Default: 2010 to current year.
#' @param staging_dir Character. Default: \code{"data/ipeds"}.
#'
#' @return Data frame: unitid, county_fips, cipcode, ed_level, year,
#'   count_men, count_women, count_total_students, plus demographic
#'   count columns available for that vintage.
pull_ipeds_completions_inst <- function(
    years       = IPEDS_START_YEAR:as.integer(format(Sys.Date(), "%Y")),
    staging_dir = "data/ipeds"
) {
  result <- lapply(years, function(yr) {
    raw    <- read_ipeds_completions_raw(yr, staging_dir)
    lookup <- .ic_unitid_county_lookup(yr, staging_dir)

    raw <- merge(raw, lookup, by = "unitid", all.x = TRUE)

    # Ensure consistent core columns exist
    if (!"count_total_students" %in% names(raw)) {
      raw$count_total_students <- rowSums(
        raw[, grep("^count_(men|women)$", names(raw), value = TRUE)],
        na.rm = TRUE
      )
    }

    raw
  })

  .bind_rows_flexible(result)
}


# County-level ----------------------------------------------------------------

#' Pull total degree count per county per year
#'
#' Sums completions across tracked degree levels (associate through doctoral,
#' IPEDS codes 2, 3, 5, 7, 17, 18, 19) for degree-granting institutions.
#' This is the anchor count; all \code{share_degrees_*} variables store this
#' total in \code{agg_var} so raw counts are recoverable as \code{value * agg_var}.
#'
#' @param years Integer vector.
#' @param staging_dir Character.
#' @return 6-column tidy data frame (geoid, year, variable, value, agg_var, survey).
pull_count_degrees_total <- function(
    years       = IPEDS_START_YEAR:as.integer(format(Sys.Date(), "%Y")),
    staging_dir = "data/ipeds"
) {
  result <- lapply(years, function(yr) {
    raw    <- read_ipeds_completions_raw(yr, staging_dir)
    lookup <- .ic_unitid_county_lookup(yr, staging_dir)
    if (is.null(lookup)) return(NULL)

    raw <- merge(raw, lookup, by = "unitid")
    raw <- raw[!is.na(raw$county_fips) & raw$ed_level %in% TRACKED_DEGREE_LEVELS, ]
    if (nrow(raw) == 0) return(NULL)

    agg <- stats::aggregate(
      raw$count_total_students,
      by  = list(geoid = raw$county_fips, year = raw$year),
      FUN = sum, na.rm = TRUE
    )
    names(agg)[3] <- "value"
    agg$variable  <- "count_degrees_total"
    agg$agg_var   <- NA_real_
    agg$survey    <- "completions"
    agg[, c("geoid", "year", "variable", "value", "agg_var", "survey")]
  })

  do.call(rbind, Filter(Negate(is.null), result))
}


#' Pull share of degrees that are associate level per county per year
#' @inheritParams pull_count_degrees_total
pull_share_degrees_assoc <- function(
    years       = IPEDS_START_YEAR:as.integer(format(Sys.Date(), "%Y")),
    staging_dir = "data/ipeds"
) {
  result <- lapply(years, function(yr) {
    .completions_share(yr, staging_dir, ASSOC_LEVELS, "share_degrees_assoc")
  })
  do.call(rbind, Filter(Negate(is.null), result))
}


#' Pull share of degrees that are bachelor's level per county per year
#' @inheritParams pull_count_degrees_total
pull_share_degrees_bach <- function(
    years       = IPEDS_START_YEAR:as.integer(format(Sys.Date(), "%Y")),
    staging_dir = "data/ipeds"
) {
  result <- lapply(years, function(yr) {
    .completions_share(yr, staging_dir, BACH_LEVELS, "share_degrees_bach")
  })
  do.call(rbind, Filter(Negate(is.null), result))
}


#' Pull share of degrees that are master's level per county per year
#' @inheritParams pull_count_degrees_total
pull_share_degrees_masters <- function(
    years       = IPEDS_START_YEAR:as.integer(format(Sys.Date(), "%Y")),
    staging_dir = "data/ipeds"
) {
  result <- lapply(years, function(yr) {
    .completions_share(yr, staging_dir, MASTERS_LEVELS, "share_degrees_masters")
  })
  do.call(rbind, Filter(Negate(is.null), result))
}


#' Pull share of degrees that are doctoral level per county per year
#' @inheritParams pull_count_degrees_total
pull_share_degrees_doctoral <- function(
    years       = IPEDS_START_YEAR:as.integer(format(Sys.Date(), "%Y")),
    staging_dir = "data/ipeds"
) {
  result <- lapply(years, function(yr) {
    .completions_share(yr, staging_dir, DOCTORAL_LEVELS, "share_degrees_doctoral")
  })
  do.call(rbind, Filter(Negate(is.null), result))
}


#' Pull share of degrees awarded to men per county per year
#' @inheritParams pull_count_degrees_total
pull_share_degrees_men <- function(
    years       = IPEDS_START_YEAR:as.integer(format(Sys.Date(), "%Y")),
    staging_dir = "data/ipeds"
) {
  result <- lapply(years, function(yr) {
    .completions_sex_share(yr, staging_dir, "count_men", "share_degrees_men")
  })
  do.call(rbind, Filter(Negate(is.null), result))
}


#' Pull share of degrees awarded to women per county per year
#' @inheritParams pull_count_degrees_total
pull_share_degrees_women <- function(
    years       = IPEDS_START_YEAR:as.integer(format(Sys.Date(), "%Y")),
    staging_dir = "data/ipeds"
) {
  result <- lapply(years, function(yr) {
    .completions_sex_share(yr, staging_dir, "count_women", "share_degrees_women")
  })
  do.call(rbind, Filter(Negate(is.null), result))
}


# Internal helpers ------------------------------------------------------------

# Build a unitid -> county_fips lookup from IC for a given year.
# Restricted to degree-granting institutions so that completions and grad
# rate county aggregations exclude non-degree-granting entities.
# Returns NULL if county_fips is not available for that year (pre-2009).
.ic_unitid_county_lookup <- function(year, staging_dir) {
  ic <- read_ipeds_ic_raw(year, staging_dir)

  if (!"county_fips" %in% names(ic) || all(is.na(ic$county_fips))) {
    return(NULL)
  }

  ic_clean <- ic[
    !is.na(ic$county_fips) &
    nzchar(ic$county_fips) &
    !is.na(ic$degree_granting_status_code) &
    ic$degree_granting_status_code == 1L,
    c("unitid", "county_fips")
  ]
  ic_clean[!duplicated(ic_clean$unitid), ]
}


# Compute share of total degrees for a given set of ed_level codes.
# value = level_count / total_count; agg_var = total_count (denominator).
# Raw count is recoverable as value * agg_var.
.completions_share <- function(year, staging_dir, ed_levels, variable_name) {
  raw    <- read_ipeds_completions_raw(year, staging_dir)
  lookup <- .ic_unitid_county_lookup(year, staging_dir)
  if (is.null(lookup)) return(NULL)

  raw <- merge(raw, lookup, by = "unitid")
  raw <- raw[!is.na(raw$county_fips), ]
  if (nrow(raw) == 0) return(NULL)

  # Denominator: tracked degree levels only, matching count_degrees_total,
  # so that all four shares sum to exactly 1.
  tracked <- raw[raw$ed_level %in% TRACKED_DEGREE_LEVELS, ]
  total <- stats::aggregate(
    tracked$count_total_students,
    by  = list(geoid = tracked$county_fips, year = tracked$year),
    FUN = sum, na.rm = TRUE
  )
  names(total)[3] <- "total"

  sub <- raw[raw$ed_level %in% ed_levels, ]
  if (nrow(sub) == 0) return(NULL)

  level <- stats::aggregate(
    sub$count_total_students,
    by  = list(geoid = sub$county_fips, year = sub$year),
    FUN = sum, na.rm = TRUE
  )
  names(level)[3] <- "level_count"

  co <- merge(total, level, by = c("geoid", "year"), all.x = TRUE)
  co$level_count[is.na(co$level_count)] <- 0L

  co <- co[co$total > 0, ]
  if (nrow(co) == 0) return(NULL)

  co$value    <- co$level_count / co$total
  co$variable <- variable_name
  co$agg_var  <- co$total
  co$survey   <- "completions"

  co[, c("geoid", "year", "variable", "value", "agg_var", "survey")]
}


# Compute share of total degrees awarded to one sex (count_men or count_women).
# value = sex_count / total_count; agg_var = total_count.
.completions_sex_share <- function(year, staging_dir, sex_col, variable_name) {
  raw    <- read_ipeds_completions_raw(year, staging_dir)
  lookup <- .ic_unitid_county_lookup(year, staging_dir)
  if (is.null(lookup)) return(NULL)

  raw <- merge(raw, lookup, by = "unitid")
  raw <- raw[!is.na(raw$county_fips) & raw$ed_level %in% TRACKED_DEGREE_LEVELS, ]
  if (nrow(raw) == 0 || !sex_col %in% names(raw)) return(NULL)

  total <- stats::aggregate(
    raw$count_total_students,
    by  = list(geoid = raw$county_fips, year = raw$year),
    FUN = sum, na.rm = TRUE
  )
  names(total)[3] <- "total"

  sex <- stats::aggregate(
    raw[[sex_col]],
    by  = list(geoid = raw$county_fips, year = raw$year),
    FUN = sum, na.rm = TRUE
  )
  names(sex)[3] <- "sex_count"

  co <- merge(total, sex, by = c("geoid", "year"), all.x = TRUE)
  co$sex_count[is.na(co$sex_count)] <- 0L

  co <- co[co$total > 0, ]
  if (nrow(co) == 0) return(NULL)

  co$value    <- co$sex_count / co$total
  co$variable <- variable_name
  co$agg_var  <- co$total
  co$survey   <- "completions"

  co[, c("geoid", "year", "variable", "value", "agg_var", "survey")]
}


# rbind a list of data frames that may have different columns (race columns
# differ pre/post 2010). Fills missing columns with NA.
.bind_rows_flexible <- function(df_list) {
  df_list <- Filter(Negate(is.null), df_list)
  if (length(df_list) == 0) return(data.frame())

  all_cols <- unique(unlist(lapply(df_list, names)))

  df_list <- lapply(df_list, function(df) {
    missing <- setdiff(all_cols, names(df))
    df[missing] <- NA
    df[, all_cols]
  })

  do.call(rbind, df_list)
}
