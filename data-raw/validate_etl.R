# data-raw/validate_etl.R
#
# Post-ETL validation checks. Run after write_ipeds_processed_to_s3() completes
# to confirm the S3 data is complete, internally consistent, and sensible.
#
# Usage:
#   devtools::load_all()
#   source("data-raw/validate_etl.R")

library(dplyr)

S3_BUCKET  <- "cori.data.ipeds"
S3_PREFIX  <- ""
SPOT_GEOID <- "33009"   # Grafton County NH
EXPECTED_YEARS <- 2010:as.integer(format(Sys.Date(), "%Y")) - 1L

cat("==========================================================\n")
cat("  cori.data.ipeds -- ETL Validation\n")
cat("  Run date:", format(Sys.time(), "%Y-%m-%d %H:%M"), "\n")
cat("==========================================================\n\n")


# ------------------------------------------------------------------
# 1. Manifest completeness
# ------------------------------------------------------------------
cat("--- 1. Manifest ---\n")

manifest <- get_ipeds_manifest(S3_BUCKET, S3_PREFIX)
cat("Total manifest rows:", nrow(manifest), "\n")

expected_datasets <- c("ic_institution", "completions_institution",
                       "grad_rates_institution", "county")

for (yr in EXPECTED_YEARS) {
  done <- manifest$dataset[manifest$year == yr]
  missing <- setdiff(expected_datasets, done)
  if (length(missing) > 0) {
    cat(sprintf("  MISSING year=%d: %s\n", yr, paste(missing, collapse = ", ")))
  }
}

years_in_manifest <- sort(unique(manifest$year[manifest$dataset == "county"]))
cat("County years in manifest:", paste(range(years_in_manifest), collapse = "-"), "\n")
cat("Total county years:", length(years_in_manifest), "\n\n")


# ------------------------------------------------------------------
# 2. Read county data
# ------------------------------------------------------------------
cat("--- 2. County data ---\n")

co <- read_ipeds_county_from_s3(s3_bucket = S3_BUCKET, s3_path_prefix = S3_PREFIX)

cat("Total rows:", format(nrow(co), big.mark = ","), "\n")
cat("Years present:", paste(range(co$year), collapse = "-"),
    paste0("(", length(unique(co$year)), " years)"), "\n")
cat("Counties:", format(length(unique(co$geoid)), big.mark = ","), "\n")
cat("Variables:", paste(sort(unique(co$variable)), collapse = ", "), "\n\n")


# ------------------------------------------------------------------
# 3. Variable completeness -- all variables present in all years
# ------------------------------------------------------------------
cat("--- 3. Variable completeness by year ---\n")

cb <- get_ipeds_codebook()
expected_vars <- cb$variable

var_by_year <- co |>
  group_by(year) |>
  summarise(vars_present = list(unique(variable)), .groups = "drop") |>
  mutate(
    n_vars   = lengths(vars_present),
    missing  = sapply(vars_present, function(v) {
      m <- setdiff(expected_vars, v)
      if (length(m) == 0) "" else paste(m, collapse = ", ")
    })
  )

missing_vars <- var_by_year |> filter(missing != "")
if (nrow(missing_vars) == 0) {
  cat("All", length(expected_vars), "expected variables present in every year.\n\n")
} else {
  cat("WARNING -- missing variables by year:\n")
  print(missing_vars |> select(year, n_vars, missing))
  cat("\n")
}


# ------------------------------------------------------------------
# 4. Value range checks
# ------------------------------------------------------------------
cat("--- 4. Value range checks ---\n")

# Shares must be 0-1
share_vars <- cb$variable[cb$unit == "share 0-1"]
share_issues <- co |>
  filter(variable %in% share_vars, !is.na(value)) |>
  filter(value < 0 | value > 1)

if (nrow(share_issues) == 0) {
  cat("Share variables: all values in [0, 1].\n")
} else {
  cat(sprintf("WARNING -- %d share values outside [0, 1]:\n", nrow(share_issues)))
  print(share_issues |> arrange(desc(abs(value - 0.5))) |> head(10))
}

# Rates must be 0-1
rate_vars <- cb$variable[cb$unit == "rate 0-1"]
rate_issues <- co |>
  filter(variable %in% rate_vars, !is.na(value)) |>
  filter(value < 0 | value > 1)

if (nrow(rate_issues) == 0) {
  cat("Rate variables: all values in [0, 1].\n")
} else {
  cat(sprintf("WARNING -- %d rate values outside [0, 1]:\n", nrow(rate_issues)))
  print(rate_issues |> head(10))
}

