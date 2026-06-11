# Broad RCT Dataset Screening Procedure

Recorded on 2026-06-09. The broad candidate workbook was generated from local/API work on 2026-06-08 and is stored at:

- `outputs/rct_candidate_screening/rct_dataset_candidates_screened.xlsx`
- `outputs/rct_candidate_screening/processed/candidate_records.csv`
- `outputs/rct_candidate_screening/processed/screening_rules.csv`
- `outputs/rct_candidate_screening/processed/source_pages.csv`
- `outputs/rct_candidate_screening/processed/summary.csv`

This procedure is intended to support a later tree or flow plot that starts from broad available dataset records and narrows to final analysis-ready participant-level RCT datasets.

## Scope

The broad screen is a metadata-level search over unrestricted/public repository APIs. It does not prove final eligibility. A record marked `Likely qualified` still requires repository-file inspection, main-publication review, cleaning, validation, and outcome reproducibility audit before it can become analysis-ready.

The phrase "all available datasets" should be interpreted operationally as all dataset records returned by the documented public API searches, not as a complete census of every possible web-hosted trial dataset.

## Current Broad Search Universe

The current broad search used:

- DataCite dataset records for:
  - `randomized controlled trial`
  - `randomised controlled trial`
  - `randomized trial`
  - `randomised trial`
- Harvard Dataverse native dataset search for:
  - `randomized controlled trial`
  - `randomised controlled trial`
  - `randomized trial`
  - `randomised trial`
  - `randomized control trial`

OSF generic search results were not treated as a countable universe because broad OSF search matches projects, files, protocols, and registrations at very large scale and is not limited to usable dataset entries. OSF records are still captured when indexed as DataCite dataset records.

## Current Broad-Screen Counts

Use `broad_dataset_screening_flow_counts.csv` for plotting. The current broad metadata screen produced:

- Raw API records: 20,743
- Deduplicated candidate dataset entries: 7,280
- Likely qualified by crude metadata screen: 1,223
- Needs manual review: 2,858
- Likely not qualified: 3,199

## Current Pre-download Screen Of Likely-qualified Records

The second screen narrows the `Likely qualified` metadata bucket before downloading any dataset files. Outputs are stored at:

- `outputs/rct_candidate_screening/likely_qualified_predownload_screen.xlsx`
- `outputs/rct_candidate_screening/predownload_screen/likely_qualified_predownload_screen.csv`
- `outputs/rct_candidate_screening/predownload_screen/download_first_shortlist.csv`
- `outputs/rct_candidate_screening/predownload_screen/landing_page_first_shortlist.csv`
- `outputs/rct_candidate_screening/predownload_screen/predownload_rules.csv`

The stricter pre-download screen produced:

- Input likely-qualified records: 1,223
- Download first: 20
- Landing page / file manifest first: 92
- Source-specific manual check: 71
- Defer - missing access/file certainty: 653
- Defer - low clinical or data confidence: 51
- Already active expansion - exclude: 2
- Already original benchmark - exclude: 12
- Exclude before download: 322

The `Download first` bucket requires a direct/open repository client, an explicit file/tabular signal, a publication DOI signal, a human clinical/health signal, no strict red flags, and no match to already curated expansion or original benchmark records.

The `Landing page / file manifest first` bucket should be checked without downloading data files. It is meant for records from direct repositories where the source looks promising but metadata does not expose enough file detail.

Strict red flags include restriction/custom/DUA or closed-access terms, animal/veterinary studies, observational/secondary analyses, protocol/materials-only records, cluster/stepped-wedge designs, aggregate/simulation records, meta-analysis/genome-only records, and non-clinical/social-policy or recruitment-study signals.

## Current Download-first Verification

The third screen downloaded or attempted to download official repository data files for the 20 records in `Download first`. Files were kept in a quarantine provenance folder rather than active trial folders:

- `rct_expansion/provenance/predownload_verification_2026_06_09/download_first_verification.xlsx`
- `rct_expansion/provenance/predownload_verification_2026_06_09/verification_results.csv`
- `rct_expansion/provenance/predownload_verification_2026_06_09/file_manifest.csv`
- `rct_expansion/provenance/predownload_verification_2026_06_09/inspection_summary.csv`
- `rct_expansion/provenance/predownload_verification_2026_06_09/archive_manifest.csv`
- `rct_expansion/provenance/predownload_verification_2026_06_09/metadata_manifest.csv`

The crude downloaded-file verification required open/no-DUA metadata, an associated publication signal, participant-level rows, treatment/group assignment, at least one outcome signal, and no obvious crossover-method flag. It produced:

- Download-first records attempted: 20
- Qualified for cleaning after downloaded-file verification: 14
- Method review before cleaning: 3
- Not qualified before cleaning: 3

The method-review records are randomized crossover studies. Do not clean them for the main benchmark unless the benchmark scope explicitly admits crossover trial data.

