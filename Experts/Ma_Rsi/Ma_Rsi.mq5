//+------------------------------------------------------------------+
//|                                                         Test.mq5 |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#include <MyInclude/ChartHelpers.mqh>
#include <MyInclude/CommonEnums.mqh>
#include <MyInclude/IndicatorHelpers.mqh>
#include <MyInclude/TesterFunctions.mqh>
#include <MyInclude/TradeManagement.mqh>
#include <Trade/AccountInfo.mqh>
#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| Global Variables                                                 |
//+------------------------------------------------------------------+
int first_ema_handle;       // Handle First EMA
double first_ema_buffer[];  // Buffer First EMA

int second_ema_handle;       // Handle second EMA
double second_ema_buffer[];  // Buffer second EMA

int third_ema_handle;       // Handle third EMA
double third_ema_buffer[];  // Buffer third EMA

int rsi_handle;       // Handle RSI
double rsi_buffer[];  // Buffer RSI

int macd_handle;              // Handle MACD
double macd_main_buffer[];    // MACD Main Buffer
double macd_signal_buffer[];  // MACD Signal Buffer

int adx_handle;           // Handle ADX
double adx_buffer[];      // ADX Main Buffer
double DI_plusBuffer[];   // ADX Plus Buffer
double DI_minusBuffer[];  // ADX Minus Buffer

int atr_handle;       // Handle ATR
double atr_buffer[];  // Buffer ATR

int magic_number = 50357114;  // Magic number
double contract_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
double points = 1 / contract_size;                        // Point
int decimal = SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);  // Decimal

double totalWeight = 0.0;           // Total weight for all indicators
double normalizedWeightMa = 0.0;    // Normalized weight for MA
double normalizedWeightRsi = 0.0;   // Normalized weight for RSI
double normalizedWeightMacd = 0.0;  // Normalized weight for MACD
double normalizedWeightAdx = 0.0;   // Normalized weight for ADX
double normalizedWeightAtr = 0.0;   // Normalized weight for ATR

MqlRates candle[];  // Variable for storing candles
MqlTick tick;       // Variable for storing ticks

CTrade ExtTrade;
closePosition last_close_position;

//+------------------------------------------------------------------+
//| Input Parameters (keep all inputs here)                          |
//+------------------------------------------------------------------+
sinput string s0;  //-----------------Strategy-----------------
input TICKER ticker = BTCUSD;
input MA ma_strategy = TRIPLE_MA;
input double weightMA = 0.4;  // Weight for MA strategy
input RSI rsi_strategy = LIMIT;
input double weightRSI = 0.3;  // Weight for RSI strategy
input MACD macd_strategy = HIST;
input double weightMACD = 0.2;  // Weight for MACD strategy
input ADX adx_strategy = USE_ADX;
input double weightADX = 0.1;  // Weight for ADX strategy
input ATR atr_strategy = USE_ATR;
input double weightATR = 0.1;  // Weight for ATR strategy
input RISK_MANAGEMENT risk_management = OPTIMIZED;

sinput string moving_average;      //-----------------Moving Average-----------------
input int first_ema_period = 13;   // first EMA period
input int second_ema_period = 48;  // second EMA period
input int third_ema_period = 200;  // third EMA period

sinput string rsi;              //-----------------RSI-----------------
input int rsi_period = 14;      // RSI period
input int rsi_overbought = 70;  // RSI overbought level
input int rsi_oversold = 30;    // RSI oversold level

sinput string macd;         //-----------------MACD-----------------
input int macd_fast = 12;   // MACD Fast
input int macd_slow = 26;   // MACD Slow
input int macd_period = 9;  // MACD Period

sinput string adx;             //-----------------ADX-----------------
input int adx_period = 14;     // ADX period
input int adx_diff = 20;       // ADX difference
input int adx_threshold = 25;  // ADX threshold

sinput string atr;                     //-----------------ATR-----------------
input int atr_period = 14;             // ATR period for volatility measurement
input double atr_sl_multiplier = 2.0;  // Multiplier for Stop Loss based on ATR
input double atr_tp_multiplier = 3.0;  // Multiplier for Take Profit based on ATR
input double min_volatility = 0.5;     // Minimum volatility threshold (in ATR points) to trade
input double max_volatility = 5.0;     // Maximum volatility threshold (in ATR points) to pause trading

