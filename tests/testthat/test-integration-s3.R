# Integration tests against real S3 data. Skipped automatically when offline
# or when no AWS/vended credentials are available (see helper-s3.R) -- these
# confirm the public read path actually works end to end, not just that the
# query-building logic is correct.

test_that("get_ipeds() returns the documented 6-column shape", {
  skip_if_no_s3()

  df <- get_ipeds(geoids = "33009", years = 2018)

  expect_s3_class(df, "data.frame")
  expect_setequal(
    names(df),
    c("geoid", "year", "variable", "value", "agg_var", "survey")
  )
  expect_true(is.character(df$geoid))
  expect_true(is.integer(df$year))
  expect_true(all(nchar(df$geoid) == 5))
})

test_that("get_ipeds() Grafton County NH 2018 spot check", {
  skip_if_no_s3()

  df <- get_ipeds(geoids = "33009", years = 2018)

  # Dartmouth + Plymouth State
  expect_equal(df$value[df$variable == "inst_count"], 2)
  # Dartmouth grants doctoral degrees
  expect_gt(df$value[df$variable == "share_degrees_doctoral"], 0)
  # No community college in Grafton County -- associate-level production is
  # negligible, not necessarily exactly zero (a four-year institution can
  # still award a small number of associate-level credentials)
  expect_lt(df$value[df$variable == "share_degrees_assoc"], 0.01)
})

test_that("get_ipeds() degree-level shares sum to 1", {
  skip_if_no_s3()

  df <- get_ipeds(geoids = "33009", years = 2018)
  level_shares <- df$value[df$variable %in% c(
    "share_degrees_assoc", "share_degrees_bach",
    "share_degrees_masters", "share_degrees_doctoral"
  )]

  expect_equal(sum(level_shares), 1, tolerance = 0.001)
})

test_that("get_ipeds() at institution grain returns institution-level rows for a known county", {
  skip_if_no_s3()

  df <- get_ipeds(geography = "institution", surveys = "institutional_characteristics",
    geoids = "33009",
    years       = 2018
  )

  expect_s3_class(df, "data.frame")
  expect_gt(nrow(df), 0)
  expect_true(all(c("unitid", "geoid", "year") %in% names(df)))
  expect_true(all(df$geoid == "33009"))
})

test_that("get_ipeds() and get_ipeds() agree on Grafton's institution count", {
  skip_if_no_s3()

  county_df <- get_ipeds(geoids = "33009", years = 2018)
  inst_df   <- get_ipeds(geography = "institution", surveys = "institutional_characteristics",
    geoids = "33009",
    years       = 2018
  )

  expect_equal(
    county_df$value[county_df$variable == "inst_count"],
    length(unique(inst_df$unitid[inst_df$is_degree_granting == 1]))
  )
})


test_that("get_ipeds() grad rates are real rates, not degenerate 1.0s", {
  # Regression guard against the COHORT-as-count defect, which made every
  # county's grad_rate_150pct exactly 1.0. Expect this to fail until
  # write_ipeds_all(overwrite = TRUE) has republished data_county.
  skip_if_no_s3()

  df <- get_ipeds(variables = "grad_rate_150pct", years = 2022)
  skip_if(nrow(df) == 0, "no grad_rate_150pct rows for 2022")

  expect_true(all(df$value >= 0 & df$value <= 1))
  # A handful of counties can legitimately hit 1.0; all of them cannot.
  expect_lt(mean(df$value == 1), 0.05)
  # agg_var carries the adjusted cohort, so it must be a positive count
  expect_true(all(df$agg_var > 0))
})

test_that("get_ipeds() degree counts are not double-counted", {
  # Regression guard against summing CIPCODE 99 grand totals and second
  # majors. National tracked degrees run about 4.2-4.8M/yr; the defect put
  # the total near 9.4M.
  skip_if_no_s3()

  df <- get_ipeds(variables = "count_degrees_total", years = 2022)
  skip_if(nrow(df) == 0, "no count_degrees_total rows for 2022")

  # 2010-2024 runs 3.41M to 4.21M; the double-counting defect put 2022 at 9.4M
  national <- sum(df$value, na.rm = TRUE)
  expect_gt(national, 3.0e6)
  expect_lt(national, 6e6)
})
