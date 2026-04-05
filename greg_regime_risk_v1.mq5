#property strict
#property version   "1.23"
#property description "Greg EA v1.23 - Improved Dashboard + Smoothed-ADX display + CSV Trade Logger + Regime edge-case fixes"

#include <Trade/Trade.mqh>

CTrade trade;

// ========================= Inputs =========================
input group "=== Core Strategy ===";
input ENUM_TIMEFRAMES SignalTF = PERIOD_H1;
input int FastEMA = 20;
input int SlowEMA = 200;
input int RSIPeriod = 14;
input int ADXPeriod = 14;
input bool UseADXFilter = true;
input double ADXMin = 18.0;
input int SupertrendPeriod = 10;
input double SupertrendMult = 3.0;
input double RSI_Buy_Min = 50.0;
input double RSI_Sell_Max = 50.0;

input group "=== Risk / Trade Management ===";
input double RiskPercent = 0.5;          // % of equity per trade
input double ATR_SL_Mult = 2.0;
input double ATR_TP_Mult = 3.0;
input int ATRPeriod = 14;
input bool UseTrailingStop = true;
input double ATR_Trail_Mult = 1.2;
input double MaxLotsCap = 1.0;           // hard cap safety
input bool OnePositionPerSymbol = true;
input bool UseVolatilityRiskScaling = true;
input double LowVolRiskMult = 1.20;      // scale RiskPercent in LOW vol regime
input double MidVolRiskMult = 1.00;      // scale RiskPercent in MID vol regime
input double HighVolRiskMult = 0.70;     // scale RiskPercent in HIGH vol regime
input double MinRiskPercentFloor = 0.10; // safety floor after scaling
input int MaxBarsInTrade = 20;           // time-based exit threshold (bars)
input int BBPeriod = 20;                 // Bollinger period
input double BBStdDev = 2.0;             // Bollinger std dev
input double ZScoreThreshold = 1.5;      // Min |z| for stretch
input int MidRegimeADXMax = 25;          // Max ADX for MR in MID regime
input bool UseMREntryFilter = true;      // Master toggle
input int ATRLookback = 100;            // Lookback bars for ATR percentile regime
input double RegimeHysteresis = 0.05;    // ATR must exceed threshold by this much to switch
input double RegimeSmoothAlpha = 0.35;   // EMA smoothing factor for ATR used in regime classification

input group "=== Guardrails ===";
input double MaxDailyLossPercent = 2.0;  // stop opening new trades after this
input int MaxConsecutiveLosses = 4;
input double MaxSpreadPoints = 50.0;
input bool UseSessionFilter = true;
input int SessionStartHour = 7;          // server time
input int SessionEndHour = 16;           // server time

input group "=== Breakeven / Risk-Free ===";
input double BeThreshold = 1.5;          // Move SL to entry when reward:risk >= this

input group "=== Misc ===";
input long Magic = 13022026;
input bool DebugLogs = false;            // Set to true only for debugging
input bool ShowDashboard = true;        // Show chart comment dashboard
input string TradeLogPath = "GregTradeLogger.csv"; // CSV log file (MQL5/Files/)

// ========================= Indicator handles =========================
int hFastEMA = INVALID_HANDLE;
int hSlowEMA = INVALID_HANDLE;
int hRSI = INVALID_HANDLE;
int hADX = INVALID_HANDLE;
int hATR = INVALID_HANDLE;
int hEMA50 = INVALID_HANDLE;
int hStdDev = INVALID_HANDLE;
int hBands = INVALID_HANDLE;
int hSupertrend = INVALID_HANDLE;

// ========================= State =========================
datetime g_lastBarTime = 0;
int g_consecutiveLosses = 0;
double g_lastEffectiveRiskPercent = 0.0;
datetime g_lastClosedTradeTime = 0;
string g_lastOpenRegimeAtEntry = "N/A";
string g_lastVolRegime = "N/A";
double g_smoothedATR = 0.0;
datetime g_volThresholdCacheBarTime = 0;
double g_cachedATRp33 = 0.0;
double g_cachedATRp66 = 0.0;
bool g_hasVolThresholdCache = false;
datetime g_volRegimeEvalBarTime = 0;
string g_cachedVolRegime = "N/A";
double g_smoothedADX = 0.0;
datetime g_adxCacheBarTime = 0;
double g_cachedAdxValue = 0.0;
bool g_hasAdxCache = false;

// ========================= Helpers =========================
bool IsNewBar(ENUM_TIMEFRAMES tf) {
   datetime t = iTime(_Symbol, tf, 0);
   if(t == 0) return false;
   if(g_lastBarTime == 0) {
      g_lastBarTime = t;
      return false;
   }
   if(t != g_lastBarTime) {
      g_lastBarTime = t;
      return true;
   }
   return false;
}

bool SessionAllowed() {
   if(!UseSessionFilter) return true;
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(SessionStartHour <= SessionEndHour)
      return (dt.hour >= SessionStartHour && dt.hour <= SessionEndHour);
   // overnight window
   return (dt.hour >= SessionStartHour || dt.hour <= SessionEndHour);
}

