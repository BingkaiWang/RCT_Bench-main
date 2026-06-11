#!/usr/bin/env python3
"""Clean qualified manually downloaded RCTC trials into trial97+ outputs."""

from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path

import numpy as np
import pandas as pd
import pyreadstat


ROOT = Path(__file__).resolve().parents[3]
WORK = Path(__file__).resolve().parent
CLEAN_DIR = ROOT / "rct_expansion/cleaned_data"
RAW_DIR = ROOT / "rct_expansion/raw_data"


def num(s):
    return pd.to_numeric(s, errors="coerce")


def zbi_total(df):
    return df[[c for c in df.columns if str(c).startswith("ZBI.")]].apply(num).sum(axis=1, min_count=1)


def qol_total(df):
    return df[[c for c in df.columns if str(c).startswith("F") and str(c)[1:].isdigit()]].apply(num).sum(axis=1, min_count=1)


def clean_name(name):
    out = "".join(ch.lower() if ch.isalnum() else "_" for ch in str(name))
    while "__" in out:
        out = out.replace("__", "_")
    return out.strip("_")


def base_covariates(df, cols):
    out = {}
    for col in cols:
        if col in df.columns:
            out[f"X_{clean_name(col)}"] = df[col]
    return out


def c00152():
    p = ROOT / "manually-download-raw-data/RCTC-00152.xlsx"
    b = pd.read_excel(p, sheet_name="BASELINE DATA")
    m3 = pd.read_excel(p, sheet_name="3-MONTH")
    m6 = pd.read_excel(p, sheet_name="6-MONTH")
    return pd.DataFrame({
        "Treatment": b["Group"].map({1: "Group 1", 2: "Group 2"}),
        "YP_zarit_burden_3m": zbi_total(m3),
        "YS_zarit_burden_6m": zbi_total(m6),
        "YS_qol_bref_3m": qol_total(m3),
        "YS_qol_bref_6m": qol_total(m6),
        "X_zarit_burden_0m": zbi_total(b),
        "X_qol_bref_0m": qol_total(b),
        "X_duration_stroke_months": b.get("S1"),
        "X_caregiver_age": b.get("C6"),
        "X_caregiver_sex": b.get("C7"),
    })


def c00166():
    p = WORK / "extracted/RCTC-00166/RCTC-00166/Albinama data upload/Albinama_Table2_Pv_PCR.dta"
    d, _ = pyreadstat.read_dta(str(p))
    return pd.DataFrame({
        "Treatment": d["treat2"].map({0: "Placebo", 1: "Primaquine"}),
        "YP_pvivax_qpcr_infection_8m": d["fail"],
        "YS_time_to_pvivax_qpcr_days": d["exit_day_8mo"],
        "X_age_years": d["age"],
        "X_pvivax_enroll": d["pv_enroll"],
        "X_village_group": d["villagegroup_corrected2"],
    })


def c00167():
    p = ROOT / "manually-download-raw-data/ANALYSED_RCT_Whole+group_RCTC00167.xlsx"
    d = pd.read_excel(p)
    return pd.DataFrame({
        "Treatment": d["group"].map({0: "Control", 1: "Education support"}),
        "YP_stroke_knowledge_3m": d["fuskqtotal"],
        "YS_self_efficacy_3m": d[[c for c in d.columns if c.startswith("fuse")]].apply(num).sum(axis=1, min_count=1),
        "YS_hads_anxiety_3m": d["fuhadsanxiety"],
        "YS_hads_depression_3m": d["fuhadsdepress"],
        "X_stroke_knowledge_0m": d["iiskqtotal"],
        "X_age_years": d["age"],
        "X_gender": d["gender"],
        "X_site": d["site"],
        "X_days_since_stroke_0m": d["ii day ssince stroke"],
    })


def c00170():
    p = WORK / "extracted/RCTC-00170/RCTC-00170/coagulation_data_clean_R Open data.xlsx"
    d = pd.read_excel(p)
    return pd.DataFrame({
        "Treatment": d["Treatment"].map({0: "Control", 1: "rhTM"}).fillna(d["Treatment rhTM (T) Control ?"].map({"C": "Control", "T": "rhTM"})),
        "YP_death_28d": d["Death =1 Alive = 0 28 day"],
        "YS_death_90d": d["Death = 1   Alive = 0   90 day Cencer"],
        "X_age_years": d.get("Age"),
        "X_sex": d.get("Sex"),
        "X_sofa_0d": d.get("SOFA0"),
        "X_dic_score_0d": d.get("DIC score 0"),
        "X_platelet_0d": d.get("PLT0"),
    })


