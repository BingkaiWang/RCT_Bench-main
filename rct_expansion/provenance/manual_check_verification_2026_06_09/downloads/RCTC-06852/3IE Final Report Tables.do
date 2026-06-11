//Analysis file
set more off
clear
use /txoutcomeandbaselinedata_3ie.dta_3ie.dta

//Table 1: Demographic characteristics
tab sex zindagi, col
sum age if zindagi==1
sum age if zindagi==0
tab indus zindagi, col
tab govtclinic zindagi, col
tab private zindagi, col
tab regimen zindagi, col
tab mobown zindagi, col
tab school zindagi, col
tab primary zindagi, col
tab secondary zindagi, col
tab tertiary zindagi, col
tab religious zindagi, col

//Figure 1: Response rates over time in treatment
clear
use /zindagisystemresponsedata_3ie.dta
tab twowkresprate twoweeksinstudy
tab twowkrr6mo twoweeksinstudy
tab twowkrr8mo twoweeksinstudy
duplicates drop patientid, force
sum resprate if onsystemthroughout==1

//Table 2: Clinically-recorded treatment success between Zindagi SMS and control groups
clear
use /txoutcomeandbaselinedata_3ie.dta
tab success zindagi, col chi2
tab cured zindagi, col chi2
tab txcomplete zindagi, col chi2
tab default zindagi, col chi2
tab died zindagi, col chi2
tab fail zindagi, col chi2
tab transfer zindagi, col chi2

//Table 3: Clinically-recorded treatment outcomes substituted with self-reported outcomes from default and transfer out patients interviewed at the end of their treatment, or those that were reported to have had died by their family members during study visits before their treatment was complete 
tab selfsuccess zindagi, col chi2
tab selfcured zindagi, col chi2
tab selfcomplete zindagi, col chi2
tab selfdefault zindagi, col chi2
tab selfdied zindagi, col chi2
tab selffail zindagi, col chi2
tab selftransfer zindagi, col chi2

//Table 5:Subgroup analysis using subgroup indices with treatment success as the outcome variable 
//subgroup: gender
gen male=sex
gen malezindagi=male*zindagi
reg success male zindagi malezindagi

//subgroup: vulnerable population
gen vulnerability=male+assetindex+school
gen vulnerable=1 if vulnerability<1.545455
replace vulnerable=0 if vulnerability>=1.545455 & vulnerability!=.
gen vulzindagi=vulnerable*zindagi
reg success zindagi vulnerable vulzindagi

//subgroup: access to mobile phone
gen onelit=1 if hhreadcount>0 & hhreadcount!=.
replace onelit=0 if hhreadcount==0
gen cansmsm1=1 if sendsms==1 & studymonth<1
replace cansmsm1=0 if sendsms==0 & studymonth<1
gen mobaccess=mobown+onelit+cansmsm1
gen highmobaccess=1 if mobaccess>2 & mobaccess!=.
replace highmobaccess=0 if mobaccess<=2
gen highmobzindagi=zindagi*highmob
reg success zindagi highmobaccess highmobzindagi

//subgroup: quality of care
gen medrem1=1 if medremind==1 & studymonth<1
replace medrem1=0 if medremind==0 & studymonth<1
gen clinicqual=0 if indus==1
replace clinicqual=0.5 if govtclinic==1
replace clinicqual=1 if private==1
gen qualcare=medrem1+clinicqual+treatsupp
gen qualgood=1 if qualcare>1 & qualcare!=.
replace qualgood=0 if qualcare<=1
gen qualgoodzindagi=qualgood*zindagi
reg success zindagi qualgood qualgoodzindagi

//Table 4: Sub-group analysis using treatment success as the outcome
** Most of this code from Casey, K., Glennerster, R., & Miguel, E. (2011). Reshaping institutions