datetime DayStart(datetime t) {
   MqlDateTime dt;
   TimeToStruct(t, dt);
   dt.hour = 0;
   dt.min = 0;
   dt.sec = 0;
   return StructToTime(dt);
}

double ClosedPnlSince(datetime fromTime) {
   if(!HistorySelect(fromTime, TimeCurrent())) return 0.0;
   double pnl = 0.0;
   int total = HistoryDealsTotal();
   for(int i=0;i<total;i++) {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol) continue;
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != Magic) continue;
      long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT) continue;
      pnl += HistoryDealGetDouble(ticket, DEAL_PROFIT);
      pnl += HistoryDealGetDouble(ticket, DEAL_SWAP);
      pnl += HistoryDealGetDouble(ticket, DEAL_COMMISSION);
   }
   return pnl;
}

void RefreshConsecutiveLosses() {
   g_consecutiveLosses = 0;
   if(!HistorySelect(0, TimeCurrent())) return;
   int total = HistoryDealsTotal();
   for(int i=total-1;i>=0;i--) {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) break;
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol) continue;
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != Magic) continue;
      long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT) continue;
      double p = HistoryDealGetDouble(ticket, DEAL_PROFIT)
               + HistoryDealGetDouble(ticket, DEAL_SWAP)
               + HistoryDealGetDouble(ticket, DEAL_COMMISSION);
      if(p < 0) g_consecutiveLosses++;
      else break;
   }
}

bool RiskGuardsPass() {
   RefreshConsecutiveLosses();
   if(g_consecutiveLosses >= MaxConsecutiveLosses) {
      if(DebugLogs) Print("Risk guard: max consecutive losses hit: ", g_consecutiveLosses);
      return false;
   }

   datetime ds = DayStart(TimeCurrent());
   double pnlToday = ClosedPnlSince(ds);
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   double lossLimit = -(eq * (MaxDailyLossPercent/100.0));
   if(pnlToday <= lossLimit) {
      if(DebugLogs) PrintFormat("Risk guard: daily loss hit. pnlToday=%.2f limit=%.2f", pnlToday, lossLimit);
      return false;
   }

   return true;
}

bool SpreadPass() {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(ask <= 0 || bid <= 0) return false;
   double spreadPts = (ask - bid) / _Point;
   return spreadPts <= MaxSpreadPoints;
}

bool HasOpenPosition() {
   if(!PositionSelect(_Symbol)) return false;
   return (PositionGetInteger(POSITION_MAGIC) == Magic);
}

double ClampVolume(double lots) {
   double minV = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxV = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0) step = 0.01;
   lots = MathMax(minV, MathMin(maxV, lots));
   lots = MathMin(lots, MaxLotsCap);
   lots = step * MathFloor(lots / step);

   int prec = 2;
   if(step < 1.0) prec = (int)MathRound(-MathLog10(step));
   return NormalizeDouble(lots, prec);
}

