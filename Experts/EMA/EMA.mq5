//+------------------------------------------------------------------+
//|                                                            a.mq5 |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Ltd."
#property link "https://www.mql5.com"
#property version "1.00"
//+------------------------------------------------------------------+
//| Include                                                          |
//+------------------------------------------------------------------+
#include <Expert/Expert.mqh>
//--- available signals
#include <Expert/Signal/SignalMA.mqh>
//--- available trailing
#include <Expert/Trailing/TrailingFixedPips.mqh>
//--- available money management
#include <Expert/Money/MoneySizeOptimized.mqh>

#include <Expert/Money/MoneyFixedRisk.mqh>
//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
//--- inputs for expert
string Expert_Title       = "EMA";   // Document name
ulong  Expert_MagicNumber = 12282;   //
bool   Expert_EveryTick   = false;   //
//--- inputs for main signal
input int Signal_ThresholdOpen  = 30;    // Signal threshold value to open
input int Signal_ThresholdClose = 100;   // Signal threshold value to close
// input double             Signal_PriceLevel     = 0.0;           // Price level to execute a deal
input double             Signal_StopLevel   = 50000.0;       // Stop Loss level (in points)
input double             Signal_TakeLevel   = 100000.0;      // Take Profit level (in points)
input int                Signal_Expiration  = 4;             // Expiration of pending orders (in bars)
input int                Signal_MA_PeriodMA = 40;            // Period of averaging
input int                Signal_MA_Shift    = 0;             // Time shift
input ENUM_MA_METHOD     Signal_MA_Method   = MODE_EMA;      // Method of averaging
input ENUM_APPLIED_PRICE Signal_MA_Applied  = PRICE_CLOSE;   // Prices series
input double             Signal_MA_Weight   = 1.0;           // Weight [0...1.0]
//--- inputs for trailing
input int Trailing_FixedPips_StopLevel   = 50;   // Stop Loss trailing level (in points)
input int Trailing_FixedPips_ProfitLevel = 50;   // Take Profit trailing level (in points)
//--- inputs for money
input double Money_SizeOptimized_DecreaseFactor = 3.0;     // Decrease factor
input double Money_FixedLot_Percent             = 100.0;   // Percent

input int Pattern_0 = 0;     // Pattern 0 weight (price on the necessary side from the indicator)
input int Pattern_1 = 0;     // Pattern 1 weight (price crossed the indicator with opposite direction)
input int Pattern_2 = 0;     // Pattern 2 weight (price crossed the indicator with the same direction)
input int Pattern_3 = 0;     // Pattern 3 weight (piercing)

//+------------------------------------------------------------------+
//| Global expert object                                             |
//+------------------------------------------------------------------+
CExpert ExtExpert;
//+------------------------------------------------------------------+
//| Initialization function of the expert                            |
//+------------------------------------------------------------------+
int OnInit() {
    //--- Initializing expert
    if(!ExtExpert.Init(Symbol(), Period(), Expert_EveryTick, Expert_MagicNumber)) {
        //--- failed
        printf(__FUNCTION__ + ": error initializing expert");
        ExtExpert.Deinit();
        return (INIT_FAILED);
    }
    //--- Creating signal
    CExpertSignal *signal = new CExpertSignal;
    if(signal == NULL) {
        //--- failed
        printf(__FUNCTION__ + ": error creating signal");
        ExtExpert.Deinit();
        return (INIT_FAILED);
    }
    //---
    ExtExpert.InitSignal(signal);
    signal.ThresholdOpen(Signal_ThresholdOpen);
    signal.ThresholdClose(Signal_ThresholdClose);
    // signal.PriceLevel(Signal_PriceLevel);
    signal.StopLevel(Signal_StopLevel);
    if(Signal_TakeLevel > 0)
        signal.TakeLevel(Signal_TakeLevel);
    signal.Expiration(Signal_Expiration);
    //--- Creating filter CSignalMA
    CSignalMA *filter0 = new CSignalMA;
    if(filter0 == NULL) {
        //--- failed
        printf(__FUNCTION__ + ": error creating filter0");
        ExtExpert.Deinit();
        return (INIT_FAILED);
    }
    signal.AddFilter(filter0);
    //--- Set filter parameters
    filter0.PeriodMA(Signal_MA_PeriodMA);
    // filter0.Shift(Signal_MA_Shift);
    filter0.Method(Signal_MA_Method);
    filter0.Applied(Signal_MA_Applied);
    // filter0.Weight(Signal_MA_Weight);
    if (Pattern_0 > 0)
        filter0.Pattern_0(Pattern_0);
    if (Pattern_1 > 0)
        filter0.Pattern_1(Pattern_1);
    if (Pattern_2 > 0)
        filter0.Pattern_2(Pattern_2);
    if (Pattern_3 > 0)
        filter0.Pattern_3(Pattern_3);

    // ExtExpert.InitSignal(filter0);

    //--- Creation of trailing object
    CTrailingFixedPips *trailing = new CTrailingFixedPips;
    if(trailing == NULL) {
        //--- failed
        printf(__FUNCTION__ + ": error creating trailing");
        ExtExpert.Deinit();
        return (INIT_FAILED);
    }
    //--- Add trailing to expert (will be deleted automatically))
    if(!ExtExpert.InitTrailing(trailing)) {
        //--- failed
        printf(__FUNCTION__ + ": error initializing trailing");
        ExtExpert.Deinit();
        return (INIT_FAILED);
    }
    //--- Set trailing parameters
    trailing.StopLevel(Trailing_FixedPips_StopLevel);
    trailing.ProfitLevel(Trailing_FixedPips_ProfitLevel);
    //--- Creation of money object
    CMoneyFixedRisk *money = new CMoneyFixedRisk;
    if(money == NULL) {
        //--- failed
        printf(__FUNCTION__ + ": error creating money");
        ExtExpert.Deinit();
        return (INIT_FAILED);
    }
    //--- Add money to expert (will be deleted automatically))
    if(!ExtExpert.InitMoney(money)) {
        //--- failed
        printf(__FUNCTION__ + ": error initializing money");
        ExtExpert.Deinit();
        return (INIT_FAILED);
    }
    //--- Set money parameters
    money.Percent(Money_FixedLot_Percent);
    //--- Check all trading objects parameters
    if(!ExtExpert.ValidationSettings()) {
        //--- failed
        ExtExpert.Deinit();
        return (INIT_FAILED);
    }
    //--- Tuning of all necessary indicators
    if(!ExtExpert.InitIndicators()) {
        //--- failed
        printf(__FUNCTION__ + ": error initializing indicators");
        ExtExpert.Deinit();
        return (INIT_FAILED);
    }
    //--- ok
    return (INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
//| Deinitialization function of the expert                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    ExtExpert.Deinit();
}
//+------------------------------------------------------------------+
//| "Tick" event handler function                                    |
//+------------------------------------------------------------------+
void OnTick() {
    ExtExpert.OnTick();
}
//+------------------------------------------------------------------+
//| "Trade" event handler function                                   |
//+------------------------------------------------------------------+
void OnTrade() {
    ExtExpert.OnTrade();
}
//+------------------------------------------------------------------+
//| "Timer" event handler function                                   |
//+------------------------------------------------------------------+
void OnTimer() {
    ExtExpert.OnTimer();
}
//+------------------------------------------------------------------+

