#!/usr/bin/env python3
"""Build the public 125-trial metadata workbook.

The public workbook keeps the 18-column Sheet1 contract and appends the
expansion provenance/audit sheets used during curation.
"""

from __future__ import annotations

import csv
from pathlib import Path

from openpyxl import Workbook, load_workbook
from openpyxl.styles import Font, PatternFill
from openpyxl.utils import get_column_letter

from metadata_taxonomy import grouped_research_area, standard_outcome_type


ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "meta_data.xlsx"
ORIGINAL_CANDIDATES = [
    ROOT / "local" / "legacy_cleaned_data" / "meta_data_original_trials1_50.xlsx",
    ROOT / "meta_data.xlsx",
    ROOT / "cleaned_data" / "meta_data.xlsx",
]
EXPANSION_CANDIDATES = [
    ROOT / "local" / "rct_expansion" / "metadata" / "meta_data_active.xlsx",
    ROOT / "rct_expansion" / "metadata" / "meta_data_active.xlsx",
]

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
    "Citation",
]

COPY_EXPANSION_SHEETS = [
    "Provenance",
    "Validation",
    "Audit_Summary",
    "Audit_Detail",
    "Duplicate_Screen",
    "Cleanup_Issues",
]

# Publication metadata corrections for original trials.  These are applied at
# build time so a stale source workbook cannot reintroduce known DOI collisions.
ORIGINAL_CURATED = {
    31: {
        "Paper Link": "https://doi.org/10.1093/cid/ciy759",
        "Publication Year": 2019,
        "Citation": 83,
    },
}

# Public analysis-contract corrections. These values describe the cleaned
# analysis table rather than repeated period rows or ancillary study sessions.
PUBLIC_CURATED = {
    18: {"Control Group": "Standard Care"},
    52: {
        "Priamry Outcome": (
            "Change in serum phosphorus at 23 weeks; tenapanor-arm stool "
            "consistency at 7 weeks"
        ),
    },
    60: {
        "Control Group": "Sham",
        "Sample Size": 46,
        "Randomization Scheme": "randomized crossover sequence",
        "Randomization Scheme(High Level)": "Crossover",
    },
    65: {
        "# of Arm": 2,
        "Control Group": "Sham tDCS",
        "Sample Size": 45,
        "Randomization Scheme": "randomized crossover sequence",
        "Randomization Scheme(High Level)": "Crossover",
    },
    69: {
        "Sample Size": 12,
        "Randomization Scheme": "randomized crossover sequence",
        "Randomization Scheme(High Level)": "Crossover",
    },
    73: {
        "# of Arm": 2,
        "Control Group": "Human-assisted reassurance call",
        "Sample Size": 29,
        "Statistical Model": "Two-arm comparison of the publication-defined call-service primary outcome",
    },
    81: {"Control Group": "Placebo"},
    82: {"Control Group": "Not identifiable (blinded arm mapping not reported)"},
    83: {"Control Group": "Control"},
    84: {"Control Group": "CBT"},
    85: {"Control Group": "Wait-list control"},
    103: {
        "Trial Number/Name": "NCT01136148",
        "Paper Name": (
            "Economic Evaluation of a General Hospital Unit for Older People "
            "with Delirium and Dementia (TEAM Randomised Controlled Trial)"
        ),
        "Journal": "PLOS ONE",
        "Paper Link": "https://doi.org/10.1371/journal.pone.0140662",
        "Publication Year": 2015,
        "# of Arm": 2,
        "Control Group": "Standard care",
        "Sample Size": 599,
        "Priamry Outcome": "Observed quality-adjusted life years (QALYs) through 90 days",
        "Trial Success(Primary Outcome Significant)": "No",
        "Statistical Model": (
            "Generalized linear models for costs and QALYs with baseline adjustment; "
            "multiple imputation in the publication"
        ),
        "Randomization Scheme": "block randomization stratified by care-home residence",
        "Randomization Scheme(High Level)": "Stratified Block",
        "Research Area": "General Medicine, Health Services & Education",
        "Citation": 23,
    },
}


