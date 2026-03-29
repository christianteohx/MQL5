What I changed:

- Added a new input: min_risk_pct_of_balance (default 5.0 = 5%) to set a balance-based minimum risk floor.
- Implemented a balance-based floor in both fixedPercentageVol() and optimizedVol():
  - Compute minRiskMoney = balance * (min_risk_pct_of_balance / 100.0)
  - Convert that to minLotsFromFloor = minRiskMoney / marginPerLot
  - Floor to stepVol and clamp between minVol and maxVol
  - Ensure finalLots = MathMax(finalLots, minLotsFromFloor)
- Updated PrintFormat statements in both functions to include the risk-floor debug info: "RiskFloor(balance=... minPct=...%% minLots=...)".

Notes / rationale:

- The new floor only affects the percentage-based sizing paths (fixedPercentageVol and optimizedVol). Fixed-volume mode (fixed_volume) is unchanged.
- The floor calculation uses margin-per-lot (margin required to open 1 lot) to convert a money floor into lots, which matches how the rest of the sizing code computes raw lots (riskMargin / marginPerLot).
- Default min_risk_pct_of_balance is set to 5.0 (5%) to meet the requested ~5-10% floor. If you prefer the alternative representation (0.05 meaning 5%), I can switch the default and the adapted printing logic.

Testing checklist I followed / recommendations:

- Inserted debug prints so backtests will show the computed risk floor per trade:
  - fixedPercentageVol prints: includes RiskFloor(...)
  - optimizedVol prints: includes RiskFloor(...)
- Recommended test: backtest on an account with $5k+ starting balance and a long losing streak to verify lots do not fall to 0.01 but respect the configured floor.

If you want me to adjust the input representation (0.05 vs 5.0) or to make the floor apply in a different way (e.g., based on SL distance and tick value rather than margin-per-lot), tell me which approach and I will update the code.
