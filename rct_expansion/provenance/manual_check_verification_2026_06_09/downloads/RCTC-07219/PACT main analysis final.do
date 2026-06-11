clear* Set working directory below*cd "C:/Users/juliagoldberg/Desktop/PACT final submission"cd /Users/juliagoldberg/Desktop/PACTsubmission"* Load workfileuse PACT_30March2012.dta, clear* Merge on wealth quintiledrop _mergesort IDmerge ID using "Wealth Index HL April 2011.dta"tab _mergedrop _merge********************************************* Primary Outcome Variables********************************************** Self-reported adherence (P35) 
* "Did the patient complete the full dosage of this ACT drug?"gen adhered_SR = .replace adhered_SR = 1 if p35==1replace adhered_SR = 0 if p35==2* Remaining ACTs in householdgen ACT_stock =.replace ACT_stock = 0 if k4==0replace ACT_stock =1 if k4>0 & k4<15* add those with no drugs at allreplace ACT_st = 0 if k1==2*exclude refusalsreplace ACT_stock = . if k2==2label var ACT_stock "ACTs in household"* Observed pillsgen pills = p33_leftreplace pills = . if p33_left<0 | p33_left>50replace pills =1 if p33_left>0 & p33_left<50tab adhered_SR pills*Per-dose self reportgen not_finished = .replace not_finished= 1 if p16b_portion<0 replace not_finished = 0 if p16b_portion>0********************************************* Secondary Outcome Variable: Health********************************************* Still sick gen still_sick = .replace still_sick = 1 if m1_symptoms==1replace still_sick = 0 if m1_symptoms==2 replace still_sick = . if m1_s<0 | m1_s ==.* Early recoverygen early_recovery = m1a_feelbetter>1 & m1a_feel!=.replace early_recovery = . if m1a_feelbetter< 0 | m1a_feelbetter==.replace early_recovery = 0 if m1a_feelbetter==-555********************************************* Patient Control variables********************************************* Drug regimen
gen drug = . 
replace drug =1 if b4_drugcode_1==1
replace drug =1 if b4_drugcode_1==2
replace drug =1 if b4_drugcode_1==3
replace drug =2 if b4_drugcode_1==4
replace drug =2 if b4_drugcode_1==5
replace drug =2 if b4_drugcode_1==6
replace drug =2 if b4_drugcode_1==7
replace drug =2 if b4_drugcode_1==8
replace drug =1 if b4_drugcode_1==10
replace drug =1 if b4_drugcode_1==11
replace drug =1 if b4_drugcode_1==12
replace drug =1 if b4_drugcode_1==13
replace drug =1 if b4_drugcode_1==14
replace drug =1 if b4_drugcode_1==15
replace drug =1 if b4_drugcode_1==16
replace drug =1 if b4_drugcode_1==17
replace drug =1 if b4_drugcode_1==18
replace drug =1 if b4_drugcode_1==19
replace drug =1 if b4_drugcode_1==20
replace drug =2 if b4_drugcode_1==23
replace drug =3 if b4_drugcode_1==24

replace drug =1 if p27_ACTname==1
replace drug =1 if p27_ACTname==2
replace drug =1 if p27_ACTname==3
replace drug =2 if p27_ACTname==4
replace drug =2 if p27_ACTname==5
replace drug =2 if p27_ACTname==6
replace drug =2 if p27_ACTname==7
replace drug =2 if p27_ACTname==8
replace drug =1 if p27_ACTname==10
replace drug =1 if p27_ACTname==11
replace drug =1 if p27_ACTname==12
replace drug =1 if p27_ACTname==13
replace drug =1 if p27_ACTname==14
replace drug =1 if p27_ACTname==15
replace drug =1 if p27_ACTname==16
replace drug =1 if p27_ACTname==17
replace drug =1 if p27_ACTname==18
replace drug =1 if p27_ACTname==19
replace drug =1 if p27_ACTname==20
replace drug =2 if p27_ACTname==23
replace drug =3 if p27_ACTname==24
replace drug =4 if drug==.

