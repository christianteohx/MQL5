# 04_ML_PERCEPTRON_PLAN — ML Perceptron for Regime Classification

**Status**: DECISION MADE — see Section 1
**Updated**: 2026-04-08

---

## 1. Decision: Perceptron over HMM

### Comparison Table

| Criterion | Perceptron / MLP | Hidden Markov Model (HMM) |
|-----------|-----------------|--------------------------|
| **MQL5 inference path** | Train in Python → export params/CSV → read in EA | Train in Python → export transition matrix + emission params → compute forward pass in MQL5 |
| **Real-time complexity** | O(features × hidden) per forward pass — trivial for small nets | O(states²) per step for Viterbi/forward algorithm — also cheap, but requires matrix operations in MQL5 |
| **Small dataset fit** | Good if using regularization; works with sklearn Perceptron on <1000 samples | GaussianHMM needs enough data to estimate covariances; struggles with <500-1000 rows |
| **Out-of-sample generalization** | Depends on regularization and feature normalization; prone to overfitting without walk-forward validation | Markov property + transition matrix gives temporal smoothness; but emission parameters can overfit market-specific patterns |
| **Regime label alignment** | Supervised — can train to reproduce ATR percentile labels exactly | Unsupervised — HMM states are latent and not guaranteed to align with LOW/MID/HIGH |
| **Predicting transitions** | Natural: treat "next regime" as label, feed sequence features | Natural: HMM is already a transition model |
| **MQL5 implementation effort** | Low — just array lookups and a few multiply-adds | Medium — need matrix multiply, exponentials for forward pass |

### Rationale

The existing regime pipeline already labels regimes using **ATR percentile** (LOW/MID/HIGH = 0/1/2). This gives us a **supervised labeling scheme** from day one. A perceptron trained to predict those same labels:

- Aligns with the existing ATR percentile regime detector (not a black-box competing with it)
- Can use the same features already computed in `data_fetcher.py`
- Is a **static classifier**: no temporal state needed if we frame features correctly (e.g., rolling stats, lagged values)
- Deploys via the proven **Python → CSV → MQL5 read** bridge already documented in this plan
- Is simpler to validate: accuracy/F1 on held-out data is directly interpretable

**HMM is not rejected** — it is already in the pipeline (`label_generator.hmm_labels`) as an *alternative labeler*. But for **real-time inference inside MT5**, the perceptron is the better production choice.

**Go/No-Go: GO — Perceptron**

---

## 2. Implementation Sketch

### 2a. Integration Architecture

```
Python Training Pipeline          MQL5 EA (Greg / ClawTrend / ClawRev)
─────────────────────────         ─────────────────────────────────────
1. Load OHLCV from CSV            7. OnNewBar() trigger
2. Compute features               8. Read predictions.csv
3. Generate labels                9. Extract [symbol, bar_time, regime_pred, confidence]
   (ATR percentile or             10. Apply as confidence multiplier
   forward-return-based)               to existing ensemble signal
4. Train sklearn MLP / Perceptron
5. Walk-forward validate           File bridge (same pattern as backtest_analyzer.py):
6. Export:                                 Python writes predictions_YYYYMMDD.csv
   - predictions CSV (bar_time,            MQL5 reads latest predictions CSV,
     regime_pred, confidence)              checks bar_time match, applies
   - norm_params.json                      Use atomic rename for write safety
     (feature means/stdevs)
```

### 2b. Perceptron Architecture

**Task**: Classify next bar's regime (LOW=0 / MID=1 / HIGH=2) using features available at bar close.

**Input features** (from `data_fetcher.py`, all normalized with z-score):

| Feature | Source | Description |
|---------|--------|-------------|
| `atr_pct` | ATR percentile rolling | Current volatility percentile rank |
| `adx_val` | ADX 14 | Trend strength |
| `rsi_14` | RSI 14 | Overbought/oversold |
| `macd_norm` | MACD / ATR | Normalized momentum |
| `bb_width_norm` | BB width / rolling median | Volatility bandwidth |
| `mom_10_norm` | 10-bar momentum / ATR | Short-horizon directional |
| `vol_pct_100` | Realized vol (annualized) | Absolute volatility level |
| `returns_lag1` | `close.pct_change().shift(1)` | Last bar return |
| `atr_change` | `atr - atr.shift(1)` normalized | Volatility change direction |
| `trend_score` | ADX × sign(MACD) | Composite trend direction |

**Architecture**:

```
Input: 10 features (normalized z-score)
  ↓
Dense layer: 24 neurons, ReLU activation, L2 regularization (alpha=0.001)
  ↓
Dropout: 0.1 (during training; OFF at inference)
  ↓
Dense layer: 12 neurons, ReLU activation, L2 regularization (alpha=0.001)
  ↓
Output layer: 3 neurons, Softmax activation
  → [P(LOW), P(MID), P(HIGH)]
```

**Training config**:
- Solver: Adam (adaptive lr)
- Learning rate: 0.001
- Max iterations: 500 (early stopping on validation loss)
- Batch size: 32
- Regularization: L2 (alpha=0.001) + early stopping on walk-forward validation set
- Label scheme: ATR percentile LOW/MID/HIGH (same as existing `label_generator.atr_percentile_labels`)

**Alternative — Logistic Regression (simpler baseline)**:
If data is limited, start with `LogisticRegression(multi_class='multinomial', C=1.0)` — fewer parameters, more robust on small datasets. Graduate to MLP only if LR underperforms.

### 2c. Label Generation Strategy

**Option A — Regime state prediction (recommended for MVP)**:
- Label = ATR percentile regime at time t (LOW/MID/HIGH)
- Features = features at time t-1 (closed bar only)
- Goal: Predict current regime from lagged features
- Rationale: Matches existing ATR percentile regime detector. ML learns to approximate/improve on it.

