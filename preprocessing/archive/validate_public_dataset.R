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
  data.frame(
    Trial_ID = id,
    n_rows = nrow(d),
    n_cols = ncol(d),
    has_treatment = "Treatment" %in% names(d),
    treatment_arms = if ("Treatment" %in% names(d)) length(unique(d$Treatment[!is.na(d$Treatment)])) else NA_integer_,
    primary_outcomes = sum(startsWith(names(d), "YP_")),
    names_match = identical(names(d), names(cdat)),
    duplicate_names = anyDuplicated(names(d)) > 0,
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
    res$duplicate_names,
]

stop_if(nrow(failures) > 0, paste("Public dataset validation failed for trial(s):", paste(failures$Trial_ID, collapse = ", ")))
stop_if(!file.exists(file.path(root, "meta_data.xlsx")), "meta_data.xlsx is missing.")
stop_if(!file.exists(file.path(root, "data-dictionary.xlsx")), "data-dictionary.xlsx is missing.")

cat("Public cleaned dataset validation passed.\n")
cat("Trials checked: ", nrow(res), "\n", sep = "")
cat("CSV/RDS pairs: 125\n")
cat("Minimum rows: ", min(res$n_rows), "\n", sep = "")
cat("Minimum primary outcomes: ", min(res$primary_outcomes), "\n", sep = "")
