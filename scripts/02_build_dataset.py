"""
02_build_dataset.py
Clean raw data, compute variables, and export the analysis dataset.

Outputs:
  data/processed/weekly_panel.csv   (for reference / quick inspection)
  data/processed/weekly_panel.dta   (Stata dataset, imported by all .do files)

Variables in the final dataset:
  week          Stata weekly date (%tw)
  nvda_ret      NVDA log weekly return
  ndx_ret       Nasdaq-100 log weekly return
  nvda_idret    NVDA idiosyncratic return (nvda_ret - ndx_ret)
  vix           VIX weekly average level
  log_vol       Log NVDA weekly trading volume
  gtrend_nvda   Google Trends index for "NVDA" (0–100)
  gtrend_buy    Google Trends index for "buy nvidia stock" (0–100)
  dgtrend_nvda  First difference of gtrend_nvda (stationary)
  dgtrend_buy   First difference of gtrend_buy (stationary)
  absgtrend     Weekly absolute change in gtrend_nvda (attention spike measure)
  post_chatgpt  Dummy = 1 after 2022-11-30 (ChatGPT launch)
"""

import os
import numpy as np
import pandas as pd

RAW  = os.path.join(os.path.dirname(__file__), '..', 'data', 'raw')
PROC = os.path.join(os.path.dirname(__file__), '..', 'data', 'processed')
os.makedirs(PROC, exist_ok=True)


# ── Helpers ───────────────────────────────────────────────────────────────────

def load_price_csv(fname):
    """Load a yfinance multi-level CSV, return a daily DataFrame."""
    path = os.path.join(RAW, fname)
    df = pd.read_csv(path, header=[0, 1], index_col=0, parse_dates=True)
    df.columns = ['_'.join(c).strip() for c in df.columns]
    return df

def weekly_log_return(fname):
    df = load_price_csv(fname)
    close_col = next(c for c in df.columns if 'Close' in c)
    px = df[[close_col]].rename(columns={close_col: 'price'}).dropna()
    wk = px.resample('W-FRI').last()
    wk['log_ret'] = np.log(wk['price'] / wk['price'].shift(1))
    return wk[['log_ret']].dropna()

def weekly_vix(fname):
    df = load_price_csv(fname)
    close_col = next(c for c in df.columns if 'Close' in c)
    vix = df[[close_col]].rename(columns={close_col: 'VIX'})
    return vix.resample('W-FRI').mean().dropna()

def weekly_volume(fname):
    df = load_price_csv(fname)
    vol_col = next(c for c in df.columns if 'Volume' in c)
    vol = df[[vol_col]].rename(columns={vol_col: 'volume'})
    wk = vol.resample('W-FRI').sum().dropna()
    wk['log_vol'] = np.log(wk['volume'].clip(lower=1))
    return wk[['log_vol']]

def load_trends(fname, col_name):
    path = os.path.join(RAW, fname)
    # Support two formats:
    #   (a) clean format from 01_fetch_data.py: first row is header "week,search_index"
    #   (b) legacy format from 01b_fetch_trends.py: 2 header rows, then data
    with open(path) as f:
        first = f.readline().strip()
    if first.startswith('Category') or first == '':
        df = pd.read_csv(path, skiprows=2, parse_dates=[0])
    else:
        df = pd.read_csv(path, parse_dates=[0])
    df.columns = ['date', col_name]
    df = df.set_index('date')
    df[col_name] = pd.to_numeric(df[col_name], errors='coerce')
    # Trends uses week-start (Monday); shift to Friday to align with returns
    df.index = df.index + pd.offsets.Week(weekday=4)
    return df.dropna()


# ── Load & merge ──────────────────────────────────────────────────────────────

print('Loading raw data...')
nvda_ret = weekly_log_return('nvda_daily.csv').rename(columns={'log_ret': 'nvda_ret'})
ndx_ret  = weekly_log_return('ndx_daily.csv').rename(columns={'log_ret': 'ndx_ret'})
vix      = weekly_vix('vix_daily.csv')
log_vol  = weekly_volume('nvda_daily.csv')
gt_nvda  = load_trends('google_trends_NVDA.csv', 'gtrend_nvda')
gt_buy   = load_trends('google_trends_buy_nvidia.csv', 'gtrend_buy')

frames = [nvda_ret, ndx_ret, vix, log_vol, gt_nvda, gt_buy]
panel = frames[0]
for f in frames[1:]:
    panel = panel.join(f, how='inner')

panel = panel.sort_index().loc['2019-01-01':'2024-12-31']

# ── Construct variables ───────────────────────────────────────────────────────

# Idiosyncratic return: removes broad market movement
panel['nvda_idret'] = panel['nvda_ret'] - panel['ndx_ret']

# First differences of Trends (unit-root correction)
panel['dgtrend_nvda'] = panel['gtrend_nvda'].diff()
panel['dgtrend_buy']  = panel['gtrend_buy'].diff()

# Absolute attention change: unsigned spike measure
panel['absgtrend'] = panel['dgtrend_nvda'].abs()

# Structural break dummy
panel['post_chatgpt'] = (panel.index >= '2022-11-30').astype(int)

panel = panel.dropna()

# ── Rename VIX column to lowercase ───────────────────────────────────────────
panel = panel.rename(columns={'VIX': 'vix'})

# ── Reorder columns ───────────────────────────────────────────────────────────
col_order = [
    'nvda_ret', 'ndx_ret', 'nvda_idret',
    'vix', 'log_vol',
    'gtrend_nvda', 'gtrend_buy',
    'dgtrend_nvda', 'dgtrend_buy', 'absgtrend',
    'post_chatgpt',
]
panel = panel[col_order]
panel.index.name = 'date'

print(f'Panel: {panel.shape[0]} weeks, {panel.shape[1]} variables')
print(f'  From: {panel.index[0].date()}  To: {panel.index[-1].date()}')
print(f'  Post-ChatGPT obs: {panel["post_chatgpt"].sum()}')

# ── Export CSV ────────────────────────────────────────────────────────────────
csv_path = os.path.join(PROC, 'weekly_panel.csv')
panel.to_csv(csv_path)
print(f'\nSaved: {csv_path}')

# ── Export Stata .dta ─────────────────────────────────────────────────────────
dta_path = os.path.join(PROC, 'weekly_panel.dta')

# Convert index to a plain column for Stata compatibility
panel_stata = panel.reset_index()
panel_stata['date'] = pd.to_datetime(panel_stata['date'])

# Variable labels for Stata
variable_labels = {
    'date':         'Friday date (end of week) — use wofd(date) to get %tw week',
    'nvda_ret':     'NVDA log weekly return',
    'ndx_ret':      'Nasdaq-100 log weekly return',
    'nvda_idret':   'NVDA idiosyncratic return (nvda - ndx)',
    'vix':          'VIX weekly average',
    'log_vol':      'Log NVDA weekly trading volume',
    'gtrend_nvda':  'Google Trends: NVDA (0-100)',
    'gtrend_buy':   'Google Trends: buy nvidia stock (0-100)',
    'dgtrend_nvda': 'First diff of gtrend_nvda',
    'dgtrend_buy':  'First diff of gtrend_buy',
    'absgtrend':    'Absolute attention change |dgtrend_nvda|',
    'post_chatgpt': '=1 after ChatGPT launch (2022-11-30)',
}

panel_stata.to_stata(
    dta_path,
    write_index=False,
    variable_labels=variable_labels,
    version=118,      # Stata 14+
    convert_dates={'date': 'td'},
)
print(f'Saved: {dta_path}')
print('\nDone. Ready for Stata analysis.')
