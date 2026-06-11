# RCT Expansion Data Curation Workflow

This folder contains the curated expansion trial workflow for additional public, participant-level, individually randomized clinical trial datasets. The expansion is kept separate from the original 50-trial benchmark so the original `cleaned_data/` outputs remain untouched.

## Current Status

Active curated expansion trials:

- Trial 51: sleep hygiene and lavender oil for athletes
- Trial 52: tenapanor for hyperphosphatemia and constipation in hemodialysis
- Trial 53: anterior quadratus lumborum block in laparoscopic partial nephrectomy
- Trial 54: vaginal spheres and pelvic floor exercises
- Trial 55: Taking Charge after acute COPD exacerbation
- Trial 56: transcranial direct-current stimulation for attention in burnout
- Trial 57: functional imagery training versus motivational interviewing for weight loss
- Trial 58: transcranial direct-current stimulation plus cognitive training in schizophrenia
- Trial 59: acute tissue flossing for ankle range of motion
- Trial 60: interferential-current dental facial treatment for masticatory function
- Trial 61: cinnamon, chromium, and carnosine supplementation in prediabetes
- Trial 62: cyclosporine-to-tacrolimus conversion after kidney transplantation
- Trial 63: HIIT versus circuit resistance training in heart failure
- Trial 64: low-dose exercise for chronic low back pain
- Trial 65: transcranial direct-current stimulation for endurance running performance
- Trial 66: Ashtanga yoga therapy for visually impaired persons
- Trial 67: high cut-off versus standard filter in continuous venovenous hemodialysis
- Trial 68: brain-computer-interface attention training for ADHD
- Trial 69: tapentadol and morphine conditioned-pain-modulation crossover
- Trial 70: Lumosity cognitive training versus crossword control
- Trial 71: antenatal asymptomatic-bacteriuria screening and birth outcomes
- Trial 72: sublingual misoprostol versus oxytocin for postpartum hemorrhage
- Trial 73: AI reassurance-call service after prostate biopsy
- Trial 74: home-based core stability exercises in hereditary ataxia
- Trial 75: reduced-branch versus conventional genicular radiofrequency ablation
- Trial 76: time-segmented-target teaching for spinal puncture training
- Trial 77: core stability exercises in early subacute stroke recovery
- Trial 78: regional moderate hyperthermia for mild-to-moderate COVID-19
- Trial 79: webtoon education for premature-labor preventive self-management
- Trial 80: digital peer support for weight management in university students

Backup trials excluded from active outputs:

- B01: insufficient publication/source information for K-MPAI primary-outcome reproducibility
- B02: source data mismatch after correcting malaria event coding
- B03: public raw files do not contain the published sputum bacterial-load primary outcome
- B04: SIS and WHODAS summaries had exact-comparison mismatches and remain archived
- B05: no associated main publication was identified

## Folder Map

- `raw_data/trialNN/`: active raw source files
- `cleaned_data/trialNN.csv` and `cleaned_data/trialNN.rds`: active participant-level cleaned datasets
- `publications/`: active downloaded publication PDFs and active publication link logs
- `metadata/meta_data_active.xlsx`: active metadata workbook
- `metadata/meta_data_backup.xlsx`: backup metadata workbook
- `metadata/meta_data_expansion.xlsx`: active-only compatibility copy
- `metadata/data_dictionary.csv`: active cleaned-variable dictionary with trial number, variable name, variable type, and a brief explanation
- `provenance/download_log.csv`: active data source log
- `provenance/skipped_candidates.csv`: skipped or ineligible candidate records
- `provenance/removed_duplicate_candidates.csv`: newly identified duplicate candidates removed from the expansion pool
- `provenance/validation_summary.csv`: active cleaned-data contract checks
- `provenance/outcome_reproducibility_targets.csv`: paper targets used for outcome audit
- `provenance/outcome_reproducibility_audit.csv`: paper-vs-cleaned comparison table
- `provenance/backup_trials.csv`: archived trial decisions and reasons
- `backup/Bxx/`: archived trials with `raw_data/`, `cleaned_data/`, `publications/` when available, and `backup_reason.md`

## Data Contract

Each active cleaned dataset must be participant-level and include:

- `Treatment`: treatment assignment, as a factor where possible, with the control/reference arm first when identifiable
- `YP_*`: at least one primary outcome
- `YS_*`: secondary outcomes when useful and available
- `X_*`: baseline covariates and baseline outcome measurements when present in raw data

Do not keep duplicate columns or variables directly computed from other included variables unless the publication reports only the derived variable and not the components.