def c00173():
    p = WORK / "extracted/RCTC-00173/RCTC-00173/AMIGOS economic evaluation dataset.xlsx"
    d = pd.read_excel(p, sheet_name="clinical data")
    return pd.DataFrame({
        "Treatment": d["Intervention"].map({0: "Standard care", 1: "Geriatric intervention"}),
        "YP_eq5d_pain_3m": d.get("po_eq5d_pain"),
        "YS_dead_3m": d.get("Dead at follow up (=1)"),
        "X_age_years": d.get("age"),
        "X_sex": d.get("sex (1=male, 2=female)"),
        "X_charlson_0m": d.get("charlson comorbidity score"),
        "X_eq5d_pain_0m": d.get("pi_eq5d_pain"),
        "X_barthel_feed_0m": d.get("pi_feed_b"),
    })


def c00175():
    p = WORK / "extracted/RCTC-00175/RCTC-00175/C4CAnonFinalDataCheck1612.ods"
    d = pd.read_excel(p, sheet_name="AnonData")
    improve = d["Primary outcome"].map({"Yes": 1, "No": 0})
    return pd.DataFrame({
        "Treatment": d["Allocation"].map({"A": "Flucloxacillin", "B": "Flucloxacillin + clindamycin"}),
        "YP_improved_day5": improve,
        "YS_diarrhoea_day5": d["D5Diarrhoea"].map({"Yes": 1, "No": 0, 1: 1, 0: 0}),
        "YS_pain_day5": d["D5PainScore"],
        "X_age_years": d["Age"],
        "X_sex": d["Sex"],
        "X_pain_0d": d["BLPainScore"],
        "X_crp_0d": d["BLBldCRP"],
    })


def c00180():
    p = WORK / "extracted/RCTC-00180/RCTC-00180/TEAM economic evaluation dataset.xlsx"
    d = pd.read_excel(p, sheet_name="clinical data")
    return pd.DataFrame({
        "Treatment": d["wardtype"].map({0: "MMHU", 1: "Geriatric ward", 2: "General ward"}),
        "YP_eq5d_pain_3m": d.get("po_eq5d_pain"),
        "YS_status_3m": d.get("po_status"),
        "YS_mmse_3m": d.get("po_mmse_total"),
        "X_age_years": d.get("age"),
        "X_gender": d.get("gender"),
        "X_eq5d_pain_0m": d.get("pi_eq5d_pain"),
        "X_npi_depression_0m": d.get("pi_npi_depress_s"),
    })


def c00181():
    p = WORK / "extracted/RCTC-00181/RCTC-00181/PAC+dataset.xls"
    d = pd.read_excel(p, sheet_name="Patient demographics for omiss")
    return pd.DataFrame({
        "Treatment": d["groupcode"].map({"Control": "Usual care", "Intervention": "Pharmacist collaborative prescribing"}),
        "YP_total_medications": d["totalmed (excl new)"],
        "YS_regular_medications": d["reg"],
        "YS_new_medications": d["new"],
        "X_prn_medications": d["prn"],
        "X_otc_medications": d["otc"],
        "X_cam_medications": d["cam"],
    })


def c00888():
    p = WORK / "extracted/RCTC-00888/RCTC-00888/Dryad_data.xlsx"
    d = pd.read_excel(p)
    return pd.DataFrame({
        "Treatment": d["Category"].map({1: "Standard care", 2: "Exercise"}),
        "YP_counts_per_day_28w": d["Counts_per_day_v2"],
        "YS_counts_per_day_36w": d["Counts_per_day_v3"],
        "YS_weight_28w": d["Weight_v2"],
        "X_counts_per_day_14w": d["Counts_per_day_v1"],
        "X_maternal_age": d["maternal _age"],
        "X_bmi_14w": d["BMI_v1"],
        "X_weight_14w": d["Weight_v1"],
    })


