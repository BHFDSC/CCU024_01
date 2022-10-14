clear
set more off
capture log close

log using "D:\Users\joannamariedavies\Desktop\CovPall CCUO24\Joanna Davies\logs", replace
cd "D:\Users\joannamariedavies\Desktop\CovPall CCUO24\Joanna Davies"

global raw "raw"
global work "work"
global output "output"
global graphs "output/graphs"

clear 
odbc load, exec("SELECT * FROM dars_nic_391419_j3w9t_collab.ccu024_01_cohort_deaths") dsn("databricks")
/*deaths from 2018-2020*/
sort PERSON_ID
save "$raw/deaths_2018_2020.dta", replace

clear
odbc load, exec("SELECT * FROM dars_nic_391419_j3w9t_collab.ccu024_01_cohort_hes_ae") dsn("databricks")
/*ae for deaths from 2018-2020*/
/*check and drop dups based on arrival date and time*/
duplicates tag AEKEY, gen(tag1)
duplicates tag PERSON_ID ARRIVALDATE ARRIVALTIME, gen(tag2)
duplicates drop PERSON_ID ARRIVALDATE ARRIVALTIME, force
sort PERSON_ID
drop tag1 tag2
save "$raw/hesAE_deaths_2018_2020.dta", replace

clear
odbc load, exec("SELECT * FROM dars_nic_391419_j3w9t_collab.ccu024_01_skinny_deaths") dsn("databricks")
/*linked in demogs*/
sort PERSON_ID
save"$raw/demogs_deaths_2018_2020.dta", replace

clear
odbc load, exec("SELECT * FROM dss_corporate.ons_chd_geo_listings") dsn("databricks")

clear
odbc load, exec("SELECT * FROM dss_corporate.hesf_ethnicity") dsn("databricks")
rename ETHNICITY_CODE ETHNIC
rename ETHNICITY_DESCRIPTION Labelhes
keep ETHNIC Label
save "$raw/hes_ethnicity.dta", replace

clear
odbc load, exec("SELECT * FROM dss_corporate.gdppr_ethnicity") dsn("databricks")
rename Value ETHNIC
rename Label Labelgp
keep ETHNIC Labelgp
save "$raw/gp_ethnicity.dta", replace

clear
insheet using "$raw/IMD_2019_lsoa_lookup.csv"
rename lsoacode2011 LSOA
sort LSOA
save "$raw/IMD_2019_lsoa_lookup.dta", replace

clear
insheet using "$raw/lsoa_STP_lookup.csv"
rename lsoa11cd LSOA
sort LSOA
save "$raw/lsoa_STP_lookup.dta", replace

clear
insheet using "$raw\stp_region_lookup.csv"
sort stp20cd
save "$raw/stp_region_lookup.dta", replace


/******************************************************/
/*merge the files*/
clear
use "$raw/deaths_2018_2020.dta"
merge 1:1 PERSON_ID using "$raw/demogs_deaths_2018_2020.dta"
drop _merge
/*data contains deaths registered in Wales - the fuzzy link to lsoa using HES/GP only draws on english HES/GP - most with missing LSOA will be Welsh deaths but NB REG_DISTRICT_CODE is the place the death was registered, not necessarily the home of the deceased*/
/*so first keep only the deahts from people in england, then drop out if REG_DISTRICT_CODE>"799" & LSOA=.*/
/*REG_DISTRICT_CODE>"799" seems to correspond to welsh REG_DISTRICT_NAME, apart from no name for 812 - tom bolton is trying to find a look up*/
gen country=""
replace country="E" if substr(LSOA, 1, 1) == "E"
replace country="W" if substr(LSOA, 1, 1) == "W"
replace country="S" if substr(LSOA, 1, 1) == "S"
replace country="missing" if substr(LSOA, 1, 1) == ""
tab country, mi

drop if country=="S" | country=="W"
tab country if REG_DISTRICT_CODE>"799", mi

drop if REG_DISTRICT_CODE>"799" & country!="E"
tab country, missing

