# Read processed IPEDS data from S3 via DuckDB


# Internal: establish a DuckDB connection via cori.data.s3::connect_to_s3().
# Uses local AWS credentials when present (maintainers); otherwise falls back
# to short-lived, read-only, bucket-scoped vended credentials, so the public
# read functions work with no AWS credentials configured at all.
# Caller is responsible for on.exit(DBI::dbDisconnect(con, shutdown = TRUE)).
.ipeds_duckdb_con <- function(bucket = "cori.data.ipeds") {
  con <- cori.data.s3::connect_to_s3(bucket)
  DBI::dbExecute(con, sprintf("SET temp_directory = '%s';", tempdir()))
  con
}


# Internal: fail loudly on filter values that cannot match anything.
#
# Without this a mistyped argument silently returns zero rows. The most
# likely slip is positional: get_ipeds() takes `survey` first and
# required, while here `years` is first and `surveys` is fourth, so
#   get_ipeds("completions", years = 2024)
# puts "completions" into `geoids` and asks for a county named completions.
.ipeds_validate_county_args <- function(geoids = NULL, variables = NULL,
                                        surveys = NULL) {
  cb          <- get_ipeds_codebook()
  county_vars <- sort(unique(cb$variable[cb$level == "county"]))

  mislaid <- function(x) {
    if (any(x %in% IPEDS_SURVEYS))  return(" Did you mean `surveys =`?")
    if (any(x %in% county_vars))    return(" Did you mean `variables =`?")
    ""
  }

  if (!is.null(surveys)) {
    bad <- setdiff(surveys, IPEDS_SURVEYS)
    if (length(bad)) {
      stop(sprintf(
        "Unknown survey: %s\n  Valid surveys: %s",
        paste(sQuote(bad), collapse = ", "),
        paste(IPEDS_SURVEYS, collapse = ", ")
      ), call. = FALSE)
    }
  }

  if (!is.null(variables)) {
    bad <- setdiff(variables, county_vars)
    if (length(bad)) {
      stop(sprintf(
        "Unknown county variable: %s%s\n  See get_ipeds_codebook() for all %d. Valid values:\n    %s",
        paste(sQuote(bad), collapse = ", "), mislaid(bad), length(county_vars),
        paste(strwrap(paste(county_vars, collapse = ", "), width = 68,
                      prefix = "\n    "), collapse = "")
      ), call. = FALSE)
    }
  }

  if (!is.null(geoids)) {
    bad <- geoids[!grepl("^[0-9]{5}$", as.character(geoids))]
    if (length(bad)) {
      stop(sprintf(
        "`geoids` must be 5-digit county FIPS codes; got %s.%s",
        paste(sQuote(utils::head(bad, 3)), collapse = ", "), mislaid(bad)
      ), call. = FALSE)
    }
  }

  invisible(TRUE)
}


# Internal: build a WHERE clause from optional filter vectors.
.ipeds_where <- function(geoids = NULL, years = NULL, variables = NULL,
                          surveys = NULL, unitids = NULL) {
  clauses <- character(0)

  if (!is.null(geoids))
    clauses <- c(clauses, sprintf(
      "geoid IN (%s)", paste0("'", geoids, "'", collapse = ", ")
    ))
  if (!is.null(years))
    clauses <- c(clauses, sprintf(
      "year IN (%s)", paste(as.integer(years), collapse = ", ")
    ))
  if (!is.null(variables))
    clauses <- c(clauses, sprintf(
      "variable IN (%s)", paste0("'", variables, "'", collapse = ", ")
    ))
  if (!is.null(surveys))
    clauses <- c(clauses, sprintf(
      "survey IN (%s)", paste0("'", surveys, "'", collapse = ", ")
    ))
  if (!is.null(unitids))
    clauses <- c(clauses, sprintf(
      "unitid IN (%s)", paste0("'", unitids, "'", collapse = ", ")
    ))

  if (length(clauses) == 0) return("")
  paste("WHERE", paste(clauses, collapse = " AND "))
}


