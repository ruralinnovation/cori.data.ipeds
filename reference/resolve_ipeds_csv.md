# Resolve the correct CSV file path inside an extracted IPEDS ZIP

IPEDS ZIPs sometimes include both a revised file (`*_rv.csv`) and an
original (`*_a.csv`). The revised file is always preferred when present.
Candidate filenames come from `.raw_csv_candidates()`, which supplies
both the lowercase and uppercase spelling of the NCES table name; this
function tries each in turn.

## Usage

``` r
resolve_ipeds_csv(extract_dir, source_table_candidates)
```

## Arguments

- extract_dir:

  Character. Path to the extracted ZIP contents.

- source_table_candidates:

  Character vector. One or more candidate base filenames (without
  extension) to search for.

## Value

Character. Full path to the resolved CSV file.
