# Read a raw IPEDS CSV for one survey vintage

Downloads (if not cached) and reads the NCES CSV with no transformation.
Column names are original NCES uppercase. Values are original including
IPEDS sentinel codes. Adds a `year` column.

## Usage

``` r
read_ipeds_raw(survey, year, staging_dir = "data/ipeds")
```

## Arguments

- survey:

  Character. One of `"institutional_characteristics"`, `"completions"`,
  `"grad_rates"`.

- year:

  Integer. Vintage year.

- staging_dir:

  Character. Local staging directory. Default: `"data/ipeds"`.

## Value

Data frame: original NCES columns plus `year`.
