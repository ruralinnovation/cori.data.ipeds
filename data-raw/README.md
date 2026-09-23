# For CORI data engineers

To pick up a new NCES IPEDS release, run `refresh_ipeds.R` — the pipeline is
incremental, so it only needs the full year range, not just the new year.

`build_dictionaries.R` documents the origin of `inst/extdata/codebook.csv`
and the three legacy dictionary CSVs; rerun it if a variable mapping needs
to change.

`validate_etl.R` runs a battery of consistency checks against `data_county`
and `data_institution` on S3 — run it after `refresh_ipeds.R` (or it's
called automatically at the end of that script).

See `?write_ipeds_all` for pipeline options including `overwrite`, `layers`,
and `s3_path_prefix` for testing against a non-production path.
