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
input int      atr_period      = 14;       // ATR Period for SL/TP sizing
input double   atr_sl_mult     = 2.0;      // ATR Multiplier for Stop Loss
input double   atr_tp_mult     = 1.5;      // ATR Multiplier for Take Profit
input double   risk_percent   = 2.0;      // Risk % of equity per trade

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                 |
//+------------------------------------------------------------------+
datetime lastBarTime   = 0;
double   lastEquity    = 0;
double   lastBalance   = 0;
double   lastPnL       = 0;

//+------------------------------------------------------------------+
//| ENUM FOR REGIME                                                  |
//+------------------------------------------------------------------+
enum RegimeEnum { REGIME_LOW, REGIME_MID, REGIME_HIGH };

//+------------------------------------------------------------------+
//| GetRegime - ATR percentile over 100 bars                         |
//+------------------------------------------------------------------+
RegimeEnum GetRegime(int atrPeriod)
{
   double atrArr[];
   if(CopyATR(_Symbol, PERIOD_CURRENT, 1, 100, atrArr) < 100) return REGIME_MID;

   // Sort to find percentiles
   double sorted[];
   ArrayResize(sorted, 100);
   ArrayCopy(sorted, atrArr);
   ArraySort(sorted);

   double p33 = sorted[33];  // 33rd percentile
   double p66 = sorted[66];  // 66th percentile
   double currentATR = atrArr[0]; // most recent ATR

   if(currentATR < p33)      return REGIME_LOW;
   else if(currentATR > p66)  return REGIME_HIGH;
   else                       return REGIME_MID;
}

//+------------------------------------------------------------------+
//| GetAtrMultiplier based on regime                                 |
//+------------------------------------------------------------------+
double GetSLMultiplier(RegimeEnum regime) { return (regime == REGIME_HIGH) ? 3.0 : (regime == REGIME_LOW) ? 1.5 : 2.0; }
double GetTPMultiplier(RegimeEnum regime) { return (regime == REGIME_HIGH) ? 1.0 : (regime == REGIME_LOW) ? 2.0 : 1.5; }

//+------------------------------------------------------------------+
//| CalculateRSI - closed bar only [1]                                |
//+------------------------------------------------------------------+
double CalculateRSI(int period)
{
   double rsiArr[];
   if(CopyBuffer(iRSI(_Symbol, PERIOD_CURRENT, period), 0, 1, 1, rsiArr) < 1) return 50.0;
   return rsiArr[0];
}

//+------------------------------------------------------------------+
//| GetBollingerBands - closed bar only [1]                          |
//+------------------------------------------------------------------+
bool GetBB(double &upper, double &middle, double &lower, int period, double dev)
{
   upper   = iBoll(_Symbol, PERIOD_CURRENT, period, 0, MODE_MAIN, 1);
   middle  = iBoll(_Symbol, PERIOD_CURRENT, period, dev, MODE_MAIN, 1);
   lower   = iBoll(_Symbol, PERIOD_CURRENT, period, dev, MODE_LOWER, 1);
   return (upper != 0 && lower != 0);
}

