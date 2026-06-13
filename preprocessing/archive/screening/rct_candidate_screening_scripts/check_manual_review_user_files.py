import csv
import json
from datetime import datetime, timezone
from pathlib import Path

import pandas as pd
import pyreadstat


ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "rct_expansion/provenance/manual_review_user_files_2026_06_11"
FLOW_COUNTS = ROOT / "rct_expansion/provenance/broad_dataset_screening_flow_counts.csv"


def rel(path):
    return str(Path(path).relative_to(ROOT))


def now_iso():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def write_csv(path, rows, fields=None):
    rows = list(rows)
    if fields is None:
        fields = list(rows[0].keys()) if rows else []
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def unique_count(df, column):
    return int(df[column].nunique(dropna=True)) if column in df.columns else ""


def value_counts(df, column):
    if column not in df.columns:
        return ""
    counts = df[column].value_counts(dropna=False)
    return "; ".join(f"{idx}={val}" for idx, val in counts.items())


def table_row(candidate_id, source_file, table_name, df, id_col="", treatment_col="", outcome_cols=None, notes=""):
    outcome_cols = outcome_cols or []
    duplicate_ids = ""
    if id_col and id_col in df.columns:
        duplicate_ids = int(df[id_col].duplicated().sum())
    return {
        "candidate_id": candidate_id,
        "source_file": rel(source_file),
        "table_name": table_name,
        "n_rows": int(df.shape[0]),
        "n_cols": int(df.shape[1]),
        "id_column": id_col,
        "unique_ids": unique_count(df, id_col) if id_col else "",
        "duplicate_id_rows": duplicate_ids,
        "treatment_column": treatment_col,
        "treatment_levels": value_counts(df, treatment_col) if treatment_col else "",
        "outcome_columns_sample": "; ".join(outcome_cols[:30]),
        "columns_sample": "; ".join(map(str, df.columns[:80])),
        "notes": notes,
    }


def update_flow_counts(candidate_decisions):
    if FLOW_COUNTS.exists():
        existing = pd.read_csv(FLOW_COUNTS)
    else:
        existing = pd.DataFrame()
    iteration_id = "manual_review_user_files_2026_06_11"
    if not existing.empty and "iteration_id" in existing.columns:
        existing = existing[existing["iteration_id"] != iteration_id]

    counts = pd.Series([r["decision"] for r in candidate_decisions]).value_counts().to_dict()
    rows = [
        {
            "iteration_id": iteration_id,
            "recorded_date": "2026-06-11",
            "stage_order": 9,
            "stage_id": "manual_review_user_files_checked",
            "parent_stage_id": "deferred_source_verified_needs_manual_review",
            "node_label": "User-provided manual-review files checked",
            "count": len(candidate_decisions),
            "node_kind": "screening",
            "criteria": "Inspected user-provided Downloads files and one existing official quarantine table where the provided archive was mismatched.",
            "source_output": "rct_expansion/provenance/manual_review_user_files_2026_06_11/manual_review_user_candidate_decisions.csv",
            "notes": "The provided RCTC-01557.zip was a mismatched duplicate of the eyeglasses dataset, so the existing official RCTC-01557 quarantine table was inspected for the candidate decision.",
        }
    ]
    mapping = [
        ("manual_review_user_qualified", "Qualified after manual data review", "qualified_for_cleaning_after_manual_data_review", "inclusion"),
        ("manual_review_user_not_qualified", "Not qualified after manual data review", "not_qualified_before_cleaning", "exclusion"),
        ("manual_review_user_duplicate", "Duplicate of active expansion trial", "duplicate_of_active_trial_exclude", "exclusion"),
    ]
    for stage_id, label, decision, kind in mapping:
        rows.append(
            {
                "iteration_id": iteration_id,
                "recorded_date": "2026-06-11",
                "stage_order": 10,
                "stage_id": stage_id,
                "parent_stage_id": "manual_review_user_files_checked",
                "node_label": label,
                "count": int(counts.get(decision, 0)),
                "node_kind": kind,
                "criteria": "Manual table inspection decision for user-supplied files.",
                "source_output": "rct_expansion/provenance/manual_review_user_files_2026_06_11/manual_review_user_candidate_decisions.csv",
                "notes": "Qualified candidates still require primary-publication review and outcome reproducibility audit before active inclusion.",
            }
        )
    out = pd.concat([existing, pd.DataFrame(rows)], ignore_index=True) if not existing.empty else pd.DataFrame(rows)
    out.to_csv(FLOW_COUNTS, index=False)


