# Public API shape and argument validation. No network required except where
# marked. See test-integration-s3.R for the real S3 round-trip.
#
# The getters follow the cori.data family convention: one function per
# measure, `geography` first. get_ipeds() is the general getter underneath.

test_that("the package exports the house-shaped getters", {
  exports <- getNamespaceExports("cori.data.ipeds")
  expect_true(all(c("get_institutions", "get_degrees", "get_completers",
                    "get_graduation_rates", "get_ipeds",
                    "get_ipeds_codebook", "get_cip_soc_crosswalk")
                  %in% exports))
})

test_that("every getter takes geography first, matching the siblings", {
  # cori.data.qcew::get_employment(geography, geoids, years) and
  # cori.data.bds::get_business_dynamics(geography, geoids, years, variables)
  # set the convention; a getter that leads with anything else is a trap.
  for (f in c("get_institutions", "get_degrees", "get_completers",
              "get_graduation_rates", "get_ipeds")) {
    expect_identical(names(formals(get(f)))[1], "geography", info = f)
  }
})

test_that("measure getters share one signature", {
  common <- c("geography", "geoids", "years", "variables", "unitids")
  for (f in c("get_institutions", "get_degrees", "get_completers",
              "get_graduation_rates")) {
    expect_identical(names(formals(get(f)))[1:5], common, info = f)
  }
})

test_that("each measure maps to exactly one survey", {
  expect_identical(
    MEASURE_SURVEY,
    c(institutions     = "institutional_characteristics",
      degrees          = "completions",
      completers       = "completers",
      graduation_rates = "grad_rates")
  )
  expect_true(all(MEASURE_SURVEY %in% IPEDS_SURVEYS))
})


# geography -------------------------------------------------------------------

test_that("geography is validated", {
  expect_error(get_degrees(geography = "state"), "should be one of")
  expect_error(get_ipeds(geography = "tract"), "should be one of")
})

test_that("institution grain needs exactly one survey", {
  expect_error(get_ipeds(geography = "institution"), "exactly one")
  expect_error(
    get_ipeds(geography = "institution", surveys = c("completions", "completers")),
    "exactly one"
  )
})

test_that("unknown surveys are rejected with the valid list", {
  expect_error(get_ipeds(surveys = "ic"), "Unknown survey")
  expect_error(get_ipeds(surveys = "ic"), "institutional_characteristics")
})


# Arguments that only apply at one grain --------------------------------------

test_that("`variables` is refused at institution grain", {
  # The institution tables are wide; `variables` filters the tidy county
  # output. Silently ignoring it would be worse than erroring.
  expect_error(
    get_degrees(geography = "institution", variables = "count_degrees_total"),
    "wide"
  )
  expect_error(
    get_ipeds(geography = "institution", surveys = "completions",
              variables = "count_degrees_total"),
    "wide"
  )
})

test_that("`unitids` is refused at county grain", {
  expect_error(get_degrees(unitids = "182670"), "institution")
  expect_error(get_ipeds(unitids = "182670"), "institution")
})


# The positional trap ---------------------------------------------------------

test_that("a survey passed positionally errors instead of returning nothing", {
  # get_ipeds_county("completions", years = 2024) used to put "completions"
  # into `geoids` and return zero rows silently. Now `geography` is first, so
  # the same slip is caught by match.arg.
  expect_error(get_ipeds("completions"), "should be one of")
  expect_error(get_degrees("completions"), "should be one of")
})

test_that("a survey passed as geoids errors with a pointer", {
  expect_error(get_ipeds(geoids = "completions"), "Did you mean `surveys =`")
})
