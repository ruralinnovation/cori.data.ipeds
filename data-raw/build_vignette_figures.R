# data-raw/build_vignette_figures.R
#
# Renders the figures embedded in vignettes/rural-higher-education.Rmd.
#
#   devtools::load_all("."); source("data-raw/build_vignette_figures.R")
#
# The vignette's analysis chunks are eval = FALSE, matching the rest of the
# cori.data family: building them live would need S3 credentials, which
# R CMD check does not have. So the charts are rendered here, committed under
# vignettes/figures/, and embedded with knitr::include_graphics(). Re-run this
# after any data or chart change so the two stay in step.
#
# Requires: cori.charts, ruraldefinitions, cori.data.pep, ggbeeswarm, sf, tigris.

suppressMessages({
  library(dplyr); library(ggplot2); library(ruraldefinitions); library(cori.charts)
})

q_      <- function(e) suppressMessages(e)
FIG_DIR <- file.path("vignettes", "figures")
dir.create(FIG_DIR, recursive = TRUE, showWarnings = FALSE)
load_fonts()
options(tigris_use_cache = TRUE)

# Base year. 2024 is the latest vintage for institutional characteristics,
# completions and completers. Graduation rates lag about a year, so the
# completion series below ends at 2023 -- that is NCES's release schedule,
# not a gap in the package.
YR        <- 2024L
GR_LAST   <- 2023L
TECH_YRS  <- (YR - 2L):YR          # most recent three years

rural     <- cbsa_2023 |> select(geoid, is_rural)
RURAL_COL <- stats::setNames(unname(cori_palettes$ctg2ruralnonrural),
                             c("Rural", "Nonrural"))
SRC       <- "Source: NCES IPEDS via cori.data.ipeds. Rural classification: CBSA 2023."
SRC_PLAIN <- "Source: NCES IPEDS via cori.data.ipeds."

finish <- function(fig, title, subtitle, source, note = NULL, file,
                   height = 5.5, width = 8) {
  fig <- fig + labs(
    title    = stringr::str_wrap(title, 52),
    subtitle = stringr::str_wrap(subtitle, 72),
    caption  = paste(stringr::str_wrap(source, 88),
                     if (!is.null(note)) stringr::str_wrap(note, 88), sep = "\n"),
    x = NULL, y = NULL
  )
  save_plot(fig, file.path(FIG_DIR, file), chart_height = height,
            chart_width = width, add_logo = FALSE)
  message("  -> ", file.path(FIG_DIR, file))
  invisible(fig)
}

county_labels <- q_(get_institutions(geography = "institution", years = YR)) |>
  filter(!is.na(county_name), !is.na(st_abbr)) |>
  distinct(geoid = county_fips, county_name, st_abbr) |>
  group_by(geoid) |> slice(1) |> ungroup() |>
  mutate(county_label = paste0(county_name, ", ", st_abbr)) |>
  select(geoid, county_label)


# 1. Map: which counties have a four-year university --------------------------
#
# A binary flag crossed with rurality, following the house pattern in
# data-rural-economic-outlook/R/viz/presentation/tradable_service_map.R:
# the two flagged categories carry the brand colors, the two unflagged
# categories sit back in grey so the map reads as presence/absence rather
# than as a continuous surface.

has_4yr <- q_(get_institutions(geography = "institution", years = YR)) |>
  filter(is_degree_granting == 1, is_4yr == 1, !is.na(county_fips)) |>
  distinct(geoid = county_fips) |>
  mutate(has_university = TRUE)

counties <- tigris::counties(cb = TRUE, progress_bar = FALSE) |>
  tigris::shift_geometry() |>
  filter(GEOID <= "57") |>
  sf::st_transform(crs = 5070)

states <- tigris::states(cb = TRUE, progress_bar = FALSE) |>
  tigris::shift_geometry() |>
  filter(GEOID <= "57") |>
  sf::st_transform(crs = 5070)

map_dta <- counties |>
  left_join(has_4yr, by = c("GEOID" = "geoid")) |>
  left_join(rural,   by = c("GEOID" = "geoid")) |>
  mutate(
    has_university = coalesce(has_university, FALSE),
    classification = case_when(
      has_university  & is_rural == "Nonrural" ~ "Four-year university\n(Nonrural)",
      has_university  & is_rural == "Rural"    ~ "Four-year university\n(Rural)",
      !has_university & is_rural == "Nonrural" ~ "Nonrural",
      !has_university & is_rural == "Rural"    ~ "Rural"
    ),
    classification = factor(classification, levels = c(
      "Four-year university\n(Nonrural)", "Four-year university\n(Rural)",
      "Nonrural", "Rural"))
  )

bbox <- sf::st_bbox(states)

