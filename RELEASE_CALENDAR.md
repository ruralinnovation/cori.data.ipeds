# Release Calendar -- cori.data.ipeds

## Source Information

| Field | Detail |
|---|---|
| **Full name** | Integrated Postsecondary Education Data System (IPEDS) |
| **Producer** | National Center for Education Statistics (NCES), U.S. Dept. of Education |
| **Program page** | https://nces.ed.gov/ipeds/ |
| **Release schedule page** | https://nces.ed.gov/ipeds/survey-components/data-release-schedule |
| **Coverage** | Institution, county (aggregated) · 2010--present · Annual |
| **Surveys covered** | Institutional Characteristics (IC), Completions (C), Graduation Rates (GR) |

## NCES Collection Periods

IPEDS surveys are grouped into three reporting periods. The three surveys
covered by this package fall in the first two periods:

| Period | Surveys in this package | Typical release |
|---|---|---|
| **Fall** | IC, Completions (C) | ~August--September following the reference year |
| **Winter** | Graduation Rates (GR) | ~September--December following the reference year |

NCES releases **provisional** data first; **final** (revised) data follows
approximately one year later. Our pipeline picks up final data where available
and falls back to provisional for the most recent vintage.

## Recent NCES Release Dates

| Collection year | Survey period | Release date | Status |
|---|---|---|---|
| 2024--25 | Fall (IC, Completions) | September 23, 2025 | Provisional |
| 2024--25 | Winter (Grad Rates) | December 9, 2025 | Provisional |
| 2023--24 | Fall (IC, Completions) | September 23, 2025 | Final |
| 2023--24 | Winter (Grad Rates) | December 9, 2025 | Final |
| 2022--23 | Fall (IC, Completions) | August 1, 2024 | Final |
| 2022--23 | Winter (Grad Rates) | September 27, 2024 | Final |
| 2021--22 | Fall (IC, Completions) | September 21, 2023 | Final |
| 2021--22 | Winter (Grad Rates) | November 7, 2023 | Final |

*"Collection year" maps to the `year` column in package output as the second
year of the academic year (e.g., 2022--23 collection = `year = 2023`).*

## Processed Years Log

Tracks which reference years have been written to S3. Mirrors the
`_MANIFEST.csv` file stored at `s3://cori.data.ipeds/data_processed/`.

| Year | Datasets written | Processed at | Notes |
|---|---|---|---|
| -- | -- | -- | -- |

## Next Capture

| Field | Detail |
|---|---|
| **Next expected release** | ~August--September 2026 (IC and Completions final for 2024--25; provisional for 2025--26) |
| **Grad Rates** | ~September--December 2026 (final for 2024--25; provisional for 2025--26) |
| **Responsible** | TBD |