tab drug, gen(drugdum)*Malegen male = .replace male = 1 if h2_respsex ==1 & h1_resptype==1replace male = 0 if h2_respsex ==2 & h1_resptype==1replace male = 1 if j1a_patsex==1 replace male = 0 if j1a_patsex == 2replace male = 2 if male==.tab male, gen(maledum)*Patient agegen age_group = 0 label define age_group 0 "Unknown" 1 "Under 5" 2 "Age 5-17" 3 "Age 18-59" 4 "Age 60 and over"label values age_group age_group* Patient respondentreplace age_group = 1 if h3_respage>= 0 & h3_respage<5replace age_group = 2 if h3_respage>= 5 & h3_respage<18replace age_group = 3 if h3_respage>= 18 & h3_respage<60replace age_group = 4 if h3_respage>= 60 & h3_respage<95replace age_g = 1 if age_g == 0 & h3a>0 & h3a<3 replace age_g = 2 if age_g == 0 & h3a>2 & h3a<6replace age_g = 3 if age_g == 0 & h3a>5 & h3a<9replace age_g = 4 if age_g == 0 & h3a>8 & h3a<15* Proxy respondentsreplace age_g= 1 if j2_patage >= 0 & j2_patage<5replace age_g= 2 if j2_patage >= 5 & j2_patage<18replace age_g = 3 if j2_patage >= 18 & j2_patage<60replace age_g = 4 if j2_patage >= 60 & j2_patage<95replace age_g = 1 if age_g == 0 & j2a>0 & j2a<3 replace age_g = 2 if age_g == 0 & j2a>2 & j2a<6replace age_g = 3 if age_g == 0 & j2a>5 & j2a<9replace age_g = 4 if age_g == 0 & j2a>8 & j2a<15tab age_g, gen(agedum)* Non-participantsgen age_cat = 0label define age_cat 0 "Unknown" 1 "Under 5" 2 "Age 5-17" 3 "Age 18-59" 4 "Age 60 and over"label values age_cat age_catreplace age_cat = 1 if b2_a>= 0 & b2_a<5replace age_cat = 2 if b2_a>= 5 & b2_a<18 replace age_cat = 3 if b2_a>= 18 & b2_a<60 replace age_cat = 4 if b2_a>= 60 & b2_a<95 replace age_c = 1 if age_c == 0 & b2a>0 & b2a<3 replace age_c = 2 if age_c == 0 & b2a>2 & b2a<6replace age_c = 3 if age_c == 0 & b2a>5 & b2a<9replace age_c = 4 if age_c == 0 & b2a>8 & b2a<15tab age_c, gen(age_c_dum)* Reference groups just adults and children gen chad = .replace chad = 1 if age_g==1replace chad = 1 if age_g==2replace chad = 2 if age_g==3replace chad = 2 if age_g==4replace chad = 3 if age_g==0tab chad, gen(chaddum). gen inter = chaddum1*drugdum1

. gen inter2 = chaddum1*drugdum2

. gen inter3 = chaddum3*drugdum2

