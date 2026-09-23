# Post-ETL validation for cori.data.ipeds
#
# Reads directly from S3 via DuckDB and runs a battery of checks against the
# data_county and data_institution layers. Designed to be run after
# write_ipeds_all() completes (maintainer-only; see data-raw/refresh_ipeds.R).
#
# Usage (either works):
#   devtools::load_all(); source("data-raw/validate_etl.R")
#   Rscript data-raw/validate_etl.R
#
# Requirements: DBI, duckdb, AWS credentials in environment or ~/.aws/config

library(DBI)
library(duckdb)

local({

S3_BUCKET      <- "cori.data.ipeds"
S3_PREFIX      <- ""
EXPECTED_YEARS <- 2010:2024
EXPECTED_VARS  <- c(
  # IC
  "inst_count", "public_inst_count", "nonprofit_inst_count",
  "fouryear_inst_count", "twoyear_inst_count", "hbcu_count", "tribal_count",
  # Completions
  "count_degrees_total",
  "share_degrees_assoc", "share_degrees_bach",
  "share_degrees_masters", "share_degrees_doctoral",
  "share_degrees_men", "share_degrees_women",
  # Grad rates (not available for the most recent year -- NCES lag)
  "grad_rate_150pct", "transfer_out_rate"
)
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

con <- dbConnect(duckdb())
on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)

dbExecute(con, "INSTALL httpfs; LOAD httpfs;")
dbExecute(con, "INSTALL aws;   LOAD aws;")
dbExecute(con, sprintf("SET temp_directory = '%s';", tempdir()))
dbExecute(con, "CREATE OR REPLACE SECRET s3_secret (
  TYPE S3,
  PROVIDER CREDENTIAL_CHAIN,
  CHAIN 'env;config',
  REGION 'us-east-1',
  URL_STYLE 'path'
);")

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
non_gr_vars  <- setdiff(EXPECTED_VARS, GR_VARS)
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

for (sv in c("institutional_characteristics", "completions", "grad_rates")) {
  ok <- tryCatch({
    inst <- get_ipeds_institution(
      survey         = sv,
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
  check(sprintf("get_ipeds_institution() returns rows for %s", sv), ok)
}


# Summary ---------------------------------------------------------------------

cat(sprintf("\n%s\n", strrep("=", 50)))
cat(sprintf("  %d passed  |  %d failed  |  %d total\n",
            pass, fail, pass + fail))
cat(sprintf("%s\n\n", strrep("=", 50)))

if (fail > 0 && !interactive()) quit(status = 1)

}) # end local()