**Option B — Regime transition prediction**:
- Label = ATR percentile regime at time t+1
- Features = features at time t
- Goal: Anticipate next regime before it happens
- More useful for trading but harder to predict; higher noise

**Start with Option A**. Transition prediction can be a later enhancement.

### 2d. MQL5 Integration Detail

The existing ATR percentile regime detector runs in MQL5 and computes LOW/MID/HIGH directly. The ML perceptron runs externally and outputs a **confidence multiplier**.

```
Signal_strength = existing_ensemble_signal  ×  ML_confidence_multiplier

Where:
  ML_confidence_multiplier = P(regime_pred)  [e.g., 0.0 to 1.5]
  Clamped to [0.5, 1.5] to prevent catastrophic signal destruction
```

**File format** (`predictions.csv`):
```csv
bar_time,symbol,regime_pred,prob_low,prob_mid,prob_high,confidence,model_version
2026-04-07 08:00,EURUSD,1,0.10,0.75,0.15,0.85,v1.0
```

**MQL5 reading logic (pseudocode)**:
```mql5
string latestFile;
long lastModified = 0;
string files[];
FileSelectFolder(...) // not needed — use known path
// Scan Files/ folder for predictions_*.csv
// Pick most recent by filename timestamp
// Read row, check bar_time matches current bar time
// If match: confidence = (double)row["confidence"];
// Else: confidence = 1.0 (neutral, ML not available)
```

### 2e. Exporting Normalization Parameters

The z-score normalization params (mean, std per feature) must be exported from Python and hardcoded or loaded by MQL5 so inference uses the same scaling:

```json
// norm_params.json
{
  "features": ["atr_pct", "adx_val", "rsi_14", "macd_norm", "bb_width_norm",
               "mom_10_norm", "vol_pct_100", "returns_lag1", "atr_change", "trend_score"],
  "mean": [0.5, 20.0, 50.0, 0.0, 0.02, 0.0, 0.15, 0.0, 0.0, 0.0],
  "std":  [0.25, 10.0, 15.0, 0.0005, 0.01, 0.002, 0.05, 0.01, 0.0001, 0.5]
}
```

MQL5 stores these as `const double` arrays at compile time. On each bar, features are computed, normalized, then the softmax is applied using precomputed weights.

**Alternative (simpler for v1)**: Skip normalization in MQL5 entirely. Have Python output discrete regime_pred (0/1/2) and a confidence score precomputed from the training set accuracy or from calibration. MQL5 just reads the CSV — no normalization math needed inside the EA.

---

## 3. Next Steps (Implementation Order)

### Step 1 — Data prep + baseline (Python only, no MQL5 yet)
- [ ] Load historical OHLCV CSV via `data_fetcher.py`
- [ ] Compute all 10 features
- [ ] Generate ATR percentile labels
- [ ] Train `LogisticRegression` baseline (multinomial)
- [ ] Walk-forward validate: 2-year train → 63-day test → roll forward
- [ ] Record: accuracy, F1 (weighted), per-class precision/recall, confusion matrix
- [ ] Threshold analysis: at what confidence does the model outperform the naive baseline (always predict majority class)?

### Step 2 — MLP if LR underperforms
- [ ] If LR F1 < 0.5 above baseline: train MLP (24×12 softmax)
- [ ] Same walk-forward validation
- [ ] Compare: does MLP beat LR enough to justify complexity?

### Step 3 — Export pipeline
- [ ] Add `predict_regime()` function in `trainer.py` or new `predictor.py`
- [ ] Export `norm_params.json` and `predictions.csv` with bar_time index
- [ ] Script: `python predict_regime.py --symbol EURUSD --output Files/predictions.csv`
- [ ] Document file naming convention and atomic rename pattern

### Step 4 — MQL5 integration
- [ ] Add `ReadM LPrediction()` function in Greg EA or a shared include
- [ ] On new bar: scan `Files/predictions_*.csv`, read latest matching symbol+bar
- [ ] Apply `confidence = clamp(prob_mid if regime_pred==MID else prob_high/low, 0.5, 1.5)`
- [ ] Add input toggle: `Use_ML_Predictions = true/false`
- [ ] Print regime + ML confidence to dashboard

### Step 5 — Validation
- [ ] Backtest Greg EA with ML toggle ON vs OFF (identical conditions)
- [ ] Walk-forward: retrain model monthly, ship new predictions.csv
- [ ] Monitor: does ML improve Sharpe / reduce drawdown / improve win rate in specific regimes?

---

## 4. Key Risks

| Risk | Mitigation |
|------|-----------|
| Overfitting (small dataset) | Strong L2 regularization, early stopping, walk-forward validation |
| Look-ahead bias | All features from closed bars only; labels from future ATR percentile computed honestly |
| Model staleness | Retrain cadence: weekly; log when prediction distribution shifts significantly |
| File sync issues | Atomic rename (Python writes .tmp → .csv); MQL5 checks timestamp |
| ML wrong in live market | Confidence multiplier clamped [0.5, 1.5]; EA falls back to ensemble-only if file missing |
| 3-state classification too noisy | Consider merging to 2-state (LOW/HIGH) first; or using confidence to abstain |

---

## 5. Commit Summary

Perceptron chosen over HMM for supervised alignment with ATR percentile labels, simpler MQL5 integration via CSV bridge, and better small-data robustness. MLP architecture: 10 inputs → Dense(24, ReLU) → Dense(12, ReLU) → Softmax(3). Integration: Option B (confidence multiplier on existing ensemble). Next step: build the Python training + prediction export pipeline, then validate against ATR percentile baseline.
