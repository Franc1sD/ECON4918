/*
==============================================================================
01_pretests.do
Pre-estimation diagnostics

1. Summary statistics
2. ADF unit root tests (all series)
3. KPSS stationarity tests
4. Time-series plots
5. Quandt-Andrews unknown structural break test
6. Chow test at Nov 2022 (ChatGPT launch)
7. ARCH-LM test (check for volatility clustering in returns)
==============================================================================
*/

use "$data/weekly_panel.dta", clear

* ── Set time series ──────────────────────────────────────────────────────────
* Observations are weekly Fridays — use daily date with 7-day delta.
* (wofd() can produce duplicate week values for Friday dates near week boundaries)
format date %td
tsset date, delta(7)

* ── 1. Summary Statistics ────────────────────────────────────────────────────
di _newline "--- SUMMARY STATISTICS ---"

estpost summarize nvda_ret ndx_ret nvda_idret vix log_vol ///
                  gtrend_nvda dgtrend_nvda gtrend_buy dgtrend_buy, ///
                  detail

esttab using "$results/table1_summary.tex", ///
    cells("mean(fmt(4)) sd(fmt(4)) min(fmt(4)) p25(fmt(4)) p50(fmt(4)) p75(fmt(4)) max(fmt(4))") ///
    noobs label replace booktabs ///
    title("Summary Statistics — Weekly Data, January 2019–December 2024") ///
    mtitles("Mean" "SD" "Min" "p25" "Median" "p75" "Max")

* ── 2. ADF Unit Root Tests ───────────────────────────────────────────────────
di _newline "--- ADF UNIT ROOT TESTS ---"
di "H0: series has a unit root (non-stationary)"
di ""

local series "nvda_ret ndx_ret nvda_idret vix log_vol gtrend_nvda gtrend_buy dgtrend_nvda dgtrend_buy"

