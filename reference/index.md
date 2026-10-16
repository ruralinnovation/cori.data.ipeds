# Package index

## IPEDS

- [`get_institutions()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/get_institutions.md)
  : Get higher education institutions
- [`get_degrees()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/get_degrees.md)
  : Get degrees conferred
- [`get_completers()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/get_completers.md)
  : Get students completing degrees
- [`get_graduation_rates()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/get_graduation_rates.md)
  : Get graduation and transfer-out rates
- [`get_ipeds()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/get_ipeds.md)
  : Get IPEDS data across surveys

## Utilities

- [`get_ipeds_codebook()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/get_ipeds_codebook.md)
  : Get the cori.data.ipeds variable codebook
- [`get_cip_soc_crosswalk()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/get_cip_soc_crosswalk.md)
  : Get the NCES CIP-to-SOC crosswalk

## Internal

Functions for data processing and maintenance

- [`.ipeds_county_query()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/dot-ipeds_county_query.md)
  : Query county-level IPEDS data from S3
- [`.ipeds_institution_query()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/dot-ipeds_institution_query.md)
  : Query institution-level IPEDS data from S3
- [`write_ipeds_all()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/write_ipeds_all.md)
  : Run the full IPEDS ETL pipeline for a range of years
- [`write_ipeds_institution_to_s3()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/write_ipeds_institution_to_s3.md)
  : Write processed institution-level data for one year to S3
- [`write_ipeds_county_to_s3()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/write_ipeds_county_to_s3.md)
  : Write processed county-level data for one year to S3
- [`download_ipeds()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/download_ipeds.md)
  : Download a single IPEDS ZIP file from NCES
- [`unzip_ipeds()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/unzip_ipeds.md)
  : Unzip a downloaded IPEDS ZIP into its staging directory
- [`resolve_ipeds_csv()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/resolve_ipeds_csv.md)
  : Resolve the correct CSV file path inside an extracted IPEDS ZIP
- [`read_ipeds_raw()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/read_ipeds_raw.md)
  : Read a raw IPEDS CSV for one survey vintage
- [`write_ipeds_raw_to_s3()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/write_ipeds_raw_to_s3.md)
  : Write raw IPEDS data for one survey vintage to S3
- [`write_ipeds_raw_batch()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/write_ipeds_raw_batch.md)
  : Write raw IPEDS data for multiple surveys and years to S3
- [`process_ipeds_institution()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/process_ipeds_institution.md)
  : Process one IPEDS survey vintage to institution level
- [`process_ipeds_institution_all()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/process_ipeds_institution_all.md)
  : Process all three surveys for a single year
- [`process_ipeds_county()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/process_ipeds_county.md)
  : Derive county-level data from institution-level data frames
- [`apply_codebook_mapping()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/apply_codebook_mapping.md)
  : Apply codebook renaming to a reconciled data frame
- [`reconcile_vintage()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/reconcile_vintage.md)
  : Reconcile any survey vintage
- [`reconcile_ic_vintage()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/reconcile_ic_vintage.md)
  : Reconcile a raw IC/HD vintage data frame
- [`reconcile_completions_vintage()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/reconcile_completions_vintage.md)
  : Reconcile a raw completions vintage data frame
- [`reconcile_completers_vintage()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/reconcile_completers_vintage.md)
  : Reconcile a raw completers vintage data frame
- [`reconcile_gr_vintage()`](https://ruralinnovation.github.io/cori.data.ipeds/reference/reconcile_gr_vintage.md)
  : Reconcile a raw graduation rates vintage data frame
