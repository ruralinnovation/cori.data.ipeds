# Local-only: reads inst/extdata/codebook.csv, no network required.

test_that("get_ipeds_codebook() returns the expected shape", {
  cb <- get_ipeds_codebook()

  expect_s3_class(cb, "data.frame")
  expect_gt(nrow(cb), 0)
  expect_true(all(c(
    "variable", "label", "description", "nces_var", "nces_title",
    "survey", "level", "unit"
  ) %in% names(cb)))
})

test_that("get_ipeds_codebook() variable names are unique", {
  cb <- get_ipeds_codebook()
  expect_equal(anyDuplicated(cb$variable), 0)
})

test_that("get_ipeds_codebook() survey and level are constrained to known values", {
  cb <- get_ipeds_codebook()

  expect_true(all(cb$survey %in% c(
    "institutional_characteristics", "completions", "grad_rates"
  )))
  expect_true(all(cb$level %in% c("institution", "county", "both")))
})

test_that("get_ipeds_codebook()'s county-level rows match the county output contract", {
  # This is the same 16-variable set get_ipeds_county() promises in its
  # county-level output (see data-raw/validate_etl.R's EXPECTED_VARS) --
  # kept here too so codebook drift fails fast in `devtools::test()`,
  # not just in the S3-dependent validation script.
  cb          <- get_ipeds_codebook()
  county_vars <- cb$variable[cb$level == "county"]

  expected <- c(
    "inst_count", "public_inst_count", "nonprofit_inst_count",
    "fouryear_inst_count", "twoyear_inst_count", "hbcu_count", "tribal_count",
    "count_degrees_total",
    "share_degrees_assoc", "share_degrees_bach",
    "share_degrees_masters", "share_degrees_doctoral",
    "share_degrees_men", "share_degrees_women",
    "grad_rate_150pct", "transfer_out_rate"
  )

  expect_setequal(county_vars, expected)
})
