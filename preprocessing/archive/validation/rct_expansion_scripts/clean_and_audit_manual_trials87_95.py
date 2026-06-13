#!/usr/bin/env python3
"""Clean and audit the qualified manual-check RCT candidates.

The batch comes from
provenance/manual_check_verification_2026_06_09/manual_check_qualified_for_cleaning_queue.csv.
It is kept separate from the earlier active expansion scripts so the raw-data
copy, cleaned files, publication review, and reproducibility audit are easy to
inspect before any later active-metadata merge.
"""

from __future__ import annotations

import csv
import math
import os
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

import numpy as np
import pandas as pd


ROOT = Path(__file__).resolve().parents[2]
EXPANSION = ROOT / "rct_expansion"
SOURCE_DIR = (
    EXPANSION
    / "provenance"
    / "manual_check_verification_2026_06_09"
    / "downloads"
)
RAW_DIR = EXPANSION / "raw_data"
CLEAN_DIR = EXPANSION / "cleaned_data"
PROV_DIR = EXPANSION / "provenance"
META_DIR = EXPANSION / "metadata"
XLRD_TARGET = Path("/private/tmp/codex_xlrd_manual_trials")

if XLRD_TARGET.exists():
    sys.path.insert(0, str(XLRD_TARGET))


@dataclass(frozen=True)
class TrialInfo:
    trial_id: str
    candidate_ids: tuple[str, ...]
    title: str
    repository: str
    dataset_doi: str
    publication_doi: str
    source_files: tuple[tuple[str, str], ...]
    publication_source: str
    primary_outcome: str
    primary_type: str
    treatment_arms: str
    control_group: str
    statistical_model: str
    randomization_scheme: str
    research_area: str
    covariate_source: str
    review_notes: str
    license_notes: str


TRIALS: list[TrialInfo] = [
    TrialInfo(
        trial_id="trial87",
        candidate_ids=("RCTC-03207",),
        title=(
            "Comparison of hemodynamic response to tracheal intubation and "
            "postoperative pain in closed reduction of nasal bone fracture"
        ),
        repository="Figshare / Springer Nature",
        dataset_doi="10.6084/m9.figshare.c.3613661_d1.v1",
        publication_doi="10.1186/s12871-016-0279-x",
        source_files=(("RCTC-03207", "12871_2016_279_MOESM1_ESM.xlsx"),),
        publication_source="BMC Anesthesiology 2016 Table 1 and Table 2",
        primary_outcome=(
            "Hemodynamic response after intubation and postoperative pain "
            "NRS/VAS in PACU"
        ),
        primary_type="continuous",
        treatment_arms="Fentanyl; Oxycodone",
        control_group="Fentanyl",
        statistical_model="Independent group comparisons; table reports means, medians, counts",
        randomization_scheme="Individually randomized, parallel two-arm",
        research_area="Anesthesiology",
        covariate_source="Publication baseline Table 1",
        review_notes=(
            "Supplemental workbook contains baseline, hemodynamic, and PACU "
            "outcomes. Complications sheet has arm blocks without participant IDs; "
            "rows were aligned within arm by original order."
        ),
        license_notes="Open-access article supplement from Springer Nature Figshare.",
    ),
    TrialInfo(
        trial_id="trial88",
        candidate_ids=("RCTC-05855",),
        title="Effects of nutrition education on recurrent coronary events after PCI",
        repository="Figshare / Springer Nature",
        dataset_doi="10.6084/m9.figshare.c.3597956_d2.v1",
        publication_doi="10.1186/s40795-016-0111-5",
        source_files=(("RCTC-05855", "40795_2016_111_MOESM1_ESM.xlsx"),),
        publication_source="BMC Nutrition 2016 Table 2",
        primary_outcome="Mortality after one-year follow-up",
        primary_type="binary event",
        treatment_arms="Control; Nutrition education",
        control_group="Control",
        statistical_model="Absolute risk reduction and Cox models in publication",
        randomization_scheme="Individually randomized, parallel two-arm",
        research_area="Cardiology / nutrition",
        covariate_source="Publication baseline Table 1 and raw data dictionary",
        review_notes="Raw database includes treatment group, baseline risk factors, and event outcomes.",
        license_notes="Open-access article supplement from Springer Nature Figshare.",
    ),
    TrialInfo(
        trial_id="trial89",
        candidate_ids=("RCTC-03212",),
        title="Acupuncture and nimodipine for mild cognitive impairment after cerebral infarction",
        repository="Figshare / Springer Nature",
        dataset_doi="10.6084/m9.figshare.c.3602990_d1.v1",
        publication_doi="10.1186/s12906-016-1337-0",
        source_files=(("RCTC-03212", "12906_2016_1337_MOESM2_ESM.xlsx"),),
        publication_source="BMC Complementary and Alternative Medicine 2016 Table 2",
        primary_outcome="Montreal Cognitive Assessment score after three-month therapy",
        primary_type="continuous",
        treatment_arms="Nimodipine alone; Acupuncture alone; Nimodipine + acupuncture",
        control_group="Nimodipine alone",
        statistical_model="Within- and between-group MoCA comparisons",
        randomization_scheme="Individually randomized, parallel three-arm",
        research_area="Neurology / complementary medicine",
        covariate_source="Primary outcome baseline values in Table 2",
        review_notes="Workbook encodes treatment assignment by arm-specific sheets.",
        license_notes="Open-access article supplement from Springer Nature Figshare.",
    ),
    TrialInfo(
        trial_id="trial90",
        candidate_ids=("RCTC-00458", "RCTC-00459"),
        title="Community pharmacist-led medication review in patients on polypharmacy",
        repository="Figshare / Springer Nature",
        dataset_doi="10.6084/m9.figshare.c.3603329_d1.v1 and d3.v1",
        publication_doi="10.1186/s12913-016-1384-8",
        source_files=(
            ("RCTC-00458", "12913_2016_1384_MOESM2_ESM.xlsx"),
            ("RCTC-00459", "12913_2016_1384_MOESM3_ESM.xlsx"),
        ),
        publication_source="BMC Health Services Research 2016 Table 5 and Table 6",
        primary_outcome="Objective adherence by MPR and DPPR",
        primary_type="continuous percentage",
        treatment_arms="Control; Intervention",
        control_group="Control",
        statistical_model="Independent group comparisons of adherence summaries",
        randomization_scheme="Individually randomized, parallel two-arm",
        research_area="Pharmacy / health services",
        covariate_source="Publication baseline and raw participant file",
        review_notes=(
            "RCTC-00459 is participant-level DPPR. RCTC-00458 is supporting "
            "medication-row MPR for the same participants; medication-row sums "
            "are retained as compact participant-level audit components."
        ),
        license_notes="Open-access article supplements from Springer Nature Figshare.",
    ),
    TrialInfo(
        trial_id="trial91",
        candidate_ids=("RCTC-03185",),
        title="MOVE-trial: Monocryl vs Vicryl Rapide for skin repair in mediolateral episiotomies",
        repository="Figshare / Springer Nature",
        dataset_doi="10.6084/m9.figshare.c.3906040_d2",
        publication_doi="10.1186/s12884-017-1545-8",
        source_files=(("RCTC-03185", "12884_2017_1545_MOESM2_ESM.xls"),),
        publication_source="BMC Pregnancy and Childbirth 2017 Table 3",
        primary_outcome="VAS pain while sitting at 10 days",
        primary_type="continuous",
        treatment_arms="Vicryl Rapide; Monocryl",
        control_group="Vicryl Rapide",
        statistical_model="Independent group comparisons of VAS and wound outcomes",
        randomization_scheme="Individually randomized, parallel two-arm",
        research_area="Obstetrics",
        covariate_source="Publication baseline table and source workbook",
        review_notes=(
            "Legacy .xls has more randomized codes than usable primary-outcome "
            "rows. Audit compares the nonmissing VAS rows to the publication table "
            "and records the count mismatch."
        ),
        license_notes="Open-access article supplement from Springer Nature Figshare.",
    ),
    TrialInfo(
        trial_id="trial92",
        candidate_ids=("RCTC-04202",),
        title="Health education intervention to improve malaria preventive practices in pregnancy",
        repository="Figshare",
        dataset_doi="10.6084/m9.figshare.13627127.v1",
        publication_doi="10.1186/s12936-021-03586-5",
        source_files=(("RCTC-04202", "12936_2021_3586_MOESM1_ESM.xlsx"),),
        publication_source="Malaria Journal 2021 Table 4 and Table 5",
        primary_outcome="Reported ITN use and IPTp doses four months post-intervention",
        primary_type="ordinal categorical",
        treatment_arms="Control; Intervention",
        control_group="Control",
        statistical_model="Chi-squared tests for practice and clinical outcomes",
        randomization_scheme="Individually randomized, parallel two-arm",
        research_area="Malaria prevention / pregnancy",
        covariate_source="Publication baseline characteristics table",
        review_notes="Source workbook contains baseline covariates, prevention-practice outcomes, and birth outcomes.",
        license_notes="Open data record on Figshare.",
    ),
    TrialInfo(
        trial_id="trial93",
        candidate_ids=("RCTC-07219",),
        title="Impact of text message reminders on adherence to antimalarial treatment",
        repository="Harvard Dataverse",
        dataset_doi="10.7910/DVN/FOMQOO",
        publication_doi="10.1371/journal.pone.0109032",
        source_files=(
            ("RCTC-07219", "PACT_30March2012.tab"),
            ("RCTC-07219", "Wealth Index HL April 2011.tab"),
            ("RCTC-07219", "PACT main analysis final.do"),
        ),
        publication_source="PLOS ONE 2014 Table 2, Table 4, and authors' Stata code",
        primary_outcome="Self-reported completion of ACT antimalarial treatment",
        primary_type="binary self-report",
        treatment_arms="Control; Reminder only; Reminder plus information",
        control_group="Control",
        statistical_model="Logistic regression with clustered standard errors",
        randomization_scheme="Individually randomized SMS assignment, three trial groups",
        research_area="Malaria treatment adherence",
        covariate_source="Publication Table 1 and authors' Stata code",
        review_notes=(
            "The released tab file omits the derived adhered_SR variable; it is "
            "recreated from p35_finishdose according to the Stata code."
        ),
        license_notes="Harvard Dataverse CC0 metadata/license from screening.",
    ),
    TrialInfo(
        trial_id="trial94",
        candidate_ids=("RCTC-06852",),
        title="Daily SMS medication reminder system and tuberculosis treatment outcomes in Pakistan",
        repository="Impact Evaluation Dataverse",
        dataset_doi="10.7910/DVN/TPRAOT",
        publication_doi="10.1371/journal.pone.0162944",
        source_files=(
            ("RCTC-06852", "txoutcomeandbaselinedata_3ie.tab"),
            ("RCTC-06852", "secondaryoutcomedata_3ie.tab"),
            ("RCTC-06852", "Treatment Outcomes and Baseline Data Codebook_3IE.xlsx"),
        ),
        publication_source="PLOS ONE 2016 Table 2",
        primary_outcome="Clinically recorded tuberculosis treatment success",
        primary_type="binary clinical outcome",
        treatment_arms="Control; Zindagi SMS",
        control_group="Control",
        statistical_model="Group comparison and regression in publication",
        randomization_scheme="Individually randomized, parallel two-arm",
        research_area="Tuberculosis treatment adherence",
        covariate_source="Publication baseline table and source codebook",
        review_notes="Downloaded through official Dataverse guestbook using repository-specified identity.",
        license_notes="CC BY-NC-SA 4.0 caveat recorded during screening.",
    ),
    TrialInfo(
        trial_id="trial95",
        candidate_ids=("RCTC-03313",),
        title="LaMaTuPe: laryngeal mask vs laryngeal tube in pediatric patients",
        repository="heiDATA",
        dataset_doi="10.11588/data/J7ZITW",
        publication_doi="10.1097/MEJ.0000000000001178",
        source_files=(("RCTC-03313", "Anonymised_Data_LaMaTuPe_2024-01-23.xlsx"),),
        publication_source="European Journal of Emergency Medicine 2025 article text and Table 2",
        primary_outcome="Insertion time in seconds",
        primary_type="continuous time",
        treatment_arms="Laryngeal mask; Laryngeal tube",
        control_group="Laryngeal mask",
        statistical_model="Mann-Whitney U test; medians and IQR",
        randomization_scheme="Individually randomized, parallel two-arm by age blocks",
        research_area="Pediatric anesthesia / emergency airway",
        covariate_source="Publication Table 1 and data glossary",
        review_notes=(
            "Public article HTML was available without login; PDF was not publicly "
            "downloadable from DOI during this run. Numeric insertion-time cells "
            "are used for the compact primary audit; compound free-text timing "
            "cells are retained in X_insertion_time_raw."
        ),
        license_notes="heiDATA record CC BY 4.0; article is CC BY-NC-ND.",
    ),
]


