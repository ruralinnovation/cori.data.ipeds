# County aggregation universe rules. Pure functions over synthetic frames --
# no network. These are regression guards for two defects that produced
# plausible-looking but wrong published numbers:
#
#   1. completions summed NCES CIPCODE 99 grand-total rows alongside the
#      per-program rows, and second majors alongside first, inflating
#      count_degrees_total by ~2.05x
#   2. grad rates aggregated the COHORT column, a categorical indicator that
#      is 1 on every section-1 row, making grad_rate_150pct exactly 1.0

test_that(".is_cip_total() identifies only the NCES grand-total code", {
  expect_true(.is_cip_total("99.0000"))
  expect_true(.is_cip_total(99))
  expect_false(.is_cip_total("51.3801"))
  expect_false(.is_cip_total("09.9999"))
  expect_false(.is_cip_total(NA))
})

test_that("tracked award levels are degrees only", {
  # AWLEVEL 2 is "award of at least 1 but less than 2 academic years" -- a
  # sub-associate certificate, not an associate degree (that is code 3).
  expect_false(2L %in% .ASSOC_LEVELS)
  expect_true(3L %in% .ASSOC_LEVELS)
  expect_setequal(.TRACKED_DEGREE_LEVELS, c(3L, 5L, 7L, 17L, 18L, 19L))
})


# Synthetic completions: one degree-granting institution with two programs,
# plus the NCES grand-total rows, a second major, and an institution that is
# not degree-granting.
.fake_completions <- function() {
  data.frame(
    unitid               = c("000001", "000001", "000001", "000001",
                             "000001", "000002"),
    geoid          = rep("11111", 6),
    cipcode              = c("51.0000", "52.0000", "99.0000", "99.0000",
                             "51.0000", "51.0000"),
    major_num            = c(1L, 1L, 1L, 1L, 2L, 1L),
    ed_level             = c(5L, 3L, 5L, 3L, 5L, 5L),
    count_total_students = c(100L, 50L, 100L, 50L, 10L, 999L),
    count_men            = c(40L, 20L, 40L, 20L, 4L, 999L),
    count_women          = c(60L, 30L, 60L, 30L, 6L, 999L),
    year                 = rep(2022L, 6),
    stringsAsFactors     = FALSE
  )
}

test_that(".county_completions() counts each degree once", {
  out <- .county_completions(.fake_completions(), dg_unitids = "000001")

  total <- out$value[out$variable == "count_degrees_total"]

  # 100 bachelor's + 50 associate. Not 310, which is what summing the
  # CIPCODE 99 rows (+150) and the second major (+10) would give.
  expect_equal(total, 150)
})

test_that(".county_completions() excludes institutions outside the degree-granting universe", {
  out <- .county_completions(.fake_completions(), dg_unitids = "000001")
  # unitid 000002 carries 999 students and must not appear anywhere
  expect_false(any(out$value == 999))
})

test_that(".county_completions() shares are computed against the deduplicated total", {
  out <- .county_completions(.fake_completions(), dg_unitids = "000001")
  val <- function(v) out$value[out$variable == v]

  expect_equal(val("share_degrees_bach"),  100 / 150)
  expect_equal(val("share_degrees_assoc"),  50 / 150)
  expect_equal(val("share_degrees_men"),    60 / 150)
  expect_equal(val("share_degrees_women"),  90 / 150)

  # agg_var is the denominator, so raw counts round-trip
  expect_equal(
    out$agg_var[out$variable == "share_degrees_bach"] *
      val("share_degrees_bach"),
    100
  )
})

test_that(".county_completions() level shares still sum to 1", {
  out <- .county_completions(.fake_completions(), dg_unitids = "000001")
  shares <- out$value[out$variable %in% c(
    "share_degrees_assoc", "share_degrees_bach",
    "share_degrees_masters", "share_degrees_doctoral"
  )]
  expect_equal(sum(shares), 1, tolerance = 1e-9)
})


