# Process all three surveys for a single year

Convenience wrapper that processes IC first (to build the geo lookup),
then completions and grad rates. Returns a named list of three data
frames.

## Usage

``` r
process_ipeds_institution_all(
  year,
  staging_dir = "data/ipeds",
  codebook = NULL
)
```

## Arguments

- year:

  Integer.

- staging_dir:

  Character.

- codebook:

  Data frame or `NULL`.

## Value

Named list with elements `institutional_characteristics`, `completions`,
`completers`, `grad_rates`. An element is `NULL` when NCES has not
published that survey for the year – `completers` starts in 2012, and
grad rates lag the other surveys by about a year.
