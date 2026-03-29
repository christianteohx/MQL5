//+------------------------------------------------------------------+
//|                                          greg_regime_risk_v2.mq5 |
//|                                                          Greg EA |
//|                           Volatility-Regime Adaptive Risk v2     |
//+------------------------------------------------------------------+
#property copyright "Greg EA"
#property version   "2.00"
#property description "Greg EA v2 - Trend + Pullback + ATR Risk + Volatility-Regime Adaptive SL/TP"
#property strict

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
input double RSI_Buy_Min = 50.0;
input double RSI_Sell_Max = 50.0;

input group "=== Risk / Trade Management ===";
input double RiskPercent = 0.5;          // % of equity per trade
input int ATRPeriod = 14;
input bool UseTrailingStop = true;
input double ATR_Trail_Mult = 1.2;
input double MaxLotsCap = 1.0;           // hard cap safety
input bool OnePositionPerSymbol = true;

input group "=== ATR-based Volatility Regime ===";
input bool UseVolatilityRegime = true;  // Enable regime-adaptive SL/TP multipliers
input int VolRegimeLookback = 100;       // Bars for ATR percentile lookback
input double VolLowThreshold = 0.33;    // Percentile below = LOW vol regime
input double VolHighThreshold = 0.66;   // Percentile above = HIGH vol regime
input double ATR_SL_Mult_LOW = 1.5;     // SL multiplier when vol is LOW
input double ATR_TP_Mult_LOW = 2.5;     // TP multiplier when vol is LOW
input double ATR_SL_Mult_MID = 2.0;     // SL multiplier when vol is MID (default)
input double ATR_TP_Mult_MID = 3.0;     // TP multiplier when vol is MID (default)
input double ATR_SL_Mult_HIGH = 2.5;    // SL multiplier when vol is HIGH
input double ATR_TP_Mult_HIGH = 4.0;    // TP multiplier when vol is HIGH

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

// ========================= Indicator handles =========================
int hFastEMA = INVALID_HANDLE;
int hSlowEMA = INVALID_HANDLE;
int hRSI = INVALID_HANDLE;
int hADX = INVALID_HANDLE;
int hATR = INVALID_HANDLE;

// ========================= State =========================
datetime g_lastBarTime = 0;
int g_consecutiveLosses = 0;

// Current volatility regime state (0=LOW, 1=MID, 2=HIGH)
int g_currentRegime = 1;
double g_currentAtrPct = 0.5;

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

double LotsByRisk(double entryPrice, double slPrice) {
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskMoney = eq * (RiskPercent / 100.0);

   double dist = MathAbs(entryPrice - slPrice);
   if(dist <= 0) return 0;

   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickValue <= 0 || tickSize <= 0) return 0;

   double moneyPerLotAtSL = (dist / tickSize) * tickValue;
   if(moneyPerLotAtSL <= 0) return 0;

   double rawLots = riskMoney / moneyPerLotAtSL;
   return ClampVolume(rawLots);
}

// ========================= Volatility Regime Detection =========================
// Classifies the current bar as LOW(0), MID(1), or HIGH(2) volatility based on
// ATR percentile over VolRegimeLookback bars.
// LOW  = ATR percentile < VolLowThreshold  (below 33rd percentile by default)
// HIGH = ATR percentile > VolHighThreshold  (above 66th percentile by default)
// MID  = everything in between

