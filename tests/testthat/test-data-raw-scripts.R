# data-raw/ is .Rbuildignore'd, so R CMD check never parses it and a syntax
# error there goes unnoticed until someone runs a maintainer script -- which
# is exactly what happened to validate_etl.R during an API rename. These
# scripts are not sourced here (they hit S3 and NCES); they are only parsed.

test_that("every data-raw script parses", {
  dir <- testthat::test_path("..", "..", "data-raw")
  skip_if_not(dir.exists(dir), "data-raw/ not present (installed package)")

  scripts <- list.files(dir, pattern = "[.]R$", full.names = TRUE)
  expect_gt(length(scripts), 0)

  for (f in scripts) {
    expect_no_error(parse(f), message = basename(f))
  }
})

