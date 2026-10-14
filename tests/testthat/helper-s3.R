# Shared helper for tests that need real S3 access. Skips gracefully rather
# than failing when no network/credentials are available (e.g. CRAN, offline
# development, CI without AWS access) -- these are integration tests, not
# something every environment running R CMD check is expected to satisfy.
skip_if_no_s3 <- function(bucket = "cori.data.ipeds") {
  testthat::skip_if_offline()

  con <- tryCatch(
    cori.data.s3::connect_to_s3(bucket),
    error = function(e) NULL
  )
  if (is.null(con)) {
    testthat::skip("No S3 access available (network or credentials)")
  }
  DBI::dbDisconnect(con, shutdown = TRUE)
  invisible(TRUE)
}
