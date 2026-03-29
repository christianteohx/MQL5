#property copyright ""
#property version   "1.00"
#property strict

// Regime detector module for Ma_Rsi EA (Phase1)

input int atr_period = 14;
input int vol_lookback = 100;
input double vol_low_pct = 0.33;
input double vol_high_pct = 0.66;
input double regime_smooth_alpha = 0.92; // alpha for previous (higher alpha -> more inertia)
input int min_regime_bars = 5;

struct RegimeState
{
  int regime; // 0=low,1=mid,2=high
  double atr_pct; // raw ATR percentile
  double regime_raw; // smoothed regime value (continuous)
  bool changed; // true if regime changed this bar
  int bars_in_regime; // bars since last regime change
};

// Persistent variables
static int atr_handle = INVALID_HANDLE;
static double prev_regime_raw = 1.0; // start in mid
static int bars_since_switch = 0;

// Utility: simple insertion sort for small arrays
void SortArray(double &arr[], int count)
{
  for(int i=1;i<count;i++)
  {
    double key = arr[i];
    int j = i-1;
    while(j>=0 && arr[j]>key)
    {
      arr[j+1]=arr[j];
      j--;
    }
    arr[j+1]=key;
  }
}

// Compute percentile rank of value within sorted window (0..1)
double PercentileFromSorted(const double &sorted[], int count, double value)
{
  if(count<=1) return 0.5;
  // find first index greater than value
  int lo=0, hi=count-1;
  if(value<=sorted[0]) return 0.0;
  if(value>=sorted[count-1]) return 1.0;
  int idx=0;
  for(int i=0;i<count;i++)
  {
    if(sorted[i]>value)
    {
      idx=i;
      break;
    }
  }
  // linear interpolation between sorted[idx-1] and sorted[idx]
  double lower = sorted[idx-1];
  double upper = sorted[idx];
  if(upper==lower) return (double)idx/(count-1);
  double t = (value - lower)/(upper-lower);
  double frac = ((double)(idx-1) + t)/(double)(count-1);
  return frac;
}

// Main function: call each tick/bar to update regime_state
RegimeState GetVolatilityRegime()
{
  RegimeState state;
  state.regime = 1;
  state.atr_pct = 0.5;
  state.regime_raw = prev_regime_raw;
  state.changed = false;
  state.bars_in_regime = bars_since_switch;

  // Ensure ATR handle
  if(atr_handle==INVALID_HANDLE)
  {
    atr_handle = iATR(_Symbol,PERIOD_CURRENT,atr_period);
    if(atr_handle==INVALID_HANDLE)
    {
      Print("GetVolatilityRegime: Failed to create ATR handle");
      return state;
    }
  }

  // Copy ATR values: need vol_lookback + 1 to include current
  int need = MathMax(vol_lookback, atr_period) + 5; // small guard
  if(need < vol_lookback + 1) need = vol_lookback + 1;
  double atr_buffer[];
  ArrayResize(atr_buffer, vol_lookback+1);
  int copied = CopyBuffer(atr_handle, 0, 0, vol_lookback+1, atr_buffer);
  if(copied<=0)
  {
    Print("GetVolatilityRegime: CopyBuffer returned ", copied);
    return state;
  }

  // Current ATR is atr_buffer[0]; build window of last vol_lookback values (including current)
  int window_count = MathMin(vol_lookback+1, copied);
  double window[];
  ArrayResize(window, window_count);
  for(int i=0;i<window_count;i++) window[i]=atr_buffer[i];

  // Build sorted copy
  double sorted[];
  ArrayResize(sorted, window_count);
  for(int i=0;i<window_count;i++) sorted[i]=window[i];
  SortArray(sorted, window_count);

  double current_atr = window[0];
  double atr_pct = PercentileFromSorted(sorted, window_count, current_atr);

  // Map percentile into raw regime continuous value: 0..1 where 0=low,1=high
  double raw_regime = atr_pct; // continuous

  // Smooth via EMA: regime_smoothed = alpha*prev + (1-alpha)*raw
  double smoothed = regime_smooth_alpha * prev_regime_raw + (1.0 - regime_smooth_alpha) * raw_regime;

  // Determine discrete regime
  int new_regime = 1;
  if(atr_pct < vol_low_pct) new_regime = 0;
  else if(atr_pct > vol_high_pct) new_regime = 2;
  else new_regime = 1;

  // Enforce min dwell: only allow switch if bars_since_switch >= min_regime_bars
  bool allow_switch = (bars_since_switch >= min_regime_bars);
  static int last_discrete_regime = 1;
  if(new_regime != last_discrete_regime)
  {
    if(allow_switch)
    {
      last_discrete_regime = new_regime;
      bars_since_switch = 0;
      state.changed = true;
      PrintFormat("Regime change -> %d at bar time %s, ATR_pct=%.3f", new_regime, TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS), atr_pct);
    }
    else
    {
      // suppress change, keep previous
      new_regime = last_discrete_regime;
      state.changed = false;
    }
  }
  else
  {
    state.changed = false;
  }

  // update counters and persisted values
  bars_since_switch++;
  state.bars_in_regime = bars_since_switch;
  state.atr_pct = atr_pct;
  state.regime_raw = smoothed;
  state.regime = last_discrete_regime;

  // Persist smoothed value
  prev_regime_raw = smoothed;

  // Display a small comment on chart
  string regime_names[3] = {"LOW","MID","HIGH"};
  Comment("VolRegime: ", regime_names[state.regime], "  ATR%: ", DoubleToString(state.atr_pct,3), "\nBarsInRegime: ", IntegerToString(state.bars_in_regime));

  return state;
}

// Cleanup handle on deinit
void CleanupRegime()
{
  if(atr_handle!=INVALID_HANDLE)
  {
    IndicatorRelease(atr_handle);
    atr_handle = INVALID_HANDLE;
  }
}

// Provide OnInit/OnDeinit wrappers if compiled as standalone
int OnInit()
{
  // initialize
  atr_handle = iATR(_Symbol,PERIOD_CURRENT,atr_period);
  prev_regime_raw = 1.0;
  bars_since_switch = min_regime_bars; // allow immediate evaluation
  Print("Ma_Rsi_Phase1: Regime module initialized");
  return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
  CleanupRegime();
}

void OnTick()
{
  // Call detector each tick
  RegimeState s = GetVolatilityRegime();
}
