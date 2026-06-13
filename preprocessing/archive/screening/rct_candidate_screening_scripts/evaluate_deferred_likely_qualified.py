import csv
import json
import re
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

import pandas as pd


ROOT = Path(__file__).resolve().parents[3]
PREDOWNLOAD = ROOT / "outputs/rct_candidate_screening/predownload_screen/likely_qualified_predownload_screen.csv"
OUT = ROOT / "rct_expansion/provenance/deferred_likely_qualified_evaluation_2026_06_11"
FLOW_COUNTS = ROOT / "rct_expansion/provenance/broad_dataset_screening_flow_counts.csv"

DEFERRED_STATUSES = {
    "Defer - missing access/file certainty",
    "Defer - low clinical or data confidence",
}

OPEN_RE = re.compile(r"cc0|cc-by|creative commons|openaccess|open access|public domain", re.I)
RESTRICTED_RE = re.compile(
    r"restrictedaccess|restricted access|closedaccess|closed access|custom terms|data use agreement|\bdua\b|"
    r"request access|available upon request|provided on request|controlled access|login required|permission required|"
    r"embargo|non[- ]?commercial|no derivatives|cc-by-nc|cc-by-nd",
    re.I,
)
PUB_RE = re.compile(r"\b10\.\d{4,9}/[^\s|;,)]*|pubmed|journal|article|publication|manuscript|issupplementto:doi", re.I)
RANDOM_RE = re.compile(r"randomi[sz]ed|randomly assigned|random allocation|randomized controlled trial|\brct\b", re.I)
HEALTH_RE = re.compile(
    r"\b(patient|patients|participant|participants|clinical|clinic|medical|medicine|health|disease|pain|surgery|"
    r"therapy|treatment|drug|dose|pharma|hospital|diabetes|cancer|covid|stroke|depression|anxiety|psych|"
    r"obesity|weight|cardiac|renal|kidney|pregnan|postpartum|nausea|vomit|atrial|fibrillation|adults|"
    r"children|women|men|older|elderly|neuro|rehabilitation|symptom|blood|infection|hiv|malaria|vaccine|"
    r"exercise|diet|sleep|back pain|bmi|glycemia|insulin|hysteroscopic|melanoma|traumatic brain injury)\b",
    re.I,
)
PARTICIPANT_RE = re.compile(r"\b(participant|patient|subject|individual|anonymi[sz]ed|de-?identified|itt|raw data)\b", re.I)
TREATMENT_RE = re.compile(r"\b(treatment|intervention|control|placebo|arm|group|allocated|assigned|randomization)\b", re.I)
OUTCOME_RE = re.compile(r"\b(outcome|score|scale|follow[- ]?up|post|change|delta|primary|secondary|endpoint|measure)\b", re.I)

ANIMAL_RE = re.compile(r"\b(calf|calves|cat|cats|dog|dogs|mouse|mice|rat|rats|animal|veterinary|dairy|cattle|bovine|porcine|sheep|goat|poultry)\b", re.I)
OBS_RE = re.compile(r"cross-sectional|observational|cohort study|case-control|retrospective|secondary analysis|non[- ]randomi[sz]ed", re.I)
CLUSTER_RE = re.compile(r"cluster[- ]randomi[sz]ed|community[- ]randomi[sz]ed|school[- ]randomi[sz]ed|stepped wedge", re.I)
NON_CLINICAL_RE = re.compile(
    r"microfinance|financial inclusion|cash transfer|business|bribe|international law|gender prejudice|"
    r"academic research|policy experiment|development economics|forecasting experiment|students, faculty|"
    r"early childhood education|school gardens|women working|gendered attitudes",
    re.I,
)
PROTOCOL_MATERIAL_RE = re.compile(
    r"study protocol|trial protocol|protocol for|statistical analysis plan|questionnaire|instrument|codebook only|"
    r"materials only|guidepost|trial organization|preregistration|ethics? approval|consort checklist",
    re.I,
)
AGGREGATE_RE = re.compile(
    r"aggregate|aggregated|summary[- ]level|summary data|table s\d+|supplementary table|additional table|"
    r"baseline characteristics|imputation model|specifications for the imputation|differentially methylated|"
    r"genome|epigenome|dmr|methylation|transcriptom|proteom",
    re.I,
)
NOT_DATA_ASSET_RE = re.compile(
    r"\berratum\b|correction:|powerpoint|slides?|audio|video|figure|image|jpg|png|pdf only|"
    r"appendix for:|additional file \d+:\s*(table|figure|appendix|protocol|questionnaire|audio|video)|"
    r"moesm\d+ of rationale and design|moesm\d+ of protocol",
    re.I,
)
RAW_PARTICIPANT_DATA_RE = re.compile(
    r"raw data(?! set of the igg)|raw dataset|raw data set|participant[- ]level|patient[- ]level|"
    r"subject[- ]level|individual[- ]level|anonymi[sz]ed participant|de-?identified (participant|patient|subject)|"
    r"itt analysis set|analysis set|clinical study data|trial data|data sets? from the phase|data from the phase",
    re.I,
)
SUPPLEMENT_RE = re.compile(r"additional file|moesm|supplement|appendix|figshare\.c\.", re.I)
TABULAR_RE = re.compile(r"csv|excel|spreadsheet|stata|spss|tab-separated|text/tab|sav|dta|xlsx|xls|tsv|\.tab\b|application/zip|text/plain", re.I)