def c00890():
    d, _ = pyreadstat.read_dta(str(ROOT / "manually-download-raw-data/RCRC-00890"))
    d = d[d["Intervention"].notna()].copy()
    return pd.DataFrame({
        "Treatment": d["Intervention"].map({1: "Third wave cognitive therapy", 2: "Mentalization-based treatment"}),
        "YP_hdrs_18w": d["HD2"],
        "YS_bdi_18w": d["BDI2"],
        "YS_who5_18w": d["WHO2"],
        "X_hdrs_0w": d["HD0"],
        "X_bdi_0w": d["BDI0"],
        "X_who5_0w": d["WHO0"],
        "X_personality_type": d["personalityType"],
    })


def c00893():
    p = WORK / "extracted/RCTC-00893/RCTC-00893/Final results SSPS.sav"
    d, _ = pyreadstat.read_sav(str(p))
    out = pd.DataFrame({
        "Treatment": d["Randomisation"].map({1: "Doctor", 2: "Emergency nurse practitioner", 3: "Extended scope physiotherapist"}),
        "YP_function_8w": d["EightweekFunction"],
        "X_function_0w": d["BaselineFunction"],
        "X_age_years": d["Age"],
        "X_sex": d["Sex"],
        "X_fracture": d["Fracture"],
    })
    return out[out["YP_function_8w"].notna()].reset_index(drop=True)


def c01313():
    p = ROOT / "manually-download-raw-data/RCTC-01313/ELAIA-1_deidentified_data_10-6-2020 (1).csv"
    d = pd.read_csv(p)
    return pd.DataFrame({
        "Treatment": d["alert"].map({0: "Usual care", 1: "AKI alert"}),
        "YP_composite_14d": d["composite_outcome"],
        "YS_death_14d": d["death14"],
        "YS_dialysis_14d": d["dialysis14"],
        "YS_aki_progression_14d": d["aki_progression14"],
        "X_age_years": d["age"],
        "X_sex": d["sex"],
        "X_hospital": d["hospital"],
        "X_baseline_creatinine": d["baseline_creat"],
        "X_sofa_0d": d["sofa"],
        "X_initial_egfr": d["initial_egfr"],
    })


def c01363():
    d = pd.read_excel(ROOT / "manually-download-raw-data/Raw_data.xlsx")
    return pd.DataFrame({
        "Treatment": pd.Categorical(d["Group"], categories=["Placebo", "Vitamin K1", "Vitamin K2"], ordered=True),
        "YP_mgp_post": d["MGP Post"],
        "YS_ca_ph_product_post": d["CA X P Product Post"],
        "X_mgp_0m": d["MGP Pre"],
        "X_ca_ph_product_0m": d["Ca x P Product Pre"],
        "X_age_years": d["Age"],
        "X_gender": d["Gender"],
        "X_pth_0m": d["PTH"],
        "X_duration_dialysis_years": d["Duration of dialysis (Years)"],
    })


def c01383():
    d = pd.read_csv(WORK / "extracted/RCTC-01383/RCTC-01383/5731a26f-520f-41fc-87cd-9aef4af27dc9.csv")
    return pd.DataFrame({
        "Treatment": pd.Categorical(d["arm"], categories=["Oral iron", "IV iron (ferumoxytol)"], ordered=True),
        "YP_hgb_4w": d["fourwk_hgb"],
        "YS_hgb_8w": d["eightwk_hgb"],
        "YS_hgb_admission": d["hgb_admit"],
        "X_hgb_screening": d["screening_hgb"],
        "X_ferritin_0w": d["ferritin"],
        "X_tsat_0w": d["tsat"],
        "X_parity": d["parity"],
    })


def c01888():
    cog = pd.read_excel(ROOT / "manually-download-raw-data/RCTC-01888/CogEvo.xlsx")
    moca = pd.read_excel(ROOT / "manually-download-raw-data/RCTC-01888/MoCAJ.xlsx")
    ch = pd.read_excel(ROOT / "manually-download-raw-data/RCTC-01888/characteristics.xlsx")
    return pd.DataFrame({
        "Treatment": cog["group"].map({"Control": "Control", "SoroTouch": "Abacus cognitive training"}),
        "YP_moca_total_post": moca["Total2"],
        "YS_cogevo_total_post": cog["Total⑦"],
        "X_moca_total_0w": moca["Total"],
        "X_cogevo_total_0w": cog["Total"],
        "X_decade": ch["decade"],
        "X_sex": ch["sex"],
        "X_depression": ch["depression"],
    })