#' Query county-level IPEDS data from S3
#'
#' Queries the processed county-level parquet files from S3 via DuckDB.
#' Returns the 6-column tidy format: one row per county / year / variable.
#'
#' County data combines all three IPEDS surveys (IC, completions, graduation
#' rates) into a single table. Use the \code{surveys} argument to filter to
#' a specific survey, or \code{variables} to select specific metrics.
#'
#' @importFrom cori.data.s3 connect_to_s3
#'
#' @param years Integer vector. Years to return. Default: all available.
#' @param geoids Character vector. 5-digit county FIPS codes to return.
#'   Default: all counties.
#' @param variables Character vector. Variable names to return (e.g.
#'   \code{"completions_total"}, \code{"grad_rate_150pct"}). Default: all.
#'   Call [get_ipeds_codebook()] for the full list.
#' @param surveys Character vector. One or more of
#'   \code{"institutional_characteristics"}, \code{"completions"},
#'   \code{"completers"}, \code{"grad_rates"}. Default: all.
#' @param s3_bucket Character. S3 bucket name. Default:
#'   \code{"cori.data.ipeds"}.
#' @param s3_path_prefix Character. Optional path prefix (e.g. \code{"test/"}).
#'   Default: \code{""}.
#'
#' @return A data frame with columns: \code{geoid} (character, 5-digit FIPS),
#'   \code{year} (integer), \code{variable} (character), \code{value}
#'   (numeric), \code{agg_var} (numeric), \code{survey} (character).
#'
#'   Note that \code{completions} variables count awards while
#'   \code{completers} variables count students, so the two are not
#'   interchangeable and the \code{count_students_*} variables must not be
#'   summed across award levels.
#'
#' @seealso [get_ipeds()], [get_ipeds_codebook()]
#'
#' Note this differs from [get_ipeds()], which takes `survey`
#' first and requires it. Here every filter is optional and `years` comes
#' first, so pass the survey by name: `get_ipeds(surveys =
#' "completions")`, not `get_ipeds("completions")`. Passing it
#' positionally used to return zero rows silently; it now errors.
#'
#' @examples
#' \dontrun{
#' # All county data for Grafton County NH
#' get_ipeds(geoids = "33009")
#'
#' # Graduation rates for all counties, 2015-2023
#' get_ipeds(
#'   variables = "grad_rate_150pct",
#'   years     = 2015:2023
#' )
#' }
#' @keywords internal
.ipeds_county_query <- function(
    years          = NULL,
    geoids         = NULL,
    variables      = NULL,
    surveys        = NULL,
    s3_bucket      = "cori.data.ipeds",
    s3_path_prefix = ""
) {
  .ipeds_validate_county_args(geoids = geoids, variables = variables,
                              surveys = surveys)

  con <- .ipeds_duckdb_con(s3_bucket)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  glob  <- sprintf(
    "s3://%s/%sdata_county/year=*/part-0.parquet",
    s3_bucket, s3_path_prefix
  )

  where <- .ipeds_where(
    geoids    = geoids,
    years     = years,
    variables = variables,
    surveys   = surveys
  )

  query <- sprintf(
    "SELECT geoid, year, variable, value, agg_var, survey
     FROM read_parquet('%s', union_by_name = true)
     %s
     ORDER BY geoid, year, survey, variable",
    glob, where
  )

  out <- DBI::dbGetQuery(con, query)

  out$geoid   <- as.character(out$geoid)
  out$year    <- as.integer(out$year)
  out$value   <- as.numeric(out$value)
  out$agg_var <- as.numeric(out$agg_var)
  out$survey  <- as.character(out$survey)

  if (nrow(out) == 0) {
    warning("No county rows matched. Check `years` (data covers ",
            IPEDS_START_YEAR, "-", IPEDS_END_YEAR, "; completers start ",
            COMPLETERS_START_YEAR, ", grad rates lag by about a year) and ",
            "that `geoids` are 5-digit county FIPS.", call. = FALSE)
  }

  message(sprintf(
    "cori.data.ipeds: county | %s rows",
    format(nrow(out), big.mark = ",")
  ))

  out
}


