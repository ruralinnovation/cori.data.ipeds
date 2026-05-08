# Session Log — cori.data.ipeds

## Status as of 2026-05-07

### What is complete

The full package is built and passing `devtools::check()` with 0 errors, 0 warnings, 0 notes.

**Package structure**
- `DESCRIPTION` — MIT license, Imports: DBI, duckdb, stringr, utils
- `NAMESPACE` — 3 exported functions only
- `R/` — 13 source files
- `inst/extdata/` — 3 data dictionary CSVs (IC, completions, grad rates), 2010--2024
- `man/` — generated Rd files
- `vignettes/introduction.Rmd` — stub, not yet written
- `data-raw/build_dictionaries.R` — documents dictionary origin
- `data-raw/validate_etl.R` — post-ETL validation script (new this session)
- `RELEASE_CALENDAR.md` — NCES release dates 2021--2025
- `LICENSE` / `LICENSE.md` — MIT

**Public API (3 exported functions)**
- `read_ipeds_county_from_s3()` — 6-column tidy, all surveys combined
- `read_ipeds_institution_from_s3()` — wide format, one survey at a time
- `get_ipeds_codebook()` — variable definitions for all 16 county variables

**Internal pipeline**
- Download, unzip, resolve CSV (prefers `_rv` revised files)
- Dictionary-driven column rename via `inst/extdata/*.csv`
- Negative IPEDS sentinel codes (-1, -2, -3) converted to NA before zero-padding
- UTF-8 sanitization via `iconv()` before DuckDB parquet write
- Manifest-driven incremental ETL (`_MANIFEST.csv` on S3)
- Year-partitioned S3 layout: `data_processed/year=YYYY/{dataset}/part-0.parquet`

---

### County variable design decisions (important context)

**Degree-granting filter**: ALL county aggregations are restricted to
`degree_granting_status_code == 1`. This filter is applied in:
- `.ic_county_base()` — IC institution counts
- `.ic_unitid_county_lookup()` — the bridge that gates completions and grad rates

Non-degree-granting institutions (cosmetology schools, professional development
orgs, etc.) appear in the wide institution tables but are excluded from county
output. This was validated against Grafton County NH (33009) where Upper Valley
Educators Institute (sector 2, 4-yr) and New England School of Hair Design
(sector 9, <2yr) are correctly excluded from county aggregations.

**Completions county variables — shares, not counts**

The county completions output uses shares with `count_degrees_total` as the
anchor. All four level shares sum to exactly 1 by construction.

| Variable | Value | agg_var |
|---|---|---|
| `count_degrees_total` | raw count of tracked degrees | NA |
| `share_degrees_assoc` | assoc / total | total |
| `share_degrees_bach` | bach / total | total |
| `share_degrees_masters` | masters / total | total |
| `share_degrees_doctoral` | doctoral / total | total |
| `share_degrees_men` | men / total | total |
| `share_degrees_women` | women / total | total |

Raw count is recoverable as `value * agg_var`.

**TRACKED_DEGREE_LEVELS**: IPEDS AWLEVEL codes 2, 3, 5, 7, 17, 18, 19.
Excludes certificates (1, 4, 6, 8) and the undocumented code 21 that appears
in some institution records. The denominator (`count_degrees_total`) and all
share numerators use this same set, so shares sum to 1.

**DOCTORAL_LEVELS corrected**: Was `c(9, 10, 11)` (pre-2009 codes).
Corrected to `c(17, 18, 19)` (post-2009 IPEDS revision). This was discovered
by finding that Dartmouth's doctoral completions (codes 17 and 18 in the raw
data) were not appearing in Grafton County. The 2009 revision split doctoral
from "first-professional" into three categories with new codes.

**`degree_granting_count` removed**: Was redundant once the degree-granting
filter was applied — `inst_count` equals it by definition. Dropped from county
output and codebook.

---

### ETL run in progress

Full production write: `write_ipeds_processed_to_s3(years = 2010:2024)` was
running as of session end, at approximately year 2017.

