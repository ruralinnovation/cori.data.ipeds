# Query county-level IPEDS data from S3

Queries the processed county-level parquet files from S3 via DuckDB.
Returns the 6-column tidy format: one row per county / year / variable.

## Usage

``` r
.ipeds_county_query(
  years = NULL,
  geoids = NULL,
  variables = NULL,
  surveys = NULL,
  s3_bucket = "cori.data.ipeds",
  s3_path_prefix = ""
)
```

## Arguments

- years:

  Integer vector. Years to return. Default: all available.

- geoids:

  Character vector. 5-digit county FIPS codes to return. Default: all
  counties.

- variables:

  Character vector. Variable names to return (e.g.
  `"completions_total"`, `"grad_rate_150pct"`). Default: all. Call
  [`get_ipeds_codebook()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/get_ipeds_codebook.md)
  for the full list.

- surveys:

  Character vector. One or more of `"institutional_characteristics"`,
  `"completions"`, `"completers"`, `"grad_rates"`. Default: all.

- s3_bucket:

  Character. S3 bucket name. Default: `"cori.data.ipeds"`.

- s3_path_prefix:

  Character. Optional path prefix (e.g. `"test/"`). Default: `""`.

## Value

A data frame with columns: `geoid` (character, 5-digit FIPS), `year`
(integer), `variable` (character), `value` (numeric), `agg_var`
(numeric), `survey` (character).

Note that `completions` variables count awards while `completers`
variables count students, so the two are not interchangeable and the
`count_students_*` variables must not be summed across award levels.

## Details

County data combines all three IPEDS surveys (IC, completions,
graduation rates) into a single table. Use the `surveys` argument to
filter to a specific survey, or `variables` to select specific metrics.

## See also

[`get_ipeds()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/get_ipeds.md),
[`get_ipeds_codebook()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/get_ipeds_codebook.md)

Note this differs from
[`get_ipeds()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/get_ipeds.md),
which takes `survey` first and requires it. Here every filter is
optional and `years` comes first, so pass the survey by name:
`get_ipeds(surveys = "completions")`, not `get_ipeds("completions")`.
Passing it positionally used to return zero rows silently; it now
errors.

## Examples

``` r
if (FALSE) { # \dontrun{
# All county data for Grafton County NH
get_ipeds(geoids = "33009")

# Graduation rates for all counties, 2015-2023
get_ipeds(
  variables = "grad_rate_150pct",
  years     = 2015:2023
)
} # }
```
