#!/usr/bin/env python3
"""Normalize the active rct_expansion folder after multi-batch additions.

The script treats the current contiguous cleaned_data/trial51+ files as the
active truth, consolidates metadata/provenance around those files, restores
raw-data slots that were overwritten by a later batch, and writes issue reports.
"""

from __future__ import annotations

import csv
import hashlib
import re
import shutil
from datetime import date
from pathlib import Path

import pandas as pd


ROOT = Path(__file__).resolve().parents[2]
EXP = ROOT / "rct_expansion"
CLEAN = EXP / "cleaned_data"
RAW = EXP / "raw_data"
META = EXP / "metadata"
PUB = EXP / "publications"
PROV = EXP / "provenance"
CLEANUP = PROV / f"folder_cleanup_{date.today().isoformat().replace('-', '_')}"

MAIN_COLUMNS = [
    "Trial_ID",
    "Trial Number/Name",
    "Paper Name",
    "Journal",
    "Paper Link",
    "Publication Year",
    "# of Arm",
    "Control Group",
    "Study Phase",
    "Sample Size",
    "Priamry Outcome",
    "Primary Outcome Type",
    "Trial Success(Primary Outcome Significant)",
    "Statistical Model",
    "Randomization Scheme",
    "Randomization Scheme(High Level)",
    "Research Area",
    "Text Data",
    "Citation",
    "Issues Encountered",
]

PROVENANCE_COLUMNS = [
    "Trial_ID",
    "Repository",
    "Dataset_DOI",
    "License",
    "Download_Date",
    "Source_Files",
    "Baseline_Covariates_Selected",
    "Baseline_Outcome_Measurements_Included",
    "Covariate_Source",
    "Cleaning_Notes",
    "Original_Trial_ID",
    "Candidate_ID",
    "License_Status",
    "Publication_Status",
    "Cleaning_Status",
    "Verification_Reasons",
]

AUDIT_DETAIL_COLUMNS = [
    "Trial_ID",
    "audit_source",
    "audit_type",
    "candidate_id",
    "Original_Trial_ID",
    "outcome_variable",
    "outcome_role",
    "arm",
    "statistic",
    "paper_value",
    "paper_precision",
    "cleaned_value",
    "absolute_diff",
    "tolerance",
    "status",
    "paper_source",
    "notes",
]

AUDIT_SOURCE_FILES = [
    ("outcome_reproducibility_audit.csv", "strict_publication_reproducibility", PROV / "outcome_reproducibility_audit.csv"),
    ("outcome_reproducibility_audit_trials81_94.csv", "strict_publication_reproducibility", PROV / "outcome_reproducibility_audit_trials81_94.csv"),
    ("outcome_reproducibility_audit_manual_trials87_95.csv", "strict_publication_reproducibility", PROV / "outcome_reproducibility_audit_manual_trials87_95.csv"),
    ("manual_summary_statistics_audit.csv", "descriptive_summary_screen", PROV / "manual_download_screen_2026_06_11/manual_summary_statistics_audit.csv"),
]

ARCHIVE_METADATA_PATTERNS = [
    "meta_data_manual_review_trials100_105.*",
    "meta_data_manual_review_trials116_121.*",
    "meta_data_manual_trials87_95.*",
    "meta_data_trial96_restore.*",
    "meta_data_trials81_86_*.xlsx",
    "meta_data_trials81_94_*.xlsx",
    "data_dictionary_manual_*.csv",
    "data_dictionary_trial96_restore.csv",
    "data_dictionary_trials81_*.csv",
    "~$meta_data_active.xlsx",
]

RAW_RESTORE_SOURCES = {
    97: [ROOT / "manually-download-raw-data/RCTC-00152.xlsx"],
    98: [PROV / "manual_download_screen_2026_06_11/extracted/RCTC-00166/RCTC-00166"],
    99: [
        ROOT / "manually-download-raw-data/ALL_demographics+and+baseline_RCTC00167.xlsx",
        ROOT / "manually-download-raw-data/ANALYSED_RCT_Whole+group_RCTC00167.xlsx",
    ],
    100: [PROV / "manual_download_screen_2026_06_11/extracted/RCTC-00170/RCTC-00170"],
    101: [PROV / "manual_download_screen_2026_06_11/extracted/RCTC-00173/RCTC-00173"],
    102: [PROV / "manual_download_screen_2026_06_11/extracted/RCTC-00175/RCTC-00175"],
    103: [PROV / "manual_download_screen_2026_06_11/extracted/RCTC-00180/RCTC-00180"],
    104: [PROV / "manual_download_screen_2026_06_11/extracted/RCTC-00181/RCTC-00181"],
    105: [PROV / "manual_download_screen_2026_06_11/extracted/RCTC-00888/RCTC-00888"],
    106: [ROOT / "manually-download-raw-data/RCRC-00890"],
    107: [PROV / "manual_download_screen_2026_06_11/extracted/RCTC-00893/RCTC-00893"],
    108: [ROOT / "manually-download-raw-data/RCTC-01313"],
    109: [ROOT / "manually-download-raw-data/Raw_data.xlsx"],
    110: [PROV / "manual_download_screen_2026_06_11/extracted/RCTC-01383/RCTC-01383"],
    111: [ROOT / "manually-download-raw-data/RCTC-01888"],
    112: [PROV / "manual_download_screen_2026_06_11/extracted/RCTC-01926/RCTC-1926"],
    113: [PROV / "manual_download_screen_2026_06_11/extracted/RCTC-01937/RCTC-01937"],
    114: [PROV / "manual_download_screen_2026_06_11/extracted/RCTC-01948/RCTC-01948"],
    115: [ROOT / "manually-download-raw-data/RCTC-05226.xls"],
}

