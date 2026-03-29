# GREG Expert (greg_regime_risk_v1) — Documentation

## What I accomplished
- Read the source file for the Greg expert: greg_regime_risk_v1.mq5
- Produced a clean markdown documentation file summarizing strategy, indicators, entries, risk management, guardrails, differences from Ma_Rsi, and potential ideas to borrow.
- Saved the document to: /tmp/mql5-repo/research/GREG_EXPERT_DOC.md

---

# GREG Expert (greg_regime_risk_v1)

## Strategy Overview
- Type: Trend-following with pullback/continuation bias.
- Timeframe: Configurable via input (default SignalTF = H1).
- Core idea: Detect regime using fast vs slow EMA (20 / 200 default) and enter on pullbacks confirmed by momentum (RSI) and optional trend strength (ADX). Uses ATR to size risk, set SL/TP and optional trailing stops.

## Indicator Setup
- Fast EMA: period = FastEMA (default 20) on SignalTF timeframe.
- Slow EMA: period = SlowEMA (default 200) on SignalTF timeframe.
- RSI: period = RSIPeriod (default 14) on SignalTF timeframe.
  - RSI thresholds: RSI_Buy_Min (default 50.0) and RSI_Sell_Max (default 50.0).
- ADX: period = ADXPeriod (default 14) on SignalTF timeframe. Optional filter (UseADXFilter = true) with ADXMin default 18.0.
- ATR: period = ATRPeriod (default 14) on SignalTF timeframe. ATR used for SL, TP, trailing stop sizing.

## Entry Logic
- Signals evaluated on closed bars (uses indicator buffers and closed-bar values).
- Trend detection:
  - Bullish regime if FastEMA (prior closed bar) > SlowEMA (prior closed bar).
  - Bearish regime if FastEMA < SlowEMA.
- Momentum/Pullback confirmation (RSI-based):
  - Buy condition: trendUp && RSI_closed >= RSI_Buy_Min && RSI_closed > RSI_prev
  - Sell condition: trendDn && RSI_closed <= RSI_Sell_Max && RSI_closed < RSI_prev
  - In plain terms: in an uptrend, RSI above centerline (>= 50) and increasing; in a downtrend, RSI below or at centerline (<= 50) and decreasing.
- ADX filter (optional): both buy and sell conditions require ADX >= ADXMin when UseADXFilter is true.
- Final signal: +1 for buy, -1 for sell, 0 otherwise.
- Only one position per symbol if OnePositionPerSymbol is true.

## Trade Execution and Price/Levels
- Entry price: uses current ask for buys and bid for sells at execution time.
- Stop Loss: ATR_SL_Mult * ATR (default 2.0) away from entry.
- Take Profit: ATR_TP_Mult * ATR (default 3.0) away from entry.
- Trailing stop (optional): if enabled, adjusts SL to follow price at ATR_Trail_Mult * ATR (default 1.2) behind price.

Code snippets (conceptual):
- SL/TP calculation (buy):
  sl = entry - ATR_SL_Mult * atr
  tp = entry + ATR_TP_Mult * atr
- SL/TP calculation (sell):
  sl = entry + ATR_SL_Mult * atr
  tp = entry - ATR_TP_Mult * atr

## Position Sizing / Risk Management
- RiskPercent (input): percentage of account equity risked per trade (default 0.5%).
- Lots computed by function LotsByRisk(entryPrice, slPrice):
  - riskMoney = equity * (RiskPercent / 100)
  - distance (price difference) to SL converted into money per lot using SYMBOL_TRADE_TICK_VALUE and SYMBOL_TRADE_TICK_SIZE
  - rawLots = riskMoney / moneyPerLotAtSL
  - Passed through ClampVolume which enforces symbol min/max, step, MaxLotsCap and rounding.
- Hard cap on lots: MaxLotsCap (default 1.0).
- trade.SetDeviationInPoints(20) used for slippage tolerance in Trade object.

## Guardrails / Safety Features
- Session filter: UseSessionFilter (default true) with SessionStartHour (7) and SessionEndHour (16) — prevents new trades outside configured server-time window.
- Spread check: MaxSpreadPoints (default 50 points) — skip if current spread in points exceeds limit.
- Max daily loss: MaxDailyLossPercent (default 2.0%) — calculates closed P&L since day start for this symbol and EA magic; stops opening new trades if P&L <= negative limit.
- Consecutive losses: MaxConsecutiveLosses (default 4) — counts recent history deals for this symbol/magic and blocks new trades when exceeded.
- One position per symbol: OnePositionPerSymbol prevents opening if existing position with EA magic exists.
- Max lots cap and symbol volume clamp to prevent oversized position.
- Debug logging toggle: DebugLogs.

## Trailing Stop Behavior
- ManageTrailing runs every new bar after signal check and will modify position SL to be at a distance ATR_Trail_Mult * ATR from the current best price (bid for buys, ask for sells) only if new SL is more protective (for buy: newSL > current SL; for sell: newSL < current SL) or when SL was zero.

## How it differs from Ma_Rsi (summary / likely differences)
Note: Ma_Rsi isn't included here; differences are inferred from Greg's implementation and typical Ma_Rsi designs.

- Regime detection: Greg explicitly uses a long-term slow EMA (200) vs a fast EMA (20) to detect regime — Ma_Rsi may rely on short MAs or RSI crossover logic without a dedicated slow EMA regime filter.
- ATR-based SL/TP sizing and risk-based lot calculation by percent of equity: Greg computes lots dynamically from ATR distance and tick value — Ma_Rsi might use fixed lot sizing or simpler risk rules.
- Multiple guardrails: Greg includes daily loss limit, consecutive-loss counter, max spread check, session time filter, and a hard cap on lots — these safety features may be absent or less extensive in Ma_Rsi.
- ADX optional filter: Greg provides an ADX threshold to require trending conditions; Ma_Rsi may not use ADX.
- Trailing stop driven by ATR multiples rather than fixed-point trailing or none.
- One-position-per-symbol enforcement and magic-number scoped history checks are explicit.

## Potential ideas to borrow into Ma_Rsi
- Daily loss guard (MaxDailyLossPercent) — helps avoid running during drawdown days.
- Consecutive loss limit — simple and effective risk control to pause trading after repeated failures.
- ATR-based dynamic SL/TP sizing and ATR-based trailing stop multiplier — adapts to instrument volatility.
- Risk-by-money-percent with conversion from pips to tick-value to compute accurate lot sizing — more precise money risk control than fixed lots.
- Session filter and max spread check — practical execution guards.
- OnePositionPerSymbol + magic-scoped closed-deal scanning for guard checks — helps keep bookkeeping reliable.

## Notes / Observations / Caveats
- Signal evaluation uses closed-bar values (CopyBuffer & index 1 for prior closed bar), which avoids repainting but means trades are only considered on new bar arrival.
- The RSI thresholds are centered at 50 by default; buy requires >=50 and rising, sell <=50 and falling. This makes the strategy a momentum continuation on pullbacks rather than extreme-mean reversion.
- ClosedPnlSince uses HistoryDeal API and sums profit + swap + commission for deals with DEAL_ENTRY_OUT — ensure broker history includes those fields and time selection Granularity matches expectations.
- RefreshConsecutiveLosses scans history from latest backward; it stops on first non-loss, counting only trailing consecutive losing closed deals for this symbol/magic.
- LotsByRisk depends on SYMBOL_TRADE_TICK_VALUE and SYMBOL_TRADE_TICK_SIZE — these must be valid for accurate sizing; otherwise function returns 0 and trade is skipped.

---

Generated by an automated read of greg_regime_risk_v1.mq5 source.
