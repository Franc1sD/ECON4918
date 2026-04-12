"""
01_fetch_data.py
Fetch all raw data and save to data/raw/.

Sources:
  - Yahoo Finance: NVDA, ^NDX, ^VIX  (daily OHLCV, Jan 2019 – Dec 2024)
  - Google Trends: "NVDA", "buy nvidia stock"  (weekly, US, same period)

Google Trends is fetched via pytrends by stitching two overlapping 5-year
windows and rescaling to a consistent 0–100 index.

Run once to populate data/raw/ before running 02_build_dataset.py.
"""

import os
import time
import numpy as np
import pandas as pd
import yfinance as yf
from pytrends.request import TrendReq

RAW = os.path.join(os.path.dirname(__file__), '..', 'data', 'raw')
os.makedirs(RAW, exist_ok=True)

START = '2019-01-01'
END   = '2024-12-31'

# ── Yahoo Finance ─────────────────────────────────────────────────────────────
TICKERS = {'NVDA': 'nvda', '^NDX': 'ndx', '^VIX': 'vix'}

print('=== Yahoo Finance ===')
for ticker, name in TICKERS.items():
    print(f'  Downloading {ticker}...')
    df = yf.download(ticker, start=START, end=END, auto_adjust=True, progress=False)
    path = os.path.join(RAW, f'{name}_daily.csv')
    df.to_csv(path)
    print(f'  -> {path}  ({len(df)} rows)')

# ── Google Trends via pytrends ────────────────────────────────────────────────
print('\n=== Google Trends ===')

pytrends = TrendReq(hl='en-US', tz=300, timeout=(10, 30))

KEYWORDS = {
    'NVDA':             'google_trends_NVDA.csv',
    'buy nvidia stock': 'google_trends_buy_nvidia.csv',
}

# Google Trends caps weekly data at ~5 years per request.
# Fetch two overlapping windows and rescale the older one onto the newer scale.
WINDOW_A = '2019-01-01 2022-06-30'
WINDOW_B = '2022-01-01 2024-12-31'

def fetch_window(keyword, timeframe, sleep=8):
    pytrends.build_payload([keyword], timeframe=timeframe, geo='US', gprop='')
    time.sleep(sleep)
    df = pytrends.interest_over_time()
    if df.empty:
        raise ValueError(f'No data for "{keyword}" / {timeframe}')
    return df[[keyword]].rename(columns={keyword: 'search_index'})

def stitch(keyword):
    print(f'  Fetching window A: {keyword}')
    wa = fetch_window(keyword, WINDOW_A)
    print(f'  Fetching window B: {keyword}')
    wb = fetch_window(keyword, WINDOW_B)

    overlap = wa.index.intersection(wb.index)
    if len(overlap) < 4:
        raise ValueError(f'Insufficient overlap ({len(overlap)} weeks) to rescale.')

    scale = wb.loc[overlap, 'search_index'].mean() / (wa.loc[overlap, 'search_index'].mean() + 1e-9)
    wa_scaled = (wa['search_index'] * scale).clip(0, 100)

    combined = pd.concat([
        wa_scaled[~wa_scaled.index.isin(wb.index)].rename('search_index').to_frame(),
        wb
    ]).sort_index()
    combined['search_index'] = combined['search_index'].clip(0, 100).round().astype(int)
    return combined

for keyword, fname in KEYWORDS.items():
    try:
        df = stitch(keyword)
        path = os.path.join(RAW, fname)
        # Save as simple two-column CSV (week start date, index)
        df.index.name = 'week'
        df.to_csv(path)
        print(f'  -> {path}  ({len(df)} rows)')
    except Exception as e:
        print(f'  ERROR fetching "{keyword}": {e}')
    time.sleep(12)

print('\nAll raw data saved to data/raw/.')
