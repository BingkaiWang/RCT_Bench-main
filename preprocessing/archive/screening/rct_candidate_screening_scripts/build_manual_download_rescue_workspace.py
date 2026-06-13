import csv
import html
import json
import re
import shutil
from datetime import datetime, timezone
from pathlib import Path

import pandas as pd


ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "rct_expansion/provenance/landing_page_recheck_2026_06_11"
OUT = ROOT / "rct_expansion/provenance/manual_download_rescue_2026_06_11"
SHORTLIST = ROOT / "outputs/rct_candidate_screening/predownload_screen/landing_page_first_shortlist.csv"

PROBLEM_QUEUES = {
    "not_qualified_before_cleaning",
    "access_failed_official_route",
    "access_retry_rate_limited",
}


def now_iso():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def clean_join(values, limit=32000):
    values = [str(v) for v in values if pd.notna(v) and str(v)]
    text = " | ".join(values)
    return text[:limit]


def safe_dir(value):
    value = re.sub(r"[^A-Za-z0-9._-]+", "_", str(value or "")).strip("_")
    return value or "candidate"


def manual_action(row):
    queue = row["final_queue"]
    repo = row["repository"]
    downloaded = int(row.get("downloaded_file_count") or 0)
    registered = int(row.get("registered_file_count") or 0)
    if repo == "Digital Commons Data@Becker":
        return "Open the landing page and use the official Request access button; files are not publicly available by anonymous automation."
    if repo == "Dryad" and queue == "access_failed_official_route":
        return "Open the Dryad landing page in a browser and use the visible Download Dataset or file buttons; automation hit 401/403 but manual browser download may work."
    if repo == "Dryad" and queue == "access_retry_rate_limited":
        if registered:
            return "Open the Dryad landing page in a browser and download the listed files; automation hit rate limits or 401/429 on official endpoints."
        return "Open the Dryad landing page in a browser and inspect the file list; automation was rate-limited before a reliable file manifest was captured."
    if queue == "not_qualified_before_cleaning" and downloaded:
        return "Files are already downloaded in quarantine; manually review whether treatment assignment is encoded in sheet names, file names, or documentation."
    if queue == "not_qualified_before_cleaning":
        return "Open the landing page and verify whether any participant-level data file exists; current official metadata exposed no usable data file."
    return "Open the landing page, download any participant-level raw data files, and place them in the candidate drop folder."


def priority(row):
    if row["repository"] == "Dryad" and row["final_queue"] in {"access_failed_official_route", "access_retry_rate_limited"}:
        return "high_manual_browser"
    if row["repository"] == "Digital Commons Data@Becker":
        return "request_access"
    if row["final_queue"] == "not_qualified_before_cleaning" and int(row.get("downloaded_file_count") or 0) > 0:
        return "manual_content_review"
    return "landing_page_check"


