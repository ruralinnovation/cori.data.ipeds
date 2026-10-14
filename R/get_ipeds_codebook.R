# IPEDS variable codebook
#
# The codebook is the single source of truth for this package. It drives three
# things, so a change here propagates through the whole pipeline:
#
#   1. Renaming  -- apply_codebook_mapping() maps `raw_variable` (the NCES
#                   column name) to `variable` (the canonical snake_case name).
#   2. Selection -- .select_codebook_columns() keeps only columns defined here,
#                   so an unmapped NCES column never reaches the output.
#   3. Docs      -- get_ipeds_codebook() is the public variable reference.
#
# Adding a variable to the output therefore means adding a row here, not
# editing the processing code.
#
# Columns follow the cori.data family convention (`variable`, `raw_variable`,
# `label`, `unit`, `notes`) plus two this package needs to drive the ETL --
# `survey` and `level` -- and one IPEDS needs because so much of it is
# categorical: `codes`.
#
# The family's `nominal` column is deliberately omitted. It is undocumented
# everywhere it appears and used inconsistently -- cori.data.bps marks a count
# of building permits TRUE, while cori.data.qcew, the one package with a real
# dollar variable, has no such column at all. Nothing in IPEDS is monetary, so
# here it would be FALSE on every row: no information, and an invitation to
# read meaning into it.
#
#   survey -- "institutional_characteristics", "completions", or "grad_rates"
#   level  -- "institution" (wide per-institution output), "county" (derived
#             tidy aggregation), or "both" (join key present in every table)
#
# `raw_variable` is empty for county-level variables: they are derived by
# process_county.R, not read from an NCES column.
#
# Rows are built one variable at a time rather than as parallel column
# vectors. With 48 variables and long notes, parallel vectors can silently
# shift out of alignment; this way each variable's attributes stay together.


# Row constructor -------------------------------------------------------------

.cb_row <- function(variable, raw_variable, label, unit, survey, level, notes,
                    codes = "") {
  data.frame(
    variable     = variable,
    raw_variable = raw_variable,
    label        = label,
    unit         = unit,
    survey       = survey,
    level        = level,
    notes        = notes,
    codes        = codes,
    stringsAsFactors = FALSE
  )
}


# Value labels for encoded variables ------------------------------------------
#
# Collapses code/label pairs into one "1 = Public; 2 = Private" string so an
# encoded variable's meaning travels in the codebook row itself rather than in
# a separate lookup table.
#
# Labels are transcribed from the NCES data dictionary workbooks shipped
# alongside the data files (the Frequencies sheet of HD2023_Dict.xlsx,
# C2023_A_Dict.xlsx, C2023_C_Dict.xlsx and GR2023_Dict.xlsx). Only codes that
# actually occur in this package's 2010-present output are listed; NCES
# documents some aggregate codes that its downloadable files do not contain.
#
# NCES sentinel values -1, -2 and -3 ("not reported", "not applicable", "not
# available") are converted to NA by .replace_sentinel_codes() during the ETL,
# so they are deliberately absent here.

.codes <- function(...) {
  kv <- c(...)
  paste(sprintf("%s = %s", names(kv), unname(kv)), collapse = "; ")
}


