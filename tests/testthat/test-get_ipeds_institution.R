# Argument validation only here -- no network required. See
# test-integration-s3.R for the real S3 round-trip.

test_that("get_ipeds_institution() requires survey", {
  expect_error(get_ipeds_institution(), "survey")
})

test_that("get_ipeds_institution() rejects an unknown survey", {
  expect_error(
    get_ipeds_institution("not_a_real_survey"),
    "should be one of"
  )
})

test_that("get_ipeds_institution() rejects the old ic shorthand name", {
  # "ic" was valid in the legacy pipeline (archive/) but the public API only
  # ever accepted the full survey names -- guards against reintroducing the
  # shorthand by mistake. Not an ambiguous-prefix case (see below), since
  # nothing in the choices starts with "ic".
  expect_error(get_ipeds_institution("ic"), "should be one of")
})

test_that("match.arg()'s partial matching resolves unambiguous prefixes", {
  # survey is passed through match.arg(), which partial-matches by default.
  # "gr" unambiguously prefixes "grad_rates" (the only choice starting with
  # "gr"), so it resolves rather than erroring -- documented here so it
  # isn't mistaken for a bug later.
  skip_if_no_s3()
  df <- get_ipeds_institution("gr", years = 2018)
  expect_gt(nrow(df), 0)
})
