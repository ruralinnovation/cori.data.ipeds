# Session Log — cori.data.ipeds

## Status as of 2026-06-29

### Architecture overview (current)

The package has been fully refactored from a single-layer
dictionary-driven pipeline into a clean three-layer architecture. Legacy
processing files have been archived.

**Three-layer ETL**

    NCES CSV (download)
          ↓
    data_raw/           -- untouched NCES parquet; original uppercase col names;
                           original sentinel codes; only addition is `year` column
          ↓  reconcile_vintage()   (era-specific fixes: sentinel→NA, zero-pad, renames)
          ↓  apply_codebook_mapping()  (NCES uppercase → snake_case canonical names)
    data_institution/   -- one parquet per survey×year; canonical names; geo attached
          ↓  process_ipeds_county()   (tidy 6-col aggregations)
    data_county/        -- one parquet per year; 16 variables; tidy long format

**S3 layout**

    s3://cori.data.ipeds/
      data_raw/survey={survey}/year={year}/part-0.parquet
      data_institution/survey={survey}/year={year}/part-0.parquet
      data_county/year={year}/part-0.parquet

**Incremental by design**: each layer skips vintages already written.
Historic years are never reprocessed once written. Adding a new year =
run `write_ipeds_all(years = NEW_YEAR)`.

------------------------------------------------------------------------

### What was completed this session

**ETL infrastructure (all new files)**

| File | Purpose |
|----|----|
| `R/reconcile_vintage.R` | Era-specific fixes between raw and codebook rename |
| `R/write_raw_to_s3.R` | Layer 1: read NCES CSV untouched, write to raw parquet |
| `R/process_institution.R` | Layer 2: reconcile + rename + geo attach |
| `R/process_county.R` | Layer 3: tidy county aggregations |
| `R/write_ipeds_to_s3.R` | Orchestrator: runs all three layers |
| `inst/extdata/codebook.csv` | Opinionated codebook (47 variables, 10 cols) |

**Archived (no longer active)**

    archive/
      process_ipeds_ic.R
      process_ipeds_completions.R
      process_ipeds_gr.R
      write_ipeds_to_s3.R   (old version)
      get_ipeds_codebook.R

------------------------------------------------------------------------

### Key design decisions

**Codebook as source of truth**

`inst/extdata/codebook.csv` defines all 47 variables with: - `variable`
— canonical snake_case name used throughout the package - `nces_var` —
original NCES uppercase name in raw data (e.g. `COUNTYCD`) - `survey` —
which survey the variable belongs to - `level` — `"both"` for variables
shared across surveys (unitid, geoid) - `era_notes` — documents known
schema breaks across vintages - `alignment_notes` — joins/crosswalks to
other datasets

Critical: `unitid` and `geoid` have `level = "both"`, which causes
[`apply_codebook_mapping()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/apply_codebook_mapping.md)
to rename them in ALL surveys (not just IC). Without this, geo joins to
completions and grad_rates would silently fail.

**Era reconciliation layer**

[`reconcile_vintage()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/reconcile_vintage.md)
sits between raw parquet and codebook renaming. Era fixes by survey:

*IC*: - 2024+: `C00CARNEGIE` → `CARNEGIE` (NCES renamed column) - All:
sentinel codes (-1, -2, -3) → NA - All: UNITID zero-padded to 6 digits -
All: COUNTYCD zero-padded to 5 digits (after sentinel removal) - All:
geo columns added as NA if absent (guard for pre-2009 attempts)

*Completions*: - All: sentinel → NA, UNITID pad - All: race/demographic
columns added as NA if absent (schema evolution) - Warns if pre-2009
doctoral AWLEVEL codes (9/10/11) appear

*Grad rates*: - All: sentinel → NA, UNITID pad, race columns padded

**Grad rate GRTYPE structure (important)**

GRTYPE (mapped to `cohort_type`) uniquely identifies the row’s role: -
GRTYPE 1 = starting cohort (not used in county aggregation) - GRTYPE 2 =
adjusted cohort **denominator** - GRTYPE 3 = completers within 150% of
normal time **numerator** → `grad_rate_150pct` - GRTYPE 4 = transfer-out
students **numerator** → `transfer_out_rate` - GRTYPE ≥ 6 = other
sections (part-time, transfer-in, etc.) — excluded

County aggregation filters directly on GRTYPE values 2/3/4, not on
CHRTSTAT.

**County variables (16 total)**

*IC survey (7 counts)*: inst_count, public_inst_count,
nonprofit_inst_count, fouryear_inst_count, twoyear_inst_count,
hbcu_count, tribal_count

*Completions survey (7)*: count_degrees_total (raw count, agg_var=NA),
share_degrees_assoc/bach/masters/doctoral/men/women (proportions,
agg_var=total)

*Grad rates survey (2)*: grad_rate_150pct, transfer_out_rate
(proportions, agg_var=NA)

All county aggregations restricted to degree-granting institutions
(`is_degree_granting == 1`) with a valid `geoid`. Excluded sectors: 0,
99.

