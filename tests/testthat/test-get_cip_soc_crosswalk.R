# CIP-to-SOC crosswalk. Reads shipped .rds files -- no network.

test_that("get_cip_soc_crosswalk() returns the documented shape", {
  for (v in c("2020", "2010")) {
    xw <- get_cip_soc_crosswalk(v)
    expect_s3_class(xw, "data.frame")
    expect_gt(nrow(xw), 1000)
    expect_identical(
      names(xw),
      c("cip_code", "cip_title", "soc_code", "soc_title",
        "cip_vintage", "soc_vintage")
    )
  }
})

test_that("get_cip_soc_crosswalk() defaults to the 2020 vintage", {
  expect_identical(get_cip_soc_crosswalk(), get_cip_soc_crosswalk("2020"))
})

test_that("get_cip_soc_crosswalk() rejects an unknown vintage", {
  expect_error(get_cip_soc_crosswalk("2015"), "should be one of")
})

test_that("get_cip_soc_crosswalk() labels its vintages so crosswalks can be row-bound", {
  a <- get_cip_soc_crosswalk("2020")
  b <- get_cip_soc_crosswalk("2010")

  expect_true(all(a$cip_vintage == 2020L) && all(a$soc_vintage == 2018L))
  expect_true(all(b$cip_vintage == 2010L) && all(b$soc_vintage == 2010L))

  both <- rbind(a, b)
  expect_setequal(unique(both$cip_vintage), c(2010L, 2020L))
})


# Join compatibility ----------------------------------------------------------
#
# The whole point of the crosswalk is joining to the completions table's
# `cipcode`. NCES quotes CIPCODE in the source CSV but read.csv type-converts
# it to numeric anyway, dropping the leading zero on the 01-09 families
# (01.0000 -> 1, 09.0702 -> 9.0702). Both sides must therefore be formatted
# identically, or the join succeeds for CIP 10+ and silently returns nothing
# for everything below it.

test_that("crosswalk CIP codes are canonical zero-padded xx.xxxx strings", {
  for (v in c("2020", "2010")) {
    xw <- get_cip_soc_crosswalk(v)
    expect_type(xw$cip_code, "character")
    expect_true(all(grepl("^[0-9]{2}[.][0-9]{4}$", xw$cip_code)))
  }
})

test_that("crosswalk retains the leading-zero CIP families", {
  xw <- get_cip_soc_crosswalk("2020")
  expect_true("01.0000" %in% xw$cip_code)   # Agriculture, General
  expect_true("09.0702" %in% xw$cip_code)   # Digital Communication
  expect_gt(length(unique(xw$cip_code[startsWith(xw$cip_code, "0")])), 100)
})

test_that(".pad_cipcode() produces exactly what the crosswalk stores", {
  # Simulates what read.csv hands the reconciler: numeric, zero already gone.
  df <- data.frame(CIPCODE = c(1, 9.0702, 11.0701, 99, NA))
  out <- .pad_cipcode(df)

  expect_type(out$CIPCODE, "character")
  expect_equal(
    out$CIPCODE,
    c("01.0000", "09.0702", "11.0701", "99.0000", NA_character_)
  )

  # and those values are present in the crosswalk as written
  xw <- get_cip_soc_crosswalk("2020")
  expect_true(all(c("01.0000", "09.0702", "11.0701") %in% xw$cip_code))
})

test_that(".pad_cipcode() is a no-op when the column is absent", {
  df <- data.frame(UNITID = "000001", stringsAsFactors = FALSE)
  expect_identical(.pad_cipcode(df), df)
})


# Unmatched programs ----------------------------------------------------------

test_that("get_cip_soc_crosswalk() keeps unmatched CIP codes with NA soc_code", {
  # Retained rather than dropped so a left join from completions never
  # silently loses a program. NCES's "99-9999" sentinel becomes NA.
  xw <- get_cip_soc_crosswalk("2020")

  expect_gt(sum(is.na(xw$soc_code)), 0)
  expect_false("99-9999" %in% xw$soc_code)
  expect_true(all(is.na(xw$soc_title[is.na(xw$soc_code)])))
})

test_that("get_cip_soc_crosswalk() is many-to-many, as documented", {
  xw <- get_cip_soc_crosswalk("2020")
  per_cip <- table(xw$cip_code)
  expect_gt(max(per_cip), 1)
  per_soc <- table(xw$soc_code[!is.na(xw$soc_code)])
  expect_gt(max(per_soc), 1)
})
