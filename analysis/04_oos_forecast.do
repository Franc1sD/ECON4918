/*
==============================================================================
04_oos_forecast.do
Out-of-sample (OOS) forecasting evaluation

Compares two models for forecasting weekly NVDA returns:
  Model AR:  nvda_ret = f(lags of nvda_ret, controls)
  Model VAR: nvda_ret = f(lags of nvda_ret, lags of dgtrend_nvda, controls)

Method: Expanding (recursive) window OOS — re-estimate on all data
through week t, forecast week t+1.

Evaluation:
  - Mean Squared Forecast Error (MSFE): AR vs. VAR
  - Clark-West (2006) test for equal predictive accuracy
  - Split evaluation pre/post ChatGPT

Note: contemporaneous controls (ndx_ret, vix, log_vol at t+1) are
included in both models as available end-of-week information.
==============================================================================
*/

use "$data/weekly_panel.dta", clear

format date %td
tsset date, delta(7)

local p    = 2                        // lag order
local nobs = _N
local train = floor(`nobs' * 0.5)    // 50% training window

di "Total obs:     `nobs'"
di "Training obs:  `train'"
di "OOS obs:       `= `nobs' - `train''"

* ── Initialize storage ───────────────────────────────────────────────────────
gen e_ar  = .
gen e_var = .
label var e_ar  "OOS forecast error — AR model"
label var e_var "OOS forecast error — VAR model"

* ── Expanding-window OOS loop ────────────────────────────────────────────────
di _newline "Running OOS loop (`= `nobs' - `train' - 1' forecasts)..."

quietly {
forvalues t = `train'/`= `nobs' - 1' {

    local t1 = `t' + 1    // forecast target

    * ── Model AR ─────────────────────────────────────────────────────────────
    reg nvda_ret L(1/`p').nvda_ret ndx_ret vix log_vol in 1/`t'

    local fc_ar = _b[_cons]
    forvalues l = 1/`p' {
        local fc_ar = `fc_ar' + _b[L`l'.nvda_ret] * nvda_ret[`t1' - `l']
    }
    local fc_ar = `fc_ar' ///
        + _b[ndx_ret] * ndx_ret[`t1'] ///
        + _b[vix]     * vix[`t1']     ///
        + _b[log_vol] * log_vol[`t1']

    replace e_ar = nvda_ret[`t1'] - `fc_ar' in `t1'

    * ── Model VAR (return equation with lagged search volume) ────────────────
    reg nvda_ret L(1/`p').nvda_ret L(1/`p').dgtrend_nvda ///
        ndx_ret vix log_vol in 1/`t'

    local fc_var = _b[_cons]
    forvalues l = 1/`p' {
        local fc_var = `fc_var' + _b[L`l'.nvda_ret]     * nvda_ret[`t1' - `l']
        local fc_var = `fc_var' + _b[L`l'.dgtrend_nvda] * dgtrend_nvda[`t1' - `l']
    }
    local fc_var = `fc_var' ///
        + _b[ndx_ret] * ndx_ret[`t1'] ///
        + _b[vix]     * vix[`t1']     ///
        + _b[log_vol] * log_vol[`t1']

    replace e_var = nvda_ret[`t1'] - `fc_var' in `t1'
}
}

di "OOS loop complete."

* ── MSFE ─────────────────────────────────────────────────────────────────────
di _newline "--- MEAN SQUARED FORECAST ERROR ---"

gen e_ar2  = e_ar^2
gen e_var2 = e_var^2

quietly sum e_ar2
local msfe_ar = r(mean)
quietly sum e_var2
local msfe_var = r(mean)
local ratio = `msfe_var' / `msfe_ar'

di "  MSFE (AR):       " %8.6f `msfe_ar'
di "  MSFE (VAR):      " %8.6f `msfe_var'
di "  Ratio (VAR/AR):  " %6.4f `ratio'
if `ratio' < 1 di "  => VAR outperforms AR (search volume improves forecast)"
else           di "  => AR outperforms VAR"

* ── Clark-West (2006) Test ────────────────────────────────────────────────────
di _newline "--- CLARK-WEST TEST (H0: AR = VAR predictive accuracy) ---"
di "(One-sided: reject if VAR is better, i.e. CW t > 1.645)"

* CW adjustment: f_adj = e_ar^2 - e_var^2 + (fc_ar - fc_var)^2
gen fc_ar  = nvda_ret - e_ar
gen fc_var = nvda_ret - e_var
gen cw_adj = e_ar2 - e_var2 + (fc_ar - fc_var)^2

reg cw_adj if !missing(e_ar, e_var)
di ""
di "CW t-stat (= t on constant): " %6.4f (_b[_cons] / _se[_cons])
di "p-value (one-sided, normal approx): " ///
    %6.4f (1 - normal(_b[_cons] / _se[_cons]))

* ── Pre / Post ChatGPT split ─────────────────────────────────────────────────
di _newline "--- OOS EVALUATION BY PERIOD ---"

local breakdate = date("2022-11-30", "YMD")

foreach period in pre post {
    if "`period'" == "pre"  local cond "date < `breakdate' & !missing(e_ar)"
    if "`period'" == "post" local cond "date >= `breakdate' & !missing(e_ar)"

    quietly sum e_ar2  if `cond'
    local m_ar = r(mean)
    local n_per = r(N)
    quietly sum e_var2 if `cond'
    local m_var = r(mean)

    di "`period'-ChatGPT  (N=`n_per'):"
    di "  MSFE AR:  " %8.6f `m_ar'
    di "  MSFE VAR: " %8.6f `m_var'
    di "  Ratio:    " %6.4f (`m_var'/`m_ar')
}

* ── Cumulative MSFE Plot ──────────────────────────────────────────────────────
gen cum_e_ar2  = sum(e_ar2)  / _n if !missing(e_ar)
gen cum_e_var2 = sum(e_var2) / _n if !missing(e_var)

twoway (line cum_e_ar2  date if !missing(e_ar), lcolor(navy) lwidth(medthick)) ///
       (line cum_e_var2 date if !missing(e_var), lcolor(cranberry) lwidth(medthick) lpattern(dash)), ///
    xline(`=`breakdate'', lcolor(red) lwidth(thin) lpattern(shortdash)) ///
    legend(order(1 "AR (no search)" 2 "VAR (with search)") position(6) rows(1)) ///
    xtitle("") ytitle("Cumulative MSFE") ///
    title("Out-of-Sample Forecast Accuracy: AR vs. VAR") ///
    note("Vertical line = ChatGPT launch (Nov 2022)") ///
    xlabel(, format(%tdMon_YY) angle(45)) ///
    scheme(s2color)
graph export "$figs/fig10_oos_msfe.png", replace width(2400)

* ── Export OOS Summary Table ─────────────────────────────────────────────────
* Save key OOS stats to a tex snippet
file open ftab using "$results/table4_oos.tex", write replace
file write ftab "\begin{table}[htbp]\centering" _newline
file write ftab "\caption{Out-of-Sample Forecasting Evaluation}" _newline
file write ftab "\begin{tabular}{lcc}" _newline
file write ftab "\hline\hline" _newline
file write ftab " & AR & VAR \\\\" _newline
file write ftab "\hline" _newline
file write ftab "Full sample MSFE & `=string(`msfe_ar',"%9.6f")' & `=string(`msfe_var',"%9.6f")' \\\\" _newline
file write ftab "MSFE ratio (VAR/AR) & \multicolumn{2}{c}{`=string(`ratio',"%6.4f")'} \\\\" _newline
file write ftab "\hline\hline" _newline
file write ftab "\end{tabular}" _newline
file write ftab "\end{table}" _newline
file close ftab

di _newline "OOS analysis complete."