ANALYSIS_FILTER_NOTES = {
    91: "Filtered to participants with observed YP_vas_sitting_10d so the compact cleaned table matches the publication primary-outcome analysis rows and passes the shared analysis missingness cutoff.",
    107: "Filtered to participants with observed YP_function_8w so the compact cleaned table passes the shared analysis missingness cutoff after all-missing QOL columns were removed.",
}


def trial_num(value) -> int | None:
    if pd.isna(value):
        return None
    match = re.search(r"(\d+)", str(value))
    return int(match.group(1)) if match else None


def clean_str(value) -> str:
    if pd.isna(value):
        return ""
    return str(value).strip()


def read_csv_if_exists(path: Path) -> pd.DataFrame:
    return pd.read_csv(path) if path.exists() else pd.DataFrame()


def read_xlsx(path: Path, sheet: str | int) -> pd.DataFrame:
    if not path.exists():
        return pd.DataFrame()
    return pd.read_excel(path, sheet_name=sheet)


def normalize_doi(text: str) -> str:
    text = clean_str(text).lower()
    text = text.replace("https://doi.org/", "").replace("http://doi.org/", "")
    match = re.search(r"10\.\d{4,9}/[-._;()/:a-z0-9]+", text)
    return match.group(0).rstrip(".,;") if match else ""


def normalize_title(text: str) -> str:
    text = clean_str(text).lower()
    text = re.sub(r"[^a-z0-9]+", " ", text)
    return re.sub(r"\s+", " ", text).strip()


def csv_hash(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def unique_preserve(items: list[str]) -> list[str]:
    out: list[str] = []
    seen = set()
    for item in items:
        if item and item not in seen:
            seen.add(item)
            out.append(item)
    return out


def active_trial_ids() -> list[int]:
    ids = []
    for path in CLEAN.glob("trial*.csv"):
        n = trial_num(path.stem)
        if n is not None:
            ids.append(n)
    return sorted(set(ids))


def read_cleaned(trial_id: int) -> pd.DataFrame:
    return pd.read_csv(CLEAN / f"trial{trial_id}.csv")


def outcome_type(series: pd.Series) -> str:
    nonnull = series.dropna()
    if nonnull.empty:
        return "Unknown"
    numeric = pd.to_numeric(nonnull, errors="coerce")
    if numeric.notna().all():
        vals = set(numeric.dropna().unique().tolist())
        if vals and vals.issubset({0, 1, 0.0, 1.0}):
            return "Binary"
        return "Continuous"
    if nonnull.nunique() <= 10:
        return "Categorical"
    return "Text/other"


def is_binary_numeric(series: pd.Series) -> bool:
    numeric = pd.to_numeric(series.dropna(), errors="coerce")
    if numeric.empty or numeric.isna().any():
        return False
    values = set(numeric.unique().tolist())
    return bool(values) and values.issubset({0, 1, 0.0, 1.0})


def file_list(path: Path) -> str:
    if not path.exists():
        return ""
    files = []
    for child in sorted(path.rglob("*")):
        if child.is_file():
            files.append(str(child.relative_to(EXP)))
    return "; ".join(files)


def source_files_for_trial(trial_id: int) -> str:
    return file_list(RAW / f"trial{trial_id}")


def copy_source_to_raw(trial_id: int, sources: list[Path], actions: list[dict]) -> None:
    target = RAW / f"trial{trial_id}"
    archive = CLEANUP / "conflicting_raw_snapshot" / f"trial{trial_id}"
    if trial_id in range(100, 106) and target.exists() and not archive.exists():
        archive.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(target), str(archive))
        actions.append({
            "action": "archived_conflicting_raw_folder",
            "trial_id": trial_id,
            "from": str(target.relative_to(ROOT)),
            "to": str(archive.relative_to(ROOT)),
        })
    target.mkdir(parents=True, exist_ok=True)
    for src in sources:
        if not src.exists():
            actions.append({
                "action": "missing_raw_restore_source",
                "trial_id": trial_id,
                "from": str(src.relative_to(ROOT)) if src.is_absolute() and ROOT in src.parents else str(src),
                "to": str(target.relative_to(ROOT)),
            })
            continue
        if src.is_dir():
            for child in src.iterdir():
                dest = target / child.name
                if dest.exists():
                    continue
                if child.is_dir():
                    shutil.copytree(child, dest)
                else:
                    shutil.copy2(child, dest)
        else:
            dest = target / src.name
            if not dest.exists():
                shutil.copy2(src, dest)
        actions.append({
            "action": "restored_raw_source",
            "trial_id": trial_id,
            "from": str(src.relative_to(ROOT)) if ROOT in src.parents else str(src),
            "to": str(target.relative_to(ROOT)),
        })


def normalize_raw_dirs() -> pd.DataFrame:
    actions: list[dict] = []
    RAW.mkdir(parents=True, exist_ok=True)
    for trial_id, sources in RAW_RESTORE_SOURCES.items():
        copy_source_to_raw(trial_id, sources, actions)
    for trial_id in active_trial_ids():
        (RAW / f"trial{trial_id}").mkdir(parents=True, exist_ok=True)
    return pd.DataFrame(actions)


