//+------------------------------------------------------------------+
//|                                             ClawTrend_v1.mq5      |
//|                                                    PM Claw Build  |
//+------------------------------------------------------------------+
#property copyright "PM Claw"
#property version   "1.00"
#property indicator_chart_output
#property indicator_buffers 2
#property indicator_plots   1

//--- plot 1: regime
#property indicator_label1  "Regime"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrNONE
#property indicator_style1  STYLE_SOLID
#property indicator_width1  0

//--- buffers
double RegimeBuffer[];
double SignalBuffer[];

//+------------------------------------------------------------------+
//| INPUTS (7 total)                                                 |
//+------------------------------------------------------------------+
input group "=== EMA ==="
input int      fast_ema      = 9;      // Fast EMA period
input int      slow_ema      = 21;     // Slow EMA period

input group "=== RSI ==="
input int      rsi_period   = 14;     // RSI period

input group "=== ATR Risk ==="
input int      atr_period   = 14;     // ATR period
input double   atr_sl_mult  = 1.5;    // ATR SL multiplier
input double   atr_tp_mult  = 3.0;    // ATR TP multiplier

input group "=== Risk Sizing ==="
input double   risk_percent = 1.0;    // Risk % of equity per trade

//+------------------------------------------------------------------+
//| GLOBAL                                                            |
//+------------------------------------------------------------------+
string  gSymbol;
double  gTickSize;
long    gDigits;
double  gPoint;
datetime gLastBarTime = 0;
datetime gLastTradeTime = 0;

//+------------------------------------------------------------------+
//| ONINIT                                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   gSymbol   = _Symbol;
   gTickSize = SymbolInfoDouble(gSymbol, SYMBOL_TRADE_TICK_SIZE);
   gDigits   = (long)SymbolInfoInteger(gSymbol, SYMBOL_DIGITS);
   gPoint    = SymbolInfoDouble(gSymbol, SYMBOL_POINT);

   IndicatorSetInteger(INDICATOR_SHORTNAME, "ClawTrend_v1");

   SetIndexBuffer(0, RegimeBuffer, INDICATOR_DATA);
   SetIndexBuffer(1, SignalBuffer, INDICATOR_DATA);

   PlotIndexSetInteger(0, PLOT_DRAW_TYPE, DRAW_LINE);
   PlotIndexSetInteger(1, PLOT_DRAW_TYPE, DRAW_NONE);

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| ONDEINIT                                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
}

//+------------------------------------------------------------------+
//| Calc ATR percentile regime over 100 bars                         |
//+------------------------------------------------------------------+
string CalcRegime(int shift)
{
   double atrVal = iATR(gSymbol, PERIOD_CURRENT, atr_period, shift);
   if(atrVal <= 0) return "MID";

   // collect 100 bars of ATR
   double vals[100];
   for(int i = 0; i < 100; i++)
   {
      vals[i] = iATR(gSymbol, PERIOD_CURRENT, atr_period, shift + i);
      if(vals[i] <= 0) { vals[i] = atrVal; }
   }

   // percentile buckets
   double sorted[100];
   ArrayCopy(sorted, vals);
   ArraySort(sorted);

   int p33 = 33;
   int p66 = 66;
   double threshLow  = sorted[p33];
   double threshHigh = sorted[p66];

   if(atrVal <= threshLow)  return "LOW";
   if(atrVal >= threshHigh) return "HIGH";
   return "MID";
}

//+------------------------------------------------------------------+
//| Get adaptive SL/TP multipliers from regime                       |
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
   else // MID
   {
      slMult = atr_sl_mult;
      tpMult = atr_tp_mult;
   }
}

//+------------------------------------------------------------------+
//| Calc lot size from risk                                          |
//+------------------------------------------------------------------+
double CalcLot(double slDist)
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double risk   = equity * risk_percent / 100.0;
   double lot    = risk / (slDist > 0 ? slDist / gPoint : 1.0);
   lot          = MathFloor(lot / SymbolInfoDouble(gSymbol, SYMBOL_VOLUME_STEP)) 
                  * SymbolInfoDouble(gSymbol, SYMBOL_VOLUME_STEP);
   return MathMax(lot, SymbolInfoDouble(gSymbol, SYMBOL_VOLUME_MIN));
}

//+------------------------------------------------------------------+
//| ONCALC                                                            |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   if(rates_total < MathMax(slow_ema, MathMax(rsi_period, atr_period)) + 100)
      return 0;

   int start = prev_calculated > 0 ? prev_calculated - 1 : 1;

   for(int i = start; i < rates_total - 1; i++)
   {
      //--- EMA values (closed bar [i+1] not yet formed — use [i] as proxy)
      double fastEMA = iMA(gSymbol, PERIOD_CURRENT, fast_ema, 0, MODE_EMA, PRICE_CLOSE, i);
      double slowEMA = iMA(gSymbol, PERIOD_CURRENT, slow_ema, 0, MODE_EMA, PRICE_CLOSE, i);

      //--- Trend
      bool isLong  = fastEMA > slowEMA;
      bool isShort = fastEMA < slowEMA;

      //--- RSI on closed bar [1] (anti-repaint)
      double rsiVal = iRSI(gSymbol, PERIOD_CURRENT, rsi_period, PRICE_CLOSE, i + 1);
      bool rsiBull  = rsiVal > 50;
      bool rsiBear  = rsiVal < 50;

      //--- Regime
      string regime = CalcRegime(i + 1);

      //--- Signal: EMA aligned + RSI confirms
      bool buySignal = isLong  && rsiBull;
      bool sellSignal = isShort && rsiBear;

      //--- Regime buffer (1=LOW, 2=MID, 3=HIGH for easy viz)
      if(regime == "LOW")       RegimeBuffer[i] = 1;
      else if(regime == "MID")  RegimeBuffer[i] = 2;
      else                      RegimeBuffer[i] = 3;

      SignalBuffer[i] = buySignal ? 1 : (sellSignal ? -1 : 0);
   }

   return rates_total - 1;
}

