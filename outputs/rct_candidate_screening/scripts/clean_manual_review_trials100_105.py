import csv
import json
import shutil
import subprocess
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
import pandas as pd
import pyreadstat


ROOT = Path(__file__).resolve().parents[3]
RAW_ROOT = ROOT / "rct_expansion/raw_data"
CLEAN_ROOT = ROOT / "rct_expansion/cleaned_data"
META_ROOT = ROOT / "rct_expansion/metadata"
PROV_ROOT = ROOT / "rct_expansion/provenance"
BASE_DEFERRED = PROV_ROOT / "deferred_likely_qualified_evaluation_2026_06_11"
BASE_USER = PROV_ROOT / "manual_review_user_files_2026_06_11"
BATCH_TAG = "manual_review_trials116_121"


TRIAL_MAP = [
    {
        "trial_id": 116,
        "candidate_id": "RCTC-01557",
        "title": "Music intervention combined with progressive muscle relaxation among women with cancer receiving chemotherapy",
        "source_paths": [
            BASE_DEFERRED
            / "source_verification_manual_review_queue/downloads/RCTC-01557/S 3 raw data.tab"
        ],
        "dataset_doi": "10.7910/dvn/6i62qk",
        "repository": "Harvard Dataverse",
    },
    {
        "trial_id": 117,
        "candidate_id": "RCTC-02282",
        "title": "Effects of S-Ketamine and Midazolam on Respiratory Variability: A Randomized Controlled Pilot Trial",
        "source_paths": [
            BASE_USER / "extracted/doi-10.34894-bazoqf/Data",
            BASE_USER / "extracted/doi-10.34894-bazoqf/Study protocol",
        ],
        "dataset_doi": "10.34894/bazoqf",
        "repository": "DataverseNL",
    },
    {
        "trial_id": 118,
        "candidate_id": "RCTC-05010",
        "title": "Cerebrolysin and repetitive transcranial magnetic stimulation in traumatic brain injury",
        "source_paths": [BASE_USER / "RCTC-05010.xlsx"],
        "dataset_doi": "10.7910/dvn/dofciv",
        "repository": "Harvard Dataverse",
    },
    {
        "trial_id": 119,
        "candidate_id": "RCTC-02127",
        "title": "Pain perceived during hysteroscopic morcellation by vaginoscopy vs standard technique in an outpatient setting",
        "source_paths": [
            BASE_DEFERRED
            / "source_verification_manual_review_queue/downloads/RCTC-02127/Collecte donn_es_Dataverse.tab"
        ],
        "dataset_doi": "10.5683/sp3/qk5zrd",
        "repository": "Borealis",
    },
    {
        "trial_id": 120,
        "candidate_id": "RCTC-04923",
        "title": "Intermittent BRAF inhibition in advanced BRAF mutated melanoma: results of a phase II randomized trial",
        "source_paths": [
            BASE_DEFERRED
            / "source_verification_qualified_queue/downloads/RCTC-04923/Fig1a_ eFig 3.tab",
            BASE_DEFERRED
            / "source_verification_qualified_queue/downloads/RCTC-04923/Fig 1b_eFig 4a_ 4b_ 5.tab",
            BASE_DEFERRED
            / "source_verification_qualified_queue/downloads/RCTC-04923/eFig 6-7.tab",
            BASE_DEFERRED
            / "source_verification_qualified_queue/downloads/RCTC-04923/eFig 8-9.tab",
            BASE_DEFERRED
            / "source_verification_qualified_queue/downloads/RCTC-04923/mapa tablas.docx",
        ],
        "dataset_doi": "10.7910/dvn/tffsgr",
        "repository": "Harvard Dataverse",
    },
    {
        "trial_id": 121,
        "candidate_id": "RCTC-04272",
        "title": "Acceptance lowers stress reactivity: Dismantling mindfulness training in a randomized controlled trial",
        "source_paths": [
            BASE_DEFERRED
            / "source_verification_qualified_queue/downloads/RCTC-04272/LindsayData_PNE.sav"
        ],
        "dataset_doi": "10.17632/bx2gvkty4c.2",
        "repository": "Mendeley Data",
    },
]


def now_iso():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def rel(path):
    return str(Path(path).relative_to(ROOT))