sort LSOA
merge m:1 LSOA using "$raw/IMD_2019_lsoa_lookup.dta"
/*4 LSOAs with no deaths? lsoaname2011
potentially inner city area with young populations*/
sort LSOA
drop _merge
merge m:1 LSOA using "$raw/lsoa_STP_lookup.dta"
drop _merge
drop if PERSON_ID==""
sort PERSON_ID
sort stp20cd
merge m:1 stp20cd using "$raw/stp_region_lookup.dta"
drop _merge
sort ETHNIC
merge m:1 ETHNIC using "$raw/hes_ethnicity.dta"
drop _merge
sort ETHNIC
merge m:1 ETHNIC using "$raw/gp_ethnicity.dta"
drop _merge
merge 1:m PERSON_ID using "$raw/hesAE_deaths_2018_2020.dta"
/*9589 not matched from using - most are ae lsoas that are welsh - so these are people that we have dropped out earlier becuase their lsoa was not english - in the small number of cases where this ae lsoa is english it must be because a more recent non-english lsoa was available - so still right to drop out these ones. I have checked that all with available ae lsoa have non-missing lsoa in demog link file. */
drop if _merge==2
drop _merge
save "$work\merged death_ae_geog.dta", replace


/***************************************************************/
/*prep the data*/
clear
use "$work\merged death_ae_geog.dta"
browse *date* *DATE*

/*create a unique count of deaths for use later*/
sort PERSON_ID
gen death=.
replace death=1 if PERSON_ID!=PERSON_ID[_n-1]

/*gen age at death*/
gen byte age_atdeath=(REG_DATE_OF_DEATH-DOB)/365
format age_atdeath %3.0f
/*age cats*/
tab age_atdeath
sum age_atdeath, detail
recode age_atdeath (0/64=1) (65/84=2) (85/120=3), gen(age_cats)
label define age_cats 1 "<65" 2 "65-84" 3 "85+"
label values age_cats age_cats
tab age_cats
/*10 year age bands - max age at death is 100 so group at 101*/
egen age_cat10=cut(age_atdeath), at(0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 101)

/*sex*/
bys SEX: sum age_atdeath
/* 1 = men*/
encode SEX, gen(sex2)
recode sex2 (4=1)
label define sex 1 other 2 men 3 women
label values sex2 sex 

/*ethnicity*/
gen ethnicity=Labelgp
replace ethnicity=Labelhes if Labelgp==""
encode ethnicity, gen(ethnicity2)
label list ethnicity2
recode ethnicity2 (12 = 1) (1 9 = 2) (10 13 = 3) (8 = 4) (20 = 5) (15 = 6) (6 23 24 25 = 7) (14 = 8) (4 16 21 22 =9) (2 3 5 7 11 = 10) (17 18 19 = .), gen(ethnicity3)
label define ethnicity 1 "white" 2 "black african" 3 "black caribbean" 4 "bangladeshi" 5 "pakistani" 6 "indian" 7 "mixed" 8 "chinese" 9 "white other" 10 "other"
label values ethnicity3 ethnicity
tab ethnicity3, mi
tab ethnicity2 ethnicity3, mi

/*gen year of death*/
gen death_year=year(REG_DATE_OF_DEATH)

/*time between death and admission*/
gen days_da=ARRIVALDATE-REG_DATE_OF_DEATH
label var days_da "days between death and admission"
gen flag=1 if days_da>0 & days_da!=.
tab flag, mi
/*<0.5% of admissions have a date of death before the admission date - set these days_da to missing so they are dropped from the analysis later*/
replace days_da=. if flag==1
drop flag
/*flag admissions in last 3 months and last 12 months*/
gen last_3m=.
replace last_3m = 1 if days_da>=-90 & days_da!=.
gen last_12m=.
replace last_12m=1 if days_da>=-360 & days_da!=.
/*gen months between death and admission*/
gen months_da=.
label var months_da "month before death"
replace months_da=1 if (days_da<=0 & days_da>=-30) & days_da!=.
replace months_da=2 if (days_da<=-31 & days_da>=-60) & days_da!=.
replace months_da=3 if (days_da<=-61 & days_da>=-90) & days_da!=.
replace months_da=4 if (days_da<=-91 & days_da>=-120) & days_da!=.
replace months_da=5 if (days_da<=-121 & days_da>=-150) & days_da!=.
replace months_da=6 if (days_da<=-151 & days_da>=-180) & days_da!=.
replace months_da=7 if (days_da<=-181 & days_da>=-210) & days_da!=.
replace months_da=8 if (days_da<=-211 & days_da>=-240) & days_da!=.
replace months_da=9 if (days_da<=-241 & days_da>=-270) & days_da!=.
replace months_da=10 if (days_da<=-271 & days_da>=-300) & days_da!=.
replace months_da=11 if (days_da<=-301 & days_da>=-330) & days_da!=.
replace months_da=12 if (days_da<=-331 & days_da>=-360) & days_da!=.

