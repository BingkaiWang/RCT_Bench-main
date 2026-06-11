import argparse
import csv
import importlib.util
import json
import shutil
from datetime import datetime, timezone
from pathlib import Path

import pandas as pd


WORKSPACE = Path(__file__).resolve().parent
ROOT = WORKSPACE.parents[2]
TARGETS = WORKSPACE / "manual_download_targets.csv"
SHORTLIST = ROOT / "outputs/rct_candidate_screening/predownload_screen/landing_page_first_shortlist.csv"
VERIFIER_SCRIPT = ROOT / "outputs/rct_candidate_screening/scripts/download_and_verify_download_first.py"


def now_iso():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def load_verifier():
    spec = importlib.util.spec_from_file_location("verifier", VERIFIER_SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.OUT = WORKSPACE
    module.DOWNLOADS = WORKSPACE / "manual_downloads"
    module.METADATA = WORKSPACE / "manual_metadata"
    module.EXTRACTED = WORKSPACE / "manual_extracted"
    module.ensure_dirs()
    return module


def split_expected_names(value):
    names = []
    for part in str(value or "").split("|"):
        part = part.strip()
        if part:
            names.append(part)
    return names


def copy_matching_downloads(target_rows, downloads_dir):
    copied = []
    downloads_dir = Path(downloads_dir).expanduser()
    if not downloads_dir.exists():
        return copied
    all_downloads = [p for p in downloads_dir.iterdir() if p.is_file()]
    by_name = {}
    for path in all_downloads:
        by_name.setdefault(path.name, []).append(path)
    for row in target_rows:
        expected = split_expected_names(row.get("expected_file_names", ""))
        if not expected:
            continue
        target_dir = ROOT / row["local_drop_dir"]
        target_dir.mkdir(parents=True, exist_ok=True)
        for name in expected:
            for src in by_name.get(name, []):
                dest = target_dir / src.name
                if dest.exists():
                    continue
                shutil.copy2(src, dest)
                copied.append({"candidate_id": row["candidate_id"], "source": str(src), "destination": str(dest.relative_to(ROOT))})
    return copied


def local_files_for(row):
    drop_dir = ROOT / row["local_drop_dir"]
    if not drop_dir.exists():
        return []
    return [p for p in sorted(drop_dir.iterdir()) if p.is_file() and not p.name.startswith(".")]


def build_manual_file_manifest(target_rows, verifier):
    rows = []
    for target in target_rows:
        for path in local_files_for(target):
            ext = path.suffix.lower()
            role = "data" if ext in verifier.DATA_EXTENSIONS else "support"
            rows.append(
                {
                    "candidate_id": target["candidate_id"],
                    "repository": target["repository"],
                    "source_record": target["doi"],
                    "file_name": path.name,
                    "download_url": "manual_download",
                    "content_type": "",
                    "declared_size": path.stat().st_size,
                    "restricted": "no",
                    "role": role,
                    "guestbook_id": "",
                    "local_path": str(path.relative_to(ROOT)),
                    "download_status": "downloaded",
                    "download_error": "",
                    "bytes_downloaded": path.stat().st_size,
                }
            )
    return rows


def write_csv(path, rows):
    rows = list(rows)
    path.parent.mkdir(parents=True, exist_ok=True)
    if not rows:
        path.write_text("", encoding="utf-8")
        return
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def main():
    parser = argparse.ArgumentParser(description="Ingest manually downloaded rescue files and rerun crude eligibility inspection.")
    parser.add_argument("--scan-downloads", action="store_true", help="Copy files from ~/Downloads when their names match expected file names.")
    parser.add_argument("--downloads-dir", default="~/Downloads")
    args = parser.parse_args()

    if not TARGETS.exists():
        raise SystemExit(f"Missing target manifest: {TARGETS}")
    target_rows = pd.read_csv(TARGETS).fillna("").to_dict("records")
    copied = copy_matching_downloads(target_rows, args.downloads_dir) if args.scan_downloads else []

    verifier = load_verifier()
    file_manifest = build_manual_file_manifest(target_rows, verifier)
    archive_rows = verifier.extract_archives(file_manifest)
    inspection = verifier.inspect_files(file_manifest, archive_rows)

    with SHORTLIST.open(newline="", encoding="utf-8") as f:
        shortlist_rows = {row["candidate_id"]: row for row in csv.DictReader(f)}
    verification = []
    for target in target_rows:
        row = shortlist_rows.get(target["candidate_id"], dict(target))
        verification.append(verifier.status_from_candidate(row, file_manifest, archive_rows, inspection))

    write_csv(WORKSPACE / "manual_ingest_copied_from_downloads.csv", copied)
    write_csv(WORKSPACE / "manual_ingest_file_manifest.csv", file_manifest)
    write_csv(WORKSPACE / "manual_ingest_archive_manifest.csv", archive_rows)
    write_csv(WORKSPACE / "manual_ingest_inspection_summary.csv", inspection)
    write_csv(WORKSPACE / "manual_ingest_verification_results.csv", verification)
    qualified = [row for row in verification if row["qualification_decision"] == "qualified_for_cleaning"]
    needs_review = [row for row in verification if row["qualification_decision"] == "needs_manual_review_before_cleaning"]
    write_csv(WORKSPACE / "manual_ingest_qualified_for_cleaning_queue.csv", qualified)
    write_csv(WORKSPACE / "manual_ingest_needs_review_queue.csv", needs_review)

    summary = {
        "generated_at_utc": now_iso(),
        "target_count": len(target_rows),
        "copied_from_downloads_count": len(copied),
        "manual_file_count": len(file_manifest),
        "readable_table_count": sum(1 for row in inspection if row.get("read_status") == "readable"),
        "decision_counts": pd.Series([row["qualification_decision"] for row in verification]).value_counts().to_dict(),
    }
    (WORKSPACE / "manual_ingest_summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
