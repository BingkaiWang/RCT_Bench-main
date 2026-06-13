# AGENTS.md

## Project Purpose

This repository benchmarks covariate-adjustment methods for randomized
controlled trials using cleaned, participant-level trial datasets. The public
dataset currently contains 125 individually randomized RCTs in a flat
`cleaned_data/` layout, with public metadata in root-level `meta_data.xlsx` and
variable metadata in root-level `data-dictionary.xlsx`.

## Public Data Contract

Each cleaned trial is saved as both `.csv` and `.rds`:

- `cleaned_data/trialN.csv`
- `cleaned_data/trialN.rds`

Required cleaned columns:

- `Treatment`: randomized treatment assignment. Put the control/reference arm
  first when it is identifiable.
- `YP_*`: primary outcome variables. At least one primary outcome is required.
- `YS_*`: secondary outcomes, when useful and available.
- `X_*`: baseline covariates measured before treatment assignment or
  intervention.

Common conventions:

- Delta outcomes are named like `YP_delta_measure_time` or
  `YS_delta_measure_time`.
- Baseline covariates are named like `X_measure_0d`, `X_measure_0w`, or
  `X_measure_0m`.
- Preserve participant-level rows. Do not aggregate to arm-level summaries.
- Keep analysis-ready variables in a compact table; raw source variables belong
  in ignored local staging folders or cleaning code.

## Metadata Contract

The public `meta_data.xlsx` workbook has `Sheet1` with the 19-column metadata
schema:

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

Keep the misspelling `Priamry Outcome` for compatibility. Do not add extra
columns to `Sheet1`; put repository, dataset DOI, license, source files,
cleaning notes, validation, and audit details in separate provenance sheets or
CSV files.

For trials 51-125, metadata should describe the primary publication rather than
the dataset record:

- `Trial Number/Name`: official registry identifier only, such as
  ClinicalTrials.gov, ISRCTN, UMIN, CTRI, TCTR, ACTRN, DRKS, ChiCTR, PACTR, or
  EUCTR. Leave blank if no registry ID is discoverable.
- `Paper Name`: published paper title, not dataset title.
- `Paper Link`: paper DOI, PubMed/PMC, or publisher page, not Dryad, Zenodo,
  Dataverse, Mendeley, or other data DOI.
- `Publication Year`: publication year for the paper.
- `Study Phase`: phase 1-4 when applicable; otherwise `Not Applicable`.
- `Randomization Scheme`: specific method such as simple randomization, block
  randomization, stratified randomization, stratified block randomization,
  minimization, factorial randomization, or randomized crossover sequence.
  `Individual` is not a scheme.
- `Randomization Scheme(High Level)`: trial1-50-style category such as
  `Simple`, `Block`, `Stratified`, `Stratified Block`, `Factorial`,
  `Crossover`, or `Not reported`.
- `Citation`: numeric citation count, currently refreshed from OpenAlex for
  trials 51-125.

## Current Structure

Public deliverables:

- `cleaned_data/trial1.csv/.rds` through `cleaned_data/trial125.csv/.rds`
- `meta_data.xlsx`
- `data-dictionary.xlsx`
- `README.md`

Preprocessing code:

- `preprocessing/RCT_data_cleaning.Rmd`: original trial cleaning workflow.
- `preprocessing/RCT_data_cleaning_trials51_125.Rmd`: expansion cleaning
  workflow for the current flat layout.
- `preprocessing/archive/RCT_analysis.Rmd`: retained downstream analysis
  workflow.
- `preprocessing/archive/RCT_outcome_reproducibility_expansion.Rmd`: retained
  outcome reproducibility and summary-statistics audit workflow.
- `preprocessing/archive/clean_metadata_trials51_125.py`: refreshes
  publication-backed metadata for trials 51-125 and writes cell-level
  provenance.
- `preprocessing/archive/build_public_metadata.py`: rebuilds root
  `meta_data.xlsx`.
- `preprocessing/archive/build_data_dictionary.R`: rebuilds root
  `data-dictionary.xlsx`.
- `preprocessing/archive/validate_public_dataset.R`: validates the flat public
  `cleaned_data/` layout.

Ignored local curation materials:

