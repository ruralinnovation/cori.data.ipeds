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
  where <- .ipeds_where(unitids = "182670", county_fips = "33009")
  expect_equal(
    where,
    "WHERE unitid IN ('182670') AND county_fips IN ('33009')"
  )
})