gen successgp=1 if success==1 & private==1
replace successgp=0 if success==0 & private==1
gen successindus=1 if success==1 & indus==1
replace successindus=0 if success==0 & indus==1
gen successgovt=1 if success==1 & govtclinic==1
replace successgovt=0 if success==0 & govtclinic==1
gen successmale=1 if success==1 & sex==1
replace successmale=0 if success==0 & sex==1
gen successfemale=1 if success==1 & sex==0
replace successfemale=0 if success==0 & sex==0
gen successtxsupp=1 if success==1 & treatsupp==1
replace successtxsupp=0 if success==0 & treatsupp==1
gen successnotxsupp=1 if success==1 & treatsupp==0
replace successnotxsupp=0 if success==0 & treatsupp==0
gen successmobown=1 if success==1 & mobown==1
replace successmobown=0 if success==0 & mobown==1
gen successnomobown=1 if success==1 & mobown==0
replace successnomobown=0 if success==0 & mobown==0
gen successschool=1 if success==1 & school==1
replace successschool=0 if success==0 & school==1
gen successnoschool=1 if success==1 & school==0
replace successnoschool=0 if success==0 & school==0
gen successanyread=1 if success==1 & anyreadhh==1
replace successanyread=0 if success==0 & anyreadhh==1
gen successnoread=1 if success==1 & anyreadhh==0
replace successnoread=0 if success==0 & anyreadhh==0
gen successmedrem=1 if success==1 & medrem1==1
replace successmedrem=0 if success==0 & medrem1==1
gen successnomedrem=1 if success==1 & medrem1==0
replace successnomedrem=0 if success==0 & medrem1==0
gen successsms=1 if success==1 & cansmsm1==1
replace successsms=0 if success==0 & cansmsm1==1
gen successnosms=1 if success==1 & cansmsm1==0
replace successnosms=0 if success==0 & cansmsm1==0

**placeholders
gen str20 varname = ""
gen float tstat = .
gen float act_pval = .
gen float tstatsim = .
gen float pvalsim = .
gen float pvals = .

local controls 
local outcomes "successgp successindus successgovt successmale successfemale successtxsupp successnotxsupp successmobown successnomobown successschool successnoschool successanyread successnoread successmedrem successnomedrem successsms successnosms"

