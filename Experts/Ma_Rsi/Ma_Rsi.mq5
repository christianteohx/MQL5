//+------------------------------------------------------------------+
//|                                                         Test.mq5 |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#include <Math/Stat/Stat.mqh>
#include <Trade/AccountInfo.mqh>
#include <Trade/Trade.mqh>
#include <MQL5Book/DealFilter.mqh>

#define USE_R2_CRITERION
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
    COMPARISON,
    LIMIT,
};

enum RISK_MANAGEMENT {
    OPTIMIZED,
    FIXED_PERCENTAGE,
    EXPONENTIAL,
};

sinput string s0;  //-----------------Strategy-----------------
input MA ma_strategy = TRIPLE_MA;
input RSI rsi_strategy = LIMIT;
input RISK_MANAGEMENT risk_management = OPTIMIZED;

sinput string s1;                  //-----------------Moving Average-----------------
input int first_ema_period = 13;   // first EMA period
input int second_ema_period = 48;  // second EMA period
input int third_ema_period = 200;  // third EMA period

sinput string s2;               //-----------------RSI-----------------
input int rsi_period = 14;      // RSI period
input int rsi_overbought = 70;  // RSI overbought level
input int rsi_oversold = 30;    // RSI oversold level

sinput string s3;                  //-----------------Risk Management-----------------
input double SL = 10;              // Stop Loss
input double TP = 10;              // Take Profit
input bool trailing_sl = true;     // Trailing Stop Loss
input int max_risk = 10;           // Maximum risk (%) per trade
input double decrease_factor = 3;  // Descrease factor
input bool boost = false;          // Use high risk until target reached
input double boost_target = 5000;  // Boost target

//+------------------------------------------------------------------+
//| Variable for indicators                                          |
//+------------------------------------------------------------------+
int first_ema_handle;       // Handle First EMA
double first_ema_buffer[];  // Buffer First EMA

int second_ema_handle;       // Handle secondium EMA
double second_ema_buffer[];  // Buffer secondium EMA

int third_ema_handle;       // Handle third EMA
double third_ema_buffer[];  // Buffer third EMA

int rsi_handle;       // Handle RSI
double rsi_buffer[];  // Buffer RSI

//+------------------------------------------------------------------+
//| Variable for functions                                           |
//+------------------------------------------------------------------+
int magic_number = 50357114;  // Magic number

MqlRates candle[];  // Variable for storing candles
MqlTick tick;       // Variable for storing ticks

