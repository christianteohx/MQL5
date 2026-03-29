Ma_Rsi Phase2 builder status

What I implemented:
- Created Ma_Rsi_Phase2.mq5 as a self-contained module implementing regime-adaptive weight profiles.
- Implemented WeightProfile struct and default profiles (trend, range, highvol, lowvol).
- Added user inputs for base weights, regime-specific weights, high/low volatility weights, smoothing alpha, and ADX thresholds.
- Implemented GetRegimeWeights(regime, adx, atr, vol) that:
  - computes a smoothed trend confidence from ADX (uses EMA with regime_weight_alpha)
  - constructs profile blends between range and trend, then blends with high/low-vol profiles based on a volatility metric
  - normalizes final profile
- Added BaseProfileFromInputs() to preserve backward compatibility when adaptive weights are OFF.
- Added ComputeCombinedSignal(...) which multiplies per-indicator confidences by regime-adjusted weights and normalizes contributions.
- Added OnTick_Example() stub demonstrating how to call the module and a Comment() that prints current profile and contributions.

Notes / caveats:
- This module is intentionally self-contained and does not modify Ma_Rsi.mq5.
- The vol_metric parameter is left generic; in the example it uses ATR as a simple volatility proxy. Integration code can pass any volatility estimate.
- Some mapping from user inputs (e.g., ATR-based weights) to profile fields is heuristic; when integrated into Ma_Rsi, you may want to refine exact mappings.
- The smoothing state (R_trend_smooth) is kept in-file as a static double. If multiple symbols/timeframes share the module, consider moving smoothing per-symbol/timeframe.

Files created:
- /Users/christianteohx/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/Program Files/MetaTrader 5/MQL5/Experts/Ma_Rsi/Ma_Rsi_Phase2.mq5
- /tmp/mql5-repo/research/BUILDER_PHASE2_STATUS.md

Next steps for integrator (main agent):
- Call ComputeCombinedSignal(...) from Ma_Rsi.mq5 OnTick() after calculating individual indicator confidences.
- Pass appropriate current_regime, adx_value, atr_value, and a chosen vol metric when calling GetRegimeWeights.
- Optionally print weight profile when regime changes (compare previous profile to current and print via Print() or Comment()).

Status: Completed phase 2 module creation.