def clean_colnames(df: pd.DataFrame) -> pd.DataFrame:
    out = df.copy()
    out.columns = [str(c).strip() for c in out.columns]
    return out


def as_num(value) -> float:
    return pd.to_numeric(value, errors="coerce")


def binary_o(value) -> float:
    if pd.isna(value):
        return 0.0
    return 1.0 if str(value).strip().lower() in {"o", "1", "yes", "y", "true"} else 0.0


def factor_map(series: pd.Series, mapping: dict) -> pd.Series:
    return series.map(mapping).astype("object")


def safe_numeric_series(series: pd.Series) -> pd.Series:
    return pd.to_numeric(series, errors="coerce")


def first_number(value) -> float:
    if pd.isna(value):
        return np.nan
    if isinstance(value, (int, float, np.integer, np.floating)):
        return float(value)
    match = re.search(r"\d+(?:\.\d+)?", str(value).replace(",", "."))
    return float(match.group(0)) if match else np.nan


def copy_sources() -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    for trial in TRIALS:
        dest_dir = RAW_DIR / trial.trial_id
        dest_dir.mkdir(parents=True, exist_ok=True)
        for candidate_id, filename in trial.source_files:
            src = SOURCE_DIR / candidate_id / filename
            dest = dest_dir / filename
            if not src.exists():
                raise FileNotFoundError(src)
            shutil.copy2(src, dest)
            rows.append(
                {
                    "Trial_ID": trial.trial_id,
                    "Candidate_ID": candidate_id,
                    "Source_File": str(src.relative_to(ROOT)),
                    "Copied_To": str(dest.relative_to(ROOT)),
                    "File_Size_Bytes": str(dest.stat().st_size),
                }
            )
    return rows


def read_source(trial_id: str, filename: str) -> Path:
    path = RAW_DIR / trial_id / filename
    if not path.exists():
        raise FileNotFoundError(path)
    return path


def make_rds(csv_path: Path, rds_path: Path, treatment_levels: list[str]) -> None:
    env = os.environ.copy()
    env["CSV_PATH"] = str(csv_path)
    env["RDS_PATH"] = str(rds_path)
    env["TREATMENT_LEVELS"] = "\x1f".join(treatment_levels)
    code = (
        "csv <- Sys.getenv('CSV_PATH'); "
        "rds <- Sys.getenv('RDS_PATH'); "
        "lev <- strsplit(Sys.getenv('TREATMENT_LEVELS'), '\\x1f', fixed=TRUE)[[1]]; "
        "df <- read.csv(csv, check.names=FALSE, stringsAsFactors=FALSE); "
        "if ('Treatment' %in% names(df)) df$Treatment <- factor(df$Treatment, levels=lev); "
        "saveRDS(df, rds)"
    )
    subprocess.run(["Rscript", "-e", code], check=True, env=env)


