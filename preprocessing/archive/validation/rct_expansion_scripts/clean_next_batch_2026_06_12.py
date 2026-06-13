#!/usr/bin/env python3
"""Clean source-verified next-batch trials into active expansion slots.

This script only promotes candidates with participant-level data and verified
primary-publication metadata. It writes cleaned CSVs plus metadata/provenance
inputs consumed by cleanup_expansion_folder.py.
"""

from __future__ import annotations

import re
import shutil
from pathlib import Path

import pandas as pd
from pandas.api.types import is_numeric_dtype


ROOT = Path(__file__).resolve().parents[2]
EXP = ROOT / "rct_expansion"
PROV = EXP / "provenance"
SRC = PROV / "next_batch_2026_06_12" / "source_verification" / "downloads"
CLEAN = EXP / "cleaned_data"
RAW = EXP / "raw_data"
META = EXP / "metadata"
PUB = EXP / "publications"


def clean_name(value: str) -> str:
    value = value.strip().lower()
    value = value.replace("%", "percent")
    value = re.sub(r"[^a-z0-9]+", "_", value)
    return re.sub(r"_+", "_", value).strip("_")


def numeric(series: pd.Series) -> pd.Series:
    return pd.to_numeric(series, errors="coerce")


def numeric_unit(series: pd.Series) -> pd.Series:
    return pd.to_numeric(series.astype(str).str.extract(r"([-+]?\d+(?:\.\d+)?)", expand=False), errors="coerce")


def covariate(series: pd.Series) -> pd.Series:
    if is_numeric_dtype(series):
        return numeric(series)
    return series.astype("string").str.strip().replace({"": pd.NA})


def copy_raw(trial_id: int, files: list[Path]) -> str:
    target = RAW / f"trial{trial_id}"
    target.mkdir(parents=True, exist_ok=True)
    copied = []
    for src in files:
        dest = target / src.name
        if not dest.exists():
            shutil.copy2(src, dest)
        copied.append(dest.relative_to(ROOT).as_posix())
    return "; ".join(copied)


def write_publication_record(trial_id: int, lines: list[str]) -> None:
    target = PUB / f"trial{trial_id}"
    target.mkdir(parents=True, exist_ok=True)
    (target / "publication_link.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")