foreach v of local series {
    di "  ADF test: `v'"
    dfuller `v', lags(4) regress
}

* ── 3. KPSS Stationarity Tests ───────────────────────────────────────────────
di _newline "--- KPSS STATIONARITY TESTS ---"
di "H0: series is stationary (opposite of ADF)"
di ""

* Requires: ssc install kpss
capture {
    foreach v of local series {
        di "  KPSS test: `v'"
        kpss `v', qs auto
    }
}
if _rc != 0 di "  kpss not installed. Run: ssc install kpss"

* ── 4. Time-Series Plots ─────────────────────────────────────────────────────
* Returns and search volume over time

twoway (line nvda_ret date, lcolor(navy) lwidth(thin)) ///
       (line ndx_ret  date, lcolor(cranberry) lwidth(thin) lpattern(dash)), ///
    xline(`=$breakdate', lcolor(red) lwidth(medthick) lpattern(shortdash)) ///
    legend(order(1 "NVDA return" 2 "NDX return") position(6) rows(1)) ///
    xtitle("") ytitle("Log weekly return") ///
    title("Weekly Returns: NVDA vs. Nasdaq-100") ///
    note("Vertical line = ChatGPT launch (Nov 2022)") ///
    xlabel(, format(%tdMon_YY) angle(45)) ///
    scheme(s2color)
graph export "$figs/fig1_returns.png", replace width(2400)

twoway (line gtrend_nvda date, lcolor(dkgreen) lwidth(thin)), ///
    xline(`=$breakdate', lcolor(red) lwidth(medthick) lpattern(shortdash)) ///
    xtitle("") ytitle("Search Index (0–100)") ///
    title("Google Trends: NVDA Search Volume") ///
    note("Vertical line = ChatGPT launch (Nov 2022)") ///
    xlabel(, format(%tdMon_YY) angle(45)) ///
    scheme(s2color)
graph export "$figs/fig2_gtrends.png", replace width(2400)

* Scatter: contemporaneous relationship
twoway scatter nvda_ret dgtrend_nvda, ///
    mcolor(navy%40) msize(small) ///
    || lfit nvda_ret dgtrend_nvda, lcolor(red) ///
    legend(off) xtitle("ΔGoogle Trends (NVDA)") ytitle("NVDA log return") ///
    title("Google Search Changes vs. NVDA Returns") ///
    scheme(s2color)
graph export "$figs/fig3_scatter.png", replace width(1800)

* ── Hook figure: NVDA price index + Google Trends (dual-axis) ────────────────
* Construct cumulative price index from log returns (base = 100 at first obs)
gen _cum_logret     = sum(nvda_ret)
gen nvda_price_idx  = 100 * exp(_cum_logret - _cum_logret[1])
label var nvda_price_idx "NVDA cumulative return index (Jan 2019 = 100)"

twoway (line nvda_price_idx date, lcolor(navy) lwidth(medthick) yaxis(1)) ///
       (line gtrend_nvda    date, lcolor(dkgreen) lwidth(medthick) ///
            lpattern(dash) yaxis(2)), ///
    xline(`=$breakdate', lcolor(red) lwidth(medthick) lpattern(shortdash)) ///
    legend(order(1 "NVDA Price Index (left)" 2 "Google Trends: NVDA (right)") ///
           position(6) rows(1)) ///
    ytitle("Price Index (Jan 2019 = 100)", axis(1)) ///
    ytitle("Search Index (0–100)", axis(2)) ///
    xtitle("") ///
    title("NVDA Price and Google Search Attention, 2019–2024") ///
    note("Vertical line = ChatGPT launch (Nov 30, 2022)") ///
    xlabel(, format(%tdMon_YY) angle(45)) ///
    scheme(s2color)
graph export "$figs/fig_hook_dualaxis.png", replace width(2400)

drop _cum_logret nvda_price_idx

* ── Stationarity figure: levels vs. first difference (side-by-side) ──────────
twoway (line gtrend_nvda date, lcolor(dkgreen) lwidth(thin)), ///
    xline(`=$breakdate', lcolor(red) lwidth(medthick) lpattern(shortdash)) ///
    xtitle("") ytitle("Search Index (0–100)") ///
    title("Google Trends: NVDA (Levels)") ///
    note("ADF Z(t) = -2.07, p = 0.258  →  unit root not rejected") ///
    xlabel(, format(%tdMon_YY) angle(45)) ///
    scheme(s2color) ///
    name(g_levels, replace)

twoway (line dgtrend_nvda date, lcolor(dkgreen) lwidth(thin)), ///
    xline(`=$breakdate', lcolor(red) lwidth(medthick) lpattern(shortdash)) ///
    yline(0, lcolor(black) lwidth(thin)) ///
    xtitle("") ytitle("ΔSearch Index") ///
    title("ΔGoogle Trends: NVDA (First Difference)") ///
    note("ADF Z(t) = -9.13, p < 0.001  →  stationary") ///
    xlabel(, format(%tdMon_YY) angle(45)) ///
    scheme(s2color) ///
    name(g_diff, replace)

graph combine g_levels g_diff, rows(1) ///
    title("Unit Root Correction: Google Trends Before and After First-Differencing") ///
    xsize(14) ysize(5)
graph export "$figs/fig_stationarity.png", replace width(2800)

graph drop g_levels g_diff

* ── 5. Quandt-Andrews Unknown Breakpoint Test ────────────────────────────────
di _newline "--- QUANDT-ANDREWS STRUCTURAL BREAK TEST ---"
di "Trims 15% from each end; tests all interior points"
di ""

* Estimate baseline return equation
reg nvda_ret L(1/2).nvda_ret L(1/2).dgtrend_nvda $controls

* Quandt-Andrews test (requires Stata 14+)
* trim(20) = 20% trimming; note: integer percent, not decimal
capture estat sbsingle, trim(20)
if _rc == 0 {
    * r(breakdate) returns a date string or "." if no clear break is identified
    local bd_str = r(breakdate)
    di "  Supremum Wald = " %6.4f r(chi2_swald) ",  p = " %5.4f r(p_swald)

    if "`bd_str'" == "." | "`bd_str'" == "" {
        di "  No statistically significant break found"
        di "  ChatGPT date retained as theory-motivated split (Chow test below)"
        global qlr_breakdate   // unset; robustness section will note no alt date
    }
    else {
        global qlr_breakdate = date("`bd_str'", "DMY")
        di "  QLR-estimated break: " %td $qlr_breakdate " (`bd_str')"
        di "  ChatGPT launch date: " %td $breakdate
        di "  Difference (weeks):  " ($qlr_breakdate - $breakdate) / 7
    }
}
else {
    di "  Note: estat sbsingle failed (rc=" _rc "). Try a simpler specification."
    di "  Falling back to manual Chow test below."
    global qlr_breakdate   // leave unset; 05_robustness.do checks for empty string
}

* ── 6. Chow Test at ChatGPT Launch ──────────────────────────────────────────
di _newline "--- CHOW TEST AT 2022w48 (ChatGPT launch) ---"

* Create interaction terms manually
gen post = post_chatgpt
gen nvda_ret_l1_post    = L.nvda_ret     * post
gen dgtrend_nvda_l1_post = L.dgtrend_nvda * post
gen ndx_ret_post        = ndx_ret        * post
gen vix_post            = vix            * post
gen log_vol_post        = log_vol        * post

reg nvda_ret L.nvda_ret L.dgtrend_nvda $controls post ///
    nvda_ret_l1_post dgtrend_nvda_l1_post ndx_ret_post vix_post log_vol_post

* Joint significance of all interaction terms = Chow test
testparm nvda_ret_l1_post dgtrend_nvda_l1_post ndx_ret_post vix_post log_vol_post

drop post nvda_ret_l1_post dgtrend_nvda_l1_post ndx_ret_post vix_post log_vol_post

* ── 7. ARCH-LM Test ──────────────────────────────────────────────────────────
di _newline "--- ARCH-LM TEST FOR VOLATILITY CLUSTERING ---"

reg nvda_ret L(1/2).nvda_ret $controls
estat archlm, lags(4)

di _newline "Pre-tests complete."