def build_targets():
    cur = pd.read_csv(SOURCE / "verification_results_curated.csv")
    shortlist = pd.read_csv(SHORTLIST)
    files = pd.read_csv(SOURCE / "file_manifest.csv")

    merged = cur[cur["final_queue"].isin(PROBLEM_QUEUES)].copy()
    merged = merged.merge(
        shortlist[["candidate_id", "url", "rights_license_short", "related_publications_short", "description_short"]],
        on="candidate_id",
        how="left",
    )
    file_groups = files.groupby("candidate_id").agg(
        expected_file_names=("file_name", clean_join),
        official_download_urls=("download_url", clean_join),
        official_file_statuses=("download_status", clean_join),
    )
    merged = merged.merge(file_groups, on="candidate_id", how="left")
    for col in ["expected_file_names", "official_download_urls", "official_file_statuses"]:
        merged[col] = merged[col].fillna("")

    rows = []
    for _, row in merged.iterrows():
        cid = row["candidate_id"]
        drop_dir = OUT / "manual_downloads" / safe_dir(cid)
        drop_dir.mkdir(parents=True, exist_ok=True)
        rows.append(
            {
                "candidate_id": cid,
                "repository": row["repository"],
                "doi": row["doi"],
                "title": row["title"],
                "final_queue": row["final_queue"],
                "manual_priority": priority(row),
                "landing_url": row.get("url", ""),
                "doi_url": f"https://doi.org/{row['doi']}" if pd.notna(row["doi"]) and row["doi"] else "",
                "local_drop_dir": str(drop_dir.relative_to(ROOT)),
                "downloaded_file_count": row.get("downloaded_file_count", 0),
                "registered_file_count": row.get("registered_file_count", 0),
                "readable_table_count": row.get("readable_table_count", 0),
                "license_status": row.get("license_status", ""),
                "publication_status": row.get("publication_status", ""),
                "randomization_status": row.get("randomization_status", ""),
                "crossover_status": row.get("crossover_status", ""),
                "current_reasons": row.get("reasons", ""),
                "expected_file_names": row.get("expected_file_names", ""),
                "official_download_urls": row.get("official_download_urls", ""),
                "official_file_statuses": row.get("official_file_statuses", ""),
                "manual_action": manual_action(row),
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


def write_attempt_log(rows):
    attempt_rows = [
        {
            "scope": "Dryad access-failed and rate-limited candidates",
            "representative_candidate_id": "RCTC-01363",
            "official_route_tested": "https://datadryad.org/stash/downloads/file_stream/1216086",
            "observed_status": "HTTP 403 from curl",
            "decision": "Do not bulk retry; use manual browser download from Dryad landing pages.",
        },
        {
            "scope": "Dryad API file links captured in file_manifest.csv",
            "representative_candidate_id": "multiple",
            "official_route_tested": "https://datadryad.org/api/v2/files/{file_id}/download",
            "observed_status": "HTTP 401 or HTTP 429 during June 11 recheck",
            "decision": "Manual browser download or later slower retry; do not bypass Dryad controls.",
        },
        {
            "scope": "Digital Commons Data@Becker / Mendeley STEP-HI",
            "representative_candidate_id": "RCTC-04981",
            "official_route_tested": "https://data.mendeley.com/datasets/grgwpgkpdg/3",
            "observed_status": "Landing page reachable; page states files are not publicly available and offers Request access.",
            "decision": "Use request-access workflow; no anonymous download route.",
        },
        {
            "scope": "Zenodo and Loughborough records with no data file registered",
            "representative_candidate_id": "multiple",
            "official_route_tested": "Repository API metadata and file manifests",
            "observed_status": "Several records expose zero files, PDF-only supplements, or restricted/no-license records.",
            "decision": "Manual landing-page check only; treat as not cleanable unless a participant-level data file is visible.",
        },
    ]
    write_csv(OUT / "alternate_official_route_attempts.csv", attempt_rows)


def write_readme(rows):
    text = f"""# Manual Download Rescue Workspace

Generated: {now_iso()}

This workspace covers the 70 candidates from the June 11 landing-page recheck that were either:

- `not_qualified_before_cleaning`
- `access_failed_official_route`
- `access_retry_rate_limited`

The goal is to use only official, non-bypass routes. Do not use paywall bypasses, CAPTCHA bypasses, login/session scraping, or tools that evade repository controls.

## Files

- `manual_download_targets.csv`: one row per candidate with landing page, DOI, expected file names, and the local drop folder.
- `manual_download_portal.html`: clickable browser portal for manual review/download.
- `alternate_official_route_attempts.csv`: short log of alternate route probes already tried.
- `manual_downloads/<candidate_id>/`: put manually downloaded files here.
- `ingest_manual_downloads.py`: scans the drop folders and reruns local file inspection/qualification.

## Manual Download Steps

1. Open `manual_download_portal.html` in a browser.
2. Work through high-priority rows first: `high_manual_browser`, then `landing_page_check`, then `manual_content_review`.
3. For each candidate, use the official landing page or DOI link only.
4. Save participant-level raw data files into the listed `manual_downloads/<candidate_id>/` folder.
5. If a candidate requires request access, keep it out of active cleaning until access is granted and terms permit reuse.
6. After downloading files, run:

```bash
/Users/bingkai/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 rct_expansion/provenance/manual_download_rescue_2026_06_11/ingest_manual_downloads.py --scan-downloads
```

The `--scan-downloads` option copies files from `~/Downloads` when their names match the expected file list in `manual_download_targets.csv`.

## Notes

- Dryad records are the main manual-browser priority. The official API exposed many file manifests but returned HTTP 401/429 for automated downloads. Browser downloads may still work, as seen with RCTC-01363.
- Some records already have downloaded files but remain in this workspace because the crude verifier did not find a treatment column. Those need manual content review, not more downloading.
"""
    (OUT / "manual_download_README.md").write_text(text, encoding="utf-8")


def write_html(rows):
    queue_counts = {}
    for row in rows:
        queue_counts[row["final_queue"]] = queue_counts.get(row["final_queue"], 0) + 1
    cards = "\n".join(
        f"<div class='card'><div class='num'>{count}</div><div>{html.escape(queue)}</div></div>"
        for queue, count in sorted(queue_counts.items())
    )
    trs = []
    for row in rows:
        landing = row["landing_url"]
        doi_url = row["doi_url"]
        file_names = html.escape(row["expected_file_names"] or "(none captured)")
        action = html.escape(row["manual_action"])
        title = html.escape(row["title"])
        trs.append(
            "<tr>"
            f"<td>{html.escape(row['manual_priority'])}</td>"
            f"<td>{html.escape(row['candidate_id'])}</td>"
            f"<td>{html.escape(row['repository'])}</td>"
            f"<td><a href='{html.escape(landing)}' target='_blank'>landing</a><br><a href='{html.escape(doi_url)}' target='_blank'>doi</a></td>"
            f"<td>{title}<br><span class='doi'>{html.escape(row['doi'])}</span></td>"
            f"<td>{html.escape(row['final_queue'])}</td>"
            f"<td class='small'>{file_names}</td>"
            f"<td class='small'>{html.escape(row['local_drop_dir'])}</td>"
            f"<td class='small'>{action}</td>"
            "</tr>"
        )
    body = "\n".join(trs)
    page = f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Manual Download Rescue - Landing Page Candidates</title>
<style>
body {{ font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; margin: 24px; color: #172033; }}
h1 {{ margin-bottom: 4px; }}
.sub {{ color: #526071; margin-top: 0; }}
.cards {{ display: flex; flex-wrap: wrap; gap: 10px; margin: 18px 0; }}
.card {{ border: 1px solid #d8dee8; border-radius: 6px; padding: 10px 14px; min-width: 190px; background: #f8fafc; }}
.num {{ font-size: 22px; font-weight: 700; }}
table {{ border-collapse: collapse; width: 100%; table-layout: fixed; }}
th, td {{ border: 1px solid #d9e2ec; padding: 8px; vertical-align: top; }}
th {{ position: sticky; top: 0; background: #1f4e79; color: white; z-index: 1; }}
td {{ font-size: 13px; }}
.small {{ font-size: 12px; line-height: 1.35; word-break: break-word; }}
.doi {{ color: #5d6b7a; font-size: 12px; }}
a {{ color: #0b5cad; }}
</style>
</head>
<body>
<h1>Manual Download Rescue</h1>
<p class="sub">Use official landing pages only. Save downloaded files into the listed local drop folder, then run the ingest script.</p>
<div class="cards">{cards}</div>
<table>
<thead>
<tr>
<th style="width: 110px;">Priority</th>
<th style="width: 90px;">Candidate</th>
<th style="width: 130px;">Repository</th>
<th style="width: 90px;">Links</th>
<th style="width: 270px;">Title / DOI</th>
<th style="width: 160px;">Queue</th>
<th>Expected Files</th>
<th style="width: 240px;">Drop Folder</th>
<th style="width: 280px;">Manual Action</th>
</tr>
</thead>
<tbody>
{body}
</tbody>
</table>
</body>
</html>
"""
    (OUT / "manual_download_portal.html").write_text(page, encoding="utf-8")


def copy_known_manual_files():
    source_dir = SOURCE / "manual_downloads/RCTC-01363"
    target_dir = OUT / "manual_downloads/RCTC-01363"
    if not source_dir.exists():
        return
    target_dir.mkdir(parents=True, exist_ok=True)
    for path in source_dir.iterdir():
        if path.is_file():
            dest = target_dir / path.name
            if not dest.exists():
                shutil.copy2(path, dest)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    rows = build_targets()
    write_csv(OUT / "manual_download_targets.csv", rows)
    write_attempt_log(rows)
    write_readme(rows)
    write_html(rows)
    copy_known_manual_files()
    summary = {
        "generated_at_utc": now_iso(),
        "source_recheck_dir": str(SOURCE.relative_to(ROOT)),
        "target_count": len(rows),
        "queue_counts": pd.Series([r["final_queue"] for r in rows]).value_counts().to_dict(),
        "priority_counts": pd.Series([r["manual_priority"] for r in rows]).value_counts().to_dict(),
    }
    (OUT / "manual_download_workspace_summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
