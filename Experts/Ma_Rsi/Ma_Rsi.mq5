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
input RISK_MANAGEMENT risk_management = OPTIMIZED;

sinput string s1;                  //-----------------Moving Average-----------------
input int first_ema_period = 13;   // first EMA period
input int second_ema_period = 48;  // second EMA period
input int third_ema_period = 200;  // third EMA period

sinput string s2;               //-----------------RSI-----------------
input int rsi_period = 14;      // RSI period
input int rsi_overbought = 70;  // RSI overbought level
input int rsi_oversold = 30;    // RSI oversold level

sinput string s3;           //-----------------MACD-----------------
input int macd_fast = 12;   // MACD Fast
input int macd_slow = 26;   // MACD Slow
input int macd_period = 9;  // MACD Period

sinput string s4;           //-----------------ADX-----------------
input int adx_period = 14;  // ADX period
input int adx_diff = 20;    // ADX difference

sinput string s5;                   //-----------------Risk Management-----------------
input bool use_threshold = true;    // Use threshold
input double buy_threshold = 0.5;   // Buy Threshold
input double sell_threshold = 0.5;  // Sell Threshold
input double SL = 10;               // Stop Loss
input double TP = 10;               // Take Profit
input int percent_change = 5;       // Percent Change before re-buying
input bool trailing_sl = true;      // Trailing Stop Loss
input int max_risk = 10;            // Maximum risk (%) per trade
input double decrease_factor = 3;   // Descrease factor
input bool boost = false;           // Use high risk until target reached
input double boost_target = 5000;   // Boost target

sinput string s6;                                 //-----------------Test-----------------
input TEST_CRITERION test_criterion = R_SQUARED;  // Test criterion

//+------------------------------------------------------------------+
//| Variable for indicators                                          |
//+------------------------------------------------------------------+
double totalWeight = 0.0;
double normalizedWeightMa = 0.0;    // Normalized weight for MA
double normalizedWeightRsi = 0.0;   // Normalized weight for RSI
double normalizedWeightMacd = 0.0;  // Normalized weight for MACD
double normalizedWeightAdx = 0.0;   // Normalized weight for ADX

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

//+------------------------------------------------------------------+
//| Variable for functions                                           |
//+------------------------------------------------------------------+
int magic_number = 50357114;  // Magic number
double contract_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
double points = 1 / contract_size;                        // Point
int decimal = SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);  // Decimal

MqlRates candle[];  // Variable for storing candles
MqlTick tick;       // Variable for storing ticks

