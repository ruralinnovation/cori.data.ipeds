# Get IPEDS data across surveys

The general getter underneath
[`get_institutions()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/get_institutions.md),
[`get_degrees()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/get_degrees.md),
[`get_completers()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/get_completers.md)
and
[`get_graduation_rates()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/get_graduation_rates.md).
Use it to pull every variable for a county in one call, or to filter
across surveys.

## Usage

``` r
get_ipeds(
  geography = "county",
  geoids = NULL,
  years = NULL,
  variables = NULL,
  surveys = NULL,
  unitids = NULL,
  s3_bucket = "cori.data.ipeds",
  s3_path_prefix = ""
)
```

## Arguments

- geography:

  Grain: `"county"` (default) for tidy long output, or `"institution"`
  for the wide per-institution table.

- geoids:

  Character vector of 5-digit county FIPS codes. Default `NULL` returns
  all counties. Filters by county at either level.

- years:

  Integer vector of years. Default `NULL` returns all available.
  Coverage is 2010 to present.

- variables:

  Character vector of county-level variable names, e.g. `"inst_count"`.
  County level only – see
  [`get_ipeds_codebook()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/get_ipeds_codebook.md).

- surveys:

  Character vector of survey names: any of
  `"institutional_characteristics"`, `"completions"`, `"completers"`,
  `"grad_rates"`. Default `NULL` returns all (county level only).

- unitids:

  Character vector of IPEDS unit IDs. Institution level only.

- s3_bucket, s3_path_prefix:

  Storage location. Defaults are production.

## Value

County level: tidy long across the requested surveys. Institution level:
the wide table for the one requested survey.

## Details

At `geography = "institution"` a single `surveys` value is required,
because each survey has a different wide schema.

## See also

[`get_ipeds_codebook()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/get_ipeds_codebook.md)

## Examples

``` r
if (FALSE) { # \dontrun{
# Everything known about one county in one year
get_ipeds(geoids = "33009", years = 2022)

# One survey, institution level
get_ipeds(geography = "institution", surveys = "completions", years = 2022)
} # }
```
