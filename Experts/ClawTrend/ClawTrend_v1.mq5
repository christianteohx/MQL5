//+------------------------------------------------------------------+
//|                                    ClawTrend_v1.mq5              |
//|                                          Trend-Following EA      |
//+------------------------------------------------------------------+
#property copyright "Claw"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 2

//--- buffers
double RegimeBuffer[];
double SignalBuffer[];

#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| INPUTS (7 total)                                                 |
//+------------------------------------------------------------------+
input int      fast_ema      = 9;       // Fast EMA period
input int      slow_ema      = 21;      // Slow EMA period
input int      rsi_period   = 14;      // RSI period
input int      atr_period   = 14;      // ATR period
input double   atr_sl_mult  = 1.5;     // ATR SL multiplier
input double   atr_tp_mult  = 3.0;     // ATR TP multiplier
input double   risk_percent = 1.0;      // Risk % of equity per trade

//+------------------------------------------------------------------+
//| GLOBAL                                                            |
//+------------------------------------------------------------------+
CTrade trade;
int g_rsiHandle = INVALID_HANDLE;
int g_emaFastHandle = INVALID_HANDLE;
int g_emaSlowHandle = INVALID_HANDLE;
int g_atrHandle = INVALID_HANDLE;
datetime gLastBarTime = 0;
datetime gLastTradeTime = 0;

//+------------------------------------------------------------------+
//| GetRegime — ATR percentile over 100 bars                          |
//+------------------------------------------------------------------+
string GetRegime()
{
   double atrArr[];
   if(CopyBuffer(g_atrHandle, 0, 0, 100, atrArr) < 100) return "MID";

   double sorted[];
   ArrayResize(sorted, 100);
   ArrayCopy(sorted, atrArr);
   ArraySort(sorted);

   double p33 = sorted[33];
   double p66 = sorted[66];
   double current = atrArr[0];

   if(current < p33) return "LOW";
   if(current > p66) return "HIGH";
   return "MID";
}

//+------------------------------------------------------------------+
//| GetRegimeMultipliers                                             |
//+------------------------------------------------------------------+
void GetRegimeMultipliers(string regime, double &slMult, double &tpMult)
{
   if(regime == "LOW")
   {
      slMult = atr_sl_mult * 0.6;
      tpMult = atr_tp_mult * 0.8;
   }
   else if(regime == "HIGH")
   {
      slMult = atr_sl_mult * 1.4;
      tpMult = atr_tp_mult * 1.3;
   }
   else
   {
      slMult = atr_sl_mult;
      tpMult = atr_tp_mult;
   }
}

//+------------------------------------------------------------------+
//| CalcLotSize                                                       |
//+------------------------------------------------------------------+
double CalcLotSize(double slDist)
{
   if(slDist <= 0) return 0.01;
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double risk = equity * risk_percent / 100.0;
   double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize == 0) tickSize = 0.00001;
   double lot = risk / (slDist * tickVal / tickSize);
   lot = NormalizeDouble(lot, 2);
   return MathMax(0.01, MathMin(lot, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX)));
}

//+------------------------------------------------------------------+
//| LogTrade — CSV                                                   |
//+------------------------------------------------------------------+
void LogTrade(string direction, double entry, double sl, double tp, double lots, string regime)
{
   string fname = "ClawTrend_trades.csv";
   int fh = FileOpen(fname, FILE_CSV | FILE_READ | FILE_WRITE);
   if(fh == INVALID_HANDLE)
   {
      fh = FileOpen(fname, FILE_CSV | FILE_WRITE);
   }
   if(fh == INVALID_HANDLE) return;

   if(FileTell(fh) == 0)
      FileWriteString(fh, "open_time,direction,entry_price,sl,tp,lots,regime,equity,balance,pnl\n");

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double pnl = equity - balance;

   string line = StringFormat("%s,%s,%.5f,%.5f,%.5f,%.2f,%s,%.2f,%.2f,%.2f\n",
      TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS),
      direction, entry, sl, tp, lots, regime, equity, balance, pnl);

   FileSeek(fh, 0, SEEK_END);
   FileWriteString(fh, line);
   FileClose(fh);
}

//+------------------------------------------------------------------+
//| PrintDashboard                                                    |
//+------------------------------------------------------------------+
void PrintDashboard(string regime, double rsiVal, double fastEMA, double slowEMA)
{
   double atrArr[];
   CopyBuffer(g_atrHandle, 0, 0, 1, atrArr);
   double atr = (ArraySize(atrArr) > 0) ? atrArr[0] : 0;

   string signal = (fastEMA > slowEMA) ? "LONG" : "SHORT";

   Print("=== ClawTrend Dashboard ===");
   Print("Symbol: ", _Symbol);
   Print("Signal: ", signal, " | Regime: ", regime);
   Print("Fast EMA: ", fastEMA, " | Slow EMA: ", slowEMA);
   Print("RSI: ", rsiVal);
   Print("ATR: ", atr);
   Print("Risk: ", risk_percent, "% | SL mult: ", atr_sl_mult, " | TP mult: ", atr_tp_mult);
   Print("Equity: ", AccountInfoDouble(ACCOUNT_EQUITY), " | Balance: ", AccountInfoDouble(ACCOUNT_BALANCE));
   Print("===========================");
}