def copy_sources():
    rows = []
    for spec in TRIAL_MAP:
        trial_dir = RAW_ROOT / f"trial{spec['trial_id']}"
        trial_dir.mkdir(parents=True, exist_ok=True)
        for src in spec["source_paths"]:
            if not src.exists():
                raise FileNotFoundError(src)
            name = src.name
            if name == "Data":
                name = "Data.csv"
            elif name == "Study protocol":
                name = "Study protocol.pdf"
            dst = trial_dir / name
            shutil.copy2(src, dst)
            rows.append(
                {
                    "Trial_ID": f"trial{spec['trial_id']}",
                    "Candidate_ID": spec["candidate_id"],
                    "Source_File": rel(src),
                    "Copied_To": rel(dst),
                    "File_Size_Bytes": dst.stat().st_size,
                }
            )
    return rows


def num(series):
    return pd.to_numeric(series, errors="coerce")


def sum_cols(df, cols):
    present = [c for c in cols if c in df.columns]
    if not present:
        return pd.Series(np.nan, index=df.index)
    return df[present].apply(pd.to_numeric, errors="coerce").sum(axis=1, min_count=1)


def clean_trial100():
    path = BASE_DEFERRED / "source_verification_manual_review_queue/downloads/RCTC-01557/S 3 raw data.tab"
    df = pd.read_csv(path, sep="\t")
    stress_items = [1, 6, 8, 11, 12, 14, 18]
    anxiety_items = [2, 4, 7, 9, 15, 19, 20]
    depression_items = [3, 5, 10, 13, 16, 17, 21]

    def dass(prefix=""):
        return [f"DASS{i}{prefix}" for i in range(1, 22)]

    def fact(prefix=""):
        return [f"{scale}{i}{prefix}" for scale, count in [("GP", 7), ("GS", 7), ("GE", 6), ("GF", 7)] for i in range(1, count + 1)]

    out = pd.DataFrame(
        {
            "Treatment": df["group"].map({1: "Group 1", 2: "Group 2"}).fillna(df["group"].astype(str)),
            "X_source_id": df["ID"],
            "YP_dass_total_t2": sum_cols(df, dass("T2")),
            "YP_delta_dass_total_t2": sum_cols(df, dass("T2")) - sum_cols(df, dass("")),
            "YP_factg_total_t2": sum_cols(df, fact("T2")),
            "YP_delta_factg_total_t2": sum_cols(df, fact("T2")) - sum_cols(df, fact("")),
            "YS_dass_total_t1": sum_cols(df, dass("T1")),
            "YS_delta_dass_total_t1": sum_cols(df, dass("T1")) - sum_cols(df, dass("")),
            "YS_dass_stress_t2": sum_cols(df, [f"DASS{i}T2" for i in stress_items]),
            "YS_dass_anxiety_t2": sum_cols(df, [f"DASS{i}T2" for i in anxiety_items]),
            "YS_dass_depression_t2": sum_cols(df, [f"DASS{i}T2" for i in depression_items]),
            "X_dass_total_0m": sum_cols(df, dass("")),
            "X_factg_total_0m": sum_cols(df, fact("")),
            "X_age_years": df["age"],
            "X_education_code": df["education"],
            "X_religion_code": df["religion"],
            "X_residence_place_code": df["place"],
            "X_job_code": df["job"],
            "X_marital_status_code": df["marrige"],
            "X_income_code": df["income"],
            "X_cancer_diagnosis_code": df["diagnose"],
            "X_cancer_stage_code": df["stage"],
            "X_treatment_type_code": df["typeoftreatment"],
            "X_chemotherapy_time": df["chemotherapytime"],
            "X_regimen_number": df["regimennumber"],
        }
    )
    return out


def clean_trial101():
    path = BASE_USER / "extracted/doi-10.34894-bazoqf/Data"
    df = pd.read_csv(path)
    metrics = ["MRR", "VRR", "VTV"]
    grouped = (
        df.groupby(["Patient_Recode", "Allocation"], dropna=False)
        [[f"{m}{t}" for m in metrics for t in ["pre", "post"]]]
        .mean()
        .reset_index()
    )
    treatment_order = ["Saline", "Midazolam", "Ketamine"]
    out = pd.DataFrame(
        {
            "Treatment": pd.Categorical(grouped["Allocation"], categories=treatment_order, ordered=True).astype(str),
            "X_source_patient_id": grouped["Patient_Recode"],
            "YP_delta_mrr_post_pre": grouped["MRRpost"] - grouped["MRRpre"],
            "YP_mrr_post": grouped["MRRpost"],
            "YS_delta_vrr_post_pre": grouped["VRRpost"] - grouped["VRRpre"],
            "YS_vrr_post": grouped["VRRpost"],
            "YS_delta_vtv_post_pre": grouped["VTVpost"] - grouped["VTVpre"],
            "YS_vtv_post": grouped["VTVpost"],
            "X_mrr_pre": grouped["MRRpre"],
            "X_vrr_pre": grouped["VRRpre"],
            "X_vtv_pre": grouped["VTVpre"],
            "X_repeated_rows_aggregated": df.groupby("Patient_Recode").size().reindex(grouped["Patient_Recode"]).to_numpy(),
        }
    )
    return out


