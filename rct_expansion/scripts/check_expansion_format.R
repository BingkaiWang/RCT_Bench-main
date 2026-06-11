#!/usr/bin/env Rscript

# Compare expansion trial files against the original non-clustered RCT format.
# Uses only base R so it can run in lightweight R environments.

root <- "rct_expansion"
orig_dir <- file.path("cleaned_data", "Non_Clustered_RCT")
exp_dir <- file.path(root, "cleaned_data")
prov_dir <- file.path(root, "provenance")
dir.create(prov_dir, recursive = TRUE, showWarnings = FALSE)

is_allowed_name <- function(x) {
  grepl("^[A-Za-z.][A-Za-z0-9_.]*$", x)
}

safe_read_csv <- function(path) {
  read.csv(path, check.names = FALSE, stringsAsFactors = FALSE)
}

check_one <- function(dir, id) {
  rds_path <- file.path(dir, paste0("trial", id, ".rds"))
  csv_path <- file.path(dir, paste0("trial", id, ".csv"))
  has_rds <- file.exists(rds_path)
  has_csv <- file.exists(csv_path)

  if (!has_rds) {
    return(data.frame(
      Trial_ID = id, has_csv = has_csv, has_rds = has_rds, n_rows = NA_integer_,
      n_cols = NA_integer_, csv_rows = NA_integer_, csv_cols = NA_integer_,
      names_match = FALSE, data_frame = FALSE, treatment_factor = FALSE,
      treatment_missing = NA_integer_, treatment_levels = NA_integer_,
      n_yp = NA_integer_, n_ys = NA_integer_, n_x = NA_integer_,
      n_bad_prefix = NA_integer_, duplicate_names = NA,
      bad_names = "", bad_prefix = "", y_all_missing = "", x_all_missing = "",
      y_model_hostile = "", exact_duplicate_columns = "",
      hard_format_pass = FALSE, analysis_compatible = FALSE,
      stringsAsFactors = FALSE
    ))
  }

  d <- readRDS(rds_path)
  cdat <- if (has_csv) safe_read_csv(csv_path) else data.frame()
  names_d <- names(d)
  ycols <- names_d[startsWith(names_d, "YP_") | startsWith(names_d, "YS_")]
  xcols <- names_d[startsWith(names_d, "X_")]
  bad_prefix <- names_d[!(names_d == "Treatment" |
                            startsWith(names_d, "YP_") |
                            startsWith(names_d, "YS_") |
                            startsWith(names_d, "X_"))]
  all_missing <- names_d[vapply(d, function(z) all(is.na(z)), logical(1))]
  y_all_missing <- intersect(ycols, all_missing)
  x_all_missing <- intersect(xcols, all_missing)
  y_model_hostile <- ycols[vapply(d[ycols], function(z) {
    if (is.numeric(z) || is.integer(z) || is.logical(z)) return(FALSE)
    length(unique(z[!is.na(z)])) > 2
  }, logical(1))]

  exact_pairs <- character(0)
  for (i in seq_along(d)) {
    if (i == 1) next
    for (j in seq_len(i - 1)) {
      both_missing <- all(is.na(d[[i]])) && all(is.na(d[[j]]))
      if (!both_missing && identical(d[[i]], d[[j]])) {
        exact_pairs <- c(exact_pairs, paste(names_d[j], names_d[i], sep = "="))
      }
    }
  }

  hard_format_pass <- has_csv && has_rds &&
    is.data.frame(d) &&
    identical(names_d, names(cdat)) &&
    "Treatment" %in% names_d &&
    is.factor(d$Treatment) &&
    sum(is.na(d$Treatment)) == 0 &&
    nlevels(as.factor(d$Treatment)) >= 2 &&
    sum(startsWith(names_d, "YP_")) >= 1 &&
    length(bad_prefix) == 0 &&
    anyDuplicated(names_d) == 0 &&
    all(is_allowed_name(names_d))

  analysis_compatible <- hard_format_pass && length(y_all_missing) == 0

  data.frame(
    Trial_ID = id,
    has_csv = has_csv,
    has_rds = has_rds,
    n_rows = nrow(d),
    n_cols = ncol(d),
    csv_rows = if (has_csv) nrow(cdat) else NA_integer_,
    csv_cols = if (has_csv) ncol(cdat) else NA_integer_,
    names_match = if (has_csv) identical(names_d, names(cdat)) else FALSE,
    data_frame = is.data.frame(d),
    treatment_factor = "Treatment" %in% names_d && is.factor(d$Treatment),
    treatment_missing = if ("Treatment" %in% names_d) sum(is.na(d$Treatment)) else NA_integer_,
    treatment_levels = if ("Treatment" %in% names_d) nlevels(as.factor(d$Treatment)) else NA_integer_,
    n_yp = sum(startsWith(names_d, "YP_")),
    n_ys = sum(startsWith(names_d, "YS_")),
    n_x = sum(startsWith(names_d, "X_")),
    n_bad_prefix = length(bad_prefix),
    duplicate_names = anyDuplicated(names_d) > 0,
    bad_names = paste(names_d[!is_allowed_name(names_d)], collapse = ";"),
    bad_prefix = paste(bad_prefix, collapse = ";"),
    y_all_missing = paste(y_all_missing, collapse = ";"),
    x_all_missing = paste(x_all_missing, collapse = ";"),
    y_model_hostile = paste(y_model_hostile, collapse = ";"),
    exact_duplicate_columns = paste(head(exact_pairs, 25), collapse = ";"),
    hard_format_pass = hard_format_pass,
    analysis_compatible = analysis_compatible,
    stringsAsFactors = FALSE
  )
}