//+------------------------------------------------------------------+
//| ONTICK                                                            |
//+------------------------------------------------------------------+
void OnTick()
{
   static datetime lastBar = 0;
   datetime curBar = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(curBar <= lastBar) return;
   lastBar = curBar;

   //--- check for new closed bar (index 1 is most recent closed bar)
   double fastEMA = iMA(gSymbol, PERIOD_CURRENT, fast_ema, 0, MODE_EMA, PRICE_CLOSE, 1);
   double slowEMA = iMA(gSymbol, PERIOD_CURRENT, slow_ema, 0, MODE_EMA, PRICE_CLOSE, 1);

   bool isLong  = fastEMA > slowEMA;
   bool isShort = fastEMA < slowEMA;

   double rsiVal = iRSI(gSymbol, PERIOD_CURRENT, rsi_period, PRICE_CLOSE, 1);
   bool rsiBull  = rsiVal > 50;
   bool rsiBear  = rsiVal < 50;

   string regime = CalcRegime(1);

   bool buySignal  = isLong  && rsiBull;
   bool sellSignal = isShort && rsiBear;

   //--- Guard: no trades if positions already open
   if(PositionSelect(gSymbol))
   {
      // existing position — skip
      return;
   }

   if(buySignal || sellSignal)
   {
      //--- ATR for SL/TP sizing
      double atrVal = iATR(gSymbol, PERIOD_CURRENT, atr_period, 1);
      double slMult, tpMult;
      GetRegimeMultipliers(regime, slMult, tpMult);

      double slDist = atrVal * slMult;
      double tpDist = atrVal * tpMult;

      double lot = CalcLot(slDist);

      double ask = SymbolInfoDouble(gSymbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(gSymbol, SYMBOL_BID);
      double entryPrice = buySignal ? ask : bid;
      double sl = buySignal ? (entryPrice - slDist) : (entryPrice + slDist);
      double tp = buySignal ? (entryPrice + tpDist) : (entryPrice - tpDist);

      double slPips  = MathAbs(entryPrice - sl)  / gPoint;
      double tpPips  = MathAbs(entryPrice - tp)  / gPoint;

      MqlTradeRequest req = {};
      MqlTradeResult  res  = {};

      req.action   = TRADE_ACTION_DEAL;
      req.symbol   = gSymbol;
      req.volume   = lot;
      req.type     = buySignal ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      req.price    = entryPrice;
      req.sl       = sl;
      req.tp       = tp;
      req.deviation = 10;
      req.comment  = "ClawTrend_v1|" + regime;

      OrderSend(req, res);

      if(res.retcode == TRADE_RETCODE_DONE)
      {
         LogTrade(buySignal ? "LONG" : "SHORT", entryPrice, sl, tp, lot, regime);
      }

      PrintDashboard(regime, slPips, tpPips, slDist, tpDist, rsiVal, fastEMA, slowEMA, res.retcode);
   }
}

//+------------------------------------------------------------------+
//| PrintDashboard                                                    |
//+------------------------------------------------------------------+
void PrintDashboard(string regime, double slPips, double tpPips,
                    double slDist, double tpDist,
                    double rsi, double fEMA, double sEMA, int retcode)
{
   string sep = "====================================";
   Print(sep);
   Print("  CLAWTREND v1 | ", gSymbol, " | ", TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES));
   Print(sep);
   PrintFormat("  REGIME   : %s", regime);
   PrintFormat("  FAST EMA : %.5f", fEMA);
   PrintFormat("  SLOW EMA : %.5f", sEMA);
   PrintFormat("  RSI(%.0f) : %.2f", (double)rsi_period, rsi);
   PrintFormat("  SL dist  : %.5f (%.1f pips)", slDist, slPips);
   PrintFormat("  TP dist  : %.5f (%.1f pips)", tpDist, tpPips);
   PrintFormat("  ATR(%.0f) : used for SL/TP", (double)atr_period);
   PrintFormat("  Equity   : %.2f", AccountInfoDouble(ACCOUNT_EQUITY));
   PrintFormat("  Balance  : %.2f", AccountInfoDouble(ACCOUNT_BALANCE));
   PrintFormat("  Trade RC  : %d", retcode);
   Print(sep);
}

//+------------------------------------------------------------------+
//| LogTrade — CSV-friendly                                          |
//+------------------------------------------------------------------+
void LogTrade(string direction, double entryPrice, double sl, double tp,
              double lot, string regime)
{
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double pnl     = equity - balance;

   string fname = "ClawTrend_trades.csv";
   int fh = FileOpen(fname, FILE_CSV | FILE_READ | FILE_WRITE | FILE_APPEND);

   if(fh == INVALID_HANDLE)
   {
      // try write-only if file doesn't exist yet
      fh = FileOpen(fname, FILE_CSV | FILE_WRITE | FILE_APPEND);
   }

   if(fh != INVALID_HANDLE)
   {
      // write header if new file
      if(FileTellPosition(fh) == 0)
      {
         FileWriteString(fh, "open_time,direction,entry_price,sl,tp,lots,regime,equity,balance,pnl\n");
      }

      string line = StringFormat("%s,%s,%.5f,%.5f,%.5f,%.2f,%s,%.2f,%.2f,%.2f\n",
         TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS),
         direction, entryPrice, sl, tp, lot, regime, equity, balance, pnl);

      FileWriteString(fh, line);
      FileClose(fh);
   }
   else
   {
      Print("[ClawTrend] Warning: could not open trade log file");
   }
}
//+------------------------------------------------------------------+
