# Fetch IPEDS data dictionaries directly from NCES
#
# NCES publishes per-table xlsx dictionaries at a predictable URL:
#   https://nces.ed.gov/ipeds/dictionary-generator?year={year}&tableName={table}
#
# The response is a zip containing a single xlsx with (at minimum) two sheets:
#   Varlist     -- varName, varTitle, DataType, FieldWidth, format
#   Description -- varName, longDescription
#
# These are joined on varName to produce one row per variable per vintage.
# Results are written to S3 as parquet so NCES is only hit once per vintage.


# Table name patterns per survey and year ------------------------------------

# IC data lives in two NCES tables:
#   HD{year}  -- institution header: location, sector, control, HBCU, etc.
#   IC{year}  -- programs offered: degree levels, Carnegie classification, etc.
# We fetch both and label them both as survey="ic".
.ipeds_table_names <- function(survey, year) {
  switch(survey,
    ic          = c(sprintf("HD%d", year), sprintf("IC%d", year)),
    completions = sprintf("C%d_A", year),
    grad_rates  = sprintf("GR%d", year),
    stop(sprintf("Unknown survey '%s'", survey))
  )
}

# Keep single-table variant for URL construction
.ipeds_table_name <- function(survey, year) {
  .ipeds_table_names(survey, year)[[1]]
}

.dict_url <- function(table, year) {
  sprintf(
    "https://nces.ed.gov/ipeds/dictionary-generator?year=%d&tableName=%s",
    year, table
  )
}


# Core fetch -----------------------------------------------------------------

#' Fetch the NCES data dictionary for one IPEDS survey vintage
#'
#' Downloads the xlsx dictionary from NCES, parses the Varlist and Description
#' sheets, and returns a tidy data frame with one row per variable.
#'
#' @param survey Character. One of \code{"ic"}, \code{"completions"},
#'   \code{"grad_rates"}.
#' @param year Integer. The survey year (e.g. 2024).
#'
#' @return Data frame with columns: survey, year, table_name, var_name,
#'   var_title, long_description, data_type, field_width.
#' @keywords internal
fetch_ipeds_dictionary <- function(survey, year) {
  tables <- .ipeds_table_names(survey, year)

  old_timeout <- getOption("timeout")
  on.exit(options(timeout = old_timeout), add = TRUE)
  options(timeout = 120)

  results <- lapply(tables, function(table) {
    .fetch_one_table(survey, year, table)
  })

  # Bind, drop duplicate var_names keeping the first occurrence
  out <- do.call(rbind, Filter(Negate(is.null), results))
  out[!duplicated(out$var_name), ]
}


# Fetch and parse one NCES table dictionary
.fetch_one_table <- function(survey, year, table) {
  url <- .dict_url(table, year)
  message(sprintf("  Fetching %s (%s)...", table, url))

  zip_path <- tempfile(fileext = ".zip")
  on.exit(unlink(zip_path), add = TRUE)

  dl_ok <- tryCatch({
    utils::download.file(url, zip_path, mode = "wb", quiet = TRUE)
    TRUE
  }, error = function(e) {
    warning(sprintf("Could not download dictionary for table %s year %d: %s",
                    table, year, e$message))
    FALSE
  })

  if (!dl_ok) return(NULL)

  extract_dir <- tempfile()
  dir.create(extract_dir)
  on.exit(unlink(extract_dir, recursive = TRUE), add = TRUE)

  utils::unzip(zip_path, exdir = extract_dir)

  xlsx_files <- list.files(extract_dir, pattern = "\\.xlsx$",
                           full.names = TRUE, recursive = TRUE)
  if (length(xlsx_files) == 0) {
    warning(sprintf("No xlsx in dictionary zip for table %s year %d", table, year))
    return(NULL)
  }

  xlsx_path <- xlsx_files[[1]]

  varlist <- tryCatch(
    readxl::read_excel(xlsx_path, sheet = "Varlist"),
    error = function(e) {
      warning(sprintf("No Varlist sheet in %s %d: %s", table, year, e$message))
      return(NULL)
    }
  )
  if (is.null(varlist)) return(NULL)

  names(varlist) <- tolower(names(varlist))

  desc <- tryCatch(
    readxl::read_excel(xlsx_path, sheet = "Description"),
    error = function(e) data.frame(varname = character(0),
                                   longdescription = character(0),
                                   stringsAsFactors = FALSE)
  )
  names(desc) <- tolower(names(desc))

  varlist <- .rename_col(varlist, "varname",    "var_name")
  varlist <- .rename_col(varlist, "vartitle",   "var_title")
  varlist <- .rename_col(varlist, "datatype",   "data_type")
  varlist <- .rename_col(varlist, "fieldwidth", "field_width")
  desc    <- .rename_col(desc, "varname",         "var_name")
  desc    <- .rename_col(desc, "longdescription", "long_description")

  out <- merge(
    varlist[, intersect(c("var_name", "var_title", "data_type", "field_width"),
                        names(varlist))],
    desc[,    intersect(c("var_name", "long_description"), names(desc))],
    by    = "var_name",
    all.x = TRUE
  )

  out$survey     <- survey
  out$year       <- as.integer(year)
  out$table_name <- table

  out[, c("survey", "year", "table_name", "var_name", "var_title",
          "long_description", "data_type", "field_width")]
}


