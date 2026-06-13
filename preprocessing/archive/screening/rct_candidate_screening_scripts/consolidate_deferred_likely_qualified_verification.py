import csv
import json
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

import pandas as pd


ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "rct_expansion/provenance/deferred_likely_qualified_evaluation_2026_06_11"
METADATA_SCREEN = BASE / "deferred_candidate_qualification.csv"
SOURCE_VERIFICATION_DIRS = [
    BASE / "source_verification_qualified_queue",
    BASE / "source_verification_manual_review_queue",
]
FLOW_COUNTS = ROOT / "rct_expansion/provenance/broad_dataset_screening_flow_counts.csv"


def now_iso():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def write_csv(path, rows, fields):
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def load_source_results():
    frames = []
    for path in SOURCE_VERIFICATION_DIRS:
        result_path = path / "verification_results.csv"
        if not result_path.exists():
            continue
        frame = pd.read_csv(result_path, dtype=str).fillna("")
        frame["source_verification_folder"] = str(path.relative_to(ROOT))
        frames.append(frame)
    if not frames:
        return pd.DataFrame()
    return pd.concat(frames, ignore_index=True)


def final_decision(row):
    source_decision = row.get("source_qualification_decision", "")
    metadata_decision = row.get("qualification_decision", "")
    if source_decision == "qualified_for_cleaning":
        return "qualified_for_cleaning_after_source_verification"
    if source_decision == "needs_manual_review_before_cleaning":
        return "needs_manual_review_before_cleaning_after_source_verification"
    if source_decision == "not_qualified_before_cleaning":
        return "not_qualified_before_cleaning_after_source_verification"
    if metadata_decision == "not_qualified_before_cleaning":
        return "not_qualified_before_cleaning_metadata_only"
    if metadata_decision == "access_or_file_uncertain_defer":
        return "access_or_file_uncertain_defer"
    return metadata_decision or "unclassified"


def update_flow_counts(final_counts, source_counts, source_summary):
    if FLOW_COUNTS.exists():
        existing = pd.read_csv(FLOW_COUNTS)
    else:
        existing = pd.DataFrame()
    iteration_id = "deferred_likely_qualified_source_verification_2026_06_11"
    if not existing.empty and "iteration_id" in existing.columns:
        existing = existing[existing["iteration_id"] != iteration_id]

    rows = [
        {
            "iteration_id": iteration_id,
            "recorded_date": "2026-06-11",
            "stage_order": 7,
            "stage_id": "deferred_source_verification_attempted",
            "parent_stage_id": "deferred_likely_qualified_evaluated",
            "node_label": "Deferred candidates source-verified",
            "count": int(sum(source_counts.values())),
            "node_kind": "screening",
            "criteria": "Official repository metadata/file routes were checked for deferred candidates that passed metadata qualification or needed manual source review.",
            "source_output": "rct_expansion/provenance/deferred_likely_qualified_evaluation_2026_06_11/final_deferred_candidate_disposition.csv",
            "notes": f"Registered {source_summary['registered_file_count']} files, downloaded {source_summary['downloaded_file_count']}, and inspected {source_summary['readable_table_count']} readable tables.",
        }
    ]
    node_defs = [
        (
            "deferred_source_verified_qualified",
            "Qualified after source verification",
            "qualified_for_cleaning_after_source_verification",
            "inclusion",
            "Official files downloaded and crude checks passed for open reuse, publication/randomization signal, participant-level rows, treatment/group assignment, and outcomes.",
            "final_qualified_for_cleaning_queue.csv",
            "Still requires primary-publication review, cleaning, validation, and reproducibility audit before active inclusion.",
        ),
        (
            "deferred_source_verified_needs_manual_review",
            "Needs manual review after source verification",
            "needs_manual_review_before_cleaning_after_source_verification",
            "review",
            "Official files downloaded or metadata inspected, but one or more publication, participant-level, treatment, or outcome checks remain unresolved.",
            "final_needs_manual_review_before_cleaning_queue.csv",
            "Manual file/publication review is needed before cleaning.",
        ),
        (
            "deferred_source_verified_not_qualified",
            "Not qualified after source verification",
            "not_qualified_before_cleaning_after_source_verification",
            "exclusion",
            "Official source verification did not confirm qualifying participant-level RCT data with treatment assignment and outcomes.",
            "final_not_qualified_before_cleaning_queue.csv",
            "Do not clean unless source information changes.",
        ),
        (
            "deferred_final_access_or_file_uncertain",
            "Still deferred for access or file uncertainty",
            "access_or_file_uncertain_defer",
            "review",
            "Metadata remains publication-backed and clinical but lacks a confirmed lawful file route or enough file evidence.",
            "final_access_or_file_uncertain_queue.csv",
            "Keep outside the cleaning queue until an official file route is identified.",
        ),
        (
            "deferred_final_metadata_not_qualified",
            "Not qualified by metadata only",
            "not_qualified_before_cleaning_metadata_only",
            "exclusion",
            "Metadata-only evaluation found disqualifying or unresolved core eligibility issues.",
            "final_not_qualified_before_cleaning_queue.csv",
            "Do not clean unless new source information resolves the issue.",
        ),
    ]
    for stage_id, label, decision, kind, criteria, output_name, notes in node_defs:
        rows.append(
            {
                "iteration_id": iteration_id,
                "recorded_date": "2026-06-11",
                "stage_order": 8,
                "stage_id": stage_id,
                "parent_stage_id": "deferred_source_verification_attempted" if "source_verified" in stage_id else "deferred_likely_qualified_evaluated",
                "node_label": label,
                "count": int(final_counts.get(decision, 0)),
                "node_kind": kind,
                "criteria": criteria,
                "source_output": f"rct_expansion/provenance/deferred_likely_qualified_evaluation_2026_06_11/{output_name}",
                "notes": notes,
            }
        )

    new_df = pd.DataFrame(rows)
    if existing.empty:
        out = new_df
    else:
        out = pd.concat([existing, new_df], ignore_index=True)
    out.to_csv(FLOW_COUNTS, index=False)


