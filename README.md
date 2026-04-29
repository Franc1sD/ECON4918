# Attention Before Action: Google Search and Nvidia Stock Returns

**ECON 4918 — Empirical Research Paper**
Francis Deng · Spring 2026

---

## Overview

This paper examines whether retail investor attention — proxied by Google Search volume — predicts Nvidia (NVDA) weekly stock returns, and whether large return movements in turn drive search activity. The analysis centers on a two-equation VAR system and tests whether this attention-return relationship structurally changed after the launch of ChatGPT in November 2022, which dramatically increased public interest in AI and Nvidia.

**Research Questions**
1. Does Google search volume for Nvidia Granger-cause its weekly stock returns?
2. Do Nvidia returns Granger-cause subsequent search activity (feedback loop)?
3. Did the attention-return relationship strengthen after ChatGPT's launch (Nov 2022)?

**Hypotheses**
- **H1:** Search volume Granger-causes NVDA returns — lagged search predicts returns even controlling for past returns and market-wide factors.
- **H2:** The relationship strengthened post-ChatGPT — the coefficient on search volume and/or Granger causality p-values improve significantly in the post-2022 subsample.

---

## Data

| Variable | Source | Frequency | Period |
|---|---|---|---|
| NVDA stock price & volume | Yahoo Finance | Daily → Weekly | Jan 2019 – Dec 2024 |
| Nasdaq-100 index (^NDX) | Yahoo Finance | Daily → Weekly | Jan 2019 – Dec 2024 |
| VIX (market uncertainty) | Yahoo Finance | Daily → Weekly | Jan 2019 – Dec 2024 |
| Google Trends: "NVDA" | Google Trends (via pytrends) | Weekly | Jan 2019 – Dec 2024 |
| Google Trends: "buy nvidia stock" | Google Trends (via pytrends) | Weekly | Jan 2019 – Dec 2024 |

**Key constructed variables:**
- `nvda_ret` — log weekly return of NVDA
- `nvda_idret` — idiosyncratic return (NVDA minus NDX)
- `dgtrend_nvda` — first difference of Google Trends index (stationary)
- `post_chatgpt` — dummy = 1 after 2022-11-30
- `absgtrend` — absolute attention change (attention spike measure)

---

## Repository Structure

```
ECON4918/
├── scripts/
│   ├── 01_fetch_data.py       # Fetch Yahoo Finance + Google Trends → data/raw/
│   └── 02_build_dataset.py    # Clean, merge, export → data/processed/weekly_panel.dta
│
├── analysis/
│   ├── 00_main.do             # Master do-file — runs all modules
│   ├── 01_pretests.do         # Unit root (ADF, KPSS), structural breaks, ARCH
│   ├── 02_var_main.do         # Full-sample VAR, Granger causality, IRF, FEVD
│   ├── 03_subsample.do        # Pre/post ChatGPT subsamples + Wald stability test
│   ├── 04_oos_forecast.do     # Recursive OOS: AR vs. VAR, Clark-West test
│   └── 05_robustness.do       # Alt. keyword, alt. lags, idiosyncratic returns, interactions
│
├── data/
│   ├── raw/                   # Raw CSVs (gitignored — regenerate with 01_fetch_data.py)
│   └── processed/             # weekly_panel.csv / .dta (gitignored — regenerate with 02_build_dataset.py)
│
├── paper/
│   └── main.tex               # Full paper (inline MLA-style citations, no BibTeX)
│
├── results/                   # Tracked (figures + tables); IRF binaries gitignored
│   ├── figures/               # fig1_returns, fig2_gtrends, fig3_scatter, fig4_stability,
│   │                          # fig5–fig7 IRFs, fig8_fevd, fig9_coefplot, fig10_oos_msfe,
│   │                          # fig_hook_dualaxis, fig_irf_pre/post, fig_stationarity
│   ├── table1_summary.tex
│   ├── table2_var_full.tex
│   ├── table3_subsample.tex
│   ├── table4_oos.tex
│   ├── table5_robustness.tex
│   └── table6_robustness2.tex
│
└── README.md
```

---

## Replication

### Step 1 — Python environment

```bash
conda activate base          # or your preferred env
pip install yfinance pytrends pandas numpy
```

### Step 2 — Fetch raw data

```bash
python scripts/01_fetch_data.py
```

Downloads daily Yahoo Finance data and stitches two Google Trends windows. Takes ~2 minutes (rate-limiting on Trends API).

### Step 3 — Build Stata dataset

```bash
python scripts/02_build_dataset.py
```

Outputs `data/processed/weekly_panel.dta` (311 weekly observations, 11 variables).

### Step 4 — Run Stata analysis

**Option A — Full pipeline (batch mode):**
```bash
stata -b do analysis/00_main.do
```

**Option B — Run individual modules in Stata GUI:**
```stata
global root "."                    // set from project root
do "analysis/01_pretests.do"
do "analysis/02_var_main.do"
do "analysis/03_subsample.do"
do "analysis/04_oos_forecast.do"
do "analysis/05_robustness.do"
```


---

## Methodology

The core model is a bivariate VAR estimated on weekly data, with NVDA log returns and the first-differenced Google Trends index as the two endogenous variables. Each equation includes lags of both variables plus exogenous controls (Nasdaq-100 return, VIX, log trading volume, and a post-ChatGPT dummy). The system lets us test whether search activity predicts returns, whether returns feed back into search, and how those dynamics shifted after November 2022.

Pre-estimation checks confirm stationarity (ADF/KPSS), identify the structural break (Quandt-Andrews + Chow test), and test for volatility clustering (ARCH-LM). Post-estimation diagnostics include bidirectional Granger causality tests, orthogonalized impulse response functions, forecast error variance decomposition, and a recursive out-of-sample forecast comparison using the Clark-West (2006) test.

---

## Key References

- Barber, B. M., & Odean, T. (2008). All that glitters: The effect of attention and news on the buying behavior of individual and institutional investors. *Review of Financial Studies*, 21(2), 785–818.
- Brogaard, J., Hendershott, T., & Riordan, R. (2022). High-frequency trading and price discovery. *Review of Financial Studies*, 35(4), 1665–1703.
- Clark, T. E., & West, K. D. (2006). Using out-of-sample mean squared prediction errors to test the martingale difference hypothesis. *Journal of Econometrics*, 135(1–2), 155–186.
- Da, Z., Engelberg, J., & Gao, P. (2011). In search of attention. *Journal of Finance*, 66(5), 1461–1499.
- Han, B., Hirshleifer, D., & Walden, J. (2023). Social transmission bias and investor behavior. *Journal of Financial and Quantitative Analysis*, 58(1), 1–33.
- Kim, O., & Verrecchia, R. E. (2019). Liquidity and volume around earnings announcements. *Journal of Accounting and Economics*, 41(1–2), 41–67.
- Merton, R. C. (1987). A simple model of capital market equilibrium with incomplete information. *Journal of Finance*, 42(3), 483–510.
- Preis, T., Moat, H. S., & Stanley, H. E. (2013). Quantifying trading behavior in financial markets using Google Trends. *Scientific Reports*, 3, 1684.
