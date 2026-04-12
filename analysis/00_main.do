/*
==============================================================================
00_main.do
Master do-file — runs the full analysis pipeline.

Usage:
  1. cd to the project root (ECON4918/)
  2. stata -b do analysis/00_main.do   (batch mode)
     or open in Stata GUI and run

Requires:
  data/processed/weekly_panel.dta   (produced by scripts/02_build_dataset.py)

Install user packages on first run (uncomment if needed):
  ssc install estout
  ssc install kpss
  ssc install coefplot
==============================================================================
*/

clear all
set more off
set linesize 120

* ── Set project root as working directory ─────────────────────────────────────
* Change this path if running from somewhere other than the project root.
* When run as: stata -b do analysis/00_main.do  from ECON4918/, this is fine.
global root "."

global data    "$root/data/processed"
global results "$root/results"
global figs    "$root/results/figures"

capture mkdir "$results"
capture mkdir "$figs"

* ── Global settings ──────────────────────────────────────────────────────────
global y       nvda_ret            // primary dependent variable
global gt      dgtrend_nvda        // primary attention variable (stationary)
global controls "ndx_ret vix log_vol"
global breakdate = date("2022-11-30", "YMD") // ChatGPT launch date (daily format)

* ── Run analysis modules ──────────────────────────────────────────────────────
log using "$results/full_analysis.log", replace text

di "============================================================"
di " 01 PRE-ESTIMATION TESTS"
di "============================================================"
do "$root/analysis/01_pretests.do"

di "============================================================"
di " 02 VAR — FULL SAMPLE"
di "============================================================"
do "$root/analysis/02_var_main.do"

di "============================================================"
di " 03 SUBSAMPLE: PRE / POST ChatGPT"
di "============================================================"
do "$root/analysis/03_subsample.do"

di "============================================================"
di " 04 OUT-OF-SAMPLE FORECASTING"
di "============================================================"
do "$root/analysis/04_oos_forecast.do"

di "============================================================"
di " 05 ROBUSTNESS CHECKS"
di "============================================================"
do "$root/analysis/05_robustness.do"

log close
di "All done. Log saved to $results/full_analysis.log"
