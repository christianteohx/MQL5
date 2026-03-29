# Greg EA — greg_regime_risk_v2

**Version:** 2.0  
**Type:** MetaTrader 5 Expert Advisor (MQL5)

---

## Overview

Greg EA is a trend-following expert advisor that combines:
- **EMA crossover** (fast vs. slow) for trend direction
- **RSI pullback** confirmation — only enters on RSI retraces toward centerline
- **ADX filter** — trend strength confirmation (optional)
- **ATR-based risk management** — dynamic SL/TP sizing
- **Volatility-regime awareness** (v2) — adapts SL/TP multipliers based on current market volatility
- **Guardrails** — daily loss limits, consecutive loss limits, session filters, spread checks
- **Trailing stop** with breakeven (risk-free) trigger
- **Live dashboard** — real-time chart comment with equity, P&L, regime, and position info

---

## Strategy Logic

### Entry Signal
1. **Trend:** Fast EMA > Slow EMA → bullish; Fast EMA < Slow EMA → bearish
2. **RSI pullback:** RSI must cross/pull back toward the centerline (50) in the direction of the trend:
   - Buy: `RSI >= RSI_Buy_Min` (default 50) AND RSI rising (`RSI[1] > RSI[2]`)
   - Sell: `RSI <= RSI_Sell_Max` (default 50) AND RSI falling (`RSI[1] < RSI[2]`)
3. **ADX filter** (optional): `ADX >= ADXMin` to confirm trend is directional

### Risk Management
- Position size = `% of equity × RiskPercent` (based on SL distance)
- Stop Loss and Take Profit sized in ATR multiples
- Hard cap on maximum lot size (`MaxLotsCap`)

### Trailing & Breakeven
- When reward:risk >= `BeThreshold`, SL moves to entry (risk-free)
- Standard ATR-based trailing stop activates after that

### Guardrails
- Max daily loss (% of equity)
- Max consecutive losses
- Max spread filter
- Session time filter

---

## Volatility Regime System (v2)

The core new feature in v2. The EA classifies the current market volatility into one of three regimes using the **ATR percentile method**:

### How It Works
1. Collect the last **100 bars** of ATR values (configurable via `VolRegimeLookback`)
2. Sort them to find the 33rd and 66th percentile values
3. Compare the current bar's ATR against these thresholds:
   - **LOW** — ATR below 33rd percentile (quiet market)
   - **MID** — ATR between 33rd and 66th percentile (normal market)
   - **HIGH** — ATR above 66th percentile (volatile market)

### Adaptive SL/TP Multipliers
The EA adjusts its SL and TP distances based on the detected regime:

| Regime | ATR SL Mult | ATR TP Mult | Rationale |
|--------|------------|-------------|-----------|
| **LOW** | 1.5× (tight) | 2.5× | Quiet markets need tighter stops; smaller targets |
| **MID** | 2.0× (default) | 3.0× | Normal conditions — standard behavior |
| **HIGH** | 2.5× (wide) | 4.0× | Volatile markets need room; larger targets to avoid premature exits |

These are configurable via the input parameters.

---

## Input Parameters

### Core Strategy
| Parameter | Default | Description |
|-----------|---------|-------------|
| `SignalTF` | H1 | Chart timeframe for signals |
| `FastEMA` | 20 | Fast EMA period |
| `SlowEMA` | 200 | Slow EMA period |
| `RSIPeriod` | 14 | RSI period |
| `ADXPeriod` | 14 | ADX period |
| `UseADXFilter` | true | Require ADX above `ADXMin` |
| `ADXMin` | 18.0 | Minimum ADX for signal |
| `RSI_Buy_Min` | 50.0 | Min RSI for buy signal |
| `RSI_Sell_Max` | 50.0 | Max RSI for sell signal |

### Risk / Trade Management
| Parameter | Default | Description |
|-----------|---------|-------------|
| `RiskPercent` | 0.5% | Equity risk per trade |
| `ATRPeriod` | 14 | ATR period |
| `UseTrailingStop` | true | Enable ATR trailing stop |
| `ATR_Trail_Mult` | 1.2 | Trailing stop ATR multiplier |
| `MaxLotsCap` | 1.0 | Hard cap on lot size |
| `OnePositionPerSymbol` | true | Only one open position per symbol |