. gen inter4 = chaddum3*drugdum1
********************************************* Household Control variables*********************************************MALE HH HEADgen male_head = .replace male_head = 1 if b5_HHhead_male==1replace male_head = 0 if b5_HHhead_male==2replace male_head = 2 if male_head==.tab male_head, gen(mheaddum)* Education of head: gen head_none = .replace head_none = 1 if b7_ed_HHhead==1replace head_none = 0 if b7_ed>1 & b7_ed<16gen head_some = .replace head_some = 1 if b7_ed_HHhead >3 & b7_ed_HHhead<11replace head_some = 1 if  b7_ed_HHhead >13 & b7_ed_HHhead<15replace head_some = 0 if b7_ed <4 replace head_some = 0 if b7_ed > 10 & b7_ed < 14gen head_higher = .replace head_higher = 1 if b7_ed_HHhead >10 & b7_ed_HHhead<14replace head_higher = 0 if b7_ed < 11gen head_ed=.replace head_ed=1 if head_none==1replace head_ed=2 if head_some==1replace head_ed=3 if head_high==1replace head_ed=4 if head_ed==.tab head_ed, gen(headdum)* Wealth indextab wealth_qreplace wealth_q = 6 if wealth_q==.tab wealth_q, gen(adum)********************************************* Facility Control variables********************************************gen vendor = . replace vendor = 1 if y4_vendcode==2061 | y4_vendcode==2063| y4_vendcode==2068 | y4_vendcode==2075 ///
| y4_vendcode==2076| y4_vendcode==2087 | y4_vendcode==2100 | y4_vendcode==2131 | y4_vendcode==2150 /// 
| y4_vendcode==2164 | y4_vendcode==2176 | y4_vendcode==2192 | y4_vendcode==2198 | y4_vendcode==2209

replace vendor = 2 if y4_vendcode>2000 & y4_vendcode<2053 | y4_vendcode==2169replace vendor = 2 if y4_vendcode>2053 & y4_vendcode<2058 | y4_vendcode==2060replace vendor = 2 if y4_vendcode>2063 & y4_vendcode<2070 | ///
y4_vendcode>2070 & y4_vendcode<2075 | y4_vendcode>2076 ///
& y4_vendcode<2086 | y4_vendcode>2088 & y4_vendcode<2110 | ///
y4_vendcode>2111 & y4_vendcode< 2120 | y4_vendcode>2120 & ///
y4_vendcode==2129 | y4_vendcode>2132 & y4_vendcode<2150 ///
| y4_vendcode>2150 & y4_vendcode==2156 | y4_vendcode>2156 & ///
y4_vendcode<2161 | y4_vendcode>2161 & y4_vendcode<2169 | ///
y4_vendcode>2169 & y4_vendcode< 2176 | y4_vendcode>2176 ///
& y4_vendcode<2183 | y4_vendcode>2183 &  y4_vendcode<2191 ///
| y4_vendcode>2192 & y4_vendcode<2198 | y4_vendcode>2200 & ///
y4_vendcode<2202 | y4_vendcode>2203 & y4_vendcode< 2209 | ///
y4_vendcode>2210 & y4_vendcode<2219
replace vendor = 3 if y4_vendcode==2059 | y4_vendcode==2086 | y4_vendcode==2088 | y4_vendcode==2097 ///
| y4_vendcode==2136 | y4_vendcode==2191 | y4_vendcode==2222 | y4_vendcode==2156
 
replace vendor = 4 if y4_vendcode==2111 | y4_vendcode== 2186

replace vendor = 5 if y4_vendcode==2053 | y4_vendcode==2058 | y4_vendcode== 2116  ///
 | y4_vendcode== 2161 | y4_vendcode== 2183 | y4_vendcode==2202 | y4_vendcode==2159

replace vendor = 6 if y4_vendcode==2185 | y4_vendcode==2199 | y4_vendcode==2200| y4_vendcode==2203replace vendor = 7 if y4_vendcode==2115

replace vendor = 8 if y4_vendcode==2120 | y4_vendcode==2130 | y4_vendcode==2219