def now_iso():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def write_csv(path, rows, fields=None):
    path.parent.mkdir(parents=True, exist_ok=True)
    rows = list(rows)
    if fields is None:
        fields = list(rows[0].keys()) if rows else []
    with open(path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def joined_text(row):
    fields = [
        "title",
        "publisher",
        "repository_client",
        "doi",
        "url",
        "formats",
        "rights_license_short",
        "related_publications_short",
        "description_short",
        "predownload_reasons",
    ]
    return " ".join(str(row.get(field, "") or "") for field in fields)


def evaluate(row):
    text = joined_text(row)
    title = str(row.get("title", "") or "")
    formats = str(row.get("formats", "") or "")
    license_text = str(row.get("rights_license_short", "") or "")
    pre_status = str(row.get("predownload_status", "") or "")

    flags = []
    positives = []

    open_ok = bool(OPEN_RE.search(license_text)) and not bool(RESTRICTED_RE.search(text))
    publication_ok = bool(PUB_RE.search(text))
    random_ok = bool(RANDOM_RE.search(text)) and not bool(CLUSTER_RE.search(text))
    health_ok = bool(HEALTH_RE.search(text))
    participant_hint = bool(PARTICIPANT_RE.search(text))
    treatment_hint = bool(TREATMENT_RE.search(text))
    outcome_hint = bool(OUTCOME_RE.search(text))
    tabular_hint = bool(TABULAR_RE.search(formats + " " + text))
    raw_participant_hint = bool(RAW_PARTICIPANT_DATA_RE.search(text))
    supplement_hint = bool(SUPPLEMENT_RE.search(text))

    if open_ok:
        positives.append("open reuse signal")
    if publication_ok:
        positives.append("publication link/DOI signal")
    if random_ok:
        positives.append("randomized-trial signal")
    if health_ok:
        positives.append("human clinical/health signal")
    if tabular_hint:
        positives.append("tabular/file signal")
    if raw_participant_hint:
        positives.append("raw or participant-level data wording")
    if participant_hint:
        positives.append("participant/patient/subject wording")
    if treatment_hint:
        positives.append("treatment/group wording")
    if outcome_hint:
        positives.append("outcome/endpoint wording")

    if not open_ok:
        flags.append("open license/reuse not clean")
    if not publication_ok:
        flags.append("associated publication not confirmed")
    if not random_ok:
        flags.append("individual randomization not confirmed")
    if not health_ok:
        flags.append("human clinical/health trial not confirmed")
    if ANIMAL_RE.search(text):
        flags.append("animal/veterinary signal")
    if OBS_RE.search(text):
        flags.append("observational/non-randomized/secondary-analysis signal")
    if CLUSTER_RE.search(text):
        flags.append("cluster/stepped-wedge signal")
    if NON_CLINICAL_RE.search(text):
        flags.append("non-clinical/social-policy signal")
    if PROTOCOL_MATERIAL_RE.search(text):
        flags.append("protocol/material/instrument-only signal")
    if AGGREGATE_RE.search(text):
        flags.append("aggregate/table/omics supplementary signal")
    if NOT_DATA_ASSET_RE.search(text):
        flags.append("non-data asset/erratum/slides/audio signal")

    strong_negative = any(
        marker in flags
        for marker in [
            "animal/veterinary signal",
            "observational/non-randomized/secondary-analysis signal",
            "cluster/stepped-wedge signal",
            "non-clinical/social-policy signal",
            "protocol/material/instrument-only signal",
            "aggregate/table/omics supplementary signal",
            "non-data asset/erratum/slides/audio signal",
            "open license/reuse not clean",
        ]
    )

    missing_core = [f for f in flags if f in {
        "associated publication not confirmed",
        "individual randomization not confirmed",
        "human clinical/health trial not confirmed",
    }]

    if strong_negative:
        decision = "not_qualified_before_cleaning"
        queue = "not_qualified_before_cleaning_queue.csv"
        next_action = "Do not clean unless new source information resolves the disqualifying metadata signal."
    elif publication_ok and random_ok and health_ok and open_ok and raw_participant_hint and (treatment_hint or tabular_hint) and (outcome_hint or tabular_hint):
        decision = "qualified_for_source_verification"
        queue = "qualified_for_source_verification_queue.csv"
        next_action = "Run official source/file-manifest verification; then inspect downloaded tables before any cleaning."
    elif publication_ok and random_ok and health_ok and open_ok and tabular_hint and not missing_core:
        decision = "needs_manual_source_review"
        queue = "needs_manual_source_review_queue.csv"
        next_action = "Manually inspect official source files or manifest to determine whether participant-level treatment/outcome data exist."
    elif pre_status == "Defer - missing access/file certainty" and publication_ok and health_ok and open_ok:
        decision = "access_or_file_uncertain_defer"
        queue = "access_or_file_uncertain_queue.csv"
        next_action = "Keep deferred until a source-specific official download route or file manifest is identified."
    else:
        decision = "not_qualified_before_cleaning"
        queue = "not_qualified_before_cleaning_queue.csv"
        next_action = "Do not clean unless new source information confirms publication, individual randomization, open reuse, and participant-level data."

    reason_parts = []
    if flags:
        reason_parts.extend(flags)
    if positives:
        reason_parts.append("positive signals: " + "; ".join(positives))
    if supplement_hint and decision != "not_qualified_before_cleaning":
        reason_parts.append("publisher supplement requires file-level confirmation")
    if not reason_parts:
        reason_parts.append("metadata supports source verification")

    score = 0
    score += 3 if publication_ok else 0
    score += 3 if random_ok else 0
    score += 3 if health_ok else 0
    score += 3 if open_ok else 0
    score += 3 if raw_participant_hint else 0
    score += 2 if tabular_hint else 0
    score += 1 if participant_hint else 0
    score += 1 if treatment_hint else 0
    score += 1 if outcome_hint else 0
    score -= 5 * sum(1 for f in flags if f not in missing_core)
    score -= 2 * len(missing_core)

    return {
        "candidate_id": row.get("candidate_id", ""),
        "deferred_source_status": pre_status,
        "qualification_decision": decision,
        "review_queue": queue,
        "qualification_score": score,
        "qualification_reasons": "; ".join(dict.fromkeys(reason_parts)),
        "open_reuse_status": "pass" if open_ok else "fail_or_unclear",
        "publication_status": "pass" if publication_ok else "unclear",
        "randomization_status": "pass" if random_ok else "unclear_or_fail",
        "human_clinical_status": "pass" if health_ok else "unclear_or_fail",
        "raw_participant_data_signal": "yes" if raw_participant_hint else "no",
        "tabular_file_signal": "yes" if tabular_hint else "no",
        "participant_signal": "yes" if participant_hint else "no",
        "treatment_signal": "yes" if treatment_hint else "no",
        "outcome_signal": "yes" if outcome_hint else "no",
        "title": row.get("title", ""),
        "publisher": row.get("publisher", ""),
        "repository_client": row.get("repository_client", ""),
        "doi": row.get("doi", ""),
        "url": row.get("url", ""),
        "publication_year": row.get("publication_year", ""),
        "formats": row.get("formats", ""),
        "rights_license_short": row.get("rights_license_short", ""),
        "related_publications_short": row.get("related_publications_short", ""),
        "description_short": row.get("description_short", ""),
        "next_action": next_action,
    }


def update_flow_counts(summary_counts):
    if FLOW_COUNTS.exists():
        existing = pd.read_csv(FLOW_COUNTS)
    else:
        existing = pd.DataFrame()
    iteration_id = "deferred_likely_qualified_evaluation_2026_06_11"
    if not existing.empty and "iteration_id" in existing.columns:
        existing = existing[existing["iteration_id"] != iteration_id]

    rows = [
        {
            "iteration_id": iteration_id,
            "recorded_date": "2026-06-11",
            "stage_order": 5,
            "stage_id": "deferred_likely_qualified_evaluated",
            "parent_stage_id": "likely_qualified_metadata",
            "node_label": "Deferred likely-qualified candidates evaluated",
            "count": int(sum(summary_counts.values())),
            "node_kind": "screening",
            "criteria": "Metadata-only qualification evaluation of likely-qualified candidates previously deferred for missing access/file certainty or low clinical/data confidence.",
            "source_output": "rct_expansion/provenance/deferred_likely_qualified_evaluation_2026_06_11/deferred_candidate_qualification.csv",
            "notes": "No raw data were downloaded in this gate; candidates marked source-verification still require official manifest/download inspection.",
        }
    ]

    node_defs = [
        (
            "deferred_qualified_for_source_verification",
            "Qualified for source verification",
            "qualified_for_source_verification",
            "inclusion",
            "Publication, randomization, human clinical, open reuse, and raw/participant-level data wording were all present without disqualifying metadata signals.",
            "qualified_for_source_verification_queue.csv",
            "Run official source/file-manifest verification before cleaning.",
        ),
        (
            "deferred_needs_manual_source_review",
            "Needs manual source review",
            "needs_manual_source_review",
            "review",
            "Core publication/randomization/health/open signals present with tabular/file evidence, but metadata does not confirm participant-level treatment/outcome data.",
            "needs_manual_source_review_queue.csv",
            "Manual source-file inspection is required before any download or cleaning queue decision.",
        ),
        (
            "deferred_access_or_file_uncertain",
            "Access or file route still uncertain",
            "access_or_file_uncertain_defer",
            "review",
            "Clinical publication-backed candidate, but source/file-access metadata remains too sparse to qualify.",
            "access_or_file_uncertain_queue.csv",
            "Keep deferred until a lawful official file route is identified.",
        ),
        (
            "deferred_not_qualified_before_cleaning",
            "Not qualified before cleaning",
            "not_qualified_before_cleaning",
            "exclusion",
            "Metadata contains disqualifying or unresolved core eligibility signals such as non-data supplement, aggregate table, protocol/material, non-clinical, observational, unclear randomization, or unclear open reuse.",
            "not_qualified_before_cleaning_queue.csv",
            "Do not clean unless new source information resolves the stated issue.",
        ),
    ]
    for stage_id, label, decision, kind, criteria, output_name, notes in node_defs:
        rows.append(
            {
                "iteration_id": iteration_id,
                "recorded_date": "2026-06-11",
                "stage_order": 6,
                "stage_id": stage_id,
                "parent_stage_id": "deferred_likely_qualified_evaluated",
                "node_label": label,
                "count": int(summary_counts.get(decision, 0)),
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
    OUT.mkdir(parents=True, exist_ok=True)
    rows = pd.read_csv(PREDOWNLOAD, dtype=str).fillna("").to_dict(orient="records")
    deferred = [r for r in rows if r.get("predownload_status") in DEFERRED_STATUSES]
    evaluated = [evaluate(r) for r in deferred]
    evaluated.sort(key=lambda r: (r["qualification_decision"], -int(r["qualification_score"]), r["publisher"], r["title"]))

    fields = list(evaluated[0].keys()) if evaluated else []
    write_csv(OUT / "deferred_candidate_qualification.csv", evaluated, fields)

    for decision in sorted({r["qualification_decision"] for r in evaluated}):
        subset = [r for r in evaluated if r["qualification_decision"] == decision]
        queue = subset[0]["review_queue"] if subset else f"{decision}.csv"
        write_csv(OUT / queue, subset, fields)

    decision_counts = Counter(r["qualification_decision"] for r in evaluated)
    source_counts = Counter(r["deferred_source_status"] for r in evaluated)
    cross_counts = Counter((r["deferred_source_status"], r["qualification_decision"]) for r in evaluated)
    publisher_counts = {}
    for decision in decision_counts:
        publisher_counts[decision] = Counter(r["publisher"] or "Unknown" for r in evaluated if r["qualification_decision"] == decision).most_common(20)

    summary_rows = []
    for decision, count in decision_counts.most_common():
        summary_rows.append({"summary_type": "qualification_decision", "group": decision, "count": count})
    for status, count in source_counts.most_common():
        summary_rows.append({"summary_type": "deferred_source_status", "group": status, "count": count})
    for (status, decision), count in sorted(cross_counts.items()):
        summary_rows.append({"summary_type": "source_status_by_decision", "group": f"{status} | {decision}", "count": count})
    for decision, pubs in publisher_counts.items():
        for publisher, count in pubs:
            summary_rows.append({"summary_type": f"top_publishers | {decision}", "group": publisher, "count": count})
    write_csv(OUT / "deferred_candidate_qualification_summary.csv", summary_rows, ["summary_type", "group", "count"])

    summary = {
        "generated_at_utc": now_iso(),
        "input_path": str(PREDOWNLOAD.relative_to(ROOT)),
        "candidate_count": len(evaluated),
        "deferred_source_status_counts": dict(source_counts),
        "qualification_decision_counts": dict(decision_counts),
        "notes": "Metadata-only qualification evaluation; no files were downloaded. Source-verification candidates still need official manifest/download inspection before cleaning.",
    }
    (OUT / "summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    update_flow_counts(decision_counts)
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
