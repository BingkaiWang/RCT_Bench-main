# AGENTS.md

## Project Purpose

This repository benchmarks covariate-adjustment methods for randomized controlled trials using cleaned, participant-level trial datasets. The existing non-clustered analysis set contains 50 individually randomized RCTs in `cleaned_data/Non_Clustered_RCT/`, with trial-level metadata in `cleaned_data/meta_data.xlsx`. Cleaning logic for the original datasets is in `RCT_data_cleaning.Rmd`; downstream analysis is in `RCT_analysis.Rmd`.

## Existing Data Contract

Each cleaned non-clustered trial is saved as both `.csv` and `.rds`:

- `cleaned_data/Non_Clustered_RCT/trialN.csv`
- `cleaned_data/Non_Clustered_RCT/trialN.rds`

Required cleaned columns:

- `Treatment`: treatment assignment, usually an R factor. Put the control/reference arm first when it is identifiable.
- `YP_*`: primary outcome variables. At least one primary outcome is required.
- `YS_*`: secondary outcomes, when useful and available.
- `X_*`: baseline covariates measured before treatment assignment or intervention.

Common conventions:

- Delta outcomes are named like `YP_delta_measure_time` or `YS_delta_measure_time`.
- Baseline covariates are named like `X_measure_0d`, `X_measure_0w`, or `X_measure_0m`.
- Preserve participant-level rows. Do not aggregate to arm-level summaries.
- Keep analysis-ready variables in a compact table; raw source variables can stay in raw data folders or cleaning code.

## Metadata Contract

The current `cleaned_data/meta_data.xlsx` has one sheet with 19 columns:

1. `Trial_ID`
2. `Trial Number/Name`
3. `Paper Name`
4. `Journal`
5. `Paper Link`
6. `Publication Year`
7. `# of Arm`
8. `Control Group`
9. `Study Phase`
10. `Sample Size`
11. `Priamry Outcome`
12. `Primary Outcome Type`
13. `Trial Success(Primary Outcome Significant)`
14. `Statistical Model`
15. `Randomization Scheme`
16. `Randomization Scheme(High Level)`
17. `Research Area`
18. `Text Data`
19. `Citation`

Keep the misspelling `Priamry Outcome` for compatibility. For expansion work, place extra provenance fields such as repository, dataset DOI, license, download date, source files, and cleaning notes in a separate metadata/provenance sheet rather than changing this main schema.

## Expansion Folder

New RCTs should be kept separate from the existing 50 unless explicitly asked otherwise. Use:

- `rct_expansion/raw_data/trial51` through `trial121`
- `rct_expansion/cleaned_data/trial51.csv/.rds` through `trial121.csv/.rds`
- `rct_expansion/publications/trialN/` for downloaded open-access publications or publication-link records
- `rct_expansion/metadata/meta_data_active.xlsx`
- `rct_expansion/metadata/meta_data_backup.xlsx`
- `rct_expansion/metadata/meta_data_expansion.xlsx` as an active-only compatibility copy
- `rct_expansion/metadata/data_dictionary.csv`
- `rct_expansion/readme.md`
- `rct_expansion/RCT_data_cleaning_expansion.Rmd`
- `rct_expansion/scripts/cleanup_expansion_folder.py`
- `rct_expansion/provenance/download_log.csv`
- `rct_expansion/provenance/skipped_candidates.csv`
- `rct_expansion/RCT_outcome_reproducibility_expansion.Rmd`
- `rct_expansion/provenance/outcome_reproducibility_targets.csv`
- `rct_expansion/provenance/outcome_reproducibility_audit.csv`
- `rct_expansion/provenance/summary_statistics_audit_active.csv`
- `rct_expansion/provenance/summary_statistics_audit_summary_active.csv`
- `rct_expansion/provenance/backup_trials.csv`
- `rct_expansion/backup/Bxx/` for archived trials with raw data, cleaned data, publications when available, and `backup_reason.md`

The current expansion workflow keeps only publication-backed, reproducibility-audited or summary-audited trials active. The active expansion set is trials 51 through 121. Backup trials B01 through B13 are archived under `rct_expansion/backup/` and should remain excluded from active raw data, cleaned data, active metadata, publication links, download logs, data dictionaries, validation summaries, and audit summaries unless their backup reasons are resolved.