def main():
    metadata = pd.read_csv(METADATA_SCREEN, dtype=str).fillna("")
    source = load_source_results()
    source_summary = {
        "registered_file_count": 0,
        "downloaded_file_count": 0,
        "readable_table_count": 0,
    }
    for path in SOURCE_VERIFICATION_DIRS:
        summary_path = path / "verification_summary.json"
        if not summary_path.exists():
            continue
        summary = json.loads(summary_path.read_text(encoding="utf-8"))
        source_summary["registered_file_count"] += int(summary.get("registered_file_count", 0))
        source_summary["downloaded_file_count"] += int(summary.get("downloaded_file_count", 0))
        source_summary["readable_table_count"] += int(summary.get("readable_table_count", 0))

    source_cols = [
        "candidate_id",
        "qualification_decision",
        "downloaded_file_count",
        "download_failed_count",
        "oversize_skipped_count",
        "archive_extracted_file_count",
        "readable_table_count",
        "license_status",
        "publication_status",
        "randomization_status",
        "crossover_status",
        "participant_level_status",
        "treatment_assignment_status",
        "outcome_status",
        "reasons",
        "best_readable_tables",
        "treatment_evidence",
        "outcome_evidence",
        "next_action",
        "source_verification_folder",
    ]
    if source.empty:
        merged = metadata.copy()
    else:
        source = source[source_cols].rename(
            columns={
                "qualification_decision": "source_qualification_decision",
                "reasons": "source_reasons",
                "next_action": "source_next_action",
            }
        )
        merged = metadata.merge(source, on="candidate_id", how="left")
    merged = merged.fillna("")
    merged["final_disposition"] = merged.apply(final_decision, axis=1)
    merged["final_next_action"] = merged.apply(
        lambda row: row["source_next_action"] if row.get("source_next_action", "") else row.get("next_action", ""),
        axis=1,
    )

    front_cols = [
        "candidate_id",
        "final_disposition",
        "qualification_decision",
        "source_qualification_decision",
        "deferred_source_status",
        "title",
        "publisher",
        "doi",
        "downloaded_file_count",
        "readable_table_count",
        "qualification_reasons",
        "source_reasons",
        "best_readable_tables",
        "treatment_evidence",
        "outcome_evidence",
        "final_next_action",
    ]
    remaining = [c for c in merged.columns if c not in front_cols]
    merged = merged[front_cols + remaining]
    rows = merged.to_dict(orient="records")
    write_csv(BASE / "final_deferred_candidate_disposition.csv", rows, list(merged.columns))

    queue_names = {
        "qualified_for_cleaning_after_source_verification": "final_qualified_for_cleaning_queue.csv",
        "needs_manual_review_before_cleaning_after_source_verification": "final_needs_manual_review_before_cleaning_queue.csv",
        "not_qualified_before_cleaning_after_source_verification": "final_not_qualified_before_cleaning_queue.csv",
        "not_qualified_before_cleaning_metadata_only": "final_not_qualified_before_cleaning_queue.csv",
        "access_or_file_uncertain_defer": "final_access_or_file_uncertain_queue.csv",
    }
    for disposition, output_name in queue_names.items():
        subset = merged[merged["final_disposition"] == disposition]
        mode_rows = subset.to_dict(orient="records")
        if output_name == "final_not_qualified_before_cleaning_queue.csv":
            all_not = merged[merged["final_disposition"].isin(["not_qualified_before_cleaning_after_source_verification", "not_qualified_before_cleaning_metadata_only"])]
            mode_rows = all_not.to_dict(orient="records")
        write_csv(BASE / output_name, mode_rows, list(merged.columns))

    final_counts = Counter(merged["final_disposition"])
    source_counts = Counter(merged.loc[merged["source_qualification_decision"] != "", "source_qualification_decision"])
    summary_rows = []
    for decision, count in final_counts.most_common():
        summary_rows.append({"summary_type": "final_disposition", "group": decision, "count": count})
    for decision, count in source_counts.most_common():
        summary_rows.append({"summary_type": "source_verification_decision", "group": decision, "count": count})
    write_csv(BASE / "final_deferred_candidate_disposition_summary.csv", summary_rows, ["summary_type", "group", "count"])

    summary = {
        "generated_at_utc": now_iso(),
        "candidate_count": int(len(merged)),
        "source_verification_candidate_count": int(sum(source_counts.values())),
        "source_verification_file_counts": source_summary,
        "source_verification_decision_counts": dict(source_counts),
        "final_disposition_counts": dict(final_counts),
    }
    (BASE / "final_summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    update_flow_counts(final_counts, source_counts, source_summary)
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