**2024 dictionary entries**: NCES released 2024 data September 2025.
Dictionary rows for 2024 were added to all three CSVs this session by
copying 2023 rows with year/filename substitution:
- IC: `hd2024`, `HD2024.zip`
- Completions: `c2024_a`, `C2024_A.zip`
- Grad rates: `gr2024`, `GR2024.zip`

---

### Immediate next steps (in order)

1. **Let the ETL finish** — resume `write_ipeds_processed_to_s3()` from where
   it left off (manifest will skip already-written years automatically):
   ```r
   devtools::load_all()
   write_ipeds_processed_to_s3(
     years       = 2010:2024,
     staging_dir = "data/ipeds",
     s3_bucket   = "cori.data.ipeds",
     overwrite   = FALSE,
     sync_to_s3  = TRUE
   )
   ```

2. **Run validation** after ETL completes:
   ```r
   source("data-raw/validate_etl.R")
   ```
   Key things to confirm:
   - All 4 datasets written for all years 2010--2024
   - Degree shares sum to 1 for all county-years
   - No bad geoids
   - Grafton County (33009) present in all years with sensible values
   - Dartmouth doctoral completions now showing in `share_degrees_doctoral`

3. **Commit everything** — all R files, dictionaries, README, RELEASE_CALENDAR

4. **Write vignette** (`vignettes/introduction.Rmd`) — narrative not yet started.
   Suggested structure:
   - What IPEDS is and what this package provides
   - Reading county data, filtering by variable/year/geography
   - Using `agg_var` to recover raw counts from shares
   - Reading institution-level data, joining to county
   - Using `get_ipeds_codebook()`
   - Annual update workflow for maintainers

5. **Final `devtools::check()`** with vignettes enabled (requires Pandoc)

---

### Known issues / things to watch

- **ed_level 21** appears in raw completions data for Plymouth State and
  hair school in 2022. Not a documented NCES AWLEVEL code. Safely excluded
  by `TRACKED_DEGREE_LEVELS` filter but worth monitoring across all years.

- **Vignette requires Pandoc** — `devtools::check()` currently run with
  `vignettes = FALSE` because Pandoc is not available in the check environment.
  Will need to resolve before CRAN-style submission.

- **Pre-2009 extension** — planned future work. HUD ZIP-to-county crosswalk
  is the preferred approach. IPEDS coding changes in 2009 (county FIPS added
  to IC, doctoral award level codes changed) need to be handled carefully.

- **ed_level 21 in grad_rates** — `GR_PRIMARY_COHORT = 1L` and
  `GR_ADJUSTED_COHORT = 12L` / `GR_COMPLETERS_150PCT = 13L` should be
  verified against the 2024 grad rates data dictionary when that year
  is processed.

---

### File map

```
R/
  utils_ipeds_dictionary.R   -- dictionary parsing, manifest, unprocessed check
  utils_ipeds_read.R         -- core read engine, CSV safe read, zero-padding
  download_ipeds.R           -- ZIP download with skip-if-present guard
  read_ipeds_ic_raw.R        -- thin wrapper: IC survey
  read_ipeds_completions_raw.R -- thin wrapper: completions survey
  read_ipeds_gr_raw.R        -- thin wrapper: grad rates survey
  process_ipeds_ic.R         -- institution + county pull_* functions (IC)
  process_ipeds_completions.R -- institution + county pull_* functions (completions)
  process_ipeds_gr.R         -- institution + county pull_* functions (grad rates)
  write_ipeds_to_s3.R        -- manifest-driven ETL orchestrator
  read_ipeds_from_s3.R       -- public read functions (DuckDB + S3)
  get_ipeds_codebook.R       -- exported codebook data frame
  globals.R                  -- globalVariables() declarations

inst/extdata/
  institutional_characteristics.csv  -- IC dictionary 2010--2024
  completions.csv                    -- completions dictionary 2010--2024
  grad_rates.csv                     -- grad rates dictionary 2010--2024

data-raw/
  build_dictionaries.R   -- documents how dictionaries were built
  validate_etl.R         -- post-ETL QA script (9 checks)
```