def first_existing(paths: list[Path]) -> Path:
    for path in paths:
        if path.exists():
            return path
    raise FileNotFoundError("None of these paths exist: " + ", ".join(map(str, paths)))


def sheet_rows(ws):
    rows = list(ws.iter_rows(values_only=True))
    while rows and all(value is None for value in rows[-1]):
        rows.pop()
    return rows


def rows_as_dicts(ws):
    rows = sheet_rows(ws)
    if not rows:
        return []
    headers = [str(value) if value is not None else "" for value in rows[0]]
    out = []
    for row in rows[1:]:
        if all(value is None for value in row):
            continue
        out.append({headers[i]: row[i] if i < len(row) else None for i in range(len(headers))})
    return out


def style_sheet(ws):
    if ws.max_row >= 1:
        fill = PatternFill("solid", fgColor="1F4E78")
        font = Font(color="FFFFFF", bold=True)
        for cell in ws[1]:
            cell.fill = fill
            cell.font = font
        ws.freeze_panes = "A2"
        ws.auto_filter.ref = ws.dimensions
    for col_idx, column in enumerate(ws.iter_cols(), start=1):
        max_len = 0
        for cell in column[:200]:
            if cell.value is not None:
                max_len = max(max_len, len(str(cell.value)))
        ws.column_dimensions[get_column_letter(col_idx)].width = min(max(max_len + 2, 10), 60)


def append_rows(ws, rows):
    for row in rows:
        ws.append(list(row))


def copy_sheet(src_ws, dest_wb, title: str):
    dest = dest_wb.create_sheet(title)
    for row in sheet_rows(src_ws):
        dest.append(list(row))
    style_sheet(dest)


def rebuild_validation_sheet(wb: Workbook) -> None:
    headers = [
        "Trial_ID",
        "n_rows",
        "n_cols",
        "has_treatment",
        "n_treatment_levels",
        "n_primary_outcomes",
        "n_secondary_outcomes",
        "n_covariates",
        "has_csv",
        "has_rds",
        "duplicate_column_names",
        "exact_duplicate_columns",
        "status",
    ]
    rows = []
    for trial_id in range(1, 126):
        csv_path = ROOT / "cleaned_data" / f"trial{trial_id}.csv"
        rds_path = ROOT / "cleaned_data" / f"trial{trial_id}.rds"
        with csv_path.open(newline="", encoding="utf-8-sig") as handle:
            reader = csv.reader(handle)
            data = list(reader)
        columns = data[0]
        body = data[1:]
        treatment_index = columns.index("Treatment") if "Treatment" in columns else None
        arms = (
            {row[treatment_index] for row in body if row[treatment_index] != ""}
            if treatment_index is not None
            else set()
        )
        column_vectors = list(zip(*body)) if body else [tuple() for _ in columns]
        duplicate_columns = 0
        seen_vectors = set()
        for vector in column_vectors:
            if vector in seen_vectors:
                duplicate_columns += 1
            seen_vectors.add(vector)
        valid_names = all(
            name == "Treatment"
            or name.startswith(("YP_", "YS_", "X_"))
            or name
            in {
                "Participant_ID",
                "Crossover_Sequence",
                "Crossover_Period",
                "Assessment_Window",
            }
            for name in columns
        )
        status = "pass" if (
            csv_path.exists()
            and rds_path.exists()
            and treatment_index is not None
            and len(arms) >= 2
            and any(name.startswith("YP_") for name in columns)
            and len(columns) == len(set(columns))
            and valid_names
        ) else "fail"
        rows.append([
            trial_id,
            len(body),
            len(columns),
            treatment_index is not None,
            len(arms),
            sum(name.startswith("YP_") for name in columns),
            sum(name.startswith("YS_") for name in columns),
            sum(name.startswith("X_") for name in columns),
            csv_path.exists(),
            rds_path.exists(),
            len(columns) - len(set(columns)),
            duplicate_columns,
            status,
        ])

    if "Validation" in wb.sheetnames:
        index = wb.sheetnames.index("Validation")
        wb.remove(wb["Validation"])
    else:
        index = len(wb.sheetnames)
    ws = wb.create_sheet("Validation", index)
    append_rows(ws, [headers] + rows)
    style_sheet(ws)


