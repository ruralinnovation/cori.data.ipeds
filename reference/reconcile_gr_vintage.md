# Reconcile a raw graduation rates vintage data frame

Applies all known era-specific fixes to a raw grad rates data frame
loaded from `data_raw`.

## Usage

``` r
reconcile_gr_vintage(df, year)
```

## Arguments

- df:

  Data frame. Raw grad rates data loaded from `data_raw`.

- year:

  Integer. Vintage year.

## Value

Data frame with reconciled column names and values.

## Details

Known era fixes applied:

- All years: IPEDS sentinel codes converted to NA

- All years: `UNITID` zero-padded to 6 digits
