# Reconcile a raw IC/HD vintage data frame

Applies all known era-specific fixes to a raw IC data frame loaded from
`data_raw`. Returns a data frame with consistent column names and clean
values ready for codebook renaming in `process_institution.R`.

## Usage

``` r
reconcile_ic_vintage(df, year)
```

## Arguments

- df:

  Data frame. Raw IC data loaded from `data_raw` parquet.

- year:

  Integer. Vintage year.

## Value

Data frame with reconciled column names and values.

## Details

Known era fixes applied:

- 2024+: `C00CARNEGIE` normalised to `CARNEGIE`

- All years: IPEDS sentinel codes (-1, -2, -3) converted to NA

- All years: `UNITID` zero-padded to 6 digits

- All years: `COUNTYCD` zero-padded to 5 digits (after sentinel removal)

- All years: geo columns (`COUNTYCD`, `COUNTYNM`, `LATITUDE`,
  `LONGITUD`) added as NA if absent
