# Apply codebook renaming to a reconciled data frame

Renames columns from their NCES uppercase names to canonical snake_case
names as defined in the codebook. Columns not in the codebook are left
unchanged (they remain available in the output but are not renamed).

## Usage

``` r
apply_codebook_mapping(df, survey, codebook)
```

## Arguments

- df:

  Data frame. Reconciled raw data (output of
  [`reconcile_vintage()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/reconcile_vintage.md)).

- survey:

  Character. Survey name used to filter the codebook.

- codebook:

  Data frame. Output of
  [`get_ipeds_codebook()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/get_ipeds_codebook.md);
  the `raw_variable` column supplies the NCES source name.

## Value

Data frame with codebook columns renamed to canonical names.