def write_cleaned(
    trial_id: str, df: pd.DataFrame, treatment_levels: list[str]
) -> pd.DataFrame:
    if "Treatment" not in df.columns:
        raise ValueError(f"{trial_id} has no Treatment column")
    y_cols = [c for c in df.columns if c.startswith("YP_")]
    if not y_cols:
        raise ValueError(f"{trial_id} has no YP_ columns")

    cols = ["Treatment"] + [c for c in df.columns if c != "Treatment"]
    out = df.loc[:, cols].copy()
    if out.columns.duplicated().any():
        dupes = out.columns[out.columns.duplicated()].tolist()
        raise ValueError(f"{trial_id} duplicate columns: {dupes}")
    out["Treatment"] = pd.Categorical(out["Treatment"], categories=treatment_levels, ordered=False)

    csv_path = CLEAN_DIR / f"{trial_id}.csv"
    rds_path = CLEAN_DIR / f"{trial_id}.rds"
    CLEAN_DIR.mkdir(parents=True, exist_ok=True)
    out.to_csv(csv_path, index=False, na_rep="")
    make_rds(csv_path, rds_path, treatment_levels)
    return out


def clean_trial87() -> tuple[pd.DataFrame, list[str]]:
    path = read_source("trial87", "12871_2016_279_MOESM1_ESM.xlsx")
    base = clean_colnames(pd.read_excel(path, sheet_name="base", header=1))
    base = base[base["Group"].isin(["F", "O"])].copy()
    base["Treatment"] = factor_map(base["Group"], {"F": "Fentanyl", "O": "Oxycodone"})
    base["row_in_arm"] = base.groupby("Treatment").cumcount() + 1

    hemo = clean_colnames(pd.read_excel(path, sheet_name="Hemodynamic changes", header=1))
    hemo = hemo[hemo["Group"].isin(["F", "O"])].copy()
    hemo["Treatment"] = factor_map(hemo["Group"], {"F": "Fentanyl", "O": "Oxycodone"})
    hemo["row_in_arm"] = hemo.groupby("Treatment").cumcount() + 1
    delta_mbp_raw = hemo.columns[8]
    hemo_part = pd.DataFrame(
        {
            "Treatment": hemo["Treatment"],
            "row_in_arm": hemo["row_in_arm"],
            "YP_delta_mbp_mmHg": safe_numeric_series(hemo[delta_mbp_raw]),
            "YS_delta_mbp_ratio": safe_numeric_series(hemo["Delta MBP/Pre induction"]),
            "X_pre_induction_hr_bpm": safe_numeric_series(hemo["Pre induction HR"]),
            "X_post_intubation_hr_bpm": safe_numeric_series(hemo["Post induction HR"]),
            "YP_delta_hr_bpm": safe_numeric_series(hemo["Post induction HR"])
            - safe_numeric_series(hemo["Pre induction HR"]),
            "YS_delta_hr_percent": safe_numeric_series(hemo["Delta HR"]) * 100.0,
        }
    )

    comp = pd.read_excel(path, sheet_name="complications", header=0)
    comp_rows: list[dict] = []
    current = None
    counts = {"F": 0, "O": 0}
    for _, row in comp.iterrows():
        marker = row.iloc[0]
        if marker in {"F", "O"}:
            current = marker
            continue
        if current not in {"F", "O"} or counts[current] >= 32:
            continue
        pain = pd.to_numeric(row.iloc[1], errors="coerce")
        if pd.isna(pain):
            continue
        counts[current] += 1
        comp_rows.append(
            {
                "Treatment": {"F": "Fentanyl", "O": "Oxycodone"}[current],
                "row_in_arm": counts[current],
                "YP_postoperative_pain_vas": pain,
                "YS_rescue_analgesic": binary_o(row.iloc[2]),
                "YS_agitation_score": pd.to_numeric(row.iloc[3], errors="coerce"),
                "YS_agitation_3_or_4": 1.0
                if pd.to_numeric(row.iloc[3], errors="coerce") >= 3
                else 0.0,
                "YS_cough": safe_numeric_series(pd.Series([row.iloc[4]])).iloc[0],
                "YS_dizziness": safe_numeric_series(pd.Series([row.iloc[5]])).iloc[0],
                "YS_oxygen_saturation_lt92": safe_numeric_series(pd.Series([row.iloc[6]])).iloc[0],
                "YS_hypotension": safe_numeric_series(pd.Series([row.iloc[7]])).iloc[0],
                "YS_bradycardia": safe_numeric_series(pd.Series([row.iloc[8]])).iloc[0],
                "YS_awakening_time_sec": safe_numeric_series(pd.Series([row.iloc[9]])).iloc[0],
            }
        )
    comp_part = pd.DataFrame(comp_rows)

    out = pd.DataFrame(
        {
            "Treatment": base["Treatment"],
            "X_source_participant_no": safe_numeric_series(base["No."]),
            "X_sex": factor_map(base["Sex"], {1: "Male", 2: "Female"}),
            "X_age_years": safe_numeric_series(base["Age"]),
            "X_height_cm": safe_numeric_series(base["Height"]),
            "X_weight_kg": safe_numeric_series(base["Weight"]),
            "X_bmi": safe_numeric_series(base["BMI"]),
            "X_asa_class": safe_numeric_series(base["ASA"]),
            "X_mallampati_class": safe_numeric_series(base["Mallampati"]),
            "X_cormack_lehane_grade": safe_numeric_series(base["Cormack-Lehane"]),
            "X_intubation_difficulty": safe_numeric_series(base["Difficulty of intubation"]),
            "X_anesthesia_time_min": safe_numeric_series(base["ANE time"]),
            "row_in_arm": base["row_in_arm"],
        }
    )
    out = out.merge(hemo_part, on=["Treatment", "row_in_arm"], how="left")
    out = out.merge(comp_part, on=["Treatment", "row_in_arm"], how="left")
    out["YS_delta_mbp_gt40pct"] = (out["YS_delta_mbp_ratio"] > 0.40).astype(float)
    out["YS_delta_hr_gt20pct"] = (out["YS_delta_hr_percent"] > 20.0).astype(float)
    out = out.drop(columns=["row_in_arm"])
    return out, ["Fentanyl", "Oxycodone"]


def clean_trial88() -> tuple[pd.DataFrame, list[str]]:
    path = read_source("trial88", "40795_2016_111_MOESM1_ESM.xlsx")
    df = pd.read_excel(path, sheet_name="raw database")
    out = pd.DataFrame(
        {
            "Treatment": factor_map(df["group"], {0: "Control", 1: "Nutrition education"}),
            "X_source_id": df["id"],
            "X_sex_code": df["sex"],
            "X_age_years": df["age"],
            "X_balloon_angioplasty": df["ballon"],
            "X_stent": df["stent"],
            "X_pharmacologic_stent": df["pharstent"],
            "X_education_years": df["school"],
            "X_hypertension": df["has"],
            "X_dyslipidemia": df["dlp"],
            "X_diabetes": df["dm"],
            "X_heart_failure": df["hf"],
            "X_prior_ami": df["p_ami"],
            "X_prior_pci": df["p_pci"],
            "X_prior_cabg": df["p_cabg"],
            "X_smoking_baseline": df["tabag0"],
            "X_antihypertensive_baseline": df["antihip0"],
            "X_oral_hypoglycemic_baseline": df["hipogl0"],
            "X_statin_baseline": df["statin0"],
            "YP_death_1y": df["mort1"],
            "YS_cabg_1y": df["cabg1"],
            "YS_ami_1y": df["ami1"],
            "YS_repeat_pci_1y": df["repci1"],
            "YS_composite_event_1y": df["comp1"],
        }
    )
    return out, ["Control", "Nutrition education"]


