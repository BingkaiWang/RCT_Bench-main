#Date created: 1/22/25
#Updated: 4/2/26 MCP
#Project: ChooseWell365
#Task: Data cleaning and analytic code for NIA 1R01AG089061
#PI: Douglas Levy, Massachusetts General Hospital
#Author: Mark Pachucki (data management) / Cassie McMillan (analysis)

####################### PROGRAM GUIDE ##############################
# Pachucki, M.
#   1. SETUP
#   2. CONSTRUCT NEW DYADIC VARIABLES
#   3. DEVELOP MERGED DATA 
#   4. CREATE TIE PROBABLILITY USING MERGED DATA 
#   5. MERGE DYADIC DATA W/ TIE PROBABLILITY DATA
#   6. OBTAIN EGO-LEVEL FOOD DATA (precise) - YEARLY
#   7. SAVE MERGED EGO-LEVEL FOOD/UPDATED TIE PREDICTION OBJECT 
#   8. SUBSET NETWORK DATA (6m)
# McMillan, C
#   9. PREP FOR SAOMS
#   10. CREATE ACTOR-LEVEL FILE
#   11. CREATE COMPOSITION CHANGE FILE
#   12. ANALYSIS REPLICATION CODE

############## 1. SETUP #################################

#working directory - cluster lcoation
setwd("/work/pi_mpachucki_umass_edu/food_projects/food_simulation_r01")

#load libraries
lapply(c('chron', 'tidyverse', 'eeptools', 'sqldf', 
         'lubridate', 'data.table', 'rio', 'plm', 'ggplot2'),
       require, character.only = TRUE)

############## 2. CONSTRUCT NEW DYADIC VARIABLES ##############

#### 2.1 CONSTRUCT NEW DYADIC VARIABLES (2015) ####
setwd("/work/pi_mpachucki_umass_edu/food_projects/food_simulation_r01/data raw/dta")
#Read yearly dta data
dyads_ntp_split<-import("dyads_and_alone15_Jan2025.dta", 
                        setclass="data.table")
#n=10,848,962 (note that it only goes back to 8-30-2015)

#Exclusion 1:  truncate dataset to remove all dyads before 11/5/2015, last 8w
#of 2015 to allow for lag. 
dyads_ntp_split<-subset(dyads_ntp_split, mdy >= "2015-11-05")
dyads_ntp_split[, .N]
# n=4,874,441 observations remain

#save intermediate dataset to save time
save.image("dyads_and_alone15_Jan2025_110515plus.Rdata")


#Exclusion 2: subset just the egos who are non-trial participants (NTP), coded NA
setwd("/work/pi_mpachucki_umass_edu/food_projects/food_simulation_r01/data analytic")
trial_membership_u <- readRDS("trial_membership_u.RDS")
colnames(trial_membership_u)[3] <- "newrandomdatetime" 

##left_join participants' "id"
dyads_ntp_split<- left_join(dyads_ntp_split, trial_membership_u, by="id")
trial_membership_u$newrandomdatetime_d<-trial_membership_u$newrandomdatetime #MCP added
trial_membership_u$id_d <- trial_membership_u$id
## left_join again, but by "id_d" (match alter newrandomdatetime_d with alter id)
dyads_ntp_split<- left_join(dyads_ntp_split, 
                            trial_membership_u[,c("id_d","newrandomdatetime_d")], 
                            by="id_d")

##To impute newstudy_month=25+ for egos who had joined the trial for more than 2y
#(this will become most important in late 2018 onward for select participants)
dyads_ntp_split[, "diff_year" := 
                  as.numeric(difftime(as.POSIXct(dyads_ntp_split$mdy),
                                      as.POSIXct(dyads_ntp_split$newrandomdatetime), 
                                      units = "weeks"))/52.25]
dyads_ntp_split <- dyads_ntp_split %>%
  mutate(newstudy_month = ifelse(!is.na(newrandomdatetime) & diff_year > 2,
                                 25, study_month))
#count  newstudy_month
dyads_ntp_split[, .N, by="newstudy_month"]

##If newrandomdatetime > mdy, participants were still NPEs
dyads_ntp_split[newrandomdatetime <= mdy & !is.na(newrandomdatetime), randomgroup_dyn := randomgroup.y][ newrandomdatetime > mdy & !is.na(newrandomdatetime), randomgroup_dyn := NA][is.na(newrandomdatetime), randomgroup_dyn := NA]

##Declare start date of purchases to create calmonth variable, where 1=Oct. 2016
purchasestart<-as.Date("2016-10-1") 
#note this is different than SSM, and makes this calmonth incommensurate w/SSM
dyads_ntp_split[, purchasestart := purchasestart]
dyads_ntp_split[, calmonth := floor(as.numeric(as.period(interval(purchasestart, mdy)), "month"))-12]

#Exclusion 3: exclude upper bound of multi-purchases 
# according to 0= remove, 1=keep

# Flag all individual items whose price was >$9.50
dyads_ntp_split[(price/tt_items) >9.50, priceflag:=0][price/tt_items <= 9.50, priceflag:=1]

# Flag all transactions whose total came to >$20
dyads_ntp_split[price>20.00, totalflag:=0][price <= 20.00, totalflag:=1]

# Flag all transactions with >=5 entrees
dyads_ntp_split[(tt_items>=5 & cw_grp=="entr?e"), entreeflag:=0][(tt_items<5 & cw_grp=="entr?e") | cw_grp!="entr?e", entreeflag:=1]

#Remove rows with flagged conditions - need to do it sequentially 
dyads_ntp_split2<- subset(dyads_ntp_split, entreeflag==1)
dyads_ntp_split2<- subset(dyads_ntp_split2, priceflag==1)
dyads_ntp_split2<- subset(dyads_ntp_split2, totalflag==1)

#count the difference between original and modified DT
dyads_ntp_split[, .N] #4874441
dyads_ntp_split2[, .N] #4868799

dyads_ntp_split[, .N] - dyads_ntp_split2[, .N] #5642
(dyads_ntp_split[, .N] - dyads_ntp_split2[, .N])/dyads_ntp_split[, .N] #0.001157466

#retain removed cases for inspection and re-merging if necessary
removed_cases<- subset(dyads_ntp_split, entreeflag==0 | priceflag==0 | totalflag==0)
#clean up
rm(dyads_ntp_split)
dyads_ntp_split<-dyads_ntp_split2
rm(dyads_ntp_split2)

## Recode various measures 

#Load age calculation function
age = function(from, to) {
  from_lt = as.POSIXlt(from)
  to_lt = as.POSIXlt(to)
  
  age = to_lt$year - from_lt$year
  
  ifelse(to_lt$mon < from_lt$mon |
           (to_lt$mon == from_lt$mon & to_lt$mday < from_lt$mday),
         age - 1, age)
}

#a. recode: participant age at purchase (ego), rename var, due to updated data
dyads_ntp_split<-rename(dyads_ntp_split, birthdate = Birthdate)

#b. recode: age
dyads_ntp_split[, age := age(birthdate, mdy)]  #note Birthdate/birthdate spelling
dyads_ntp_split[, age_d := age(birthdate_d, mdy)]

#c. recode: ego trial memberships
#  intervention group (1st 6m) = 6
#  intervention group (2nd 6m) = 7
#  control group (months 1-42) = 2
#  year 2 int group (1st 6m) = 3
#  year 2 int group (2nd 6m) = 4
#  nonparticipant = 5 
dyads_ntp_split[randomgroup_dyn == 1 & newstudy_month<=6, randomgroup6:=6][randomgroup_dyn == 1 & (newstudy_month>6 & newstudy_month<=12), randomgroup6:=7][randomgroup_dyn == 3, randomgroup6:=2][randomgroup_dyn == 1 & (newstudy_month>12 & newstudy_month<=18), randomgroup6:=3][randomgroup_dyn == 1 & (newstudy_month>18 & newstudy_month<=25), randomgroup6:=4]
dyads_ntp_split[is.na(randomgroup6), randomgroup6:=5]

#Ego var - generate 3-category randomgroup var
dyads_ntp_split <- dyads_ntp_split %>% 
  mutate(randomgroup3 = ifelse(randomgroup6 == 2, 2,
                               ifelse(randomgroup6 == 3 | randomgroup6 == 4 |
                                        randomgroup6 == 6 | randomgroup6 == 7, 1,
                                      ifelse(randomgroup6 == 5 & id %in% trial_membership_u[trial_membership_u$group_dup == 1,]$id, 1, 
                                             ifelse(randomgroup6 == 5 & id %in% trial_membership_u[trial_membership_u$group_dup == 2,]$id, 2, 3)))))

#Alter var
dyads_ntp_split[newrandomdatetime_d <= mdy, randomgroup_d_dyn := randomgroup_d][randomdatetime_d > mdy, randomgroup_d_dyn := NA]
dyads_ntp_split[is.na(newrandomdatetime_d), randomgroup_d_dyn := NA]
dyads_ntp_split[newrandomdatetime_d < as.Date("2016-10-01"), randomgroup_d_dyn := NA]
dyads_ntp_split[randomgroup_d_dyn == 1 &  study_month_d <=6, randomgroup6_d:=6][randomgroup_d_dyn == 1 & ( study_month_d >6 &  study_month_d <=12), randomgroup6_d:=7][randomgroup_d_dyn == 3, randomgroup6_d:=2][randomgroup_d_dyn == 1 & ( study_month_d >12 &  study_month_d <=18), randomgroup6_d:=3][randomgroup_d_dyn == 1 & ( study_month_d >18 &  study_month_d <=24), randomgroup6_d:=4]
dyads_ntp_split[is.na(randomgroup6_d), randomgroup6_d:=5]

#d. recode: education categories
#recode to: (1) HS or less, (2) Some college, (3) College, 
#           (4) Advanced degree, (5) NA (not available)
#Ego var
dyads_ntp_split[education == "B-Less Than HS Graduate" | education == "C-HS Graduate or Equivalent", ed_cat:=1][education == "D-Some College" | education == "E-Technical School" | education == "F-2-Year College Degree", ed_cat:=2][education == "G-Bachelor's Level Degree" | education == "H-Some Graduate School", ed_cat:=3][education == "I-Master's Level Degree" | education == "J-Doctorate (Academic)" | education == "K-Doctorate (Professional)" | education == "L-Post-Doctorate", ed_cat:=4]
dyads_ntp_split[is.na(ed_cat), ed_cat:=5]
#Alter var
dyads_ntp_split[education_d == "B-Less Than HS Graduate" | education_d == "C-HS Graduate or Equivalent", ed_cat_d:=1][education_d == "D-Some College" | education_d == "E-Technical School" | education_d == "F-2-Year College Degree", ed_cat_d:=2][education_d == "G-Bachelor's Level Degree" | education_d == "H-Some Graduate School", ed_cat_d:=3][education_d == "I-Master's Level Degree" | education_d == "J-Doctorate (Academic)" | education_d == "K-Doctorate (Professional)" | education_d == "L-Post-Doctorate", ed_cat_d:=4]
dyads_ntp_split[is.na(ed_cat_d), ed_cat_d:=5]

#e. recode: study year
#this is somewhat redundant of study months, but useful for easy data description
dyads_ntp_split[study_month>0 & study_month <= 12, study_year:=1][study_month > 12 & study_month <= 24, study_year:=2]

#f. recode: race 
#due to small cell sizes for both ego and alter vars  
# We need to combine "unknown" ("U") with "other" ("O")
dyads_ntp_split[race_cat == "A", race_cat5:="A"][race_cat == "B", race_cat5:="B"][race_cat == "H", race_cat5:="H"][race_cat == "O", race_cat5:="O"][race_cat == "U", race_cat5:="O"][race_cat == "W", race_cat5:="W"]
dyads_ntp_split[race_cat_d == "A", race_cat5_d:="A"][race_cat_d == "B", race_cat5_d:="B"][race_cat_d == "H", race_cat5_d:="H"][race_cat_d == "O", race_cat5_d:="O"][race_cat_d == "U", race_cat5_d:="O"][race_cat_d == "W", race_cat5_d:="W"]

#g. recode: job category
#recode observations with "no EEO-1 reporting" job category to "NA" because of small cells
# For egos in 2016 it's n=2, 2017 n=2, 2018 n=2, 2019 n=1
dyads_ntp_split[job_cat == "No EEO-1 Reporting", job_cat:=NA]
dyads_ntp_split[job_cat_d == "No EEO-1 Reporting", job_cat:=NA]

#h. recode: transform cw_grp from UTF-8 encoding to latin for "entr?e"
dyads_ntp_split$cw_grp<-iconv(dyads_ntp_split$cw_grp, "latin1", "UTF-8")

#i. recode: create new var to denote item type (food or beverage)
dyads_ntp_split[cw_grp != "beverage", item_type:="food"][cw_grp == "beverage", item_type:="bev"]

## Diagnostics 
#solo observations (row-level)
dyads_ntp_split <- dyads_ntp_split %>%
  mutate(solo_obs = ifelse(is.na(id_d) & !is.na(id), 1, 0))
dyads_ntp_split[, .N, by=solo_obs] #n=20849 solo observations

sub_solo_obs<- subset(dyads_ntp_split, select=c("id","id_d", "mdy","time_n",
                                                "item_type","cw_grp","RYG", "kcal", 
                                                "solo_obs"))

#solo occasions 
# In the case that a purchase contains multiple types of items (bevs and foods),
# There will be multiple observations per occasion. We need to calculate how 
# many unique purchasing occasions there are where a person purchases
# by themselves. 
sub_solo_occas <- (unique(sub_solo_obs, by = c("id","mdy","time_n")))
sub_solo_occas[, .N, by=solo_obs] #n=12652 solo occassions 
sub_solo_occas$solo_obs<-as.factor(sub_solo_occas$solo_obs)
levels(sub_solo_occas$solo_obs) <- c("dyadic", "solo")
sub_solo_occas[, .N, by=solo_obs] #n=12652 solo observations

#plot solo vs. dyadic distribution over the course of the day
ggplot(sub_solo_occas, aes(time_n, fill=solo_obs))+  #plots curve, w/# of seconds as unit of measure
  geom_density(alpha=0.3)+
  theme_classic()+
  scale_x_continuous("Time of ego's purchase",
                     # breaks = c("1960-01-01 00:00:00", "1960-01-01 06:00:00", 
                     #            "1960-01-01 12:00:00", "1960-01-01 18:00:00", 
                     #            "1960-01-01 11:59:00"),
                     labels=c("12:00a", "6:00a", "12:00p",
                              "6:00p", "11:59p"))+
  scale_y_continuous("Scaled density")+
  scale_fill_discrete(name = "obs type")+
  labs(title="2015")

setwd("/work/pi_mpachucki_umass_edu/food_projects/food_simulation_r01/plots")
ggsave("2015_solovsdyadic_dist.pdf", width = 5, height = 4)

setwd("/work/pi_mpachucki_umass_edu/food_projects/food_simulation_r01/data analytic")
save.image("dyads_ntp_core_2015.Rdata")
#Also save RDS (only an R object is saved) b/c we can combine all RDS in one workspace
saveRDS(dyads_ntp_split, file = "dyads_ntp_2015.RDS")
rm(list = ls())

#### 2.1 CONSTRUCT NEW DYADIC VARIABLES (2016) ####
setwd("/work/pi_mpachucki_umass_edu/food_projects/food_simulation_r01/data raw/dta")
#Read yearly dta data
dyads_ntp_split<-import("dyads_and_alone16_Jan2025.dta", 
                        setclass="data.table")
#n=31,110,836

# #Exclusion 1:  truncate dataset to remove all dyads before 10/1/2016
# dyads_ntp_split<-subset(dyads_ntp_split, mdy >= "2016-10-01")
# # n=7,834,632 observations remain

#save intermediate dataset to save time
save.image("dyads_and_alone16_Jan2025.Rdata")


#Exclusion 2: subset just the egos who are non-trial participants (NTP), coded NA
setwd("/work/pi_mpachucki_umass_edu/food_projects/food_simulation_r01/data analytic")
trial_membership_u <- readRDS("trial_membership_u.RDS")
colnames(trial_membership_u)[3] <- "newrandomdatetime" 

##left_join participants' "id"
dyads_ntp_split<- left_join(dyads_ntp_split, trial_membership_u, by="id")
trial_membership_u$newrandomdatetime_d<-trial_membership_u$newrandomdatetime #MCP added
trial_membership_u$id_d <- trial_membership_u$id
## left_join again, but by "id_d" (match alter newrandomdatetime_d with alter id)
dyads_ntp_split<- left_join(dyads_ntp_split, 
                            trial_membership_u[,c("id_d","newrandomdatetime_d")], 
                            by="id_d")

##To impute newstudy_month=25+ for egos who had joined the trial for more than 2y
#(this will become most important in late 2018 onward for select participants)
dyads_ntp_split[, "diff_year" := 
                  as.numeric(difftime(as.POSIXct(dyads_ntp_split$mdy),
                                      as.POSIXct(dyads_ntp_split$newrandomdatetime), 
                                      units = "weeks"))/52.25]
dyads_ntp_split <- dyads_ntp_split %>%
  mutate(newstudy_month = ifelse(!is.na(newrandomdatetime) & diff_year > 2,
                                 25, study_month))
#count  newstudy_month
dyads_ntp_split[, .N, by="newstudy_month"]

##If newrandomdatetime > mdy, participants were still NPEs
dyads_ntp_split[newrandomdatetime <= mdy & !is.na(newrandomdatetime), randomgroup_dyn := randomgroup.y][ newrandomdatetime > mdy & !is.na(newrandomdatetime), randomgroup_dyn := NA][is.na(newrandomdatetime), randomgroup_dyn := NA]

##Declare start date of purchases to create calmonth variable, where 1=Oct. 2016
purchasestart<-as.Date("2016-10-1") 
#note this is different than SSM, and makes this calmonth incommensurate w/SSM
dyads_ntp_split[, purchasestart := purchasestart]
dyads_ntp_split[, calmonth := floor(as.numeric(as.period(interval(purchasestart, mdy)), "month"))-12]

#Exclusion 3: exclude upper bound of multi-purchases 
# according to 0= remove, 1=keep

# Flag all individual items whose price was >$9.50
dyads_ntp_split[(price/tt_items) >9.50, priceflag:=0][price/tt_items <= 9.50, priceflag:=1]

# Flag all transactions whose total came to >$20
dyads_ntp_split[price>20.00, totalflag:=0][price <= 20.00, totalflag:=1]

# Flag all transactions with >=5 entrees
dyads_ntp_split[(tt_items>=5 & cw_grp=="entr?e"), entreeflag:=0][(tt_items<5 & cw_grp=="entr?e") | cw_grp!="entr?e", entreeflag:=1]

#Remove rows with flagged conditions - need to do it sequentially 
dyads_ntp_split2<- subset(dyads_ntp_split, entreeflag==1)
dyads_ntp_split2<- subset(dyads_ntp_split2, priceflag==1)
dyads_ntp_split2<- subset(dyads_ntp_split2, totalflag==1)

#count the difference between original and modified DT
dyads_ntp_split[, .N] #31110836
dyads_ntp_split2[, .N] #31053037

dyads_ntp_split[, .N] - dyads_ntp_split2[, .N] #57799
(dyads_ntp_split[, .N] - dyads_ntp_split2[, .N])/dyads_ntp_split[, .N] #0.001857841

#retain removed cases for inspection and re-merging if necessary
removed_cases<- subset(dyads_ntp_split, entreeflag==0 | priceflag==0 | totalflag==0)
#clean up
rm(dyads_ntp_split)
dyads_ntp_split<-dyads_ntp_split2
rm(dyads_ntp_split2)

## Recode various measures 

#Load age calculation function
age = function(from, to) {
  from_lt = as.POSIXlt(from)
  to_lt = as.POSIXlt(to)
  
  age = to_lt$year - from_lt$year
  
  ifelse(to_lt$mon < from_lt$mon |
           (to_lt$mon == from_lt$mon & to_lt$mday < from_lt$mday),
         age - 1, age)
}

#a. recode: participant age at purchase (ego), rename var, due to updated data
dyads_ntp_split<-rename(dyads_ntp_split, birthdate = Birthdate)

#b. recode: age
dyads_ntp_split[, age := age(birthdate, mdy)]  #note Birthdate/birthdate spelling
dyads_ntp_split[, age_d := age(birthdate_d, mdy)]

#c. recode: ego trial memberships
#  intervention group (1st 6m) = 6
#  intervention group (2nd 6m) = 7
#  control group (months 1-42) = 2
#  year 2 int group (1st 6m) = 3
#  year 2 int group (2nd 6m) = 4
#  nonparticipant = 5 
dyads_ntp_split[randomgroup_dyn == 1 & newstudy_month<=6, randomgroup6:=6][randomgroup_dyn == 1 & (newstudy_month>6 & newstudy_month<=12), randomgroup6:=7][randomgroup_dyn == 3, randomgroup6:=2][randomgroup_dyn == 1 & (newstudy_month>12 & newstudy_month<=18), randomgroup6:=3][randomgroup_dyn == 1 & (newstudy_month>18 & newstudy_month<=25), randomgroup6:=4]
dyads_ntp_split[is.na(randomgroup6), randomgroup6:=5]

#Ego var - generate 3-category randomgroup var
dyads_ntp_split <- dyads_ntp_split %>% 
  mutate(randomgroup3 = ifelse(randomgroup6 == 2, 2,
                               ifelse(randomgroup6 == 3 | randomgroup6 == 4 |
                                        randomgroup6 == 6 | randomgroup6 == 7, 1,
                                      ifelse(randomgroup6 == 5 & id %in% trial_membership_u[trial_membership_u$group_dup == 1,]$id, 1, 
                                             ifelse(randomgroup6 == 5 & id %in% trial_membership_u[trial_membership_u$group_dup == 2,]$id, 2, 3)))))

#Alter var
dyads_ntp_split[newrandomdatetime_d <= mdy, randomgroup_d_dyn := randomgroup_d][randomdatetime_d > mdy, randomgroup_d_dyn := NA]
dyads_ntp_split[is.na(newrandomdatetime_d), randomgroup_d_dyn := NA]
dyads_ntp_split[newrandomdatetime_d < as.Date("2016-10-01"), randomgroup_d_dyn := NA]
dyads_ntp_split[randomgroup_d_dyn == 1 &  study_month_d <=6, randomgroup6_d:=6][randomgroup_d_dyn == 1 & ( study_month_d >6 &  study_month_d <=12), randomgroup6_d:=7][randomgroup_d_dyn == 3, randomgroup6_d:=2][randomgroup_d_dyn == 1 & ( study_month_d >12 &  study_month_d <=18), randomgroup6_d:=3][randomgroup_d_dyn == 1 & ( study_month_d >18 &  study_month_d <=24), randomgroup6_d:=4]
dyads_ntp_split[is.na(randomgroup6_d), randomgroup6_d:=5]

#d. recode: education categories
#recode to: (1) HS or less, (2) Some college, (3) College, 
#           (4) Advanced degree, (5) NA (not available)
#Ego var
dyads_ntp_split[education == "B-Less Than HS Graduate" | education == "C-HS Graduate or Equivalent", ed_cat:=1][education == "D-Some College" | education == "E-Technical School" | education == "F-2-Year College Degree", ed_cat:=2][education == "G-Bachelor's Level Degree" | education == "H-Some Graduate School", ed_cat:=3][education == "I-Master's Level Degree" | education == "J-Doctorate (Academic)" | education == "K-Doctorate (Professional)" | education == "L-Post-Doctorate", ed_cat:=4]
dyads_ntp_split[is.na(ed_cat), ed_cat:=5]
#Alter var
dyads_ntp_split[education_d == "B-Less Than HS Graduate" | education_d == "C-HS Graduate or Equivalent", ed_cat_d:=1][education_d == "D-Some College" | education_d == "E-Technical School" | education_d == "F-2-Year College Degree", ed_cat_d:=2][education_d == "G-Bachelor's Level Degree" | education_d == "H-Some Graduate School", ed_cat_d:=3][education_d == "I-Master's Level Degree" | education_d == "J-Doctorate (Academic)" | education_d == "K-Doctorate (Professional)" | education_d == "L-Post-Doctorate", ed_cat_d:=4]
dyads_ntp_split[is.na(ed_cat_d), ed_cat_d:=5]

#e. recode: study year
#this is somewhat redundant of study months, but useful for easy data description
dyads_ntp_split[study_month>0 & study_month <= 12, study_year:=1][study_month > 12 & study_month <= 24, study_year:=2]

#f. recode: race 
#due to small cell sizes for both ego and alter vars  
# We need to combine "unknown" ("U") with "other" ("O")
dyads_ntp_split[race_cat == "A", race_cat5:="A"][race_cat == "B", race_cat5:="B"][race_cat == "H", race_cat5:="H"][race_cat == "O", race_cat5:="O"][race_cat == "U", race_cat5:="O"][race_cat == "W", race_cat5:="W"]
dyads_ntp_split[race_cat_d == "A", race_cat5_d:="A"][race_cat_d == "B", race_cat5_d:="B"][race_cat_d == "H", race_cat5_d:="H"][race_cat_d == "O", race_cat5_d:="O"][race_cat_d == "U", race_cat5_d:="O"][race_cat_d == "W", race_cat5_d:="W"]

#g. recode: job category
#recode observations with "no EEO-1 reporting" job category to "NA" because of small cells
# For egos in 2016 it's n=2, 2017 n=2, 2018 n=2, 2019 n=1
dyads_ntp_split[job_cat == "No EEO-1 Reporting", job_cat:=NA]
dyads_ntp_split[job_cat_d == "No EEO-1 Reporting", job_cat:=NA]

#h. recode: transform cw_grp from UTF-8 encoding to latin for "entr?e"
dyads_ntp_split$cw_grp<-iconv(dyads_ntp_split$cw_grp, "latin1", "UTF-8")

#i. recode: create new var to denote item type (food or beverage)
dyads_ntp_split[cw_grp != "beverage", item_type:="food"][cw_grp == "beverage", item_type:="bev"]

## Diagnostics 
#solo observations (row-level)
dyads_ntp_split <- dyads_ntp_split %>%
  mutate(solo_obs = ifelse(is.na(id_d) & !is.na(id), 1, 0))
dyads_ntp_split[, .N, by=solo_obs] #n=139876 solo observations

sub_solo_obs<- subset(dyads_ntp_split, select=c("id","id_d", "mdy","time_n",
                                                "item_type","cw_grp","RYG", "kcal", 
                                                "solo_obs"))

#solo occasions 
# In the case that a purchase contains multiple types of items (bevs and foods),
# There will be multiple observations per occasion. We need to calculate how 
# many unique purchasing occasions there are where a person purchases
# by themselves. 
sub_solo_occas <- (unique(sub_solo_obs, by = c("id","mdy","time_n")))
sub_solo_occas[, .N, by=solo_obs] #n=84878 solo occassions 
sub_solo_occas$solo_obs<-as.factor(sub_solo_occas$solo_obs)
levels(sub_solo_occas$solo_obs) <- c("dyadic", "solo")
sub_solo_occas[, .N, by=solo_obs] #n=84878 solo observations

#plot solo vs. dyadic distribution over the course of the day
ggplot(sub_solo_occas, aes(time_n, fill=solo_obs))+  #plots curve, w/# of seconds as unit of measure
  geom_density(alpha=0.3)+
  theme_classic()+
  scale_x_continuous("Time of ego's purchase",
                     # breaks = c("1960-01-01 00:00:00", "1960-01-01 06:00:00", 
                     #            "1960-01-01 12:00:00", "1960-01-01 18:00:00", 
                     #            "1960-01-01 11:59:00"),
                     labels=c("12:00a", "6:00a", "12:00p",
                              "6:00p", "11:59p"))+
  scale_y_continuous("Scaled density")+
  scale_fill_discrete(name = "obs type")+
  labs(title="2016")

setwd("/work/pi_mpachucki_umass_edu/food_projects/food_simulation_r01/plots")
ggsave("2016_solovsdyadic_dist.pdf", width = 5, height = 4)

setwd("/work/pi_mpachucki_umass_edu/food_projects/food_simulation_r01/data analytic")
save.image("dyads_ntp_core_2016.Rdata")
#Also save RDS (only an R object is saved) b/c we can combine all RDS in one workspace
saveRDS(dyads_ntp_split, file = "dyads_ntp_2016.RDS")
rm(list = ls())


#### 2.2 CONSTRUCT NEW DYADIC VARIABLES (2017) ####
setwd("/work/pi_mpachucki_umass_edu/food_projects/food_simulation_r01/data raw/dta")
#Read yearly dta data
dyads_ntp_split<-import("dyads_and_alone17_Jan2025.dta", 
                        setclass="data.table")
dyads_ntp_split[, .N] #x
#n=29163104

## NO LONGER AN EXCLUSION - WE'RE KEEPING ALL OF 2016 b/c of YEAR STRUCTURE OF SAOM
# #Exclusion 1:  truncate dataset to remove all dyads before 10/1/2016
# dyads_ntp_split<-subset(dyads_ntp_split, mdy >= "2016-10-01")
# # n=7,834,632 observations remain
# 
# #save intermediate dataset to save time
# save.image("dyads_and_alone16_Jan2025_102016+.Rdata")

#Exclusion 2: subset just the egos who are non-trial participants (NTP), coded NA
setwd("/work/pi_mpachucki_umass_edu/food_projects/food_simulation_r01/data analytic")
trial_membership_u <- readRDS("trial_membership_u.RDS")
colnames(trial_membership_u)[3] <- "newrandomdatetime" 

##left_join participants' "id"
dyads_ntp_split<- left_join(dyads_ntp_split, trial_membership_u, by="id")
trial_membership_u$newrandomdatetime_d<-trial_membership_u$newrandomdatetime #MCP added
trial_membership_u$id_d <- trial_membership_u$id
## left_join again, but by "id_d" (match alter newrandomdatetime_d with alter id)
dyads_ntp_split<- left_join(dyads_ntp_split, 
                            trial_membership_u[,c("id_d","newrandomdatetime_d")], 
                            by="id_d")

##To impute newstudy_month=25+ for egos who had joined the trial for more than 2y
#(this will become most important in late 2018 onward for select participants)
dyads_ntp_split[, "diff_year" := 
                  as.numeric(difftime(as.POSIXct(dyads_ntp_split$mdy),
                                      as.POSIXct(dyads_ntp_split$newrandomdatetime), 
                                      units = "weeks"))/52.25]
dyads_ntp_split <- dyads_ntp_split %>%
  mutate(newstudy_month = ifelse(!is.na(newrandomdatetime) & diff_year > 2,
                                 25, study_month))
#count  newstudy_month
dyads_ntp_split[, .N, by="newstudy_month"]

##If newrandomdatetime > mdy, participants were still NPEs
dyads_ntp_split[newrandomdatetime <= mdy & !is.na(newrandomdatetime), randomgroup_dyn := randomgroup.y][ newrandomdatetime > mdy & !is.na(newrandomdatetime), randomgroup_dyn := NA][is.na(newrandomdatetime), randomgroup_dyn := NA]

##Declare start date of purchases to create calmonth variable, where 1=Oct. 2016
purchasestart<-as.Date("2016-10-1") 
#note this is different than SSM, and makes this calmonth incommensurate w/SSM
dyads_ntp_split[, purchasestart := purchasestart]
dyads_ntp_split[, calmonth := floor(as.numeric(as.period(interval(purchasestart, mdy)), "month"))-12]

#Exclusion 3: exclude upper bound of multi-purchases 
# according to 0= remove, 1=keep

# Flag all individual items whose price was >$9.50
dyads_ntp_split[(price/tt_items) >9.50, priceflag:=0][price/tt_items <= 9.50, priceflag:=1]

# Flag all transactions whose total came to >$20
dyads_ntp_split[price>20.00, totalflag:=0][price <= 20.00, totalflag:=1]

# Flag all transactions with >=5 entrees
dyads_ntp_split[(tt_items>=5 & cw_grp=="entr?e"), entreeflag:=0][(tt_items<5 & cw_grp=="entr?e") | cw_grp!="entr?e", entreeflag:=1]

#Remove rows with flagged conditions - need to do it sequentially 
dyads_ntp_split2<- subset(dyads_ntp_split, entreeflag==1)
dyads_ntp_split2<- subset(dyads_ntp_split2, priceflag==1)
dyads_ntp_split2<- subset(dyads_ntp_split2, totalflag==1)

#count the difference between original and modified DT
dyads_ntp_split[, .N] #29163104
dyads_ntp_split2[, .N] #29092811

dyads_ntp_split[, .N] - dyads_ntp_split2[, .N] #70293
(dyads_ntp_split[, .N] - dyads_ntp_split2[, .N])/dyads_ntp_split[, .N] #0.00241034

#retain removed cases for inspection and re-merging if necessary
removed_cases<- subset(dyads_ntp_split, entreeflag==0 | priceflag==0 | totalflag==0)
#clean up
rm(dyads_ntp_split)
dyads_ntp_split<-dyads_ntp_split2
rm(dyads_ntp_split2)
gc()

## Recode various measures 

#Load age calculation function
age = function(from, to) {
  from_lt = as.POSIXlt(from)
  to_lt = as.POSIXlt(to)
  
  age = to_lt$year - from_lt$year
  
  ifelse(to_lt$mon < from_lt$mon |
           (to_lt$mon == from_lt$mon & to_lt$mday < from_lt$mday),
         age - 1, age)
}

#a. recode: participant age at purchase (ego), rename var, due to updated data
dyads_ntp_split<-rename(dyads_ntp_split, birthdate = Birthdate)

#b. recode: age
dyads_ntp_split[, age := age(birthdate, mdy)]  #note Birthdate/birthdate spelling
dyads_ntp_split[, age_d := age(birthdate_d, mdy)]

#c. recode: ego trial memberships
#  intervention group (1st 6m) = 6
#  intervention group (2nd 6m) = 7
#  control group (months 1-42) = 2
#  year 2 int group (1st 6m) = 3
#  year 2 int group (2nd 6m) = 4
#  nonparticipant = 5 
dyads_ntp_split[randomgroup_dyn == 1 & newstudy_month<=6, randomgroup6:=6][randomgroup_dyn == 1 & (newstudy_month>6 & newstudy_month<=12), randomgroup6:=7][randomgroup_dyn == 3, randomgroup6:=2][randomgroup_dyn == 1 & (newstudy_month>12 & newstudy_month<=18), randomgroup6:=3][randomgroup_dyn == 1 & (newstudy_month>18 & newstudy_month<=25), randomgroup6:=4]
dyads_ntp_split[is.na(randomgroup6), randomgroup6:=5]

#Ego var - generate 3-category randomgroup var
dyads_ntp_split <- dyads_ntp_split %>% 
  mutate(randomgroup3 = ifelse(randomgroup6 == 2, 2,
                               ifelse(randomgroup6 == 3 | randomgroup6 == 4 |
                                        randomgroup6 == 6 | randomgroup6 == 7, 1,
                                      ifelse(randomgroup6 == 5 & id %in% trial_membership_u[trial_membership_u$group_dup == 1,]$id, 1, 
                                             ifelse(randomgroup6 == 5 & id %in% trial_membership_u[trial_membership_u$group_dup == 2,]$id, 2, 3)))))

#Alter var
dyads_ntp_split[newrandomdatetime_d <= mdy, randomgroup_d_dyn := randomgroup_d][randomdatetime_d > mdy, randomgroup_d_dyn := NA]
dyads_ntp_split[is.na(newrandomdatetime_d), randomgroup_d_dyn := NA]
dyads_ntp_split[newrandomdatetime_d < as.Date("2016-10-01"), randomgroup_d_dyn := NA]
dyads_ntp_split[randomgroup_d_dyn == 1 &  study_month_d <=6, randomgroup6_d:=6][randomgroup_d_dyn == 1 & ( study_month_d >6 &  study_month_d <=12), randomgroup6_d:=7][randomgroup_d_dyn == 3, randomgroup6_d:=2][randomgroup_d_dyn == 1 & ( study_month_d >12 &  study_month_d <=18), randomgroup6_d:=3][randomgroup_d_dyn == 1 & ( study_month_d >18 &  study_month_d <=24), randomgroup6_d:=4]
dyads_ntp_split[is.na(randomgroup6_d), randomgroup6_d:=5]

