#!/usr/bin/env Rscript

# Build a unified variable-level data dictionary for all cleaned RCT datasets.
# The script intentionally uses only base R so it can run in a lightweight
# project environment without installing workbook-writing packages.

root <- normalizePath(".", mustWork = TRUE)
output_path <- file.path(root, "data-dictionary.xlsx")
trial_output_dir <- file.path(root, "data_dictionary")
trial_validation_path <- file.path(trial_output_dir, "validation_summary.json")
expansion_dictionary_candidates <- c(
  file.path(root, "rct_expansion", "metadata", "data_dictionary.csv"),
  file.path(root, "local", "rct_expansion", "metadata", "data_dictionary.csv")
)
expansion_dictionary_path <- expansion_dictionary_candidates[
  file.exists(expansion_dictionary_candidates)
][1]

candidate_dirs <- data.frame(
  dir = c(
    file.path(root, "cleaned_data"),
    file.path(root, "cleaned_data", "Non_Clustered_RCT"),
    file.path(root, "rct_expansion", "cleaned_data")
  ),
  priority = c(1L, 2L, 2L),
  stringsAsFactors = FALSE
)

xml_escape <- function(x) {
  x <- as.character(x)
  x[is.na(x)] <- ""
  x <- gsub("&", "&amp;", x, fixed = TRUE)
  x <- gsub("<", "&lt;", x, fixed = TRUE)
  x <- gsub(">", "&gt;", x, fixed = TRUE)
  x <- gsub("\"", "&quot;", x, fixed = TRUE)
  x <- gsub("'", "&apos;", x, fixed = TRUE)
  x
}

col_letter <- function(n) {
  out <- character(length(n))
  for (i in seq_along(n)) {
    x <- n[i]
    letters <- character()
    while (x > 0) {
      rem <- (x - 1L) %% 26L
      letters <- c(LETTERS[rem + 1L], letters)
      x <- (x - 1L) %/% 26L
    }
    out[i] <- paste0(letters, collapse = "")
  }
  out
}

discover_rds_files <- function() {
  rows <- list()
  for (i in seq_len(nrow(candidate_dirs))) {
    d <- candidate_dirs$dir[i]
    if (!dir.exists(d)) next
    files <- list.files(d, pattern = "^trial[0-9]+\\.rds$", full.names = TRUE)
    if (!length(files)) next
    ids <- as.integer(sub("^trial([0-9]+)\\.rds$", "\\1", basename(files)))
    keep <- !is.na(ids)
    rows[[length(rows) + 1L]] <- data.frame(
      Trial_ID = ids[keep],
      path = normalizePath(files[keep], mustWork = TRUE),
      priority = candidate_dirs$priority[i],
      stringsAsFactors = FALSE
    )
  }
  if (!length(rows)) stop("No cleaned trial RDS files found.")
  files <- do.call(rbind, rows)
  files <- files[order(files$Trial_ID, files$priority, files$path), ]
  files <- files[!duplicated(files$Trial_ID), ]
  files <- files[order(files$Trial_ID), ]
  files
}

variable_role <- function(variable_name) {
  if (identical(variable_name, "Treatment")) return("Treatment assignment")
  if (identical(variable_name, "Participant_ID")) return("Participant cluster identifier")
  if (variable_name %in% c("Crossover_Sequence", "Crossover_Period", "Assessment_Window")) {
    return("Trial design variable")
  }
  if (startsWith(variable_name, "YP_")) return("Primary outcome")
  if (startsWith(variable_name, "YS_")) return("Secondary outcome")
  if (startsWith(variable_name, "X_")) return("Baseline covariate")
  "Other"
}

readable_variable_name <- function(variable_name) {
  x <- sub("^(YP|YS|X)_", "", variable_name)
  x <- gsub("_", " ", x, fixed = TRUE)
  trimws(gsub("[[:space:]]+", " ", x))
}

generated_explanation <- function(variable_name) {
  readable <- readable_variable_name(variable_name)
  role <- variable_role(variable_name)
  if (role == "Treatment assignment") {
    return("Randomized treatment assignment; control or reference arm is first when identifiable.")
  }
  if (role == "Participant cluster identifier") {
    return("De-identified participant cluster identifier for repeated-measures or crossover rows; exclude from adjustment covariates.")
  }
  if (role == "Trial design variable") {
    return(paste("Crossover or repeated-measures design variable:", readable))
  }
  if (role == "Primary outcome") return(paste("Primary outcome:", readable))
  if (role == "Secondary outcome") return(paste("Secondary outcome:", readable))
  if (role == "Baseline covariate") {
    return(paste("Baseline covariate or pre-treatment measurement:", readable))
  }
  paste("Cleaned analysis variable:", readable)
}

