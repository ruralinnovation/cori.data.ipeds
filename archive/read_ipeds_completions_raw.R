# Read raw completions data from downloaded ZIP


#' Read raw completions data for a given year
#'
#' Downloads (if needed), extracts, and reads the IPEDS Completions file
#' for a single year. Returns a data frame with columns renamed to
#' snake_case aliases per the data dictionary.
#'
#' The unit of analysis is institution / CIP code / award level. One row
#' represents a unique combination of institution, field of study, and
#' degree level.
#'
#' @param year Integer. Survey year (2000–present).
#' @param staging_dir Character. Root staging directory.
#'   Default: \code{"data/ipeds"}.
#'
#' @return A data frame with one row per unitid/cipcode/awlevel and columns
#'   as defined by the data dictionary aliases for that year.
#' @keywords internal
read_ipeds_completions_raw <- function(year, staging_dir = "data/ipeds") {
  .read_ipeds_vintage("completions", year, staging_dir)
}