#d. recode: education categories
#recode to: (1) HS or less, (2) Some college, (3) College, 
#           (4) Advanced degree, (5) NA (not available)
#Ego var
dyads_ntp_split[education == "B-Less Than HS Graduate" | education == "C-HS Graduate or Equivalent", ed_cat:=1][education == "D-Some College" | education == "E-Technical School" | education == "F-2-Year College Degree", ed_cat:=2][education == "G-Bachelor's Level Degree" | education == "H-Some Graduate School", ed_cat:=3][education == "I-Master's Level Degree" | education == "J-Doctorate (Academic)" | education == "K-Doctorate (Professional)" | education == "L-Post-Doctorate", ed_cat:=4]
dyads_ntp_split[is.na(ed_cat), ed_cat:=5]
#Alter var
dyads_ntp_split[education_d == "B-Less Than HS Graduate" | education_d == "C-HS Graduate or Equivalent", ed_cat_d:=1][education_d == "D-Some College" | education_d == "E-Technical School" | education_d == "F-2-Year College Degree", ed_cat_d:=2][education_d == "G-Bachelor's Level Degree" | education_d == "H-Some Graduate School", ed_cat_d:=3][education_d == "I-Master's Level Degree" | education_d == "J-Doctorate (Academic)" | education_d == "K-Doctorate (Professional)" | education_d == "L-Post-Doctorate", ed_cat_d:=4]
dyads_ntp_split[is.na(ed_cat_d), ed_cat_d:=5]

#e. recode: study year
#this is somewhat redundant of study months, but useful for easy data description
dyads_ntp_split[study_month>0 & study_month <= 12, study_year:=1][study_month > 12 & study_month <= 24, study_year:=2]

#f. recode: race 
#due to small cell sizes for both ego and alter vars  
# We need to combine "unknown" ("U") with "other" ("O")
dyads_ntp_split[race_cat == "A", race_cat5:="A"][race_cat == "B", race_cat5:="B"][race_cat == "H", race_cat5:="H"][race_cat == "O", race_cat5:="O"][race_cat == "U", race_cat5:="O"][race_cat == "W", race_cat5:="W"]
dyads_ntp_split[race_cat_d == "A", race_cat5_d:="A"][race_cat_d == "B", race_cat5_d:="B"][race_cat_d == "H", race_cat5_d:="H"][race_cat_d == "O", race_cat5_d:="O"][race_cat_d == "U", race_cat5_d:="O"][race_cat_d == "W", race_cat5_d:="W"]

#g. recode: job category
#recode observations with "no EEO-1 reporting" job category to "NA" because of small cells
# For egos in 2016 it's n=2, 2017 n=2, 2018 n=2, 2019 n=1
dyads_ntp_split[job_cat == "No EEO-1 Reporting", job_cat:=NA]
dyads_ntp_split[job_cat_d == "No EEO-1 Reporting", job_cat:=NA]

#h. recode: transform cw_grp from UTF-8 encoding to latin for "entr?e"
dyads_ntp_split$cw_grp<-iconv(dyads_ntp_split$cw_grp, "latin1", "UTF-8")

#i. recode: create new var to denote item type (food or beverage)
dyads_ntp_split[cw_grp != "beverage", item_type:="food"][cw_grp == "beverage", item_type:="bev"]

## Diagnostics 
#solo observations (row-level)
dyads_ntp_split <- dyads_ntp_split %>%
  mutate(solo_obs = ifelse(is.na(id_d) & !is.na(id), 1, 0))
dyads_ntp_split[, .N, by=solo_obs] #n=143314 solo observations

sub_solo_obs<- subset(dyads_ntp_split, select=c("id","id_d", "mdy","time_n",
                                                "item_type","cw_grp","RYG", "kcal", 
                                                "solo_obs"))

#solo occasions 
# In the case that a purchase contains multiple types of items (bevs and foods),
# There will be multiple observations per occasion. We need to calculate how 
# many unique purchasing occasions there are where a person purchases
# by themselves. 
sub_solo_occas <- (unique(sub_solo_obs, by = c("id","mdy","time_n")))
sub_solo_occas[, .N, by=solo_obs] #n=87121 solo occassions 
sub_solo_occas$solo_obs<-as.factor(sub_solo_occas$solo_obs)
levels(sub_solo_occas$solo_obs) <- c("dyadic", "solo")
sub_solo_occas[, .N, by=solo_obs] #n=87121 solo observations

#plot solo vs. dyadic distribution over the course of the day
ggplot(sub_solo_occas, aes(time_n, fill=solo_obs))+  #plots curve, w/# of seconds as unit of measure
  geom_density(alpha=0.3)+
  theme_classic()+
  scale_x_continuous("Time of ego's purchase",
                     # breaks = c("1960-01-01 00:00:00", "1960-01-01 06:00:00", 
                     #            "1960-01-01 12:00:00", "1960-01-01 18:00:00", 
                     #            "1960-01-01 11:59:00"),
                     labels=c("12:00a", "6:00a", "12:00p",
                              "6:00p", "11:59p"))+
  scale_y_continuous("Scaled density")+
  scale_fill_discrete(name = "obs type")+
  labs(title="2017")

setwd("/work/pi_mpachucki_umass_edu/food_projects/food_simulation_r01/plots")
ggsave("2017_solovsdyadic_dist.pdf", width = 5, height = 4)

setwd("/work/pi_mpachucki_umass_edu/food_projects/food_simulation_r01/data analytic")
save.image("dyads_ntp_core_2017.Rdata")
#Also save RDS (only an R object is saved) b/c we can combine all RDS in one workspace
saveRDS(dyads_ntp_split, file = "dyads_ntp_2017.RDS")
rm(list = ls())


#### 2.3 CONSTRUCT NEW DYADIC VARIABLES (2018) ####
setwd("/work/pi_mpachucki_umass_edu/food_projects/food_simulation_r01/data raw/dta")
#Read yearly dta data
dyads_ntp_split<-import("dyads_and_alone18_Jan2025.dta", 
                        setclass="data.table")
dyads_ntp_split[, .N] #26042011

# #Exclusion 1:  truncate dataset to remove all dyads before 10/1/2016
# dyads_ntp_split<-subset(dyads_ntp_split, mdy >= "2016-10-01")
# # n=7,834,632 observations remain
# 
# #save intermediate dataset to save time
# save.image("dyads_and_alone16_Jan2025_102016+.Rdata")

#Exclusion 2: subset just the egos who are non-trial participants (NTP), coded NA
setwd("/work/pi_mpachucki_umass_edu/food_projects/food_simulation_r01/data analytic")
trial_membership_u <- readRDS("trial_membership_u.RDS")
colnames(trial_membership_u)[3] <- "newrandomdatetime" 

##left_join participants' "id"
dyads_ntp_split<- left_join(dyads_ntp_split, trial_membership_u, by="id")
trial_membership_u$newrandomdatetime_d<-trial_membership_u$newrandomdatetime #MCP added
trial_membership_u$id_d <- trial_membership_u$id
## left_join again, but by "id_d" (match alter newrandomdatetime_d with alter id)
dyads_ntp_split<- left_join(dyads_ntp_split, 
                            trial_membership_u[,c("id_d","newrandomdatetime_d")], 
                            by="id_d")

##To impute newstudy_month=25+ for egos who had joined the trial for more than 2y
#(this will become most important in late 2018 onward for select participants)
dyads_ntp_split[, "diff_year" := 
                  as.numeric(difftime(as.POSIXct(dyads_ntp_split$mdy),
                                      as.POSIXct(dyads_ntp_split$newrandomdatetime), 
                                      units = "weeks"))/52.25]
dyads_ntp_split <- dyads_ntp_split %>%
  mutate(newstudy_month = ifelse(!is.na(newrandomdatetime) & diff_year > 2,
                                 25, study_month))
#count  newstudy_month
dyads_ntp_split[, .N, by="newstudy_month"]

##If newrandomdatetime > mdy, participants were still NPEs
dyads_ntp_split[newrandomdatetime <= mdy & !is.na(newrandomdatetime), randomgroup_dyn := randomgroup.y][ newrandomdatetime > mdy & !is.na(newrandomdatetime), randomgroup_dyn := NA][is.na(newrandomdatetime), randomgroup_dyn := NA]

##Declare start date of purchases to create calmonth variable, where 1=Oct. 2016
purchasestart<-as.Date("2016-10-1") 
#note this is different than SSM, and makes this calmonth incommensurate w/SSM
dyads_ntp_split[, purchasestart := purchasestart]
dyads_ntp_split[, calmonth := floor(as.numeric(as.period(interval(purchasestart, mdy)), "month"))-12]

#Exclusion 3: exclude upper bound of multi-purchases 
# according to 0= remove, 1=keep

# Flag all individual items whose price was >$9.50
dyads_ntp_split[(price/tt_items) >9.50, priceflag:=0][price/tt_items <= 9.50, priceflag:=1]

# Flag all transactions whose total came to >$20
dyads_ntp_split[price>20.00, totalflag:=0][price <= 20.00, totalflag:=1]

# Flag all transactions with >=5 entrees
dyads_ntp_split[(tt_items>=5 & cw_grp=="entr?e"), entreeflag:=0][(tt_items<5 & cw_grp=="entr?e") | cw_grp!="entr?e", entreeflag:=1]

#Remove rows with flagged conditions - need to do it sequentially 
dyads_ntp_split2<- subset(dyads_ntp_split, entreeflag==1)
dyads_ntp_split2<- subset(dyads_ntp_split2, priceflag==1)
dyads_ntp_split2<- subset(dyads_ntp_split2, totalflag==1)

#count the difference between original and modified DT
dyads_ntp_split[, .N] #26042011
dyads_ntp_split2[, .N] #25965607

dyads_ntp_split[, .N] - dyads_ntp_split2[, .N] #76404
(dyads_ntp_split[, .N] - dyads_ntp_split2[, .N])/dyads_ntp_split[, .N] #0.002933875

#retain removed cases for inspection and re-merging if necessary
removed_cases<- subset(dyads_ntp_split, entreeflag==0 | priceflag==0 | totalflag==0)
#clean up
rm(dyads_ntp_split)
dyads_ntp_split<-dyads_ntp_split2
rm(dyads_ntp_split2)

## Recode various measures 

#Load age calculation function
age = function(from, to) {
  from_lt = as.POSIXlt(from)
  to_lt = as.POSIXlt(to)
  
  age = to_lt$year - from_lt$year
  
  ifelse(to_lt$mon < from_lt$mon |
           (to_lt$mon == from_lt$mon & to_lt$mday < from_lt$mday),
         age - 1, age)
}

#a. recode: participant age at purchase (ego), rename var, due to updated data
dyads_ntp_split<-rename(dyads_ntp_split, birthdate = Birthdate)

#b. recode: age
dyads_ntp_split[, age := age(birthdate, mdy)]  #note Birthdate/birthdate spelling
dyads_ntp_split[, age_d := age(birthdate_d, mdy)]

#c. recode: ego trial memberships
#  intervention group (1st 6m) = 6
#  intervention group (2nd 6m) = 7
#  control group (months 1-42) = 2
#  year 2 int group (1st 6m) = 3
#  year 2 int group (2nd 6m) = 4
#  nonparticipant = 5 
dyads_ntp_split[randomgroup_dyn == 1 & newstudy_month<=6, randomgroup6:=6][randomgroup_dyn == 1 & (newstudy_month>6 & newstudy_month<=12), randomgroup6:=7][randomgroup_dyn == 3, randomgroup6:=2][randomgroup_dyn == 1 & (newstudy_month>12 & newstudy_month<=18), randomgroup6:=3][randomgroup_dyn == 1 & (newstudy_month>18 & newstudy_month<=25), randomgroup6:=4]
dyads_ntp_split[is.na(randomgroup6), randomgroup6:=5]

#Ego var - generate 3-category randomgroup var
dyads_ntp_split <- dyads_ntp_split %>% 
  mutate(randomgroup3 = ifelse(randomgroup6 == 2, 2,
                               ifelse(randomgroup6 == 3 | randomgroup6 == 4 |
                                        randomgroup6 == 6 | randomgroup6 == 7, 1,
                                      ifelse(randomgroup6 == 5 & id %in% trial_membership_u[trial_membership_u$group_dup == 1,]$id, 1, 
                                             ifelse(randomgroup6 == 5 & id %in% trial_membership_u[trial_membership_u$group_dup == 2,]$id, 2, 3)))))

#Alter var
dyads_ntp_split[newrandomdatetime_d <= mdy, randomgroup_d_dyn := randomgroup_d][randomdatetime_d > mdy, randomgroup_d_dyn := NA]
dyads_ntp_split[is.na(newrandomdatetime_d), randomgroup_d_dyn := NA]
dyads_ntp_split[newrandomdatetime_d < as.Date("2016-10-01"), randomgroup_d_dyn := NA]
dyads_ntp_split[randomgroup_d_dyn == 1 &  study_month_d <=6, randomgroup6_d:=6][randomgroup_d_dyn == 1 & ( study_month_d >6 &  study_month_d <=12), randomgroup6_d:=7][randomgroup_d_dyn == 3, randomgroup6_d:=2][randomgroup_d_dyn == 1 & ( study_month_d >12 &  study_month_d <=18), randomgroup6_d:=3][randomgroup_d_dyn == 1 & ( study_month_d >18 &  study_month_d <=24), randomgroup6_d:=4]
dyads_ntp_split[is.na(randomgroup6_d), randomgroup6_d:=5]

#d. recode: education categories
#recode to: (1) HS or less, (2) Some college, (3) College, 
#           (4) Advanced degree, (5) NA (not available)
#Ego var
dyads_ntp_split[education == "B-Less Than HS Graduate" | education == "C-HS Graduate or Equivalent", ed_cat:=1][education == "D-Some College" | education == "E-Technical School" | education == "F-2-Year College Degree", ed_cat:=2][education == "G-Bachelor's Level Degree" | education == "H-Some Graduate School", ed_cat:=3][education == "I-Master's Level Degree" | education == "J-Doctorate (Academic)" | education == "K-Doctorate (Professional)" | education == "L-Post-Doctorate", ed_cat:=4]
dyads_ntp_split[is.na(ed_cat), ed_cat:=5]
#Alter var
dyads_ntp_split[education_d == "B-Less Than HS Graduate" | education_d == "C-HS Graduate or Equivalent", ed_cat_d:=1][education_d == "D-Some College" | education_d == "E-Technical School" | education_d == "F-2-Year College Degree", ed_cat_d:=2][education_d == "G-Bachelor's Level Degree" | education_d == "H-Some Graduate School", ed_cat_d:=3][education_d == "I-Master's Level Degree" | education_d == "J-Doctorate (Academic)" | education_d == "K-Doctorate (Professional)" | education_d == "L-Post-Doctorate", ed_cat_d:=4]
dyads_ntp_split[is.na(ed_cat_d), ed_cat_d:=5]

#e. recode: study year
#this is somewhat redundant of study months, but useful for easy data description
dyads_ntp_split[study_month>0 & study_month <= 12, study_year:=1][study_month > 12 & study_month <= 24, study_year:=2]

#f. recode: race 
#due to small cell sizes for both ego and alter vars  
# We need to combine "unknown" ("U") with "other" ("O")
dyads_ntp_split[race_cat == "A", race_cat5:="A"][race_cat == "B", race_cat5:="B"][race_cat == "H", race_cat5:="H"][race_cat == "O", race_cat5:="O"][race_cat == "U", race_cat5:="O"][race_cat == "W", race_cat5:="W"]
dyads_ntp_split[race_cat_d == "A", race_cat5_d:="A"][race_cat_d == "B", race_cat5_d:="B"][race_cat_d == "H", race_cat5_d:="H"][race_cat_d == "O", race_cat5_d:="O"][race_cat_d == "U", race_cat5_d:="O"][race_cat_d == "W", race_cat5_d:="W"]

#g. recode: job category
#recode observations with "no EEO-1 reporting" job category to "NA" because of small cells
# For egos in 2016 it's n=2, 2017 n=2, 2018 n=2, 2019 n=1
dyads_ntp_split[job_cat == "No EEO-1 Reporting", job_cat:=NA]
dyads_ntp_split[job_cat_d == "No EEO-1 Reporting", job_cat:=NA]

#h. recode: transform cw_grp from UTF-8 encoding to latin for "entr?e"
dyads_ntp_split$cw_grp<-iconv(dyads_ntp_split$cw_grp, "latin1", "UTF-8")

#i. recode: create new var to denote item type (food or beverage)
dyads_ntp_split[cw_grp != "beverage", item_type:="food"][cw_grp == "beverage", item_type:="bev"]

## Diagnostics 
#solo observations (row-level)
dyads_ntp_split <- dyads_ntp_split %>%
  mutate(solo_obs = ifelse(is.na(id_d) & !is.na(id), 1, 0))
dyads_ntp_split[, .N, by=solo_obs] #n=123112 solo observations

sub_solo_obs<- subset(dyads_ntp_split, select=c("id","id_d", "mdy","time_n",
                                                "item_type","cw_grp","RYG", "kcal", 
                                                "solo_obs"))

#solo occasions 
# In the case that a purchase contains multiple types of items (bevs and foods),
# There will be multiple observations per occasion. We need to calculate how 
# many unique purchasing occasions there are where a person purchases
# by themselves. 
sub_solo_occas <- (unique(sub_solo_obs, by = c("id","mdy","time_n")))
sub_solo_occas[, .N, by=solo_obs] #n=74541 solo occassions 
sub_solo_occas$solo_obs<-as.factor(sub_solo_occas$solo_obs) #change for grouping
levels(sub_solo_occas$solo_obs) <- c("dyadic", "solo") #label the levels
sub_solo_occas[, .N, by=solo_obs] #n=74541 solo observations

#plot solo vs. dyadic distribution over the course of the day
ggplot(sub_solo_occas, aes(time_n, fill=solo_obs))+  #plots curve, w/# of seconds as unit of measure
  geom_density(alpha=0.3)+
  theme_classic()+
  scale_x_continuous("Time of ego's purchase",
                     # breaks = c("1960-01-01 00:00:00", "1960-01-01 06:00:00", 
                     #            "1960-01-01 12:00:00", "1960-01-01 18:00:00", 
                     #            "1960-01-01 11:59:00"),
                     labels=c("12:00a", "6:00a", "12:00p",
                              "6:00p", "11:59p"))+
  scale_y_continuous("Scaled density")+
  scale_fill_discrete(name = "obs type")+
  labs(title="2018")

setwd("/work/pi_mpachucki_umass_edu/food_projects/food_simulation_r01/plots")
ggsave("2018_solovsdyadic_dist.pdf", width = 5, height = 4)

setwd("/work/pi_mpachucki_umass_edu/food_projects/food_simulation_r01/data analytic")
save.image("dyads_ntp_core_2018.Rdata")

#Also save RDS (only an R object is saved) b/c we can combine all RDS in one workspace
saveRDS(dyads_ntp_split, file = "dyads_ntp_2018.RDS")
rm(list = ls())



#### 2.4 CONSTRUCT NEW DYADIC VARIABLES (2019) ####
setwd("/work/pi_mpachucki_umass_edu/food_projects/food_simulation_r01/data raw/dta")
#Read yearly dta data
dyads_ntp_split<-import("dyads_and_alone19_Jan2025.dta", 
                        setclass="data.table")
dyads_ntp_split[, .N] #25050599

# #Exclusion 1:  truncate dataset to remove all dyads before 10/1/2016
# dyads_ntp_split<-subset(dyads_ntp_split, mdy >= "2016-10-01")
# # n=7,834,632 observations remain
# 
# #save intermediate dataset to save time
# save.image("dyads_and_alone16_Jan2025_102016+.Rdata")

#Exclusion 2: subset just the egos who are non-trial participants (NTP), coded NA
setwd("/work/pi_mpachucki_umass_edu/food_projects/food_simulation_r01/data analytic")
trial_membership_u <- readRDS("trial_membership_u.RDS")
colnames(trial_membership_u)[3] <- "newrandomdatetime" 

##left_join participants' "id"
dyads_ntp_split<- left_join(dyads_ntp_split, trial_membership_u, by="id")
trial_membership_u$newrandomdatetime_d<-trial_membership_u$newrandomdatetime #MCP added
trial_membership_u$id_d <- trial_membership_u$id
## left_join again, but by "id_d" (match alter newrandomdatetime_d with alter id)
dyads_ntp_split<- left_join(dyads_ntp_split, 
                            trial_membership_u[,c("id_d","newrandomdatetime_d")], 
                            by="id_d")

##To impute newstudy_month=25+ for egos who had joined the trial for more than 2y
#(this will become most important in late 2018 onward for select participants)
dyads_ntp_split[, "diff_year" := 
                  as.numeric(difftime(as.POSIXct(dyads_ntp_split$mdy),
                                      as.POSIXct(dyads_ntp_split$newrandomdatetime), 
                                      units = "weeks"))/52.25]
dyads_ntp_split <- dyads_ntp_split %>%
  mutate(newstudy_month = ifelse(!is.na(newrandomdatetime) & diff_year > 2,
                                 25, study_month))
#count  newstudy_month
dyads_ntp_split[, .N, by="newstudy_month"]

##If newrandomdatetime > mdy, participants were still NPEs
dyads_ntp_split[newrandomdatetime <= mdy & !is.na(newrandomdatetime), randomgroup_dyn := randomgroup.y][ newrandomdatetime > mdy & !is.na(newrandomdatetime), randomgroup_dyn := NA][is.na(newrandomdatetime), randomgroup_dyn := NA]

##Declare start date of purchases to create calmonth variable, where 1=Oct. 2016
purchasestart<-as.Date("2016-10-1") 
#note this is different than SSM, and makes this calmonth incommensurate w/SSM
dyads_ntp_split[, purchasestart := purchasestart]
dyads_ntp_split[, calmonth := floor(as.numeric(as.period(interval(purchasestart, mdy)), "month"))-12]

#Exclusion 3: exclude upper bound of multi-purchases 
# according to 0= remove, 1=keep

# Flag all individual items whose price was >$9.50
dyads_ntp_split[(price/tt_items) >9.50, priceflag:=0][price/tt_items <= 9.50, priceflag:=1]

# Flag all transactions whose total came to >$20
dyads_ntp_split[price>20.00, totalflag:=0][price <= 20.00, totalflag:=1]

# Flag all transactions with >=5 entrees
dyads_ntp_split[(tt_items>=5 & cw_grp=="entr?e"), entreeflag:=0][(tt_items<5 & cw_grp=="entr?e") | cw_grp!="entr?e", entreeflag:=1]

#Remove rows with flagged conditions - need to do it sequentially 
dyads_ntp_split2<- subset(dyads_ntp_split, entreeflag==1)
dyads_ntp_split2<- subset(dyads_ntp_split2, priceflag==1)
dyads_ntp_split2<- subset(dyads_ntp_split2, totalflag==1)

#count the difference between original and modified DT
dyads_ntp_split[, .N] #25050599
dyads_ntp_split2[, .N] #24921760

dyads_ntp_split[, .N] - dyads_ntp_split2[, .N] #128839
(dyads_ntp_split[, .N] - dyads_ntp_split2[, .N])/dyads_ntp_split[, .N] #0.00514315

#retain removed cases for inspection and re-merging if necessary
removed_cases<- subset(dyads_ntp_split, entreeflag==0 | priceflag==0 | totalflag==0)
#clean up
rm(dyads_ntp_split)
dyads_ntp_split<-dyads_ntp_split2
rm(dyads_ntp_split2)

## Recode various measures 

#Load age calculation function
age = function(from, to) {
  from_lt = as.POSIXlt(from)
  to_lt = as.POSIXlt(to)
  
  age = to_lt$year - from_lt$year
  
  ifelse(to_lt$mon < from_lt$mon |
           (to_lt$mon == from_lt$mon & to_lt$mday < from_lt$mday),
         age - 1, age)
}

#a. recode: participant age at purchase (ego), rename var, due to updated data
dyads_ntp_split<-rename(dyads_ntp_split, birthdate = Birthdate)

#b. recode: age
dyads_ntp_split[, age := age(birthdate, mdy)]  #note Birthdate/birthdate spelling
dyads_ntp_split[, age_d := age(birthdate_d, mdy)]

#c. recode: ego trial memberships
#  intervention group (1st 6m) = 6
#  intervention group (2nd 6m) = 7
#  control group (months 1-42) = 2
#  year 2 int group (1st 6m) = 3
#  year 2 int group (2nd 6m) = 4
#  nonparticipant = 5 
dyads_ntp_split[randomgroup_dyn == 1 & newstudy_month<=6, randomgroup6:=6][randomgroup_dyn == 1 & (newstudy_month>6 & newstudy_month<=12), randomgroup6:=7][randomgroup_dyn == 3, randomgroup6:=2][randomgroup_dyn == 1 & (newstudy_month>12 & newstudy_month<=18), randomgroup6:=3][randomgroup_dyn == 1 & (newstudy_month>18 & newstudy_month<=25), randomgroup6:=4]
dyads_ntp_split[is.na(randomgroup6), randomgroup6:=5]

#Ego var - generate 3-category randomgroup var
dyads_ntp_split <- dyads_ntp_split %>% 
  mutate(randomgroup3 = ifelse(randomgroup6 == 2, 2,
                               ifelse(randomgroup6 == 3 | randomgroup6 == 4 |
                                        randomgroup6 == 6 | randomgroup6 == 7, 1,
                                      ifelse(randomgroup6 == 5 & id %in% trial_membership_u[trial_membership_u$group_dup == 1,]$id, 1, 
                                             ifelse(randomgroup6 == 5 & id %in% trial_membership_u[trial_membership_u$group_dup == 2,]$id, 2, 3)))))

#Alter var
dyads_ntp_split[newrandomdatetime_d <= mdy, randomgroup_d_dyn := randomgroup_d][randomdatetime_d > mdy, randomgroup_d_dyn := NA]
dyads_ntp_split[is.na(newrandomdatetime_d), randomgroup_d_dyn := NA]
dyads_ntp_split[newrandomdatetime_d < as.Date("2016-10-01"), randomgroup_d_dyn := NA]
dyads_ntp_split[randomgroup_d_dyn == 1 &  study_month_d <=6, randomgroup6_d:=6][randomgroup_d_dyn == 1 & ( study_month_d >6 &  study_month_d <=12), randomgroup6_d:=7][randomgroup_d_dyn == 3, randomgroup6_d:=2][randomgroup_d_dyn == 1 & ( study_month_d >12 &  study_month_d <=18), randomgroup6_d:=3][randomgroup_d_dyn == 1 & ( study_month_d >18 &  study_month_d <=24), randomgroup6_d:=4]
dyads_ntp_split[is.na(randomgroup6_d), randomgroup6_d:=5]

#d. recode: education categories
#recode to: (1) HS or less, (2) Some college, (3) College, 
#           (4) Advanced degree, (5) NA (not available)
#Ego var
dyads_ntp_split[education == "B-Less Than HS Graduate" | education == "C-HS Graduate or Equivalent", ed_cat:=1][education == "D-Some College" | education == "E-Technical School" | education == "F-2-Year College Degree", ed_cat:=2][education == "G-Bachelor's Level Degree" | education == "H-Some Graduate School", ed_cat:=3][education == "I-Master's Level Degree" | education == "J-Doctorate (Academic)" | education == "K-Doctorate (Professional)" | education == "L-Post-Doctorate", ed_cat:=4]
dyads_ntp_split[is.na(ed_cat), ed_cat:=5]
#Alter var
dyads_ntp_split[education_d == "B-Less Than HS Graduate" | education_d == "C-HS Graduate or Equivalent", ed_cat_d:=1][education_d == "D-Some College" | education_d == "E-Technical School" | education_d == "F-2-Year College Degree", ed_cat_d:=2][education_d == "G-Bachelor's Level Degree" | education_d == "H-Some Graduate School", ed_cat_d:=3][education_d == "I-Master's Level Degree" | education_d == "J-Doctorate (Academic)" | education_d == "K-Doctorate (Professional)" | education_d == "L-Post-Doctorate", ed_cat_d:=4]
dyads_ntp_split[is.na(ed_cat_d), ed_cat_d:=5]

#e. recode: study year
#this is somewhat redundant of study months, but useful for easy data description
dyads_ntp_split[study_month>0 & study_month <= 12, study_year:=1][study_month > 12 & study_month <= 24, study_year:=2]

#f. recode: race 
#due to small cell sizes for both ego and alter vars  
# We need to combine "unknown" ("U") with "other" ("O")
dyads_ntp_split[race_cat == "A", race_cat5:="A"][race_cat == "B", race_cat5:="B"][race_cat == "H", race_cat5:="H"][race_cat == "O", race_cat5:="O"][race_cat == "U", race_cat5:="O"][race_cat == "W", race_cat5:="W"]
dyads_ntp_split[race_cat_d == "A", race_cat5_d:="A"][race_cat_d == "B", race_cat5_d:="B"][race_cat_d == "H", race_cat5_d:="H"][race_cat_d == "O", race_cat5_d:="O"][race_cat_d == "U", race_cat5_d:="O"][race_cat_d == "W", race_cat5_d:="W"]

#g. recode: job category
#recode observations with "no EEO-1 reporting" job category to "NA" because of small cells
# For egos in 2016 it's n=2, 2017 n=2, 2018 n=2, 2019 n=1
dyads_ntp_split[job_cat == "No EEO-1 Reporting", job_cat:=NA]
dyads_ntp_split[job_cat_d == "No EEO-1 Reporting", job_cat:=NA]

#h. recode: transform cw_grp from UTF-8 encoding to latin for "entr?e"
dyads_ntp_split$cw_grp<-iconv(dyads_ntp_split$cw_grp, "latin1", "UTF-8")

#i. recode: create new var to denote item type (food or beverage)
dyads_ntp_split[cw_grp != "beverage", item_type:="food"][cw_grp == "beverage", item_type:="bev"]

## Diagnostics 
#solo observations (row-level)
dyads_ntp_split <- dyads_ntp_split %>%
  mutate(solo_obs = ifelse(is.na(id_d) & !is.na(id), 1, 0))
dyads_ntp_split[, .N, by=solo_obs] #n=127072 solo observations

sub_solo_obs<- subset(dyads_ntp_split, select=c("id","id_d", "mdy","time_n",
                                                "item_type","cw_grp","RYG", "kcal", 
                                                "solo_obs"))

#solo occasions 
# In the case that a purchase contains multiple types of items (bevs and foods),
# There will be multiple observations per occasion. We need to calculate how 
# many unique purchasing occasions there are where a person purchases
# by themselves. 
sub_solo_occas <- (unique(sub_solo_obs, by = c("id","mdy","time_n")))
sub_solo_occas[, .N, by=solo_obs] #n=x solo occassions 
sub_solo_occas$solo_obs<-as.factor(sub_solo_occas$solo_obs) #change for grouping
levels(sub_solo_occas$solo_obs) <- c("dyadic", "solo") #label the levels
sub_solo_occas[, .N, by=solo_obs] #n=x solo observations

#plot solo vs. dyadic distribution over the course of the day
ggplot(sub_solo_occas, aes(time_n, fill=solo_obs))+  #plots curve, w/# of seconds as unit of measure
  geom_density(alpha=0.3)+
  theme_classic()+
  scale_x_continuous("Time of ego's purchase",
                     # breaks = c("1960-01-01 00:00:00", "1960-01-01 06:00:00", 
                     #            "1960-01-01 12:00:00", "1960-01-01 18:00:00", 
                     #            "1960-01-01 11:59:00"),
                     labels=c("12:00a", "6:00a", "12:00p",
                              "6:00p", "11:59p"))+
  scale_y_continuous("Scaled density")+
  scale_fill_discrete(name = "obs type")+
  labs(title="2019")

setwd("/work/pi_mpachucki_umass_edu/food_projects/food_simulation_r01/plots")
ggsave("2019_solovsdyadic_dist.pdf", width = 5, height = 4)

setwd("/work/pi_mpachucki_umass_edu/food_projects/food_simulation_r01/data analytic")
save.image("dyads_ntp_core_2019.Rdata")

#Also save RDS (only an R object is saved) b/c we can combine all RDS in one workspace
saveRDS(dyads_ntp_split, file = "dyads_ntp_2019.RDS")
rm(list = ls())



############## 3. DEVELOP MERGED DATA #############
# This is the full 50-million observation dyad dataset 
# that merges data across 2016-2020 (with 2 weeks of 2015 included). 
# We use this dataset to (a) create the updated probability measure (section 5.2) & 
# (b) merge the tie probability measure back to this 50-million dataset. 
# This 50-million dataset will be truncated down to different sizes depending on whether the resulting 
# datasets are used for calculating Y or key Xs. 
# The former is dyads_1511_1912u_upd_dvs, 
# the latter is dyads_1511_1912u_upd_exp.

gc() #keep space tidy and memory clear

### 2015
dyads_ntp_2015 <- readRDS("dyads_ntp_2015.RDS")
dyads_ntp_2015$Month_Yr <- format(as.Date(dyads_ntp_2015$mdy), "%Y-%m")
dyads_1511_1512p <- setDT(dyads_ntp_2015)
range(dyads_1511_1512p$Month_Yr) ### check if we get 01/2016-12/2016
keycols2 = c("id","mdy","time_n", "RYG", "cw_grp","kcal","price","id_d")  #key on ego and alter's purchases (alter should be included)
dyads_1511_1512u <- unique(dyads_1511_1512p, by = keycols2) #checked, and still preserves solo food purchases (id=some n, id_d=NA)
dyads_1511_1512u[, .N] #n=2432044 solo observations
rm(dyads_ntp_2015, dyads_1511_1512p) #drop object to save space
gc() #garbage collection, clear out memory

### 2016
dyads_ntp_2016 <- readRDS("dyads_ntp_2016.RDS")
dyads_ntp_2016$Month_Yr <- format(as.Date(dyads_ntp_2016$mdy), "%Y-%m")
dyads_1601_1612p <- setDT(dyads_ntp_2016)
range(dyads_1601_1612p$Month_Yr) ### check if we get 01/2016-12/2016
keycols2 = c("id","mdy","time_n", "RYG", "cw_grp","kcal","price","id_d")  #key on ego and alter's purchases (alter should be included)
dyads_1601_1612u <- unique(dyads_1601_1612p, by = keycols2)
dyads_1601_1612u[, .N] #n=15788114 solo observations
rm(dyads_ntp_2016,dyads_1601_1612p) #drop object to save space
gc() #garbage collection, clear out memory

### 2017
dyads_ntp_2017 <- readRDS("dyads_ntp_2017.RDS")
dyads_ntp_2017$Month_Yr <- format(as.Date(dyads_ntp_2017$mdy), "%Y-%m")
dyads_1701_1712p <- setDT(dyads_ntp_2017)
range(dyads_1701_1712p$Month_Yr) ### check if we get 01/2017-12/2017
keycols2 = c("id","mdy","time_n", "RYG", "cw_grp","kcal","price","id_d")  #key on ego and alter's purchases (alter should be included)
dyads_1701_1712u <- unique(dyads_1701_1712p, by = keycols2)
dyads_1701_1712u[, .N] #n=15013123 solo observations
rm(dyads_ntp_2017,dyads_1701_1712p)  #drop object to save space
gc() #garbage collection, clear out memory

### 2018
dyads_ntp_2018 <- readRDS("dyads_ntp_2018.RDS")
dyads_ntp_2018$Month_Yr <- format(as.Date(dyads_ntp_2018$mdy), "%Y-%m")
dyads_1801_1812p <- setDT(dyads_ntp_2018)
range(dyads_1801_1812p$Month_Yr) ### check if we get 01/2018-12/2018
keycols2 = c("id","mdy","time_n", "RYG", "cw_grp","kcal","price","id_d")  #key on ego and alter's purchases (alter should be included)
dyads_1801_1812u <- unique(dyads_1801_1812p, by = keycols2)
dyads_1801_1812u[, .N] #n=13416026 solo observations
rm(dyads_ntp_2018,dyads_1801_1812p) #drop object to save space
gc() #garbage collection, clear out memory

### 2019
dyads_ntp_2019 <- readRDS("dyads_ntp_2019.RDS")
dyads_ntp_2019$Month_Yr <- format(as.Date(dyads_ntp_2019$mdy), "%Y-%m")
dyads_1901_1912p <- setDT(dyads_ntp_2019)
range(dyads_1901_1912p$Month_Yr) ### check if we get 01/2019-12/2019
keycols2 = c("id","mdy","time_n", "RYG", "cw_grp","kcal","price","id_d")  #key on ego and alter's purchases (alter should be included)
dyads_1901_1912u <- unique(dyads_1901_1912p, by = keycols2)
dyads_1901_1912u[, .N] #n=13408133 solo observations
rm(dyads_ntp_2019,dyads_1901_1912p) #drop object to save space
rm(keycols2)
gc() #garbage collection, clear out memory

## Merge 2015-2019 data
dyads_ntp_m <- rbind(dyads_1511_1512u,dyads_1601_1612u,
                     dyads_1701_1712u,dyads_1801_1812u,
                     dyads_1901_1912u)
dyads_ntp_m[, .N] #n=60057440  observations
dyads_ntp_m[, .N, by=solo_obs] #n=554222 solo observations


#save space! no longer needed
rm(dyads_1511_1512u,dyads_1601_1612u,dyads_1701_1712u,
   dyads_1801_1812u,dyads_1901_1912u)
gc()

#incremental save
saveRDS(dyads_ntp_m, file = "dyads_ntp_m.RDS")
#note: this object does NOT have any tie probability measure in it (yet)

