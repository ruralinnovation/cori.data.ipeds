# Pure string-building logic, no network required. .ipeds_where() is
# unexported but callable directly here since tests run inside the
# package namespace.

test_that(".ipeds_where() returns an empty string when nothing is filtered", {
  expect_equal(.ipeds_where(), "")
})

test_that(".ipeds_where() builds a single-clause WHERE for one filter", {
  expect_equal(.ipeds_where(geoids = "33009"), "WHERE geoid IN ('33009')")
})

test_that(".ipeds_where() quotes multiple values in an IN list", {
  expect_equal(
    .ipeds_where(geoids = c("33009", "33001")),
    "WHERE geoid IN ('33009', '33001')"
  )
})

test_that(".ipeds_where() coerces years to integers, unquoted", {
  expect_equal(.ipeds_where(years = c(2018, 2020)), "WHERE year IN (2018, 2020)")
})

test_that(".ipeds_where() combines multiple filters with AND, in a fixed order", {
  where <- .ipeds_where(geoids = "33009", years = 2018, variables = "inst_count")
  expect_equal(
    where,
    "WHERE geoid IN ('33009') AND year IN (2018) AND variable IN ('inst_count')"
  )
})

test_that(".ipeds_where() supports the institution-level filter set", {
  # Institution and county grain both filter on `geoid`, so one clause builder
  # serves both -- there is no separate county_fips argument.
  where <- .ipeds_where(unitids = "182670", geoids = "33009")
  expect_equal(
    where,
    "WHERE geoid IN ('33009') AND unitid IN ('182670')"
  )
})


# Argument validation ---------------------------------------------------------
#
# get_ipeds(geography = "institution", surveys = ) takes `survey` first and required; get_ipeds()
# takes `years` first with `surveys` fourth. Passing a survey positionally to
# the county getter therefore lands it in `geoids` and used to return zero rows
# with no complaint.

test_that(".ipeds_validate_county_args() catches a survey passed as a geoid", {
  expect_error(
    .ipeds_validate_county_args(geoids = "completions"),
    "5-digit county FIPS"
  )
  expect_error(
    .ipeds_validate_county_args(geoids = "completions"),
    "Did you mean `surveys =`"
  )
})

test_that(".ipeds_validate_county_args() catches a variable passed as a geoid", {
  expect_error(
    .ipeds_validate_county_args(geoids = "grad_rate_150pct"),
    "Did you mean `variables =`"
  )
})

test_that(".ipeds_validate_county_args() rejects unknown surveys and variables", {
  expect_error(.ipeds_validate_county_args(surveys = "ic"), "Unknown survey")
  expect_error(.ipeds_validate_county_args(variables = "grad_rate"),
               "Unknown county variable")
})

test_that(".ipeds_validate_county_args() accepts valid input", {
  expect_true(.ipeds_validate_county_args(
    geoids    = c("33009", "06037"),
    variables = c("inst_count", "grad_rate_150pct"),
    surveys   = c("completions", "completers")
  ))
  expect_true(.ipeds_validate_county_args())
})

test_that(".ipeds_validate_county_args() rejects malformed FIPS codes", {
  expect_error(.ipeds_validate_county_args(geoids = "3309"), "5-digit")
  expect_error(.ipeds_validate_county_args(geoids = "NH"), "5-digit")
})
