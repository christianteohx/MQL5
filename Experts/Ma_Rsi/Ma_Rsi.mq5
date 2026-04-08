//+------------------------------------------------------------------+
//|                                                    Ma_Rsi_v3.mq5 |
//|                                   Binary 3-Indicator Architecture |
//|                                    fastEMA > slowEMA + RSI < 30  |
//+------------------------------------------------------------------+

#include <Trade/Trade.mqh>
#include <Trade/SymbolInfo.mqh>
#include <Trade/AccountInfo.mqh>

//+------------------------------------------------------------------+
//| Input variables                                                  |
//+------------------------------------------------------------------+

sinput string strategy_string;                //-----------------Strategy-----------------
input int      fast_ema_period   = 9;         // Fast EMA period
input int      slow_ema_period   = 21;        // Slow EMA period
input int      rsi_period       = 14;        // RSI period
input int      atr_period       = 14;         // ATR period for SL/TP
input double   atr_sl_mult      = 1.5;        // ATR SL multiplier
input double   atr_tp_mult      = 3.0;        // ATR TP multiplier
input double   risk_percent     = 1.0;        // Risk % of equity per trade

sinput string s_guardrails;                              //-----------------Guardrails-----------------
input double MaxDailyLossPercent = 2.0;                 // Max daily loss as % of equity
input int    MaxConsecutiveLosses = 4;                  // Max consecutive losses before pausing
input double MaxSpreadPoints = 50.0;                    // Max spread in points to allow trades
input bool   UseSessionFilter = true;                  // Enable session time filter
input int     SessionStartHour = 7;                     // Session start hour (broker time)
input int     SessionEndHour = 16;                     // Session end hour (broker time)
input bool   DebugRiskGuards = false;                   // Print guard trigger messages

//+------------------------------------------------------------------+
//| Indicator handles                                                |
//+------------------------------------------------------------------+

int g_emaFastHandle = INVALID_HANDLE;
int g_emaSlowHandle = INVALID_HANDLE;
int g_rsiHandle    = INVALID_HANDLE;
int g_atrHandle     = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Global variables                                                 |
//+------------------------------------------------------------------+

ulong   g_magicNumber  = 50357114;
double  g_contractSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
int     g_decimal      = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
double  g_tickSize     = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

CTrade  g_trade;
CSymbolInfo g_symbol;

MqlRates g_candle[];
MqlTick  g_tick;

int     g_consecutiveLosses = 0;
datetime g_lastResetTime    = 0;

//+------------------------------------------------------------------+
//| Guard Helper Functions                                           |
//+------------------------------------------------------------------+

datetime DayStart(datetime t) {
   MqlDateTime dt;
   TimeToStruct(t, dt);
   dt.hour = 0;
   dt.min  = 0;
   dt.sec  = 0;
   return StructToTime(dt);
}

double ClosedPnlSince(datetime fromTime) {
   if(!HistorySelect(fromTime, TimeCurrent())) return 0.0;
   double pnl = 0.0;
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++) {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol) continue;
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != g_magicNumber) continue;
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
   for(int i = total - 1; i >= 0; i--) {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) break;
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol) continue;
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != g_magicNumber) continue;
      long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT) continue;
      double p = HistoryDealGetDouble(ticket, DEAL_PROFIT)
               + HistoryDealGetDouble(ticket, DEAL_SWAP)
               + HistoryDealGetDouble(ticket, DEAL_COMMISSION);
      if(p < 0) g_consecutiveLosses++;
      else break;
   }
}

bool SessionPass() {
   if(!UseSessionFilter) return true;
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(dt.hour < SessionStartHour || dt.hour >= SessionEndHour) return false;
   return true;
}

bool SpreadPass() {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(ask <= 0 || bid <= 0) return false;
   double spreadPts = (ask - bid) / _Point;
   return spreadPts <= MaxSpreadPoints;
}