############## 4. CREATE TIE PROBABLILITY USING MERGED DATA #############
dyads_ntp_m <- readRDS("dyads_ntp_m.RDS")

## also, since we keep ego's multiple purchase at the same time, 
## we have NOT to double count the frequencies of ego-alter pair due to this data format issue. 
## we thus need to unique their co-purchasing by ignoring the items ego purchased
dyads_1511_1912u <- (unique(dyads_ntp_m, by = c("id","mdy","time_n","id_d")))
dyads_1511_1912u[, .N] #n=31661727  observations
#note: this reduces the 60-million observation datatable down to n=31million
rm(dyads_ntp_m)

#incremental save
saveRDS(dyads_1511_1912u, file = "dyads_1511_1912u.RDS")

## create seg and dup variables
# Note: these model coefficients were derived April 11, 2019 by Doug's analysis for NHB 2021 paper.
# Not needed for analyses that omit demographics
dyads_1511_1912u <- dyads_1511_1912u[race_cat == race_cat_d, race_match_coeff := 0.013679717][race_cat != race_cat_d, race_match_coeff := 0][race_cat == 6 & race_cat_d == 6, race_match_coeff := NA]
dyads_1511_1912u <- dyads_1511_1912u[deptid == deptid_d, dept_match_coeff := 3.632209848][deptid != deptid_d, dept_match_coeff := 0][is.na(deptid) & is.na(deptid_d), dept_match_coeff := NA]
dyads_1511_1912u <- dyads_1511_1912u[job_cat == job_cat_d, job_cat_match_coeff := 0.804071954][job_cat != job_cat_d, job_cat_match_coeff := 0][job_cat == 6 & job_cat_d == 6, job_cat_match_coeff := NA]
dyads_1511_1912u <- dyads_1511_1912u[sex == sex_d, gender_match_coeff := 0.424263288][sex != sex_d, gender_match_coeff := 0][sex == 3 & sex_d == 3, gender_match_coeff := NA]
dyads_1511_1912u <- dyads_1511_1912u[abs(age-age_d)>=0 & abs(age-age_d)<5, agediffcat5_coeff := 0][abs(age-age_d)>=5 & abs(age-age_d)<10, agediffcat5_coeff := 0.096430176][abs(age-age_d)>=10 & abs(age-age_d)<15, agediffcat5_coeff := -0.547884339][abs(age-age_d)>=15 & abs(age-age_d)<20, agediffcat5_coeff := -0.53005367][abs(age-age_d)>=20, agediffcat5_coeff := -0.775077442][is.na(age) & is.na(age_d), agediffcat5_coeff := NA]

# #here, we create new 6-month lookback blocks for moving windows (to account for all of 2016)
# dyads_1511_1912u <- dyads_1511_1912u[, seg_16_02 := 0][mdy >=  as.Date("2015-09-01") & mdy < as.Date("2016-03-01"), seg_16_02 := 1][]
# dyads_1511_1912u <- dyads_1511_1912u[, seg_16_01 := 0][mdy >=  as.Date("2015-08-01") & mdy < as.Date("2016-02-01"), seg_16_01 := 1][]
# dyads_1511_1912u <- dyads_1511_1912u[, seg_15_12 := 0][mdy >=  as.Date("2015-07-01") & mdy < as.Date("2016-01-01"), seg_15_12 := 1][]
# #identify duplicate dyads in terms of occurrence in monthly networks (to account for all of 2016)
# dyads_1511_1912u <- dyads_1511_1912u[, dup_16_09 :=0][seg_16_09 == 1, dup_16_09 := .N, by=list(id, id_d, seg_16_09)][]
# dyads_1511_1912u <- dyads_1511_1912u[, dup_16_08 :=0][seg_16_08 == 1, dup_16_08 := .N, by=list(id, id_d, seg_16_08)][]
# dyads_1511_1912u <- dyads_1511_1912u[, dup_16_07 :=0][seg_16_07 == 1, dup_16_07 := .N, by=list(id, id_d, seg_16_07)][]

#here, we create 6-month lookback blocks for moving windows
dyads_1511_1912u <- dyads_1511_1912u[, seg_16_09 := 0][mdy >=  as.Date("2016-04-01") & mdy < as.Date("2016-10-01"), seg_16_09 := 1][]
dyads_1511_1912u <- dyads_1511_1912u[, seg_16_08 := 0][mdy >=  as.Date("2016-03-01") & mdy < as.Date("2016-09-01"), seg_16_08 := 1][]
dyads_1511_1912u <- dyads_1511_1912u[, seg_16_07 := 0][mdy >=  as.Date("2016-02-01") & mdy < as.Date("2016-08-01"), seg_16_07 := 1][]
dyads_1511_1912u <- dyads_1511_1912u[, seg_16_06 := 0][mdy >=  as.Date("2016-01-01") & mdy < as.Date("2016-07-01"), seg_16_06 := 1][]
dyads_1511_1912u <- dyads_1511_1912u[, seg_16_05 := 0][mdy >=  as.Date("2015-12-01") & mdy < as.Date("2016-06-01"), seg_16_05 := 1][]
dyads_1511_1912u <- dyads_1511_1912u[, seg_16_04 := 0][mdy >=  as.Date("2015-11-01") & mdy < as.Date("2016-05-01"), seg_16_04 := 1][]
dyads_1511_1912u <- dyads_1511_1912u[, seg_16_03 := 0][mdy >=  as.Date("2015-10-01") & mdy < as.Date("2016-04-01"), seg_16_03 := 1][]

# identify duplicate dyads in terms of occurrence in monthly networks
dyads_1511_1912u <- dyads_1511_1912u[, dup_16_09 :=0][seg_16_09 == 1, dup_16_09 := .N, by=list(id, id_d, seg_16_09)][]
dyads_1511_1912u <- dyads_1511_1912u[, dup_16_08 :=0][seg_16_08 == 1, dup_16_08 := .N, by=list(id, id_d, seg_16_08)][]
dyads_1511_1912u <- dyads_1511_1912u[, dup_16_07 :=0][seg_16_07 == 1, dup_16_07 := .N, by=list(id, id_d, seg_16_07)][]
dyads_1511_1912u <- dyads_1511_1912u[, dup_16_06 :=0][seg_16_06 == 1, dup_16_06 := .N, by=list(id, id_d, seg_16_06)][]
dyads_1511_1912u <- dyads_1511_1912u[, dup_16_05 :=0][seg_16_05 == 1, dup_16_05 := .N, by=list(id, id_d, seg_16_05)][]
dyads_1511_1912u <- dyads_1511_1912u[, dup_16_04 :=0][seg_16_04 == 1, dup_16_04 := .N, by=list(id, id_d, seg_16_04)][]
dyads_1511_1912u <- dyads_1511_1912u[, dup_16_03 :=0][seg_16_03 == 1, dup_16_03 := .N, by=list(id, id_d, seg_16_03)][]

dyads_1511_1912u <- dyads_1511_1912u[, seg_17_03 := 0][mdy >=  as.Date("2016-10-01") & mdy < as.Date("2017-04-01"), seg_17_03 := 1][]
dyads_1511_1912u <- dyads_1511_1912u[, seg_17_02 := 0][mdy >=  as.Date("2016-09-01") & mdy < as.Date("2017-03-01"), seg_17_02 := 1][]
dyads_1511_1912u <- dyads_1511_1912u[, seg_17_01 := 0][mdy >=  as.Date("2016-08-01") & mdy < as.Date("2017-02-01"), seg_17_01 := 1][]
dyads_1511_1912u <- dyads_1511_1912u[, seg_16_12 := 0][mdy >=  as.Date("2016-07-01") & mdy < as.Date("2017-01-01"), seg_16_12 := 1][]
dyads_1511_1912u <- dyads_1511_1912u[, seg_16_11 := 0][mdy >=  as.Date("2016-06-01") & mdy < as.Date("2016-12-01"), seg_16_11 := 1][]
dyads_1511_1912u <- dyads_1511_1912u[, seg_16_10 := 0][mdy >=  as.Date("2016-05-01") & mdy < as.Date("2016-11-01"), seg_16_10 := 1][]

dyads_1511_1912u <- dyads_1511_1912u[, dup_17_03 :=0][seg_17_03 == 1, dup_17_03 := .N, by=list(id, id_d, seg_17_03)][]
dyads_1511_1912u <- dyads_1511_1912u[, dup_17_02 :=0][seg_17_02 == 1, dup_17_02 := .N, by=list(id, id_d, seg_17_02)][]
dyads_1511_1912u <- dyads_1511_1912u[, dup_17_01 :=0][seg_17_01 == 1, dup_17_01 := .N, by=list(id, id_d, seg_17_01)][]
dyads_1511_1912u <- dyads_1511_1912u[, dup_16_12 :=0][seg_16_12 == 1, dup_16_12 := .N, by=list(id, id_d, seg_16_12)][]
dyads_1511_1912u <- dyads_1511_1912u[, dup_16_11 :=0][seg_16_11 == 1, dup_16_11 := .N, by=list(id, id_d, seg_16_11)][]
dyads_1511_1912u <- dyads_1511_1912u[, dup_16_10 :=0][seg_16_10 == 1, dup_16_10 := .N, by=list(id, id_d, seg_16_10)][]

dyads_1511_1912u <- dyads_1511_1912u[, seg_17_09 := 0][mdy >=  as.Date("2017-04-01") & mdy < as.Date("2017-10-01"), seg_17_09 := 1][]
dyads_1511_1912u <- dyads_1511_1912u[, seg_17_08 := 0][mdy >=  as.Date("2017-03-01") & mdy < as.Date("2017-09-01"), seg_17_08 := 1][]
dyads_1511_1912u <- dyads_1511_1912u[, seg_17_07 := 0][mdy >=  as.Date("2017-02-01") & mdy < as.Date("2017-08-01"), seg_17_07 := 1][]
dyads_1511_1912u <- dyads_1511_1912u[, seg_17_06 := 0][mdy >=  as.Date("2017-01-01") & mdy < as.Date("2017-07-01"), seg_17_06 := 1][]
dyads_1511_1912u <- dyads_1511_1912u[, seg_17_05 := 0][mdy >=  as.Date("2016-12-01") & mdy < as.Date("2017-06-01"), seg_17_05 := 1][]
dyads_1511_1912u <- dyads_1511_1912u[, seg_17_04 := 0][mdy >=  as.Date("2016-11-01") & mdy < as.Date("2017-05-01"), seg_17_04 := 1][]

dyads_1511_1912u <- dyads_1511_1912u[, dup_17_09 :=0][seg_17_09 == 1, dup_17_09 := .N, by=list(id, id_d, seg_17_09)][]
dyads_1511_1912u <- dyads_1511_1912u[, dup_17_08 :=0][seg_17_08 == 1, dup_17_08 := .N, by=list(id, id_d, seg_17_08)][]
dyads_1511_1912u <- dyads_1511_1912u[, dup_17_07 :=0][seg_17_07 == 1, dup_17_07 := .N, by=list(id, id_d, seg_17_07)][]
dyads_1511_1912u <- dyads_1511_1912u[, dup_17_06 :=0][seg_17_06 == 1, dup_17_06 := .N, by=list(id, id_d, seg_17_06)][]
dyads_1511_1912u <- dyads_1511_1912u[, dup_17_05 :=0][seg_17_05 == 1, dup_17_05 := .N, by=list(id, id_d, seg_17_05)][]
dyads_1511_1912u <- dyads_1511_1912u[, dup_17_04 :=0][seg_17_04 == 1, dup_17_04 := .N, by=list(id, id_d, seg_17_04)][]

dyads_1511_1912u <- dyads_1511_1912u[, seg_18_03 := 0][mdy >=  as.Date("2017-10-01") & mdy < as.Date("2018-04-01"), seg_18_03 := 1][]
dyads_1511_1912u <- dyads_1511_1912u[, seg_18_02 := 0][mdy >=  as.Date("2017-09-01") & mdy < as.Date("2018-03-01"), seg_18_02 := 1][]
dyads_1511_1912u <- dyads_1511_1912u[, seg_18_01 := 0][mdy >=  as.Date("2017-08-01") & mdy < as.Date("2018-02-01"), seg_18_01 := 1][]
dyads_1511_1912u <- dyads_1511_1912u[, seg_17_12 := 0][mdy >=  as.Date("2017-07-01") & mdy < as.Date("2018-01-01"), seg_17_12 := 1][]
dyads_1511_1912u <- dyads_1511_1912u[, seg_17_11 := 0][mdy >=  as.Date("2017-06-01") & mdy < as.Date("2017-12-01"), seg_17_11 := 1][]
dyads_1511_1912u <- dyads_1511_1912u[, seg_17_10 := 0][mdy >=  as.Date("2017-05-01") & mdy < as.Date("2017-11-01"), seg_17_10 := 1][]

dyads_1511_1912u <- dyads_1511_1912u[, dup_18_03 :=0][seg_18_03 == 1, dup_18_03 := .N, by=list(id, id_d, seg_18_03)][]
dyads_1511_1912u <- dyads_1511_1912u[, dup_18_02 :=0][seg_18_02 == 1, dup_18_02 := .N, by=list(id, id_d, seg_18_02)][]
dyads_1511_1912u <- dyads_1511_1912u[, dup_18_01 :=0][seg_18_01 == 1, dup_18_01 := .N, by=list(id, id_d, seg_18_01)][]
dyads_1511_1912u <- dyads_1511_1912u[, dup_17_12 :=0][seg_17_12 == 1, dup_17_12 := .N, by=list(id, id_d, seg_17_12)][]
dyads_1511_1912u <- dyads_1511_1912u[, dup_17_11 :=0][seg_17_11 == 1, dup_17_11 := .N, by=list(id, id_d, seg_17_11)][]
dyads_1511_1912u <- dyads_1511_1912u[, dup_17_10 :=0][seg_17_10 == 1, dup_17_10 := .N, by=list(id, id_d, seg_17_10)][]

dyads_1511_1912u <- dyads_1511_1912u[, seg_18_09 := 0][mdy >=  as.Date("2018-04-01") & mdy < as.Date("2018-10-01"), seg_18_09 := 1][]
dyads_1511_1912u <- dyads_1511_1912u[, seg_18_08 := 0][mdy >=  as.Date("2018-03-01") & mdy < as.Date("2018-09-01"), seg_18_08 := 1][]
dyads_1511_1912u <- dyads_1511_1912u[, seg_18_07 := 0][mdy >=  as.Date("2018-02-01") & mdy < as.Date("2018-08-01"), seg_18_07 := 1][]
dyads_1511_1912u <- dyads_1511_1912u[, seg_18_06 := 0][mdy >=  as.Date("2018-01-01") & mdy < as.Date("2018-07-01"), seg_18_06 := 1][]
dyads_1511_1912u <- dyads_1511_1912u[, seg_18_05 := 0][mdy >=  as.Date("2017-12-01") & mdy < as.Date("2018-06-01"), seg_18_05 := 1][]
dyads_1511_1912u <- dyads_1511_1912u[, seg_18_04 := 0][mdy >=  as.Date("2017-11-01") & mdy < as.Date("2018-05-01"), seg_18_04 := 1][]

dyads_1511_1912u <- dyads_1511_1912u[, dup_18_09 :=0][seg_18_09 == 1, dup_18_09 := .N, by=list(id, id_d, seg_18_09)][]
dyads_1511_1912u <- dyads_1511_1912u[, dup_18_08 :=0][seg_18_08 == 1, dup_18_08 := .N, by=list(id, id_d, seg_18_08)][]
dyads_1511_1912u <- dyads_1511_1912u[, dup_18_07 :=0][seg_18_07 == 1, dup_18_07 := .N, by=list(id, id_d, seg_18_07)][]
dyads_1511_1912u <- dyads_1511_1912u[, dup_18_06 :=0][seg_18_06 == 1, dup_18_06 := .N, by=list(id, id_d, seg_18_06)][]
dyads_1511_1912u <- dyads_1511_1912u[, dup_18_05 :=0][seg_18_05 == 1, dup_18_05 := .N, by=list(id, id_d, seg_18_05)][]
dyads_1511_1912u <- dyads_1511_1912u[, dup_18_04 :=0][seg_18_04 == 1, dup_18_04 := .N, by=list(id, id_d, seg_18_04)][]

dyads_1511_1912u <- dyads_1511_1912u[, seg_19_03 := 0][mdy >=  as.Date("2018-10-01") & mdy < as.Date("2019-04-01"), seg_19_03 := 1][]
dyads_1511_1912u <- dyads_1511_1912u[, seg_19_02 := 0][mdy >=  as.Date("2018-09-01") & mdy < as.Date("2019-03-01"), seg_19_02 := 1][]
dyads_1511_1912u <- dyads_1511_1912u[, seg_19_01 := 0][mdy >=  as.Date("2018-08-01") & mdy < as.Date("2019-02-01"), seg_19_01 := 1][]
dyads_1511_1912u <- dyads_1511_1912u[, seg_18_12 := 0][mdy >=  as.Date("2018-07-01") & mdy < as.Date("2019-01-01"), seg_18_12 := 1][]
dyads_1511_1912u <- dyads_1511_1912u[, seg_18_11 := 0][mdy >=  as.Date("2018-06-01") & mdy < as.Date("2018-12-01"), seg_18_11 := 1][]
dyads_1511_1912u <- dyads_1511_1912u[, seg_18_10 := 0][mdy >=  as.Date("2018-05-01") & mdy < as.Date("2018-11-01"), seg_18_10 := 1][]

dyads_1511_1912u <- dyads_1511_1912u[, dup_19_03 :=0][seg_19_03 == 1, dup_19_03 := .N, by=list(id, id_d, seg_19_03)][]
dyads_1511_1912u <- dyads_1511_1912u[, dup_19_02 :=0][seg_19_02 == 1, dup_19_02 := .N, by=list(id, id_d, seg_19_02)][]
dyads_1511_1912u <- dyads_1511_1912u[, dup_19_01 :=0][seg_19_01 == 1, dup_19_01 := .N, by=list(id, id_d, seg_19_01)][]
dyads_1511_1912u <- dyads_1511_1912u[, dup_18_12 :=0][seg_18_12 == 1, dup_18_12 := .N, by=list(id, id_d, seg_18_12)][]
dyads_1511_1912u <- dyads_1511_1912u[, dup_18_11 :=0][seg_18_11 == 1, dup_18_11 := .N, by=list(id, id_d, seg_18_11)][]
dyads_1511_1912u <- dyads_1511_1912u[, dup_18_10 :=0][seg_18_10 == 1, dup_18_10 := .N, by=list(id, id_d, seg_18_10)][]

dyads_1511_1912u <- dyads_1511_1912u[, seg_19_09 := 0][mdy >=  as.Date("2019-04-01") & mdy < as.Date("2019-10-01"), seg_19_09 := 1][]
dyads_1511_1912u <- dyads_1511_1912u[, seg_19_08 := 0][mdy >=  as.Date("2019-03-01") & mdy < as.Date("2019-09-01"), seg_19_08 := 1][]
dyads_1511_1912u <- dyads_1511_1912u[, seg_19_07 := 0][mdy >=  as.Date("2019-02-01") & mdy < as.Date("2019-08-01"), seg_19_07 := 1][]
dyads_1511_1912u <- dyads_1511_1912u[, seg_19_06 := 0][mdy >=  as.Date("2019-01-01") & mdy < as.Date("2019-07-01"), seg_19_06 := 1][]
dyads_1511_1912u <- dyads_1511_1912u[, seg_19_05 := 0][mdy >=  as.Date("2018-12-01") & mdy < as.Date("2019-06-01"), seg_19_05 := 1][]
dyads_1511_1912u <- dyads_1511_1912u[, seg_19_04 := 0][mdy >=  as.Date("2018-11-01") & mdy < as.Date("2019-05-01"), seg_19_04 := 1][]

dyads_1511_1912u <- dyads_1511_1912u[, dup_19_09 :=0][seg_19_09 == 1, dup_19_09 := .N, by=list(id, id_d, seg_19_09)][]
dyads_1511_1912u <- dyads_1511_1912u[, dup_19_08 :=0][seg_19_08 == 1, dup_19_08 := .N, by=list(id, id_d, seg_19_08)][]
dyads_1511_1912u <- dyads_1511_1912u[, dup_19_07 :=0][seg_19_07 == 1, dup_19_07 := .N, by=list(id, id_d, seg_19_07)][]
dyads_1511_1912u <- dyads_1511_1912u[, dup_19_06 :=0][seg_19_06 == 1, dup_19_06 := .N, by=list(id, id_d, seg_19_06)][]
dyads_1511_1912u <- dyads_1511_1912u[, dup_19_05 :=0][seg_19_05 == 1, dup_19_05 := .N, by=list(id, id_d, seg_19_05)][]
dyads_1511_1912u <- dyads_1511_1912u[, dup_19_04 :=0][seg_19_04 == 1, dup_19_04 := .N, by=list(id, id_d, seg_19_04)][]

dyads_1511_1912u <- dyads_1511_1912u[, seg_20_03 := 0][mdy >=  as.Date("2019-10-01") & mdy < as.Date("2020-04-01"), seg_20_03 := 1][]
dyads_1511_1912u <- dyads_1511_1912u[, seg_20_02 := 0][mdy >=  as.Date("2019-09-01") & mdy < as.Date("2020-03-01"), seg_20_02 := 1][]
dyads_1511_1912u <- dyads_1511_1912u[, seg_20_01 := 0][mdy >=  as.Date("2019-08-01") & mdy < as.Date("2020-02-01"), seg_20_01 := 1][]
dyads_1511_1912u <- dyads_1511_1912u[, seg_19_12 := 0][mdy >=  as.Date("2019-07-01") & mdy < as.Date("2020-01-01"), seg_19_12 := 1][]
dyads_1511_1912u <- dyads_1511_1912u[, seg_19_11 := 0][mdy >=  as.Date("2019-06-01") & mdy < as.Date("2019-12-01"), seg_19_11 := 1][]
dyads_1511_1912u <- dyads_1511_1912u[, seg_19_10 := 0][mdy >=  as.Date("2019-05-01") & mdy < as.Date("2019-11-01"), seg_19_10 := 1][]

dyads_1511_1912u <- dyads_1511_1912u[, dup_20_03 :=0][seg_20_03 == 1, dup_20_03 := .N, by=list(id, id_d, seg_20_03)][]
dyads_1511_1912u <- dyads_1511_1912u[, dup_20_02 :=0][seg_20_02 == 1, dup_20_02 := .N, by=list(id, id_d, seg_20_02)][]
dyads_1511_1912u <- dyads_1511_1912u[, dup_20_01 :=0][seg_20_01 == 1, dup_20_01 := .N, by=list(id, id_d, seg_20_01)][]
dyads_1511_1912u <- dyads_1511_1912u[, dup_19_12 :=0][seg_19_12 == 1, dup_19_12 := .N, by=list(id, id_d, seg_19_12)][]
dyads_1511_1912u <- dyads_1511_1912u[, dup_19_11 :=0][seg_19_11 == 1, dup_19_11 := .N, by=list(id, id_d, seg_19_11)][]
dyads_1511_1912u <- dyads_1511_1912u[, dup_19_10 :=0][seg_19_10 == 1, dup_19_10 := .N, by=list(id, id_d, seg_19_10)][]

saveRDS(dyads_1511_1912u, file = "dyads_1511_1912u.RDS")

## create unique ego-alter pairs in a given month 

dyads_16_04 <- unique(dyads_1511_1912u[dup_16_04 != 0, !c("seg_16_09", 
                                                          "seg_16_08", "seg_16_07", "seg_16_06",
                                                          "seg_16_05", "seg_16_04", "seg_16_03",
                                                          "dup_16_09", "dup_16_08", "dup_16_07",
                                                          "dup_16_06", "dup_16_05", "dup_16_03")], #note here no dup_16_04
                      by = c("id", "id_d", "dup_16_04","Month_Yr"))

dyads_16_05 <- unique(dyads_1511_1912u[dup_16_05 != 0, !c("seg_16_09", 
                                                          "seg_16_08", "seg_16_07", "seg_16_06",
                                                          "seg_16_05", "seg_16_04", "seg_16_03",
                                                          "dup_16_09", "dup_16_08", "dup_16_07",
                                                          "dup_16_06", "dup_16_04", "dup_16_03")], #note here no dup_16_05
                      by = c("id", "id_d", "dup_16_05","Month_Yr"))

dyads_16_06 <- unique(dyads_1511_1912u[dup_16_06 != 0, !c("seg_16_09", 
                                                          "seg_16_08", "seg_16_07", "seg_16_06",
                                                          "seg_16_05", "seg_16_04", "seg_16_03",
                                                          "dup_16_09", "dup_16_08", "dup_16_07",
                                                          "dup_16_05", "dup_16_04", "dup_16_03")], #note here no dup_16_06
                      by = c("id", "id_d", "dup_16_06","Month_Yr"))

dyads_16_07 <- unique(dyads_1511_1912u[dup_16_07 != 0, !c("seg_16_09", 
                                                          "seg_16_08", "seg_16_07", "seg_16_06",
                                                          "seg_16_05", "seg_16_04", "seg_16_03",
                                                          "dup_16_09", "dup_16_08", "dup_16_06",
                                                          "dup_16_05", "dup_16_04", "dup_16_03")], #note here no dup_16_07
                      by = c("id", "id_d", "dup_16_07","Month_Yr"))

dyads_16_08 <- unique(dyads_1511_1912u[dup_16_08 != 0, !c("seg_16_09", 
                                                          "seg_16_08", "seg_16_07", "seg_16_06",
                                                          "seg_16_05", "seg_16_04", "seg_16_03",
                                                          "dup_16_09", "dup_16_07", "dup_16_06",
                                                          "dup_16_05", "dup_16_04", "dup_16_03")], #note here no dup_16_08
                      by = c("id", "id_d", "dup_16_08","Month_Yr"))

dyads_16_09 <- unique(dyads_1511_1912u[dup_16_09 != 0, !c("seg_16_09", 
                                                          "seg_16_08", "seg_16_07", "seg_16_06",
                                                          "seg_16_05", "seg_16_04", "seg_16_03",
                                                          "dup_16_08", "dup_16_07", "dup_16_06",
                                                          "dup_16_05", "dup_16_04", "dup_16_03")],  #note here no dup_16_09
                      by = c("id", "id_d", "dup_16_09","Month_Yr"))

## break up the loop
rm(dyads_1511_1912u)
save.image("dyads_1511_1912u_monthly_tie_prob_pretrial.Rdata")
gc()
dyads_1511_1912u <- readRDS("dyads_1511_1912u.RDS")
rm(dyads_16_04,dyads_16_05,dyads_16_06,dyads_16_07,dyads_16_08,dyads_16_09)
## end of break

dyads_16_10 <- unique(dyads_1511_1912u[dup_16_10 != 0, !c("seg_17_03", 
                                                          "seg_17_02", "seg_17_01", "seg_16_12",
                                                          "seg_16_11", "seg_16_10",
                                                          "dup_17_03", "dup_17_02", "dup_17_01", 
                                                          "dup_16_12", "dup_16_11")], #note here no dup_16_10
                      by = c("id", "id_d", "dup_16_10","Month_Yr"))

dyads_16_11 <- unique(dyads_1511_1912u[dup_16_11 != 0, !c("seg_17_03", 
                                                          "seg_17_02", "seg_17_01", "seg_16_12",
                                                          "seg_16_11", "seg_16_10",
                                                          "dup_17_03", "dup_17_02", "dup_17_01", 
                                                          "dup_16_12", "dup_16_10")], #note here no dup_16_11
                      by = c("id", "id_d", "dup_16_11","Month_Yr"))

## break up the loop
rm(dyads_1511_1912u)
save.image("dyads_1511_1912u_monthly_tie_prob_m1_m2.Rdata")
gc()
dyads_1511_1912u <- readRDS("dyads_1511_1912u.RDS")
rm(dyads_16_10,dyads_16_11)
## end of break

dyads_16_12 <- unique(dyads_1511_1912u[dup_16_12 != 0, !c("seg_17_03", 
                                                          "seg_17_02", "seg_17_01", "seg_16_12",
                                                          "seg_16_11", "seg_16_10",
                                                          "dup_17_03", "dup_17_02", "dup_17_01",  
                                                          "dup_16_11", "dup_16_10")], #note here no dup_16_12
                      by = c("id", "id_d", "dup_16_12","Month_Yr"))

dyads_17_01 <- unique(dyads_1511_1912u[dup_17_01 != 0, !c("seg_17_03", 
                                                          "seg_17_02", "seg_17_01", "seg_16_12",
                                                          "seg_16_11", "seg_16_10",
                                                          "dup_17_03", "dup_17_02", "dup_16_12",  
                                                          "dup_16_11", "dup_16_10")], #note here no dup_17_01
                      by = c("id", "id_d", "dup_17_01","Month_Yr"))

## break up the loop
rm(dyads_1511_1912u)
save.image("dyads_1511_1912u_monthly_tie_prob_m3_m4.Rdata")
gc()
dyads_1511_1912u <- readRDS("dyads_1511_1912u.RDS")
rm(dyads_16_12,dyads_17_01)
## end of break

dyads_17_02 <- unique(dyads_1511_1912u[dup_17_02 != 0, !c("seg_17_03", 
                                                          "seg_17_02", "seg_17_01", "seg_16_12",
                                                          "seg_16_11", "seg_16_10",
                                                          "dup_17_03", "dup_17_01", "dup_16_12",  
                                                          "dup_16_11", "dup_16_10")], #note here no dup_17_02
                      by = c("id", "id_d", "dup_17_02","Month_Yr"))

dyads_17_03 <- unique(dyads_1511_1912u[dup_17_03 != 0, !c("seg_17_03", 
                                                          "seg_17_02", "seg_17_01", "seg_16_12",
                                                          "seg_16_11", "seg_16_10",
                                                          "dup_17_02", "dup_17_01", "dup_16_12",  
                                                          "dup_16_11", "dup_16_10")], #note here no dup_17_03
                      by = c("id", "id_d", "dup_17_03","Month_Yr"))

## break up the loop
rm(dyads_1511_1912u)
save.image("dyads_1511_1912u_monthly_tie_prob_m5_m6.Rdata")
dyads_1511_1912u <- readRDS("dyads_1511_1912u.RDS")
rm(dyads_17_02,dyads_17_03)
## end of break

dyads_17_04 <- unique(dyads_1511_1912u[dup_17_04 != 0, !c("seg_17_09", 
                                                          "seg_17_08", "seg_17_07", "seg_17_06",
                                                          "seg_17_05", "seg_17_04",
                                                          "dup_17_09", "dup_17_08", "dup_17_07",
                                                          "dup_17_06", "dup_17_05")], #note here no dup_17_04
                      by = c("id", "id_d", "dup_17_04","Month_Yr"))

dyads_17_05 <- unique(dyads_1511_1912u[dup_17_05 != 0, !c("seg_17_09", 
                                                          "seg_17_08", "seg_17_07", "seg_17_06",
                                                          "seg_17_05", "seg_17_04",
                                                          "dup_17_09", "dup_17_08", "dup_17_07",
                                                          "dup_17_06", "dup_17_04")], #note here no dup_17_05
                      by = c("id", "id_d", "dup_17_05","Month_Yr"))

## break up the loop
rm(dyads_1511_1912u)
save.image("dyads_1511_1912u_monthly_tie_prob_m7_m8.Rdata")
gc()
dyads_1511_1912u <- readRDS("dyads_1511_1912u.RDS")
rm(dyads_17_04,dyads_17_05)
## end of break

dyads_17_06 <- unique(dyads_1511_1912u[dup_17_06 != 0, !c("seg_17_09", 
                                                          "seg_17_08", "seg_17_07", "seg_17_06",
                                                          "seg_17_05", "seg_17_04",
                                                          "dup_17_09", "dup_17_08", "dup_17_07",
                                                          "dup_17_05", "dup_17_04")], #note here no dup_17_06
                      by = c("id", "id_d", "dup_17_06","Month_Yr"))

dyads_17_07 <- unique(dyads_1511_1912u[dup_17_07 != 0, !c("seg_17_09", 
                                                          "seg_17_08", "seg_17_07", "seg_17_06",
                                                          "seg_17_05", "seg_17_04",
                                                          "dup_17_09", "dup_17_08", "dup_17_06",
                                                          "dup_17_05", "dup_17_04")], #note here no dup_17_07
                      by = c("id", "id_d", "dup_17_07","Month_Yr"))

## break up the loop
rm(dyads_1511_1912u)
save.image("dyads_1511_1912u_monthly_tie_prob_m9_m10.Rdata")
gc()
dyads_1511_1912u <- readRDS("dyads_1511_1912u.RDS")
rm(dyads_17_06,dyads_17_07)
## end of break

dyads_17_08 <- unique(dyads_1511_1912u[dup_17_08 != 0, !c("seg_17_09", 
                                                          "seg_17_08", "seg_17_07", "seg_17_06",
                                                          "seg_17_05", "seg_17_04",
                                                          "dup_17_09", "dup_17_07", "dup_17_06",
                                                          "dup_17_05", "dup_17_04")], #note here no dup_17_08
                      by = c("id", "id_d", "dup_17_08","Month_Yr"))

dyads_17_09 <- unique(dyads_1511_1912u[dup_17_09 != 0, !c("seg_17_09", 
                                                          "seg_17_08", "seg_17_07", "seg_17_06",
                                                          "seg_17_05", "seg_17_04", 
                                                          "dup_17_08", "dup_17_07", "dup_17_06",
                                                          "dup_17_05", "dup_17_04")],  #note here no dup_17_09
                      by = c("id", "id_d", "dup_17_09","Month_Yr"))

## break up the loop
rm(dyads_1511_1912u)
save.image("dyads_1511_1912u_monthly_tie_prob_m11_m12.Rdata")
gc()
dyads_1511_1912u <- readRDS("dyads_1511_1912u.RDS")
rm(dyads_17_08,dyads_17_09)
## end of break

dyads_17_10 <- unique(dyads_1511_1912u[dup_17_10 != 0, !c("seg_18_03", 
                                                          "seg_18_02", "seg_18_01", "seg_17_12",
                                                          "seg_17_11", "seg_17_10",
                                                          "dup_18_03", "dup_18_02", "dup_18_01", 
                                                          "dup_17_12", "dup_17_11")], #note here no dup_17_10
                      by = c("id", "id_d", "dup_17_10","Month_Yr"))

dyads_17_11 <- unique(dyads_1511_1912u[dup_17_11 != 0, !c("seg_18_03", 
                                                          "seg_18_02", "seg_18_01", "seg_17_12",
                                                          "seg_17_11", "seg_17_10",
                                                          "dup_18_03", "dup_18_02", "dup_18_01", 
                                                          "dup_17_12", "dup_17_10")], #note here no dup_17_11
                      by = c("id", "id_d", "dup_17_11","Month_Yr"))

## break up the loop
rm(dyads_1511_1912u)
save.image("dyads_1511_1912u_monthly_tie_prob_m13_m14.Rdata")
gc()
dyads_1511_1912u <- readRDS("dyads_1511_1912u.RDS")
rm(dyads_17_10,dyads_17_11)
## end of break

dyads_17_12 <- unique(dyads_1511_1912u[dup_17_12 != 0, !c("seg_18_03", 
                                                          "seg_18_02", "seg_18_01", "seg_17_12",
                                                          "seg_17_11", "seg_17_10",
                                                          "dup_18_03", "dup_18_02", "dup_18_01",  
                                                          "dup_17_11", "dup_17_10")], #note here no dup_17_12
                      by = c("id", "id_d", "dup_17_12","Month_Yr"))

dyads_18_01 <- unique(dyads_1511_1912u[dup_18_01 != 0, !c("seg_18_03", 
                                                          "seg_18_02", "seg_18_01", "seg_17_12",
                                                          "seg_17_11", "seg_17_10",
                                                          "dup_18_03", "dup_18_02", "dup_17_12",  
                                                          "dup_17_11", "dup_17_10")], #note here no dup_18_01
                      by = c("id", "id_d", "dup_18_01","Month_Yr"))

## break up the loop
rm(dyads_1511_1912u)
save.image("dyads_1511_1912u_monthly_tie_prob_m15_m16.Rdata")
gc()
dyads_1511_1912u <- readRDS("dyads_1511_1912u.RDS")
rm(dyads_17_12,dyads_18_01)
## end of break

dyads_18_02 <- unique(dyads_1511_1912u[dup_18_02 != 0, !c("seg_18_03", 
                                                          "seg_18_02", "seg_18_01", "seg_17_12",
                                                          "seg_17_11", "seg_17_10",
                                                          "dup_18_03", "dup_18_01", "dup_17_12",  
                                                          "dup_17_11", "dup_17_10")], #note here no dup_18_02
                      by = c("id", "id_d", "dup_18_02","Month_Yr"))

