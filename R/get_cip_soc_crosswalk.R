# CIP-to-SOC crosswalk accessor
#
# The crosswalks are shipped as .rds in inst/extdata/ rather than built inline
# like the codebook: at roughly 6,000 rows each they are data, not
# documentation. data-raw/build_cip_soc_crosswalk.R regenerates them from the
# NCES source workbooks.


#' Get the NCES CIP-to-SOC crosswalk
#'
#' Returns the National Center for Education Statistics crosswalk mapping
#' Classification of Instructional Programs (CIP) codes to Standard
#' Occupational Classification (SOC) codes. Joining it to the `cipcode` column
#' of [get_degrees()]'s institution-level output turns degree production
#' into occupational supply, which is the usual bridge from education data to
#' workforce and economic development analysis.
#'
#' @section Choosing a vintage:
#'
#' NCES revises the CIP taxonomy roughly every ten years and the crosswalk
#' follows the SOC revision cycle, so the correct vintage depends on the
#' completions year you are joining to:
#'
#' \itemize{
#'   \item `vintage = "2020"` -- CIP 2020 to SOC 2018. Use for completions
#'     years 2020 and later, which NCES reports on the CIP 2020 taxonomy.
#'   \item `vintage = "2010"` -- CIP 2010 to SOC 2010. Use for completions
#'     years 2010 through 2019.
#' }
#'
#' Some programs were recoded between taxonomies, so a CIP code can mean
#' different things either side of 2020. Pairing a completions year with the
#' wrong crosswalk vintage will mostly appear to work -- the join succeeds and
#' returns plausible occupations -- which makes it worth getting right
#' deliberately rather than by default.
#'
#' @section Joining:
#'
#' The relation is many-to-many: one CIP maps to several SOC codes and vice
#' versa. Joining completions to it therefore multiplies rows, and summing
#' `count_total_students` afterwards will overcount unless you first decide
#' how to apportion a program's graduates across its occupations, or you
#' restrict to a specific SOC set and take distinct CIP codes.
#'
#' `cip_code` is formatted to match the `cipcode` column of the completions
#' table exactly -- a zero-padded `"xx.xxxx"` character string, so the 01-09
#' families join correctly.
#'
#' CIP codes with no occupational match are retained with `soc_code = NA`
#' rather than dropped, so a left join never silently loses a program. NCES's
#' `"99-9999"` no-match sentinel is converted to `NA`.
#'
#' @param vintage Character. Crosswalk vintage: `"2020"` (CIP 2020 to SOC
#'   2018, the default) or `"2010"` (CIP 2010 to SOC 2010).
#'
#' @return A data frame with columns `cip_code`, `cip_title`, `soc_code`,
#'   `soc_title`, `cip_vintage`, `soc_vintage`. The vintage columns are
#'   integers, so crosswalks can be row-bound and stay self-describing.
#'
#' @seealso [get_degrees()], [get_ipeds_codebook()]
#'
#' @source NCES CIP resources:
#'   \url{https://nces.ed.gov/ipeds/cipcode/resources.aspx}
#'
#' @examples
#' xw <- get_cip_soc_crosswalk()
#' head(xw)
#'
#' # Which occupations does a computer science degree map to?
#' xw[xw$cip_code == "11.0701", c("soc_code", "soc_title")]
#'
#' \dontrun{
#' # Degrees awarded in programs feeding software development occupations
#' comp <- get_degrees(geography = "institution", years = 2022)
#' soc  <- c("15-1251", "15-1252", "15-1253", "15-1254")
#' cips <- unique(xw$cip_code[xw$soc_code %in% soc])
#' sum(comp$count_total_students[
#'   comp$cip_code %in% cips &
#'   comp$major_num == 1 &
#'   comp$cipcode != "99.0000"
#' ])
#' }
#' @export
get_cip_soc_crosswalk <- function(vintage = c("2020", "2010")) {
  vintage <- match.arg(vintage)

  file <- sprintf("cip_soc_%s.rds", vintage)
  path <- system.file("extdata", file, package = "cori.data.ipeds")

  if (!nzchar(path) || !file.exists(path)) {
    stop(sprintf(
      "Crosswalk file '%s' not found in the installed package. Rebuild it with data-raw/build_cip_soc_crosswalk.R",
      file
    ))
  }

  readRDS(path)
}
