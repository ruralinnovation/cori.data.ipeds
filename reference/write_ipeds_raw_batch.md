# Write raw IPEDS data for multiple surveys and years to S3

Loops over all combinations of surveys and years, calling
[`write_ipeds_raw_to_s3()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/write_ipeds_raw_to_s3.md)
for each. Skips already-written vintages unless `overwrite = TRUE`.

## Usage

``` r
write_ipeds_raw_batch(
  years = IPEDS_START_YEAR:IPEDS_END_YEAR,
  surveys = IPEDS_SURVEYS,
  staging_dir = "data/ipeds",
  s3_bucket = "cori.data.ipeds",
  s3_path_prefix = "",
  overwrite = FALSE,
  sync_to_s3 = TRUE
)
```

## Arguments

- years:

  Integer vector. Default: 2010 to current year.

- surveys:

  Character vector. Default: all three surveys.

- staging_dir:

  Character.

- s3_bucket:

  Character.

- s3_path_prefix:

  Character.

- overwrite:

  Logical.

- sync_to_s3:

  Logical.

## Value

Invisibly returns a data frame summarising what was written.