def c01926():
    d = pd.read_csv(WORK / "extracted/RCTC-01926/RCTC-1926/Song_ntrainerdeidentified_datadryad_2.13.19.csv")
    return pd.DataFrame({
        "Treatment": d["Intervention Group"].map({"Control Group": "Non-pulsatile pacifier", "NTrainer Group": "NTrainer stimulation"}),
        "YP_time_to_full_oral_feeds_days": d["Time to FOF"],
        "YS_reached_full_oral_feeds": d["Reached Primary Outcome"],
        "YS_length_of_stay_days": d["los"],
        "X_gestational_age_weeks": d["ga"],
        "X_birth_weight_g": d["bw"],
        "X_gender": d["Gender"],
        "X_subgroup": d["SubGroup"],
    })


def c01937():
    d, _ = pyreadstat.read_sav(str(WORK / "extracted/RCTC-01937/RCTC-01937/QuitPilot_Participants sp.sav"))
    return pd.DataFrame({
        "Treatment": d["Group"].map({0: "Usual care", 1: "Counselling + pharmacotherapy"}),
        "YP_smoking_abstinence_26w": d["ITTca"],
        "YS_smoking_abstinence_7d": d["ITT7d"],
        "YS_co_ppm_26w": d["T2_COppm"],
        "X_age_years": d["age"],
        "X_gender": d["gender"],
        "X_hads_anxiety_0w": d["HADS_Anx"],
        "X_hads_depression_0w": d["HADS_Dep"],
        "X_cigarettes_per_day_0w": d["cigday"],
    })


def c01948():
    desc = pd.read_excel(WORK / "extracted/RCTC-01948/RCTC-01948/TABLE_1_DESCRIPTION_Database resubmit.xls", sheet_name=0)
    out = pd.read_excel(WORK / "extracted/RCTC-01948/RCTC-01948/TABLE_3_OUTCOME_database resubmit.xls", sheet_name=0)
    desc = desc[desc["Group affiliation: "].astype(str).isin(["1", "2"])].reset_index(drop=True)
    out = out.iloc[-len(desc):].reset_index(drop=True)
    return pd.DataFrame({
        "Treatment": desc["Group affiliation: "].astype(str).map({"1": "Early sitting", "2": "Progressive sitting"}),
        "YP_rankin_3m": out["M3 Rankin score"],
        "YS_nihss_day7": out["Day 7 NIHSS"],
        "YS_barthel_3m": out["M3: Index de Barthel"],
        "X_age_years": desc["Age (year old), rounded"],
        "X_gender": desc["Gender:"],
        "X_rankin_preadmission": desc["Pre-admission Rankin score"],
        "X_nihss_admission": desc[" NIHSS"],
    })


def c05226():
    d = pd.read_excel(ROOT / "manually-download-raw-data/RCTC-05226.xls", sheet_name="Dataset ")
    fp_type = d.get("fp_type", pd.Series(index=d.index, dtype=object)).astype(str)
    return pd.DataFrame({
        "Treatment": pd.Categorical(d["Group"], categories=["Control- no SMS", "PP Checklist Only", "PP Checklist & PNC General", "PP Checklist & FP SMS"], ordered=True),
        "YP_family_planning_uptake": d["q30_fp_use"].map({"no": 0, "yes": 1}),
        "YS_sought_treatment_postpartum": d["seek_advice2"].map({"no": 0, "yes": 1}),
        "YS_chose_longacting_fp": fp_type.str.contains("IUCD|implant", case=False, na=False).astype(float),
        "X_education": d["education"],
        "X_marital_status": d["marital_status"],
        "X_number_pregnancies": d["number_pregnancies"],
        "X_ever_used_fp": d["ever_used_fp"],
        "X_hospital": d["Hospital"],
    })