# Rename a column safely (no-op if column doesn't exist) --------------------
.rename_col <- function(df, from, to) {
  if (from %in% names(df)) names(df)[names(df) == from] <- to
  df
}


# S3 read/write --------------------------------------------------------------

#' Write a fetched dictionary to S3 as parquet
#'
#' @param survey Character.
#' @param year Integer.
#' @param s3_bucket Character. Default: \code{"cori.data.ipeds"}.
#' @param s3_path_prefix Character. Default: \code{""}.
#' @param staging_dir Character. Local staging directory. Default:
#'   \code{"data/ipeds"}.
#' @param overwrite Logical. Re-fetch even if already on S3. Default:
#'   \code{FALSE}.
#' @keywords internal
write_ipeds_dictionary_to_s3 <- function(
    survey,
    year,
    s3_bucket      = "cori.data.ipeds",
    s3_path_prefix = "",
    staging_dir    = "data/ipeds",
    overwrite      = FALSE
) {
  s3_uri <- sprintf(
    "s3://%s/%sdata_dictionary/survey=%s/year=%d/part-0.parquet",
    s3_bucket, s3_path_prefix, survey, year
  )

  local_dir  <- file.path(staging_dir, "s3_dictionary",
                           sprintf("survey=%s", survey),
                           sprintf("year=%d", year))
  local_path <- file.path(local_dir, "part-0.parquet")

  if (!overwrite && file.exists(local_path)) {
    message(sprintf("  Dictionary %s %d: already local, skipping fetch", survey, year))
  } else {
    df <- fetch_ipeds_dictionary(survey, year)
    dir.create(local_dir, recursive = TRUE, showWarnings = FALSE)
    .write_dict_parquet(df, local_path)
    message(sprintf("  Dictionary %s %d: %d vars written locally", survey, year, nrow(df)))
  }

  message(sprintf("  Uploading dictionary %s %d to S3...", survey, year))
  exit_code <- base::system2(
    "aws", args = c("s3", "cp", local_path, s3_uri)
  )
  if (exit_code != 0) {
    stop(sprintf("Failed to upload dictionary to %s", s3_uri))
  }

  invisible(local_path)
}


#' Read a stored IPEDS dictionary from S3 via DuckDB
#'
#' @param survey Character. Or \code{NULL} for all surveys.
#' @param year Integer. Or \code{NULL} for all years.
#' @param s3_bucket Character.
#' @param s3_path_prefix Character.
#' @keywords internal
read_ipeds_dictionary_from_s3 <- function(
    survey         = NULL,
    year           = NULL,
    s3_bucket      = "cori.data.ipeds",
    s3_path_prefix = ""
) {
  con <- .ipeds_duckdb_con()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  glob <- sprintf(
    "s3://%s/%sdata_dictionary/*/*/part-0.parquet",
    s3_bucket, s3_path_prefix
  )

  where <- .ipeds_where(list(survey = survey, year = year))

  sql <- sprintf(
    "SELECT * FROM read_parquet('%s', union_by_name = true, hive_partitioning = true) %s ORDER BY survey, year, var_name",
    glob, where
  )

  DBI::dbGetQuery(con, sql)
}


# Write a data frame to parquet via DuckDB
.write_dict_parquet <- function(df, path) {
  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  DBI::dbWriteTable(con, "df", df, overwrite = TRUE)
  DBI::dbExecute(con, sprintf("COPY df TO '%s' (FORMAT 'parquet')", path))
}
