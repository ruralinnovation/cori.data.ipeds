# Get graduation and transfer-out rates

Completion outcomes from the IPEDS Graduation Rates survey, for the
four-year full-time first-time bachelor's degree-seeking cohort.

## Usage

``` r
get_graduation_rates(
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
Institution level: `unitid`, `geoid`, `cohort_type`, `grad_rate_status`,
`count_men`, `count_women`, `count_total_students`, `year`, `survey`.

## Details

County rates are cohort-weighted across the county's institutions, not a
mean of institutional rates, and `agg_var` carries the adjusted cohort
so they can be weighted correctly when rolled up further. A county-year
where no institution reported is omitted rather than returned as zero,
so `transfer_out_rate` is absent for roughly a quarter of the
county-years that have a graduation rate. NCES publishes this survey
about a year behind the others.

## See also

[`get_degrees()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/get_degrees.md),
[`get_ipeds_codebook()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/get_ipeds_codebook.md)

## Examples

``` r
if (FALSE) { # \dontrun{
get_graduation_rates(geoids = "33009", years = 2012:2023)
} # }
```
