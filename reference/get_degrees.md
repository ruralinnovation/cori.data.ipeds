# Get degrees conferred

Credential production from the IPEDS Completions survey. At county level
this is total degrees conferred and the share by level and by sex; at
institution level it is awards by program, one row per institution x CIP
code x award level x major number.

## Usage

``` r
get_degrees(
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

County level: `geoid`, `year`, `variable`, `value`, `agg_var`, `survey`,
where `agg_var` is total degrees so `value * agg_var` recovers a raw
count. Institution level: `unitid`, `geoid`, `cipcode`, `major_num`,
`ed_level`, `count_men`, `count_women`, `count_total_students`, `year`,
`survey`.

## Details

County figures count degrees only – associate through doctoral – and
exclude NCES grand-total rows and second majors. The institution table
retains both, so see
[`get_ipeds_codebook()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/get_ipeds_codebook.md)
before aggregating it yourself.

## See also

[`get_completers()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/get_completers.md)
for student headcounts rather than awards,
[`get_cip_soc_crosswalk()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/get_cip_soc_crosswalk.md)
to map programs to occupations

## Examples

``` r
if (FALSE) { # \dontrun{
get_degrees(geoids = "33009", years = 2022)
get_degrees(geography = "institution", geoids = "33009", years = 2022)
} # }
```