TRIALS = [
    (97, "RCTC-00152", "Effect of a tailored multidimensional intervention on care burden", c00152, "10.5061/dryad.gf1vhhmm5"),
    (98, "RCTC-00166", "P. vivax/P. ovale hypnozoite reservoir trial", c00166, "10.5061/dryad.m1n03"),
    (99, "RCTC-00167", "Education and support package for stroke patients/carers", c00167, "10.5061/dryad.4ms68"),
    (100, "RCTC-00170", "rhTM for severe septic DIC", c00170, "10.5061/dryad.2n6v4"),
    (101, "RCTC-00173", "AMIGOS geriatric intervention economic evaluation", c00173, "10.5061/dryad.6vh02"),
    (102, "RCTC-00175", "Adjunctive clindamycin for cellulitis", c00175, "10.5061/dryad.5q1j0"),
    (103, "RCTC-00180", "TEAM MMHU economic evaluation", c00180, "10.5061/dryad.90p17"),
    (104, "RCTC-00181", "Preadmission clinic pharmacist collaborative prescribing", c00181, "10.5061/dryad.81tr1"),
    (105, "RCTC-00888", "Exercise program for pregnant women with obesity", c00888, "10.5061/dryad.87f03"),
    (106, "RCTC-00890", "Third wave cognitive therapy versus MBT", c00890, "10.5061/dryad.2d7h5"),
    (107, "RCTC-00893", "ED professional soft tissue injury management", c00893, "10.5061/dryad.8jf11"),
    (108, "RCTC-01313", "AKI alert randomized trial", c01313, "10.5061/dryad.4f4qrfj95"),
    (109, "RCTC-01363", "Vitamin K1/K2 vascular calcification trial", c01363, "10.5061/dryad.vx0k6djsv"),
    (110, "RCTC-01383", "Ferumoxytol versus oral iron in pregnancy", c01383, "10.5061/dryad.k3j9kd5qd"),
    (111, "RCTC-01888", "Abacus cognitive training app", c01888, "10.5061/dryad.1ns1rn8zx"),
    (112, "RCTC-01926", "NTrainer oral stimulation in preterm infants", c01926, "10.5061/dryad.rg57q6m"),
    (113, "RCTC-01937", "QuitPilot stroke/TIA smoking cessation", c01937, "10.5061/dryad.p67jf576"),
    (114, "RCTC-01948", "SEVEL early sitting in ischemic stroke", c01948, "10.5061/dryad.jh15q"),
    (115, "RCTC-05226", "SMS postpartum behaviors and family planning", c05226, "10.5061/dryad.866t1g1nw"),
]


NOT_QUALIFIED = [
    ("RCTC-00079", "not_qualified", "Public data do not expose randomized arm/model assignment in participant table."),
    ("RCTC-00135", "not_qualified", "No associated main journal publication identified on the Dryad record; keep out of active set until resolved."),
    ("RCTC-00158", "not_qualified", "Not an RCT participant-level dataset; graph data for representativeness study."),
    ("RCTC-00161", "not_qualified", "Publication/data title is non-randomised controlled trial; table not participant-level outcome data."),
    ("RCTC-00896", "not_qualified", "Survey summary workbook lacks clear participant-level treatment assignment."),
    ("RCTC-01383", "qualified_cleaned", "Publication-backed individual RCT; cleaned despite treatment signal missed by first-pass detector."),
    ("RCTC-01810", "not_qualified", "Summary workbook is aggregate-level, not participant-level."),
    ("RCTC-01873", "not_qualified", "WINGS intervention dataset lacks individual treatment assignment sufficient for compact RCT cleaning."),
    ("RCTC-01889", "not_qualified", "SPSS file contains summarized group variables, not participant-level rows."),
    ("RCTC-01934", "not_qualified", "Figure-source workbook is aggregate/figure data, not participant-level trial data."),
    ("RCTC-01941", "not_qualified", "Dryad record states non-randomized single-arm interventional trial."),
    ("RCTC-05141", "not_qualified", "Combined depression database has multiple studies/stages; randomized sertraline contrast not cleanly isolated for this pass."),
    ("RCTC-05210", "not_qualified", "Randomized crossover design; not added to non-clustered parallel-arm benchmark without a prespecified crossover handling rule."),
    ("RCTC-05223", "not_qualified", "Already original benchmark / duplicate DOI signal in screening records."),
    ("RCTC-05235", "not_qualified", "Household-randomized trial; excluded from non-clustered benchmark."),
    ("RCTC-05250", "not_qualified", "Patient-preference arm and raw sheet formatting require treatment/filter reconciliation before compact cleaning."),
]


def sanitize(df):
    out = df.copy()
    out = out.loc[:, ~out.columns.duplicated()]
    out = out.dropna(how="all")
    out = out[[c for c in out.columns if c == "Treatment" or c.startswith(("YP_", "YS_", "X_"))]]
    if "Treatment" not in out or not any(c.startswith("YP_") for c in out.columns):
        raise ValueError("missing Treatment or YP column")
    return out


