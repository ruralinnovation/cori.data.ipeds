# Public getters
#
# Shaped to match the rest of the cori.data family: one function per measure,
# named for the measure, with `geography` first. Compare cori.data.qcew's
# get_employment(geography, geoids, years) or cori.data.bds's
# get_business_dynamics(geography, geoids, years, variables).
#
# Where the siblings use `geography` to pick an aggregation level (county,
# state, nation), this package uses it to pick a grain:
#
#   geography = "county"       tidy long, one row per geoid x year x variable
#   geography = "institution"  wide, one row per the survey's natural grain
#
# Each measure maps to one IPEDS survey:
#
#   get_institutions()       institutional_characteristics
#   get_degrees()            completions
#   get_completers()         completers
#   get_graduation_rates()   grad_rates
#
# get_ipeds() is the general getter underneath them, for pulling across
# surveys in one call.


MEASURE_SURVEY <- c(
  institutions      = "institutional_characteristics",
  degrees           = "completions",
  completers        = "completers",
  graduation_rates  = "grad_rates"
)


# Shared implementation for the four measure wrappers.
.ipeds_measure <- function(survey, geography, geoids, years, variables,
                           unitids, s3_bucket, s3_path_prefix) {
  geography <- match.arg(geography, c("county", "institution"))

  if (geography == "county") {
    if (!is.null(unitids)) {
      stop("`unitids` only applies to geography = \"institution\"; ",
           "county output is not identified by institution.", call. = FALSE)
    }
    .ipeds_county_query(
      years = years, geoids = geoids, variables = variables,
      surveys = survey, s3_bucket = s3_bucket, s3_path_prefix = s3_path_prefix
    )
  } else {
    if (!is.null(variables)) {
      stop("`variables` filters the tidy county output. At ",
           "geography = \"institution\" the output is wide, so select ",
           "columns after the call instead.", call. = FALSE)
    }
    .ipeds_institution_query(
      survey = survey, years = years, unitids = unitids, county_fips = geoids,
      s3_bucket = s3_bucket, s3_path_prefix = s3_path_prefix
    )
  }
}

#' Get higher education institutions
#'
#' Institutional presence and composition from the IPEDS Institutional
#' Characteristics survey. At county grain this is counts of degree-granting
#' institutions by control and level; at institution grain it is the
#' institution directory, one row per institution with location, sector,
#' classification and derived flags.
#'
#' @param geography Grain: `"county"` (default) for tidy long output, or
#'   `"institution"` for the wide per-institution table.
#' @param geoids Character vector of 5-digit county FIPS codes. Default `NULL`
#'   returns all counties. Filters by county at either grain.
#' @param years Integer vector of years. Default `NULL` returns all available.
#'   Coverage is 2010 to present.
#' @param variables Character vector of county-level variable names, e.g.
#'   `"inst_count"`. County grain only -- see [get_ipeds_codebook()].
#' @param unitids Character vector of IPEDS unit IDs. Institution grain only.
#' @param s3_bucket,s3_path_prefix Storage location. Defaults are production.
#'
#' @return County grain: `geoid`, `year`, `variable`, `value`, `agg_var`,
#'   `survey`. Institution grain: the codebook's institution-level columns for
#'   this survey, plus derived flags, `year` and `survey`.
#'
#' @seealso [get_degrees()], [get_completers()], [get_graduation_rates()],
#'   [get_ipeds_codebook()]
#'
#' @examples
#' \dontrun{
#' get_institutions(geoids = "33009", years = 2022)
#' get_institutions(geography = "institution", geoids = "33009", years = 2022)
#' }
#' @export
get_institutions <- function(geography      = "county",
                             geoids         = NULL,
                             years          = NULL,
                             variables      = NULL,
                             unitids        = NULL,
                             s3_bucket      = "cori.data.ipeds",
                             s3_path_prefix = "") {
  .ipeds_measure(MEASURE_SURVEY[["institutions"]], geography, geoids, years,
                 variables, unitids, s3_bucket, s3_path_prefix)
}


#' Get degrees conferred
#'
#' Credential production from the IPEDS Completions survey. At county grain
#' this is total degrees conferred and the share by level and by sex; at
#' institution grain it is awards by program, one row per institution x CIP
#' code x award level x major number.
#'
#' County figures count degrees only -- associate through doctoral -- and
#' exclude NCES grand-total rows and second majors. The institution table
#' retains both, so see [get_ipeds_codebook()] before aggregating it yourself.
#'
#' @inheritParams get_institutions
#'
#' @return County grain: `geoid`, `year`, `variable`, `value`, `agg_var`,
#'   `survey`, where `agg_var` is total degrees so `value * agg_var` recovers
#'   a raw count. Institution grain: `unitid`, `county_fips`, `cipcode`,
#'   `major_num`, `ed_level`, `count_men`, `count_women`,
#'   `count_total_students`, `year`, `survey`.
#'
#' @seealso [get_completers()] for student headcounts rather than awards,
#'   [get_cip_soc_crosswalk()] to map programs to occupations
#'
#' @examples
#' \dontrun{
#' get_degrees(geoids = "33009", years = 2022)
#' get_degrees(geography = "institution", geoids = "33009", years = 2022)
#' }
#' @export
get_degrees <- function(geography      = "county",
                        geoids         = NULL,
                        years          = NULL,
                        variables      = NULL,
                        unitids        = NULL,
                        s3_bucket      = "cori.data.ipeds",
                        s3_path_prefix = "") {
  .ipeds_measure(MEASURE_SURVEY[["degrees"]], geography, geoids, years,
                 variables, unitids, s3_bucket, s3_path_prefix)
}


