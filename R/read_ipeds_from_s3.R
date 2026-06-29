# Read processed IPEDS data from S3 via DuckDB


# Internal: establish a DuckDB connection with S3 credentials configured.
# Caller is responsible for on.exit(DBI::dbDisconnect(con, shutdown = TRUE)).
.ipeds_duckdb_con <- function() {
  con <- DBI::dbConnect(duckdb::duckdb())

  DBI::dbExecute(con, "INSTALL httpfs; LOAD httpfs;")
  DBI::dbExecute(con, "INSTALL aws;   LOAD aws;")
  DBI::dbExecute(con, sprintf("SET temp_directory = '%s';", tempdir()))
  DBI::dbExecute(con, "CREATE OR REPLACE SECRET s3_secret (
    TYPE S3,
    PROVIDER CREDENTIAL_CHAIN,
    CHAIN 'env;config',
    REGION 'us-east-1',
    URL_STYLE 'path'
  );")

  con
}


# Internal: build a WHERE clause from optional filter vectors.
.ipeds_where <- function(geoids = NULL, years = NULL, variables = NULL,
                          surveys = NULL, unitids = NULL, county_fips = NULL) {
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
  if (!is.null(county_fips))
    clauses <- c(clauses, sprintf(
      "county_fips IN (%s)", paste0("'", county_fips, "'", collapse = ", ")
    ))

  if (length(clauses) == 0) return("")
  paste("WHERE", paste(clauses, collapse = " AND "))
}


#' Read county-level IPEDS data from S3
#'
#' Queries the processed county-level parquet files from S3 via DuckDB.
#' Returns the 6-column tidy format: one row per county / year / variable.
#'
#' County data combines all three IPEDS surveys (IC, completions, graduation
#' rates) into a single table. Use the \code{surveys} argument to filter to
#' a specific survey, or \code{variables} to select specific metrics.
#'
#' @param years Integer vector. Years to return. Default: all available.
#' @param geoids Character vector. 5-digit county FIPS codes to return.
#'   Default: all counties.
#' @param variables Character vector. Variable names to return (e.g.
#'   \code{"completions_total"}, \code{"grad_rate_150pct"}). Default: all.
#'   See \code{inst/extdata/codebook.csv} for the full list.
#' @param surveys Character vector. One or more of \code{"ic"},
#'   \code{"completions"}, \code{"grad_rates"}. Default: all.
#' @param s3_bucket Character. S3 bucket name. Default:
#'   \code{"cori.data.ipeds"}.
#' @param s3_path_prefix Character. Optional path prefix (e.g. \code{"test/"}).
#'   Default: \code{""}.
#'
#' @return A data frame with columns: \code{geoid} (character, 5-digit FIPS),
#'   \code{year} (integer), \code{variable} (character), \code{value}
#'   (numeric), \code{agg_var} (numeric), \code{survey} (character).
#'
#' @examples
#' \dontrun{
#' # All county data for Grafton County NH
#' read_ipeds_county_from_s3(geoids = "33009")
#'
#' # Graduation rates for all counties, 2015-2023
#' read_ipeds_county_from_s3(
#'   variables = "grad_rate_150pct",
#'   years     = 2015:2023
#' )
#' }
#' @export
read_ipeds_county_from_s3 <- function(
    years          = NULL,
    geoids         = NULL,
    variables      = NULL,
    surveys        = NULL,
    s3_bucket      = "cori.data.ipeds",
    s3_path_prefix = ""
) {
  con <- .ipeds_duckdb_con()
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

  out
}


#' Read institution-level IPEDS data from S3
#'
#' Queries processed institution-level parquet files from S3 via DuckDB.
#' Returns wide-format data — column structure varies by survey.
#'
#' Because each survey has a different schema, only one survey can be
#' queried per call. Use \code{county_fips} to pull all institutions in
#' one or more counties, then aggregate on your own terms.
#'
#' @param survey Character. One of \code{"ic"}, \code{"completions"},
#'   \code{"grad_rates"}.
#' @param years Integer vector. Years to return. Default: all available.
#' @param unitids Character vector. IPEDS unit IDs to return. Default: all.
#' @param county_fips Character vector. 5-digit county FIPS codes. Returns
#'   all institutions in those counties. Default: all.
#' @param s3_bucket Character. Default: \code{"cori.data.ipeds"}.
#' @param s3_path_prefix Character. Default: \code{""}.
#'
#' @return A wide data frame. Columns depend on survey:
#'   \itemize{
#'     \item \strong{ic}: unitid, inst_name, county_fips, st_abbr, city,
#'       zipcode, latitude, longitude, sector_code, is_public, is_nonprofit,
#'       is_forprofit, is_4yr, is_2yr, is_degree_granting, is_hbcu,
#'       is_tribal, carnegie_classification_code, urbanization_level_code, year
#'     \item \strong{completions}: unitid, county_fips, cipcode, ed_level,
#'       major_num, count_men, count_women, count_total_students,
#'       demographic count columns (vary by vintage), year
#'     \item \strong{grad_rates}: unitid, county_fips, grad_rate_cat, cohort,
#'       count_men, count_women, count_total_students,
#'       demographic count columns (vary by vintage), year
#'   }
#'
#' @examples
#' \dontrun{
#' # All institutions in Grafton County NH
#' read_ipeds_institution_from_s3("ic", county_fips = "33009")
#'
#' # Completions for a specific institution
#' read_ipeds_institution_from_s3("completions", unitids = "182670")
#' }
#' @export
read_ipeds_institution_from_s3 <- function(
    survey,
    years          = NULL,
    unitids        = NULL,
    county_fips    = NULL,
    s3_bucket      = "cori.data.ipeds",
    s3_path_prefix = ""
) {
  survey <- match.arg(survey, c("ic", "completions", "grad_rates"))
  dataset <- paste0(survey, "_institution")

  con <- .ipeds_duckdb_con()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  glob <- sprintf(
    "s3://%s/%sdata_institution/survey=%s/year=*/part-0.parquet",
    s3_bucket, s3_path_prefix, survey
  )

  where <- .ipeds_where(
    years       = years,
    unitids     = unitids,
    county_fips = county_fips
  )

  query <- sprintf(
    "SELECT * FROM read_parquet('%s', union_by_name = true) %s ORDER BY year",
    glob, where
  )

  out <- DBI::dbGetQuery(con, query)

  # Enforce consistent types on key columns
  if ("unitid"      %in% names(out)) out$unitid      <- as.character(out$unitid)
  if ("county_fips" %in% names(out)) out$county_fips <- as.character(out$county_fips)
  if ("year"        %in% names(out)) out$year        <- as.integer(out$year)

  out
}