//+------------------------------------------------------------------+
//| Guardrails                                                        |
//+------------------------------------------------------------------+
bool CheckGuardrails()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(dt.day_of_week == 0 || dt.day_of_week == 6) return false;
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance > 0 && (balance - equity) / balance > 0.20) return false;
   return true;
}

//+------------------------------------------------------------------+
//| CountPositions                                                    |
//+------------------------------------------------------------------+
int CountPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) == _Symbol) count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| OnTick                                                            |
//+------------------------------------------------------------------+
void OnTick()
{
   datetime currentBar = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(currentBar == gLastBarTime) return;
   gLastBarTime = currentBar;

   if(!CheckGuardrails()) return;

   //--- Read closed bar [1] for signals (anti-repaint)
   double fastEMAArr[], slowEMAArr[];
   if(CopyBuffer(g_emaFastHandle, 0, 1, 1, fastEMAArr) < 1) return;
   if(CopyBuffer(g_emaSlowHandle, 0, 1, 1, slowEMAArr) < 1) return;
   double fastEMA = fastEMAArr[0];
   double slowEMA = slowEMAArr[0];

   double rsiArr[];
   if(CopyBuffer(g_rsiHandle, 0, 1, 1, rsiArr) < 1) return;
   double rsiVal = rsiArr[0];

   string regime = GetRegime();
   double slMult, tpMult;
   GetRegimeMultipliers(regime, slMult, tpMult);

   PrintDashboard(regime, rsiVal, fastEMA, slowEMA);

   if(CountPositions() > 0) return;

   bool isLong = (fastEMA > slowEMA);
   bool isShort = (fastEMA < slowEMA);
   bool rsiBull = (rsiVal > 50);
   bool rsiBear = (rsiVal < 50);

   bool buySignal = isLong && rsiBull;
   bool sellSignal = isShort && rsiBear;

   if(!buySignal && !sellSignal) return;

   // Capture ATR from closed bar [1] once — lock SL/TL distances here, do not recalculate
   double atrArr[];
   if(CopyBuffer(g_atrHandle, 0, 1, 1, atrArr) < 1) return;
   double atrAtEntry = atrArr[0];

   double slDist = atrAtEntry * slMult;
   double tpDist = atrAtEntry * tpMult;
   double lots = CalcLotSize(slDist);

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(buySignal)
   {
      // SL/TP locked from atrAtEntry — entry price is ask
      double sl = NormalizeDouble(ask - slDist, _Digits);
      double tp = NormalizeDouble(ask + tpDist, _Digits);
      bool ok = trade.Buy(lots, _Symbol, ask, sl, tp, "ClawTrend_v1|" + regime);
      if(ok) LogTrade("BUY", ask, sl, tp, lots, regime);
   }
   else if(sellSignal)
   {
      // SL/TP locked from atrAtEntry — entry price is bid
      double sl = NormalizeDouble(bid + slDist, _Digits);
      double tp = NormalizeDouble(bid - tpDist, _Digits);
      bool ok = trade.Sell(lots, _Symbol, bid, sl, tp, "ClawTrend_v1|" + regime);
      if(ok) LogTrade("SELL", bid, sl, tp, lots, regime);
   }
}

//+------------------------------------------------------------------+
//| OnInit                                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(0);
   trade.SetDeviationInPoints(10);
   trade.SetTypeFilling(ORDER_FILLING_FOK);

   g_rsiHandle = iRSI(_Symbol, PERIOD_CURRENT, rsi_period, PRICE_CLOSE);
   g_emaFastHandle = iMA(_Symbol, PERIOD_CURRENT, fast_ema, 0, MODE_EMA, PRICE_CLOSE);
   g_emaSlowHandle = iMA(_Symbol, PERIOD_CURRENT, slow_ema, 0, MODE_EMA, PRICE_CLOSE);
   g_atrHandle = iATR(_Symbol, PERIOD_CURRENT, atr_period);

   if(g_rsiHandle == INVALID_HANDLE || g_emaFastHandle == INVALID_HANDLE ||
      g_emaSlowHandle == INVALID_HANDLE || g_atrHandle == INVALID_HANDLE)
   {
      Print("ClawTrend_v1 ERROR: Failed to create indicator handles!");
      return INIT_FAILED;
   }

   gLastBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   Print("ClawTrend_v1 initialized - Trend Following EA");
   Print("Params: fast_ema=", fast_ema, ", slow_ema=", slow_ema,
         ", rsi_period=", rsi_period, ", atr_period=", atr_period,
         ", atr_sl_mult=", atr_sl_mult, ", atr_tp_mult=", atr_tp_mult,
         ", risk_percent=", risk_percent);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeinit                                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_rsiHandle != INVALID_HANDLE) IndicatorRelease(g_rsiHandle);
   if(g_emaFastHandle != INVALID_HANDLE) IndicatorRelease(g_emaFastHandle);
   if(g_emaSlowHandle != INVALID_HANDLE) IndicatorRelease(g_emaSlowHandle);
   if(g_atrHandle != INVALID_HANDLE) IndicatorRelease(g_atrHandle);
   Print("ClawTrend_v1 deinitialized - Reason: ", reason);
}
//+------------------------------------------------------------------+