//+------------------------------------------------------------------+
//| CalculateLotSize                                                  |
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
   request.volume      = lots;
   request.type        = type;
   request.price       = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   request.sl          = sl;
   request.tp          = tp;
   request.deviation   = 10;
   request.comment     = "ClawRev_v1";

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
   double rsi   = CalculateRSI(rsi_period);
   double upper, middle, lower;
   GetBB(upper, middle, lower, bb_period, bb_deviation);
   double atr   = iATR(_Symbol, PERIOD_CURRENT, atr_period);
   RegimeEnum regime = GetRegime(atr_period);

   string regimeStr = (regime == REGIME_HIGH) ? "HIGH" : (regime == REGIME_MID) ? "MID" : "LOW";
   string signal = "NEUTRAL";

   // Mean-reversion signals
   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   bool bbUpperTouch = (price >= upper * 0.999);
   bool bbLowerTouch = (price <= lower * 1.001);
   bool rsiOB = (rsi > 70);
   bool rsiOS = (rsi < 30);

   if(rsiOB && bbUpperTouch) signal = "SELL (overbought + BB upper)";
   else if(rsiOS && bbLowerTouch) signal = "BUY (oversold + BB lower)";

   // Regime-based SL/TP multipliers
   double slMult = GetSLMultiplier(regime);
   double tpMult = GetTPMultiplier(regime);

   Print("=== ClawRev Dashboard ===");
   Print("Symbol: ", _Symbol, " | Timeframe: ", EnumToString(PERIOD_CURRENT));
   Print("RSI(", rsi_period, "): ", rsi, (rsiOB ? " [OVERBOUGHT]" : (rsiOS ? " [OVERSOLD]" : "")));
   Print("BB(", bb_period, ", ", bb_deviation, ") | Upper: ", upper, " | Middle: ", middle, " | Lower: ", lower);
   Print("Price: ", price, " | BB Upper Touch: ", bbUpperTouch, " | BB Lower Touch: ", bbLowerTouch);
   Print("ATR(", atr_period, "): ", atr);
   Print("Regime: ", regimeStr, " | SL Mult: ", slMult, " | TP Mult: ", tpMult);
   Print("Signal: ", signal);
   Print("Equity: ", AccountInfoDouble(ACCOUNT_EQUITY), " | Balance: ", AccountInfoDouble(ACCOUNT_BALANCE));
   Print("============================");
}

//+------------------------------------------------------------------+
//| Guardrail checks                                                 |
//+------------------------------------------------------------------+
bool CheckGuardrails()
{
   // No trades during high impact news (simple time-based guard)
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
//| Check for new bar                                                |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(currentBarTime != lastBarTime)
   {
      lastBarTime = currentBarTime;
      return true;
   }
   return false;
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
   if(!IsNewBar()) return;
   if(!CheckGuardrails()) return;

   // Dashboard output every bar
   PrintDashboard();

   // Only one position at a time
   if(CountPositions() > 0) return;

   double rsi   = CalculateRSI(rsi_period);
   double upper, middle, lower;
   GetBB(upper, middle, lower, bb_period, bb_deviation);
   double atr   = iATR(_Symbol, PERIOD_CURRENT, atr_period);
   RegimeEnum regime = GetRegime(atr_period);

   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double spread = SymbolInfoDouble(_Symbol, SYMBOL_SPREAD);

   // Mean reversion entry logic
   bool rsiOB = (rsi > 70);
   bool rsiOS = (rsi < 30);
   bool bbUpperTouch = (price >= upper * 0.999);
   bool bbLowerTouch = (price <= lower * 1.001);

   double slMult = GetSLMultiplier(regime);
   double tpMult = GetTPMultiplier(regime);

   double slDist = atr * atr_sl_mult * slMult;
   double tpDist = atr * atr_tp_mult * tpMult;

   // SELL: RSI overbought + price at BB upper
   if(rsiOB && bbUpperTouch)
   {
      double sl = price + slDist;
      double tp = price - tpDist;
      double lots = CalculateLotSize(slDist);
      OpenTrade(ORDER_TYPE_SELL, sl, tp, lots, regime);
   }
   // BUY: RSI oversold + price at BB lower
   else if(rsiOS && bbLowerTouch)
   {
      double sl = price - slDist;
      double tp = price + tpDist;
      double lots = CalculateLotSize(slDist);
      OpenTrade(ORDER_TYPE_BUY, sl, tp, lots, regime);
   }
}

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   lastBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   lastEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   lastBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   Print("ClawRev_v1 initialized - Mean Reversion EA");
   Print("Parameters: bb_period=", bb_period, ", bb_deviation=", bb_deviation,
         ", rsi_period=", rsi_period, ", atr_period=", atr_period,
         ", atr_sl_mult=", atr_sl_mult, ", atr_tp_mult=", atr_tp_mult,
         ", risk_percent=", risk_percent);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("ClawRev_v1 deinitialized - Reason: ", reason);
}
//+------------------------------------------------------------------+