nonmissing_values <- function(x) {
  x[!is.na(x)]
}

n_unique_nonmissing <- function(x) {
  length(unique(nonmissing_values(x)))
}

is_time_like_name <- function(variable_name) {
  grepl(
    "time|survival|time_to|event_time|followup|follow_up|length_of_stay|(^|_)los($|_)",
    tolower(variable_name)
  )
}

infer_variable_type <- function(x, variable_name) {
  vals <- nonmissing_values(x)
  n_unique <- length(unique(vals))
  if (identical(variable_name, "Treatment")) return("factor")
  if (inherits(x, "Date") || inherits(x, "POSIXt") || inherits(x, "hms")) return("date/time")
  if (is.factor(x) || is.character(x)) {
    if (n_unique <= 2L) return("binary")
    return("factor")
  }
  if (is.logical(x)) return("binary")
  if (is.numeric(x) || is.integer(x)) {
    if (is_time_like_name(variable_name) && n_unique > 2L) {
      return("time-to-event/continuous time")
    }
    if (n_unique <= 2L) return("binary")
    return("continuous")
  }
  class(x)[1]
}

format_value <- function(x) {
  if (inherits(x, "Date")) return(format(x, "%Y-%m-%d"))
  if (inherits(x, "POSIXt")) return(format(x, "%Y-%m-%d %H:%M:%S"))
  if (is.numeric(x) || is.integer(x)) return(format(signif(x, 6), scientific = FALSE, trim = TRUE))
  as.character(x)
}

levels_or_range <- function(x, variable_type) {
  vals <- nonmissing_values(x)
  if (!length(vals)) return("")
  if (variable_type %in% c("continuous", "time-to-event/continuous time", "date/time")) {
    rng <- range(vals, na.rm = TRUE)
    return(paste(format_value(rng[1]), "to", format_value(rng[2])))
  }
  unique_vals <- unique(as.character(vals))
  unique_vals <- unique_vals[order(unique_vals)]
  displayed <- head(unique_vals, 20L)
  suffix <- if (length(unique_vals) > length(displayed)) "; ..." else ""
  paste0(paste(displayed, collapse = "; "), suffix)
}

read_existing_expansion_dictionary <- function(path) {
  if (!file.exists(path)) return(data.frame())
  dict <- read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
  required <- c("Trial_ID", "variable_name", "brief_explanation")
  if (!all(required %in% names(dict))) {
    warning("Existing expansion dictionary is missing required columns; ignoring it.")
    return(data.frame())
  }
  dict$key <- paste(dict$Trial_ID, dict$variable_name, sep = "\r")
  dict[!duplicated(dict$key), c("key", "brief_explanation")]
}

build_dictionary <- function(files, existing_dict) {
  existing_lookup <- setNames(existing_dict$brief_explanation, existing_dict$key)
  out <- vector("list", nrow(files))
  for (i in seq_len(nrow(files))) {
    id <- files$Trial_ID[i]
    d <- readRDS(files$path[i])
    variable_names <- names(d)
    rows <- vector("list", length(variable_names))
    for (j in seq_along(variable_names)) {
      variable_name <- variable_names[j]
      x <- d[[j]]
      type <- infer_variable_type(x, variable_name)
      key <- paste(id, variable_name, sep = "\r")
      existing_explanation <- unname(existing_lookup[key])
      has_existing <- length(existing_explanation) == 1L &&
        !is.na(existing_explanation) &&
        nzchar(trimws(existing_explanation))
      role <- variable_role(variable_name)
      rows[[j]] <- data.frame(
        Trial_ID = id,
        variable_name = variable_name,
        variable_role = role,
        variable_type = type,
        r_class = paste(class(x), collapse = "/"),
        n_rows = nrow(d),
        n_missing = sum(is.na(x)),
        n_unique_nonmissing = n_unique_nonmissing(x),
        levels_or_range = levels_or_range(x, type),
        short_explanation = if (has_existing) existing_explanation else generated_explanation(variable_name),
        source = if (has_existing) {
          "existing_expansion_dictionary"
        } else if (role == "Other") {
          "generated_from_cleaned_data"
        } else {
          "generated_from_cleaned_variable_name"
        },
        stringsAsFactors = FALSE
      )
    }
    out[[i]] <- do.call(rbind, rows)
  }
  do.call(rbind, out)
}