# Synthetic grad rates: GRTYPE 2 = adjusted cohort, 3 = completers within
# 150%, 4 = transfer-out. count_total_students holds the real counts.
.fake_grad_rates <- function() {
  data.frame(
    unitid               = c("000001", "000001", "000001", "000003"),
    geoid          = rep("11111", 4),
    cohort_type          = c(2L, 3L, 4L, 2L),
    count_total_students = c(1000L, 700L, 100L, 555L),
    year                 = rep(2022L, 4),
    stringsAsFactors     = FALSE
  )
}

test_that(".county_grad_rates() computes a real rate, not a ratio of row counts", {
  out <- .county_grad_rates(.fake_grad_rates(), dg_unitids = "000001")
  val <- function(v) out$value[out$variable == v]

  expect_equal(val("grad_rate_150pct"),  0.7)
  expect_equal(val("transfer_out_rate"), 0.1)

  # The old defect made this exactly 1.0 for every county
  expect_lt(val("grad_rate_150pct"), 1)
})

test_that(".county_grad_rates() carries the adjusted cohort in agg_var", {
  out <- .county_grad_rates(.fake_grad_rates(), dg_unitids = "000001")

  expect_equal(out$agg_var[out$variable == "grad_rate_150pct"], 1000)
  # so the completer count is recoverable
  expect_equal(
    out$value[out$variable == "grad_rate_150pct"] *
      out$agg_var[out$variable == "grad_rate_150pct"],
    700
  )
})

test_that(".county_grad_rates() excludes institutions outside the degree-granting universe", {
  out <- .county_grad_rates(.fake_grad_rates(), dg_unitids = "000001")
  # unitid 000003 would have added 555 to the denominator
  expect_equal(out$agg_var[out$variable == "grad_rate_150pct"], 1000)
})


test_that("process_ipeds_county() refuses to aggregate without IC", {
  # completions and grad_rates carry no degree-granting flag of their own,
  # so without IC the documented restriction cannot be honoured. Skipping
  # with a warning beats publishing an unrestricted aggregation.
  expect_warning(
    out <- process_ipeds_county(list(
      institutional_characteristics = NULL,
      completions                   = .fake_completions(),
      grad_rates                    = NULL
    )),
    "degree-granting"
  )
  expect_null(out)
})


# Completers ------------------------------------------------------------------
#
# Headcounts from the C{year}_C file, one row per institution x award level
# category. Distinct from completions, which counts awards.

.fake_completers <- function() {
  data.frame(
    unitid               = c("000001", "000001", "000001", "000001",
                             "000001", "000004"),
    geoid          = rep("11111", 6),
    # 3 = associate, 5 = bachelor's, 7 = master's, 9 = doctoral,
    # 2 = a certificate level that must not be aggregated
    award_level_category = c(3L, 5L, 7L, 9L, 2L, 5L),
    count_total_students = c(40L, 300L, 90L, 10L, 500L, 777L),
    year                 = rep(2022L, 6),
    stringsAsFactors     = FALSE
  )
}

test_that(".county_completers() emits one variable per degree level", {
  out <- .county_completers(.fake_completers(), dg_unitids = "000001")
  val <- function(v) out$value[out$variable == v]

  expect_equal(val("count_students_assoc"),     40)
  expect_equal(val("count_students_bach"),     300)
  expect_equal(val("count_students_masters"),   90)
  expect_equal(val("count_students_doctoral"),  10)
  expect_setequal(out$survey, "completers")
})

test_that(".county_completers() ignores certificate award levels", {
  out <- .county_completers(.fake_completers(), dg_unitids = "000001")
  # AWLEVELC 2 carries 500 students and is not a degree
  expect_false(any(out$value == 500))
  expect_equal(nrow(out), 4)
})

test_that(".county_completers() applies the degree-granting universe", {
  out <- .county_completers(.fake_completers(), dg_unitids = "000001")
  # unitid 000004 carries 777 bachelor's completers
  expect_equal(out$value[out$variable == "count_students_bach"], 300)
})

test_that(".county_completers() emits no cross-level total", {
  # Students are not additive across levels -- a cross-level total would
  # overcount anyone earning degrees at two levels in the same year.
  out <- .county_completers(.fake_completers(), dg_unitids = "000001")
  expect_false(any(grepl("total", out$variable)))
  expect_true(all(is.na(out$agg_var)))
})