#' Get students completing degrees
#'
#' Student headcounts from the IPEDS Completions survey's completers file.
#' Distinct from [get_degrees()], which counts awards: a student earning two
#' degrees at one level is one completer but two degrees.
#'
#' County variables are per award level and must not be summed across levels --
#' a student earning degrees at two levels in one year appears at both.
#' Coverage starts in 2012; NCES published no completers file before that.
#'
#' @inheritParams get_institutions
#'
#' @return County grain: `geoid`, `year`, `variable`, `value`, `agg_var`,
#'   `survey`. Institution grain: `unitid`, `county_fips`,
#'   `award_level_category`, `count_men`, `count_women`,
#'   `count_total_students`, `year`, `survey`.
#'
#' @seealso [get_degrees()]
#'
#' @examples
#' \dontrun{
#' get_completers(geoids = "33009", years = 2022)
#' }
#' @export
get_completers <- function(geography      = "county",
                           geoids         = NULL,
                           years          = NULL,
                           variables      = NULL,
                           unitids        = NULL,
                           s3_bucket      = "cori.data.ipeds",
                           s3_path_prefix = "") {
  .ipeds_measure(MEASURE_SURVEY[["completers"]], geography, geoids, years,
                 variables, unitids, s3_bucket, s3_path_prefix)
}


#' Get graduation and transfer-out rates
#'
#' Completion outcomes from the IPEDS Graduation Rates survey, for the
#' four-year full-time first-time bachelor's degree-seeking cohort.
#'
#' County rates are cohort-weighted across the county's institutions, not a
#' mean of institutional rates, and `agg_var` carries the adjusted cohort so
#' they can be weighted correctly when rolled up further. A county-year where
#' no institution reported is omitted rather than returned as zero, so
#' `transfer_out_rate` is absent for roughly a quarter of the county-years
#' that have a graduation rate. NCES publishes this survey about a year behind
#' the others.
#'
#' @inheritParams get_institutions
#'
#' @return County grain: `geoid`, `year`, `variable`, `value`, `agg_var`,
#'   `survey`. Institution grain: `unitid`, `county_fips`, `cohort_type`,
#'   `grad_rate_status`, `count_men`, `count_women`, `count_total_students`,
#'   `year`, `survey`.
#'
#' @seealso [get_degrees()], [get_ipeds_codebook()]
#'
#' @examples
#' \dontrun{
#' get_graduation_rates(geoids = "33009", years = 2012:2023)
#' }
#' @export
get_graduation_rates <- function(geography      = "county",
                                 geoids         = NULL,
                                 years          = NULL,
                                 variables      = NULL,
                                 unitids        = NULL,
                                 s3_bucket      = "cori.data.ipeds",
                                 s3_path_prefix = "") {
  .ipeds_measure(MEASURE_SURVEY[["graduation_rates"]], geography, geoids,
                 years, variables, unitids, s3_bucket, s3_path_prefix)
}


#' Get IPEDS data across surveys
#'
#' The general getter underneath [get_institutions()], [get_degrees()],
#' [get_completers()] and [get_graduation_rates()]. Use it to pull every
#' variable for a county in one call, or to filter across surveys.
#'
#' At `geography = "institution"` a single `surveys` value is required,
#' because each survey has a different wide schema.
#'
#' @inheritParams get_institutions
#' @param surveys Character vector of survey names: any of
#'   `"institutional_characteristics"`, `"completions"`, `"completers"`,
#'   `"grad_rates"`. Default `NULL` returns all (county grain only).
#'
#' @return County grain: tidy long across the requested surveys. Institution
#'   grain: the wide table for the one requested survey.
#'
#' @seealso [get_ipeds_codebook()]
#'
#' @examples
#' \dontrun{
#' # Everything known about one county in one year
#' get_ipeds(geoids = "33009", years = 2022)
#'
#' # One survey, institution grain
#' get_ipeds(geography = "institution", surveys = "completions", years = 2022)
#' }
#' @export
get_ipeds <- function(geography      = "county",
                      geoids         = NULL,
                      years          = NULL,
                      variables      = NULL,
                      surveys        = NULL,
                      unitids        = NULL,
                      s3_bucket      = "cori.data.ipeds",
                      s3_path_prefix = "") {
  geography <- match.arg(geography, c("county", "institution"))

  if (geography == "county") {
    if (!is.null(unitids)) {
      stop("`unitids` only applies to geography = \"institution\".", call. = FALSE)
    }
    return(.ipeds_county_query(
      years = years, geoids = geoids, variables = variables,
      surveys = surveys, s3_bucket = s3_bucket, s3_path_prefix = s3_path_prefix
    ))
  }

  if (length(surveys) != 1L) {
    stop("geography = \"institution\" needs exactly one `surveys` value, ",
         "because each survey has a different wide schema. Got ",
         if (is.null(surveys)) "none" else length(surveys), ".\n  Valid: ",
         paste(IPEDS_SURVEYS, collapse = ", "), call. = FALSE)
  }
  if (!is.null(variables)) {
    stop("`variables` filters the tidy county output. At ",
         "geography = \"institution\" the output is wide, so select columns ",
         "after the call instead.", call. = FALSE)
  }

  .ipeds_institution_query(
    survey = surveys, years = years, unitids = unitids, county_fips = geoids,
    s3_bucket = s3_bucket, s3_path_prefix = s3_path_prefix
  )
}