write_xlsx_one_sheet <- function(data, path, sheet_name = "Data_Dictionary") {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  temp_dir <- tempfile("data_dictionary_xlsx_")
  dir.create(temp_dir, recursive = TRUE)
  on.exit(unlink(temp_dir, recursive = TRUE), add = TRUE)

  dir.create(file.path(temp_dir, "_rels"), recursive = TRUE)
  dir.create(file.path(temp_dir, "docProps"), recursive = TRUE)
  dir.create(file.path(temp_dir, "xl", "_rels"), recursive = TRUE)
  dir.create(file.path(temp_dir, "xl", "worksheets"), recursive = TRUE)

  headers <- names(data)
  data_chars <- as.data.frame(
    lapply(data, function(x) {
      x <- as.character(x)
      x[is.na(x)] <- ""
      x
    }),
    stringsAsFactors = FALSE,
    check.names = FALSE
  )
  all_rows <- rbind(headers, as.matrix(data_chars))
  all_rows[is.na(all_rows)] <- ""
  n_rows <- nrow(all_rows)
  n_cols <- ncol(all_rows)
  last_cell <- paste0(col_letter(n_cols), n_rows)

  cell_xml <- function(value, row_idx, col_idx, header = FALSE) {
    ref <- paste0(col_letter(col_idx), row_idx)
    style <- if (header) " s=\"1\"" else ""
    if (!header && col_idx %in% c(1L, 6L, 7L, 8L) && grepl("^-?[0-9]+$", value)) {
      return(sprintf("<c r=\"%s\"%s><v>%s</v></c>", ref, style, value))
    }
    sprintf(
      "<c r=\"%s\" t=\"inlineStr\"%s><is><t>%s</t></is></c>",
      ref, style, xml_escape(value)
    )
  }

  rows_xml <- character(n_rows)
  for (r in seq_len(n_rows)) {
    cells <- vapply(
      seq_len(n_cols),
      function(c) cell_xml(all_rows[r, c], r, c, header = r == 1L),
      character(1)
    )
    rows_xml[r] <- sprintf("<row r=\"%d\">%s</row>", r, paste0(cells, collapse = ""))
  }

  column_widths <- c(10, 34, 24, 28, 18, 10, 10, 18, 42, 78, 34)
  cols_xml <- paste0(
    vapply(seq_len(n_cols), function(i) {
      width <- column_widths[pmin(i, length(column_widths))]
      sprintf("<col min=\"%d\" max=\"%d\" width=\"%s\" customWidth=\"1\"/>", i, i, width)
    }, character(1)),
    collapse = ""
  )

  writeLines(c(
    "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>",
    "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">",
    "<Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/>",
    "<Default Extension=\"xml\" ContentType=\"application/xml\"/>",
    "<Override PartName=\"/docProps/core.xml\" ContentType=\"application/vnd.openxmlformats-package.core-properties+xml\"/>",
    "<Override PartName=\"/docProps/app.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.extended-properties+xml\"/>",
    "<Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/>",
    "<Override PartName=\"/xl/worksheets/sheet1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>",
    "<Override PartName=\"/xl/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml\"/>",
    "</Types>"
  ), file.path(temp_dir, "[Content_Types].xml"))

  writeLines(c(
    "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>",
    "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">",
    "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"xl/workbook.xml\"/>",
    "<Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties\" Target=\"docProps/core.xml\"/>",
    "<Relationship Id=\"rId3\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties\" Target=\"docProps/app.xml\"/>",
    "</Relationships>"
  ), file.path(temp_dir, "_rels", ".rels"))

  writeLines(c(
    "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>",
    "<Properties xmlns=\"http://schemas.openxmlformats.org/officeDocument/2006/extended-properties\" xmlns:vt=\"http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes\">",
    "<Application>RCT Bench preprocessing</Application>",
    "</Properties>"
  ), file.path(temp_dir, "docProps", "app.xml"))

  created <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  writeLines(c(
    "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>",
    "<cp:coreProperties xmlns:cp=\"http://schemas.openxmlformats.org/package/2006/metadata/core-properties\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\" xmlns:dcterms=\"http://purl.org/dc/terms/\" xmlns:dcmitype=\"http://purl.org/dc/dcmitype/\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\">",
    "<dc:title>RCT Bench Data Dictionary</dc:title>",
    "<dc:creator>RCT Bench preprocessing</dc:creator>",
    sprintf("<dcterms:created xsi:type=\"dcterms:W3CDTF\">%s</dcterms:created>", created),
    "</cp:coreProperties>"
  ), file.path(temp_dir, "docProps", "core.xml"))

  writeLines(c(
    "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>",
    "<workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\">",
    "<sheets>",
    sprintf("<sheet name=\"%s\" sheetId=\"1\" r:id=\"rId1\"/>", xml_escape(sheet_name)),
    "</sheets>",
    "</workbook>"
  ), file.path(temp_dir, "xl", "workbook.xml"))

  writeLines(c(
    "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>",
    "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">",
    "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet1.xml\"/>",
    "<Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/>",
    "</Relationships>"
  ), file.path(temp_dir, "xl", "_rels", "workbook.xml.rels"))

  writeLines(c(
    "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>",
    "<styleSheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\">",
    "<fonts count=\"2\"><font><sz val=\"11\"/><name val=\"Calibri\"/></font><font><b/><sz val=\"11\"/><color rgb=\"FFFFFFFF\"/><name val=\"Calibri\"/></font></fonts>",
    "<fills count=\"3\"><fill><patternFill patternType=\"none\"/></fill><fill><patternFill patternType=\"gray125\"/></fill><fill><patternFill patternType=\"solid\"><fgColor rgb=\"FF1F4E78\"/><bgColor indexed=\"64\"/></patternFill></fill></fills>",
    "<borders count=\"1\"><border><left/><right/><top/><bottom/><diagonal/></border></borders>",
    "<cellStyleXfs count=\"1\"><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\"/></cellStyleXfs>",
    "<cellXfs count=\"2\"><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\" xfId=\"0\"/><xf numFmtId=\"0\" fontId=\"1\" fillId=\"2\" borderId=\"0\" xfId=\"0\" applyFont=\"1\" applyFill=\"1\"/></cellXfs>",
    "<cellStyles count=\"1\"><cellStyle name=\"Normal\" xfId=\"0\" builtinId=\"0\"/></cellStyles>",
    "</styleSheet>"
  ), file.path(temp_dir, "xl", "styles.xml"))

  sheet_xml <- c(
    "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>",
    "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\">",
    sprintf("<dimension ref=\"A1:%s\"/>", last_cell),
    "<sheetViews><sheetView workbookViewId=\"0\"><pane ySplit=\"1\" topLeftCell=\"A2\" activePane=\"bottomLeft\" state=\"frozen\"/></sheetView></sheetViews>",
    "<sheetFormatPr defaultRowHeight=\"15\"/>",
    sprintf("<cols>%s</cols>", cols_xml),
    sprintf("<sheetData>%s</sheetData>", paste0(rows_xml, collapse = "")),
    sprintf("<autoFilter ref=\"A1:%s\"/>", last_cell),
    "<pageMargins left=\"0.7\" right=\"0.7\" top=\"0.75\" bottom=\"0.75\" header=\"0.3\" footer=\"0.3\"/>",
    "</worksheet>"
  )
  writeLines(sheet_xml, file.path(temp_dir, "xl", "worksheets", "sheet1.xml"))

  if (file.exists(path)) unlink(path)
  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(temp_dir)
  status <- system2("/usr/bin/zip", c("-qr", shQuote(path), "."), stdout = TRUE, stderr = TRUE)
  if (!file.exists(path)) {
    stop("Failed to write workbook: ", paste(status, collapse = "\n"))
  }
  invisible(path)
}

