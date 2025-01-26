//+------------------------------------------------------------------+
//|                                                         Test.mq5 |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#include <Tests/MaximumFavorableExcursion.mqh>
#include <Tests/MeanAbsoluteError.mqh>
#include <Tests/RSquared.mqh>
#include <Tests/RootMeanSquaredError.mqh>
#include <Trade/AccountInfo.mqh>
#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| Input variables                                                  |
//+------------------------------------------------------------------+
enum MA {
    NO_MA,
    SINGLE_MA,
    DOUBLE_MA,
    TRIPLE_MA,
};

enum RSI {
    NO_RSI,
    LIMIT,
    COMPARISON,
};

enum MACD {
    NO_MACD,
    SIGNAL,
    HIST,
};

enum ADX {
    NO_ADX,
    USE_ADX,
};

enum RISK_MANAGEMENT {
    OPTIMIZED,
    FIXED_PERCENTAGE,
};

enum TEST_CRITERION {
    MAXIMUM_FAVORABLE_EXCURSION,
    MEAN_ABSOLUTE_ERROR,
    ROOT_MEAN_SQUARED_ERROR,
    R_SQUARED,
    WIN_RATE,
    CUSTOMIZED_MAX,
    SMALL_TRADES,
    BIG_TRADES,
    BALANCE_DRAWDOWN,
    BALANCExRECOVERYxSHARPE,
    HIGH_GROWTH,
    NONE,
};

enum TICKER {
    BTCUSD,
    XAUUSD
};

sinput string s0;  //-----------------Strategy-----------------
input TICKER ticker = BTCUSD;
input MA ma_strategy = TRIPLE_MA;
input RSI rsi_strategy = LIMIT;
input MACD macd_strategy = HIST;
input ADX adx_strategy = USE_ADX;
input RISK_MANAGEMENT risk_management = OPTIMIZED;

sinput string s1;                  //-----------------Moving Average-----------------
input int first_ema_period = 13;   // first EMA period
input int second_ema_period = 48;  // second EMA period
input int third_ema_period = 200;  // third EMA period
input double weightMA = 0.4;       // Weight for MA strategy

sinput string s2;               //-----------------RSI-----------------
input int rsi_period = 14;      // RSI period
input int rsi_overbought = 70;  // RSI overbought level
input int rsi_oversold = 30;    // RSI oversold level
input double weightRSI = 0.3;   // Weight for RSI strategy

sinput string s3;               //-----------------MACD-----------------
input int macd_fast = 12;       // MACD Fast
input int macd_slow = 26;       // MACD Slow
input int macd_period = 9;      // MACD Period
input double weightMACD = 0.2;  // Weight for MACD strategy

sinput string s4;              //-----------------ADX-----------------
input int adx_period = 14;     // ADX period
input int adx_diff = 20;       // ADX difference
input double weightADX = 0.1;  // Weight for ADX strategy

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

struct closePosition {
    int buySell;
    double price;
} last_close_position;

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

bool IsTradingTime() {
    MqlDateTime tm = {};
    datetime time = TimeCurrent(tm);

    // Check if the time is between 10:30 and 11:30
    if ((tm.hour == 17 && tm.min >= 30) || (tm.hour == 18 && tm.min <= 30)) {
        // Print("Time- ", tm.hour, ":", tm.min);
        return true;  // It is within the trading window
    }
    return false;  // It is outside the trading window
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
        buy_rsi = rsi_buffer[0] < rsi_overbought;
        sell_rsi = rsi_buffer[0] > rsi_oversold;
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
            if (!use_threshold && Buy) {
                closeAllTrade();
                const string message = "Buy Signal for " + _Symbol;
                SendNotification(message);
                BuyAtMarket();
                return;
            } else if (buy_confidence >= buy_threshold) {
                closeAllTrade();
                const string message = "Buy Signal for " + _Symbol;
                SendNotification(message);
                BuyAtMarket();
            }

            if (!use_threshold && Sell) {
                closeAllTrade();
                const string message = "Sell Signal for " + _Symbol;
                SendNotification(message);
                SellAtMarket();
                return;
            } else if (sell_confidence >= sell_threshold) {
                // printf("Sell");
                closeAllTrade();
                // drawVerticalLine("Sell", candle[1].time, clrRed);
                const string message = "Sell Signal for " + _Symbol;
                SendNotification(message);
                SellAtMarket();
            }
        }
    }

    ArrayFree(first_ema_buffer);
    ArrayFree(second_ema_buffer);
    ArrayFree(third_ema_buffer);
    ArrayFree(rsi_buffer);

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

