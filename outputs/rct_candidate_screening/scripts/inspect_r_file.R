args <- commandArgs(trailingOnly = TRUE)
path <- args[[1]]

id_re <- "(?i)\\b(id|subject|participant|patient|record|studyid|pid|sid)\\b"
treat_re <- "(?i)treat|trt|arm|group|condition|intervention|control|placebo|allocation|random|study[_ ]?group|product|sequence|assigned|trialarm|rx|alert"
outcome_re <- "(?i)outcome|primary|secondary|score|scale|follow|post|change|delta|pain|vas|qol|quality|anxiety|depress|stress|nausea|vomit|rhodes|rankin|mrs|nihss|adherence|step|activity|weight|bmi|waist|satiety|satiation|glucose|glyc|insulin|ghrelin|thirst|salt|atrial|fibrillation|poaf|hospital|event|rate|symptom|pcs|tsk|promis|odi|mobility|feasibility|usability|accept|heart|blood|cd4|viral|infection|recurrence|clinical"

summarize_df <- function(dat, object_name) {
  dat <- as.data.frame(dat)
  cols <- names(dat)
  id_cols <- grep(id_re, cols, value = TRUE)
  treatment_cols <- grep(treat_re, cols, value = TRUE)
  outcome_cols <- grep(outcome_re, cols, value = TRUE)
  treatment_levels <- c()
  for (col in head(treatment_cols, 6)) {
    vals <- unique(as.character(dat[[col]][!is.na(dat[[col]])]))
    if (length(vals) > 1 && length(vals) <= 12) {
      treatment_levels <- c(treatment_levels, paste0(col, ": ", paste(head(vals, 8), collapse = " | ")))
    }
  }
  numeric_count <- sum(vapply(dat, is.numeric, logical(1)))
  list(
    sheet_or_object = object_name,
    read_status = "readable",
    read_error = "",
    n_rows_sampled = nrow(dat),
    n_cols = ncol(dat),
    columns_sample = paste(head(cols, 80), collapse = "; "),
    id_candidates = paste(head(id_cols, 20), collapse = "; "),
    treatment_candidates = paste(head(treatment_cols, 30), collapse = "; "),
    treatment_levels_sample = paste(head(treatment_levels, 5), collapse = " || "),
    outcome_candidates = paste(head(outcome_cols, 40), collapse = "; "),
    numeric_col_count = numeric_count
  )
}

result <- tryCatch({
  ext <- tolower(tools::file_ext(path))
  if (ext == "sav") {
    if (requireNamespace("haven", quietly = TRUE)) {
      summarize_df(haven::read_sav(path), "sav")
    } else if (requireNamespace("foreign", quietly = TRUE)) {
      summarize_df(foreign::read.spss(path, to.data.frame = TRUE, use.value.labels = FALSE), "sav")
    } else {
      stop("neither haven nor foreign is installed")
    }
  } else if (ext == "dta") {
    if (requireNamespace("haven", quietly = TRUE)) {
      summarize_df(haven::read_dta(path), "dta")
    } else if (requireNamespace("foreign", quietly = TRUE)) {
      summarize_df(foreign::read.dta(path), "dta")
    } else {
      stop("neither haven nor foreign is installed")
    }
  } else if (ext %in% c("rds", "rdata")) {
    if (ext == "rds") {
      obj <- readRDS(path)
    } else {
      env <- new.env(parent = emptyenv())
      nm <- load(path, envir = env)
      obj <- env[[nm[[1]]]]
    }
    if (is.data.frame(obj)) {
      summarize_df(obj, paste(class(obj), collapse = "/"))
    } else if (is.list(obj)) {
      dfs <- Filter(is.data.frame, obj)
      if (length(dfs) > 0) {
        summarize_df(dfs[[1]], paste0("list:", names(dfs)[[1]]))
      } else {
        list(
          sheet_or_object = paste(class(obj), collapse = "/"),
          read_status = "readable_non_tabular",
          read_error = "",
          n_rows_sampled = "",
          n_cols = "",
          columns_sample = paste(head(names(obj), 80), collapse = "; "),
          id_candidates = "",
          treatment_candidates = "",
          treatment_levels_sample = "",
          outcome_candidates = "",
          numeric_col_count = ""
        )
      }
    } else {
      list(
        sheet_or_object = paste(class(obj), collapse = "/"),
        read_status = "readable_non_tabular",
        read_error = "",
        n_rows_sampled = "",
        n_cols = "",
        columns_sample = "",
        id_candidates = "",
        treatment_candidates = "",
        treatment_levels_sample = "",
        outcome_candidates = "",
        numeric_col_count = ""
      )
    }
  } else {
    stop(paste("unsupported extension", ext))
  }
}, error = function(e) {
  list(
    sheet_or_object = "",
    read_status = "failed",
    read_error = conditionMessage(e),
    n_rows_sampled = "",
    n_cols = "",
    columns_sample = "",
    id_candidates = "",
    treatment_candidates = "",
    treatment_levels_sample = "",
    outcome_candidates = "",
    numeric_col_count = ""
  )
})

json_escape <- function(value) {
  value <- as.character(value)
  value <- gsub("\\\\", "\\\\\\\\", value, fixed = TRUE)
  value <- gsub("\"", "\\\\\"", value, fixed = TRUE)
  value <- gsub("\n", "\\\\n", value, fixed = TRUE)
  value <- gsub("\r", "\\\\r", value, fixed = TRUE)
  value <- gsub("\t", "\\\\t", value, fixed = TRUE)
  value
}

json_value <- function(value) {
  if (length(value) == 0 || is.null(value) || (length(value) == 1 && is.na(value))) {
    return("null")
  }
  if (length(value) > 1) {
    value <- paste(value, collapse = "; ")
  }
  if (is.numeric(value) && length(value) == 1) {
    return(as.character(value))
  }
  if (is.logical(value) && length(value) == 1) {
    return(if (isTRUE(value)) "true" else "false")
  }
  paste0("\"", json_escape(value), "\"")
}

to_json_object <- function(x) {
  keys <- names(x)
  fields <- vapply(keys, function(key) paste0("\"", json_escape(key), "\":", json_value(x[[key]])), character(1))
  paste0("{", paste(fields, collapse = ","), "}")
}

cat(to_json_object(result))
