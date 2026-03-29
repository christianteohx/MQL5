# Academic Research: Market Regime Detection for Algorithmic Trading

Date range searched: 2020–2024

Summary
- Goal: identify market regimes (e.g., trending vs. mean-reverting, high vs. low volatility) to adapt strategy allocation and risk controls.
- Methods surveyed: Hidden Markov Models (HMM), Markov regime-switching (Hamilton) models, Kalman Filters / state-space models, clustering approaches (K-means, GMM), volatility-based heuristics (realized volbreaks), change-point detection (CUSUM, BOCPD), deep learning (LSTM/Transformer classification), and information-theoretic approaches (entropy, permutation entropy).

Method summaries (pros/cons, complexity, accuracy)

1) Hidden Markov Models (HMM) / Regime-Switching
- Summary: Model returns or latent state as a finite-state Markov chain with state-dependent observation distributions. Estimate via Baum–Welch (EM) or Bayesian methods.
- Pros: Interpretable discrete regimes, well-understood estimation, captures persistence via transition matrix; can incorporate exogenous variables.
- Cons: Assumes Markov property and fixed number of regimes; sensitive to model specification and nonstationarity; can lag on rapid regime shifts.
- Complexity: O(T * N^2) per EM iteration (T = observations, N = states). Feasible in real-time for small N (2–4).
- Accuracy: Good when regimes are well-separated; many papers report improved risk-adjusted returns when used for allocation or volatility-scaling.

2) Kalman Filters / Switching Kalman Filter
- Summary: Continuous state-space models for latent factors (e.g., trend) with recursive filtering. Switching variants allow discrete regime changes.
- Pros: Online, low-latency updates; flexible (time-varying parameters); natural for trend estimation and state smoothing.
- Cons: Linear-Gaussian assumptions in standard form; switching variants more complex and computationally heavier.
- Complexity: O(T * k^3) per step depending on state dimension k. Online and efficient for low k.
- Accuracy: Effective for trend/noise separation; less direct for discrete regime labelling unless extended.

3) Clustering (K-means, Gaussian Mixture Models)
- Summary: Unsupervised clustering on feature vectors (returns, vol, skewness, momentum) to identify regime clusters.
- Pros: Simple, flexible feature-based approach; nonparametric clustering captures arbitrary cluster shapes with GMMs.
- Cons: Requires careful feature engineering and scaling; cluster labels arbitrary and may switch frequently; no temporal persistence unless augmented.
- Complexity: Typically O(T * K * I) per iteration (K clusters, I iterations). Lightweight.
- Accuracy: Works well for exploratory analysis; less robust in online detection without temporal smoothing.

4) Volatility-based heuristics and change-point detection
- Summary: Define regimes based on realized volatility thresholds, or detect shifts using CUSUM, Bayesian Online Change Point Detection (BOCPD).
- Pros: Intuitive, fast, directly addresses risk regimes; BOCPD provides online posterior for change events.
- Cons: Thresholds need calibration; volatility spikes may be transient; change-point methods detect shifts but not classify regime type.
- Complexity: Low for volatility thresholding; BOCPD O(T) online with cost depending on run-length truncation.
- Accuracy: Strong for distinguishing high/low volatility; works well as a safety-layer for risk management.

5) Deep learning (LSTM, Transformers, CNN)
- Summary: Supervised or semi-supervised models trained on market data and features to predict regime labels or latent states.
- Pros: Can learn complex nonlinear patterns and interactions; adaptable to large feature sets.
- Cons: Data-hungry, risk of overfitting, low interpretability, slow to adapt to structural breaks unless retrained frequently.
- Complexity: High (training cost); inference can be moderate depending on model.
- Accuracy: Promising in academic experiments, but mixed in live trading due to regime nonstationarity and label noise.

6) Information-theoretic approaches (entropy, permutation entropy)
- Summary: Use entropy measures to detect complexity changes in returns/time series, flagging regime transitions.
- Pros: Model-free, sensitive to structural changes, useful for early warning signals.
- Cons: Requires windowing and parameter choices; can produce false positives in noisy environments.
- Complexity: Low–moderate depending on entropy estimator.
- Accuracy: Useful as complementary signal, particularly for detecting increases in unpredictability.

Key academic papers (2020–2024)
- "Regime Switching Models in Finance: A Review" — recent surveys summarizing HMM and regime-switching applications (see e.g., 2021 review articles).
- Guidolin & Timmermann, "Asset Allocation under Regime Switching" (classical reference; useful background).
- Kearns et al., "Market Regimes and Portfolio Construction" (2020–2022 papers exploring regime-aware allocation improvements). [Search for specific arXiv/SSRN links during implementation]
- Adams & MacKay, "Bayesian Online Changepoint Detection" (2007 classic; frequently used in later papers and applications). Implementations and extensions through 2020s.
- Hamilton, "A New Approach to the Economic Analysis of Nonstationary Time Series and the Business Cycle" (1989) — foundational switching model.
- Recent applied papers (2020–2024): look for works combining HMM with realized volatility features, papers applying BOCPD to financial time series, and papers using permutation entropy for regime detection. (Specific links and DOIs should be fetched when moving from PoC to production.)

