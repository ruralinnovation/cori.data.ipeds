# Get the NCES CIP-to-SOC crosswalk

Returns the National Center for Education Statistics crosswalk mapping
Classification of Instructional Programs (CIP) codes to Standard
Occupational Classification (SOC) codes. Joining it to the `cipcode`
column of
[`get_degrees()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/get_degrees.md)'s
institution-level output turns degree production into occupational
supply, which is the usual bridge from education data to workforce and
economic development analysis.

## Usage

``` r
get_cip_soc_crosswalk(vintage = c("2020", "2010"))
```

## Source

NCES CIP resources: <https://nces.ed.gov/ipeds/cipcode/resources.aspx>

## Arguments

- vintage:

  Character. Crosswalk vintage: `"2020"` (CIP 2020 to SOC 2018, the
  default) or `"2010"` (CIP 2010 to SOC 2010).

## Value

A data frame with columns `cip_code`, `cip_title`, `soc_code`,
`soc_title`, `cip_vintage`, `soc_vintage`. The vintage columns are
integers, so crosswalks can be row-bound and stay self-describing.

## Choosing a vintage

NCES revises the CIP taxonomy roughly every ten years and the crosswalk
follows the SOC revision cycle, so the correct vintage depends on the
completions year you are joining to:

- `vintage = "2020"` – CIP 2020 to SOC 2018. Use for completions years
  2020 and later, which NCES reports on the CIP 2020 taxonomy.

- `vintage = "2010"` – CIP 2010 to SOC 2010. Use for completions years
  2010 through 2019.

Some programs were recoded between taxonomies, so a CIP code can mean
different things either side of 2020. Pairing a completions year with
the wrong crosswalk vintage will mostly appear to work – the join
succeeds and returns plausible occupations – which makes it worth
getting right deliberately rather than by default.

## Joining

The relation is many-to-many: one CIP maps to several SOC codes and vice
versa. Joining completions to it therefore multiplies rows, and summing
`count_total_students` afterwards will overcount unless you first decide
how to apportion a program's graduates across its occupations, or you
restrict to a specific SOC set and take distinct CIP codes.

`cip_code` is formatted to match the `cipcode` column of the completions
table exactly – a zero-padded `"xx.xxxx"` character string, so the 01-09
families join correctly.

CIP codes with no occupational match are retained with `soc_code = NA`
rather than dropped, so a left join never silently loses a program.
NCES's `"99-9999"` no-match sentinel is converted to `NA`.

## See also

[`get_degrees()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/get_degrees.md),
[`get_ipeds_codebook()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/get_ipeds_codebook.md)

## Examples

``` r
xw <- get_cip_soc_crosswalk()
head(xw)
#>   cip_code                                      cip_title soc_code
#> 1  01.0000                          Agriculture, General.  19-1011
#> 2  01.0000                          Agriculture, General.  19-1012
#> 3  01.0000                          Agriculture, General.  19-1013
#> 4  01.0000                          Agriculture, General.  19-4012
#> 5  01.0000                          Agriculture, General.  25-1041
#> 6  01.0101 Agricultural Business and Management, General.  11-9013
#>                                            soc_title cip_vintage soc_vintage
#> 1                                  Animal Scientists        2020        2018
#> 2                  Food Scientists and Technologists        2020        2018
#> 3                          Soil and Plant Scientists        2020        2018
#> 4                           Agricultural Technicians        2020        2018
#> 5      Agricultural Sciences Teachers, Postsecondary        2020        2018
#> 6 Farmers, Ranchers, and Other Agricultural Managers        2020        2018

# Which occupations does a computer science degree map to?
xw[xw$cip_code == "11.0701", c("soc_code", "soc_title")]
#>     soc_code                                       soc_title
#> 657  11-3021       Computer and Information Systems Managers
#> 658  15-1212                   Information Security Analysts
#> 659  15-1221    Computer and Information Research Scientists
#> 660  15-1231            Computer Network Support Specialists
#> 661  15-1243                             Database Architects
#> 662  15-1251                            Computer Programmers
#> 663  15-1252                             Software Developers
#> 664  15-1253 Software Quality Assurance Analysts and Testers
#> 665  15-1254                                  Web Developers
#> 666  15-1255             Web and Digital Interface Designers
#> 667  15-1299                 Computer Occupations, All Other
#> 668  15-2051                                 Data Scientists
#> 669  25-1021        Computer Science Teachers, Postsecondary

if (FALSE) { # \dontrun{
# Degrees awarded in programs feeding software development occupations
comp <- get_degrees(geography = "institution", years = 2022)
soc  <- c("15-1251", "15-1252", "15-1253", "15-1254")
cips <- unique(xw$cip_code[xw$soc_code %in% soc])
sum(comp$count_total_students[
  comp$cip_code %in% cips &
  comp$major_num == 1 &
  comp$cipcode != "99.0000"
])
} # }
```