CTrade ExtTrade;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
    if (ma_strategy == SINGLE_MA) {
        if (first_ema_period < 1) {
            Alert("Invalid EMA period");
            return -1;
        }
    } else if (ma_strategy == DOUBLE_MA) {
        if (first_ema_period > second_ema_period) {
            Alert("Invalid EMA period");
            return -1;
        }
    } else if (ma_strategy == TRIPLE_MA) {
        if (first_ema_period > second_ema_period || second_ema_period > third_ema_period) {
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

    ExtTrade.SetExpertMagicNumber(magic_number);
    ExtTrade.SetDeviationInPoints(10);
    ExtTrade.SetTypeFilling(ORDER_FILLING_FOK);

    first_ema_handle = iCustom(_Symbol, Period(), "Examples/Custom Moving Average", first_ema_period, 0, MODE_EMA, clrRed, PRICE_CLOSE);
    second_ema_handle = iCustom(_Symbol, Period(), "Examples/Custom Moving Average", second_ema_period, 0, MODE_EMA, clrBlue, PRICE_CLOSE);
    third_ema_handle = iCustom(_Symbol, Period(), "Examples/Custom Moving Average", third_ema_period, 0, MODE_EMA, clrYellow, PRICE_CLOSE);

    rsi_handle = iRSI(_Symbol, _Period, rsi_period, PRICE_CLOSE);

    // Check if the EMA was created successfully
    if (first_ema_handle == INVALID_HANDLE || second_ema_handle == INVALID_HANDLE || third_ema_handle == INVALID_HANDLE || rsi_handle == INVALID_HANDLE) {
        Alert("Error trying to create Handles for indicator - error: ", GetLastError(), "!");

        return -1;
    }

    CopyRates(_Symbol, _Period, 0, 4, candle);
    ArraySetAsSeries(candle, true);

    ChartIndicatorAdd(0, 0, first_ema_handle);
    ChartIndicatorAdd(0, 0, second_ema_handle);
    ChartIndicatorAdd(0, 0, third_ema_handle);
    ChartIndicatorAdd(0, 1, rsi_handle);

    SetIndexBuffer(0, first_ema_buffer, INDICATOR_DATA);
    SetIndexBuffer(1, second_ema_buffer, INDICATOR_DATA);
    SetIndexBuffer(2, third_ema_buffer, INDICATOR_DATA);
    SetIndexBuffer(3, rsi_buffer, INDICATOR_DATA);

    return (INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    IndicatorRelease(first_ema_handle);
    IndicatorRelease(second_ema_handle);
    IndicatorRelease(third_ema_handle);
    IndicatorRelease(rsi_handle);

    // backlog.Clear();
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

    // Feed candle buffers with data
    CopyRates(_Symbol, _Period, 0, 4, candle);
    ArraySetAsSeries(candle, true);

    // Sort the data vector
    ArraySetAsSeries(first_ema_buffer, true);
    ArraySetAsSeries(second_ema_buffer, true);
    ArraySetAsSeries(third_ema_buffer, true);
    ArraySetAsSeries(rsi_buffer, true);

    SymbolInfoTick(_Symbol, tick);

    bool buy_single_ma = candle[1].open < first_ema_buffer[1] && candle[1].close > first_ema_buffer[1];
    bool buy_ma_cross = first_ema_buffer[0] > second_ema_buffer[0] && first_ema_buffer[2] < second_ema_buffer[2];
    bool buy_triple_ma = first_ema_buffer[0] > third_ema_buffer[0] && second_ema_buffer[0] > third_ema_buffer[0];
    bool buy_rsi = true;

    bool sell_single_ma = candle[1].open > first_ema_buffer[1] && candle[1].close < first_ema_buffer[1];
    bool sell_ma_cross = first_ema_buffer[0] < second_ema_buffer[0] && first_ema_buffer[2] > second_ema_buffer[2];
    bool sell_triple_ma = first_ema_buffer[0] < third_ema_buffer[0] && second_ema_buffer[0] < third_ema_buffer[0];
    bool sell_rsi = true;

    if (rsi_strategy == COMPARISON) {
        buy_rsi = rsi_buffer[0] > rsi_buffer[1];
        sell_rsi = rsi_buffer[0] < rsi_buffer[1];
    } else if (rsi_strategy == LIMIT) {
        buy_rsi = rsi_buffer[0] < rsi_overbought;
        sell_rsi = rsi_buffer[0] > rsi_oversold;
    }

    bool Buy = false;
    bool Sell = false;

    if (ma_strategy == SINGLE_MA) {
        Buy = buy_single_ma;
        Sell = sell_single_ma;

    } else if (ma_strategy == DOUBLE_MA) {
        Buy = buy_ma_cross;
        Sell = sell_ma_cross;

    } else if (ma_strategy == TRIPLE_MA) {
        Buy = (buy_ma_cross && buy_triple_ma);
        Sell = (sell_ma_cross && sell_triple_ma);

        if (candle[1].open < third_ema_buffer[1] && candle[1].close > third_ema_buffer[1]) {
            Buy = true;
        } else if (candle[1].open > third_ema_buffer[1] && candle[1].close < third_ema_buffer[1]) {
            Sell = true;
        }
    }

    if (rsi_strategy != NO_RSI) {
        Buy = Buy && buy_rsi;
        Sell = Sell && sell_rsi;
    }

    bool newBar = isNewBar();

    if (newBar) {
        if (Buy && PositionSelect(_Symbol) == false) {
            closeAllTrade();
            // drawVerticalLine("Buy", candle[1].time, clrGreen);
            const string message = "Buy Signal for " + _Symbol;
            SendNotification(message);
            BuyAtMarket();
        }

        if (Sell && PositionSelect(_Symbol) == false) {
            closeAllTrade();
            // drawVerticalLine("Sell", candle[1].time, clrRed);
            const string message = "Sell Signal for " + _Symbol;
            SendNotification(message);
            SellAtMarket();
        }
    }

    ArrayFree(first_ema_buffer);
    ArrayFree(second_ema_buffer);
    ArrayFree(third_ema_buffer);
    ArrayFree(rsi_buffer);

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
void BuyAtMarket() {
    double sl = 0;
    double tp = 0;

    if (SL > 0)
        sl = NormalizeDouble(tick.ask - (SL / _Point), _Digits);
    if (TP > 0)
        tp = NormalizeDouble(tick.ask + (TP / _Point), _Digits);

    if (!ExtTrade.PositionOpen(_Symbol, ORDER_TYPE_BUY, getVolume(), tick.ask, sl, tp)) {
        Print("Buy Order failed. Return code=", ExtTrade.ResultRetcode(),
              ". Code description: ", ExtTrade.ResultRetcodeDescription());
    } else {
        // Print("Order Buy Executed successfully!");
    }
}

void SellAtMarket() {
    double sl = 0;
    double tp = 0;

    if (SL > 0)
        sl = NormalizeDouble(tick.bid + (SL / _Point), _Digits);
    if (TP > 0)
        tp = NormalizeDouble(tick.bid - (TP / _Point), _Digits);

    if (!ExtTrade.PositionOpen(_Symbol, ORDER_TYPE_BUY, getVolume(), tick.bid, sl, tp)) {
        Print("Sell Order failed. Return code=", ExtTrade.ResultRetcode(),
              ". Code description: ", ExtTrade.ResultRetcodeDescription());
    } else {
        // Print(("Order Sell Executed successfully!"));
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
        ulong position_ticket = PositionGetTicket(i);                         // ticket of the position
        string position_symbol = PositionGetString(POSITION_SYMBOL);          // symbol
        int digits = (int)SymbolInfoInteger(position_symbol, SYMBOL_DIGITS);  // number of decimal places

        double profit = PositionGetDouble(POSITION_PROFIT);  // open price

        if (profit > 0.00) {
            double stop_loss = PositionGetDouble(POSITION_SL);
            double take_profit = PositionGetDouble(POSITION_TP);

            if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
                if (trailing_sl && stop_loss < tick.bid - (SL / _Point)) {
                    stop_loss = NormalizeDouble(tick.bid - (SL / _Point), digits);
                }

                if (!ExtTrade.PositionModify(position_ticket, stop_loss, 0)) {
                    //--- failure message
                    Print("Modify buy SL failed. Return code=", ExtTrade.ResultRetcode(),
                          ". Code description: ", ExtTrade.ResultRetcodeDescription());
                } else {
                    // Print(("Order Update Stop Loss Buy Executed successfully!"));
                }

            } else {
                if (trailing_sl && stop_loss > tick.ask + (SL / _Point)) {
                    stop_loss = NormalizeDouble(tick.ask + (SL / _Point), digits);
                }

                if (!ExtTrade.PositionModify(position_ticket, stop_loss, 0)) {
                    //--- failure message
                    Print("Modify sell SL failed. Return code=", ExtTrade.ResultRetcode(),
                          ". Code description: ", ExtTrade.ResultRetcodeDescription());
                } else {
                    // Print(("Order Update Stop Loss Sell Executed successfully!"));
                }
            }
        }
    }
}

double getVolume() {
    if (boost == true && AccountInfoDouble(ACCOUNT_BALANCE) < boost_target) {
        return boostVol();
    }

    if (risk_management == OPTIMIZED) {
        return optimizedVol();
    } else if (risk_management == FIXED_PERCENTAGE) {
        return fixedPercentageVol();
    } else if (risk_management == EXPONENTIAL) {
        return exponentialVol();
    }

    return 0.01;
}

double fixedPercentageVol() {
    double cur_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double contract_price = cur_price * 0.01 / 3.67;

    double free_margin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);

    double volume = free_margin * (max_risk / 100) / contract_price * 0.01;

    double min_vol = 0.01;
    double max_vol = 300;

    if (volume < min_vol) {
        volume = min_vol;
    } else if (volume > max_vol) {
        volume = max_vol;
    }

    return NormalizeDouble(volume, 2);
}

//+------------------------------------------------------------------+
//| Calculate optimal lot size                                       |
//+------------------------------------------------------------------+
double optimizedVol(void) {
    double price = 0.0;
    double margin = 0.0;

    //--- select lot size
    if (!SymbolInfoDouble(_Symbol, SYMBOL_ASK, price))
        return (0.0);

    if (!OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, 1.0, price, margin))
        return (0.0);

    if (margin <= 0.0)
        return (0.0);

    // Print("Account Margin Free: " + DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_FREE)));
    // Print("Maximum Risk: " + DoubleToString(max_risk));
    // Print("Margin: " + DoubleToString(margin));

    double lot = NormalizeDouble(AccountInfoDouble(ACCOUNT_MARGIN_FREE) * max_risk / margin, 2);

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
            lot = NormalizeDouble(lot - lot * losses / decrease_factor, 1);
    }

    //--- normalize and check limits
    double stepvol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    lot = stepvol * NormalizeDouble(lot / stepvol, 0);
    lot = NormalizeDouble(lot * 0.01 / 2, 2);

    double minvol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

    if (lot < minvol)
        lot = minvol;

    double maxvol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

    if (lot > maxvol)
        lot = maxvol;

    //--- return trading volume
    return lot;
}

