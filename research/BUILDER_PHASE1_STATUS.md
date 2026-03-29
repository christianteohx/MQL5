Phase1 Regime Detector Implementation

What I implemented:
- Created Ma_Rsi_Phase1.mq5 implementing an ATR-based volatility regime detector as a self-contained module.
- Exposed inputs: atr_period, vol_lookback, vol_low_pct, vol_high_pct, regime_smooth_alpha, min_regime_bars.
- Implemented GetVolatilityRegime() which:
  - Creates/uses an iATR handle and CopyBuffer to fetch ATR values.
  - Computes rolling percentile of current ATR within the last vol_lookback bars by sorting the window and finding the rank.
  - Produces a continuous raw regime value (atr percentile), applies EMA smoothing using regime_smooth_alpha.
  - Classifies discrete regimes (0=LOW,1=MID,2=HIGH) using vol_low_pct and vol_high_pct thresholds.
  - Enforces min_regime_bars dwell time before allowing a regime switch.
  - Persists smoothed value and bars-since-switch in static variables across calls.
  - Displays a Comment() on chart and Print()s when regime changes.
- Added OnInit/OnDeinit/OnTick wrappers for standalone testing and cleaned up the ATR handle on deinit.

Notes and caveats:
- Rolling percentile is implemented by sorting the window each call (sufficient for vol_lookback ~100). For very large lookbacks a more efficient running order-statistic structure could be used.
- State is persisted in static variables (prev_regime_raw, bars_since_switch, last_discrete_regime). If the EA is reloaded these reset; for cross-session persistence consider GlobalVariables.
- The module uses Comment() which will overwrite other chart comments; integrate carefully into the main EA to avoid conflicts.

Files created:
- /Users/christianteohx/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/Program Files/MetaTrader 5/MQL5/Experts/Ma_Rsi/Ma_Rsi_Phase1.mq5
- /tmp/mql5-repo/research/BUILDER_PHASE1_STATUS.md

Next steps for integration:
- Import GetVolatilityRegime() into Ma_Rsi.mq5 and call it each bar, using the returned RegimeState to adjust strategy behavior.
- Optionally replace static persistence with GlobalVariableGet/Set if persistence across restarts is required.
