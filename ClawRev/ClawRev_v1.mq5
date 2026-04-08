//+------------------------------------------------------------------+
//|                                            ClawRev_v1.mq5         |
//|                                    Mean-Reversion Expert Advisor |
//+------------------------------------------------------------------+
#property copyright "ClawRev_v1"
#property version   "1.00"
#property strict

//+------------------------------------------------------------------+
//| INPUTS - 7 total parameters                                      |
//+------------------------------------------------------------------+
input int      bb_period       = 20;       // Bollinger Band Period
input double   bb_deviation    = 2.0;      // Bollinger Band Deviation
input int      rsi_period      = 14;       // RSI Period
input int      atr_period       = 14;       // ATR Period for SL/TP sizing
input double   atr_sl_mult     = 2.0;      // ATR Multiplier for Stop Loss
input double   atr_tp_mult     = 1.5;      // ATR Multiplier for Take Profit
input double   risk_percent   = 2.0;      // Risk % of equity per trade

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                 |
//+------------------------------------------------------------------+
datetime g_lastBarTime = 0;

// Indicator handles
int g_rsiHandle = INVALID_HANDLE;
int g_bbHandle = INVALID_HANDLE;
int g_atrHandle = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| ENUM FOR REGIME                                                  |
//+------------------------------------------------------------------+
enum RegimeEnum { REGIME_LOW, REGIME_MID, REGIME_HIGH };

//+------------------------------------------------------------------+
//| GetRegime - ATR percentile over 100 bars                          |
//+------------------------------------------------------------------+
RegimeEnum GetRegime()
{
   double atrArr[];
   if(CopyBuffer(g_atrHandle, 0, 0, 100, atrArr) < 100) return REGIME_MID;

   // Sort to find percentiles
   double sorted[];
   ArrayResize(sorted, 100);
   ArrayCopy(sorted, atrArr);
   ArraySort(sorted);

   double p33 = sorted[33];  // 33rd percentile
   double p66 = sorted[66];  // 66th percentile
   double currentATR = atrArr[0]; // most recent ATR

   if(currentATR < p33)       return REGIME_LOW;
   else if(currentATR > p66)  return REGIME_HIGH;
   else                        return REGIME_MID;
}

//+------------------------------------------------------------------+
//| GetAtrMultiplier based on regime                                 |
//+------------------------------------------------------------------+
double GetSLMultiplier(RegimeEnum regime) { return (regime == REGIME_HIGH) ? 3.0 : (regime == REGIME_LOW) ? 1.5 : 2.0; }
double GetTPMultiplier(RegimeEnum regime) { return (regime == REGIME_HIGH) ? 4.0 : (regime == REGIME_LOW) ? 2.5 : 3.0; }

//+------------------------------------------------------------------+
//| CalculateRSI - closed bar only [1]                               |
//+------------------------------------------------------------------+
double CalculateRSI()
{
   double rsiArr[];
   if(CopyBuffer(g_rsiHandle, 0, 1, 1, rsiArr) < 1) return 50.0;
   return rsiArr[0];
}

//+------------------------------------------------------------------+
//| GetBollingerBands - closed bar only [1]                          |
//+------------------------------------------------------------------+
bool GetBB(double &upper, double &middle, double &lower)
{
   double upperArr[], middleArr[], lowerArr[];
   if(CopyBuffer(g_bbHandle, 1, 1, 1, upperArr) < 1) return false;
   if(CopyBuffer(g_bbHandle, 0, 1, 1, middleArr) < 1) return false;
   if(CopyBuffer(g_bbHandle, 2, 1, 1, lowerArr) < 1) return false;
   upper   = upperArr[0];
   middle  = middleArr[0];
   lower   = lowerArr[0];
   return (upper != 0.0 && lower != 0.0);
}

//+------------------------------------------------------------------+
//| CalculateLotSize                                                 |
//+------------------------------------------------------------------+
double CalculateLotSize(double slDist)
{
   if(slDist <= 0) return 0.01;
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskAmt = equity * (risk_percent / 100.0);
   double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize == 0) tickSize = 0.00001;
   double lot = NormalizeDouble(riskAmt / (slDist * tickVal / tickSize), 2);
   return MathMax(0.01, MathMin(lot, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX)));
}

