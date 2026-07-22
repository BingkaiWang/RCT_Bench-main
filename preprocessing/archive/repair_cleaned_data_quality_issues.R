#!/usr/bin/env Rscript

# Apply source-backed, analysis-contract repairs to the public cleaned data.
# This is intentionally a deterministic post-cleaning step: the original trial
# cleaning notebooks remain historical records, while this script prevents
# known identifiers, post-treatment covariates, sentinel values, and naming
# errors from being reintroduced when the public deliverables are rebuilt.

root <- normalizePath(".", mustWork = TRUE)
clean_dir <- file.path(root, "cleaned_data")

read_trial <- function(id) readRDS(file.path(clean_dir, sprintf("trial%d.rds", id)))

write_trial <- function(d, id) {
  csv_path <- file.path(clean_dir, sprintf("trial%d.csv", id))
  rds_path <- file.path(clean_dir, sprintf("trial%d.rds", id))
  write.csv(d, csv_path, row.names = FALSE, na = "", quote = TRUE)
  saveRDS(d, rds_path)
}

rename_columns <- function(d, mapping) {
  present <- intersect(names(mapping), names(d))
  names(d)[match(present, names(d))] <- unname(mapping[present])
  if (anyDuplicated(names(d))) stop("Rename created duplicate columns.")
  d
}

drop_columns <- function(d, columns) d[setdiff(names(d), intersect(columns, names(d)))]

insert_after <- function(d, after, name, value) {
  stopifnot(length(value) == nrow(d), after %in% names(d), !name %in% names(d))
  pos <- match(after, names(d))
  cbind(d[seq_len(pos)], setNames(data.frame(value, stringsAsFactors = FALSE), name), d[-seq_len(pos)])
}

trim_categorical <- function(x) {
  if (!is.factor(x) && !is.character(x)) return(x)
  y <- trimws(as.character(x))
  y[y == ""] <- NA_character_
  if (is.factor(x)) factor(y, levels = unique(trimws(levels(x)))) else y
}

replace_exact_numeric <- function(x, values) {
  if (!is.numeric(x) && !is.integer(x)) return(x)
  x[x %in% values] <- NA
  x
}

repair <- function(id, fn) {
  d <- read_trial(id)
  out <- fn(d)
  stopifnot(is.data.frame(out), "Treatment" %in% names(out), any(startsWith(names(out), "YP_")))
  write_trial(out, id)
  message(sprintf("Repaired trial%d: %d rows, %d columns", id, nrow(out), ncol(out)))
}

# Normalize historical outcome prefixes. These are follow-up outcomes, not
# analysis-set or pre/post helper fields.
repair(1, function(d) rename_columns(d, c(
  post_YP_delta_HOMA_IR_7m = "YS_delta_HOMA_IR_7m",
  post_YS_delta_BMI_7m = "YS_delta_BMI_7m",
  post_YS_delta_WHR_7m = "YS_delta_WHR_7m",
  post_YS_delta_Acne_7m = "YS_delta_Acne_7m",
  post_YS_delta_Hirsutism_7m = "YS_delta_Hirsutism_7m",
  post_YS_delta_FPG_7m = "YS_delta_FPG_7m",
  post_YS_delta_FINS_7m = "YS_delta_FINS_7m",
  post_YS_delta_GlucoseAUC_7m = "YS_delta_GlucoseAUC_7m",
  post_YS_delta_InsulinAUC_7m = "YS_delta_InsulinAUC_7m",
  post_YS_delta_HOMA_beta_7m = "YS_delta_HOMA_beta_7m",
  post_YS_delta_Cpeptide_7m = "YS_delta_Cpeptide_7m",
  post_YS_delta_HbA1c_7m = "YS_delta_HbA1c_7m"
)))
repair(6, function(d) rename_columns(d, c(pre_YP_delta_CCA_IMT_12m = "YS_delta_CCA_IMT_12m")))
repair(16, function(d) rename_columns(d, c(
  pre_YP_delta_BDI_6w = "YS_delta_BDI_6w",
  pre_YS_delta_MADRS_6w = "YS_delta_MADRS_6w",
  pre_YS_delta_BAI_6w = "YS_delta_BAI_6w",
  pre_YS_delta_QOLI_6w = "YS_delta_QOLI_6w",
  pre_YS_delta_IPAQ_6w = "YS_delta_IPAQ_6w"
)))
repair(18, function(d) rename_columns(d, c(
  post_YP_time_to_disengaged_24m = "YS_time_to_disengaged_24m",
  post_YP_event_disengaged_24m = "YS_event_disengaged_24m",
  post_YP_prop_time_in_care_24m = "YS_prop_time_in_care_24m",
  post_YP_disengaged_24m_final = "YS_disengaged_24m_final",
  post_YP_event_disengaged_24m_final = "YS_event_disengaged_24m_final"
)))
repair(26, function(d) rename_columns(d, c(pre_YP_delta_Adherence_3m = "YS_delta_Adherence_3m")))
repair(47, function(d) {
  mapping <- setNames(sub("^pre_YS_", "YS_", grep("^pre_YS_", names(d), value = TRUE)), grep("^pre_YS_", names(d), value = TRUE))
  d <- rename_columns(d, mapping)
  drop_columns(d, "YS_death")
})