def clean_trial89() -> tuple[pd.DataFrame, list[str]]:
    path = read_source("trial89", "12906_2016_1337_MOESM2_ESM.xlsx")
    sheet_map = {
        "Nimodipine": "Nimodipine alone",
        "Acupuncture": "Acupuncture alone",
        "nimodipine +acupuncture": "Nimodipine + acupuncture",
    }
    pieces = []
    for sheet, arm in sheet_map.items():
        df = clean_colnames(pd.read_excel(path, sheet_name=sheet, header=1))
        baseline = safe_numeric_series(df["Enrollment day"])
        post = safe_numeric_series(df["at the end of 3-month therapy"])
        follow = safe_numeric_series(df["post-treament 3 month follow-up"])
        pieces.append(
            pd.DataFrame(
                {
                    "Treatment": arm,
                    "X_source_patient_no": df["Patient No"],
                    "X_moca_enrollment": baseline,
                    "YP_moca_3m": post,
                    "YS_moca_followup_6m": follow,
                    "YP_delta_moca_3m": post - baseline,
                    "YS_delta_moca_followup_6m": follow - baseline,
                }
            )
        )
    return pd.concat(pieces, ignore_index=True), list(sheet_map.values())


def clean_trial90() -> tuple[pd.DataFrame, list[str]]:
    mpr_path = read_source("trial90", "12913_2016_1384_MOESM2_ESM.xlsx")
    dppr_path = read_source("trial90", "12913_2016_1384_MOESM3_ESM.xlsx")
    mpr = pd.read_excel(mpr_path, sheet_name="Tabelle1")
    dppr = pd.read_excel(dppr_path, sheet_name="Tabelle1")
    mpr["MPR_percent"] = safe_numeric_series(mpr["MPR"]) * 100.0
    agg = (
        mpr.groupby("Pat ID")
        .agg(
            X_mpr_medication_count=("MPR_percent", "count"),
            YS_mpr_mean_percent=("MPR_percent", "mean"),
            X_mpr_percent_sum=("MPR_percent", "sum"),
            X_mpr_percent_sumsq=("MPR_percent", lambda x: float(np.square(x).sum())),
        )
        .reset_index()
    )
    out = dppr.merge(agg, on="Pat ID", how="left")
    out = pd.DataFrame(
        {
            "Treatment": out["Study group"],
            "X_source_patient_id": out["Pat ID"],
            "X_gender": out["Gender"],
            "X_study_region": out["Study region"],
            "X_mpr_medication_count": out["X_mpr_medication_count"],
            "X_mpr_percent_sum": out["X_mpr_percent_sum"],
            "X_mpr_percent_sumsq": out["X_mpr_percent_sumsq"],
            "YP_dppr_percent": safe_numeric_series(out["DPPR"]) * 100.0,
            "YS_mpr_mean_percent": out["YS_mpr_mean_percent"],
        }
    )
    return out, ["Control", "Intervention"]


def clean_trial91() -> tuple[pd.DataFrame, list[str]]:
    path = read_source("trial91", "12884_2017_1545_MOESM2_ESM.xls")
    try:
        df = pd.read_excel(path, sheet_name=0, engine="xlrd")
    except ImportError as exc:
        raise RuntimeError(
            "Reading trial91 requires xlrd. Install with "
            "`python3 -m pip install xlrd --target /private/tmp/codex_xlrd_manual_trials`."
        ) from exc
    tr_col = "stichting 1=monocryl 2 =vicryl"
    df = df[df[tr_col].isin([1, 2])].copy()
    out = pd.DataFrame(
        {
            "Treatment": factor_map(df[tr_col], {2: "Vicryl Rapide", 1: "Monocryl"}),
            "X_source_research_number": df["research number.1"],
            "X_maternal_age_years": safe_numeric_series(df["maternal age"]),
            "X_ethnicity": df[
                "etnicity (C= Caucasian, B= Black, H = hindu, M = Mediterenean, A = Asian)"
            ],
            "X_operative_delivery": df["operative delivery ( V= Ventouse)"],
            "YS_vas_sitting_24h": safe_numeric_series(df["VAS 24 hrs sitting"]),
            "YS_vas_walking_24h": safe_numeric_series(df["VAS 24 hrs walking"]),
            "YS_vas_lying_24h": safe_numeric_series(df["VAS 24 hrs lying"]),
            "YS_analgesia_24h": safe_numeric_series(df["analgesia 24 hrs"]),
            "YS_dehiscence_24h": safe_numeric_series(df["dehiscence 24 hrs"]),
            "YP_vas_sitting_10d": safe_numeric_series(df["VAS 10 days sitting"]),
            "YS_vas_walking_10d": safe_numeric_series(df["VAS 10 days walking"]),
            "YS_vas_lying_10d": safe_numeric_series(df["VAS 10 days lying"]),
            "YS_analgesia_10d": safe_numeric_series(df["analgesia 10 days"]),
            "YS_infection_10d": safe_numeric_series(df["infection 10 days"]),
            "YS_suture_removal_10d": safe_numeric_series(df["suture removal 10 days"]),
            "YS_dehiscence_10d": safe_numeric_series(df["dehiscence 10 days"]),
            "YS_vas_sitting_6w": safe_numeric_series(df["VAS 6 weeks sitting"]),
            "YS_vas_walking_6w": safe_numeric_series(df["VAS 6 weeks walking"]),
            "YS_vas_lying_6w": safe_numeric_series(df["VAS 6 weeks lying"]),
            "YS_vas_sitting_3m": safe_numeric_series(df["VAS 3 months sitting"]),
            "YS_vas_walking_3m": safe_numeric_series(df["VAS 3 months walking"]),
            "YS_vas_lying_3m": safe_numeric_series(df["VAS 3 months lying"]),
            "YS_dehiscence_3m": safe_numeric_series(df["dehiscence within 3 months"]),
            "YS_stitches_removed_3m": safe_numeric_series(df["stitches removed within 3 months"]),
            "YS_infection_3m": safe_numeric_series(df["infection within 3 months"]),
        }
    )
    return out, ["Vicryl Rapide", "Monocryl"]


def clean_trial92() -> tuple[pd.DataFrame, list[str]]:
    path = read_source("trial92", "12936_2021_3586_MOESM1_ESM.xlsx")
    df = pd.read_excel(path, sheet_name="Sheet1")
    live_birth = df["PREG_OUTCOME"].map({"Livebirth": 1.0, "Stillbirth": 0.0})
    birth_weight = safe_numeric_series(df["BIRTH_WEIGHT"])
    out = pd.DataFrame(
        {
            "Treatment": factor_map(df["GROUP"], {"CONTROL": "Control", "INTERVENTION": "Intervention"}),
            "X_source_sno": df["SNO"],
            "X_age_years": df["AGE"],
            "X_ethnicity": df["ETHNICITY"],
            "X_marital_status": df["MARITAL"],
            "X_family_type": df["FAM_TYPE"],
            "X_residency": df["RESIDENCY"],
            "X_education": df["EDUCATION"],
            "X_employment": df["EMPLOYMENT"],
            "X_income": df["INCOME"],
            "X_age_at_marriage": df["AGE_MARRIAGE"],
            "X_gravidity": df["GRAVIDITY"],
            "X_parity": df["PARITY"],
            "X_amenorrhoea_months": df["Amenorrohoea"],
            "X_preterm_history": df["Preterm_Hx"],
            "X_miscarriage_history": df["Miscarriage_Hx"],
            "X_itn_use_baseline": df["Bas_ITN"],
            "YS_itn_use_2m": df["F1_ITN"],
            "YP_itn_use_4m": df["F2_ITN"],
            "X_ipt_doses_baseline": df["Bas_IPT"],
            "YS_ipt_doses_2m": df["F1_IPT"],
            "YP_ipt_doses_4m": df["F2_IPT"],
            "X_pcv_baseline": df["Bas_PCV"],
            "YS_pcv_2m": df["F1_PCV"],
            "X_malaria_diagnosis_baseline": df["Bas_Malaria"],
            "YS_malaria_diagnosis_2m": df["F1_Malaria"],
            "YS_malaria_diagnosis_4m": df["F2_Malaria"],
            "YS_live_birth": live_birth,
            "YS_birth_weight_kg": birth_weight,
            "YS_low_birth_weight": (birth_weight < 2.5).where(birth_weight.notna()).astype(float),
        }
    )
    return out, ["Control", "Intervention"]