Mathematical justification for regime detection
- Nonstationarity: Financial returns exhibit time-varying moments (volatility clustering, changing correlations). Regime models explicitly model piecewise-stationary behavior, enabling estimators that adapt parameter choices (e.g., risk scaling) to current regime.
- Utility improvement: If a strategy's return distribution parameters differ across regimes (mean, variance, skew), then conditioning on regime reduces estimation error for variance and expected return, improving risk-adjusted returns. Formally, optimizing allocations conditional on regime s: maximize E[U(w'R) | S=s] yields different optimal w_s; mixing without regime info increases conditional variance and estimation error.
- Information theory: Regime detection reduces Shannon entropy of the predictive distribution for returns; effective regime classification increases mutual information I(R_{t+1}; S_t), improving forecastability.
- Control perspective: Regime detection is analogous to a low-level controller estimating system mode; switching to mode-specific controllers (strategy parameters) reduces tracking error and improves robustness.

Recommended approach for MQL5 implementation (practical, low-latency)
- Hybrid pipeline combining fast volatility/change-point detection + small-state HMM for classification:
  1. Online volatility monitor (e.g., EWMA of squared returns or realized vol over minute/hour windows) with adaptive thresholds to flag high-vol states.
  2. Bayesian Online Change Point Detection (BOCPD) to detect structural breaks quickly; use as veto or reset signal for HMM state posterior.
  3. Two- or three-state HMM (states: trending-up, mean-reverting/sideways, high-vol/crash) trained offline on historical features (returns, realized vol, momentum, skewness) and used online with forward-only filtering (no smoothing) for low-latency state probabilities.
  4. Kalman filter for continuous trend estimation used inside the trending state to adapt position sizing and stop-loss levels.
- Rationale: volatility/change-point methods handle rapid risk events and protect capital; small HMM provides smooth regime probabilities for allocation; Kalman filter supplies continuous signal for execution.

Specific parameters / heuristics
- HMM:
  - Number of states: 2–3 for simplicity (low-vol trend vs high-vol risk / sideways).
  - Observation features: 5–30-min returns, EWMA volatility (lambda 0.94–0.97), 1–3 period momentum, rolling skewness (window 50–200), correlation with broader index if available.
  - Emission distributions: Gaussian on standardized returns or Gaussian Mixture for fat tails.
  - Transition prior: encourage persistence (self-transition probs 0.90–0.98) to avoid rapid switching.
  - Update cadence: retrain parameters weekly/monthly offline; use online filtering with fixed parameters.

- Volatility monitor:
  - EWMA vol lambda = 0.96–0.98 for 5–60 min intraday; realized vol computed from 5-min returns for intraday strategies.
  - High-vol threshold: when instantaneous vol > 2–3 * long-run median vol → flag high-vol regime.

- BOCPD / change-point:
  - Hazard function: constant hazard with daily hazard ~1/200 (tunable), but for intraday use higher hazard; truncate run-length after 200–500 steps for speed.
  - Use Student-t observation model to handle heavy tails.

- Kalman filter:
  - State: [price level, trend], process noise tuned so trend adapts over 50–200 bars.
  - Use measurement noise based on observed intrabar variance.

Evaluation and backtesting suggestions
- Backtest regime-aware allocation against static baseline over multiple market periods (bull, bear, sideways) with walk-forward retraining.
- Metrics: Sharpe, Sortino, max drawdown, hit-rate of regime detection (precision/recall if synthetic labels available), turnover and transaction costs sensitivity.
- Ablation: test HMM-only, vol-only, HMM+BOCPD, and HMM+KF variants.

What I accomplished / next steps
- Created an initial literature-informed summary and a practical, implementable recommendation for MQL5 focusing on low-latency hybrid design.
- Next steps (suggested):
  1. Fetch and link specific recent (2020–2024) papers and implementations (arXiv/SSRN/Journal links) for citation in the repo.
  2. Prototype an offline HMM + BOCPD pipeline in Python to validate parameter choices and generate labeled regimes for MQL5 porting.
  3. Implement lightweight MQL5 modules: EWMA vol monitor, HMM forward filter (2–3 states), and Kalman trend filter; integrate BOCPD as optional module.

References and further reading
- Hamilton (1989) — Regime-switching models foundational work.
- Adams & MacKay (2007) — Bayesian Online Changepoint Detection.
- Survey papers (2020–2022) on regime detection and regime-aware allocation (collect specific citations during follow-up).

Prepared by: regime-detection-research subagent
