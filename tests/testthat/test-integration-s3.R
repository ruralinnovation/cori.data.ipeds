# Integration tests against real S3 data. Skipped automatically when offline
# or when no AWS/vended credentials are available (see helper-s3.R) -- these
# confirm the public read path actually works end to end, not just that the
# query-building logic is correct.

test_that("get_ipeds_county() returns the documented 6-column shape", {
  skip_if_no_s3()

  df <- get_ipeds_county(geoids = "33009", years = 2018)

  expect_s3_class(df, "data.frame")
  expect_setequal(
    names(df),
    c("geoid", "year", "variable", "value", "agg_var", "survey")
  )
  expect_true(is.character(df$geoid))
  expect_true(is.integer(df$year))
  expect_true(all(nchar(df$geoid) == 5))
})

test_that("get_ipeds_county() Grafton County NH 2018 spot check", {
  skip_if_no_s3()

  df <- get_ipeds_county(geoids = "33009", years = 2018)

  # Dartmouth + Plymouth State
  expect_equal(df$value[df$variable == "inst_count"], 2)
  # Dartmouth grants doctoral degrees
  expect_gt(df$value[df$variable == "share_degrees_doctoral"], 0)
  # No community college in Grafton County -- associate-level production is
  # negligible, not necessarily exactly zero (a four-year institution can
  # still award a small number of associate-level credentials)
  expect_lt(df$value[df$variable == "share_degrees_assoc"], 0.01)
})

test_that("get_ipeds_county() degree-level shares sum to 1", {
  skip_if_no_s3()

  df <- get_ipeds_county(geoids = "33009", years = 2018)
  level_shares <- df$value[df$variable %in% c(
    "share_degrees_assoc", "share_degrees_bach",
    "share_degrees_masters", "share_degrees_doctoral"
  )]

  expect_equal(sum(level_shares), 1, tolerance = 0.001)
})

test_that("get_ipeds_institution() returns institution-level rows for a known county", {
  skip_if_no_s3()

  df <- get_ipeds_institution(
    "institutional_characteristics",
    county_fips = "33009",
    years       = 2018
  )

  expect_s3_class(df, "data.frame")
  expect_gt(nrow(df), 0)
  expect_true(all(c("unitid", "county_fips", "year") %in% names(df)))
  expect_true(all(df$county_fips == "33009"))
})

test_that("get_ipeds_county() and get_ipeds_institution() agree on Grafton's institution count", {
  skip_if_no_s3()

  county_df <- get_ipeds_county(geoids = "33009", years = 2018)
  inst_df   <- get_ipeds_institution(
    "institutional_characteristics",
    county_fips = "33009",
    years       = 2018
  )

  expect_equal(
    county_df$value[county_df$variable == "inst_count"],
    length(unique(inst_df$unitid[inst_df$is_degree_granting == 1]))
  )
})