//+------------------------------------------------------------------+
//| Useful functions                                                 |
//+------------------------------------------------------------------+
//--- for bar change
bool isNewBar() {
    static datetime last_time = 0;
    datetime lastbar_time = (datetime)SeriesInfoInteger(Symbol(), Period(), SERIES_LASTBAR_DATE);

    if (last_time == 0) {
        last_time = lastbar_time;
        return false;
    }

    if (last_time != lastbar_time) {
        last_time = lastbar_time;
        return true;
    }

    return false;
}

//+------------------------------------------------------------------+
//| FUNCTIONS TO ASSIST IN THE VISUALIZATION OF THE STRATEGY         |
//+------------------------------------------------------------------+
void drawVerticalLine(string name, datetime dt, color cor = clrAliceBlue) {
    ObjectDelete(0, name);
    ObjectCreate(0, name, OBJ_VLINE, 0, dt, 0);
    ObjectSetInteger(0, name, OBJPROP_COLOR, cor);
}

//+------------------------------------------------------------------+
//| FUNCTIONS FOR SENDING ORDERS                                     |
//+------------------------------------------------------------------+
void BuyAtMarket(string comments = "") {
    double sl = 0;
    double tp = 0;

    if (SL > 0)
        sl = NormalizeDouble(tick.ask - (SL), decimal);
    if (TP > 0)
        tp = NormalizeDouble(tick.ask + (TP), decimal);

    if (!ExtTrade.PositionOpen(_Symbol, ORDER_TYPE_BUY, getVolume(), tick.ask, sl, tp, comments)) {
        Print("Buy Order failed. Return code=", ExtTrade.ResultRetcode(),
              ". Code description: ", ExtTrade.ResultRetcodeDescription());
        Print("Ask: ", tick.ask, " SL: ", sl, " TP: ", tp);

    } else {
        // Print("Order Buy Executed successfully!");
    }
}

void SellAtMarket(string comments = "") {
    double sl = 0;
    double tp = 0;

    if (SL > 0)
        sl = NormalizeDouble(tick.bid + (SL), decimal);
    if (TP > 0)
        tp = NormalizeDouble(tick.bid - (TP), decimal);

    if (!ExtTrade.PositionOpen(_Symbol, ORDER_TYPE_SELL, getVolume(), tick.bid, sl, tp, comments)) {
        Print("Sell Order failed. Return code=", ExtTrade.ResultRetcode(),
              ". Code description: ", ExtTrade.ResultRetcodeDescription());
        Print("Bid: ", tick.bid, " SL: ", sl, " TP: ", tp);
    } else {
        // Print(("Order Sell Executed successfully!"));
    }
}

bool CheckForOpenTrade() {
    int total = PositionsTotal();

    if (total > 0) {
        return true;
    }

    last_close_position.buySell = NULL;

    return false;
}

void CheckPercentChange() {
    double current_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double last_price = last_close_position.price;

    double change = ((current_price - last_price) / last_price) * 100;

    if (MathAbs(change) > percent_change) {
        closeAllTrade();
        if (last_close_position.buySell == NULL) {
            if (change > 0) {
                printf("Buying after %.2f%% change", change);
                BuyAtMarket("Continue buy");
            } else {
                printf("Selling after %.2f%% change", change);
                SellAtMarket("Continue sell");
            }
        }

        if (last_close_position.buySell == POSITION_TYPE_BUY) {
            printf("Rebuying after %.2f%% change", change);
            BuyAtMarket("Continue buy");
        } else {
            printf("Reselling after %.2f%% change", change);
            SellAtMarket("Continue sell");
        }
    }
}

void closeAllTrade() {
    int total = PositionsTotal();
    for (int i = 0; i < total; i++) {
        ulong ticket = PositionGetTicket(i);

        if (!ExtTrade.PositionClose(ticket)) {
            Print("Close trade failed. Return code=", ExtTrade.ResultRetcode(),
                  ". Code description: ", ExtTrade.ResultRetcodeDescription());
        } else {
            if (PositionGetDouble(POSITION_PROFIT) > 0) {
                last_close_position.buySell = PositionGetInteger(POSITION_TYPE);
                last_close_position.price = PositionGetDouble(POSITION_PRICE_CURRENT);
            }
            // Print("Close position successfully!");
        }
    }
}