validate_dictionary <- function(dictionary, files) {
  expected_ids <- 1:125
  found_ids <- sort(unique(dictionary$Trial_ID))
  if (!identical(found_ids, expected_ids)) {
    stop("Dictionary Trial_ID coverage is not exactly 1:125.")
  }
  if (any(!nzchar(dictionary$variable_type))) stop("Blank variable_type values found.")
  if (any(!nzchar(dictionary$short_explanation))) stop("Blank short_explanation values found.")

  counts_from_files <- vapply(files$path, function(path) ncol(readRDS(path)), integer(1))
  expected_counts <- setNames(counts_from_files, files$Trial_ID)
  dictionary_counts <- table(dictionary$Trial_ID)
  for (id in names(expected_counts)) {
    if (as.integer(dictionary_counts[id]) != expected_counts[id]) {
      stop("Dictionary row count mismatch for trial", id)
    }
  }
  if (any(duplicated(dictionary[c("Trial_ID", "variable_name")]))) {
    stop("Duplicate Trial_ID/variable_name rows found.")
  }
  invisible(TRUE)
}

replacement_dictionary_explanations <- c(
  "100\rTreatment" = "Treatment: randomized assignment to home exercise (control/reference) or supervised physical therapy.",
  "100\rYP_delta_zcq_symptom_severity_6w" = "Primary outcome: change from baseline to 6 weeks in the Zurich Claudication Questionnaire (ZCQ) symptom-severity score; negative values indicate improvement.",
  "100\rYS_delta_zcq_physical_function_6w" = "Secondary outcome: change from baseline to 6 weeks in the ZCQ physical-function score; negative values indicate improvement.",
  "100\rYS_zcq_satisfaction_6w" = "Secondary outcome: ZCQ treatment-satisfaction score at 6 weeks.",
  "100\rYS_delta_nrs_back_pain_6w" = "Secondary outcome: change from baseline to 6 weeks in back-pain numeric rating scale (NRS, 0-10); negative values indicate improvement.",
  "100\rYS_delta_nrs_leg_pain_6w" = "Secondary outcome: change from baseline to 6 weeks in leg-pain NRS (0-10); negative values indicate improvement.",
  "100\rYS_delta_nrs_leg_numbness_6w" = "Secondary outcome: change from baseline to 6 weeks in leg-numbness NRS (0-10); negative values indicate improvement.",
  "100\rYS_delta_walk_distance_m_6w" = "Secondary outcome: change from baseline to 6 weeks in self-paced walking-test distance, in metres.",
  "100\rYS_delta_daily_steps_6w" = "Secondary outcome: change from baseline to 6 weeks in mean daily steps, in steps/day.",
  "100\rX_zcq_symptom_severity_0w" = "Baseline covariate: ZCQ symptom-severity score at week 0.",
  "100\rX_zcq_physical_function_0w" = "Baseline covariate: ZCQ physical-function score at week 0.",
  "100\rX_nrs_back_pain_0w" = "Baseline covariate: back-pain NRS at week 0 (0-10).",
  "100\rX_nrs_leg_pain_0w" = "Baseline covariate: leg-pain NRS at week 0 (0-10).",
  "100\rX_nrs_leg_numbness_0w" = "Baseline covariate: leg-numbness NRS at week 0 (0-10).",
  "100\rX_walk_distance_m_0w" = "Baseline covariate: self-paced walking-test distance at week 0, in metres.",
  "100\rX_daily_steps_0w" = "Baseline covariate: mean daily steps at week 0, in steps/day.",
  "100\rX_age_years" = "Baseline covariate: age, in years.",
  "100\rX_sex" = "Baseline covariate: participant sex (Female or Male).",
  "100\rX_bmi" = "Baseline covariate: body mass index, in kg/m².",
  "100\rX_symptom_duration_months" = "Baseline covariate: duration of lumbar spinal stenosis symptoms, in months.",
  "108\rTreatment" = "Treatment: randomized assignment to placebo (control/reference) or tranexamic acid (TXA).",
  "108\rYP_any_oral_bleeding_7d" = "Primary outcome: indicator for any oral post-extraction bleeding through day 7 (1=yes, 0=no).",
  "108\rYS_oral_bleeding_count_7d" = "Secondary outcome: number of oral post-extraction bleeding episodes through day 7.",
  "108\rYS_clinically_relevant_oral_bleeding_7d" = "Secondary outcome: indicator for any clinically relevant oral bleeding through day 7 (1=yes, 0=no).",
  "108\rYS_clinically_relevant_oral_bleeding_count_7d" = "Secondary outcome: number of clinically relevant oral bleeding episodes through day 7.",
  "108\rYS_early_oral_bleeding_7d" = "Secondary outcome: indicator for any early oral bleeding through day 7 (1=yes, 0=no).",
  "108\rYS_early_oral_bleeding_count_7d" = "Secondary outcome: number of early oral bleeding episodes through day 7.",
  "108\rYS_delayed_oral_bleeding_7d" = "Secondary outcome: indicator for any delayed oral bleeding through day 7 (1=yes, 0=no).",
  "108\rYS_delayed_oral_bleeding_count_7d" = "Secondary outcome: number of delayed oral bleeding episodes through day 7.",
  "108\rYS_unplanned_medical_contact_7d" = "Secondary outcome: indicator for an unplanned medical contact through day 7 (1=yes, 0=no).",
  "108\rYS_thrombotic_event_7d" = "Safety outcome: indicator for a thrombotic event through day 7 (1=yes, 0=no).",
  "108\rX_age_years" = "Baseline covariate: age, in years.",
  "108\rX_sex" = "Baseline covariate: participant sex as recorded in the source workbook (F or M).",
  "108\rX_noac_type" = "Baseline covariate: non-vitamin K oral anticoagulant (NOAC) type.",
  "108\rX_alcohol_units_per_day" = "Baseline covariate: alcohol consumption, in units/day.",
  "108\rX_smoking_status" = "Baseline covariate: smoking status (Active, Never, or Previous).",
  "108\rX_chronic_heart_failure" = "Baseline covariate: chronic heart failure indicator (1=yes, 0=no).",
  "108\rX_hypertension" = "Baseline covariate: hypertension indicator (1=yes, 0=no).",
  "108\rX_diabetes" = "Baseline covariate: diabetes indicator (1=yes, 0=no).",
  "108\rX_history_stroke" = "Baseline covariate: history of stroke indicator (1=yes, 0=no).",
  "108\rX_chads_vasc_score" = "Baseline covariate: CHA₂DS₂-VASc thromboembolic-risk score.",
  "108\rX_noac_indication" = "Baseline covariate: clinical indication for NOAC treatment.",
  "108\rX_time_last_noac_to_extraction_days" = "Baseline procedural covariate: time from the last NOAC dose to dental extraction, in days.",
  "108\rX_number_extracted_teeth" = "Baseline procedural covariate: number of teeth extracted.")