dyads_18_03 <- unique(dyads_1511_1912u[dup_18_03 != 0, !c("seg_18_03", 
                                                          "seg_18_02", "seg_18_01", "seg_17_12",
                                                          "seg_17_11", "seg_17_10",
                                                          "dup_18_02", "dup_18_01", "dup_17_12",  
                                                          "dup_17_11", "dup_17_10")], #note here no dup_18_03
                      by = c("id", "id_d", "dup_18_03","Month_Yr"))

## break up the loop
rm(dyads_1511_1912u)
save.image("dyads_1511_1912u_monthly_tie_prob_m17_m18.Rdata")
gc()
dyads_1511_1912u <- readRDS("dyads_1511_1912u.RDS")
rm(dyads_18_02,dyads_18_03)
## end of break

dyads_18_04 <- unique(dyads_1511_1912u[dup_18_04 != 0, !c("seg_18_09", 
                                                          "seg_18_08", "seg_18_07", "seg_18_06",
                                                          "seg_18_05", "seg_18_04",
                                                          "dup_18_09", "dup_18_08", "dup_18_07",
                                                          "dup_18_06", "dup_18_05")], #note here no dup_18_04
                      by = c("id", "id_d", "dup_18_04","Month_Yr"))

dyads_18_05 <- unique(dyads_1511_1912u[dup_18_05 != 0, !c("seg_18_09", 
                                                          "seg_18_08", "seg_18_07", "seg_18_06",
                                                          "seg_18_05", "seg_18_04",
                                                          "dup_18_09", "dup_18_08", "dup_18_07",
                                                          "dup_18_06", "dup_18_04")], #note here no dup_18_05
                      by = c("id", "id_d", "dup_18_05","Month_Yr"))

## break up the loop
rm(dyads_1511_1912u)
save.image("dyads_1511_1912u_monthly_tie_prob_m19_m20.Rdata")
gc()
dyads_1511_1912u <- readRDS("dyads_1511_1912u.RDS")
rm(dyads_18_04,dyads_18_05)
## end of break

dyads_18_06 <- unique(dyads_1511_1912u[dup_18_06 != 0, !c("seg_18_09", 
                                                          "seg_18_08", "seg_18_07", "seg_18_06",
                                                          "seg_18_05", "seg_18_04",
                                                          "dup_18_09", "dup_18_08", "dup_18_07",
                                                          "dup_18_05", "dup_18_04")], #note here no dup_18_06
                      by = c("id", "id_d", "dup_18_06","Month_Yr"))

dyads_18_07 <- unique(dyads_1511_1912u[dup_18_07 != 0, !c("seg_18_09", 
                                                          "seg_18_08", "seg_18_07", "seg_18_06",
                                                          "seg_18_05", "seg_18_04",
                                                          "dup_18_09", "dup_18_08", "dup_18_06",
                                                          "dup_18_05", "dup_18_04")], #note here no dup_18_07
                      by = c("id", "id_d", "dup_18_07","Month_Yr"))

## break up the loop
rm(dyads_1511_1912u)
save.image("dyads_1511_1912u_monthly_tie_prob_m21_m22.Rdata")
gc()
dyads_1511_1912u <- readRDS("dyads_1511_1912u.RDS")
rm(dyads_18_06,dyads_18_07)
## end of break

dyads_18_08 <- unique(dyads_1511_1912u[dup_18_08 != 0, !c("seg_18_09", 
                                                          "seg_18_08", "seg_18_07", "seg_18_06",
                                                          "seg_18_05", "seg_18_04",
                                                          "dup_18_09", "dup_18_07", "dup_18_06",
                                                          "dup_18_05", "dup_18_04")], #note here no dup_18_08
                      by = c("id", "id_d", "dup_18_08","Month_Yr"))

dyads_18_09 <- unique(dyads_1511_1912u[dup_18_09 != 0, !c("seg_18_09", 
                                                          "seg_18_08", "seg_18_07", "seg_18_06",
                                                          "seg_18_05", "seg_18_04", 
                                                          "dup_18_08", "dup_18_07", "dup_18_06",
                                                          "dup_18_05", "dup_18_04")],  #note here no dup_18_09
                      by = c("id", "id_d", "dup_18_09","Month_Yr"))

## break up the loop
rm(dyads_1511_1912u)
save.image("dyads_1511_1912u_monthly_tie_prob_m23_m24.Rdata")
gc()
dyads_1511_1912u <- readRDS("dyads_1511_1912u.RDS")
rm(dyads_18_08,dyads_18_09)
## end of break

dyads_18_10 <- unique(dyads_1511_1912u[dup_18_10 != 0, !c("seg_19_03", 
                                                          "seg_19_02", "seg_19_01", "seg_18_12",
                                                          "seg_18_11", "seg_18_10",
                                                          "dup_19_03", "dup_19_02", "dup_19_01", 
                                                          "dup_18_12", "dup_18_11")], #note here no dup_18_10
                      by = c("id", "id_d", "dup_18_10","Month_Yr"))

dyads_18_11 <- unique(dyads_1511_1912u[dup_18_11 != 0, !c("seg_19_03", 
                                                          "seg_19_02", "seg_19_01", "seg_18_12",
                                                          "seg_18_11", "seg_18_10",
                                                          "dup_19_03", "dup_19_02", "dup_19_01", 
                                                          "dup_18_12", "dup_18_10")], #note here no dup_18_11
                      by = c("id", "id_d", "dup_18_11","Month_Yr"))

## break up the loop
rm(dyads_1511_1912u)
save.image("dyads_1511_1912u_monthly_tie_prob_m25_m26.Rdata")
gc()
dyads_1511_1912u <- readRDS("dyads_1511_1912u.RDS")
rm(dyads_18_10,dyads_18_11)
## end of break

dyads_18_12 <- unique(dyads_1511_1912u[dup_18_12 != 0, !c("seg_19_03", 
                                                          "seg_19_02", "seg_19_01", "seg_18_12",
                                                          "seg_18_11", "seg_18_10",
                                                          "dup_19_03", "dup_19_02", "dup_19_01",  
                                                          "dup_18_11", "dup_18_10")], #note here no dup_18_12
                      by = c("id", "id_d", "dup_18_12","Month_Yr"))

dyads_19_01 <- unique(dyads_1511_1912u[dup_19_01 != 0, !c("seg_19_03", 
                                                          "seg_19_02", "seg_19_01", "seg_18_12",
                                                          "seg_18_11", "seg_18_10",
                                                          "dup_19_03", "dup_19_02", "dup_18_12",  
                                                          "dup_18_11", "dup_18_10")], #note here no dup_19_01
                      by = c("id", "id_d", "dup_19_01","Month_Yr"))

## break up the loop
rm(dyads_1511_1912u)
save.image("dyads_1511_1912u_monthly_tie_prob_m27_m28.Rdata")
gc()
dyads_1511_1912u <- readRDS("dyads_1511_1912u.RDS")
rm(dyads_18_12,dyads_19_01)
## end of break

dyads_19_02 <- unique(dyads_1511_1912u[dup_19_02 != 0, !c("seg_19_03", 
                                                          "seg_19_02", "seg_19_01", "seg_18_12",
                                                          "seg_18_11", "seg_18_10",
                                                          "dup_19_03", "dup_19_01", "dup_18_12",  
                                                          "dup_18_11", "dup_18_10")], #note here no dup_19_02
                      by = c("id", "id_d", "dup_19_02","Month_Yr"))

dyads_19_03 <- unique(dyads_1511_1912u[dup_19_03 != 0, !c("seg_19_03", 
                                                          "seg_19_02", "seg_19_01", "seg_18_12",
                                                          "seg_18_11", "seg_18_10",
                                                          "dup_19_02", "dup_19_01", "dup_18_12",  
                                                          "dup_18_11", "dup_18_10")], #note here no dup_19_03
                      by = c("id", "id_d", "dup_19_03","Month_Yr"))

## break up the loop
rm(dyads_1511_1912u)
save.image("dyads_1511_1912u_monthly_tie_prob_m29_m30.Rdata")
gc()
dyads_1511_1912u <- readRDS("dyads_1511_1912u.RDS")
rm(dyads_19_02,dyads_19_03)
## end of break

dyads_19_04 <- unique(dyads_1511_1912u[dup_19_04 != 0, !c("seg_19_09", 
                                                          "seg_19_08", "seg_19_07", "seg_19_06",
                                                          "seg_19_05", "seg_19_04",
                                                          "dup_19_09", "dup_19_08", "dup_19_07",
                                                          "dup_19_06", "dup_19_05")], #note here no dup_19_04
                      by = c("id", "id_d", "dup_19_04","Month_Yr"))


dyads_19_05 <- unique(dyads_1511_1912u[dup_19_05 != 0, !c("seg_19_09", 
                                                          "seg_19_08", "seg_19_07", "seg_19_06",
                                                          "seg_19_05", "seg_19_04",
                                                          "dup_19_09", "dup_19_08", "dup_19_07",
                                                          "dup_19_06", "dup_19_04")], #note here no dup_19_05
                      by = c("id", "id_d", "dup_19_05","Month_Yr"))

## break up the loop
rm(dyads_1511_1912u)
save.image("dyads_1511_1912u_monthly_tie_prob_m31_m32.Rdata")
gc()
dyads_1511_1912u <- readRDS("dyads_1511_1912u.RDS")
rm(dyads_19_04,dyads_19_05)
## end of break

dyads_19_06 <- unique(dyads_1511_1912u[dup_19_06 != 0, !c("seg_19_09", 
                                                          "seg_19_08", "seg_19_07", "seg_19_06",
                                                          "seg_19_05", "seg_19_04",
                                                          "dup_19_09", "dup_19_08", "dup_19_07",
                                                          "dup_19_05", "dup_19_04")], #note here no dup_19_06
                      by = c("id", "id_d", "dup_19_06","Month_Yr"))


dyads_19_07 <- unique(dyads_1511_1912u[dup_19_07 != 0, !c("seg_19_09", 
                                                          "seg_19_08", "seg_19_07", "seg_19_06",
                                                          "seg_19_05", "seg_19_04",
                                                          "dup_19_09", "dup_19_08", "dup_19_06",
                                                          "dup_19_05", "dup_19_04")], #note here no dup_19_07
                      by = c("id", "id_d", "dup_19_07","Month_Yr"))

## break up the loop
rm(dyads_1511_1912u)
save.image("dyads_1511_1912u_monthly_tie_prob_m33_m34.Rdata")
gc()
dyads_1511_1912u <- readRDS("dyads_1511_1912u.RDS")
rm(dyads_19_06,dyads_19_07)
## end of break

dyads_19_08 <- unique(dyads_1511_1912u[dup_19_08 != 0, !c("seg_19_09", 
                                                          "seg_19_08", "seg_19_07", "seg_19_06",
                                                          "seg_19_05", "seg_19_04",
                                                          "dup_19_09", "dup_19_07", "dup_19_06",
                                                          "dup_19_05", "dup_19_04")], #note here no dup_19_08
                      by = c("id", "id_d", "dup_19_08","Month_Yr"))

dyads_19_09 <- unique(dyads_1511_1912u[dup_19_09 != 0, !c("seg_19_09", 
                                                          "seg_19_08", "seg_19_07", "seg_19_06",
                                                          "seg_19_05", "seg_19_04", 
                                                          "dup_19_08", "dup_19_07", "dup_19_06",
                                                          "dup_19_05", "dup_19_04")],  #note here no dup_19_09
                      by = c("id", "id_d", "dup_19_09","Month_Yr"))

## break up the loop
rm(dyads_1511_1912u)
save.image("dyads_1511_1912u_monthly_tie_prob_m35_m36.Rdata")
gc()
dyads_1511_1912u <- readRDS("dyads_1511_1912u.RDS")
rm(dyads_19_08,dyads_19_09)
## end of break

dyads_19_10 <- unique(dyads_1511_1912u[dup_19_10 != 0, !c("seg_20_03", 
                                                          "seg_20_02", "seg_20_01", "seg_19_12",
                                                          "seg_19_11", "seg_19_10",
                                                          "dup_20_03", "dup_20_02", "dup_20_01", 
                                                          "dup_19_12", "dup_19_11")], #note here no dup_19_10
                      by = c("id", "id_d", "dup_19_10","Month_Yr"))

dyads_19_11 <- unique(dyads_1511_1912u[dup_19_11 != 0, !c("seg_20_03", 
                                                          "seg_20_02", "seg_20_01", "seg_19_12",
                                                          "seg_19_11", "seg_19_10",
                                                          "dup_20_03", "dup_20_02", "dup_20_01", 
                                                          "dup_19_12", "dup_19_10")], #note here no dup_19_11
                      by = c("id", "id_d", "dup_19_11","Month_Yr"))

## break up the loop
rm(dyads_1511_1912u)
save.image("dyads_1511_1912u_monthly_tie_prob_m37_m38.Rdata")
gc()
dyads_1511_1912u <- readRDS("dyads_1511_1912u.RDS")
rm(dyads_19_10,dyads_19_11)
## end of break

dyads_19_12 <- unique(dyads_1511_1912u[dup_19_12 != 0, !c("seg_20_03", 
                                                          "seg_20_02", "seg_20_01", "seg_19_12",
                                                          "seg_19_11", "seg_19_10",
                                                          "dup_20_03", "dup_20_02", "dup_20_01",  
                                                          "dup_19_11", "dup_19_10")], #note here no dup_19_12
                      by = c("id", "id_d", "dup_19_12","Month_Yr"))

dyads_20_01 <- unique(dyads_1511_1912u[dup_20_01 != 0, !c("seg_20_03", 
                                                          "seg_20_02", "seg_20_01", "seg_19_12",
                                                          "seg_19_11", "seg_19_10",
                                                          "dup_20_03", "dup_20_02", "dup_19_12",  
                                                          "dup_19_11", "dup_19_10")], #note here no dup_20_01
                      by = c("id", "id_d", "dup_20_01","Month_Yr"))

## break up the loop
rm(dyads_1511_1912u)
save.image("dyads_1511_1912u_monthly_tie_prob_m39_m40.Rdata")
gc()


dyads_1511_1912u <- readRDS("dyads_1511_1912u.RDS")
rm(dyads_19_12,dyads_20_01)
## end of break

dyads_20_02 <- unique(dyads_1511_1912u[dup_20_02 != 0, !c("seg_20_03",
                                                          "seg_20_02", "seg_20_01", "seg_19_12",
                                                          "seg_19_11", "seg_19_10",
                                                          "dup_20_03", "dup_20_01", "dup_19_12",
                                                          "dup_19_11", "dup_19_10")], #note here no dup_20_02
                      by = c("id", "id_d", "dup_20_02","Month_Yr"))

dyads_20_03 <- unique(dyads_1511_1912u[dup_20_03 != 0, !c("seg_20_03",
                                                          "seg_20_02", "seg_20_01", "seg_19_12",
                                                          "seg_19_11", "seg_19_10",
                                                          "dup_20_02", "dup_20_01", "dup_19_12",
                                                          "dup_19_11", "dup_19_10")], #note here no dup_20_03
                      by = c("id", "id_d", "dup_20_03","Month_Yr"))

## break up the loop
rm(dyads_1511_1912u)
save.image("dyads_1511_1912u_monthly_tie_prob_m41_m42.Rdata")
gc()
dyads_1511_1912u <- readRDS("dyads_1511_1912u.RDS")
rm(dyads_20_02,dyads_20_03)
# end of break

## segment 0: Months -5 to 0 (Oct1 16-Mar31 17) 
# read data for tie probability prediction
setwd("/work/pi_mpachucki_umass_edu/food_projects/food_simulation_r01/data analytic")
load("dyads_1511_1912u_monthly_tie_prob_pretrial.Rdata")

dyads_16_09[ , num_lt_2min_cat_tw := fcase(
  dup_16_09 == 1, 0.933120514, 
  dup_16_09 == 2, 0.817687813,
  dup_16_09 == 3, 1.609523574,
  dup_16_09 >= 4, 4.72763085,
  default = 0
)]

dyads_16_08[ , num_lt_2min_cat_tw := fcase(
  dup_16_08 == 1, 0.933120514, 
  dup_16_08 == 2, 0.817687813,
  dup_16_08 == 3, 1.609523574,
  dup_16_08 >= 4, 4.72763085,
  default = 0
)]

dyads_16_07[ , num_lt_2min_cat_tw := fcase(
  dup_16_07 == 1, 0.933120514, 
  dup_16_07 == 2, 0.817687813,
  dup_16_07 == 3, 1.609523574,
  dup_16_07 >= 4, 4.72763085,
  default = 0
)]

dyads_16_06[ , num_lt_2min_cat_tw := fcase(
  dup_16_06 == 1, 0.933120514, 
  dup_16_06 == 2, 0.817687813,
  dup_16_06 == 3, 1.609523574,
  dup_16_06 >= 4, 4.72763085,
  default = 0
)]

dyads_16_05[ , num_lt_2min_cat_tw := fcase(
  dup_16_05 == 1, 0.933120514, 
  dup_16_05 == 2, 0.817687813,
  dup_16_05 == 3, 1.609523574,
  dup_16_05 >= 4, 4.72763085,
  default = 0
)]

dyads_16_04[ , num_lt_2min_cat_tw := fcase(
  dup_16_04 == 1, 0.933120514, 
  dup_16_04 == 2, 0.817687813,
  dup_16_04 == 3, 1.609523574,
  dup_16_04 >= 4, 4.72763085,
  default = 0
)]

dyads_16_09[ , logodds_upd := -5.490030491 + gender_match_coeff + agediffcat5_coeff + race_match_coeff + dept_match_coeff + job_cat_match_coeff + num_lt_2min_cat_tw]
dyads_16_09[ , predprob_upd := (exp(logodds_upd))/(1+exp(logodds_upd))]

dyads_16_08[ , logodds_upd := -5.490030491 + gender_match_coeff + agediffcat5_coeff + race_match_coeff + dept_match_coeff + job_cat_match_coeff + num_lt_2min_cat_tw]
dyads_16_08[ , predprob_upd := (exp(logodds_upd))/(1+exp(logodds_upd))]

dyads_16_07[ , logodds_upd := -5.490030491 + gender_match_coeff + agediffcat5_coeff + race_match_coeff + dept_match_coeff + job_cat_match_coeff + num_lt_2min_cat_tw]
dyads_16_07[ , predprob_upd := (exp(logodds_upd))/(1+exp(logodds_upd))]

dyads_16_06[ , logodds_upd := -5.490030491 + gender_match_coeff + agediffcat5_coeff + race_match_coeff + dept_match_coeff + job_cat_match_coeff + num_lt_2min_cat_tw]
dyads_16_06[ , predprob_upd := (exp(logodds_upd))/(1+exp(logodds_upd))]

dyads_16_05[ , logodds_upd := -5.490030491 + gender_match_coeff + agediffcat5_coeff + race_match_coeff + dept_match_coeff + job_cat_match_coeff + num_lt_2min_cat_tw]
dyads_16_05[ , predprob_upd := (exp(logodds_upd))/(1+exp(logodds_upd))]

dyads_16_04[ , logodds_upd := -5.490030491 + gender_match_coeff + agediffcat5_coeff + race_match_coeff + dept_match_coeff + job_cat_match_coeff + num_lt_2min_cat_tw]
dyads_16_04[ , predprob_upd := (exp(logodds_upd))/(1+exp(logodds_upd))]

#MCP edit 9/12/22 - cut down # of vars in each object to save space! Won't load into RStudio otherwise. 
#previously, this had been at the end of segment 7. 

dyads_16_04 <- dyads_16_04[mdy>="2016-04-01" & mdy<"2016-05-01",c("id","mdy","time_n","id_d",
                                                                  "sex","race_cat5","ed_cat","job_cat",
                                                                  "randomgroup3", "solo_obs",
                                                                  "num_lt_2min_cat_tw","cafe",
                                                                  "logodds_upd","predprob_upd")]
dyads_16_05 <- dyads_16_05[mdy>="2016-05-01" & mdy<"2016-06-01",c("id","mdy","time_n","id_d",
                                                                  "sex","race_cat5","ed_cat","job_cat",
                                                                  "randomgroup3", "solo_obs",
                                                                  "num_lt_2min_cat_tw","cafe",
                                                                  "logodds_upd","predprob_upd")]
dyads_16_06 <- dyads_16_06[mdy>="2016-06-01" & mdy<"2016-07-01",c("id","mdy","time_n","id_d",
                                                                  "sex","race_cat5","ed_cat","job_cat",
                                                                  "randomgroup3", "solo_obs",
                                                                  "num_lt_2min_cat_tw","cafe",
                                                                  "logodds_upd","predprob_upd")]
dyads_16_07 <- dyads_16_07[mdy>="2016-07-01" & mdy<"2016-08-01",c("id","mdy","time_n","id_d",
                                                                  "sex","race_cat5","ed_cat","job_cat",
                                                                  "randomgroup3", "solo_obs",
                                                                  "num_lt_2min_cat_tw","cafe",
                                                                  "logodds_upd","predprob_upd")]
dyads_16_08 <- dyads_16_08[mdy>="2016-08-01" & mdy<"2016-09-01",c("id","mdy","time_n","id_d",
                                                                  "sex","race_cat5","ed_cat","job_cat",
                                                                  "randomgroup3", "solo_obs",
                                                                  "num_lt_2min_cat_tw","cafe",
                                                                  "logodds_upd","predprob_upd")]
dyads_16_09 <- dyads_16_09[mdy>="2016-09-01" & mdy<"2016-10-01",c("id","mdy","time_n","id_d",
                                                                  "sex","race_cat5","ed_cat","job_cat",
                                                                  "randomgroup3", "solo_obs",
                                                                  "num_lt_2min_cat_tw","cafe",
                                                                  "logodds_upd","predprob_upd")]

## segment 1: Months 1-6 (Oct1 16-Mar31 17)
# read data for tie probability prediction
gc() #clear up free RStudio memory
load("dyads_1511_1912u_monthly_tie_prob_m1_m2.Rdata")
load("dyads_1511_1912u_monthly_tie_prob_m3_m4.Rdata")
load("dyads_1511_1912u_monthly_tie_prob_m5_m6.Rdata")

dyads_17_03[ , num_lt_2min_cat_tw := fcase(
  dup_17_03 == 1, 0.933120514, 
  dup_17_03 == 2, 0.817687813,
  dup_17_03 == 3, 1.609523574,
  dup_17_03 >= 4, 4.72763085,
  default = 0
)]

dyads_17_02[ , num_lt_2min_cat_tw := fcase(
  dup_17_02 == 1, 0.933120514, 
  dup_17_02 == 2, 0.817687813,
  dup_17_02 == 3, 1.609523574,
  dup_17_02 >= 4, 4.72763085,
  default = 0
)]

dyads_17_01[ , num_lt_2min_cat_tw := fcase(
  dup_17_01 == 1, 0.933120514, 
  dup_17_01 == 2, 0.817687813,
  dup_17_01 == 3, 1.609523574,
  dup_17_01 >= 4, 4.72763085,
  default = 0
)]

dyads_16_12[ , num_lt_2min_cat_tw := fcase(
  dup_16_12 == 1, 0.933120514, 
  dup_16_12 == 2, 0.817687813,
  dup_16_12 == 3, 1.609523574,
  dup_16_12 >= 4, 4.72763085,
  default = 0
)]

dyads_16_11[ , num_lt_2min_cat_tw := fcase(
  dup_16_11 == 1, 0.933120514, 
  dup_16_11 == 2, 0.817687813,
  dup_16_11 == 3, 1.609523574,
  dup_16_11 >= 4, 4.72763085,
  default = 0
)]

dyads_16_10[ , num_lt_2min_cat_tw := fcase(
  dup_16_10 == 1, 0.933120514, 
  dup_16_10 == 2, 0.817687813,
  dup_16_10 == 3, 1.609523574,
  dup_16_10 >= 4, 4.72763085,
  default = 0
)]

dyads_17_03[ , logodds_upd := -5.490030491 + gender_match_coeff + agediffcat5_coeff + race_match_coeff + dept_match_coeff + job_cat_match_coeff + num_lt_2min_cat_tw]
dyads_17_03[ , predprob_upd := (exp(logodds_upd))/(1+exp(logodds_upd))]

dyads_17_02[ , logodds_upd := -5.490030491 + gender_match_coeff + agediffcat5_coeff + race_match_coeff + dept_match_coeff + job_cat_match_coeff + num_lt_2min_cat_tw]
dyads_17_02[ , predprob_upd := (exp(logodds_upd))/(1+exp(logodds_upd))]

dyads_17_01[ , logodds_upd := -5.490030491 + gender_match_coeff + agediffcat5_coeff + race_match_coeff + dept_match_coeff + job_cat_match_coeff + num_lt_2min_cat_tw]
dyads_17_01[ , predprob_upd := (exp(logodds_upd))/(1+exp(logodds_upd))]

dyads_16_12[ , logodds_upd := -5.490030491 + gender_match_coeff + agediffcat5_coeff + race_match_coeff + dept_match_coeff + job_cat_match_coeff + num_lt_2min_cat_tw]
dyads_16_12[ , predprob_upd := (exp(logodds_upd))/(1+exp(logodds_upd))]

dyads_16_11[ , logodds_upd := -5.490030491 + gender_match_coeff + agediffcat5_coeff + race_match_coeff + dept_match_coeff + job_cat_match_coeff + num_lt_2min_cat_tw]
dyads_16_11[ , predprob_upd := (exp(logodds_upd))/(1+exp(logodds_upd))]

dyads_16_10[ , logodds_upd := -5.490030491 + gender_match_coeff + agediffcat5_coeff + race_match_coeff + dept_match_coeff + job_cat_match_coeff + num_lt_2min_cat_tw]
dyads_16_10[ , predprob_upd := (exp(logodds_upd))/(1+exp(logodds_upd))]

dyads_16_10 <- dyads_16_10[mdy>="2016-10-01" & mdy<"2016-11-01",c("id","mdy","time_n","id_d",
                                                                  "sex","race_cat5","ed_cat","job_cat",
                                                                  "randomgroup3", "solo_obs",
                                                                  "num_lt_2min_cat_tw","cafe",
                                                                  "logodds_upd","predprob_upd")]
dyads_16_11 <- dyads_16_11[mdy>="2016-11-01" & mdy<"2016-12-01",c("id","mdy","time_n","id_d",
                                                                  "sex","race_cat5","ed_cat","job_cat",
                                                                  "randomgroup3", "solo_obs",
                                                                  "num_lt_2min_cat_tw","cafe",
                                                                  "logodds_upd","predprob_upd")]
dyads_16_12 <- dyads_16_12[mdy>="2016-12-01" & mdy<"2017-01-01",c("id","mdy","time_n","id_d",
                                                                  "sex","race_cat5","ed_cat","job_cat",
                                                                  "randomgroup3", "solo_obs",
                                                                  "num_lt_2min_cat_tw","cafe",
                                                                  "logodds_upd","predprob_upd")]
dyads_17_01 <- dyads_17_01[mdy>="2017-01-01" & mdy<"2017-02-01",c("id","mdy","time_n","id_d",
                                                                  "sex","race_cat5","ed_cat","job_cat",
                                                                  "randomgroup3", "solo_obs",
                                                                  "num_lt_2min_cat_tw","cafe",
                                                                  "logodds_upd","predprob_upd")]
dyads_17_02 <- dyads_17_02[mdy>="2017-02-01" & mdy<"2017-03-01",c("id","mdy","time_n","id_d",
                                                                  "sex","race_cat5","ed_cat","job_cat",
                                                                  "randomgroup3", "solo_obs",
                                                                  "num_lt_2min_cat_tw","cafe",
                                                                  "logodds_upd","predprob_upd")]
dyads_17_03 <- dyads_17_03[mdy>="2017-03-01" & mdy<"2017-04-01",c("id","mdy","time_n","id_d",
                                                                  "sex","race_cat5","ed_cat","job_cat",
                                                                  "randomgroup3", "solo_obs",
                                                                  "num_lt_2min_cat_tw","cafe",
                                                                  "logodds_upd","predprob_upd")]

## segment 2: Months 7-12 (Apr1 17-Sept30 17)
# read data for tie probability prediction
gc() #clear up free RStudio memory
load("dyads_1511_1912u_monthly_tie_prob_m7_m8.Rdata")
load("dyads_1511_1912u_monthly_tie_prob_m9_m10.Rdata")
load("dyads_1511_1912u_monthly_tie_prob_m11_m12.Rdata")

dyads_17_09[ , num_lt_2min_cat_tw := fcase(
  dup_17_09 == 1, 0.933120514, 
  dup_17_09 == 2, 0.817687813,
  dup_17_09 == 3, 1.609523574,
  dup_17_09 >= 4, 4.72763085,
  default = 0
)]

dyads_17_08[ , num_lt_2min_cat_tw := fcase(
  dup_17_08 == 1, 0.933120514, 
  dup_17_08 == 2, 0.817687813,
  dup_17_08 == 3, 1.609523574,
  dup_17_08 >= 4, 4.72763085,
  default = 0
)]

dyads_17_07[ , num_lt_2min_cat_tw := fcase(
  dup_17_07 == 1, 0.933120514, 
  dup_17_07 == 2, 0.817687813,
  dup_17_07 == 3, 1.609523574,
  dup_17_07 >= 4, 4.72763085,
  default = 0
)]

dyads_17_06[ , num_lt_2min_cat_tw := fcase(
  dup_17_06 == 1, 0.933120514, 
  dup_17_06 == 2, 0.817687813,
  dup_17_06 == 3, 1.609523574,
  dup_17_06 >= 4, 4.72763085,
  default = 0
)]

dyads_17_05[ , num_lt_2min_cat_tw := fcase(
  dup_17_05 == 1, 0.933120514, 
  dup_17_05 == 2, 0.817687813,
  dup_17_05 == 3, 1.609523574,
  dup_17_05 >= 4, 4.72763085,
  default = 0
)]

dyads_17_04[ , num_lt_2min_cat_tw := fcase(
  dup_17_04 == 1, 0.933120514, 
  dup_17_04 == 2, 0.817687813,
  dup_17_04 == 3, 1.609523574,
  dup_17_04 >= 4, 4.72763085,
  default = 0
)]

dyads_17_09[ , logodds_upd := -5.490030491 + gender_match_coeff + agediffcat5_coeff + race_match_coeff + dept_match_coeff + job_cat_match_coeff + num_lt_2min_cat_tw]
dyads_17_09[ , predprob_upd := (exp(logodds_upd))/(1+exp(logodds_upd))]

dyads_17_08[ , logodds_upd := -5.490030491 + gender_match_coeff + agediffcat5_coeff + race_match_coeff + dept_match_coeff + job_cat_match_coeff + num_lt_2min_cat_tw]
dyads_17_08[ , predprob_upd := (exp(logodds_upd))/(1+exp(logodds_upd))]

dyads_17_07[ , logodds_upd := -5.490030491 + gender_match_coeff + agediffcat5_coeff + race_match_coeff + dept_match_coeff + job_cat_match_coeff + num_lt_2min_cat_tw]
dyads_17_07[ , predprob_upd := (exp(logodds_upd))/(1+exp(logodds_upd))]

dyads_17_06[ , logodds_upd := -5.490030491 + gender_match_coeff + agediffcat5_coeff + race_match_coeff + dept_match_coeff + job_cat_match_coeff + num_lt_2min_cat_tw]
dyads_17_06[ , predprob_upd := (exp(logodds_upd))/(1+exp(logodds_upd))]

dyads_17_05[ , logodds_upd := -5.490030491 + gender_match_coeff + agediffcat5_coeff + race_match_coeff + dept_match_coeff + job_cat_match_coeff + num_lt_2min_cat_tw]
dyads_17_05[ , predprob_upd := (exp(logodds_upd))/(1+exp(logodds_upd))]

dyads_17_04[ , logodds_upd := -5.490030491 + gender_match_coeff + agediffcat5_coeff + race_match_coeff + dept_match_coeff + job_cat_match_coeff + num_lt_2min_cat_tw]
dyads_17_04[ , predprob_upd := (exp(logodds_upd))/(1+exp(logodds_upd))]

dyads_17_04 <- dyads_17_04[mdy>="2017-04-01" & mdy<"2017-05-01",c("id","mdy","time_n","id_d",
                                                                  "sex","race_cat5","ed_cat","job_cat",
                                                                  "randomgroup3", "solo_obs",
                                                                  "num_lt_2min_cat_tw","cafe",
                                                                  "logodds_upd","predprob_upd")]
dyads_17_05 <- dyads_17_05[mdy>="2017-05-01" & mdy<"2017-06-01",c("id","mdy","time_n","id_d",
                                                                  "sex","race_cat5","ed_cat","job_cat",
                                                                  "randomgroup3", "solo_obs",
                                                                  "num_lt_2min_cat_tw","cafe",
                                                                  "logodds_upd","predprob_upd")]
dyads_17_06 <- dyads_17_06[mdy>="2017-06-01" & mdy<"2017-07-01",c("id","mdy","time_n","id_d",
                                                                  "sex","race_cat5","ed_cat","job_cat",
                                                                  "randomgroup3", "solo_obs",
                                                                  "num_lt_2min_cat_tw","cafe",
                                                                  "logodds_upd","predprob_upd")]
dyads_17_07 <- dyads_17_07[mdy>="2017-07-01" & mdy<"2017-08-01",c("id","mdy","time_n","id_d",
                                                                  "sex","race_cat5","ed_cat","job_cat",
                                                                  "randomgroup3", "solo_obs",
                                                                  "num_lt_2min_cat_tw","cafe",
                                                                  "logodds_upd","predprob_upd")]
dyads_17_08 <- dyads_17_08[mdy>="2017-08-01" & mdy<"2017-09-01",c("id","mdy","time_n","id_d",
                                                                  "sex","race_cat5","ed_cat","job_cat",
                                                                  "randomgroup3", "solo_obs",
                                                                  "num_lt_2min_cat_tw","cafe",
                                                                  "logodds_upd","predprob_upd")]
dyads_17_09 <- dyads_17_09[mdy>="2017-09-01" & mdy<"2017-10-01",c("id","mdy","time_n","id_d",
                                                                  "sex","race_cat5","ed_cat","job_cat",
                                                                  "randomgroup3", "solo_obs",
                                                                  "num_lt_2min_cat_tw","cafe",
                                                                  "logodds_upd","predprob_upd")]

## segment 3: Months 13-18 (Oct1 17-Mar31 18)
# read data for tie probability prediction
gc() #clear up free RStudio memory
load("dyads_1511_1912u_monthly_tie_prob_m13_m14.Rdata")
load("dyads_1511_1912u_monthly_tie_prob_m15_m16.Rdata")
load("dyads_1511_1912u_monthly_tie_prob_m17_m18.Rdata")

dyads_18_03[ , num_lt_2min_cat_tw := fcase(
  dup_18_03 == 1, 0.933120514, 
  dup_18_03 == 2, 0.817687813,
  dup_18_03 == 3, 1.609523574,
  dup_18_03 >= 4, 4.72763085,
  default = 0
)]

dyads_18_02[ , num_lt_2min_cat_tw := fcase(
  dup_18_02 == 1, 0.933120514, 
  dup_18_02 == 2, 0.817687813,
  dup_18_02 == 3, 1.609523574,
  dup_18_02 >= 4, 4.72763085,
  default = 0
)]

dyads_18_01[ , num_lt_2min_cat_tw := fcase(
  dup_18_01 == 1, 0.933120514, 
  dup_18_01 == 2, 0.817687813,
  dup_18_01 == 3, 1.609523574,
  dup_18_01 >= 4, 4.72763085,
  default = 0
)]

dyads_17_12[ , num_lt_2min_cat_tw := fcase(
  dup_17_12 == 1, 0.933120514, 
  dup_17_12 == 2, 0.817687813,
  dup_17_12 == 3, 1.609523574,
  dup_17_12 >= 4, 4.72763085,
  default = 0
)]

dyads_17_11[ , num_lt_2min_cat_tw := fcase(
  dup_17_11 == 1, 0.933120514, 
  dup_17_11 == 2, 0.817687813,
  dup_17_11 == 3, 1.609523574,
  dup_17_11 >= 4, 4.72763085,
  default = 0
)]

dyads_17_10[ , num_lt_2min_cat_tw := fcase(
  dup_17_10 == 1, 0.933120514, 
  dup_17_10 == 2, 0.817687813,
  dup_17_10 == 3, 1.609523574,
  dup_17_10 >= 4, 4.72763085,
  default = 0
)]

dyads_18_03[ , logodds_upd := -5.490030491 + gender_match_coeff + agediffcat5_coeff + race_match_coeff + dept_match_coeff + job_cat_match_coeff + num_lt_2min_cat_tw]
dyads_18_03[ , predprob_upd := (exp(logodds_upd))/(1+exp(logodds_upd))]

