# Introduction to cori.data.ipeds

## What is this data?

The Integrated Postsecondary Education Data System (IPEDS) is the annual
survey the National Center for Education Statistics collects from every
institution participating in federal student aid programs — roughly
6,000 colleges, universities and technical schools. Reporting is
mandatory for participants, so IPEDS is a near-census of American higher
education rather than a sample.

NCES distributes it as about a dozen separate survey files per year,
each with its own grain and identifier conventions. This package
harmonizes four of them:

| Measure | Getter | NCES file | Grain of the source file |
|----|----|----|----|
| Institutional characteristics | [`get_institutions()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/get_institutions.md) | `HD{year}` | One row per institution |
| Degrees conferred | [`get_degrees()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/get_degrees.md) | `C{year}_A` | Institution × CIP × award level × major number |
| Students completing | [`get_completers()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/get_completers.md) | `C{year}_C` | Institution × award level category |
| Graduation rates | [`get_graduation_rates()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/get_graduation_rates.md) | `GR{year}` | Institution × cohort type × status |

Not covered: enrollment (`EF`), finance (`F`), staff (`S`), admissions
(`ADM`), student financial aid (`SFA`) and outcome measures (`OM`).
Those are separate IPEDS surveys with their own grains, and nothing here
reads them.

Data is available at the **county and institution levels** from **2010
to the present**, with two exceptions: completers begin in 2012, because
NCES published no `C_C` file before that, and graduation rates lag the
other surveys by about a year.

## Quick start

``` r

library(cori.data.ipeds)
```

``` r

# See all available variables, which survey they come from, and their coverage
get_ipeds_codebook()
```

All four data getters follow the same signature,
`get_*(geography, geoids, years, variables, unitids)`, and at county
level return **tidy (long) format**:
`geoid | year | variable | value | agg_var | survey`. `agg_var` carries
the denominator where the variable is a rate or share, so counties can
be rolled up correctly.

``` r

# Institutional presence and composition
institutions <- get_institutions(geoids = "33009", years = 2024)

# Degrees conferred
degrees <- get_degrees(geoids = "33009", years = 2024)

# Students completing — distinct from degrees, see below
completers <- get_completers(geoids = "33009", years = 2024)

# Completion outcomes
grad_rates <- get_graduation_rates(geoids = "33009", years = 2012:2023)
```

[`get_ipeds()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/get_ipeds.md)
is the general getter for pulling across all four functions in one call:

``` r

# Everything known about one county in one year
get_ipeds(geoids = "33009", years = 2024)
```

## Two levels: county and institution

`geography` selects the geographic unit, the same as in other cori.data
packages. IPEDS is collected from institutions rather than places, so
the finest unit available here is the institution itself — every record
carries coordinates, address, city and county — and county output
aggregates those points.

``` r

# County level (default): tidy long, one row per geoid x year x variable
get_degrees(geoids = "33009", years = 2024)

# Institution level: wide, one row per institution and the survey's own
# dimensions -- CIP code, award level, cohort type
get_degrees(geography = "institution", geoids = "33009", years = 2024)
```

The county level is an aggregation restricted to degree-granting
institutions, with NCES’s grand-total rows, second majors and
certificates already excluded. The institution level is deliberately
unfiltered — it keeps everything NCES publishes, including the CIP
detail, so you can aggregate on your own terms.

Two things to know before using the output:

- **`variables` applies to the county level only.** At institution level
  the output is wide, so select columns after the call.
- **Absence is represented by no row.** A county with no degree-granting
  institution does not appear in the county output. Start joins from a
  full county list, or the counties the question is about drop out
  silently.

## What this package changes

Both levels differ from the raw NCES files in the same ways:

- **Canonical names.** `COUNTYCD` becomes `geoid`, `AWLEVEL` becomes
  `ed_level`, and so on.
  [`get_ipeds_codebook()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/get_ipeds_codebook.md)
  is the mapping, and it drives the ETL rather than merely documenting
  it.
- **Sentinels become `NA`.** NCES codes “not reported”, “not applicable”
  and “not available” as `-1`, `-2` and `-3`. Left as integers they
  silently corrupt any mean.
- **Identifiers stay character.** `unitid` is zero-padded to six digits
  and `cipcode` to `"xx.xxxx"`, so CIP families 01 through 09 keep their
  leading zero and still join to the SOC crosswalk.
- **Derived flags are added.** `is_public`, `is_4yr`,
  `is_degree_granting`, `is_hbcu`, `is_tribal` and others are computed
  from `sector_code` and the NCES status codes.

## Decoding categorical variables

Much of IPEDS is categorical, and the institution level returns those
columns as the bare integers NCES publishes. The codebook’s `codes`
column carries the value labels.

``` r

cb <- get_ipeds_codebook()

# Categorical variable labels
cb[nzchar(cb$codes), c("variable", "label")]

# What do sector_code's numbers mean?
cb$codes[cb$variable == "sector_code"]
#> "0 = Administrative unit only; 1 = Public, 4-year or above; ..."
```

Only codes that actually occur in the published data are listed, and the
NCES sentinels are absent because the ETL converts them to `NA`.

## Mapping programs to occupations

