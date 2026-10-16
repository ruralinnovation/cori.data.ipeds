# Reconcile a raw completions vintage data frame

Applies all known era-specific fixes to a raw completions data frame
loaded from `data_raw`.

## Usage

``` r
reconcile_completions_vintage(df, year)
```

## Arguments

- df:

  Data frame. Raw completions data loaded from `data_raw`.

- year:

  Integer. Vintage year.

## Value

Data frame with reconciled column names and values.

## Details

Known era fixes applied:

- All years: IPEDS sentinel codes converted to NA

- All years: `UNITID` zero-padded to 6 digits

- All years: `CIPCODE` restored to the canonical zero-padded `"xx.xxxx"`
  string

- 2010+: warns if pre-2008 doctoral AWLEVEL codes (9/10/11) are found
  (should not appear for years \>= 2010)
