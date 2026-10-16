# Write raw IPEDS data for one survey vintage to S3

Reads the NCES CSV via
[`read_ipeds_raw()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/read_ipeds_raw.md),
writes it as parquet locally, then uploads to S3. Skips if already
written unless `overwrite = TRUE`.

## Usage

``` r
write_ipeds_raw_to_s3(
  survey,
  year,
  staging_dir = "data/ipeds",
  s3_bucket = "cori.data.ipeds",
  s3_path_prefix = "",
  overwrite = FALSE,
  sync_to_s3 = TRUE
)
```

## Arguments

- survey:

  Character.

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

  Logical. Set `FALSE` for local-only testing. Default: `TRUE`.

## Value

Invisibly returns a one-row manifest data frame.
