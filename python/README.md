# Greg EA — Regime Pipeline

Tools for generating market regime labels, training models, analyzing backtests, and exporting parameters for MQL5.

## Files

| File | Purpose |
|------|---------|
| `data_fetcher.py` | Load OHLCV CSV and compute technical features (ATR, ADX, RSI, MACD, Bollinger, etc.) |
| `label_generator.py` | Regime labeling methods: ATR percentile, ADX threshold, combined, HMM |
| `trainer.py` | Training utilities and walk-forward validation |
| `backtest_analyzer.py` | **Analyze Greg EA trade logs per-regime and produce metrics + reports** |
| `parameter_exporter.py` | Export optimized parameters for MQL5 and JSON formats |
| `example_notebook.ipynb` | Example workflow (Jupyter notebook) |
| `requirements.txt` | Python dependencies |

---

## backtest_analyzer.py — Usage

### Quick Start

```bash
python backtest_analyzer.py --csv GregTradeLogger.csv --output reports/
```

### Python API

```python
from backtest_analyzer import GregBacktestAnalyzer

analyzer = GregBacktestAnalyzer('GregTradeLogger.csv', starting_balance=10000.0)
analyzer.load()
report = analyzer.run()
analyzer.print_summary(report)

# Export
analyzer.to_json('report.json')
analyzer.to_csv('regime_summary.csv')
```

### Greg EA CSV Format (input)

The analyzer reads trade logs written by `greg_regime_risk_v1.mq5` via `LogTradeToCSV()`:

```
CloseTime,Symbol,Direction,Profit,Regime,ATR,ATR_smooth,Pips,DurationBars
2025-01-15 08:00,EURUSD,BUY,45.23,LOW,0.00120,0.00118,4.5,12
```

- **Regime**: LOW | MID | HIGH (volatility regime at time of entry)
- **Direction**: BUY | SELL
- **Profit**: net P&L in account currency (includes commission + swap)
- **Pips**: pip profit/loss
- **DurationBars**: number of H1 bars the trade was held

### Output Metrics

**Overall**: total trades, win rate, profit factor, expectancy, largest win/loss, consecutive streaks, avg pips/bars per trade, Sharpe, Sortino, Calmar, annual return, annual volatility, max drawdown

**Per-Regime** (LOW / MID / HIGH): trade count, win rate, gross profit/loss, net profit, profit factor, expectancy, avg pips, avg bars, Sharpe, max drawdown %

**Per-Direction** (BUY / SELL): trade count, win rate, net profit, avg pips, profit factor

**Monthly P&L**: aggregated profit per calendar month

### CLI Options

```
--csv        Path to trade log CSV (required)
--output     Output directory for reports (default: .)
--balance    Starting balance for % calculations (default: 10000)
--json       Write full JSON report to this path
--regime-csv Write per-regime summary CSV to this path
```

---

## label_generator.py — Usage

```python
from label_generator import RegimeLabeler

labeler = RegimeLabeler()
labels = labeler.atr_percentile_labels(atr_series, lookback=100, low=0.33, high=0.66)
hmm_labels = labeler.hmm_labels(features_df, n_states=3)
```

---

## parameter_exporter.py — Usage

```python
from parameter_exporter import ParameterExporter

exporter = ParameterExporter()
exporter.export_mql5_inputs(params, 'output.mqh')
exporter.export_json(params, 'params.json')
```