def clean_trial102():
    path = BASE_USER / "RCTC-05010.xlsx"
    df = pd.read_excel(path, sheet_name="ITT_analysis set")
    order = ["PLC+SHM", "CRB+SHM", "CRB+rTMS"]
    out = pd.DataFrame(
        {
            "Treatment": pd.Categorical(df["GROUP"], categories=order, ordered=True).astype(str),
            "X_subject_id": df["SUBJECT"],
            "YP_cognitive_composite_180_bd_full_adj": num(df["180_BD_full_adj"]),
            "YP_cognitive_composite_180_crude_full_adj": num(df["180_crude_full_adj"]),
            "YP_moca_visit3": num(df["MOTS_3"]),
            "YP_delta_moca_visit3": num(df["MOTS_3"]) - num(df["MOTS_1"]),
            "YS_hamilton_anxiety_visit3": num(df["HARTS_3"]),
            "YS_digit_forward_visit3": num(df["DGFRES_3"]),
            "YS_digit_backward_visit3": num(df["DGBRES_3"]),
            "YS_tmt1_time_visit3": num(df["TMT1_3_truncated"]),
            "YS_tmt2_time_visit3": num(df["TMT2_3_truncated"]),
            "X_age_years": df["AGE"],
            "X_sex_code": df["SEX"],
            "X_moca_0m": df["MOTS_1"],
            "X_psi_digit_symbol_0m": df["PSCNUM_1"],
            "X_psi_symbol_search_correct_0m": df["PSSCNUM_1"],
            "X_psi_symbol_search_incorrect_0m": df["PSSINUM_1"],
            "X_digit_forward_0m": df["DGFRES_1"],
            "X_digit_backward_0m": df["DGBRES_1"],
            "X_hamilton_anxiety_0m": df["HARTS_1"],
            "X_tmt1_time_0m": df["TMT1_1_truncated"],
            "X_tmt2_time_0m": df["TMT2_1_truncated"],
        }
    )
    return out


def clean_trial103():
    path = (
        BASE_DEFERRED
        / "source_verification_manual_review_queue/downloads/RCTC-02127/Collecte donn_es_Dataverse.tab"
    )
    df = pd.read_csv(path, sep="\t")
    out = pd.DataFrame(
        {
            "Treatment": df["Randomisation"].map({1.0: "Randomisation arm 1", 2.0: "Randomisation arm 2"}),
            "X_source_record_id": df["RecordId"],
            "YP_pain_score": df["Scoredlr"],
            "YS_procedure_duration_min": df["Durée"],
            "YS_conversion": df["Conversion"],
            "YS_postoperative_symptoms": df["Symppost"],
            "YS_postoperative_complication": df["Complicationpost"],
            "YS_postoperative_bleeding": df["Saignementpost"],
            "YS_glycine_or_ns_deficit": df["Déficitglycine/NS"],
            "YS_fentanyl_total": df["Fentanyltotal"],
            "YS_versed_total": df["Versedtotal"],
            "X_age_years": df["Age"],
            "X_height_cm": df["Taille"],
            "X_weight_kg": df["Poids"],
            "X_bmi": df["IMC"],
            "X_education_code": df["education"],
            "X_marital_status_code": df["statutmarital"],
            "X_prior_csection": df["ATCDCS"],
            "X_smoking": df["tabac"],
            "X_infertility": df["infertilité"],
            "X_prior_hysteroscopy": df["ATCDhystero"],
            "X_gynecologic_pain": df["Dlrgyneco"],
            "X_chronic_pain": df["dlrchronique"],
            "X_sexual_partner": df["Partenairesexuel"],
            "X_contraception_code": df["Contraception1"],
        }
    )
    return out


