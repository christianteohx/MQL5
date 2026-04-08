//+------------------------------------------------------------------+
//|                                    ClawRev_v1.mq5                |
//|                                       Mean-Reversion EA           |
//+------------------------------------------------------------------+
#property copyright "Claw"
#property version   "1.00"
#property strict

//+------------------------------------------------------------------+
//| INPUTS (7 total)                                                 |
//+------------------------------------------------------------------+
input int      bb_period      = 20;      // Bollinger Band period
input double   bb_deviation   = 2.0;     // BB deviation
input int      rsi_period    = 14;      // RSI period
input int      atr_period    = 14;       // ATR period
input double   atr_sl_mult   = 2.0;     // ATR SL multiplier
input double   atr_tp_mult   = 1.5;     // ATR TP multiplier
input double   risk_percent  = 2.0;      // Risk % of equity per trade

//+------------------------------------------------------------------+
//| GLOBAL                                                            |
//+------------------------------------------------------------------+
int g_rsiHandle = INVALID_HANDLE;
int g_bbHandle = INVALID_HANDLE;
int g_atrHandle = INVALID_HANDLE;
datetime gLastBarTime = 0;

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
//| GetBBValues — closed bar [1]                                    |
//+------------------------------------------------------------------+
bool GetBB(double &upper, double &middle, double &lower)
{
   double upperArr[], middleArr[], lowerArr[];
   if(CopyBuffer(g_bbHandle, 1, 1, 1, upperArr) < 1) return false;
   if(CopyBuffer(g_bbHandle, 0, 1, 1, middleArr) < 1) return false;
   if(CopyBuffer(g_bbHandle, 2, 1, 1, lowerArr) < 1) return false;
   upper = upperArr[0];
   middle = middleArr[0];
   lower = lowerArr[0];
   return (upper != 0.0 && lower != 0.0);
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
//| OpenTrade                                                         |
//+------------------------------------------------------------------+
bool OpenTrade(ENUM_ORDER_TYPE type, double sl, double tp, double lots, string regime)
{
   MqlTradeRequest req = {};
   MqlTradeResult res = {};

   req.action = TRADE_ACTION_DEAL;
   req.symbol = _Symbol;
   req.volume = lots;
   req.type = type;
   req.price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   req.sl = sl;
   req.tp = tp;
   req.deviation = 10;
   req.comment = "ClawRev_v1|" + regime;

   bool sent = OrderSend(req, res);
   if(sent && res.retcode == TRADE_RETCODE_DONE)
   {
      LogTrade((type == ORDER_TYPE_BUY) ? "BUY" : "SELL", req.price, sl, tp, lots, regime);
   }
   return sent;
}

//+------------------------------------------------------------------+
//| LogTrade — CSV                                                   |
//+------------------------------------------------------------------+
void LogTrade(string direction, double entry, double sl, double tp, double lots, string regime)
{
   string fname = "ClawRev_trades.csv";
   int fh = FileOpen(fname, FILE_CSV | FILE_READ | FILE_WRITE);
   if(fh == INVALID_HANDLE)
   {
      fh = FileOpen(fname, FILE_CSV | FILE_WRITE);
   }
   if(fh == INVALID_HANDLE) return;

   if(FileTellPosition(fh) == 0)
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
void PrintDashboard(string regime, double rsiVal, double upper, double middle, double lower)
{
   double atrArr[];
   CopyBuffer(g_atrHandle, 0, 0, 1, atrArr);
   double atr = (ArraySize(atrArr) > 0) ? atrArr[0] : 0;

   string signal = "NEUTRAL";
   if(rsiVal > 70) signal = "SELL (overbought)";
   else if(rsiVal < 30) signal = "BUY (oversold)";

   Print("=== ClawRev Dashboard ===");
   Print("Symbol: ", _Symbol);
   Print("Signal: ", signal, " | Regime: ", regime);
   Print("RSI: ", rsiVal);
   Print("BB Upper: ", upper, " | Middle: ", middle, " | Lower: ", lower);
   Print("ATR: ", atr);
   Print("Risk: ", risk_percent, "% | SL mult: ", atr_sl_mult, " | TP mult: ", atr_tp_mult);
   Print("Equity: ", AccountInfoDouble(ACCOUNT_EQUITY), " | Balance: ", AccountInfoDouble(ACCOUNT_BALANCE));
   Print("==========================");
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

   double rsiArr[];
   if(CopyBuffer(g_rsiHandle, 0, 1, 1, rsiArr) < 1) return;
   double rsiVal = rsiArr[0];

   double upper, middle, lower;
   if(!GetBB(upper, middle, lower)) return;

   string regime = GetRegime();
   double slMult, tpMult;
   GetRegimeMultipliers(regime, slMult, tpMult);

   PrintDashboard(regime, rsiVal, upper, middle, lower);

   if(CountPositions() > 0) return;

   double atrArr[];
   if(CopyBuffer(g_atrHandle, 0, 1, 1, atrArr) < 1) return;
   double atr = atrArr[0];

   double slDist = atr * slMult;
   double tpDist = atr * tpMult;
   double lots = CalcLotSize(slDist);

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // Mean-reversion signals on closed bar
   bool overbought = (rsiVal > 70);
   bool oversold = (rsiVal < 30);
   bool atUpper = (price >= upper * 0.9999);
   bool atLower = (price <= lower * 1.0001);

   // BUY: oversold + BB lower touch
   if(oversold && atLower)
   {
      double sl = ask - slDist;
      double tp = ask + tpDist;
      OpenTrade(ORDER_TYPE_BUY, sl, tp, lots, regime);
   }
   // SELL: overbought + BB upper touch
   else if(overbought && atUpper)
   {
      double sl = bid + slDist;
      double tp = bid - tpDist;
      OpenTrade(ORDER_TYPE_SELL, sl, tp, lots, regime);
   }
}

//+------------------------------------------------------------------+
//| OnInit                                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   g_rsiHandle = iRSI(_Symbol, PERIOD_CURRENT, rsi_period, PRICE_CLOSE);
   g_bbHandle = iBands(_Symbol, PERIOD_CURRENT, bb_period, 0, bb_deviation, PRICE_CLOSE);
   g_atrHandle = iATR(_Symbol, PERIOD_CURRENT, atr_period);

   if(g_rsiHandle == INVALID_HANDLE || g_bbHandle == INVALID_HANDLE || g_atrHandle == INVALID_HANDLE)
   {
      Print("ClawRev_v1 ERROR: Failed to create indicator handles!");
      return INIT_FAILED;
   }

   gLastBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   Print("ClawRev_v1 initialized - Mean Reversion EA");
   Print("Params: bb_period=", bb_period, ", bb_deviation=", bb_deviation,
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
   if(g_bbHandle != INVALID_HANDLE) IndicatorRelease(g_bbHandle);
   if(g_atrHandle != INVALID_HANDLE) IndicatorRelease(g_atrHandle);
   Print("ClawRev_v1 deinitialized - Reason: ", reason);
}
//+------------------------------------------------------------------+