csv_escape <- function(value) {
  value <- as.character(value)
  value[is.na(value)] <- ""
  escaped <- gsub("\"", "\"\"", value, fixed = TRUE)
  needs_quote <- grepl("[,\"\r\n]", value)
  escaped[needs_quote] <- paste0("\"", escaped[needs_quote], "\"")
  escaped
}

write_csv_minimal <- function(data, path) {
  data_chars <- as.data.frame(
    lapply(data, function(x) {
      x <- as.character(x)
      x[is.na(x)] <- ""
      x
    }),
    stringsAsFactors = FALSE,
    check.names = FALSE
  )
  matrix_values <- rbind(names(data_chars), as.matrix(data_chars))
  lines <- apply(matrix_values, 1L, function(row) paste(csv_escape(row), collapse = ","))
  new_text <- paste0(paste(lines, collapse = "\n"), "\n")
  old_text <- if (file.exists(path)) paste0(readChar(path, file.info(path)$size, useBytes = TRUE)) else ""
  if (!identical(old_text, new_text)) {
    writeChar(new_text, path, eos = NULL, useBytes = TRUE)
  }
  invisible(path)
}

sync_trial_dictionary_csvs <- function(dictionary, files, output_dir) {
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  public_columns <- setdiff(names(dictionary), "source")
  validation <- vector("list", 125L)

  for (id in 1:125) {
    path <- file.path(output_dir, sprintf("trial%d_dictionary.csv", id))
    current <- dictionary[dictionary$Trial_ID == id, public_columns, drop = FALSE]
    existing <- if (file.exists(path)) {
      read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
    } else {
      data.frame()
    }
    existing_lookup <- if (nrow(existing) && all(c("variable_name", "short_explanation") %in% names(existing))) {
      setNames(existing$short_explanation, existing$variable_name)
    } else {
      character()
    }

    for (i in seq_len(nrow(current))) {
      variable_name <- current$variable_name[i]
      key <- paste(id, variable_name, sep = "\r")
      curated <- unname(replacement_dictionary_explanations[key])
      if (length(curated) == 1L && !is.na(curated) && nzchar(curated)) {
        current$short_explanation[i] <- curated
      } else if (variable_name %in% names(existing_lookup)) {
        existing_text <- unname(existing_lookup[variable_name])
        if (!is.na(existing_text) && nzchar(trimws(existing_text))) {
          current$short_explanation[i] <- existing_text
        }
      }
    }
    write_csv_minimal(current, path)

    cleaned <- readRDS(files$path[files$Trial_ID == id])
    variable_names <- as.character(current$variable_name)
    prefixes_valid <- all(
      grepl("^(Treatment$|(YP|YS|X)_)", variable_names) |
        variable_names %in% c(
          "Participant_ID", "Crossover_Sequence", "Crossover_Period", "Assessment_Window"
        )
    )
    variables_match <- identical(variable_names, names(cleaned))
    validation[[id]] <- list(
      trialId = id,
      rows = nrow(current),
      checkedRows = ncol(cleaned),
      prefixesValid = prefixes_valid,
      variablesMatchCleanedData = variables_match,
      sourceColumnRemoved = !"source" %in% names(current)
    )
  }
  validation
}

