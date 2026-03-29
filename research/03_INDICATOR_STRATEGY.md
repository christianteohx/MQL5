# Indicator Strategy Research

## What I accomplished
Compiled research and recommendations for dynamic indicator adjustment strategies for multi-indicator trading systems. Covered:
- Best indicator combinations per regime
- Recommended weight profiles per regime
- Specific parameter adjustment formulas
- Transition/hysteresis strategies
- Implementation approach for MQL5
- Testing and validation plan

---

## 1. Best indicator combinations per regime type

1. Trending (strong trend)
- Primary indicators: Moving Average (MA) crossovers (EMA preferred), MACD (histogram and signal), ADX (trend strength)
- Supporting: Volume (OBV or VWAP), Momentum (RSI as trend confirmation rather than overbought/oversold)
- Rationale: MA crossovers and MACD capture directional momentum; ADX filters trend strength and reduces false signals.

2. Ranging (mean-reversion)
- Primary indicators: RSI, Stochastic Oscillator, Bollinger Bands
- Supporting: Mean Reversion entry rules using price action near support/resistance, VWAP for intra-day ranges
- Rationale: Oscillators identify extreme oscillations and Bollinger Bands indicate reversion zones.

3. High volatility
- Primary indicators: Volatility bands (Wilder Bands, wider Bollinger Band multipliers), ATR-based stops and position sizing
- Supporting: Volatility-adjusted MA periods (longer to avoid noise), use wider take-profit/stop-loss
- Rationale: High volatility increases noise; widen filters and stops to reduce whipsaw.

4. Low volatility
- Primary indicators: Shorter MA crossovers, tighter Bollinger multipliers, mean-reversion oscillators with smaller thresholds
- Supporting: Lower ATR multipliers for tighter stops, increase trade frequency with smaller size
- Rationale: When volatility is low, use more sensitive indicators and tighter risk settings.

5. Transitional / Mixed regimes
- Use regime-agnostic confidence measures (ensemble weighting) and require higher confidence thresholds to act.
- Combine trend and mean-reversion signals but require agreement or higher aggregated confidence.

---

## 2. Recommended weight profiles per regime
(Weights apply to an ensemble where each indicator emits a signal in [-1,0,1] with confidence c in [0,1]; final aggregate signal = sign(sum_i w_i * c_i * s_i))

1. Trending
- EMA crossover: 0.35
- MACD: 0.30
- ADX (>= threshold): 0.20 (used as a multiplier to trend weights when ADX indicates strong trend)
- Volume (OBV): 0.10
- Oscillators (RSI): 0.05 (confirmation only)

2. Ranging
- RSI/Stoch: 0.40
- Bollinger Bands: 0.30
- Mean-price/VWAP reversion: 0.20
- Short MA crossover (fast only): 0.10 (weak confirmation)

3. High volatility
- ATR-based filter/size: 0.30
- Volatility bands: 0.30
- Trend indicators (EMA/MACD): 0.20
- Oscillators: 0.20 (use conservatively)

4. Low volatility
- Short MAs: 0.30
- Oscillators: 0.30
- Bollinger (narrow): 0.20
- ATR-based sizing: 0.20

Notes:
- ADX can act multiplicatively: if ADX > ADX_high, multiply trend weights by (1 + k*(ADX-ADX_high)/ADX_high) clipped to a cap.
- Normalize weights so sum(w)=1 after any regime adjustments.

---

## 3. Specific parameter adjustment formulas

Notation:
- ATR_t = ATR at time t (period N_atr)
- Vol_t = volatility measure (e.g., 20-period historical volatility or ATR normalized)
- ADX_t = ADX at time t
- Base parameters: RSI_base = 14, MA_base_short = 9, MA_base_long = 26, BB_period = 20, BB_dev = 2

1. Volatility-weighted MA periods
- MA_short = round(MA_base_short * (1 + alpha * (Vol_t / Vol_ref - 1)))
- MA_long = round(MA_base_long * (1 + alpha * (Vol_t / Vol_ref - 1)))
- alpha ∈ [0.2, 0.8] (tuning parameter), Vol_ref is long-term median volatility (e.g., 100-day)
- Interpretation: higher volatility -> longer MAs to smooth noise; lower volatility -> shorter MAs to be more responsive.

2. Dynamic RSI thresholds
- Overbought = 70 + beta * (Vol_t / Vol_ref - 1) * 10
- Oversold = 30 - beta * (Vol_t / Vol_ref - 1) * 10
- beta ∈ [0.3, 0.8]
- Cap thresholds to [60, 85] for overbought and [15, 40] for oversold.
- Rationale: high volatility requires wider thresholds to avoid false extremes.

3. ATR-based SL/TP multipliers
- SL = price_entry - sign(direction) * ATR_t * m_sl(t)
- TP = price_entry + sign(direction) * ATR_t * m_tp(t)
- m_sl(t) = m_sl_base * (1 + gamma * (Vol_t / Vol_ref - 1))
- m_tp(t) = m_tp_base * (1 + gamma_tp * (Vol_t / Vol_ref - 1))
- Example: m_sl_base = 3, m_tp_base = 6, gamma ∈ [0.3, 1.0]

4. ADX as regime trigger
- Regime = Trending if ADX_t > ADX_high (e.g., 25-30)
- Regime = Ranging if ADX_t < ADX_low (e.g., 20)
- Between ADX_low and ADX_high = Mixed/uncertain