replace vendor = 9 if y4_vendcode==2110 | y4_vendcode==2147
tab vendor, gen(venddum)gen private = 0replace private = 0 if vendor ==6replace private = 0 if vendor ==5replace private = 0 if vendor ==7replace private = 0 if vendor ==8replace private = 1 if vendor ==4replace private = 1 if vendor ==3replace private = 1 if vendor ==2replace private = 1 if vendor ==1replace private = 1 if vendor ==9gen formal = 0replace formal = 0 if vendor ==1replace formal = 0 if vendor ==2replace formal = 0 if vendor ==9replace formal = 1 if vendor ==7replace formal = 1 if vendor ==4replace formal = 1 if vendor ==6replace formal = 1 if vendor ==3replace formal = 1 if vendor ==5replace formal = 1 if vendor ==8*********************************************Figure 1: Study Design********************************************tab sampletab treated_atetab message* Why ineligiblegen screened_out = . label define screened_out 1 "no consent" 2 "not ACT" 3 "under 18" 4 "not for HH" 5 "no phone" 6 "distance over 30" 7 "Other"label values screened_out screened_outreplace screened_out = 1 if z1_vconsent==2replace screened_out = 2 if z4b_drug_eligible==2replace screened_out = 3 if z3_over18==2replace screened_out = 4 if z4a_drug4house==2 & z4_drug4you==2replace screened_out = 5 if z7b_phone_eligible==2replace screened_out = 6 if z5_distance==2replace screened_out = 7 if sample==0 & screened==.replace screened_o =. if sample==1tab screened_out************************************************ Table 1: Patients characteristics by group***********************************************gen screened = .label define screened 0 "Screened out" 1 "Eligible but no #" 2 "RCT sample - control" 3 "RCT sample - treatment" label values screened screenedreplace screened = 0 if sample==0replace screened = 1 if sample==1 & treated_ate==.replace screened = 2 if treated_ate==0replace screened = 3 if treated_ate==1tab screened, gen(groupdum)gen groupdum5 = 0replace groupdum5 = 1 if treated_ate!=.* male sextabstat maledum2 if maledum3!=1, by(screened) col(stats) stats(sum mean sd)
tabstat maledum1 if maledum3!=1, by(screened) col(stats) stats(sum mean sd)

* age groups
tabstat age_c_dum2, by(screened) col(stats) stats(sum mean sd)
tabstat age_c_dum3, by(screened) col(stats) stats(sum mean sd)
tabstat age_c_dum4, by(screened) col(stats) stats(sum mean sd)
tabstat age_c_dum5, by(screened) col(stats) stats(sum mean sd)

* male household head
tabstat mheaddum2, by(screened) col(stats) stats(sum mean sd)

* household head educational attainment
tabstat head_none, by(screened) col(stats) stats(sum mean sd)
tabstat head_some, by(screened) col(stats) stats(sum mean sd)
tabstat head_higher, by(screened) col(stats) stats(sum mean sd)

* household wealth
tabstat adum1, by(screened) col(stats) stats(sum mean sd)
tabstat adum2, by(screened) col(stats) stats(sum mean sd)
tabstat adum3, by(screened) col(stats) stats(sum mean sd)
tabstat adum4, by(screened) col(stats) stats(sum mean sd)
tabstat adum5, by(screened) col(stats) stats(sum mean sd)

* Drug type: 
* Artemether lumefantrine 
tabstat drugdum1, by(screened) col(stats) stats(sum mean sd)

* Artesunate amodiaquine
tabstat drugdum2, by(screened) col(stats) stats(sum mean sd)


* Vendor type:
* Pharmacy
tabstat venddum1, by(screened) col(stats) stats(sum mean sd)

*Licensed chemical seller
tabstat venddum2, by(screened) col(stats) stats(sum mean sd)

*Private clinic
tabstat venddum3, by(screened) col(stats) stats(sum mean sd)

*Privae hospital
tabstat venddum4, by(screened) col(stats) stats(sum mean sd)

*Public hospital
tabstat venddum5, by(screened) col(stats) stats(sum mean sd)

*Public clinic
tabstat venddum6, by(screened) col(stats) stats(sum mean sd)