def metadata_sources() -> tuple[dict[int, dict], dict[int, dict]]:
    main: dict[int, dict] = {}
    provenance: dict[int, dict] = {}

    active = read_xlsx(META / "meta_data_active.xlsx", "Sheet1")
    active_prov = read_xlsx(META / "meta_data_active.xlsx", "Provenance")
    for _, row in active.iterrows():
        tid = trial_num(row.get("Trial_ID"))
        if tid is not None:
            main[tid] = {col: clean_str(row.get(col, "")) for col in MAIN_COLUMNS}
            main[tid]["Trial_ID"] = str(tid)
    for _, row in active_prov.iterrows():
        tid = trial_num(row.get("Trial_ID"))
        if tid is not None:
            provenance[tid] = {col: clean_str(row.get(col, "")) for col in PROVENANCE_COLUMNS}
            provenance[tid]["Trial_ID"] = str(tid)

    for path in [
        META / "meta_data_manual_trials87_95.csv",
        META / "meta_data_trial96_restore.csv",
        META / "meta_data_manual_review_trials116_121.csv",
        *sorted(META.glob("meta_data_next_batch_*.csv")),
    ]:
        df = read_csv_if_exists(path)
        for _, row in df.iterrows():
            tid = trial_num(row.get("Trial_ID"))
            if tid is not None:
                main[tid] = {col: clean_str(row.get(col, "")) for col in MAIN_COLUMNS}
                main[tid]["Trial_ID"] = str(tid)

    for path in sorted(META.glob("provenance_next_batch_*.csv")):
        df = read_csv_if_exists(path)
        for _, row in df.iterrows():
            tid = trial_num(row.get("Trial_ID"))
            if tid is not None:
                provenance[tid] = {col: clean_str(row.get(col, "")) for col in PROVENANCE_COLUMNS}
                provenance[tid]["Trial_ID"] = str(tid)

    manual = read_csv_if_exists(PROV / "manual_download_screen_2026_06_11/manual_final_decisions.csv")
    prepub = read_csv_if_exists(PROV / "manual_download_screen_2026_06_11/manual_candidate_decisions_prepub.csv")
    prepub_by_id = {
        clean_str(row.get("candidate_id")): row
        for _, row in prepub.iterrows()
        if clean_str(row.get("candidate_id"))
    }
    validation = read_csv_if_exists(PROV / "manual_download_screen_2026_06_11/manual_validation_summary.csv")
    validation_by_trial = {
        trial_num(row.get("Trial_ID")): row
        for _, row in validation.iterrows()
        if trial_num(row.get("Trial_ID")) is not None
    }
    for _, row in manual.iterrows():
        tid = trial_num(row.get("Trial_ID"))
        if tid is None or not (97 <= tid <= 115):
            continue
        cid = clean_str(row.get("candidate_id"))
        pre = prepub_by_id.get(cid)
        title = clean_str(pre.get("title")) if pre is not None else ""
        if not title:
            title = clean_str(row.get("source_title"))
        doi = clean_str(row.get("dataset_doi")) or (clean_str(pre.get("doi")) if pre is not None else "")
        d = read_cleaned(tid)
        yp_cols = [c for c in d.columns if c.startswith("YP_")]
        primary = yp_cols[0] if yp_cols else ""
        val = validation_by_trial.get(tid)
        main[tid] = {
            "Trial_ID": str(tid),
            "Trial Number/Name": cid,
            "Paper Name": title,
            "Journal": "",
            "Paper Link": f"https://doi.org/{doi}" if doi else "",
            "Publication Year": "",
            "# of Arm": str(int(val.get("treatment_arms"))) if val is not None and not pd.isna(val.get("treatment_arms")) else str(d["Treatment"].nunique(dropna=True)),
            "Control Group": clean_str(d["Treatment"].dropna().iloc[0]) if "Treatment" in d and d["Treatment"].dropna().size else "",
            "Study Phase": "Not recorded",
            "Sample Size": str(len(d)),
            "Priamry Outcome": primary.replace("YP_", "").replace("_", " "),
            "Primary Outcome Type": outcome_type(d[primary]) if primary else "Unknown",
            "Trial Success(Primary Outcome Significant)": "Not recorded",
            "Statistical Model": "Not recorded in compact cleanup metadata",
            "Randomization Scheme": "Publication-backed participant-level randomized trial",
            "Randomization Scheme(High Level)": "Individual",
            "Research Area": "Clinical / health",
            "Text Data": "No",
            "Citation": "",
            "Issues Encountered": clean_str(row.get("notes")),
        }
        provenance[tid] = {
            "Trial_ID": str(tid),
            "Repository": "Dryad",
            "Dataset_DOI": doi,
            "License": "",
            "Download_Date": "2026-06-11",
            "Source_Files": source_files_for_trial(tid),
            "Baseline_Covariates_Selected": "; ".join([c for c in d.columns if c.startswith("X_")]),
            "Baseline_Outcome_Measurements_Included": "; ".join([c for c in d.columns if re.search(r"_0[dwmy]?$|_0m$|_0w$|_0d$", c)]),
            "Covariate_Source": "Manual cleanup from batch provenance and cleaned variables",
            "Cleaning_Notes": clean_str(row.get("notes")),
            "Original_Trial_ID": "",
            "Candidate_ID": cid,
            "License_Status": "Open repository record; confirm license in source record if needed",
            "Publication_Status": "Publication-backed per manual screen",
            "Cleaning_Status": "active_cleaned",
            "Verification_Reasons": "Recovered from manual_final_decisions.csv and current cleaned data",
        }

    return main, provenance