def clean_trial104():
    path = BASE_DEFERRED / "source_verification_qualified_queue/downloads/RCTC-04923/Fig1a_ eFig 3.tab"
    df = pd.read_csv(path, sep="\t")
    out = pd.DataFrame(
        {
            "Treatment": df["arm"].map({"A-Continuous": "Continuous treatment", "B-Intermittent": "Intermittent treatment"}),
            "X_source_subject_id": df["subjid"],
            "YP_progression_free_survival_months": df["pfsm"],
            "YP_pfs_event": df["cspfs"],
            "YS_overall_survival_months": df["osm"],
            "YS_overall_survival_event": df["csos"],
            "X_melanoma_stage": df["gstage"],
        }
    )
    return out


def clean_trial105():
    path = BASE_DEFERRED / "source_verification_qualified_queue/downloads/RCTC-04272/LindsayData_PNE.sav"
    df, meta = pyreadstat.read_sav(str(path), apply_value_formats=False)
    d = df[df["Exclude_2"] == 1].copy()
    treatment = d["StudyCondition"].map({1.0: "Monitor + Accept", 2.0: "Monitor Only", 3.0: "Control"})
    sex = d["Sex"].map({1.0: "Male", 2.0: "Female"})
    race = d["Race_a"].map(
        {
            1.0: "White",
            2.0: "Black",
            3.0: "Asian",
            4.0: "Native American",
            5.0: "Bi/multiracial",
            6.0: "Other",
        }
    )
    out = pd.DataFrame(
        {
            "Treatment": treatment,
            "X_source_subject_id": d["SubjectID"],
            "YP_subjective_stress_overall": d["Subjective_Stress_Overall"],
            "YS_cortisol_auc_i_log_em": d["Cort_AUC_I_log_EMreplace"],
            "YS_cortisol_log_25min_post_tsst": d["TSST_cortisolB_log_EMreplace"],
            "YS_cortisol_log_35min_post_tsst": d["TSST_cortisolC_log_EMreplace"],
            "YS_dbp_tsst_performance": d["DBP_TSST_Perf_mean_strict"],
            "YS_sbp_tsst_performance": d["SBP_TSST_Perf_mean_strict"],
            "X_cortisol_log_prestress_0d": d["TSST_cortisolA_log_EMreplace"],
            "X_dbp_prestress_0d": d["DBP_TSST_Base_mean_strict"],
            "X_sbp_prestress_0d": d["SBP_TSST_Base_mean_strict"],
            "X_age_years": d["Age"],
            "X_sex": sex,
            "X_race": race,
            "X_ethnicity_code": d["Ethnicity"],
            "X_education_code": d["Edu"],
            "X_bmi": d["BMI"],
            "X_lessons_completed": d["Lessons_completed"],
            "X_days_intervention_end_to_post": d["Days_InterventionEnd_PostSession"],
            "X_follicular_phase_post": d["Follicular_phase_post"],
        }
    )
    return out


CLEANERS = {
    116: clean_trial100,
    117: clean_trial101,
    118: clean_trial102,
    119: clean_trial103,
    120: clean_trial104,
    121: clean_trial105,
}

TREATMENT_LEVELS = {
    116: ["Group 1", "Group 2"],
    117: ["Saline", "Midazolam", "Ketamine"],
    118: ["PLC+SHM", "CRB+SHM", "CRB+rTMS"],
    119: ["Randomisation arm 1", "Randomisation arm 2"],
    120: ["Continuous treatment", "Intermittent treatment"],
    121: ["Control", "Monitor + Accept", "Monitor Only"],
}


def write_rds(csv_path, rds_path, treatment_levels):
    code = (
        "args <- commandArgs(trailingOnly=TRUE); "
        "dat <- read.csv(args[1], check.names=FALSE, stringsAsFactors=FALSE); "
        "lev <- strsplit(args[3], '\t', fixed=TRUE)[[1]]; "
        "dat$Treatment <- factor(dat$Treatment, levels=lev); "
        "saveRDS(dat, args[2])"
    )
    subprocess.run(
        ["Rscript", "-e", code, str(csv_path), str(rds_path), "\t".join(treatment_levels)],
        check=True,
        cwd=ROOT,
    )