void UpdateVolatilityRegime(double currentAtr) {
   if(!UseVolatilityRegime) {
      g_currentRegime = 1;  // default to MID when disabled
      g_currentAtrPct = 0.5;
      return;
   }

   // Copy ATR history for percentile ranking
   double atrArr[];
   ArrayResize(atrArr, VolRegimeLookback);
   ArraySetAsSeries(atrArr, true);
   int copied = CopyBuffer(hATR, 0, 0, VolRegimeLookback, atrArr);
   if(copied < VolRegimeLookback) {
      if(DebugLogs) Print("UpdateVolatilityRegime: only copied ", copied, " bars");
      g_currentRegime = 1;
      g_currentAtrPct = 0.5;
      return;
   }

   // Use the previous closed bar's ATR as the "current" for regime classification
   double atrNow = atrArr[1];  // most recent completed bar

   // Build a sorted copy for percentile ranking
   double sorted[];
   ArrayResize(sorted, VolRegimeLookback);
   for(int i=0;i<VolRegimeLookback;i++) sorted[i] = atrArr[i];

   // Bubble sort (same approach as Phase1, reliable for this size)
   for(int i=0;i<VolRegimeLookback-1;i++) {
      for(int j=i+1;j<VolRegimeLookback;j++) {
         if(sorted[j] < sorted[i]) {
            double tmp = sorted[i];
            sorted[i] = sorted[j];
            sorted[j] = tmp;
         }
      }
   }

   // Compute percentile rank of atrNow within the sorted window
   double atrPct = 0.5;
   if(atrNow <= sorted[0]) {
      atrPct = 0.0;
   } else if(atrNow >= sorted[VolRegimeLookback-1]) {
      atrPct = 1.0;
   } else {
      // Linear interpolation between sorted elements
      int idx = 0;
      for(int i=0;i<VolRegimeLookback;i++) {
         if(sorted[i] > atrNow) { idx = i; break; }
      }
      double lower = sorted[idx-1];
      double upper = sorted[idx];
      if(upper != lower) {
         double t = (atrNow - lower) / (upper - lower);
         atrPct = ((double)(idx-1) + t) / (double)(VolRegimeLookback-1);
      }
   }

   // Determine regime
   int newRegime = 1;
   if(atrPct < VolLowThreshold) newRegime = 0;       // LOW
   else if(atrPct > VolHighThreshold) newRegime = 2; // HIGH
   else newRegime = 1;                                // MID

   // Log regime changes
   if(newRegime != g_currentRegime) {
      string regimeNames[3] = {"LOW", "MID", "HIGH"};
      if(DebugLogs) PrintFormat("VolRegime change: %s -> %s (ATR_pct=%.3f, ATR=%.5f)",
         regimeNames[g_currentRegime], regimeNames[newRegime], atrPct, atrNow);
      g_currentRegime = newRegime;
   }

   g_currentAtrPct = atrPct;
}

// Returns the regime as a readable string
string VolRegimeToString() {
   string names[3] = {"LOW ", "MID ", "HIGH"};
   return names[g_currentRegime];
}

// Returns the effective SL multiplier for the current regime
double GetRegimeSLMult() {
   if(!UseVolatilityRegime) return ATR_SL_Mult_MID;
   if(g_currentRegime == 0) return ATR_SL_Mult_LOW;
   if(g_currentRegime == 2) return ATR_SL_Mult_HIGH;
   return ATR_SL_Mult_MID;
}

// Returns the effective TP multiplier for the current regime
double GetRegimeTPMult() {
   if(!UseVolatilityRegime) return ATR_TP_Mult_MID;
   if(g_currentRegime == 0) return ATR_TP_Mult_LOW;
   if(g_currentRegime == 2) return ATR_TP_Mult_HIGH;
   return ATR_TP_Mult_MID;
}

// ========================= Signal & ATR =========================
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

