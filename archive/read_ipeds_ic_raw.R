# Read raw institutional characteristics data from downloaded ZIP


#' Read raw institutional characteristics data for a given year
#'
#' Downloads (if needed), extracts, and reads the IPEDS Institutional
#' Characteristics file for a single year. Returns a data frame with columns
#' renamed to snake_case aliases per the data dictionary. All variable
#' selection is dictionary-driven — only aliased columns are returned.
#'
#' @param year Integer. Survey year (2000–present).
#' @param staging_dir Character. Root staging directory.
#'   Default: \code{"data/ipeds"}.
#'
#' @return A data frame with one row per institution and columns as defined
#'   by the data dictionary aliases for that year. Always includes
#'   \code{unitid}, \code{county_fips}, and \code{year}.
#' @keywords internal
read_ipeds_ic_raw <- function(year, staging_dir = "data/ipeds") {
  .read_ipeds_vintage("ic", year, staging_dir)
}
