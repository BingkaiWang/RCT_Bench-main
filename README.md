# RCT Bench

RCT Bench is a curated benchmark of public, participant-level randomized
controlled trial datasets for evaluating covariate-adjustment methods.

## Dataset

The public cleaned dataset contains 125 individually randomized RCTs:

- `cleaned_data/trial1.csv` through `cleaned_data/trial125.csv`
- `cleaned_data/trial1.rds` through `cleaned_data/trial125.rds`
- `meta_data.xlsx`
- `data-dictionary.xlsx`
- `rct_bench_all_data_and_dictionaries.zip` for one-click download of all
  cleaned trial files and per-trial dictionary CSVs

Each cleaned trial is participant-level and follows the same variable contract:

- `Treatment`: randomized treatment assignment, with the control/reference arm
  first when identifiable.
- `YP_*`: primary outcome variables. Each trial has at least one.
- `YS_*`: secondary outcome variables when useful and available.
- `X_*`: baseline covariates or pre-treatment measurements.
- `Participant_ID`: an optional de-identified cluster key retained only for
  crossover/repeated-measures trials; it is not an adjustment covariate.
- `Crossover_Sequence`, `Crossover_Period`, and `Assessment_Window`: optional
  trial-design fields that are likewise excluded from the `X_*` covariate set.

## Metadata

`meta_data.xlsx` contains one public metadata workbook for all 125 trials. The
main `Sheet1` uses an 18-column metadata schema, including the
historical spelling `Priamry Outcome` for compatibility.

`Primary Outcome Type` uses the controlled categories `Continuous`, `Binary`,
`Count`, `Time-to-event`, `Ordinal`, and `Categorical`; trials with co-primary
outcomes of different types use semicolon-separated combinations. `Research
Area` uses 15 broad clinical groupings to keep filtering consistent across
trials.

Additional workbook sheets preserve expansion curation context where available:

- `Provenance`
- `Validation`
- `Audit_Summary`
- `Audit_Detail`
- `Duplicate_Screen`
- `Cleanup_Issues`

`data-dictionary.xlsx` contains one row per variable per trial with the variable
role, inferred statistical/storage type, R class, missingness, unique-value
count, levels or range, and a short explanation.

For expansion trials 51-125, metadata should describe the primary publication
rather than the source dataset record. `Trial Number/Name` is reserved for
official registry identifiers such as ClinicalTrials.gov, ISRCTN, UMIN, CTRI,
TCTR, ACTRN, DRKS, or similar registries; it is left blank when no registry ID
is discoverable. `Paper Link` should point to the paper DOI or publisher page,
and `Citation` is stored as a numeric citation count.

## Data Curation Rationale And Workflow

RCT Bench is designed for method evaluation, so each trial is curated to expose
the participant-level structure needed for covariate-adjusted analyses while
keeping the analysis table compact and reproducible. The cleaned files retain
randomized treatment assignment, publication-aligned primary outcomes, useful
secondary outcomes, and baseline covariates measured before treatment.

Expansion trials are screened before inclusion. A candidate must be an
individually randomized trial, provide participant-level data with treatment
assignment and at least one outcome, have reuse terms compatible with research
reuse, and be linkable to a primary publication or official preprint. Cluster
trials, observational studies, simulations, reviews, meta-analyses, and
aggregate-only datasets are excluded from the public benchmark.

The curation workflow is:

1. Identify candidate datasets from open repositories and confirm eligibility.
2. Link each dataset to the primary publication, trial registry, DOI, and
   journal record when available.
3. Clean source data into one participant-level `.csv` and `.rds` file per
   trial using the `Treatment`, `YP_*`, `YS_*`, and `X_*` contract.
4. Select baseline covariates from the publication baseline table or
   prespecified analysis variables rather than keeping every raw field.
5. Audit cleaned outcomes against publication values when feasible; otherwise
   record descriptive summary-statistics audit rows.
6. Apply the reproducible public-contract repair step for known identifier,
   sentinel, crossover-grain, and variable-role issues.
7. Refresh publication-backed metadata, data dictionary, validation summaries,
   and provenance outputs from scripts rather than editing generated artifacts
   by hand.

Raw files, downloaded papers, backup candidates, screening queues, and detailed
provenance live under ignored `local/` staging folders. The public repository
keeps the cleaned benchmark, public metadata workbooks, and reusable
preprocessing code.

## Preprocessing

Reproducible cleaning, screening, validation, and metadata-generation code lives
under `preprocessing/`.

Important entry points:

- `preprocessing/RCT_data_cleaning.Rmd`: original trial cleaning workflow.
- `preprocessing/RCT_data_cleaning_trials51_125.Rmd`: expansion trial cleaning
  workflow for the current flat 125-trial public layout.
- `preprocessing/archive/RCT_outcome_reproducibility_expansion.Rmd`: retained
  expansion outcome reproducibility and summary-statistics audit workflow.
- `preprocessing/archive/RCT_analysis.Rmd`: downstream method-comparison
  analysis workflow retained from the original repository.
- `preprocessing/archive/build_public_metadata.py`: rebuilds
  `meta_data.xlsx`.
- `preprocessing/archive/clean_metadata_trials51_125.py`: refreshes
  publication-backed metadata for trials 51-125 and writes a cell-level
  provenance CSV.
- `preprocessing/archive/build_data_dictionary.R`: rebuilds
  `data-dictionary.xlsx`, the 125 `data_dictionary/trialN_dictionary.csv`
  files, and `data_dictionary/validation_summary.json`.
- `preprocessing/archive/validate_public_dataset.R`: validates the flat public
  `cleaned_data/` layout.
- `preprocessing/archive/repair_cleaned_data_quality_issues.R`: applies the
  source-backed public-contract repairs before metadata and dictionary rebuilds.

## Local Materials

Raw data, downloaded publications, provenance archives, screening workspaces,
backup candidates, generated plots, and legacy staging folders are kept under
`local/`. That folder is intentionally ignored by git so the public repository
stays focused on the cleaned benchmark and reproducible preprocessing code.

## Use

In R, a cleaned trial can be loaded with:

```r
trial1 <- readRDS("cleaned_data/trial1.rds")
trial51 <- read.csv("cleaned_data/trial51.csv", check.names = FALSE)
```

Before analysis, validate the public layout:

```sh
Rscript preprocessing/archive/validate_public_dataset.R
```

Regenerate metadata and the data dictionary:

```sh
Rscript preprocessing/archive/repair_cleaned_data_quality_issues.R
python3 preprocessing/archive/clean_metadata_trials51_125.py  # requires openpyxl and network access for OpenAlex refreshes
python3 preprocessing/archive/build_public_metadata.py
Rscript preprocessing/archive/build_data_dictionary.R
```