The 2026-06-11 folder cleanup normalized the active expansion folder after several batches. `meta_data_active.xlsx` and `meta_data_expansion.xlsx` are currently identical compatibility copies. Both contain sheets `Sheet1`, `Provenance`, `Validation`, `Audit_Summary`, `Audit_Detail`, `Duplicate_Screen`, and `Cleanup_Issues`. `Audit_Summary` has one row per active trial; `Audit_Detail` contains the per-outcome/per-arm summary-statistics audit rows. The same audit information is exported to `provenance/summary_statistics_audit_summary_active.csv` and `provenance/summary_statistics_audit_active.csv`.

During cleanup, a later batch that had temporarily overwritten `raw_data/trial100` through `trial105` was resolved. Current active `trial100` through `trial105` are the restored RCTC-00170 through RCTC-00888 trials. The later manual-review batch is active as `trial116` through `trial121`. The overwritten raw files from the later batch were preserved under `rct_expansion/provenance/folder_cleanup_2026_06_11/conflicting_raw_snapshot/`.

Temporary batch IDs are allowed during cleaning and audit, but they are not final active IDs. After the primary-publication reproducibility audit, move all failed, non-auditable, no-publication, or reclean-needed candidates into the next available `backup/Bxx/` folders. Then renumber the passing candidates contiguously after the current active maximum trial number, and write an explicit original-to-final mapping table in provenance. For the 2026-06-09 trial81-trial94 batch, original temporary trials 85, 86, 89, 91, 92, and 93 became active trials 81 through 86; original temporary trials 81, 82, 83, 84, 87, 88, 90, and 94 became backups B06 through B13.

## Expansion Workflow

For each candidate trial:

1. Check the repository record and related publication to confirm individual randomization, participant-level data, treatment assignment, outcomes, and acceptable reuse terms.
2. Search PubMed by study name/title and follow PubMed Central, DOI, journal, or repository links for the associated paper. Download the full publication PDF into `rct_expansion/publications/trialN/` when it is publicly available online without login, payment, CAPTCHA, embargo, or data-use restrictions; otherwise record the publication link and availability status. Manually downloaded PDFs should be logged in `pubmed_publication_downloads.csv`.
3. Read the primary publication before finalizing cleaned variables. Use the publication to identify treatment arms, control/reference arm, primary outcome, secondary outcomes, baseline table variables, statistical model, randomization scheme, sample size, journal, year, DOI/link, and citation.
4. Clean raw data in `RCT_data_cleaning_expansion.Rmd` and write one participant-level `.csv` and `.rds` per active trial.
5. Regenerate `meta_data_active.xlsx`, `meta_data_backup.xlsx`, `meta_data_expansion.xlsx`, `data_dictionary.csv`, `publication_links.csv`, `download_log.csv`, `validation_summary.csv`, and summary-statistics audit CSVs from the workflow scripts rather than editing generated outputs by hand.
6. If no associated main publication can be identified, remove the trial from active cleaned data and archive any downloaded raw/cleaned files under the next available `backup/Bxx/` folder.
7. Run `RCT_outcome_reproducibility_expansion.Rmd` after cleaning when exact publication-value auditing is available. Active trials should have strict publication audit rows when possible; otherwise include descriptive summary-statistics audit rows marked clearly as pending publication comparison or no-main-publication.
8. Run `python3 rct_expansion/scripts/cleanup_expansion_folder.py` after batch changes to consolidate active metadata, validation, publication links, duplicate screens, and audit sheets.
9. Run `Rscript rct_expansion/scripts/check_expansion_format.R` and `Rscript rct_expansion/scripts/check_analysis_preflight.R` before treating trials 51-121 as analysis-ready.

Run order for the active expansion:

1. Update raw/publication files and cleaning logic.
2. Run `RCT_data_cleaning_expansion.Rmd` from a clean R session to regenerate active cleaned `.csv`/`.rds`, metadata, data dictionary, publication links, download log, and validation summary.
3. Run `RCT_outcome_reproducibility_expansion.Rmd` from a clean R session to regenerate reproducibility targets, audit rows, and backup decisions.
4. Move any primary-outcome failures or non-auditable trials to `rct_expansion/backup/Bxx/`.
5. Renumber the passing trials contiguously after the current active maximum trial number, then rerun both Rmd files.
6. Run `rct_expansion/scripts/cleanup_expansion_folder.py` to normalize active metadata and embed audit information in `Audit_Summary` and `Audit_Detail`.
7. Run `Rscript rct_expansion/scripts/check_expansion_format.R` and `Rscript rct_expansion/scripts/check_analysis_preflight.R`.
8. Confirm active outputs and all active provenance files exclude backup trials, while backup metadata/provenance and the renumbering map preserve the original temporary IDs.

## Outcome Reproducibility Audit

