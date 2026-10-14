# Package-level constants -----------------------------------------------------

IPEDS_START_YEAR <- 2010L
IPEDS_END_YEAR   <- 2024L
IPEDS_SURVEYS    <- c("institutional_characteristics", "completions",
                      "completers", "grad_rates")

# The completers survey (NCES file C{year}_C) was first published for 2012,
# two years after the other three. Vintages before this are skipped.
COMPLETERS_START_YEAR <- 2012L
