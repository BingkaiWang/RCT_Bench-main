library(tidyverse)
library(readxl)
library(readr)
library(haven)
library(writexl)

root <- "rct_expansion"
raw_dir <- file.path(root, "raw_data")
clean_dir <- file.path(root, "cleaned_data")
meta_dir <- file.path(root, "metadata")
prov_dir <- file.path(root, "provenance")
verification_dir <- file.path(prov_dir, "predownload_verification_2026_06_09")
download_dir <- file.path(verification_dir, "downloads")
extracted_dir <- file.path(verification_dir, "extracted")

dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(clean_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(meta_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(prov_dir, recursive = TRUE, showWarnings = FALSE)

today <- "2026-06-09"

num <- function(x, missing_codes = c(
  "", "NA", "NaN", "nan", ".",
  "777", "999", "999.0", "999.00", "999999", "999999.0", "999999.00",
  "-95", "-96", "-96(1)", "-96(2)", "-97", "-98", "-99"
)) {
  if (inherits(x, "haven_labelled")) x <- haven::zap_labels(x)
  if (is.logical(x)) return(as.numeric(x))
  x_chr <- trimws(as.character(x))
  x_chr[x_chr %in% missing_codes] <- NA_character_
  readr::parse_number(x_chr, na = missing_codes, locale = readr::locale(decimal_mark = "."))
}

num_keep_999 <- function(x) num(x, missing_codes = c("", "NA", "NaN", "nan", ".", "-96", "-96(1)", "-96(2)", "-97", "-98", "-99"))

binary_num <- function(x) {
  if (inherits(x, "haven_labelled")) x <- haven::zap_labels(x)
  if (is.logical(x)) return(as.numeric(x))
  x_chr <- tolower(trimws(as.character(x)))
  out <- rep(NA_real_, length(x_chr))
  true_idx <- x_chr %in% c("true", "yes", "y", "1")
  false_idx <- x_chr %in% c("false", "no", "n", "0")
  out[true_idx] <- 1
  out[false_idx] <- 0
  other_idx <- !true_idx & !false_idx & !is.na(x_chr) & x_chr != ""
  out[other_idx] <- num(x_chr[other_idx])
  out
}

first_nonmissing <- function(x) {
  ok <- !is.na(x) & trimws(as.character(x)) != ""
  if (!any(ok)) return(NA)
  x[which(ok)[1]]
}

last_nonmissing <- function(x) {
  ok <- !is.na(x) & trimws(as.character(x)) != ""
  if (!any(ok)) return(NA)
  x[tail(which(ok), 1)]
}

row_sum_na <- function(df) {
  if (ncol(df) == 0) return(rep(NA_real_, nrow(df)))
  m <- as.data.frame(lapply(df, num))
  out <- rowSums(m, na.rm = TRUE)
  out[rowSums(!is.na(m)) == 0] <- NA_real_
  out
}

row_mean_na <- function(df) {
  if (ncol(df) == 0) return(rep(NA_real_, nrow(df)))
  m <- as.data.frame(lapply(df, num))
  out <- rowMeans(m, na.rm = TRUE)
  out[rowSums(!is.na(m)) == 0] <- NA_real_
  out
}

max_na <- function(x) {
  x <- num(x)
  if (all(is.na(x))) return(NA_real_)
  max(x, na.rm = TRUE)
}

clean_variable_type <- function(variable_name) {
  dplyr::case_when(
    variable_name == "Treatment" ~ "Treatment assignment",
    startsWith(variable_name, "YP_") ~ "Primary outcome",
    startsWith(variable_name, "YS_") ~ "Secondary outcome",
    startsWith(variable_name, "X_") ~ "Baseline covariate",
    TRUE ~ "Other"
  )
}

clean_variable_explanation <- function(variable_name) {
  readable_name <- variable_name %>%
    stringr::str_remove("^(YP|YS|X)_") %>%
    stringr::str_replace_all("_", " ") %>%
    stringr::str_squish()

  dplyr::case_when(
    variable_name == "Treatment" ~ "Randomized treatment assignment; control or reference arm is first when identifiable.",
    startsWith(variable_name, "YP_") ~ paste("Primary outcome:", readable_name),
    startsWith(variable_name, "YS_") ~ paste("Secondary outcome:", readable_name),
    startsWith(variable_name, "X_") ~ paste("Baseline covariate or pre-treatment measurement:", readable_name),
    TRUE ~ paste("Cleaned analysis variable:", readable_name)
  )
}

copy_candidate_sources <- function(candidate_id, trial_id) {
  target_dir <- output_raw_dir(trial_id)
  dir.create(target_dir, recursive = TRUE, showWarnings = FALSE)

  for (source_dir in c(file.path(download_dir, candidate_id), file.path(extracted_dir, candidate_id))) {
    if (!dir.exists(source_dir)) next
    source_items <- list.files(source_dir, full.names = TRUE, all.files = FALSE, no.. = TRUE)
    for (item in source_items) {
      destination <- file.path(target_dir, basename(item))
      if (file.exists(destination)) next
      file.copy(item, destination, recursive = TRUE, copy.mode = FALSE, copy.date = TRUE)
    }
  }
}

source_files_for_trial <- function(trial_id) {
  target_dir <- file.path(raw_dir, paste0("trial", trial_id))
  files <- list.files(target_dir, recursive = TRUE, all.files = FALSE, no.. = TRUE)
  files <- files[!grepl("(^|/)\\.DS_Store$", files)]
  paste(files, collapse = "; ")
}

write_trial <- function(df, trial_id) {
  output <- output_clean_paths(trial_id)
  stopifnot("Treatment" %in% names(df))
  stopifnot(any(startsWith(names(df), "YP_")))
  stopifnot(anyDuplicated(names(df)) == 0)
  df <- df %>%
    mutate(across(where(is.character), ~ na_if(.x, "")))
  write_csv(df, output$csv, na = "")
  saveRDS(df, output$rds)
  df
}

validate_trial <- function(trial_id) {
  path <- file.path(clean_dir, paste0("trial", trial_id, ".rds"))
  d <- readRDS(path)
  treatment_levels <- if ("Treatment" %in% names(d)) nlevels(as.factor(d$Treatment)) else 0
  primary_count <- sum(startsWith(names(d), "YP_"))
  duplicate_name_count <- sum(duplicated(names(d)))
  duplicate_exact_count <- 0
  if (ncol(d) > 1) {
    duplicate_exact_count <- sum(duplicated(as.list(d)))
  }
  tibble(
    Trial_ID = trial_id,
    n_rows = nrow(d),
    n_cols = ncol(d),
    has_treatment = "Treatment" %in% names(d),
    n_treatment_levels = treatment_levels,
    n_primary_outcomes = primary_count,
    n_secondary_outcomes = sum(startsWith(names(d), "YS_")),
    n_covariates = sum(startsWith(names(d), "X_")),
    duplicate_name_count = duplicate_name_count,
    duplicate_exact_column_count = duplicate_exact_count,
    csv_loads = file.exists(file.path(clean_dir, paste0("trial", trial_id, ".csv"))),
    rds_loads = TRUE,
    passes_contract = "Treatment" %in% names(d) &&
      treatment_levels >= 2 &&
      primary_count >= 1 &&
      duplicate_name_count == 0 &&
      duplicate_exact_count == 0
  )
}

trial_id_map <- tribble(
  ~Original_Trial_ID, ~New_Trial_ID, ~Backup_ID, ~Final_Status,
  81L, NA_integer_, "B06", "backup",
  82L, NA_integer_, "B07", "backup",
  83L, NA_integer_, "B08", "backup",
  84L, NA_integer_, "B09", "backup",
  85L, 81L, NA_character_, "active",
  86L, 82L, NA_character_, "active",
  87L, NA_integer_, "B10", "backup",
  88L, NA_integer_, "B11", "backup",
  89L, 83L, NA_character_, "active",
  90L, NA_integer_, "B12", "backup",
  91L, 84L, NA_character_, "active",
  92L, 85L, NA_character_, "active",
  93L, 86L, NA_character_, "active",
  94L, NA_integer_, "B13", "backup"
)

map_row <- function(original_trial_id) {
  out <- trial_id_map %>% filter(Original_Trial_ID == as.integer(original_trial_id))
  if (nrow(out) != 1) stop("No final mapping for original trial", original_trial_id)
  out
}

output_raw_dir <- function(original_trial_id) {
  m <- map_row(original_trial_id)
  if (m$Final_Status == "active") return(file.path(raw_dir, paste0("trial", m$New_Trial_ID)))
  file.path(root, "backup", m$Backup_ID, "raw_data")
}

output_clean_paths <- function(original_trial_id) {
  m <- map_row(original_trial_id)
  if (m$Final_Status == "active") {
    return(list(
      csv = file.path(clean_dir, paste0("trial", m$New_Trial_ID, ".csv")),
      rds = file.path(clean_dir, paste0("trial", m$New_Trial_ID, ".rds"))
    ))
  }
  backup_clean_dir <- file.path(root, "backup", m$Backup_ID, "cleaned_data")
  dir.create(backup_clean_dir, recursive = TRUE, showWarnings = FALSE)
  list(
    csv = file.path(backup_clean_dir, paste0(m$Backup_ID, ".csv")),
    rds = file.path(backup_clean_dir, paste0(m$Backup_ID, ".rds"))
  )
}

qualified <- read_csv(file.path(verification_dir, "qualified_for_cleaning_queue.csv"), show_col_types = FALSE) %>%
  mutate(Original_Trial_ID = 81:94) %>%
  left_join(trial_id_map, by = "Original_Trial_ID") %>%
  mutate(Trial_ID = coalesce(New_Trial_ID, Original_Trial_ID))

walk2(qualified$candidate_id, qualified$Original_Trial_ID, copy_candidate_sources)

# Trial 81: QPSS
qpss <- read_tsv(file.path(download_dir, "RCTC-02120", "QPSS_RCTData.tab"), show_col_types = FALSE)
score_qpss <- function(data) {
  data <- data %>%
    mutate(across(
      c(
        MQOLA, MQOL1a, MQOL2:MQOL22,
        QOLFA, QOLF1:QOLF17
      ),
      num
    )) %>%
    mutate(
      MQOL1a_r = 10 - MQOL1a,
      MQOL3_r = 10 - MQOL3,
      MQOL4_r = 10 - MQOL4,
      MQOL5_r = 10 - MQOL5,
      MQOL6_r = 10 - MQOL6,
      MQOL7_r = 10 - MQOL7,
      MQOL10_r = 10 - MQOL10,
      MQOL15_r = 10 - MQOL15,
      MQOL_PHY = row_mean_na(pick(MQOL1a_r, MQOL2, MQOL3_r)),
      MQOL_PSY = row_mean_na(pick(MQOL4_r, MQOL5_r, MQOL6_r, MQOL7_r)),
      MQOL_EXI = row_mean_na(pick(MQOL8, MQOL9, MQOL10_r, MQOL11)),
      MQOL_SOC = row_mean_na(pick(MQOL12, MQOL13, MQOL14)),
      MQOL_BUR = MQOL15_r,
      MQOL_ENV = MQOL16,
      MQOL_COG = row_mean_na(pick(MQOL17, MQOL18)),
      MQOL_QC = row_mean_na(pick(MQOL19, MQOL21)),
      MQOL_TOT = row_mean_na(pick(MQOL_PHY, MQOL_PSY, MQOL_EXI, MQOL_SOC, MQOL_BUR, MQOL_ENV, MQOL_COG, MQOL_QC)),
      QOLF3_r = 10 - QOLF3,
      QOLF4_r = 10 - QOLF4,
      QOLF15_r = 10 - QOLF15,
      QOLF16_r = 10 - QOLF16,
      QOLF17_r = 10 - QOLF17,
      QOLF_ENV = row_mean_na(pick(QOLF1, QOLF2)),
      QOLF_PAT = QOLF3_r,
      QOLF_OWN = row_mean_na(pick(QOLF4_r, QOLF5, QOLF6, QOLF7, QOLF8)),
      QOLF_OUT = row_mean_na(pick(QOLF9, QOLF10, QOLF11)),
      QOLF_QC = row_mean_na(pick(QOLF12, QOLF14)),
      QOLF_REL = row_mean_na(pick(QOLF15_r, QOLF16_r)),
      QOLF_FIN = QOLF17_r,
      QOLF_TOT = row_mean_na(pick(QOLF_ENV, QOLF_PAT, QOLF_OWN, QOLF_OUT, QOLF_QC, QOLF_REL, QOLF_FIN))
    )
}
qpss <- score_qpss(qpss)
qpss_baseline <- qpss %>%
  arrange(MPLUSID, Period_2Mo) %>%
  group_by(MPLUSID) %>%
  slice(1) %>%
  ungroup()
qpss_latest <- qpss %>%
  arrange(MPLUSID, Period_2Mo) %>%
  group_by(MPLUSID) %>%
  summarise(
    YP_mqol_summary_final = num(last_nonmissing(MQOL_TOT)),
    YP_delta_mqol_summary = num(last_nonmissing(MQOL_TOT)) - num(first_nonmissing(MQOL_TOT)),
    YP_qolltif_summary_final = num(last_nonmissing(QOLF_TOT)),
    YP_delta_qolltif_summary = num(last_nonmissing(QOLF_TOT)) - num(first_nonmissing(QOLF_TOT)),
    YS_mqol_global_item_final = num(last_nonmissing(MQOLA)),
    YS_delta_mqol_global_item = num(last_nonmissing(MQOLA)) - num(first_nonmissing(MQOLA)),
    YS_qolltif_global_item_final = num(last_nonmissing(QOLFA)),
    YS_delta_qolltif_global_item = num(last_nonmissing(QOLFA)) - num(first_nonmissing(QOLFA)),
    X_observed_followup_periods = n(),
    .groups = "drop"
  )
trial81 <- qpss_baseline %>%
  transmute(
    MPLUSID,
    Treatment = factor(paste0("Arm_", Group), levels = c("Arm_2", "Arm_3")),
    X_participant_type = factor(MSDATA_P_type, levels = c(1, 2), labels = c("Patient", "Family caregiver")),
    X_mqol_summary_0m = num(MQOL_TOT),
    X_mqol_global_item_0m = num(MQOLA),
    X_qolltif_summary_0m = num(QOLF_TOT),
    X_qolltif_global_item_0m = num(QOLFA),
    X_age_years = num(Age_Valid),
    X_gender_code = num(Gender2),
    X_site = num(Site),
    X_income = num(Income),
    X_born_canada = num(BornCan),
    X_marital_4c = num(Marital_4C),
    X_education_4c = num(Educ_valid_4C),
    X_days_since_start = num(DaysSinceStart_min)
  ) %>%
  left_join(qpss_latest, by = "MPLUSID") %>%
  select(-MPLUSID) %>%
  write_trial(81)

# Trial 82: Smartphone physical-activity rewards/incentives
trial82_raw <- read_sav(file.path(extracted_dir, "RCTC-02392", "5. Processed Used Data", "5. Processed Used Data__MERGED Datafile formal analysis 200528.sav"))
trial82 <- tibble(
  Treatment = factor(as.character(as_factor(trial82_raw$Group)), levels = paste0("GR", 1:5)),
  YP_days_achieved_goal = num(trial82_raw[["@$daysAchievedGoal"]]),
  YS_adherent_days = num(trial82_raw$AdherentDays),
  YS_average_steps = num(trial82_raw[["@$averageSteps"]]),
  YS_sum_steps = num(trial82_raw[["@$sumOfSteps"]]),
  X_language = as.factor(as.character(as_factor(trial82_raw$Language))),
  X_historic_average_steps = na_if(num(trial82_raw[["@$historicAvgSteps"]]), -1),
  X_participation_days = num(trial82_raw[["@$participantParticipationInDays"]]),
  X_step_goal = num(trial82_raw[["@$stepGoal"]]),
  X_goal_difficulty = as.factor(as.character(trial82_raw[["@$goalDifficulty"]])),
  X_no_of_days = num(trial82_raw[["@$noOfDays"]])
) %>%
  write_trial(82)

# Trial 83: 2IUDnCT
iud <- read_tsv(file.path(download_dir, "RCTC-01479", "2IUD paper data.tab"), show_col_types = FALSE)
iud_baseline <- iud %>%
  filter(month == 0) %>%
  distinct(fakeid, .keep_all = TRUE)
iud_followup <- iud %>%
  filter(month > 0) %>%
  arrange(fakeid, month) %>%
  group_by(fakeid) %>%
  summarise(
    YP_gvl_detectable_6m = num(gvl[month == 6][1]),
    YP_gvl_detectable_24m = num(gvl[month == 24][1]),
    YP_gvl_detectable_any_6_24m = max_na(gvl[month %in% c(6, 24)]),
    YS_iud_removal_any_24m = max_na(iudremove),
    YS_iud_expulsion_any_24m = max_na(iudexpulsion),
    YS_any_rti_any_24m = max_na(anyrti),
    YS_pvl_detectable_6m = num(pvl[month == 6][1]),
    YS_pvl_detectable_24m = num(pvl[month == 24][1]),
    YS_cd4_final = num(last_nonmissing(cd4)),
    YS_delta_cd4_final = num(last_nonmissing(cd4)) - num(first_nonmissing(cd4)),
    .groups = "drop"
  )
trial83 <- iud_baseline %>%
  transmute(
    fakeid,
    Treatment = factor(arm, levels = c("C-IUD", "LNG IUD")),
    X_age_years = num(age),
    X_education = num(education),
    X_employed = num(employed),
    X_gravid = num(gravid),
    X_ever_pregnant = num(everpreg),
    X_sex_partners = num(sexparts),
    X_sex_frequency = num(sexfreq),
    X_art = num(art),
    X_hbg = num(hbg),
    X_cd4_0m = num(cd4),
    X_gvl_detectable_0m = num(gvl),
    X_pvl_detectable_0m = num(pvl)
  ) %>%
  left_join(iud_followup, by = "fakeid") %>%
  select(-fakeid) %>%
  write_trial(83)

# Trial 84: MPYA Study
mpya_q <- read_tsv(file.path(download_dir, "RCTC-01467", "questionnaire.tab"), show_col_types = FALSE)
mpya_adherence <- read_tsv(file.path(download_dir, "RCTC-01467", "adherence.tab"), show_col_types = FALSE)
mpya_dbs <- read_tsv(file.path(download_dir, "RCTC-01467", "dbs.tab"), show_col_types = FALSE)
mpya_base <- mpya_q %>%
  arrange(ptid, visitcode) %>%
  group_by(ptid) %>%
  slice(1) %>%
  ungroup()
mpya_ad_final <- mpya_adherence %>%
  arrange(ptid, visitcode) %>%
  group_by(ptid) %>%
  slice_tail(n = 1) %>%
  ungroup() %>%
  transmute(
    ptid,
    YP_prep_adherence_percent_final = num(prep_adh_p),
    YS_pharmacy_adherence_percent_final = num(pharm_adh_p),
    YS_prep_adherence_percent_month_final = num(prep_adh_m),
    YS_pharmacy_adherence_percent_month_final = num(pharm_adh_m)
  )
mpya_dbs_final <- mpya_dbs %>%
  arrange(ptid, visitcode) %>%
  group_by(ptid) %>%
  slice_tail(n = 1) %>%
  ungroup() %>%
  transmute(ptid, YS_dbs_tfvdp_adjusted_final = num(dbs_adj))
trial84 <- mpya_base %>%
  transmute(
    ptid,
    Treatment = factor(paste0("Arm_", arm), levels = c("Arm_0", "Arm_1")),
    X_site = num(site),
    X_screen_age_category = num(scrnage_cat),
    X_screen_sex = num(scrnsex),
    X_screen_score = num(scrnscore),
    X_education_years = num(eduyrs),
    X_job = num(demojob),
    X_marital = num(demomarry),
    X_depression_score = num(depress),
    X_depression_binary = num(depressbi),
    X_prep_stress = num(prepstress),
    X_necessity = num(necessity),
    X_concerns = num(concerns),
    X_self_esteem = num(selfesteem),
    X_ipv = num(ipv),
    X_hiv_stigma = num(hivstigma),
    X_prep_stigma = num(prepstigma)
  ) %>%
  left_join(mpya_ad_final, by = "ptid") %>%
  left_join(mpya_dbs_final, by = "ptid") %>%
  select(-ptid) %>%
  write_trial(84)

# Trial 85: Aprepitant for nausea/vomiting after sleeve gastrectomy
aprep <- read_excel(file.path(download_dir, "RCTC-01535", "Base Aprepitant.xlsx"), skip = 1, .name_repair = "unique") %>%
  filter(num_keep_999(Grupo) %in% c(1, 2, 3), !is.na(num(Folio)))
aprep_24h_score_cols <- names(aprep)[47:54]
aprep_nausea_24h_col <- names(aprep)[49]
aprep_vomiting_24h_col <- names(aprep)[52]
aprep_rescue_24h_col <- names(aprep)[55]
trial85 <- aprep %>%
  mutate(
    YS_rhodes_nausea_vomiting_score_24h = row_sum_na(select(., all_of(aprep_24h_score_cols))),
    YP_nausea_present_24h = as.integer(num(.data[[aprep_nausea_24h_col]]) > 0)
  ) %>%
  transmute(
    Treatment = factor(paste0("Arm_", num_keep_999(Grupo)), levels = c("Arm_1", "Arm_2", "Arm_3")),
    YP_nausea_present_24h,
    YS_rhodes_nausea_vomiting_score_24h,
    YS_nausea_intensity_24h = num(.data[[aprep_nausea_24h_col]]),
    YS_vomiting_episodes_24h = num(.data[[aprep_vomiting_24h_col]]),
    YS_rescue_medication_24h = num(.data[[aprep_rescue_24h_col]]),
    X_age_years = num(Edad),
    X_sex = num(Sexo),
    X_weight_kg = num(`Peso (kg)`),
    X_height_m = num(`Talla (m)`),
    X_bmi = num(IMC),
    X_operating_room = num(Sala),
    X_asa = num(ASA),
    X_surgery_duration_min = num(`Duracion Cx (Min)`)
  ) %>%
  write_trial(85)

# Trial 86: Tocovid and postoperative atrial fibrillation after CABG
tocovid <- read_tsv(file.path(download_dir, "RCTC-01411", "Raw Data Tocovid.tab"), show_col_types = FALSE)
trial86 <- tocovid %>%
  transmute(
    Treatment = factor(paste0("Arm_", Randomization), levels = c("Arm_1", "Arm_2")),
    YP_postoperative_atrial_fibrillation = if_else(num_keep_999(AF) == 999, NA_real_, num_keep_999(AF)),
    YS_af_episode_count = num(AFnumber),
    YS_ventilation_hours = num(Ventilation),
    YS_cicu_stay_days = num(CICUstay),
    YS_hdu_stay_days = num(HDUstay),
    YS_hospital_stay_days = num(HospStay),
    X_age_years = num(AGE),
    X_gender = num(GENDER),
    X_ethnicity = num(ETHNIC),
    X_euroscore = num(Euroscore),
    X_bmi = num(BMI),
    X_nyha = num(NYHA),
    X_left_atrial_size = num(LEFTAT_SIZE),
    X_right_atrial_size = num(RIGHTATsize),
    X_ejection_fraction = num(EF),
    X_diabetes = num(DM),
    X_hypertension = num(HPT),
    X_asthma = num(ASTHMA),
    X_copd = num(COPD),
    X_ckd = num(CKD),
    X_hypercholesterolemia = num(HYPERCHOL),
    X_smoker = num(SMOKER),
    X_alcohol = num(ALCOHOL),
    X_cross_clamp_time = num(XCLAMPTIME),
    X_bypass_time = num(BYPASSTIME)
  ) %>%
  write_trial(86)

# Trial 87: MyPlate versus calorie counting
myplate_anthro <- read_tsv(file.path(download_dir, "RCTC-01501", "MyPlate anthro public use.2023 03 21.tab"), show_col_types = FALSE)
myplate_survey <- read_tsv(file.path(download_dir, "RCTC-01501", "MyPlate svy data PCORI pub use data.2023 04 20.tab"), show_col_types = FALSE)
trial87 <- myplate_anthro %>%
  left_join(
    myplate_survey %>%
      select(subjid, hsf_1hungerx1, hsf_1hungerx3, hsf_2satisx1, hsf_2satisx3, full_3meal_rx1, full_3meal_rx3),
    by = "subjid"
  ) %>%
  transmute(
    Treatment = factor(paste0("Arm_", expcondx1), levels = c("Arm_1", "Arm_2")),
    YP_delta_hunger_day_x3_x1 = num(hsf_1hungerx3) - num(hsf_1hungerx1),
    YP_hunger_day_x3 = num(hsf_1hungerx3),
    YP_delta_satisfaction_last_meal_x3_x1 = num(hsf_2satisx3) - num(hsf_2satisx1),
    YP_satisfaction_last_meal_x3 = num(hsf_2satisx3),
    YP_delta_full_after_3_meals_x3_x1 = num(full_3meal_rx3) - num(full_3meal_rx1),
    YP_full_after_3_meals_x3 = num(full_3meal_rx3),
    YP_delta_weight_kg_x3_x1 = num(weight_measuredx3) - num(weight_measuredx1),
    YP_weight_kg_x3 = num(weight_measuredx3),
    YP_delta_waist_circumference_x3_x1 = num(waist_circ_measured_1x3) - num(waist_circ_measured_1x1),
    YP_waist_circumference_x3 = num(waist_circ_measured_1x3),
    X_age_years = num(sagex1),
    X_sex = num(ssexx1),
    X_education = num(educx1),
    X_ethnicity = num(ethnicityx1),
    X_hunger_day_x1 = num(hsf_1hungerx1),
    X_satisfaction_last_meal_x1 = num(hsf_2satisx1),
    X_full_after_3_meals_x1 = num(full_3meal_rx1),
    X_weight_kg_x1 = num(weight_measuredx1),
    X_waist_circumference_x1 = num(waist_circ_measured_1x1),
    X_systolic_bp_1_x1 = num(blood_press_sys_1x1),
    X_diastolic_bp_1_x1 = num(blood_press_dias_1x1)
  ) %>%
  write_trial(87)

# Trial 88: VR preoperative anxiety in children
vr_base <- file.path(download_dir, "RCTC-01824")
vr_assessment <- bind_rows(
  read_csv(file.path(vr_base, "control_assessment.csv"), show_col_types = FALSE) %>% mutate(Treatment = "Control"),
  read_csv(file.path(vr_base, "VR_assessment.csv"), show_col_types = FALSE) %>% mutate(Treatment = "VR")
)
vr_demographics <- bind_rows(
  read_csv(file.path(vr_base, "control_demographics.csv"), show_col_types = FALSE) %>% mutate(Treatment = "Control"),
  read_csv(file.path(vr_base, "VR_demographics.csv"), show_col_types = FALSE) %>% mutate(Treatment = "VR")
)
trial88 <- vr_assessment %>%
  left_join(vr_demographics, by = c("Code", "Treatment")) %>%
  transmute(
    Treatment = factor(Treatment, levels = c("Control", "VR")),
    YP_mypas_t1 = num(`mYPAS-T1`),
    YP_delta_mypas_t1_t0 = num(`mYPAS-T1`) - num(`mYPAS-T0`),
    YS_stai_state = num(`STAI-S`),
    YS_pss_total = num(`PSS-Total`),
    X_mypas_t0 = num(`mYPAS-T0`),
    X_stai_trait = num(`STAI-T`),
    X_age_years = num(Age),
    X_sex = as.factor(Sex),
    X_asa = num(ASA),
    X_subspecialty = as.factor(Subspecialty)
  ) %>%
  write_trial(88)

# Trial 89: Evolife web-based lifestyle intervention
evolife <- read_excel(file.path(download_dir, "RCTC-00485", "Evolife trial dataset.xlsx"), skip = 1, .name_repair = "unique")
trial89 <- evolife %>%
  transmute(
    Treatment = factor(paste0("Arm_", Group), levels = c("Arm_0", "Arm_1")),
    YP_delta_pal_t3_t1 = num(PAL_t3) - num(PAL_t1),
    YP_pal_t3 = num(PAL_t3),
    YP_delta_total_energy_intake_t3_t1 = num(`Total EI_t3`) - num(`Total EI_t1`),
    YP_total_energy_intake_t3 = num(`Total EI_t3`),
    YS_delta_steps_t3_t1 = num(Steps_t3) - num(Steps_t1),
    YS_steps_t3 = num(Steps_t3),
    YS_delta_mvpa_t3_t1 = num(MVPA_t3) - num(MVPA_t1),
    YS_delta_bmi_t3_t1 = num(BMI_t3) - num(BMI_t1),
    YS_delta_saturated_fat_t3_t1 = num(`Saturated fat_t3`) - num(`Saturated fat_t1`),
    X_age_years = num(Age),
    X_sex = num(Sex),
    X_ethnicity = num(Ethnicity),
    X_marital_status = num(`Marital status`),
    X_employment = num(Employment),
    X_education_level = num(`Education level`),
    X_imd = num(IMD),
    X_smoking_status = num(`Smoking status`),
    X_perceived_health = num(`Perceived health`),
    X_pal_t1 = num(PAL_t1),
    X_total_energy_intake_t1 = num(`Total EI_t1`),
    X_steps_t1 = num(Steps_t1),
    X_mvpa_t1 = num(MVPA_t1),
    X_bmi_t1 = num(BMI_t1),
    X_saturated_fat_t1 = num(`Saturated fat_t1`)
  ) %>%
  write_trial(89)

# Trial 90: Brain-IT exergame pilot RCT
brain_base <- file.path(download_dir, "RCTC-03815")
read_brain_study_results <- function(file_name, sheet_name) {
  raw <- read_excel(file.path(brain_base, file_name), sheet = sheet_name, col_names = FALSE, .name_repair = "minimal")
  names_row <- as.character(unlist(raw[4, ]))
  names_row[is.na(names_row) | names_row == ""] <- paste0("V", which(is.na(names_row) | names_row == ""))
  names(raw) <- make.unique(names_row)
  raw <- raw[-c(1:5), , drop = FALSE]
  raw <- raw[!is.na(raw[[1]]) & raw[[1]] != "", , drop = FALSE]
  raw
}
brain_baseline <- read_excel(
  file.path(brain_base, "3_Data_Other-Outcomes_Brain-IT-Pilot-Feasibility-RCT_for-publication.xlsx"),
  sheet = "Baseline Factors",
  skip = 1
) %>%
  filter(!is.na(pat_ID), pat_allocation %in% c("Usual Care", "Exergame"))
brain_secondary <- read_brain_study_results("2_Data_Secondary-Outcomes_Brain-IT-Pilot-Feasibility-RCT_for-publication.xlsx", "Study results") %>%
  filter(pat_allocation %in% c("Usual Care", "Exergame")) %>%
  transmute(
    pat_ID,
    YP_delta_qmci_score_post_pre = num(Qmci_score_tot_POST) - num(Qmci_score_tot_PRE),
    YP_qmci_score_post = num(Qmci_score_tot_POST),
    YS_dass_depression_post = num(DASS_21_depression_tot_score_POST),
    YS_dass_anxiety_post = num(DASS_21_anxiety_tot_score_POST),
    YS_dass_stress_post = num(DASS_21_stress_tot_score_POST),
    X_qmci_score_pre = num(Qmci_score_tot_PRE),
    X_dass_depression_pre = num(DASS_21_depression_tot_score_PRE),
    X_dass_anxiety_pre = num(DASS_21_anxiety_tot_score_PRE),
    X_dass_stress_pre = num(DASS_21_stress_tot_score_PRE)
  )
trial90 <- brain_baseline %>%
  transmute(
    pat_ID,
    Treatment = factor(pat_allocation, levels = c("Usual Care", "Exergame")),
    X_age_years = num(pat_age),
    X_sex = num(pat_sex),
    X_education_years = num(pat_education),
    X_height_m = num(pat_height),
    X_weight_kg = num(pat_weight),
    X_bmi = num(pat_bmi),
    X_activity = num(pat_activity),
    X_medication = num(pat_medication),
    X_category = as.factor(pat_category),
    X_clinical_subtype = as.factor(pat_clinicalsutype),
    X_usual_care = as.factor(pat_usualcare)
  ) %>%
  left_join(brain_secondary, by = "pat_ID") %>%
  select(-pat_ID) %>%
  write_trial(90)

# Trial 91: Bouldering psychotherapy versus CBT
bpt <- read_sav(file.path(download_dir, "RCTC-04054", "Repository_BPT CBT_Rohdaten.sav"))
sum_items <- function(data, columns) row_sum_na(data[, columns, drop = FALSE])
bpt_t0_phq <- sum_items(bpt, paste0("t0phq", 1:9))
bpt_t1_phq <- sum_items(bpt, paste0("t1phq", 1:9))
bpt_t4_phq <- sum_items(bpt, c("t4sphq1", paste0("t4phq", 2:9)))
bpt_t0_gad <- sum_items(bpt, paste0("t0gad_", 1:7))
bpt_t1_gad <- sum_items(bpt, paste0("t1gad_", 1:7))
bpt_t0_sigma <- sum_items(bpt, paste0("t0sigma_", 1:10))
bpt_t1_sigma <- sum_items(bpt, paste0("t1sigma_", 1:10))
trial91 <- tibble(
  Treatment = factor(as.character(as_factor(bpt$Gruppe_t0t1)), levels = c("CBT", "BPT")),
  YP_delta_madrs_post_pre = bpt_t1_sigma - bpt_t0_sigma,
  YP_madrs_post = bpt_t1_sigma,
  YP_delta_phq_post_pre = bpt_t1_phq - bpt_t0_phq,
  YP_phq_post = bpt_t1_phq,
  YS_phq_followup = bpt_t4_phq,
  YS_gad_post = bpt_t1_gad,
  X_phq_0w = bpt_t0_phq,
  X_gad_0w = bpt_t0_gad,
  X_madrs_0w = bpt_t0_sigma,
  X_sphq_0w = sum_items(bpt, paste0("SPHQ", 1:9)),
  X_dropout_50_percent = num(bpt$Abbruch50_dich)
) %>%
  write_trial(91)

# Trial 92: VRNT for chronic back pain
heal <- file.path(download_dir, "RCTC-05110", "HEAL_data.xlsx")
heal_subject <- read_excel(heal, sheet = "FINAL_SubjectLevel")
heal_pain <- read_excel(heal, sheet = "FINAL_Pain")
heal_pcs <- read_excel(heal, sheet = "FINAL_PCS")
heal_tsk <- read_excel(heal, sheet = "FINAL_TSK")
heal_olbp <- read_excel(heal, sheet = "FINAL_OLBP_SF12")
heal_promis <- read_excel(heal, sheet = "FINAL_PROMIS")
trial92 <- heal_subject %>%
  transmute(
    Subject_ID = `Subject ID`,
    Treatment = factor(Tx_WL, levels = c("WL", "Tx")),
    X_age_years = num(Age),
    X_sex = num(Sex_1M),
    X_bmi = num(BMI),
    X_pain_duration = num(Paindur),
    X_education_level = as.factor(Education_level_1_to_8),
    X_income = num(Income_no0),
    X_employed_status = num(Employed_Status)
  ) %>%
  left_join(
    heal_pain %>%
      transmute(
        Subject_ID,
        YP_delta_bpi_average_pain_post_pre = num(BPI4_pavg) - num(BPI1and2_pavg),
        YP_bpi_average_pain_post = num(BPI4_pavg),
        YS_bpi_average_pain_followup = num(BPI5_pavg),
        YS_bpi_interference_post = num(BPI4_ptot),
        YS_bpi_interference_followup = num(BPI5_ptot),
        X_bpi_average_pain_pre = num(BPI1and2_pavg),
        X_bpi_total_p1 = num(BPI1_ptot)
      ),
    by = "Subject_ID"
  ) %>%
  left_join(heal_pcs %>% transmute(Subject_ID = `Subject ID`, YS_pcs_total_p5 = num(PCS5_tot), X_pcs_total_p1 = num(PCS1_tot)), by = "Subject_ID") %>%
  left_join(heal_tsk %>% transmute(Subject_ID = `Subject ID`, YS_tsk_total_p5 = num(TSK5_total), X_tsk_total_p1 = num(TSK1_total)), by = "Subject_ID") %>%
  left_join(heal_olbp %>% transmute(Subject_ID = `Subject ID`, YS_olbp_total_p5 = num(OLBP5_total), YS_sf12_phys_p5 = num(SF5_Phys), YS_sf12_ment_p5 = num(SF5_Ment), X_olbp_total_p1 = num(OLBP1_total), X_sf12_phys_p1 = num(SF1_Phys), X_sf12_ment_p1 = num(SF1_Ment)), by = "Subject_ID") %>%
  left_join(heal_promis %>% transmute(Subject_ID = `Subject ID`, YS_promis_anxiety_p5 = num(P5_Anxiety), YS_promis_depression_p5 = num(P5_Dep), X_promis_anxiety_p1 = num(P1_Anxiety), X_promis_depression_p1 = num(P1_Dep)), by = "Subject_ID") %>%
  select(-Subject_ID) %>%
  write_trial(92)

# Trial 93: VIBRANT trial processed data
vibrant_base <- file.path(extracted_dir, "RCTC-05268", "mae_1_csv_export_20260109")
vibrant_read <- function(file_name) {
  read_csv(file.path(vibrant_base, file_name), show_col_types = FALSE)
}
vibrant_col <- vibrant_read("mae_1_csv_export_20260109__00_colData.csv") %>%
  filter(randomized == TRUE, !is.na(pid), !is.na(arm))
vibrant_participant <- vibrant_read("mae_1_csv_export_20260109__99_metadata__participant_crfs_merged.csv")
vibrant_visits <- vibrant_read("mae_1_csv_export_20260109__99_metadata__visits_crfs_merged.csv")
vibrant_lbp <- vibrant_read("mae_1_csv_export_20260109__01_col_LBP_mg__01_outcome.csv")
vibrant_crispatus <- vibrant_read("mae_1_csv_export_20260109__03_col_crispatus_mg__01_outcome.csv")
vibrant_assign <- vibrant_col %>%
  arrange(pid, visit_number, study_day) %>%
  group_by(pid) %>%
  summarise(
    Treatment = first_nonmissing(arm),
    X_site = first_nonmissing(site),
    X_location = first_nonmissing(location),
    X_itt = as.numeric(first_nonmissing(ITT)),
    X_mitt = as.numeric(first_nonmissing(mITT)),
    X_pp = as.numeric(first_nonmissing(PP)),
    .groups = "drop"
  )
vibrant_outcomes <- vibrant_col %>%
  left_join(vibrant_lbp, by = "mae_uid") %>%
  left_join(vibrant_crispatus, by = "mae_uid") %>%
  arrange(pid, visit_number, study_day) %>%
  group_by(pid) %>%
  summarise(
    YP_colonized_lbp_by_mg_first5w = max_na(colonized_LBP_by_mg[study_day <= 35]),
    YS_colonized_lbp_by_mg_final = binary_num(last_nonmissing(colonized_LBP_by_mg)),
    YS_colonized_lbp_at_mg_final = binary_num(last_nonmissing(colonized_LBP_at_mg)),
    YS_crispatus_dominance_by_mg_final = binary_num(last_nonmissing(crispatus_dominance_by_mg)),
    .groups = "drop"
  )
vibrant_visit_summary <- vibrant_col %>%
  select(pid, visit_code, visit_number, study_day) %>%
  left_join(vibrant_visits, by = c("pid", "visit_code")) %>%
  arrange(pid, visit_number, study_day.x, study_day.y) %>%
  group_by(pid) %>%
  summarise(
    X_nugent_total_score_baseline = num(first_nonmissing(nugent_total_score)),
    YS_nugent_total_score_final = num(last_nonmissing(nugent_total_score)),
    X_past_week_sex_partner_baseline = as.factor(first_nonmissing(past_week_sex_partner)),
    .groups = "drop"
  )
trial93 <- vibrant_assign %>%
  left_join(vibrant_participant %>%
    transmute(
      pid,
      X_age_years = num(age),
      X_race = as.factor(race),
      X_ethnicity = as.factor(ethn),
      X_cut_size_meals = as.factor(cut_size_meals),
      X_eat_less = as.factor(eat_less),
      X_hungry_did_not_eat = as.factor(hungry_did_not_eat),
      X_sexual_partners_lifetime = num(sexual_partners_lifetime),
      X_sexual_partners_past_month = num(sexual_partners_past_month)
    ), by = "pid") %>%
  left_join(vibrant_outcomes, by = "pid") %>%
  left_join(vibrant_visit_summary, by = "pid") %>%
  mutate(Treatment = factor(Treatment, levels = c("Pl", "LC106-3", "LC106-7", "LC106-o", "LC115"))) %>%
  select(-pid) %>%
  write_trial(93)

# Trial 94: Acceptance and stress reactivity after mindfulness training
lindsay <- read_sav(file.path(download_dir, "RCTC-04273", "LindsayData_PNE.sav"))
trial94 <- lindsay %>%
  mutate(Treatment_raw = as.character(as_factor(StudyCondition))) %>%
  filter(num(Exclude_0) == 1, !is.na(Treatment_raw)) %>%
  transmute(
    Treatment = factor(Treatment_raw, levels = c("Control", "MonitorOnly", "MonitorAccept")),
    YP_cortisol_auc_log_emreplace = num(Cort_AUC_I_log_EMreplace),
    YS_subjective_stress_overall = num(Subjective_Stress_Overall),
    X_age_years = num(Age),
    X_sex = num(Sex),
    X_bmi = num(BMI),
    X_race_a = as.factor(as.character(as_factor(Race_a))),
    X_race_b = as.factor(as.character(as_factor(Race_b))),
    X_race_c = as.factor(as.character(as_factor(Race_c))),
    X_ethnicity = as.factor(as.character(as_factor(Ethnicity))),
    X_education = as.factor(as.character(as_factor(Edu))),
    X_lessons_completed = num(Lessons_completed),
    X_expect_think = num(Expect2_think),
    X_expect_feel = num(Expect2_feel),
    X_expect_average = num(Expect2_average)
  ) %>%
  write_trial(94)

included_trials <- sort(trial_id_map$New_Trial_ID[trial_id_map$Final_Status == "active"])
validation <- map_dfr(included_trials, validate_trial)
write_csv(validation, file.path(prov_dir, "validation_summary_trials81_86.csv"))

data_dictionary <- map_dfr(included_trials, function(id) {
  d <- readRDS(file.path(clean_dir, paste0("trial", id, ".rds")))
  tibble(
    Trial_ID = id,
    variable_name = names(d),
    variable_type = map_chr(names(d), clean_variable_type),
    brief_explanation = map_chr(names(d), clean_variable_explanation)
  )
})
write_csv(data_dictionary, file.path(meta_dir, "data_dictionary_trials81_86.csv"))

primary_outcomes <- map_chr(included_trials, function(id) {
  d <- readRDS(file.path(clean_dir, paste0("trial", id, ".rds")))
  paste(names(d)[startsWith(names(d), "YP_")], collapse = "; ")
})

sample_sizes <- map_int(included_trials, function(id) {
  nrow(readRDS(file.path(clean_dir, paste0("trial", id, ".rds"))))
})

arm_counts <- map_int(included_trials, function(id) {
  d <- readRDS(file.path(clean_dir, paste0("trial", id, ".rds")))
  nlevels(as.factor(d$Treatment))
})

control_groups <- map_chr(included_trials, function(id) {
  d <- readRDS(file.path(clean_dir, paste0("trial", id, ".rds")))
  levels(as.factor(d$Treatment))[1]
})

active_qualified <- qualified %>%
  filter(Final_Status == "active") %>%
  arrange(New_Trial_ID)

meta_main <- active_qualified %>%
  transmute(
    Trial_ID = New_Trial_ID,
    `Trial Number/Name` = candidate_id,
    `Paper Name` = title,
    Journal = NA_character_,
    `Paper Link` = if_else(!is.na(doi), paste0("https://doi.org/", doi), NA_character_),
    `Publication Year` = NA_integer_,
    `# of Arm` = arm_counts,
    `Control Group` = control_groups,
    `Study Phase` = NA_character_,
    `Sample Size` = sample_sizes,
    `Priamry Outcome` = primary_outcomes,
    `Primary Outcome Type` = "Publication-audited cleaned outcome",
    `Trial Success(Primary Outcome Significant)` = NA_character_,
    `Statistical Model` = NA_character_,
    `Randomization Scheme` = "Individual randomization indicated by repository/publication-screening record and primary-publication audit",
    `Randomization Scheme(High Level)` = "Individual",
    `Research Area` = NA_character_,
    `Text Data` = "No",
    Citation = NA_character_
  )

provenance <- active_qualified %>%
  transmute(
    Trial_ID = New_Trial_ID,
    Original_Trial_ID,
    Candidate_ID = candidate_id,
    Repository = repository,
    Dataset_DOI = doi,
    License_Status = license_status,
    Publication_Status = publication_status,
    Download_Date = today,
    Source_Files = map_chr(Trial_ID, source_files_for_trial),
    Cleaning_Status = "active_after_publication_audit",
    Cleaning_Notes = "Cleaned from official downloaded files after download-first verification, primary-publication review, and outcome reproducibility audit. Original temporary trial IDs are stored in trials81_94_renumbering_map.csv.",
    Verification_Reasons = reasons
  )

write_xlsx(
  list(Sheet1 = meta_main, Provenance = provenance, Validation = validation),
  file.path(meta_dir, "meta_data_trials81_86_active.xlsx")
)

download_log <- provenance %>%
  transmute(
    Trial_ID,
    Repository,
    Dataset_DOI,
    Download_Date,
    Status = Cleaning_Status,
    Source_Files
  )
write_csv(download_log, file.path(prov_dir, "download_log_trials81_86.csv"))

flow_path <- file.path(prov_dir, "broad_dataset_screening_flow_counts.csv")
if (file.exists(flow_path)) {
  flow <- read_csv(flow_path, show_col_types = FALSE)
  flow <- flow %>% mutate(recorded_date = as.character(recorded_date))
  new_flow <- tibble(
    iteration_id = "trials81_86_active_after_audit_2026_06_09",
    recorded_date = today,
    stage_order = c(13, 14),
    stage_id = c("trials81_86_active_after_backup_renumbering", "trials81_86_active_contract_pass_after_renumbering"),
    parent_stage_id = c("trials81_94_final_analysis_ready_after_audit", "trials81_86_active_after_backup_renumbering"),
    node_label = c("Renumbered active trial81-trial86 datasets", "Renumbered active trial81-trial86 datasets passing structural contract"),
    count = c(length(included_trials), sum(validation$passes_contract)),
    node_kind = c("screening", "inclusion"),
    criteria = c(
      "Publication-audit-passing trial81-trial94 candidates were renumbered contiguously as active trial81-trial86; failures were moved to backup/B06-B13.",
      "Treatment has at least two levels, at least one YP_* outcome exists, CSV/RDS outputs load, and no duplicate names or exact duplicate columns are present after renumbering."
    ),
    source_output = c(
      "rct_expansion/provenance/trials81_94_renumbering_map.csv; rct_expansion/cleaned_data/trial81.csv through trial86.csv",
      "rct_expansion/provenance/validation_summary_trials81_86.csv"
    ),
    notes = c(
      "Active IDs are final IDs; original temporary IDs are retained only in provenance and backup folders.",
      "These six trials are the active post-audit branch after failed candidates were archived."
    )
  )
  flow <- flow %>%
    filter(!stage_id %in% new_flow$stage_id) %>%
    bind_rows(new_flow)
  write_csv(flow, flow_path)
}

validation
