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
gen week = wofd(date)
format week %tw
tsset week

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

twoway (line nvda_ret week, lcolor(navy) lwidth(thin)) ///
       (line ndx_ret  week, lcolor(cranberry) lwidth(thin) lpattern(dash)), ///
    xline(`=$breakdate', lcolor(red) lwidth(medthick) lpattern(shortdash)) ///
    legend(order(1 "NVDA return" 2 "NDX return") position(6) rows(1)) ///
    xtitle("") ytitle("Log weekly return") ///
    title("Weekly Returns: NVDA vs. Nasdaq-100") ///
    note("Vertical line = ChatGPT launch (Nov 2022)") ///
    xlabel(, format(%twMon_YY) angle(45)) ///
    scheme(s2color)
graph export "$figs/fig1_returns.png", replace width(2400)

twoway (line gtrend_nvda week, lcolor(dkgreen) lwidth(thin)), ///
    xline(`=$breakdate', lcolor(red) lwidth(medthick) lpattern(shortdash)) ///
    xtitle("") ytitle("Search Index (0–100)") ///
    title("Google Trends: NVDA Search Volume") ///
    note("Vertical line = ChatGPT launch (Nov 2022)") ///
    xlabel(, format(%twMon_YY) angle(45)) ///
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

* ── 5. Quandt-Andrews Unknown Breakpoint Test ────────────────────────────────
di _newline "--- QUANDT-ANDREWS STRUCTURAL BREAK TEST ---"
di "Trims 15% from each end; tests all interior points"
di ""

* Estimate baseline return equation
reg nvda_ret L(1/2).nvda_ret L(1/2).dgtrend_nvda $controls

* Quandt-Andrews test (requires Stata 14+)
estat sbsingle

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