bool RiskGuardsPass() {
   RefreshConsecutiveLosses();

   if(MaxConsecutiveLosses > 0 && g_consecutiveLosses >= MaxConsecutiveLosses) {
      if(DebugRiskGuards) Print("Risk guard: max consecutive losses hit: ", g_consecutiveLosses);
      return false;
   }

   datetime todayStart = DayStart(TimeCurrent());
   double pnlToday = ClosedPnlSince(todayStart);
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   double lossLimit = -(eq * (MaxDailyLossPercent / 100.0));
   if(MaxDailyLossPercent > 0 && pnlToday <= lossLimit) {
      if(DebugRiskGuards) PrintFormat("Risk guard: daily loss hit. pnlToday=%.2f limit=%.2f", pnlToday, lossLimit);
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| ATR volatility filter — pass if ATR > 33rd percentile             |
//+------------------------------------------------------------------+

bool volOk() {
   double atrArr[];
   if(CopyBuffer(g_atrHandle, 0, 0, 100, atrArr) < 100) return true; // default pass
   double sorted[];
   ArrayResize(sorted, 100);
   ArrayCopy(sorted, atrArr);
   ArraySort(sorted);
   double p33 = sorted[33];
   return (atrArr[0] > p33); // ATR above 33rd percentile = pass
}

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+

int OnInit() {
   if(MQLInfoInteger(MQL_TESTER)) {
      // debug prints enabled in backtest
   }

   g_symbol.Name(_Symbol);
   g_contractSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
   g_decimal      = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   g_tickSize     = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

   // Validate periods
   if(fast_ema_period < 1 || slow_ema_period < 1 || rsi_period < 1 || atr_period < 1) {
      Alert("Invalid period parameters");
      return INIT_FAILED;
   }
   if(fast_ema_period >= slow_ema_period) {
      Alert("fast_ema_period must be less than slow_ema_period");
      return INIT_FAILED;
   }

   // Create indicator handles
   g_emaFastHandle = iMA(_Symbol, Period(), fast_ema_period, 0, MODE_EMA, PRICE_CLOSE);
   g_emaSlowHandle = iMA(_Symbol, Period(), slow_ema_period, 0, MODE_EMA, PRICE_CLOSE);
   g_rsiHandle     = iRSI(_Symbol, Period(), rsi_period, PRICE_CLOSE);
   g_atrHandle     = iATR(_Symbol, Period(), atr_period);

   if(g_emaFastHandle == INVALID_HANDLE || g_emaSlowHandle == INVALID_HANDLE ||
      g_rsiHandle == INVALID_HANDLE || g_atrHandle == INVALID_HANDLE) {
      Alert("Error creating indicator handles: ", GetLastError());
      return INIT_FAILED;
   }

   // CTrade setup
   g_trade.SetExpertMagicNumber(g_magicNumber);
   g_trade.SetDeviationInPoints(10);
   g_trade.SetTypeFilling(ORDER_FILLING_FOK);

   ArraySetAsSeries(g_candle, true);

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+

void OnDeinit(const int reason) {
   if(g_emaFastHandle != INVALID_HANDLE) IndicatorRelease(g_emaFastHandle);
   if(g_emaSlowHandle != INVALID_HANDLE) IndicatorRelease(g_emaSlowHandle);
   if(g_rsiHandle != INVALID_HANDLE)     IndicatorRelease(g_rsiHandle);
   if(g_atrHandle != INVALID_HANDLE)      IndicatorRelease(g_atrHandle);
}

//+------------------------------------------------------------------+
//| Position helpers                                                  |
//+------------------------------------------------------------------+

bool HasBuyPosition() {
   for(int i = 0; i < PositionsTotal(); i++) {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket)) {
         if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY && PositionGetString(POSITION_SYMBOL) == _Symbol) {
            return true;
         }
      }
   }
   return false;
}

