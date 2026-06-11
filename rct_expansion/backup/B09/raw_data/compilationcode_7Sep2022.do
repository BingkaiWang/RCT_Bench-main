cd "/Volumes/Work/Work Space/Projects/Dataverse/MPYA"

use "/Volumes/Work/Work Space/Projects/MPYA/Projects/Jessica Haberer/Aim 1/Work/redcapv2.dta", clear

drop enrage redcap_event_name democode esxdate drugdrunk demopleas demodown eipvslap eipvkick eipvsex demodate visitcode_old

label var ptid "Participant ID:"
label define site 0 "Kisumu" 1 "Thika"
label values site site
label var site "Study site"
label var arm "Randomized study arm"
label var scrnage "3. What is your age?"
label var scrnpreg "5. Are you pregnant?"
label var scrnsex "13. Have you had vaginal or anal sex in at least once within the past 3 months?"
label var scrnsd "14. Are you in a serodiscordant relationship, meaning that you have a sexual partner who has HIV?"
label var scrnpartner "15. Are you married or living with husband/steady partner?"
label var scrnsupport "16. Do you have a partner who provides financial/material support?"
label var scrnalcohol "18. Have you used any alcohol in the past 3 months?"
label var scrnscore "Calculated Risk Score"
label var drugsmok "6. Have you smoked cigarettes in the past three months?"
label var drugdrugbl "7. Have you used other recreational drugs in the past three months?"
*note drugsmok "baseline asks..."
rename drugdrugname___1 drugname_khat
rename drugdrugname___2 drugname_bhangi
rename drugdrugname___3 drugname_heroin
rename drugdrugname___4 drugname_cocaine
rename drugdrugname___5 drugname_kuber
rename drugdrugname___6 drugname_shisha
rename drugdrugname___7 drugname_other
label values drugname_khat yesno
label values drugname_bhangi yesno
label values drugname_heroin yesno
label values drugname_cocaine yesno
label values drugname_kuber yesno
label values drugname_shisha yesno
label values drugname_other yesno

label var drugname_khat "Khat"
label var drugname_bhangi "Bhangi"
label var drugname_heroin "Heroine"
label var drugname_cocaine "Cocaine"
label var drugname_kuber "Kuber"
label var drugname_shisha "Shisa"
label var drugname_other "Other drug"

label var drugsmokbl "6. Have you ever smoked cigarettes?"
label var raps4_positive "Positive response from the Rapid Alcohol Problems Screen (RAPS4)"
label values raps4_positive yesno
label var eduyrs "1. Number of completed years of education"
label var demojob "3. Job/occupation (tick primary employment if more than one applies)"
label var demomarry "4. Marital status"
label var demolive "5. With whom do you live?"
label var demoeat "9. Do you worry about having enough food to eat on most days?"
label var demodaily "11. Have you ever taken a medication daily for more than one week?"
label values demodaily yesno

rename demobc___0 demobc_none 
rename demobc___1 demobc_inj 
rename demobc___2 demobc_imp 
rename demobc___3 demobc_oral 
rename demobc___4 demobc_iud 
rename demobc___5 demobc_dia 
rename demobc___6 demobc_tub 
rename demobc___7 demobc_emer  
rename demobc___8 demobc_con 
rename demobc___9 demobc_other 

label var demobc_none "Birth control - none"
label var demobc_inj "Birth control - Injectable"
label var demobc_imp "Birth control - Implant"
label var demobc_oral "Birth control - Oral"
label var demobc_iud "Birth control - IUD"
label var demobc_dia "Birth control - Diaphragm"
label var demobc_tub "Birth control - Tubal ligation/hysterectomy"
label var demobc_emer "Birth control - Emergency contraceptive pill"
label var demobc_con "Birth control - Condoms"
label var demobc_other "Birth control - Other" 


label values demobc_none yesno
label values demobc_inj yesno
label values demobc_imp yesno
label values demobc_oral yesno
label values demobc_iud yesno
label values demobc_dia yesno
label values demobc_tub yesno
label values demobc_emer yesno
label values demobc_con yesno
label values demobc_other yesno


label var demotravel "8. How long did it take you to travel to the clinic today?"
label var depress "Depression score on the 2 Depression Questions"

label var depressbi "Scoring >=3 on depression score"

label var riskgmbl "Gambling risk score"

