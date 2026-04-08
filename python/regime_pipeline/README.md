# Regime Pipeline

MQL5 Python pipeline for real-time volatility regime classification (LOW / MID / HIGH) via LogisticRegression.

## Modules

| File | Role |
|------|------|
| `data_fetcher.py` | OHLCV data retrieval (MT5 bridge stub + simulated data for dev) |
| `label_generator.py` | ATR percentile → LOW/MID/HIGH regime labels |
| `regime_classifier.py` | Feature extraction + LogisticRegression training + predictions.csv export |

## Feature Set (10 features)

| # | Feature | Description |
|---|---------|-------------|
| 1 | `atr_zscore` | ATR(14) z-score over 100-bar rolling window |
| 2 | `rsi_zscore` | RSI(14) z-score over 100-bar window |
| 3 | `ret_std_zscore` | 20-bar return std z-score |
| 4 | `vol_chg_zscore` | Volume change z-score |
| 5 | `hl_range_zscore` | High-Low range z-score |
| 6 | `close_ema20_dev_zscore` | Close vs 20 EMA deviation z-score |
| 7 | `momentum_5_zscore` | 5-bar momentum z-score |
| 8 | `atr_pct_rank` | ATR percentile rank (0–1, bounded) |
| 9 | `rsi_pct_rank` | RSI percentile rank (0–1) |
| 10 | `trend_alignment` | `(close>EMA20) + (close>EMA50)` → 0/1/2 |

## Label Scheme

- **LOW**  — ATR percentile < 0.33
- **MID**  — 0.33 ≤ ATR percentile < 0.67
- **HIGH** — ATR percentile ≥ 0.67

## Usage

```bash
# Install deps
pip install -r requirements.txt

# Run classifier
python regime_classifier.py \
  --symbol EURUSD \
  --timeframe H1 \
  --bars 500 \
  --output predictions.csv
```

## Output

`predictions.csv` — consumed by the MQL5 EA:

```
bar_time,symbol,regime_pred,confidence
2026-04-08 08:00:00,EURUSD,HIGH,0.72
```

## Architecture

```
OHLCV bars
    │
    ▼  extract_features()      → 10 z-score features
    │
    ▼  train_logistic_regression() → sklearn multinomial LogisticRegression
    │
    ▼  predict_regime()         → LOW/MID/HIGH + softmax confidence
    │
    ▼  export_predictions()     → predictions.csv
```