def write_cleaned_outputs():
    rows = []
    for spec in TRIAL_MAP:
        trial_id = spec["trial_id"]
        cleaned = CLEANERS[trial_id]()
        cleaned = cleaned.loc[:, ~cleaned.columns.duplicated()].copy()
        cleaned_path = CLEAN_ROOT / f"trial{trial_id}.csv"
        rds_path = CLEAN_ROOT / f"trial{trial_id}.rds"
        cleaned_path.parent.mkdir(parents=True, exist_ok=True)
        cleaned.to_csv(cleaned_path, index=False)
        write_rds(cleaned_path, rds_path, TREATMENT_LEVELS[trial_id])
        rows.append(
            {
                "Trial_ID": f"trial{trial_id}",
                "Candidate_ID": spec["candidate_id"],
                "Cleaned_CSV": rel(cleaned_path),
                "Cleaned_RDS": rel(rds_path),
                "n_rows": cleaned.shape[0],
                "n_columns": cleaned.shape[1],
            }
        )
    return rows


def exact_duplicate_count(df):
    count = 0
    cols = list(df.columns)
    for i in range(len(cols)):
        for j in range(i + 1, len(cols)):
            if df[cols[i]].equals(df[cols[j]]):
                count += 1
    return count


def validate_cleaned():
    rows = []
    for spec in TRIAL_MAP:
        trial_id = spec["trial_id"]
        csv_path = CLEAN_ROOT / f"trial{trial_id}.csv"
        rds_path = CLEAN_ROOT / f"trial{trial_id}.rds"
        df = pd.read_csv(csv_path)
        yp = [c for c in df.columns if c.startswith("YP_")]
        ys = [c for c in df.columns if c.startswith("YS_")]
        x = [c for c in df.columns if c.startswith("X_")]
        treatment_levels = TREATMENT_LEVELS[trial_id]
        rows.append(
            {
                "Trial_ID": f"trial{trial_id}",
                "Candidate_ID": spec["candidate_id"],
                "n_rows": df.shape[0],
                "n_columns": df.shape[1],
                "treatment_levels": "; ".join(treatment_levels),
                "n_treatment_levels": df["Treatment"].nunique(dropna=True),
                "has_treatment": "yes" if "Treatment" in df.columns else "no",
                "yp_columns": "; ".join(yp),
                "n_yp_columns": len(yp),
                "ys_columns": "; ".join(ys),
                "n_ys_columns": len(ys),
                "x_columns": "; ".join(x),
                "n_x_columns": len(x),
                "has_primary_outcome": "yes" if yp else "no",
                "duplicate_column_names": int(df.columns.duplicated().sum()),
                "exact_duplicate_column_count": exact_duplicate_count(df),
                "csv_exists": "yes" if csv_path.exists() else "no",
                "rds_exists": "yes" if rds_path.exists() else "no",
                "passes_basic_cleaned_contract": "yes"
                if "Treatment" in df.columns and df["Treatment"].nunique(dropna=True) >= 2 and len(yp) >= 1
                else "no",
            }
        )
    return rows


def data_dictionary():
    explanations = {
        "Treatment": "Randomized treatment assignment arm.",
        "YP_": "Primary or primary-like outcome variable constructed from available source data.",
        "YS_": "Secondary outcome or supportive follow-up outcome variable.",
        "X_": "Baseline covariate, source identifier, or pre-treatment/pre-stress measurement retained for adjustment/provenance.",
    }
    rows = []
    for spec in TRIAL_MAP:
        trial_id = spec["trial_id"]
        df = pd.read_csv(CLEAN_ROOT / f"trial{trial_id}.csv")
        for col in df.columns:
            if col == "Treatment":
                vtype = "Treatment"
                brief = explanations["Treatment"]
            elif col.startswith("YP_"):
                vtype = "Primary outcome"
                brief = explanations["YP_"]
            elif col.startswith("YS_"):
                vtype = "Secondary outcome"
                brief = explanations["YS_"]
            elif col.startswith("X_"):
                vtype = "Baseline covariate"
                brief = explanations["X_"]
            else:
                vtype = "Other"
                brief = "Other retained analysis variable."
            rows.append(
                {
                    "Trial_ID": f"trial{trial_id}",
                    "Candidate_ID": spec["candidate_id"],
                    "variable_name": col,
                    "variable_type": vtype,
                    "brief_explanation": brief,
                }
            )
    return rows