sinput string risk;                 //-----------------Risk Management-----------------
input bool use_threshold = true;    // Use threshold
input double buy_threshold = 0.5;   // Buy Threshold
input double sell_threshold = 0.5;  // Sell Threshold
input double SL = 10;               // Stop Loss (fixed, but overridden by ATR)
input double TP = 10;               // Take Profit (fixed, but overridden by ATR)
input int percent_change = 5;       // Percent Change before re-buying
input bool trailing_sl = true;      // Trailing Stop Loss
input int max_risk = 10;            // Maximum risk (%) per trade
input double decrease_factor = 3;   // Decrease factor
input bool boost = false;           // Use high risk until target reached
input double boost_target = 5000;   // Boost target

sinput string test;                                            //-----------------Test-----------------
input TEST_CRITERION test_criterion = R_SQUARED;  // Test criterion

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
    Print("Points: ", points);
    Print("Contract Size: ", SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE));
    Print("Decimal: ", decimal);

    if (ma_strategy == SINGLE_MA) {
        if (first_ema_period < 1) {
            Alert("Invalid EMA period");
            return -1;
        }
    } else if (ma_strategy == DOUBLE_MA) {
        if (first_ema_period >= second_ema_period) {
            Alert("Invalid EMA period");
            return -1;
        }
    } else if (ma_strategy == TRIPLE_MA) {
        if (first_ema_period >= second_ema_period || second_ema_period >= third_ema_period) {
            Alert("Invalid EMA period");
            return -1;
        }
    }

    if (rsi_strategy != NO_RSI) {
        if (rsi_overbought < rsi_oversold) {
            Alert("Invalid RSI levels");
            return -1;
        }
    }

    if (macd_strategy != NO_MACD) {
        if (macd_fast >= macd_slow) {
            Alert("Invalid MACD levels");
            return -1;
        }
    }

    if (adx_strategy != NO_ADX) {
        if (adx_period < 1) {
            Alert("Invalid ADX period");
            return -1;
        }
    }

    if (atr_strategy != NO_ATR) {
        if (atr_period < 1) {
            Alert("Invalid ATR period");
            return -1;
        }
    }

    ExtTrade.SetExpertMagicNumber(magic_number);
    ExtTrade.SetDeviationInPoints(10);
    ExtTrade.SetTypeFilling(ORDER_FILLING_FOK);

    first_ema_handle = iCustom(_Symbol, Period(), "Examples/Custom Moving Average", first_ema_period, 0, MODE_EMA, clrRed, PRICE_CLOSE);
    second_ema_handle = iCustom(_Symbol, Period(), "Examples/Custom Moving Average", second_ema_period, 0, MODE_EMA, clrBlue, PRICE_CLOSE);
    third_ema_handle = iCustom(_Symbol, Period(), "Examples/Custom Moving Average", third_ema_period, 0, MODE_EMA, clrYellow, PRICE_CLOSE);

    rsi_handle = iRSI(_Symbol, _Period, rsi_period, PRICE_CLOSE);
    macd_handle = iMACD(_Symbol, _Period, macd_fast, macd_slow, macd_period, PRICE_CLOSE);
    adx_handle = iADX(_Symbol, _Period, adx_period);
    atr_handle = iATR(_Symbol, _Period, atr_period);

    // Check if the indicators were created successfully
    if (first_ema_handle == INVALID_HANDLE || second_ema_handle == INVALID_HANDLE ||
        third_ema_handle == INVALID_HANDLE || rsi_handle == INVALID_HANDLE ||
        macd_handle == INVALID_HANDLE || adx_handle == INVALID_HANDLE ||
        atr_handle == INVALID_HANDLE) {
        Alert("Error trying to create Handles for indicator - error: ", GetLastError(), "!");
        return INIT_FAILED;
    }

    // Check active indicators and sum their weights
    if (ma_strategy != NO_MA) {
        totalWeight += weightMA;
    }

    if (rsi_strategy != NO_RSI) {
        totalWeight += weightRSI;
    }

    if (macd_strategy != NO_MACD) {
        totalWeight += weightMACD;
    }

    if (adx_strategy != NO_ADX) {
        totalWeight += weightADX;
    }

    if (atr_strategy != NO_ATR) {
        totalWeight += weightATR;  // Include ATR weight if used
    }

    // Normalize weights for active indicators
    if (ma_strategy != NO_MA) {
        normalizedWeightMa = weightMA / totalWeight;
    }

    if (rsi_strategy != NO_RSI) {
        normalizedWeightRsi = weightRSI / totalWeight;
    }

    if (macd_strategy != NO_MACD) {
        normalizedWeightMacd = weightMACD / totalWeight;
    }

    if (adx_strategy != NO_ADX) {
        normalizedWeightAdx = weightADX / totalWeight;
    }

    if (atr_strategy != NO_ATR) {
        normalizedWeightAtr = weightATR / totalWeight;  // Add normalized weight for ATR
    }

    last_close_position.buySell = NULL;
    last_close_position.price = SymbolInfoDouble(_Symbol, SYMBOL_BID);

    CopyRates(_Symbol, _Period, 0, 4, candle);
    ArraySetAsSeries(candle, true);

    ChartIndicatorAdd(0, 0, first_ema_handle);
    ChartIndicatorAdd(0, 0, second_ema_handle);
    ChartIndicatorAdd(0, 0, third_ema_handle);
    ChartIndicatorAdd(0, 1, rsi_handle);
    ChartIndicatorAdd(0, 2, macd_handle);
    ChartIndicatorAdd(0, 3, adx_handle);
    ChartIndicatorAdd(0, 4, atr_handle); 

    SetIndexBuffer(0, first_ema_buffer, INDICATOR_DATA);
    SetIndexBuffer(1, second_ema_buffer, INDICATOR_DATA);
    SetIndexBuffer(2, third_ema_buffer, INDICATOR_DATA);
    SetIndexBuffer(3, rsi_buffer, INDICATOR_DATA);
    SetIndexBuffer(4, macd_main_buffer, INDICATOR_DATA);
    SetIndexBuffer(5, macd_signal_buffer, INDICATOR_DATA);
    SetIndexBuffer(6, adx_buffer, INDICATOR_DATA);
    SetIndexBuffer(7, DI_plusBuffer, INDICATOR_DATA);
    SetIndexBuffer(8, DI_minusBuffer, INDICATOR_DATA);
    SetIndexBuffer(9, atr_buffer, INDICATOR_DATA);

    return (INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    closeAllTrade();

    IndicatorRelease(first_ema_handle);
    IndicatorRelease(second_ema_handle);
    IndicatorRelease(third_ema_handle);
    IndicatorRelease(rsi_handle);
    IndicatorRelease(macd_handle);
    IndicatorRelease(adx_handle);
    IndicatorRelease(atr_handle);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
    if (!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) {
        Print("Trading is not allowed on this terminal.");
        return;
    }

    if (CopyBuffer(first_ema_handle, 0, 0, 4, first_ema_buffer) < 4 ||
        CopyBuffer(second_ema_handle, 0, 0, 4, second_ema_buffer) < 4 ||
        CopyBuffer(third_ema_handle, 0, 0, 4, third_ema_buffer) < 4 ||
        CopyBuffer(rsi_handle, 0, 0, 4, rsi_buffer) < 4 ||
        CopyBuffer(macd_handle, 0, 0, 4, macd_main_buffer) < 4 ||
        CopyBuffer(macd_handle, 1, 0, 4, macd_signal_buffer) < 4 ||
        CopyBuffer(adx_handle, 0, 0, 4, adx_buffer) < 4 ||
        CopyBuffer(adx_handle, 1, 0, 4, DI_plusBuffer) < 4 ||
        CopyBuffer(adx_handle, 2, 0, 4, DI_minusBuffer) < 4 ||
        CopyBuffer(atr_handle, 0, 0, 4, atr_buffer) < 4) {
        Print("Failed to copy indicator data - error: ", GetLastError());
        return;
    }

    // Copy candle data
    if (CopyRates(_Symbol, _Period, 0, 4, candle) < 4) {
        Print("Failed to copy rates - error: ", GetLastError());
        return;
    }

    // Set arrays as time series
    ArraySetAsSeries(candle, true);
    ArraySetAsSeries(first_ema_buffer, true);
    ArraySetAsSeries(second_ema_buffer, true);
    ArraySetAsSeries(third_ema_buffer, true);
    ArraySetAsSeries(rsi_buffer, true);
    ArraySetAsSeries(macd_main_buffer, true);
    ArraySetAsSeries(macd_signal_buffer, true);
    ArraySetAsSeries(adx_buffer, true);
    ArraySetAsSeries(DI_plusBuffer, true);
    ArraySetAsSeries(DI_minusBuffer, true);
    ArraySetAsSeries(atr_buffer, true);

    // Get current tick data
    if (!SymbolInfoTick(_Symbol, tick)) {
        Print("Failed to get tick data - error: ", GetLastError());
        return;
    }

    // Initialize confidence variables
    double buy_confidence = 0.0, sell_confidence = 0.0;
    double confidenceMA = 0.0, confidenceRSI = 0.0, confidenceMACD = 0.0, confidenceADX = 0.0, confidenceATR = 0.0;

    // MA Strategy Logic
    bool buy_single_ma = candle[1].open < first_ema_buffer[1] && candle[1].close > first_ema_buffer[1];
    bool sell_single_ma = candle[1].open > first_ema_buffer[1] && candle[1].close < first_ema_buffer[1];
    bool buy_ma_cross = first_ema_buffer[0] > second_ema_buffer[0] && first_ema_buffer[2] < second_ema_buffer[2];
    bool sell_ma_cross = first_ema_buffer[0] < second_ema_buffer[0] && first_ema_buffer[2] > second_ema_buffer[2];
    bool buy_triple_ma = first_ema_buffer[0] > third_ema_buffer[0] && second_ema_buffer[0] > third_ema_buffer[0];
    bool sell_triple_ma = first_ema_buffer[0] < third_ema_buffer[0] && second_ema_buffer[0] < third_ema_buffer[0];
    bool Buy = false, Sell = false;

    if (ma_strategy == SINGLE_MA) {
        Buy = buy_single_ma;
        Sell = sell_single_ma;
        confidenceMA = buy_single_ma ? 1.0 : (sell_single_ma ? -1.0 : 0.0);
    } else if (ma_strategy == DOUBLE_MA) {
        Buy = buy_ma_cross;
        Sell = sell_ma_cross;
        confidenceMA = buy_ma_cross ? 1.0 : (sell_ma_cross ? -1.0 : 0.0);
    } else if (ma_strategy == TRIPLE_MA) {
        Buy = buy_ma_cross && buy_triple_ma;
        Sell = sell_ma_cross && sell_triple_ma;
        confidenceMA = (buy_ma_cross && buy_triple_ma) ? 1.0 : ((sell_ma_cross && sell_triple_ma) ? -1.0 : 0.0);
    }

    // RSI Strategy Logic (with gradient confidence)
    bool buy_rsi = false, sell_rsi = false;
    if (rsi_strategy == COMPARISON) {
        buy_rsi = rsi_buffer[0] > rsi_buffer[1];
        sell_rsi = rsi_buffer[0] < rsi_buffer[1];
        confidenceRSI = buy_rsi ? 1.0 : (sell_rsi ? -1.0 : 0.0);
    } else if (rsi_strategy == LIMIT) {
        if (rsi_buffer[0] < rsi_oversold) {
            buy_rsi = true;
            confidenceRSI = 1.0;
        } else if (rsi_buffer[0] > rsi_overbought) {
            sell_rsi = true;
            confidenceRSI = -1.0;
        } else {
            // Gradient confidence between oversold and overbought
            confidenceRSI = (rsi_oversold - rsi_buffer[0]) / (rsi_oversold - rsi_overbought);
        }
    }

    if (rsi_strategy != NO_RSI) {
        Buy = Buy && buy_rsi;
        Sell = Sell && sell_rsi;
    }

    // MACD Strategy Logic
    bool buy_macd = false, sell_macd = false;
    if (macd_strategy == SIGNAL) {
        buy_macd = macd_main_buffer[0] > macd_signal_buffer[0] && macd_main_buffer[2] < macd_signal_buffer[2];
        sell_macd = macd_main_buffer[0] < macd_signal_buffer[0] && macd_main_buffer[2] > macd_signal_buffer[2];
        confidenceMACD = buy_macd ? 1.0 : (sell_macd ? -1.0 : 0.0);
    } else if (macd_strategy == HIST) {
        double hist = macd_main_buffer[0] - macd_signal_buffer[0];
        buy_macd = hist > 0;
        sell_macd = hist < 0;
        confidenceMACD = MathMin(1.0, MathMax(-1.0, hist * 10000));  // Scale based on histogram size
    }

    if (macd_strategy != NO_MACD) {
        Buy = Buy && buy_macd;
        Sell = Sell && sell_macd;
    }

    // ADX Strategy Logic (with trend strength)
    bool buy_adx = false, sell_adx = false;
    if (adx_strategy == USE_ADX) {
        double di_diff = DI_plusBuffer[0] - DI_minusBuffer[0];
        buy_adx = di_diff > adx_diff && adx_buffer[0] > adx_threshold;
        sell_adx = -di_diff > adx_diff && adx_buffer[0] > adx_threshold;
        confidenceADX = buy_adx ? 1.0 : (sell_adx ? -1.0 : 0.0);
    }

    if (adx_strategy != NO_ADX) {
        Buy = Buy && buy_adx;
        Sell = Sell && sell_adx;
    }

    // Calculate weighted confidence
    if (ma_strategy != NO_MA) {
        buy_confidence += confidenceMA * normalizedWeightMa;
        sell_confidence += -confidenceMA * normalizedWeightMa;
    }
    if (rsi_strategy != NO_RSI) {
        buy_confidence += confidenceRSI * normalizedWeightRsi;
        sell_confidence += -confidenceRSI * normalizedWeightRsi;
    }
    if (macd_strategy != NO_MACD) {
        buy_confidence += confidenceMACD * normalizedWeightMacd;
        sell_confidence += -confidenceMACD * normalizedWeightMacd;
    }
    if (adx_strategy != NO_ADX) {
        buy_confidence += confidenceADX * normalizedWeightAdx;
        sell_confidence += -confidenceADX * normalizedWeightAdx;
    }

    // Normalize confidence to [0, 1]
    buy_confidence = MathMax(0.0, MathMin(1.0, buy_confidence));
    sell_confidence = MathMax(0.0, MathMin(1.0, sell_confidence));

    // Trading logic
    bool newBar = isNewBar();
    bool tradeTime = IsTradingTime();  // Remove override unless intentional

    if (tradeTime && newBar) {
        if (!use_threshold) {
            trade(Buy, Sell);
        } else {
            thresholdTrade(buy_confidence, sell_confidence, buy_threshold, sell_threshold);
        }
    }

    // Risk management
    if (percent_change > 0 && !CheckForOpenTrade()) {
        CheckPercentChange();
    }

    if (trailing_sl) {
        updateSLTP();
    }

    // Balance check (clarified)
    // double min_balance = 1000.0;  // Could be an input: input double minBalance = 1000.0;
    // if (AccountInfoDouble(ACCOUNT_BALANCE) < min_balance) {
    //     Print("Balance below minimum threshold (", min_balance, "). Removing EA.");
    //     ExpertRemove();
    // }

    if (AccountInfoDouble(ACCOUNT_BALANCE) < (SymbolInfoDouble(_Symbol, SYMBOL_BID) * 0.01 / 3.67)) {
        Print("Balance below minimum threshold. Removing EA.");
        ExpertRemove();
    }
}

