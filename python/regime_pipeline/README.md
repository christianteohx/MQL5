Regime Pipeline

This package provides tools to generate market regime labels, train models (HMM and classifiers), and analyze backtest performance per regime. Designed to work from CSV OHLCV exports (no live MT5 required).

Files:
- data_fetcher.py: load CSV and compute technical features
- label_generator.py: several regime labelling methods (ATR percentile, ADX, combined, HMM)
- trainer.py: training utilities, walk-forward validation
- backtest_analyzer.py: analyze backtest results per regime and plotting helpers
- parameter_exporter.py: export optimized parameters for MQL5
- example_notebook.ipynb: example workflow (notebook)
- requirements.txt: python dependencies