def metadata_rows():
    info = {
        116: {
            "arms": 2,
            "control": "Not identified from compact source",
            "sample": 24,
            "primary": "DASS total and FACT-G total at T2/change from baseline",
            "ptype": "continuous scale",
            "area": "Oncology supportive care / psycho-oncology",
            "model": "Pilot RCT group comparisons; publication review still required",
            "randomization": "Individually randomized, parallel two-arm pilot trial",
            "year": 2023,
        },
        117: {
            "arms": 3,
            "control": "Saline",
            "sample": 25,
            "primary": "Post-pre respiratory variability metrics MRR/VRR/VTV",
            "ptype": "continuous physiologic measure",
            "area": "Anesthesia / respiratory physiology",
            "model": "Repeated rows aggregated to patient-level means; publication review still required",
            "randomization": "Individually randomized, parallel three-arm pilot trial",
            "year": 2025,
        },
        118: {
            "arms": 3,
            "control": "PLC+SHM",
            "sample": 86,
            "primary": "Cognitive composite and MoCA follow-up scores",
            "ptype": "continuous neuropsychological score",
            "area": "Traumatic brain injury / neurorehabilitation",
            "model": "ITT analysis-set outcomes; publication review still required",
            "randomization": "Individually randomized, parallel three-arm trial",
            "year": 2023,
        },
        119: {
            "arms": 2,
            "control": "Not identified from compact source",
            "sample": 57,
            "primary": "Pain score during hysteroscopic morcellation",
            "ptype": "continuous pain score",
            "area": "Gynecology / outpatient hysteroscopy",
            "model": "Independent randomized-arm comparison; publication review still required",
            "randomization": "Individually randomized, parallel two-arm trial",
            "year": 2022,
        },
        120: {
            "arms": 2,
            "control": "Continuous treatment",
            "sample": 70,
            "primary": "Progression-free survival months and event indicator",
            "ptype": "time-to-event",
            "area": "Oncology / melanoma",
            "model": "Survival analysis in publication; compact data retain PFS/OS summaries",
            "randomization": "Individually randomized, parallel two-arm phase II trial",
            "year": 2021,
        },
        121: {
            "arms": 3,
            "control": "Control",
            "sample": 144,
            "primary": "Subjective stress reactivity composite",
            "ptype": "continuous stress score",
            "area": "Behavioral medicine / mindfulness",
            "model": "TSST-completer analysis set; publication review still required",
            "randomization": "Individually randomized, parallel three-arm trial",
            "year": 2017,
        },
    }
    rows = []
    for spec in TRIAL_MAP:
        trial_id = spec["trial_id"]
        inf = info[trial_id]
        title = spec["title"]
        rows.append(
            {
                "Trial_ID": f"trial{trial_id}",
                "Trial Number/Name": title,
                "Paper Name": title,
                "Journal": "Not fully reviewed",
                "Paper Link": f"https://doi.org/{spec['dataset_doi']}" if spec["dataset_doi"].startswith("10.") else spec["dataset_doi"],
                "Publication Year": inf["year"],
                "# of Arm": inf["arms"],
                "Control Group": inf["control"],
                "Study Phase": "Publication review pending",
                "Sample Size": inf["sample"],
                "Priamry Outcome": inf["primary"],
                "Primary Outcome Type": inf["ptype"],
                "Trial Success(Primary Outcome Significant)": "Not audited",
                "Statistical Model": inf["model"],
                "Randomization Scheme": inf["randomization"],
                "Randomization Scheme(High Level)": "Individual randomization",
                "Research Area": inf["area"],
                "Text Data": "No",
                "Citation": f"{title}. Dataset DOI: {spec['dataset_doi']}.",
            }
        )
    return rows


def download_log_rows(copy_rows):
    by_trial = {}
    for row in copy_rows:
        by_trial.setdefault(row["Trial_ID"], []).append(Path(row["Copied_To"]).name)
    rows = []
    for spec in TRIAL_MAP:
        trial = f"trial{spec['trial_id']}"
        rows.append(
            {
                "Trial_ID": spec["trial_id"],
                "Candidate_ID": spec["candidate_id"],
                "Repository": spec["repository"],
                "Dataset_DOI": spec["dataset_doi"],
                "Download_Date": "2026-06-11",
                "Status": "cleaned_after_manual_review_pending_publication_audit",
                "Source_Files": "; ".join(by_trial.get(trial, [])),
            }
        )
    return rows


