# For CORI data engineers

To pick up a new NCES IPEDS release, run `refresh_ipeds.R` — the pipeline is
incremental, so it only needs the full year range, not just the new year.

The codebook is R code, not data: see `R/get_ipeds_codebook.R`. Adding or
changing a variable means editing that file, then `devtools::document()`.

`build_dictionaries.R` is provenance notes for `dictionaries/` -- the NCES
variable inventories kept as reference when extending coverage. Nothing in
the pipeline reads them, and running that script does nothing.

`validate_etl.R` runs a battery of consistency checks against `data_county`
and `data_institution` on S3 — run it after `refresh_ipeds.R` (or it's
called automatically at the end of that script).

See `?write_ipeds_all` for pipeline options including `overwrite`, `layers`,
and `s3_path_prefix` for testing against a non-production path.
