# Variable codebook for all processed IPEDS output


#' Get the IPEDS variable codebook
#'
#' Returns a data frame describing every variable available in the county-level
#' tidy output from \code{\link{read_ipeds_county_from_s3}}. Use this to look
#' up variable names, units, descriptions, and which survey each comes from.
#'
#' @return A data frame with columns:
#'   \describe{
#'     \item{variable}{Character. Variable name as it appears in the
#'       \code{variable} column of county output.}
#'     \item{survey}{Character. Source survey: \code{"ic"},
#'       \code{"completions"}, or \code{"grad_rates"}.}
#'     \item{label}{Character. Short human-readable label.}
#'     \item{description}{Character. Full description of what the variable
#'       measures, how it is computed, and any caveats.}
#'     \item{unit}{Character. Unit of measurement (e.g. \code{"count"},
#'       \code{"rate 0-1"}).}
#'     \item{agg_var_description}{Character. What \code{agg_var} represents
#'       for this variable, or \code{NA} if \code{agg_var} is always
#'       \code{NA}.}
#'   }
#'
#' @examples
#' cb <- get_ipeds_codebook()
#' cb[cb$survey == "grad_rates", ]
#'
#' @export
get_ipeds_codebook <- function() {
  data.frame(
    stringsAsFactors = FALSE,

    variable = c(
      # IC -- institution counts (degree-granting only)
      "inst_count",
      "public_inst_count",
      "nonprofit_inst_count",
      "fouryear_inst_count",
      "twoyear_inst_count",
      "hbcu_count",
      "tribal_count",
      # Completions -- total count (anchor)
      "count_degrees_total",
      # Completions -- shares by level (raw count = value * agg_var)
      "share_degrees_assoc",
      "share_degrees_bach",
      "share_degrees_masters",
      "share_degrees_doctoral",
      # Completions -- shares by sex
      "share_degrees_men",
      "share_degrees_women",
      # Graduation rates
      "grad_rate_150pct",
      "transfer_out_rate"
    ),

    survey = c(
      rep("ic", 7),
      rep("completions", 7),
      rep("grad_rates", 2)
    ),

    label = c(
      # IC (all counts are degree-granting institutions only)
      "Total degree-granting institutions",
      "Public degree-granting institutions",
      "Private nonprofit degree-granting institutions",
      "Four-year degree-granting institutions",
      "Two-year degree-granting institutions",
      "HBCUs (degree-granting)",
      "Tribal colleges (degree-granting)",
      # Completions
      "Total degrees conferred",
      "Share -- associate degrees",
      "Share -- bachelor's degrees",
      "Share -- master's degrees",
      "Share -- doctoral degrees",
      "Share -- awarded to men",
      "Share -- awarded to women",
      # Grad rates
      "150% graduation rate",
      "Transfer-out rate"
    ),

    description = c(
      # IC -- all counts restricted to degree_granting_status == 1
      paste0(
        "Count of degree-granting postsecondary institutions in the county ",
        "reporting to IPEDS IC (degree_granting_status = 1). Excludes ",
        "administrative units, less-than-2-year schools, and any institution ",
        "not conferring awards."
      ),
      paste0(
        "Count of publicly funded degree-granting institutions ",
        "(sector codes 1, 4, 7) in the county."
      ),
      paste0(
        "Count of private nonprofit degree-granting institutions ",
        "(sector codes 2, 5, 8) in the county."
      ),
      paste0(
        "Count of four-year or above degree-granting institutions ",
        "(sector codes 1, 2, 3) in the county."
      ),
      paste0(
        "Count of two-year degree-granting institutions ",
        "(sector codes 4, 5, 6) in the county."
      ),
      paste0(
        "Count of Historically Black Colleges and Universities with ",
        "degree-granting status (HBCU flag = 1) in the county."
      ),
      paste0(
        "Count of tribal colleges and universities with degree-granting ",
        "status (tribal college flag = 1) in the county."
      ),
      # Completions
      paste0(
        "Total postsecondary awards and degrees conferred in the county across ",
        "all CIP codes and award levels. Anchor count used as the denominator ",
        "for all share_degrees_* variables (stored in their agg_var column). ",
        "Raw count for any share variable is recoverable as value * agg_var."
      ),
      paste0(
        "Share of total degrees that are associate level (IPEDS award level ",
        "codes 2 and 3). Range: 0 to 1. ",
        "Raw count = value * agg_var."
      ),
      paste0(
        "Share of total degrees that are bachelor's level (IPEDS award level ",
        "code 5). Range: 0 to 1. ",
        "Raw count = value * agg_var."
      ),
      paste0(
        "Share of total degrees that are master's level (IPEDS award level ",
        "code 7). Range: 0 to 1. ",
        "Raw count = value * agg_var."
      ),
      paste0(
        "Share of total degrees that are doctoral level (IPEDS award level ",
        "codes 9, 10, 11 -- research, other doctoral, and professional ",
        "practice). Range: 0 to 1. ",
        "Raw count = value * agg_var."
      ),
      paste0(
        "Share of total degrees awarded to men across all CIP codes and award ",
        "levels. Range: 0 to 1. ",
        "Raw count = value * agg_var."
      ),
      paste0(
        "Share of total degrees awarded to women across all CIP codes and ",
        "award levels. Range: 0 to 1. ",
        "Raw count = value * agg_var."
      ),
      # Grad rates
      paste0(
        "Share of the full-time, first-time bachelor's degree-seeking cohort ",
        "(cohort type 1) completing a degree or certificate within 150% of ",
        "normal time. Computed as sum(completers) / sum(adjusted cohort) ",
        "across all institutions in the county. Range: 0 to 1."
      ),
      paste0(
        "Share of the full-time, first-time bachelor's degree-seeking cohort ",
        "(cohort type 1) transferring out without a degree. Computed as ",
        "sum(transfers) / sum(adjusted cohort) across all institutions in the ",
        "county. Range: 0 to 1."
      )
    ),

    unit = c(
      rep("count", 7),
      "count",
      rep("share 0-1", 6),
      rep("rate 0-1", 2)
    ),

    agg_var_description = c(
      rep(NA_character_, 7),
      NA_character_,
      rep("Total degrees conferred in county (denominator; raw count = value * agg_var)", 6),
      rep("Sum of adjusted cohort sizes across all institutions in the county (use as weight when averaging rates)", 2)
    )
  )
}