def write_csv(path, rows, fields=None):
    rows = list(rows)
    if fields is None:
        fields = list(rows[0].keys()) if rows else []
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def write_metadata_xlsx(meta_rows, path):
    df = pd.DataFrame(meta_rows)
    with pd.ExcelWriter(path, engine="openpyxl") as writer:
        df.to_excel(writer, sheet_name="metadata", index=False)
        provenance = pd.DataFrame(
            [
                {
                    "field": "Batch",
                    "value": BATCH_TAG,
                },
                {
                    "field": "Generated_At_UTC",
                    "value": now_iso(),
                },
                {
                    "field": "Scope",
                    "value": "trial116-trial121 structural cleaning outputs; primary-publication audit pending.",
                },
            ]
        )
        provenance.to_excel(writer, sheet_name="provenance", index=False)


def update_flow_counts(validation_rows):
    flow_path = PROV_ROOT / "broad_dataset_screening_flow_counts.csv"
    if flow_path.exists():
        existing = pd.read_csv(flow_path)
    else:
        existing = pd.DataFrame()
    iteration_id = "manual_review_trials116_121_cleaning_2026_06_11"
    if not existing.empty and "iteration_id" in existing.columns:
        existing = existing[existing["iteration_id"] != iteration_id]
    passing = sum(1 for r in validation_rows if r["passes_basic_cleaned_contract"] == "yes")
    rows = [
        {
            "iteration_id": iteration_id,
            "recorded_date": "2026-06-11",
            "stage_order": 11,
            "stage_id": "manual_review_trials116_121_cleaned",
            "parent_stage_id": "manual_review_user_qualified",
            "node_label": "Manual-review candidates cleaned as trial116-trial121",
            "count": len(TRIAL_MAP),
            "node_kind": "screening",
            "criteria": "Copied source files to raw_data, constructed compact participant-level cleaned CSV/RDS outputs, and generated batch metadata/data dictionary.",
            "source_output": "rct_expansion/provenance/validation_summary_manual_review_trials116_121.csv",
            "notes": "These are structural cleaning outputs pending primary-publication review and outcome reproducibility audit.",
        },
        {
            "iteration_id": iteration_id,
            "recorded_date": "2026-06-11",
            "stage_order": 12,
            "stage_id": "manual_review_trials116_121_contract_pass",
            "parent_stage_id": "manual_review_trials116_121_cleaned",
            "node_label": "Trial116-trial121 cleaned outputs passing structural contract",
            "count": passing,
            "node_kind": "inclusion",
            "criteria": "Treatment exists with at least two arms, at least one YP_* outcome exists, and CSV/RDS outputs were written.",
            "source_output": "rct_expansion/provenance/validation_summary_manual_review_trials116_121.csv",
            "notes": "Publication-supported primary outcome confirmation is still required.",
        },
    ]
    out = pd.concat([existing, pd.DataFrame(rows)], ignore_index=True) if not existing.empty else pd.DataFrame(rows)
    out.to_csv(flow_path, index=False)


def main():
    copy_rows = copy_sources()
    clean_rows = write_cleaned_outputs()
    validation_rows = validate_cleaned()
    dd_rows = data_dictionary()
    meta_rows = metadata_rows()
    dl_rows = download_log_rows(copy_rows)

    write_csv(PROV_ROOT / f"{BATCH_TAG}_raw_copy_log.csv", copy_rows)
    write_csv(PROV_ROOT / f"{BATCH_TAG}_cleaned_output_log.csv", clean_rows)
    write_csv(PROV_ROOT / "validation_summary_manual_review_trials116_121.csv", validation_rows)
    write_csv(META_ROOT / "data_dictionary_manual_review_trials116_121.csv", dd_rows)
    write_csv(META_ROOT / "meta_data_manual_review_trials116_121.csv", meta_rows)
    write_csv(PROV_ROOT / "download_log_manual_review_trials116_121.csv", dl_rows)
    write_metadata_xlsx(meta_rows, META_ROOT / "meta_data_manual_review_trials116_121.xlsx")
    update_flow_counts(validation_rows)

    summary = {
        "generated_at_utc": now_iso(),
        "trials_cleaned": [f"trial{spec['trial_id']}" for spec in TRIAL_MAP],
        "candidate_ids": [spec["candidate_id"] for spec in TRIAL_MAP],
        "validation_pass_count": sum(1 for r in validation_rows if r["passes_basic_cleaned_contract"] == "yes"),
        "notes": "Structural cleaning complete; primary-publication review and reproducibility audit remain pending.",
    }
    (PROV_ROOT / "manual_review_trials116_121_summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