def clean_endotoxemia() -> tuple[dict, dict]:
    trial_id = 122
    source = SRC / "RCTC-02326" / "12916_2025_4292_MOESM1_ESM.xlsx"
    raw_files = copy_raw(trial_id, [source])
    df = pd.read_excel(source, sheet_name="Schmidt et al Supplementary Dat")

    out = pd.DataFrame()
    out["Treatment"] = (
        "group_"
        + df["group"].astype("Int64").astype(str)
        + "_medication_"
        + df["medication"].astype("Int64").astype(str)
        + "_communication_"
        + df["communication"].astype("Int64").astype(str)
    )

    primary_map = {
        "GASE_Sickness_Score_6h": "YP_GASE_sickness_score_6h",
        "DELTA_GASE": "YP_delta_GASE_6h",
        "STADI_S_Global_6h": "YP_STADI_state_global_6h",
        "DELTA_STADI_Gesamt": "YP_delta_STADI_global_6h",
    }
    secondary_map = {
        "STADI_S_Depression_6h": "YS_STADI_state_depression_6h",
        "STADI_S_Anxiety_6h": "YS_STADI_state_anxiety_6h",
        "STAI_S_6h": "YS_STAI_state_6h",
        "KSS_6h": "YS_KSS_sleepiness_6h",
        "MDBF_positive_mood_6h": "YS_MDBF_positive_mood_6h",
        "TNFa_peak_increase_3h": "YS_TNFa_peak_increase_3h",
        "IL6_peak_increase_3h": "YS_IL6_peak_increase_3h",
        "Cort_peak_increase_3h": "YS_cortisol_peak_increase_3h",
    }
    covariate_map = {
        "sex_assigned_at_birth": "X_sex_assigned_at_birth",
        "age_years": "X_age_years",
        "height_cm": "X_height_cm",
        "bodyweight_kg": "X_bodyweight_kg",
        "BMI": "X_BMI",
        "years_of_education": "X_years_of_education",
        "dummy_education_atleast_12_years": "X_education_atleast_12_years",
        "GEEE_IBU_preexperience": "X_ibuprofen_preexperience",
        "dummy_GEEE_IBU_use_within_last_12_months": "X_ibuprofen_use_last_12m",
        "STADI_T_Depression": "X_STADI_trait_depression",
        "STADI_T_Anxiety": "X_STADI_trait_anxiety",
        "STADI_T_Global": "X_STADI_trait_global",
        "GASE_Sickness_Score_BL": "X_GASE_sickness_score_0h",
        "STADI_S_Global_BLI": "X_STADI_state_global_0h",
        "STAI_S_BL": "X_STAI_state_0h",
        "KSS_BLI": "X_KSS_sleepiness_0h",
        "MDBF_positive_mood_BL": "X_MDBF_positive_mood_0h",
        "HR_BL": "X_heart_rate_0h",
        "Temp_BL": "X_temperature_0h",
        "TNFa_BL": "X_TNFa_0h",
        "IL6_BL": "X_IL6_0h",
        "Cort_Plasma_BL": "X_cortisol_0h",
    }
    for src, dest in {**primary_map, **secondary_map, **covariate_map}.items():
        out[dest] = numeric(df[src])

    out.to_csv(CLEAN / f"trial{trial_id}.csv", index=False)
    write_publication_record(
        trial_id,
        [
            "Primary publication: https://doi.org/10.1186/s12916-025-04292-8",
            "Dataset record: https://doi.org/10.6084/m9.figshare.29817847",
            "Publication PDF not downloaded by this batch; open-access link recorded.",
        ],
    )
    main = {
        "Trial_ID": trial_id,
        "Trial Number/Name": "RCTC-02326",
        "Paper Name": "Placebo effects improve sickness symptoms and drug efficacy during systemic inflammation: a randomized controlled trial in human experimental endotoxemia",
        "Journal": "BMC Medicine",
        "Paper Link": "https://doi.org/10.1186/s12916-025-04292-8",
        "Publication Year": "2025",
        "# of Arm": out["Treatment"].nunique(),
        "Control Group": "group_1_medication_1_communication_1",
        "Study Phase": "Human experimental endotoxemia randomized controlled trial",
        "Sample Size": len(out),
        "Priamry Outcome": "Bodily sickness symptoms and affective symptoms through 6 hours",
        "Primary Outcome Type": "Continuous",
        "Trial Success(Primary Outcome Significant)": "Publication reports ibuprofen and positive-labeling symptom effects",
        "Statistical Model": "Publication primary analysis; compact cleaned data provide arm-level outcomes and baseline covariates",
        "Randomization Scheme": "Randomized 2 by 2 factorial placebo design",
        "Randomization Scheme(High Level)": "Individual",
        "Research Area": "Inflammation / placebo effects",
        "Text Data": "No",
        "Citation": "Schmidt et al. Placebo effects improve sickness symptoms and drug efficacy during systemic inflammation: a randomized controlled trial in human experimental endotoxemia. BMC Medicine. 2025. doi:10.1186/s12916-025-04292-8.",
        "Issues Encountered": "Source file uses numeric medication and communication labels; cleaned Treatment preserves source-coded group labels pending exact arm-label confirmation from full methods.",
    }
    prov = {
        "Trial_ID": trial_id,
        "Repository": "figshare",
        "Dataset_DOI": "10.6084/m9.figshare.29817847",
        "License": "CC BY 4.0",
        "Download_Date": "2026-06-12",
        "Source_Files": raw_files,
        "Baseline_Covariates_Selected": "; ".join(c for c in out.columns if c.startswith("X_")),
        "Baseline_Outcome_Measurements_Included": "; ".join(c for c in out.columns if c.endswith("_0h")),
        "Covariate_Source": "Primary publication baseline and source spreadsheet baseline measures",
        "Cleaning_Notes": "Participant-level file; 2 by 2 design retained as four source-coded treatment arms.",
        "Original_Trial_ID": "",
        "Candidate_ID": "RCTC-02326",
        "License_Status": "Open figshare record, CC BY 4.0",
        "Publication_Status": "Primary publication verified via Crossref DOI",
        "Cleaning_Status": "active_cleaned",
        "Verification_Reasons": "Source verifier found participant-level spreadsheet with treatment/group assignment and outcome columns.",
    }
    return main, prov