def clean_trial93() -> tuple[pd.DataFrame, list[str]]:
    path = read_source("trial93", "PACT_30March2012.tab")
    df = pd.read_csv(path, sep="\t", low_memory=False)
    df = df[df["treated_ate"].notna()].copy()

    adhered = pd.Series(np.nan, index=df.index)
    adhered[df["p35_finishdose"].eq(1)] = 1.0
    adhered[df["p35_finishdose"].eq(2)] = 0.0
    still = pd.Series(np.nan, index=df.index)
    still[df["m1_symptoms"].eq(1)] = 1.0
    still[df["m1_symptoms"].eq(2)] = 0.0
    pills = safe_numeric_series(df["p33_left"])
    pills_obs = pills.copy()
    pills_obs[(pills_obs < 0) | (pills_obs > 50)] = np.nan
    pills_obs[(pills_obs > 0) & (pills_obs < 50)] = 1.0
    pills_obs[pills_obs == 0] = 0.0
    act_stock = pd.Series(np.nan, index=df.index)
    act_stock[df["k4_drugsACTs"].eq(0)] = 0.0
    act_stock[(df["k4_drugsACTs"] > 0) & (df["k4_drugsACTs"] < 15)] = 1.0
    act_stock[df["k1_drugshave"].eq(2)] = 0.0
    act_stock[df["k2_drugsshow"].eq(2)] = np.nan

    treatment = np.where(
        df["treated_ate"].eq(0),
        "Control",
        np.where(df["message"].eq(1), "Reminder plus information", "Reminder only"),
    )
    out = pd.DataFrame(
        {
            "Treatment": treatment,
            "X_source_id": df["ID"],
            "X_any_sms": df["treated_ate"],
            "X_message_long": df["message"],
            "X_itt_treated": df["_treated_itt"],
            "X_patient_age_reported": df.get("b2_age"),
            "X_patient_age_followup": df.get("h3_respage"),
            "X_patient_age_proxy": df.get("j2_patage"),
            "X_household_head_male": df.get("b5_HHhead_male"),
            "X_household_head_education": df.get("b7_ed_HHhead"),
            "X_household_rooms": df.get("b11_HHrooms"),
            "X_sleep_under_net": df.get("b12a_HHsleep_net"),
            "X_mobile_phones": df.get("b16_HHmobiles"),
            "X_air_conditioner": df.get("b17_HHac"),
            "X_drug_code": df.get("b4_drugcode_1"),
            "X_vendor_code": df.get("y4_vendcode"),
            "YP_adhered_self_report": adhered,
            "YS_still_sick_followup": still,
            "YS_pills_remaining_observed": pills_obs,
            "YS_act_stock_in_household": act_stock,
        }
    )
    return out, ["Control", "Reminder only", "Reminder plus information"]


def clean_trial94() -> tuple[pd.DataFrame, list[str]]:
    path = read_source("trial94", "txoutcomeandbaselinedata_3ie.tab")
    df = pd.read_csv(path, sep="\t", low_memory=False)
    out = pd.DataFrame(
        {
            "Treatment": factor_map(df["zindagi"], {0: "Control", 1: "Zindagi SMS"}),
            "X_source_patient_id": df["patientid"],
            "X_sex": df["sex"],
            "X_age_years": df["age"],
            "X_mother_tongue": df["mother_tongue"],
            "X_urdu": df["urdu"],
            "X_mobile_phone_owner": df["mobown"],
            "X_regimen_type": df["regimentype"],
            "X_can_read": df["canread"],
            "X_can_write": df["canwrite"],
            "X_school": df["school"],
            "X_highest_grade": df["highestgrade"],
            "X_marital_status": df["marstat"],
            "X_children": df["children"],
            "X_asset_index": df["assetindex"],
            "X_clinic_category": df["cliniccat"],
            "X_days_first_treatment": df["daysfirsttreat"],
            "YP_clinical_treatment_success": df["success"],
            "YS_clinical_treatment_complete": df["txcomplete"],
            "YS_clinical_cured": df["cured"],
            "YS_clinical_default": df["default"],
            "YS_clinical_died": df["died"],
            "YS_clinical_failure": df["fail"],
            "YS_clinical_transfer_out": df["transfer"],
            "YS_self_reported_success": df["selfsuccess"],
            "YS_self_reported_complete": df["selfcomplete"],
        }
    )
    return out, ["Control", "Zindagi SMS"]


def clean_trial95() -> tuple[pd.DataFrame, list[str]]:
    path = read_source("trial95", "Anonymised_Data_LaMaTuPe_2024-01-23.xlsx")
    df = pd.read_excel(path, sheet_name="Datensatz LaMaTuPe")
    df = df[df["Studienarm"].notna()].copy()
    time_raw = df["Insertionszeit"]
    time_numeric = pd.to_numeric(time_raw, errors="coerce")
    out = pd.DataFrame(
        {
            "Treatment": factor_map(df["Studienarm"], {1: "Laryngeal mask", 2: "Laryngeal tube"}),
            "X_dataset_status": df["Datensatz"],
            "X_age_years": df["Alter in Jahren"],
            "X_age_group": df["Altersgruppe"],
            "X_sex_code": df["Geschlecht"],
            "X_height_cm": df["Körpergröße"],
            "X_weight_kg": df["Gewicht"],
            "X_asa_status": df["ASA"],
            "X_mallampati": df["Mallampati"],
            "X_surgical_procedure": df["Eingriffsart"],
            "X_treatment_department": df["operierende Fachabteilung"],
            "X_expected_size": df["erwartete Größe"],
            "X_used_size": df["verwendete Größe"],
            "X_insertion_time_raw": time_raw,
            "YP_insertion_time_sec": time_numeric,
            "YS_first_pass_success": df["First-Pass-Success"],
            "YS_overall_success": df["Overall-pass-success"],
            "YS_insertion_success_code": df["Insertionserfolg"],
            "YS_crossover": pd.to_numeric(
                df["Verfahrenswechsel"].replace({"Ja - LT": 1}), errors="coerce"
            ),
            "YS_attempt_count": df["Anzahl Versuche"],
            "YS_leakage_pressure_cmH2O": df["Leckagedruck"],
            "YS_postop_complication": df["Komplikationen postop"],
            "YS_postop_throat_pain": df["Schmerzen Mund-Rachenraum postop"],
            "X_anesthesiologist_experience_years": df["Berufserfahrung"],
        }
    )
    return out, ["Laryngeal mask", "Laryngeal tube"]


CLEANERS: dict[str, Callable[[], tuple[pd.DataFrame, list[str]]]] = {
    "trial87": clean_trial87,
    "trial88": clean_trial88,
    "trial89": clean_trial89,
    "trial90": clean_trial90,
    "trial91": clean_trial91,
    "trial92": clean_trial92,
    "trial93": clean_trial93,
    "trial94": clean_trial94,
    "trial95": clean_trial95,
}


def paper_tolerance(paper_value: float) -> float:
    return abs(float(paper_value)) * 0.05


