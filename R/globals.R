# Package-level constants -----------------------------------------------------

IPEDS_START_YEAR <- 2010L
IPEDS_END_YEAR   <- 2024L
IPEDS_SURVEYS    <- c("ic", "completions", "grad_rates")


# globalVariables() declarations to silence R CMD check NOTEs for symbols
# used in stats::aggregate() formula notation and data frame column references.

utils::globalVariables(c(
  # process_ipeds_gr.R — formula LHS/RHS in aggregate()
  "cohort_size",
  "completers",
  "transfers",
  "county_fips"
))