dyads_18_02[ , logodds_upd := -5.490030491 + gender_match_coeff + agediffcat5_coeff + race_match_coeff + dept_match_coeff + job_cat_match_coeff + num_lt_2min_cat_tw]
dyads_18_02[ , predprob_upd := (exp(logodds_upd))/(1+exp(logodds_upd))]

dyads_18_01[ , logodds_upd := -5.490030491 + gender_match_coeff + agediffcat5_coeff + race_match_coeff + dept_match_coeff + job_cat_match_coeff + num_lt_2min_cat_tw]
dyads_18_01[ , predprob_upd := (exp(logodds_upd))/(1+exp(logodds_upd))]

dyads_17_12[ , logodds_upd := -5.490030491 + gender_match_coeff + agediffcat5_coeff + race_match_coeff + dept_match_coeff + job_cat_match_coeff + num_lt_2min_cat_tw]
dyads_17_12[ , predprob_upd := (exp(logodds_upd))/(1+exp(logodds_upd))]

dyads_17_11[ , logodds_upd := -5.490030491 + gender_match_coeff + agediffcat5_coeff + race_match_coeff + dept_match_coeff + job_cat_match_coeff + num_lt_2min_cat_tw]
dyads_17_11[ , predprob_upd := (exp(logodds_upd))/(1+exp(logodds_upd))]

dyads_17_10[ , logodds_upd := -5.490030491 + gender_match_coeff + agediffcat5_coeff + race_match_coeff + dept_match_coeff + job_cat_match_coeff + num_lt_2min_cat_tw]
dyads_17_10[ , predprob_upd := (exp(logodds_upd))/(1+exp(logodds_upd))]


dyads_17_10 <- dyads_17_10[mdy>="2017-10-01" & mdy<"2017-11-01",c("id","mdy","time_n","id_d",
                                                                  "sex","race_cat5","ed_cat","job_cat",
                                                                  "randomgroup3", "solo_obs",
                                                                  "num_lt_2min_cat_tw","cafe",
                                                                  "logodds_upd","predprob_upd")]
dyads_17_11 <- dyads_17_11[mdy>="2017-11-01" & mdy<"2017-12-01",c("id","mdy","time_n","id_d",
                                                                  "sex","race_cat5","ed_cat","job_cat",
                                                                  "randomgroup3", "solo_obs",
                                                                  "num_lt_2min_cat_tw","cafe",
                                                                  "logodds_upd","predprob_upd")]
dyads_17_12 <- dyads_17_12[mdy>="2017-12-01" & mdy<"2018-01-01",c("id","mdy","time_n","id_d",
                                                                  "sex","race_cat5","ed_cat","job_cat",
                                                                  "randomgroup3", "solo_obs",
                                                                  "num_lt_2min_cat_tw","cafe",
                                                                  "logodds_upd","predprob_upd")]
dyads_18_01 <- dyads_18_01[mdy>="2018-01-01" & mdy<"2018-02-01",c("id","mdy","time_n","id_d",
                                                                  "sex","race_cat5","ed_cat","job_cat",
                                                                  "randomgroup3", "solo_obs",
                                                                  "num_lt_2min_cat_tw","cafe",
                                                                  "logodds_upd","predprob_upd")]
dyads_18_02 <- dyads_18_02[mdy>="2018-02-01" & mdy<"2018-03-01",c("id","mdy","time_n","id_d",
                                                                  "sex","race_cat5","ed_cat","job_cat",
                                                                  "randomgroup3", "solo_obs",
                                                                  "num_lt_2min_cat_tw","cafe",
                                                                  "logodds_upd","predprob_upd")]
dyads_18_03 <- dyads_18_03[mdy>="2018-03-01" & mdy<"2018-04-01",c("id","mdy","time_n","id_d",
                                                                  "sex","race_cat5","ed_cat","job_cat",
                                                                  "randomgroup3", "solo_obs",
                                                                  "num_lt_2min_cat_tw","cafe",
                                                                  "logodds_upd","predprob_upd")]

## segment 4: Months 19-24 (Apr1 18-Sept30 18) 
# read data for tie probability prediction
gc() #clear up free RStudio memory
load("dyads_1511_1912u_monthly_tie_prob_m19_m20.Rdata")
load("dyads_1511_1912u_monthly_tie_prob_m21_m22.Rdata")
load("dyads_1511_1912u_monthly_tie_prob_m23_m24.Rdata")

dyads_18_09[ , num_lt_2min_cat_tw := fcase(
  dup_18_09 == 1, 0.933120514, 
  dup_18_09 == 2, 0.817687813,
  dup_18_09 == 3, 1.609523574,
  dup_18_09 >= 4, 4.72763085,
  default = 0
)]

dyads_18_08[ , num_lt_2min_cat_tw := fcase(
  dup_18_08 == 1, 0.933120514, 
  dup_18_08 == 2, 0.817687813,
  dup_18_08 == 3, 1.609523574,
  dup_18_08 >= 4, 4.72763085,
  default = 0
)]

dyads_18_07[ , num_lt_2min_cat_tw := fcase(
  dup_18_07 == 1, 0.933120514, 
  dup_18_07 == 2, 0.817687813,
  dup_18_07 == 3, 1.609523574,
  dup_18_07 >= 4, 4.72763085,
  default = 0
)]

dyads_18_06[ , num_lt_2min_cat_tw := fcase(
  dup_18_06 == 1, 0.933120514, 
  dup_18_06 == 2, 0.817687813,
  dup_18_06 == 3, 1.609523574,
  dup_18_06 >= 4, 4.72763085,
  default = 0
)]

dyads_18_05[ , num_lt_2min_cat_tw := fcase(
  dup_18_05 == 1, 0.933120514, 
  dup_18_05 == 2, 0.817687813,
  dup_18_05 == 3, 1.609523574,
  dup_18_05 >= 4, 4.72763085,
  default = 0
)]

dyads_18_04[ , num_lt_2min_cat_tw := fcase(
  dup_18_04 == 1, 0.933120514, 
  dup_18_04 == 2, 0.817687813,
  dup_18_04 == 3, 1.609523574,
  dup_18_04 >= 4, 4.72763085,
  default = 0
)]

dyads_18_09[ , logodds_upd := -5.490030491 + gender_match_coeff + agediffcat5_coeff + race_match_coeff + dept_match_coeff + job_cat_match_coeff + num_lt_2min_cat_tw]
dyads_18_09[ , predprob_upd := (exp(logodds_upd))/(1+exp(logodds_upd))]

dyads_18_08[ , logodds_upd := -5.490030491 + gender_match_coeff + agediffcat5_coeff + race_match_coeff + dept_match_coeff + job_cat_match_coeff + num_lt_2min_cat_tw]
dyads_18_08[ , predprob_upd := (exp(logodds_upd))/(1+exp(logodds_upd))]

dyads_18_07[ , logodds_upd := -5.490030491 + gender_match_coeff + agediffcat5_coeff + race_match_coeff + dept_match_coeff + job_cat_match_coeff + num_lt_2min_cat_tw]
dyads_18_07[ , predprob_upd := (exp(logodds_upd))/(1+exp(logodds_upd))]

dyads_18_06[ , logodds_upd := -5.490030491 + gender_match_coeff + agediffcat5_coeff + race_match_coeff + dept_match_coeff + job_cat_match_coeff + num_lt_2min_cat_tw]
dyads_18_06[ , predprob_upd := (exp(logodds_upd))/(1+exp(logodds_upd))]

dyads_18_05[ , logodds_upd := -5.490030491 + gender_match_coeff + agediffcat5_coeff + race_match_coeff + dept_match_coeff + job_cat_match_coeff + num_lt_2min_cat_tw]
dyads_18_05[ , predprob_upd := (exp(logodds_upd))/(1+exp(logodds_upd))]

dyads_18_04[ , logodds_upd := -5.490030491 + gender_match_coeff + agediffcat5_coeff + race_match_coeff + dept_match_coeff + job_cat_match_coeff + num_lt_2min_cat_tw]
dyads_18_04[ , predprob_upd := (exp(logodds_upd))/(1+exp(logodds_upd))]

dyads_18_04 <- dyads_18_04[mdy>="2018-04-01" & mdy<"2018-05-01",c("id","mdy","time_n","id_d",
                                                                  "sex","race_cat5","ed_cat","job_cat",
                                                                  "randomgroup3", "solo_obs",
                                                                  "num_lt_2min_cat_tw","cafe",
                                                                  "logodds_upd","predprob_upd")]
dyads_18_05 <- dyads_18_05[mdy>="2018-05-01" & mdy<"2018-06-01",c("id","mdy","time_n","id_d",
                                                                  "sex","race_cat5","ed_cat","job_cat",
                                                                  "randomgroup3", "solo_obs",
                                                                  "num_lt_2min_cat_tw","cafe",
                                                                  "logodds_upd","predprob_upd")]
dyads_18_06 <- dyads_18_06[mdy>="2018-06-01" & mdy<"2018-07-01",c("id","mdy","time_n","id_d",
                                                                  "sex","race_cat5","ed_cat","job_cat",
                                                                  "randomgroup3", "solo_obs",
                                                                  "num_lt_2min_cat_tw","cafe",
                                                                  "logodds_upd","predprob_upd")]
dyads_18_07 <- dyads_18_07[mdy>="2018-07-01" & mdy<"2018-08-01",c("id","mdy","time_n","id_d",
                                                                  "sex","race_cat5","ed_cat","job_cat",
                                                                  "randomgroup3", "solo_obs",
                                                                  "num_lt_2min_cat_tw","cafe",
                                                                  "logodds_upd","predprob_upd")]
dyads_18_08 <- dyads_18_08[mdy>="2018-08-01" & mdy<"2018-09-01",c("id","mdy","time_n","id_d",
                                                                  "sex","race_cat5","ed_cat","job_cat",
                                                                  "randomgroup3", "solo_obs",
                                                                  "num_lt_2min_cat_tw","cafe",
                                                                  "logodds_upd","predprob_upd")]
dyads_18_09 <- dyads_18_09[mdy>="2018-09-01" & mdy<"2018-10-01",c("id","mdy","time_n","id_d",
                                                                  "sex","race_cat5","ed_cat","job_cat",
                                                                  "randomgroup3", "solo_obs",
                                                                  "num_lt_2min_cat_tw","cafe",
                                                                  "logodds_upd","predprob_upd")]

## segment 5: Months 25-30 (Oct1 18-Mar31 19) 
# read data for tie probability prediction
gc() #clear up free RStudio memory
load("dyads_1511_1912u_monthly_tie_prob_m25_m26.Rdata")
load("dyads_1511_1912u_monthly_tie_prob_m27_m28.Rdata")
load("dyads_1511_1912u_monthly_tie_prob_m29_m30.Rdata")

dyads_19_03[ , num_lt_2min_cat_tw := fcase(
  dup_19_03 == 1, 0.933120514, 
  dup_19_03 == 2, 0.817687813,
  dup_19_03 == 3, 1.609523574,
  dup_19_03 >= 4, 4.72763085,
  default = 0
)]

dyads_19_02[ , num_lt_2min_cat_tw := fcase(
  dup_19_02 == 1, 0.933120514, 
  dup_19_02 == 2, 0.817687813,
  dup_19_02 == 3, 1.609523574,
  dup_19_02 >= 4, 4.72763085,
  default = 0
)]

dyads_19_01[ , num_lt_2min_cat_tw := fcase(
  dup_19_01 == 1, 0.933120514, 
  dup_19_01 == 2, 0.817687813,
  dup_19_01 == 3, 1.609523574,
  dup_19_01 >= 4, 4.72763085,
  default = 0
)]

dyads_18_12[ , num_lt_2min_cat_tw := fcase(
  dup_18_12 == 1, 0.933120514, 
  dup_18_12 == 2, 0.817687813,
  dup_18_12 == 3, 1.609523574,
  dup_18_12 >= 4, 4.72763085,
  default = 0
)]

dyads_18_11[ , num_lt_2min_cat_tw := fcase(
  dup_18_11 == 1, 0.933120514, 
  dup_18_11 == 2, 0.817687813,
  dup_18_11 == 3, 1.609523574,
  dup_18_11 >= 4, 4.72763085,
  default = 0
)]

dyads_18_10[ , num_lt_2min_cat_tw := fcase(
  dup_18_10 == 1, 0.933120514, 
  dup_18_10 == 2, 0.817687813,
  dup_18_10 == 3, 1.609523574,
  dup_18_10 >= 4, 4.72763085,
  default = 0
)]

dyads_19_03[ , logodds_upd := -5.490030491 + gender_match_coeff + agediffcat5_coeff + race_match_coeff + dept_match_coeff + job_cat_match_coeff + num_lt_2min_cat_tw]
dyads_19_03[ , predprob_upd := (exp(logodds_upd))/(1+exp(logodds_upd))]

dyads_19_02[ , logodds_upd := -5.490030491 + gender_match_coeff + agediffcat5_coeff + race_match_coeff + dept_match_coeff + job_cat_match_coeff + num_lt_2min_cat_tw]
dyads_19_02[ , predprob_upd := (exp(logodds_upd))/(1+exp(logodds_upd))]

dyads_19_01[ , logodds_upd := -5.490030491 + gender_match_coeff + agediffcat5_coeff + race_match_coeff + dept_match_coeff + job_cat_match_coeff + num_lt_2min_cat_tw]
dyads_19_01[ , predprob_upd := (exp(logodds_upd))/(1+exp(logodds_upd))]

dyads_18_12[ , logodds_upd := -5.490030491 + gender_match_coeff + agediffcat5_coeff + race_match_coeff + dept_match_coeff + job_cat_match_coeff + num_lt_2min_cat_tw]
dyads_18_12[ , predprob_upd := (exp(logodds_upd))/(1+exp(logodds_upd))]

dyads_18_11[ , logodds_upd := -5.490030491 + gender_match_coeff + agediffcat5_coeff + race_match_coeff + dept_match_coeff + job_cat_match_coeff + num_lt_2min_cat_tw]
dyads_18_11[ , predprob_upd := (exp(logodds_upd))/(1+exp(logodds_upd))]

dyads_18_10[ , logodds_upd := -5.490030491 + gender_match_coeff + agediffcat5_coeff + race_match_coeff + dept_match_coeff + job_cat_match_coeff + num_lt_2min_cat_tw]
dyads_18_10[ , predprob_upd := (exp(logodds_upd))/(1+exp(logodds_upd))]

dyads_18_10 <- dyads_18_10[mdy>="2018-10-01" & mdy<"2018-11-01",c("id","mdy","time_n","id_d",
                                                                  "sex","race_cat5","ed_cat","job_cat",
                                                                  "randomgroup3", "solo_obs",
                                                                  "num_lt_2min_cat_tw","cafe",
                                                                  "logodds_upd","predprob_upd")]
dyads_18_11 <- dyads_18_11[mdy>="2018-11-01" & mdy<"2018-12-01",c("id","mdy","time_n","id_d",
                                                                  "sex","race_cat5","ed_cat","job_cat",
                                                                  "randomgroup3", "solo_obs",
                                                                  "num_lt_2min_cat_tw","cafe",
                                                                  "logodds_upd","predprob_upd")]
dyads_18_12 <- dyads_18_12[mdy>="2018-12-01" & mdy<"2019-01-01",c("id","mdy","time_n","id_d",
                                                                  "sex","race_cat5","ed_cat","job_cat",
                                                                  "randomgroup3", "solo_obs",
                                                                  "num_lt_2min_cat_tw","cafe",
                                                                  "logodds_upd","predprob_upd")]
dyads_19_01 <- dyads_19_01[mdy>="2019-01-01" & mdy<"2019-02-01",c("id","mdy","time_n","id_d",
                                                                  "sex","race_cat5","ed_cat","job_cat",
                                                                  "randomgroup3", "solo_obs",
                                                                  "num_lt_2min_cat_tw","cafe",
                                                                  "logodds_upd","predprob_upd")]
dyads_19_02 <- dyads_19_02[mdy>="2019-02-01" & mdy<"2019-03-01",c("id","mdy","time_n","id_d",
                                                                  "sex","race_cat5","ed_cat","job_cat",
                                                                  "randomgroup3", "solo_obs",
                                                                  "num_lt_2min_cat_tw","cafe",
                                                                  "logodds_upd","predprob_upd")]
dyads_19_03 <- dyads_19_03[mdy>="2019-03-01" & mdy<"2019-04-01",c("id","mdy","time_n","id_d",
                                                                  "sex","race_cat5","ed_cat","job_cat",
                                                                  "randomgroup3", "solo_obs",
                                                                  "num_lt_2min_cat_tw","cafe",
                                                                  "logodds_upd","predprob_upd")]

## segment 6: Months 31-36 (Apr1 19-Sept30 19)
# read data for tie probability prediction
gc() #clear up free RStudio memory
load("dyads_1511_1912u_monthly_tie_prob_m31_m32.Rdata")
load("dyads_1511_1912u_monthly_tie_prob_m33_m34.Rdata")
load("dyads_1511_1912u_monthly_tie_prob_m35_m36.Rdata")

dyads_19_09[ , num_lt_2min_cat_tw := fcase(
  dup_19_09 == 1, 0.933120514, 
  dup_19_09 == 2, 0.817687813,
  dup_19_09 == 3, 1.609523574,
  dup_19_09 >= 4, 4.72763085,
  default = 0
)]

dyads_19_08[ , num_lt_2min_cat_tw := fcase(
  dup_19_08 == 1, 0.933120514, 
  dup_19_08 == 2, 0.817687813,
  dup_19_08 == 3, 1.609523574,
  dup_19_08 >= 4, 4.72763085,
  default = 0
)]

dyads_19_07[ , num_lt_2min_cat_tw := fcase(
  dup_19_07 == 1, 0.933120514, 
  dup_19_07 == 2, 0.817687813,
  dup_19_07 == 3, 1.609523574,
  dup_19_07 >= 4, 4.72763085,
  default = 0
)]

dyads_19_06[ , num_lt_2min_cat_tw := fcase(
  dup_19_06 == 1, 0.933120514, 
  dup_19_06 == 2, 0.817687813,
  dup_19_06 == 3, 1.609523574,
  dup_19_06 >= 4, 4.72763085,
  default = 0
)]

dyads_19_05[ , num_lt_2min_cat_tw := fcase(
  dup_19_05 == 1, 0.933120514, 
  dup_19_05 == 2, 0.817687813,
  dup_19_05 == 3, 1.609523574,
  dup_19_05 >= 4, 4.72763085,
  default = 0
)]

dyads_19_04[ , num_lt_2min_cat_tw := fcase(
  dup_19_04 == 1, 0.933120514, 
  dup_19_04 == 2, 0.817687813,
  dup_19_04 == 3, 1.609523574,
  dup_19_04 >= 4, 4.72763085,
  default = 0
)]

dyads_19_09[ , logodds_upd := -5.490030491 + gender_match_coeff + agediffcat5_coeff + race_match_coeff + dept_match_coeff + job_cat_match_coeff + num_lt_2min_cat_tw]
dyads_19_09[ , predprob_upd := (exp(logodds_upd))/(1+exp(logodds_upd))]

dyads_19_08[ , logodds_upd := -5.490030491 + gender_match_coeff + agediffcat5_coeff + race_match_coeff + dept_match_coeff + job_cat_match_coeff + num_lt_2min_cat_tw]
dyads_19_08[ , predprob_upd := (exp(logodds_upd))/(1+exp(logodds_upd))]

dyads_19_07[ , logodds_upd := -5.490030491 + gender_match_coeff + agediffcat5_coeff + race_match_coeff + dept_match_coeff + job_cat_match_coeff + num_lt_2min_cat_tw]
dyads_19_07[ , predprob_upd := (exp(logodds_upd))/(1+exp(logodds_upd))]

dyads_19_06[ , logodds_upd := -5.490030491 + gender_match_coeff + agediffcat5_coeff + race_match_coeff + dept_match_coeff + job_cat_match_coeff + num_lt_2min_cat_tw]
dyads_19_06[ , predprob_upd := (exp(logodds_upd))/(1+exp(logodds_upd))]

dyads_19_05[ , logodds_upd := -5.490030491 + gender_match_coeff + agediffcat5_coeff + race_match_coeff + dept_match_coeff + job_cat_match_coeff + num_lt_2min_cat_tw]
dyads_19_05[ , predprob_upd := (exp(logodds_upd))/(1+exp(logodds_upd))]

dyads_19_04[ , logodds_upd := -5.490030491 + gender_match_coeff + agediffcat5_coeff + race_match_coeff + dept_match_coeff + job_cat_match_coeff + num_lt_2min_cat_tw]
dyads_19_04[ , predprob_upd := (exp(logodds_upd))/(1+exp(logodds_upd))]

dyads_19_04 <- dyads_19_04[mdy>="2019-04-01" & mdy<"2019-05-01",c("id","mdy","time_n","id_d",
                                                                  "sex","race_cat5","ed_cat","job_cat",
                                                                  "randomgroup3", "solo_obs",
                                                                  "num_lt_2min_cat_tw","cafe",
                                                                  "logodds_upd","predprob_upd")]
dyads_19_05 <- dyads_19_05[mdy>="2019-05-01" & mdy<"2019-06-01",c("id","mdy","time_n","id_d",
                                                                  "sex","race_cat5","ed_cat","job_cat",
                                                                  "randomgroup3", "solo_obs",
                                                                  "num_lt_2min_cat_tw","cafe",
                                                                  "logodds_upd","predprob_upd")]
dyads_19_06 <- dyads_19_06[mdy>="2019-06-01" & mdy<"2019-07-01",c("id","mdy","time_n","id_d",
                                                                  "sex","race_cat5","ed_cat","job_cat",
                                                                  "randomgroup3", "solo_obs",
                                                                  "num_lt_2min_cat_tw","cafe",
                                                                  "logodds_upd","predprob_upd")]
dyads_19_07 <- dyads_19_07[mdy>="2019-07-01" & mdy<"2019-08-01",c("id","mdy","time_n","id_d",
                                                                  "sex","race_cat5","ed_cat","job_cat",
                                                                  "randomgroup3", "solo_obs",
                                                                  "num_lt_2min_cat_tw","cafe",
                                                                  "logodds_upd","predprob_upd")]
dyads_19_08 <- dyads_19_08[mdy>="2019-08-01" & mdy<"2019-09-01",c("id","mdy","time_n","id_d",
                                                                  "sex","race_cat5","ed_cat","job_cat",
                                                                  "randomgroup3", "solo_obs",
                                                                  "num_lt_2min_cat_tw","cafe",
                                                                  "logodds_upd","predprob_upd")]
dyads_19_09 <- dyads_19_09[mdy>="2019-09-01" & mdy<"2019-10-01",c("id","mdy","time_n","id_d",
                                                                  "sex","race_cat5","ed_cat","job_cat",
                                                                  "randomgroup3", "solo_obs",
                                                                  "num_lt_2min_cat_tw","cafe",
                                                                  "logodds_upd","predprob_upd")]

## segment 7: Months 37-42 (Oct1 19-Mar31 20)
# read data for tie probability prediction
gc() #clear up free RStudio memory
load("dyads_1511_1912u_monthly_tie_prob_m37_m38.Rdata")
load("dyads_1511_1912u_monthly_tie_prob_m39_m40.Rdata")
load("dyads_1511_1912u_monthly_tie_prob_m41_m42.Rdata")

dyads_20_03[ , num_lt_2min_cat_tw := fcase(
  dup_20_03 == 1, 0.933120514, 
  dup_20_03 == 2, 0.817687813,
  dup_20_03 == 3, 1.609523574,
  dup_20_03 >= 4, 4.72763085,
  default = 0
)]

dyads_20_02[ , num_lt_2min_cat_tw := fcase(
  dup_20_02 == 1, 0.933120514, 
  dup_20_02 == 2, 0.817687813,
  dup_20_02 == 3, 1.609523574,
  dup_20_02 >= 4, 4.72763085,
  default = 0
)]

dyads_20_01[ , num_lt_2min_cat_tw := fcase(
  dup_20_01 == 1, 0.933120514, 
  dup_20_01 == 2, 0.817687813,
  dup_20_01 == 3, 1.609523574,
  dup_20_01 >= 4, 4.72763085,
  default = 0
)]

dyads_19_12[ , num_lt_2min_cat_tw := fcase(
  dup_19_12 == 1, 0.933120514, 
  dup_19_12 == 2, 0.817687813,
  dup_19_12 == 3, 1.609523574,
  dup_19_12 >= 4, 4.72763085,
  default = 0
)]

dyads_19_11[ , num_lt_2min_cat_tw := fcase(
  dup_19_11 == 1, 0.933120514, 
  dup_19_11 == 2, 0.817687813,
  dup_19_11 == 3, 1.609523574,
  dup_19_11 >= 4, 4.72763085,
  default = 0
)]

dyads_19_10[ , num_lt_2min_cat_tw := fcase(
  dup_19_10 == 1, 0.933120514, 
  dup_19_10 == 2, 0.817687813,
  dup_19_10 == 3, 1.609523574,
  dup_19_10 >= 4, 4.72763085,
  default = 0
)]

dyads_20_03[ , logodds_upd := -5.490030491 + gender_match_coeff + agediffcat5_coeff + race_match_coeff + dept_match_coeff + job_cat_match_coeff + num_lt_2min_cat_tw]
dyads_20_03[ , predprob_upd := (exp(logodds_upd))/(1+exp(logodds_upd))]

dyads_20_02[ , logodds_upd := -5.490030491 + gender_match_coeff + agediffcat5_coeff + race_match_coeff + dept_match_coeff + job_cat_match_coeff + num_lt_2min_cat_tw]
dyads_20_02[ , predprob_upd := (exp(logodds_upd))/(1+exp(logodds_upd))]

dyads_20_01[ , logodds_upd := -5.490030491 + gender_match_coeff + agediffcat5_coeff + race_match_coeff + dept_match_coeff + job_cat_match_coeff + num_lt_2min_cat_tw]
dyads_20_01[ , predprob_upd := (exp(logodds_upd))/(1+exp(logodds_upd))]

dyads_19_12[ , logodds_upd := -5.490030491 + gender_match_coeff + agediffcat5_coeff + race_match_coeff + dept_match_coeff + job_cat_match_coeff + num_lt_2min_cat_tw]
dyads_19_12[ , predprob_upd := (exp(logodds_upd))/(1+exp(logodds_upd))]

dyads_19_11[ , logodds_upd := -5.490030491 + gender_match_coeff + agediffcat5_coeff + race_match_coeff + dept_match_coeff + job_cat_match_coeff + num_lt_2min_cat_tw]
dyads_19_11[ , predprob_upd := (exp(logodds_upd))/(1+exp(logodds_upd))]

dyads_19_10[ , logodds_upd := -5.490030491 + gender_match_coeff + agediffcat5_coeff + race_match_coeff + dept_match_coeff + job_cat_match_coeff + num_lt_2min_cat_tw]
dyads_19_10[ , predprob_upd := (exp(logodds_upd))/(1+exp(logodds_upd))]

dyads_19_10 <- dyads_19_10[mdy>="2019-10-01" & mdy<"2019-11-01",c("id","mdy","time_n","id_d",
                                                                  "sex","race_cat5","ed_cat","job_cat",
                                                                  "randomgroup3", "solo_obs",
                                                                  "num_lt_2min_cat_tw","cafe",
                                                                  "logodds_upd","predprob_upd")]
dyads_19_11 <- dyads_19_11[mdy>="2019-11-01" & mdy<"2019-12-01",c("id","mdy","time_n","id_d",
                                                                  "sex","race_cat5","ed_cat","job_cat",
                                                                  "randomgroup3", "solo_obs",
                                                                  "num_lt_2min_cat_tw","cafe",
                                                                  "logodds_upd","predprob_upd")]
dyads_19_12 <- dyads_19_12[mdy>="2019-12-01" & mdy<"2020-01-01",c("id","mdy","time_n","id_d",
                                                                  "sex","race_cat5","ed_cat","job_cat",
                                                                  "randomgroup3", "solo_obs",
                                                                  "num_lt_2min_cat_tw","cafe",
                                                                  "logodds_upd","predprob_upd")]
dyads_20_01 <- dyads_20_01[mdy>="2020-01-01" & mdy<"2020-02-01",c("id","mdy","time_n","id_d",
                                                                  "sex","race_cat5","ed_cat","job_cat",
                                                                  "randomgroup3", "solo_obs",
                                                                  "num_lt_2min_cat_tw","cafe",
                                                                  "logodds_upd","predprob_upd")]
dyads_20_02 <- dyads_20_02[mdy>="2020-02-01" & mdy<"2020-03-01",c("id","mdy","time_n","id_d",
                                                                  "sex","race_cat5","ed_cat","job_cat",
                                                                  "randomgroup3", "solo_obs",
                                                                  "num_lt_2min_cat_tw","cafe",
                                                                  "logodds_upd","predprob_upd")]
dyads_20_03 <- dyads_20_03[mdy>="2020-03-01" & mdy<"2020-04-01",c("id","mdy","time_n","id_d",
                                                                  "sex","race_cat5","ed_cat","job_cat",
                                                                  "randomgroup3", "solo_obs",
                                                                  "num_lt_2min_cat_tw","cafe",
                                                                  "logodds_upd","predprob_upd")]

### We then merge the new monthly 
dyads_tie_probability_upd <- rbind(dyads_16_04, dyads_16_05, dyads_16_06,
                                   dyads_16_07, dyads_16_08, dyads_16_09,
                                   dyads_16_10, dyads_16_11, dyads_16_12,
                                   dyads_17_01, dyads_17_02, dyads_17_03,
                                   dyads_17_04, dyads_17_05, dyads_17_06,
                                   dyads_17_07, dyads_17_08, dyads_17_09,
                                   dyads_17_10, dyads_17_11, dyads_17_12,
                                   dyads_18_01, dyads_18_02, dyads_18_03,
                                   dyads_18_04, dyads_18_05, dyads_18_06,
                                   dyads_18_07, dyads_18_08, dyads_18_09,
                                   dyads_18_10, dyads_18_11, dyads_18_12,
                                   dyads_19_01, dyads_19_02, dyads_19_03,
                                   dyads_19_04, dyads_19_05, dyads_19_06,
                                   dyads_19_07, dyads_19_08, dyads_19_09,
                                   dyads_19_10, dyads_19_11, dyads_19_12,
                                   dyads_20_01, dyads_20_02, dyads_20_03,
                                   use.names=FALSE)

dyads_tie_probability_upd$Month_Yr <- format(as.Date(dyads_tie_probability_upd$mdy), "%Y-%m")

## this data object stores month-specific tie probability for each pair between 2016-4 and 2020-03 
range(dyads_tie_probability_upd$Month_Yr)
saveRDS(dyads_tie_probability_upd, file = "dyads_tie_probability_upd_v1.RDS")
gc() #clear free Rstudio memory

rm(dyads_16_04, dyads_16_05, dyads_16_06,
   dyads_16_07, dyads_16_08, dyads_16_09,
   dyads_16_10, dyads_16_11, dyads_16_12,
   dyads_17_01, dyads_17_02, dyads_17_03,
   dyads_17_04, dyads_17_05, dyads_17_06,
   dyads_17_07, dyads_17_08, dyads_17_09,
   dyads_17_10, dyads_17_11, dyads_17_12,
   dyads_18_01, dyads_18_02, dyads_18_03,
   dyads_18_04, dyads_18_05, dyads_18_06,
   dyads_18_07, dyads_18_08, dyads_18_09,
   dyads_18_10, dyads_18_11, dyads_18_12,
   dyads_19_01, dyads_19_02, dyads_19_03,
   dyads_19_04, dyads_19_05, dyads_19_06,
   dyads_19_07, dyads_19_08, dyads_19_09,
   dyads_19_10, dyads_19_11, dyads_19_12,
   dyads_20_01, dyads_20_02, dyads_20_03)


############## 5. MERGE DYADIC DATA W/ TIE PROBABLILITY DATA #############
dyads_1511_1912u <- readRDS("/work/pi_mpachucki_umass_edu/food_projects/food_simulation_r01/data analytic/dyads_ntp_m.RDS")
dyads_1511_1912u[, .N,]  #count of cases (60057440)
dyads_tie_probability_upd_v1 <- readRDS("/work/pi_mpachucki_umass_edu/food_projects/food_simulation_r01/data analytic/1.5_6m lookback probability/dyads_tie_probability_upd_v1.RDS")
dyads_tie_probability_upd_v1[, .N,]  #count of cases (26249214)
gc() #clear free memory

#for this threshold analysis of only high-probability ties (e.g., ≥0.6), we're going to 
#bring in just the high-prob dyad subset)
#dyads_tie_probability_upd <- subset.data.frame(dyads_tie_probability_upd, predprob_upd>=0.6) 

## note: this tie probability is a month-based measure, therefore, dyads in a given month have the same probability
## To not duplicate mdy and time_n, we only read c("id", "id_d", "Month_Yr", "predprob_upd") in dyads_tie_probability_upd object
dyads_1511_1912u_upd <- left_join(dyads_1511_1912u, 
                                  dyads_tie_probability_upd_v1[,c("id", "id_d", "Month_Yr", "predprob_upd")], 
                                  by = c("id","id_d","Month_Yr"))
dim(unique(dyads_1511_1912u_upd, by = "id")) ## 8725 egos

rm(dyads_1511_1912u)
rm(dyads_tie_probability_upd_v1)
setwd("/work/pi_mpachucki_umass_edu/food_projects/food_simulation_r01/data analytic/1.5_6m lookback probability")
saveRDS(dyads_1511_1912u_upd, file = "dyads_1511_1912u_upd.RDS")

############## 6. OBTAIN EGO-LEVEL FOOD DATA (precise) - YEARLY  #################################
#version 2 (more precise, based on yearly data)
#codes up dyadic food data from scratch to yearly level
#and ignores entry-into trial data entirely.
#does not attempt to build a panel data structure

#read in data (all month dyadic data with tie probabilities)
dyads_1511_1912u_upd <- readRDS("dyads_1511_1912u_upd.RDS")
dyads_1511_1912u_upd[, .N,]  #count of cases (60057440)
setDT(dyads_1511_1912u_upd)
gc()  #clear unused memory for Unity not to crash

id_dates = dyads_1511_1912u_upd[, .(
  min  = min(mdy, na.rm = TRUE),
  max  = max(mdy, na.rm = TRUE)
), by = id]

gc()  #clear unused memory for Unity not to crash

#exclude dyads from 2015 and 2020
#generate year variable
dyads_1511_1912u_upd[, year := fifelse(Month_Yr >= "2015-01" & Month_Yr <= "2015-12", 2015,
                                       fifelse(Month_Yr >= "2016-01" & Month_Yr <= "2016-12", 2016,
                                               fifelse(Month_Yr >= "2017-01" & Month_Yr <= "2017-12", 2017,
                                                       fifelse(Month_Yr >= "2018-01" & Month_Yr <= "2018-12", 2018,
                                                               fifelse(Month_Yr >= "2019-01" & Month_Yr <= "2019-12", 2019,
                                                                       fifelse(Month_Yr >= "2020-01" & Month_Yr <= "2020-03", 2020, NA_integer_))))))]


dyads_1511_1912u_upd_dvs <- dyads_1511_1912u_upd[year %in% 2016:2019]
dyads_1511_1912u_upd_dvs[, .N,]  #count of cases (57625396)
dyads_1511_1912u_upd_dvs[, .N, by=year]  #inspect dropped cases for descriptive purposes

# 
# year        N
# <num>    <int>
# 1:  2016 15788114
# 2:  2017 15013123
# 3:  2018 13416026
# 4:  2019 13408133

## The dyads_1511_1912u_upd object keeps multiple ego-alter co-purchases in one occasion,
## which means we would see three ego purchase records at the same time if they connected to
## three alters within +/- 2 mins. We thus need to deduplicate dyadic co-purchasing by ignoring
## # of alters egos connected to, so that each row corresponds to one ego's purchase of a item type.
## We don't want to simplify to the purchase occasion per row, otherwise we lose ability to parse
## food vs. bev. 
dyads_1511_1912u_upd_dvs <- (unique
                             (dyads_1511_1912u_upd, 
                               by = c("id","mdy","time_n","item_type","cw_grp","RYG","kcal")))
dyads_1511_1912u_upd_dvs[, .N,]  #count of cases (6946768), note that it includes 2015 lookback #s
# dyads_1511_1912u_upd_dvs <- dyads_1511_1912u_upd[year %in% 2016:2019]
dyads_1511_1912u_upd_dvs[, .N,by=year]  #count of cases (6946768), note that it includes 2015 lookback #s

# year       N
# <num>   <int>
# 1:  2015  270196
# 2:  2016 1805779
# 3:  2017 1771970
# 4:  2018 1543080
# 5:  2019 1555743

#this reduces the data object from n=57625396 to n=6946768 obs.
#note: 'unique' just keeps the first id_d if there were multiple alters, 
#but we just keep id_d in here for diagnostic purposes,
#not because we're interested in alter purchases with this object. 