/*OOH flag*/
/*flag time between 18:00-08:00*/
gen double arrival_time2 = clock(ARRIVALTIME, "hm")
format arrival_time2 %tc_HH:MM
gen OOH=0
replace OOH=1 if arrival_time2 >= tc(18:00) & arrival_time2!=.
replace OOH=1 if arrival_time2 < tc(8:00) & arrival_time2!=.
/*flag weekends*/
gen week_day = dow(ARRIVALDATE)
replace OOH=1 if week_day==0 | week_day==6
/*flag bank hols*/
replace OOH=1 if ARRIVALDATE==d(01jan2019)
replace OOH=1 if ARRIVALDATE==d(19apr2019)
replace OOH=1 if ARRIVALDATE==d(22apr2019)
replace OOH=1 if ARRIVALDATE==d(06may2019)
replace OOH=1 if ARRIVALDATE==d(27may2019)
replace OOH=1 if ARRIVALDATE==d(26aug2019)
replace OOH=1 if ARRIVALDATE==d(25dec2019)
replace OOH=1 if ARRIVALDATE==d(26dec2019)
/**/
replace OOH=1 if ARRIVALDATE==d(01jan2020)
replace OOH=1 if ARRIVALDATE==d(10apr2020)
replace OOH=1 if ARRIVALDATE==d(13apr2020)
replace OOH=1 if ARRIVALDATE==d(08may2020)
replace OOH=1 if ARRIVALDATE==d(25may2020)
replace OOH=1 if ARRIVALDATE==d(31aug2020)
replace OOH=1 if ARRIVALDATE==d(25dec2020)
replace OOH=1 if ARRIVALDATE==d(28dec2020)
/*gen in hours flag*/
gen IOED=0
replace IOED=1 if OOH==0

/*cause of death*/
/*MCoD*/
codebook S_UNDERLYING_COD_ICD10 /*<1% missing*/
icd10cm check S_UNDERLYING_COD_ICD10, generate(invalid)
tab S_UNDERLYING_COD_ICD10 if invalid==99
icd10cm clean S_UNDERLYING_COD_ICD10, gen (Main_cause_clean)
icd10cm generate Main_causeR =  Main_cause_clean, description
icd10cm generate Main_causeR1 =  Main_cause_clean, categor

*generate covid death from underlying cause of death
gen covid_death=.
replace covid_death=1 if Main_cause_clean=="U07.1" | Main_cause_clean=="U07.2"
replace covid_death=0 if covid_death!=1
tab covid_death, m

gen underlying_chap=.
replace underlying_chap=1 if Main_cause_clean>="A00" & Main_cause_clean<="B99"
replace underlying_chap=2 if Main_cause_clean>="C00" & Main_cause_clean<="D49"
replace underlying_chap=3 if Main_cause_clean>="D50" & Main_cause_clean<="D90"
replace underlying_chap=4 if Main_cause_clean>="E00" & Main_cause_clean<="E90"
replace underlying_chap=5 if Main_cause_clean>="F00" & Main_cause_clean<="F99"
replace underlying_chap=6 if Main_cause_clean>="G00" & Main_cause_clean<="G99"
replace underlying_chap=7 if Main_cause_clean>="H00" & Main_cause_clean<="H59"
replace underlying_chap=8 if Main_cause_clean>="H60" & Main_cause_clean<="H95"
replace underlying_chap=9 if Main_cause_clean>="I00" & Main_cause_clean<="I99"
replace underlying_chap=10 if Main_cause_clean>="J00" & Main_cause_clean<="J99"
replace underlying_chap=11 if Main_cause_clean>="K00" & Main_cause_clean<="K93"
replace underlying_chap=12 if Main_cause_clean>="L00" & Main_cause_clean<="L99"
replace underlying_chap=13 if Main_cause_clean>="M00" & Main_cause_clean<="M99"
replace underlying_chap=14 if Main_cause_clean>="N00" & Main_cause_clean<="N99"
replace underlying_chap=15 if Main_cause_clean>="O00" & Main_cause_clean<="O999"
replace underlying_chap=16 if Main_cause_clean>="P00" & Main_cause_clean<="P96"
replace underlying_chap=17 if Main_cause_clean>="Q00" & Main_cause_clean<="Q99"
replace underlying_chap=18 if Main_cause_clean>="R00" & Main_cause_clean<="R99"
replace underlying_chap=19 if Main_cause_clean>="S00" & Main_cause_clean<="T98"
replace underlying_chap=20 if Main_cause_clean>="V01" & Main_cause_clean<="Y98"
replace underlying_chap=21 if Main_cause_clean>="Z00" & Main_cause_clean<="Z99"
replace underlying_chap=22 if Main_cause_clean>="U00" & Main_cause_clean<="U85"
replace underlying_chap=. if S_UNDERLYING_COD_ICD10==""