//+------------------------------------------------------------------+
//| Expert tester function                                           |
//+------------------------------------------------------------------+
double OnTester() {
    double score = 0.0;

    if (test_criterion == BALANCExRECOVERYxSHARPE) {
        score = GetBalanceRecoverySharpeRatio();
    } else if (test_criterion == MAXIMUM_FAVORABLE_EXCURSION) {
        score = GetMaximumFavorableExcursionOnBalanceCurve();
    } else if (test_criterion == MEAN_ABSOLUTE_ERROR) {
        score = GetMeanAbsoluteErrorOnBalanceCurve();
    } else if (test_criterion == ROOT_MEAN_SQUARED_ERROR) {
        double rmse = GetRootMeanSquareErrorOnBalanceCurve(TP);
        double offset = TesterStatistics(STAT_INITIAL_DEPOSIT) * 0.001;  // 0.1% of initial deposit
        double fitness = 1.0 / (rmse + offset);
        score = fitness;
    } else if (test_criterion == R_SQUARED) {
        score = GetR2onBalanceCurve();
    } else if (test_criterion == CUSTOMIZED_MAX) {
        score = customized_max();
    } else if (test_criterion == WIN_RATE) {
        double totalTrades = TesterStatistics(STAT_TRADES);       // Total number of trades
        double wonTrades = TesterStatistics(STAT_PROFIT_TRADES);  // Number of winning trades

        if (TesterStatistics(STAT_TRADES) == 0) {
            score = 0;
        } else {
            score = wonTrades / totalTrades;
        }
    } else if (test_criterion == BALANCE_DRAWDOWN) {
        double profit = TesterStatistics(STAT_PROFIT);
        double dd = TesterStatistics(STAT_BALANCE_DDREL_PERCENT) / 100.0;
        score = profit * (1.0 - dd);  // Penalize drawdown consistently
    } else if (test_criterion == HIGH_GROWTH) {
        score = highGrowth();
    } else if (test_criterion == PROFIT_MINUS_LOSS) {
        score = profit_minus_loss();
    } else if (test_criterion == PROFIT_WITH_TIEBREAKER) {
        score = profit_with_tiebreaker();
    } else if (test_criterion == GROWTH_WITH_DRAWDOWN_PENALTY) {  // Fixed syntax error
        score = GrowthWithDrawdownPenalty();
    } else if (test_criterion == NONE) {
        score = none();
    }

    return score;
}