double boostVol(void) {
    double cur_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double contract_price = cur_price * 0.01 / 3.67;
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);

    int minRisk = 10;

    double risk = MathSqrt(MathPow(boost_target, 2) / MathPow(balance, 2)) * minRisk;
    double volume = equity * (risk / 100) / contract_price * 0.01;

    double min_vol = 0.01;
    double max_vol = 300;

    if (volume < min_vol) {
        volume = min_vol;
    } else if (volume > max_vol) {
        volume = max_vol;
    }

    return NormalizeDouble(volume, 2);
}

double exponentialVol(void) {
    double cur_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double contract_price = cur_price * 0.01 / 3.67;

    double free_margin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);

    double volume = free_margin * (max_risk / 100) / contract_price * 0.01;

    HistorySelect(0, TimeCurrent());
    //---
    int orders = HistoryDealsTotal();  // total history deals
    int consec_wins = 0;               // number of losses orders without a break

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
            consec_wins++;
        else
            break;
    }

    volume = volume * MathPow(1.05, consec_wins);

    double min_vol = MathMax(0.01, free_margin * (5 / 100) / contract_price * 0.01);
    double max_vol = MathMin(300, free_margin / contract_price * 0.01);

    if (volume < min_vol) {
        volume = min_vol;
    } else if (volume > max_vol) {
        volume = max_vol;
    }

    return NormalizeDouble(volume, 2);
}