test_that(".county_completers() returns NULL when the level column is missing", {
  df <- .fake_completers()
  df$award_level_category <- NULL
  expect_warning(out <- .county_completers(df, "000001"), "missing columns")
  expect_null(out)
})

test_that("process_ipeds_county() aggregates completers alongside the other surveys", {
  out <- process_ipeds_county(list(
    institutional_characteristics = data.frame(
      unitid = "000001", geoid = "11111", is_degree_granting = 1L,
      sector_code = 1L, is_public = 1L, is_nonprofit = 0L, is_4yr = 1L,
      is_2yr = 0L, is_hbcu = 0L, is_tribal = 0L, year = 2022L,
      stringsAsFactors = FALSE
    ),
    completions = .fake_completions(),
    completers  = .fake_completers(),
    grad_rates  = .fake_grad_rates()
  ))

  expect_true("completers" %in% out$survey)
  expect_setequal(
    out$variable[out$survey == "completers"],
    c("count_students_assoc", "count_students_bach",
      "count_students_masters", "count_students_doctoral")
  )
  # all four surveys represented
  expect_setequal(
    unique(out$survey),
    c("institutional_characteristics", "completions", "completers", "grad_rates")
  )
})


# Raw header normalisation ----------------------------------------------------

test_that(".normalize_nces_names() uppercases and trims", {
  expect_equal(.normalize_nces_names(c("unitid", "Awlevel")), c("UNITID", "AWLEVEL"))
  expect_equal(.normalize_nces_names("CNRALW  "), "CNRALW")
  expect_equal(.normalize_nces_names(" DFRCGID "), "DFRCGID")
})

test_that(".normalize_nces_names() strips a UTF-8 BOM in any representation", {
  # NCES began shipping BOMs on some 2023+ files. Left in place, the first
  # column name stops matching UNITID and the column is dropped -- which is
  # how completers 2023/2024 lost unitid and geoid.
  expect_equal(.normalize_nces_names("﻿UNITID"), "UNITID")
  expect_equal(.normalize_nces_names("<ef><bb><bf>UNITID"), "UNITID")
  expect_equal(
    .normalize_nces_names(rawToChar(c(as.raw(c(0xef, 0xbb, 0xbf)), charToRaw("UNITID")))),
    "UNITID"
  )
})

test_that(".normalize_nces_names() leaves clean names untouched", {
  nms <- c("UNITID", "AWLEVELC", "CSTOTLT", "C2MORM", "GRTOTLT")
  expect_equal(.normalize_nces_names(nms), nms)
})


# Unreported numerators -------------------------------------------------------

test_that(".county_grad_rates() omits a county with no numerator rows rather than publishing 0", {
  # Transfer-out reporting is effectively optional. A county whose
  # institutions report an adjusted cohort but no transfer-out row has no
  # transfer-out rate -- publishing 0.000 would be a false precision, and it
  # affected 23% of county-years before this was fixed.
  df <- data.frame(
    unitid               = c("000001", "000001"),
    geoid          = c("11111", "11111"),
    cohort_type          = c(2L, 3L),      # cohort + completers, no type 4
    count_total_students = c(1000L, 700L),
    year                 = c(2022L, 2022L),
    stringsAsFactors     = FALSE
  )
  out <- .county_grad_rates(df, dg_unitids = "000001")

  expect_true("grad_rate_150pct" %in% out$variable)
  expect_false("transfer_out_rate" %in% out$variable)
})

test_that(".county_grad_rates() keeps a genuinely reported zero", {
  # Distinct from the case above: here type 4 IS reported, as zero.
  df <- data.frame(
    unitid               = c("000001", "000001", "000001"),
    geoid          = rep("11111", 3),
    cohort_type          = c(2L, 3L, 4L),
    count_total_students = c(1000L, 700L, 0L),
    year                 = rep(2022L, 3),
    stringsAsFactors     = FALSE
  )
  out <- .county_grad_rates(df, dg_unitids = "000001")

  expect_true("transfer_out_rate" %in% out$variable)
  expect_equal(out$value[out$variable == "transfer_out_rate"], 0)
})
