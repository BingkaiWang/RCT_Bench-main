Info on the data files and the aelq R script accompanying the paper:
Vinh-Hung V, Gorobets O, Adriaenssens N, Van Parijs H, Storme G, Verellen D, Nguyen NP, Magne N, De Ridder M.
Lung-Heart Outcomes and Mortality through the 2020 COVID-19 Pandemic in a Prospective Cohort of Breast Cancer Radiotherapy Patients.
Cancers. 2022; 14(24):6241. https://doi.org/10.3390/cancers14246241

"aelq2_base2.txt" = baseline characteristics.

"aelq3.txt" = longitudinal maesurements.

Variables in "aelq2_base2.txt":

"aelq2_base2.txt" = baseline characteristics. 
# Age at randomization, years. 
# RTdose: cf TomoBreast papers. 
# 51 Gy = hypofractionated, simultaneous integrated boost
# 42 Gy = hypofractionated, no boost, mastectomy cases only
# 50 Gy = conventional, no boost, mastectomy cases only
# 66 Gy = conventional, sequential boost
# Weight kg, Height cm, 
# Detection 1=found by screening (senology follow-up/controle)
# 	2=found by symptoms (pain, palpable)
# 	9=unknown
# Smoker 	0= Not smoker
# 	1= Smoker
# 	2=ex-smoker
# Mastectomy (and other binary coded) 1= yes
# chemosched 0=none
# 	1= planned after RT (sequential)
# 	2= prior to RT and is finished (sequential)
# 	3= chemo is on-going or is planned to start with RT (concomitant)
# hormonetherapy 	0=no
# 	1=tamoxifen (nolvadex)
# 	2=Femara (Letrozole)
# 	3=zoladex
# 	4=tamoxifen + zoladex
# Laterality 1,=Right, 2=Left, 3=Bilateral
# LengthFU: length of follow-up, days from randomization

"aelq3.txt" = longitudinal maesurements.
# "Nr" = Case ID
# "Time" in days from origin (origin =date of randomization), 
# if negative =before randomization
#    "KPS"       "Weight"    
# "Died"      "LocalRec"  "Metast"    "NewPrim"   = binary code, 0=no, 1=yes
# "fAEBreast" "fAEHeart"  "fAELung"   "fAEOther" 
# fAE = freedom from breast, heart, lung, other adverse event score
# "LVEF2" = ejection fraction, %
# "MacIver" = estimated cardiac strain

# the following are pulmonary function tests, untransformed units
# "FVC", "FEV1", "PEF", "VC", "TLC", "RV", "FRC", "Raw", "sRaw", "DLCO",
# "VA", "PF"

# "fDY", "fFA", "fPA" = freedom from dyspnea, from fatigue, from pain
# range 0 to 100 (best)
# see paper:
# Van Parijs, H.; Vinh-Hung, V.; Fontaine, C.; Storme, G.; Verschraegen, C.;
# Nguyen, D.M.; Adriaenssens, N.; Nguyen, N.P.; Gorobets, O.; De Ridder, M.
# Cardiopulmonary-related patient-reported outcomes in a randomized clinical
# trial of radiation therapy for breast cancer. BMC Cancer 2021, 21, 1177,
# doi:10.1186/s12885-021-08916-z.
# 
# "Year" = year of the observation
# example: randomized 1/1/2011, measurement done 1/31/2011, time = 30 days,
# Year =2011
#