- `local/rct_expansion/metadata/meta_data_active.xlsx`
- `local/rct_expansion/metadata/meta_data_expansion.xlsx`
- `local/rct_expansion/metadata/meta_data_backup.xlsx`
- `local/rct_expansion/provenance/*`
- `local/rct_expansion/publications/*`
- `local/rct_expansion/raw_data/*`
- `local/rct_expansion/backup/Bxx/*`

`local/` is ignored by git and may contain raw data, downloaded publications,
screening workspaces, backup candidates, generated audit outputs, and API
caches. Do not move these materials into the public tree unless explicitly
asked.

## Curation Rationale

This benchmark is for evaluating statistical adjustment methods, not for
rehosting raw repositories. Curation should keep the public files compact,
participant-level, and publication-aligned:

- Include only real individually randomized trials with participant-level data,
  treatment assignment, at least one outcome, and acceptable research reuse
  terms.
- Exclude cluster-randomized, observational, simulated, review, meta-analysis,
  and aggregate-only datasets from the flat public benchmark.
- Align primary outcomes to the primary publication whenever the public source
  data allow it.
- Select baseline covariates from the publication baseline table or
  prespecified analysis variables when available. Do not keep extra raw fields
  merely because they exist.
- Include baseline measurements of primary and secondary outcomes as `X_*`
  variables when present in raw data.
- Remove duplicate variables and variables directly computed from other
  included variables unless the publication specifically reports the derived
  variable and not the components.

## Workflow

For new or revised trials:

1. Verify eligibility, reuse terms, individual randomization, participant-level
   treatment assignment, and at least one outcome.
2. Link the dataset to the primary publication and official registry when
   available. Use official repository APIs, DOI landing pages, PubMed/PMC,
   publisher pages, and open-access PDFs. Do not bypass paywalls, CAPTCHA,
   login barriers, embargoes, data-use agreements, or rate limits.
3. Clean source data into the flat `cleaned_data/trialN.csv/.rds` contract.
4. Regenerate active local metadata/provenance from scripts rather than editing
   generated outputs by hand.
5. Refresh trials 51-125 publication metadata with
   `python3 preprocessing/archive/clean_metadata_trials51_125.py` when paper
   metadata or citation counts need updating.
6. Rebuild public metadata with
   `python3 preprocessing/archive/build_public_metadata.py`.
7. Rebuild the data dictionary with
   `Rscript preprocessing/archive/build_data_dictionary.R`.
8. Validate the public layout with
   `Rscript preprocessing/archive/validate_public_dataset.R`.

If network access is needed for OpenAlex, PubMed, Crossref, repository APIs, or
paper lookups, request it explicitly and cache source responses under ignored
local provenance folders where practical.

## Outcome Reproducibility Audit

When publication-value auditing is available, compare exact means, SDs,
medians/IQRs, counts, event totals, and rates reported in the primary
publication against the cleaned participant-level data. Use a 5% relative
tolerance unless a task specifies a different audit standard. If a mismatch is
due to curation logic, correct the cleaning workflow and regenerate outputs.

When exact adjusted/model-based targets are impractical, record descriptive
summary-statistics audit rows and clearly mark their status so they are not
mistaken for strict publication-value reproduction.

The active metadata workbooks preserve audit context in:

- `Audit_Summary`
- `Audit_Detail`
- `Validation`
- `Provenance`
- `Duplicate_Screen`
- `Cleanup_Issues`

The same audit/provenance information may also be exported under
`local/rct_expansion/provenance/`.

## Validation Expectations

For every public cleaned trial:

- `Treatment` exists and has at least two non-missing arms.
- At least one `YP_*` column exists.
- Rows are participant-level.
- `.csv` and `.rds` outputs load successfully.
- No duplicate column names are present.
- Metadata identify the paper title, journal, paper link, publication year,
  sample size, primary outcome, trial success, statistical model,
  randomization scheme, research area, and numeric citation count where
  available.
- Root `meta_data.xlsx` preserves 125 rows, the original 19 main columns, and
  the audit/provenance sheets.
- Root `data-dictionary.xlsx` contains one row per public cleaned variable.

Before finalizing metadata changes, audit trials 51-125 for no dataset DOI in
`Paper Link`, no dataset-title `Paper Name`, numeric `Citation`, and no internal
dataset IDs in `Trial Number/Name`.
