# Derive county-level aggregations from institution-level data
#
# Takes the output of process_ipeds_institution_all() and produces a single
# tidy data frame with one row per county x variable x year.
#
# Output schema (6 columns):
#   geoid    -- 5-digit county FIPS (character, zero-padded)
#   year     -- integer vintage year
#   variable -- canonical variable name (from codebook)
#   value    -- numeric value
#   agg_var  -- denominator for share variables (NA for counts)
#   survey   -- "ic", "completions", or "grad_rates"
#
# All aggregations are restricted to degree-granting institutions
# (is_degree_granting == 1) with a valid county_fips.
#
# Completions shares use TRACKED_DEGREE_LEVELS as both numerator universe
# (by level) and denominator, so the four level shares sum to exactly 1.


# Award level groupings -------------------------------------------------------

# These mirror the archived process_ipeds_completions.R but are now explicit
# constants here rather than scattered across pull_* functions.

.ASSOC_LEVELS   <- c(2L, 3L)
.BACH_LEVELS    <- c(5L)
.MASTERS_LEVELS <- c(7L)
.DOCTORAL_LEVELS <- c(17L, 18L, 19L)

# Tracked levels define both the denominator for shares and the universe
# for count_degrees_total. Excludes certificates and undocumented codes.
.TRACKED_DEGREE_LEVELS <- c(
  .ASSOC_LEVELS, .BACH_LEVELS, .MASTERS_LEVELS, .DOCTORAL_LEVELS
)

# Graduation rate GRTYPE codes (Section 1: bachelor's degree-seeking cohort)
# GRTYPE uniquely identifies the row role within Section 1 of the GR survey.
# GRTYPE 1 = starting cohort (not used here)
# GRTYPE 2 = adjusted cohort minus exclusions (denominator)
# GRTYPE 3 = completers within 150% of normal time (numerator for grad_rate_150pct)
# GRTYPE 4 = transfer-out students (numerator for transfer_out_rate)
# GRTYPE >= 6 = other sections (part-time, transfer-in, etc.; excluded)
.GR_ADJUSTED_COHORT_TYPE   <- 2L
.GR_COMPLETERS_150PCT_TYPE <- 3L
.GR_TRANSFER_OUT_TYPE      <- 4L


# Main entry point ------------------------------------------------------------

#' Derive county-level data from institution-level data frames
#'
#' Accepts the named list returned by \code{process_ipeds_institution_all()}
#' and returns a single tidy data frame with county-level metrics.
#'
#' @param inst_list Named list with elements \code{ic}, \code{completions},
#'   \code{grad_rates}. Output of \code{process_ipeds_institution_all()}.
#'
#' @return Tidy data frame: geoid, year, variable, value, agg_var, survey.
#' @keywords internal
process_ipeds_county <- function(inst_list) {
  parts <- list()

  if (!is.null(inst_list$ic)) {
    message("    Aggregating IC to county...")
    ic_county <- .county_ic(inst_list$ic)
    if (!is.null(ic_county)) parts <- c(parts, list(ic_county))
  }

  if (!is.null(inst_list$completions)) {
    message("    Aggregating completions to county...")
    comp_county <- .county_completions(inst_list$completions)
    if (!is.null(comp_county)) parts <- c(parts, list(comp_county))
  }

  if (!is.null(inst_list$grad_rates)) {
    message("    Aggregating grad rates to county...")
    gr_county <- .county_grad_rates(inst_list$grad_rates)
    if (!is.null(gr_county)) parts <- c(parts, list(gr_county))
  }

  if (length(parts) == 0) return(NULL)

  out <- do.call(rbind, parts)
  out[order(out$geoid, out$survey, out$variable), ]
}


# IC county aggregations ------------------------------------------------------

.county_ic <- function(ic_df) {
  base <- .ic_county_base(ic_df)
  if (is.null(base) || nrow(base) == 0) return(NULL)

  # One tidy row per flag column per county
  flag_vars <- list(
    inst_count           = rep(1L, nrow(base)),
    public_inst_count    = base$is_public,
    nonprofit_inst_count = base$is_nonprofit,
    fouryear_inst_count  = base$is_4yr,
    twoyear_inst_count   = base$is_2yr,
    hbcu_count           = base$is_hbcu,
    tribal_count         = base$is_tribal
  )

  parts <- lapply(names(flag_vars), function(var) {
    vals <- flag_vars[[var]]
    if (is.null(vals)) return(NULL)
    .flag_to_county_tidy(base, vals, var, "ic")
  })

  do.call(rbind, Filter(Negate(is.null), parts))
}

# Filter IC to the base used for all county aggregations:
# degree-granting, valid county_fips, not administrative/unclassified sector.
.ic_county_base <- function(ic_df) {
  required <- c("county_fips", "is_degree_granting", "sector_code", "year")
  missing  <- setdiff(required, names(ic_df))
  if (length(missing) > 0) {
    warning(sprintf(".ic_county_base: missing columns: %s", paste(missing, collapse = ", ")))
    return(NULL)
  }

  ic_df[
    !is.na(ic_df$county_fips) &
    nzchar(ic_df$county_fips) &
    !is.na(ic_df$is_degree_granting) &
    ic_df$is_degree_granting == 1L &
    !is.na(ic_df$sector_code) &
    !ic_df$sector_code %in% .EXCLUDED_SECTORS,
  ]
}

# Aggregate a numeric flag vector to county totals and return tidy rows.
.flag_to_county_tidy <- function(base, flag_vals, variable_name, survey) {
  agg <- stats::aggregate(
    flag_vals,
    by   = list(geoid = base$county_fips, year = base$year),
    FUN  = sum,
    na.rm = TRUE
  )
  names(agg)[3] <- "value"
  agg$variable  <- variable_name
  agg$agg_var   <- NA_real_
  agg$survey    <- survey
  agg[, c("geoid", "year", "variable", "value", "agg_var", "survey")]
}


