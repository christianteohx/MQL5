Completed: Python regime pipeline implementation

What I did:
- Created files: requirements.txt, README.md, data_fetcher.py, label_generator.py, trainer.py, backtest_analyzer.py, parameter_exporter.py, example_notebook.ipynb
- Implemented feature engineering (ATR, ADX, RSI, MACD, Bollinger width, momentum, volatility)
- Implemented regime labelers: ATR percentile, ADX thresholds, combined labels, HMM-based labels
- Implemented trainer with HMM training, classifier training (RF/LogReg), and walk-forward validation
- Implemented backtest analyzer with per-regime metrics, plotting functions, and strategy comparison
- Implemented parameter exporter for MQL5 input block and JSON

Notes / Next steps:
- The HMM and ADX implementations are simplified and intended for CSV-only workflows. Validate results on real data and tune parameters.
- example_notebook.ipynb is a skeleton — fill with concrete sample runs using your CSVs.
- If you want, I can add unit tests and CI, or flesh the notebook with runnable examples.

Location: /tmp/mql5-repo/python/regime_pipeline/