5. Weight interpolation between regimes
- Let R_trend ∈ [0,1] be trend-confidence (from ADX_scaled), R_range = 1 - R_trend
- w_i(t) = R_trend * w_i_trend + R_range * w_i_range
- Smooth R_trend via exponential smoothing: R_trend_s = alpha_r * R_trend_prev + (1-alpha_r) * R_trend_raw, alpha_r ∈ [0.85, 0.98]

6. Confidence scaling with volatility
- For each indicator i, adjust confidence: c_i_adj = c_i_raw * (1 + delta_i * (Vol_t / Vol_ref - 1)) for indicators that perform better in higher vol (e.g., trend indicators), or (1 - delta_i * ...) for ones that worsen.

---

## 4. Transition and hysteresis strategies

1. Hysteresis thresholds
- Use separate entry and exit thresholds for regime detection. Example: ADX_enter = 30, ADX_exit = 22.
- Only switch to trending when ADX > ADX_enter and only revert to ranging when ADX < ADX_exit.

2. Minimum dwell time
- After a regime change, enforce a minimum dwell time (e.g., 5-20 bars depending on timeframe) before allowing another change.

3. Smooth interpolation
- Use an EMA/smoothing on regime score (ADX_scaled, volatility score, momentum composite) with a long alpha (0.9) to avoid flicker.

4. Confidence threshold for action
- Require aggregated absolute signal magnitude S = |sum_i w_i * c_i * s_i| to exceed a threshold T_action which depends on regime confidence. In low-confidence/mixed regime, increase T_action.

5. Signal persistence
- Require the same directional signal to persist for k bars (k=1..3) before opening a position to reduce whipsaw.

6. Ensemble voting with decay
- Track recent N signals and weight them by recency (exponential decay). Use majority or weighted sum for final decision.

---

## 5. Implementation approach for MQL5

1. Architecture
- Modular indicators: implement each indicator as a function/class returning (signal, confidence)
- Regime detector module: computes ADX, volatility score, and outputs regime_score ∈ [0,1]
- Ensemble manager: holds weight profiles for each regime and computes final aggregated signal
- Risk manager: ATR-based position sizing, SL/TP computation, max concurrent trades
- State persistence: use GlobalVariables or files to persist regime_score and smoothed values across ticks

2. Practical MQL5 snippets / pseudocode
- Indicator function signature: tuple GetIndicatorSignal(string name, int handle, int shift)
- Regime smoothing: regime_smoothed = iCustom or manual EMA: regime_smoothed = Alpha*regime_smoothed_prev + (1-Alpha)*regime_raw
- Weight interpolation: compute w_i(t) per formulas and normalize
- Order execution: validate S > T_action and persistence k-bar rule before sending OrderSend

3. Performance considerations
- Reuse indicator handles (use iMA/iRSI/iADX handles) and call CopyBuffer rather than recomputing from scratch
- Calculate indicators only on new bar (OnTick -> check if new bar) for efficiency depending on timeframe
- Avoid heavy loops; vectorize with CopyBuffer ranges

4. Parameter exposure
- Expose key parameters as external inputs: alpha, beta, gamma, ADX thresholds, Vol_ref period, smoothing alphas, weight base sets

---

## 6. Testing and validation plan

1. Regime detection validation
- Label historical data into regimes via simple rules (ADX and volatility percentiles) and compute confusion matrix between detected regime and labeled regime
- Track metrics: precision/recall for detecting trending vs ranging, average dwell time, false change rate

2. Walk-forward analysis
- Split data into expanding windows: optimize parameters on in-sample, test on out-of-sample; roll-forward and accumulate results
- Track stability of parameter sets across windows

3. Backtesting per-regime metrics
- Compute returns, Sharpe, Sortino, max drawdown separately per regime (i.e., evaluate performance when system reports trending vs ranging)
- Also compute per-trade expectancy and percent profitable per regime

4. Sensitivity and ablation
- Sensitivity: vary alpha/beta/gamma and observe performance bands
- Ablation: remove one indicator at a time and measure impact on performance per regime

5. Robustness checks
- Add transaction costs and slippage
- Monte Carlo resampling of trade sequence and price paths
- Out-of-sample stress tests: shock volatility up/down, regime switches faster/slower

6. Live paper trading
- Run the system in paper mode with live market data, log regime scores, indicator signals, and keep detailed trace for each trade
- Compare live signals to backtest to detect lookahead or data mismatch issues

7. Key metrics to monitor in production
- Regime classification accuracy proxy (e.g., P&L per regime)
- Signal consistency (persistence counts)
- Trade entry vs predicted regime
- Rolling expectancy, win rate, average profit/loss per regime
- Latency and missed signal counts

---

## References and further reading (select)
- Campbell, Lo, MacKinlay — The Econometrics of Financial Markets (volatility/statistics)
- Perry J. Kaufman — Adaptive Moving Average and Adaptive systems
- Wells Wilder — ATR/ADX foundational papers
- Academic papers on regime switching models (Hamilton Markov switching)
- Practitioner articles on ensemble indicators and volatility targeting (e.g., articles on QuantStart, Quantpedia)


---

## Implementation notes for the main agent
- File written to: /tmp/mql5-repo/research/03_INDICATOR_STRATEGY.md
- The doc includes formulas and pseudocode-level guidance suitable to implement in MQL5; parameter ranges are suggestions and must be tuned per instrument/timeframe.
- Recommended next steps: implement modular indicator wrappers in MQL5, create a regime test harness, and run walk-forward optimization.