fig <- ggplot() +
  geom_sf(data = map_dta, aes(fill = classification), color = NA, linewidth = 0) +
  geom_sf(data = states, fill = NA, color = "black", linewidth = 0.3) +
  scale_fill_manual(
    name   = NULL,
    values = c(
      "Four-year university\n(Nonrural)" = unname(cori_colors[["Dark Purple"]]),
      "Four-year university\n(Rural)"    = unname(cori_colors[["Emerald"]]),
      "Nonrural"                         = "#d8d8d8",
      "Rural"                            = "#efefef"
    ),
    na.value = "#ffffff", na.translate = FALSE
  ) +
  coord_sf(crs = sf::st_crs(5070),
           xlim = c(bbox[["xmin"]], bbox[["xmax"]]),
           ylim = c(bbox[["ymin"]], bbox[["ymax"]]), expand = FALSE) +
  theme_cori_map() +
  theme(
    legend.position   = "top",
    legend.direction  = "horizontal",
    legend.key.width  = unit(20, "pt"),
    legend.key.height = unit(20, "pt"),
    legend.spacing.x  = unit(8, "pt"),
    legend.text       = element_text(size = 10, lineheight = 0.9),
    legend.box.spacing = unit(0, "pt"),
    plot.caption      = element_text(size = 8, hjust = 0, lineheight = 1.2)
  )

finish(fig,
  "341 rural counties anchor a four-year university",
  sprintf("Counties containing at least one four-year degree-granting institution, %d", YR),
  SRC, "Counties with no institution produce no row in the data; absence is treated as none.",
  "access_map.png", height = 8, width = 12)


# 2. Institution composition, faceted by level and control --------------------

ic <- q_(get_institutions(geography = "institution", years = YR)) |>
  mutate(geoid = county_fips) |>
  inner_join(rural, by = "geoid") |>
  filter(is_degree_granting == 1, is_4yr == 1 | is_2yr == 1) |>
  mutate(
    level   = if_else(is_4yr == 1, "Four-year", "Two-year"),
    control = if_else(is_public == 1, "Public", "Private")
  )

fig <- ic |>
  count(is_rural, level, control) |>
  group_by(is_rural) |>
  mutate(share = n / sum(n)) |>
  ungroup() |>
  ggplot(aes(x = share, y = control, fill = is_rural)) +
  geom_col(position = position_dodge(width = 0.72), width = 0.62) +
  geom_text(aes(label = scales::percent(share, accuracy = 1)),
            position = position_dodge(width = 0.72), hjust = -0.2, size = 2.8) +
  facet_wrap(~ level) +
  scale_fill_manual(values = RURAL_COL, name = NULL) +
  scale_x_continuous(labels = scales::percent_format(accuracy = 1),
                     expand = expansion(mult = c(0, 0.22))) +
  theme_cori_horizontal_bars() +
  theme(legend.position = "top")

finish(fig,
  "Rural capacity rests on public two-year colleges",
  sprintf("Share of a county type's degree-granting institutions, %d", YR),
  SRC, "Note: shares sum to 100% within rural and within nonrural. Private includes nonprofit and for-profit.",
  "institution_type.png", height = 4.8)


# 3. Production per capita, county by county ----------------------------------

deg <- q_(get_degrees(variables = "count_degrees_total", years = YR)) |>
  select(geoid, degrees = value)
pop <- q_(cori.data.pep::get_population(geography = "county", years = YR)) |>
  filter(variable == "population") |> select(geoid, population = value)

per_cap <- rural |>
  inner_join(pop, by = "geoid") |>
  left_join(deg, by = "geoid") |>
  mutate(degrees = coalesce(degrees, 0)) |>
  filter(degrees > 0, population > 0) |>
  mutate(per_1k = 1000 * degrees / population)

fig <- ggplot(per_cap, aes(x = per_1k, y = is_rural, color = is_rural)) +
  ggbeeswarm::geom_beeswarm(aes(size = population), cex = 0.9,
                            orientation = "y", alpha = 0.4) +
  scale_color_manual(values = RURAL_COL, guide = "none") +
  scale_size_continuous(range = c(0.4, 4), guide = "none") +
  scale_x_log10(breaks = c(0.3, 1, 3, 10, 30, 100),
                labels = c("0.3", "1", "3", "10", "30", "100")) +
  theme_cori() +
  theme(panel.grid.major.y = element_blank())

finish(fig,
  "A few college towns do the heavy lifting",
  sprintf("Degrees conferred per 1,000 residents, one dot per county, %d", YR),
  SRC, "Note: log scale, so each gridline is 3x the one before. Dot size is county population. Counties producing no degrees are excluded.",
  "per_capita.png", height = 3.6)


# 4. Completion outcomes over time --------------------------------------------

update_cori_geom_defaults()   # must precede a line geom

trend <- q_(get_graduation_rates(variables = "grad_rate_150pct",
                                 years = 2010:GR_LAST)) |>
  inner_join(rural, by = "geoid") |>
  group_by(year, is_rural) |>
  # agg_var is the adjusted cohort, so this is cohort-weighted
  summarise(rate = sum(value * agg_var) / sum(agg_var), .groups = "drop")

