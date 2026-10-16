# Download a single IPEDS ZIP file from NCES

Downloads the ZIP for a given survey vintage. Skips the download if the
file already exists locally.

## Usage

``` r
download_ipeds(survey, year, download_url, staging_dir = "data/ipeds")
```

## Arguments

- survey:

  Character. One of `"institutional_characteristics"`, `"completions"`,
  `"grad_rates"`.

- year:

  Integer. Survey year.

- download_url:

  Character. Full URL to the NCES ZIP file, as built by
  `.raw_download_url()` from the survey and year.

- staging_dir:

  Character. Root staging directory. Default: `"data/ipeds"`.

## Value

Invisibly returns the local path to the downloaded ZIP.
