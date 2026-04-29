/*
==============================================================================
05_robustness.do
Robustness checks

1.  Alternative keyword: "buy nvidia stock" (dgtrend_buy)
2.  Alternative lag lengths: p=1, p=4
3.  Idiosyncratic return as dependent variable (nvda_idret)
4.  High-attention weeks: does search volume spike predict outsized returns?
5.  Asymmetric attention: positive vs. negative return weeks
6.  Controlling for earnings announcement weeks (approximate)
==============================================================================
*/

use "$data/weekly_panel.dta", clear

format date %td
tsset date, delta(7)

local p = 2    // baseline lag order

* ── 1. Alternative Keyword: dgtrend_buy ──────────────────────────────────────
di _newline "=== ROBUSTNESS 1: Alternative keyword (buy nvidia stock) ==="

var nvda_ret dgtrend_buy, lags(1/`p') ///
    exog(ndx_ret vix log_vol post_chatgpt) dfk small
estimates store var_buy

vargranger
di "(Compare Granger p-values to baseline using dgtrend_nvda)"

reg nvda_ret L(1/`p').nvda_ret L(1/`p').dgtrend_buy ndx_ret vix log_vol post_chatgpt
estimates store eq1_buy

* ── 2. Alternative Lag Lengths ────────────────────────────────────────────────
di _newline "=== ROBUSTNESS 2: Alternative lag lengths ==="

foreach lag in 1 4 {
    di _newline "VAR(`lag'):"
    var nvda_ret dgtrend_nvda, lags(1/`lag') ///
        exog(ndx_ret vix log_vol post_chatgpt) dfk small
    estimates store var_p`lag'

    di "Granger (p=`lag'):"
    vargranger

    reg nvda_ret L(1/`lag').nvda_ret L(1/`lag').dgtrend_nvda ///
        ndx_ret vix log_vol post_chatgpt
    estimates store eq1_p`lag'
}

* ── 3. Idiosyncratic Return as Dependent Variable ─────────────────────────────
di _newline "=== ROBUSTNESS 3: Idiosyncratic return (nvda_ret - ndx_ret) ==="

var nvda_idret dgtrend_nvda, lags(1/`p') ///
    exog(vix log_vol post_chatgpt) dfk small
estimates store var_idret

vargranger

reg nvda_idret L(1/`p').nvda_idret L(1/`p').dgtrend_nvda ///
    vix log_vol post_chatgpt
estimates store eq1_idret

* ── 4. High-Attention Weeks ───────────────────────────────────────────────────
di _newline "=== ROBUSTNESS 4: Do attention spikes predict outsized returns? ==="

* Define attention spike: top-quartile of |dgtrend_nvda|
quietly sum absgtrend, detail
local p75 = r(p75)
gen hi_attention = (absgtrend >= `p75' & !missing(absgtrend))
label var hi_attention "Top-quartile attention spike week"

* T-test: do high-attention weeks have higher |nvda_ret|?
gen abs_nvda_ret = abs(nvda_ret)
ttest abs_nvda_ret, by(hi_attention)

* Regression: return magnitude on attention spike
reg abs_nvda_ret hi_attention ndx_ret vix log_vol post_chatgpt
estimates store eq_hiatt

* ── 5. Asymmetric Attention: Positive vs. Negative Return Weeks ──────────────
di _newline "=== ROBUSTNESS 5: Asymmetric attention response ==="

gen pos_ret = (nvda_ret >= 0)
label var pos_ret "Positive return week"

* Do returns Granger-cause MORE search in negative return weeks?
* Interaction: L.nvda_ret × (1 - pos_ret)
gen neg_ret_x = L.nvda_ret * (1 - pos_ret)

reg dgtrend_nvda L.nvda_ret neg_ret_x L.dgtrend_nvda ///
    ndx_ret vix log_vol post_chatgpt
estimates store eq_asym

di "  Coefficient on neg_ret_x: does fear/loss drive more searches?"

drop neg_ret_x pos_ret abs_nvda_ret

* ── 6. VIX Interaction: Does attention matter more in uncertain markets? ──────
di _newline "=== ROBUSTNESS 6: Attention × VIX interaction ==="

* Standardize VIX
quietly sum vix
gen vix_std = (vix - r(mean)) / r(sd)

gen gt_vix = L.dgtrend_nvda * vix_std

reg nvda_ret L(1/`p').nvda_ret L.dgtrend_nvda gt_vix ///
    ndx_ret vix log_vol post_chatgpt
estimates store eq_vix_int

drop vix_std gt_vix hi_attention

* ── 7. QLR-Estimated Break vs. ChatGPT Date ──────────────────────────────────
di _newline "=== ROBUSTNESS 7: Alternative break date from QLR test ==="

if "$qlr_breakdate" == "" {
    di "  QLR test found no statistically significant break (see 01_pretests.do output)."
    di "  ChatGPT date is the sole split; no alternative subsample table produced."
}
else {
    local qlr_bd = $qlr_breakdate
    di "  QLR-estimated break: " %td `qlr_bd'
    di "  ChatGPT launch date: " %td $breakdate
    di "  Difference (weeks):  " (`qlr_bd' - $breakdate) / 7

    foreach period in "pre" "post" {
        preserve
        if "`period'" == "pre"  keep if date <  `qlr_bd'
        if "`period'" == "post" keep if date >= `qlr_bd'

        reg nvda_ret L(1/`p').nvda_ret L(1/`p').dgtrend_nvda ///
            ndx_ret vix log_vol
        estimates store eq_qlr_`period'
        restore
    }

    esttab eq_qlr_pre eq_qlr_post using "$results/table_qlr_break.tex", ///
        b(4) se(4) star(* 0.10 ** 0.05 *** 0.01) ///
        label replace booktabs ///
        title("Robustness: Subsample Split at QLR-Estimated Break Date") ///
        mtitles("Pre-QLR break" "Post-QLR break") ///
        note("Break date estimated by Quandt-Andrews QLR test (estat sbsingle)." ///
             "Compare to Table 3 which splits at ChatGPT launch (Nov 30, 2022).")
}

* ── Export Robustness Table ───────────────────────────────────────────────────
di _newline "--- EXPORT ROBUSTNESS TABLE ---"

esttab eq1_buy eq1_p1 eq1_p4 eq1_idret using "$results/table5_robustness.tex", ///
    b(4) se(4) star(* 0.10 ** 0.05 *** 0.01) ///
    label replace booktabs ///
    title("Robustness Checks — Return Equation") ///
    mtitles("Alt. keyword" "VAR(1)" "VAR(4)" "Idiosyncratic ret.") ///
    note("Standard errors in parentheses. * p<0.10, ** p<0.05, *** p<0.01." ///
         "All models estimated with OLS on the return equation.")

* VIX interaction and high-attention separately
esttab eq_hiatt eq_asym eq_vix_int using "$results/table6_robustness2.tex", ///
    b(4) se(4) star(* 0.10 ** 0.05 *** 0.01) ///
    label replace booktabs ///
    title("Robustness: Nonlinearities and Interactions") ///
    mtitles("Attention spike" "Asymmetric response" "Attention × VIX") ///
    note("Standard errors in parentheses. * p<0.10, ** p<0.05, *** p<0.01.")

di _newline "Robustness checks complete."