The not-qualified records at this stage are:

- `RCTC-01905`: Dryad metadata is public, but official file downloads returned HTTP 403 during automated ethical download attempts.
- `RCTC-02158`: Zenodo metadata indicates restricted access and exposes no public files.
- `RCTC-05031`: downloaded participant-level criteria/prediction data, but no treatment/group assignment was found.

Some otherwise qualified records have skipped oversized non-tabular archives, including heart-rate/EEG or neuroimaging archives. These skips are recorded in `file_manifest.csv`; the pre-cleaning decision was based on downloaded clinical/tabular files.

The current local benchmark contains:

- Original non-clustered analysis-ready trials: 50
- Active expansion analysis-ready trials: 36
- Total current active analysis-ready trials: 86
- Archived backup expansion trials: 13

The current 86 analysis-ready trials are not all descendants of the 2026-06-08 broad metadata workbook. They represent the current curated benchmark state and should be plotted as a separate curated-history branch unless future curation explicitly links broad-screen candidate IDs to final trial IDs.

## Trial 81-94 Preliminary Cleaning Batch

On 2026-06-09, the 14 `download_first_qualified_for_cleaning` candidates from the downloaded-file verification queue were first cleaned and audited with temporary IDs `trial81` through `trial94`. After primary-publication audit, passing candidates were renumbered as active `trial81` through `trial86`; failed, non-auditable, no-publication, or reclean-needed candidates were moved to `backup/B06` through `backup/B13`.

Generated files:

- Cleaning script: `rct_expansion/RCT_data_cleaning_trials81_94.R`
- Active raw source folders: `rct_expansion/raw_data/trial81` through `rct_expansion/raw_data/trial86`
- Active cleaned outputs: `rct_expansion/cleaned_data/trial81.csv/.rds` through `rct_expansion/cleaned_data/trial86.csv/.rds`
- Archived backup folders: `rct_expansion/backup/B06` through `rct_expansion/backup/B13`
- Renumbering map: `rct_expansion/provenance/trials81_94_renumbering_map.csv`
- Active metadata workbook: `rct_expansion/metadata/meta_data_trials81_86_active.xlsx`
- Active audited workbook: `rct_expansion/metadata/meta_data_trials81_86_audited.xlsx`
- Data dictionary supplement: `rct_expansion/metadata/data_dictionary_trials81_86.csv`
- Validation summary: `rct_expansion/provenance/validation_summary_trials81_86.csv`
- Download/cleaning log supplement: `rct_expansion/provenance/download_log_trials81_86.csv`

The original 14-row temporary sidecar outputs were retained only as archived pre-renumbering snapshots with `_pre_renumbering` filenames; current active sidecars use `trial81_86` filenames.

Tree-plot nodes appended to `broad_dataset_screening_flow_counts.csv`:

- `download_first_cleaned_trials81_94_preliminary`: 14 preliminary cleaned datasets.
- `download_first_cleaned_trials81_94_contract_pass`: 14 cleaned datasets passing structural validation.

The preliminary branch is now resolved: active files contain only the six passing trials, and the eight nonpassing candidates live only in backup folders and backup metadata.

## Trial 81-94 Primary-Publication Review And Audit

On 2026-06-09, the 14 structurally valid preliminary cleaned trials were reviewed against their associated primary publications or preprints and audited against extractable paper outcome targets.

Generated files:

- Audit script: `rct_expansion/RCT_outcome_reproducibility_trials81_94.R`
- Audited workbook: `rct_expansion/metadata/meta_data_trials81_86_audited.xlsx`
- Publication review table: `rct_expansion/provenance/publication_review_trials81_94.csv`
- Paper target table: `rct_expansion/provenance/outcome_reproducibility_targets_trials81_94.csv`
- Paper-vs-cleaned audit table: `rct_expansion/provenance/outcome_reproducibility_audit_trials81_94.csv`
- Trial-level decisions: `rct_expansion/provenance/audit_decisions_trials81_94.csv`

Audit procedure:

1. Identify the associated main results publication or preprint from the repository record, publication DOI, PubMed/PMC/publisher page, registry record, or downloaded paper.
2. Read the paper methods/results to identify the publication primary outcome, treatment arms, control arm, sample size, randomization, and statistical model.
3. Extract exact paper outcome targets when the paper reports auditable means, SDs, counts, rates, percentages, or table values.
4. Compare each target to the cleaned participant-level data using the standard audit schema and `tolerance = abs(paper_value) * 0.05`.
5. Mark model-only, longitudinal, restricted-filter, publication-missing, or cleaned-primary-mismatch targets explicitly rather than silently passing them.
6. Count a trial as analysis-ready only when at least one publication-supported primary outcome target is reproduced and no blocking publication/cleaning issue remains. Original temporary `trial91` is retained as active `trial84` with a note because MADRS reproduces, while one PHQ-9 row needs caution before treating PHQ-9 as co-primary.

