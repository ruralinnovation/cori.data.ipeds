# cori.data.ipeds — Refactor: Current State & Proposed State

**Package:** cori.data.ipeds
**Purpose:** Access NCES IPEDS data — institutional characteristics, degree
completions, and graduation rates — at institution and county level,
2010–present.

---

## Current State

### What the package exposes today

```
export(load_codebook)
export(read_ipeds_county_from_s3)
export(read_ipeds_institution_from_s3)
export(write_ipeds_all)
```

| Function | What it does | Consistent with family convention? |
|---|---|---|
| `read_ipeds_county_from_s3()` | Queries S3 via DuckDB, returns tidy county data | No — every other package hides this behind a `get_*()` wrapper (`get_population()`, `get_building_permits()`, `get_employment()`, `get_business_dynamics()`, `get_housing_units()`) |
| `read_ipeds_institution_from_s3()` | Queries S3, returns wide institution-level data | Same issue |
| `load_codebook()` | Returns variable documentation | Name doesn't match `get_<pkg>_codebook()` convention (`get_pep_codebook`, `get_bps_codebook`, `get_bds_codebook`, `get_hu_codebook`, `get_qcew_codebook`) |
| `write_ipeds_all()` | Runs the full raw→institution→county ETL pipeline and writes to S3 | **Exported to end users** — this is a maintainer-only orchestrator. No sibling package exports its write/pull functions (`write_pep_processed_to_s3`, `write_bps_to_s3` are internal-only) |

**Problems with the current state:**

1. No semantic getter — users must already know the low-level S3/DuckDB
   function names and exact argument names (this is what caused the
   `read_county_ipeds_from_s3` / `year=` mix-up).
2. `write_ipeds_all()` being public means any installer can accidentally
   trigger a full NCES download + S3 write.
3. `load_codebook()` breaks the naming convention used everywhere else,
   so it won't show up next to the data functions in tab-completion or docs.
4. Package root has accumulated non-standard clutter no sibling package
   carries: an `archive/` directory of superseded ETL scripts, a duplicate
   `LICENSE.md` next to `LICENSE`, a `SESSION_LOG.md` dev-session scratch
   file, and no `_pkgdown.yml` (every sibling has one).
5. `data-raw/` has two overlapping validation scripts
   (`validate_county_output.R`, `validate_etl.R`) and no `refresh_ipeds.R` /
   `README.md` maintainer entry point, unlike `cori.data.pep`'s
   `data-raw/refresh_pep.R` + `data-raw/README.md`.

---

## Proposed State

### Exported functions (after)

| Function | What it does | Change |
|---|---|---|
| `get_higher_ed()` *(name TBD)* | County-level tidy data — wraps `read_ipeds_county_from_s3()`, adds geography filter + result messaging | **New**, mirrors `get_population()` / `get_employment()` |
| `get_institutions()` *(name TBD)* | Institution-level wide data — wraps `read_ipeds_institution_from_s3()` | **New** |
| `get_ipeds_codebook()` | Renamed from `load_codebook()` | Rename, matches `get_<pkg>_codebook()` |

Everything else — `write_ipeds_all()`, `read_ipeds_*_from_s3()`,
`process_ipeds_*()`, `reconcile_*_vintage()`, `download_ipeds()` and the
rest of the ETL internals — becomes internal-only (still callable by
maintainers via `:::` or `devtools::load_all()`), matching how `pep`/`bps`
hide their `pull_*`/`write_*_to_s3`/`latest_*_vintage` internals.

### Structural cleanup (mechanical, low-risk)

| Item | Action |
|---|---|
| `archive/` (5 superseded scripts) | Delete — git history already preserves them (confirmed via `git log`) |
| `LICENSE.md` | Delete — keep `LICENSE` only, matching every sibling package |
| `SESSION_LOG.md` | Fold anything still relevant into this doc / `RELEASE_CALENDAR.md`, then delete |
| `_pkgdown.yml` | Add, modeled on `cori.data.pep`'s / `cori.data.bps`'s |
| `data-raw/validate_county_output.R` + `validate_etl.R` | Consolidate into one script |
| `data-raw/refresh_ipeds.R` + `data-raw/README.md` | Add, modeled on `cori.data.pep`'s maintainer refresh workflow |

**No changes to:** processing logic (`process_institution.R`,
`process_county.R`, `reconcile_vintage.R`), S3 layout, `globals.R`,
`inst/extdata/codebook.csv`.

---

## File Changes Summary

| File | Current | After |
|---|---|---|
| `R/get_ipeds.R` | Does not exist | **New** — `get_higher_ed()`, `get_institutions()` |
| `R/read_ipeds_from_s3.R` | `read_ipeds_county_from_s3()` / `read_ipeds_institution_from_s3()` exported | Marked internal |
| `R/process_institution.R` | `load_codebook()` exported | Renamed `get_ipeds_codebook()`, still exported |
| `R/write_ipeds_to_s3.R` | `write_ipeds_all()` exported | Marked internal |
| `NAMESPACE` | 4 exports | 3 exports: `get_higher_ed`, `get_institutions`, `get_ipeds_codebook` |
| `README.md` | Uses `read_ipeds_*_from_s3()` in Quick Start | Updated to new getters |

---

## What This Is Not