The cleaning workflow also regenerates `metadata/data_dictionary.csv`. It must contain one row per active cleaned variable with `Trial_ID`, `variable_name`, `variable_type`, and `brief_explanation`.

## Curation Workflow

1. Verify candidate eligibility: individual randomization, participant-level data, treatment assignment, outcomes, main publication, non-duplicate status, and acceptable reuse terms.
2. Screen candidate titles and publication DOIs against `cleaned_data/meta_data.xlsx` and the existing expansion metadata. The cleaning workflow writes `provenance/duplicate_screening_active.csv` for active candidates and `provenance/duplicate_screening.csv` for the full identified candidate pool. Active duplicates stop the workflow.
3. Search PubMed by study name/title and follow PubMed Central, DOI, journal, or repository links for the associated paper. Download the full publication PDF into `publications/` when it is publicly available online without login, payment, CAPTCHA, embargo, or data-use restrictions; otherwise record the publication link and availability status.
4. Read the associated paper before finalizing variables. Extract treatment arms, primary/secondary outcomes, baseline table variables, statistical model, randomization scheme, sample size, citation, and reported outcome summaries.
5. Select covariates from variables prespecified in the primary statistical analysis, when available, and variables reported in the baseline characteristics table of the primary publication.
6. Include baseline measurements of primary and secondary outcomes as `X_*` variables when raw data contain them.
7. Implement cleaning in `RCT_data_cleaning_expansion.Rmd`.
8. Regenerate active cleaned files, metadata, data dictionary, publication links, download log, and validation summary from the cleaning Rmd.
9. Run the outcome reproducibility audit in `RCT_outcome_reproducibility_expansion.Rmd`.
10. Correct curation logic when a mismatch is clearly caused by cleaning. Rerun cleaning and audit after correction.
11. Move trials to `backup/Bxx/` when the publication or source data do not allow primary-outcome reproducibility, or when corrected source data still cannot reproduce the publication primary outcome within tolerance.

## Reproducibility Audit

The audit compares exact numeric paper summaries against the cleaned data:

- means and SDs
- medians and IQRs
- counts and event totals
- rates, including person-time rates when reported

Audit columns:

`Trial_ID`, `outcome_variable`, `outcome_role`, `arm`, `statistic`, `paper_value`, `paper_precision`, `cleaned_value`, `absolute_diff`, `tolerance`, `status`, `paper_source`, `notes`

Tolerance is 5% of the reported paper value: `tolerance = abs(paper_value) * 0.05`. Active trials must have at least one primary-outcome audit target with `status = pass`.

## Run Order

From the repository root, rerun cleaning first and then the reproducibility audit:

```sh
Rscript -e 'knitr::purl("rct_expansion/RCT_data_cleaning_expansion.Rmd", output="/private/tmp/RCT_data_cleaning_expansion.R", quiet=TRUE); source("/private/tmp/RCT_data_cleaning_expansion.R")'
Rscript -e 'knitr::purl("rct_expansion/RCT_outcome_reproducibility_expansion.Rmd", output="/private/tmp/RCT_outcome_reproducibility_expansion.R", quiet=TRUE); source("/private/tmp/RCT_outcome_reproducibility_expansion.R")'
python3 rct_expansion/scripts/cleanup_expansion_folder.py
```

After rerunning, confirm:

- active `raw_data/`, `cleaned_data/`, `publications/`, `meta_data_active.xlsx`, `meta_data_expansion.xlsx`, `data_dictionary.csv`, `publication_links.csv`, `download_log.csv`, `pubmed_publication_downloads.csv`, and `validation_summary.csv` include only active trials 51 through 121
- `duplicate_screening_active.csv` has no active duplicate rows; `duplicate_screening.csv` records any skipped/search-pool candidates that overlap existing metadata
- `removed_duplicate_candidates.csv` records duplicate candidates removed from the expansion pool
- `meta_data_backup.xlsx` and `backup_trials.csv` include archived backup trials B01 through B13
- all active primary audit rows have `status = pass`
- active `.rds` files pass the dataset contract

## Ethical Download Rules

Use official repository APIs, PubMed Central links, publisher open-access links, or DOI landing pages. Do not bypass rate limits, CAPTCHA, login barriers, paywalls, embargoes, data-use agreements, or access controls. If a repository asks for identity, use: Bingkai Wang, University of Michigan, bingkai@umich.edu. If a repository is temporarily unavailable, record the candidate in `provenance/skipped_candidates.csv` and move to the next candidate.
