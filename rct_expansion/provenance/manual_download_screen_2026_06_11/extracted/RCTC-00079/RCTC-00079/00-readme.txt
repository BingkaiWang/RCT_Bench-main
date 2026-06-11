This README file was generated on 2026-02-23 (YYYY-MM-DD) by Solveig Konst.
Last updated: 2026-04-13


-------------------
GENERAL INFORMATION
-------------------

// Title of Dataset: Background data for: Patient-Tailored Levothyroxine Dosage with Pharmacokinetic/Pharmacodynamic Modeling: A Novel Approach After Total Thyroidectomy

// DOI:  https://doi.org/10.18710/T5BQ22

// Contact Information
     // Name: Vegard Brun
     // Institution: UiT The Arctic University of Norway
     // Email: vegard.h.brun@uit.no
     // ORCID: https://orcid.org/0000-0002-4136-3073

// Contributors: See metadata field Contributor.
// Data Type: See metadata field Data Type.
// Date of Collection: See metadata field Date of Collection.
// Geographic location: See metadata section Geospatial Metadata.
// Funding sources: See metadata section Funding Information.

// Description of dataset:

This dataset constitutes the background data for the study: Patient-Tailored Levothyroxine Dosage with Pharmacokinetic/Pharmacodynamic Modeling: A Novel Approach After Total Thyroidectomy (doi: 10.1089/thy.2021.0125).The study's objective was to investigate whether a new pharmacokinetic/pharmacodynamic model for Levothyroxine dosage lead to better and faster levothyroxine dosage. Patients >18 years with a planned total thyroidectomy were eligible for participation. 

Data were collected in two phases. The first phase, conducted from 2016 to 2017, comprised the pilot study. Data from the pilot study was used to develop the pharmacokinetic/pharmacodynamic model.     

The second phase, conducted from 2017 to 2019, consisted of a randomised controlled trial utilizing the Pharmacokinetic/pharmacodynamic model for calculating each patient's optimal levothyroxine dosage. 

Data collected in the two phases are patient demographics, laboratory results and levothyroxine dosage. Laboratory results and levothyroxine dosage were collected at multiple time points during the study, both before and after surgery. Data from the pilot study and the RCT have been merged and anonymised.

All participants provided written informed consent for data collection. 


--------------------------
METHODOLOGICAL INFORMATION
--------------------------

Description of methods used for collection/generation and processing of data: 

Patients from two Norwegian hospitals (University Hospital of North Norway and Haukeland University Hospital) and one Swedish hospital (Västervik Hospital) were recruited prior to surgery (total or completion thyroidectomy). All patients provided written informed consent.
Data were collected prospectively and at multiple time points during the study. All data were collected from the hospital's electronic health record or directly from the patient. Data collection was performed by the treating physician or by a study nurse.
All data were manually recorded and stored in REDcap during the study.

Time points for data collection:
1) Pre-operative data:
The first data collection was conducted upon recruitment and prior to surgery. Patient demographics and results from preoperative blood samples were recorded. 

2) Post-operative data:
After surgery patients were prescribed a single daily oral dosage of levothyroxine according to normal clinical practise at the clinic. Dosage was recorded. Each patients individual TSH-target was decided and recorded. 
Patients were instructed to give four additional blood samples for measuring thyroid function during the first two weeks postoperatively. The blood samples were to be spread evenly throughout the two week period, but not on specific days. Most samples were taken in an out patient setting and generally analyzed at the same laboratory for each patient. Blood samples were analysed using standard procedures at the respective laboratories. FT4 values were in most cases given with no decimals, FT3 values with single decimal and TSH with two decimal precision.

2) Two weeks postoperatively:
Patients in the RCT had a follow up appointment by telephone by the treating physician. Results from the previous blood samples were recorded and the levothyroxine dosage adjusted according to this. 

3) Eight weeks postoperatively:
All patients had a follow up with the treating physician. Blood samples for measuring thyroid function were done and the levothyroxine dosage adjusted according to the results from the blood samples. 