### Volatility Regime (v2)
| Parameter | Default | Description |
|-----------|---------|-------------|
| `UseVolatilityRegime` | true | Enable regime-adaptive SL/TP |
| `VolRegimeLookback` | 100 | Bars for ATR percentile lookback |
| `VolLowThreshold` | 0.33 | Percentile below = LOW regime |
| `VolHighThreshold` | 0.66 | Percentile above = HIGH regime |
| `ATR_SL_Mult_LOW` | 1.5 | SL multiplier (LOW vol) |
| `ATR_TP_Mult_LOW` | 2.5 | TP multiplier (LOW vol) |
| `ATR_SL_Mult_MID` | 2.0 | SL multiplier (MID vol) |
| `ATR_TP_Mult_MID` | 3.0 | TP multiplier (MID vol) |
| `ATR_SL_Mult_HIGH` | 2.5 | SL multiplier (HIGH vol) |
| `ATR_TP_Mult_HIGH` | 4.0 | TP multiplier (HIGH vol) |

### Guardrails
| Parameter | Default | Description |
|-----------|---------|-------------|
| `MaxDailyLossPercent` | 2.0% | Stop trading after this daily loss |
| `MaxConsecutiveLosses` | 4 | Pause after this many consecutive losses |
| `MaxSpreadPoints` | 50.0 | Max spread to allow trades |
| `UseSessionFilter` | true | Enable trading hours filter |
| `SessionStartHour` | 7 | Session start (broker time) |
| `SessionEndHour` | 16 | Session end (broker time) |

### Breakeven
| Parameter | Default | Description |
|-----------|---------|-------------|
| `BeThreshold` | 1.5 | Move SL to entry when R:R >= this |

### Misc
| Parameter | Default | Description |
|-----------|---------|-------------|
| `Magic` | 13022026 | Magic number for position identification |
| `DebugLogs` | false | Enable verbose debug printing |
| `ShowDashboard` | true | Show chart comment dashboard |

---

## Installation

1. Copy `greg_regime_risk_v2.mq5` to:
   ```
   <MetaTrader 5 Data Folder>/MQL5/Experts/Greg/
   ```
2. In MetaTrader 5, open the **Navigator** panel → **Expert Advisors**
3. Find **greg_regime_risk_v2** under the Greg folder
4. Drag onto a chart or double-click to attach
5. Configure inputs as desired and click **OK**

For backtesting, attach the EA to a chart of the desired symbol/timeframe, then run the Strategy Tester (`Ctrl+R`).

---

## Dashboard (Chart Comment)

The EA prints a live dashboard showing:

```
Greg EA v2.0 | US500
----------------------------------------
Equity:   125000.00
Balance:  124500.00
Daily P&L: -320.00 (-0.26%)
----------------------------------------
Signal:   BUY
ATR(14):  12.50000
Vol Regime: MID  (50.0%tile)
SL Mult:  2.0  TP Mult:  3.0
Risk:     0.5%
----------------------------------------
Consecutive Losses: 2
Max Daily Loss: 2.0%
Max Consec Loss: 4
----------------------------------------
Position: Long 0.50 lots @ 5420.50 | P&L: 125.30
```

The **Vol Regime** line shows the current ATR-based volatility classification and its percentile rank. The SL/TP multipliers shown are the **effective** ones for the current regime.

---

## Files

| File | Description |
|------|-------------|
| `greg_regime_risk_v1.mq5` | Original EA without volatility regime |
| `greg_regime_risk_v2.mq5` | **Current** — adds volatility-regime SL/TP adaptation |
| `README.md` | This documentation |

---

## Regime Logic Reference

The regime detection is derived from **Phase1** (ATR volatility regime detector):

```
LOW  = current_ATR < 33rd percentile of last 100 ATR values
MID  = 33rd <= current_ATR <= 66th percentile
HIGH = current_ATR > 66th percentile
```

This approach is robust because:
- It adapts to the instrument's own volatility history (no fixed thresholds)
- Percentile ranking is relative — works the same on volatile instruments like crude as on calm ones like EUR/USD
- The `VolLowThreshold` and `VolHighThreshold` inputs allow tuning the sensitivity