**Tracked degree levels**: AWLEVEL codes 2, 3 (associate’s), 5
(bachelor’s), 7 (master’s), 17, 18, 19 (doctoral). Excludes certificates
and undocumented codes. All four level shares use this same universe →
shares sum to exactly 1.

------------------------------------------------------------------------

### Validation (2023 data)

    County rows: 21,092
    Variables: 16 (all expected)

    Share level sum: min=1, median=1, max=1  ✓
    Sex share sum:   min=1, median=1, max=1  ✓
    Grad rate range: [0, 1]                  ✓

    Grafton County NH (33009) 2023:
      inst_count = 2 (Dartmouth + Plymouth State)
      count_degrees_total = 6,620
      share_degrees_bach = 0.665
      share_degrees_masters = 0.270
      share_degrees_doctoral = 0.065  ← Dartmouth doctoral present ✓
      share_degrees_assoc = 0          ← no community college ✓

------------------------------------------------------------------------

### Running the full pipeline

``` r

devtools::load_all()

# One year (new vintage)
write_ipeds_all(years = 2024, sync_to_s3 = TRUE)

# Full backfill 2010–2023 (skips already-written)
write_ipeds_all(years = 2010:2023, sync_to_s3 = TRUE)

# Layer-by-layer (useful for debugging)
write_ipeds_all(years = 2023, layers = "raw",         sync_to_s3 = FALSE)
write_ipeds_all(years = 2023, layers = "institution", sync_to_s3 = FALSE)
write_ipeds_all(years = 2023, layers = "county",      sync_to_s3 = FALSE)
```

------------------------------------------------------------------------

### File map (current)

    R/
      reconcile_vintage.R       -- era fixes: sentinel→NA, zero-pad, col renames
      write_raw_to_s3.R         -- Layer 1: NCES CSV → raw parquet (untouched)
      process_institution.R     -- Layer 2: reconcile + codebook rename + geo
      process_county.R          -- Layer 3: tidy county aggregations
      write_ipeds_to_s3.R       -- Orchestrator: write_ipeds_all()
      fetch_ipeds_dictionary.R  -- Fetch NCES dictionary xlsx (bootstrap once/vintage)
      read_ipeds_from_s3.R      -- Public read functions (DuckDB + S3)
      download_ipeds.R          -- ZIP download with skip-if-present guard
      utils_ipeds_read.R        -- CSV safe read, helpers
      utils_ipeds_dictionary.R  -- (legacy; kept for read_ipeds_from_s3 dependency)
      read_ipeds_ic_raw.R       -- (legacy thin wrapper)
      read_ipeds_completions_raw.R -- (legacy thin wrapper)
      read_ipeds_gr_raw.R       -- (legacy thin wrapper)
      globals.R                 -- IPEDS_START_YEAR, IPEDS_SURVEYS, globalVariables()

    inst/extdata/
      codebook.csv              -- 47-variable opinionated codebook (NEW)
      institutional_characteristics.csv  -- legacy IC dictionary (still used by read_ipeds_from_s3)
      completions.csv           -- legacy completions dictionary
      grad_rates.csv            -- legacy grad rates dictionary

    archive/
      process_ipeds_ic.R
      process_ipeds_completions.R
      process_ipeds_gr.R
      write_ipeds_to_s3.R
      get_ipeds_codebook.R

------------------------------------------------------------------------

### Immediate next steps

1.  **Run full backfill** —
    `write_ipeds_all(years = 2010:2024, sync_to_s3 = TRUE)` (2024 IC and
    completions will write; GR2024 will be skipped — grad rates lag one
    year)

2.  **Write vignette** — `vignettes/introduction.Rmd` Suggested
    structure:

    - What IPEDS is and what this package provides
    - Reading county data, filtering by variable/year/geography
    - Using `agg_var` to recover raw counts from shares
    - Reading institution-level data
    - Annual update workflow for maintainers

3.  **Clean up archive/** — if files in `archive/` remain unused after
    the backfill is confirmed, delete them permanently.

4.  **CIP-to-SOC crosswalk** — completions data is stored at the
    institution × CIP × award level grain in `data_institution` but CIP
    detail is discarded during county rollup. A CIP-to-SOC crosswalk
    would enable county-level variables like “share of degrees in STEM
    fields” or alignment between local degree production and employer
    demand. NCES publishes a CIP-to-SOC crosswalk; BLS O\*NET is an
    alternative source. This would add new variables to `data_county`
    and new rows to `codebook.csv`.

------------------------------------------------------------------------

### Known issues / things to watch

- **GR2024 returns 404**: Grad rates lag by an extra year. 2023 is the
  latest available. This is expected NCES behavior.

- **ed_level 21** appears in raw completions data. Not a documented NCES
  AWLEVEL code. Safely excluded by `TRACKED_DEGREE_LEVELS` filter.

- **Pre-2009 extension** — planned future work. `geoid` (NCES
  `COUNTYCD`) was added to IC in 2009; would need ZIP-to-county
  crosswalk for earlier years.
