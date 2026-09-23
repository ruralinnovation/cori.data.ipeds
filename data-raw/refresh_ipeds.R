# For CORI data engineers
#
# Run this after NCES publishes a new IPEDS release (see RELEASE_CALENDAR.md
# for the annual schedule) to add the new year(s) to S3.
#
# The pipeline is incremental across all three layers (raw -> institution ->
# county) -- vintages already written are skipped automatically, so it's
# always safe to pass the full year range rather than just the new year.

devtools::load_all(".")

latest_year <- as.integer(format(Sys.Date(), "%Y")) - 1L

# Bump IPEDS_END_YEAR in R/globals.R to latest_year as part of this release
# so write_ipeds_all()'s own default stays in sync.
write_ipeds_all(years = IPEDS_START_YEAR:latest_year, sync_to_s3 = TRUE)

# Then validate:
source("data-raw/validate_etl.R")