def audit_row(
    rows: list[dict],
    trial_id: str,
    outcome_variable: str,
    role: str,
    arm: str,
    statistic: str,
    paper_value: float,
    cleaned_value: float,
    source: str,
    notes: str = "",
    precision: str = "",
) -> None:
    if cleaned_value is None or (isinstance(cleaned_value, float) and math.isnan(cleaned_value)):
        diff = np.nan
        status = "fail"
    else:
        diff = abs(float(cleaned_value) - float(paper_value))
        status = "pass" if diff <= paper_tolerance(paper_value) + 1e-9 else "fail"
    rows.append(
        {
            "Trial_ID": trial_id,
            "outcome_variable": outcome_variable,
            "outcome_role": role,
            "arm": arm,
            "statistic": statistic,
            "paper_value": paper_value,
            "paper_precision": precision,
            "cleaned_value": cleaned_value,
            "absolute_diff": diff,
            "tolerance": paper_tolerance(paper_value),
            "status": status,
            "paper_source": source,
            "notes": notes,
        }
    )


def add_mean_sd_audit(
    rows: list[dict],
    df: pd.DataFrame,
    trial_id: str,
    var: str,
    role: str,
    source: str,
    paper: dict[str, tuple[float, float]],
    notes: str = "",
) -> None:
    for arm, (paper_mean, paper_sd) in paper.items():
        series = safe_numeric_series(df.loc[df["Treatment"].eq(arm), var]).dropna()
        audit_row(rows, trial_id, var, role, arm, "mean", paper_mean, series.mean(), source, notes)
        audit_row(rows, trial_id, var, role, arm, "sd", paper_sd, series.std(ddof=1), source, notes)


def add_count_audit(
    rows: list[dict],
    df: pd.DataFrame,
    trial_id: str,
    var: str,
    role: str,
    source: str,
    paper: dict[str, float],
    notes: str = "",
) -> None:
    for arm, paper_count in paper.items():
        cleaned = safe_numeric_series(df.loc[df["Treatment"].eq(arm), var]).sum(skipna=True)
        audit_row(rows, trial_id, var, role, arm, "event_count", paper_count, cleaned, source, notes)


