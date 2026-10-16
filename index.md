# cori.data.ipeds

Access and analyze [Integrated Postsecondary Education Data System
(IPEDS)](https://nces.ed.gov/ipeds/) data at both the institution and
county levels. Covers institutional characteristics, degree completions,
and graduation rates from 2010 to the present.

## Surveys Covered

| Survey | Unit of Analysis | Years |
|----|----|----|
| Institutional Characteristics (IC) | Institution | 2010–present |
| Completions (C) | Institution / CIP / Award Level | 2010–present (student counts 2012–present) |
| Graduation Rates (GR) | Institution / Cohort | 2010–present |

## Installation

``` r

# install.packages("remotes")
remotes::install_github("ruralinnovation/cori.data.ipeds")
```

## Quick Start

``` r

library(cori.data.ipeds)

# One function per measure; `geography` is the first argument
get_institutions(geoids = "33009", years = 2022)      # institutional presence
get_degrees(geoids = "33009", years = 2022)           # degrees conferred
get_completers(geoids = "33009", years = 2022)        # students completing
get_graduation_rates(geoids = "33009", years = 2022)  # completion outcomes

# `geography` selects the geographic unit. County is tidy long; institution
# is point-level and wide.
get_degrees(geography = "institution", geoids = "33009", years = 2022)

# Everything about a county, across all four functions, in one call
get_ipeds(geoids = "33009", years = 2022)

# Variable definitions, coverage, vintage caveats and value labels
# (e.g., what sector_code = 4 means, plus the other 19 categorical columns)
get_ipeds_codebook()

# Map programs to occupations
get_cip_soc_crosswalk()
```

| Function | Measure | IPEDS survey |
|----|----|----|
| [`get_institutions()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/get_institutions.md) | Institutional presence and composition | Institutional Characteristics (`HD{year}`) |
| [`get_degrees()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/get_degrees.md) | Degrees conferred (by program at the institution level) | Completions (`C{year}_A`) |
| [`get_completers()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/get_completers.md) | Student headcounts by award level (2012+) | Completions (`C{year}_C`) |
| [`get_graduation_rates()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/get_graduation_rates.md) | Completion and transfer-out rates | Graduation Rates (`GR{year}`) |
| [`get_ipeds()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/get_ipeds.md) | All of the above in one call, optionally filtered | All of the above |

## Start exploring

``` r

# Package overview: surveys covered, county and institution levels, counting conventions
vignette("introduction", package = "cori.data.ipeds")

# A worked rural analysis, with charts
vignette("rural-higher-education", package = "cori.data.ipeds")
```

## Output Format

County-level functions return a six-column tidy format:

| Column | Type | Description |
|----|----|----|
| `geoid` | character | 5-digit county FIPS, always zero-padded |
| `year` | integer | Observation year |
| `variable` | character | Snake_case variable name |
| `value` | numeric | The observation |
| `agg_var` | numeric | Denominator or aggregation weight. For `share_degrees_*` variables: total degrees conferred (raw count = `value * agg_var`). For `grad_rate_*` variables: adjusted cohort size. `NA` for institution count variables. |
| `survey` | character | Source survey: `"institutional_characteristics"`, `"completions"`, or `"grad_rates"` |

Institution-level functions return wide format. Column structure varies
by survey.

### County variables

All county-level aggregations are restricted to **degree-granting
institutions only** (`is_degree_granting = 1`). Non-degree-granting
entities (cosmetology schools, professional development organizations,
etc.) appear in the wide institution tables but are excluded from county
output.

| Variable | Survey | Description |
|----|----|----|
| `inst_count` | institutional_characteristics | Degree-granting institutions |
| `public_inst_count` | institutional_characteristics | Public degree-granting institutions |
| `nonprofit_inst_count` | institutional_characteristics | Private nonprofit degree-granting institutions |
| `fouryear_inst_count` | institutional_characteristics | Four-year degree-granting institutions |
| `twoyear_inst_count` | institutional_characteristics | Two-year degree-granting institutions |
| `hbcu_count` | institutional_characteristics | HBCUs |
| `tribal_count` | institutional_characteristics | Tribal colleges |
| `count_degrees_total` | completions | Total degrees conferred (associate through doctoral) |
| `share_degrees_assoc` | completions | Share of degrees that are associate level (AWLEVEL 3) |
| `share_degrees_bach` | completions | Share of degrees that are bachelor’s level (AWLEVEL 5) |
| `share_degrees_masters` | completions | Share of degrees that are master’s level (AWLEVEL 7) |
| `share_degrees_doctoral` | completions | Share of degrees that are doctoral level (AWLEVEL 17, 18, 19) |
| `share_degrees_men` | completions | Share of degrees awarded to men |
| `share_degrees_women` | completions | Share of degrees awarded to women |
| `grad_rate_150pct` | grad_rates | 150% graduation rate (bachelor’s cohort) |
| `transfer_out_rate` | grad_rates | Transfer-out rate (bachelor’s cohort) |

The four `share_degrees_*` level variables sum to exactly 1. Raw counts
are recoverable as `value * agg_var`. Use
[`get_ipeds_codebook()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/get_ipeds_codebook.md)
for full variable definitions.

### Counting conventions

IPEDS includes rows that will double-count degrees if summed naively.
The county aggregations handle this; if you aggregate the
institution-level tables yourself, you need to as well.

| Convention | What it is | How county output handles it |
|----|----|----|
| `cipcode` 99 | Each institution’s grand total across all programs, included alongside the per-program rows | Excluded. Including it exactly doubles every degree count. |
| `major_num` 2 | Second major of a double-majoring student | Excluded, so counts are credentials awarded rather than major-credential pairs. |
| Award level | `ed_level` spans certificates through doctorates | Only degrees are counted: AWLEVEL 3, 5, 7, 17, 18, 19. Certificate levels (1, 2, 4, 6, 8) are excluded entirely, including the sub-associate “1 to 2 year” award (code 2). |
| Cohort type | `grad_rates` rows cover four different cohort universes | Only the four-year full-time first-time bachelor’s cohort (`cohort_type` 2, 3, 4) is aggregated. |

Graduation rates are cohort-weighted across a county’s institutions (the
county-wide completer total over the county-wide adjusted cohort), not
an unweighted mean of institutional rates. NCES publishes graduation
rates about a year after the other two surveys, so the most recent year
typically has completions and institutional characteristics but no
graduation rates.

## Refreshing the Data

The package reads data from an S3 bucket maintained by CORI staff using
internal pipeline functions. The pipeline is incremental:
already-processed vintages are skipped, so only new NCES releases need
to be added each year.

## Data Source

Produced by the [National Center for Education Statistics
(NCES)](https://nces.ed.gov/), U.S. Department of Education. Released
annually, typically 9–12 months after the reference year.