def clean_prp() -> tuple[dict, dict]:
    trial_id = 123
    source = SRC / "RCTC-04065" / "12893_2021_1370_MOESM1_ESM.xlsx"
    raw_files = copy_raw(trial_id, [source])
    df = pd.read_excel(source, sheet_name="Sheet1")

    out = pd.DataFrame()
    out["Treatment"] = "group_" + df["group"].astype(str).str.strip()
    out["YP_wound_healing_speed_day"] = numeric(df["wound healing speed (Day)"])
    out["YS_cavity_volume_cc"] = numeric_unit(df["cavity volume"])
    for col in ["VAS1", "VAS2", "VAS3", "VAS4", "VAS5"]:
        out[f"YS_{col.lower()}"] = numeric(df[col])
    out["YS_painkiller_amount"] = numeric(df["painkiller amount"])
    out["YS_walking_time_without_pain_hour"] = numeric_unit(df["walking time without pain"])
    out["YS_pain_free_time_to_defecate_hour"] = numeric_unit(df["pain-free time to defecate"])
    out["YS_return_to_daily_activity_day"] = numeric_unit(df["the time to return to daily activity"])
    out["YS_complication_recurrence"] = numeric(df["complication/recurrence"])

    for prefix in ["SF36", "NHP"]:
        for col in df.columns:
            if col.startswith(prefix) and "-POST" in col:
                out[f"YS_{clean_name(col)}"] = numeric(df[col])
            elif col.startswith(prefix) and "-PRE" in col:
                out[f"X_{clean_name(col)}"] = numeric(df[col])

    covariates = [
        "gender",
        "age",
        "education level",
        "job",
        "smoking frequency",
        "comorbidities",
        "drug using",
        "family history of PS",
        "fraquency of changing underwear",
        "frequency of bathing",
        "cleaning hair in the gluteal area",
        "epilation in the gluteal area",
        "standing working",
        "sitting working",
        "complaint period",
        "past abscess drainage",
        "number of pits",
        "the direction of the sinuses",
    ]
    for col in covariates:
        dest = f"X_{clean_name(col)}"
        out[dest] = covariate(df[col])

    out.to_csv(CLEAN / f"trial{trial_id}.csv", index=False)
    write_publication_record(
        trial_id,
        [
            "Primary publication: https://doi.org/10.1186/s12893-021-01370-5",
            "Dataset record: https://doi.org/10.6084/m9.figshare.16841159",
            "Publication PDF not downloaded by this batch; open-access link recorded.",
        ],
    )
    main = {
        "Trial_ID": trial_id,
        "Trial Number/Name": "RCTC-04065",
        "Paper Name": "Platelet-rich plasma treatment improves postoperative recovery in patients with pilonidal sinus disease: a randomized controlled clinical trial",
        "Journal": "BMC Surgery",
        "Paper Link": "https://doi.org/10.1186/s12893-021-01370-5",
        "Publication Year": "2021",
        "# of Arm": out["Treatment"].nunique(),
        "Control Group": "group_A",
        "Study Phase": "Randomized controlled clinical trial",
        "Sample Size": len(out),
        "Priamry Outcome": "Wound healing speed in days",
        "Primary Outcome Type": "Continuous",
        "Trial Success(Primary Outcome Significant)": "Publication reports improved postoperative recovery with platelet-rich plasma",
        "Statistical Model": "Publication primary analysis; compact cleaned data provide arm-level outcomes and baseline covariates",
        "Randomization Scheme": "Randomized controlled clinical trial",
        "Randomization Scheme(High Level)": "Individual",
        "Research Area": "Surgery / wound healing",
        "Text Data": "No",
        "Citation": "Boztug et al. Platelet-rich plasma treatment improves postoperative recovery in patients with pilonidal sinus disease: a randomized controlled clinical trial. BMC Surgery. 2021. doi:10.1186/s12893-021-01370-5.",
        "Issues Encountered": "Source file uses group letters without embedded arm labels; cleaned Treatment preserves source-coded labels pending exact intervention-label confirmation from full methods.",
    }
    prov = {
        "Trial_ID": trial_id,
        "Repository": "figshare",
        "Dataset_DOI": "10.6084/m9.figshare.16841159",
        "License": "CC BY 4.0",
        "Download_Date": "2026-06-12",
        "Source_Files": raw_files,
        "Baseline_Covariates_Selected": "; ".join(c for c in out.columns if c.startswith("X_")),
        "Baseline_Outcome_Measurements_Included": "; ".join(c for c in out.columns if c.startswith("X_sf36") or c.startswith("X_nhp")),
        "Covariate_Source": "Primary publication baseline table and source spreadsheet baseline measures",
        "Cleaning_Notes": "Participant-level source spreadsheet retained with group letters as treatment arms.",
        "Original_Trial_ID": "",
        "Candidate_ID": "RCTC-04065",
        "License_Status": "Open figshare record, CC BY 4.0",
        "Publication_Status": "Primary publication verified via Crossref DOI",
        "Cleaning_Status": "active_cleaned",
        "Verification_Reasons": "Source verifier found participant-level spreadsheet with treatment/group assignment and clinical outcome columns.",
    }
    return main, prov