def refresh_metadata_from_cleaned(main: dict[int, dict], provenance: dict[int, dict]) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    validation_rows = []
    dictionary_rows = []
    issues = []

    ids = active_trial_ids()
    active_max = max(ids) if ids else 121
    expected = set(range(51, max(active_max, 121) + 1))
    missing = sorted(expected - set(ids))
    extra = sorted(set(ids) - expected)
    for tid in missing:
        issues.append({"severity": "error", "trial_id": tid, "issue_type": "missing_cleaned_trial", "details": f"trial{tid}.csv is missing"})
    for tid in extra:
        issues.append({"severity": "warning", "trial_id": tid, "issue_type": "unexpected_cleaned_trial", "details": f"trial{tid}.csv is outside the contiguous active range"})

    for tid in ids:
        d = read_cleaned(tid)
        csv_path = CLEAN / f"trial{tid}.csv"
        rds_path = CLEAN / f"trial{tid}.rds"
        treatment_levels = d["Treatment"].dropna().astype(str).unique().tolist() if "Treatment" in d.columns else []
        yp_cols = [c for c in d.columns if c.startswith("YP_")]
        ys_cols = [c for c in d.columns if c.startswith("YS_")]
        x_cols = [c for c in d.columns if c.startswith("X_")]
        duplicate_cols = d.columns[d.columns.duplicated()].tolist()
        exact_duplicate_pairs = []
        for i, col_a in enumerate(d.columns):
            for col_b in d.columns[i + 1:]:
                both_missing = d[col_a].isna().all() and d[col_b].isna().all()
                if not both_missing and d[col_a].equals(d[col_b]):
                    exact_duplicate_pairs.append(f"{col_a}={col_b}")

        status = "pass"
        if "Treatment" not in d.columns or len(treatment_levels) < 2 or not yp_cols or not rds_path.exists():
            status = "fail"
        validation_rows.append({
            "Trial_ID": tid,
            "n_rows": len(d),
            "n_cols": len(d.columns),
            "has_treatment": "Treatment" in d.columns,
            "n_treatment_levels": len(treatment_levels),
            "n_primary_outcomes": len(yp_cols),
            "n_secondary_outcomes": len(ys_cols),
            "n_covariates": len(x_cols),
            "has_csv": csv_path.exists(),
            "has_rds": rds_path.exists(),
            "duplicate_column_names": "; ".join(duplicate_cols),
            "exact_duplicate_columns": "; ".join(exact_duplicate_pairs[:20]),
            "status": status,
        })

        if status == "fail":
            issues.append({
                "severity": "error",
                "trial_id": tid,
                "issue_type": "cleaned_contract_failure",
                "details": f"Treatment levels={len(treatment_levels)}, YP columns={len(yp_cols)}, RDS exists={rds_path.exists()}",
            })
        if duplicate_cols:
            issues.append({"severity": "error", "trial_id": tid, "issue_type": "duplicate_column_names", "details": "; ".join(duplicate_cols)})
        if exact_duplicate_pairs:
            issues.append({"severity": "warning", "trial_id": tid, "issue_type": "exact_duplicate_columns", "details": "; ".join(exact_duplicate_pairs[:20])})
        if not source_files_for_trial(tid):
            issues.append({"severity": "warning", "trial_id": tid, "issue_type": "missing_raw_files", "details": f"raw_data/trial{tid} has no files"})

        meta = main.setdefault(tid, {col: "" for col in MAIN_COLUMNS})
        meta["Trial_ID"] = str(tid)
        meta.setdefault("Trial Number/Name", f"trial{tid}")
        meta["Sample Size"] = str(len(d))
        meta["# of Arm"] = str(len(treatment_levels))
        if not meta.get("Control Group"):
            meta["Control Group"] = treatment_levels[0] if treatment_levels else ""
        if yp_cols and not meta.get("Priamry Outcome"):
            meta["Priamry Outcome"] = yp_cols[0].replace("YP_", "").replace("_", " ")
        if yp_cols and not meta.get("Primary Outcome Type"):
            meta["Primary Outcome Type"] = outcome_type(d[yp_cols[0]])
        for col in MAIN_COLUMNS:
            meta.setdefault(col, "")
        if tid in ANALYSIS_FILTER_NOTES:
            existing_issue = clean_str(meta.get("Issues Encountered"))
            filter_note = ANALYSIS_FILTER_NOTES[tid]
            if filter_note not in existing_issue:
                meta["Issues Encountered"] = "; ".join([x for x in [existing_issue, filter_note] if x])

        prov = provenance.setdefault(tid, {col: "" for col in PROVENANCE_COLUMNS})
        prov["Trial_ID"] = str(tid)
        if not prov.get("Source_Files"):
            prov["Source_Files"] = source_files_for_trial(tid)
        if not prov.get("Baseline_Covariates_Selected"):
            prov["Baseline_Covariates_Selected"] = "; ".join(x_cols)
        if not prov.get("Cleaning_Status"):
            prov["Cleaning_Status"] = "active_cleaned"
        for col in PROVENANCE_COLUMNS:
            prov.setdefault(col, "")
        if tid in ANALYSIS_FILTER_NOTES:
            existing_note = clean_str(prov.get("Cleaning_Notes"))
            filter_note = ANALYSIS_FILTER_NOTES[tid]
            if filter_note not in existing_note:
                prov["Cleaning_Notes"] = "; ".join([x for x in [existing_note, filter_note] if x])

        for col in d.columns:
            if col == "Treatment":
                vtype = "Treatment assignment"
                desc = "Randomized treatment assignment; control/reference arm is first when identifiable."
            elif col.startswith("YP_"):
                vtype = "Primary outcome"
                desc = "Primary outcome: " + col[3:].replace("_", " ")
            elif col.startswith("YS_"):
                vtype = "Secondary outcome"
                desc = "Secondary outcome: " + col[3:].replace("_", " ")
            elif col.startswith("X_"):
                vtype = "Baseline covariate"
                desc = "Baseline covariate or pre-treatment measurement: " + col[2:].replace("_", " ")
            else:
                vtype = "Other"
                desc = "Cleaned analysis variable: " + col.replace("_", " ")
            dictionary_rows.append({
                "Trial_ID": tid,
                "variable_name": col,
                "variable_type": vtype,
                "brief_explanation": desc,
            })

    meta_df = pd.DataFrame([main[tid] for tid in sorted(ids)])
    meta_df = meta_df[MAIN_COLUMNS]
    prov_df = pd.DataFrame([provenance[tid] for tid in sorted(ids)])
    prov_df = prov_df[PROVENANCE_COLUMNS]
    validation_df = pd.DataFrame(validation_rows).sort_values("Trial_ID")
    dictionary_df = pd.DataFrame(dictionary_rows).sort_values(["Trial_ID", "variable_name"])
    issues_df = pd.DataFrame(issues)
    return meta_df, prov_df, validation_df, dictionary_df, issues_df