double LotsByRisk(double entryPrice, double slPrice, double riskPercentToUse) {
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskMoney = eq * (riskPercentToUse / 100.0);
   if(riskMoney <= 0.0) return 0.0;

   double dist = MathAbs(entryPrice - slPrice);
   if(dist <= 0.0) return 0.0;

   // Respect broker minimum stop distance for safer sizing in ultra-low ATR conditions.
   double stopsLevelPts = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minStopDist = stopsLevelPts * _Point;
   if(minStopDist > 0.0 && dist < minStopDist) dist = minStopDist;

   // Robust risk-per-lot in account currency via OrderCalcProfit (avoids tick-value edge cases).
   ENUM_ORDER_TYPE calcType = (slPrice < entryPrice ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
   double slCalc = (calcType == ORDER_TYPE_BUY) ? (entryPrice - dist) : (entryPrice + dist);
   double oneLotLoss = 0.0;
   if(!OrderCalcProfit(calcType, _Symbol, 1.0, entryPrice, slCalc, oneLotLoss)) return 0.0;

   double moneyPerLotAtSL = MathAbs(oneLotLoss);
   if(moneyPerLotAtSL <= 0.0) return 0.0;

   double rawLots = riskMoney / moneyPerLotAtSL;
   return ClampVolume(rawLots);
}

double EffectiveRiskPercent(double atrVal) {
   double eff = RiskPercent;
   if(!UseVolatilityRiskScaling) return eff;

   string vr = GetVolatilityRegime(atrVal);
   if(vr == "LOW") eff *= LowVolRiskMult;
   else if(vr == "HIGH") eff *= HighVolRiskMult;
   else eff *= MidVolRiskMult;

   if(eff < MinRiskPercentFloor) eff = MinRiskPercentFloor;
   return eff;
}

int SignalDirection(double &atrOut) {
   // Read closed bars only: [1] current closed, [2] previous closed
   double fast[3], slow[3], rsi[3], adx[3], atr[3];

   ArraySetAsSeries(fast, true);
   ArraySetAsSeries(slow, true);
   ArraySetAsSeries(rsi, true);
   ArraySetAsSeries(adx, true);
   ArraySetAsSeries(atr, true);

   if(CopyBuffer(hFastEMA, 0, 0, 3, fast) < 3) return 0;
   if(CopyBuffer(hSlowEMA, 0, 0, 3, slow) < 3) return 0;
   if(CopyBuffer(hRSI, 0, 0, 3, rsi) < 3) return 0;
   if(CopyBuffer(hATR, 0, 0, 3, atr) < 3) return 0;
   if(UseADXFilter && CopyBuffer(hADX, 0, 0, 3, adx) < 3) return 0;

   atrOut = atr[1];
   if(atrOut <= 0) return 0;

   bool trendUp = fast[1] > slow[1];
   bool trendDn = fast[1] < slow[1];

   // Pullback + continuation style: price momentum via RSI around centerline
   bool buyCond = trendUp && (rsi[1] >= RSI_Buy_Min) && (rsi[1] > rsi[2]);
   bool sellCond = trendDn && (rsi[1] <= RSI_Sell_Max) && (rsi[1] < rsi[2]);

   if(UseADXFilter) {
      buyCond = buyCond && (adx[1] >= ADXMin);
      sellCond = sellCond && (adx[1] >= ADXMin);
   }

   if(buyCond && !sellCond) return +1;
   if(sellCond && !buyCond) return -1;
   return 0;
}

bool UpdateVolatilityThresholdCache() {
   datetime barTime = iTime(_Symbol, SignalTF, 1); // closed bar
   if(barTime == 0) return false;
   if(g_hasVolThresholdCache && g_volThresholdCacheBarTime == barTime) return true;

   // Compute ATR percentile vs ATRLookback closed bars: LOW < 33rd, HIGH > 66th, else MID
   double atrArr[];
   ArrayResize(atrArr, ATRLookback);
   ArraySetAsSeries(atrArr, true);
   if(CopyBuffer(hATR, 0, 1, ATRLookback, atrArr) < ATRLookback) return false;

   // Bubble sort to get percentiles (simple and reliable)
   for(int i = 0; i < ATRLookback - 1; i++) {
      for(int j = i + 1; j < ATRLookback; j++) {
         if(atrArr[j] < atrArr[i]) {
            double tmp = atrArr[i];
            atrArr[i] = atrArr[j];
            atrArr[j] = tmp;
         }
      }
   }

   int p33Idx = MathMax(0, MathMin(ATRLookback - 1, (int)MathRound(0.33 * ATRLookback) - 1));
   int p66Idx = MathMax(0, MathMin(ATRLookback - 1, (int)MathRound(0.66 * ATRLookback) - 1));
   g_cachedATRp33 = atrArr[p33Idx];
   g_cachedATRp66 = atrArr[p66Idx];
   if(g_cachedATRp66 < g_cachedATRp33) {
      double tmp = g_cachedATRp66;
      g_cachedATRp66 = g_cachedATRp33;
      g_cachedATRp33 = tmp;
   }

   g_volThresholdCacheBarTime = barTime;
   g_hasVolThresholdCache = true;
   return true;
}

double GetSmoothedADX() {
   datetime barTime = iTime(_Symbol, SignalTF, 1); // closed bar
   if(barTime == 0) return -1.0;
   if(g_hasAdxCache && g_adxCacheBarTime == barTime) return g_cachedAdxValue;

   double adx[2];
   ArraySetAsSeries(adx, true);
   if(CopyBuffer(hADX, 0, 0, 2, adx) < 2) return -1.0;
   if(adx[1] <= 0.0) return -1.0;

   double alpha = MathMax(0.0, MathMin(1.0, RegimeSmoothAlpha));
   // Bootstrap: if alpha is effectively 0 OR we have no prior value, use raw ADX directly.
   if(alpha <= 0.0 || g_smoothedADX <= 0.0) g_smoothedADX = adx[1];
   else g_smoothedADX = alpha * adx[1] + (1.0 - alpha) * g_smoothedADX;

   g_cachedAdxValue = g_smoothedADX;
   g_adxCacheBarTime = barTime;
   g_hasAdxCache = true;
   return g_cachedAdxValue;
}

string GetVolatilityRegime(double currentATR) {
   datetime barTime = iTime(_Symbol, SignalTF, 1); // evaluate once per closed bar
   if(barTime == 0) return "N/A";
   if(g_volRegimeEvalBarTime == barTime) return g_cachedVolRegime;

   if(!UpdateVolatilityThresholdCache()) return "N/A";

   if(currentATR <= 0.0) {
      double atr[2];
      ArraySetAsSeries(atr, true);
      if(CopyBuffer(hATR, 0, 0, 2, atr) < 2 || atr[1] <= 0.0) return "N/A";
      currentATR = atr[1];
   }

   // Smooth ATR input to reduce abrupt regime flips.
   double alpha = MathMax(0.0, MathMin(1.0, RegimeSmoothAlpha));
   // Bootstrap: if alpha is effectively 0 OR we have no prior value, use raw ATR directly.
   if(alpha <= 0.0 || g_smoothedATR <= 0.0) g_smoothedATR = currentATR;
   else g_smoothedATR = alpha * currentATR + (1.0 - alpha) * g_smoothedATR;

   double atrEval = g_smoothedATR;
   if(atrEval <= 0.0) return "N/A";

   // Stateful hysteresis: only switch when crossing opposite side with margin.
   double lowEnter  = g_cachedATRp33 - RegimeHysteresis * g_cachedATRp33;
   double lowExit   = g_cachedATRp33 + RegimeHysteresis * g_cachedATRp33;
   double highEnter = g_cachedATRp66 + RegimeHysteresis * g_cachedATRp66;
   double highExit  = g_cachedATRp66 - RegimeHysteresis * g_cachedATRp66;

   string prev = g_lastVolRegime;
   string next = "MID";

   if(prev == "LOW") {
      if(atrEval >= lowExit) next = "MID";
      else next = "LOW";
   } else if(prev == "HIGH") {
      if(atrEval <= highExit) next = "MID";
      else next = "HIGH";
   } else {
      if(atrEval < lowEnter) next = "LOW";
      else if(atrEval > highEnter) next = "HIGH";
      else next = "MID";
   }

   g_lastVolRegime = next;
   g_cachedVolRegime = next;
   g_volRegimeEvalBarTime = barTime;
   return g_cachedVolRegime;
}

bool ZScoreStretch(int dir) {
   // z = (Close - EMA50) / StdDev(50), evaluated on closed bar [1]
   double ema50[2], sd50[2], closeArr[2];
   ArraySetAsSeries(ema50, true);
   ArraySetAsSeries(sd50, true);
   ArraySetAsSeries(closeArr, true);

   if(CopyBuffer(hEMA50, 0, 0, 2, ema50) < 2) return false;
   if(CopyBuffer(hStdDev, 0, 0, 2, sd50) < 2) return false;
   if(CopyClose(_Symbol, SignalTF, 0, 2, closeArr) < 2) return false;

   if(sd50[1] <= 0.0) return false;

   double z = (closeArr[1] - ema50[1]) / sd50[1];

   if(dir > 0) return (z <= -ZScoreThreshold);
   if(dir < 0) return (z >= ZScoreThreshold);
   return false;
}

int SupertrendDirection() {
   // Determine trend using closed bar [1] relative to Supertrend line
   double st[3], closeArr[3];
   ArraySetAsSeries(st, true);
   ArraySetAsSeries(closeArr, true);

   if(CopyBuffer(hSupertrend, 0, 0, 3, st) < 3) return 0;
   if(CopyClose(_Symbol, SignalTF, 0, 3, closeArr) < 3) return 0;
   if(st[1] <= 0.0) return 0;

   if(closeArr[1] > st[1]) return +1;
   if(closeArr[1] < st[1]) return -1;
   return 0;
}

bool BBReentrySignal(int dir) {
   // Long: bar[2] below lower band, bar[1] closes back inside + RSI cross above 30
   // Short: bar[2] above upper band, bar[1] closes back inside + RSI cross below 70
   double upper[3], lower[3], rsi[3], closeArr[3];
   ArraySetAsSeries(upper, true);
   ArraySetAsSeries(lower, true);
   ArraySetAsSeries(rsi, true);
   ArraySetAsSeries(closeArr, true);

   if(CopyBuffer(hBands, 1, 0, 3, upper) < 3) return false;
   if(CopyBuffer(hBands, 2, 0, 3, lower) < 3) return false;
   if(CopyBuffer(hRSI, 0, 0, 3, rsi) < 3) return false;
   if(CopyClose(_Symbol, SignalTF, 0, 3, closeArr) < 3) return false;

   if(dir > 0) {
      bool wasOutside = (closeArr[2] < lower[2]);
      bool reentered = (closeArr[1] > lower[1]);
      bool rsiCross = (rsi[2] <= 30.0 && rsi[1] > 30.0);
      return (wasOutside && reentered && rsiCross);
   }

   if(dir < 0) {
      bool wasOutside = (closeArr[2] > upper[2]);
      bool reentered = (closeArr[1] < upper[1]);
      bool rsiCross = (rsi[2] >= 70.0 && rsi[1] < 70.0);
      return (wasOutside && reentered && rsiCross);
   }

   return false;
}


bool GetLatestClosedDealSince(datetime fromTime, ulong &dealTicketOut, datetime &dealTimeOut) {
   dealTicketOut = 0;
   dealTimeOut = 0;

   datetime startTime = (fromTime > 0 ? fromTime : 0);
   if(!HistorySelect(startTime, TimeCurrent())) return false;

   int total = HistoryDealsTotal();
   for(int i = total - 1; i >= 0; i--) {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol) continue;
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != Magic) continue;
      if(HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;

      datetime dt = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
      if(dt <= fromTime) continue;

      dealTicketOut = ticket;
      dealTimeOut = dt;
      return true;
   }

   return false;
}