bool HasSellPosition() {
   for(int i = 0; i < PositionsTotal(); i++) {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket)) {
         if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL && PositionGetString(POSITION_SYMBOL) == _Symbol) {
            return true;
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+

void OnTick() {
   // Copy closed bar [1] data — anti-repaint
   if(CopyRates(_Symbol, Period(), 0, 4, g_candle) < 4) {
      Print("Failed to copy rates: ", GetLastError());
      return;
   }
   ArraySetAsSeries(g_candle, true);

   double fastEMAArr[], slowEMAArr[], rsiArr[], atrArr[];
   ArraySetAsSeries(fastEMAArr, true);
   ArraySetAsSeries(slowEMAArr, true);
   ArraySetAsSeries(rsiArr, true);
   ArraySetAsSeries(atrArr, true);

   if(CopyBuffer(g_emaFastHandle, 0, 0, 2, fastEMAArr) < 2 ||
      CopyBuffer(g_emaSlowHandle, 0, 0, 2, slowEMAArr) < 2 ||
      CopyBuffer(g_rsiHandle, 0, 0, 2, rsiArr) < 2 ||
      CopyBuffer(g_atrHandle, 0, 0, 2, atrArr) < 2) {
      Print("Failed to copy indicator buffers: ", GetLastError());
      return;
   }

   double fastEMA = fastEMAArr[1]; // closed bar [1]
   double slowEMA = slowEMAArr[1];
   double rsiVal  = rsiArr[1];
   double atrVal  = atrArr[1];

   // Binary signals
   bool isLong  = (fastEMA > slowEMA) && (rsiVal < 30) && volOk();
   bool isShort = (fastEMA < slowEMA) && (rsiVal > 70) && volOk();

   // Skip if no signal
   if(!isLong && !isShort) return;

   // Risk guards
   if(!RiskGuardsPass()) return;
   if(!SessionPass())    return;
   if(!SpreadPass())     return;

   // Check existing positions
   bool hasBuy  = HasBuyPosition();
   bool hasSell = HasSellPosition();

   if(isLong && !hasBuy) {
      if(hasSell) closeAllTrade();
      BuyAtMarket(atrVal);
   }
   else if(isShort && !hasSell) {
      if(hasBuy) closeAllTrade();
      SellAtMarket(atrVal);
   }
}

//+------------------------------------------------------------------+
//| New bar detection                                                |
//+------------------------------------------------------------------+

bool isNewBar() {
   static datetime last_time = 0;
   datetime lastbar_time = (datetime)SeriesInfoInteger(Symbol(), Period(), SERIES_LASTBAR_DATE);
   if(last_time == 0) { last_time = lastbar_time; return false; }
   if(last_time != lastbar_time) { last_time = lastbar_time; return true; }
   return false;
}

//+------------------------------------------------------------------+
//| Order execution                                                  |
//+------------------------------------------------------------------+

double RoundToTick(double price) {
   return MathRound(price / g_tickSize) * g_tickSize;
}

double getVolume() {
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double price      = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double marginPerLot = 0.0;

   if(!OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, 1.0, price, marginPerLot) || marginPerLot <= 0.0) {
      Print("getVolume: OrderCalcMargin failed: ", GetLastError());
      return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   }

   double riskMargin = freeMargin * (risk_percent / 100.0);
   double rawLots    = riskMargin / marginPerLot;

   double stepVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minVol  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxVol  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   double floored = stepVol * MathFloor(rawLots / stepVol);
   double clamped = MathMax(minVol, MathMin(maxVol, floored));

   int precision = 0;
   if(stepVol < 1.0) precision = (int)MathRound(-MathLog10(stepVol));

   return NormalizeDouble(clamped, precision);
}

void BuyAtMarket(double atrVal) {
   if(!SymbolInfoTick(_Symbol, g_tick)) {
      Print("BuyAtMarket: SymbolInfoTick failed: ", GetLastError());
      return;
   }

   double sl = NormalizeDouble(RoundToTick(g_tick.bid - atrVal * atr_sl_mult), g_decimal);
   double tp = NormalizeDouble(RoundToTick(g_tick.ask + atrVal * atr_tp_mult), g_decimal);
   double vol = getVolume();

   if(!g_trade.PositionOpen(_Symbol, ORDER_TYPE_BUY, vol, g_tick.ask, sl, tp)) {
      Print("Buy failed. Retcode=", g_trade.ResultRetcode(), " desc: ", g_trade.ResultRetcodeDescription());
   } else {
      Print("BUY ", _Symbol, " vol=", vol, " ask=", g_tick.ask, " SL=", sl, " TP=", tp);
   }
}

void SellAtMarket(double atrVal) {
   if(!SymbolInfoTick(_Symbol, g_tick)) {
      Print("SellAtMarket: SymbolInfoTick failed: ", GetLastError());
      return;
   }

   double sl = NormalizeDouble(RoundToTick(g_tick.ask + atrVal * atr_sl_mult), g_decimal);
   double tp = NormalizeDouble(RoundToTick(g_tick.bid - atrVal * atr_tp_mult), g_decimal);
   double vol = getVolume();

   if(!g_trade.PositionOpen(_Symbol, ORDER_TYPE_SELL, vol, g_tick.bid, sl, tp)) {
      Print("SELL failed. Retcode=", g_trade.ResultRetcode(), " desc: ", g_trade.ResultRetcodeDescription());
   } else {
      Print("SELL ", _Symbol, " vol=", vol, " bid=", g_tick.bid, " SL=", sl, " TP=", tp);
   }
}

void closeAllTrade() {
   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(!g_trade.PositionClose(ticket)) {
         Print("closeAllTrade: PositionClose failed. Retcode=", g_trade.ResultRetcode());
      }
   }
}
