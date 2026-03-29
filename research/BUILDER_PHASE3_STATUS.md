Ma_Rsi Phase3 implementation status

What I accomplished:
- Created Ma_Rsi_Phase3.mq5 as a self-contained Phase 3 module.
  - Adds inputs for enabling adaptive parameters and base scaling controls (MA, RSI, ATR SL/TP, BB dev).
  - Implements vol reference tracking (slow EMA-like) and GetVolRatio(current_atr).
  - Implements parameter adjustment helpers:
    - GetAdjustedMAPeriods
    - GetAdjustedRSIThresholds
    - GetAdjustedSLTP
    - GetAdjustedBBDev
  - Provides Phase3_GetAdjustedParams() so the main expert can query adjusted params.
  - OnTick() demonstrates usage and writes a Comment() with current vol_ratio and adjusted params.

Details main agent should know:
- The module is self-contained and does not modify Ma_Rsi.mq5. It is designed to be called from the main expert.
- Phase3_GetAdjustedParams() returns adjusted MA periods, RSI thresholds, SL/TP distances, BB deviation and vol_ratio.
- Volatility reference uses a slow-tracking average (initial incremental mean until vol_ref_period samples, then slow EMA). This was chosen for stability and backward-compatibility.
- Default fallbacks use base parameters when ATR cannot be read.
- Clamping is applied to keep RSI thresholds and BB dev in sensible ranges.

Next integration steps for main expert (not performed here):
- Include or #import this file/module and call Phase3_GetAdjustedParams() in OnTick() after obtaining regime state.
- Use returned values in MA computation, RSI comparisons, stop-loss/take-profit sizing and Bollinger band calculations.
- Ensure any existing parameter displays are extended to include the Phase3 outputs if desired.

Location of files created:
- /Users/christianteohx/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/Program Files/MetaTrader 5/MQL5/Experts/Ma_Rsi/Ma_Rsi_Phase3.mq5
- /tmp/mql5-repo/research/BUILDER_PHASE3_STATUS.md

If you want tweaks to the vol_ref behaviour (faster/slower), different clamping limits, or unit tests/examples integrated into the main expert, say which area to adjust.