* F-stats and p-valuesgen pvalue = .gen fstat = .local i=1foreach x of varlist age_c_dum2-age_c_dum5 {	reg `x' groupdum1 groupdum5, r	test groupdum1 = groupdum5 = 0	replace fstat = r(F) in `i'	replace pvalue = r(p) in `i'	local i = `i'+1	}		******************************* Figure 2: By Dose Graph******************************FULL SAMPLE:forvalues i=11/16{	local j= `i'-10	gen took`j' = p`i'b_portion>0 	replace took`j' = . if  p`i'b_portion==. 	}* Restrict Figure to adults only in control groupsum took* if age_g>2 & treated_ate==0 & drug==1 sum took* if age_g>2 & treated_ate==0 & drug==2 ************************************************Table 2: Main results***********************************************gen sms_short = message==0gen sms_long  = message==1***** Absolute numberstab treated_ate adhered_SR, rowtab sms_long adhered_SR, row***** Main regressions:logistic adhered_SR treated_ate sms_long maledum1 maledum3 chaddum1 chaddum3 mheaddum1 mheaddum3 headdum1 headdum2 headdum4 adum1-adum4 adum6 venddum1-venddum6 drugdum1-drugdum3 inter* if treated_ate!=., vce(cluster p1a_vendcode)outreg2 using table2, replace eform ci excel*********************************************** Table 3: Subgroup analysis**********************************************

* Tabulations
* Child/adult
tab treated_ate adhered_SR if chaddum1==1, r // children control and tmt
tab treated_ate adhered_SR if chaddum2==1, r // adults control and tmt
tab sms_long adhered_SR if chaddum1==1, r  // children long message
tab sms_long adhered_SR if chaddum2==1, r // adults long message

* Males/females
tab treated_ate adhered_SR if maledum2==1, r // males control and tmt
tab treated_ate adhered_SR if maledum1==1, r // females control and tmt
tab sms_long adhered_SR if maledum2==1, r  // males long message
tab sms_long adhered_SR if maledum1==1, r // females long message

* HH head education
tab treated_ate adhered_SR if head_none==1, r 
tab treated_ate adhered_SR if head_some==1, r 
tab treated_ate adhered_SR if head_higher==1, r 
tab sms_long adhered_SR if head_none==1, r 
tab sms_long adhered_SR if head_some==1, r 
tab sms_long adhered_SR if head_higher==1, r 

* Wealth quintile
tab treated_ate adhered_SR if adum1==1, r 
tab treated_ate adhered_SR if adum2==1, r 
tab treated_ate adhered_SR if adum3==1, r 
tab treated_ate adhered_SR if adum4==1, r 
tab treated_ate adhered_SR if adum5==1, r 
tab sms_long adhered_SR if adum1==1, r 
tab sms_long adhered_SR if adum2==1, r 
tab sms_long adhered_SR if adum3==1, r 
tab sms_long adhered_SR if adum4==1, r 
tab sms_long adhered_SR if adum5==1, r 

* Vendor
tab treated_ate adhered_SR if venddum1==1, r // pharmacy
tab treated_ate adhered_SR if venddum2==1, r // LCS
tab treated_ate adhered_SR if venddum3==1, r // private clinic
tab treated_ate adhered_SR if venddum4==1, r // private hosp
tab treated_ate adhered_SR if venddum5==1, r // public hosp
tab treated_ate adhered_SR if venddum6==1, r // public clinic
tab sms_long  adhered_SR if venddum1==1, r 
tab sms_long  adhered_SR if venddum2==1, r 
tab sms_long  adhered_SR if venddum3==1, r 
tab sms_long  adhered_SR if venddum4==1, r 
tab sms_long  adhered_SR if venddum5==1, r 
tab sms_long  adhered_SR if venddum6==1, r 

* Drug
tab treated_ate adhered_SR if drugdum1==1, r // AL
tab treated_ate adhered_SR if drugdum2==1, r // AS+AQ
tab sms_long adhered_SR if drugdum1==1, r // AL
tab sms_long adhered_SR if drugdum2==1, r // AS+AQ