void PrintTradeJournal(ulong closeDealTicket) {
   if(closeDealTicket == 0) return;
   if(!HistorySelect(0, TimeCurrent())) return;

   long positionId = HistoryDealGetInteger(closeDealTicket, DEAL_POSITION_ID);
   datetime exitTime = (datetime)HistoryDealGetInteger(closeDealTicket, DEAL_TIME);
   double exitPrice = HistoryDealGetDouble(closeDealTicket, DEAL_PRICE);
   double exitPnl = HistoryDealGetDouble(closeDealTicket, DEAL_PROFIT)
                  + HistoryDealGetDouble(closeDealTicket, DEAL_SWAP)
                  + HistoryDealGetDouble(closeDealTicket, DEAL_COMMISSION);

   ulong entryDealTicket = 0;
   datetime entryTime = 0;
   for(int i = 0; i < HistoryDealsTotal(); i++) {
      ulong t = HistoryDealGetTicket(i);
      if(t == 0) continue;
      if(HistoryDealGetString(t, DEAL_SYMBOL) != _Symbol) continue;
      if(HistoryDealGetInteger(t, DEAL_MAGIC) != Magic) continue;
      if(HistoryDealGetInteger(t, DEAL_POSITION_ID) != positionId) continue;
      if(HistoryDealGetInteger(t, DEAL_ENTRY) != DEAL_ENTRY_IN) continue;

      datetime tIn = (datetime)HistoryDealGetInteger(t, DEAL_TIME);
      if(entryDealTicket == 0 || tIn < entryTime) {
         entryDealTicket = t;
         entryTime = tIn;
      }
   }
   if(entryDealTicket == 0) return;

   long entryType = HistoryDealGetInteger(entryDealTicket, DEAL_TYPE);
   string direction = (entryType == DEAL_TYPE_BUY ? "BUY" : (entryType == DEAL_TYPE_SELL ? "SELL" : "N/A"));
   double entryPrice = HistoryDealGetDouble(entryDealTicket, DEAL_PRICE);
   double entrySL = HistoryDealGetDouble(entryDealTicket, DEAL_SL);
   double entryTP = HistoryDealGetDouble(entryDealTicket, DEAL_TP);

   double pipSize = (_Digits == 3 || _Digits == 5) ? (10.0 * _Point) : _Point;
   double pnlPips = (direction == "BUY")
      ? ((exitPrice - entryPrice) / pipSize)
      : ((direction == "SELL") ? ((entryPrice - exitPrice) / pipSize) : 0.0);

   int entryBarShift = iBarShift(_Symbol, SignalTF, entryTime, false);
   int exitBarShift = iBarShift(_Symbol, SignalTF, exitTime, false);
   int durationBars = 0;
   if(entryBarShift >= 0 && exitBarShift >= 0) durationBars = MathAbs(entryBarShift - exitBarShift);

   PrintFormat(
      "[TradeJournal] EntryTime=%s Dir=%s Entry=%.5f SL=%.5f TP=%.5f RegimeAtEntry=%s | ExitTime=%s Exit=%.5f PnL=%.1f pips (%.2f) DurationBars=%d",
      TimeToString(entryTime, TIME_DATE|TIME_MINUTES),
      direction,
      entryPrice,
      entrySL,
      entryTP,
      g_lastOpenRegimeAtEntry,
      TimeToString(exitTime, TIME_DATE|TIME_MINUTES),
      exitPrice,
      pnlPips,
      exitPnl,
      durationBars
   );

   LogTradeToCSV(closeDealTicket, exitPnl, pnlPips, durationBars);
}


