# README: tDCS and Cognitive Training in Schizophrenia

## Overview
This dataset contains clinical, cognitive, and psychopathology data from a **randomized, double-blind, sham-controlled trial** investigating the effects of **transcranial direct current stimulation (tDCS) combined with cognitive training** on cognitive functioning in patients with **schizophrenia (ICD-10: F20)**.

The data correspond to the study published as:  
**Stuchlíková et al., *BMC Psychiatry* (2026)** – *Transcranial direct current stimulation and cognitive training in the treatment of cognitive deficit in schizophrenia*.

---

## Study Design
- **Participants:** Clinically stable patients with schizophrenia (ages 18–50)
- **Groups:**  
  - `treatment = 1` → sham tDCS + cognitive training  
  - `treatment = 2` → active tDCS + cognitive training
- **Intervention duration:**  
  - Mandatory 1 week (5 sessions)  
  - Optional extension to 3 weeks
- **Assessments:**  
  - Cognition: RBANS (Versions A, B, C)  
  - Symptoms: PANSS (baseline, 1 week, 3 weeks)

---

## Data Structure

### Identifiers and Grouping
- **subject** – Participant ID  
- **treatment** – 1 = sham, 2 = active tDCS  
- **sex** – 1 = male, 2 = female  
- **age** – Age in years  

---

### Demographic and Clinical Variables
- **status** – 1 = single, 2 = married  
- **education** – 1 = elementary, 2 = vocational, 3 = high school, 4 = university  
- **employment** – 1 = employed, 2 = unemployed, 3 = disability  
- **laterality** – 1 = right-handed, 2 = left-handed  
- **DOI F20 (years)** – Duration of schizophrenia (years)

---

### Somatic Comorbidities (0 = no, 1 = yes)
- **Hypertension**
- **Arrythmia**
- **Hyperlipidemia**
- **Thyroid Disease**
- **Autoimmune Disorder**
- **Neurological Disorder**
- **Sleep Apnea**

---

### Medication
- **OLZ-eq (mg)** – Olanzapine-equivalent antipsychotic dose (mg/day)  
- **AD** – Antidepressants (0 = no, 1 = yes)  
- **BDZ** – Benzodiazepines (0 = no, 1 = yes)

---

## Cognitive Outcomes (RBANS)

### RBANS Versions
- **RBANS A** – Baseline  
- **RBANS B** – 1-week endpoint  
- **RBANS C** – 3-week endpoint (optional, exploratory)

### Subtests
- List Learning  
- Story Memory  
- Figure Copy  
- Line Orientation  
- Picture Naming  
- Semantic Fluency  
- Digit Span  
- Coding  
- List Recall  
- List Recognition  
- Story Recall  
- Figure Recall  

### Index Scores (IS-RBANS)
- **IM** – Immediate Memory  
- **VC** – Visuospatial/Constructional  
- **LAN** – Language  
- **ATT** – Attention  
- **DM** – Delayed Memory  
- **Total** – Total cognitive score  

---

## Psychopathology Outcomes (PANSS)
Measured at:
- **B** – Baseline  
- **1W** – 1 week  
- **3W** – 3 weeks (optional)

Subscales:
- **PANSS N** – Negative symptoms  
- **PANSS P** – Positive symptoms  
- **PANSS G** – General psychopathology  
- **PANSS Total** – Total score  

---

## Missing Data
- RBANS C and PANSS 3W data are available **only for participants who continued into the optional 3-week extension**.
- Empty cells indicate assessments not performed.

---

## Intended Use
- Analysis of cognitive outcomes following tDCS + cognitive training
- Replication of results reported in Stuchlíková et al. (2026)
- Exploratory analyses of cognition–symptom relationships in schizophrenia

---

## Citation
If you use this dataset, please cite:

> Stuchlíková Z, et al. (2026).  
> *Transcranial direct current stimulation and cognitive training in the treatment of cognitive deficit in schizophrenia: a randomized controlled trial.*  
> **BMC Psychiatry**, 26:102. https://doi.org/10.1186/s12888-025-07749-5

---

## Ethics
Approved by the Ethics Committees of the National Institute of Mental Health and Hospital České Budějovice. Written informed consent obtained from all participants.