def clean_pfama1_vaccine() -> tuple[dict, dict]:
    trial_id = 124
    source = SRC / "RCTC-03206" / "12936_2016_1466_MOESM1_ESM.xlsx"
    raw_files = copy_raw(trial_id, [source])
    df = pd.read_excel(source, sheet_name="Dataset")
    wide = df.pivot(index=["ID", "ID_grp", "Groups"], columns="Day", values=["IgG", "GIA05", "GIA10"])
    wide.columns = [f"{measure}_{int(day)}d" for measure, day in wide.columns]
    wide = wide.reset_index()

    out = pd.DataFrame()
    out["Treatment"] = wide["Groups"].map({"Tetanus Toxoid": "Tetanus_Toxoid", "PfAMA1": "PfAMA1"})
    out["YP_IgG_84d"] = numeric(wide["IgG_84d"])
    out["YP_GIA05_84d"] = numeric(wide["GIA05_84d"])
    out["YP_GIA10_84d"] = numeric(wide["GIA10_84d"])
    for day in [28, 56, 140, 364]:
        out[f"YS_IgG_{day}d"] = numeric(wide.get(f"IgG_{day}d"))
    for day in [364]:
        out[f"YS_GIA05_{day}d"] = numeric(wide.get(f"GIA05_{day}d"))
        out[f"YS_GIA10_{day}d"] = numeric(wide.get(f"GIA10_{day}d"))
    out["X_IgG_0d"] = numeric(wide["IgG_0d"])
    out["X_GIA05_0d"] = numeric(wide["GIA05_0d"])
    out["X_GIA10_0d"] = numeric(wide["GIA10_0d"])

    # Put the reference/control vaccine arm first in the CSV and later R factor.
    order = pd.Categorical(out["Treatment"], categories=["Tetanus_Toxoid", "PfAMA1"], ordered=True)
    out = out.assign(_order=order).sort_values(["_order"]).drop(columns=["_order"])

    out.to_csv(CLEAN / f"trial{trial_id}.csv", index=False)
    write_publication_record(
        trial_id,
        [
            "Primary publication: https://doi.org/10.1186/s12936-016-1466-4",
            "Dataset record: https://doi.org/10.6084/m9.figshare.c.3617936_d1.v1",
            "Publication PDF not downloaded by this batch; open-access link recorded.",
        ],
    )
    main = {
        "Trial_ID": trial_id,
        "Trial Number/Name": "RCTC-03206",
        "Paper Name": "Phase 1 randomized controlled trial to evaluate the safety and immunogenicity of recombinant Pichia pastoris-expressed Plasmodium falciparum apical membrane antigen 1 (PfAMA1-FVO [25-545]) in healthy Malian adults in Bandiagara",
        "Journal": "Malaria Journal",
        "Paper Link": "https://doi.org/10.1186/s12936-016-1466-4",
        "Publication Year": "2016",
        "# of Arm": out["Treatment"].nunique(),
        "Control Group": "Tetanus_Toxoid",
        "Study Phase": "Phase 1 randomized controlled vaccine trial",
        "Sample Size": len(out),
        "Priamry Outcome": "Immunogenicity measures IgG, GIA05, and GIA10 at day 84",
        "Primary Outcome Type": "Continuous",
        "Trial Success(Primary Outcome Significant)": "Not recorded",
        "Statistical Model": "Publication primary analysis; compact cleaned data provide participant-level immunogenicity outcomes",
        "Randomization Scheme": "Randomized controlled trial",
        "Randomization Scheme(High Level)": "Individual",
        "Research Area": "Malaria vaccine / immunogenicity",
        "Text Data": "No",
        "Citation": "Thera et al. Phase 1 randomized controlled trial to evaluate the safety and immunogenicity of PfAMA1-FVO [25-545] in healthy Malian adults in Bandiagara. Malaria Journal. 2016. doi:10.1186/s12936-016-1466-4.",
        "Issues Encountered": "Source file provides repeated immunogenicity rows but no demographic baseline table; cleaned data pivoted to one participant row with baseline immunogenicity covariates.",
    }
    prov = {
        "Trial_ID": trial_id,
        "Repository": "figshare",
        "Dataset_DOI": "10.6084/m9.figshare.c.3617936_d1.v1",
        "License": "CC BY 4.0",
        "Download_Date": "2026-06-12",
        "Source_Files": raw_files,
        "Baseline_Covariates_Selected": "; ".join(c for c in out.columns if c.startswith("X_")),
        "Baseline_Outcome_Measurements_Included": "X_IgG_0d; X_GIA05_0d; X_GIA10_0d",
        "Covariate_Source": "Source spreadsheet baseline immunogenicity measures",
        "Cleaning_Notes": "Repeated day-level data pivoted to one participant row; Tetanus Toxoid retained as reference arm.",
        "Original_Trial_ID": "",
        "Candidate_ID": "RCTC-03206",
        "License_Status": "Open figshare record, CC BY 4.0",
        "Publication_Status": "Primary publication verified via Crossref DOI",
        "Cleaning_Status": "active_cleaned",
        "Verification_Reasons": "Source verifier found treatment groups and participant-level longitudinal immunogenicity outcomes.",
    }
    return main, prov