def annotate_quality_repairs(wb: Workbook) -> None:
    if "Audit_Detail" in wb.sheetnames:
        ws = wb["Audit_Detail"]
        headers = {cell.value: cell.column for cell in ws[1]}
        for row in range(ws.max_row, 1, -1):
            if str(ws.cell(row, headers["Trial_ID"]).value) == "103":
                ws.delete_rows(row)
        updates = {
            (83, "YP_delta_pal_t3_t1", "Control", "mean"): {
                "tolerance": 0.005,
                "status": "pass",
                "notes": (
                    "Paper reports two decimals; cleaned 0.00893 rounds to 0.01. "
                    "Tolerance includes half the reported 0.01 unit."
                ),
            },
            (84, "YP_delta_phq_post_pre", "CBT", "mean"): {
                "status": "reconciled_component_values",
                "notes": (
                    "Paper change (-3.46) equals its rounded post mean (10.35) minus "
                    "rounded baseline mean (13.81); both component means reproduce. "
                    "The available paired-row mean change is -3.11765 because post data are missing."
                ),
            },
            (87, "YP_delta_hr_bpm", "Oxycodone", "mean"): {
                "status": "source_file_incomplete",
                "notes": (
                    "Publication reports 18.71, but the public supplementary sheet has only "
                    "30 observed HR pairs (mean 17.6667) for 32 randomized patients. "
                    "No unsupported imputation was applied."
                ),
            },
            (90, "YP_dppr_percent", "Control", "sd"): {
                "status": "publication_source_mismatch",
                "notes": (
                    "Publication reports SD 20.75, while all 147 participant-level DPPR values "
                    "in its supplementary file give SD 15.1162. The reported 20.75 also equals "
                    "the control medication-level MPR SD; cleaned source values were retained."
                ),
            },
        }
        for row in range(2, ws.max_row + 1):
            raw_trial_id = ws.cell(row, headers["Trial_ID"]).value
            try:
                trial_id = int(raw_trial_id)
            except (TypeError, ValueError):
                trial_id = raw_trial_id
            key = (
                trial_id,
                ws.cell(row, headers["outcome_variable"]).value,
                ws.cell(row, headers["arm"]).value,
                ws.cell(row, headers["statistic"]).value,
            )
            if key in updates:
                for field, value in updates[key].items():
                    ws.cell(row, headers[field]).value = value
        trial103_rows = [
            ("Treatment", "allocation", "MMHU", "n_randomized", 309, 309),
            ("Treatment", "allocation", "Standard care", "n_randomized", 290, 290),
            ("YP_qaly_90d_observed", "primary", "All participants", "n_observed", 272, 272),
            ("YP_qaly_90d_observed", "primary", "MMHU", "n_observed", 139, 139),
            ("YP_qaly_90d_observed", "primary", "Standard care", "n_observed", 133, 133),
        ]
        for outcome, role, arm, statistic, paper_value, cleaned_value in trial103_rows:
            values = {
                "Trial_ID": 103,
                "audit_source": "PLOS ONE 2015 TEAM economic evaluation",
                "audit_type": "paper_value_reproducibility",
                "outcome_variable": outcome,
                "outcome_role": role,
                "arm": arm,
                "statistic": statistic,
                "paper_value": paper_value,
                "cleaned_value": cleaned_value,
                "absolute_diff": 0,
                "tolerance": 0,
                "status": "pass",
                "paper_source": "https://doi.org/10.1371/journal.pone.0140662",
                "notes": "Randomized-arm and observed-QALY counts reproduce the publication.",
            }
            ws.append([values.get(ws.cell(1, column).value) for column in range(1, ws.max_column + 1)])
        style_sheet(ws)

    if "Audit_Summary" in wb.sheetnames:
        ws = wb["Audit_Summary"]
        headers = {cell.value: cell.column for cell in ws[1]}
        summary_updates = {
            83: {"pass_rows": 8, "fail_rows": 0, "nonpass_statuses": None},
            84: {"pass_rows": 15, "fail_rows": 0, "nonpass_statuses": "reconciled_component_values"},
            87: {"pass_rows": 11, "fail_rows": 0, "nonpass_statuses": "source_file_incomplete"},
            90: {"pass_rows": 7, "fail_rows": 0, "nonpass_statuses": "publication_source_mismatch"},
            103: {
                "audit_rows": 5,
                "audit_types": "paper_value_reproducibility",
                "audit_sources": "PLOS ONE 2015 TEAM economic evaluation",
                "primary_rows": 3,
                "pass_rows": 5,
                "fail_rows": 0,
                "descriptive_rows": 0,
                "nonpass_statuses": None,
                "has_paper_values": True,
                "audit_coverage_status": "strict_or_paper_value_audit_present",
            },
        }
        for row in range(2, ws.max_row + 1):
            raw_trial_id = ws.cell(row, headers["Trial_ID"]).value
            try:
                trial_id = int(raw_trial_id)
            except (TypeError, ValueError):
                trial_id = raw_trial_id
            if trial_id in summary_updates:
                for field, value in summary_updates[trial_id].items():
                    ws.cell(row, headers[field]).value = value

    if "Cleanup_Issues" in wb.sheetnames:
        ws = wb["Cleanup_Issues"]
    else:
        ws = wb.create_sheet("Cleanup_Issues")
        ws.append(["Trial_ID", "Issue_Type", "Issue", "Status", "Resolution", "Notes"])
    existing = {
        (ws.cell(row, 1).value, ws.cell(row, 2).value, ws.cell(row, 3).value)
        for row in range(2, ws.max_row + 1)
    }
    quality_rows = [
        ("database", "cleaned-data quality sweep", "Identifiers, post-treatment covariates, sentinels, nonstandard names, and stale dictionaries", "resolved", "Applied deterministic repair script and rebuilt both dictionary layers", "Full 125-trial validation and duplicate screening rerun on 2026-07-22."),
        (38, "missing-value sentinel", "888/999 codes in survival, CD8, and pretreatment fields", "resolved", "Converted verified sentinel codes to missing values", "Primary survival time and affected baseline/secondary fields are numeric with explicit missingness."),
        (52, "arm-specific primary outcome", "BSFS change exists only in the tenapanor arm", "resolved", "Reclassified as YS_delta_bsfs_7w_tenapanor_only", "Serum-phosphorus change remains the randomized primary contrast available in both arms."),
        (60, "crossover row grain", "Participant cluster key absent and row count used as sample size", "resolved", "Added Participant_ID and explicit crossover design fields; metadata N=46", "Two period rows per randomized participant are retained."),
        (65, "crossover analysis set", "Ancillary nonrandomized control session and post-treatment X fields", "resolved", "Restricted to active-versus-sham sessions; added Participant_ID; moved blinding/safety fields to YS_", "Metadata N=45 and two treatment levels."),
        (69, "crossover row grain", "Subject identifier mislabeled as X_ and repeated-row N in metadata", "resolved", "Renamed to Participant_ID and Assessment_Window; metadata N=12", "Six repeated condition/window rows per participant are retained."),
        (73, "structurally undefined primary outcome", "No-call arm cannot have call-service satisfaction", "resolved", "Restricted cleaned benchmark to the randomized AI-versus-human call subset", "Metadata describes 29 participants and two arms for the publication-defined primary endpoint."),
        (17, "possible duplicate rows", "One exact duplicate row pair cannot be traced without the unavailable source participant ID", "documented", "Retained both rows", "No row was deleted without participant-level evidence."),
        (63, "differential outcome missingness", "FMD outcomes are more frequently missing in control/HIIT arms", "documented", "Retained observed participant rows and missingness", "No source-backed recovery or defensible imputation was available."),
        (87, "publication/source mismatch", "Oxycodone HR delta mean differs because the supplementary sheet has two missing HR pairs", "documented", "Retained observed source values", "Audit status is source_file_incomplete; no unsupported imputation was applied."),
        (90, "publication/source mismatch", "Published control DPPR SD 20.75 differs from supplementary participant-level SD 15.1162", "documented", "Retained supplementary participant-level values", "The paper's 20.75 equals its control MPR SD, suggesting a reporting copy error."),
        (90, "coincident public rows", "Removing the direct source identifier leaves 24 rows in 10 coincident public profiles", "resolved", "Retained all participant rows", "Every coincident profile maps to distinct source patient IDs; no participant was duplicated."),
        (95, "structural primary-outcome missingness", "Insertion time is undefined for failed device insertions and differs by arm", "documented", "Retained missing insertion times and explicit success/failure outcomes", "Encoding failed attempts as an arbitrary time would change the estimand."),
        (103, "primary-outcome alignment", "An isolated EQ-5D pain item was mislabeled as the primary outcome and standard-care ward subtypes were treated as separate arms", "resolved", "Derived observed 90-day QALYs from patient-reported EQ-5D-3L and combined both standard-care ward types", "The resulting 272 observed QALYs exactly match the publication's reported count; metadata now links the TEAM economic-evaluation paper."),
        ("database", "publication-audit coverage", "Legacy trials 1-50 and descriptive-only expansion trials lack strict paper-value targets", "open", "Prioritize future publication-value audits", "Structural and semantic validation cannot substitute for paper-value reproduction."),
    ]
    for item in quality_rows:
        if item[:3] not in existing:
            ws.append(item)
    style_sheet(ws)