//+------------------------------------------------------------------+
//| OpenTrade                                                        |
//+------------------------------------------------------------------+
bool OpenTrade(ENUM_ORDER_TYPE type, double sl, double tp, double lots, RegimeEnum regime)
{
   string dirStr = (type == ORDER_TYPE_BUY) ? "BUY" : "SELL";
   MqlTradeRequest request = {};
   MqlTradeResult result = {};

   request.action       = TRADE_ACTION_DEAL;
   request.symbol       = _Symbol;
   request.volume       = lots;
   request.type         = type;
   request.price        = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   request.sl           = sl;
   request.tp           = tp;
   request.deviation     = 10;
   request.comment      = "ClawRev_v1";

   bool sent = OrderSend(request, result);
   if(sent && result.retcode == TRADE_RETCODE_DONE)
   {
      LogTrade(dirStr, request.price, sl, tp, lots, regime);
   }
   return sent;
}

//+------------------------------------------------------------------+
//| LogTrade - CSV format                                            |
//+------------------------------------------------------------------+
void LogTrade(string direction, double entry, double sl, double tp, double lots, RegimeEnum regime)
{
   string regimeStr = (regime == REGIME_HIGH) ? "HIGH" : (regime == REGIME_MID) ? "MID" : "LOW";
   string path = "ClawRev_trades.csv";
   datetime now = TimeCurrent();
   string openTime = TimeToString(now, TIME_DATE | TIME_MINUTES);

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double pnl = equity - balance;

   string header = "open_time,direction,entry_price,sl,tp,lots,regime,equity,balance,pnl";
   string line = StringFormat("%s,%s,%.5f,%.5f,%.5f,%.2f,%s,%.2f,%.2f,%.2f",
                              openTime, direction, entry, sl, tp, lots, regimeStr, equity, balance, pnl);

   bool exists = FileIsExist(path);
   int fileHandle = FileOpen(path, FILE_CSV | FILE_READ | FILE_WRITE);
   if(fileHandle != INVALID_HANDLE)
   {
      if(!exists) FileWriteString(fileHandle, header + "\n");
      FileSeek(fileHandle, 0, SEEK_END);
      FileWriteString(fileHandle, line + "\n");
      FileClose(fileHandle);
   }
}

//+------------------------------------------------------------------+
//| PrintDashboard                                                   |
//+------------------------------------------------------------------+
void PrintDashboard()
{
   double rsi = CalculateRSI();
   double upper, middle, lower;
   GetBB(upper, middle, lower);

   double atrArr[];
   CopyBuffer(g_atrHandle, 0, 0, 1, atrArr);
   double atr = (ArraySize(atrArr) > 0) ? atrArr[0] : 0;

   RegimeEnum regime = GetRegime();

   string regimeStr = (regime == REGIME_HIGH) ? "HIGH" : (regime == REGIME_MID) ? "MID" : "LOW";
   string signal = "NEUTRAL";

   // Mean-reversion signals
   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   bool bbUpperTouch = (price >= upper * 0.9999);
   bool bbLowerTouch = (price <= lower * 1.0001);
   bool rsiOB = (rsi > 70);
   bool rsiOS = (rsi < 30);

   if(rsiOB && bbUpperTouch) signal = "SELL (overbought + BB upper)";
   else if(rsiOS && bbLowerTouch) signal = "BUY (oversold + BB lower)";

   double slMult = GetSLMultiplier(regime);
   double tpMult = GetTPMultiplier(regime);

   Print("=== ClawRev Dashboard ===");
   Print("Symbol: ", _Symbol);
   Print("RSI: ", rsi, (rsiOB ? " [OVERBOUGHT]" : (rsiOS ? " [OVERSOLD]" : "")));
   Print("BB Upper: ", upper, " | Middle: ", middle, " | Lower: ", lower);
   Print("Price: ", price, " | BB Upper Touch: ", bbUpperTouch, " | BB Lower Touch: ", bbLowerTouch);
   Print("ATR: ", atr);
   Print("Regime: ", regimeStr, " | SL Mult: ", slMult, " | TP Mult: ", tpMult);
   Print("Signal: ", signal);
   Print("Equity: ", AccountInfoDouble(ACCOUNT_EQUITY), " | Balance: ", AccountInfoDouble(ACCOUNT_BALANCE));
   Print("=========================");
}