def build_audit(cleaned: dict[str, pd.DataFrame]) -> tuple[pd.DataFrame, pd.DataFrame]:
    rows: list[dict] = []

    t87 = cleaned["trial87"]
    add_mean_sd_audit(
        rows,
        t87,
        "trial87",
        "YP_delta_mbp_mmHg",
        "primary",
        "BMC Anesthesiology 2016 Table 2",
        {"Fentanyl": (12.63, 16.76), "Oxycodone": (5.51, 18.29)},
    )
    add_mean_sd_audit(
        rows,
        t87,
        "trial87",
        "YP_delta_hr_bpm",
        "primary",
        "BMC Anesthesiology 2016 Table 2",
        {"Fentanyl": (18.47, 13.74), "Oxycodone": (18.71, 16.84)},
        notes="The Oxycodone source sheet has missing HR delta values; Fentanyl reproduces exactly and Oxycodone SD remains within tolerance.",
    )
    for arm, paper_med in {"Fentanyl": 5.0, "Oxycodone": 3.0}.items():
        vals = safe_numeric_series(t87.loc[t87["Treatment"].eq(arm), "YP_postoperative_pain_vas"]).dropna()
        audit_row(
            rows,
            "trial87",
            "YP_postoperative_pain_vas",
            "primary",
            arm,
            "median",
            paper_med,
            vals.median(),
            "BMC Anesthesiology 2016 Table 2",
        )
    add_count_audit(
        rows,
        t87,
        "trial87",
        "YS_rescue_analgesic",
        "secondary",
        "BMC Anesthesiology 2016 Table 2",
        {"Fentanyl": 17, "Oxycodone": 9},
    )

    t88 = cleaned["trial88"]
    add_count_audit(
        rows,
        t88,
        "trial88",
        "YP_death_1y",
        "primary",
        "BMC Nutrition 2016 Table 2",
        {"Nutrition education": 5, "Control": 7},
    )
    for var, paper in {
        "YS_ami_1y": {"Nutrition education": 5, "Control": 6},
        "YS_repeat_pci_1y": {"Nutrition education": 4, "Control": 6},
        "YS_cabg_1y": {"Nutrition education": 4, "Control": 4},
        "YS_composite_event_1y": {"Nutrition education": 11, "Control": 13},
    }.items():
        add_count_audit(rows, t88, "trial88", var, "secondary", "BMC Nutrition 2016 Table 2", paper)

    t89 = cleaned["trial89"]
    add_mean_sd_audit(
        rows,
        t89,
        "trial89",
        "X_moca_enrollment",
        "baseline_primary",
        "BMC Complement Altern Med 2016 Table 2",
        {
            "Nimodipine alone": (21.1, 4.3),
            "Acupuncture alone": (21.8, 3.5),
            "Nimodipine + acupuncture": (20.5, 3.9),
        },
    )
    add_mean_sd_audit(
        rows,
        t89,
        "trial89",
        "YP_moca_3m",
        "primary",
        "BMC Complement Altern Med 2016 Table 2",
        {
            "Nimodipine alone": (23.5, 4.6),
            "Acupuncture alone": (25.4, 4.1),
            "Nimodipine + acupuncture": (24.5, 3.3),
        },
    )
    add_mean_sd_audit(
        rows,
        t89,
        "trial89",
        "YS_moca_followup_6m",
        "secondary",
        "BMC Complement Altern Med 2016 Table 2",
        {
            "Nimodipine alone": (24.2, 4.6),
            "Acupuncture alone": (26.1, 3.6),
            "Nimodipine + acupuncture": (26.0, 2.8),
        },
    )

    t90 = cleaned["trial90"]
    add_mean_sd_audit(
        rows,
        t90,
        "trial90",
        "YP_dppr_percent",
        "primary",
        "BMC Health Services Research 2016 Table 6",
        {"Intervention": (88.0, 13.31), "Control": (87.5, 20.75)},
        notes="DPPR is participant-level in the source file.",
    )
    for arm, mean_paper, sd_paper in [
        ("Intervention", 88.3, 19.03),
        ("Control", 87.5, 20.75),
    ]:
        sub = t90.loc[t90["Treatment"].eq(arm)]
        n = safe_numeric_series(sub["X_mpr_medication_count"]).sum()
        total = safe_numeric_series(sub["X_mpr_percent_sum"]).sum()
        total_sq = safe_numeric_series(sub["X_mpr_percent_sumsq"]).sum()
        mean = total / n
        sd = math.sqrt((total_sq - n * mean * mean) / (n - 1))
        audit_row(
            rows,
            "trial90",
            "YS_mpr_mean_percent",
            "primary_supporting",
            arm,
            "medication_row_weighted_mean",
            mean_paper,
            mean,
            "BMC Health Services Research 2016 Table 5",
            "Weighted from compact participant-level MPR sum/count components.",
        )
        audit_row(
            rows,
            "trial90",
            "YS_mpr_mean_percent",
            "primary_supporting",
            arm,
            "medication_row_weighted_sd",
            sd_paper,
            sd,
            "BMC Health Services Research 2016 Table 5",
            "Weighted from compact participant-level MPR sum/count/sumsq components.",
        )

    t91 = cleaned["trial91"]
    add_mean_sd_audit(
        rows,
        t91,
        "trial91",
        "YP_vas_sitting_10d",
        "primary",
        "BMC Pregnancy and Childbirth 2017 Table 3",
        {"Monocryl": (2.8, 2.5), "Vicryl Rapide": (2.5, 2.1)},
        notes="Publication reports n=64/67; cleaned nonmissing primary rows are audited separately.",
    )
    for arm, paper_n in {"Monocryl": 64, "Vicryl Rapide": 67}.items():
        cleaned_n = safe_numeric_series(t91.loc[t91["Treatment"].eq(arm), "YP_vas_sitting_10d"]).notna().sum()
        audit_row(
            rows,
            "trial91",
            "YP_vas_sitting_10d",
            "primary",
            arm,
            "nonmissing_n",
            paper_n,
            cleaned_n,
            "BMC Pregnancy and Childbirth 2017 Table 3",
            "Count mismatch retained as a source-data limitation; means/SDs reproduce within tolerance.",
        )

    t92 = cleaned["trial92"]
    for arm, counts in {
        "Intervention": {1: 30, 2: 8, 3: 28, 4: 39, 5: 34},
        "Control": {1: 35, 2: 22, 3: 24, 4: 22, 5: 25},
    }.items():
        for category, paper_count in counts.items():
            cleaned_count = (t92.loc[t92["Treatment"].eq(arm), "YP_itn_use_4m"] == category).sum()
            audit_row(
                rows,
                "trial92",
                "YP_itn_use_4m",
                "primary",
                f"{arm}: category {category}",
                "category_count",
                paper_count,
                cleaned_count,
                "Malaria Journal 2021 Table 4",
                "ITN categories: 1 never, 2 seldom, 3 sometimes, 4 often, 5 almost always.",
            )
    for arm, counts in {
        "Intervention": {0: 6, 1: 20, 2: 82, 3: 31},
        "Control": {0: 10, 1: 47, 2: 62, 3: 9},
    }.items():
        for category, paper_count in counts.items():
            cleaned_count = (t92.loc[t92["Treatment"].eq(arm), "YP_ipt_doses_4m"] == category).sum()
            audit_row(
                rows,
                "trial92",
                "YP_ipt_doses_4m",
                "primary",
                f"{arm}: category {category}",
                "category_count",
                paper_count,
                cleaned_count,
                "Malaria Journal 2021 Table 4",
                "IPTp categories are reported number of doses by four months.",
            )

    t93 = cleaned["trial93"]
    for arm, paper_pct in {
        "Control": 61.5,
        "Any reminder": 66.4,
        "Reminder plus information": 64.1,
    }.items():
        if arm == "Any reminder":
            mask = t93["X_any_sms"].eq(1)
        else:
            mask = t93["Treatment"].eq(arm)
        vals = safe_numeric_series(t93.loc[mask, "YP_adhered_self_report"]).dropna()
        audit_row(
            rows,
            "trial93",
            "YP_adhered_self_report",
            "primary",
            arm,
            "percent",
            paper_pct,
            vals.mean() * 100.0,
            "PLOS ONE 2014 Table 2",
            "Any reminder corresponds to treated_ate=1 in the authors' Stata code.",
        )
    for arm, paper_n in {"Control": 538, "Any reminder": 572, "Reminder plus information": 304}.items():
        if arm == "Any reminder":
            mask = t93["X_any_sms"].eq(1)
        else:
            mask = t93["Treatment"].eq(arm)
        cleaned_n = safe_numeric_series(t93.loc[mask, "YP_adhered_self_report"]).notna().sum()
        audit_row(
            rows,
            "trial93",
            "YP_adhered_self_report",
            "primary",
            arm,
            "nonmissing_n",
            paper_n,
            cleaned_n,
            "PLOS ONE 2014 Table 2",
        )

    t94 = cleaned["trial94"]
    add_count_audit(
        rows,
        t94,
        "trial94",
        "YP_clinical_treatment_success",
        "primary",
        "PLOS ONE 2016 Table 2",
        {"Zindagi SMS": 917, "Control": 903},
    )
    for arm, paper_pct in {"Zindagi SMS": 83.0, "Control": 83.0}.items():
        vals = safe_numeric_series(t94.loc[t94["Treatment"].eq(arm), "YP_clinical_treatment_success"]).dropna()
        audit_row(
            rows,
            "trial94",
            "YP_clinical_treatment_success",
            "primary",
            arm,
            "percent",
            paper_pct,
            vals.mean() * 100.0,
            "PLOS ONE 2016 Table 2",
            "Publication rounds percentages to whole numbers.",
        )
    for var, paper in {
        "YS_clinical_treatment_complete": {"Zindagi SMS": 332, "Control": 325},
        "YS_clinical_cured": {"Zindagi SMS": 585, "Control": 578},
        "YS_clinical_default": {"Zindagi SMS": 108, "Control": 103},
        "YS_clinical_died": {"Zindagi SMS": 19, "Control": 19},
        "YS_clinical_failure": {"Zindagi SMS": 27, "Control": 29},
        "YS_clinical_transfer_out": {"Zindagi SMS": 33, "Control": 39},
    }.items():
        add_count_audit(rows, t94, "trial94", var, "secondary", "PLOS ONE 2016 Table 2", paper)

    t95 = cleaned["trial95"]
    for arm, paper_median in {"Laryngeal mask": 31.0, "Laryngeal tube": 37.0}.items():
        vals = safe_numeric_series(t95.loc[t95["Treatment"].eq(arm), "YP_insertion_time_sec"]).dropna()
        audit_row(
            rows,
            "trial95",
            "YP_insertion_time_sec",
            "primary",
            arm,
            "median",
            paper_median,
            vals.median(),
            "European Journal of Emergency Medicine 2025 Table 2",
            "Compound free-text timing cells are retained in X_insertion_time_raw and excluded from this compact numeric audit.",
        )

    audit = pd.DataFrame(rows)
    targets = audit[
        [
            "Trial_ID",
            "outcome_variable",
            "outcome_role",
            "arm",
            "statistic",
            "paper_value",
            "paper_precision",
            "paper_source",
            "notes",
        ]
    ].copy()
    return targets, audit


def build_publication_review() -> pd.DataFrame:
    rows = []
    for trial in TRIALS:
        rows.append(
            {
                "Trial_ID": trial.trial_id,
                "Candidate_IDs": "; ".join(trial.candidate_ids),
                "Title": trial.title,
                "Repository": trial.repository,
                "Dataset_DOI": trial.dataset_doi,
                "Publication_DOI": trial.publication_doi,
                "Publication_Source": trial.publication_source,
                "Primary_Outcome": trial.primary_outcome,
                "Primary_Outcome_Type": trial.primary_type,
                "Treatment_Arms": trial.treatment_arms,
                "Control_Group": trial.control_group,
                "Statistical_Model": trial.statistical_model,
                "Randomization_Scheme": trial.randomization_scheme,
                "Randomization_Scheme_High_Level": "Individual randomization",
                "Research_Area": trial.research_area,
                "Covariate_Source": trial.covariate_source,
                "Publication_Review_Status": "reviewed",
                "Qualified_After_Publication_Review": "yes",
                "Review_Notes": trial.review_notes,
                "License_Notes": trial.license_notes,
                "Source_Files": "; ".join(f"{cid}/{fname}" for cid, fname in trial.source_files),
            }
        )
    return pd.DataFrame(rows)


