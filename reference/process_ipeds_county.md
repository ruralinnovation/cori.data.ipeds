# Derive county-level data from institution-level data frames

Accepts the named list returned by
[`process_ipeds_institution_all()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/process_ipeds_institution_all.md)
and returns a single tidy data frame with county-level metrics.

## Usage

``` r
process_ipeds_county(inst_list)
```

## Arguments

- inst_list:

  Named list with elements `institutional_characteristics`,
  `completions`, `grad_rates`. Output of
  [`process_ipeds_institution_all()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/process_ipeds_institution_all.md).

## Value

Tidy data frame: geoid, year, variable, value, agg_var, survey.
