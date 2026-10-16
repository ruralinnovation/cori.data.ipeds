# Write processed county-level data for one year to S3

Reads institution-level parquets (written by
[`write_ipeds_institution_to_s3()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/write_ipeds_institution_to_s3.md)),
derives county aggregations, writes one parquet per year, uploads to S3.
Skips if already written.

## Usage

``` r
write_ipeds_county_to_s3(
  year,
  staging_dir = "data/ipeds",
  s3_bucket = "cori.data.ipeds",
  s3_path_prefix = "",
  overwrite = FALSE,
  sync_to_s3 = TRUE
)
```

## Arguments

- year:

  Integer.

- staging_dir:

  Character. Default: `"data/ipeds"`.

- s3_bucket:

  Character. Default: `"cori.data.ipeds"`.

- s3_path_prefix:

  Character. Default: `""`.

- overwrite:

  Logical. Default: `FALSE`.

- sync_to_s3:

  Logical. Default: `TRUE`.

## Value

Invisibly returns a one-row manifest data frame.
