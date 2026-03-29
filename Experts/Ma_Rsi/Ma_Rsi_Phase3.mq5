//+------------------------------------------------------------------+
//| Ma_Rsi_Phase3.mq5                                               |
//| Phase 3: Dynamic Parameters Per Regime                           |
//| Self-contained module intended to be integrated with Ma_Rsi      |
//+------------------------------------------------------------------+
#property copyright "Phase3"
#property version   "1.00"
#property strict

//--- Inputs: dynamic-parameter control and bases
input bool use_adaptive_params = false; // Enable regime-based parameter adjustment
// Volatility reference (long-term median ATR)
input int vol_ref_period = 100;
// MA period scaling
input double ma_vol_alpha = 0.5; // How much volatility affects MA period [0.2-0.8]
input int ma_short_base = 9; // Base short MA period
input int ma_long_base = 26; // Base long MA period
// RSI threshold adjustment
input double rsi_vol_beta = 0.5; // How much volatility affects RSI thresholds [0.3-0.8]
input double rsi_buy_base = 30.0; // Base oversold level
input double rsi_sell_base = 70.0; // Base overbought level
input double rsi_buy_min = 15.0; // Floor for RSI oversold
input double rsi_sell_max = 85.0; // Ceiling for RSI overbought
// ATR SL/TP multiplier adjustment
input double sl_vol_gamma = 0.5; // How much volatility affects SL [0.3-1.0]
input double tp_vol_gamma_tp = 0.3; // How much volatility affects TP
input double sl_base_mult = 3.0; // Base SL ATR multiplier
input double tp_base_mult = 6.0; // Base TP ATR multiplier
// Bollinger Band width adjustment
input double bb_vol_delta = 0.5; // How much volatility affects BB dev [0.3-0.7]
input double bb_dev_base = 2.0; // Base Bollinger deviation

// Backwards-compatibility base params (kept in case use_adaptive_params=false)
input int rsi_period = 14;
input int atr_period = 14;

//--- Global statics for vol ref
static double g_vol_ref = 0.0;
static int g_vol_ref_count = 0;

//--- Helper: safe clamp
double Clamp(double v, double lo, double hi)
{
  if(v<lo) return lo;
  if(v>hi) return hi;
  return v;
}

//+------------------------------------------------------------------+
//| GetVolRatio: current_atr / vol_ref (rolling median-like via slow EMA)
//+------------------------------------------------------------------+
double GetVolRatio(double current_atr)
{
  // maintain a slow-tracking reference vol (rolling average to approximate median behaviour)
  if(g_vol_ref_count < vol_ref_period)
  {
    // incremental average until we have vol_ref_period samples
    g_vol_ref = (g_vol_ref * (double)g_vol_ref_count + current_atr) / (double)(g_vol_ref_count + 1);
    g_vol_ref_count++;
  }
  else
  {
    // slow EMA to allow drift without being too reactive
    double alpha = 1.0 / MathMax(50.0, vol_ref_period); // very slow; ensures stability
    g_vol_ref = (1.0 - alpha) * g_vol_ref + alpha * current_atr;
  }

  if(g_vol_ref <= 0.0) return 1.0;
  return current_atr / g_vol_ref;
}

//+------------------------------------------------------------------+
//| Adjusted MA Periods                                               |
//+------------------------------------------------------------------+
void GetAdjustedMAPeriods(double vol_ratio, int &short_period, int &long_period)
{
  double factor = 1.0 + ma_vol_alpha * (vol_ratio - 1.0);
  short_period = (int)MathRound(ma_short_base * factor);
  long_period  = (int)MathRound(ma_long_base  * factor);
  short_period = MathMax(2, short_period);
  long_period  = MathMax(short_period + 1, long_period);
}

//+------------------------------------------------------------------+
//| Adjusted RSI thresholds                                           |
//+------------------------------------------------------------------+
void GetAdjustedRSIThresholds(double vol_ratio, double &rsi_ob, double &rsi_os)
{
  // change by up to roughly 10 * beta per 1.0 vol_ratio delta
  rsi_ob = rsi_sell_base + rsi_vol_beta * (vol_ratio - 1.0) * 10.0;
  rsi_os = rsi_buy_base  - rsi_vol_beta * (vol_ratio - 1.0) * 10.0;

  // clamp to safety floors/ceilings
  rsi_ob = Clamp(rsi_ob, rsi_sell_base, rsi_sell_max);
  rsi_os = Clamp(rsi_os, rsi_buy_min, rsi_buy_base);
}

//+------------------------------------------------------------------+
//| Adjusted SL/TP distances based on ATR and vol ratio               |
//+------------------------------------------------------------------+
void GetAdjustedSLTP(double atr_value, double vol_ratio, double &sl_dist, double &tp_dist)
{
  sl_dist = atr_value * sl_base_mult * (1.0 + sl_vol_gamma * (vol_ratio - 1.0));
  tp_dist = atr_value * tp_base_mult * (1.0 + tp_vol_gamma_tp * (vol_ratio - 1.0));
  // ensure positive
  sl_dist = MathMax(0.0001, sl_dist);
  tp_dist = MathMax(0.0001, tp_dist);
}