def main():
    original_path = first_existing(ORIGINAL_CANDIDATES)
    expansion_path = first_existing(EXPANSION_CANDIDATES)

    original_wb = load_workbook(original_path, data_only=False)
    expansion_wb = load_workbook(expansion_path, data_only=False)

    original_rows = [
        row for row in rows_as_dicts(original_wb[original_wb.sheetnames[0]])
        if row.get("Trial_ID") is not None and int(row.get("Trial_ID")) <= 50
    ]
    expansion_rows = [
        row for row in rows_as_dicts(expansion_wb["Sheet1"])
        if row.get("Trial_ID") is not None and 51 <= int(row.get("Trial_ID")) <= 125
    ]

    combined = []
    for row in original_rows + expansion_rows:
        trial_id = int(row["Trial_ID"])
        row = dict(row)
        row.update(ORIGINAL_CURATED.get(trial_id, {}))
        row.update(PUBLIC_CURATED.get(trial_id, {}))
        row["Primary Outcome Type"] = standard_outcome_type(trial_id)
        row["Research Area"] = grouped_research_area(row.get("Research Area"))
        values = [row.get(column) for column in MAIN_COLUMNS]
        values[0] = trial_id
        combined.append(values)

    trial_ids = [int(row[0]) for row in combined if row[0] is not None]
    if sorted(trial_ids) != list(range(1, 126)):
        raise ValueError(f"Expected Trial_ID 1:125 exactly, found {min(trial_ids)}:{max(trial_ids)} ({len(trial_ids)} rows)")
    if len(set(trial_ids)) != 125:
        raise ValueError("Duplicate Trial_ID values found in combined metadata.")

    wb = Workbook()
    ws = wb.active
    ws.title = "Sheet1"
    append_rows(ws, [MAIN_COLUMNS] + combined)
    style_sheet(ws)

    for sheet_name in COPY_EXPANSION_SHEETS:
        if sheet_name in expansion_wb.sheetnames:
            copy_sheet(expansion_wb[sheet_name], wb, sheet_name)

    rebuild_validation_sheet(wb)
    annotate_quality_repairs(wb)

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    wb.save(OUTPUT)
    print(f"Wrote {OUTPUT}")
    print(f"Sheet1 rows: {len(combined)}")
    print(f"Expansion metadata source: {expansion_path}")
    print(f"Original metadata source: {original_path}")


if __name__ == "__main__":
    main()
