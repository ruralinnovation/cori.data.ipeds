# data-raw/build_cip_soc_crosswalk.R
#
# Builds the two CIP-to-SOC crosswalk .rds files shipped in inst/extdata/.
# Run this to refresh them when NCES publishes a new crosswalk vintage:
#
#   devtools::load_all(); source("data-raw/build_cip_soc_crosswalk.R")
#
# Requires readxl (Suggests). The .rds files are version-controlled, so
# consumers never run this -- get_cip_soc_crosswalk() just reads them.
#
# Sources (NCES CIP resources: https://nces.ed.gov/ipeds/cipcode/resources.aspx)
#
#   CIP 2020 -> SOC 2018
#     https://nces.ed.gov/ipeds/cipcode/Files/CIP2020_SOC2018_Crosswalk.xlsx
#     Eight sheets. "CIP-SOC" is the authoritative full relation; "SOC-CIP"
#     is the same relation keyed the other way but is NOT identical -- it
#     omits four pairs for CIP 03.0204 (Natural Resource Economics), so we
#     read CIP-SOC only. "New CIP", "New SOC" and "Added Matches" are
#     subsets of CIP-SOC documenting what changed from the previous vintage,
#     so including them would duplicate rows. "Unmatched CIP Codes" lists
#     CIP codes with no SOC match, carried in with soc_code = NA so a left
#     join from completions never silently drops a program.
#
#   CIP 2010 -> SOC 2010
#     https://nces.ed.gov/ipeds/cipcode/Files/FINALCIPtoSOCcrosswalk_022811.xls
#     Legacy .xls, single populated sheet, three title rows above the header.
#
# Which vintage to use depends on the completions year: NCES moved to the
# CIP 2020 taxonomy in 2020, so use the 2010 crosswalk for completions years
# 2010-2019 and the 2020 crosswalk from 2020 on. See the `notes` in
# get_cip_soc_crosswalk()'s documentation.

if (!requireNamespace("readxl", quietly = TRUE)) {
  stop("readxl is required to rebuild the crosswalks: install.packages('readxl')")
}

URL_2020 <- "https://nces.ed.gov/ipeds/cipcode/Files/CIP2020_SOC2018_Crosswalk.xlsx"
URL_2010 <- "https://nces.ed.gov/ipeds/cipcode/Files/FINALCIPtoSOCcrosswalk_022811.xls"

OUT_DIR <- file.path("inst", "extdata")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

# NCES uses these sentinels for "no match found" in both directions.
NO_MATCH_SOC <- "99-9999"
NO_MATCH_CIP <- "99.9999"


# Normalise a CIP code to the canonical zero-padded "xx.xxxx" string, matching
# what reconcile_completions_vintage() produces for the completions table.
# Handles both character input (already formatted) and numeric input (Excel
# may hand back 1 for "01.0000").
.norm_cip <- function(x) {
  x <- trimws(as.character(x))
  n <- suppressWarnings(as.numeric(x))
  ifelse(is.na(n), NA_character_, sprintf("%07.4f", n))
}

.norm_soc <- function(x) trimws(as.character(x))


# Download to a temp file and read one sheet.
.read_remote_sheet <- function(url, ext, sheet, skip = 0) {
  fp <- tempfile(fileext = ext)
  on.exit(unlink(fp), add = TRUE)
  utils::download.file(url, fp, mode = "wb", quiet = FALSE)
  readxl::read_excel(fp, sheet = sheet, skip = skip, col_types = "text")
}


# -- CIP 2020 -> SOC 2018 -----------------------------------------------------

message("Building CIP2020 -> SOC2018 crosswalk...")

fp_2020 <- tempfile(fileext = ".xlsx")
utils::download.file(URL_2020, fp_2020, mode = "wb", quiet = FALSE)

main_2020 <- readxl::read_excel(fp_2020, sheet = "CIP-SOC", col_types = "text")
unmatched_2020 <- readxl::read_excel(fp_2020, sheet = "Unmatched CIP Codes",
                                     col_types = "text")
unlink(fp_2020)

cip_soc_2020 <- data.frame(
  cip_code    = .norm_cip(c(main_2020$CIP2020Code,  unmatched_2020$CIP2020Code)),
  cip_title   = trimws(c(main_2020$CIP2020Title, unmatched_2020$CIP2020Title)),
  soc_code    = .norm_soc(c(main_2020$SOC2018Code,  unmatched_2020$SOC2018Code)),
  soc_title   = trimws(c(main_2020$SOC2018Title, unmatched_2020$SOC2018Title)),
  cip_vintage = 2020L,
  soc_vintage = 2018L,
  stringsAsFactors = FALSE
)

# NO MATCH rows become explicit NAs rather than a magic code
no_match <- !is.na(cip_soc_2020$soc_code) & cip_soc_2020$soc_code == NO_MATCH_SOC
cip_soc_2020$soc_code[no_match]  <- NA_character_
cip_soc_2020$soc_title[no_match] <- NA_character_

cip_soc_2020 <- unique(cip_soc_2020)
cip_soc_2020 <- cip_soc_2020[order(cip_soc_2020$cip_code, cip_soc_2020$soc_code), ]
rownames(cip_soc_2020) <- NULL

saveRDS(cip_soc_2020, file.path(OUT_DIR, "cip_soc_2020.rds"), compress = "xz")
message(sprintf("  %s rows, %s CIP codes, %s SOC codes -> inst/extdata/cip_soc_2020.rds",
                format(nrow(cip_soc_2020), big.mark = ","),
                length(unique(cip_soc_2020$cip_code)),
                length(unique(stats::na.omit(cip_soc_2020$soc_code)))))


# -- CIP 2010 -> SOC 2010 -----------------------------------------------------

message("Building CIP2010 -> SOC2010 crosswalk...")

raw_2010 <- .read_remote_sheet(URL_2010, ".xls", sheet = 1, skip = 3)
names(raw_2010) <- trimws(names(raw_2010))

cip_soc_2010 <- data.frame(
  cip_code    = .norm_cip(raw_2010[["CIP2010 Code"]]),
  cip_title   = trimws(raw_2010[["CIP2010Title"]]),
  soc_code    = .norm_soc(raw_2010[["SOC2010Code"]]),
  soc_title   = trimws(raw_2010[["SOC2010Title"]]),
  cip_vintage = 2010L,
  soc_vintage = 2010L,
  stringsAsFactors = FALSE
)

no_match <- !is.na(cip_soc_2010$soc_code) &
  cip_soc_2010$soc_code %in% c(NO_MATCH_SOC, NO_MATCH_CIP)
cip_soc_2010$soc_code[no_match]  <- NA_character_
cip_soc_2010$soc_title[no_match] <- NA_character_

cip_soc_2010 <- cip_soc_2010[!is.na(cip_soc_2010$cip_code), ]
cip_soc_2010 <- unique(cip_soc_2010)
cip_soc_2010 <- cip_soc_2010[order(cip_soc_2010$cip_code, cip_soc_2010$soc_code), ]
rownames(cip_soc_2010) <- NULL

saveRDS(cip_soc_2010, file.path(OUT_DIR, "cip_soc_2010.rds"), compress = "xz")
message(sprintf("  %s rows, %s CIP codes, %s SOC codes -> inst/extdata/cip_soc_2010.rds",
                format(nrow(cip_soc_2010), big.mark = ","),
                length(unique(cip_soc_2010$cip_code)),
                length(unique(stats::na.omit(cip_soc_2010$soc_code)))))

message("\nDone. Remember: *.rds is gitignored, so commit with `git add -f`.")
