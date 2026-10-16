# Process one IPEDS survey vintage to institution level

Reads the raw parquet for the given survey and year, applies
[`reconcile_vintage()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/reconcile_vintage.md),
applies the codebook renaming, attaches lat/long from IC (for
completions and grad rates), and returns the processed data frame.

## Usage

``` r
process_ipeds_institution(
  survey,
  year,
  staging_dir = "data/ipeds",
  codebook = NULL,
  geo_lookup = NULL
)
```

## Arguments

- survey:

  Character. One of `"institutional_characteristics"`, `"completions"`,
  `"completers"`, `"grad_rates"`.

- year:

  Integer. Vintage year.

- staging_dir:

  Character. Local staging directory. Default: `"data/ipeds"`.

- codebook:

  Data frame or `NULL`. Pass a pre-loaded codebook to avoid repeated
  disk reads when processing multiple surveys. If `NULL`, the codebook
  is loaded automatically.

- geo_lookup:

  Data frame or `NULL`. Pre-built unitid -\> geo lookup from the
  processed IC data for this year. If `NULL` and survey is not
  `"institutional_characteristics"`, geo is looked up automatically from
  the local IC raw parquet.

## Value

Processed data frame with canonical column names and lat/long.
