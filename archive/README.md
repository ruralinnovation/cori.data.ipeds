# Archive

Files here are no longer part of the active pipeline. They are kept temporarily
for reference in case anything was missed during the refactor.

**If a file in this folder has gone unused for one full release cycle, delete it.**
There is no reason to carry dead code indefinitely.

## Contents

| File | Why archived |
|---|---|
| `process_ipeds_ic.R` | Replaced by `R/process_institution.R` + `R/process_county.R` |
| `process_ipeds_completions.R` | Replaced by `R/process_institution.R` + `R/process_county.R` |
| `process_ipeds_gr.R` | Replaced by `R/process_institution.R` + `R/process_county.R` |
| `write_ipeds_to_s3.R` | Replaced by new `R/write_ipeds_to_s3.R` (three-layer orchestrator) |
| `get_ipeds_codebook.R` | Replaced by `inst/extdata/codebook.csv` |
| `fetch_ipeds_dictionary.R` | Built but never wired into the pipeline; the codebook.csv handles renaming |
| `utils_ipeds_read.R` | Only served the legacy thin wrappers below |
| `utils_ipeds_dictionary.R` | Only served `utils_ipeds_read.R` |
| `read_ipeds_ic_raw.R` | Legacy thin wrapper; superseded by `write_raw_to_s3.R` |
| `read_ipeds_completions_raw.R` | Legacy thin wrapper; superseded by `write_raw_to_s3.R` |
| `read_ipeds_gr_raw.R` | Legacy thin wrapper; superseded by `write_raw_to_s3.R` |