Tree-plot nodes appended to `broad_dataset_screening_flow_counts.csv`:

- `trials81_94_primary_publication_reviewed`: 14 trials reviewed.
- `trials81_94_primary_publication_identified`: 13 trials with an associated main results publication or preprint.
- `trials81_94_no_primary_publication`: 1 excluded temporary trial, moved to `B11` (original `trial88`).
- `trials81_94_primary_audit_analysis_ready`: 6 temporary trials passing the publication audit gate, renumbered as active `trial81` through `trial86` (original temporary `trial85`, `trial86`, `trial89`, `trial91`, `trial92`, `trial93`).
- `trials81_94_primary_audit_not_analysis_ready`: 7 publication-linked temporary trials needing recleaning, model reproduction, or exclusion after audit, moved to `B06`, `B07`, `B08`, `B09`, `B10`, `B12`, and `B13` (original temporary `trial81`, `trial82`, `trial83`, `trial84`, `trial87`, `trial90`, `trial94`).
- `trials81_94_final_analysis_ready_after_audit`: 6 trials retained after this gate and renumbered as active `trial81` through `trial86`.
- `trials81_86_active_after_backup_renumbering`: 6 renumbered active datasets after archiving failed candidates.
- `trials81_86_active_contract_pass_after_renumbering`: 6 renumbered active datasets passing structural validation.

## Crude Metadata Screening Rules

Each deduplicated candidate receives transparent flags rather than being silently dropped.

Associated publication signal:

- Yes when DataCite related identifiers indicate article, document, citation, or supplement links.
- Yes when Harvard Dataverse records mention publications, related materials, manuscript/article data, replication data, or DOI-like publication references.

No-DUA/open signal:

- Yes when source/license text includes open terms such as Creative Commons, CC0, CC-BY, open access, public domain, or common open repositories.
- No when restriction terms are detected.

Restriction or DUA signal:

- Yes when metadata includes terms such as restricted access, access restricted, data use agreement, DUA, controlled access, request access, available upon request, login required, permission required, or embargo.

Individual-level signal:

- Yes when metadata suggests participant-level, individual-participant, patient-level, student-level, subject-level, respondent-level, raw data, clinical data, survey data, treatment/control/intervention group, random assignment, or similar trial-level row structure.

Data-file signal:

- Yes when file counts are reported or metadata references analyzable file formats such as CSV, Excel, SPSS, Stata, tabular files, or OpenXML spreadsheets.

Exclusion signals:

- Cluster randomization, community/school randomization, stepped-wedge designs, aggregate-only data, protocol-only records, statistical analysis plans, questionnaires/materials-only records, review/meta-analysis records, simulations, or animal-only studies.

Status assignment:

- `Likely qualified`: RCT signal plus associated publication signal, open/no-DUA signal, individual-level signal, and no detected restriction, cluster-randomization, or protocol/materials-only signal.
- `Needs manual review`: RCT-looking and publication-backed, but at least one required signal is weak or missing.
- `Likely not qualified`: detected restriction/DUA, cluster-randomization, protocol/materials-only signal, or weak overall RCT/data/publication evidence.

## Future Screening Workflow

1. Run the broad API searches and save raw API responses under a dated output or provenance folder.
2. Normalize all records into a flat table with title, DOI, repository/publisher, URL, year, creators, license/rights, formats, related publication fields, and description text.
3. Deduplicate by concept DOI, version DOI, identical DOI, or normalized title/repository key.
4. Apply the crude metadata flags above.
5. Append a new `iteration_id` block to `broad_dataset_screening_flow_counts.csv`.
6. Manually inspect the `Likely qualified` and high-priority `Needs manual review` records.
7. For candidate trials selected for expansion, record source files and publication links in the usual expansion provenance tables.
8. Clean participant-level files, validate the cleaned-data contract, and run the outcome reproducibility audit.
9. Move failures or non-auditable trials to backup.
10. Add final tree-plot rows connecting screened candidates to active trial IDs only after the candidate has passed cleaning, validation, and at least one primary-outcome reproducibility audit target.

## Tree Plot Convention

`broad_dataset_screening_flow_counts.csv` is a node table with parent links. Recommended plot interpretation:

- `stage_id` is the node identifier.
- `parent_stage_id` is the tree edge.
- `count` is the node size or label.
- `node_kind` distinguishes source, screening, inclusion, exclusion, review, and final-analysis nodes.
- `criteria` provides the short rule shown in captions or tooltips.
- `source_output` points back to the workbook, CSV, or provenance file that supports the count.

For a future all-the-way tree, use this high-level path:

`all API records -> deduplicated candidate entries -> crude metadata screen -> manually eligible trial candidates -> publication-backed downloadable datasets -> cleaned participant-level datasets -> validated datasets -> reproducibility-audited datasets -> active analysis-ready datasets`
