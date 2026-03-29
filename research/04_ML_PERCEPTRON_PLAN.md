04_ML_PERCEPTRON_PLAN

1. MQL5 ML Approaches (with pros/cons/feasibility)

- MLPBuffer (MQL5 native) — does it work? performance? limitations?
  - Overview: MLPBuffer is an approach that uses MQL5-native data structures and the MQL5 Machine Learning helpers (if available) to store small neural network weights and perform simple forward passes directly inside an Expert Advisor (EA). In practice this usually means implementing a compact perceptron or small multi-layer perceptron with hand-crafted matrix ops and activation functions in MQL5 code, or translating a trained small model into arrays of coefficients embedded in the EA.
  - Pros: Native execution (no external dependencies), simple deployment, no IPC latency, works offline inside the terminal and is easy to version with the EA.
  - Cons: MQL5's language and runtime are not designed for heavy numeric computation — vectorized operations are slow, memory is limited, and implementing training inside MQL5 is impractical. Complex models or frequent retraining are not realistic. Also, numerical precision and advanced activation functions / layers are cumbersome to implement.
  - Feasibility: Medium for inference with very small models (e.g., single hidden layer perceptron with tens of neurons); low for anything larger. Best used for lightweight inference only, with training done externally.

- ONNX Runtime in MQL5 — possible? constraints?
  - Overview: ONNX Runtime is a cross-platform inference engine capable of running complex models in many languages. Running ONNX in MQL5 would require either a bridging DLL (Windows) or a custom wrapper that exposes inference calls to MQL5's Import mechanism.
  - Pros: Can run complex modern architectures and leverage optimized CPU/GPU execution. Standardized model format.
  - Cons: Integration complexity is high. MQL5 runs inside MT5 which restricts dynamic linking and sandboxing; deploying and calling a custom DLL can be non-trivial and may run into policy or platform limitations. Cross-platform portability is limited (MT5 on Mac uses different layers), and distribution requires shipping external binaries which reduces portability and increases the chance of compatibility and security issues.
  - Feasibility: Low to Medium. Technically possible on Windows if you can supply a stable, trusted DLL and handle ABI and threading carefully. Generally not recommended unless you have strong devops and control of the target environment.

- Python writes to CSV/JSON → MQL5 reads each bar — simplest approach, works offline
  - Overview: Train and run predictions in Python (scikit-learn, PyTorch, TensorFlow). Export per-bar predictions (or model outputs) to CSV/JSON file. Have the EA read the file on each new completed bar and use the predictions for decision logic.
  - Pros: Simple to implement, flexible (full Python ecosystems available), decouples training/inference from MQL5. Easy to retrain, validate, and version. Platform-agnostic (works wherever Python can run).
  - Cons: Slight IPC latency (file I/O), potential sync issues (ensure read happens after write, use atomic rename pattern), requires an external process for runtime predictions or scheduled prediction exports. Not real-time per tick but perfectly acceptable for bar-based strategies.
  - Feasibility: High. This is the practical approach used by many practitioners.

- MT5 built-in ensemble classes
  - Overview: MQL5 ships with some statistical helpers and higher-level classes that can be used to build ensembles or do simple machine-learning-like logic. These are limited compared to modern ML frameworks but can be combined with technical indicators.
  - Pros: Native, no external dependencies, low latency.
  - Cons: Limited flexibility and model complexity.
  - Feasibility: Medium for rule-based ensembles and simple parametric models.

- What MQL5 community actually uses successfully
  - Practical community patterns favor external training/inference with Python or R and exporting signals to MQL5 via CSV, shared memory, local sockets, or lightweight DLLs. Very few rely on heavy in-EA ML stacks. Logistic regression, small perceptrons translated into arrays, and feature-engineered rule models are common.

2. Perceptron Design

- Features
  - Indicator values: normalized values from RSI, MACD, moving averages, ATR-normalized returns, Bollinger band z-score. Use normalized representations rather than raw prices.
  - Regime state: discrete or continuous regime indicator (e.g., trend vs. mean-reversion, or a 0-1 probability). This can be a feature produced by a separate regime classifier or from macro features (ADX, 200-day MA crossing, VIX proxy).
  - Volatility ratio: current ATR / rolling ATR mean, or realized volatility ratio to capture regimes of risk.
  - Momentum: N-bar returns across multiple horizons (1, 5, 20 bars), normalized.
  - Volume or tick activity: where available — normalized to z-scores per instrument/time-of-day.

- Output options
  - Confidence multiplier: scalar in [0,2] used to scale position size or signal strength.
  - Buy/sell/neutral probabilities / discrete decisions: either softprobabilities from a sigmoid/softmax or hard decisions after thresholding.
  - Regime probability: model outputs probability of regime label (if trained for regime), which downstream logic can use to switch weights.

- Architecture example
  - Simple 2-layer perceptron: Input vector → Dense hidden layer (ReLU) → Output layer (sigmoid for binary outcome or linear + softmax for multi-class). Hidden layer size: 8–64 neurons depending on feature count.
  - Activation choices: ReLU or LeakyReLU in hidden layer, sigmoid at output for binary, softmax for multi-class.

- Normalization
  - Use per-feature z-score normalization (mean, std dev) computed over a rolling window or computed on training set and stored. Alternatively min-max scaling with clipped extreme values. Always apply the same normalization in Python during training and in MQL5 at inference time.

3. Label Generation

- Forward returns
  - Label using forward returns over an N-bar horizon (e.g., 5, 10, 20 bars). For classification, set label to 1 if forward return > threshold, 0 otherwise. Threshold can be 0 or transaction-cost-adjusted (e.g., > spread+slippage).