# adjust timestamp vars to be useful format
dyads_1511_1912u_upd_dvs <- dyads_1511_1912u_upd_dvs[, timestamp := as.POSIXct(paste(mdy, strftime(time_n, format="%H:%M:%S", tz = "GMT")),
                                                                               format="%Y-%m-%d %H:%M:%S") ]
dyads_1511_1912u_upd_dvs <- dyads_1511_1912u_upd_dvs[, timestamp_d := as.POSIXct(paste(mdy, strftime(time_n_d, format="%H:%M:%S", tz = "GMT")),
                                                                                 format="%Y-%m-%d %H:%M:%S") ]
dyads_1511_1912u_upd_dvs <- dyads_1511_1912u_upd_dvs[, Month_Yr_check := format(as.Date(timestamp), "%Y-%m")]
gc()  #clear unused memory for Unity not to crash

# subset selected covars (n=12 vars)
dyads_foodsubset <- dyads_1511_1912u_upd_dvs[, .(
  id, id_d, mdy, Month_Yr, time_n,
  item_type, timestamp, year,
  tt_items, cw_grp, RYG, kcal
)]

#drop any rows that are pre-intervention or 2020
setDT(dyads_foodsubset)
dyads_foodsubset <- dyads_foodsubset[ !is.na(year) ] 
dyads_foodsubset <- dyads_foodsubset[ year!=2015] 
dyads_foodsubset <- dyads_foodsubset[ year!=2020] 
dyads_foodsubset[, .N,]  #count of cases (6676572)

#verify they're all between 2016-01-01 and 2019-12-31
id_dates = dyads_foodsubset[, .(
  min  = min(mdy, na.rm = TRUE),
  max  = max(mdy, na.rm = TRUE)
), by = id]
id_dates[, .N,]  #count of cases (6676572)
gc()  #clear unused memory for Unity not to crash
rm(id_dates)

# #verify id=16,id=144 
# ex_alldyad <- dyads_foodsubset[dyads_foodsubset$id == 16 | dyads_foodsubset$id == 144 ]
# ex_occadyad <- dyads_1511_1912u_upd[dyads_1511_1912u_upd$id == 16 | dyads_1511_1912u_upd$id == 144 ]
rm(dyads_1511_1912u_upd)

save.image(paste("FoodData_Yearly_v1.5_6mlookback",Sys.Date(),".Rdata", sep = ""))


## PREPARE PROPORTION OF COMBINED (FOOD+BEV) PURCHASE VARIABLES FOR EGOS BY YEAR
# this is different than SSM project, where we prepared by ego-month.
## set panel data for observed purchases (separate food & bev)
setwd("/work/pi_mpachucki_umass_edu/food_projects/food_simulation_r01/data analytic/1.5_6m lookback probability")

#create object that rolls up dyads to yearly observed purchases
#here, suffix "pty" is "per type within year"
dyads_1511_1912pty <- dyads_1511_1912u_upd_dvs[
  , .(purchase = sum(tt_items)), by = .(id, year, RYG, item_type)
][
  , .(
    RYG = as.factor(RYG),
    tot = sum(purchase),
    pctpurchase = purchase / sum(purchase)
  ), by = .(id, year, item_type)
]

# create object that rolls up dyads to yearly observed purchases
# here, suffix "cty" is "combined types within year" (food + bevs)
dyads_1511_1912cty <- dyads_1511_1912u_upd_dvs[
  , .(purchase = sum(tt_items)), by = .(id, year, RYG)
][
  , .(
    RYG = as.factor(RYG),
    tot = sum(purchase),
    pctpurchase = purchase / sum(purchase)
  ), by = .(id, year)
]
## keep pctpurchase for food models
subtest_foods_t <- dyads_1511_1912pty[item_type=="food",]
count(subtest_foods_t)

## keep pctpurchase for beverage models
subtest_bev_t <- dyads_1511_1912pty[item_type=="bev",]
count(subtest_bev_t)

## The following datasets are generated for merging back to the master data
## keep pctpurchase for green food models
subtest_gf_t <- dyads_1511_1912pty[RYG == "G" & item_type=="food",]
count(subtest_gf_t)

## keep pctpurchase for red food models
subtest_rf_t <- dyads_1511_1912pty[RYG == "R" & item_type=="food",]
count(subtest_rf_t)

## keep pctpurchase for yellow food models
subtest_yf_t <- dyads_1511_1912pty[RYG == "Y" & item_type=="food",]
count(subtest_yf_t)

## keep pctpurchase for green bev models
subtest_gb_t <- dyads_1511_1912pty[RYG == "G" & item_type=="bev",]
count(subtest_gb_t)

## keep pctpurchase for red bev models
subtest_rb_t <- dyads_1511_1912pty[RYG == "R" & item_type=="bev",]
count(subtest_rb_t)

## keep pctpurchase for yellow bev models
subtest_yb_t <- dyads_1511_1912pty[RYG == "Y" & item_type=="bev",]
count(subtest_yb_t)

## rename pctpurchase colnames for each models
setnames(subtest_gf_t, "pctpurchase", "pctpurchase_gf_t")
setnames(subtest_rf_t, "pctpurchase", "pctpurchase_rf_t")
setnames(subtest_yf_t, "pctpurchase", "pctpurchase_yf_t")
setnames(subtest_gb_t, "pctpurchase", "pctpurchase_gb_t")
setnames(subtest_rb_t, "pctpurchase", "pctpurchase_rb_t")
setnames(subtest_yb_t, "pctpurchase", "pctpurchase_yb_t")


## The following datasets are generated for merging back to the master data
## keep pctpurchase for green food models
subtest_g_ct <- dyads_1511_1912cty[RYG == "G",]
count(subtest_g_ct)

## keep pctpurchase for red food models
subtest_r_ct <- dyads_1511_1912cty[RYG == "R",]
count(subtest_r_ct)

## keep pctpurchase for yellow food models
subtest_y_ct <- dyads_1511_1912cty[RYG == "Y",]
count(subtest_y_ct)

## rename pctpurchase colnames for each models
setnames(subtest_g_ct, "pctpurchase", "pctpurchase_g_ct")
setnames(subtest_r_ct, "pctpurchase", "pctpurchase_r_ct")
setnames(subtest_y_ct, "pctpurchase", "pctpurchase_y_ct")

## Created a balanced dataframe (8622 egos x 4 years)
unbalanced.panel <- dyads_foodsubset[, .(count = .N), by = c("id","year")]
apply(unbalanced.panel, 2, function(x) any(is.na(x)))# there are no NA in this dataframe
is.pbalanced(unbalanced.panel) # check if it is a balanced panel (FALSE!)
unbalanced.panel[, time_id := as.numeric(year)]
balanced.panel <- make.pbalanced(unbalanced.panel, index=c('id','time_id'))
is.pbalanced(balanced.panel, index=c('id','time_id')) # check if it is a balanced panel (TRUE!)

setDT(balanced.panel)
balanced.panel[, purch := fifelse(is.na(year), 0, 1)]

# Set keys for joining (optional but makes repeated joins faster)
setkey(balanced.panel, id, year)
setkey(subtest_gf_t, id, year)
setkey(subtest_rf_t, id, year)
setkey(subtest_yf_t, id, year)
setkey(subtest_gb_t, id, year)
setkey(subtest_rb_t, id, year)
setkey(subtest_yb_t, id, year)
setkey(subtest_g_ct, id, year)
setkey(subtest_r_ct, id, year)
setkey(subtest_y_ct, id, year)

# Perform sequential left joins using merge()
master.panel <- merge(balanced.panel, subtest_gf_t[, .(id, year, pctpurchase_gf_t)], 
                      by = c("id", "year"), all.x = TRUE)
master.panel <- merge(master.panel, subtest_rf_t[, .(id, year, pctpurchase_rf_t)], 
                      by = c("id", "year"), all.x = TRUE)
master.panel <- merge(master.panel, subtest_yf_t[, .(id, year, pctpurchase_yf_t)], 
                      by = c("id", "year"), all.x = TRUE)
master.panel <- merge(master.panel, subtest_gb_t[, .(id, year, pctpurchase_gb_t)], 
                      by = c("id", "year"), all.x = TRUE)
master.panel <- merge(master.panel, subtest_rb_t[, .(id, year, pctpurchase_rb_t)], 
                      by = c("id", "year"), all.x = TRUE)
master.panel <- merge(master.panel, subtest_yb_t[, .(id, year, pctpurchase_yb_t)], 
                      by = c("id", "year"), all.x = TRUE)
master.panel <- merge(master.panel, subtest_g_ct[, .(id, year, pctpurchase_g_ct)], 
                      by = c("id", "year"), all.x = TRUE)
master.panel <- merge(master.panel, subtest_r_ct[, .(id, year, pctpurchase_r_ct)], 
                      by = c("id", "year"), all.x = TRUE)
master.panel <- merge(master.panel, subtest_y_ct[, .(id, year, pctpurchase_y_ct)], 
                      by = c("id", "year"), all.x = TRUE)
#treat master.panel as data.table
setDT(master.panel)

## b) Generate indicator to show "any food purchase in ego-year" to allow us
## to subset efficiently.
master.panel[, `:=`(
  purch_food = fifelse(is.na(pctpurchase_gf_t) & is.na(pctpurchase_rf_t) & is.na(pctpurchase_yf_t), 0, 1),
  purch_bev  = fifelse(is.na(pctpurchase_gb_t) & is.na(pctpurchase_rb_t) & is.na(pctpurchase_yb_t), 0, 1)
)]

#drop all 2020 observations
master.panel <- master.panel[ time_id!=2020]  #none here, took care of them earlier
master.panel$year = NULL

#relabel long-name vqrs!
setnames(master.panel, old=c('id', 'count', 'time_id', 'purch',
                             'pctpurchase_gf_t','pctpurchase_rf_t',
                             'pctpurchase_yf_t','pctpurchase_gb_t',
                             'pctpurchase_rb_t','pctpurchase_yb_t',
                             'pctpurchase_g_ct','pctpurchase_r_ct','pctpurchase_y_ct',
                             'purch_food','purch_bev'),
         new=c('id', 'ct', 'year', 'p','gf','rf','yf','gb','rb','yb',
               'g_ct','r_ct','y_ct', 'p_fd', 'p_bev'))

## Keep the original vars which have NA. Mutate new variables to impute zero
master.panel[, `:=`(
  gf_imp = fifelse(p_fd == 0, NA_real_, fifelse(is.na(gf), 0, gf)),
  rf_imp = fifelse(p_fd == 0, NA_real_, fifelse(is.na(rf), 0, rf)),
  yf_imp = fifelse(p_fd == 0, NA_real_, fifelse(is.na(yf), 0, yf)),
  gb_imp = fifelse(p_bev == 0, NA_real_, fifelse(is.na(gb), 0, gb)),
  rb_imp = fifelse(p_bev == 0, NA_real_, fifelse(is.na(rb), 0, rb)),
  yb_imp = fifelse(p_bev == 0, NA_real_, fifelse(is.na(yb), 0, yb))
)]

## impute zeros if foods have non-zero value but beverages are NA
master.panel[(p_bev==0 & p_fd==1), gb_imp := 0]
master.panel[(p_bev==0 & p_fd==1), yb_imp := 0]
master.panel[(p_bev==0 & p_fd==1), rb_imp := 0]
#spot-check: id 56795 (2016, 2018), 56810 (2016,17) should now=0 in [x]b_imp  

## impute zeros if beverages have non-zero values but foods are NA
master.panel[(p_fd==0 & p_bev==1), gf_imp := 0]
master.panel[(p_fd==0 & p_bev==1), yf_imp := 0]
master.panel[(p_fd==0 & p_bev==1), rf_imp := 0]
#spot-check: id 56951 (2019) should now=0 in [x]f_imp

master.panel[, `:=`(
  g_imp = fifelse(p == 0, NA, fifelse(is.na(g_ct), 0, g_ct)),
  r_imp = fifelse(p == 0, NA, fifelse(is.na(r_ct), 0, r_ct)),
  y_imp = fifelse(p == 0, NA, fifelse(is.na(y_ct), 0, y_ct))
)]

# PREPARE HEALTHY PURCHASING SCORES
master.panel[, hps_t := 1 * g_imp + 0.5 * y_imp + 0 * r_imp]
master.panel[, hps_t_100 := 100 * hps_t]

# PREPARE KCAL OUTCOMES
# (1) Entrees measure: retain "occasions" which include where there's meals >= 1 entrees included
## select all timestamp where there is at least one entrees
ts_entree = dyads_foodsubset[cw_grp == "entrée", .(id, timestamp)]
ts_entree = unique(ts_entree)
ts_entree[, kcal_entree := 1]

kcal_occa_entree = ts_entree[dyads_foodsubset, on = .(id, timestamp)]
kcal_occa_entree = kcal_occa_entree[kcal_entree == 1, .(id, mdy, time_n, year, kcal, tt_items, timestamp, cw_grp, RYG)]

kcal_occa_entree = kcal_occa_entree[, .(
  occa_kcal_entree = sum(kcal), 
  active_occa_entree = uniqueN(timestamp)
), by = .(id, year)]
kcal_occa_entree[, avg_kcal_occa_entree := occa_kcal_entree/active_occa_entree]

kcal_occa_entree[, id := as.character(id)]
master.panel[, id := as.character(id)]

master.panel <- kcal_occa_entree[master.panel, on = .(id, year)]

## (2) Active purchasing days in the year approach: average kCal in a day that 
#they made a purchase
kcal_year <- dyads_foodsubset[, .(id, mdy, time_n, year, kcal, tt_items)]
kcal_year = kcal_year[, .(
  year_kcal = sum(kcal), 
  active_days = uniqueN(mdy)
), by = .(id, year)]
kcal_year[, avg_kcal_days := year_kcal/active_days]
kcal_year[, id := as.character(id)]
master.panel[, id := as.character(id)]
master.panel <- kcal_year[master.panel, on = .(id, year)]

############## 6a DIAGNOSTICS #################################

#build occasion-level kcal measure, just to rule out non-entree purchases
#THIS IS JUST for diagnostic purposes. 
kcal_occa = dyads_foodsubset [, 
                              .(id, mdy, time_n, year, kcal, tt_items, timestamp)
][,
  .(
    occa_kcal   = sum(kcal, na.rm = TRUE),
    active_occa = uniqueN(timestamp)
  ),
  by = .(id, year)
][
  , avg_kcal_occa := occa_kcal / active_occa
]

kcal_occa[, id := as.character(id)]

master.panel <- kcal_occa[master.panel, on = .(id, year)]

#build side-dish-level kcal measure, to rule out non-entree purchases
#THIS IS JUST FOR DIAGNOSTIC purposes
dyads_foodsubset[, .N, by=cw_grp] 
ts_othitem = unique(
  dyads_foodsubset[cw_grp %in% c("item/side", "condiment"), .(id, timestamp)]
)
ts_othitem[, kcal_othitem := 1]
kcal_occa_othitem = ts_othitem[dyads_foodsubset, on = .(id, timestamp)]
kcal_occa_othitem = kcal_occa_othitem[kcal_othitem == 1, .(id, mdy, time_n, year, kcal, tt_items, timestamp, cw_grp, RYG)]
kcal_occa_othitem = kcal_occa_othitem[,
                                      .(
                                        occa_kcal_othitems = sum(kcal), 
                                        active_occa_othitems = n_distinct(timestamp)
                                      ), by = .(id, year)
][,
  avg_kcal_occa_othitems := occa_kcal_othitems/active_occa_othitems
]

kcal_occa_othitem[, id := as.character(id)]
master.panel[, id := as.character(id)]
master.panel <- kcal_occa_othitem[master.panel, by = c("id", "year")]

#subset yearly panel for comparison with monthly roll-up
master.panel_year = master.panel[, .(id, year,
                                     gf_imp,rf_imp,yf_imp,
                                     gb_imp,rb_imp,yb_imp,
                                     p_fd,p_bev,
                                     hps_t_100,
                                     avg_kcal_days,avg_kcal_occa_entree)]

#relabel long-name vars!
setnames(master.panel_year, old=c('id', 'year',
                                  'gf_imp','rf_imp','yf_imp',
                                  'gb_imp','rb_imp','yb_imp',
                                  'p_fd','p_bev',
                                  'hps_t_100',
                                  'avg_kcal_days','avg_kcal_occa_entree'),
         new=c('id', 'year','gf','rf','yf','gb','rb','yb',
               'p_fd','p_bev','hps','kcal','kcal_ent'))

## flag if some type of color purchase is missing but others are there 
## e.g. GR but not Y; RY but not G; or GY but not R 
master.panel_year[, miss_col_fb := fifelse(
  (is.na(yf) & !is.na(gf) & !is.na(rf)) |
    (is.na(gf) & !is.na(rf) & !is.na(yf)) |
    (is.na(rf) & !is.na(gf) & !is.na(yf)) |
    (is.na(yb) & !is.na(gb) & !is.na(rb)) |
    (is.na(gb) & !is.na(rb) & !is.na(yb)) |
    (is.na(rb) & !is.na(gb) & !is.na(yb)), 
  1L, 0L)]

master.panel_year[, .N, by=miss_col_fb] #0 observations of 34488

#flag for missing kCal value, but there are def f/b values 
#(might just be they didn't purchase entrees!)
master.panel_year[, miss_kcal_fb := fifelse(
  (is.na(kcal) & p_fd == 1) | (is.na(kcal) & p_bev == 1), 
  1L, 0L
)]


#Q: how many observations are there w/missing kcal va when there are 
master.panel_year[, .N, by=miss_kcal_fb] #0 observations of 34488

#Q: how many are because they just had beverages but not food?
#(this means they're clearly missing entrees)
master.panel_year[, miss_kcal_b_only := fifelse(
  (is.na(kcal) & p_fd == 0 & p_bev == 1), 
  1L, 0L
)]
master.panel_year[, .N, by=miss_kcal_b_only] #0 observations of 34488

#Q: how many of those remaining 691 didn't purchase entrees?
#TBD (Mark 1/20/25)
master.panel[, miss_kcal_othitems := fifelse(
  is.na(avg_kcal_occa_entree) & !is.na(avg_kcal_occa_othitems), 
  1L, 0L
)]
master.panel[, .N, by=miss_kcal_othitems] #269 observations of 960
#n=538 didn't purchase entrees

#comparison between kCal (avg, based on purchasing days) & kcal (entrees per occasions) 
master.panel_year[, miss_kcal := fifelse(is.na(kcal_ent) & !is.na(kcal), 1L, 0L)]
master.panel_year[, .N, by=miss_kcal] #838 observations of 33650


############## 6b. RESHAPE DATA #################################
id_foodyear_w = master.panel_year
id_foodyear_w[, c("p_fd", "p_bev", "miss_kcal") := NULL]


#reshape long to wide
id_foodyear_w = dcast(
  id_foodyear_w, 
  id ~ year, 
  value.var = c("gf", "rf", "yf", "gb", "rb", "yb", "hps", "kcal", "kcal_ent")
)

#(1)How many people have data at all 4 points? (HPS)
missing_years = id_foodyear_w[, .(id,
                                  # min, max, group2
                                  hps_2016, hps_2017, hps_2018, hps_2019)]

missing_years[, freq_year_NA := as.factor(rowSums(is.na(.SD))), .SDcols = 2:5]
tabulate(missing_years$freq_year_NA)
# [1] 4771 1197 1443 1211

############## 6c. ADDITIONAL DIAGNOSTICS #################################
## flag exactly repeated values across kCal-years
id_foodyear_w[, yearly_dupes := fifelse((kcal_2016==kcal_2017) & 
                                          (kcal_2017==kcal_2018) & 
                                          (kcal_2018==kcal_2019), 1L, 0L)]
id_foodyear_w[, .N, by=yearly_dupes] #0 observations of 8622, though there are 1284 NAs
id_foodyear_w[, yearly_dupes := NULL]

#compare with rough monthly roll-up
id_foodmonth_w <- readRDS("/work/pi_mpachucki_umass_edu/food_projects/food_simulation_r01/id_datesfood_rev.RDS")
setDT(id_foodmonth_w)
id_dates = id_foodmonth_w[, .(id, min, max)]
id_foodmonth_w[, min := NULL]
id_foodmonth_w[, max := NULL]

#generate missing value dataframe 
missing <- id_foodyear_w[, lapply(.SD, function(x) sum(is.na(x)))]
names(missing)[1] <- "year_bydyad_v3"

#export RDS of missingness report (diagnostics)
saveRDS(missing, "foodmissingnesscomparison.RDS")

#merge datatable of food purchases with id on dates for joiners/leavers (39 vars)
id_datesfoodyear = merge(id_dates, id_foodyear_w, by="id", all.data=TRUE)

#export RDS of just ego-level monthly-aggregated-to-yearly purchases
saveRDS(id_datesfoodyear, "id_datesfoodyear_v3.RDS")

##inspect all kCal data
#read in
id_covars <- readRDS("id_covars.RDS")
trial_membership_u <- readRDS("trial_membership_u.RDS")
id_datesfoodyear <- readRDS("id_datesfoodyear.RDS")
setDT(id_covars)
setDT(trial_membership_u)
setDT(id_datesfoodyear)
#clean up extraneous vars
id_covars[, randomgroup := NULL]
id_datesfoodyear[, min := NULL]
id_datesfoodyear[, max := NULL]

#### 6d. merge in covariates with yearly food data  ####

#subset for key covariates
setDT(dyads_1511_1912u_upd_dvs)
dyads_covars<- dyads_1511_1912u_upd_dvs[, .(id, deptid, race_cat5, job_cat, sex,
                                            ed_cat,mdy)]
dyads_covars[, race_cat5 := as.factor(race_cat5)]
dyads_covars[, deptid := as.factor(deptid)]
dyads_covars[, job_cat := as.factor(job_cat)]
dyads_covars[, sex := as.factor(sex)]
dyads_covars[, ed_cat := as.factor(ed_cat)]

dyads_covars[, .N,by=race_cat5]


#group dyads down to the individual-employee level
# there are some employees with a job_cat that's NA in dyads_covars


id_covars = dyads_covars[, .(
  min  = min(mdy, na.rm = TRUE),
  max  = max(mdy, na.rm = TRUE)
), by = .(id, race_cat5, job_cat, sex, ed_cat)
][, .(
  job_cat2 = first(job_cat),
  race_cat2 = first(race_cat5),
  sex2 = first(sex),
  ed_cat2 = first(ed_cat),
  min2 = min(min),
  max2 = max(max)
), by = id]
id_covars[, .N,] #8622

#rename
names(id_covars)[2] <- "job_cat"
names(id_covars)[3] <- "race_cat"
names(id_covars)[4] <- "sex"
names(id_covars)[5] <- "ed_cat"
names(id_covars)[6] <- "min"
names(id_covars)[7] <- "max"

#inspect
id_covars[, .N, by=job_cat] #2 NAs of 8622, can't do anything about them
id_covars[, .N, by=race_cat] #0 NAs of 8622
id_covars[, .N, by=sex] #0 NAs of 8622
id_covars[, .N, by=ed_cat] #0 NAs of 8622, but need to relabel

levels(id_covars$ed_cat) <- c("HS or less", "Some college", 
                              "College", "Advanced", "Missing") #label the levels


#Exclusion 1: subset just the egos who are non-trial participants (NTP), coded NA
trial_membership_u <- readRDS("/work/pi_mpachucki_umass_edu/food_projects/food_simulation_r01/data analytic/trial_membership_u.RDS")
setDT(trial_membership_u)

id_covars <- trial_membership_u[id_covars, on = "id"]
id_covars[, .N, by=group_dup] #1=299, 2=303, NA=8123

# id_covars = id_datesfoodyear[id_covars, on = "id"]

#force the 2 NAs in job_cat to be a level b/c that's how table1 needs it
id_covars[ , job_cat2 := factor(
  ifelse(is.na(job_cat), "NoIdea", as.character(job_cat))
)]

id_covars[, group_dup := as.factor(group_dup)]
id_covars[ , group2 := factor(
  ifelse(is.na(group_dup), "NPE", as.character(group_dup))
)]
levels(id_covars$group2) <- c("Int","Ctl","NPE")
id_covars[, .N, by=group2] #Int=299, Ctl=303, NPE=8123

#inspect cross-tabs
label(id_covars$ed_cat)   <- "Education"
label(id_covars$job_cat)   <- "Job"
label(id_covars$race_cat)   <- "Race/Eth"
label(id_covars$sex)   <- "Sex"
label(id_covars$group_dup)   <- "Groups"

table1(~ kcal_2016 + kcal_ent_2016 + kcal_2017 + kcal_ent_2017 +
         kcal_2018 + kcal_ent_2018 + kcal_2019 + kcal_ent_2019 | sex, 
       data=id_covars)
table1(~ kcal_2016 + kcal_ent_2016 + kcal_2017 + kcal_ent_2017 +
         kcal_2018 + kcal_ent_2018 + kcal_2019 + kcal_ent_2019 | race_cat, 
       data=id_covars)
table1(~ kcal_2016 + kcal_ent_2016 + kcal_2017 + kcal_ent_2017 +
         kcal_2018 + kcal_ent_2018 + kcal_2019 + kcal_ent_2019 | job_cat2, 
       data=id_covars)
table1(~ kcal_2016 + kcal_ent_2016 + kcal_2017 + kcal_ent_2017 +
         kcal_2018 + kcal_ent_2018 + kcal_2019 + kcal_ent_2019 | ed_cat, 
       data=id_covars)
table1(~ kcal_2016 + kcal_ent_2016 + kcal_2017 + kcal_ent_2017 +
         kcal_2018 + kcal_ent_2018 + kcal_2019 + kcal_ent_2019 | group2, 
       data=id_covars)


############## 7. SAVE MERGED EGO-LEVEL FOOD/UPDATED TIE PREDICTION OBJECT ############
rm(dyads_1511_1912u_upd_dvs)
save.image(paste("FoodData_Yearly_v1.5_6mlookback",Sys.Date(),".Rdata", sep = ""))

rm(list=setdiff(ls(), c("id_covars", "id_foodyear_w", 
                        "missing_years", "trial_membership")))
id_covars[, randomgroup := NULL]
id_covars[, group_dup := NULL]

save.image(paste("FoodData_Yearly",Sys.Date(),".Rdata", sep = ""))

############## 8. SUBSET NETWORK DATA (6m) #################################

#This section has three parts. 
# 1) First, we just keep relevant covars. ("dyads_key")
#read in data (all month dyadic data with tie probabilities)
dyads_1511_1912u_upd <- readRDS("dyads_1511_1912u_upd.RDS")
setDT(dyads_1511_1912u_upd)

dyads_keydup = dyads_1511_1912u_upd[, .(id, id_d, Month_Yr, calmonth,
                                        deptid, race_cat, job_cat, sex,
                                        ed_cat, mdy, time_n, predprob_upd)]

# 2) we group by purchasing occasion (getting rid of single-item
# dyad records. group by 'mdy', 'time_n', and ego/alter)

keycols = c("id","id_d", "mdy","time_n")  #key on ego and alter's purchases (alter should be included)
dyads_key <- unique(dyads_keydup, by = keycols)

# 3) Then, we just keep ties above a high threshold
dyads_key_0.96 <- dyads_key[predprob_upd >= 0.96]

#plot predicted probability distribution
ggplot(dyads_key, aes(predprob_upd))+
  geom_density()+
  theme_classic()+
  labs(title="New (predicted probability)")
describe(dyads_key$predprob)

#example plot
ggplot(dyads_key_0.96, aes(x=predprob)) + 
  geom_histogram(aes(y=..density..), color="black", fill="white")+
  geom_density(alpha=.2, fill="#FF6666") 

rm(dyads_1511_1912u_upd)
rm(dyads_keydup)

save.image(paste("NetworkVisualizations_",Sys.Date(),".Rdata", sep = ""))

############## 9. PREP FOR SAOMS  ############## 

#EL with all years
el<-dyads_key_0.96[,1:2]
el_nodup<-unique(el)
library(statnet)
full_0.96_net<-network(el_nodup,directed = T) # cant handle duplicates where ego & alter switch
full_0.96_net
full_0.96_mat<-as.matrix(full_0.96_net)
IDs<-colnames(full_0.96_mat) # saves col and row names
write.csv(IDs, file="IDs.csv")

# make symmetric 
isSymmetric(full_0.96_mat)
table(full_0.96_mat)
full_0.96_mat<-symmetrize(full_0.96_mat, rule = "weak") # sym to make network symmetric
isSymmetric(full_0.96_mat)
table(full_0.96_mat)
full_0.96_net<-network(full_0.96_mat,directed = F) # cant handle duplicates where ego & alter switch
full_0.96_net
plot(full_0.96_net, vertex.cex = .2)

############## 10. CREATE ACTOR-LEVEL FILE ############## 
#no 2020 data
dyads_key_0.96<-read.csv(file = "dyads_key_0.96_no2020.csv")
ID<-read.csv(file="IDs_no2020.csv")

library(dplyr)

# for race
race_ego<-dyads_key_0.96[,c(1,6)]
race_alter<-dyads_key_0.96[,c(2,13)]
colnames(race_alter)<-c(colnames(race_ego))

race<-rbind(race_ego, race_alter)
race<-unique(race)
actor_attr<-left_join(ID,race, by = "id" )

table(actor_attr$race_cat, useNA= "ifany")
table(actor_attr$race_cat, useNA= "ifany")/sum(table(actor_attr$race_cat, useNA= "ifany"))

# is missing race data (listed as U) correctly coded?

#for job cat
job_ego<-dyads_key_0.96[,c(1,7)]
job_alter<-dyads_key_0.96[,c(2,14)]
colnames(job_alter)<-c(colnames(job_ego))

job<-rbind(job_ego, job_alter)
job<-unique(job)
actor_attr<-left_join(actor_attr,job, by = "id" )

table(actor_attr$job_cat, useNA= "ifany")
table(actor_attr$job_cat, useNA= "ifany")/sum(table(actor_attr$job_cat, useNA= "ifany"))


#for sex
sex_ego<-dyads_key_0.96[,c(1,8)]
sex_alter<-dyads_key_0.96[,c(2,15)]
colnames(sex_alter)<-c(colnames(sex_ego))

sex<-rbind(sex_ego, sex_alter)
sex<-unique(sex)
actor_attr<-left_join(actor_attr,sex, by = "id" )

table(actor_attr$sex, useNA= "ifany")
table(actor_attr$sex, useNA= "ifany")/sum(table(actor_attr$sex, useNA= "ifany"))


# for birth date
dob_ego<-dyads_key_0.96[,c(1,9)]
dob_alter<-dyads_key_0.96[,c(2,16)]
colnames(dob_alter)<-c(colnames(dob_ego))

dob<-rbind(dob_ego, dob_alter)
dob<-unique(dob)
actor_attr<-left_join(actor_attr,dob, by = "id" )

table(actor_attr$birthdate, useNA= "ifany")
table(actor_attr$birthdate, useNA= "ifany")/sum(table(actor_attr$birthdate, useNA= "ifany"))

# for group status --- ISSUES BC IT CHANGES not constant

dyads_key_0.96$year<-as.numeric(format(as.Date(dyads_key_0.96$mdy, format="%m/%d/%Y"),"%Y"))
dyads_key_0.96$calmonth_6<-dyads_key_0.96$calmonth+6
table(dyads_key_0.96$year, dyads_key_0.96$calmonth_6) # which months are which year?

# it looks like group status changes month by month? Check that this is correct

# ego wide data set to get time varying nature of group
dyads_key_0.96_wide_ego<-dyads_key_0.96[,c(1,4,11)]
dyads_key_0.96_wide_ego$calmonth<- dyads_key_0.96_wide_ego$calmonth+6
dyads_key_0.96_wide_ego<- reshape(dyads_key_0.96_wide_ego, idvar = "id", timevar = "calmonth", direction = "wide")


dyads_key_0.96_wide_alter<-dyads_key_0.96[,c(2,4,18)]
dyads_key_0.96_wide_alter$calmonth<- dyads_key_0.96_wide_alter$calmonth+6
colnames(dyads_key_0.96_wide_alter) <-c("id"  ,   "calmonth" , "group_d" ) # change col names so that id_d = id
dyads_key_0.96_wide_alter<- reshape(dyads_key_0.96_wide_alter, idvar = "id", timevar = "calmonth", direction = "wide")

# join the 2 wide data sets together in case some one is only in there as an ego / alter
group_long<-full_join(dyads_key_0.96_wide_ego, dyads_key_0.96_wide_alter, by = "id" )

# turn nas into 99s so ifelse will work
group_long[is.na(group_long)]<- 99

#create indicator of intervention at 2016
group_long$intervention16<-ifelse(group_long$group.1 == "Intervention" |
                                    group_long$group.2 == "Intervention" |
                                    group_long$group.3 == "Intervention" |
                                    group_long$group.4 == "Intervention" |
                                    group_long$group.5 == "Intervention" |
                                    group_long$group.6 == "Intervention" |
                                    group_long$group.7 == "Intervention" | 
                                    group_long$group.8 == "Intervention" | 
                                    group_long$group.9 == "Intervention" |
                                    group_long$group_d.1 == "Intervention" |
                                    group_long$group_d.2 == "Intervention" |
                                    group_long$group_d.3 == "Intervention" |
                                    group_long$group_d.4 == "Intervention" |
                                    group_long$group_d.5 == "Intervention" |
                                    group_long$group_d.6 == "Intervention" |
                                    group_long$group_d.7 == "Intervention" | 
                                    group_long$group_d.8 == "Intervention" | 
                                    group_long$group_d.9 == "Intervention" 
                                  ,1,0)

table(group_long$intervention16)
#101 people in 2016


#create indicator of intervention at 2017

group_long$intervention17<-ifelse(group_long$group.10 == "Intervention" |
                                    group_long$group.11 == "Intervention" |
                                    group_long$group.12 == "Intervention" |
                                    group_long$group.13 == "Intervention" |
                                    group_long$group.14 == "Intervention" |
                                    group_long$group.15 == "Intervention" |
                                    group_long$group.16 == "Intervention" | 
                                    group_long$group.17 == "Intervention" |
                                    group_long$group.18 == "Intervention" |
                                    group_long$group.19 == "Intervention" | 
                                    group_long$group.20 == "Intervention" | 
                                    group_long$group.21 == "Intervention" |
                                    group_long$group_d.10 == "Intervention" |
                                    group_long$group_d.11 == "Intervention" |
                                    group_long$group_d.12 == "Intervention" |
                                    group_long$group_d.13 == "Intervention" |
                                    group_long$group_d.14 == "Intervention" |
                                    group_long$group_d.15 == "Intervention" |
                                    group_long$group_d.16 == "Intervention" | 
                                    group_long$group_d.17 == "Intervention" |
                                    group_long$group_d.18 == "Intervention" |
                                    group_long$group_d.19 == "Intervention" | 
                                    group_long$group_d.20 == "Intervention" | 
                                    group_long$group_d.21 == "Intervention" ,1,0)

table(group_long$intervention17)
#144 people in 2017


#create indicator of intervention at 2018

group_long$intervention18<-ifelse(group_long$group.22 == "Intervention" |
                                    group_long$group.23 == "Intervention" |
                                    group_long$group.24 == "Intervention" |
                                    group_long$group.25 == "Intervention" |
                                    group_long$group.26 == "Intervention" |
                                    group_long$group.27 == "Intervention" |
                                    group_long$group.28 == "Intervention" | 
                                    group_long$group.29 == "Intervention" |
                                    group_long$group.30 == "Intervention" |
                                    group_long$group.31 == "Intervention" | 
                                    group_long$group.32 == "Intervention" | 
                                    group_long$group.33 == "Intervention" |
                                    group_long$group_d.22 == "Intervention" |
                                    group_long$group_d.23 == "Intervention" |
                                    group_long$group_d.24 == "Intervention" |
                                    group_long$group_d.25 == "Intervention" |
                                    group_long$group_d.26 == "Intervention" |
                                    group_long$group_d.27 == "Intervention" |
                                    group_long$group_d.28 == "Intervention" | 
                                    group_long$group_d.29 == "Intervention" |
                                    group_long$group_d.30 == "Intervention" |
                                    group_long$group_d.31 == "Intervention" | 
                                    group_long$group_d.32 == "Intervention" | 
                                    group_long$group_d.33 == "Intervention" ,1,0)

table(group_long$intervention18)
#117 people in 2018


#create indicator of intervention at 2019