# Remove non-informative public variables and normalize one mislabeled outcome.
repair(10, function(d) drop_columns(d, "YS_vocal_cord_pos_intub"))
repair(27, function(d) drop_columns(d, "YS_endocrine_status_3m"))
repair(40, function(d) drop_columns(d, "YS_attempt3_success"))
repair(49, function(d) rename_columns(d, c(X_O2sat_final = "YS_O2sat_final")))
repair(123, function(d) drop_columns(d, "YS_complication_recurrence"))

# Whitespace and explicit missing-value normalization.
repair(39, function(d) {
  for (name in names(d)) {
    if (is.factor(d[[name]]) || is.character(d[[name]])) {
      y <- as.character(d[[name]])
      y[tolower(trimws(y)) == "missing"] <- NA_character_
      d[[name]] <- if (is.factor(d[[name]])) factor(y) else y
    }
  }
  d
})
repair(38, function(d) {
  for (name in intersect(c("YP_time", "YS_CD8_20w", "X_preanti_0w", "X_CD8_0w"), names(d))) {
    d[[name]] <- replace_exact_numeric(d[[name]], c(888, 999))
  }
  d
})
repair(43, function(d) {
  for (name in names(d)) d[[name]] <- trim_categorical(d[[name]])
  d
})
repair(67, function(d) {
  cols <- c(
    "X_beta2_concentration_pre_1h", "X_myoglobin_concentration_pre_1h",
    "X_urea_concentration_pre_1h", "X_creatinine_concentration_pre_1h",
    "X_albumin_concentration_pre_1h"
  )
  for (name in intersect(cols, names(d))) d[[name]] <- replace_exact_numeric(d[[name]], 9999)
  d
})
repair(79, function(d) {
  for (name in intersect(c("X_occupation", "X_pregnancy_complication_experience"), names(d))) {
    y <- as.character(d[[name]])
    y[trimws(y) == "999"] <- NA_character_
    d[[name]] <- factor(y)
  }
  d
})
repair(95, function(d) {
  d$YS_leakage_pressure_cmH2O <- replace_exact_numeric(d$YS_leakage_pressure_cmH2O, 999)
  d
})
repair(101, function(d) {
  for (name in intersect(c("YP_eq5d_pain_3m", "X_eq5d_pain_0m", "X_barthel_feed_0m"), names(d))) {
    y <- trimws(as.character(d[[name]]))
    y[y == "."] <- NA_character_
    d[[name]] <- suppressWarnings(as.numeric(y))
  }
  d
})
# Trial103 is the TEAM economic-evaluation dataset. Its primary health outcome
# is observed 90-day QALYs derived from patient-reported EQ-5D-3L, not one
# isolated pain-domain item. Standard-care ward subtypes are one randomized arm.
repair(103, function(d) {
  extractor <- file.path(root, "preprocessing", "archive", "extract_trial103_primary_outcome.py")
  output <- system2("python3", shQuote(extractor), stdout = TRUE, stderr = TRUE)
  if (!is.null(attr(output, "status")) && attr(output, "status") != 0L) {
    stop(paste(output, collapse = "\n"))
  }
  staged_path <- file.path(
    root, "local", "rct_expansion", "provenance", "cleaned_data_quality_audit",
    "trial103_primary_repair.csv"
  )
  out <- read.csv(staged_path, stringsAsFactors = FALSE, check.names = FALSE)
  out$Treatment <- factor(out$Treatment, levels = c("Standard care", "MMHU"))
  out$YS_status_90d <- factor(out$YS_status_90d, levels = c("Alive", "Dead"))
  out$X_gender_0d <- factor(out$X_gender_0d)
  stopifnot(nrow(out) == 599L, sum(!is.na(out$YP_qaly_90d_observed)) == 272L)
  out
})
repair(107, function(d) {
  d$X_age_years <- replace_exact_numeric(d$X_age_years, 999)
  d$YP_function_8w <- replace_exact_numeric(d$YP_function_8w, c(888, 999))
  d
})

