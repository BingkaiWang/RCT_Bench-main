#!/usr/bin/env Rscript

# Validate the public flat cleaned_data layout after merging the expansion set.

root <- normalizePath(".", mustWork = TRUE)
clean_dir <- file.path(root, "cleaned_data")
csv_files <- list.files(clean_dir, pattern = "^trial[0-9]+\\.csv$", full.names = TRUE)
rds_files <- list.files(clean_dir, pattern = "^trial[0-9]+\\.rds$", full.names = TRUE)

trial_id <- function(path, ext) {
  as.integer(sub(paste0("^trial([0-9]+)\\.", ext, "$"), "\\1", basename(path)))
}

csv_ids <- sort(trial_id(csv_files, "csv"))
rds_ids <- sort(trial_id(rds_files, "rds"))
expected_ids <- 1:125

stop_if <- function(condition, message) {
  if (condition) stop(message, call. = FALSE)
}

stop_if(!identical(csv_ids, expected_ids), "CSV coverage is not exactly trial1 through trial125.")
stop_if(!identical(rds_ids, expected_ids), "RDS coverage is not exactly trial1 through trial125.")

checks <- lapply(expected_ids, function(id) {
  rds_path <- file.path(clean_dir, paste0("trial", id, ".rds"))
  csv_path <- file.path(clean_dir, paste0("trial", id, ".csv"))
  d <- readRDS(rds_path)
  cdat <- read.csv(csv_path, check.names = FALSE, stringsAsFactors = FALSE)
  allowed_design <- c("Participant_ID", "Crossover_Sequence", "Crossover_Period", "Assessment_Window")
  valid_names <- names(d) == "Treatment" |
    startsWith(names(d), "YP_") |
    startsWith(names(d), "YS_") |
    startsWith(names(d), "X_") |
    names(d) %in% allowed_design
  id_like_x <- grepl(
    "^X_.*(source|participant|subject_id|patient_id|record_id|research_number|(^|_)id($|_))",
    names(d), ignore.case = TRUE
  )
  post_treatment_x <- names(d) %in% c(
    "X_O2sat_final", "X_blinding_guess", "X_blinding_certainty", "X_adverse_event",
    "X_dropout_50_percent", "X_itt", "X_mitt", "X_pp", "X_post_intubation_hr_bpm",
    "X_any_sms", "X_message_long", "X_itt_treated", "X_days_intervention_end_to_post",
    "X_follicular_phase_post"
  )
  string_sentinels <- vapply(d, function(x) {
    if (!is.factor(x) && !is.character(x)) return(FALSE)
    any(tolower(trimws(as.character(x))) %in% c(".", "missing"), na.rm = TRUE)
  }, logical(1))
  numeric_sentinels <- vapply(d, function(x) {
    if (!is.numeric(x) && !is.integer(x)) return(FALSE)
    any(x %in% c(9999, 999, 888, -555, -777, -888, -999), na.rm = TRUE)
  }, logical(1))
  all_missing <- vapply(d, function(x) all(is.na(x)), logical(1))
  cluster_ok <- if (id %in% c(60L, 65L, 69L)) {
    "Participant_ID" %in% names(d) && anyDuplicated(d$Participant_ID) > 0L
  } else {
    !"Participant_ID" %in% names(d)
  }
  data.frame(
    Trial_ID = id,
    n_rows = nrow(d),
    n_cols = ncol(d),
    has_treatment = "Treatment" %in% names(d),
    treatment_arms = if ("Treatment" %in% names(d)) length(unique(d$Treatment[!is.na(d$Treatment)])) else NA_integer_,
    primary_outcomes = sum(startsWith(names(d), "YP_")),
    names_match = identical(names(d), names(cdat)),
    duplicate_names = anyDuplicated(names(d)) > 0,
    valid_variable_names = all(valid_names),
    identifier_covariates = any(id_like_x),
    post_treatment_covariates = any(post_treatment_x),
    unnormalized_string_sentinels = any(string_sentinels),
    unnormalized_numeric_sentinels = any(numeric_sentinels),
    all_missing_columns = any(all_missing),
    cluster_identifier_ok = cluster_ok,
    stringsAsFactors = FALSE
  )
})

res <- do.call(rbind, checks)
failures <- res[
  !res$has_treatment |
    is.na(res$treatment_arms) |
    res$treatment_arms < 2 |
    res$primary_outcomes < 1 |
    !res$names_match |
    res$duplicate_names |
    !res$valid_variable_names |
    res$identifier_covariates |
    res$post_treatment_covariates |
    res$unnormalized_string_sentinels |
    res$unnormalized_numeric_sentinels |
    res$all_missing_columns |
    !res$cluster_identifier_ok,
]

stop_if(nrow(failures) > 0, paste("Public dataset validation failed for trial(s):", paste(failures$Trial_ID, collapse = ", ")))
stop_if(!file.exists(file.path(root, "meta_data.xlsx")), "meta_data.xlsx is missing.")
stop_if(!file.exists(file.path(root, "data-dictionary.xlsx")), "data-dictionary.xlsx is missing.")

cat("Public cleaned dataset validation passed.\n")
cat("Trials checked: ", nrow(res), "\n", sep = "")
cat("CSV/RDS pairs: 125\n")
cat("Minimum rows: ", min(res$n_rows), "\n", sep = "")
cat("Minimum primary outcomes: ", min(res$primary_outcomes), "\n", sep = "")
