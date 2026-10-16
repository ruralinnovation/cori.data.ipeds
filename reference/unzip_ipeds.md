# Unzip a downloaded IPEDS ZIP into its staging directory

Extracts the ZIP into `staging_dir/{survey}/{year}/extracted/`. Skips
extraction if the directory is non-empty (guards against re-extracting
after a clean download). Deletes and re-creates the extraction directory
if it exists but is empty (indicates a prior failed extraction).

## Usage

``` r
unzip_ipeds(survey, year, staging_dir = "data/ipeds")
```

## Arguments

- survey:

  Character.

- year:

  Integer.

- staging_dir:

  Character. Default: `"data/ipeds"`.

## Value

Invisibly returns the path to the extraction directory.
