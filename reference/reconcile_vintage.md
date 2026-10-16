# Reconcile any survey vintage

Dispatches to the appropriate per-survey reconciler.

## Usage

``` r
reconcile_vintage(survey, df, year)
```

## Arguments

- survey:

  Character. One of `"institutional_characteristics"`, `"completions"`,
  `"completers"`, `"grad_rates"`.

- df:

  Data frame. Raw data for the vintage.

- year:

  Integer. Vintage year.

## Value

Reconciled data frame.
