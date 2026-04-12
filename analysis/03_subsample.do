/*
==============================================================================
03_subsample.do
Subsample analysis: Pre vs. Post ChatGPT launch (Nov 30, 2022)

Motivated by H2: the search-return relationship strengthened after ChatGPT
drew mass retail attention to AI and Nvidia.

Steps:
  1. Split sample at ChatGPT launch date
  2. VAR estimation in each subsample
  3. Granger causality in each subsample
  4. IRF comparison
  5. Wald test: are coefficients equal across subsamples?
  6. Coefficient plot (pre vs. post)
==============================================================================
*/

use "$data/weekly_panel.dta", clear

gen week = wofd(date)
format week %tw
tsset week

local p = 2    // lag order (consistent with 02_var_main.do)

* ── 1. Split ─────────────────────────────────────────────────────────────────
* ChatGPT launched November 30, 2022 → Stata week 2022w48
local breakdate = weekly("2022w48", "YW")

* ── 2–3. VAR + Granger per subsample ────────────────────────────────────────
foreach period in "pre" "post" {
    if "`period'" == "pre" {
        local cond "week < `breakdate'"
        local title "Pre-ChatGPT (Jan 2019 – Nov 2022)"
    }
    else {
        local cond "week >= `breakdate'"
        local title "Post-ChatGPT (Nov 2022 – Dec 2024)"
    }

    di _newline "=============================================="
    di " VAR — `title'"
    di "=============================================="

    preserve
    keep if `cond'

    * Lag selection
    varsoc nvda_ret dgtrend_nvda, exog(ndx_ret vix log_vol) maxlag(6)

    * VAR
    var nvda_ret dgtrend_nvda, lags(1/`p') ///
        exog(ndx_ret vix log_vol) dfk small
    estimates store var_`period'

    * Stability
    varstable

    * Granger causality
    di "Granger causality — `title':"
    vargranger

    * IRF
    irf create irf_`period', step(12) ///
        set("$results/irf_`period'") replace order(dgtrend_nvda nvda_ret)

    irf graph oirf, irf(irf_`period') ///
        impulse(dgtrend_nvda) response(nvda_ret) ///
        yline(0, lcolor(black) lwidth(thin)) ///
        title("IRF: ΔSearch → NVDA Return (`title')") ///
        xtitle("Weeks after shock") ytitle("Response") ///
        scheme(s2color) ci
    graph export "$figs/fig_irf_`period'.png", replace width(2000)

    * Store return-equation estimates for comparison table
    reg nvda_ret L(1/`p').nvda_ret L(1/`p').dgtrend_nvda ///
        ndx_ret vix log_vol
    estimates store eq_ret_`period'

    restore
}

* ── 4. Coefficient Comparison Table ─────────────────────────────────────────
di _newline "--- COEFFICIENT COMPARISON TABLE ---"

esttab eq_ret_pre eq_ret_post using "$results/table3_subsample.tex", ///
    b(4) se(4) star(* 0.10 ** 0.05 *** 0.01) ///
    label replace booktabs ///
    title("VAR Return Equation: Pre vs. Post ChatGPT") ///
    mtitles("Pre-ChatGPT" "Post-ChatGPT") ///
    note("Standard errors in parentheses. * p<0.10, ** p<0.05, *** p<0.01.")

* ── 5. Coefficient Plot ──────────────────────────────────────────────────────
* Requires: ssc install coefplot

capture {
    coefplot (eq_ret_pre, label("Pre-ChatGPT") msymbol(circle)) ///
             (eq_ret_post, label("Post-ChatGPT") msymbol(diamond)), ///
        keep(L1.dgtrend_nvda L2.dgtrend_nvda L1.nvda_ret L2.nvda_ret) ///
        xline(0, lcolor(black) lwidth(thin)) ///
        title("Return Equation Coefficients: Pre vs. Post ChatGPT") ///
        xtitle("Coefficient") ///
        scheme(s2color) legend(position(6) rows(1))
    graph export "$figs/fig9_coefplot.png", replace width(2000)
}
if _rc != 0 di "coefplot not installed. Run: ssc install coefplot"

* ── 6. Pooled Wald Test for Parameter Stability ──────────────────────────────
di _newline "--- WALD TEST: EQUAL COEFFICIENTS PRE vs. POST ---"
di "Interact all RHS variables with post_chatgpt dummy in pooled regression"

* Pooled return equation with full interactions
foreach v in nvda_ret_l1 nvda_ret_l2 dgtrend_l1 dgtrend_l2 ndx_ret vix log_vol {
    gen `v'_x = .
}

replace nvda_ret_l1_x  = L.nvda_ret     * post_chatgpt
replace nvda_ret_l2_x  = L2.nvda_ret    * post_chatgpt
replace dgtrend_l1_x   = L.dgtrend_nvda * post_chatgpt
replace dgtrend_l2_x   = L2.dgtrend_nvda * post_chatgpt
replace ndx_ret_x      = ndx_ret        * post_chatgpt
replace vix_x          = vix            * post_chatgpt
replace log_vol_x      = log_vol        * post_chatgpt

reg nvda_ret L.nvda_ret L2.nvda_ret L.dgtrend_nvda L2.dgtrend_nvda ///
    ndx_ret vix log_vol post_chatgpt ///
    nvda_ret_l1_x nvda_ret_l2_x dgtrend_l1_x dgtrend_l2_x ///
    ndx_ret_x vix_x log_vol_x

di _newline "Wald test — all interaction terms = 0 (full parameter stability):"
testparm nvda_ret_l1_x nvda_ret_l2_x dgtrend_l1_x dgtrend_l2_x ///
         ndx_ret_x vix_x log_vol_x

di _newline "Wald test — search volume interactions only:"
testparm dgtrend_l1_x dgtrend_l2_x

drop nvda_ret_l1_x nvda_ret_l2_x dgtrend_l1_x dgtrend_l2_x ///
     ndx_ret_x vix_x log_vol_x

di _newline "Subsample analysis complete."
