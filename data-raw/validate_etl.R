# Post-ETL validation for cori.data.ipeds
#
# Reads directly from S3 via DuckDB and runs a battery of checks against the
# data_county and data_institution layers. Designed to be run after
# write_ipeds_all() completes (maintainer-only; see data-raw/refresh_ipeds.R).
#
# Usage (the package must be loaded -- this script calls its internals):
#   devtools::load_all(); source("data-raw/validate_etl.R")
#
# Requirements: DBI, duckdb, and S3 read access. Credentials are resolved by
# cori.data.s3::connect_to_s3() via .ipeds_duckdb_con(), the same path the
# public read functions use, so this validates what users actually hit.

library(DBI)

local({

S3_BUCKET      <- "cori.data.ipeds"
S3_PREFIX      <- ""
EXPECTED_YEARS <- IPEDS_START_YEAR:IPEDS_END_YEAR
EXPECTED_VARS  <- c(
  # IC
  "inst_count", "public_inst_count", "nonprofit_inst_count",
  "fouryear_inst_count", "twoyear_inst_count", "hbcu_count", "tribal_count",
  # Completions
  "count_degrees_total",
  "share_degrees_assoc", "share_degrees_bach",
  "share_degrees_masters", "share_degrees_doctoral",
  "share_degrees_men", "share_degrees_women",
  # Completers (student headcounts; 2012+ only)
  "count_students_assoc", "count_students_bach",
  "count_students_masters", "count_students_doctoral",
  # Grad rates (not available for the most recent year -- NCES lag)
  "grad_rate_150pct", "transfer_out_rate"
)
COMPLETER_VARS   <- c("count_students_assoc", "count_students_bach",
                      "count_students_masters", "count_students_doctoral")
SHARE_LEVEL_VARS <- c("share_degrees_assoc", "share_degrees_bach",
                      "share_degrees_masters", "share_degrees_doctoral")
SHARE_SEX_VARS   <- c("share_degrees_men", "share_degrees_women")
GR_VARS          <- c("grad_rate_150pct", "transfer_out_rate")

# Spot check: Grafton County NH -- home of Dartmouth + Plymouth State
SPOT_GEOID <- "33009"
SPOT_NAME  <- "Grafton County NH (Dartmouth)"


# Setup -----------------------------------------------------------------------

pass <- 0L
fail <- 0L

check <- function(label, expr, detail = NULL) {
  result <- tryCatch(expr, error = function(e) FALSE)
  if (isTRUE(result)) {
    cat(sprintf("  PASS  %s\n", label))
    pass <<- pass + 1L
  } else {
    cat(sprintf("  FAIL  %s\n", label))
    if (!is.null(detail)) cat(sprintf("        %s\n", detail))
    fail <<- fail + 1L
  }
}

con <- .ipeds_duckdb_con(S3_BUCKET)
on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)

glob <- sprintf("s3://%s/%sdata_county/year=*/part-0.parquet", S3_BUCKET, S3_PREFIX)

cat("\nReading county data from S3...\n")
df <- dbGetQuery(con, sprintf(
  "SELECT * FROM read_parquet('%s', union_by_name = true)", glob
))
df$year  <- as.integer(df$year)
df$value <- as.numeric(df$value)
cat(sprintf("  %s rows loaded\n\n", format(nrow(df), big.mark = ",")))


# 1. Year coverage ------------------------------------------------------------

cat("--- 1. Year coverage ---\n")

years_present <- sort(unique(df$year))

check("All expected years present",
  all(EXPECTED_YEARS %in% years_present),
  sprintf("Missing: %s", paste(setdiff(EXPECTED_YEARS, years_present), collapse = ", "))
)

check("No unexpected years present",
  all(years_present %in% EXPECTED_YEARS),
  sprintf("Extra: %s", paste(setdiff(years_present, EXPECTED_YEARS), collapse = ", "))
)


# 2. Variable coverage --------------------------------------------------------

cat("\n--- 2. Variable coverage ---\n")

vars_present <- unique(df$variable)
non_gr_vars  <- setdiff(EXPECTED_VARS, c(GR_VARS, COMPLETER_VARS))
latest_year  <- max(EXPECTED_YEARS)

check("All non-grad-rate variables present across all years",
  all(non_gr_vars %in% vars_present),
  sprintf("Missing: %s", paste(setdiff(non_gr_vars, vars_present), collapse = ", "))
)

check("Grad rate variables present for at least the years before the NCES lag",
  {
    gr_years <- unique(df$year[df$variable == "grad_rate_150pct"])
    all(setdiff(EXPECTED_YEARS, latest_year) %in% gr_years)
  },
  "grad_rate_150pct missing for some years before the most recent one"
)

check("No unknown variables in output",
  all(vars_present %in% EXPECTED_VARS),
  sprintf("Unknown: %s", paste(setdiff(vars_present, EXPECTED_VARS), collapse = ", "))
)

check("County-level variables match get_ipeds_codebook() exactly",
  {
    cb <- tryCatch(get_ipeds_codebook(), error = function(e) NULL)
    cb_county_vars <- if (is.null(cb)) character(0) else cb$variable[cb$level == "county"]
    length(cb_county_vars) > 0 && setequal(cb_county_vars, EXPECTED_VARS)
  },
  "get_ipeds_codebook()'s level == \"county\" rows differ from this script's EXPECTED_VARS -- update whichever is stale"
)


# 3. County coverage ----------------------------------------------------------

cat("\n--- 3. County coverage ---\n")

county_counts <- aggregate(geoid ~ year, df[df$variable == "inst_count", ],
                           FUN = function(x) length(unique(x)))
names(county_counts)[2] <- "n_counties"

cat("  County counts by year:\n")
county_counts_sorted <- county_counts[order(county_counts$year), ]
for (i in seq_len(nrow(county_counts_sorted))) {
  cat(sprintf("    %d: %d counties\n",
              county_counts_sorted$year[i],
              county_counts_sorted$n_counties[i]))
}

check("No year-over-year county count change exceeds 5%",
  {
    counts <- county_counts_sorted$n_counties
    yoy_pct <- abs(diff(counts) / head(counts, -1))
    bad_years <- county_counts_sorted$year[which(yoy_pct > 0.05) + 1]
    if (length(bad_years) > 0) {
      cat(sprintf("        Suspicious jumps in: %s\n",
                  paste(bad_years, collapse = ", ")))
      FALSE
    } else {
      TRUE
    }
  }
)


# 4. No duplicates --------------------------------------------------------------

cat("\n--- 4. Duplicate rows ---\n")

n_total  <- nrow(df)
n_unique <- nrow(unique(df[, c("geoid", "year", "variable")]))

check("No duplicate geoid x year x variable rows",
  n_total == n_unique,
  sprintf("%d duplicate rows found", n_total - n_unique)
)


# 5. Value integrity ------------------------------------------------------------

cat("\n--- 5. Value integrity ---\n")

check("No negative counts (inst_count, count_degrees_total)",
  {
    counts <- df[df$variable %in% c("inst_count", "count_degrees_total"), ]
    all(counts$value >= 0, na.rm = TRUE)
  }
)

check("All share values between 0 and 1",
  {
    shares <- df[df$variable %in% c(SHARE_LEVEL_VARS, SHARE_SEX_VARS), ]
    all(shares$value >= 0 & shares$value <= 1, na.rm = TRUE)
  }
)

check("All grad rate values between 0 and 1",
  {
    gr <- df[df$variable %in% GR_VARS, ]
    all(gr$value >= 0 & gr$value <= 1, na.rm = TRUE)
  }
)

check("No NA values in geoid or year",
  !any(is.na(df$geoid)) && !any(is.na(df$year))
)

check("All geoids are exactly 5 characters",
  all(nchar(df$geoid) == 5)
)


# 6. Share sums -------------------------------------------------------------

cat("\n--- 6. Share sums ---\n")

shares_wide <- reshape(
  df[df$variable %in% SHARE_LEVEL_VARS, c("geoid", "year", "variable", "value")],
  idvar     = c("geoid", "year"),
  timevar   = "variable",
  direction = "wide"
)
shares_wide$total <- rowSums(
  shares_wide[, paste0("value.", SHARE_LEVEL_VARS)], na.rm = FALSE
)
shares_wide <- shares_wide[!is.na(shares_wide$total), ]

check("Degree level shares sum to 1.0 (+-0.001) for all county-years",
  all(abs(shares_wide$total - 1) < 0.001),
  sprintf("Max deviation: %.6f", max(abs(shares_wide$total - 1), na.rm = TRUE))
)

sex_wide <- reshape(
  df[df$variable %in% SHARE_SEX_VARS, c("geoid", "year", "variable", "value")],
  idvar     = c("geoid", "year"),
  timevar   = "variable",
  direction = "wide"
)
sex_wide$total <- rowSums(
  sex_wide[, paste0("value.", SHARE_SEX_VARS)], na.rm = FALSE
)
sex_wide <- sex_wide[!is.na(sex_wide$total), ]

check("Sex shares sum to 1.0 (+-0.001) for all county-years",
  all(abs(sex_wide$total - 1) < 0.001),
  sprintf("Max deviation: %.6f", max(abs(sex_wide$total - 1), na.rm = TRUE))
)


# 7. National trends ----------------------------------------------------------

cat("\n--- 7. National trends ---\n")

nat_degrees <- aggregate(value ~ year,
  df[df$variable == "count_degrees_total", ], FUN = sum, na.rm = TRUE)
nat_degrees <- nat_degrees[order(nat_degrees$year), ]

check("National degree count is positive in all years",
  all(nat_degrees$value > 0)
)

check("National degree count grew between 2010 and 2020",
  nat_degrees$value[nat_degrees$year == 2020] >
  nat_degrees$value[nat_degrees$year == 2010]
)

nat_inst <- aggregate(value ~ year,
  df[df$variable == "inst_count", ], FUN = sum, na.rm = TRUE)

check("National institution count is plausible (4,000-10,000 total per year)",
  all(nat_inst$value >= 4000 & nat_inst$value <= 10000)
)


# 8. Spot check: Grafton County NH (Dartmouth) ---------------------------------

cat(sprintf("\n--- 8. Spot check: %s ---\n", SPOT_NAME))

grafton <- df[df$geoid == SPOT_GEOID, ]

check("Grafton County present in all expected years",
  all(EXPECTED_YEARS %in% unique(grafton$year)),
  sprintf("Missing years: %s",
    paste(setdiff(EXPECTED_YEARS, unique(grafton$year)), collapse = ", "))
)

check("Grafton County has exactly 2 institutions in 2023",
  grafton$value[grafton$year == 2023 & grafton$variable == "inst_count"] == 2
)

check("Grafton County 2023: doctoral share > 0 (Dartmouth)",
  grafton$value[grafton$year == 2023 & grafton$variable == "share_degrees_doctoral"] > 0
)

check("Grafton County 2023: no associate degrees (no community college)",
  grafton$value[grafton$year == 2023 & grafton$variable == "share_degrees_assoc"] == 0
)

check("Grafton County 2023: grad rate present and > 0.5",
  {
    gr <- grafton$value[grafton$year == 2023 & grafton$variable == "grad_rate_150pct"]
    length(gr) == 1 && gr > 0.5
  }
)


# 9. Institution-level smoke test -- one query per survey ---------------------

cat("\n--- 9. Institution-level checks ---\n")

for (sv in IPEDS_SURVEYS) {
  ok <- tryCatch({
    inst <- get_ipeds(geography = "institution", surveys = sv,
      s3_bucket      = S3_BUCKET,
      s3_path_prefix = S3_PREFIX
    )
    cat(sprintf("  %-32s rows: %s  cols: %d  years: %s-%s\n",
                paste0(sv, ":"),
                format(nrow(inst), big.mark = ","),
                ncol(inst),
                min(inst$year),
                max(inst$year)))
    nrow(inst) > 0
  }, error = function(e) {
    cat(sprintf("  ERROR reading %s: %s\n", sv, conditionMessage(e)))
    FALSE
  })
  check(sprintf("institution-grain read returns rows for %s", sv), ok)
}


# 9b. Completers coverage ----------------------------------------------------

cat("\n--- 9b. Completers coverage ---\n")

check("Completer variables present for 2012 onward",
  {
    yrs <- unique(df$year[df$variable == "count_students_bach"])
    all(intersect(EXPECTED_YEARS, 2012:max(EXPECTED_YEARS)) %in% yrs)
  },
  "count_students_bach missing for some year from 2012 on"
)

check("Completer variables absent before 2012 (NCES did not publish C_C)",
  !any(df$year[df$variable %in% COMPLETER_VARS] < 2012),
  "completer rows found before 2012 -- NCES published no C{year}_C then"
)

check("Degree-level completers do not exceed degrees conferred",
  {
    # A student can earn two degrees at one level, so completers <= degrees
    # within a county-year at the matching level.
    deg <- df[df$variable == "count_degrees_total", c("geoid", "year", "value")]
    names(deg)[3] <- "degrees"
    stu <- stats::aggregate(
      df$value[df$variable %in% COMPLETER_VARS],
      by = list(geoid = df$geoid[df$variable %in% COMPLETER_VARS],
                year  = df$year[df$variable %in% COMPLETER_VARS]),
      FUN = sum, na.rm = TRUE
    )
    names(stu)[3] <- "students"
    m <- merge(deg, stu, by = c("geoid", "year"))
    # Cross-level summing overcounts students, so allow headroom; this is a
    # smoke test for an order-of-magnitude error, not an identity.
    nrow(m) > 0 && mean(m$students <= m$degrees * 1.5) > 0.95
  },
  "summed degree-level completers look implausible against count_degrees_total"
)


# 10. Regression guards ------------------------------------------------------
#
# Both defects these catch produced values that passed every range check:
# grad rates sat at exactly 1.0 (plausible-looking, in [0, 1]) because the
# aggregation summed a categorical column, and degree counts were ~2.05x too
# high because NCES grand-total rows and second majors were summed alongside
# the detail rows.

cat("\n--- 10. Regression guards ---\n")

gr_rate <- df[df$variable == "grad_rate_150pct", ]

check("grad_rate_150pct is not degenerate at 1.0",
  {
    nrow(gr_rate) > 0 && mean(gr_rate$value == 1, na.rm = TRUE) < 0.05
  },
  sprintf("%.1f%% of county-years are exactly 1.0 -- the aggregation is probably summing a category code, not a count",
          100 * mean(gr_rate$value == 1, na.rm = TRUE))
)

check("grad rate agg_var carries a positive adjusted cohort",
  nrow(gr_rate) > 0 && all(gr_rate$agg_var > 0, na.rm = TRUE) &&
    !all(is.na(gr_rate$agg_var)),
  "agg_var should hold the adjusted cohort size so the completer count is recoverable as value * agg_var"
)

for (yr in intersect(EXPECTED_YEARS, unique(df$year))) {
  national <- sum(df$value[df$variable == "count_degrees_total" & df$year == yr],
                  na.rm = TRUE)
  # Observed range across 2010-2024 is 3.41M (2010) to 4.21M (2021) -- real
  # growth in degree production, so the band has to span it. It still catches
  # the defect it exists for: double-counting put 2022 at 9.4M.
  check(sprintf("count_degrees_total national total is plausible for %d", yr),
    national > 3.0e6 && national < 6e6,
    sprintf("got %s; expected roughly 3.4-4.3M degrees (associate through doctoral). Over ~6M means CIPCODE 99 grand totals or second majors are being summed.",
            format(national, big.mark = ","))
  )
}


# 11. Codebook integrity ----------------------------------------------------
#
# The codebook drives renaming, column selection and the public documentation,
# so a drift between it and what actually lands on S3 is silent and
# user-visible. These checks compare the two directly rather than trusting
# either one.

cat("\n--- 11. Codebook integrity ---\n")

cb <- tryCatch(get_ipeds_codebook(), error = function(e) NULL)

check("get_ipeds_codebook() loads", !is.null(cb))

if (!is.null(cb)) {

  # -- county variables: codebook vs what is actually published -------------
  published_vars <- sort(unique(df$variable))
  cb_county      <- sort(unique(cb$variable[cb$level == "county"]))
  check("Every county variable in the codebook is published",
    length(setdiff(cb_county, published_vars)) == 0,
    sprintf("in codebook, never published: %s",
            paste(setdiff(cb_county, published_vars), collapse = ", "))
  )
  check("Every published county variable is in the codebook",
    length(setdiff(published_vars, cb_county)) == 0,
    sprintf("published, undocumented: %s",
            paste(setdiff(published_vars, cb_county), collapse = ", "))
  )

  # -- institution columns: codebook vs each survey's wide output -----------
  DERIVED_IC_FLAGS <- c("is_public", "is_nonprofit", "is_forprofit",
                        "is_4yr", "is_2yr", "is_degree_granting",
                        "is_hbcu", "is_tribal")

  for (sv in IPEDS_SURVEYS) {
    inst <- tryCatch(
      get_ipeds(geography = "institution", surveys = sv, years = latest_year,
                s3_bucket = S3_BUCKET, s3_path_prefix = S3_PREFIX),
      error = function(e) NULL
    )
    if (is.null(inst) || nrow(inst) == 0) {
      # grad rates lag a year, so the latest vintage may legitimately be empty
      cat(sprintf("  SKIP  %s: no %d data to compare\n", sv, latest_year))
      next
    }
    got <- setdiff(names(inst), c("year", "survey", DERIVED_IC_FLAGS))
    expected <- cb$variable[(cb$survey == sv | cb$level == "both") &
                              cb$level != "county"]
    check(sprintf("%s institution columns match the codebook", sv),
      setequal(got, expected),
      sprintf("codebook only: %s | output only: %s",
              paste(setdiff(expected, got), collapse = ", "),
              paste(setdiff(got, expected), collapse = ", "))
    )
  }

  # -- declared units vs actual column types -------------------------------
  comp <- tryCatch(
    get_ipeds(geography = "institution", surveys = "completions",
              years = latest_year, s3_bucket = S3_BUCKET,
              s3_path_prefix = S3_PREFIX),
    error = function(e) NULL
  )
  if (!is.null(comp) && nrow(comp) > 0) {
    check("cipcode is stored as character, as the codebook declares",
      is.character(comp$cipcode),
      "numeric cipcode drops the leading zero on the 01-09 CIP families and breaks the SOC crosswalk join"
    )
    unit_ok <- vapply(c("major_num", "ed_level", "count_total_students"),
      function(v) {
        u <- cb$unit[cb$variable == v & cb$survey == "completions"][1]
        !grepl("character", u) || is.character(comp[[v]])
      }, logical(1))
    check("Declared units match actual column types", all(unit_ok))
  }

  # -- notes must not reference an API that no longer exists ----------------
  STALE <- c("get_ipeds_county", "get_ipeds_institution", "inst/extdata",
             "cohort_size", "load_codebook")
  stale_hits <- unlist(lapply(STALE, function(pat)
    cb$variable[grepl(pat, cb$notes, fixed = TRUE)]))
  check("Codebook notes contain no stale API references",
    length(stale_hits) == 0,
    sprintf("stale references in: %s", paste(unique(stale_hits), collapse = ", "))
  )

  # -- every variable is actually documented --------------------------------
  check("Every variable has a label, unit and notes",
    all(nzchar(cb$label)) && all(nzchar(cb$unit)) && all(nzchar(cb$notes))
  )

  # -- coverage claims in notes vs published year ranges --------------------
  coverage_claim <- function(variable, first_year) {
    yrs <- unique(df$year[df$variable == variable])
    if (!length(yrs)) return(FALSE)
    min(yrs) == first_year
  }
  check("Completer variables start in the year the codebook claims",
    coverage_claim("count_students_bach", COMPLETERS_START_YEAR),
    sprintf("count_students_bach should start at %d", COMPLETERS_START_YEAR)
  )
  check("Degree variables start in the package's first year",
    coverage_claim("count_degrees_total", IPEDS_START_YEAR),
    sprintf("count_degrees_total should start at %d", IPEDS_START_YEAR)
  )
}


# Summary ---------------------------------------------------------------------

cat(sprintf("\n%s\n", strrep("=", 50)))
cat(sprintf("  %d passed  |  %d failed  |  %d total\n",
            pass, fail, pass + fail))
cat(sprintf("%s\n\n", strrep("=", 50)))

if (fail > 0 && !interactive()) quit(status = 1)

}) # end local()