group_long$intervention19<-ifelse(group_long$group.34 == "Intervention" |
                                    group_long$group.35 == "Intervention" |
                                    group_long$group.36 == "Intervention" |
                                    group_long$group.37 == "Intervention" |
                                    group_long$group.38 == "Intervention" |
                                    group_long$group.39 == "Intervention" |
                                    group_long$group.40 == "Intervention" | 
                                    group_long$group.41 == "Intervention" |
                                    group_long$group.42 == "Intervention" |
                                    group_long$group.43 == "Intervention" | 
                                    group_long$group.44 == "Intervention" | 
                                    group_long$group.45 == "Intervention" |
                                    group_long$group_d.34 == "Intervention" |
                                    group_long$group_d.35 == "Intervention" |
                                    group_long$group_d.36 == "Intervention" |
                                    group_long$group_d.37 == "Intervention" |
                                    group_long$group_d.38 == "Intervention" |
                                    group_long$group_d.39 == "Intervention" |
                                    group_long$group_d.40 == "Intervention" | 
                                    group_long$group_d.41 == "Intervention" |
                                    group_long$group_d.42 == "Intervention" |
                                    group_long$group_d.43 == "Intervention" | 
                                    group_long$group_d.44 == "Intervention" | 
                                    group_long$group_d.45 == "Intervention",1,0)

table(group_long$intervention19)
#70 people in 2018

# combine to see if this works
group<-group_long[,c(1,92:95)]

group<-unique(group)
actor_attr<-left_join(actor_attr,group, by = "id" )

# works now!! It's stil not clear tho how intervention is coded, do they
# stay intervention for ever, or do they go back to "none" after a certain period?




# ##############OLD
# 
# 
# #create indicator of intervention at 2017
# 
# dyads_key_0.96_wide_ego$intervention17<-ifelse(dyads_key_0.96_wide_ego$group.10 == "Intervention" |
#                                                  dyads_key_0.96_wide_ego$group.11 == "Intervention" |
#                                                  dyads_key_0.96_wide_ego$group.12 == "Intervention" |
#                                                  dyads_key_0.96_wide_ego$group.13 == "Intervention" |
#                                                  dyads_key_0.96_wide_ego$group.14 == "Intervention" |
#                                                  dyads_key_0.96_wide_ego$group.15 == "Intervention" |
#                                                  dyads_key_0.96_wide_ego$group.16 == "Intervention" | 
#                                                  dyads_key_0.96_wide_ego$group.17 == "Intervention" |
#                                                  dyads_key_0.96_wide_ego$group.18 == "Intervention" |
#                                                  dyads_key_0.96_wide_ego$group.19 == "Intervention" | 
#                                                  dyads_key_0.96_wide_ego$group.20 == "Intervention" | 
#                                                  dyads_key_0.96_wide_ego$group.21 == "Intervention" ,1,0)
# 
# table(dyads_key_0.96_wide_ego$intervention17)
# #141 people in 2017
# 
# 
# #create indicator of intervention at 2018
# 
# dyads_key_0.96_wide_ego$intervention18<-ifelse(dyads_key_0.96_wide_ego$group.22 == "Intervention" |
#                                                  dyads_key_0.96_wide_ego$group.23 == "Intervention" |
#                                                  dyads_key_0.96_wide_ego$group.24 == "Intervention" |
#                                                  dyads_key_0.96_wide_ego$group.25 == "Intervention" |
#                                                  dyads_key_0.96_wide_ego$group.26 == "Intervention" |
#                                                  dyads_key_0.96_wide_ego$group.27 == "Intervention" |
#                                                  dyads_key_0.96_wide_ego$group.28 == "Intervention" | 
#                                                  dyads_key_0.96_wide_ego$group.29 == "Intervention" |
#                                                  dyads_key_0.96_wide_ego$group.30 == "Intervention" |
#                                                  dyads_key_0.96_wide_ego$group.31 == "Intervention" | 
#                                                  dyads_key_0.96_wide_ego$group.32 == "Intervention" | 
#                                                  dyads_key_0.96_wide_ego$group.33 == "Intervention" ,1,0)
# 
# table(dyads_key_0.96_wide_ego$intervention18)
# #116 people in 2018
# 
# 
# #create indicator of intervention at 2019
# 
# dyads_key_0.96_wide_ego$intervention19<-ifelse(dyads_key_0.96_wide_ego$group.34 == "Intervention" |
#                                                  dyads_key_0.96_wide_ego$group.35 == "Intervention" |
#                                                  dyads_key_0.96_wide_ego$group.36 == "Intervention" |
#                                                  dyads_key_0.96_wide_ego$group.37 == "Intervention" |
#                                                  dyads_key_0.96_wide_ego$group.38 == "Intervention" |
#                                                  dyads_key_0.96_wide_ego$group.39 == "Intervention" |
#                                                  dyads_key_0.96_wide_ego$group.40 == "Intervention" | 
#                                                  dyads_key_0.96_wide_ego$group.41 == "Intervention" |
#                                                  dyads_key_0.96_wide_ego$group.42 == "Intervention" |
#                                                  dyads_key_0.96_wide_ego$group.43 == "Intervention" | 
#                                                  dyads_key_0.96_wide_ego$group.44 == "Intervention" | 
#                                                  dyads_key_0.96_wide_ego$group.45 == "Intervention" ,1,0)
# 
# table(dyads_key_0.96_wide_ego$intervention19)
# #70 people in 2018
#  
# #how are intervention people coded? Looks like you can go from intervention to none from this data
# 
# 
# # alter wide data set to get time varying nature of group
# # it looks like group status changes month by month?
# dyads_key_0.96_wide_alter<-dyads_key_0.96[,c(2,4,18)]
# dyads_key_0.96_wide_alter$calmonth<- dyads_key_0.96_wide_alter$calmonth+6
# colnames(dyads_key_0.96_wide_alter) <-c("id"  ,   "calmonth" , "group" ) # change col names to be the same as ego
# dyads_key_0.96_wide_alter<- reshape(dyads_key_0.96_wide_alter, idvar = "id", timevar = "calmonth", direction = "wide")
# # turn nas into 99s so ifelse will work
# dyads_key_0.96_wide_alter[is.na(dyads_key_0.96_wide_alter)]<- 99
# 
# #create indicator of intervention at 2016
# 
# dyads_key_0.96_wide_alter$intervention16<-ifelse(dyads_key_0.96_wide_alter$group.1 == "Intervention" |
#                                                    dyads_key_0.96_wide_alter$group.2 == "Intervention" |
#                                                    dyads_key_0.96_wide_alter$group.3 == "Intervention" |
#                                                    dyads_key_0.96_wide_alter$group.4 == "Intervention" |
#                                                    dyads_key_0.96_wide_alter$group.5 == "Intervention" |
#                                                    dyads_key_0.96_wide_alter$group.6 == "Intervention" |
#                                                    dyads_key_0.96_wide_alter$group.7 == "Intervention" | 
#                                                    dyads_key_0.96_wide_alter$group.8 == "Intervention" | 
#                                                    dyads_key_0.96_wide_alter$group.9 == "Intervention" ,1,0)
# 
# table(dyads_key_0.96_wide_alter$intervention16)
# #100 people in 2016
# 
# 
# #create indicator of intervention at 2017
# 
# dyads_key_0.96_wide_alter$intervention17<-ifelse(dyads_key_0.96_wide_alter$group.10 == "Intervention" |
#                                                    dyads_key_0.96_wide_alter$group.11 == "Intervention" |
#                                                    dyads_key_0.96_wide_alter$group.12 == "Intervention" |
#                                                    dyads_key_0.96_wide_alter$group.13 == "Intervention" |
#                                                    dyads_key_0.96_wide_alter$group.14 == "Intervention" |
#                                                    dyads_key_0.96_wide_alter$group.15 == "Intervention" |
#                                                    dyads_key_0.96_wide_alter$group.16 == "Intervention" | 
#                                                    dyads_key_0.96_wide_alter$group.17 == "Intervention" |
#                                                    dyads_key_0.96_wide_alter$group.18 == "Intervention" |
#                                                    dyads_key_0.96_wide_alter$group.19 == "Intervention" | 
#                                                    dyads_key_0.96_wide_alter$group.20 == "Intervention" | 
#                                                    dyads_key_0.96_wide_alter$group.21 == "Intervention" ,1,0)
# 
# table(dyads_key_0.96_wide_alter$intervention17)
# #143 people in 2017
# 
# 
# #create indicator of intervention at 2018
# 
# dyads_key_0.96_wide_alter$intervention18<-ifelse(dyads_key_0.96_wide_alter$group.22 == "Intervention" |
#                                                    dyads_key_0.96_wide_alter$group.23 == "Intervention" |
#                                                    dyads_key_0.96_wide_alter$group.24 == "Intervention" |
#                                                    dyads_key_0.96_wide_alter$group.25 == "Intervention" |
#                                                    dyads_key_0.96_wide_alter$group.26 == "Intervention" |
#                                                    dyads_key_0.96_wide_alter$group.27 == "Intervention" |
#                                                    dyads_key_0.96_wide_alter$group.28 == "Intervention" | 
#                                                    dyads_key_0.96_wide_alter$group.29 == "Intervention" |
#                                                    dyads_key_0.96_wide_alter$group.30 == "Intervention" |
#                                                    dyads_key_0.96_wide_alter$group.31 == "Intervention" | 
#                                                    dyads_key_0.96_wide_alter$group.32 == "Intervention" | 
#                                                    dyads_key_0.96_wide_alter$group.33 == "Intervention" ,1,0)
# 
# table(dyads_key_0.96_wide_alter$intervention18)
# #116 people in 2018
# 
# 
# #create indicator of intervention at 2019
# 
# dyads_key_0.96_wide_alter$intervention19<-ifelse(dyads_key_0.96_wide_alter$group.34 == "Intervention" |
#                                                    dyads_key_0.96_wide_alter$group.35 == "Intervention" |
#                                                    dyads_key_0.96_wide_alter$group.36 == "Intervention" |
#                                                    dyads_key_0.96_wide_alter$group.37 == "Intervention" |
#                                                    dyads_key_0.96_wide_alter$group.38 == "Intervention" |
#                                                    dyads_key_0.96_wide_alter$group.39 == "Intervention" |
#                                                    dyads_key_0.96_wide_alter$group.40 == "Intervention" | 
#                                                    dyads_key_0.96_wide_alter$group.41 == "Intervention" |
#                                                    dyads_key_0.96_wide_alter$group.42 == "Intervention" |
#                                                    dyads_key_0.96_wide_alter$group.43 == "Intervention" | 
#                                                    dyads_key_0.96_wide_alter$group.44 == "Intervention" | 
#                                                    dyads_key_0.96_wide_alter$group.45 == "Intervention" ,1,0)
# 
# table(dyads_key_0.96_wide_alter$intervention19)
# #69 people in 2018
# 
# # combine to see if this works
# group_ego<-dyads_key_0.96_wide_ego[,c(1,47:50)]
# group_alter<-dyads_key_0.96_wide_alter[,c(1,47:50)]
# 
# group<-rbind(group_ego, group_alter)
# group<-unique(group)
# actor_attr<-left_join(actor_attr,group, by = "id" )
# 
# 
# # issues in that we have 6 more cases than we should. Data is likely not lining up
# # figured out the issue: if people don't use cafeteria much, they might have a year of
# # missing as an alter, only will be listed as an ego. This makes my work from earlier not consistent
# 
# group$dup<- as.numeric(duplicated(group$id))
# 
# ###OLD
# group_ego<-dyads_key_0.96[,c(1,11)]
# group_alter<-dyads_key_0.96[,c(2,18)]
# colnames(group_alter)<-c(colnames(group_ego))
# 
# group<-rbind(group_ego, group_alter)
# group<-unique(group)
# actor_attr<-left_join(actor_attr,group, by = "id" )
# 
# table(actor_attr$group, useNA= "ifany")
# table(actor_attr$group, useNA= "ifany")/sum(table(actor_attr$group, useNA= "ifany"))
# 
# 


# for ed cat

educ_ego<-dyads_key_0.96[,c(1,10)]
educ_alter<-dyads_key_0.96[,c(2,17)]
colnames(educ_alter)<-c(colnames(educ_ego))

educ<-rbind(educ_ego, educ_alter)
educ<-unique(educ)
actor_attr<-left_join(actor_attr,educ, by = "id" )

table(actor_attr$ed_cat, useNA= "ifany")
table(actor_attr$ed_cat, useNA= "ifany")/sum(table(actor_attr$ed_cat, useNA= "ifany"))

# for dept

dept_ego<-dyads_key_0.96[,c(1,5)]
dept_alter<-dyads_key_0.96[,c(2,12)]
colnames(dept_alter)<-c(colnames(dept_ego))

dept<-rbind(dept_ego, dept_alter)
dept<-unique(dept)
actor_attr<-left_join(actor_attr,dept, by = "id" )

table(actor_attr$deptid, useNA= "ifany")
table(actor_attr$deptid, useNA= "ifany")/sum(table(actor_attr$deptid, useNA= "ifany"))


# make age vars. it'll be the age you are at the end of the year
# so what you turn that year
library(eeptools)
actor_attr$age2016<-floor(age_calc(as.Date(actor_attr$birthdate, "%m/%d/%Y"),as.Date("2016-12-31"), units = "years"))
actor_attr$age2017<-floor(age_calc(as.Date(actor_attr$birthdate, "%m/%d/%Y"),as.Date("2017-12-31"), units = "years"))
actor_attr$age2018<-floor(age_calc(as.Date(actor_attr$birthdate, "%m/%d/%Y"),as.Date("2018-12-31"), units = "years"))
actor_attr$age2019<-floor(age_calc(as.Date(actor_attr$birthdate, "%m/%d/%Y"),as.Date("2019-12-31"), units = "years"))



#make an intervention constant variable for now
actor_attr$intervention_ever<-ifelse(actor_attr$intervention16+actor_attr$intervention17+actor_attr$intervention18+actor_attr$intervention19>0,1,0)
table(actor_attr$intervention_ever)


#recode vars to all be numeric

# Race: 1 = White, 2 = Hispanic, 3 = Black, 4 = Asian, 5 = Other
actor_attr$race[actor_attr$race_cat == "W"]<-1
actor_attr$race[actor_attr$race_cat == "H"]<-2
actor_attr$race[actor_attr$race_cat == "B"]<-3
actor_attr$race[actor_attr$race_cat == "A"]<-4
actor_attr$race[actor_attr$race_cat == "O"]<-5
actor_attr$race<- as.numeric(actor_attr$race)

# Job category: 1 = Admin Support, 2 = Mgmt/Clinician, 3 = Professionals, 4 = Service Workers, 5 = Technicians
actor_attr$job[actor_attr$job_cat == "Admin Support"]<-1
actor_attr$job[actor_attr$job_cat == "Mgmt/Clinician"]<-2
actor_attr$job[actor_attr$job_cat == "Professionals"]<-3
actor_attr$job[actor_attr$job_cat == "Service Workers"]<-4
actor_attr$job[actor_attr$job_cat == "Technicians"]<-5
actor_attr$job<- as.numeric(actor_attr$job)

# Sex: 0 = Female, 1 = Male
actor_attr$sex_num[actor_attr$sex == "F"]<-1
actor_attr$sex_num[actor_attr$sex == "M"]<-0
actor_attr$sex_num<- as.numeric(actor_attr$sex_num)

#Dept number: 1-362
actor_attr$dept<-as.numeric(factor(actor_attr$deptid))

write.csv(actor_attr, file = "actor_attr.csv")
save(actor_attr, file = "actor_attr.RData")


###################################

# add in dummy race terms and other alt race terms
load( file = "actor_attr.RData")

table(actor_attr$race_cat)/2890
actor_attr$race4[actor_attr$race_cat == "W"]<-1
actor_attr$race4[actor_attr$race_cat == "H"]<-2
actor_attr$race4[actor_attr$race_cat == "B"]<-3
actor_attr$race4[actor_attr$race_cat == "A"]<-4
actor_attr$race4[actor_attr$race_cat == "O"]<-4


actor_attr$race2[actor_attr$race_cat == "W"]<-1
actor_attr$race2[actor_attr$race_cat == "H"]<-2
actor_attr$race2[actor_attr$race_cat == "B"]<-2
actor_attr$race2[actor_attr$race_cat == "A"]<-2
actor_attr$race2[actor_attr$race_cat == "O"]<-2


actor_attr$white[actor_attr$race_cat == "W"]<-1
actor_attr$white[actor_attr$race_cat == "H"]<-0
actor_attr$white[actor_attr$race_cat == "B"]<-0
actor_attr$white[actor_attr$race_cat == "A"]<-0
actor_attr$white[actor_attr$race_cat == "O"]<-0


actor_attr$hisp[actor_attr$race_cat == "W"]<-0
actor_attr$hisp[actor_attr$race_cat == "H"]<-1
actor_attr$hisp[actor_attr$race_cat == "B"]<-0
actor_attr$hisp[actor_attr$race_cat == "A"]<-0
actor_attr$hisp[actor_attr$race_cat == "O"]<-0

actor_attr$black[actor_attr$race_cat == "W"]<-0
actor_attr$black[actor_attr$race_cat == "H"]<-0
actor_attr$black[actor_attr$race_cat == "B"]<-1
actor_attr$black[actor_attr$race_cat == "A"]<-0
actor_attr$black[actor_attr$race_cat == "O"]<-0


actor_attr$asian[actor_attr$race_cat == "W"]<-0
actor_attr$asian[actor_attr$race_cat == "H"]<-0
actor_attr$asian[actor_attr$race_cat == "B"]<-0
actor_attr$asian[actor_attr$race_cat == "A"]<-1
actor_attr$asian[actor_attr$race_cat == "O"]<-0


actor_attr$other[actor_attr$race_cat == "W"]<-0
actor_attr$other[actor_attr$race_cat == "H"]<-0
actor_attr$other[actor_attr$race_cat == "B"]<-0
actor_attr$other[actor_attr$race_cat == "A"]<-0
actor_attr$other[actor_attr$race_cat == "O"]<-1


actor_attr$other_asian[actor_attr$race_cat == "W"]<-0
actor_attr$other_asian[actor_attr$race_cat == "H"]<-0
actor_attr$other_asian[actor_attr$race_cat == "B"]<-0
actor_attr$other_asian[actor_attr$race_cat == "A"]<-1
actor_attr$other_asian[actor_attr$race_cat == "O"]<-1

save(actor_attr, file = "actor_attr.RData")

########################################################
# Adding in data on when the intervention was #
######################################################

load( file = "actor_attr.RData")
dyads_key_0.96<-read.csv(file = "dyads_key_0.96_all_vars_no2020.csv")

# date the intervention started
interv_date_ego<-as.data.frame(cbind(dyads_key_0.96$id, dyads_key_0.96$randomdatetime))
interv_date_alter<-as.data.frame(cbind(dyads_key_0.96$id_d, dyads_key_0.96$randomdatetime_d))
colnames(interv_date_alter)<-c(colnames(interv_date_ego))

interv_date<-rbind(interv_date_ego, interv_date_alter)
interv_date<-unique(interv_date)

#issues with duplicates (people who joined the intervention late have multiple cases)

#flag duplicates but have to sort in a certain way first
interv_date
interv_date<- interv_date[order(is.na(interv_date$V2), decreasing = F),]
interv_date<- interv_date[order(interv_date$V1, decreasing = F),]
interv_date$dup<-duplicated(interv_date[,1])

table(interv_date$dup)
interv_date<-interv_date[interv_date$dup == FALSE,]
interv_date<-interv_date[,c(1,2)]

#clean up for merge
colnames(interv_date)<-c("id","interv_start")
interv_date$id<-as.integer(interv_date$id)


actor_attr<-left_join(actor_attr,interv_date, by = "id" )


############################################
#generate a dummy for if ever in control group
actor_attr$control_ever <- ifelse(actor_attr$intervention_ever == 0 & is.na(actor_attr$interv_start) == F,1,0 )



###########################################
#try to create new intervention terms
actor_attr$intervention16<-NULL
actor_attr$intervention17<-NULL
actor_attr$intervention18<-NULL
actor_attr$intervention19<-NULL

actor_attr$interv_start<-as.Date(actor_attr$interv_start, format="%m/%d/%Y")
actor_attr$interv_start_yr<-as.numeric(format(as.Date(actor_attr$interv_start, format="%m/%d/%Y"),"%Y"))
table(actor_attr$interv_start_yr) # starts are all in 16-18

library(eeptools)
actor_attr$intervention16<-0
actor_attr$intervention17<-0
actor_attr$intervention18<-0
actor_attr$intervention19<-0

for (i in 1:nrow(actor_attr)){
  if(actor_attr$interv_start_yr[i] == 2016 & is.na(actor_attr$interv_start_yr[i])==F & actor_attr$intervention_ever[i] == 1){
    actor_attr$intervention16[i] <- age_calc(actor_attr$interv_start[i],as.Date("2016-12-31"), units = "months")
    actor_attr$intervention17[i] <- 12-actor_attr$intervention16[i]
  }
}


for (i in 1:nrow(actor_attr)){
  if(actor_attr$interv_start_yr[i] == 2017 & is.na(actor_attr$interv_start_yr[i])==F& actor_attr$intervention_ever[i] == 1){
    actor_attr$intervention17[i] <- age_calc(actor_attr$interv_start[i],as.Date("2017-12-31"), units = "months")
    actor_attr$intervention18[i] <- 12-actor_attr$intervention17[i]
  }
}


for (i in 1:nrow(actor_attr)){
  if(actor_attr$interv_start_yr[i] == 2018 & is.na(actor_attr$interv_start_yr[i])==F & actor_attr$intervention_ever[i] == 1){
    actor_attr$intervention18[i] <- age_calc(actor_attr$interv_start[i],as.Date("2018-12-31"), units = "months")
    actor_attr$intervention19[i] <- 12-actor_attr$intervention18[i]
  }
}


##############
# create post intervention variable

actor_attr$postinterv16<-0
actor_attr$postinterv17<-0
actor_attr$postinterv18<-0
actor_attr$postinterv19<-0

for (i in 1:nrow(actor_attr)){
  if(actor_attr$interv_start_yr[i] == 2016 & is.na(actor_attr$interv_start_yr[i])==F & actor_attr$intervention_ever[i] == 1){
    actor_attr$postinterv17[i] <- 12-actor_attr$intervention17[i]
    actor_attr$postinterv18[i]<-12
    actor_attr$postinterv19[i]<-12
  }
}

for (i in 1:nrow(actor_attr)){
  if(actor_attr$interv_start_yr[i] == 2017 & is.na(actor_attr$interv_start_yr[i])==F & actor_attr$intervention_ever[i] == 1){
    actor_attr$postinterv18[i]<-12-actor_attr$intervention18[i]
    actor_attr$postinterv19[i]<-12
  }
}

for (i in 1:nrow(actor_attr)){
  if(actor_attr$interv_start_yr[i] == 2018 & is.na(actor_attr$interv_start_yr[i])==F & actor_attr$intervention_ever[i] == 1){
    actor_attr$postinterv19[i]<-12-actor_attr$intervention19[i]
  }
}



##############
# create ever intervention variable

actor_attr$everinterv16<-0
actor_attr$everinterv17<-0
actor_attr$everinterv18<-0
actor_attr$everinterv19<-0

for (i in 1:nrow(actor_attr)){
  if(actor_attr$interv_start_yr[i] == 2016 & is.na(actor_attr$interv_start_yr[i])==F & actor_attr$intervention_ever[i] == 1){
    actor_attr$everinterv16[i] <- actor_attr$intervention16[i]
    actor_attr$everinterv17[i]<-12
    actor_attr$everinterv18[i]<-12
    actor_attr$everinterv19[i]<-12
  }
}
for (i in 1:nrow(actor_attr)){
  if(actor_attr$interv_start_yr[i] == 2017 & is.na(actor_attr$interv_start_yr[i])==F& actor_attr$intervention_ever[i] == 1){
    actor_attr$everinterv17[i] <- actor_attr$intervention17[i]
    actor_attr$everinterv18[i]<-12
    actor_attr$everinterv19[i]<-12
  }
}

for (i in 1:nrow(actor_attr)){
  if(actor_attr$interv_start_yr[i] == 2018 & is.na(actor_attr$interv_start_yr[i])==F& actor_attr$intervention_ever[i] == 1){
    actor_attr$everinterv18[i] <- actor_attr$intervention18[i]
    actor_attr$everinterv19[i]<-12
  }
}









###########################################
#try to create new control terms
actor_attr$control16<-0
actor_attr$control17<-0
actor_attr$control18<-0
actor_attr$control19<-0



for (i in 1:nrow(actor_attr)){
  if(actor_attr$interv_start_yr[i] == 2016 & is.na(actor_attr$interv_start_yr[i])==F & actor_attr$control_ever[i] == 1){
    actor_attr$control16[i] <- age_calc(actor_attr$interv_start[i],as.Date("2016-12-31"), units = "months")
    actor_attr$control17[i] <- 12-actor_attr$control16[i]
  }
}


for (i in 1:nrow(actor_attr)){
  if(actor_attr$interv_start_yr[i] == 2017 & is.na(actor_attr$interv_start_yr[i])==F& actor_attr$control_ever[i] == 1){
    actor_attr$control17[i] <- age_calc(actor_attr$interv_start[i],as.Date("2017-12-31"), units = "months")
    actor_attr$control18[i] <- 12-actor_attr$control17[i]
  }
}


for (i in 1:nrow(actor_attr)){
  if(actor_attr$interv_start_yr[i] == 2018 & is.na(actor_attr$interv_start_yr[i])==F & actor_attr$control_ever[i] == 1){
    actor_attr$control18[i] <- age_calc(actor_attr$interv_start[i],as.Date("2018-12-31"), units = "months")
    actor_attr$control19[i] <- 12-actor_attr$control18[i]
  }
}


##############
# create post control variable

actor_attr$postcontrol16<-0
actor_attr$postcontrol17<-0
actor_attr$postcontrol18<-0
actor_attr$postcontrol19<-0

for (i in 1:nrow(actor_attr)){
  if(actor_attr$interv_start_yr[i] == 2016 & is.na(actor_attr$interv_start_yr[i])==F & actor_attr$control_ever[i] == 1){
    actor_attr$postcontrol17[i] <- 12-actor_attr$control17[i]
    actor_attr$postcontrol18[i]<-12
    actor_attr$postcontrol19[i]<-12
  }
}

for (i in 1:nrow(actor_attr)){
  if(actor_attr$interv_start_yr[i] == 2017 & is.na(actor_attr$interv_start_yr[i])==F & actor_attr$control_ever[i] == 1){
    actor_attr$postcontrol18[i]<-12-actor_attr$control18[i]
    actor_attr$postcontrol19[i]<-12
  }
}

for (i in 1:nrow(actor_attr)){
  if(actor_attr$interv_start_yr[i] == 2018 & is.na(actor_attr$interv_start_yr[i])==F & actor_attr$control_ever[i] == 1){
    actor_attr$postcontrol19[i]<-12-actor_attr$control19[i]
  }
}



##############
# create ever intervention variable

actor_attr$evercontrol16<-0
actor_attr$evercontrol17<-0
actor_attr$evercontrol18<-0
actor_attr$evercontrol19<-0

for (i in 1:nrow(actor_attr)){
  if(actor_attr$interv_start_yr[i] == 2016 & is.na(actor_attr$interv_start_yr[i])==F & actor_attr$control_ever[i] == 1){
    actor_attr$evercontrol16[i] <- actor_attr$control16[i]
    actor_attr$evercontrol17[i]<-12
    actor_attr$evercontrol18[i]<-12
    actor_attr$evercontrol19[i]<-12
  }
}
for (i in 1:nrow(actor_attr)){
  if(actor_attr$interv_start_yr[i] == 2017 & is.na(actor_attr$interv_start_yr[i])==F& actor_attr$control_ever[i] == 1){
    actor_attr$evercontrol17[i] <- actor_attr$control17[i]
    actor_attr$evercontrol18[i]<-12
    actor_attr$evercontrol19[i]<-12
  }
}

for (i in 1:nrow(actor_attr)){
  if(actor_attr$interv_start_yr[i] == 2018 & is.na(actor_attr$interv_start_yr[i])==F& actor_attr$control_ever[i] == 1){
    actor_attr$evercontrol18[i] <- actor_attr$control18[i]
    actor_attr$evercontrol19[i]<-12
  }
}



save(actor_attr, file = "actor_attr.RData")



###################################

# create categorical measures of age

#2016
load( file = "actor_attr.RData")
actor_attr$age_18_29_2016<-0
actor_attr$age_18_29_2016 [actor_attr$age2016<30]<-1
actor_attr$age_30_39_2016<-0
actor_attr$age_30_39_2016 [actor_attr$age2016>=30 & actor_attr$age2016<=39]<-1 
actor_attr$age_40_49_2016<-0
actor_attr$age_40_49_2016 [actor_attr$age2016>=40 & actor_attr$age2016<=49]<-1 
actor_attr$age_50_2016<-0
actor_attr$age_50_2016 [actor_attr$age2016>=50 ]<-1 

sum(actor_attr$age_18_29_2016,actor_attr$age_30_39_2016, actor_attr$age_40_49_2016,actor_attr$age_50_2016)


actor_attr$age_cat_2016[actor_attr$age_18_29_2016 == 1] <-1
actor_attr$age_cat_2016[actor_attr$age_30_39_2016 == 1] <-2
actor_attr$age_cat_2016[actor_attr$age_40_49_2016 == 1] <-3
actor_attr$age_cat_2016[actor_attr$age_50_2016 == 1] <-4


#2017
actor_attr$age_18_29_2017<-0
actor_attr$age_18_29_2017 [actor_attr$age2017<30]<-1
actor_attr$age_30_39_2017<-0
actor_attr$age_30_39_2017 [actor_attr$age2017>=30 & actor_attr$age2017<=39]<-1 
actor_attr$age_40_49_2017<-0
actor_attr$age_40_49_2017 [actor_attr$age2017>=40 & actor_attr$age2017<=49]<-1 
actor_attr$age_50_2017<-0
actor_attr$age_50_2017 [actor_attr$age2017>=50 ]<-1 

sum(actor_attr$age_18_29_2017,actor_attr$age_30_39_2017, actor_attr$age_40_49_2017,actor_attr$age_50_2017)


actor_attr$age_cat_2017[actor_attr$age_18_29_2017 == 1] <-1
actor_attr$age_cat_2017[actor_attr$age_30_39_2017 == 1] <-2
actor_attr$age_cat_2017[actor_attr$age_40_49_2017 == 1] <-3
actor_attr$age_cat_2017[actor_attr$age_50_2017 == 1] <-4


#2018
actor_attr$age_18_29_2018<-0
actor_attr$age_18_29_2018 [actor_attr$age2018<30]<-1
actor_attr$age_30_39_2018<-0
actor_attr$age_30_39_2018 [actor_attr$age2018>=30 & actor_attr$age2018<=39]<-1 
actor_attr$age_40_49_2018<-0
actor_attr$age_40_49_2018 [actor_attr$age2018>=40 & actor_attr$age2018<=49]<-1 
actor_attr$age_50_2018<-0
actor_attr$age_50_2018 [actor_attr$age2018>=50 ]<-1 

sum(actor_attr$age_18_29_2018,actor_attr$age_30_39_2018, actor_attr$age_40_49_2018,actor_attr$age_50_2018)


actor_attr$age_cat_2018[actor_attr$age_18_29_2018 == 1] <-1
actor_attr$age_cat_2018[actor_attr$age_30_39_2018 == 1] <-2
actor_attr$age_cat_2018[actor_attr$age_40_49_2018 == 1] <-3
actor_attr$age_cat_2018[actor_attr$age_50_2018 == 1] <-4


#2019

actor_attr$age_18_29_2019<-0
actor_attr$age_18_29_2019 [actor_attr$age2019<30]<-1
actor_attr$age_30_39_2019<-0
actor_attr$age_30_39_2019 [actor_attr$age2019>=30 & actor_attr$age2019<=39]<-1 
actor_attr$age_40_49_2019<-0
actor_attr$age_40_49_2019 [actor_attr$age2019>=40 & actor_attr$age2019<=49]<-1 
actor_attr$age_50_2019<-0
actor_attr$age_50_2019 [actor_attr$age2019>=50 ]<-1 

sum(actor_attr$age_18_29_2019,actor_attr$age_30_39_2019, actor_attr$age_40_49_2019,actor_attr$age_50_2019)


actor_attr$age_cat_2019[actor_attr$age_18_29_2019 == 1] <-1
actor_attr$age_cat_2019[actor_attr$age_30_39_2019 == 1] <-2
actor_attr$age_cat_2019[actor_attr$age_40_49_2019 == 1] <-3
actor_attr$age_cat_2019[actor_attr$age_50_2019 == 1] <-4

save(actor_attr, file = "actor_attr.RData")


# create dummy vars for job type
load(file = "actor_attr.RData")

# Job category: 1 = Admin Support, 2 = Mgmt/Clinician, 3 = Professionals, 4 = Service Workers, 5 = Technicians
actor_attr$admin[actor_attr$job == 1] <-1
actor_attr$admin[actor_attr$job == 2] <-0
actor_attr$admin[actor_attr$job == 3] <-0
actor_attr$admin[actor_attr$job == 4] <-0
actor_attr$admin[actor_attr$job == 5] <-0

actor_attr$mgmt_clinician[actor_attr$job == 1] <-0
actor_attr$mgmt_clinician[actor_attr$job == 2] <-1
actor_attr$mgmt_clinician[actor_attr$job == 3] <-0
actor_attr$mgmt_clinician[actor_attr$job == 4] <-0
actor_attr$mgmt_clinician[actor_attr$job == 5] <-0

actor_attr$prof[actor_attr$job == 1] <-0
actor_attr$prof[actor_attr$job == 2] <-0
actor_attr$prof[actor_attr$job == 3] <-1
actor_attr$prof[actor_attr$job == 4] <-0
actor_attr$prof[actor_attr$job == 5] <-0

actor_attr$service[actor_attr$job == 1] <-0
actor_attr$service[actor_attr$job == 2] <-0
actor_attr$service[actor_attr$job == 3] <-0
actor_attr$service[actor_attr$job == 4] <-1
actor_attr$service[actor_attr$job == 5] <-0

actor_attr$tech[actor_attr$job == 1] <-0
actor_attr$tech[actor_attr$job == 2] <-0
actor_attr$tech[actor_attr$job == 3] <-0
actor_attr$tech[actor_attr$job == 4] <-0
actor_attr$tech[actor_attr$job == 5] <-1

save(actor_attr,file = "actor_attr.RData")



# create a time non varying for ever in trial
actor_attr$evertrial <- actor_attr$intervention_ever+actor_attr$control_ever
save(actor_attr,file = "actor_attr.RData")


# create time varying versions of trial status

# during/ post trial
actor_attr$evertrial16 <- actor_attr$everinterv16 + actor_attr$evercontrol16
actor_attr$evertrial17 <- actor_attr$everinterv17 + actor_attr$evercontrol17
actor_attr$evertrial18 <- actor_attr$everinterv18 + actor_attr$evercontrol18
actor_attr$evertrial19 <- actor_attr$everinterv19 + actor_attr$evercontrol19

#before trial
actor_attr$pretrial16 <- 0
actor_attr$pretrial17 <- 0
actor_attr$pretrial18 <- 0
actor_attr$pretrial19 <- 0
for (i in 1:2890){
  if (actor_attr$evertrial[i] == 1){
    actor_attr$pretrial16[i] <- 12-actor_attr$evertrial16[i]
    actor_attr$pretrial17[i] <- 12-actor_attr$evertrial17[i]
    actor_attr$pretrial18[i] <- 12-actor_attr$evertrial18[i]
    actor_attr$pretrial19[i] <- 12-actor_attr$evertrial19[i]
  }
}

#binary versions
actor_attr$evertrial_bin16<- 0
for (i in 1:2890){
  if (actor_attr$evertrial16[i]>0){
    actor_attr$evertrial_bin16[i] <-1
  }
}
actor_attr$evertrial_bin17<- 0
for (i in 1:2890){
  if (actor_attr$evertrial17[i]>0){
    actor_attr$evertrial_bin17[i] <-1
  }
}
actor_attr$evertrial_bin18<- 0
for (i in 1:2890){
  if (actor_attr$evertrial18[i]>0){
    actor_attr$evertrial_bin18[i] <-1
  }
}
actor_attr$evertrial_bin19<- 0
for (i in 1:2890){
  if (actor_attr$evertrial19[i]>0){
    actor_attr$evertrial_bin19[i] <-1
  }
}


actor_attr$pretrial_bin16 <- 0
actor_attr$pretrial_bin17 <- 0
actor_attr$pretrial_bin18 <- 0
actor_attr$pretrial_bin19 <- 0
for (i in 1:2890){
  if (actor_attr$evertrial[i] == 1){
    actor_attr$pretrial_bin16[i] <- 1-actor_attr$evertrial_bin16[i]
    actor_attr$pretrial_bin17[i] <- 1-actor_attr$evertrial_bin17[i]
    actor_attr$pretrial_bin18[i] <- 1-actor_attr$evertrial_bin18[i]
    actor_attr$pretrial_bin19[i] <- 1-actor_attr$evertrial_bin19[i]
  }
}