void ManageTrailing(double atrVal) {
   if(!PositionSelect(_Symbol)) return;
   if(PositionGetInteger(POSITION_MAGIC) != Magic) return;

   long type = PositionGetInteger(POSITION_TYPE);
   double sl = PositionGetDouble(POSITION_SL);
   double tp = PositionGetDouble(POSITION_TP);
   double entry = PositionGetDouble(POSITION_PRICE_OPEN);
   datetime entryTime = (datetime)PositionGetInteger(POSITION_TIME);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point;
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   // ----- Time-based exit: after MaxBarsInTrade bars, force to BE or close -----
   int barsOpen = iBarShift(_Symbol, SignalTF, entryTime, false);
   if(MaxBarsInTrade > 0 && barsOpen > MaxBarsInTrade) {
      double beSL = (type == POSITION_TYPE_BUY) ? entry : (entry + spread);
      beSL = NormalizeDouble(beSL, digits);

      bool beSet = true;
      if(type == POSITION_TYPE_BUY) {
         if(sl == 0.0 || sl < beSL) beSet = trade.PositionModify(_Symbol, beSL, tp);
      } else if(type == POSITION_TYPE_SELL) {
         if(sl == 0.0 || sl > beSL) beSet = trade.PositionModify(_Symbol, beSL, tp);
      }

      if(!beSet) {
         trade.PositionClose(_Symbol);
      }
      return;
   }

   if(!UseTrailingStop) return;

   // If ATR is unavailable this bar, skip ATR-dependent trailing logic.
   // (Time-exit and hard-close path above still executes.)
   if(atrVal <= 0.0) return;

   // ----- Breakeven (risk-free trade) -----
   if(sl != 0.0) {
      double riskDist = 0.0;
      double favorableDist = 0.0;

      if(type == POSITION_TYPE_BUY) {
         riskDist = entry - sl;
         favorableDist = bid - entry;
      } else if(type == POSITION_TYPE_SELL) {
         riskDist = sl - entry;
         favorableDist = entry - ask;
      }

      if(riskDist > 0 && favorableDist > 0) {
         double rr = favorableDist / riskDist;
         if(rr >= BeThreshold) {
            // Move SL to entry (- spread buffer for sells to avoid premature stopouts)
            double newSL = (type == POSITION_TYPE_BUY) ? entry : entry - spread;
            newSL = NormalizeDouble(newSL, digits);
            if(newSL != sl) {
               if(DebugLogs) PrintFormat("BE triggered: liveRR=%.2f, moving SL from %.5f to %.5f", rr, sl, newSL);
               trade.PositionModify(_Symbol, newSL, tp);
               return;  // skip trailing while at be
            }
         }
      }
   }

   // ----- Standard trailing stop -----
   if(type == POSITION_TYPE_BUY) {
      double newSL = bid - ATR_Trail_Mult * atrVal;
      newSL = NormalizeDouble(newSL, digits);
      if(newSL > sl || sl == 0) trade.PositionModify(_Symbol, newSL, tp);
   } else if(type == POSITION_TYPE_SELL) {
      // For short: SL is ABOVE entry (sl > entry). As price falls, ask drops,
      // so newSL = ask - ATR*mult should be LOWER than current sl to tighten.
      // Condition: newSL < sl (tightening) OR first activation (sl == 0)
      double newSL = ask - ATR_Trail_Mult * atrVal;
      newSL = NormalizeDouble(newSL, digits);
      if((newSL < sl && sl > 0) || sl == 0) trade.PositionModify(_Symbol, newSL, tp);
   }
}

