# Relaxed Summary-Statistics Recheck For Backup B06-B14

Date: 2026-06-11

Purpose: Recheck backup trials B06-B14 under the relaxed rule that exact adjusted or model-based treatment-effect reproduction is not required when publication-aligned individual-level outcomes and descriptive summaries can be recovered.

Files:

- `backup_relaxed_summary_recoverability_B06_B14.csv`: one decision row per backup ID.
- `backup_relaxed_summary_statistics_B06_B13.csv`: computed descriptive summaries for current cleaned backup outcomes, plus B12 primary-outcome workbook summaries.
- `backup_relaxed_summary_recoverability_B06_B14.xlsx`: workbook copy of both tables.

Key decisions:

- B06: pass under relaxed summary screen after reclean. MQOL-E and QOLLTI-F summary-score outcomes were rebuilt in `backup/B06/cleaned_data/B06.csv` and `.rds`; exact SEM effects remain out of scope.
- B07: partial. Days-achieved-goal summaries are computable, but the paper's restricted effectiveness and goal-tailoring subset still needs exact reconstruction from the SPSS syntax.
- B08: computable. Binary genital viral-load event summaries are available at 6 and 24 months; the publication primary target is adjusted odds ratios.
- B09: partial. Final PrEP adherence summaries are computable, but the publication primary target is longitudinal electronic-monitor adherence and no simple publication summary target was matched in this pass.
- B10: partial. Simple weight-change summaries are computable, with one arm close to the adjusted paper value and one arm mismatching it.
- B11: not recoverable without a main publication.
- B12: recoverable after reclean. The public primary-outcome workbook contains recruitment, adherence, compliance, attrition, SUS, EEQ-G, and BREQ variables; current cleaned file still uses secondary Qmci outcomes.
- B13: partial. Subjective stress summaries and two of three cortisol AUC-I arms are recovered closely, but MonitorAccept cortisol AUC-I remains mismatched.
- B14: not present in the current workspace.

Recommended priority for possible restoration under the relaxed rule:

1. B06, if the relaxed summary rule is accepted for active-set inclusion.
2. B12, after recleaning around the primary feasibility/usability workbook.
3. B08, if unadjusted event summaries are sufficient despite the adjusted publication target.
4. B07, B09, B10, and B13 only after the noted filter, longitudinal-summary, or sample-rule issues are resolved.
5. B11 remains excluded unless a main results publication is identified.
