# Read raw graduation rates data from downloaded ZIP


#' Read raw graduation rates data for a given year
#'
#' Downloads (if needed), extracts, and reads the IPEDS Graduation Rates
#' file for a single year. Returns a data frame with columns renamed to
#' snake_case aliases per the data dictionary.
#'
#' The unit of analysis is institution / graduation rate category (CHRTSTAT)
#' / cohort type. CHRTSTAT codes distinguish cohort sizes from completion
#' counts at various time thresholds (100\%, 150\%, 200\% of normal time).
#'
#' @param year Integer. Survey year (2000–present).
#' @param staging_dir Character. Root staging directory.
#'   Default: \code{"data/ipeds"}.
#'
#' @return A data frame with one row per unitid/chrtstat/cohort and columns
#'   as defined by the data dictionary aliases for that year.
#' @keywords internal
read_ipeds_gr_raw <- function(year, staging_dir = "data/ipeds") {
  .read_ipeds_vintage("grad_rates", year, staging_dir)
}