4) After the first eight weeks:
Patients had follow up appointments every eight week with new blood samples and adjustment of Levothyroxine dosage. This continued until the patient reached the target TSH or dropped out of the study for other reasons. 


After the last patient had finished the study, all data were transfered to Microsoft Excel. Data from the pilot study and the RCT were then combined and anonymised.
All dates have been transformed to number of days after surgery (days before surgery have negative value). Because Levothyroxine have fixed tablet strengths, some patients have different dose on different days of the week. To simplify the dataset all dosages have been transformed to average daily dose.  
Please see data specific information below for additional information on data processing. 
 
--------------------
DATA & FILE OVERVIEW
--------------------

// File List: 
The dataset consists of four data files, one copy of the consent form and one readme file. 

Documentation:
- 00-readme.txt (plain text file)
This file (= the current document) contains the documentation of the dataset.

Data:
- Patient-demographic.txt (Tab delimited text)
- Lab-results.txt (Tab delimited text)
- Levothyroxine-Dosage.txt (Tab delimited text)
- Thyrogen-Dosage.txt (Tab delimited text)

Other:
- consent-form.pdf
- data-privacy-assessment.pdf


------------------------------
DATA-SPECIFIC INFORMATION FOR: Patient-demographic.txt
------------------------------

// Variable/Column List: 
- Patient No.: Patient ID
- Height (cm): Patient height in cm
- Weight (kg): Patient weight in kg
- Sex: Patient sex, Male or Female
- Diagnosis: Cancer, Goitre or Graves
- Age at surgery (years): Patient's age in years. 

// Missing data codes: 
No missing data in this table


------------------------------
DATA-SPECIFIC INFORMATION FOR: Lab-results.txt
------------------------------

// Variable/Column List: 
- Patient No: Patient ID
- Days after surgery: States number of days after surgery the observation is made. Day 0 is the day of surgery. Negative days (i.e. -22) is days before surgery. 
- Value: Numeric value of the observation
- Analysis: type of lab analysis (TSH, FT4, FT3, Creatinine, Albumine). 
- Unit: The unit of the measurement
- Censored: If the observation is censored or not. Se bullet-point 3. for explanation

// Missing data codes: 
There are no missing data in this table.

// Specialized formats or other abbreviations used: 

Abbreviations: 
- TSH: Thyroid Stimulation Hormone, FT4: Free thyroxine, FT3: Free triiodothyronine

Censoring: 
- For measurements of TSH laboratories have a lower limit of Quantification (LLOQ). For this dataset we have three different LLOQ (0.01, 0.03 and 0.05) depending on which laboratory conducted the analysis. For measurements on the LLOQ, we therefore dont know if the true value is just below the LLOQ or far from it, and the observation is therefore censored.


------------------------------
DATA-SPECIFIC INFORMATION FOR: Levothyroxine-dosage.txt
------------------------------

// Variable/Column List: 
- Patient No: Patient ID
- Days after surgery: States number of days after surgery the observation is made. Day 0 is the day of surgery. Negative days (i.e. -22) is days before surgery.
- Average daily dose: Numeric value of the average daily dose of Levothyroxine
- Unit: Unit of measurement for the observation
- Drug: Drug type. 

// Missing data codes: 
Missing data are represented by empty cells.


------------------------------
DATA-SPECIFIC INFORMATION FOR: Thyrogen-dosage.txt
------------------------------

// Variable/Column List: 
- Patient No: Patient ID
- Days after surgery: States number of days after surgery the observation is made. Day 0 is the day of surgery. Negative days (i.e. -22) is days before surgery.
- Drug: Drug type. 

Only a few of the patients received treatment with thyreotropin alfa. This information is included in the dataset because the treatment may influence the measurements of thyroid function a few days after treatment. 


--------------------------
SHARING/ACCESS INFORMATION
--------------------------
// Licenses/restrictions: See Terms tab.
// Links to publications that cite or use the data: See metadata field Related Publication.
// Data sources: See metadata field Data Sources.
// Recommended citation: See citation generated by repository.