void updateSLTP() {
    MqlTradeRequest request;
    MqlTradeResult response;

    int total = PositionsTotal();

    for (int i = 0; i < total; i++) {
        //--- parameters of the order
        ulong position_ticket = PositionGetTicket(i);                 // ticket of the position
        string position_symbol = PositionGetString(POSITION_SYMBOL);  // symbol

        double profit = PositionGetDouble(POSITION_PROFIT);  // open price

        if (profit > 0.00) {
            double prev_stop_loss = PositionGetDouble(POSITION_SL);
            double prev_take_profit = PositionGetDouble(POSITION_TP);

            double stop_loss = prev_stop_loss;
            double take_profit = prev_take_profit;

            if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
                if (trailing_sl && (stop_loss < tick.bid - (SL) || stop_loss == 0)) {
                    stop_loss = NormalizeDouble(tick.bid - (SL), decimal);
                }

                if (TP > 0) {
                    take_profit = NormalizeDouble(tick.bid + (TP), decimal);
                } else {
                    take_profit = NormalizeDouble(0, decimal);
                }

                if (stop_loss == prev_stop_loss && take_profit == prev_take_profit) {
                    continue;
                }

                if (!ExtTrade.PositionModify(position_ticket, stop_loss, take_profit)) {
                    //--- failure message
                    Print("Modify buy SL failed. Return code=", ExtTrade.ResultRetcode(),
                          ". Code description: ", ExtTrade.ResultRetcodeDescription());
                    Print("Bid: ", tick.bid, " SL: ", stop_loss, " TP: ", take_profit);
                } else {
                    // Print(("Order Update Stop Loss Buy Executed successfully!"));
                }
            } else {
                if (trailing_sl && (stop_loss > tick.ask + (SL) || stop_loss == 0)) {
                    stop_loss = NormalizeDouble(tick.ask + (SL), decimal);
                }

                if (TP > 0) {
                    take_profit = NormalizeDouble(tick.ask - (TP), decimal);
                } else {
                    take_profit = NormalizeDouble(0, decimal);
                }

                if (stop_loss == prev_stop_loss && take_profit == prev_take_profit) {
                    continue;
                }

                if (!ExtTrade.PositionModify(position_ticket, stop_loss, take_profit)) {
                    //--- failure message
                    Print("Modify sell SL failed. Return code=", ExtTrade.ResultRetcode(),
                          ". Code description: ", ExtTrade.ResultRetcodeDescription());
                    Print("Ask: ", tick.ask, " SL: ", stop_loss, " TP: ", take_profit);
                } else {
                    // Print(("Order Update Stop Loss Sell Executed successfully!"));
                }
            }
        }
    }
}

int getVolume() {
    if (boost == true && boost_target > 0) {
        if (ACCOUNT_BALANCE < boost_target) {
            return boostVol();
        } else {
            return optimizedVol();
        }
    }

    if (risk_management == OPTIMIZED) {
        return optimizedVol();
    } else if (risk_management == FIXED_PERCENTAGE) {
        return fixedPercentageVol();
    } else {
        return 1;
    }
}

int fixedPercentageVol() {
    double cur_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double contract_price = cur_price * (contract_size / 10) / 3.67;
    double free_margin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
    double risk = max_risk;
    double volume = free_margin * (risk / 100) / contract_price;

    double min_vol = 0.01;
    double max_vol = 300;

    if (volume < min_vol) {
        volume = min_vol;
    } else if (volume > max_vol) {
        volume = max_vol;
    }

    return (int)volume;
}

//+------------------------------------------------------------------+
//| Calculate optimal lot size                                       |
//+------------------------------------------------------------------+
int optimizedVol(void) {
    double price = 0.0;
    double margin = 0.0;

    //--- select lot size
    if (!SymbolInfoDouble(_Symbol, SYMBOL_ASK, price))
        return (0.0);

    if (!OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, 1.0, price, margin))
        return (0.0);

    if (margin <= 0.0)
        return (0.0);

    double volume = NormalizeDouble(AccountInfoDouble(ACCOUNT_MARGIN_FREE) * max_risk / margin, 2);

    //--- calculate number of losses orders without a break1
    if (decrease_factor > 0) {
        //--- select history for access
        HistorySelect(0, TimeCurrent());
        //---
        int orders = HistoryDealsTotal();  // total history deals
        int losses = 0;                    // number of losses orders without a break

        for (int i = orders - 1; i >= 0; i--) {
            ulong ticket = HistoryDealGetTicket(i);

            if (ticket == 0) {
                Print("HistoryDealGetTicket failed, no trade history");
                break;
            }

            //--- check symbol
            if (HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol)
                continue;

            //--- check profit
            double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);

            if (profit > 0.0)
                break;

            if (profit < 0.0)
                losses++;
        }

        if (losses > 1)
            volume = NormalizeDouble(volume - volume * losses / decrease_factor, 1);
    }

    //--- normalize and check limits
    double stepvol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    volume = stepvol * NormalizeDouble(volume / stepvol, 0);
    volume = NormalizeDouble(volume * 0.01 / 2, 2);

    double minvol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

    if (volume < minvol)
        volume = minvol;

    double maxvol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

    if (volume > maxvol)
        volume = maxvol;

    //--- return trading volume

    Print("Optimized Volume: ", volume);
    return (int)volume;
}

