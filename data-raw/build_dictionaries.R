# data-raw/build_dictionaries.R
#
# Provenance notes for the reference material in data-raw/dictionaries/.
# This script documents where those files came from; it is not part of the
# pipeline and running it does nothing.
#
# NOTHING IN THE PIPELINE READS THESE FILES. The package codebook lives in
# R/get_ipeds_codebook.R as an inline data frame (matching the convention in
# cori.data.pep, cori.data.hu and cori.data.qcew), and NCES download URLs and
# in-ZIP filenames are derived from survey and year by .raw_download_url(),
# .raw_table_name() and .raw_csv_candidates() in R/write_raw_to_s3.R.
#
# data-raw/dictionaries/ holds:
#
#   institutional_characteristics.csv
#   completions.csv
#   grad_rates.csv
#     Hand-curated inventories of every NCES variable in each survey back to
#     1980, with per-year source table, download URL, description and a
#     proposed snake_case alias. Curated from the NCES IPEDS Data Center
#     variable documentation at
#     https://nces.ed.gov/ipeds/datacenter/DataFiles.aspx
#
#     These drove the pre-refactor, dictionary-driven pipeline. They are kept
#     because the per-year variable inventory and the human-readable NCES
#     descriptions are expensive to reproduce and are the natural starting
#     point when extending coverage to a new survey or variable.
#
#   codebook_pre_refactor.csv
#     The codebook as it existed before it moved into R code. Kept for
#     diffing; R/get_ipeds_codebook.R supersedes it.
#
# TO ADD A VARIABLE TO THE PACKAGE OUTPUT
#
#   1. Look it up in the relevant dictionary above to confirm the NCES
#      column name and which years carry it.
#   2. Add a .cb_row() entry in R/get_ipeds_codebook.R with that column as
#      `raw_variable`, and record any vintage caveats in `notes`.
#   3. If the column name or meaning changed across years, add the fix to
#      the appropriate reconciler in R/reconcile_vintage.R.
#   4. devtools::document(), then re-run the pipeline for affected years
#      with write_ipeds_all(overwrite = TRUE).
#
# TO PICK UP A NEW NCES RELEASE YEAR
#
#   See data-raw/refresh_ipeds.R. Bump IPEDS_END_YEAR in R/globals.R; the
#   dictionaries do not need editing.