def duplicate_screen(meta_df: pd.DataFrame) -> pd.DataFrame:
    rows = []
    columns = [
        "candidate_trial_id",
        "reference_source",
        "reference_trial_id",
        "match_rule",
        "candidate_title",
        "reference_title",
    ]
    active = meta_df.copy()
    active["doi_norm"] = active.apply(lambda r: normalize_doi(" ".join([clean_str(r.get("Paper Link")), clean_str(r.get("Citation"))])), axis=1)
    active["title_norm"] = active["Paper Name"].map(normalize_title)
    original = read_xlsx(ROOT / "cleaned_data/meta_data.xlsx", 0)
    if not original.empty:
        original["doi_norm"] = original.apply(lambda r: normalize_doi(" ".join([clean_str(r.get("Paper Link")), clean_str(r.get("Citation"))])), axis=1)
        original["title_norm"] = original["Paper Name"].map(normalize_title)

    for i, a in active.iterrows():
        for j, b in active.iterrows():
            if j <= i:
                continue
            rule = ""
            if a["doi_norm"] and a["doi_norm"] == b["doi_norm"]:
                rule = "active_doi_exact"
            elif a["title_norm"] and a["title_norm"] == b["title_norm"]:
                rule = "active_title_exact"
            if rule:
                rows.append({
                    "candidate_trial_id": a["Trial_ID"],
                    "reference_source": "active_expansion",
                    "reference_trial_id": b["Trial_ID"],
                    "match_rule": rule,
                    "candidate_title": a["Paper Name"],
                    "reference_title": b["Paper Name"],
                })

    if not original.empty:
        for _, a in active.iterrows():
            for _, b in original.iterrows():
                rule = ""
                if a["doi_norm"] and a["doi_norm"] == b["doi_norm"]:
                    rule = "original50_doi_exact"
                elif a["title_norm"] and a["title_norm"] == b["title_norm"]:
                    rule = "original50_title_exact"
                if rule:
                    rows.append({
                        "candidate_trial_id": a["Trial_ID"],
                        "reference_source": "original_meta_data",
                        "reference_trial_id": clean_str(b.get("Trial_ID")),
                        "match_rule": rule,
                        "candidate_title": a["Paper Name"],
                        "reference_title": clean_str(b.get("Paper Name")),
                    })

    hash_to_trials: dict[str, list[int]] = {}
    for path in CLEAN.glob("trial*.csv"):
        tid = trial_num(path.stem)
        if tid is None:
            continue
        hash_to_trials.setdefault(csv_hash(path), []).append(tid)
    for digest, ids in hash_to_trials.items():
        if len(ids) > 1:
            rows.append({
                "candidate_trial_id": ids[0],
                "reference_source": "active_cleaned_file_hash",
                "reference_trial_id": ";".join(map(str, ids[1:])),
                "match_rule": "cleaned_csv_sha256_exact",
                "candidate_title": "",
                "reference_title": digest,
            })
    return pd.DataFrame(rows, columns=columns)


