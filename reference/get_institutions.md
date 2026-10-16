# Get higher education institutions

Institutional presence and composition from the IPEDS Institutional
Characteristics survey. At county level this is counts of
degree-granting institutions by control and level; at institution level
it is the institution directory, one row per institution with location,
sector, classification and derived flags.

## Usage

``` r
get_institutions(
  geography = "county",
  geoids = NULL,
  years = NULL,
  variables = NULL,
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

- unitids:

  Character vector of IPEDS unit IDs. Institution level only.

- s3_bucket, s3_path_prefix:

  Storage location. Defaults are production.

## Value

County level: `geoid`, `year`, `variable`, `value`, `agg_var`, `survey`.
Institution level: the codebook's institution-level columns for this
survey, plus derived flags, `year` and `survey`.

## See also

[`get_degrees()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/get_degrees.md),
[`get_completers()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/get_completers.md),
[`get_graduation_rates()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/get_graduation_rates.md),
[`get_ipeds_codebook()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/get_ipeds_codebook.md)

## Examples

``` r
if (FALSE) { # \dontrun{
get_institutions(geoids = "33009", years = 2022)
get_institutions(geography = "institution", geoids = "33009", years = 2022)
} # }
```