[`get_cip_soc_crosswalk()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/get_cip_soc_crosswalk.md)
returns the NCES crosswalk from CIP program codes to SOC occupation
codes, which turns the institution level’s CIP detail into a workforce
measure.

``` r

xw <- get_cip_soc_crosswalk("2020")   # CIP 2020 to SOC 2018, for years 2020+
xw <- get_cip_soc_crosswalk("2010")   # CIP 2010 to SOC 2010, for 2010-2019
```

The relation is many-to-many, so joining it to completions multiplies
rows. Collapse to a distinct CIP set before joining, or any sum
afterwards is inflated.

## Filtering by geography

``` r

# Specific counties
degrees <- get_degrees(geoids = c("33009", "33011"), years = 2015:2024)

# A whole state, via the institution table's st_abbr. This lists only counties
# that contain an institution; start from a full county list before joining
# other data.
mt_counties <- get_institutions(geography = "institution", years = 2024) |>
  dplyr::filter(st_abbr == "MT") |>
  dplyr::distinct(geoid) |>
  dplyr::pull(geoid)

get_degrees(geoids = mt_counties, years = 2024)

# Specific institutions, by IPEDS unit ID
get_degrees(geography = "institution", unitids = "182670", years = 2024)
```

## Rural vs. nonrural comparison

``` r

library(dplyr)

county_degrees <- get_degrees(geography = "county", years = 2024)

rural_definition <- ruraldefinitions::cbsa_2023 |> select(geoid, is_rural)

county_comparison <- county_degrees |>
  filter(variable == "count_degrees_total") |>
  left_join(rural_definition, by = "geoid") |>
  filter(!is.na(is_rural)) |>
  group_by(year, is_rural) |>
  summarize(total_degrees = sum(value, na.rm = TRUE), .groups = "drop")

print(county_comparison)
```

## Understanding agg_var

Variables that are rates or shares include an `agg_var` column — the
weight needed to aggregate correctly across counties. For graduation
rates it is the adjusted cohort; for degree shares it is total degrees
conferred, so `value * agg_var` recovers a raw count.

An unweighted mean gives a 40-student county the same weight as a
40,000-student one:

``` r

rates <- get_graduation_rates(geography = "county", years = 2023)

rates |>
  filter(variable == "grad_rate_150pct") |>
  summarize(
    weighted   = sum(value * agg_var, na.rm = TRUE) / sum(agg_var, na.rm = TRUE),
    unweighted = mean(value, na.rm = TRUE)
  )
```

## Counting conventions

The institution tables are unfiltered because the right filter depends
on the question. Three NCES conventions will inflate a naive sum:

- **`cipcode == "99.0000"`** is each institution’s grand total across
  programs, included alongside the per-program rows.
- **`major_num == 2`** is the second major of a double-majoring student.
- **Certificates are not degrees.** `ed_level` spans certificates
  through doctorates; the county variables count codes 3, 5, 7, 17, 18
  and 19 only.

The first two together inflate a 2024 national degree count from 4.14
million to 8.46 million. The county getters apply all three already, so
this matters only when aggregating the institution tables directly.

## Coverage caveats

[`get_ipeds_codebook()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/get_ipeds_codebook.md)
carries a `notes` field per variable recording vintage caveats. These
are the ones that most often change an answer.

**Graduation rates lag** the other surveys by about a year.

**Transfer-out reporting is effectively optional.** A county-year where
no institution reported a transfer-out row is omitted rather than
published as zero, so `transfer_out_rate` is absent for roughly a
quarter of the county-years that do have a graduation rate. A value of 0
is a reported zero, not missing data.

**Award level codes changed inside the covered period.** `ed_level` code
1 runs 2010–2019 and is replaced by codes 20 and 21 from 2020;
`award_level_category` code 1 is likewise replaced by 11 and 12. All are
sub-associate certificates and all are excluded from degree
aggregations, so county variables are unaffected, but aggregating
certificates from the institution tables requires using the right code
for the year.

**Completer variables are not additive across levels.** A student
earning a bachelor’s and a master’s in the same year is counted at both.

**Geography is the institution’s, not the student’s.** County assignment
comes from the institution’s address, so commuting and online enrollment
both appear as production in the campus county.

**Carnegie classification is the 2000 edition** and is `NA` for roughly
half of all institution-years: NCES codes institutions outside the
Carnegie universe as `-2`, which the ETL converts to `NA`.

## Where next

[`vignette("rural-higher-education", package = "cori.data.ipeds")`](https://ruralinnovation.github.io/cori.data.ipeds/articles/rural-higher-education.md)
compares rural and nonrural counties across all four measures, with
charts.

## Data sources

> The Center on Rural Innovation’s curation of U.S. Department of
> Education, National Center for Education Statistics, *Integrated
> Postsecondary Education Data System (IPEDS)*.
> <https://nces.ed.gov/ipeds/>
>
> The Center on Rural Innovation’s curation of U.S. Census Bureau,
> *Metropolitan and Micropolitan Statistical Areas (OMB delineations)*.
> <https://www.census.gov/programs-surveys/metro-micro.html>
>
> CIP-to-SOC crosswalk: NCES, *Classification of Instructional
> Programs*. <https://nces.ed.gov/ipeds/cipcode/resources.aspx>