int boostVol(void) {
    double cur_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double contract_price = cur_price * (contract_size / 10);
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);

    int minRisk = 10;

    double risk = MathMin(MathSqrt(MathPow(boost_target, 2) / MathPow(balance, 2)) * minRisk, 100);
    double volume = equity * (risk / 100) / contract_price;

    printf("Risk: %.2f", risk);
    printf("Volume: %.2f", volume);

    double min_vol = 1;
    double max_vol = 300;

    if (volume < min_vol) {
        volume = min_vol;
    } else if (volume > max_vol) {
        volume = max_vol;
    }

    Print("Boost Volume: ", volume);

    return int(volume);
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
    } else if (test_criterion == SMALL_TRADES) {
        score = small_trades();
    } else if (test_criterion == BIG_TRADES) {
        score = big_trades();
    } else if (test_criterion == BALANCE_DRAWDOWN) {
        score = -TesterStatistics(STAT_BALANCEDD_PERCENT);
    } else if (test_criterion == HIGH_GROWTH) {
        score = highGrowth();
    } else if (test_criterion == NONE) {
        score = none();
    }

    return score;
}

double sign(const double x) {
    return x > 0 ? +1 : (x < 0 ? -1 : 0);
}

double highGrowth() {
    double netProfit = TesterStatistics(STAT_PROFIT);
    double maxDrawdown = TesterStatistics(STAT_BALANCE_DD);

    double maxDrawdownPercent = TesterStatistics(STAT_BALANCEDD_PERCENT);
    if (maxDrawdownPercent <= 0) maxDrawdownPercent = 0.1;  // Avoid zero division

    // Score formula
    double score = (netProfit * 1.5) / maxDrawdownPercent;

    // Penalize negative profit heavily
    if (netProfit < 0) {
        score *= 0.1;  // Reduce score significantly for losing strategies
    }

    return score;
}

double GetBalanceRecoverySharpeRatio() {
    double netProfit = TesterStatistics(STAT_PROFIT);
    double recoveryFactor = TesterStatistics(STAT_RECOVERY_FACTOR);
    double sharpeRatio = TesterStatistics(STAT_SHARPE_RATIO);

    // Normalize values (example scale factor, adjust based on data range)
    double normalizedProfit = netProfit / 1000.0;
    double normalizedRecovery = recoveryFactor / 10.0;
    double normalizedSharpe = sharpeRatio / 5.0;

    // Weight components
    double weightProfit = 0.5;
    double weightRecovery = 0.3;
    double weightSharpe = 0.2;

    // Calculate score
    double score = (weightProfit * normalizedProfit) *
                       (weightRecovery * normalizedRecovery) +
                   (weightSharpe * normalizedSharpe);

    // Penalize negative profit
    if (netProfit < 0 || recoveryFactor < 1 || sharpeRatio < 0.5) {
        score *= 0.1;  // Halve the score for losing strategies
    }

    return score;
}

double customized_max() {
    double netProfit = TesterStatistics(STAT_PROFIT);          // Net profit
    double maxDrawdown = TesterStatistics(STAT_EQUITY_DD);     // Maximum equity drawdown
    double grossProfit = TesterStatistics(STAT_GROSS_PROFIT);  // Gross profit
    double grossLoss = TesterStatistics(STAT_GROSS_LOSS);      // Gross loss
    double totalTrades = TesterStatistics(STAT_TRADES);        // Total number of trades
    double wonTrades = TesterStatistics(STAT_PROFIT_TRADES);   // Number of winning trades

    // Calculate Profit Factor
    double profitFactor = 0;
    if (grossLoss != 0)
        profitFactor = grossProfit / MathAbs(grossLoss);

    // Calculate Win Rate
    double winRate = 0;
    if (totalTrades > 0)
        winRate = wonTrades / totalTrades;

    // Avoid division by zero
    if (maxDrawdown == 0)
        maxDrawdown = 1;

    // Compute the Optimization Criterion
    double criterion = ((netProfit) / maxDrawdown) * (profitFactor * winRate);

    return criterion;
}

