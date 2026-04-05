#property strict
#property version   "1.21"
#property description "Greg EA v1.21 - Trend + Pullback + ATR Risk + Vol-Scaled Sizing + Live Dashboard + BE"

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
double g_lastEffectiveRiskPercent = 0.0;

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

double EffectiveRiskPercent(double atrVal) {
   double eff = RiskPercent;
   if(!UseVolatilityRiskScaling) return eff;

   string vr = GetVolatilityRegime(atrVal);
   if(vr == "LOW ") eff *= LowVolRiskMult;
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

string GetVolatilityRegime(double currentATR) {
   // Compute ATR percentile vs 100-bar lookback: LOW < 33rd, HIGH > 66th, else MID
   double atrArr[];
   ArrayResize(atrArr, 100);
   ArraySetAsSeries(atrArr, true);
   if(CopyBuffer(hATR, 0, 0, 100, atrArr) < 100) return "N/A";

   // Bubble sort to get percentiles (simple and reliable)
   for(int i = 0; i < 99; i++) {
      for(int j = i + 1; j < 100; j++) {
         if(atrArr[j] < atrArr[i]) {
            double tmp = atrArr[i];
            atrArr[i] = atrArr[j];
            atrArr[j] = tmp;
         }
      }
   }

   double p33 = atrArr[32];  // 33rd percentile (0-indexed)
   double p66 = atrArr[65];  // 66th percentile

   if(currentATR < p33) return "LOW ";
   if(currentATR > p66) return "HIGH";
   return "MID ";
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
            // Move SL to entry (+ spread buffer for sells)
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

   if(hFastEMA == INVALID_HANDLE || hSlowEMA == INVALID_HANDLE || hRSI == INVALID_HANDLE || hATR == INVALID_HANDLE || (UseADXFilter && hADX == INVALID_HANDLE)) {
      Print("Init failed: indicator handle invalid. err=", GetLastError());
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber(Magic);
   trade.SetDeviationInPoints(20);

   if(DebugLogs) Print("Greg EA v1.2 initialized.");
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

   if(ShowDashboard) PrintDashboard();

   if(!SessionAllowed()) return;
   if(!SpreadPass()) return;
   if(!RiskGuardsPass()) return;

   double atr = 0.0;
   int dir = SignalDirection(atr);

   ManageTrailing(atr);

   if(OnePositionPerSymbol && HasOpenPosition()) return;
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

   if(DebugLogs) {
      PrintFormat("Order dir=%d lots=%.2f entry=%.5f sl=%.5f tp=%.5f risk%%=%.2f ok=%d ret=%d", dir, lots, entry, sl, tp, effRisk, (int)ok, trade.ResultRetcode());
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

   string regimeStr = "N/A";
   double atrVal = 0;
   int dir = SignalDirection(atrVal);
   if(dir > 0) regimeStr = "BUY ";
   else if(dir < 0) regimeStr = "SELL ";
   else regimeStr = "NONE";

   // ATR-based volatility regime awareness (raw ATR — compare to recent range for context)
   string volRegime = GetVolatilityRegime(atrVal);

   string txt = StringFormat(
      "Greg EA v1.2 | %s\n" +
      "----------------------------\n" +
      "Equity:   %.2f\n" +
      "Balance:  %.2f\n" +
      "Daily P&L: %.2f (%.2f%%)\n" +
      "----------------------------\n" +
      "Signal:   %s\n" +
      "ATR(%d):  %.5f\n" +
      "Vol:      %s\n" +
      "Risk:     %.1f%% (eff %.2f%%) | SL:%.1f TP:%.1f\n" +
      "----------------------------\n" +
      "Consecutive Losses: %d\n" +
      "Max Daily Loss: %.1f%%\n" +
      "Max Consec Loss: %d\n" +
      "----------------------------\n" +
      "Position: %s",
      _Symbol,
      eq, bal, dailyPnl, (bal > 0 ? dailyPnl/bal*100 : 0),
      regimeStr,
      ATRPeriod, atrVal,
      volRegime,
      RiskPercent, g_lastEffectiveRiskPercent, ATR_SL_Mult, ATR_TP_Mult,
      g_consecutiveLosses,
      MaxDailyLossPercent,
      MaxConsecutiveLosses,
      posStr
   );

   Comment(txt);
}