def clean_japanese_activity() -> tuple[dict, dict]:
    trial_id = 125
    files = {
        0: SRC / "RCTC-06366" / "13102_2021_360_MOESM5_ESM.csv",
        1: SRC / "RCTC-06367" / "13102_2021_360_MOESM6_ESM.csv",
        2: SRC / "RCTC-06365" / "13102_2021_360_MOESM7_ESM.csv",
    }
    raw_files = copy_raw(trial_id, list(files.values()))
    dfs = {period: pd.read_csv(path) for period, path in files.items()}
    baseline = dfs[0].copy()
    baseline = baseline.sort_values("subject_ID")
    baseline_indexed = baseline.set_index("subject_ID")

    id_cols = {"Unnamed: 0", "subject_ID", "group", "period"}
    baseline_cols = [c for c in baseline.columns if c not in id_cols]
    measure_cols = [c for c in baseline_cols if c not in {"sex", "age_group", "height"}]

    out = pd.DataFrame(index=baseline_indexed.index)
    out["Treatment"] = baseline_indexed["group"].map({"control": "control", "active": "active_control", "intervention": "intervention"})

    for col in baseline_cols:
        out[f"X_{clean_name(col)}_0y"] = covariate(baseline_indexed[col])

    for period, suffix in [(1, "1y"), (2, "2y")]:
        follow = dfs[period].set_index("subject_ID")
        for col in measure_cols:
            prefix = "YP" if period == 1 and col in {"step-count", "PA_(METs / hour)", "moderate_PA"} else "YS"
            out[f"{prefix}_{clean_name(col)}_{suffix}"] = numeric(follow[col]).reindex(out.index)

    out = out.reset_index(drop=True)
    order = pd.Categorical(out["Treatment"], categories=["control", "active_control", "intervention"], ordered=True)
    out = out.assign(_order=order).sort_values("_order").drop(columns="_order")
    out.to_csv(CLEAN / f"trial{trial_id}.csv", index=False)
    write_publication_record(
        trial_id,
        [
            "Primary publication: https://doi.org/10.1186/s13102-021-00360-7",
            "Dataset records: https://doi.org/10.6084/m9.figshare.16869727 ; https://doi.org/10.6084/m9.figshare.16869729.v1 ; https://doi.org/10.6084/m9.figshare.16869731",
            "Publication PDF not downloaded by this batch; open-access link recorded.",
        ],
    )
    main = {
        "Trial_ID": trial_id,
        "Trial Number/Name": "RCTC-06366/RCTC-06367/RCTC-06365",
        "Paper Name": "Effect of a 1-year intervention comprising brief counselling sessions and low-dose physical activity recommendations in Japanese adults, and retention of the effect at 2 years: a randomized trial",
        "Journal": "BMC Sports Science, Medicine and Rehabilitation",
        "Paper Link": "https://doi.org/10.1186/s13102-021-00360-7",
        "Publication Year": "2021",
        "# of Arm": out["Treatment"].nunique(),
        "Control Group": "control",
        "Study Phase": "Behavioral physical activity randomized trial",
        "Sample Size": len(out),
        "Priamry Outcome": "Year-1 step count, PA MET-hours, and moderate physical activity",
        "Primary Outcome Type": "Continuous",
        "Trial Success(Primary Outcome Significant)": "Not recorded",
        "Statistical Model": "Publication primary analysis; compact cleaned data provide period-1 and period-2 participant-level outcomes",
        "Randomization Scheme": "Randomized trial",
        "Randomization Scheme(High Level)": "Individual",
        "Research Area": "Physical activity / preventive health",
        "Text Data": "No",
        "Citation": "Tripette et al. Effect of a 1-year intervention comprising brief counselling sessions and low-dose physical activity recommendations in Japanese adults, and retention of the effect at 2 years: a randomized trial. BMC Sports Science, Medicine and Rehabilitation. 2021. doi:10.1186/s13102-021-00360-7.",
        "Issues Encountered": "Three repository records are period-specific supplements for the same trial; cleaned as one participant-level trial using period 0 baseline and period 1/2 follow-up outcomes.",
    }
    prov = {
        "Trial_ID": trial_id,
        "Repository": "figshare",
        "Dataset_DOI": "10.6084/m9.figshare.16869727; 10.6084/m9.figshare.16869729.v1; 10.6084/m9.figshare.16869731",
        "License": "CC BY 4.0",
        "Download_Date": "2026-06-12",
        "Source_Files": raw_files,
        "Baseline_Covariates_Selected": "; ".join(c for c in out.columns if c.startswith("X_")),
        "Baseline_Outcome_Measurements_Included": "; ".join(c for c in out.columns if c.startswith("X_") and c.endswith("_0y")),
        "Covariate_Source": "Source spreadsheet period-0 baseline measures and demographics",
        "Cleaning_Notes": "Period-specific supplements reconciled by subject_ID. All baseline participants retained; missing follow-up values represent attrition.",
        "Original_Trial_ID": "",
        "Candidate_ID": "RCTC-06366/RCTC-06367/RCTC-06365",
        "License_Status": "Open figshare records, CC BY 4.0",
        "Publication_Status": "Primary publication verified via Crossref DOI",
        "Cleaning_Status": "active_cleaned",
        "Verification_Reasons": "Source verifier found participant-level period files with treatment/group assignment and physical activity/health outcome columns.",
    }
    return main, prov


def main() -> None:
    CLEAN.mkdir(parents=True, exist_ok=True)
    META.mkdir(parents=True, exist_ok=True)
    main_rows = []
    prov_rows = []
    for cleaner in [clean_endotoxemia, clean_prp, clean_pfama1_vaccine, clean_japanese_activity]:
        main_row, prov_row = cleaner()
        main_rows.append(main_row)
        prov_rows.append(prov_row)
    pd.DataFrame(main_rows).to_csv(META / "meta_data_next_batch_2026_06_12.csv", index=False)
    pd.DataFrame(prov_rows).to_csv(META / "provenance_next_batch_2026_06_12.csv", index=False)


if __name__ == "__main__":
    main()