CTrade ExtTrade;
closePosition last_close_position;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
    if (ticker == BTCUSD) {
    } else if (ticker == XAUUSD) {
        // points = 1;
        // contract_size = 0.1;
    }

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

    ExtTrade.SetExpertMagicNumber(magic_number);
    ExtTrade.SetDeviationInPoints(10);
    ExtTrade.SetTypeFilling(ORDER_FILLING_FOK);

    first_ema_handle = iCustom(_Symbol, Period(), "Examples/Custom Moving Average", first_ema_period, 0, MODE_EMA, clrRed, PRICE_CLOSE);
    second_ema_handle = iCustom(_Symbol, Period(), "Examples/Custom Moving Average", second_ema_period, 0, MODE_EMA, clrBlue, PRICE_CLOSE);
    third_ema_handle = iCustom(_Symbol, Period(), "Examples/Custom Moving Average", third_ema_period, 0, MODE_EMA, clrYellow, PRICE_CLOSE);

    rsi_handle = iRSI(_Symbol, _Period, rsi_period, PRICE_CLOSE);
    macd_handle = iMACD(_Symbol, _Period, macd_fast, macd_slow, macd_period, PRICE_CLOSE);
    adx_handle = iADX(_Symbol, _Period, adx_period);

    // Check if the EMA was created successfully
    if (first_ema_handle == INVALID_HANDLE || second_ema_handle == INVALID_HANDLE || third_ema_handle == INVALID_HANDLE || rsi_handle == INVALID_HANDLE || macd_handle == INVALID_HANDLE) {
        Alert("Error trying to create Handles for indicator - error: ", GetLastError(), "!");
        return -1;
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

    // normalize weights for active indicators
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

    SetIndexBuffer(0, first_ema_buffer, INDICATOR_DATA);
    SetIndexBuffer(1, second_ema_buffer, INDICATOR_DATA);
    SetIndexBuffer(2, third_ema_buffer, INDICATOR_DATA);
    SetIndexBuffer(3, rsi_buffer, INDICATOR_DATA);
    SetIndexBuffer(4, macd_main_buffer, INDICATOR_DATA);
    SetIndexBuffer(5, macd_signal_buffer, INDICATOR_DATA);
    SetIndexBuffer(6, adx_buffer, INDICATOR_DATA);
    SetIndexBuffer(7, DI_plusBuffer, INDICATOR_DATA);
    SetIndexBuffer(8, DI_minusBuffer, INDICATOR_DATA);

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
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
    if (!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) {
        Print("Trading is not allowed on this terminal.");
        return;
    }

    CopyBuffer(first_ema_handle, 0, 0, 4, first_ema_buffer);
    CopyBuffer(second_ema_handle, 0, 0, 4, second_ema_buffer);
    CopyBuffer(third_ema_handle, 0, 0, 4, third_ema_buffer);
    CopyBuffer(rsi_handle, 0, 0, 4, rsi_buffer);
    CopyBuffer(macd_handle, 0, 0, 4, macd_main_buffer);    // MACD Main Line
    CopyBuffer(macd_handle, 1, 0, 4, macd_signal_buffer);  // Signal Line
    CopyBuffer(adx_handle, 0, 0, 4, adx_buffer);           // ADX
    CopyBuffer(adx_handle, 1, 0, 4, DI_plusBuffer);        // DI+
    CopyBuffer(adx_handle, 2, 0, 4, DI_minusBuffer);       // DI-

    // Feed candle buffers with data
    CopyRates(_Symbol, _Period, 0, 4, candle);
    ArraySetAsSeries(candle, true);

    // Sort the data vector
    ArraySetAsSeries(first_ema_buffer, true);
    ArraySetAsSeries(second_ema_buffer, true);
    ArraySetAsSeries(third_ema_buffer, true);
    ArraySetAsSeries(rsi_buffer, true);
    ArraySetAsSeries(macd_main_buffer, true);
    ArraySetAsSeries(macd_signal_buffer, true);
    ArraySetAsSeries(adx_buffer, true);
    ArraySetAsSeries(DI_plusBuffer, true);
    ArraySetAsSeries(DI_minusBuffer, true);

    SymbolInfoTick(_Symbol, tick);

    double buy_confidence = 0.0;
    double sell_confidence = 0.0;
    double confidenceMA = 0.0;
    double confidenceRSI = 0.0;
    double confidenceMACD = 0.0;
    double confidenceADX = 0.0;

    bool buy_single_ma = candle[1].open < first_ema_buffer[1] && candle[1].close > first_ema_buffer[1];
    bool buy_ma_cross = first_ema_buffer[0] > second_ema_buffer[0] && first_ema_buffer[2] < second_ema_buffer[2];
    bool buy_triple_ma = first_ema_buffer[0] > third_ema_buffer[0] && second_ema_buffer[0] > third_ema_buffer[0];
    bool buy_rsi = true;
    bool buy_macd = true;
    bool buy_adx = true;

    bool sell_single_ma = candle[1].open > first_ema_buffer[1] && candle[1].close < first_ema_buffer[1];
    bool sell_ma_cross = first_ema_buffer[0] < second_ema_buffer[0] && first_ema_buffer[2] > second_ema_buffer[2];
    bool sell_triple_ma = first_ema_buffer[0] < third_ema_buffer[0] && second_ema_buffer[0] < third_ema_buffer[0];
    bool sell_rsi = true;
    bool sell_macd = true;
    bool sell_adx = true;

    if (rsi_strategy == COMPARISON) {
        buy_rsi = rsi_buffer[0] > rsi_buffer[1];
        sell_rsi = rsi_buffer[0] < rsi_buffer[1];
    } else if (rsi_strategy == LIMIT) {
        buy_rsi = rsi_buffer[0] < rsi_oversold;
        sell_rsi = rsi_buffer[0] > rsi_overbought;
    }

    if (macd_strategy == SIGNAL) {
        buy_macd = macd_main_buffer[0] > macd_signal_buffer[0] && macd_main_buffer[2] < macd_signal_buffer[2];
        sell_macd = macd_main_buffer[0] < macd_signal_buffer[0] && macd_main_buffer[2] > macd_signal_buffer[2];
    } else if (macd_strategy == HIST) {
        buy_macd = (macd_main_buffer[0] - macd_signal_buffer[0]) > 0;
        sell_macd = (macd_main_buffer[0] - macd_signal_buffer[0]) < 0;
    }

    if (adx_strategy == USE_ADX) {
        buy_adx = (DI_plusBuffer[0] - DI_minusBuffer[0]) > adx_diff;
        sell_adx = (DI_minusBuffer[0] - DI_plusBuffer[0]) > adx_diff;
    }

    bool Buy = true;
    bool Sell = true;

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

        // if (candle[1].open < third_ema_buffer[1] && candle[1].close > third_ema_buffer[1]) {
        //     Buy = true;
        // } else if (candle[1].open > third_ema_buffer[1] && candle[1].close < third_ema_buffer[1]) {
        //     Sell = true;
        // }
    }

    if (rsi_strategy != NO_RSI) {
        Buy = Buy && buy_rsi;
        Sell = Sell && sell_rsi;
        confidenceRSI = buy_rsi ? 1.0 : (sell_rsi ? -1.0 : 0.0);
    }

    if (macd_strategy != NO_MACD) {
        Buy = Buy && buy_macd;
        Sell = Sell && sell_macd;
        confidenceMACD = buy_macd ? 1.0 : (sell_macd ? -1.0 : 0.0);
    }

    if (adx_strategy != NO_ADX) {
        Buy = Buy && buy_adx;
        Sell = Sell && sell_adx;
        confidenceADX = buy_adx ? 1.0 : (sell_adx ? -1.0 : 0.0);
    }

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

    // Ensure confidence is within [0,1]
    buy_confidence = MathMax(0.0, MathMin(1.0, buy_confidence));
    sell_confidence = MathMax(0.0, MathMin(1.0, sell_confidence));

    bool newBar = isNewBar();
    bool tradeTime = IsTradingTime();

    tradeTime = true;

    if (tradeTime) {
        if (newBar) {
            if (!use_threshold) {
                trade(Buy, Sell);
            } else {
                thresholdTrade(buy_confidence, sell_confidence, buy_threshold, sell_threshold);
            }
        }
    }

    ArrayFree(first_ema_buffer);
    ArrayFree(second_ema_buffer);
    ArrayFree(third_ema_buffer);
    ArrayFree(rsi_buffer);
    ArrayFree(macd_main_buffer);
    ArrayFree(macd_signal_buffer);
    ArrayFree(adx_buffer);
    ArrayFree(DI_plusBuffer);
    ArrayFree(DI_minusBuffer);

    if (percent_change > 0 && !CheckForOpenTrade()) {
        // printf("No open trades");
        CheckPercentChange();
    }

    if (trailing_sl) {
        updateSLTP();
    }

    if (AccountInfoDouble(ACCOUNT_BALANCE) < (SymbolInfoDouble(_Symbol, SYMBOL_BID) * 0.01 / 3.67)) {
        ExpertRemove();
    }
}