def main():
    table_rows = []
    file_rows = []
    decisions = []

    # RCTC-01367: user-provided dataverse_files.zip, also duplicated by mislabeled RCTC-01557.zip.
    dta_path = BASE / "extracted/dataverse_files/Long_term_adoption_Dataverse.dta"
    eye = pd.read_stata(dta_path)
    schools_treatments = eye.groupby("schid")["treatment"].nunique(dropna=True)
    table_rows.append(
        table_row(
            "RCTC-01367",
            dta_path,
            "Long_term_adoption_Dataverse.dta",
            eye,
            id_col="schid",
            treatment_col="treatment",
            outcome_cols=["endown_sc", "endown_sf", "harmvision_end", "nowearjun_end"],
            notes=f"Treatment is constant within {int((schools_treatments == 1).sum())} of {int(schools_treatments.shape[0])} schools; schools with >1 treatment={int((schools_treatments > 1).sum())}.",
        )
    )
    decisions.append(
        {
            "candidate_id": "RCTC-01367",
            "candidate_title": "Spillover Effect of One-off Subsidies on Long-Run Health Products Adoption: Experimental Evidence from Free Eyeglasses in Rural China",
            "files_checked": "dataverse_files.zip",
            "decision": "not_qualified_before_cleaning",
            "decision_reason": "Data are participant-level and have treatment/outcomes, but treatment assignment is constant within school ID schid across 31 schools, indicating clustered assignment; this is outside the non-clustered individual-randomization contract.",
            "next_action": "Do not move to active non-clustered cleaning queue.",
        }
    )

    # RCTC-01557 user zip mismatch and official quarantine table.
    mislabeled_path = BASE / "extracted/RCTC-01557/Long_term_adoption_Dataverse.dta"
    mislabeled = pd.read_stata(mislabeled_path)
    table_rows.append(
        table_row(
            "RCTC-01557_user_zip",
            mislabeled_path,
            "Long_term_adoption_Dataverse.dta",
            mislabeled,
            id_col="schid",
            treatment_col="treatment",
            outcome_cols=["endown_sc", "endown_sf", "harmvision_end"],
            notes="This file is byte-identical to the RCTC-01367 eyeglasses Stata file and does not match the expected music-intervention chemotherapy candidate.",
        )
    )
    official_01557 = ROOT / "rct_expansion/provenance/deferred_likely_qualified_evaluation_2026_06_11/source_verification_manual_review_queue/downloads/RCTC-01557/S 3 raw data.tab"
    music = pd.read_csv(official_01557, sep="\t")
    music_outcomes = [c for c in music.columns if c.startswith(("DASS", "GP", "GS", "GE", "GF"))]
    table_rows.append(
        table_row(
            "RCTC-01557",
            official_01557,
            "S 3 raw data.tab",
            music,
            id_col="ID",
            treatment_col="group",
            outcome_cols=music_outcomes,
            notes="Official quarantine table, not the user-provided zip, contains the expected music-intervention chemotherapy data.",
        )
    )
    decisions.append(
        {
            "candidate_id": "RCTC-01557",
            "candidate_title": "Music intervention combined with progressive muscle relaxation among women with cancer receiving chemotherapy",
            "files_checked": "RCTC-01557.zip; existing official quarantine S 3 raw data.tab",
            "decision": "qualified_for_cleaning_after_manual_data_review",
            "decision_reason": "The user-provided zip is mismatched, but the official quarantine table has 24 participant rows, unique ID, two group levels, treatment type, and longitudinal DASS/FACT-G item outcomes.",
            "next_action": "Use the official quarantine table, not the mislabeled user zip; read the publication and map primary outcome/covariates before cleaning.",
        }
    )

    # RCTC-02282 DataverseNL zip.
    bazoqf_path = BASE / "extracted/doi-10.34894-bazoqf/Data"
    bazoqf = pd.read_csv(bazoqf_path)
    table_rows.append(
        table_row(
            "RCTC-02282",
            bazoqf_path,
            "Data",
            bazoqf,
            id_col="Patient_Recode",
            treatment_col="Allocation",
            outcome_cols=["MRRpre", "VRRpre", "VTVpre", "MRRpost", "VRRpost", "VTVpost"],
            notes="Rows are repeated within patient IDs, so cleaning should reconcile repeated measurements to the publication-aligned participant-level estimand.",
        )
    )
    decisions.append(
        {
            "candidate_id": "RCTC-02282",
            "candidate_title": "Effects of S-Ketamine and Midazolam on Respiratory Variability: A Randomized Controlled Pilot Trial",
            "files_checked": "doi-10.34894-bazoqf.zip",
            "decision": "qualified_for_cleaning_after_manual_data_review",
            "decision_reason": "Data include treatment allocation with three arms, patient IDs, and pre/post respiratory variability outcomes; repeated rows per patient require cleaning reconciliation but are not arm-level aggregates.",
            "next_action": "Read main publication/protocol and map primary outcome; collapse or otherwise handle repeated patient rows according to publication analysis.",
        }
    )

    # RCTC-00064: duplicate/supporting copy of active trial82/RCTC-01411.
    sav_path = BASE / "extracted/RCTC-00064/Raw Data.sav"
    tocovid, _ = pyreadstat.read_sav(str(sav_path), apply_value_formats=False)
    table_rows.append(
        table_row(
            "RCTC-00064",
            sav_path,
            "Raw Data.sav",
            tocovid,
            id_col="ID",
            treatment_col="Randomization",
            outcome_cols=["AF", "AFnumber", "AFepisode", "OnsetAF", "HospStay", "CICUstay", "HDUstay"],
            notes="Same 250x122 structure and variables as active trial82/RCTC-01411 Raw Data Tocovid.tab; AF coding differs only in missing value representation.",
        )
    )
    decisions.append(
        {
            "candidate_id": "RCTC-00064",
            "candidate_title": "Blinded analysis of Tocovid in postoperative atrial fibrillation after CABG",
            "files_checked": "RCTC-00064.zip",
            "decision": "duplicate_of_active_trial_exclude",
            "decision_reason": "Structurally usable data, but the same Tocovid POAF study is already active as trial82 from RCTC-01411 with publication DOI 10.31083/j.rcm2304122 and a passing primary-outcome audit.",
            "next_action": "Do not add as a new active candidate; keep only as duplicate/supporting provenance if useful.",
        }
    )

    # RCTC-05010 user Excel.
    xlsx_path = BASE / "RCTC-05010.xlsx"
    tbi = pd.read_excel(xlsx_path, sheet_name="ITT_analysis set")
    tbi_outcomes = [c for c in tbi.columns if c.endswith(("_1", "_2", "_3")) or c.startswith(("z_", "MOTS", "PSC", "PSS", "SCWT", "DGF", "DGB", "TMRES", "TMT", "HDT", "HART", "RTI", "MTT", "OTS"))]
    table_rows.append(
        table_row(
            "RCTC-05010",
            xlsx_path,
            "ITT_analysis set",
            tbi,
            id_col="SUBJECT",
            treatment_col="GROUP",
            outcome_cols=tbi_outcomes,
            notes="Workbook also contains a CRF_variables dictionary sheet.",
        )
    )
    decisions.append(
        {
            "candidate_id": "RCTC-05010",
            "candidate_title": "Cerebrolysin and repetitive transcranial magnetic stimulation in traumatic brain injury",
            "files_checked": "RCTC-05010.xlsx",
            "decision": "qualified_for_cleaning_after_manual_data_review",
            "decision_reason": "Excel workbook contains an ITT analysis set with 86 unique subjects, three randomized groups, baseline/follow-up neuropsychological outcomes, and a CRF variable dictionary.",
            "next_action": "Read the publication and CRF dictionary, then map the primary endpoint and baseline covariates before cleaning.",
        }
    )

    file_rows.extend(
        [
            {
                "provided_file": rel(BASE / "dataverse_files.zip"),
                "matched_candidate_id": "RCTC-01367",
                "status": "checked",
                "notes": "Contains Long_term_adoption_Dataverse.dta and Stata analysis code.",
            },
            {
                "provided_file": rel(BASE / "doi-10.34894-bazoqf.zip"),
                "matched_candidate_id": "RCTC-02282",
                "status": "checked",
                "notes": "Contains Data CSV plus Study protocol PDF.",
            },
            {
                "provided_file": rel(BASE / "RCTC-00064.zip"),
                "matched_candidate_id": "RCTC-00064",
                "status": "checked_duplicate_active_trial82",
                "notes": "Contains Raw Data.sav, Output Data.pdf, and CONSORT checklist.",
            },
            {
                "provided_file": rel(BASE / "RCTC-01557.zip"),
                "matched_candidate_id": "RCTC-01557",
                "status": "mismatched_contents",
                "notes": "Archive contains the eyeglasses RCTC-01367 Stata file, not the music-intervention chemotherapy data.",
            },
            {
                "provided_file": rel(BASE / "RCTC-05010.xlsx"),
                "matched_candidate_id": "RCTC-05010",
                "status": "checked",
                "notes": "Contains ITT_analysis set and CRF_variables sheets.",
            },
        ]
    )

    write_csv(BASE / "manual_review_user_file_manifest.csv", file_rows)
    write_csv(BASE / "manual_review_user_table_inspection.csv", table_rows)
    write_csv(BASE / "manual_review_user_candidate_decisions.csv", decisions)
    write_csv(
        BASE / "qualified_for_cleaning_after_manual_data_review_queue.csv",
        [r for r in decisions if r["decision"] == "qualified_for_cleaning_after_manual_data_review"],
    )
    write_csv(
        BASE / "not_qualified_or_duplicate_after_manual_data_review.csv",
        [r for r in decisions if r["decision"] != "qualified_for_cleaning_after_manual_data_review"],
    )

    summary = {
        "generated_at_utc": now_iso(),
        "provided_file_count": len(file_rows),
        "candidate_decision_counts": pd.Series([r["decision"] for r in decisions]).value_counts().to_dict(),
        "qualified_candidates": [r["candidate_id"] for r in decisions if r["decision"] == "qualified_for_cleaning_after_manual_data_review"],
        "notes": "Qualified candidates are structurally data-qualified only; they still need primary-publication review and outcome reproducibility audit before active inclusion.",
    }
    (BASE / "manual_review_user_summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    update_flow_counts(decisions)
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