double OnTester() {
    #ifdef USE_R2_CRITERION
        return GetR2onBalanceCurve();
    #else const double profit = TesterStatistics(STAT_PROFIT);
        return sign(profit) * sqrt(fabs(profit)) * sqrt(TesterStatistics(STAT_PROFIT_FACTOR)) * sqrt(TesterStatistics(STAT_TRADES)) * sqrt(fabs(TesterStatistics(STAT_SHARPE_RATIO)));
    #endif
}

double sign (const double x) {
    return x > 0 ? +1 : (x < 0 ? -1 : 0);
}

struct R2A {
    double r2;
    double angle;
    R2A() : r2(0), angle(0) {}
};

R2A RSquared(const double& data[]) {
    int size = ArraySize(data);
    if (size <= 2) return R2A();
    double x, y, div;
    int k = 0;
    double Sx = 0, Sy = 0, Sxy = 0, Sx2 = 0, Sy2 = 0;
    for (int i = 0; i < size; ++i) {
        if (data[i] == EMPTY_VALUE || !MathIsValidNumber(data[i])) continue;
        x = i + 1;
        y = data[i];
        Sx += x;
        Sy += y;
        Sxy += x * y;
        Sx2 += x * x;
        Sy2 += y * y;
        ++k;
    }
    size = k;
    const double Sx22 = Sx * Sx / size;
    const double Sy22 = Sy * Sy / size;
    const double SxSy = Sx * Sy / size;
    div = (Sx2 - Sx22) * (Sy2 - Sy22);
    if (fabs(div) < DBL_EPSILON) return R2A();
    R2A result;
    result.r2 = (Sxy - SxSy) * (Sxy - SxSy) / div;
    result.angle = (Sxy - SxSy) / (Sx2 - Sx22);
    return result;
}

double RSquaredTest(const double& data[]) {
    const R2A result = RSquared(data);
    const double weight = 1.0 - 1.0 / sqrt(ArraySize(data) + 1);
    if (result.angle < 0) return -fabs(result.r2) * weight;
    return result.r2 * weight;
}

#define STAT_PROPS 4

double GetR2onBalanceCurve() {
    HistorySelect(0, LONG_MAX);
    const ENUM_DEAL_PROPERTY_DOUBLE props[STAT_PROPS] = {
        DEAL_PROFIT, DEAL_SWAP, DEAL_COMMISSION, DEAL_FEE};
    double expenses[][STAT_PROPS];
    ulong tickets[];  // only needed because of the 'select' prototype, but useful for debugging
    DealFilter filter;
    filter.let(DEAL_TYPE, (1 << DEAL_TYPE_BUY) | (1 << DEAL_TYPE_SELL), IS::OR_BITWISE)
        .let(DEAL_ENTRY,
             (1 << DEAL_ENTRY_OUT) | (1 << DEAL_ENTRY_INOUT) | (1 << DEAL_ENTRY_OUT_BY), IS::OR_BITWISE)
        .select(props, tickets, expenses);
    const int n = ArraySize(tickets);
    double balance[];
    ArrayResize(balance, n + 1);
    balance[0] = TesterStatistics(STAT_INITIAL_DEPOSIT);
    for (int i = 0; i < n; ++i) {
        double result = 0;
        for (int j = 0; j < STAT_PROPS; ++j) {
            result += expenses[i][j];
        }
        balance[i + 1] = result + balance[i];
    }
    const double r2 = RSquaredTest(balance);
    return r2 * 100;
}