**run original regressions for all outcomes tested and store the actual (observed) p-vals/t-stats
local i=1
qui foreach outcome in `outcomes' {
    reg `outcome' zindagi `controls'
    quietly replace tstat = abs(_b[zindagi]/_se[zindagi]) in `i'
    quietly replace act_pval = 2*ttail(e(N),abs(tstat)) in `i'
    quietly replace varname = "`outcome'" in `i'
    local `outcome'_ct_0 = 0
    local i = `i' + 1
    }

*sort the p-vals by the actual (observed) p-vals 
*(this will reorder some of the obs, but that shouldn't matter)
gsort act_pval
local numvars = `i' - 1
di `numvars'

**Generate variables for simulated treatments
gen byte simzindagi = .
gen float simzindagi_uni = .

*run iterations of the simulation, record results in p-val storage counters
local reps 10000
forvalues j=1/`reps' {
	* in this section we assign the placebo treatments and
	*run regressions using the placebo treatments
	quietly replace simzindagi_uni = uniform()
	quietly replace simzindagi = (simzindagi_uni>0.5)
	forvalues x=1/`numvars' {
		local depvar = varname[`x']
        quietly reg `depvar' simzindagi `controls'
	   	quietly replace tstatsim = abs(_b[simzindagi]/_se[simzindagi]) in `x'
        quietly replace pvalsim = 2*ttail(e(N),abs(tstatsim)) in `x'
		local x=`x'+1
    }
	*in this section we perform the "step down" procedure that replaces simulated p-vals
	*with the minimum of the set of simulated p-vals associated with outcomes that had actual 
	*p-vals greater than or equal to the one being replaced.  For each outcome, we keep count
	*of how many times the ultimate simulated p-val is less than the actual observed p-val.
	local y=`numvars'
	while `y'>=1 {
		quietly replace pvalsim = min(pvalsim,pvalsim[_n+1]) in `y'
		local depvar = varname[`y']
		if pvalsim[`y'] <= act_pval[`y'] {
			local `depvar'_ct_0 = ``depvar'_ct_0' + 1
		}
		local y=`y'-1
	}
	if mod(`j',100)==0 {
		di "Rep: " + `j'
	}
}
*perform the final adjustment that ensures that the ordering to adjusted p-vals 
*is the same as the original ordering of actual p-vals.  
*note that this is actually a "step up" procedure rather than a "step down"
forvalues x=1/`numvars' {
    local depvar = varname[`x']
    quietly replace pvals = max(round(``depvar'_ct_0'/10000,.001), pvals[`x'-1]) in `x'
}
list varname act_pval pvals if varname!=""

//Table 6: Secondary outcome variables
clear
use /secondaryoutcomedata_3ie.dta
** Most of this code from Casey, K., Glennerster, R., & Miguel, E. (2011). Reshaping institutions
gen days2=daysinstudy*daysinstudy

**placeholders
gen str20 varname = ""
gen float tstat = .
gen float act_pval = .
gen float tstatsim = .
gen float pvalsim = .
gen float pvals = .

local controls "regimen daysinstudy days2"
local outcomes "tbmed24hr hopefulness healthy supported difftasks"

**run original regressions for all outcomes tested and store the actual (observed) p-vals/t-stats
local i=1
qui foreach outcome in `outcomes' {
    reg `outcome' zindagi `controls'
    quietly replace tstat = abs(_b[zindagi]/_se[zindagi]) in `i'
    quietly replace act_pval = 2*ttail(e(N),abs(tstat)) in `i'
    quietly replace varname = "`outcome'" in `i'
    local `outcome'_ct_0 = 0
    local i = `i' + 1
    }

*sort the p-vals by the actual (observed) p-vals 
*(this will reorder some of the obs, but that shouldn't matter)
gsort act_pval
local numvars = `i' - 1
di `numvars'

**Generate variables for simulated treatments
gen byte simzindagi = .
gen float simzindagi_uni = .

*run iterations of the simulation, record results in p-val storage counters
local reps 10000
forvalues j=1/`reps' {
	* in this section we assign the placebo treatments and
	*run regressions using the placebo treatments
	quietly replace simzindagi_uni = uniform()
	quietly replace simzindagi = (simzindagi_uni>0.5)
	forvalues x=1/`numvars' {
		local depvar = varname[`x']
        quietly reg `depvar' simzindagi `controls'
	   	quietly replace tstatsim = abs(_b[simzindagi]/_se[simzindagi]) in `x'
        quietly replace pvalsim = 2*ttail(e(N),abs(tstatsim)) in `x'
		local x=`x'+1
    }
	*in this section we perform the "step down" procedure that replaces simulated p-vals
	*with the minimum of the set of simulated p-vals associated with outcomes that had actual 
	*p-vals greater than or equal to the one being replaced.  For each outcome, we keep count
	*of how many times the ultimate simulated p-val is less than the actual observed p-val.
	local y=`numvars'
	while `y'>=1 {
		quietly replace pvalsim = min(pvalsim,pvalsim[_n+1]) in `y'
		local depvar = varname[`y']
		if pvalsim[`y'] <= act_pval[`y'] {
			local `depvar'_ct_0 = ``depvar'_ct_0' + 1
		}
		local y=`y'-1
	}
	if mod(`j',100)==0 {
		di "Rep: " + `j'
	}
}
*perform the final adjustment that ensures that the ordering to adjusted p-vals 
*is the same as the original ordering of actual p-vals.  
*note that this is actually a "step up" procedure rather than a "step down"
forvalues x=1/`numvars' {
    local depvar = varname[`x']
    quietly replace pvals = max(round(``depvar'_ct_0'/10000,.001), pvals[`x'-1]) in `x'
}
list varname act_pval pvals if varname!=""