# Completions county aggregations ---------------------------------------------

.county_completions <- function(comp_df) {
  required <- c("unitid", "county_fips", "ed_level",
                "count_total_students", "count_men", "count_women", "year")
  missing  <- setdiff(required, names(comp_df))
  if (length(missing) > 0) {
    warning(sprintf(".county_completions: missing columns: %s",
                    paste(missing, collapse = ", ")))
    return(NULL)
  }

  # Restrict to valid county and tracked degree levels
  df <- comp_df[
    !is.na(comp_df$county_fips) &
    nzchar(comp_df$county_fips),
  ]
  if (nrow(df) == 0) return(NULL)

  # Denominator: all tracked levels
  tracked <- df[!is.na(df$ed_level) & df$ed_level %in% .TRACKED_DEGREE_LEVELS, ]
  if (nrow(tracked) == 0) return(NULL)

  total <- stats::aggregate(
    tracked$count_total_students,
    by   = list(geoid = tracked$county_fips, year = tracked$year),
    FUN  = sum,
    na.rm = TRUE
  )
  names(total)[3] <- "total"

  parts <- list(
    # Raw count
    .completions_count(total),
    # Level shares
    .completions_share(df, total, .ASSOC_LEVELS,    "share_degrees_assoc"),
    .completions_share(df, total, .BACH_LEVELS,     "share_degrees_bach"),
    .completions_share(df, total, .MASTERS_LEVELS,  "share_degrees_masters"),
    .completions_share(df, total, .DOCTORAL_LEVELS, "share_degrees_doctoral"),
    # Sex shares
    .completions_sex_share(tracked, total, "count_men",   "share_degrees_men"),
    .completions_sex_share(tracked, total, "count_women", "share_degrees_women")
  )

  do.call(rbind, Filter(Negate(is.null), parts))
}

.completions_count <- function(total) {
  out <- total
  names(out)[3] <- "value"
  out$variable <- "count_degrees_total"
  out$agg_var  <- NA_real_
  out$survey   <- "completions"
  out[, c("geoid", "year", "variable", "value", "agg_var", "survey")]
}

.completions_share <- function(df, total, ed_levels, variable_name) {
  sub <- df[!is.na(df$ed_level) & df$ed_level %in% ed_levels, ]
  if (nrow(sub) == 0) return(NULL)

  level <- stats::aggregate(
    sub$count_total_students,
    by   = list(geoid = sub$county_fips, year = sub$year),
    FUN  = sum,
    na.rm = TRUE
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

.completions_sex_share <- function(tracked, total, sex_col, variable_name) {
  if (!sex_col %in% names(tracked)) return(NULL)

  sex <- stats::aggregate(
    tracked[[sex_col]],
    by   = list(geoid = tracked$county_fips, year = tracked$year),
    FUN  = sum,
    na.rm = TRUE
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


# Grad rates county aggregations ----------------------------------------------

.county_grad_rates <- function(gr_df) {
  required <- c("unitid", "county_fips", "cohort_type", "cohort_size", "year")
  missing  <- setdiff(required, names(gr_df))
  if (length(missing) > 0) {
    warning(sprintf(".county_grad_rates: missing columns: %s",
                    paste(missing, collapse = ", ")))
    return(NULL)
  }

  # Restrict to valid county FIPS
  df <- gr_df[
    !is.na(gr_df$county_fips) &
    nzchar(gr_df$county_fips),
  ]
  if (nrow(df) == 0) return(NULL)

  # GRTYPE 2: adjusted cohort (denominator for both rates)
  denom <- df[!is.na(df$cohort_type) & df$cohort_type == .GR_ADJUSTED_COHORT_TYPE, ]

  cohort_total <- stats::aggregate(
    denom$cohort_size,
    by   = list(geoid = denom$county_fips, year = denom$year),
    FUN  = sum,
    na.rm = TRUE
  )
  names(cohort_total)[3] <- "cohort"
  cohort_total <- cohort_total[cohort_total$cohort > 0, ]
  if (nrow(cohort_total) == 0) return(NULL)

  parts <- list(
    .gr_rate(df, cohort_total, .GR_COMPLETERS_150PCT_TYPE, "grad_rate_150pct"),
    .gr_rate(df, cohort_total, .GR_TRANSFER_OUT_TYPE,      "transfer_out_rate")
  )

  do.call(rbind, Filter(Negate(is.null), parts))
}

# Aggregate a numerator GRTYPE to county rates against the adjusted cohort total.
.gr_rate <- function(df, cohort_total, grtype_code, variable_name) {
  num_df <- df[!is.na(df$cohort_type) & df$cohort_type == grtype_code, ]
  if (nrow(num_df) == 0) return(NULL)

  num <- stats::aggregate(
    num_df$cohort_size,
    by   = list(geoid = num_df$county_fips, year = num_df$year),
    FUN  = sum,
    na.rm = TRUE
  )
  names(num)[3] <- "numerator"

  co <- merge(cohort_total, num, by = c("geoid", "year"), all.x = TRUE)
  co$numerator[is.na(co$numerator)] <- 0L
  co <- co[co$cohort > 0, ]
  if (nrow(co) == 0) return(NULL)

  co$value    <- co$numerator / co$cohort
  co$variable <- variable_name
  co$agg_var  <- NA_real_
  co$survey   <- "grad_rates"
  co[, c("geoid", "year", "variable", "value", "agg_var", "survey")]
}