# Trial52 has a publication-defined, tenapanor-only BSFS endpoint. Retain it as
# a clearly arm-specific secondary variable; the serum-phosphorus outcome is
# the primary randomized contrast available in both arms.
repair(52, function(d) rename_columns(d, c(
  YP_delta_bsfs_7w = "YS_delta_bsfs_7w_tenapanor_only"
)))

# Preserve participant clustering for crossover trials without exposing the
# cluster key as an adjustment covariate.
repair(60, function(d) {
  if ("Participant_ID" %in% names(d)) return(d)
  raw_path <- file.path(
    root, "local", "rct_expansion", "raw_data", "trial60",
    "YoshiDr323-DFT-IW-masticatory-83d4493", "data", "processed", "DFT_glucose.csv"
  )
  raw <- read.csv(raw_path, stringsAsFactors = FALSE, check.names = FALSE)
  keys <- unique(raw[c("ID", "Sequence", "Period", "Treatment")])
  recoded <- ifelse(keys$Treatment == "N", "Sham", "IW stimulation")
  stopifnot(nrow(keys) == nrow(d), identical(as.character(d$Treatment), recoded))
  d <- rename_columns(d, c(X_sequence_0d = "Crossover_Sequence", X_period_0d = "Crossover_Period"))
  insert_after(d, "Treatment", "Participant_ID", sprintf("P%03d", as.integer(factor(keys$ID, levels = unique(keys$ID)))))
})
repair(65, function(d) {
  d <- d[as.character(d$Treatment) %in% c("Sham tDCS", "Active tDCS"), , drop = FALSE]
  d$Treatment <- factor(as.character(d$Treatment), levels = c("Sham tDCS", "Active tDCS"))
  stopifnot(sum(d$Treatment == "Sham tDCS") == 45L, sum(d$Treatment == "Active tDCS") == 45L)
  participant <- ave(seq_len(nrow(d)), as.character(d$Treatment), FUN = seq_along)
  d <- rename_columns(d, c(
    X_blinding_guess = "YS_blinding_guess",
    X_blinding_certainty = "YS_blinding_certainty",
    X_adverse_event = "YS_adverse_event",
    X_first_allocation = "Crossover_Sequence"
  ))
  if ("Participant_ID" %in% names(d)) d else insert_after(d, "Treatment", "Participant_ID", sprintf("P%03d", participant))
})
repair(69, function(d) {
  if ("Participant_ID" %in% names(d)) return(d)
  subject <- sprintf("S%s", as.character(d$X_subject_id))
  d <- rename_columns(d, c(X_period_label = "Assessment_Window"))
  d <- drop_columns(d, "X_subject_id")
  insert_after(d, "Treatment", "Participant_ID", subject)
})