The reproducibility audit extracts exact numeric outcome summaries from the primary publication, computes matching summaries from cleaned data, and writes:

- `provenance/outcome_reproducibility_targets.csv`
- `provenance/outcome_reproducibility_audit.csv`
- `provenance/backup_trials.csv`
- `provenance/summary_statistics_audit_active.csv`
- `provenance/summary_statistics_audit_summary_active.csv`

Use this audit schema: `Trial_ID`, `outcome_variable`, `outcome_role`, `arm`, `statistic`, `paper_value`, `paper_precision`, `cleaned_value`, `absolute_diff`, `tolerance`, `status`, `paper_source`, `notes`.

Compare exact means, SDs, medians/IQRs, counts, event totals, and rates when the paper reports them. The audit uses a 5% relative tolerance: `tolerance = abs(paper_value) * 0.05`. If a mismatch is clearly due to curation logic, correct `RCT_data_cleaning_expansion.Rmd`, regenerate cleaned outputs, and rerun the audit. If the corrected public source data still cannot reproduce the publication primary outcome within tolerance, or if the paper/source lacks enough information to audit the primary outcome, move the trial to backup.

The consolidated active audit uses two metadata workbook sheets:

- `Audit_Summary`: one row per active trial with row counts, audit sources, status counts, paper-value coverage, and `audit_coverage_status`.
- `Audit_Detail`: one row per audit statistic. It extends the audit schema with `audit_source`, `audit_type`, `candidate_id`, and `Original_Trial_ID`.

For active trials without existing publication-value audit rows, generate descriptive summary-statistics audit rows from the cleaned data. These rows should include treatment-arm `n` and primary-outcome descriptive summaries by arm. Use statuses such as `descriptive_recovered_pending_publication_comparison` or `descriptive_recovered_no_main_publication` so they are not mistaken for strict paper-value reproducibility passes. As of the 2026-06-11 cleanup, `trial96` and `trial116` through `trial121` have generated descriptive audit rows rather than exact paper-value comparison rows.

When the user explicitly asks for a workload-reduction or relaxed summary-statistics screen, do not require exact reproduction of adjusted or model-based publication effects such as SEM estimates, adjusted odds ratios, GEE targets, negative-binomial effects, or covariate-adjusted treatment contrasts. For that relaxed screen, determine whether publication-aligned participant-level outcomes can be constructed and whether descriptive summaries such as `n`, means, SDs/variances, medians/IQRs, counts, event totals, and rates can be recovered from the cleaned data, primary publication, repository workbook, or official analysis syntax. Record these results separately from the strict audit using statuses such as `pass_relaxed_summary`, `partial_summary_recovered`, `recoverable_needs_reclean`, `filter_reconciliation_needed`, or `not_recoverable_no_main_publication`. A relaxed screen can prioritize candidates for recleaning or restoration, but do not move a backup trial into the active set until the cleaned variables are updated, the relaxed audit provenance is written, and the active metadata/provenance are regenerated.

Each backup trial should have:

- `backup/Bxx/raw_data/`
- `backup/Bxx/cleaned_data/`
- `backup/Bxx/publications/`
- `backup/Bxx/backup_reason.md`

Current backup reasons:

- B01: insufficient publication/source information; no exact post/change K-MPAI summary for the cleaned primary outcome.
- B02: source data mismatch; corrected numeric malaria event coding still does not reproduce published incidence rates within the 5% audit tolerance.
- B03: insufficient publication/source information; public raw files do not contain the published sputum bacterial-load primary outcome.
- B04: source data mismatch under exact comparison; archived in the backup set, though its audited rows are within the updated 5% tolerance.
- B05: no associated main publication identified.
- B06: original temporary trial81; strict publication primary target is model-based, but the 2026-06-11 relaxed summary-statistics recheck recleaned MQOL-E/QOLLTI-F summary outcomes and recovered descriptive endpoint/change summaries.
- B07: original temporary trial82; publication analysis filter is not fully reconstructed in the compact cleaned data.
- B08: original temporary trial83; publication primary target is an adjusted longitudinal model target not reproduced by the compact audit.
- B09: original temporary trial84; publication primary target is longitudinal adherence analyzed by negative binomial models, not the compact final adherence summary.
- B10: original temporary trial87; publication adjusted primary target is not reproduced by simple cleaned means.
- B11: original temporary trial88; no associated main results publication was identified.
- B12: original temporary trial90; cleaned primary outcomes do not match the publication primary feasibility/usability outcomes, but the 2026-06-11 relaxed recheck found the primary feasibility workbook recoverable and needing recleaning.
- B13: original temporary trial94; exact mTSST cortisol AUC-I sample/model target is only partially reproduced and fails the Monitor + Accept target.