def normalize_pubmed_download_log() -> pd.DataFrame:
    path = PUB / "pubmed_publication_downloads.csv"
    if not path.exists():
        return pd.DataFrame()
    rows = []
    actions = []
    with path.open(newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        fieldnames = reader.fieldnames or []
        for row in reader:
            old_pdf_path = row.get("PDF_Path", "")
            if old_pdf_path:
                tid = trial_num(row.get("Trial_ID"))
                basename = Path(old_pdf_path).name
                candidates = sorted((PUB / f"trial{tid}").glob(basename)) if tid is not None else []
                if candidates:
                    row["PDF_Path"] = str(candidates[0].relative_to(ROOT))
                else:
                    row["PDF_Path"] = old_pdf_path.replace("rct_expansion_10/", "rct_expansion/")
                if row["PDF_Path"] != old_pdf_path:
                    actions.append({
                        "action": "updated_pubmed_download_pdf_path",
                        "trial_id": tid,
                        "from": old_pdf_path,
                        "to": row["PDF_Path"],
                    })
            rows.append(row)
    if rows and fieldnames:
        with path.open("w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            writer.writeheader()
            writer.writerows(rows)
    return pd.DataFrame(actions)


def normalize_trial_id(value) -> str:
    n = trial_num(value)
    if n is not None:
        return str(n)
    return clean_str(value)


def normalize_audit_frame(df: pd.DataFrame, audit_source: str, audit_type: str) -> pd.DataFrame:
    out = df.copy()
    out["audit_source"] = audit_source
    out["audit_type"] = audit_type
    for col in AUDIT_DETAIL_COLUMNS:
        if col not in out.columns:
            out[col] = ""
    out["Trial_ID"] = out["Trial_ID"].map(normalize_trial_id)
    return out[AUDIT_DETAIL_COLUMNS]


def generated_descriptive_audit_rows(trial_id: int, meta_row: pd.Series | None = None) -> list[dict]:
    d = read_cleaned(trial_id)
    candidate_id = clean_str(meta_row.get("Trial Number/Name")) if meta_row is not None else ""
    publication_status = "no_main_publication_identified" if meta_row is not None and clean_str(meta_row.get("Paper Link")) in {"", "Not identified"} else "pending_publication_value_extraction"
    status = "descriptive_recovered_no_main_publication" if publication_status == "no_main_publication_identified" else "descriptive_recovered_pending_publication_comparison"
    notes = (
        "Generated during folder cleanup because no existing summary-stat audit rows were found for this active trial. "
        "Values are descriptive summaries computed from cleaned participant-level data; paper_value is blank until publication values are extracted."
    )
    rows: list[dict] = []
    if "Treatment" not in d.columns:
        return rows
    for arm, part in d.groupby("Treatment", dropna=False):
        arm_label = clean_str(arm) if not pd.isna(arm) else "Missing Treatment"
        rows.append({
            "Trial_ID": str(trial_id),
            "audit_source": "generated_from_cleaned_data",
            "audit_type": "descriptive_summary_screen",
            "candidate_id": candidate_id,
            "Original_Trial_ID": "",
            "outcome_variable": "Treatment",
            "outcome_role": "allocation",
            "arm": arm_label,
            "statistic": "n",
            "paper_value": "",
            "paper_precision": "",
            "cleaned_value": int(len(part)),
            "absolute_diff": "",
            "tolerance": "",
            "status": status,
            "paper_source": publication_status,
            "notes": notes,
        })
    primary_cols = [c for c in d.columns if c.startswith("YP_")]
    for col in primary_cols:
        for arm, part in d.groupby("Treatment", dropna=False):
            arm_label = clean_str(arm) if not pd.isna(arm) else "Missing Treatment"
            values = pd.to_numeric(part[col], errors="coerce").dropna()
            if values.empty:
                continue
            stat_rows = [
                ("n_nonmissing", int(values.size)),
                ("mean", float(values.mean())),
                ("sd", float(values.std(ddof=1)) if values.size > 1 else ""),
            ]
            if is_binary_numeric(part[col]):
                stat_rows.extend([
                    ("event_count", float(values.sum())),
                    ("rate", float(values.mean())),
                ])
            else:
                stat_rows.extend([
                    ("median", float(values.median())),
                    ("q1", float(values.quantile(0.25))),
                    ("q3", float(values.quantile(0.75))),
                ])
            for statistic, cleaned_value in stat_rows:
                rows.append({
                    "Trial_ID": str(trial_id),
                    "audit_source": "generated_from_cleaned_data",
                    "audit_type": "descriptive_summary_screen",
                    "candidate_id": candidate_id,
                    "Original_Trial_ID": "",
                    "outcome_variable": col,
                    "outcome_role": "primary",
                    "arm": arm_label,
                    "statistic": statistic,
                    "paper_value": "",
                    "paper_precision": "",
                    "cleaned_value": cleaned_value,
                    "absolute_diff": "",
                    "tolerance": "",
                    "status": status,
                    "paper_source": publication_status,
                    "notes": notes,
                })
    return rows


def build_audit_tables(meta_df: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame]:
    active_ids = set(meta_df["Trial_ID"].astype(str))
    frames = []
    for source_name, audit_type, path in AUDIT_SOURCE_FILES:
        if not path.exists():
            continue
        df = pd.read_csv(path)
        if df.empty or "Trial_ID" not in df.columns:
            continue
        normalized = normalize_audit_frame(df, source_name, audit_type)
        normalized = normalized[normalized["Trial_ID"].isin(active_ids)]
        if not normalized.empty:
            frames.append(normalized)

    detail = pd.concat(frames, ignore_index=True) if frames else pd.DataFrame(columns=AUDIT_DETAIL_COLUMNS)
    audited_ids = set(detail["Trial_ID"].astype(str))
    meta_by_trial = {str(row["Trial_ID"]): row for _, row in meta_df.iterrows()}
    generated_rows = []
    for trial_id in sorted(int(x) for x in active_ids - audited_ids):
        generated_rows.extend(generated_descriptive_audit_rows(trial_id, meta_by_trial.get(str(trial_id))))
    if generated_rows:
        generated = pd.DataFrame(generated_rows, columns=AUDIT_DETAIL_COLUMNS)
        detail = pd.concat([detail, generated], ignore_index=True)

    if detail.empty:
        summary = pd.DataFrame(columns=[
            "Trial_ID", "audit_rows", "audit_types", "audit_sources", "primary_rows",
            "pass_rows", "fail_rows", "descriptive_rows", "nonpass_statuses",
            "has_paper_values", "audit_coverage_status",
        ])
        return detail, summary

    detail["Trial_ID"] = detail["Trial_ID"].astype(str)
    detail = detail.sort_values(["Trial_ID", "outcome_role", "outcome_variable", "arm", "statistic"]).reset_index(drop=True)

    def status_summary(statuses: pd.Series) -> str:
        bad = sorted(set(clean_str(x) for x in statuses if clean_str(x) and clean_str(x) not in {"pass", "descriptive_recovered", "descriptive_recovered_pending_publication_comparison", "descriptive_recovered_no_main_publication"}))
        return "; ".join(bad)

    summary_rows = []
    for trial_id, part in detail.groupby("Trial_ID", sort=True):
        statuses = part["status"].map(clean_str)
        has_paper_values = part["paper_value"].map(clean_str).ne("").any()
        generated_only = set(part["audit_source"].map(clean_str)) == {"generated_from_cleaned_data"}
        if statuses.eq("pass").any():
            coverage = "strict_or_paper_value_audit_present"
        elif statuses.str.startswith("descriptive_recovered").any():
            coverage = "descriptive_summary_audit_present"
        elif generated_only:
            coverage = "generated_descriptive_summary_audit"
        else:
            coverage = "audit_rows_present_needs_review"
        summary_rows.append({
            "Trial_ID": trial_id,
            "audit_rows": len(part),
            "audit_types": "; ".join(unique_preserve(part["audit_type"].map(clean_str).tolist())),
            "audit_sources": "; ".join(unique_preserve(part["audit_source"].map(clean_str).tolist())),
            "primary_rows": int((part["outcome_role"].map(clean_str) == "primary").sum()),
            "pass_rows": int((statuses == "pass").sum()),
            "fail_rows": int(statuses.str.contains("fail", case=False, na=False).sum()),
            "descriptive_rows": int(statuses.str.startswith("descriptive_recovered").sum()),
            "nonpass_statuses": status_summary(statuses),
            "has_paper_values": bool(has_paper_values),
            "audit_coverage_status": coverage,
        })
    summary = pd.DataFrame(summary_rows).sort_values("Trial_ID")
    return detail, summary


def normalize_publications(meta_df: pd.DataFrame) -> pd.DataFrame:
    actions = []
    PUB.mkdir(parents=True, exist_ok=True)
    for path in list(PUB.glob("trial*.*")):
        tid = trial_num(path.name)
        if tid is None or not path.is_file():
            continue
        dest_dir = PUB / f"trial{tid}"
        dest_dir.mkdir(parents=True, exist_ok=True)
        dest = dest_dir / path.name
        if not dest.exists():
            shutil.move(str(path), str(dest))
            actions.append({"action": "moved_publication_file_to_trial_folder", "trial_id": tid, "from": str(path.relative_to(ROOT)), "to": str(dest.relative_to(ROOT))})

    for _, row in meta_df.iterrows():
        tid = int(row["Trial_ID"])
        folder = PUB / f"trial{tid}"
        folder.mkdir(parents=True, exist_ok=True)
        link_file = folder / "publication_link.txt"
        text = "\n".join([
            f"Trial_ID: {tid}",
            f"Paper Name: {clean_str(row.get('Paper Name'))}",
            f"Paper Link: {clean_str(row.get('Paper Link'))}",
            f"Citation: {clean_str(row.get('Citation'))}",
            "Availability: PDF stored here when publicly available; otherwise this file records the publication link.",
            "",
        ])
        link_file.write_text(text, encoding="utf-8")
    return pd.DataFrame(actions)


def write_outputs(
    meta_df: pd.DataFrame,
    prov_df: pd.DataFrame,
    validation_df: pd.DataFrame,
    dictionary_df: pd.DataFrame,
    issues_df: pd.DataFrame,
    duplicates_df: pd.DataFrame,
    audit_detail_df: pd.DataFrame,
    audit_summary_df: pd.DataFrame,
) -> None:
    META.mkdir(parents=True, exist_ok=True)
    PROV.mkdir(parents=True, exist_ok=True)
    PUB.mkdir(parents=True, exist_ok=True)

    dictionary_df.to_csv(META / "data_dictionary.csv", index=False)
    validation_df.to_csv(PROV / "validation_summary.csv", index=False)
    audit_detail_df.to_csv(PROV / "summary_statistics_audit_active.csv", index=False)
    audit_summary_df.to_csv(PROV / "summary_statistics_audit_summary_active.csv", index=False)
    issues_df.to_csv(CLEANUP / "cleanup_issues.csv", index=False)
    duplicates_df.to_csv(PROV / "duplicate_screening_active.csv", index=False)
    duplicates_df.to_csv(PROV / "duplicate_screening.csv", index=False)

    publication_links = meta_df[["Trial_ID", "Paper Name", "Paper Link", "Citation"]].copy()
    publication_links["publication_folder"] = publication_links["Trial_ID"].map(lambda x: f"publications/trial{x}")
    publication_links.to_csv(PUB / "publication_links.csv", index=False)

    download_log = prov_df[["Trial_ID", "Repository", "Dataset_DOI", "License", "Download_Date", "Source_Files", "Cleaning_Notes"]].copy()
    download_log.to_csv(PROV / "download_log.csv", index=False)

    for path in [META / "meta_data_active.xlsx", META / "meta_data_expansion.xlsx"]:
        with pd.ExcelWriter(path, engine="openpyxl") as writer:
            meta_df.to_excel(writer, sheet_name="Sheet1", index=False)
            prov_df.to_excel(writer, sheet_name="Provenance", index=False)
            validation_df.to_excel(writer, sheet_name="Validation", index=False)
            audit_summary_df.to_excel(writer, sheet_name="Audit_Summary", index=False)
            audit_detail_df.to_excel(writer, sheet_name="Audit_Detail", index=False)
            duplicates_df.to_excel(writer, sheet_name="Duplicate_Screen", index=False)
            issues_df.to_excel(writer, sheet_name="Cleanup_Issues", index=False)

    backup = META / "meta_data_backup.xlsx"
    if backup.exists():
        # Keep backup workbook intact; active consolidation should not rewrite archived trials.
        pass


def archive_batch_metadata() -> pd.DataFrame:
    archive = META / f"archive_{date.today().isoformat().replace('-', '_')}_batch_outputs"
    archive.mkdir(parents=True, exist_ok=True)
    actions = []
    for pattern in ARCHIVE_METADATA_PATTERNS:
        for path in META.glob(pattern):
            if not path.exists() or path.parent == archive:
                continue
            dest = archive / path.name
            if dest.exists():
                dest.unlink()
            shutil.move(str(path), str(dest))
            actions.append({"action": "archived_superseded_metadata_file", "from": str(path.relative_to(ROOT)), "to": str(dest.relative_to(ROOT))})
    rapp = CLEAN / ".Rapp.history"
    if rapp.exists():
        dest = CLEANUP / "stray_files" / ".Rapp.history"
        dest.parent.mkdir(parents=True, exist_ok=True)
        if dest.exists():
            dest.unlink()
        shutil.move(str(rapp), str(dest))
        actions.append({"action": "archived_stray_cleaned_data_file", "from": str(rapp.relative_to(ROOT)), "to": str(dest.relative_to(ROOT))})
    return pd.DataFrame(actions)


def write_summary(meta_df: pd.DataFrame, validation_df: pd.DataFrame, issues_df: pd.DataFrame, duplicates_df: pd.DataFrame, action_frames: list[pd.DataFrame]) -> None:
    CLEANUP.mkdir(parents=True, exist_ok=True)
    actions = pd.concat([df for df in action_frames if df is not None and not df.empty], ignore_index=True) if any(df is not None and not df.empty for df in action_frames) else pd.DataFrame()
    actions.to_csv(CLEANUP / "cleanup_actions.csv", index=False)
    counts = validation_df["status"].value_counts().to_dict()
    summary = [
        "# RCT Expansion Folder Cleanup",
        "",
        f"Run date: {date.today().isoformat()}",
        "",
        f"- Active cleaned trials: {len(meta_df)} ({pd.to_numeric(meta_df['Trial_ID']).min()}-{pd.to_numeric(meta_df['Trial_ID']).max()})",
        f"- Validation statuses: {counts}",
        f"- Duplicate-screen rows: {len(duplicates_df)}",
        f"- Cleanup issue rows: {len(issues_df)}",
        f"- Action rows: {len(actions)}",
        "",
        "Key notes:",
        "- trial100-trial105 raw folders were archived before restoring the older RCTC-00170 through RCTC-00888 raw sources.",
        "- The later manual-review batch remains active as trial116-trial121 in the current cleaned/raw files.",
        "- Superseded batch metadata files were moved under metadata/archive_*_batch_outputs; unified active metadata is meta_data_active.xlsx and meta_data_expansion.xlsx.",
        "- Summary-stat audit information is embedded in the metadata workbooks as Audit_Summary and Audit_Detail and exported to provenance/summary_statistics_audit_*.csv.",
        "",
    ]
    (CLEANUP / "cleanup_summary.md").write_text("\n".join(summary), encoding="utf-8")


def main() -> None:
    CLEANUP.mkdir(parents=True, exist_ok=True)
    raw_actions = normalize_raw_dirs()
    main_meta, provenance = metadata_sources()
    meta_df, prov_df, validation_df, dictionary_df, issues_df = refresh_metadata_from_cleaned(main_meta, provenance)
    duplicates_df = duplicate_screen(meta_df)
    audit_detail_df, audit_summary_df = build_audit_tables(meta_df)
    publication_actions = normalize_publications(meta_df)
    pubmed_actions = normalize_pubmed_download_log()
    write_outputs(meta_df, prov_df, validation_df, dictionary_df, issues_df, duplicates_df, audit_detail_df, audit_summary_df)
    archive_actions = archive_batch_metadata()
    write_summary(meta_df, validation_df, issues_df, duplicates_df, [raw_actions, publication_actions, pubmed_actions, archive_actions])
    print(f"Cleaned active expansion metadata for {len(meta_df)} trials")
    print(f"Validation failures: {(validation_df['status'] == 'fail').sum()}")
    print(f"Duplicate-screen rows: {len(duplicates_df)}")
    print(f"Issue rows: {len(issues_df)}")
    print(f"Summary: {CLEANUP / 'cleanup_summary.md'}")


if __name__ == "__main__":
    main()
