library(tidyverse)
library(readxl)
library(writexl)

root <- "rct_expansion"
clean_dir <- file.path(root, "cleaned_data")
meta_dir <- file.path(root, "metadata")
prov_dir <- file.path(root, "provenance")
dir.create(meta_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(prov_dir, recursive = TRUE, showWarnings = FALSE)

today <- "2026-06-09"

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

current_trial_id <- function(original_trial_id) {
  m <- map_row(original_trial_id)
  if (m$Final_Status == "active") return(as.character(m$New_Trial_ID))
  m$Backup_ID
}

read_trial <- function(original_trial_id) {
  m <- map_row(original_trial_id)
  if (m$Final_Status == "active") {
    return(readRDS(file.path(clean_dir, paste0("trial", m$New_Trial_ID, ".rds"))))
  }
  readRDS(file.path(root, "backup", m$Backup_ID, "cleaned_data", paste0(m$Backup_ID, ".rds")))
}

arm_subset <- function(d, trial_id, arm) {
  treatment <- as.character(d$Treatment)
  if (is.na(arm) || arm == "Overall") return(d)

  trial_id <- as.character(trial_id)
  idx <- rep(FALSE, nrow(d))
  if (trial_id == "85" && arm == "Placebo") idx <- treatment == "Arm_1"
  else if (trial_id == "85" && arm == "Aprepitant") idx <- treatment %in% c("Arm_2", "Arm_3")
  else if (trial_id == "87" && arm == "MyPlate") idx <- treatment == "Arm_1"
  else if (trial_id == "87" && arm == "Calorie Counting") idx <- treatment == "Arm_2"
  else if (trial_id == "89" && arm == "Control") idx <- treatment == "Arm_0"
  else if (trial_id == "89" && arm == "Intervention") idx <- treatment == "Arm_1"
  else if (trial_id == "92" && arm == "Control") idx <- treatment == "WL"
  else if (trial_id == "92" && arm == "VRNT") idx <- treatment == "Tx"
  else if (trial_id == "93" && arm == "Active mITT") idx <- treatment != "Pl" & d$X_mitt == 1
  else if (trial_id == "93" && arm == "Placebo mITT") idx <- treatment == "Pl" & d$X_mitt == 1
  else if (trial_id == "94" && arm == "Monitor + Accept") idx <- treatment == "MonitorAccept"
  else if (trial_id == "94" && arm == "Monitor Only") idx <- treatment == "MonitorOnly"
  else if (trial_id == "94" && arm == "Control") idx <- treatment == "Control"
  else idx <- treatment == arm

  d[which(idx), , drop = FALSE]
}

cleaned_stat <- function(original_trial_id, outcome_variable, arm, statistic) {
  d <- read_trial(original_trial_id)
  if (!outcome_variable %in% names(d)) return(NA_real_)
  dd <- arm_subset(d, original_trial_id, arm)
  if (nrow(dd) == 0) return(NA_real_)
  x <- suppressWarnings(as.numeric(dd[[outcome_variable]]))
  x <- x[!is.na(x)]
  if (length(x) == 0) return(NA_real_)

  switch(
    statistic,
    mean = mean(x),
    sd = sd(x),
    n = length(x),
    sum = sum(x),
    event_count = sum(x > 0),
    percent = 100 * mean(x == 1),
    event_percent = 100 * mean(x > 0),
    NA_real_
  )
}

publication_review <- tribble(
  ~Trial_ID, ~Candidate_ID, ~Primary_Publication_Found, ~Paper_Name, ~Journal, ~Publication_Year, ~Paper_DOI, ~Paper_Link, ~Dataset_DOI, ~Repository, ~Sample_Size_Paper, ~Cleaned_N, ~Arms_Paper, ~Control_Group, ~Primary_Outcome_From_Publication, ~Cleaned_Primary_Outcome, ~Statistical_Model, ~Randomization_Scheme, ~Publication_Review_Status, ~Outcome_Audit_Status, ~Decision, ~Review_Notes,
  81, "RCTC-02120", TRUE, "Quality of Life Assessment and Practice Support System randomized trial", "PLOS One", 2025, "10.1371/journal.pone.0320306", "https://doi.org/10.1371/journal.pone.0320306", "10.5683/sp3/a4jg2r", "Borealis", "442 randomized patients", 442, "2", "Control/usual care arm in paper", "Patient MQOL-E at one year; caregiver QOLLTI-F secondary", "YP_mqol_total_final; YP_delta_mqol_total", "Longitudinal structural equation model with missing-at-random handling", "Individual randomization", "primary_publication_reviewed", "not_auditable_model_target", "not_analysis_ready_after_audit", "Paper reports model-based one-year intervention effects; compact cleaned endpoint/delta summaries do not reproduce the longitudinal SEM target.",
  82, "RCTC-02392", TRUE, "MobileCoach physical activity financial incentives randomized trial", "JMIR mHealth and uHealth", 2022, "10.2196/38339", "https://doi.org/10.2196/38339", "10.34894/g3koyt", "DataverseNL", "96 in effectiveness analysis; 65 in goal-tailoring primary subset", 133, "5", "No-incentive/control group", "Number of days, from 0 to 20, that the tailored step goal was achieved", "YP_days_achieved_goal", "Restricted effectiveness analysis with exclusions for untailored goals and selected participants", "Individual randomization", "primary_publication_reviewed", "analysis_filter_not_reconstructed", "not_analysis_ready_after_audit", "The source includes syntax for the paper filter, but the compact cleaned data do not contain all paper filter variables and include 133 participants.",
  83, "RCTC-01479", TRUE, "Effects of copper intrauterine device versus levonorgestrel intrauterine system on genital HIV viral load", "PLOS Medicine", 2020, "10.1371/journal.pmed.1003110", "https://doi.org/10.1371/journal.pmed.1003110", "10.7910/dvn/ntn7ky", "Harvard Dataverse", "199 randomized women", 199, "2", "Copper IUD", "Detectable genital HIV viral load at 6 and 24 months", "YP_gvl_detectable_6m; YP_gvl_detectable_24m; YP_gvl_detectable_any_6_24m", "Adjusted generalized estimating equation/as-treated models", "Individual 1:1 randomization", "primary_publication_reviewed", "model_not_reproduced", "not_analysis_ready_after_audit", "Cleaned data contain the gVL outcomes, but the paper primary target is an adjusted longitudinal odds ratio not reproduced by the compact audit.",
  84, "RCTC-01467", TRUE, "Monitoring PrEP in Young Adult women randomized trial", "Lancet HIV", 2021, "10.1016/S2352-3018(20)30307-6", "https://doi.org/10.1016/S2352-3018(20)30307-6", "10.7910/dvn/ppqksw", "Harvard Dataverse", "348 randomized participants", 348, "2", "Standard adherence support/control arm", "PrEP adherence over 24 months by real-time electronic monitoring", "YP_prep_adherence_percent_final", "Negative binomial models adjusted for site and quarterly visit among PrEP collectors", "Individual randomization", "primary_publication_reviewed", "not_auditable_longitudinal_target", "not_analysis_ready_after_audit", "The paper primary target is visit-level longitudinal adherence; the preliminary cleaned table keeps a compact final adherence percentage.",
  85, "RCTC-01535", TRUE, "Aprepitant for prevention of postoperative nausea and vomiting after laparoscopic sleeve gastrectomy", "Obesity Surgery", 2024, "10.1007/s11695-024-07129-0", "https://doi.org/10.1007/s11695-024-07129-0", "10.7910/dvn/cf2lgp", "Harvard Dataverse", "400 with 24-hour outcome denominators", 401, "3 source arms; paper combines aprepitant arms", "Placebo", "Nausea/PONV at 24 hours", "YP_nausea_present_24h", "Arm-level count/rate comparisons", "Individual randomization", "primary_publication_reviewed", "primary_target_pass", "analysis_ready", "The paper's 24-hour nausea/PONV counts reproduce from nonmissing source outcomes after combining aprepitant dose arms.",
  86, "RCTC-01411", TRUE, "Effect of Tocovid on postoperative atrial fibrillation after CABG", "Reviews in Cardiovascular Medicine", 2022, "10.31083/j.rcm2304122", "https://doi.org/10.31083/j.rcm2304122", "10.7910/dvn/xgdwg5", "Harvard Dataverse", "250 randomized patients", 250, "2", "Placebo/control arm", "Occurrence of postoperative atrial fibrillation", "YP_postoperative_atrial_fibrillation", "Arm-level and overall event summaries", "Individual randomization", "primary_publication_reviewed", "primary_target_pass", "analysis_ready", "The overall POAF event count and rate reproduce exactly from the cleaned binary outcome.",
  87, "RCTC-01501", TRUE, "Randomized comparative effectiveness trial of MyPlate versus calorie counting among Latino adults", "Annals of Family Medicine", 2023, "10.1370/afm.2964", "https://doi.org/10.1370/afm.2964", "10.7910/dvn/jo6og9", "Harvard Dataverse", "261 randomized participants", 261, "2", "Calorie Counting comparator", "Satiation/satiety, body weight, and waist circumference", "Patient-centered survey outcomes; weight and waist outcomes", "Adjusted comparative effectiveness models", "Individual randomization", "primary_publication_reviewed", "adjusted_target_not_reproduced", "not_analysis_ready_after_audit", "Arm labels were verified in the codebook, but the paper's adjusted weight target is not reproduced by simple cleaned means.",
  88, "RCTC-01824", FALSE, "Immersive virtual reality exposure for reducing preoperative anxiety in children", NA_character_, NA_integer_, NA_character_, "https://doi.org/10.17632/psxdxfw37t.1", "10.17632/psxdxfw37t.1", "Mendeley Data", "No main publication found", 72, "2", "Control", "Protocol/registry mYPAS outcome only", "YP_mypas_t1; YP_delta_mypas_t1_t0", NA_character_, "Individual randomization indicated by dataset/registry", "no_primary_publication_found", "no_publication_audit_possible", "exclude_no_primary_publication", "I found dataset and registry information but no associated main results publication, so no primary-publication audit can be completed.",
  89, "RCTC-00485", TRUE, "Effects of a web-based evolutionary mismatch-framed intervention targeting physical activity and diet", "International Journal of Behavioral Medicine", 2019, "10.1007/s12529-019-09821-3", "https://doi.org/10.1007/s12529-019-09821-3", "10.15125/bath-01245", "University of Bath", "59 completed participants", 59, "2", "Control", "Daily physical activity level and total energy intake at 12 weeks", "YP_delta_pal_t3_t1; YP_delta_total_energy_intake_t3_t1", "ANCOVA/adjusted mean difference with descriptive change summaries", "Individual randomization", "primary_publication_reviewed", "primary_target_pass_with_rounding_note", "analysis_ready", "Primary PAL and total-energy-intake change summaries reproduce the table values; one near-zero rounded PAL row is flagged by strict 5 percent tolerance.",
  90, "RCTC-03815", TRUE, "Feasibility, usability and acceptance of Brain-IT pilot feasibility RCT", "Frontiers in Aging Neuroscience", 2023, "10.3389/fnagi.2023.1163388", "https://doi.org/10.3389/fnagi.2023.1163388", "10.5281/zenodo.7428377", "Zenodo", "18 included; 16 randomized into usual care/exergame in current cleaned file", 16, "2 randomized arms plus feasibility records", "Usual care", "Recruitment, attrition, adherence, compliance, SUS, and acceptance feasibility outcomes", "YP_delta_qmci_score_post_pre; YP_qmci_score_post", "Feasibility/usability descriptive summaries", "Individual pilot randomization", "primary_publication_reviewed", "cleaned_primary_mismatch", "needs_reclean_to_publication_primary", "The current cleaned file uses secondary cognitive Qmci outcomes and excludes two feasibility records; it needs recleaning around the paper primary feasibility outcomes.",
  91, "RCTC-04054", TRUE, "Bouldering psychotherapy is not inferior to cognitive behavioural therapy in the group treatment of depression", "British Journal of Clinical Psychology", 2022, "10.1111/bjc.12347", "https://doi.org/10.1111/bjc.12347", "10.5281/zenodo.5645183", "Zenodo", "156 ITT participants", 156, "2", "CBT comparator", "Depressive symptom severity assessed by MADRS and PHQ-9", "YP_delta_madrs_post_pre; YP_madrs_post; YP_delta_phq_post_pre; YP_phq_post", "Mixed-model ANOVA and non-inferiority comparisons", "Individual randomization", "primary_publication_reviewed", "madrs_primary_target_pass_phq_partial", "analysis_ready_with_notes", "MADRS primary pre/post/change targets reproduce within tolerance; one PHQ-9 CBT change row is outside the strict 5 percent tolerance.",
  92, "RCTC-05110", TRUE, "Virtual reality neuroscience therapy for chronic back pain", "Pain", 2024, "10.1097/j.pain.0000000000003198", "https://doi.org/10.1097/j.pain.0000000000003198", "10.5281/zenodo.17715051", "Zenodo", "61 randomized participants", 61, "2", "Wait-list control", "Brief Pain Inventory average pain intensity after treatment", "YP_delta_bpi_average_pain_post_pre; YP_bpi_average_pain_post", "Group comparisons of clinical pain outcomes", "Individual randomization", "primary_publication_reviewed", "primary_target_pass", "analysis_ready", "Baseline and post-treatment BPI average pain means and SDs reproduce the reported table values.",
  93, "RCTC-05268", TRUE, "VIBRANT trial primary and secondary outcomes", "medRxiv preprint", 2025, "10.1101/2025.09.18.25336053", "https://doi.org/10.1101/2025.09.18.25336053", "10.5281/zenodo.18201511", "Zenodo", "96 randomized participants; 71 active mITT in primary detection target", 96, "5", "Placebo", "Detection of L. crispatus LBP strains by metagenomic sequencing in first five weeks", "YP_colonized_lbp_by_mg_first5w", "Primary safety and microbiome detection summaries", "Individual randomization", "primary_publication_reviewed", "primary_target_pass", "analysis_ready", "The active-arm mITT count 47 of 71 reproduces the preprint primary microbiome detection target.",
  94, "RCTC-04273", TRUE, "Acceptance lowers stress reactivity: Dismantling mindfulness training in a randomized controlled trial", "Psychoneuroendocrinology", 2018, "10.1016/j.psyneuen.2017.09.015", "https://doi.org/10.1016/j.psyneuen.2017.09.015", "10.17632/bx2gvkty4c.1", "Mendeley Data", "153 randomized; 144 in mTSST sample", 153, "3", "Stress-management control", "Stress reactivity, especially log cortisol AUC-I after mTSST", "YP_cortisol_auc_log_emreplace", "Condition comparisons with EM estimation and covariate adjustment", "Individual randomization", "primary_publication_reviewed", "partial_fail_exact_sample_rule", "not_analysis_ready_after_audit", "Control and monitor-only cortisol means are close, but the Monitor + Accept AUC-I target does not reproduce from the compact cleaned data."
) %>%
  rename(Original_Trial_ID = Trial_ID) %>%
  left_join(trial_id_map, by = "Original_Trial_ID") %>%
  mutate(Trial_ID = map_chr(Original_Trial_ID, current_trial_id)) %>%
  relocate(Trial_ID, Original_Trial_ID)

targets <- tribble(
  ~Trial_ID, ~outcome_variable, ~outcome_role, ~arm, ~statistic, ~paper_value, ~paper_precision, ~paper_source, ~notes, ~status_override,
  "81", "YP_delta_mqol_total", "primary", "Intervention effect", "model_effect", -0.01, 0.01, "QPSS PLOS One 2025 results", "One-year patient MQOL-E intervention effect from longitudinal SEM; compact cleaned endpoint cannot reproduce model estimate.", "not_auditable_model_target",
  "82", "YP_days_achieved_goal", "primary", "Restricted effectiveness sample", "mean", NA_real_, NA_real_, "MobileCoach JMIR 2022 results and analysis syntax", "Primary outcome is days achieved goal among a restricted tailored-goal effectiveness subset; filter variables are not fully represented in cleaned data.", "analysis_filter_not_reconstructed",
  "83", "YP_gvl_detectable_6m", "primary", "LNG IUD vs C-IUD", "adjusted_odds_ratio", 0.78, 0.01, "2IUDnCT PLOS Medicine 2020 abstract/results", "Paper target is adjusted odds ratio at 6 months, not a simple arm summary.", "model_not_reproduced",
  "83", "YP_gvl_detectable_24m", "primary", "LNG IUD vs C-IUD", "adjusted_odds_ratio", 1.03, 0.01, "2IUDnCT PLOS Medicine 2020 abstract/results", "Paper target is adjusted odds ratio at 24 months, not a simple arm summary.", "model_not_reproduced",
  "84", "YP_prep_adherence_percent_final", "primary", "Intervention effect", "negative_binomial_effect", NA_real_, NA_real_, "MPYA Lancet HIV 2021 methods/results", "Primary adherence target is longitudinal electronic-monitor data analyzed by negative binomial models.", "not_auditable_longitudinal_target",
  "85", "YP_nausea_present_24h", "primary", "Placebo", "sum", 67, 1, "Aprepitant Obesity Surgery 2024 abstract/results", "24-hour nausea/PONV event count.", NA_character_,
  "85", "YP_nausea_present_24h", "primary", "Aprepitant", "sum", 22, 1, "Aprepitant Obesity Surgery 2024 abstract/results", "24-hour nausea/PONV event count after combining aprepitant dose arms.", NA_character_,
  "85", "YP_nausea_present_24h", "primary", "Placebo", "percent", 33.7, 0.1, "Aprepitant Obesity Surgery 2024 abstract/results", "24-hour nausea/PONV event percent among nonmissing outcomes.", NA_character_,
  "85", "YP_nausea_present_24h", "primary", "Aprepitant", "percent", 10.9, 0.1, "Aprepitant Obesity Surgery 2024 abstract/results", "24-hour nausea/PONV event percent among nonmissing outcomes.", NA_character_,
  "85", "YS_vomiting_episodes_24h", "secondary", "Placebo", "event_count", 6, 1, "Aprepitant Obesity Surgery 2024 abstract/results", "24-hour vomiting event count.", NA_character_,
  "85", "YS_vomiting_episodes_24h", "secondary", "Aprepitant", "event_count", 1, 1, "Aprepitant Obesity Surgery 2024 abstract/results", "24-hour vomiting event count.", NA_character_,
  "85", "YS_rescue_medication_24h", "secondary", "Placebo", "event_count", 11, 1, "Aprepitant Obesity Surgery 2024 abstract/results", "24-hour rescue-medication event count.", NA_character_,
  "85", "YS_rescue_medication_24h", "secondary", "Aprepitant", "event_count", 5, 1, "Aprepitant Obesity Surgery 2024 abstract/results", "24-hour rescue-medication event count.", NA_character_,
  "86", "YP_postoperative_atrial_fibrillation", "primary", "Overall", "sum", 88, 1, "Tocovid RCM 2022 Table 2", "Overall postoperative atrial fibrillation count.", NA_character_,
  "86", "YP_postoperative_atrial_fibrillation", "primary", "Overall", "percent", 35.2, 0.1, "Tocovid RCM 2022 Table 2", "Overall postoperative atrial fibrillation percent.", NA_character_,
  "87", "YP_delta_weight_kg_x3_x1", "primary", "MyPlate", "mean", -0.34, 0.01, "MyPlate Annals of Family Medicine 2023 abstract/results", "Reported adjusted body-weight change in kg.", NA_character_,
  "87", "YP_delta_weight_kg_x3_x1", "primary", "Calorie Counting", "mean", -0.75, 0.01, "MyPlate Annals of Family Medicine 2023 abstract/results", "Reported adjusted body-weight change in kg.", NA_character_,
  "88", "YP_mypas_t1", "primary", "VR vs Control", "mean", NA_real_, NA_real_, "Dataset and registry search", "No associated main results publication found.", "no_primary_publication_found",
  "89", "YP_delta_pal_t3_t1", "primary", "Intervention", "mean", 0.06, 0.01, "Evolife Int J Behav Med 2019 Table 3", "Change in daily PAL from baseline to 12 weeks.", NA_character_,
  "89", "YP_delta_pal_t3_t1", "primary", "Intervention", "sd", 0.15, 0.01, "Evolife Int J Behav Med 2019 Table 3", "Change in daily PAL from baseline to 12 weeks.", NA_character_,
  "89", "YP_delta_pal_t3_t1", "primary", "Control", "mean", 0.01, 0.01, "Evolife Int J Behav Med 2019 Table 3", "Change in daily PAL from baseline to 12 weeks; paper rounded near zero.", NA_character_,
  "89", "YP_delta_pal_t3_t1", "primary", "Control", "sd", 0.16, 0.01, "Evolife Int J Behav Med 2019 Table 3", "Change in daily PAL from baseline to 12 weeks.", NA_character_,
  "89", "YP_delta_total_energy_intake_t3_t1", "primary", "Intervention", "mean", -431, 1, "Evolife Int J Behav Med 2019 Table 3", "Change in total energy intake, kcal/day, from baseline to 12 weeks.", NA_character_,
  "89", "YP_delta_total_energy_intake_t3_t1", "primary", "Intervention", "sd", 694, 1, "Evolife Int J Behav Med 2019 Table 3", "Change in total energy intake, kcal/day, from baseline to 12 weeks.", NA_character_,
  "89", "YP_delta_total_energy_intake_t3_t1", "primary", "Control", "mean", -124, 1, "Evolife Int J Behav Med 2019 Table 3", "Change in total energy intake, kcal/day, from baseline to 12 weeks.", NA_character_,
  "89", "YP_delta_total_energy_intake_t3_t1", "primary", "Control", "sd", 535, 1, "Evolife Int J Behav Med 2019 Table 3", "Change in total energy intake, kcal/day, from baseline to 12 weeks.", NA_character_,
  "90", "YP_delta_qmci_score_post_pre", "primary", "Exergame", "mean", NA_real_, NA_real_, "Brain-IT Front Aging Neurosci 2023 abstract/results", "Current cleaned primary is Qmci, while publication primary outcomes are feasibility, usability, and acceptance.", "cleaned_primary_mismatch",
  "91", "X_madrs_0w", "primary_baseline", "BPT", "mean", 23.46, 0.01, "Bouldering psychotherapy BJC 2022 Table 3", "MADRS pre-test ITT mean.", NA_character_,
  "91", "YP_madrs_post", "primary", "BPT", "mean", 15.40, 0.01, "Bouldering psychotherapy BJC 2022 Table 3", "MADRS post-test ITT mean.", NA_character_,
  "91", "YP_delta_madrs_post_pre", "primary", "BPT", "mean", -8.06, 0.01, "Bouldering psychotherapy BJC 2022 Table 3", "MADRS post-pre ITT change.", NA_character_,
  "91", "YP_delta_madrs_post_pre", "primary", "BPT", "sd", 10.15, 0.01, "Bouldering psychotherapy BJC 2022 Table 3", "MADRS post-pre ITT change.", NA_character_,
  "91", "X_madrs_0w", "primary_baseline", "CBT", "mean", 24.04, 0.01, "Bouldering psychotherapy BJC 2022 Table 3", "MADRS pre-test ITT mean.", NA_character_,
  "91", "YP_madrs_post", "primary", "CBT", "mean", 18.05, 0.01, "Bouldering psychotherapy BJC 2022 Table 3", "MADRS post-test ITT mean.", NA_character_,
  "91", "YP_delta_madrs_post_pre", "primary", "CBT", "mean", -5.99, 0.01, "Bouldering psychotherapy BJC 2022 Table 3", "MADRS post-pre ITT change.", NA_character_,
  "91", "YP_delta_madrs_post_pre", "primary", "CBT", "sd", 9.17, 0.01, "Bouldering psychotherapy BJC 2022 Table 3", "MADRS post-pre ITT change.", NA_character_,
  "91", "X_phq_0w", "primary", "BPT", "mean", 13.66, 0.01, "Bouldering psychotherapy BJC 2022 Table 3", "PHQ-9 pre-test ITT mean.", NA_character_,
  "91", "YP_phq_post", "primary", "BPT", "mean", 9.03, 0.01, "Bouldering psychotherapy BJC 2022 Table 3", "PHQ-9 post-test ITT mean.", NA_character_,
  "91", "YP_delta_phq_post_pre", "primary", "BPT", "mean", -4.63, 0.01, "Bouldering psychotherapy BJC 2022 Table 3", "PHQ-9 post-pre ITT change.", NA_character_,
  "91", "YP_delta_phq_post_pre", "primary", "BPT", "sd", 6.13, 0.01, "Bouldering psychotherapy BJC 2022 Table 3", "PHQ-9 post-pre ITT change.", NA_character_,
  "91", "X_phq_0w", "primary", "CBT", "mean", 13.81, 0.01, "Bouldering psychotherapy BJC 2022 Table 3", "PHQ-9 pre-test ITT mean.", NA_character_,
  "91", "YP_phq_post", "primary", "CBT", "mean", 10.35, 0.01, "Bouldering psychotherapy BJC 2022 Table 3", "PHQ-9 post-test ITT mean.", NA_character_,
  "91", "YP_delta_phq_post_pre", "primary", "CBT", "mean", -3.46, 0.01, "Bouldering psychotherapy BJC 2022 Table 3", "PHQ-9 post-pre ITT change.", NA_character_,
  "91", "YP_delta_phq_post_pre", "primary", "CBT", "sd", 5.67, 0.01, "Bouldering psychotherapy BJC 2022 Table 3", "PHQ-9 post-pre ITT change.", NA_character_,
  "92", "X_bpi_average_pain_pre", "primary_baseline", "VRNT", "mean", 4.0, 0.1, "VRNT Pain 2024 Table 2", "BPI-SF average pain at baseline.", NA_character_,
  "92", "X_bpi_average_pain_pre", "primary_baseline", "VRNT", "sd", 1.2, 0.1, "VRNT Pain 2024 Table 2", "BPI-SF average pain at baseline.", NA_character_,
  "92", "X_bpi_average_pain_pre", "primary_baseline", "Control", "mean", 4.3, 0.1, "VRNT Pain 2024 Table 2", "BPI-SF average pain at baseline.", NA_character_,
  "92", "X_bpi_average_pain_pre", "primary_baseline", "Control", "sd", 1.4, 0.1, "VRNT Pain 2024 Table 2", "BPI-SF average pain at baseline.", NA_character_,
  "92", "YP_bpi_average_pain_post", "primary", "VRNT", "mean", 2.5, 0.1, "VRNT Pain 2024 Table 2", "BPI-SF average pain after treatment.", NA_character_,
  "92", "YP_bpi_average_pain_post", "primary", "VRNT", "sd", 1.6, 0.1, "VRNT Pain 2024 Table 2", "BPI-SF average pain after treatment.", NA_character_,
  "92", "YP_bpi_average_pain_post", "primary", "Control", "mean", 3.8, 0.1, "VRNT Pain 2024 Table 2", "BPI-SF average pain after treatment.", NA_character_,
  "92", "YP_bpi_average_pain_post", "primary", "Control", "sd", 1.8, 0.1, "VRNT Pain 2024 Table 2", "BPI-SF average pain after treatment.", NA_character_,
  "93", "YP_colonized_lbp_by_mg_first5w", "primary", "Active mITT", "sum", 47, 1, "VIBRANT medRxiv 2025 primary results", "Active-arm mITT participants with at least one LBP strain detected in first five weeks.", NA_character_,
  "93", "YP_colonized_lbp_by_mg_first5w", "primary", "Active mITT", "percent", 66.1, 0.1, "VIBRANT medRxiv 2025 primary results", "Active-arm mITT percent with at least one LBP strain detected in first five weeks.", NA_character_,
  "94", "YP_cortisol_auc_log_emreplace", "primary", "Monitor + Accept", "mean", -2.25, 0.01, "Lindsay Psychoneuroendocrinology 2018 Table 2", "Log cortisol AUC-I, EM-estimated mean in mTSST sample.", NA_character_,
  "94", "YP_cortisol_auc_log_emreplace", "primary", "Monitor Only", "mean", 23.23, 0.01, "Lindsay Psychoneuroendocrinology 2018 Table 2", "Log cortisol AUC-I, EM-estimated mean in mTSST sample.", NA_character_,
  "94", "YP_cortisol_auc_log_emreplace", "primary", "Control", "mean", 27.62, 0.01, "Lindsay Psychoneuroendocrinology 2018 Table 2", "Log cortisol AUC-I, EM-estimated mean in mTSST sample.", NA_character_,
  "94", "YS_subjective_stress_overall", "secondary", "Monitor + Accept", "mean", 48.53, 0.01, "Lindsay Psychoneuroendocrinology 2018 Table 2", "Subjective stress reactivity.", NA_character_,
  "94", "YS_subjective_stress_overall", "secondary", "Monitor Only", "mean", 48.52, 0.01, "Lindsay Psychoneuroendocrinology 2018 Table 2", "Subjective stress reactivity.", NA_character_,
  "94", "YS_subjective_stress_overall", "secondary", "Control", "mean", 51.55, 0.01, "Lindsay Psychoneuroendocrinology 2018 Table 2", "Subjective stress reactivity.", NA_character_
) %>%
  rename(Original_Trial_ID = Trial_ID) %>%
  mutate(Original_Trial_ID = as.integer(Original_Trial_ID)) %>%
  left_join(trial_id_map, by = "Original_Trial_ID") %>%
  mutate(Trial_ID = map_chr(Original_Trial_ID, current_trial_id)) %>%
  relocate(Trial_ID, Original_Trial_ID)

computed <- targets %>%
  mutate(
    cleaned_value = pmap_dbl(
      list(Original_Trial_ID, outcome_variable, arm, statistic),
      cleaned_stat
    ),
    absolute_diff = abs(cleaned_value - paper_value),
    tolerance = abs(paper_value) * 0.05,
    status = case_when(
      !is.na(status_override) ~ status_override,
      is.na(paper_value) | is.na(cleaned_value) ~ "insufficient_information",
      absolute_diff <= tolerance ~ "pass",
      TRUE ~ "fail"
    )
  ) %>%
  select(Trial_ID, Original_Trial_ID, outcome_variable, outcome_role, arm, statistic, paper_value,
         paper_precision, cleaned_value, absolute_diff, tolerance, status,
         paper_source, notes)

audit_decisions <- publication_review %>%
  transmute(
    Trial_ID,
    Original_Trial_ID,
    Candidate_ID,
    Primary_Publication_Found,
    Outcome_Audit_Status,
    Decision,
    Analysis_Ready = Decision %in% c("analysis_ready", "analysis_ready_with_notes"),
    Blocking_Reason = case_when(
      Decision %in% c("analysis_ready", "analysis_ready_with_notes") ~ NA_character_,
      Decision == "exclude_no_primary_publication" ~ "No associated main results publication identified.",
      Decision == "needs_reclean_to_publication_primary" ~ "Cleaned primary outcomes do not match the publication primary outcomes.",
      TRUE ~ "Publication primary target was model-based, longitudinal, filtered, or otherwise not reproduced by the compact cleaned data."
    ),
    Next_Action = case_when(
      Decision == "analysis_ready" ~ "Eligible for final active trial81-trial86 analysis-ready set.",
      Decision == "analysis_ready_with_notes" ~ "Eligible if MADRS is treated as the auditable primary outcome; recalc PHQ before using it as co-primary.",
      Decision == "exclude_no_primary_publication" ~ "Archived under backup/Bxx until a valid main publication is found.",
      Decision == "needs_reclean_to_publication_primary" ~ "Reclean around feasibility/usability primary outcomes before re-auditing.",
      TRUE ~ "Archived under backup/Bxx unless the exact publication model/filter is implemented and passes."
    ),
    Review_Notes
  )

meta_main <- publication_review %>%
  filter(Final_Status == "active") %>%
  transmute(
    Trial_ID = as.integer(Trial_ID),
    `Trial Number/Name` = Candidate_ID,
    `Paper Name` = Paper_Name,
    Journal,
    `Paper Link` = Paper_Link,
    `Publication Year` = Publication_Year,
    `# of Arm` = suppressWarnings(as.integer(str_extract(Arms_Paper, "^[0-9]+"))),
    `Control Group` = Control_Group,
    `Study Phase` = NA_character_,
    `Sample Size` = Cleaned_N,
    `Priamry Outcome` = Primary_Outcome_From_Publication,
    `Primary Outcome Type` = "Primary publication reviewed; see audit workbook sheets",
    `Trial Success(Primary Outcome Significant)` = NA_character_,
    `Statistical Model` = Statistical_Model,
    `Randomization Scheme` = Randomization_Scheme,
    `Randomization Scheme(High Level)` = "Individual",
    `Research Area` = NA_character_,
    `Text Data` = "No",
    Citation = paste0(Paper_Name, ". ", Journal, ". ", Publication_Year, ". DOI: ", Paper_DOI)
  )

validation_path <- file.path(prov_dir, "validation_summary_trials81_86.csv")
validation <- if (file.exists(validation_path)) {
  read_csv(validation_path, show_col_types = FALSE)
} else {
  tibble()
}

write_csv(publication_review, file.path(prov_dir, "publication_review_trials81_94.csv"))
write_csv(
  targets %>%
    select(Trial_ID, Original_Trial_ID, outcome_variable, outcome_role, arm, statistic,
           paper_value, paper_precision, paper_source, notes),
  file.path(prov_dir, "outcome_reproducibility_targets_trials81_94.csv")
)
write_csv(computed, file.path(prov_dir, "outcome_reproducibility_audit_trials81_94.csv"))
write_csv(audit_decisions, file.path(prov_dir, "audit_decisions_trials81_94.csv"))

backup_updates <- audit_decisions %>%
  filter(!Analysis_Ready) %>%
  transmute(
    Trial_ID,
    Original_Trial_ID,
    reason = Blocking_Reason,
    status = "backup",
    primary_failure_summary = Review_Notes,
    next_action = Next_Action
  )

backup_path <- file.path(prov_dir, "backup_trials.csv")
if (file.exists(backup_path)) {
  backup_trials <- read_csv(backup_path, show_col_types = FALSE) %>%
    filter(!Trial_ID %in% backup_updates$Trial_ID) %>%
    bind_rows(backup_updates)
} else {
  backup_trials <- backup_updates
}
write_csv(backup_trials, backup_path)

write_xlsx(
  list(
    Main_Metadata = meta_main,
    Publication_Review = publication_review,
    Audit_Targets = targets %>%
      select(Trial_ID, Original_Trial_ID, outcome_variable, outcome_role, arm, statistic,
             paper_value, paper_precision, paper_source, notes),
    Outcome_Audit = computed,
    Audit_Decisions = audit_decisions,
    Backup_Decisions = backup_updates,
    Validation = validation
  ),
  file.path(meta_dir, "meta_data_trials81_86_audited.xlsx")
)

active_sidecar_path <- file.path(meta_dir, "meta_data_trials81_86_active.xlsx")
if (file.exists(file.path(meta_dir, "meta_data_active.xlsx")) && file.exists(active_sidecar_path)) {
  old_meta <- read_excel(file.path(meta_dir, "meta_data_active.xlsx"), sheet = "Sheet1") %>%
    filter(suppressWarnings(as.integer(Trial_ID)) < 81)
  old_provenance <- read_excel(file.path(meta_dir, "meta_data_active.xlsx"), sheet = "Provenance") %>%
    filter(suppressWarnings(as.integer(Trial_ID)) < 81)
  new_provenance <- read_excel(active_sidecar_path, sheet = "Provenance")
  combined_meta <- bind_rows(old_meta, meta_main) %>% arrange(as.integer(Trial_ID))
  combined_provenance <- bind_rows(old_provenance, new_provenance) %>% arrange(as.integer(Trial_ID))
  write_xlsx(list(Sheet1 = combined_meta, Provenance = combined_provenance), file.path(meta_dir, "meta_data_active.xlsx"))
  write_xlsx(list(Sheet1 = combined_meta, Provenance = combined_provenance), file.path(meta_dir, "meta_data_expansion.xlsx"))
}

dict_path <- file.path(meta_dir, "data_dictionary.csv")
new_dict_path <- file.path(meta_dir, "data_dictionary_trials81_86.csv")
if (file.exists(dict_path) && file.exists(new_dict_path)) {
  combined_dict <- read_csv(dict_path, show_col_types = FALSE) %>%
    filter(suppressWarnings(as.integer(Trial_ID)) < 81) %>%
    bind_rows(read_csv(new_dict_path, show_col_types = FALSE)) %>%
    arrange(as.integer(Trial_ID), variable_name)
  write_csv(combined_dict, dict_path)
}

download_log_path <- file.path(prov_dir, "download_log.csv")
new_download_log_path <- file.path(prov_dir, "download_log_trials81_86.csv")
if (file.exists(download_log_path) && file.exists(new_download_log_path)) {
  combined_download_log <- read_csv(download_log_path, show_col_types = FALSE) %>%
    filter(suppressWarnings(as.integer(Trial_ID)) < 81) %>%
    bind_rows(read_csv(new_download_log_path, show_col_types = FALSE)) %>%
    arrange(as.integer(Trial_ID))
  write_csv(combined_download_log, download_log_path)
}

validation_summary_path <- file.path(prov_dir, "validation_summary.csv")
new_validation_summary_path <- file.path(prov_dir, "validation_summary_trials81_86.csv")
if (file.exists(validation_summary_path) && file.exists(new_validation_summary_path)) {
  combined_validation <- read_csv(validation_summary_path, show_col_types = FALSE) %>%
    filter(suppressWarnings(as.integer(Trial_ID)) < 81) %>%
    bind_rows(read_csv(new_validation_summary_path, show_col_types = FALSE)) %>%
    arrange(as.integer(Trial_ID))
  write_csv(combined_validation, validation_summary_path)
}

publication_links_path <- file.path(root, "publications", "publication_links.csv")
if (file.exists(publication_links_path)) {
  new_publication_links <- publication_review %>%
    filter(Final_Status == "active") %>%
    transmute(
      Trial_ID = as.integer(Trial_ID),
      `Paper Name` = Paper_Name,
      `Paper Link` = Paper_Link,
      Repository,
      Dataset_DOI
    )
  combined_publication_links <- read_csv(publication_links_path, show_col_types = FALSE) %>%
    filter(suppressWarnings(as.integer(Trial_ID)) < 81) %>%
    bind_rows(new_publication_links) %>%
    arrange(as.integer(Trial_ID))
  write_csv(combined_publication_links, publication_links_path)
}

backup_meta_path <- file.path(meta_dir, "meta_data_backup.xlsx")
if (file.exists(backup_meta_path)) {
  backup_meta_updates <- publication_review %>%
    filter(Final_Status == "backup") %>%
    transmute(
      Trial_ID,
      Original_Trial_ID,
      `Trial Number/Name` = Candidate_ID,
      `Paper Name` = Paper_Name,
      Journal,
      `Paper Link` = Paper_Link,
      `Publication Year` = Publication_Year,
      `# of Arm` = suppressWarnings(as.integer(str_extract(Arms_Paper, "^[0-9]+"))),
      `Control Group` = Control_Group,
      `Study Phase` = NA_character_,
      `Sample Size` = Cleaned_N,
      `Priamry Outcome` = Primary_Outcome_From_Publication,
      `Primary Outcome Type` = "Archived after primary-publication outcome audit",
      `Trial Success(Primary Outcome Significant)` = NA_character_,
      `Statistical Model` = Statistical_Model,
      `Randomization Scheme` = Randomization_Scheme,
      `Randomization Scheme(High Level)` = "Individual",
      `Research Area` = NA_character_,
      `Text Data` = "No",
      Citation = paste0(Paper_Name, ". ", Journal, ". ", Publication_Year, ". DOI: ", Paper_DOI),
      `Issues Encountered` = Review_Notes
    )

  backup_provenance_updates <- audit_decisions %>%
    filter(!Analysis_Ready) %>%
    left_join(
      publication_review %>%
        select(Trial_ID, Repository, Dataset_DOI),
      by = "Trial_ID"
    ) %>%
    transmute(
      Trial_ID,
      Original_Trial_ID,
      Repository,
      Dataset_DOI,
      License = NA_character_,
      Download_Date = today,
      Source_Files = map_chr(Trial_ID, function(id) {
        files <- list.files(file.path(root, "backup", id, "raw_data"), recursive = TRUE, all.files = FALSE, no.. = TRUE)
        paste(files, collapse = "; ")
      }),
      Backup_Reason = Blocking_Reason,
      Backup_Folder = file.path("backup", Trial_ID),
      Next_Action
    )

  old_backup_meta <- read_excel(backup_meta_path, sheet = "Sheet1") %>%
    filter(!Trial_ID %in% backup_meta_updates$Trial_ID)
  old_backup_provenance <- read_excel(backup_meta_path, sheet = "Provenance") %>%
    filter(!Trial_ID %in% backup_provenance_updates$Trial_ID)
  write_xlsx(
    list(
      Sheet1 = bind_rows(old_backup_meta, backup_meta_updates),
      Provenance = bind_rows(old_backup_provenance, backup_provenance_updates)
    ),
    backup_meta_path
  )
}

flow_path <- file.path(prov_dir, "broad_dataset_screening_flow_counts.csv")
if (file.exists(flow_path)) {
  flow <- read_csv(flow_path, show_col_types = FALSE) %>%
    mutate(recorded_date = as.character(recorded_date))

  analysis_ready_n <- sum(audit_decisions$Analysis_Ready)
  publication_found_n <- sum(publication_review$Primary_Publication_Found)
  no_publication_n <- sum(!publication_review$Primary_Publication_Found)
  audit_not_ready_n <- publication_found_n - analysis_ready_n

  new_flow <- tibble(
    iteration_id = "trials81_94_publication_audit_2026_06_09",
    recorded_date = today,
    stage_order = c(9, 10, 10, 11, 11, 12),
    stage_id = c(
      "trials81_94_primary_publication_reviewed",
      "trials81_94_primary_publication_identified",
      "trials81_94_no_primary_publication",
      "trials81_94_primary_audit_analysis_ready",
      "trials81_94_primary_audit_not_analysis_ready",
      "trials81_94_final_analysis_ready_after_audit"
    ),
    parent_stage_id = c(
      "download_first_cleaned_trials81_94_contract_pass",
      "trials81_94_primary_publication_reviewed",
      "trials81_94_primary_publication_reviewed",
      "trials81_94_primary_publication_identified",
      "trials81_94_primary_publication_identified",
      "trials81_94_primary_audit_analysis_ready"
    ),
    node_label = c(
      "Trial81-trial94 primary-publication reviews completed",
      "Trials with associated main publication or preprint identified",
      "Trials without associated main publication",
      "Trials passing primary-publication outcome audit gate",
      "Trials needing reclean, model reproduction, or exclusion after audit",
      "Renumbered trial81-trial86 analysis-ready after publication audit"
    ),
    count = c(
      nrow(publication_review),
      publication_found_n,
      no_publication_n,
      analysis_ready_n,
      audit_not_ready_n,
      analysis_ready_n
    ),
    node_kind = c("screening", "inclusion", "exclusion", "inclusion", "exclusion", "inclusion"),
    criteria = c(
      "Reviewed associated primary publications/preprints and extracted primary outcome targets.",
      "Associated main results publication or preprint could be identified and linked.",
      "No associated main results publication could be identified from repository, registry, DOI, or web search.",
      "At least one publication-supported primary outcome target reproduced within the audit decision rules, with blocking issues absent or documented as nonblocking.",
      "Primary target was missing, model-only, filtered but unreconstructed, mismatched, or lacking a main publication.",
      "Final reduced active trial81-trial86 set after primary-publication review, reproducibility audit, and backup archiving."
    ),
    source_output = c(
      "rct_expansion/provenance/publication_review_trials81_94.csv",
      "rct_expansion/provenance/publication_review_trials81_94.csv",
      "rct_expansion/provenance/publication_review_trials81_94.csv",
      "rct_expansion/provenance/audit_decisions_trials81_94.csv; rct_expansion/provenance/outcome_reproducibility_audit_trials81_94.csv",
      "rct_expansion/provenance/audit_decisions_trials81_94.csv; rct_expansion/provenance/outcome_reproducibility_audit_trials81_94.csv",
      "rct_expansion/metadata/meta_data_trials81_86_audited.xlsx"
    ),
    notes = c(
      "This is the next narrowing gate after structural validation.",
      "Trial88 fails this gate and remains outside the analysis-ready set.",
      "Trial88 is excluded unless a valid main results publication appears.",
      "Original temporary IDs 85, 86, 89, 91, 92, and 93 were renumbered as active trial81-trial86; trial84 has PHQ caution noted.",
      "Original temporary IDs 81, 82, 83, 84, 87, 90, and 94 were moved to backup/B06-B10, B12, and B13 among publication-linked trials.",
      "Analysis-ready count is provisional for active trial84 if PHQ-9 is treated as co-primary rather than secondary."
    )
  )

  flow <- flow %>%
    filter(!stage_id %in% new_flow$stage_id) %>%
    bind_rows(new_flow) %>%
    arrange(stage_order, stage_id)

  write_csv(flow, flow_path)
}

audit_decisions %>%
  count(Decision, Analysis_Ready)