//+------------------------------------------------------------------+
//| Guardrail checks                                                 |
//+------------------------------------------------------------------+
bool CheckGuardrails()
{
   datetime now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);

   // Weekend check
   if(dt.day_of_week == 0 || dt.day_of_week == 6) return false;

   // No positions if equity drawdown > 20%
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance > 0 && (balance - equity) / balance > 0.20) return false;

   return true;
}

//+------------------------------------------------------------------+
//| Count open positions                                             |
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
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(currentBarTime == g_lastBarTime) return;
   g_lastBarTime = currentBarTime;

   if(!CheckGuardrails()) return;

   PrintDashboard();

   if(CountPositions() > 0) return;

   double rsi = CalculateRSI();
   double upper, middle, lower;
   GetBB(upper, middle, lower);

   double atrArr[];
   CopyBuffer(g_atrHandle, 0, 0, 1, atrArr);
   double atr = (ArraySize(atrArr) > 0) ? atrArr[0] : 0;

   RegimeEnum regime = GetRegime();

   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // Mean reversion entry logic
   bool rsiOB = (rsi > 70);
   bool rsiOS = (rsi < 30);
   bool bbUpperTouch = (price >= upper * 0.9999);
   bool bbLowerTouch = (price <= lower * 1.0001);

   double slMult = GetSLMultiplier(regime);
   double tpMult = GetTPMultiplier(regime);

   double slDist = atr * atr_sl_mult;
   double tpDist = atr * atr_tp_mult;

   // SELL: RSI overbought + price at/near BB upper
   if(rsiOB && bbUpperTouch)
   {
      double sl = price + slDist * slMult;
      double tp = price - tpDist * tpMult;
      double lots = CalculateLotSize(slDist * slMult);
      OpenTrade(ORDER_TYPE_SELL, sl, tp, lots, regime);
   }
   // BUY: RSI oversold + price at/near BB lower
   else if(rsiOS && bbLowerTouch)
   {
      double sl = price - slDist * slMult;
      double tp = price + tpDist * tpMult;
      double lots = CalculateLotSize(slDist * slMult);
      OpenTrade(ORDER_TYPE_BUY, sl, tp, lots, regime);
   }
}

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   g_rsiHandle = iRSI(_Symbol, PERIOD_CURRENT, rsi_period, PRICE_CLOSE);
   g_bbHandle  = iBands(_Symbol, PERIOD_CURRENT, bb_period, 0, bb_deviation, PRICE_CLOSE);
   g_atrHandle = iATR(_Symbol, PERIOD_CURRENT, atr_period);

   if(g_rsiHandle == INVALID_HANDLE || g_bbHandle == INVALID_HANDLE || g_atrHandle == INVALID_HANDLE)
   {
      Print("ClawRev_v1 ERROR: Failed to create indicator handles!");
      return INIT_FAILED;
   }

   g_lastBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   Print("ClawRev_v1 initialized - Mean Reversion EA");
   Print("Parameters: bb_period=", bb_period, ", bb_deviation=", bb_deviation,
         ", rsi_period=", rsi_period, ", atr_period=", atr_period,
         ", atr_sl_mult=", atr_sl_mult, ", atr_tp_mult=", atr_tp_mult,
         ", risk_percent=", risk_percent);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_rsiHandle != INVALID_HANDLE) IndicatorRelease(g_rsiHandle);
   if(g_bbHandle != INVALID_HANDLE)  IndicatorRelease(g_bbHandle);
   if(g_atrHandle != INVALID_HANDLE) IndicatorRelease(g_atrHandle);
   Print("ClawRev_v1 deinitialized - Reason: ", reason);
}
//+------------------------------------------------------------------+
