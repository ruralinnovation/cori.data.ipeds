# Run the full IPEDS ETL pipeline for a range of years

Runs all three layers (raw → institution → county) for each year in
order. Each layer skips already-written vintages unless
`overwrite = TRUE`.

## Usage

``` r
write_ipeds_all(
  years = IPEDS_START_YEAR:IPEDS_END_YEAR,
  staging_dir = "data/ipeds",
  s3_bucket = "cori.data.ipeds",
  s3_path_prefix = "",
  overwrite = FALSE,
  sync_to_s3 = TRUE,
  layers = c("raw", "institution", "county")
)
```

## Arguments

- years:

  Integer vector. Default: 2010 to current year.

- staging_dir:

  Character.

- s3_bucket:

  Character.

- s3_path_prefix:

  Character.

- overwrite:

  Logical. Reprocess even if already written. Default: `FALSE`.

- sync_to_s3:

  Logical. Upload to S3 after writing locally. Default: `TRUE`.

- layers:

  Character vector. Which layers to run. Default: all three.

## Value

Invisibly returns a manifest data frame.