fig <- ggplot(trend, aes(x = year, y = rate, color = is_rural)) +
  geom_line(linewidth = 1) +
  geom_point(size = 2) +
  scale_color_manual(values = RURAL_COL, name = NULL) +
  scale_y_continuous(labels = scales::percent_format(accuracy = 1)) +
  scale_x_continuous(breaks = seq(2010, GR_LAST, 2)) +
  theme_cori() +
  theme(legend.position = "top")

finish(fig,
  "Rural completion keeps climbing, though metro climbs faster",
  sprintf("Cohort-weighted completion within 150%% of normal time, %d-%d", 2010, GR_LAST),
  SRC, sprintf("Note: weighted by adjusted cohort size. Ends at %d because NCES publishes graduation rates about a year behind the other surveys.", GR_LAST),
  "grad_rate.png")


# 5. Degrees against students -------------------------------------------------

lv <- c(assoc = "Associate", bach = "Bachelor", masters = "Master", doctoral = "Doctoral")

deg_lvl <- q_(get_degrees(variables = paste0("share_degrees_", names(lv)), years = YR)) |>
  mutate(level = base::sub("share_degrees_", "", variable), n = value * agg_var) |>
  group_by(level) |> summarise(Degrees = sum(n), .groups = "drop")
stu_lvl <- q_(get_completers(years = YR)) |>
  mutate(level = base::sub("count_students_", "", variable)) |>
  group_by(level) |> summarise(Students = sum(value), .groups = "drop")

# scales::cut_short_scale() renders 2,036,305 as "2.0M" and 931,397 as "931K"
short <- scales::label_number(accuracy = 0.1, scale_cut = scales::cut_short_scale())

fig <- inner_join(deg_lvl, stu_lvl, by = "level") |>
  tidyr::pivot_longer(c(Degrees, Students), names_to = "measure", values_to = "n") |>
  mutate(level = factor(lv[level], levels = rev(unname(lv)))) |>
  ggplot(aes(x = n, y = level, fill = measure)) +
  geom_col(position = position_dodge(width = 0.72), width = 0.62) +
  geom_text(aes(label = short(n)), position = position_dodge(width = 0.72),
            hjust = -0.15, size = 2.9) +
  scale_fill_manual(values = stats::setNames(unname(cori_palettes$ctg2tlpu),
                                             c("Degrees", "Students")), name = NULL) +
  scale_x_continuous(labels = short, expand = expansion(mult = c(0, 0.2))) +
  theme_cori_horizontal_bars() +
  theme(legend.position = "top")

finish(fig,
  "Second degrees cluster at the associate level",
  sprintf("Degrees conferred against students completing, %d", YR),
  SRC_PLAIN,
  "Note: the gap is students earning more than one degree at the same level. Student counts are not additive across levels.",
  "degrees_students.png", height = 4.6)


# 6. The tech pipeline: SOC major group 15, three most recent years -----------

xw <- get_cip_soc_crosswalk("2020")

# SOC major group 15 is "Computer and Mathematical Occupations" -- the whole
# group rather than a hand-picked list, so the definition is one a reader can
# check against BLS. 21 detailed occupations, including data scientists and
# statisticians alongside software and support roles.
cips <- xw |>
  filter(grepl("^15-", soc_code)) |>
  distinct(cip_code) |>
  pull(cip_code)

tech <- q_(get_degrees(geography = "institution", years = TECH_YRS)) |>
  filter(cipcode %in% cips, major_num == 1L, cipcode != "99.0000",
         ed_level %in% c(3L, 5L, 7L, 17L, 18L, 19L)) |>
  group_by(geoid = county_fips) |>
  summarise(tech_degrees = sum(count_total_students, na.rm = TRUE), .groups = "drop")

top <- rural |>
  left_join(tech, by = "geoid") |>
  mutate(tech_degrees = coalesce(tech_degrees, 0)) |>
  filter(is_rural == "Rural") |>
  slice_max(tech_degrees, n = 10) |>
  left_join(county_labels, by = "geoid") |>
  mutate(county_label = coalesce(county_label, geoid))

fig <- top |>
  mutate(county_label = factor(county_label, levels = rev(county_label))) |>
  ggplot(aes(x = tech_degrees, y = county_label)) +
  geom_col(fill = unname(cori_colors[["Emerald"]]), width = 0.7) +
  geom_text(aes(label = scales::comma(tech_degrees)), hjust = -0.15, size = 3) +
  scale_x_continuous(labels = scales::comma, expand = expansion(mult = c(0, 0.15))) +
  theme_cori_horizontal_bars()

finish(fig,
  "Rural tech degree production concentrates in a few counties",
  sprintf("Degrees in programs feeding computer and mathematical occupations, %d-%d combined",
          min(TECH_YRS), max(TECH_YRS)),
  paste(SRC, "Occupations: SOC major group 15 via the NCES CIP2020-SOC2018 crosswalk."),
  "Note: first majors only, CIP 99 grand totals excluded, degree levels only.",
  "tech_pipeline.png", height = 6)

message("\nDone. ", length(list.files(FIG_DIR, pattern = "[.]png$")), " figures in ", FIG_DIR)