orig <- do.call(rbind, lapply(1:50, function(id) check_one(orig_dir, id)))
expansion <- do.call(rbind, lapply(51:121, function(id) check_one(exp_dir, id)))

write.csv(orig, file.path(prov_dir, "format_check_original_trials1_50.csv"), row.names = FALSE)
write.csv(expansion, file.path(prov_dir, "format_check_expansion_trials51_121.csv"), row.names = FALSE)

warnings <- expansion[!expansion$analysis_compatible |
                        expansion$x_all_missing != "" |
                        expansion$y_model_hostile != "" |
                        expansion$exact_duplicate_columns != "", ]
write.csv(warnings, file.path(prov_dir, "format_check_expansion_warnings.csv"), row.names = FALSE)

summary_lines <- c(
  "# Expansion Format Check",
  "",
  paste0("Run date: ", Sys.Date()),
  "",
  paste0("- Original trials checked: ", nrow(orig)),
  paste0("- Expansion trials checked: ", nrow(expansion)),
  paste0("- Expansion hard-format pass: ", sum(expansion$hard_format_pass), "/", nrow(expansion)),
  paste0("- Expansion analysis-compatible pass: ", sum(expansion$analysis_compatible), "/", nrow(expansion)),
  paste0("- Expansion warning rows: ", nrow(warnings)),
  "",
  "Hard-format pass requires CSV/RDS pair, matching names, data-frame RDS, factor Treatment, non-missing Treatment, at least two arms, at least one YP_ outcome, no unsupported column prefixes, no duplicate names, and syntactic column names.",
  "",
  "Analysis-compatible pass additionally requires no all-missing YP_/YS_ outcome columns. Nonnumeric categorical outcomes are reported as warnings but are allowed because the original trials include such outcomes too.",
  ""
)

if (nrow(warnings) > 0) {
  summary_lines <- c(summary_lines, "## Warnings", "")
  for (i in seq_len(nrow(warnings))) {
    row <- warnings[i, ]
    bits <- c()
    if (!row$analysis_compatible) bits <- c(bits, "analysis_compatible=FALSE")
    if (row$x_all_missing != "") bits <- c(bits, paste0("all-missing X: ", row$x_all_missing))
    if (row$y_model_hostile != "") bits <- c(bits, paste0("categorical/non-numeric outcomes: ", row$y_model_hostile))
    if (row$exact_duplicate_columns != "") bits <- c(bits, paste0("exact duplicate columns: ", row$exact_duplicate_columns))
    summary_lines <- c(summary_lines, paste0("- trial", row$Trial_ID, ": ", paste(bits, collapse = " | ")))
  }
}

writeLines(summary_lines, file.path(prov_dir, "format_check_summary.md"))

cat(paste(summary_lines, collapse = "\n"), "\n")