double small_trades() {
    double netProfit = TesterStatistics(STAT_PROFIT);                // Net Profit
    double shortTrades = TesterStatistics(STAT_SHORT_TRADES);        // Total Number of Trades
    double maxDrawdown = TesterStatistics(STAT_EQUITY_DD);           // Maximum Drawdown
    double profitFactor = TesterStatistics(STAT_PROFIT_FACTOR);      // Profit Factor
    double expectedPayoff = TesterStatistics(STAT_EXPECTED_PAYOFF);  // Expected Payoff

    // Weights based on importance for many small trades
    double shortTradesWeight = 0.40;     // 50% weight for many small trades
    double expectedPayoffWeight = 0.15;  // 20% weight for small but profitable trades
    double netProfitWeight = 0.40;       // 20% weight for overall profitability
    double maxDrawdownWeight = 0.5;      // 10% weight for controlling risk

    // Score calculation
    double score = (shortTrades * shortTradesWeight) + (expectedPayoff * expectedPayoffWeight) + (netProfit * netProfitWeight) - (maxDrawdown * maxDrawdownWeight);  // Smaller drawdown is better

    if (netProfit < 0) {
        score = MathMin(-1 / score, 1 / score);  // Avoid negative scores
    }

    return score;  // Return the final score to rank the optimization results
}

double big_trades() {
    double netProfit = TesterStatistics(STAT_PROFIT);                // Net Profit
    double maxProfitTrade = TesterStatistics(STAT_MAX_PROFITTRADE);  // Largest individual profit trade
    double longTrades = TesterStatistics(STAT_LONG_TRADES);          // Total Number of Trades
    double maxDrawdown = TesterStatistics(STAT_EQUITY_DD);           // Maximum Drawdown
    double recoveryFactor = TesterStatistics(STAT_RECOVERY_FACTOR);  // Recovery Factor

    // Weights based on importance for fewer but bigger trades
    double maxProfitTradeWeight = 0.40;  // 40% weight for fewer but bigger trades
    double netProfitWeight = 0.30;       // 30% weight for overall profitability
    double recoveryFactorWeight = 0.20;  // 20% weight for bouncing back from losses
    double longTradesWeight = 0.20;      // 10% weight for fewer trades (inverted, so fewer is better)

    // Score calculation
    double score = (maxProfitTrade * maxProfitTradeWeight) + (netProfit * netProfitWeight) + (recoveryFactor * recoveryFactorWeight) + (longTrades * longTradesWeight);  // Favor fewer trades

    if (netProfit < 0) {
        score = MathMin(-1 / score, 1 / score);  // Avoid negative scores
    }

    return score;  // Return the final score to rank the optimization results
}

double none() {
    double netProfit = TesterStatistics(STAT_PROFIT);                // Net Profit
    double maxDrawdown = TesterStatistics(STAT_EQUITY_DD_RELATIVE);  // Maximum Drawdown
    double profitFactor = TesterStatistics(STAT_PROFIT_FACTOR);      // Profit Factor
    double sharpeRatio = TesterStatistics(STAT_SHARPE_RATIO);        // Sharpe Ratio
    double recoveryFactor = TesterStatistics(STAT_RECOVERY_FACTOR);  // Recovery Factor
    double totalTrades = TesterStatistics(STAT_TRADES);              // Total Number of Trades

    // Weights based on importance
    double netProfitWeight = 0.45;       // 45% weight for Net Profit
    double maxDrawdownWeight = 0.25;     // 25% weight for Maximum Drawdown
    double profitFactorWeight = 0.12;    // 12% weight for Profit Factor
    double sharpeRatioWeight = 0.08;     // 8% weight for Sharpe Ratio
    double recoveryFactorWeight = 0.05;  // 5% weight for Recovery Factor
    double totalTradesWeight = 0.05;     // 5% weight for Total Trades

    // Score calculation: higher scores should indicate better performance
    double score = (netProfit * netProfitWeight) - (maxDrawdown * maxDrawdownWeight)  // Subtract drawdown (smaller is better)
                   + (profitFactor * profitFactorWeight) + (sharpeRatio * sharpeRatioWeight) + (recoveryFactor * recoveryFactorWeight) + (totalTrades * totalTradesWeight);

    return score;  // Return the final score to rank the optimization results
}