double OnTester() {
    double score = 0.0;

    if (test_criterion == BALANCExRECOVERYxSHARPE) {
        score = GetBalanceRecoverySharpeRatio();
    } else if (test_criterion == MAXIMUM_FAVORABLE_EXCURSION) {
        score = GetMaximumFavorableExcursionOnBalanceCurve();
    } else if (test_criterion == MEAN_ABSOLUTE_ERROR) {
        score = GetMeanAbsoluteErrorOnBalanceCurve();
    } else if (test_criterion == ROOT_MEAN_SQUARED_ERROR) {
        score = GetRootMeanSquareErrorOnBalanceCurve();
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
        // Profit*1-BalanceDDrel
        if (profit >= 0) {
            score = TesterStatistics(STAT_PROFIT) * (100 - TesterStatistics(STAT_BALANCE_DDREL_PERCENT) / 100);
        } else {
            score = TesterStatistics(STAT_PROFIT) * (100 + TesterStatistics(STAT_BALANCE_DDREL_PERCENT) / 100);
        }
    } else if (test_criterion == HIGH_GROWTH) {
        score = highGrowth();
    } else if (test_criterion == PROFIT_MINUS_LOSS) {
        score = profit_minus_loss();
    } else if (test_criterion == PROFIT_WITH_TIEBREAKER) {
        score = profit_with_tiebreaker();
    } else if (test_criterion == NONE) {
        score = none();
    }

    return score;
}