def build_metadata(cleaned: dict[str, pd.DataFrame]) -> pd.DataFrame:
    journal_year = {
        "trial87": ("BMC Anesthesiology", 2016, "Mixed: pain significant; hemodynamic deltas not significant"),
        "trial88": ("BMC Nutrition", 2016, "No"),
        "trial89": ("BMC Complementary and Alternative Medicine", 2016, "Yes"),
        "trial90": ("BMC Health Services Research", 2016, "No"),
        "trial91": ("BMC Pregnancy and Childbirth", 2017, "No"),
        "trial92": ("Malaria Journal", 2021, "Yes"),
        "trial93": ("PLOS ONE", 2014, "Yes"),
        "trial94": ("PLOS ONE", 2016, "No"),
        "trial95": ("European Journal of Emergency Medicine", 2025, "Yes"),
    }
    rows = []
    for trial in TRIALS:
        journal, year, success = journal_year[trial.trial_id]
        rows.append(
            {
                "Trial_ID": trial.trial_id,
                "Trial Number/Name": trial.title,
                "Paper Name": trial.title,
                "Journal": journal,
                "Paper Link": f"https://doi.org/{trial.publication_doi}",
                "Publication Year": year,
                "# of Arm": len(cleaned[trial.trial_id]["Treatment"].cat.categories)
                if isinstance(cleaned[trial.trial_id]["Treatment"].dtype, pd.CategoricalDtype)
                else len(cleaned[trial.trial_id]["Treatment"].dropna().unique()),
                "Control Group": trial.control_group,
                "Study Phase": "Not applicable / not reported",
                "Sample Size": len(cleaned[trial.trial_id]),
                "Priamry Outcome": trial.primary_outcome,
                "Primary Outcome Type": trial.primary_type,
                "Trial Success(Primary Outcome Significant)": success,
                "Statistical Model": trial.statistical_model,
                "Randomization Scheme": trial.randomization_scheme,
                "Randomization Scheme(High Level)": "Individual randomization",
                "Research Area": trial.research_area,
                "Text Data": "No",
                "Citation": f"{trial.title}. {journal} ({year}). doi:{trial.publication_doi}",
            }
        )
    columns = [
        "Trial_ID",
        "Trial Number/Name",
        "Paper Name",
        "Journal",
        "Paper Link",
        "Publication Year",
        "# of Arm",
        "Control Group",
        "Study Phase",
        "Sample Size",
        "Priamry Outcome",
        "Primary Outcome Type",
        "Trial Success(Primary Outcome Significant)",
        "Statistical Model",
        "Randomization Scheme",
        "Randomization Scheme(High Level)",
        "Research Area",
        "Text Data",
        "Citation",
    ]
    return pd.DataFrame(rows, columns=columns)


def explain_variable(name: str) -> tuple[str, str]:
    custom = {
        "Treatment": ("treatment", "Randomized treatment assignment with the control/reference arm first when identifiable."),
        "YP_delta_mbp_mmHg": ("primary_outcome", "Change in mean blood pressure after intubation, mmHg."),
        "YP_delta_hr_bpm": ("primary_outcome", "Change in heart rate after intubation, beats per minute."),
        "YP_postoperative_pain_vas": ("primary_outcome", "Postoperative pain score in PACU."),
        "YP_death_1y": ("primary_outcome", "Death by one-year follow-up."),
        "YP_moca_3m": ("primary_outcome", "MoCA score after three months of therapy."),
        "YP_delta_moca_3m": ("primary_outcome", "Change in MoCA from enrollment to three months."),
        "YP_dppr_percent": ("primary_outcome", "Daily polypharmacy possession ratio as a percent."),
        "YP_vas_sitting_10d": ("primary_outcome", "VAS pain while sitting at ten days."),
        "YP_itn_use_4m": ("primary_outcome", "Reported ITN use category four months post-intervention."),
        "YP_ipt_doses_4m": ("primary_outcome", "Reported IPTp dose count four months post-intervention."),
        "YP_adhered_self_report": ("primary_outcome", "Self-reported completion of ACT antimalarial treatment."),
        "YP_clinical_treatment_success": ("primary_outcome", "Clinically recorded tuberculosis treatment success."),
        "YP_insertion_time_sec": ("primary_outcome", "Supraglottic airway insertion time in seconds."),
    }
    if name in custom:
        return custom[name]
    if name.startswith("YP_"):
        return "primary_outcome", name[3:].replace("_", " ")
    if name.startswith("YS_"):
        return "secondary_outcome", name[3:].replace("_", " ")
    if name.startswith("X_"):
        return "baseline_covariate", name[2:].replace("_", " ")
    return "identifier_or_auxiliary", name.replace("_", " ")


def build_dictionary(cleaned: dict[str, pd.DataFrame]) -> pd.DataFrame:
    rows = []
    for trial_id, df in cleaned.items():
        for col in df.columns:
            var_type, explanation = explain_variable(col)
            rows.append(
                {
                    "Trial_ID": trial_id,
                    "variable_name": col,
                    "variable_type": var_type,
                    "brief_explanation": explanation,
                }
            )
    return pd.DataFrame(rows)


def validation_summary(cleaned: dict[str, pd.DataFrame]) -> pd.DataFrame:
    rows = []
    for trial_id, df in cleaned.items():
        y_cols = [c for c in df.columns if c.startswith("YP_")]
        dup_cols = df.columns[df.columns.duplicated()].tolist()
        exact_dupes = df.T.duplicated().sum()
        if isinstance(df["Treatment"].dtype, pd.CategoricalDtype):
            treatment_levels = [str(x) for x in df["Treatment"].cat.categories.tolist()]
        else:
            treatment_levels = [str(x) for x in df["Treatment"].dropna().unique().tolist()]
        rows.append(
            {
                "Trial_ID": trial_id,
                "n_rows": len(df),
                "n_columns": df.shape[1],
                "treatment_levels": "; ".join(treatment_levels),
                "n_treatment_levels": len(treatment_levels),
                "has_treatment": "yes" if "Treatment" in df.columns else "no",
                "yp_columns": "; ".join(y_cols),
                "n_yp_columns": len(y_cols),
                "has_primary_outcome": "yes" if y_cols else "no",
                "duplicate_column_names": "; ".join(dup_cols),
                "exact_duplicate_column_count": int(exact_dupes),
                "csv_exists": "yes" if (CLEAN_DIR / f"{trial_id}.csv").exists() else "no",
                "rds_exists": "yes" if (CLEAN_DIR / f"{trial_id}.rds").exists() else "no",
            }
        )
    return pd.DataFrame(rows)


def write_csv(path: Path, df: pd.DataFrame) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    df.to_csv(path, index=False, quoting=csv.QUOTE_MINIMAL)


def main() -> int:
    RAW_DIR.mkdir(parents=True, exist_ok=True)
    CLEAN_DIR.mkdir(parents=True, exist_ok=True)
    PROV_DIR.mkdir(parents=True, exist_ok=True)
    META_DIR.mkdir(parents=True, exist_ok=True)

    copy_log = copy_sources()
    cleaned: dict[str, pd.DataFrame] = {}
    for trial in TRIALS:
        df, levels = CLEANERS[trial.trial_id]()
        cleaned[trial.trial_id] = write_cleaned(trial.trial_id, df, levels)

    targets, audit = build_audit(cleaned)
    write_csv(PROV_DIR / "manual_trials87_95_raw_copy_log.csv", pd.DataFrame(copy_log))
    write_csv(PROV_DIR / "publication_review_manual_trials87_95.csv", build_publication_review())
    write_csv(PROV_DIR / "outcome_reproducibility_targets_manual_trials87_95.csv", targets)
    write_csv(PROV_DIR / "outcome_reproducibility_audit_manual_trials87_95.csv", audit)
    write_csv(PROV_DIR / "validation_summary_manual_trials87_95.csv", validation_summary(cleaned))
    write_csv(META_DIR / "data_dictionary_manual_trials87_95.csv", build_dictionary(cleaned))
    metadata = build_metadata(cleaned)
    write_csv(META_DIR / "meta_data_manual_trials87_95.csv", metadata)
    metadata.to_excel(META_DIR / "meta_data_manual_trials87_95.xlsx", index=False)

    print("Cleaned trials:", ", ".join(sorted(cleaned)))
    print("Audit rows:", len(audit), "pass:", int((audit["status"] == "pass").sum()), "fail:", int((audit["status"] == "fail").sum()))
    print(PROV_DIR / "outcome_reproducibility_audit_manual_trials87_95.csv")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
