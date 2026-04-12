/*
==============================================================================
02_var_main.do
Full-sample VAR analysis

System:
  Endogenous:  nvda_ret, dgtrend_nvda
  Exogenous:   ndx_ret, vix, log_vol, post_chatgpt

Steps:
  1. VAR lag order selection (varsoc)
  2. VAR estimation
  3. Stability check
  4. Residual diagnostics (LM autocorrelation, normality)
  5. Granger causality tests (bidirectional)
  6. Impulse Response Functions (orthogonalized)
  7. Forecast Error Variance Decomposition (FEVD)
  8. Export results table
==============================================================================
*/

use "$data/weekly_panel.dta", clear

gen week = wofd(date)
format week %tw
tsset week

* ── 1. Lag Order Selection ───────────────────────────────────────────────────
di _newline "--- LAG ORDER SELECTION ---"

varsoc nvda_ret dgtrend_nvda, ///
    exog(ndx_ret vix log_vol post_chatgpt) maxlag(8)

* AIC often selects higher lags in weekly financial data.
* Use p=2 (BIC-preferred, parsimonious) as baseline; p=4 as robustness.
local p = 2

* ── 2. VAR Estimation ────────────────────────────────────────────────────────
di _newline "--- VAR(`p') ESTIMATION — FULL SAMPLE ---"

var nvda_ret dgtrend_nvda, lags(1/`p') ///
    exog(ndx_ret vix log_vol post_chatgpt) ///
    dfk small

estimates store var_full

* ── 3. Stability Check ───────────────────────────────────────────────────────
di _newline "--- VAR STABILITY (all eigenvalues inside unit circle?) ---"
varstable, graph
graph export "$figs/fig4_stability.png", replace width(1600)

* ── 4. Residual Diagnostics ─────────────────────────────────────────────────
di _newline "--- RESIDUAL DIAGNOSTICS ---"

* LM autocorrelation test (H0: no autocorrelation at lag h)
varlmar, mlag(4)

* Normality of residuals
varnorm, jbera

* ── 5. Granger Causality ─────────────────────────────────────────────────────
di _newline "--- GRANGER CAUSALITY TESTS ---"
di "H1 (H0 to reject): Search volume Granger-causes NVDA returns"
di "H2 (H0 to reject): NVDA returns Granger-cause search volume"
di ""

vargranger

* Save Granger output to log — also extract key p-values
di _newline "Interpretation:"
di "  p < 0.05: Granger-causality is significant at 5%"

* ── 6. Impulse Response Functions ────────────────────────────────────────────
di _newline "--- IMPULSE RESPONSE FUNCTIONS ---"

* Create IRF set — orthogonalized (Cholesky), ordering: dgtrend_nvda → nvda_ret
* (search happens before trading action within the week)
irf create irf_full, step(12) set("$results/irf_full") replace order(dgtrend_nvda nvda_ret)

* (a) Response of nvda_ret to dgtrend_nvda shock
irf graph oirf, irf(irf_full) ///
    impulse(dgtrend_nvda) response(nvda_ret) ///
    yline(0, lcolor(black) lwidth(thin)) ///
    title("IRF: Response of NVDA Return to Search Volume Shock") ///
    xtitle("Weeks after shock") ytitle("Response") ///
    scheme(s2color) ci
graph export "$figs/fig5_irf_gt_to_ret.png", replace width(2000)

* (b) Response of dgtrend_nvda to nvda_ret shock
irf graph oirf, irf(irf_full) ///
    impulse(nvda_ret) response(dgtrend_nvda) ///
    yline(0, lcolor(black) lwidth(thin)) ///
    title("IRF: Response of Search Volume to NVDA Return Shock") ///
    xtitle("Weeks after shock") ytitle("Response") ///
    scheme(s2color) ci
graph export "$figs/fig6_irf_ret_to_gt.png", replace width(2000)

* (c) Combined 2×2 IRF panel
irf graph oirf, irf(irf_full) ///
    yline(0, lcolor(black) lwidth(thin)) ///
    title("Orthogonalized Impulse Response Functions — Full Sample") ///
    scheme(s2color) ci
graph export "$figs/fig7_irf_all.png", replace width(2400)

* ── 7. Forecast Error Variance Decomposition ─────────────────────────────────
di _newline "--- FORECAST ERROR VARIANCE DECOMPOSITION ---"

irf table fevd, irf(irf_full) impulse(dgtrend_nvda) response(nvda_ret)
irf table fevd, irf(irf_full) impulse(nvda_ret) response(nvda_ret)

* Save FEVD figure
irf graph fevd, irf(irf_full) response(nvda_ret) ///
    title("FEVD: Share of NVDA Return Variance Explained") ///
    xtitle("Forecast horizon (weeks)") ytitle("Fraction of variance") ///
    scheme(s2color)
graph export "$figs/fig8_fevd.png", replace width(2000)

* ── 8. Export Coefficient Table ──────────────────────────────────────────────
di _newline "--- EXPORT RESULTS ---"

* Re-estimate for esttab (equation by equation for clean output)
reg nvda_ret L(1/`p').nvda_ret L(1/`p').dgtrend_nvda ///
    ndx_ret vix log_vol post_chatgpt
estimates store eq1_ret

reg dgtrend_nvda L(1/`p').nvda_ret L(1/`p').dgtrend_nvda ///
    ndx_ret vix log_vol post_chatgpt
estimates store eq2_gt

esttab eq1_ret eq2_gt using "$results/table2_var_full.tex", ///
    b(4) se(4) star(* 0.10 ** 0.05 *** 0.01) ///
    label replace booktabs ///
    title("VAR(`p') Full-Sample Estimates") ///
    mtitles("NVDA Return" "ΔSearch Volume") ///
    note("Standard errors in parentheses. * p<0.10, ** p<0.05, *** p<0.01." ///
         "Exogenous controls: NDX return, VIX, log volume, post-ChatGPT dummy.")

di _newline "Full-sample VAR complete."