void ManageTrailing(double atrVal) {
   if(!UseTrailingStop) return;
   if(!PositionSelect(_Symbol)) return;
   if(PositionGetInteger(POSITION_MAGIC) != Magic) return;

   long type = PositionGetInteger(POSITION_TYPE);
   double sl = PositionGetDouble(POSITION_SL);
   double tp = PositionGetDouble(POSITION_TP);
   double entry = PositionGetDouble(POSITION_PRICE_OPEN);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point;
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   // ----- Breakeven (risk-free trade) -----
   if(sl != 0.0) {
      double riskDist = 0.0;
      double rewardDist = 0.0;

      if(type == POSITION_TYPE_BUY) {
         riskDist = entry - sl;
         rewardDist = tp - entry;
      } else if(type == POSITION_TYPE_SELL) {
         riskDist = sl - entry;
         rewardDist = entry - tp;
      }

      if(riskDist > 0 && rewardDist > 0) {
         double rr = rewardDist / riskDist;
         if(rr >= BeThreshold) {
            double newSL = (type == POSITION_TYPE_BUY) ? entry : entry + spread;
            newSL = NormalizeDouble(newSL, digits);
            if(newSL != sl) {
               if(DebugLogs) PrintFormat("BE triggered: rr=%.2f, moving SL from %.5f to %.5f", rr, sl, newSL);
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

   if(hFastEMA == INVALID_HANDLE || hSlowEMA == INVALID_HANDLE ||
      hRSI == INVALID_HANDLE || hATR == INVALID_HANDLE ||
      (UseADXFilter && hADX == INVALID_HANDLE)) {
      Print("Init failed: indicator handle invalid. err=", GetLastError());
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber(Magic);
   trade.SetDeviationInPoints(20);

   // Initialize volatility regime on startup
   double dummyAtr = 0;
   SignalDirection(dummyAtr);  // prime the ATR buffer
   UpdateVolatilityRegime(dummyAtr);

   if(DebugLogs) Print("Greg EA v2 initialized. VolRegime=", VolRegimeToString());
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
}

void OnTick() {
   if(!IsNewBar(SignalTF)) return;

   // Update volatility regime on each new bar
   double atr = 0;
   SignalDirection(atr);  // also populates atr
   UpdateVolatilityRegime(atr);

   if(ShowDashboard) PrintDashboard();

   if(!SessionAllowed()) return;
   if(!SpreadPass()) return;
   if(!RiskGuardsPass()) return;

   int dir = SignalDirection(atr);

   ManageTrailing(atr);

   if(OnePositionPerSymbol && HasOpenPosition()) return;
   if(dir == 0) return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(ask <= 0 || bid <= 0) return;

   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double entry = (dir > 0 ? ask : bid);

   // Regime-adaptive SL/TP multipliers
   double slMult = GetRegimeSLMult();
   double tpMult = GetRegimeTPMult();

   double sl = 0.0, tp = 0.0;
   if(dir > 0) {
      sl = NormalizeDouble(entry - slMult * atr, digits);
      tp = NormalizeDouble(entry + tpMult * atr, digits);
   } else {
      sl = NormalizeDouble(entry + slMult * atr, digits);
      tp = NormalizeDouble(entry - tpMult * atr, digits);
   }

   double lots = LotsByRisk(entry, sl);
   if(lots <= 0) {
      if(DebugLogs) Print("Skip: computed lots <= 0");
      return;
   }

   bool ok = false;
   if(dir > 0) ok = trade.Buy(lots, _Symbol, 0.0, sl, tp, "greg_regime_risk_v2");
   else ok = trade.Sell(lots, _Symbol, 0.0, sl, tp, "greg_regime_risk_v2");

   if(DebugLogs) {
      PrintFormat("Order dir=%d lots=%.2f entry=%.5f sl=%.5f tp=%.5f regime=%s slMult=%.1f tpMult=%.1f ok=%d ret=%d",
         dir, lots, entry, sl, tp, VolRegimeToString(), slMult, tpMult,
         (int)ok, trade.ResultRetcode());
   }
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
      posProfit = PositionGetDouble(PROFIT);
      string dir = type == POSITION_TYPE_BUY ? "Long" : "Short";
      posStr = StringFormat("%s %.2f lots @ %.5f | P&L: %.2f", dir, vol, openPrice, posProfit);
   }

   // Prime ATR for regime update (safe to call even without a signal)
   double atrVal = 0;
   int dashDir = SignalDirection(atrVal);  // populate atrVal and get direction
   UpdateVolatilityRegime(atrVal);  // recompute regime using current bar's ATR

   string regimeStr = "N/A";
   if(PositionSelect(_Symbol) && PositionGetInteger(POSITION_MAGIC) == Magic) {
      long type = PositionGetInteger(POSITION_TYPE);
      regimeStr = (type == POSITION_TYPE_BUY) ? "BUY " : "SELL ";
   } else if(atrVal > 0) {
      if(dashDir > 0) regimeStr = "BUY ";
      else if(dashDir < 0) regimeStr = "SELL ";
      else regimeStr = "NONE";
   }

   string volRegimeStr = VolRegimeToString();
   string volRegimeNote = "";
   if(UseVolatilityRegime) {
      volRegimeNote = StringFormat(" (%.0f%%tile)", g_currentAtrPct * 100);
   } else {
      volRegimeStr = "OFF ";
      volRegimeNote = "";
   }

   // Show effective multipliers based on current regime
   double slMult = GetRegimeSLMult();
   double tpMult = GetRegimeTPMult();

   string txt = StringFormat(
      "Greg EA v2.0 | %s\n" +
      "----------------------------------------\n" +
      "Equity:   %.2f\n" +
      "Balance:  %.2f\n" +
      "Daily P&L: %.2f (%.2f%%)\n" +
      "----------------------------------------\n" +
      "Signal:   %s\n" +
      "ATR(%d):  %.5f\n" +
      "Vol Regime: %s%s\n" +
      "SL Mult:  %.1f  TP Mult:  %.1f\n" +
      "Risk:     %.1f%%\n" +
      "----------------------------------------\n" +
      "Consecutive Losses: %d\n" +
      "Max Daily Loss: %.1f%%\n" +
      "Max Consec Loss: %d\n" +
      "----------------------------------------\n" +
      "Position: %s",
      _Symbol,
      eq, bal, dailyPnl, (bal > 0 ? dailyPnl/bal*100 : 0),
      regimeStr,
      ATRPeriod, atrVal,
      volRegimeStr, volRegimeNote,
      slMult, tpMult,
      RiskPercent,
      g_consecutiveLosses,
      MaxDailyLossPercent,
      MaxConsecutiveLosses,
      posStr
   );

   Comment(txt);
}