- Not a data change — same S3 layout, same variables, same vintages.
- Not a change to the ETL pipeline — `write_ipeds_all()` and everything
  downstream of it is untouched, just no longer exported.
- Since this package has no external installs yet (locally sourced only,
  not yet pushed to GitHub as a dependency), **no deprecation wrappers are
  proposed** — unlike `cori.data.pep`'s `read_pep_from_s3()`, there's no
  installed base to break, so old names can just be removed outright rather
  than kept as deprecated aliases. Open to doing it the cautious way instead
  if you'd rather.

## Open Questions for You

1. **Naming the county-level getter.** Candidates: `get_higher_ed()`,
   `get_ipeds()`, `get_college_outcomes()`. It returns the unified tidy
   table spanning all three surveys (institution counts, completion shares,
   graduation rates).
2. **Naming the institution-level getter.** Candidates: `get_institutions()`,
   `get_ipeds_institutions()`. Returns wide-format data for one survey at a
   time (institution-level grain).
3. **Deprecation wrappers or clean break?** Given no known external callers
   yet, proposing a clean break (delete old names) rather than pep's
   deprecated-wrapper approach — confirm that's fine.
4. **`agg_var` column** — keep as-is (needed to recover raw counts for
   `share_degrees_*` and cohort sizes for `grad_rate_*`), unlike pep which
   dropped it. Confirming this stays.

## Future Work: Per-Year Vintage Tracking

Not part of this refactor — logged here so the design isn't lost.

**Problem.** `RELEASE_CALENDAR.md` already documents that NCES releases each
reference year as **provisional** first, then republishes it as **final**
(revised) roughly a year later. QCEW/PEP/BPS handle this exact situation
with a vintage mechanism (`vintage = "latest"` vs. a pinned label); `ipeds`
has no equivalent — each year's data is currently written once and can be
silently superseded, so a query run before vs. after a revision can return
different numbers for the same `years` argument with no way to know which
version you got.

**Why it's not a straight copy of qcew's pattern.** QCEW's vintaging
resnapshots the *entire* dataset (all years) into a new versioned folder on
every run. `ipeds`'s pipeline is deliberately incremental — already-written
years are skipped, only new ones get processed — so a whole-dataset
resnapshot would undo that. The better fit is a **per-year** vintage state
(`provisional` / `final`) rather than one dataset-wide label, since only the
most recent year or two is ever actually revised; everything older is
already final and stable.

**Proposed shape.**
- Each year's data has at most two immutable states: `provisional` (first
  release) and `final` (NCES's revision). Once written, neither is ever
  overwritten — `final` is added alongside `provisional`, not in place of it.
- `get_ipeds_county()` / `get_ipeds_institution()` gain a `vintage` argument:
  `"latest"` (default — final if it exists for a given year, else
  provisional; matches today's de facto behavior, just non-destructively),
  `"final"` (only years NCES has finalized), or `"provisional"` (always the
  first release per year, even after superseded — the actual reproducibility
  guarantee).
- Open question: the pipeline can't reliably infer provisional vs. final
  from the NCES file itself at write time. Simplest answer is the maintainer
  passes it explicitly when running the refresh, driven by the release
  status already tracked by hand in `RELEASE_CALENDAR.md`.

**Effort estimate:** roughly a day of focused work — the design is the
hard part (sketched above), the code changes are mechanical, and there's a
one-time backfill needed for data already written before this exists.

## Future Work: CIP-Level Completions & SOC Crosswalk

Not part of this refactor — logged here so the design isn't lost.

**Problem.** Completions data is already stored at institution × CIP × award
level grain in `data_institution`, but CIP (field of study) detail is
discarded during today's county rollup — `get_ipeds_county()` only tracks
completions by degree level (assoc/bach/masters/doctoral) and sex, not by
field. There's no way to answer "what fields are degrees being produced in"
or "how does local degree production align with local employer demand"
at the county level.

**Crosswalk source (confirmed).** NCES/IES publishes a CIP-to-SOC crosswalk
directly — no need to reach for O*NET's version, which was my first
(incorrect) suggestion. Available at
https://nces.ed.gov/ipeds/cipcode/resources.aspx?y=55:
`CIP2020_SOC2018_Crosswalk.xlsx` (~419 KB), matching the CIP2020 vintage
IPEDS completions already uses, so no cross-vintage CIP translation is
needed. A "Guidelines for Using the CIP to SOC Crosswalk" PDF is on the same
page.

**Proposed shape.**
- Extend the county rollup (or add a parallel output) that preserves CIP
  code instead of collapsing it — e.g. degree counts by county × year × CIP
  (2-digit family, or more granular), independent of the existing 16-variable
  county table.
- Bundle the NCES crosswalk into the package (`inst/extdata/`, same pattern
  as `codebook.csv`) and join it to produce county × year × SOC-aligned
  degree production.
- New public getter — naming and exact grain TBD when this gets picked up.

**Open question.** The crosswalk is one-to-many (one CIP program can map to
multiple SOC occupations). Needs a decision: split each CIP's degree count
proportionally across its mapped SOC codes, or report all mapped SOCs per
CIP without splitting (leaving weighting to the consumer)? The "Guidelines"
PDF on the NCES page may already have a recommended approach — worth reading
before deciding.

**Effort estimate:** not yet scoped in detail — depends on the answer to
the one-to-many question above, which affects the shape of the output table.