lab def underlying_chapL1 0"Covid-19" 1"Infectious and parasitic diseases" 2"Neoplasms" 3"Diseases of the blood and blood forming organs and certain disorders involving immune mechanism" 4"Endocrine, nutritional and metabolic diseases" 5"Mental and behavioural disorders" 6"Diseases of the nervous system" 7"Diseases of the eye" 8"Diseases of the ear and mastoid process" 9"Diseases of the circulatory system" 10"Diseases of the respiratory system" 11"Diseases of the digestive system" 12"Diseases of the skin and subcutaneous tissue" 13"Disease of the musculoskeletal system and connective tissue" 14"Disease of the genitounrinary system" 15"Pregnancy, childbirth and the puerperium" 16"Certain conditions originating in the perinatal period" 17"Congenital malformations, deformations and chromosomal abnormalities" 18"Symptoms, signs and abnormal clinical and laboratory findings, not elsewhere classified" 19"Injury, poisoning and certain other consequences of external causes" 20"External causes of morbidity and mortality" 21"Factors influencing health status and contact with health services" 22"Codes for special purposes", replace 
lab val underlying_chap underlying_chapL1

*Main causes of death
gen COD_cat=.
replace COD_cat=1 if underlying_chap==2
replace COD_cat=2 if Main_cause_clean>="F00" & Main_cause_clean<="F03" | Main_cause_clean>="G30" & Main_cause_clean<"G31"
replace COD_cat=3 if underlying_chap==9
replace COD_cat=4 if underlying_chap==10
replace COD_cat=5 if COD_cat==. & underlying_chap!=.

lab def COD_cat 1"cancer" 2"dementia" 3"cardiovascular" 4"respiratory" 5"other"
lab val COD_cat COD_cat
tab COD_cat, mi

/*imd quintiles*/
tab indexofmultipledeprivationimddec, mi
recode indexofmultipledeprivationimddec (1/2=1) (3/4=2) (5/6=3) (7/8=4) (9/10=5), gen(imd_quints)
tab indexofmultipledeprivationimddec imd_quints, mi
/*check imd against age - more deprived die younger*/
bys imd_quints: sum age_atdeath

/*ICS/STP*/
codebook stp20nm
encode stp20nm, gen(stp)

/*region*/
codebook nhser20nm
encode nhser20nm, gen(region)
label define region2 1 East 2 London 3 Midlands 4 "N'East/Y'shire'" 5 "N'West" 6 "S'East" 7 "S'West"
label values region region2

/*ethnicity*/
/*WAITING FOR ACCESS TO THE LOOK UPS*/

save "$work/OOH_cleaned.dta", replace


/*******************************************************************/
/***ANALYSIS***/
/*check main outcomes for outliers etc*/
clear
use "$work/OOH_cleaned.dta"
keep if death_year==2020 | death_year==2019
gen last12m_OOH=1 if last_12m==1 & OOH==1
collapse (sum)last_12m (sum)last12m_OOH, by(PERSON_ID death_year)
bys death_year: sum last_12m, detail
bys death_year: sum last12m_OOH, detail
/*2020: all ed max 221; ooh max 175*/
/*2019: all ed max 256; ooh max 189*/


