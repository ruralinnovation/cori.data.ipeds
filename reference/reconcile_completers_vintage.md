# Reconcile a raw completers vintage data frame

Applies all known era-specific fixes to a raw completers data frame
(NCES `C{year}_C`) loaded from `data_raw`.

## Usage

``` r
reconcile_completers_vintage(df, year)
```

## Arguments

- df:

  Data frame. Raw completers data loaded from `data_raw`.

- year:

  Integer. Vintage year.

## Value

Data frame with reconciled column names and values.

## Details

Known era fixes applied:

- All years: IPEDS sentinel codes converted to NA

- All years: `UNITID` zero-padded to 6 digits

`AWLEVELC` is left as NCES reports it. Its degree-level codes (3, 5, 7,
9) are stable across every published vintage, but its certificate-level
codes are not: code 1 appears 2012-2019 and is replaced by codes 11 and
12 from 2020. County aggregations therefore use the degree-level codes
only.
