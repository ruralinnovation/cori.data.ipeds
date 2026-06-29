# data-raw/build_dictionaries.R
#
# Documents the origin of the three IPEDS data dictionaries bundled in
# inst/extdata/. Run this script to regenerate or update the dictionaries.
#
# The dictionaries were originally hand-curated from the NCES IPEDS Data
# Center variable documentation:
#   https://nces.ed.gov/ipeds/datacenter/DataFiles.aspx
#
# Each CSV maps IPEDS variable names (var) to snake_case aliases for the
# three surveys covered by this package:
#
#   inst/extdata/institutional_characteristics.csv
#   inst/extdata/completions.csv
#   inst/extdata/grad_rates.csv
#
# Columns: survey, year, source_table, download_table_url, var, alias,
#          description, unit_of_analysis (completions + grad_rates only)
#
# To update for a new NCES release year, add rows for the new year to each
# CSV following the existing pattern. The download_table_url should point to
# the new NCES ZIP file. The var and alias columns should match the new
# NCES data file's column names.
#
# After updating, copy the CSVs to inst/extdata/ and rebuild the package:
#
#   file.copy("data-raw/institutional_characteristics.csv",
#             "inst/extdata/institutional_characteristics.csv",
#             overwrite = TRUE)
#   devtools::document()
#   devtools::install()