//+------------------------------------------------------------------+
//| Adjusted Bollinger deviation                                      |
//+------------------------------------------------------------------+
double GetAdjustedBBDev(double vol_ratio)
{
  double dev = bb_dev_base * (1.0 + bb_vol_delta * (vol_ratio - 1.0));
  return MathMax(0.1, dev);
}

//+------------------------------------------------------------------+
//| Example OnTick integration (self-contained signal computation)     |
//+------------------------------------------------------------------+
void OnTick()
{
  // This module is intended to be included as a phase3 enhancement.
  // It computes adjusted parameters and demonstrates usage.

  // basic market data samples
  double atr_value = iATR(NULL, PERIOD_CURRENT, atr_period, 1); // last completed bar
  if(atr_value <= 0.0) atr_value = iATR(NULL, PERIOD_CURRENT, atr_period, 0);
  if(atr_value <= 0.0) return; // cannot proceed

  // fetch regime info placeholder: the real system will call GetVolatilityRegime()
  // Here we do not call external files; assume regime detection exists in main module.

  // compute adaptive params if enabled
  int ma_short = ma_short_base;
  int ma_long  = ma_long_base;
  double rsi_ob = rsi_sell_base;
  double rsi_os = rsi_buy_base;
  double sl_dist = atr_value * sl_base_mult;
  double tp_dist = atr_value * tp_base_mult;
  double bb_dev = bb_dev_base;
  double vol_ratio = 1.0;

  if(use_adaptive_params)
  {
    vol_ratio = GetVolRatio(atr_value);
    GetAdjustedMAPeriods(vol_ratio, ma_short, ma_long);
    GetAdjustedRSIThresholds(vol_ratio, rsi_ob, rsi_os);
    GetAdjustedSLTP(atr_value, vol_ratio, sl_dist, tp_dist);
    bb_dev = GetAdjustedBBDev(vol_ratio);
  }

  // Example: compute MA values used for crossover signals
  double ma_short_val = iMA(NULL, PERIOD_CURRENT, ma_short, 0, MODE_EMA, PRICE_CLOSE, 1);
  double ma_long_val  = iMA(NULL, PERIOD_CURRENT, ma_long, 0, MODE_EMA, PRICE_CLOSE, 1);

  // Example: RSI value
  double rsi_val = iRSI(NULL, PERIOD_CURRENT, rsi_period, PRICE_CLOSE, 1);

  // Compose a short Comment for display to help debugging — main system may append this
  string info = StringFormat("Phase3: vol_ratio=%.3f ma=%d/%d rsi=%.1f ob/os=%.1f/%.1f SL=%.4f TP=%.4f BBdev=%.2f",
                             vol_ratio, ma_short, ma_long, rsi_val, rsi_ob, rsi_os, sl_dist, tp_dist, bb_dev);
  Comment(info);

  // Signals demonstration (do NOT open trades here in this module)
  // Real signal handling should be in main expert using returned adjusted params.
}

//+------------------------------------------------------------------+
//| Utility: expose a function to get current adjusted parameters     |
//| so the main expert can call Phase3_GetAdjustedParams() to obtain |
//| a struct/values to use when generating signals.                 |
//+------------------------------------------------------------------+

void Phase3_GetAdjustedParams(int &out_ma_short, int &out_ma_long, double &out_rsi_ob, double &out_rsi_os,
                               double &out_sl_dist, double &out_tp_dist, double &out_bb_dev, double &out_vol_ratio)
{
  double atr_value = iATR(NULL, PERIOD_CURRENT, atr_period, 1);
  if(atr_value <= 0.0) atr_value = iATR(NULL, PERIOD_CURRENT, atr_period, 0);
  if(atr_value <= 0.0)
  {
    // fall back to base values
    out_ma_short = ma_short_base;
    out_ma_long  = ma_long_base;
    out_rsi_ob = rsi_sell_base; out_rsi_os = rsi_buy_base;
    out_sl_dist = atr_value * sl_base_mult; out_tp_dist = atr_value * tp_base_mult;
    out_bb_dev = bb_dev_base; out_vol_ratio = 1.0;
    return;
  }

  out_ma_short = ma_short_base;
  out_ma_long  = ma_long_base;
  out_rsi_ob = rsi_sell_base; out_rsi_os = rsi_buy_base;
  out_sl_dist = atr_value * sl_base_mult; out_tp_dist = atr_value * tp_base_mult;
  out_bb_dev = bb_dev_base; out_vol_ratio = 1.0;

  if(use_adaptive_params)
  {
    out_vol_ratio = GetVolRatio(atr_value);
    GetAdjustedMAPeriods(out_vol_ratio, out_ma_short, out_ma_long);
    GetAdjustedRSIThresholds(out_vol_ratio, out_rsi_ob, out_rsi_os);
    GetAdjustedSLTP(atr_value, out_vol_ratio, out_sl_dist, out_tp_dist);
    out_bb_dev = GetAdjustedBBDev(out_vol_ratio);
  }
}

//+------------------------------------------------------------------+
// End of Ma_Rsi_Phase3.mq5
