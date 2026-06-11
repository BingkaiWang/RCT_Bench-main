library(tidyverse)

root <- "rct_expansion"
raw_dir <- file.path(root, "raw_data")
clean_dir <- file.path(root, "cleaned_data")
publication_dir <- file.path(root, "publications")
backup_dir <- file.path(root, "backup")
prov_dir <- file.path(root, "provenance")
tmp_dir <- file.path(root, ".renumber_trials81_94_tmp")

dir.create(backup_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(prov_dir, recursive = TRUE, showWarnings = FALSE)

decisions <- read_csv(file.path(prov_dir, "audit_decisions_trials81_94.csv"), show_col_types = FALSE) %>%
  mutate(Original_Trial_ID = if ("Original_Trial_ID" %in% names(.)) as.integer(Original_Trial_ID) else as.integer(Trial_ID)) %>%
  arrange(Original_Trial_ID)

active_map <- decisions %>%
  filter(Analysis_Ready) %>%
  mutate(
    New_Trial_ID = row_number() + 80L,
    Backup_ID = NA_character_,
    Final_Status = "active"
  ) %>%
  select(Original_Trial_ID, New_Trial_ID, Backup_ID, Candidate_ID, Decision, Final_Status, Blocking_Reason, Review_Notes)

backup_map <- decisions %>%
  filter(!Analysis_Ready) %>%
  mutate(
    New_Trial_ID = NA_integer_,
    Backup_ID = sprintf("B%02d", row_number() + 5L),
    Final_Status = "backup"
  ) %>%
  select(Original_Trial_ID, New_Trial_ID, Backup_ID, Candidate_ID, Decision, Final_Status, Blocking_Reason, Review_Notes)

renumbering_map <- bind_rows(active_map, backup_map) %>%
  arrange(Final_Status != "active", coalesce(New_Trial_ID, Original_Trial_ID))

map_path <- file.path(prov_dir, "trials81_94_renumbering_map.csv")
already_migrated <- file.exists(map_path) &&
  file.exists(file.path(clean_dir, "trial86.rds")) &&
  !file.exists(file.path(clean_dir, "trial94.rds")) &&
  dir.exists(file.path(backup_dir, "B13"))

if (already_migrated) {
  message("Trial81-trial94 batch is already migrated; leaving files unchanged.")
  print(read_csv(map_path, show_col_types = FALSE))
  quit(save = "no", status = 0)
}

dir.create(tmp_dir, recursive = TRUE, showWarnings = FALSE)

move_one <- function(from, to) {
  if (!file.exists(from)) return(invisible(FALSE))
  dir.create(dirname(to), recursive = TRUE, showWarnings = FALSE)
  if (file.exists(to)) stop("Destination already exists: ", to)
  ok <- file.rename(from, to)
  if (!ok) stop("Could not move ", from, " to ", to)
  invisible(TRUE)
}

move_contents <- function(from, to) {
  if (!dir.exists(from)) return(invisible(FALSE))
  dir.create(to, recursive = TRUE, showWarnings = FALSE)
  items <- list.files(from, full.names = TRUE, all.files = FALSE, no.. = TRUE)
  for (item in items) {
    move_one(item, file.path(to, basename(item)))
  }
  if (length(list.files(from, all.files = FALSE, no.. = TRUE)) == 0) {
    unlink(from, recursive = TRUE)
  }
  invisible(TRUE)
}

rename_publication_prefix <- function(dir_path, old_prefix, new_prefix) {
  if (!dir.exists(dir_path)) return(invisible(FALSE))
  files <- list.files(dir_path, full.names = TRUE, recursive = FALSE, all.files = FALSE, no.. = TRUE)
  for (path in files) {
    new_name <- sub(old_prefix, new_prefix, basename(path), fixed = TRUE)
    if (new_name != basename(path)) {
      move_one(path, file.path(dirname(path), new_name))
    }
  }
  invisible(TRUE)
}

# Stage active trials first so old active IDs can be freed before renumbering.
for (i in seq_len(nrow(active_map))) {
  old_id <- active_map$Original_Trial_ID[i]
  move_one(file.path(raw_dir, paste0("trial", old_id)), file.path(tmp_dir, "raw", paste0("trial", old_id)))
  move_one(file.path(clean_dir, paste0("trial", old_id, ".csv")), file.path(tmp_dir, "cleaned", paste0("trial", old_id, ".csv")))
  move_one(file.path(clean_dir, paste0("trial", old_id, ".rds")), file.path(tmp_dir, "cleaned", paste0("trial", old_id, ".rds")))
  move_one(file.path(publication_dir, paste0("trial", old_id)), file.path(tmp_dir, "publications", paste0("trial", old_id)))
}

for (i in seq_len(nrow(backup_map))) {
  old_id <- backup_map$Original_Trial_ID[i]
  backup_id <- backup_map$Backup_ID[i]
  bdir <- file.path(backup_dir, backup_id)
  if (dir.exists(bdir)) stop("Backup directory already exists: ", bdir)
  dir.create(file.path(bdir, "raw_data"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(bdir, "cleaned_data"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(bdir, "publications"), recursive = TRUE, showWarnings = FALSE)

  move_contents(file.path(raw_dir, paste0("trial", old_id)), file.path(bdir, "raw_data"))
  move_one(file.path(clean_dir, paste0("trial", old_id, ".csv")), file.path(bdir, "cleaned_data", paste0(backup_id, ".csv")))
  move_one(file.path(clean_dir, paste0("trial", old_id, ".rds")), file.path(bdir, "cleaned_data", paste0(backup_id, ".rds")))

  move_contents(file.path(publication_dir, paste0("trial", old_id)), file.path(bdir, "publications"))
  rename_publication_prefix(file.path(bdir, "publications"), paste0("trial", old_id), backup_id)

  reason <- backup_map$Blocking_Reason[i]
  if (is.na(reason) || reason == "") reason <- backup_map$Decision[i]
  writeLines(
    c(
      paste0("# ", backup_id, " Backup Reason"),
      "",
      paste0("- Original trial ID: trial", old_id),
      paste0("- Candidate ID: ", backup_map$Candidate_ID[i]),
      paste0("- Audit decision: ", backup_map$Decision[i]),
      paste0("- Reason: ", reason),
      paste0("- Review notes: ", backup_map$Review_Notes[i]),
      "",
      "This candidate was removed from the active trial81-trial86 branch after primary-publication review and outcome reproducibility audit."
    ),
    file.path(bdir, "backup_reason.md")
  )
}

for (i in seq_len(nrow(active_map))) {
  old_id <- active_map$Original_Trial_ID[i]
  new_id <- active_map$New_Trial_ID[i]
  move_one(file.path(tmp_dir, "raw", paste0("trial", old_id)), file.path(raw_dir, paste0("trial", new_id)))
  move_one(file.path(tmp_dir, "cleaned", paste0("trial", old_id, ".csv")), file.path(clean_dir, paste0("trial", new_id, ".csv")))
  move_one(file.path(tmp_dir, "cleaned", paste0("trial", old_id, ".rds")), file.path(clean_dir, paste0("trial", new_id, ".rds")))
  move_one(file.path(tmp_dir, "publications", paste0("trial", old_id)), file.path(publication_dir, paste0("trial", new_id)))
  rename_publication_prefix(file.path(publication_dir, paste0("trial", new_id)), paste0("trial", old_id), paste0("trial", new_id))
}

if (dir.exists(tmp_dir) && length(list.files(tmp_dir, recursive = TRUE, all.files = FALSE, no.. = TRUE)) == 0) {
  unlink(tmp_dir, recursive = TRUE)
}

write_csv(renumbering_map, map_path)
renumbering_map