#' Query institution-level IPEDS data from S3
#'
#' Queries processed institution-level parquet files from S3 via DuckDB.
#' Returns wide-format data — column structure varies by survey.
#'
#' Because each survey has a different schema, only one survey can be
#' queried per call. Use \code{geoids} to pull all institutions in
#' one or more counties, then aggregate on your own terms.
#'
#' @param survey Character. One of \code{"institutional_characteristics"},
#'   \code{"completions"} (awards by program), \code{"completers"} (student
#'   headcounts by award level, 2012 onward), or \code{"grad_rates"}.
#' @param years Integer vector. Years to return. Default: all available.
#' @param unitids Character vector. IPEDS unit IDs to return. Default: all.
#' @param geoids Character vector. 5-digit county GEOIDs. Returns all
#'   institutions in those counties. Default: all.
#' @param s3_bucket Character. Default: \code{"cori.data.ipeds"}.
#' @param s3_path_prefix Character. Default: \code{""}.
#'
#' @return A wide data frame, one row per institution and the survey's own
#'   dimensions:
#'   institution for `institutional_characteristics`, institution x CIP x
#'   award level x major number for `completions`, and institution x cohort
#'   type for `grad_rates`.
#'
#'   Columns are exactly the `level == "institution"` and `level == "both"`
#'   variables that [get_ipeds_codebook()] lists for that survey, plus
#'   `year`, plus `survey` (derived from the S3 partition path). The
#'   `institutional_characteristics` output additionally carries the derived
#'   flags `is_public`, `is_nonprofit`, `is_forprofit`, `is_4yr`, `is_2yr`,
#'   `is_degree_granting`, `is_hbcu`, and `is_tribal`.
#'
#'   Rather than enumerating columns here, query the codebook -- it is the
#'   source the column selection is driven from, so it cannot drift:
#'   `cb <- get_ipeds_codebook(); cb[cb$survey == "completions", ]`.
#'
#'   Note that `completions` retains NCES `cipcode` 99 rows (each
#'   institution's grand total across programs) and `major_num` 2 rows
#'   (second majors). Both are convenient at institution level but must be
#'   excluded before summing, or degrees are counted more than once; the
#'   county aggregations already exclude them.
#'
#' @seealso [get_ipeds()], [get_ipeds_codebook()]
#'
#' @examples
#' \dontrun{
#' # All institutions in Grafton County NH
#' get_institutions(geography = "institution", geoids = "33009")
#'
#' # Completions for a specific institution
#' get_degrees(geography = "institution", unitids = "182670")
#' }
#' @keywords internal
.ipeds_institution_query <- function(
    survey,
    years          = NULL,
    unitids        = NULL,
    geoids         = NULL,
    s3_bucket      = "cori.data.ipeds",
    s3_path_prefix = ""
) {
  survey <- match.arg(survey, c("institutional_characteristics", "completions",
                                "completers", "grad_rates"))

  con <- .ipeds_duckdb_con(s3_bucket)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  glob <- sprintf(
    "s3://%s/%sdata_institution/survey=%s/year=*/part-0.parquet",
    s3_bucket, s3_path_prefix, survey
  )


  where <- .ipeds_where(
    years   = years,
    unitids = unitids,
    geoids  = geoids
  )

  query <- sprintf(
    "SELECT * FROM read_parquet('%s', union_by_name = true) %s ORDER BY year",
    glob, where
  )

  out <- DBI::dbGetQuery(con, query)

  # Enforce consistent types on key columns
  if ("unitid"      %in% names(out)) out$unitid      <- as.character(out$unitid)
  if ("geoid"       %in% names(out)) out$geoid       <- as.character(out$geoid)
  if ("year"        %in% names(out)) out$year        <- as.integer(out$year)

  if (nrow(out) == 0) {
    warning(sprintf(
      "No institution rows matched for survey '%s'. %s covers %d-%d%s.",
      survey, survey, IPEDS_START_YEAR, IPEDS_END_YEAR,
      switch(survey,
        completers = sprintf("; completers start %d", COMPLETERS_START_YEAR),
        grad_rates = "; grad rates lag the other surveys by about a year",
        "")
    ), call. = FALSE)
  }

  message(sprintf(
    "cori.data.ipeds: institution | survey: %s | %s rows",
    survey, format(nrow(out), big.mark = ",")
  ))

  out
}