def write_rds(csv_path, rds_path):
    script = f"""
d <- read.csv({json.dumps(str(csv_path))}, check.names=FALSE, stringsAsFactors=FALSE)
d$Treatment <- factor(d$Treatment, levels=unique(d$Treatment[!is.na(d$Treatment) & d$Treatment != ""]))
saveRDS(d, {json.dumps(str(rds_path))})
"""
    subprocess.run(["Rscript", "-e", script], check=True)


def audit_rows(trial_id, cid, df):
    rows = []
    treatment_counts = df["Treatment"].value_counts(dropna=False)
    for arm, count in treatment_counts.items():
        rows.append({
            "Trial_ID": trial_id,
            "candidate_id": cid,
            "outcome_variable": "Treatment",
            "outcome_role": "allocation",
            "arm": arm,
            "statistic": "n",
            "paper_value": "",
            "cleaned_value": int(count),
            "status": "descriptive_recovered",
            "notes": "Arm counts recovered from cleaned participant-level data.",
        })
    primary = [c for c in df.columns if c.startswith("YP_")][0]
    for arm, part in df.groupby("Treatment", dropna=False):
        x = pd.to_numeric(part[primary], errors="coerce")
        rows.append({
            "Trial_ID": trial_id,
            "candidate_id": cid,
            "outcome_variable": primary,
            "outcome_role": "primary",
            "arm": arm,
            "statistic": "mean",
            "paper_value": "",
            "cleaned_value": float(x.mean()) if x.notna().any() else "",
            "status": "descriptive_recovered",
            "notes": "Primary-outcome descriptive mean computed for publication summary-stat screen.",
        })
    return rows


def main():
    CLEAN_DIR.mkdir(parents=True, exist_ok=True)
    rows = []
    dictionary = []
    audits = []
    validation = []
    for trial_id, cid, title, fn, doi in TRIALS:
        df = sanitize(fn())
        csv_path = CLEAN_DIR / f"trial{trial_id}.csv"
        rds_path = CLEAN_DIR / f"trial{trial_id}.rds"
        df.to_csv(csv_path, index=False)
        write_rds(csv_path, rds_path)
        rows.append({
            "Trial_ID": trial_id,
            "candidate_id": cid,
            "source_title": title,
            "dataset_doi": doi,
            "cleaned_csv": str(csv_path.relative_to(ROOT)),
            "cleaned_rds": str(rds_path.relative_to(ROOT)),
            "decision": "qualified_cleaned",
            "notes": "Publication-backed participant-level randomized trial with recoverable treatment and outcome variables.",
        })
        validation.append({
            "Trial_ID": trial_id,
            "candidate_id": cid,
            "rows": len(df),
            "columns": len(df.columns),
            "treatment_arms": df["Treatment"].nunique(dropna=True),
            "primary_outcomes": sum(c.startswith("YP_") for c in df.columns),
            "status": "pass" if df["Treatment"].nunique(dropna=True) >= 2 and any(c.startswith("YP_") for c in df.columns) else "fail",
        })
        for c in df.columns:
            dictionary.append({
                "Trial_ID": trial_id,
                "candidate_id": cid,
                "variable_name": c,
                "variable_type": "Treatment assignment" if c == "Treatment" else ("Primary outcome" if c.startswith("YP_") else ("Secondary outcome" if c.startswith("YS_") else "Baseline covariate")),
                "brief_explanation": c.replace("_", " "),
            })
        audits.extend(audit_rows(trial_id, cid, df))

    for cid, decision, reason in NOT_QUALIFIED:
        if cid not in {r["candidate_id"] for r in rows}:
            rows.append({"Trial_ID": "", "candidate_id": cid, "source_title": "", "dataset_doi": "", "cleaned_csv": "", "cleaned_rds": "", "decision": decision, "notes": reason})

    pd.DataFrame(rows).sort_values(["decision", "candidate_id"]).to_csv(WORK / "manual_final_decisions.csv", index=False)
    pd.DataFrame(dictionary).to_csv(WORK / "manual_cleaned_data_dictionary.csv", index=False)
    pd.DataFrame(audits).to_csv(WORK / "manual_summary_statistics_audit.csv", index=False)
    pd.DataFrame(validation).to_csv(WORK / "manual_validation_summary.csv", index=False)
    print(json.dumps({"cleaned_trials": len(TRIALS), "not_qualified": len([r for r in rows if r["decision"] == "not_qualified"])}, indent=2))


if __name__ == "__main__":
    main()
