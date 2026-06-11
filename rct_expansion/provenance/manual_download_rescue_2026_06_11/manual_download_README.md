# Manual Download Rescue Workspace

Generated: 2026-06-11T14:54:48+00:00

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
