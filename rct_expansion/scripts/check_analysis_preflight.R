#!/usr/bin/env Rscript

# Lightweight analysis preflight for active expansion trials.
# Mirrors the shared analysis assumption that covariates can be mean/mode
# imputed, then outcomes with more than 40% missingness are skipped.

root <- "rct_expansion"
exp_dir <- file.path(root, "cleaned_data")
prov_dir <- file.path(root, "provenance")
dir.create(prov_dir, recursive = TRUE, showWarnings = FALSE)

mode1 <- function(x) {
  ux <- unique(x[!is.na(x)])
  if (length(ux) == 0) return(NA)
  ux[which.max(tabulate(match(x, ux)))]
}

is_binary_like <- function(x) {
  vals <- unique(x[!is.na(x)])
  length(vals) > 0 && length(vals) <= 2
}

impute_covariates <- function(d, covs) {
  for (cov in covs) {
    if (is.numeric(d[[cov]]) || is.integer(d[[cov]])) {
      m <- mean(d[[cov]], na.rm = TRUE)
      if (!is.nan(m)) d[[cov]][is.na(d[[cov]])] <- m
    } else {
      m <- mode1(d[[cov]])
      d[[cov]][is.na(d[[cov]])] <- m
    }
  }
  d
}

check_trial <- function(id) {
  d <- readRDS(file.path(exp_dir, paste0("trial", id, ".rds")))
  covs <- names(d)[startsWith(names(d), "X_")]
  d <- impute_covariates(d, covs)

  yp <- names(d)[startsWith(names(d), "YP_")]
  ys <- names(d)[startsWith(names(d), "YS_")]
  ys_valid <- ys[vapply(d[ys], function(x) {
    is.numeric(x) || is.integer(x) || is.logical(x) || is_binary_like(x)
  }, logical(1))]
  outcomes <- c(yp, ys_valid)

  usable <- 0L
  high_missing <- character(0)
  zero_complete <- character(0)

  for (outcome in outcomes) {
    if (mean(is.na(d[[outcome]])) > 0.4) {
      high_missing <- c(high_missing, outcome)
      next
    }
    complete_vars <- c(outcome, "Treatment", covs)
    n_complete <- sum(complete.cases(d[, complete_vars, drop = FALSE]))
    if (n_complete > 0) {
      usable <- usable + 1L
    } else {
      zero_complete <- c(zero_complete, outcome)
    }
  }

  data.frame(
    Trial_ID = id,
    n_outcomes_checked = length(outcomes),
    usable_outcomes = usable,
    high_missing_outcomes = paste(high_missing, collapse = ";"),
    zero_complete_outcomes = paste(zero_complete, collapse = ";"),
    analysis_preflight_pass = usable > 0 && length(zero_complete) == 0,
    stringsAsFactors = FALSE
  )
}

ids <- 51:121
res <- do.call(rbind, lapply(ids, check_trial))
write.csv(res, file.path(prov_dir, "analysis_preflight_expansion_trials51_121.csv"), row.names = FALSE)

summary_lines <- c(
  "# Expansion Analysis Preflight",
  "",
  paste0("Run date: ", Sys.Date()),
  "",
  paste0("- Expansion trials checked: ", nrow(res)),
  paste0("- Analysis preflight pass: ", sum(res$analysis_preflight_pass), "/", nrow(res)),
  paste0("- Minimum usable outcomes in any trial: ", min(res$usable_outcomes)),
  "",
  "Pass means the cleaned trial has at least one YP_/YS_ outcome usable after the shared 40% outcome-missingness screen and mean/mode covariate imputation."
)

failures <- res[!res$analysis_preflight_pass, ]
if (nrow(failures) > 0) {
  summary_lines <- c(summary_lines, "", "## Failures", "")
  for (i in seq_len(nrow(failures))) {
    row <- failures[i, ]
    summary_lines <- c(
      summary_lines,
      paste0(
        "- trial", row$Trial_ID,
        ": usable_outcomes=", row$usable_outcomes,
        "; high_missing=", row$high_missing_outcomes,
        "; zero_complete=", row$zero_complete_outcomes
      )
    )
  }
}

writeLines(summary_lines, file.path(prov_dir, "analysis_preflight_summary.md"))
cat(paste(summary_lines, collapse = "\n"), "\n")