label define riskfut 1 "Not all all" 2 "Sometimes" 3 "A lot"
label values riskfut riskfut
label var riskfut "9. Generally speaking, how much do you think about the future?"
label define riskhiv 1 "Yes" 0 "No" 2 "Not sure"
label values riskhiv riskhiv
label var riskhiv "10. In thinking about the past month, do you think you were at risk for getting HIV?"

label var srpower "Sexual relationship power score"
label var srpowercat "Categories of Sexual relationship power"
label var totpart "1. How many sexual partners do you have currently"
label var esxphiv "2. To your knowledge do any of your sexual partners have HIV?"
label define esxphiv 1 "Yes" 0 "No" 2 "Don't Know"	
label values esxphiv esxphiv
label var sexacts "3. In the past month how many times did you have sex with a main partner?"
label var unsafe_sex  "Sex without a condom"
label values unsafe_sex yesno

label var prepdisc "2. Does anyone know you will be/are taking PrEP?"
label var srppart "1. Does participant identify a primary sexual relationship?"
label values srppart yesno

rename prepdiscwho___1 prepdisc_sexpart
rename prepdiscwho___2 prepdisc_friend
rename prepdiscwho___3 prepdisc_family
rename prepdiscwho___4 prepdisc_other

label values prepdisc_sexpart yesno
label values prepdisc_friend yesno
label values prepdisc_family yesno
label values prepdisc_other yesno

label var prepdisc_sexpart "PrEP diclosure to sexual partner"
label var prepdisc_friend "PrEP diclosure to friend" 
label var prepdisc_family "PrEP diclosure to family member"
label var prepdisc_other "PrEP diclosure to other"

label var prepstress "7. Everyone has stress in their lives; has taking PrEP affected the stress in your life?"

label var necessity "Necessity score"
label var necessitytert "Tertiles of Concerns score"

label var selfesteem "Self esteem score"
label var selfesteemlow "Low self esteem"

label var ipv "Intimate Partner Violence" 
label values ipv yesno

label var hivstigma "HIV Stigma score"
label var hivstigmatert "Tertiles of HIV Stigma score"

label var prepstigma "PrEP stigma score"
label var prepstigmatert "Tertiles of PrEP Stigma score"

label var concerns "Concerns score"
label var concernstert "Tertiles of PrEP Concerns score"

* deidentifying dates 
replace date=date-20809
label var date "Days from study start"
format date %9.0g 
recode scrnage (18/20=0 "18-20") (21/24=1 "21-24"), gen(scrnage_cat)
drop scrnage
move drugdrugbl drugname_khat
move scrnage_cat scrnsex
save questionnaire.dta, replace 

* Adherence (Prep and Pharmacy)
use "/Volumes/Work/Work Space/Projects/MPYA/Projects/Jessica Haberer/Aim 1/Work/adh_summaryv2.dta", clear
replace previsitdt=previsitdt-20809
replace visitdt=visitdt-20809
format previsitdt %9.0g
format visitdt %9.0g
drop fprepdate 
label var previsitdt "Previous study visit date"
label var visitdt "Study visit date"
label var prep_adh_m "PreP adherence from previous to present study visit"
label var prep_adh_p "Total PrEP adherence"
label var pharm_adh_m "Pharmacy adherence from previous to present study visit"
label var pharm_adh_p "Total pharmacy adherence" 
rename prep_fupm prep_fup 
rename pharm_fupm pharm_fup 
label var prep_fup "Total PrEP adherence followup"
label var pharm_fup "Total pharmacy adherence followup"
label var ptid "Participant identier"
save adherence.dta, replace 



* DBS
use "/Volumes/Work/Work Space/Projects/MPYA/Projects/Jessica Haberer/DBS vs Wisepill adherence/mpya_dbs.dta", clear
keep ptid dbstfvdp freezethawissue  collectiondate dbs_adj visitcode hb
label var dbstfvdp "Raw dbs results"
label var freezethawissue "Whether the sample experienced the thawing problem"
label var collectiondate "Days from study start to sample collectiondate"
replace collectiondate=collectiondate-20809
format collectiondate %9.0g
label var dbs_adj "DBS with adjustment for Hb<11"
label var hb "Hemoglobin"
label var ptid "Participant identifier"
save dbs.dta, replace 


