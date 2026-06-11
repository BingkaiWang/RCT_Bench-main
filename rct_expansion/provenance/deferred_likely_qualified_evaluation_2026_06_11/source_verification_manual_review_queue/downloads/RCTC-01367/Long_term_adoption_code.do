clear all
set more off
set scrollbufsize 2048000
set maxvar 32767
capture log close

use "C:\Users\yuanyi\Desktop\Long_term_adoption_result\Long_term_adoption_Dataverse.dta", clear

* 全局宏定义控制变量
global stu_controls male grade7 LogMAR zmath dadjun momjun dadmigrant ///
                    mommigrant log_pocketm tsratio log_totalst distance

* 剔除样本流失数据
keep if attrition == 0 


/*******************************************************************************
        Table 2 : Summary Statistics and Balance Check 
********************************************************************************/
eststo clear
estpost tabstat $stu_controls if needgl == 0, ///
                by(treatment) statistics(mean sd) columns(statistics) total
esttab using "check_balance_students_full.csv", replace main(mean) aux(sd) ///
                nostar nogap unstack noobs nonote label b(3)

eststo clear
foreach var of varlist LogMAR $stu_controls {
    eststo: reg `var' treatment if needgl == 0, vce(cluster schid)
}
esttab using "eyeglasses_impact_banlance_check.csv", replace ///
                star(* 0.10 ** 0.05 *** 0.01) se(3) b(3) wide


/*******************************************************************************
        Table 3: Main Result - Impact on Adoption 
********************************************************************************/
eststo clear    
* 基础回归
eststo: reg endown_sc treatment i.strata if needgl == 0, vce(cluster schid)
eststo: reg endown_sc treatment i.strata $stu_controls if needgl == 0, vce(cluster schid)

* 控制机制变量
eststo: reg ecst_LogMAR treatment i.strata $stu_controls if needgl == 0, vce(cluster schid)
eststo: reg endown_sc treatment i.strata $stu_controls ecst_LogMAR if needgl == 0, vce(cluster schid)

esttab using "long_term_adoption.csv", replace star(* 0.10 ** 0.05 *** 0.01) ///
                se(3) b(3) nogap r2 obs 


/*******************************************************************************
        Table 4: Robustness Check 
********************************************************************************/
capture ssc install relogit
capture ssc install firthlogit

eststo clear
eststo: reg endown_sf treatment i.strata $stu_controls ecst_LogMAR if needgl == 0, vce(cluster schid)
eststo: logit endown_sc treatment $stu_controls i.strata ecst_LogMAR if needgl == 0, cluster(schid)
eststo: relogit endown_sc treatment $stu_controls ecst_LogMAR if needgl == 0, cluster(schid)
eststo: firthlogit endown_sc treatment $stu_controls ecst_LogMAR if needgl == 0

esttab using "robustness_check1.csv", replace star(* 0.10 ** 0.05 *** 0.01) se(3) b(3) nogap

* --- Average Marginal Effects 计算 ---
* 1. Logit AME
logit endown_sc treatment $stu_controls i.strata ecst_LogMAR if needgl == 0, cluster(schid)
margins, dydx(treatment)

* 2. Relogit AME
relogit endown_sc treatment $stu_controls ecst_LogMAR if needgl == 0, cluster(schid)
predict lp_relogit, xb  
gen p_relogit = 1/(1 + exp(-lp_relogit))  
gen me_treatment_re = p_relogit * (1 - p_relogit) * _b[treatment]  
summarize me_treatment_re if needgl == 0 

* 3. Firthlogit AME
firthlogit endown_sc treatment $stu_controls ecst_LogMAR if needgl == 0
predict lp_firth, xb  
gen p_firth = 1/(1 + exp(-lp_firth))  
gen me_treatment_fi = p_firth * (1 - p_firth) * _b[treatment]  
summarize me_treatment_fi if needgl == 0  


/*******************************************************************************
        Table 5: Heterogenous Effects 
********************************************************************************/
eststo clear     
* By Gender
eststo: reg endown_sc treatment i.strata $stu_controls ecst_LogMAR if needgl == 0 & male == 0, vce(cluster schid)
eststo: reg endown_sc treatment i.strata $stu_controls ecst_LogMAR if needgl == 0 & male == 1, vce(cluster schid)

* By Grade
eststo: reg endown_sc treatment i.strata $stu_controls ecst_LogMAR if needgl == 0 & grade7 == 1, vce(cluster schid)
eststo: reg endown_sc treatment i.strata $stu_controls ecst_LogMAR if needgl == 0 & grade7 == 0, vce(cluster schid)

* By Math Score
eststo: reg endown_sc treatment i.strata $stu_controls ecst_LogMAR if needgl == 0 & zmath < 0.1, vce(cluster schid)
eststo: reg endown_sc treatment i.strata $stu_controls ecst_LogMAR if needgl == 0 & zmath >= 0.1, vce(cluster schid)

esttab using "heterogenous_effect.csv", replace star(* 0.10 ** 0.05 *** 0.01) se(3) b(3) nogap r2 obs


/*******************************************************************************
        Mechanism Analysis 
********************************************************************************/   
* --- Mechanism 2: Anchoring Effect ---
graph box price_glasses if needgl == 0, over(treatment) ///
    marker(1, msymbol(circle) mcolor(red)) ///
    title("两组学生眼镜价格分布") ytitle("price (yuan)") ///
    note("箱体：Q1-Q3；横线：中位数；红点：均值；须线：1.5*IQR范围")

* Group analysis based on baseline class glass ratio
eststo clear
eststo: reg endown_sc treatment i.strata $stu_controls ecst_LogMAR if needgl == 0 & ratio_own_need < 0.1, vce(cluster schid)
eststo: reg endown_sc treatment i.strata $stu_controls ecst_LogMAR if needgl == 0 & ratio_own_need >= 0.1 & ratio_own_need < ., vce(cluster schid)

eststo: reg endown_sc treatment i.strata $stu_controls ecst_LogMAR if needgl == 0 & classglass_base_sf <= 1, vce(cluster schid)
eststo: reg endown_sc treatment i.strata $stu_controls ecst_LogMAR if needgl == 0 & classglass_base_sf > 1 & classglass_base_sf < ., vce(cluster schid)

* --- Mechanism 3: Social Learning ---
eststo clear
foreach var of varlist non_help_end harmvision_end ugly_end mildno_end nowearjun_end {
    eststo: reg `var' treatment $stu_controls i.strata if needgl == 0, vce(cluster schid)
}
foreach var of varlist non_help_end harmvision_end ugly_end mildno_end nowearjun_end {
    eststo: reg `var' treatment $stu_controls i.strata if needgl == 1, vce(cluster schid)
}
esttab using "attitude_willing.csv", replace star(* 0.10 ** 0.05 *** 0.01) se(3) b(3) nogap r2

* --- Mechanism 4: Stigma & IV ---  
eststo clear
reg endown_sc treatment i.strata $stu_controls ecst_LogMAR if needgl == 0 & tease_bully_bs == 0, vce(cluster schid) level(90)
reg endown_sc treatment i.strata $stu_controls ecst_LogMAR if needgl == 0 & tease_bully_bs == 1, vce(cluster schid) level(90)
reg endown_sc treatment i.strata $stu_controls ecst_LogMAR if needgl == 0 & hglass_bs > 1, vce(cluster schid) level(90)
reg endown_sc treatment i.strata $stu_controls ecst_LogMAR if needgl == 0 & hglass_bs <= 1, vce(cluster schid) level(90)
reg endown_sc treatment i.strata $stu_controls ecst_LogMAR if needgl == 0 & nglass_bs <= 14, vce(cluster schid) level(90)
reg endown_sc treatment i.strata $stu_controls ecst_LogMAR if needgl == 0 & nglass_bs > 14 & nglass_bs <= 20, vce(cluster schid) level(90)
reg endown_sc treatment i.strata $stu_controls ecst_LogMAR if needgl == 0 & nglass_bs > 20, vce(cluster schid) level(90)

* IV Results
eststo clear
eststo: reg teased2 treatment i.strata $stu_controls ecst_LogMAR if needgl == 0, vce(cluster schid)
eststo: reg ratio_peer_glass_end treatment i.strata $stu_controls ecst_LogMAR if needgl == 0, vce(cluster schid)
eststo: ivregress 2sls teased2 (ratio_peer_glass_end = treatment) i.strata $stu_controls ecst_LogMAR if needgl == 0, vce(cluster schid)
eststo: ivregress 2sls endown_sc (ratio_peer_glass_end = treatment) i.strata $stu_controls ecst_LogMAR if needgl == 0, vce(cluster schid)
esttab using "stigma.csv", replace star(* 0.10 ** 0.05 *** 0.01) se(3) b(3) nogap r2


/*******************************************************************************
        Appendix Tables and Figures
********************************************************************************/


* Appendix Balance Check for needgl == 1
eststo clear
estpost tabstat $stu_controls if needgl == 1, by(treatment) statistics(mean sd) columns(statistics) total
esttab using "check_balance_students_full_needgl1.csv", replace main(mean) aux(sd) nostar nogap unstack noobs nonote label b(3)

* Appendix Figure: Leave-one-school-off
destring schid, replace
levelsof schid, local(schools)
local n_school = `:list sizeof schools'
matrix results_loo = J(`n_school', 6, .)
local row = 1

reg endown_sc treatment i.strata $stu_controls ecst_LogMAR if needgl == 0, vce(cluster schid)
scalar beta_full = _b[treatment]

foreach s of local schools {
    reg endown_sc treatment i.strata $stu_controls ecst_LogMAR if needgl == 0 & schid != `s', vce(cluster schid)
    matrix results_loo[`row',1] = `s'
    matrix results_loo[`row',2] = _b[treatment]
    matrix results_loo[`row',3] = _se[treatment]
    matrix results_loo[`row',4] = 2*ttail(e(df_r), abs(_b[treatment]/_se[treatment]))
    matrix results_loo[`row',5] = _b[treatment] - beta_full
    matrix results_loo[`row',6] = ((_b[treatment] - beta_full) / beta_full) * 100
    local row = `row' + 1
}

* Appendix Figure: Placebo Test (1000 Iterations Randomization)
set seed 12345
local n_iter = 1000
matrix placebo_results = J(`n_iter', 1, .)

forvalues i = 1/`n_iter' {
    preserve
    duplicates drop schid, force
    gen random_u = runiform()
    gen treat_school = (random_u <= 0.5)
    tempfile school_treat
    save `school_treat', replace
    restore
    
    merge m:1 schid using `school_treat', keep(match) nogen
    gen treat = treat_school
    
    quietly reg endown_sc treat i.strata $stu_controls ecst_LogMAR if needgl == 0, vce(cluster schid)
    matrix placebo_results[`i',1] = _b[treat]
    drop random_u treat_school treat
}
svmat placebo_results, names(placebo)


* Appendix Figure3 
clear all
cd "C:\Users\yuanyi\Desktop\Long_term_adoption_result"

input byte group byte pos str40 label_name float b float lb float ub
1 1 "Not teased"        0.016  0.006  0.025
1 2 "Teased"            0.041  0.002  0.080
2 1 "1 glass"           0.028  0.015  0.042
2 2 "More than 1 glass" 0.060  0.039  0.081
3 1 "Small (<=14)"      0.023  0.014  0.033
3 2 "Medium (15-20)"    0.106  0.023  0.189
3 3 "Large (>20)"       0.161  0.056  0.266
end


// ==========================================
// Figure 1: Whether there was teasing behavior within the class at the baseline stage
// ==========================================
preserve
keep if group == 1
twoway (rcap lb ub pos, lcolor(blue)) ///
       (scatter b pos, msymbol(circle) mcolor(red)), ///
       yline(0, lpattern(dash) lcolor(black)) ///
       xlabel(1 "Not teased" 2 "Teased", nogrid labsize(small)) ///
       xscale(range(0.5 2.5)) ///
       ytitle("Impact") xtitle("") title("Being teased or not being teased") ///
       legend(off) graphregion(color(white)) plotregion(margin(medium)) ///
       name(g_tease_v, replace)
restore

// ==========================================
// Figure 2: The proportion of students wearing glasses in the class during the baseline period
// ==========================================
preserve
keep if group == 2
twoway (rcap lb ub pos, lcolor(blue)) ///
       (scatter b pos, msymbol(circle) mcolor(red)), ///
       yline(0, lpattern(dash) lcolor(black)) ///
       xlabel(1 "1 glass" 2 "More than 1 glass", nogrid labsize(small)) ///
       xscale(range(0.5 2.5)) ///
       ytitle("Impact") xtitle("") title("The number of glasses owned") ///
       legend(off) graphregion(color(white)) plotregion(margin(medium)) ///
       name(g_prev_v, replace)
restore

// ==========================================
// Figure 3: The number of free glasses distributed
// ==========================================
preserve
keep if group == 3
twoway (rcap lb ub pos, lcolor(blue)) ///
       (scatter b pos, msymbol(circle) mcolor(red)), ///
       yline(0, lpattern(dash) lcolor(black)) ///
       xlabel(1 "Small" 2 "Medium" 3 "Large", labsize(small) nogrid) ///
       xscale(range(0.5 3.5)) ///
       ytitle("Impact") xtitle("") title("Quantity of eyeglasses") ///
       legend(off) graphregion(color(white)) plotregion(margin(medium)) ///
       name(g_qty_v, replace)
restore

// ==========================================
// Generate merged Figure
// ==========================================
graph combine g_tease_v g_prev_v g_qty_v, ///
    col(3) xsize(12) ysize(4) ///
    graphregion(color(white)) imargin(small)
    
graph export "treatment_coef_vertical.png", width(1200) height(700) replace