- Backtest P&L outcome as label
  - Generate labels by simulating the EA’s trading logic on historical data and marking whether the trade at that bar would have been profitable after costs. This aligns model objectives to P&L but risks overfitting to the backtest-specific rules.

- Avoid look-ahead bias
  - Use only closed-bar data as inputs. Labels are forward returns computed on subsequent bars and should never be fed back into features. When using N-bar forward returns, ensure there is at least a 1-bar lag between the last input bar and the start of the label window if the EA would only act on bar close.

- Self-supervised alternatives
  - Train to predict next-bar return direction or multi-horizon returns directly, which can work as a lightweight signal and requires no complex labeling pipeline.

4. Integration Patterns

- Option A: ML as gate
  - ML model acts as a gating function. For instance, only allow signals from the primary system to execute when ML confidence > threshold. This reduces false positives and is conservative.

- Option B: ML as confidence multiplier (RECOMMENDED)
  - ML outputs a confidence scalar that multiplies position sizing or signal strength from the existing ensemble. This is robust because it augments the ensemble rather than replacing it. If ML is wrong, ensemble still functions. This approach eases A/B testing and gradual rollout.

- Option C: ML predicts regime → regime-specific weights
  - ML predicts regimes and a set of weights are applied to ensemble components based on regime probabilities. This is more complex but allows dynamic adaptation of strategy weights.

- Option D: ML replaces ensemble entirely
  - ML outputs discrete trading decisions. Higher potential but higher risk. Requires much stronger validation and continuous monitoring.

Recommendation: Option B
  - Rationale: complements the existing ensemble, reduces risk of catastrophic failure, simple to implement using CSV bridge, and allows straightforward backtesting comparisons.

5. MQL5 Constraints

- Memory limits
  - MQL5 EAs are constrained in memory and code-size. Embedding large model weight matrices is possible but will bloat the EA and could exceed comfortable limits (~1-2MB effective working footprint).

- Latency
  - Do inference only on new bar events (OnNewBar or OnTick with a closed-bar check). Running heavy inference per tick is unnecessary and would increase CPU and latency.

- File approach best practice
  - Use Python to write predictions atomically (write to temp file then rename). MQL5 reads the CSV/JSON once per new closed bar. Include timestamp or bar index to ensure alignment and avoid stale reads.

- Model retraining
  - Retrain offline in Python. When retraining is complete, ship new prediction files or new model outputs. If you need to ship new weight arrays into the EA, stop/redeploy the EA to avoid inconsistencies.

6. Industry Practice

- Common model types
  - Simple linear/logistic models and small neural networks are common in production for robustness and interpretability. Ensemble modeling (averaging multiple small models) is more typical than a single monolithic deep network.

- Feature sets
  - Returns at multiple horizons, realized volatility, momentum, volume/tick features, and regime indicators are core features. Feature engineering and clean labeling often matter more than model complexity.

- Retrain frequency
  - Daily or weekly retraining is common, depending on market regime velocity. For high-frequency signals, retrain more often; for daily bar strategies, weekly or monthly retrain may be adequate.

- Institutional approach
  - Firms like Bridgewater or Two Sigma rely on many diversified models and ensemble weighting rather than a single ML black box. Combining small models with economic/regime-aware logic is standard.

Summary Table (concise)

- MLPBuffer: Complexity Medium | Feasibility Medium | Pros Native, no external | Cons Limited, slow
- ONNX: Complexity High | Feasibility Low | Pros Powerful | Cons Complex setup, deployment
- Python CSV: Complexity Low | Feasibility High | Pros Simple, flexible | Cons IPC latency
- Gate (ML confidence): Complexity Medium | Feasibility High | Pros Robust | Cons Threshold tuning

Recommended Implementation Plan

1. Generate labels from historical backtest data in Python, applying the same trading rules and transaction cost model used in production.
2. Train a simple sklearn Perceptron or LogisticRegression (or small Keras MLP) on normalized features (z-score). Validate with cross-validation and walk-forward testing.
3. Export per-bar predictions to CSV (script runs daily or on retrain). Include bar timestamp, symbol, prediction_confidence, predicted_label, and model_version.
4. MQL5 EA reads the CSV on each new closed bar, verifies model_version/timestamp and applies prediction as a confidence multiplier to the existing ensemble signal.
5. Phase in: start with ML as an optional toggle behind a configuration parameter. Backtest the EA with and without ML in identical conditions and monitor live performance.

Key Risks

- Overfitting: small datasets and over-parameterized models will not generalize. Prefer simpler models and strong cross-validation (walk-forward) procedures.
- Look-ahead bias: ensure label generation and feature construction only use closed-bar data and realistic fills/costs.
- Model staleness: markets change. Retrain cadence and monitoring are essential. Implement monitoring of prediction distribution shifts and P&L attribution.

Appendix: Practical tips

- Atomic file writes: Python writes predictions to temp file and renames. MQL5 checks for the presence of a new file and reads it once per bar.
- Timestamp alignment: use bar close UNIX timestamp or ISO8601 to align predictions precisely.
- Model versioning: include model_version and training_date in CSV so the EA can record which model produced the prediction.
- Threshold selection: when using ML as gate or multiplier, choose thresholds based on out-of-sample ROC curves and expected P&L improvement, not just accuracy.

Conclusion

A pragmatic, low-risk path is to train a simple perceptron/logistic model in Python, export predictions to CSV, and have MQL5 read and apply a confidence multiplier on each new bar (Option B). This offers high feasibility, easy validation, minimal platform complexity, and the ability to iterate quickly while preserving the robustness of the existing ensemble.