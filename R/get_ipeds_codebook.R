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
# `label`, `unit`, `notes`) plus two this package needs to drive the ETL:
# `survey` and `level`.
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

.cb_row <- function(variable, raw_variable, label, unit, survey, level, notes) {
  data.frame(
    variable     = variable,
    raw_variable = raw_variable,
    label        = label,
    unit         = unit,
    survey       = survey,
    level        = level,
    notes        = notes,
    stringsAsFactors = FALSE
  )
}


#' Get the cori.data.ipeds variable codebook
#'
#' Returns documentation for every variable available via
#' [get_ipeds()] and [get_ipeds()]. Covers the three IPEDS
#' surveys this package harmonizes: Institutional Characteristics, Completions,
#' and Graduation Rates, 2010 to present.
#'
#' Use `level` to separate the two output grains: `"institution"` variables
#' appear in [get_ipeds()]'s institution-grain output, `"county"` variables in
#' [get_ipeds()]'s tidy output, and `"both"` marks the join keys present
#' in every table.
#'
#' `notes` records vintage caveats -- which years a variable covers, NCES
#' column renames, and taxonomy changes -- so cross-year comparability is
#' documented alongside the variable rather than in separate prose.
#'
#' @return A data frame with columns: `variable`, `raw_variable`, `label`,
#'   `unit`, `survey`, `level`, `notes`.
#'   `raw_variable` is the original NCES column name, as stored in the
#'   `data_raw` layer on S3; it is empty for derived county-level variables.
#'
#' @seealso [get_ipeds()], [get_ipeds()]
#'
#' @examples
#' cb <- get_ipeds_codebook()
#'
#' # County-level variables only
#' cb[cb$level == "county", c("variable", "label", "unit")]
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
      paste0(
        "Control of institution: 1 = Public, 2 = Private nonprofit, ",
        "3 = Private for-profit. Coverage: 2010-present."
      )
    ),
    .cb_row(
      "inst_level_code", "ICLEVEL", "Institution level code",
      "integer (1-3)", ic, "institution",
      paste0(
        "Highest level of degree or certificate program offered: 1 = Four or ",
        "more years, 2 = At least two but less than four years, 3 = Less ",
        "than two years. Coverage: 2010-present."
      )
    ),
    .cb_row(
      "hbcu_code", "HBCU", "HBCU flag code",
      "integer (1-2)", ic, "institution",
      paste0(
        "Whether the institution is a Historically Black College or ",
        "University as designated by the U.S. Department of Education. ",
        "1 = Yes, 2 = No. Coverage: 2010-present."
      )
    ),
    .cb_row(
      "has_hospital_code", "HOSPITAL", "Hospital flag code",
      "integer (1-2)", ic, "institution",
      "Whether the institution owns or operates a hospital. 1 = Yes, 2 = No. Coverage: 2010-present."
    ),
    .cb_row(
      "tribal_college_code", "TRIBAL", "Tribal college flag code",
      "integer (1-2)", ic, "institution",
      paste0(
        "Whether the institution is a tribal college or university as ",
        "defined by the Tribally Controlled Colleges and Universities ",
        "Assistance Act of 1978. 1 = Yes, 2 = No. Coverage: 2010-present."
      )
    ),
    .cb_row(
      "degree_granting_status_code", "DEGGRANT", "Degree-granting status code",
      "integer (1-2)", ic, "institution",
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
      paste0(
        "2000 Carnegie Classification code, distinguishing research ",
        "universities, doctoral universities, master's colleges, ",
        "baccalaureate colleges, associate's colleges, and special-focus ",
        "institutions. See the NCES data dictionary for the full code list. ",
        "NCES renamed this column from CARNEGIE (2010-2023) to C00CARNEGIE ",
        "in 2024; reconcile_ic_vintage() normalizes C00CARNEGIE back to ",
        "CARNEGIE so the mapping is consistent across vintages. Values are ",
        "unchanged by the rename. Coverage: 2010-present."
      )
    ),
    .cb_row(
      "highest_level_offered_code", "HLOFFER", "Highest level offered code",
      "integer (1-11)", ic, "institution",
      paste0(
        "Highest award level offered, from certificates of less than one ",
        "year (1) through doctoral degrees (11). Coverage: 2010-present."
      )
    ),
    .cb_row(
      "highest_degree_offered_code", "HDEGOFR1", "Highest degree offered code",
      "integer (0-6)", ic, "institution",
      paste0(
        "Highest degree offered: 0 = Non-degree-granting, 1 = Certificate, ",
        "2 = Associate's, 3 = Bachelor's, 4 = Master's, 5 = Doctor's, ",
        "6 = First professional. Coverage: 2010-present."
      )
    ),
    .cb_row(
      "undergrad_degree_offered_code", "UGOFFER", "Undergrad degree offered code",
      "integer (1-2)", ic, "institution",
      paste0(
        "Whether the institution offers undergraduate degree or certificate ",
        "programs. 1 = Yes, 2 = No. Coverage: 2010-present."
      )
    ),
    .cb_row(
      "grad_degree_offered_code", "GROFFER", "Graduate degree offered code",
      "integer (1-2)", ic, "institution",
      paste0(
        "Whether the institution offers graduate degree or certificate ",
        "programs. 1 = Yes, 2 = No. Coverage: 2010-present."
      )
    ),
    .cb_row(
      "urbanization_level_code", "LOCALE", "Urbanization level code",
      "integer (11-43)", ic, "institution",
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
      paste0(
        "Whether the institution is a land-grant university designated under ",
        "the Morrill Acts. 1 = Yes, 2 = No. Land-grant institutions receive ",
        "federal funding for agriculture, engineering, and mechanical arts ",
        "research and are disproportionately rural. Coverage: 2010-present."
      )
    ),
    .cb_row(
      "institution_size_code", "INSTSIZE", "Institution size code",
      "integer (1-5)", ic, "institution",
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
        "in 2009 (9/10/11 became 17/18/19); this package starts at 2010, so ",
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
        "Doctoral codes changed in 2009 (9/10/11 became 17/18/19); this ",
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
