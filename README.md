# cori.data.ipeds

Access and analyze [Integrated Postsecondary Education Data System (IPEDS)](https://nces.ed.gov/ipeds/) data at both the institution and county level. Covers institutional characteristics, degree completions, and graduation rates from 2010 to present.

## Surveys Covered

| Survey | Unit of Analysis | Years |
|---|---|---|
| Institutional Characteristics (IC) | Institution | 2010–present |
| Completions (C) | Institution / CIP / Award Level | 2010–present |
| Graduation Rates (GR) | Institution / Cohort | 2010–present |

## Installation

```r
# install.packages("remotes")
remotes::install_github("ruralinnovation/cori.data.ipeds")
```

## Quick Start

```r
library(cori.data.ipeds)

# One function per measure, `geography` first — same shape as
# cori.data.qcew::get_employment() and the rest of the family.
get_institutions(geoids = "33009", years = 2022)      # institutional presence
get_degrees(geoids = "33009", years = 2022)           # credentials conferred
get_completers(geoids = "33009", years = 2022)        # students completing
get_graduation_rates(geoids = "33009", years = 2022)  # completion outcomes

# `geography` switches grain. County is tidy long; institution is wide.
get_degrees(geography = "institution", geoids = "33009", years = 2022)
# unitid | county_fips | cipcode | major_num | ed_level | count_* | year

# Everything about a county, across all four surveys, in one call
get_ipeds(geoids = "33009", years = 2022)

# Variable definitions, coverage and vintage caveats
get_ipeds_codebook()

# Map programs to occupations
get_cip_soc_crosswalk()
```

| Function | Measure | IPEDS survey |
|---|---|---|
| `get_institutions()` | Institutional presence and composition | Institutional Characteristics |
| `get_degrees()` | Credentials conferred, by program at institution grain | Completions |
| `get_completers()` | Students completing, by award level (2012+) | Completions (completers file) |
| `get_graduation_rates()` | Completion and transfer-out rates | Graduation Rates |
| `get_ipeds()` | All of the above, or filtered across surveys | any |

## Output Format

County-level functions return a six-column tidy format:

| Column | Type | Description |
|---|---|---|
| `geoid` | character | 5-digit county FIPS, always zero-padded |
| `year` | integer | Observation year |
| `variable` | character | Snake_case variable name |
| `value` | numeric | The observation |
| `agg_var` | numeric | Denominator or aggregation weight. For `share_degrees_*` variables: total degrees conferred (raw count = `value * agg_var`). For `grad_rate_*` variables: adjusted cohort size. `NA` for institution count variables. |
| `survey` | character | Source survey: `"institutional_characteristics"`, `"completions"`, or `"grad_rates"` |

Institution-level functions return wide format. Column structure varies by survey — see `get_ipeds(geography = "institution", surveys = )` documentation. `county_fips` is a foreign key to the county-level data.

### County variables

All county-level aggregations are restricted to **degree-granting institutions only** (`degree_granting_status = 1`). Non-degree-granting entities (cosmetology schools, professional development organizations, etc.) appear in the wide institution tables but are excluded from county output.

| Variable | Survey | Description |
|---|---|---|
| `inst_count` | institutional_characteristics | Degree-granting institutions |
| `public_inst_count` | institutional_characteristics | Public degree-granting institutions |
| `nonprofit_inst_count` | institutional_characteristics | Private nonprofit degree-granting institutions |
| `fouryear_inst_count` | institutional_characteristics | Four-year degree-granting institutions |
| `twoyear_inst_count` | institutional_characteristics | Two-year degree-granting institutions |
| `hbcu_count` | institutional_characteristics | HBCUs |
| `tribal_count` | institutional_characteristics | Tribal colleges |
| `count_degrees_total` | completions | Total degrees conferred (associate through doctoral) |
| `share_degrees_assoc` | completions | Share of degrees that are associate level (AWLEVEL 3) |
| `share_degrees_bach` | completions | Share of degrees that are bachelor's level |
| `share_degrees_masters` | completions | Share of degrees that are master's level |
| `share_degrees_doctoral` | completions | Share of degrees that are doctoral level |
| `share_degrees_men` | completions | Share of degrees awarded to men |
| `share_degrees_women` | completions | Share of degrees awarded to women |
| `grad_rate_150pct` | grad_rates | 150% graduation rate (bachelor's cohort) |
| `transfer_out_rate` | grad_rates | Transfer-out rate (bachelor's cohort) |

The four `share_degrees_*` level variables sum to exactly 1. Raw counts are recoverable as `value * agg_var`. Use `get_ipeds_codebook()` for full variable definitions.

### Counting conventions

IPEDS ships rows that will double-count degrees if summed naively. The county aggregations handle this; if you aggregate the institution-level tables yourself, you need to as well.

| Convention | What it is | How county output handles it |
|---|---|---|
| `cipcode` 99 | Each institution's grand total across all programs, shipped alongside the per-program rows | Excluded. Including it exactly doubles every degree count. |
| `major_num` 2 | Second major of a double-majoring student | Excluded, so counts are credentials awarded rather than major-credential pairs. |
| Award level | `ed_level` spans certificates through doctorates | Only degrees are counted: AWLEVEL 3, 5, 7, 17, 18, 19. Certificate levels (1, 2, 4, 6, 8) are excluded entirely, including the sub-associate "1 to 2 year" award (code 2). |
| Cohort type | `grad_rates` rows cover four different cohort universes | Only the four-year full-time first-time bachelor's cohort (`cohort_type` 2, 3, 4) is aggregated. |

Graduation rates are cohort-weighted across a county's institutions -- the county-wide completer total over the county-wide adjusted cohort -- not an unweighted mean of institutional rates. NCES publishes graduation rates about a year behind the other two surveys, so the most recent year typically has completions and institutional characteristics but no grad rates.

## Refreshing the Data

The S3 data is maintained by CORI/RISI staff using internal pipeline functions. The pipeline is incremental — already-processed vintages are skipped, so only new NCES releases need to be added each year.

## Planned Next Steps

### Extend historical coverage to 2000–2009

NCES did not include county FIPS codes or coordinates in IPEDS institutional
characteristics files before 2009. The award level coding scheme for
completions also changed in 2009 (doctoral degrees were split from
"first-professional" into three separate categories), and the IC "highest
degree offered" variable used a different code set pre-2009. Extending
coverage to 2000 requires associating institutions to counties via one of
two methods:

1. **HUD ZIP→county crosswalk** *(preferred)*: The U.S. Department of Housing
   and Urban Development publishes quarterly [USPS ZIP-to-county crosswalk
   files](https://www.huduser.gov/portal/datasets/usps_crosswalk.html). Every
   IPEDS institution has a ZIP code back to 2000. Where a ZIP spans multiple
   counties, the residential address ratio is used to assign the dominant
   county. This approach is clean, reproducible, and requires no external API.

2. **Geocoding / place matching** *(fallback)*: For institutions where the ZIP
   crosswalk is ambiguous (ZIP straddles a county line with a near-even split),
   full street addresses or city/state can be geocoded or matched to Census
   designated places and then linked to counties via a place-to-county
   relationship file.

The HUD crosswalk is the right primary path for a first implementation. Place
matching would serve as a validation or gap-fill step.

## Data Source

Produced by the [National Center for Education Statistics (NCES)](https://nces.ed.gov/), U.S. Department of Education. Released annually, typically 9–12 months after the reference year.