#' Get the cori.data.ipeds variable codebook
#'
#' Returns documentation for every variable available via
#' [get_ipeds()] and [get_ipeds()]. Covers the three IPEDS
#' surveys this package harmonizes: Institutional Characteristics, Completions,
#' and Graduation Rates, 2010 to present.
#'
#' Use `level` to separate the two output levels: `"institution"` variables
#' appear in [get_ipeds()]'s institution-level output, `"county"` variables in
#' [get_ipeds()]'s tidy output, and `"both"` marks the join keys present
#' in every table.
#'
#' `notes` records vintage caveats -- which years a variable covers, NCES
#' column renames, and taxonomy changes -- so cross-year comparability is
#' documented alongside the variable rather than in separate prose.
#'
#' Much of IPEDS is categorical, and the institution-level output returns
#' those columns as the bare integers NCES publishes. `codes` carries the
#' value labels for them, transcribed from the NCES data dictionary
#' workbooks, so a `sector_code` of 4 can be resolved without leaving the
#' package. Only codes that actually occur in this package's output are
#' listed. NCES sentinel values (-1, -2, -3) are converted to `NA` during the
#' ETL and so do not appear.
#'
#' @return A data frame with columns: `variable`, `raw_variable`, `label`,
#'   `unit`, `survey`, `level`, `notes`, `codes`.
#'   `raw_variable` is the original NCES column name, as stored in the
#'   `data_raw` layer on S3; it is empty for derived county-level variables.
#'   `codes` decodes the categorical variables -- a `"1 = Public; 2 =
#'   Private not-for-profit"` string -- and is empty for the rest.
#'
#' @seealso [get_ipeds()], [get_ipeds()]
#'
#' @examples
#' cb <- get_ipeds_codebook()
#'
#' # County-level variables only
#' cb[cb$level == "county", c("variable", "label", "unit")]
#'
#' # Which variables are categorical, and what do their numbers mean?
#' cb[nzchar(cb$codes), c("variable", "codes")]
#'
#' # Decode one
#' cb$codes[cb$variable == "sector_code"]
#'
#' @export
get_ipeds_codebook <- function() {

  ic <- "institutional_characteristics"

  rbind(

    # -- Join keys (present in every table) -----------------------------------

    .cb_row(
      "unitid", "UNITID", "Institution ID",
      "character (6-digit zero-padded)", ic, "both",
      paste0(
        "Unique six-digit IPEDS identifier for each institution. Stable ",
        "across years and surveys -- use as the join key across all IPEDS ",
        "tables. Zero-padded to six characters so leading zeros survive. ",
        "Coverage: 2010-present. Cross-referenceable with College Scorecard ",
        "and NSLDS."
      )
    ),
    .cb_row(
      "geoid", "COUNTYCD", "County GEOID",
      "character (5-digit zero-padded)", ic, "both",
      paste0(
        "Five-digit county FIPS code (state + county), zero-padded. Named ",
        "geoid to match the rest of the cori.data family. On the ",
        "completions, completers and grad_rates tables this is joined from ",
        "the ",
        "institutional_characteristics file for the same year, keyed on ",
        "unitid. Not available before 2009, so pre-2010 backfill would need ",
        "a ZIP-to-county crosswalk. Coverage: 2010-present. Joins directly ",
        "to geoid in cori.data.pep, cori.data.qcew, and other county-level ",
        "CORI datasets."
      )
    ),

    # -- Institutional Characteristics: identity and location -----------------

    .cb_row(
      "inst_name", "INSTNM", "Institution name",
      "character", ic, "institution",
      "Legal name of the institution as reported to IPEDS. Coverage: 2010-present."
    ),
    .cb_row(
      "county_name", "COUNTYNM", "County name",
      "character", ic, "institution",
      paste0(
        "Name of the county in which the institution is located. Not ",
        "available before 2009. Coverage: 2010-present."
      )
    ),
    .cb_row(
      "st_abbr", "STABBR", "State abbreviation",
      "character", ic, "institution",
      "Two-letter postal abbreviation for the institution's state. Coverage: 2010-present."
    ),
    .cb_row(
      "city", "CITY", "City",
      "character", ic, "institution",
      "City in which the institution is located. Coverage: 2010-present."
    ),
    .cb_row(
      "address", "ADDR", "Street address",
      "character", ic, "institution",
      "Street address or post office box as reported to IPEDS. Coverage: 2010-present."
    ),
    .cb_row(
      "zipcode", "ZIP", "ZIP code",
      "character", ic, "institution",
      "ZIP code of the institution. Coverage: 2010-present."
    ),
    .cb_row(
      "latitude", "LATITUDE", "Latitude",
      "numeric (decimal degrees)", ic, "institution",
      paste0(
        "Latitude of the institution in decimal degrees. Use with longitude ",
        "to assign institutions to any geography (CBSA, rural-urban ",
        "classification, custom regions). Not available before 2009. ",
        "Coverage: 2010-present."
      )
    ),
    .cb_row(
      "longitude", "LONGITUD", "Longitude",
      "numeric (decimal degrees)", ic, "institution",
      paste0(
        "Longitude of the institution in decimal degrees. Use with latitude ",
        "to assign institutions to any geography. Not available before 2009. ",
        "Coverage: 2010-present."
      )
    ),

    # -- Institutional Characteristics: classification ------------------------

    .cb_row(
      "sector_code", "SECTOR", "Sector code",
      "integer (1-9; 0 = admin; 99 = unknown)", ic, "institution",
      codes = .codes(
        "0" = "Administrative unit only",
        "1" = "Public, 4-year or above",
        "2" = "Private not-for-profit, 4-year or above",
        "3" = "Private for-profit, 4-year or above",
        "4" = "Public, 2-year",
        "5" = "Private not-for-profit, 2-year",
        "6" = "Private for-profit, 2-year",
        "7" = "Public, less-than-2-year",
        "8" = "Private not-for-profit, less-than-2-year",
        "9" = "Private for-profit, less-than-2-year",
        "99" = "Sector unknown (not active)"
      ),
      paste0(
        "Nine-category sector combining control (public / nonprofit / ",
        "for-profit) and level (4-year / 2-year / less-than-2-year). ",
        "Code 0 = administrative unit, 99 = not assigned; both are excluded ",
        "from county aggregations. Public = 1, 4, 7; nonprofit = 2, 5, 8; ",
        "for-profit = 3, 6, 9; four-year = 1, 2, 3; two-year = 4, 5, 6. ",
        "Coverage: 2010-present."
      )
    ),
    .cb_row(
      "funding_source_code", "CONTROL", "Funding source code",
      "integer (1-3)", ic, "institution",
      codes = .codes(
        "1" = "Public",
        "2" = "Private not-for-profit",
        "3" = "Private for-profit"
      ),
      paste0(
        "Control of institution: 1 = Public, 2 = Private nonprofit, ",
        "3 = Private for-profit. Coverage: 2010-present."
      )
    ),
    .cb_row(
      "inst_level_code", "ICLEVEL", "Institution level code",
      "integer (1-3)", ic, "institution",
      codes = .codes(
        "1" = "Four or more years",
        "2" = "At least 2 but less than 4 years",
        "3" = "Less than 2 years (below associate)"
      ),
      paste0(
        "Highest level of degree or certificate program offered: 1 = Four or ",
        "more years, 2 = At least two but less than four years, 3 = Less ",
        "than two years. Coverage: 2010-present."
      )
    ),
    .cb_row(
      "hbcu_code", "HBCU", "HBCU flag code",
      "integer (1-2)", ic, "institution",
      codes = .codes(
        "1" = "Yes",
        "2" = "No"
      ),
      paste0(
        "Whether the institution is a Historically Black College or ",
        "University. Defined by the Higher Education Act of 1965 as ",
        "amended: established prior to 1964, principal mission the ",
        "education of Black Americans, and accredited. Distinct from ",
        "land-grant status -- only 22 of the 102 HBCUs in 2023 are ",
        "land-grant institutions. Coverage: 2010-present."
      )
    ),
    .cb_row(
      "has_hospital_code", "HOSPITAL", "Hospital flag code",
      "integer (1-2)", ic, "institution",
      codes = .codes(
        "1" = "Yes",
        "2" = "No"
      ),
      "Whether the institution owns or operates a hospital. 1 = Yes, 2 = No. Coverage: 2010-present."
    ),
    .cb_row(
      "tribal_college_code", "TRIBAL", "Tribal college flag code",
      "integer (1-2)", ic, "institution",
      codes = .codes(
        "1" = "Yes",
        "2" = "No"
      ),
      paste0(
        "Whether the institution is one of the Tribal Colleges and ",
        "Universities. NCES defines these operationally rather than by ",
        "statute: tribally controlled and, with few exceptions, located on ",
        "reservations, and all members of the American Indian Higher ",
        "Education Consortium. Every tribal college also carries ",
        "land_grant_code = 1. Coverage: 2010-present."
      )
    ),
    .cb_row(
      "degree_granting_status_code", "DEGGRANT", "Degree-granting status code",
      "integer (1-2)", ic, "institution",
      codes = .codes(
        "1" = "Degree-granting",
        "2" = "Nondegree-granting, primarily postsecondary"
      ),
      paste0(
        "Whether the institution is degree-granting: 1 = Degree-granting, ",
        "2 = Non-degree-granting. All county-level aggregations in this ",
        "package are restricted to code 1, including the completions, ",
        "completers and grad_rates aggregations, which inherit this flag ",
        "by joining from ",
        "the institutional_characteristics file for the same year. ",
        "Coverage: 2010-present."
      )
    ),
    .cb_row(
      "carnegie_classification_code", "CARNEGIE", "Carnegie classification code",
      "integer", ic, "institution",
      codes = .codes(
        "15" = "Doctoral/Research Universities--Extensive",
        "16" = "Doctoral/Research Universities--Intensive",
        "21" = "Master's Colleges and Universities I",
        "22" = "Master's Colleges and Universities II",
        "31" = "Baccalaureate Colleges--Liberal Arts",
        "32" = "Baccalaureate Colleges--General",
        "33" = "Baccalaureate/Associate's Colleges",
        "40" = "Associate's Colleges",
        "51" = "Theological seminaries and other specialized faith-related institutions",
        "52" = "Medical schools and medical centers",
        "53" = "Other separate health profession schools",
        "54" = "Schools of engineering and technology",
        "55" = "Schools of business and management",
        "56" = "Schools of art, music, and design",
        "57" = "Schools of law",
        "58" = "Teachers colleges",
        "59" = "Other specialized institutions",
        "60" = "Tribal colleges"
      ),
      paste0(
        "2000 Carnegie Classification code, distinguishing research ",
        "universities, doctoral universities, master's colleges, ",
        "baccalaureate colleges, associate's colleges, and special-focus ",
        "institutions. Roughly half of all institution-years are NA: NCES ",
        "codes institutions outside the Carnegie universe (unaccredited or ",
        "nondegree-granting) as -2, which the ETL converts to NA. ",
        "NCES renamed this column from CARNEGIE (2010-2023) to C00CARNEGIE ",
        "in 2024; reconcile_ic_vintage() normalizes C00CARNEGIE back to ",
        "CARNEGIE so the mapping is consistent across vintages. Values are ",
        "unchanged by the rename. Coverage: 2010-present."
      )
    ),
    .cb_row(
      "highest_level_offered_code", "HLOFFER", "Highest level offered code",
      "integer (1-9)", ic, "institution",
      codes = .codes(
        "1" = "Award of less than one academic year",
        "2" = "At least 1 but less than 2 academic years",
        "3" = "Associate's degree",
        "4" = "At least 2 but less than 4 academic years",
        "5" = "Bachelor's degree",
        "6" = "Postbaccalaureate certificate",
        "7" = "Master's degree",
        "8" = "Post-master's certificate",
        "9" = "Doctor's degree"
      ),
      paste0(
        "Highest award level offered, from certificates of less than one ",
        "year (1) through doctoral degrees (9). Unlike ",
        "highest_degree_offered_code, this one is ordered: a larger value is ",
        "a higher award level. Coverage: 2010-present."
      )
    ),
    .cb_row(
      "highest_degree_offered_code", "HDEGOFR1", "Highest degree offered code",
      "integer (0; 11-14; 20; 30; 40)", ic, "institution",
      codes = .codes(
        "0" = "Non-degree granting",
        "11" = "Doctor's degree - research/scholarship and professional practice",
        "12" = "Doctor's degree - research/scholarship",
        "13" = "Doctor's degree - professional practice",
        "14" = "Doctor's degree - other",
        "20" = "Master's degree",
        "30" = "Bachelor's degree",
        "40" = "Associate's degree"
      ),
      paste0(
        "Highest degree offered. Note that the codes run in the opposite ",
        "direction to every other level variable here: higher numbers mean ",
        "lower degrees, so 40 is an associate's degree and 11-14 are ",
        "doctorates. Code 0 matches degree_granting_status_code = 2 exactly. ",
        "Coverage: 2010-present."
      )
    ),
    .cb_row(
      "undergrad_degree_offered_code", "UGOFFER", "Undergrad degree offered code",
      "integer (1-2)", ic, "institution",
      codes = .codes(
        "1" = "Undergraduate degree or certificate offering",
        "2" = "No undergraduate offering"
      ),
      paste0(
        "Whether the institution offers undergraduate degree or certificate ",
        "programs. 1 = Yes, 2 = No. Coverage: 2010-present."
      )
    ),
    .cb_row(
      "grad_degree_offered_code", "GROFFER", "Graduate degree offered code",
      "integer (1-2)", ic, "institution",
      codes = .codes(
        "1" = "Graduate degree or certificate offering",
        "2" = "No graduate offering"
      ),
      paste0(
        "Whether the institution offers graduate degree or certificate ",
        "programs. 1 = Yes, 2 = No. Coverage: 2010-present."
      )
    ),
    .cb_row(
      "urbanization_level_code", "LOCALE", "Urbanization level code",
      "integer (11-43)", ic, "institution",
      codes = .codes(
        "11" = "City: Large",
        "12" = "City: Midsize",
        "13" = "City: Small",
        "21" = "Suburb: Large",
        "22" = "Suburb: Midsize",
        "23" = "Suburb: Small",
        "31" = "Town: Fringe",
        "32" = "Town: Distant",
        "33" = "Town: Remote",
        "41" = "Rural: Fringe",
        "42" = "Rural: Distant",
        "43" = "Rural: Remote"
      ),
      paste0(
        "Degree of urbanization using the NCES urban-centric locale ",
        "classification, from large city (11) to remote rural (43). Aligns ",
        "with the locale framework used across CCD and other NCES surveys. ",
        "Coverage: 2010-present."
      )
    ),
    .cb_row(
      "land_grant_code", "LANDGRNT", "Land grant flag code",
      "integer (1-2)", ic, "institution",
      codes = .codes(
        "1" = "Land grant institution",
        "2" = "Not a land grant institution"
      ),
      paste0(
        "Whether the institution is a land-grant university. NCES defines ",
        "this as designation by a state legislature or Congress to receive ",
        "the benefits of the Morrill Acts of 1862 and 1890, but the flag in ",
        "the data is broader: all 35 tribal colleges carry it under the 1994 ",
        "land-grant designation, 29% of the 121 land-grant institutions in ",
        "2023. Land-grant institutions receive federal funding for ",
        "agriculture, engineering and mechanical arts research and are ",
        "disproportionately rural. Coverage: 2010-present."
      )
    ),
    .cb_row(
      "institution_size_code", "INSTSIZE", "Institution size code",
      "integer (1-5)", ic, "institution",
      codes = .codes(
        "1" = "Under 1,000",
        "2" = "1,000 - 4,999",
        "3" = "5,000 - 9,999",
        "4" = "10,000 - 19,999",
        "5" = "20,000 and above"
      ),
      paste0(
        "Enrollment-based size classification: 1 = Under 1,000, ",
        "2 = 1,000-4,999, 3 = 5,000-9,999, 4 = 10,000-19,999, ",
        "5 = 20,000 or more. NCES reports -1 for not-reported; the ",
        "reconciler converts IPEDS negative sentinel codes to NA. ",
        "Coverage: 2010-present."
      )
    ),

    # -- Completions ----------------------------------------------------------

    .cb_row(
      "cipcode", "CIPCODE", "CIP code",
      "character (xx.xxxx)", "completions", "institution",
      paste0(
        "Six-digit Classification of Instructional Programs (CIP) code ",
        "identifying the program of study, formatted xx.xxxx and stored as ",
        "a character string so the leading zero on the 01-09 families ",
        "survives -- join to the NCES CIP-SOC crosswalk via ",
        "get_cip_soc_crosswalk(). NCES also ",
        "ships CIPCODE 99 rows holding each institution's grand total across ",
        "programs; these are excluded from county aggregations to avoid ",
        "double-counting, but are retained in the institution-level output ",
        "where they are the convenient per-institution total. The CIP ",
        "taxonomy was updated in 2020 and some programs were recoded -- use ",
        "the NCES CIP crosswalk (nces.ed.gov/ipeds/cipcode) for comparisons ",
        "spanning 2020. Coverage: 2010-present."
      )
    ),
    .cb_row(
      "major_num", "MAJORNUM", "Major number",
      "integer (1-2)", "completions", "institution",
      codes = .codes(
        "1" = "First major",
        "2" = "Second major"
      ),
      paste0(
        "Whether the award is counted as a first major (1) or second major ",
        "(2). A student completing a double major appears once under each. ",
        "County aggregations use first majors only, so counts reflect ",
        "credentials awarded rather than major-credential pairs. ",
        "Coverage: 2010-present."
      )
    ),
    .cb_row(
      "ed_level", "AWLEVEL", "Award level code",
      "integer", "completions", "institution",
      codes = .codes(
        "1" = "Certificates of less than 1 year (through 2019)",
        "2" = "Certificates of at least 1 but less than 2 years",
        "3" = "Associate's degree",
        "4" = "Certificates of at least 2 but less than 4 years",
        "5" = "Bachelor's degree",
        "6" = "Postbaccalaureate certificate",
        "7" = "Master's degree",
        "8" = "Post-master's certificate",
        "17" = "Doctor's degree - research/scholarship",
        "18" = "Doctor's degree - professional practice",
        "19" = "Doctor's degree - other",
        "20" = "Certificates of less than 12 weeks (2020 onward)",
        "21" = "Certificates of at least 12 weeks but less than 1 year (2020 onward)"
      ),
      paste0(
        "IPEDS award level code identifying the type of credential: ",
        "1 = award of less than 1 year, 2 = award of 1 to 2 years, ",
        "3 = Associate's, 4 = award of 2 to 4 years, 5 = Bachelor's, ",
        "6 = Postbaccalaureate certificate, 7 = Master's, ",
        "8 = Post-master's certificate, 17 = Doctoral (research/scholarship), ",
        "18 = Doctoral (professional practice), 19 = Doctoral (other). ",
        "County degree aggregations use codes 3, 5, 7, 17, 18, 19 only -- ",
        "that is, degrees from associate's through doctoral, excluding all ",
        "sub-associate and post-award certificates. Doctoral codes changed ",
        "in 2008 (9, 10 and 11 -- doctor's, first-professional degree and ",
        "first-professional certificate -- became 17/18/19); this package ",
        "starts at 2010, so ",
        "only the post-revision codes appear. A second break lands inside ",
        "the covered period: code 1 (award of less than 1 academic year) is ",
        "present 2010-2019 and absent from 2020, when NCES replaced it with ",
        "codes 20 and 21 subdividing short-duration certificates -- the ",
        "national totals line up across the break (553,790 under code 1 in ",
        "2019; 87,541 + 431,512 = 519,053 under 20 + 21 in 2020). All three ",
        "codes are sub-associate certificates and all three are excluded ",
        "from the degree aggregations, so the break does not affect any ",
        "county variable; it matters only if you aggregate certificates from ",
        "the institution-level table yourself, where you must use code 1 ",
        "before 2020 and codes 20 and 21 from 2020 on. Coverage: 2010-present."
      )
    ),
    .cb_row(
      "count_men", "CTOTALM", "Completions to men",
      "integer (count)", "completions", "institution",
      paste0(
        "Awards and degrees conferred to men in the reporting year for the ",
        "given CIP code, award level, and major number. Coverage: 2010-present."
      )
    ),
    .cb_row(
      "count_women", "CTOTALW", "Completions to women",
      "integer (count)", "completions", "institution",
      paste0(
        "Awards and degrees conferred to women in the reporting year for the ",
        "given CIP code, award level, and major number. Coverage: 2010-present."
      )
    ),
    .cb_row(
      "count_total_students", "CTOTALT", "Total completions",
      "integer (count)", "completions", "institution",
      paste0(
        "Awards and degrees conferred to all recipients in the reporting ",
        "year for the given CIP code, award level, and major number. Sum of ",
        "all race/ethnicity and gender categories, and the measure county ",
        "completions aggregations are built from. Coverage: 2010-present."
      )
    ),

    # -- Completers (NCES C{year}_C: student headcounts) ----------------------

    .cb_row(
      "award_level_category", "AWLEVELC", "Award level category code",
      "integer", "completers", "institution",
      codes = .codes(
        "1" = "Not labelled in the current NCES dictionary (2012-2019 only)",
        "2" = "Certificate of at least 1 but less than 4 years",
        "3" = "Associate's degree",
        "5" = "Bachelor's degree",
        "7" = "Master's degree",
        "9" = "Doctor's degree",
        "10" = "Postbaccalaureate or post-master's certificate",
        "11" = "Certificate of less than 12 weeks (2020 onward)",
        "12" = "Certificate of at least 12 weeks but less than 1 year (2020 onward)"
      ),
      paste0(
        "NCES award level category, a coarser grouping than the completions ",
        "survey's ed_level: 3 = Associate's, 5 = Bachelor's, 7 = Master's, ",
        "9 = Doctoral (all three doctoral types pooled, unlike ed_level ",
        "which splits 17/18/19). The remaining codes are certificates. The ",
        "degree-level codes are stable across every published vintage; the ",
        "certificate codes are not -- code 1 appears 2012-2019 and is ",
        "replaced by codes 11 and 12 from 2020 (477,339 students under code ",
        "1 in 2019; 82,022 + 374,003 under 11 + 12 in 2020). County ",
        "aggregations use the degree-level codes only, so they are unaffected. ",
        "Coverage: 2012-present."
      )
    ),
    .cb_row(
      "count_men", "CSTOTLM", "Completers, men",
      "integer (count)", "completers", "institution",
      paste0(
        "Number of men receiving an award at this level. A headcount of ",
        "students, not of awards. Coverage: 2012-present."
      )
    ),
    .cb_row(
      "count_women", "CSTOTLW", "Completers, women",
      "integer (count)", "completers", "institution",
      paste0(
        "Number of women receiving an award at this level. A headcount of ",
        "students, not of awards. Coverage: 2012-present."
      )
    ),
    .cb_row(
      "count_total_students", "CSTOTLT", "Completers, total",
      "integer (count)", "completers", "institution",
      paste0(
        "Number of students receiving an award at this level -- the measure ",
        "the county completers aggregations are built from. This is a ",
        "headcount, so it differs from the completions survey's ",
        "count_total_students, which counts awards: a student earning two ",
        "degrees at the same level is one completer but two degrees ",
        "(nationally in 2022, 4,035,014 degree-level completers against ",
        "4,153,739 degrees). Students are NOT additive across award level ",
        "categories -- someone earning a bachelor's and a master's in the ",
        "same year is counted in both -- so summing across levels ",
        "overcounts by roughly 6%. Coverage: 2012-present."
      )
    ),

    # -- Graduation Rates -----------------------------------------------------

    .cb_row(
      "cohort_type", "GRTYPE", "Cohort type code",
      "integer", "grad_rates", "institution",
      codes = .codes(
        "1" = "4-year institutions, revised cohort",
        "2" = "4-year institutions, adjusted cohort (revised cohort minus exclusions)",
        "3" = "4-year institutions, completers within 150% of normal time",
        "4" = "4-year institutions, transfer-out students",
        "5" = "Not labelled in the current NCES dictionary (2010 only)",
        "6" = "Bachelor's or equivalent subcohort (4-year institution)",
        "7" = "Bachelor's or equivalent subcohort, exclusions",
        "8" = "Bachelor's or equivalent subcohort, adjusted cohort",
        "9" = "Bachelor's or equivalent subcohort, completers within 150% of normal time, total",
        "10" = "Bachelor's or equivalent subcohort, completers of programs of less than 2 years (150% of normal time)",
        "11" = "Bachelor's or equivalent subcohort, completers of programs of 2 but less than 4 years (150% of normal time)",
        "12" = "Bachelor's or equivalent subcohort, completers of bachelor's or equivalent degrees, total (150% of normal time)",
        "13" = "Bachelor's or equivalent subcohort, completers of bachelor's or equivalent degrees in 4 years or less",
        "14" = "Bachelor's or equivalent subcohort, completers of bachelor's or equivalent degrees in 5 years",
        "15" = "Bachelor's or equivalent subcohort, completers of bachelor's or equivalent degrees in 6 years",
        "16" = "Bachelor's or equivalent subcohort, transfer-out students",
        "17" = "Not labelled in the current NCES dictionary (2010 only)",
        "18" = "Other degree/certificate-seeking subcohort (4-year institution)",
        "19" = "Other degree/certificate-seeking subcohort, exclusions",
        "20" = "Other degree/certificate-seeking subcohort, adjusted cohort",
        "21" = "Other degree/certificate-seeking subcohort, completers within 150% of normal time, total",
        "22" = "Other degree/certificate-seeking subcohort, completers of programs of less than 2 years (150% of normal time)",
        "23" = "Other degree/certificate-seeking subcohort, completers of programs of 2 but less than 4 years (150% of normal time)",
        "24" = "Other degree/certificate-seeking subcohort, completers of bachelor's or equivalent degrees (150% of normal time)",
        "25" = "Other degree/certificate-seeking subcohort, transfer-out students",
        "26" = "Not labelled in the current NCES dictionary (2010 only)",
        "27" = "Degree/certificate-seeking students (2-year institution), revised cohort",
        "28" = "Degree/certificate-seeking subcohort (2-year institution), exclusions",
        "29" = "Degree/certificate-seeking students (2-year institution), adjusted cohort",
        "30" = "Degree/certificate-seeking students (2-year institution), completers within 150% of normal time, total",
        "31" = "Degree/certificate-seeking students (2-year institution), completers of programs of less than 2 years (150% of normal time)",
        "32" = "Degree/certificate-seeking students (2-year institution), completers of programs of 2 but less than 4 years (150% of normal time)",
        "33" = "Degree/certificate-seeking students (2-year institution), transfer-out students",
        "34" = "Not labelled in the current NCES dictionary (2010 only)",
        "35" = "Degree/certificate-seeking students (2-year institution), completers within 100% of normal time, total",
        "36" = "Degree/certificate-seeking students (2-year institution), completers of programs of less than 2 years (100% of normal time)",
        "37" = "Degree/certificate-seeking students (2-year institution), completers of programs of 2 but less than 4 years (100% of normal time)",
        "40" = "Total exclusions, 4-year institutions",
        "41" = "4-year institutions, noncompleters still enrolled (2011 onward)",
        "42" = "4-year institutions, no longer enrolled (2011 onward)",
        "43" = "Bachelor's or equivalent subcohort, noncompleters still enrolled (2011 onward)",
        "44" = "Bachelor's or equivalent subcohort, no longer enrolled (2011 onward)",
        "45" = "Other degree/certificate-seeking subcohort, noncompleters still enrolled (2011 onward)",
        "46" = "Other degree/certificate-seeking subcohort, no longer enrolled (2011 onward)",
        "47" = "Degree/certificate-seeking students (2-year institution), noncompleters still enrolled (2011 onward)",
        "48" = "Degree/certificate-seeking students (2-year institution), no longer enrolled (2011 onward)"
      ),
      paste0(
        "Composite NCES code identifying both the cohort universe (the ",
        "survey's SECTION) and the row's role within it (its CHRTSTAT). ",
        "County aggregations use section 1, the four-year full-time ",
        "first-time bachelor's degree-seeking cohort: 2 = adjusted cohort ",
        "(denominator), 3 = completers within 150% of normal time, ",
        "4 = transfer-out students. Codes 6-16 cover section 2, 18-25 ",
        "section 3, and 28-37 section 4 -- other cohort universes that are ",
        "not aggregated here. Filtering on CHRTSTAT instead of GRTYPE would ",
        "pool sections together, since CHRTSTAT values repeat across them. ",
        "Coverage: 2010-present."
      )
    ),
    .cb_row(
      "grad_rate_status", "CHRTSTAT", "Graduation rate status code",
      "integer", "grad_rates", "institution",
      codes = .codes(
        "10" = "Revised cohort",
        "11" = "Exclusions",
        "12" = "Adjusted cohort (revised cohort minus exclusions)",
        "13" = "Completers within 150% of normal time",
        "14" = "Completers of programs of less than 2 years (150% of normal time)",
        "15" = "Completers of programs of 2 but less than 4 years (150% of normal time)",
        "16" = "Completers of bachelor's or equivalent degrees (150% of normal time)",
        "17" = "Completers of bachelor's or equivalent degrees in 4 years or less",
        "18" = "Completers of bachelor's or equivalent degrees in 5 years",
        "19" = "Completers of bachelor's or equivalent degrees in 6 years",
        "20" = "Transfer-out students",
        "21" = "Still enrolled in long programs (2010 only)",
        "22" = "Completers of programs within 100% of normal time, total",
        "23" = "Completers of programs of less than 2 years within 100% of normal time",
        "24" = "Completers of programs of 2 but less than 4 years within 100% of normal time",
        "31" = "Noncompleters, still enrolled (2011 onward)",
        "32" = "Noncompleters, no longer enrolled (2011 onward)"
      ),
      paste0(
        "NCES code for the record's role in the rate calculation: ",
        "12 = adjusted cohort (denominator), 13 = completers within 150% of ",
        "normal time, 20 = transfer-out students. Retained for traceability; ",
        "the aggregations key on cohort_type, which also pins the cohort ",
        "universe. Coverage: 2010-present."
      )
    ),
    .cb_row(
      "count_men", "GRTOTLM", "Cohort count, men",
      "integer (count)", "grad_rates", "institution",
      paste0(
        "Number of men in this graduation-rate record -- a cohort count, a ",
        "completer count, or a transfer-out count depending on cohort_type. ",
        "Coverage: 2010-present."
      )
    ),
    .cb_row(
      "count_women", "GRTOTLW", "Cohort count, women",
      "integer (count)", "grad_rates", "institution",
      paste0(
        "Number of women in this graduation-rate record -- a cohort count, a ",
        "completer count, or a transfer-out count depending on cohort_type. ",
        "Coverage: 2010-present."
      )
    ),
    .cb_row(
      "count_total_students", "GRTOTLT", "Cohort count, total",
      "integer (count)", "grad_rates", "institution",
      paste0(
        "Number of students in this graduation-rate record -- a cohort ",
        "count, a completer count, or a transfer-out count depending on ",
        "cohort_type. This is the measure the county grad-rate ",
        "aggregations are built from. Note that NCES also ships a COHORT ",
        "column in this survey, which is a categorical indicator of the ",
        "cohort universe and not a count; it is deliberately not mapped. ",
        "Coverage: 2010-present."
      )
    ),

    # -- County: institutional characteristics --------------------------------

    .cb_row(
      "inst_count", "", "Institution count",
      "integer (count)", ic, "county",
      paste0(
        "Number of degree-granting institutions with a valid county FIPS ",
        "code operating in the county. Excludes administrative units ",
        "(sector 0), unassigned sectors (99), and non-degree-granting ",
        "institutions. agg_var is NA. Coverage: 2010-present."
      )
    ),
    .cb_row(
      "public_inst_count", "", "Public institution count",
      "integer (count)", ic, "county",
      paste0(
        "Number of degree-granting public institutions (sector codes 1, 4, ",
        "7) in the county. agg_var is NA. Coverage: 2010-present."
      )
    ),
    .cb_row(
      "nonprofit_inst_count", "", "Nonprofit institution count",
      "integer (count)", ic, "county",
      paste0(
        "Number of degree-granting private nonprofit institutions (sector ",
        "codes 2, 5, 8) in the county. agg_var is NA. Coverage: 2010-present."
      )
    ),
    .cb_row(
      "fouryear_inst_count", "", "Four-year institution count",
      "integer (count)", ic, "county",
      paste0(
        "Number of degree-granting four-year-or-above institutions (sector ",
        "codes 1, 2, 3) in the county. agg_var is NA. Coverage: 2010-present."
      )
    ),
    .cb_row(
      "twoyear_inst_count", "", "Two-year institution count",
      "integer (count)", ic, "county",
      paste0(
        "Number of degree-granting two-year institutions (sector codes 4, ",
        "5, 6) in the county. agg_var is NA. Coverage: 2010-present."
      )
    ),
    .cb_row(
      "hbcu_count", "", "HBCU count",
      "integer (count)", ic, "county",
      paste0(
        "Number of degree-granting Historically Black Colleges and ",
        "Universities in the county. agg_var is NA. Coverage: 2010-present."
      )
    ),
    .cb_row(
      "tribal_count", "", "Tribal college count",
      "integer (count)", ic, "county",
      paste0(
        "Number of degree-granting tribal colleges and universities in the ",
        "county. agg_var is NA. Coverage: 2010-present."
      )
    ),

    # -- County: completions --------------------------------------------------

    .cb_row(
      "count_degrees_total", "", "Total degrees conferred",
      "integer (count)", "completions", "county",
      paste0(
        "Degrees conferred by degree-granting institutions in the county ",
        "across all tracked award levels (associate's through doctoral; ",
        "AWLEVEL 3, 5, 7, 17, 18, 19). Excludes CIPCODE 99 grand-total rows ",
        "and second majors (MAJORNUM 2), so a degree is counted once. ",
        "Certificates are excluded entirely. This is the denominator for ",
        "every share_degrees_* variable. agg_var is NA. Coverage: 2010-present."
      )
    ),
    .cb_row(
      "share_degrees_assoc", "", "Share associate degrees",
      "proportion (0-1)", "completions", "county",
      paste0(
        "Proportion of tracked degrees conferred at the associate's level ",
        "(AWLEVEL 3). Sub-associate certificates (AWLEVEL 2) are not ",
        "included. Raw count is recoverable as value * agg_var, where ",
        "agg_var is count_degrees_total. Coverage: 2010-present."
      )
    ),
    .cb_row(
      "share_degrees_bach", "", "Share bachelor degrees",
      "proportion (0-1)", "completions", "county",
      paste0(
        "Proportion of tracked degrees conferred at the bachelor's level ",
        "(AWLEVEL 5). Raw count recoverable as value * agg_var. ",
        "Coverage: 2010-present."
      )
    ),
    .cb_row(
      "share_degrees_masters", "", "Share master degrees",
      "proportion (0-1)", "completions", "county",
      paste0(
        "Proportion of tracked degrees conferred at the master's level ",
        "(AWLEVEL 7). Raw count recoverable as value * agg_var. ",
        "Coverage: 2010-present."
      )
    ),
    .cb_row(
      "share_degrees_doctoral", "", "Share doctoral degrees",
      "proportion (0-1)", "completions", "county",
      paste0(
        "Proportion of tracked degrees conferred at the doctoral level ",
        "(AWLEVEL 17, 18, 19). Raw count recoverable as value * agg_var. ",
        "Doctoral codes changed in 2008 (9/10/11 became 17/18/19); this ",
        "package covers 2010+, so only post-revision codes appear. ",
        "Coverage: 2010-present."
      )
    ),
    .cb_row(
      "share_degrees_men", "", "Share degrees to men",
      "proportion (0-1)", "completions", "county",
      paste0(
        "Proportion of tracked degrees conferred to men across all levels. ",
        "Complement of share_degrees_women; the two sum to 1 for any ",
        "county-year with completions data. Raw count recoverable as ",
        "value * agg_var. Coverage: 2010-present."
      )
    ),
    .cb_row(
      "share_degrees_women", "", "Share degrees to women",
      "proportion (0-1)", "completions", "county",
      paste0(
        "Proportion of tracked degrees conferred to women across all ",
        "levels. Complement of share_degrees_men. Raw count recoverable as ",
        "value * agg_var. Coverage: 2010-present."
      )
    ),

    # -- County: completers ---------------------------------------------------

    .cb_row(
      "count_students_assoc", "", "Students completing associate degrees",
      "integer (count)", "completers", "county",
      paste0(
        "Number of students at degree-granting institutions in the county ",
        "who received a associate's award (AWLEVELC 3). A headcount, so it is ",
        "not comparable to count_degrees_total, which counts awards. Do not ",
        "sum the count_students_* variables: a student earning degrees at ",
        "two levels in the same year appears in both, so a cross-level total ",
        "overcounts. agg_var is NA. Coverage: 2012-present; NA for 2010-2011, ",
        "which NCES did not publish."
      )
    ),
    .cb_row(
      "count_students_bach", "", "Students completing bachelor degrees",
      "integer (count)", "completers", "county",
      paste0(
        "Number of students at degree-granting institutions in the county ",
        "who received a bachelor's award (AWLEVELC 5). A headcount, so it is ",
        "not comparable to count_degrees_total, which counts awards. Do not ",
        "sum the count_students_* variables: a student earning degrees at ",
        "two levels in the same year appears in both, so a cross-level total ",
        "overcounts. agg_var is NA. Coverage: 2012-present; NA for 2010-2011, ",
        "which NCES did not publish."
      )
    ),
    .cb_row(
      "count_students_masters", "", "Students completing master degrees",
      "integer (count)", "completers", "county",
      paste0(
        "Number of students at degree-granting institutions in the county ",
        "who received a master's award (AWLEVELC 7). A headcount, so it is ",
        "not comparable to count_degrees_total, which counts awards. Do not ",
        "sum the count_students_* variables: a student earning degrees at ",
        "two levels in the same year appears in both, so a cross-level total ",
        "overcounts. agg_var is NA. Coverage: 2012-present; NA for 2010-2011, ",
        "which NCES did not publish."
      )
    ),
    .cb_row(
      "count_students_doctoral", "", "Students completing doctoral degrees",
      "integer (count)", "completers", "county",
      paste0(
        "Number of students at degree-granting institutions in the county ",
        "who received a doctoral award (AWLEVELC 9). A headcount, so it is ",
        "not comparable to count_degrees_total, which counts awards. Do not ",
        "sum the count_students_* variables: a student earning degrees at ",
        "two levels in the same year appears in both, so a cross-level total ",
        "overcounts. agg_var is NA. Coverage: 2012-present; NA for 2010-2011, ",
        "which NCES did not publish."
      )
    ),

    # -- County: graduation rates ---------------------------------------------

    .cb_row(
      "grad_rate_150pct", "", "150% graduation rate",
      "proportion (0-1)", "grad_rates", "county",
      paste0(
        "Proportion of the four-year full-time first-time bachelor's ",
        "degree-seeking adjusted cohort who completed within 150% of normal ",
        "time (six years for a four-year program). Computed as the county ",
        "sum of cohort_type 3 counts over the county sum of cohort_type 2 ",
        "counts, so it is a cohort-weighted average across the county's ",
        "institutions rather than a mean of institutional rates. agg_var is ",
        "the adjusted cohort size, so the completer count is recoverable as ",
        "value * agg_var. A county-year where no institution reported any ",
        "completer row is omitted rather than published as 0. ",
        "Matches the six-year graduation rate reported in ",
        "College Scorecard. NCES publishes graduation rates about a year ",
        "behind the other two surveys, so the most recent completions and ",
        "institutional_characteristics vintage typically has no grad-rate ",
        "counterpart. Coverage: 2010-present."
      )
    ),
    .cb_row(
      "transfer_out_rate", "", "Transfer-out rate",
      "proportion (0-1)", "grad_rates", "county",
      paste0(
        "Proportion of the adjusted cohort (cohort_type 2) who transferred ",
        "to another institution without completing (cohort_type 4). ",
        "Cohort-weighted across the county's institutions. agg_var is the ",
        "adjusted cohort size. Reporting transfer-out is effectively optional ",
        "for institutions, so coverage is much thinner than for ",
        "grad_rate_150pct: a county-year where no institution reported any ",
        "transfer-out row is omitted entirely rather than published as 0, so ",
        "expect this variable to be absent for roughly a quarter of the ",
        "county-years that do have a graduation rate. A value of 0 therefore ",
        "means a reported zero, not missing data. Coverage: 2010-present."
      )
    )
  )
}