/*table 1*/
clear 
use "$work/OOH_cleaned.dta"
keep if death_year==2020
gen age25=age_atdeath
gen age75=age_atdeath
collapse  (median)age_atdeath (p25)age25 (p75)age75
save "$work/age.dta", replace
/**/
clear 
use "$work/OOH_cleaned.dta"
keep if death_year==2020
foreach var of varlist sex2 COD_cat imd_quints region ethnicity3 {
preserve
replace `var'=99 if `var'==.
collapse (sum)death (sum)last_12m, by(OOH `var')
reshape wide death last_12m, i(`var') j(OOH)
replace death0=0 if death0==.
replace death1=0 if death1==.
replace last_12m0=0 if last_12m0==.
replace last_12m1=0 if last_12m1==.
gen alldeaths=death0+death1
drop death0 death1
gen allED=last_12m0 + last_12m1
gen allEDrate=allED/alldeaths
rename last_12m0 IO
rename last_12m1 OOH
gen IOrate=IO/alldeaths
gen OOHrate=OOH/alldeaths
order `var' alldeaths allED allEDrate IO IOrate OOH OOHrate
save "$work/`var'.dta", replace
restore
}
clear
use "$work\age.dta"
append using "$work\sex2.dta"
append using "$work\ethnicity3.dta"
append using "$work\COD_cat.dta"
append using "$work\imd_quints.dta"
append using "$work\region.dta"
order age* sex2 ethnicity COD_cat imd_quints region
export excel using "$output\table1.xls", firstrow(varlabel) replace

/*all ED compare 2019 and 2020 - probably NOT FOR REPORT*/
clear 
use "$work/OOH_cleaned.dta"
keep if death_year==2020 | death_year==2019
collapse (sum)last_12m (sum)death, by(months_da death_year)

bys death_year: egen alldeaths = sum(death)
drop if months_da==.
drop death

reshape wide last_12m alldeaths, i(months_da) j(death_year)

gen rate2019=last_12m2019/alldeaths2019*1000
gen rate2020=last_12m2020/alldeaths2020*1000

label var rate2019 "2019"
label var rate2020 "2020"

twoway line rate2019 rate2020 months_da, xscale(reverse) xlabel(1(1)12) title("Rate of ED visits per 1,000 deaths in 2019  and 2020", size(*0.7)) graphregion(color(white))

graph save "$graphs\rate per 1000 2019 v 2020", replace 
export excel using "$output\England OOH 2020.xls", firstrow(varlabel) sheet("19v20", replace)


/*2020 only in hours v out of hours*/
clear 
use "$work/OOH_cleaned.dta"
keep if death_year==2020 
collapse (sum)last_12m (sum)death, by(months_da OOH)

egen alldeaths = sum(death)
drop if months_da==.
drop death

reshape wide last_12m alldeaths, i(months_da) j(OOH)
rename last_12m0 ED_visit
rename last_12m1 OOH_ED_visit
drop alldeaths0

gen rateED=ED_visit/alldeaths1*1000
gen rateOOHED=OOH_ED_visit/alldeaths1*1000

label var rateED "in hours"
label var rateOOHED "out of hours"

twoway line rateED rateOOHED months_da, xscale(reverse) xlabel(1(1)12) title("Rate per 1,000 deaths in 2020, of in-hours and out-of-hours" "emergency department visits in the last 12 months of life", size(*0.7)) graphregion(color(white))

graph save "$graphs\rate per 1000 IO and OOH ED", replace 
export excel using "$output\England OOH 2020.xls", firstrow(varlabel) sheet("IOvOOH", replace)

/************************/
/*UNADJUSTED BAR CHART*/
/************************/
/*mdm by age & sex*/
clear 
use "$work/OOH_cleaned.dta"
keep if death_year==2020
drop if imd_quints==. /*3949 (<1%)*/
drop if age_cats==.
keep if sex2==2 | sex2==3
collapse (sum)last_12m (sum)death, by(imd_quints age_cats sex2 OOH)
bys imd_quints age_cats sex2: egen alldeaths = sum(death)
drop if OOH==0

rename last_12m OOH_visits
sort sex2 age_cats imd_quints
drop death
gen rate=OOH_visit/alldeaths*1000
label define imd_quints 1 "1 most deprived" 5 "5 least deprived"
label values imd_quints imd_quints

graph bar (asis)rate, over(imd_quints) over(age_cats) by(sex2, title("Rate per 1,000 deaths in 2020 of out-of-hours ED visits" "for patients in the last 12 months of life, by deprivation, age and sex", size(*0.7)) graphregion(color(white)) note("") l1title("rate per 1000 deaths", size(*0.6))) asyvars bar(1, fcolor(navy) fi(100) blcolor(none)) bar(2, fcolor(navy) fi(85) blcolor(none)) bar(3, fcolor(navy) fi(70) blcolor(none)) bar(4, fcolor(navy) fi(55) blcolor(none)) bar(5, fcolor(navy) fi(40) blcolor(none)) bargap(5) legend(row(1) size(*0.6))

graph save "$graphs\bar age sex", replace
drop OOH
export excel using "$output\England OOH 2020.xls", firstrow(varlabel) sheet("agesex", replace)

/**************************************************************/
/*AGE AND SEX STANDARDISE THE RATES*/
/*first generate a standard population, then calculate the age and sex specific rates for each cod or trust and then collapse down and apply the *1000*/
/*STANDARD POPULATION*/
/*use all deaths in 2019 as the standard populations - i think better to use 2019 than 2020 becuase of increase in deaths in 2020*/
clear 
use "$work/OOH_cleaned.dta"
/*replace age_cat10=10 if age_cat10==0 combine the lowest two age cats - too few 0-10 deaths */
keep if death_year==2019
keep if sex2==2 | sex2==3
drop if age_atdeath==.
duplicates drop PERSON_ID, force
collapse (count)death, by(sex2 age_cat10)
rename death standardpop2019
sort sex2 age_cat10 
save "$work\2019standard_population.dta", replace
/************************************************************/
/*UCOD*/
clear 
use "$work/OOH_cleaned.dta"
keep if death_year==2020
drop if imd_quints==. 
drop if COD_cat==.
keep if sex2==2 | sex2==3
drop if age_atdeath==.
collapse (sum)last_12m (sum)death, by(COD_cat imd_quints age_cat10 sex2 OOH)
bys COD_cat imd_quints sex2 age_cat10: egen alldeaths = sum(death)
drop if OOH==0
drop death
rename last_12m OOHvisits_n
sort sex2 age_cat10 imd_quints COD_cat
merge m:1 sex2 age_cat10 using "$work\2019standard_population.dta"
drop _merge
gen rate=OOHvisits_n/alldeaths
gen exp=rate*standardpop2019
collapse (sum)exp standardpop2019 OOHvisits_n alldeaths, by(imd_quints COD_cat)
sort COD_cat imd_quints
gen rawrate=OOHvisits_n/alldeaths
gen adjrate=exp/standardpop2019
gen adjratepertho=adjrate*1000

label define imd_quints 1 "1 most deprived" 5 "5 least deprived"
label values imd_quints imd_quints

graph bar (asis)adjratepertho, over(imd_quints) over(COD_cat, label(labsize(small))) title("Age and sex standardised rate of out-of-hours ED visits in last 12 months of life" "per 1,000 deaths in 2020, by deprivation and underlying cause of death", size(*0.7)) graphregion(color(white)) note("") l1title("rate per 1000 deaths", size(*0.6)) asyvars bar(1, fcolor(navy) fi(100) blcolor(none)) bar(2, fcolor(navy) fi(85) blcolor(none)) bar(3, fcolor(navy) fi(70) blcolor(none)) bar(4, fcolor(navy) fi(55) blcolor(none)) bar(5, fcolor(navy) fi(40) blcolor(none)) bargap(5) legend(row(1) size(*0.6))

graph save "$graphs\standardised UCOD", replace
drop exp standardpop2019
export excel using "$output\England OOH 2020.xls", firstrow(varlabel) sheet("ucod", replace)

/*REGION*/
clear 
use "$work/OOH_cleaned.dta"
keep if death_year==2020
drop if imd_quints==. 
drop if region==.
keep if sex2==2 | sex2==3
drop if age_atdeath==.
collapse (sum)last_12m (sum)death, by(region imd_quints age_cat10 sex2 OOH)
bys region imd_quints sex2 age_cat10: egen alldeaths = sum(death)
drop if OOH==0
drop death
rename last_12m OOHvisits_n
sort sex2 age_cat10 imd_quints region
merge m:1 sex2 age_cat10 using "$work\2019standard_population.dta"
drop _merge
gen rate=OOHvisits_n/alldeaths
gen exp=rate*standardpop2019
collapse (sum)exp standardpop2019 OOHvisits_n alldeaths, by(imd_quints region)
sort region imd_quints
gen rawrate=OOHvisits_n/alldeaths
gen adjrate=exp/standardpop2019
gen adjratepertho=adjrate*1000

label define imd_quints 1 "1 most deprived" 5 "5 least deprived"
label values imd_quints imd_quints

graph bar (asis)adjratepertho, over(imd_quints) over(region, label(labsize(small))) title("Age and sex standardised rate of out-of-hours ED visits in last 12 months of life" "per 1,000 deaths in 2020, by deprivation and region", size(*0.7)) graphregion(color(white)) note("") l1title("rate per 1000 deaths", size(*0.6)) asyvars bar(1, fcolor(navy) fi(100) blcolor(none)) bar(2, fcolor(navy) fi(85) blcolor(none)) bar(3, fcolor(navy) fi(70) blcolor(none)) bar(4, fcolor(navy) fi(55) blcolor(none)) bar(5, fcolor(navy) fi(40) blcolor(none)) bargap(5) legend(row(1) size(*0.6))

graph save "$graphs\standardised REGION", replace
drop exp standardpop2019
export excel using "$output\England OOH 2020.xls", firstrow(varlabel) sheet("region", replace)

/*ETHNICITY*/
clear 
use "$work/OOH_cleaned.dta"
keep if death_year==2020
drop if imd_quints==. 
drop if ethnicity3==.
keep if sex2==2 | sex2==3
drop if age_atdeath==.
collapse (sum)last_12m (sum)death, by(ethnicity3 imd_quints age_cat10 sex2 OOH)
bys ethnicity3 imd_quints sex2 age_cat10: egen alldeaths = sum(death)
drop if OOH==0
drop death
rename last_12m OOHvisits_n
sort sex2 age_cat10 imd_quints ethnicity3
merge m:1 sex2 age_cat10 using "$work\2019standard_population.dta"
drop _merge
gen rate=OOHvisits_n/alldeaths
gen exp=rate*standardpop2019
collapse (sum)exp standardpop2019 OOHvisits_n alldeaths, by(imd_quints ethnicity3)
sort ethnicity3 imd_quints
gen rawrate=OOHvisits_n/alldeaths
gen adjrate=exp/standardpop2019
gen adjratepertho=adjrate*1000

label define imd_quints 1 "1 most deprived" 5 "5 least deprived"
label values imd_quints imd_quints

graph bar (asis)adjratepertho, over(imd_quints) over(ethnicity3, label(labsize(tiny))) title("Age and sex standardised rate of out-of-hours ED visits in last 12 months of life" "per 1,000 deaths in 2020, by deprivation and ethnicity", size(*0.7)) graphregion(color(white)) note("") l1title("rate per 1000 deaths", size(*0.6)) asyvars bar(1, fcolor(navy) fi(100) blcolor(none)) bar(2, fcolor(navy) fi(85) blcolor(none)) bar(3, fcolor(navy) fi(70) blcolor(none)) bar(4, fcolor(navy) fi(55) blcolor(none)) bar(5, fcolor(navy) fi(40) blcolor(none)) bargap(5) legend(row(1) size(*0.6))

graph save "$graphs\standardised ETHNICITY", replace
drop exp standardpop2019
export excel using "$output\England OOH 2020.xls", firstrow(varlabel) sheet("ethnicity", replace)

/*FOR MAPPING*/
/*age and sex adjusted rates for trusts*/
clear 
use "$work/OOH_cleaned.dta"
keep if death_year==2020
drop if stp==.
keep if sex2==2 | sex2==3
drop if age_atdeath==.
collapse (sum)last_12m (sum)death, by(stp age_cat10 sex2 OOH)
bys stp sex2 age_cat10: egen alldeaths = sum(death)
drop if OOH==0
drop death
rename last_12m OOHvisits_n
sort sex2 age_cat10 stp
merge m:1 sex2 age_cat10 using "$work\2019standard_population.dta"
drop _merge
gen rate=OOHvisits_n/alldeaths
gen exp=rate*standardpop2019
collapse (sum)exp standardpop2019 OOHvisits_n alldeaths, by(stp)
sort stp 
gen rawrate=OOHvisits_n/alldeaths
gen adjrate=exp/standardpop2019
gen adjratepertho=adjrate*1000

drop exp standardpop2019
export excel using "$output\England OOH 2020.xls", firstrow(varlabel) sheet("stp", replace)

/************************************************************/
/*age and sex standardised the rate over 12 months before death, line graphs*/
/*UCOD*/
clear 
use "$work/OOH_cleaned.dta"
keep if death_year==2020
drop if COD_cat==.
keep if sex2==2 | sex2==3
drop if age_atdeath==.
collapse (sum)last_12m (sum)death, by(COD_cat age_cat10 sex2 OOH months_da)
bys COD_cat sex2 age_cat10: egen alldeaths = sum(death)
drop if OOH==0
drop if months_da==.
drop death
rename last_12m OOHvisits_n
sort sex2 age_cat10 COD_cat months_da 
merge m:1 sex2 age_cat10 using "$work\2019standard_population.dta"
drop _merge
gen rate=OOHvisits_n/alldeaths
gen exp=rate*standardpop2019
collapse (sum)exp standardpop2019 OOHvisits_n alldeaths, by(COD_cat months_da)
sort COD_cat months_da
gen rawrate=OOHvisits_n/alldeaths
gen adjrate=exp/standardpop2019
gen adjratepertho=adjrate*1000

export excel using "$output\England OOH 2020.xls", firstrow(varlabel) sheet("12m_UCOD", replace)

keep months_da COD_cat adjratepertho
reshape wide adjratepertho, i(months_da) j(COD_cat)
label var adjratepertho1 cancer
label var adjratepertho2 dementia
label var adjratepertho3 cardiovascular
label var adjratepertho4 respiratory
label var adjratepertho5 other

twoway line adjratepertho1 adjratepertho2 adjratepertho3 adjratepertho4 adjratepertho5 months_da, xscale(reverse) xlabel(1(1)12) title("Rate per 1,000 deaths in 2020, of out-of-hours emergency department visits" "in the last 12 months of life, by cause of death", size(*0.7)) graphregion(color(white))

graph save "$graphs\OOH rate per 1000_UCOD", replace 



/**************************************************************/
/*deprivation*/
clear 
use "$work/OOH_cleaned.dta"
keep if death_year==2020
drop if imd_quints==. 
keep if sex2==2 | sex2==3
drop if age_atdeath==.
collapse (sum)last_12m (sum)death, by(imd_quints age_cat10 sex2 OOH months_da)
bys imd_quints sex2 age_cat10: egen alldeaths = sum(death)
drop if OOH==0
drop if months_da==.
drop death
rename last_12m OOHvisits_n
sort sex2 age_cat10 imd_quints months_da 
merge m:1 sex2 age_cat10 using "$work\2019standard_population.dta"
drop _merge
gen rate=OOHvisits_n/alldeaths
gen exp=rate*standardpop2019
collapse (sum)exp standardpop2019 OOHvisits_n alldeaths, by(imd_quints months_da)
sort imd_quints months_da
gen rawrate=OOHvisits_n/alldeaths
gen adjrate=exp/standardpop2019
gen adjratepertho=adjrate*1000

export excel using "$output\England OOH 2020.xls", firstrow(varlabel) sheet("12m_dep", replace)

keep months_da imd_quints adjratepertho
reshape wide adjratepertho, i(months_da) j(imd_quints)
label var adjratepertho1 1
label var adjratepertho2 2
label var adjratepertho3 3
label var adjratepertho4 4
label var adjratepertho5 5

twoway line adjratepertho1 adjratepertho2 adjratepertho3 adjratepertho4 adjratepertho5 months_da, xscale(reverse) xlabel(1(1)12) title("Rate per 1,000 deaths in 2020, of out-of-hours emergency department visits" "in the last 12 months of life, by deprivation", size(*0.7)) graphregion(color(white))

graph save "$graphs\OOH rate per 1000_dep", replace 




