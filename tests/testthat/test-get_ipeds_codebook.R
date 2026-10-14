# The codebook is now a pure function (no file I/O), so these run anywhere --
# no network, no credentials, and nothing that can go missing from an install.

test_that("get_ipeds_codebook() returns the documented shape", {
  cb <- get_ipeds_codebook()

  expect_s3_class(cb, "data.frame")
  expect_gt(nrow(cb), 0)
  expect_identical(
    names(cb),
    c("variable", "raw_variable", "label", "unit",
      "survey", "level", "notes", "codes")
  )
})

test_that("get_ipeds_codebook() decodes every categorical variable", {
  # The institution grain returns NCES's bare integers, so a variable whose
  # unit declares it an integer category needs its numbers spelled out --
  # otherwise sector_code = 4 is unreadable without leaving the package.
  cb <- get_ipeds_codebook()

  coded <- c(
    "sector_code", "funding_source_code", "inst_level_code", "hbcu_code",
    "has_hospital_code", "tribal_college_code", "degree_granting_status_code",
    "carnegie_classification_code", "highest_level_offered_code",
    "highest_degree_offered_code", "undergrad_degree_offered_code",
    "grad_degree_offered_code", "urbanization_level_code", "land_grant_code",
    "institution_size_code", "major_num", "ed_level",
    "award_level_category", "cohort_type", "grad_rate_status"
  )

  expect_true(all(coded %in% cb$variable))
  expect_true(all(nzchar(cb$codes[cb$variable %in% coded])))

  # Counts are not categories, so they must not carry a code list
  expect_true(all(!nzchar(
    cb$codes[cb$variable %in% c("count_men", "count_women",
                                "count_total_students", "inst_count")]
  )))
})

test_that("get_ipeds_codebook()'s code lists parse as code = label pairs", {
  cb <- get_ipeds_codebook()

  for (v in cb$variable[nzchar(cb$codes)]) {
    pairs <- strsplit(cb$codes[cb$variable == v][1], "; ", fixed = TRUE)[[1]]
    expect_true(all(grepl("^-?[0-9]+ = .+", pairs)),
                info = sprintf("%s has a malformed code list", v))

    codes <- sub(" = .*$", "", pairs)
    expect_equal(anyDuplicated(codes), 0,
                 info = sprintf("%s lists a code twice", v))
  }
})

test_that("get_ipeds_codebook() does not restate codes in notes", {
  # Regression guard. highest_degree_offered_code once described a 0-6 scale
  # in `notes` that does not exist in the data -- it is really 0, 11-14, 20,
  # 30, 40, with 40 the LOWEST degree. Where a variable has a `codes` entry,
  # that is the single place its numbers are defined.
  cb <- get_ipeds_codebook()
  hd <- cb[cb$variable == "highest_degree_offered_code", ]

  expect_false(grepl("1 = Certificate", hd$notes, fixed = TRUE))
  expect_true(grepl("40", hd$codes, fixed = TRUE))
  expect_equal(
    sub("^.*40 = ", "", hd$codes),
    "Associate's degree"
  )
})

test_that("get_ipeds_codebook() survey and level are constrained to known values", {
  cb <- get_ipeds_codebook()

  expect_true(all(cb$survey %in% c(
    "institutional_characteristics", "completions", "completers", "grad_rates"
  )))
  expect_true(all(cb$level %in% c("institution", "county", "both")))
})

test_that("get_ipeds_codebook() is unique on variable within a survey", {
  # Not globally unique: count_men / count_women / count_total_students are
  # defined once per survey because they map from different NCES columns
  # (CTOTALM in completions, GRTOTLM in grad rates). Both consumers --
  # apply_codebook_mapping() and .select_codebook_columns() -- filter by
  # survey first, so the key that must be unique is variable + survey.
  cb <- get_ipeds_codebook()
  expect_equal(anyDuplicated(cb[, c("variable", "survey")]), 0)
})

test_that("get_ipeds_codebook() maps a raw NCES column iff the variable is read from one", {
  cb <- get_ipeds_codebook()

  # Institution-level and shared variables are renamed from an NCES column
  from_nces <- cb[cb$level %in% c("institution", "both"), ]
  expect_true(all(nzchar(from_nces$raw_variable)))

  # County-level variables are derived in process_county.R, not read
  derived <- cb[cb$level == "county", ]
  expect_true(all(!nzchar(derived$raw_variable)))
})

test_that("get_ipeds_codebook() documents coverage for every variable", {
  # `notes` carries the vintage caveats that make cross-year comparison
  # safe; an empty one means a variable shipped undocumented.
  cb <- get_ipeds_codebook()
  expect_true(all(nzchar(cb$notes)))
  expect_true(all(nzchar(cb$label)))
  expect_true(all(nzchar(cb$unit)))
})

test_that("get_ipeds_codebook() maps the grad-rate counts, not the COHORT category", {
  # Regression guard. COHORT is a categorical indicator of the cohort
  # universe and is 1 on every section-1 row, so aggregating it yields a
  # count of institutions and a graduation rate of exactly 1.0. The real
  # counts are in GRTOTLT / GRTOTLM / GRTOTLW.
  cb <- get_ipeds_codebook()
  gr <- cb[cb$survey == "grad_rates" & cb$level == "institution", ]

  expect_true("GRTOTLT" %in% gr$raw_variable)
  expect_false("COHORT"  %in% gr$raw_variable)
  expect_equal(
    gr$variable[gr$raw_variable == "GRTOTLT"],
    "count_total_students"
  )
})

test_that("get_ipeds_codebook() exposes the completions columns the universe filter needs", {
  # .county_completions() filters on cipcode and major_num, which means both
  # have to survive .select_codebook_columns() to reach it.
  cb <- get_ipeds_codebook()
  comp <- cb[cb$survey == "completions" & cb$level == "institution", ]

  expect_true(all(c("cipcode", "major_num") %in% comp$variable))
  expect_equal(comp$raw_variable[comp$variable == "major_num"], "MAJORNUM")
})

test_that("get_ipeds_codebook()'s county-level rows match the county output contract", {
  # This is the same 20-variable set get_ipeds() promises in its
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
    "count_students_assoc", "count_students_bach",
    "count_students_masters", "count_students_doctoral",
    "grad_rate_150pct", "transfer_out_rate"
  )

  expect_setequal(county_vars, expected)
})