write_trial_validation_json <- function(validation, path) {
  bool <- function(x) if (isTRUE(x)) "true" else "false"
  rows <- vapply(validation, function(item) {
    sprintf(
      paste0(
        "    {\n",
        "      \"trialId\": %d,\n",
        "      \"rows\": %d,\n",
        "      \"checkedRows\": %d,\n",
        "      \"prefixesValid\": %s,\n",
        "      \"variablesMatchCleanedData\": %s,\n",
        "      \"sourceColumnRemoved\": %s\n",
        "    }"
      ),
      item$trialId, item$rows, item$checkedRows,
      bool(item$prefixesValid), bool(item$variablesMatchCleanedData),
      bool(item$sourceColumnRemoved)
    )
  }, character(1))
  row_counts <- vapply(validation, function(item) item$rows, integer(1))
  text <- paste0(
    "{\n",
    "  \"summary\": {\n",
    sprintf("    \"files\": %d,\n", length(validation)),
    sprintf("    \"dictionaryRows\": %d,\n", sum(row_counts)),
    sprintf("    \"allRowCountsMatch\": %s,\n", bool(all(vapply(validation, function(item) item$rows == item$checkedRows, logical(1))))),
    sprintf("    \"allPrefixesValid\": %s,\n", bool(all(vapply(validation, function(item) item$prefixesValid, logical(1))))),
    sprintf("    \"allVariablesMatchCleanedData\": %s,\n", bool(all(vapply(validation, function(item) item$variablesMatchCleanedData, logical(1))))),
    sprintf("    \"allSourceColumnsRemoved\": %s,\n", bool(all(vapply(validation, function(item) item$sourceColumnRemoved, logical(1))))),
    sprintf("    \"minRows\": %d,\n", min(row_counts)),
    sprintf("    \"maxRows\": %d\n", max(row_counts)),
    "  },\n",
    "  \"validation\": [\n",
    paste(rows, collapse = ",\n"), "\n",
    "  ]\n",
    "}\n"
  )
  writeChar(text, path, eos = NULL, useBytes = TRUE)
  invisible(path)
}

files <- discover_rds_files()
if (nrow(files) != 125L || !identical(files$Trial_ID, 1:125)) {
  stop("Expected exactly 125 contiguous cleaned trial RDS files with Trial_ID 1:125.")
}

existing_dict <- read_existing_expansion_dictionary(expansion_dictionary_path)
dictionary <- build_dictionary(files, existing_dict)
validate_dictionary(dictionary, files)
write_xlsx_one_sheet(dictionary, output_path)
trial_validation <- sync_trial_dictionary_csvs(dictionary, files, trial_output_dir)
write_trial_validation_json(trial_validation, trial_validation_path)

cat("Wrote ", output_path, "\n", sep = "")
cat("Trials: ", length(unique(dictionary$Trial_ID)), "\n", sep = "")
cat("Variables: ", nrow(dictionary), "\n", sep = "")
cat("Variable types:\n")
print(sort(table(dictionary$variable_type), decreasing = TRUE))
cat("Sources:\n")
print(sort(table(dictionary$source), decreasing = TRUE))
cat("Trial-specific dictionaries: ", length(trial_validation), "\n", sep = "")
cat("Trial-specific dictionary rows: ", sum(vapply(trial_validation, function(item) item$rows, integer(1))), "\n", sep = "")
