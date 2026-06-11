# RCT Expansion Folder Cleanup

Run date: 2026-06-11

- Active cleaned trials: 71 (51-121)
- Validation statuses: {'pass': 71}
- Duplicate-screen rows: 0
- Cleanup issue rows: 0
- Action rows: 20

Key notes:
- trial100-trial105 raw folders were archived before restoring the older RCTC-00170 through RCTC-00888 raw sources.
- The later manual-review batch remains active as trial116-trial121 in the current cleaned/raw files.
- Superseded batch metadata files were moved under metadata/archive_*_batch_outputs; unified active metadata is meta_data_active.xlsx and meta_data_expansion.xlsx.
- Summary-stat audit information is embedded in the metadata workbooks as Audit_Summary and Audit_Detail and exported to provenance/summary_statistics_audit_*.csv.