save(actor_attr,file = "actor_attr.RData")




# during trial only
actor_attr$trial16 <- actor_attr$intervention16 + actor_attr$control16
actor_attr$trial17 <- actor_attr$intervention17 + actor_attr$control17
actor_attr$trial18 <- actor_attr$intervention18 + actor_attr$control18
actor_attr$trial19 <- actor_attr$intervention19 + actor_attr$control19

# post trial only
actor_attr$posttrial16 <- actor_attr$postinterv16 + actor_attr$postcontrol16
actor_attr$posttrial17 <- actor_attr$postinterv17 + actor_attr$postcontrol17
actor_attr$posttrial18 <- actor_attr$postinterv18 + actor_attr$postcontrol18
actor_attr$posttrial19 <- actor_attr$postinterv19 + actor_attr$postcontrol19

#binary versions
actor_attr$trial_bin16<- 0
for (i in 1:2890){
  if (actor_attr$trial16[i]>0){
    actor_attr$trial_bin16[i] <-1
  }
}
actor_attr$trial_bin17<- 0
for (i in 1:2890){
  if (actor_attr$trial17[i]>0){
    actor_attr$trial_bin17[i] <-1
  }
}
actor_attr$trial_bin18<- 0
for (i in 1:2890){
  if (actor_attr$trial18[i]>0){
    actor_attr$trial_bin18[i] <-1
  }
}
actor_attr$trial_bin19<- 0
for (i in 1:2890){
  if (actor_attr$trial19[i]>0){
    actor_attr$trial_bin19[i] <-1
  }
}


actor_attr$posttrial_bin16<- 0
for (i in 1:2890){
  if (actor_attr$posttrial16[i]==12){
    actor_attr$posttrial_bin16[i] <-1
  }
}
actor_attr$posttrial_bin17<- 0
for (i in 1:2890){
  if (actor_attr$posttrial17[i]==12){
    actor_attr$posttrial_bin17[i] <-1
  }
}
actor_attr$posttrial_bin18<- 0
for (i in 1:2890){
  if (actor_attr$posttrial18[i]==12){
    actor_attr$posttrial_bin18[i] <-1
  }
}
actor_attr$posttrial_bin19<- 0
for (i in 1:2890){
  if (actor_attr$posttrial19[i]==12){
    actor_attr$posttrial_bin19[i] <-1
  }
}

save(actor_attr,file = "actor_attr.RData")


#create pre intervention and pre control
load(file = "actor_attr.RData")
#before intervention
actor_attr$preinterv16 <- 0
actor_attr$preinterv17 <- 0
actor_attr$preinterv18 <- 0
actor_attr$preinterv19 <- 0
for (i in 1:2890){
  if (actor_attr$intervention_ever[i] == 1){
    actor_attr$preinterv16[i] <- actor_attr$pretrial16[i]
    actor_attr$preinterv17[i] <- actor_attr$pretrial17[i]
    actor_attr$preinterv18[i] <- actor_attr$pretrial18[i]
    actor_attr$preinterv19[i] <- actor_attr$pretrial19[i]
  }
}

#before control
actor_attr$precontrol16 <- 0
actor_attr$precontrol17 <- 0
actor_attr$precontrol18 <- 0
actor_attr$precontrol19 <- 0
for (i in 1:2890){
  if (actor_attr$control_ever[i] == 1){
    actor_attr$precontrol16[i] <- actor_attr$pretrial16[i]
    actor_attr$precontrol17[i] <- actor_attr$pretrial17[i]
    actor_attr$precontrol18[i] <- actor_attr$pretrial18[i]
    actor_attr$precontrol19[i] <- actor_attr$pretrial19[i]
  }
}
save(actor_attr,file = "actor_attr.RData")

############## 11. CREATE COMPOSITION CHANGE FILE ############## 

library(lubridate)
dat<-read.csv(file = "actor_attr_purch.csv")

table(dat$min) #starts 4/2016
table(dat$max) # ends 2/2020 (but we are ending in 12/2019)

# create month and year vars. 
dat$start_yr<-year(as.Date(dat$min, format="%m/%d/%Y"))
dat$start_mo<-month(as.Date(dat$min, format="%m/%d/%Y"))
dat$end_yr<-year(as.Date(dat$max, format="%m/%d/%Y"))
dat$end_mo<-month(as.Date(dat$max, format="%m/%d/%Y"))

# make joiner/leaver file
dat$join<-NA
for (i in 1:nrow(dat)){
  if (dat$start_yr[i] == 2016){
    dat$join[i]<-1
  }
  if(dat$start_yr[i] == 2017){
    dat$join[i]<- round(1+((dat$start_mo[i]-1)/12), digits = 1)
  }
  if(dat$start_yr[i] == 2018){
    dat$join[i]<- round(2+((dat$start_mo[i]-1)/12), digits = 1)
  }
  if(dat$start_yr[i] == 2019){
    dat$join[i]<- round(3+((dat$start_mo[i]-1)/12), digits = 1)
  }
}
dat$leave<-NA
for (i in 1:nrow(dat)){
  if (dat$end_yr[i] == 2016){ #giving them a small amount of time, otherwise, they need to be dropped
    dat$leave[i]<-1.1
  }
  if(dat$end_yr[i] == 2017){
    dat$leave[i]<- round(1+((dat$end_mo[i])/12), digits = 1)
  }
  if(dat$end_yr[i] == 2018){
    dat$leave[i]<- round(2+((dat$end_mo[i])/12), digits = 1)
  }
  if(dat$end_yr[i] == 2019){
    dat$leave[i]<- round(3+((dat$end_mo[i])/12), digits = 1)
  }
  if(dat$end_yr[i] == 2020){
    dat$leave[i]<- 4
  }
}
table(dat$join)
table(dat$leave)

# turn into a list
compchange<-list()
for (i in 1:nrow(dat)){
  compchange[[i]]<-c(dat$join[i], dat$leave[i])
}
compchange
save(compchange, file = "compchange_1_2025.RData")
#check to see if this is aligning with the network data

#Load the data
load(file="adjmat_2016_all_actors.RData")
dat$deg16<-rowSums(mat_16_all_actors)
load(file="adjmat_2017_all_actors.RData")
dat$deg17<-rowSums(mat_17_all_actors)
load(file="adjmat_2018_all_actors.RData")
dat$deg18<-rowSums(mat_18_all_actors)
load(file="adjmat_2019_all_actors.RData")
dat$deg19<-rowSums(mat_19_all_actors)
#### Make network w 2016 edges ####
table(dyads_key_0.96$Month_Yr, useNA = "ifany")
y16_0.96_el<-rbind(dyads_key_0.96[dyads_key_0.96$Month_Yr =="2016-04",],
                   dyads_key_0.96[dyads_key_0.96$Month_Yr =="2016-05",],
                   dyads_key_0.96[dyads_key_0.96$Month_Yr =="2016-06",],
                   dyads_key_0.96[dyads_key_0.96$Month_Yr =="2016-07",],
                   dyads_key_0.96[dyads_key_0.96$Month_Yr =="2016-08",],
                   dyads_key_0.96[dyads_key_0.96$Month_Yr =="2016-09",],
                   dyads_key_0.96[dyads_key_0.96$Month_Yr =="2016-10",],
                   dyads_key_0.96[dyads_key_0.96$Month_Yr =="2016-11",],
                   dyads_key_0.96[dyads_key_0.96$Month_Yr =="2016-12",])

el_16_nodup<-unique(y16_0.96_el[,1:2])
write.csv(el_16_nodup, file = "el_16_nodup.csv")
y16_net_try1<-network(el_16_nodup,directed = T)
y16_net_try1
y16_net_try1_mat<-as.matrix(y16_net_try1)

# make symmetric 
isSymmetric(y16_net_try1_mat)
table(y16_net_try1_mat)
y16_net_try1_mat<-symmetrize(y16_net_try1_mat, rule = "weak") # sym to make network symmetric
isSymmetric(y16_net_try1_mat)
table(y16_net_try1_mat)
3324 /2
#1662 symmetric ties at T1

#create empty matrix w correct col and row names
empty_mat<-matrix(data= 0, 
                  nrow = length(IDs), 
                  ncol = length(IDs),
                  dimnames= list(IDs, IDs))


# fill in with EL info
mat_16_all_actors<-empty_mat
for (i in 1:nrow(el_16_nodup)){
  mat_16_all_actors[match(el_16_nodup$id[i],IDs), match(el_16_nodup$id_d[i],IDs)]<-1
}
table(mat_16_all_actors)
isSymmetric(mat_16_all_actors)
mat_16_all_actors<-symmetrize(mat_16_all_actors, rule = "weak") # sym to make network symmetric
isSymmetric(mat_16_all_actors)
table(mat_16_all_actors)
# 3324/2 = same number of ties!
net_16_all_actors<-network(mat_16_all_actors,directed = F) 
plot(net_16_all_actors, vertex.cex =.2,  arrowhead.cex = 0)
save(mat_16_all_actors, file="adjmat_2016_all_actors.RData")
write.csv(mat_16_all_actors, file="adjmat_2016_all_actors.csv")


#### Make network w 2017 edges ####
y17_0.96_el<-rbind(dyads_key_0.96[dyads_key_0.96$Month_Yr =="2017-01",],
                   dyads_key_0.96[dyads_key_0.96$Month_Yr =="2017-02",],
                   dyads_key_0.96[dyads_key_0.96$Month_Yr =="2017-03",],
                   dyads_key_0.96[dyads_key_0.96$Month_Yr =="2017-04",],
                   dyads_key_0.96[dyads_key_0.96$Month_Yr =="2017-05",],
                   dyads_key_0.96[dyads_key_0.96$Month_Yr =="2017-06",],
                   dyads_key_0.96[dyads_key_0.96$Month_Yr =="2017-07",],
                   dyads_key_0.96[dyads_key_0.96$Month_Yr =="2017-08",],
                   dyads_key_0.96[dyads_key_0.96$Month_Yr =="2017-09",],
                   dyads_key_0.96[dyads_key_0.96$Month_Yr =="2017-10",],
                   dyads_key_0.96[dyads_key_0.96$Month_Yr =="2017-11",],
                   dyads_key_0.96[dyads_key_0.96$Month_Yr =="2017-12",])

el_17_nodup<-unique(y17_0.96_el[,1:2])
y17_net_try1<-network(el_17_nodup,directed = T)
y17_net_try1
y17_net_try1_mat<-as.matrix(y17_net_try1)
# make symmetric 
isSymmetric(y17_net_try1_mat)
table(y17_net_try1_mat)
y17_net_try1_mat<-symmetrize(y17_net_try1_mat, rule = "weak") # sym to make network symmetric
isSymmetric(y17_net_try1_mat)
table(y17_net_try1_mat)
4746 /2
#2373 symmetric ties at T1



# fill in with adjmat with EL info
mat_17_all_actors<-empty_mat
for (i in 1:nrow(el_17_nodup)){
  mat_17_all_actors[match(el_17_nodup$id[i],IDs), match(el_17_nodup$id_d[i],IDs)]<-1
}
table(mat_17_all_actors)
isSymmetric(mat_17_all_actors)
mat_17_all_actors<-symmetrize(mat_17_all_actors, rule = "weak") # sym to make network symmetric
isSymmetric(mat_17_all_actors)
table(mat_17_all_actors)
# 4746/2 = same number of ties!
net_17_all_actors<-network(mat_17_all_actors,directed = F) 
plot(net_17_all_actors, vertex.cex =.2,  arrowhead.cex = 0)
save(mat_17_all_actors, file="adjmat_2017_all_actors.RData")


#### Make network w 2018 edges ####
y18_0.96_el<-rbind(dyads_key_0.96[dyads_key_0.96$Month_Yr =="2018-01",],
                   dyads_key_0.96[dyads_key_0.96$Month_Yr =="2018-02",],
                   dyads_key_0.96[dyads_key_0.96$Month_Yr =="2018-03",],
                   dyads_key_0.96[dyads_key_0.96$Month_Yr =="2018-04",],
                   dyads_key_0.96[dyads_key_0.96$Month_Yr =="2018-05",],
                   dyads_key_0.96[dyads_key_0.96$Month_Yr =="2018-06",],
                   dyads_key_0.96[dyads_key_0.96$Month_Yr =="2018-07",],
                   dyads_key_0.96[dyads_key_0.96$Month_Yr =="2018-08",],
                   dyads_key_0.96[dyads_key_0.96$Month_Yr =="2018-09",],
                   dyads_key_0.96[dyads_key_0.96$Month_Yr =="2018-10",],
                   dyads_key_0.96[dyads_key_0.96$Month_Yr =="2018-11",],
                   dyads_key_0.96[dyads_key_0.96$Month_Yr =="2018-12",])

el_18_nodup<-unique(y18_0.96_el[,1:2])
y18_net_try1<-network(el_18_nodup,directed = T)
y18_net_try1
y18_net_try1_mat<-as.matrix(y18_net_try1)
# make symmetric 
isSymmetric(y18_net_try1_mat)
table(y18_net_try1_mat)
y18_net_try1_mat<-symmetrize(y18_net_try1_mat, rule = "weak") # sym to make network symmetric
isSymmetric(y18_net_try1_mat)
table(y18_net_try1_mat)
4100 /2
#2050 symmetric ties at T1



# fill in with adjmat with EL info
mat_18_all_actors<-empty_mat
for (i in 1:nrow(el_18_nodup)){
  mat_18_all_actors[match(el_18_nodup$id[i],IDs), match(el_18_nodup$id_d[i],IDs)]<-1
}
table(mat_18_all_actors)
isSymmetric(mat_18_all_actors)
mat_18_all_actors<-symmetrize(mat_18_all_actors, rule = "weak") # sym to make network symmetric
isSymmetric(mat_18_all_actors)
table(mat_18_all_actors)
# 4100/2 = same number of ties!
net_18_all_actors<-network(mat_18_all_actors,directed = F) 
plot(net_18_all_actors, vertex.cex =.2,  arrowhead.cex = 0)
write.table(mat_18_all_actors,file="adjmat_2018_all_actors.csv",col.names = colnames(empty_mat),sep = ",",row.names = colnames(empty_mat))
save(mat_18_all_actors, file="adjmat_2018_all_actors.RData")



#### Make network w 2019 edges ####
y19_0.96_el<-rbind(dyads_key_0.96[dyads_key_0.96$Month_Yr =="2019-01",],
                   dyads_key_0.96[dyads_key_0.96$Month_Yr =="2019-02",],
                   dyads_key_0.96[dyads_key_0.96$Month_Yr =="2019-03",],
                   dyads_key_0.96[dyads_key_0.96$Month_Yr =="2019-04",],
                   dyads_key_0.96[dyads_key_0.96$Month_Yr =="2019-05",],
                   dyads_key_0.96[dyads_key_0.96$Month_Yr =="2019-06",],
                   dyads_key_0.96[dyads_key_0.96$Month_Yr =="2019-07",],
                   dyads_key_0.96[dyads_key_0.96$Month_Yr =="2019-08",],
                   dyads_key_0.96[dyads_key_0.96$Month_Yr =="2019-09",],
                   dyads_key_0.96[dyads_key_0.96$Month_Yr =="2019-10",],
                   dyads_key_0.96[dyads_key_0.96$Month_Yr =="2019-11",],
                   dyads_key_0.96[dyads_key_0.96$Month_Yr =="2019-12",])

el_19_nodup<-unique(y19_0.96_el[,1:2])
y19_net_try1<-network(el_19_nodup,directed = T)
y19_net_try1
y19_net_try1_mat<-as.matrix(y19_net_try1)
# make symmetric 
isSymmetric(y19_net_try1_mat)
table(y19_net_try1_mat)
y19_net_try1_mat<-symmetrize(y19_net_try1_mat, rule = "weak") # sym to make network symmetric
isSymmetric(y19_net_try1_mat)
table(y19_net_try1_mat)
3868 /2
#1934 symmetric ties at T1

# fill in with adjmat with EL info
mat_19_all_actors<-empty_mat
for (i in 1:nrow(el_19_nodup)){
  mat_19_all_actors[match(el_19_nodup$id[i],IDs), match(el_19_nodup$id_d[i],IDs)]<-1
}
table(mat_19_all_actors)
isSymmetric(mat_19_all_actors)
mat_19_all_actors<-symmetrize(mat_19_all_actors, rule = "weak") # sym to make network symmetric
isSymmetric(mat_19_all_actors)
table(mat_19_all_actors)
# 3868 /2 = same number of ties!
net_19_all_actors<-network(mat_19_all_actors,directed = F) 
plot(net_19_all_actors, vertex.cex =.2,  arrowhead.cex = 0)
save(mat_19_all_actors, file="adjmat_2019_all_actors.RData")

############## 12. ANALYSIS REPLICATION CODE ############## 

#Also included as supplemental material in: 
#McMillan, Cassie, Mark C. Pachucki, Jiaao Yu, A. James O’Malley, 
#Anne N. Thorndike, and Douglas E. Levy. "Network threats to causal inference: 
#Variations in network position by participation in randomized controlled 
#trials." Social Networks 86 (2026): 229-239.

#### Step 1. SAOM Estimation ####

library(RSiena) 
library(parallel)

# Load the data 

load(file="adjmat_2016_all_actors.RData") # 2016 co-purchasing adjacency matrix
net1<-as.matrix(mat_16_all_actors)
load(file="adjmat_2017_all_actors.RData") # 2017 co-purchasing adjacency matrix
net2<-as.matrix(mat_17_all_actors)
load(file="adjmat_2018_all_actors.RData") # 2018 co-purchasing adjacency matrix
net3<-as.matrix(mat_18_all_actors)
load(file="adjmat_2019_all_actors.RData") # 2019 co-purchasing adjacency matrix
net4<-as.matrix(mat_19_all_actors)

load("actor_attr.RData") # Employee-level data

# create objects needed for SAOM
nactor<-NROW(net1)
purch_net<- sienaNet(array(c(net1, net2, net3, net4), dim=c(nactor, nactor, 4))) # network DV 

# Composition change 
load("compchange_1_2025.RData") # data with informtion on when employees joined and leaved the network
changes<-sienaCompositionChange(compchange) # joiner and leaver file


# create SIENA objects for constant actor-level covariates
race4<-coCovar(actor_attr$race4)
hisp<-coCovar(actor_attr$hisp)
black<-coCovar(actor_attr$black)
oth_as<-coCovar(actor_attr$other_asian)
white<-coCovar(actor_attr$white)
sex<-coCovar(actor_attr$sex_num)
job<-coCovar(actor_attr$job)
admin<-coCovar(actor_attr$admin)
mgmt_clinician <-coCovar(actor_attr$mgmt_clinician)
prof<-coCovar(actor_attr$prof)
service<-coCovar(actor_attr$service)
tech<-coCovar(actor_attr$tech)
educ<-coCovar(actor_attr$ed_cat)
evertrial<-coCovar(actor_attr$evertrial)

# create SIENA object for time-varying actor-level covariate(s): 
age_18_29<-varCovar(as.matrix(cbind(actor_attr$age_18_29_2016,actor_attr$age_18_29_2017, actor_attr$age_18_29_2018, actor_attr$age_18_29_2019)))
age_30_39<-varCovar(as.matrix(cbind(actor_attr$age_30_39_2016,actor_attr$age_30_39_2017, actor_attr$age_30_39_2018, actor_attr$age_30_39_2019)))
age_40_49<-varCovar(as.matrix(cbind(actor_attr$age_40_49_2016,actor_attr$age_40_49_2017, actor_attr$age_40_49_2018, actor_attr$age_40_49_2019)))
age_50<-varCovar(as.matrix(cbind(actor_attr$age_50_2016,actor_attr$age_50_2017, actor_attr$age_50_2018, actor_attr$age_50_2019)))
age_cat<-varCovar(as.matrix(cbind(actor_attr$age_cat_2016,actor_attr$age_cat_2017, actor_attr$age_cat_2018, actor_attr$age_cat_2019)))


# create SIENA object for the dependent individual-level variable (HPS-4)
hps_DV<-sienaDependent(as.matrix(cbind(actor_attr$hps_cat_2016,actor_attr$hps_cat_2017,actor_attr$hps_cat_2018,actor_attr$hps_cat_2019)), type="behavior", allowOnly=FALSE) # !!! changed name of DV and input to alcohol names


# create the SIENA data object;
fulldata <- sienaDataCreate(purch_net,
                            race4,
                            white,
                            hisp,
                            black,
                            oth_as,
                            sex,
                            job,
                            admin,
                            mgmt_clinician,
                            prof,
                            service,
                            tech,
                            dept,
                            educ,
                            age_18_29,
                            age_30_39,
                            age_40_49,
                            age_50,
                            age_cat,
                            hps_DV,
                            evertrial,
                            changes)


# Create an effects object from the data object
fulleff<-getEffects(fulldata)
fulleff

# Add all effects to the SAOM

# Structural network effects  
fulleff<-setEffect(fulleff, transTriads, name = "purch_net")
fulleff<-setEffect(fulleff, inPopSqrt, name = "purch_net")
fulleff<-setEffect(fulleff, outInAss, parameter = 2, name = "purch_net")
fulleff<-setEffect(fulleff, outTrunc, parameter = 1, name = "purch_net")


# Actor-based network effects
fulleff<-setEffect(fulleff, egoX, interaction1 = "age_18_29") 
fulleff<-setEffect(fulleff, egoX, interaction1 = "age_30_39") 
fulleff<-setEffect(fulleff, egoX, interaction1 = "age_40_49") 
fulleff<-setEffect(fulleff, sameX, interaction1 = "age_cat") 

fulleff<-setEffect(fulleff, sameX, interaction1 = "educ")
fulleff<-setEffect(fulleff, sameX, interaction1 = "job")
fulleff<-setEffect(fulleff, sameX, interaction1 = "race4")
fulleff<-setEffect(fulleff, egoX, interaction1 = "hisp")
fulleff<-setEffect(fulleff, egoX, interaction1 = "black")
fulleff<-setEffect(fulleff, egoX, interaction1 = "oth_as")
fulleff<-setEffect(fulleff, sameX, interaction1 = "sex")
fulleff<-setEffect(fulleff, egoX, interaction1 = "sex")
fulleff<-setEffect(fulleff, egoX, interaction1 = "evertrial")
fulleff<-setEffect(fulleff, sameX, interaction1 = "evertrial")
fulleff<-setEffect(fulleff, egoX, interaction1 = "hps_DV")
fulleff<-setEffect(fulleff, simX, interaction1 = "hps_DV")

# Behavior(HPS) dynamics
fulleff<- setEffect(fulleff, avAlt, name = "hps_DV", interaction1 = "purch_net")  
fulleff<- setEffect(fulleff, effFrom, name ='hps_DV', interaction1 = 'intervention')
fulleff<- setEffect(fulleff, effFrom, name ='hps_DV', interaction1 = 'control')
fulleff<- setEffect(fulleff, effFrom, name ='hps_DV', interaction1 = 'age_18_29')
fulleff<- setEffect(fulleff, effFrom, name ='hps_DV', interaction1 = 'age_30_39')
fulleff<- setEffect(fulleff, effFrom, name ='hps_DV', interaction1 = 'age_40_49')
fulleff<- setEffect(fulleff, effFrom, name ='hps_DV', interaction1 = 'admin')
fulleff<- setEffect(fulleff, effFrom, name ='hps_DV', interaction1 = 'prof')
fulleff<- setEffect(fulleff, effFrom, name ='hps_DV', interaction1 = 'service')
fulleff<- setEffect(fulleff, effFrom, name ='hps_DV', interaction1 = 'tech')
fulleff<- setEffect(fulleff, effFrom, name ='hps_DV', interaction1 = 'sex')
fulleff<- setEffect(fulleff, effFrom, name ='hps_DV', interaction1 = 'hisp')
fulleff<- setEffect(fulleff, effFrom, name ='hps_DV', interaction1 = 'black')
fulleff<- setEffect(fulleff, effFrom, name ='hps_DV', interaction1 = 'oth_as')

fulleff

# Set initial values (based on prior SAOM runs)
fulleff[fulleff$effectName=='constant purch_net rate (period 1)' & fulleff$type=='rate', 'initialValue'] <-3.4408
fulleff[fulleff$effectName=='constant purch_net rate (period 2)' & fulleff$type=='rate', 'initialValue'] <-4.0844
fulleff[fulleff$effectName=='constant purch_net rate (period 3)' & fulleff$type=='rate', 'initialValue'] <-4.8175
fulleff[fulleff$effectName=='degree (density)' & fulleff$type=='eval', 'initialValue'] <- -6.5451
fulleff[fulleff$effectName=='transitive triads' & fulleff$type=='eval', 'initialValue'] <- 1.6478
fulleff[fulleff$effectName=='sqrt degree of alter' & fulleff$type=='eval', 'initialValue'] <- 1.0521
fulleff[fulleff$effectName=='degree^(1/#) assortativity' & fulleff$type=='eval', 'initialValue'] <- -0.5265
fulleff[fulleff$effectName=='outdegree-trunc(#)' & fulleff$type=='eval', 'initialValue'] <-  -4.1596
fulleff[fulleff$effectName=='same race4' & fulleff$type=='eval', 'initialValue'] <- 0.4997
fulleff[fulleff$effectName=='hisp ego' & fulleff$type=='eval', 'initialValue'] <-  0.7873
fulleff[fulleff$effectName=='black ego' & fulleff$type=='eval', 'initialValue'] <-  0.7702
fulleff[fulleff$effectName=='oth_as ego' & fulleff$type=='eval', 'initialValue'] <- 0.3129
fulleff[fulleff$effectName=='sex ego' & fulleff$type=='eval', 'initialValue'] <-  -0.8637 
fulleff[fulleff$effectName=='same sex' & fulleff$type=='eval', 'initialValue'] <- 1.4851
fulleff[fulleff$effectName=='same job' & fulleff$type=='eval', 'initialValue'] <-  1.5766
fulleff[fulleff$effectName=='same educ' & fulleff$type=='eval', 'initialValue'] <-  0.4913
fulleff[fulleff$effectName=='hps_DV ego' & fulleff$type=='eval', 'initialValue'] <-  -0.1215
fulleff[fulleff$effectName=='hps_DV similarity' & fulleff$type=='eval', 'initialValue'] <- 0.5546
fulleff[fulleff$effectName=='age_18_29 ego' & fulleff$type=='eval', 'initialValue'] <- 0.4204
fulleff[fulleff$effectName=='age_30_39 ego' & fulleff$type=='eval', 'initialValue'] <- -0.1078
fulleff[fulleff$effectName=='age_40_49 ego' & fulleff$type=='eval', 'initialValue'] <- 0.3732
fulleff[fulleff$effectName=='same age_cat' & fulleff$type=='eval', 'initialValue'] <- 0.6407

fulleff[fulleff$effectName=='rate hps_DV (period 1)' & fulleff$type=='rate', 'initialValue'] <- 0.6207
fulleff[fulleff$effectName=='rate hps_DV (period 2)' & fulleff$type=='rate', 'initialValue'] <- 0.6954
fulleff[fulleff$effectName=='rate hps_DV (period 3)' & fulleff$type=='rate', 'initialValue'] <- 0.6705 
fulleff[fulleff$effectName=='hps_DV linear shape' & fulleff$type=='eval', 'initialValue'] <-  0.1326
fulleff[fulleff$effectName=='hps_DV quadratic shape' & fulleff$type=='eval', 'initialValue'] <--1.47
fulleff[fulleff$effectName=='hps_DV average alter' & fulleff$type=='eval', 'initialValue'] <-2.577
fulleff[fulleff$effectName=='hps_DV: effect from hisp' & fulleff$type=='eval', 'initialValue'] <--0.2683
fulleff[fulleff$effectName=='hps_DV: effect from black' & fulleff$type=='eval', 'initialValue'] <--0.4979
fulleff[fulleff$effectName=='hps_DV: effect from oth_as' & fulleff$type=='eval', 'initialValue'] <- -0.4255

fulleff[fulleff$effectName=='hps_DV: effect from sex' & fulleff$type=='eval', 'initialValue'] <- 0.0943
fulleff[fulleff$effectName=='hps_DV: effect from admin' & fulleff$type=='eval', 'initialValue'] <--0.7482
fulleff[fulleff$effectName=='hps_DV: effect from prof' & fulleff$type=='eval', 'initialValue'] <-0.0689
fulleff[fulleff$effectName=='hps_DV: effect from service' & fulleff$type=='eval', 'initialValue'] <- -0.7381
fulleff[fulleff$effectName=='hps_DV: effect from tech' & fulleff$type=='eval', 'initialValue'] <- -0.5829

fulleff[fulleff$effectName=='hps_DV: effect from age_18_29' & fulleff$type=='eval', 'initialValue'] <--0.4465
fulleff[fulleff$effectName=='hps_DV: effect from age_30_39' & fulleff$type=='eval', 'initialValue'] <--0.3834
fulleff[fulleff$effectName=='hps_DV: effect from age_40_49' & fulleff$type=='eval', 'initialValue'] <--0.2106


fulleff


# Estimate the SAOM

modeloptions <- sienaAlgorithmCreate(useStdInits = FALSE, n3 = 1300, nsub = 3)
output<-siena07(modeloptions, data=fulldata, effects=fulleff, batch=TRUE, verbose=FALSE, nbrNodes=2, useCluster=TRUE, initC=TRUE, returnDeps = TRUE) 

# Additionally code run to achieve convergence:
#modeloptions <- sienaAlgorithmCreate(useStdInits = FALSE, n3 = 1500, nsub = 3)
#output<-siena07(modeloptions, data=fulldata, effects=fulleff, batch=TRUE, verbose=FALSE, nbrNodes=2, useCluster=TRUE, initC=TRUE, returnDeps = TRUE,prevAns = output)

output


#### Step 2. SAOM Simulations ####

#changes fulleff object to the observed values from the SAOM estimated in Step 1
fulleff$initialValue[fulleff$include] <- output$theta

# Code needed for both knockout experiments explained below
# KO1: remove differences in network position; KO2: remove peer influence

# KO1: set the following trial-related network eval effects to 0
fulleff[fulleff$effectName=='evertrial ego' & fulleff$type=='eval', 'initialValue'] <- 0
fulleff[fulleff$effectName=='evertrial similarity' & fulleff$type=='eval', 'initialValue'] <- 0

# KO2: set the peer influence effect to 0:
fulleff[fulleff$effectName=='hps_DV average alter' & fulleff$type=='eval', 'initialValue'] <- 0

fulleff

# Run 1000 simulations for each knock out experiment:

InitAlg <- sienaAlgorithmCreate(projname="Init", useStdInits=FALSE,
                                cond=FALSE, nsub=0, n3=1000, simOnly=TRUE, seed = 30323)

InitSim   <- siena07(InitAlg, data=fulldata, eff=fulleff,
                     returnDeps=TRUE, batch=TRUE)


#### Step 3. Compare simulation output to the observed data ####

# Calculate Average HPS-4 for all actors at the end of the observed study (2019)
hps4<- mean(actor_attr$hps_cat_2019, na.rm = T)
hps4
sd(actor_attr$hps_cat_2019, na.rm = T)

# Calculate Average HPS-4 for intervention participants at the end of the observed study (2019)
sum(actor_attr$intervention_ever)
inter_obs<-c()
for (j in 1:nactor) {
  if (actor_attr$intervention_ever[j] == 1){
    inter_obs <-rbind(inter_obs,actor_attr$hps_cat_2019[j])} }
inter_obs
table(inter_obs)

hps4_interv<-mean(inter_obs, na.rm = T)
hps4_interv
sd(inter_obs, na.rm = T)

# Calculate Average HPS-4 for control participants at the end of the observed study (2019)

sum(actor_attr$control_ever)
cont_obs<-c()
for (j in 1:nactor) {
  if (actor_attr$control_ever[j] == 1){
    cont_obs <-rbind(cont_obs,actor_attr$hps_cat_2019[j])} }
cont_obs
table(cont_obs)
hps4_cont<-mean(cont_obs, na.rm = T)
hps4_cont
sd(cont_obs, na.rm = T)


# Calculate Average HPS-4 for all actors at the end of the simulation. Remove actors who should be 
# missing in 2019 because they left the workplace.
table(actor_attr$hps_cat_2019)
nactor<-2890
nactor_nomiss<-2890-449 #449 are not in sample at final wave
nsim<-1000
Zs5_noHPS_nomiss <- NULL
Zs5_noHPS_nomiss <- array(NA, dim=c(2890,1))
Zb5_noHPS_nomiss <- NULL
Zb5_noHPS_nomiss <- array (0, dim=c(nsim, 1))
for (m in 1:nsim) {
  for (n in 1:nactor) {
    if(is.na(actor_attr$hps_cat_2019[n])==F) {Zs5_noHPS_nomiss[n,1] <-  InitSim$sims[[m]][[1]]$hps_DV[[3]][[n]]}
  }
  Zb5_noHPS_nomiss[m] <-mean(Zs5_noHPS_nomiss, na.rm=T)
}
Zb5_noHPS_nomiss
mean(Zb5_noHPS_nomiss) 
sd(Zb5_noHPS_nomiss)
t.test(Zb5_noHPS_nomiss,mu =hps4) # test for significant difference between simulated and observed average



# Calculate Average HPS-4 for intervention participants at the end of the simulation. Remove actors who should be 
# missing in 2019 because they left the workplace.

ninter<- 168 
inter_all_noHPS_nomiss <- NULL
inter_all_noHPS_nomiss   <-  array (0, dim=c(nsim, 1))
Zs5_inter_nomiss_sum <- array(NA, dim=c(nactor,1))


for (i in 1:nsim) {
  inter_each_noHPS_nomiss  <- NULL
  inter_each_noHPS_nomiss  <- c()
  for (j in 1:nactor) {
    if (actor_attr$intervention_ever[j] == 1){
      if(is.na(actor_attr$hps_cat_2016[n])==F) {Zs5_inter_nomiss_sum[n,1] <-  actor_attr$hps_cat_2016[n]}
      if(is.na(actor_attr$hps_cat_2017[n])==F) {Zs5_inter_nomiss_sum[n,1] <-  Zs5_inter_nomiss_sum[n,1]+  InitSim$sims[[m]][[1]]$hps_DV[[1]][[n]]}
      if(is.na(actor_attr$hps_cat_2018[n])==F) {Zs5_inter_nomiss_sum[n,1] <-  Zs5_inter_nomiss_sum[n,1]+ InitSim$sims[[m]][[1]]$hps_DV[[2]][[n]]}
      if(is.na(actor_attr$hps_cat_2019[n])==F) {Zs5_inter_nomiss_sum[n,1] <-  Zs5_inter_nomiss_sum[n,1]+ InitSim$sims[[m]][[1]]$hps_DV[[3]][[n]]}
      
      
      inter_each_noHPS_nomiss  <-rbind(inter_each_noHPS_nomiss ,Zs5_inter_nomiss_sum[n,1])
      
    }
  }
  inter_all_noHPS_nomiss [i] <-colSums(inter_each_noHPS_nomiss , na.rm=T)/ninter
}
inter_all_noHPS_nomiss
mean(inter_all_noHPS_nomiss) 
sd(inter_all_noHPS_nomiss) 
t.test(inter_all_noHPS_nomiss,mu =hps4_interv) #  test for significant difference between simulated and observed average



# Calculate Average HPS-4 for control participants at the end of the simulation. Remove actors who should be 
# missing in 2019 because they left the workplace.
actor_attr$control_ever
ncont<-165


cont_all_noHPS_nomiss <- NULL
cont_all_noHPS_nomiss  <-  array (0, dim=c(nsim, 1))

for (i in 1:nsim) {
  cont_each_noHPS_nomiss <- NULL
  cont_each_noHPS_nomiss <- c()
  for (j in 1:nactor) {
    if (actor_attr$control_ever[j] == 1& is.na(actor_attr$hps_cat_2019[j])==F){
      cont_each_noHPS_nomiss <-rbind(cont_each_noHPS_nomiss,InitSim$sims[[i]][[1]]$hps_DV[[3]][[j]])}
  }
  cont_all_noHPS_nomiss[i] <-colSums(cont_each_noHPS_nomiss, na.rm=T)/ncont
}
cont_all_noHPS_nomiss
mean(cont_all_noHPS_nomiss, na.rm = T) 
t.test(cont_all_noHPS_nomiss,mu =hps4_cont) #  test for significant difference between simulated and observed average
sd(cont_all_noHPS_nomiss, na.rm = T) 


# Compare the difference between the HPS-4 of the intervention & control groups in the observed data
# versus the simulated data.
diff_noHPS_nomiss<- inter_all_noHPS_nomiss -cont_all_noHPS_nomiss
mean (diff_noHPS_nomiss)
sd (diff_noHPS_nomiss)
t.test(diff_noHPS_nomiss,mu =hps4_interv-hps4_cont) #  test for significant difference between simulated and observed 

#### END ####
