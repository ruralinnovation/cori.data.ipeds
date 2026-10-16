# Write processed institution-level data for one year to S3

Reads from local raw parquet, processes all three surveys via
[`process_ipeds_institution_all()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/process_ipeds_institution_all.md),
writes one parquet per survey locally, then uploads to S3. Skips if
already written.

## Usage

``` r
write_ipeds_institution_to_s3(
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

Invisibly returns a data frame summarising what was written.