* Regressionslogistic adhered_SR treated_ate sms_long maledum1 maledum3 chaddum1 chaddum3 mheaddum1 mheaddum3 headdum1 headdum2 headdum4 adum1-adum4 adum6 venddum1-venddum6 drugdum1-drugdum3 inter* if chaddum1==1 & treated_ate!=., vce(cluster p1a_vendcode)logistic adhered_SR treated_ate sms_long maledum1 maledum3 chaddum1 chaddum3 mheaddum1 mheaddum3 headdum1 headdum2 headdum4 adum1-adum4 adum6 venddum1-venddum6 drugdum1-drugdum3 inter* if chaddum2==1 & treated_ate!=., vce(cluster p1a_vendcode)logistic adhered_SR treated_ate sms_long maledum1 maledum3 chaddum1 chaddum3 mheaddum1 mheaddum3 headdum1 headdum2 headdum4 adum1-adum4 adum6 venddum1-venddum6 drugdum1-drugdum3 inter* if male==0 & treated_ate!=., vce(cluster p1a_vendcode)logistic adhered_SR treated_ate sms_long maledum1 maledum3 chaddum1 chaddum3 mheaddum1 mheaddum3 headdum1 headdum2 headdum4 adum1-adum4 adum6 venddum1-venddum6 drugdum1-drugdum3 inter* if male==1 & treated_ate!=., vce(cluster p1a_vendcode)logistic adhered_SR treated_ate sms_long maledum1 maledum3 chaddum1 chaddum3 mheaddum1 mheaddum3 headdum1 headdum2 headdum4 adum1-adum4 adum6 venddum1-venddum6 drugdum1-drugdum3 inter* if headdum1==1 & treated_ate!=., vce(cluster p1a_vendcode)logistic adhered_SR treated_ate sms_long maledum1 maledum3 chaddum1 chaddum3 mheaddum1 mheaddum3 headdum1 headdum2 headdum4 adum1-adum4 adum6 venddum1-venddum6 drugdum1-drugdum3 inter* if headdum2==1 & treated_ate!=., vce(cluster p1a_vendcode)logistic adhered_SR treated_ate sms_long maledum1 maledum3 chaddum1 chaddum3 mheaddum1 mheaddum3 headdum1 headdum2 headdum4 adum1-adum4 adum6 venddum1-venddum6 drugdum1-drugdum3 inter* if headdum3==1 & treated_ate!=., vce(cluster p1a_vendcode)logistic adhered_SR treated_ate sms_long maledum1 maledum3 chaddum1 chaddum3 mheaddum1 mheaddum3 headdum1 headdum2 headdum4 adum1-adum4 adum6 venddum1-venddum6 drugdum1-drugdum3 inter* if adum1==1 & treated_ate!=., vce(cluster p1a_vendcode)logistic adhered_SR treated_ate sms_long maledum1 maledum3 chaddum1 chaddum3 mheaddum1 mheaddum3 headdum1 headdum2 headdum4 adum1-adum4 adum6 venddum1-venddum6 drugdum1-drugdum3 inter* if adum2==1 & treated_ate!=., vce(cluster p1a_vendcode)logistic adhered_SR treated_ate sms_long maledum1 maledum3 chaddum1 chaddum3 mheaddum1 mheaddum3 headdum1 headdum2 headdum4 adum1-adum4 adum6 venddum1-venddum6 drugdum1-drugdum3 inter* if adum3==1 & treated_ate!=., vce(cluster p1a_vendcode)logistic adhered_SR treated_ate sms_long maledum1 maledum3 chaddum1 chaddum3 mheaddum1 mheaddum3 headdum1 headdum2 headdum4 adum1-adum4 adum6 venddum1-venddum6 drugdum1-drugdum3 inter* if adum4==1 & treated_ate!=., vce(cluster p1a_vendcode)logistic adhered_SR treated_ate sms_long maledum1 maledum3 chaddum1 chaddum3 mheaddum1 mheaddum3 headdum1 headdum2 headdum4 adum1-adum4 adum6 venddum1-venddum6 drugdum1-drugdum3 inter* if adum5==1 & treated_ate!=., vce(cluster p1a_vendcode)logistic adhered_SR treated_ate sms_long maledum1 maledum3 chaddum1 chaddum3 mheaddum1 mheaddum3 headdum1 headdum2 headdum4 adum1-adum4 adum6 venddum1-venddum6 drugdum1-drugdum3 inter* if vendor==2 & treated_ate!=., vce(cluster p1a_vendcode)logistic adhered_SR treated_ate sms_long maledum1 maledum3 chaddum1 chaddum3 mheaddum1 mheaddum3 headdum1 headdum2 headdum4 adum1-adum4 adum6 venddum1-venddum6 drugdum1-drugdum3 inter* if vendor==3 & treated_ate!=., vce(cluster p1a_vendcode)logistic adhered_SR treated_ate sms_long maledum1 maledum3 chaddum1 chaddum3 mheaddum1 mheaddum3 headdum1 headdum2 headdum4 adum1-adum4 adum6 venddum1-venddum6 drugdum1-drugdum3 inter* if vendor==4 & treated_ate!=., vce(cluster p1a_vendcode)logistic adhered_SR treated_ate sms_long maledum1 maledum3 chaddum1 chaddum3 mheaddum1 mheaddum3 headdum1 headdum2 headdum4 adum1-adum4 adum6 venddum1-venddum6 drugdum1-drugdum3 inter* if vendor==5 & treated_ate!=., vce(cluster p1a_vendcode)logistic adhered_SR treated_ate sms_long maledum1 maledum3 chaddum1 chaddum3 mheaddum1 mheaddum3 headdum1 headdum2 headdum4 adum1-adum4 adum6 venddum1-venddum6 drugdum1-drugdum3 inter* if vendor==6 & treated_ate!=., vce(cluster p1a_vendcode)logistic adhered_SR treated_ate sms_long maledum1 maledum3 chaddum1 chaddum3 mheaddum1 mheaddum3 headdum1 headdum2 headdum4 adum1-adum4 adum6 venddum1-venddum6 drugdum1-drugdum3 inter* if drug==1 & treated_ate!=., vce(cluster p1a_vendcode)logistic adhered_SR treated_ate sms_long maledum1 maledum3 chaddum1 chaddum3 mheaddum1 mheaddum3 headdum1 headdum2 headdum4 adum1-adum4 adum6 venddum1-venddum6 drugdum1-drugdum3 inter* if drug==2 & treated_ate!=., vce(cluster p1a_vendcode)*********************************************** Table 4: Validating self-reports**********************************************tab adhered_SR pills if treated_ate!=., rowtab adhered_SR ACT if treated_ate!=., rowtab adhered_SR took6 if treated_ate!=. & age_g>2, row************************************************Table 5: Health***********************************************tab treated_ate still, r // Message A and control
tab sms_long still, r // Message Blogistic still adhered_SR maledum1 maledum3 chaddum1 chaddum3 mheaddum1 mheaddum3 headdum1 headdum2 headdum4 adum1-adum4 adum6 venddum1-venddum6 drugdum1-drugdum3 inter*, rlogistic still treated_ate sms_long  adhered_SR treated_ate sms_long maledum1 maledum3 chaddum1 chaddum3 mheaddum1 mheaddum3 headdum1 headdum2 headdum4 adum1-adum4 adum6 venddum1-venddum6 drugdum1-drugdum3 inter* if treated_ate!=., vce(cluster p1a_vendcode) 
outreg2 using table5, replace eform ci excellogistic still sms_short sms_long maledum1 maledum3 chaddum1 chaddum3 mheaddum1 mheaddum3 headdum1 headdum2 headdum4 adum1-adum4 adum6 venddum1-venddum6 drugdum1-drugdum3 inter*, routreg2 using table5, append eform ci  excel* Aux reglogistic still sms_short sms_long  maledum* agedum2-agedum5 headdum* mheaddum* adum* private formal if age_g>0 & age_g<3, r