## Outcome And Covariate Rules

Primary outcomes must match the primary publication whenever the raw data allow it. If the publication primary outcome is unavailable in the public raw files, keep the best available outcome only when the trial remains useful, and document the mismatch in `Issues Encountered` and provenance notes.

Baseline measurements of primary and secondary outcomes should be included as `X_*` variables when present in the raw data. If no baseline analogue exists, or the baseline measurement is unavailable, record that in the provenance sheet. For the expansion workbook, use `Baseline_Outcome_Measurements_Included` to document this trial by trial.

Baseline covariates should follow this rule: construct the candidate pool using variables prespecified in the primary statistical analysis when available, and variables reported in the baseline characteristics table of the primary publication. Do not keep extra raw variables merely because they are available. In the expansion workbook, record selected covariates in `Baseline_Covariates_Selected` and their source in `Covariate_Source`.

Remove duplicate variables and variables directly computed from other variables already included, unless the publication specifically reports the derived variable and not the components. Prefer the publication-supported representation. For example, use a combined prior-event variable when the paper reports a combined baseline count, and avoid keeping both raw anthropometric values and derived anthropometric z-scores when the paper/model uses the z-scores.

## Candidate Eligibility

Before adding a dataset:

- Verify it is a real randomized clinical trial with individual-level randomization.
- Exclude cluster-randomized, observational, simulated, review, meta-analysis, or aggregate-only datasets.
- Confirm the data include individual-level treatment assignment and at least one outcome.
- Confirm it is not one of the existing 50 trials by checking title, DOI, trial registration, and repository record.
- Confirm reuse terms are open enough for research reuse. Do not use datasets with strong access or reuse restrictions.
- Confirm the main publication or preprint is linked. Download publicly available papers when practical and permitted; otherwise record the link and availability status.

## Ethical Download Rules

- Use official repository APIs, PubMed Central links, publisher open-access links, DOI landing pages, or download links when available.
- Do not bypass rate limits, CAPTCHA, login barriers, paywalls, embargoes, data-use agreements, or access controls.
- If a repository asks for downloader identity, use: Bingkai Wang, University of Michigan, bingkai@umich.edu.
- If a repository website or API is down, temporarily skip that candidate, record it in `rct_expansion/provenance/skipped_candidates.csv`, and move to a backup candidate.
- Record title, repository, DOI/URL, attempted timestamp, reason, observed status/error, and next action for all skipped candidates.

## Validation Expectations

For each cleaned expansion trial:

- `Treatment` exists and has at least two non-missing arms.
- At least one `YP_*` column exists.
- Rows are participant-level.
- Cleaned sample size is compared against repository/publication metadata.
- `.csv` and `.rds` outputs load successfully in R.
- Metadata and provenance identify source repository, dataset DOI, license, publication link, download date, source files, and cleaning notes.
- `metadata/data_dictionary.csv` is regenerated from the cleaned files and includes one row per active cleaned variable with `Trial_ID`, `variable_name`, `variable_type`, and `brief_explanation`.
- `metadata/meta_data_active.xlsx` and `metadata/meta_data_expansion.xlsx` include `Audit_Summary` and `Audit_Detail` sheets, and the same information is exported to `provenance/summary_statistics_audit_summary_active.csv` and `provenance/summary_statistics_audit_active.csv`.
- Every active trial has either strict publication-value audit rows or descriptive summary-statistics audit rows clearly marked with the appropriate status.
- The active expansion excludes trials without an identified associated publication.
- All `X_*` covariates are supported by the primary publication baseline table or prespecified analysis, except explicitly documented unavoidable limitations.
- Baseline measurements of `YP_*` and `YS_*` outcomes are included when raw data contain them.
- No duplicate column names or exact duplicate columns are present.
- Format and analysis-preflight outputs are regenerated in `provenance/format_check_*.csv`, `provenance/format_check_summary.md`, `provenance/analysis_preflight_expansion_trials51_121.csv`, and `provenance/analysis_preflight_summary.md`.
- Format and analysis-preflight outputs are regenerated in `provenance/format_check_*.csv`, `provenance/format_check_summary.md`, `provenance/analysis_preflight_expansion_trials51_121.csv`, and `provenance/analysis_preflight_summary.md`.
- Format and analysis-preflight outputs are regenerated in `provenance/format_check_*.csv`, `provenance/format_check_summary.md`, `provenance/analysis_preflight_expansion_trials51_121.csv`, and `provenance/analysis_preflight_summary.md`.
