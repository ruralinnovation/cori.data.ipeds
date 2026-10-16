# Query institution-level IPEDS data from S3

Queries processed institution-level parquet files from S3 via DuckDB.
Returns wide-format data — column structure varies by survey.

## Usage

``` r
.ipeds_institution_query(
  survey,
  years = NULL,
  unitids = NULL,
  geoids = NULL,
  s3_bucket = "cori.data.ipeds",
  s3_path_prefix = ""
)
```

## Arguments

- survey:

  Character. One of `"institutional_characteristics"`, `"completions"`
  (awards by program), `"completers"` (student headcounts by award
  level, 2012 onward), or `"grad_rates"`.

- years:

  Integer vector. Years to return. Default: all available.

- unitids:

  Character vector. IPEDS unit IDs to return. Default: all.

- geoids:

  Character vector. 5-digit county GEOIDs. Returns all institutions in
  those counties. Default: all.

- s3_bucket:

  Character. Default: `"cori.data.ipeds"`.

- s3_path_prefix:

  Character. Default: `""`.

## Value

A wide data frame, one row per institution and the survey's own
dimensions: institution for `institutional_characteristics`, institution
x CIP x award level x major number for `completions`, and institution x
cohort type for `grad_rates`.

Columns are exactly the `level == "institution"` and `level == "both"`
variables that
[`get_ipeds_codebook()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/get_ipeds_codebook.md)
lists for that survey, plus `year`, plus `survey` (derived from the S3
partition path). The `institutional_characteristics` output additionally
carries the derived flags `is_public`, `is_nonprofit`, `is_forprofit`,
`is_4yr`, `is_2yr`, `is_degree_granting`, `is_hbcu`, and `is_tribal`.

Rather than enumerating columns here, query the codebook – it is the
source the column selection is driven from, so it cannot drift:
`cb <- get_ipeds_codebook(); cb[cb$survey == "completions", ]`.

Note that `completions` retains NCES `cipcode` 99 rows (each
institution's grand total across programs) and `major_num` 2 rows
(second majors). Both are convenient at institution level but must be
excluded before summing, or degrees are counted more than once; the
county aggregations already exclude them.

## Details

Because each survey has a different schema, only one survey can be
queried per call. Use `geoids` to pull all institutions in one or more
counties, then aggregate on your own terms.

## See also

[`get_ipeds()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/get_ipeds.md),
[`get_ipeds_codebook()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/get_ipeds_codebook.md)

## Examples

``` r
if (FALSE) { # \dontrun{
# All institutions in Grafton County NH
get_institutions(geography = "institution", geoids = "33009")

# Completions for a specific institution
get_degrees(geography = "institution", unitids = "182670")
} # }
```