# Counts must be non-negative
count_vars <- cb$variable[cb$unit == "count"]
count_issues <- co |>
  filter(variable %in% count_vars, !is.na(value)) |>
  filter(value < 0)

if (nrow(count_issues) == 0) {
  cat("Count variables: no negative values.\n")
} else {
  cat(sprintf("WARNING -- %d negative count values:\n", nrow(count_issues)))
  print(count_issues |> head(10))
}
cat("\n")


# ------------------------------------------------------------------
# 5. Degree shares sum to 1
# ------------------------------------------------------------------
cat("--- 5. Degree share sums ---\n")

level_share_vars <- c("share_degrees_assoc", "share_degrees_bach",
                      "share_degrees_masters", "share_degrees_doctoral")

share_sums <- co |>
  filter(variable %in% level_share_vars) |>
  group_by(geoid, year) |>
  summarise(share_sum = sum(value, na.rm = TRUE), n_vars = n(), .groups = "drop") |>
  filter(n_vars == 4)   # only where all four are present

sum_issues <- share_sums |> filter(abs(share_sum - 1) > 0.001)

cat(sprintf("County-years with all 4 level shares: %s\n",
            format(nrow(share_sums), big.mark = ",")))

if (nrow(sum_issues) == 0) {
  cat("All level share sums are within 0.001 of 1.0.\n\n")
} else {
  cat(sprintf("WARNING -- %d county-years where shares don't sum to 1:\n",
              nrow(sum_issues)))
  print(sum_issues |> arrange(desc(abs(share_sum - 1))) |> head(10))
  cat("\n")
}


# ------------------------------------------------------------------
# 6. No sentinel geoids (IPEDS negative-code artifacts)
# ------------------------------------------------------------------
cat("--- 6. GEOID validity ---\n")

bad_geoids <- co |>
  filter(!grepl("^[0-9]{5}$", geoid)) |>
  distinct(geoid)

if (nrow(bad_geoids) == 0) {
  cat("All geoids are valid 5-digit FIPS codes.\n\n")
} else {
  cat(sprintf("WARNING -- %d non-standard geoids found:\n", nrow(bad_geoids)))
  print(bad_geoids)
  cat("\n")
}


# ------------------------------------------------------------------
# 7. Spot check -- Grafton County NH (33009)
# ------------------------------------------------------------------
cat(sprintf("--- 7. Spot check: geoid %s ---\n", SPOT_GEOID))

spot <- co |> filter(geoid == SPOT_GEOID)

cat("Years present:", paste(range(spot$year), collapse = "-"),
    paste0("(", length(unique(spot$year)), " years)"), "\n")

# Latest year detail
latest_yr <- max(spot$year)
cat(sprintf("\nLatest year (%d):\n", latest_yr))
spot |>
  filter(year == latest_yr) |>
  select(variable, value, agg_var, survey) |>
  arrange(survey, variable) |>
  print()
cat("\n")


# ------------------------------------------------------------------
# 8. Institution-level smoke tests -- one query per survey
# ------------------------------------------------------------------
cat("--- 8. Institution-level checks ---\n")

for (sv in c("ic", "completions", "grad_rates")) {
  tryCatch({
    inst <- read_ipeds_institution_from_s3(
      survey         = sv,
      s3_bucket      = S3_BUCKET,
      s3_path_prefix = S3_PREFIX
    )
    cat(sprintf("  %-25s rows: %s  cols: %d  years: %s-%s\n",
                paste0(sv, ":"),
                format(nrow(inst), big.mark = ","),
                ncol(inst),
                min(inst$year),
                max(inst$year)))
  }, error = function(e) {
    cat(sprintf("  ERROR reading %s: %s\n", sv, conditionMessage(e)))
  })
}
cat("\n")


# ------------------------------------------------------------------
# 9. Row count trend (county) -- flag big year-over-year swings
# ------------------------------------------------------------------
cat("--- 9. County row count by year ---\n")

row_counts <- co |>
  group_by(year) |>
  summarise(rows = n(), counties = n_distinct(geoid), .groups = "drop") |>
  arrange(year) |>
  mutate(row_chg_pct = round((rows / lag(rows) - 1) * 100, 1))

print(as.data.frame(row_counts))

big_swings <- row_counts |> filter(!is.na(row_chg_pct), abs(row_chg_pct) > 10)
if (nrow(big_swings) > 0) {
  cat("\nNOTE -- years with >10% row count change from prior year:\n")
  print(as.data.frame(big_swings))
}

cat("\n==========================================================\n")
cat("  Validation complete.\n")
cat("==========================================================\n")