# Trial73's publication-defined primary outcome is only defined for the two
# reassurance-call arms. Restrict the benchmark table to that randomized
# primary-analysis subset instead of representing structurally undefined values
# as missing outcomes in a third arm.
repair(73, function(d) {
  d <- d[as.character(d$Treatment) != "No call", , drop = FALSE]
  d$Treatment <- factor(
    as.character(d$Treatment),
    levels = c("Human-assisted reassurance call", "AI-assisted reassurance call")
  )
  drop_columns(d, "YS_fever_d1")
})

# Use interpretable public treatment labels where the arm mapping is known.
repair(81, function(d) {
  if (!any(grepl("^Arm_", as.character(d$Treatment)))) return(d)
  d$Treatment <- factor(
    c(Arm_1 = "Placebo", Arm_2 = "Aprepitant arm 1", Arm_3 = "Aprepitant arm 2")[as.character(d$Treatment)],
    levels = c("Placebo", "Aprepitant arm 1", "Aprepitant arm 2")
  )
  d
})
repair(82, function(d) {
  if (!any(grepl("^Arm_", as.character(d$Treatment)))) return(d)
  d$Treatment <- factor(
    c(Arm_1 = "Blinded arm 1", Arm_2 = "Blinded arm 2")[as.character(d$Treatment)],
    levels = c("Blinded arm 1", "Blinded arm 2")
  )
  d
})
repair(83, function(d) {
  if (!any(grepl("^Arm_", as.character(d$Treatment)))) return(d)
  d$Treatment <- factor(
    c(Arm_0 = "Control", Arm_1 = "Intervention")[as.character(d$Treatment)],
    levels = c("Control", "Intervention")
  )
  d
})
repair(85, function(d) {
  if (!any(as.character(d$Treatment) %in% c("WL", "Tx"))) return(d)
  d$Treatment <- factor(
    c(WL = "Wait-list control", Tx = "VR neuroscience therapy")[as.character(d$Treatment)],
    levels = c("Wait-list control", "VR neuroscience therapy")
  )
  d
})

# Remove identifiers and post-randomization/analysis-set fields from X_.
identifier_columns <- list(
  `87` = "X_source_participant_no",
  `88` = "X_source_id",
  `89` = "X_source_patient_no",
  `90` = "X_source_patient_id",
  `91` = "X_source_research_number",
  `92` = "X_source_sno",
  `93` = "X_source_id",
  `94` = "X_source_patient_id",
  `116` = "X_source_id",
  `117` = "X_source_patient_id",
  `118` = "X_subject_id",
  `119` = "X_source_record_id",
  `120` = "X_source_subject_id",
  `121` = "X_source_subject_id"
)
for (id_text in names(identifier_columns)) {
  id <- as.integer(id_text)
  repair(id, function(d) drop_columns(d, identifier_columns[[id_text]]))
}
repair(84, function(d) drop_columns(d, "X_dropout_50_percent"))
repair(86, function(d) drop_columns(d, c("X_itt", "X_mitt", "X_pp")))
repair(87, function(d) drop_columns(d, "X_post_intubation_hr_bpm"))
repair(93, function(d) {
  d <- drop_columns(d, c(
    "X_any_sms", "X_message_long", "X_itt_treated", "X_patient_age_followup"
  ))
  sentinel_cols <- intersect(c(
    "X_patient_age_reported", "X_patient_age_proxy", "X_household_head_male",
    "X_household_head_education", "X_household_rooms", "X_sleep_under_net",
    "X_mobile_phones", "X_air_conditioner", "X_drug_code"
  ), names(d))
  for (name in sentinel_cols) {
    x <- suppressWarnings(as.numeric(as.character(d[[name]])))
    x[x <= -500] <- NA_real_
    d[[name]] <- x
  }
  d
})
repair(121, function(d) drop_columns(d, c(
  "X_days_intervention_end_to_post", "X_follicular_phase_post"
)))

message("All cleaned-data quality repairs completed.")