// ========================= MQL Events =========================
int OnInit() {
   hFastEMA = iMA(_Symbol, SignalTF, FastEMA, 0, MODE_EMA, PRICE_CLOSE);
   hSlowEMA = iMA(_Symbol, SignalTF, SlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   hRSI = iRSI(_Symbol, SignalTF, RSIPeriod, PRICE_CLOSE);
   hADX = iADX(_Symbol, SignalTF, ADXPeriod);
   hATR = iATR(_Symbol, SignalTF, ATRPeriod);
   hEMA50 = iMA(_Symbol, SignalTF, 50, 0, MODE_EMA, PRICE_CLOSE);
   hStdDev = iStdDev(_Symbol, SignalTF, 50, 0, MODE_SMA, PRICE_CLOSE);
   hBands = iBands(_Symbol, SignalTF, BBPeriod, 0, BBStdDev, PRICE_CLOSE);
   hSupertrend = iCustom(_Symbol, SignalTF, "Examples\\Supertrend", SupertrendPeriod, SupertrendMult);

   if(hFastEMA == INVALID_HANDLE || hSlowEMA == INVALID_HANDLE || hRSI == INVALID_HANDLE || hADX == INVALID_HANDLE || hATR == INVALID_HANDLE || hEMA50 == INVALID_HANDLE || hStdDev == INVALID_HANDLE || hBands == INVALID_HANDLE || hSupertrend == INVALID_HANDLE) {
      Print("Init failed: indicator handle invalid. err=", GetLastError());
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber(Magic);
   trade.SetDeviationInPoints(20);
   g_lastClosedTradeTime = TimeCurrent();

   if(DebugLogs) Print("Greg EA v1.23 initialized.");
   if(ShowDashboard) PrintDashboard();
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
   Comment("");
   if(hFastEMA != INVALID_HANDLE) IndicatorRelease(hFastEMA);
   if(hSlowEMA != INVALID_HANDLE) IndicatorRelease(hSlowEMA);
   if(hRSI != INVALID_HANDLE) IndicatorRelease(hRSI);
   if(hADX != INVALID_HANDLE) IndicatorRelease(hADX);
   if(hATR != INVALID_HANDLE) IndicatorRelease(hATR);
   if(hEMA50 != INVALID_HANDLE) IndicatorRelease(hEMA50);
   if(hStdDev != INVALID_HANDLE) IndicatorRelease(hStdDev);
   if(hBands != INVALID_HANDLE) IndicatorRelease(hBands);
   if(hSupertrend != INVALID_HANDLE) IndicatorRelease(hSupertrend);
}

void OnTick() {
   if(!IsNewBar(SignalTF)) return;

   if(ShowDashboard) PrintDashboard();

   bool hasOpenPosition = HasOpenPosition();
   if(!hasOpenPosition) {
      ulong closedDealTicket = 0;
      datetime closedDealTime = 0;
      if(GetLatestClosedDealSince(g_lastClosedTradeTime, closedDealTicket, closedDealTime)) {
         PrintTradeJournal(closedDealTicket);
         g_lastClosedTradeTime = closedDealTime;
      }
   }

   if(!SessionAllowed()) return;
   if(!SpreadPass()) return;
   if(!RiskGuardsPass()) return;

   double atr = 0.0;
   int dir = SignalDirection(atr);

   ManageTrailing(atr);

   string volRegime = GetVolatilityRegime(atr);
   if(UseMREntryFilter && dir != 0 && (volRegime == "LOW" || volRegime == "MID")) {
      if(volRegime == "MID") {
         double adxMid = GetSmoothedADX();
         if(adxMid <= 0.0) return;
         if(adxMid >= MidRegimeADXMax) {
            if(DebugLogs) PrintFormat("MR filter: MID regime ADX too high (%.2f >= %d)", adxMid, MidRegimeADXMax);
            return;
         }
      }

      bool stretchOk = ZScoreStretch(dir);
      bool reentryOk = BBReentrySignal(dir);
      if(!(stretchOk && reentryOk)) {
         if(DebugLogs) PrintFormat("MR filter: blocked dir=%d stretch=%d reentry=%d regime=%s", dir, (int)stretchOk, (int)reentryOk, volRegime);
         return;
      }
   }

   if(volRegime == "HIGH" && dir != 0) {
      double adxHigh = GetSmoothedADX();
      if(adxHigh <= 0.0) {
         if(DebugLogs) Print("HIGH regime: ADX copy failed");
         return;
      }
      if(adxHigh < 20.0) {
         if(DebugLogs) PrintFormat("HIGH regime filter: ADX too low (%.2f < 20)", adxHigh);
         return;
      }

      int stDir = SupertrendDirection();
      if(stDir == 0) {
         if(DebugLogs) Print("HIGH regime: Supertrend copy failed or zero");
         return;
      }
      if((dir > 0 && stDir <= 0) || (dir < 0 && stDir >= 0)) {
         if(DebugLogs) PrintFormat("HIGH regime filter: Supertrend mismatch signal=%d supertrend=%d", dir, stDir);
         return;
      }
   }

   if(OnePositionPerSymbol && hasOpenPosition) return;
   if(dir == 0) return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(ask <= 0 || bid <= 0) return;

   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double entry = (dir > 0 ? ask : bid);
   double sl = 0.0, tp = 0.0;

   if(dir > 0) {
      sl = NormalizeDouble(entry - ATR_SL_Mult * atr, digits);
      tp = NormalizeDouble(entry + ATR_TP_Mult * atr, digits);
   } else {
      sl = NormalizeDouble(entry + ATR_SL_Mult * atr, digits);
      tp = NormalizeDouble(entry - ATR_TP_Mult * atr, digits);
   }

   // Ensure SL respects broker minimum stop distance.
   double stopsLevelPts = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minStopDist = stopsLevelPts * _Point;
   if(minStopDist > 0.0) {
      if(dir > 0 && (entry - sl) < minStopDist) sl = NormalizeDouble(entry - minStopDist, digits);
      if(dir < 0 && (sl - entry) < minStopDist) sl = NormalizeDouble(entry + minStopDist, digits);
   }

   double effRisk = EffectiveRiskPercent(atr);
   g_lastEffectiveRiskPercent = effRisk;

   double lots = LotsByRisk(entry, sl, effRisk);
   if(lots <= 0) {
      if(DebugLogs) Print("Skip: computed lots <= 0");
      return;
   }

   bool ok = false;
   if(dir > 0) ok = trade.Buy(lots, _Symbol, 0.0, sl, tp, "greg_regime_risk_v1");
   else ok = trade.Sell(lots, _Symbol, 0.0, sl, tp, "greg_regime_risk_v1");

   if(ok) {
      g_lastOpenRegimeAtEntry = volRegime;
   }

   if(DebugLogs) {
      PrintFormat("Order dir=%d lots=%.2f entry=%.5f sl=%.5f tp=%.5f risk%%=%.2f ok=%d ret=%d", dir, lots, entry, sl, tp, effRisk, (int)ok, trade.ResultRetcode());
   }
}

// Writes a closed trade to CSV in MQL5/Files/.
// Format: CloseTime,Symbol,Direction,Profit,RegimeAtEntry,ATR_at_entry,Pips,DurationBars
void LogTradeToCSV(ulong closeDealTicket, double exitPnl, double pnlPips, int durationBars) {
   if(closeDealTicket == 0) return;
   if(!HistorySelect(0, TimeCurrent())) return;

   long positionId = HistoryDealGetInteger(closeDealTicket, DEAL_POSITION_ID);
   datetime exitTime = (datetime)HistoryDealGetInteger(closeDealTicket, DEAL_TIME);

   // Find entry deal
   ulong entryTicket = 0;
   datetime entryTime = 0;
   for(int i = 0; i < HistoryDealsTotal(); i++) {
      ulong t = HistoryDealGetTicket(i);
      if(t == 0) continue;
      if(HistoryDealGetString(t, DEAL_SYMBOL) != _Symbol) continue;
      if(HistoryDealGetInteger(t, DEAL_MAGIC) != Magic) continue;
      if(HistoryDealGetInteger(t, DEAL_POSITION_ID) != positionId) continue;
      if(HistoryDealGetInteger(t, DEAL_ENTRY) != DEAL_ENTRY_IN) continue;
      datetime tIn = (datetime)HistoryDealGetInteger(t, DEAL_TIME);
      if(entryTicket == 0 || tIn < entryTime) {
         entryTicket = t;
         entryTime = tIn;
      }
   }
   if(entryTicket == 0) return;

   long entryType = HistoryDealGetInteger(entryTicket, DEAL_TYPE);
   string direction = (entryType == DEAL_TYPE_BUY ? "BUY" : (entryType == DEAL_TYPE_SELL ? "SELL" : "N/A"));

   string header = "CloseTime,Symbol,Direction,Profit,Regime,ATR,ATR_smooth,Pips,DurationBars";
   string row = StringFormat("%s,%s,%s,%.2f,%s,%.5f,%.5f,%.1f,%d",
      TimeToString(exitTime, TIME_DATE|TIME_MINUTES),
      _Symbol,
      direction,
      exitPnl,
      g_lastOpenRegimeAtEntry,
      0.0,          // ATR-at-entry placeholder (0 — callers may override)
      g_smoothedATR,
      pnlPips,
      durationBars
   );

   int fh = FileOpen(TradeLogPath, FILE_CSV|FILE_WRITE|FILE_SHARE_READ|FILE_SHARE_WRITE, ',', CP_ACP);
   if(fh == INVALID_HANDLE) {
      if(DebugLogs) PrintFormat("CSVLog: FileOpen failed for %s err=%d", TradeLogPath, GetLastError());
      return;
   }

   // Append: seek to end
   FileSeek(fh, 0, SEEK_END);
   long fsize = FileTell(fh);
   if(fsize == 0) FileWriteString(fh, header + "\r\n");
   FileWriteString(fh, row + "\r\n");
   FileClose(fh);

   if(DebugLogs) PrintFormat("CSVLog: wrote row -> %s", row);
}

void PrintDashboard() {
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double dailyPnl = ClosedPnlSince(DayStart(TimeCurrent()));

   string posStr = "None";
   double posProfit = 0;
   if(PositionSelect(_Symbol) && PositionGetInteger(POSITION_MAGIC) == Magic) {
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double curPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
      double vol = PositionGetDouble(POSITION_VOLUME);
      long type = PositionGetInteger(POSITION_TYPE);
      posProfit = PositionGetDouble(POSITION_PROFIT);
      string dir = type == POSITION_TYPE_BUY ? "Long" : "Short";
      posStr = StringFormat("%s %.2f lots @ %.5f | P&L: %.2f", dir, vol, openPrice, posProfit);
   }

   string regimeStr = "N/A";
   double atrVal = 0;
   int dir = SignalDirection(atrVal);
   if(dir > 0) regimeStr = "BUY";
   else if(dir < 0) regimeStr = "SELL";
   else regimeStr = "NONE";

   // ATR-based volatility regime
   string volRegime = GetVolatilityRegime(atrVal);

   // Fetch smoothed values for dashboard (evaluated on closed bar)
   double smADX = GetSmoothedADX();
   double smATR = g_smoothedATR;  // already computed by GetVolatilityRegime this bar
   string smADXStr = (smADX > 0) ? StringFormat("%.1f", smADX) : "N/A";
   string smATRStr = (smATR > 0) ? StringFormat("%.5f", smATR) : "N/A";

   string txt = StringFormat(
      "Greg EA v1.23 | %s\n" +
      "--------------------------------------------\n" +
      "Equity:     %.2f\n" +
      "Balance:    %.2f\n" +
      "Daily P&L:  %.2f (%.2f%%)\n" +
      "--------------------------------------------\n" +
      "Dir:        %s\n" +
      "ATR sm:     %s\n" +
      "ADX sm:     %s\n" +
      "Vol Regime: %s\n" +
      "--------------------------------------------\n" +
      "Risk:       %.1f%% (eff %.2f%%)\n" +
      "SL mult:    %.1f   TP mult: %.1f\n" +
      "--------------------------------------------\n" +
      "Consec Losses: %d\n" +
      "Max Daily Loss: %.1f%%\n" +
      "Max Consec:     %d\n" +
      "--------------------------------------------\n" +
      "Position: %s",
      _Symbol,
      eq, bal, dailyPnl, (bal > 0 ? dailyPnl/bal*100 : 0),
      regimeStr,
      smATRStr,
      smADXStr,
      volRegime,
      RiskPercent, g_lastEffectiveRiskPercent,
      ATR_SL_Mult, ATR_TP_Mult,
      g_consecutiveLosses,
      MaxDailyLossPercent,
      MaxConsecutiveLosses,
      posStr
   );

   Comment(txt);
}
