# Get students completing degrees

Student headcounts from the IPEDS Completions survey's completers file.
Distinct from
[`get_degrees()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/get_degrees.md),
which counts awards: a student earning two degrees at one level is one
completer but two degrees.

## Usage

``` r
get_completers(
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
Institution level: `unitid`, `geoid`, `award_level_category`,
`count_men`, `count_women`, `count_total_students`, `year`, `survey`.

## Details

County variables are per award level and must not be summed across
levels – a student earning degrees at two levels in one year appears at
both. Coverage starts in 2012; NCES published no completers file before
that.

## See also

[`get_degrees()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/get_degrees.md)

## Examples

``` r
if (FALSE) { # \dontrun{
get_completers(geoids = "33009", years = 2022)
} # }
```
