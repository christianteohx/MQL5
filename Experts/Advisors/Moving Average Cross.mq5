#property link "https://www.mql5.com"
#property version "1.00"

#include <Tests/MaximumFavorableExcursion.mqh>
#include <Tests/MeanAbsoluteError.mqh>
#include <Tests/RSquared.mqh>
#include <Tests/RootMeanSquaredError.mqh>

enum TEST_CRITERION {
    MAXIMUM_FAVORABLE_EXCURSION,
    MEAN_ABSOLUTE_ERROR,
    ROOT_MEAN_SQUARED_ERROR,
    R_SQUARED,
    WIN_RATE,
};

input int MAPeriodShort = 13;
input int MAPeriodLong = 48;
input int MAShift = 0;
input ENUM_MA_METHOD MAMethodS = MODE_EMA;
input ENUM_MA_METHOD MAMethodL = MODE_EMA;
input ENUM_APPLIED_PRICE MAPrice = PRICE_CLOSE;
input double stopLoss = 0.05;
input double takeProfit = 0.2;
input double volume = 0.01;

input TEST_CRITERION test_criterion = R_SQUARED;  // Test criterion

double highestPrice;
double lowestPrice;
double currentTP;

enum orderType {
    orderBuy,
    orderSell
};

datetime candleTimes[], lastCandleTime;

MqlTradeRequest request;
MqlTradeResult result;
MqlTradeCheckResult checkResult;

bool checkNewCandle(datetime &candles[], datetime &last) {
    bool newCandle = false;

    CopyTime(_Symbol, _Period, 0, 3, candles);

    if (last != 0) {
        if (candles[0] > last) {
            newCandle = true;
            last = candles[0];
        }
    } else {
        last = candles[0];
    }

    return newCandle;
}

bool closePosition() {
    double vol = 0;
    long type = WRONG_VALUE;
    long posID = 0;

    ZeroMemory(request);

    if (PositionSelect(_Symbol)) {
        vol = PositionGetDouble(POSITION_VOLUME);
        type = PositionGetInteger(POSITION_TYPE);
        posID = PositionGetInteger(POSITION_IDENTIFIER);

        request.sl = PositionGetDouble(POSITION_SL);
        request.tp = PositionGetDouble(POSITION_TP);
    } else {
        return false;
    }

    request.symbol = _Symbol;
    request.volume = vol;
    request.action = TRADE_ACTION_DEAL;
    request.type_filling = ORDER_FILLING_FOK;
    request.deviation = 10;
    double price = 0;

    if (type == POSITION_TYPE_BUY) {
        // Buy
        request.type = ORDER_TYPE_BUY;
        price = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_ASK), _Digits);
    } else if (POSITION_TYPE_SELL) {
        // Sell
        request.type = ORDER_TYPE_SELL;
        price = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_BID), _Digits);
    }

    request.price = price;

    if (OrderCheck(request, checkResult)) {
        Print("Checked!");
    } else {
        Print("Not correct! ERROR :" + IntegerToString(checkResult.retcode));
        return false;
    }

    if (OrderSend(request, result)) {
        Print("Successful send!");
    } else {
        Print("Error order not send!");
        return false;
    }

    if (result.retcode == TRADE_RETCODE_DONE || result.retcode == TRADE_RETCODE_PLACED) {
        Print("Trade Placed!");
        return true;
    } else {
        return false;
    }
}
bool makePosition(orderType type) {
    ZeroMemory(request);
    request.symbol = _Symbol;
    request.volume = volume;
    request.action = TRADE_ACTION_DEAL;
    request.type_filling = ORDER_FILLING_FOK;
    double price = 0;

    if (type == orderBuy) {
        // Buy
        request.type = ORDER_TYPE_BUY;
        price = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_ASK), _Digits);
        request.sl = NormalizeDouble(price - (stopLoss / 0.01), _Digits);
        request.tp = NormalizeDouble(price + (takeProfit / 0.01), _Digits);

    } else if (type == orderSell) {
        // Sell
        request.type = ORDER_TYPE_SELL;
        price = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_BID), _Digits);
        request.sl = NormalizeDouble(price + (stopLoss / 0.01), _Digits);
        request.tp = NormalizeDouble(price - (takeProfit / 0.01), _Digits);
    }
    request.deviation = 10;
    request.price = price;

    if (OrderCheck(request, checkResult)) {
        Print("Checked!");
    } else {
        Print("Not Checked! ERROR :" + IntegerToString(checkResult.retcode));
        return false;
    }

    if (OrderSend(request, result)) {
        Print("Ordem enviada com sucesso!");
    } else {
        Print("Ordem não enviada!");
        return false;
    }

    if (result.retcode == TRADE_RETCODE_DONE || result.retcode == TRADE_RETCODE_PLACED) {
        Print("Trade Placed!");
        return true;
    } else {
        return false;
    }
}

int OnInit() {
    if (MAPeriodShort > MAPeriodLong) {
        Alert("Invalid EMA period");
        return -1;
    }

    ArraySetAsSeries(candleTimes, true);
    return (0);
}

void OnTick() {
    if (checkNewCandle(candleTimes, lastCandleTime)) {
        double maS[];
        double maL[];
        ArraySetAsSeries(maS, true);
        ArraySetAsSeries(maL, true);
        double candleClose[];
        ArraySetAsSeries(candleClose, true);
        int maSHandle = iMA(_Symbol, _Period, MAPeriodShort, MAShift, MAMethodS, MAPrice);
        int maLHandle = iMA(_Symbol, _Period, MAPeriodLong, MAShift, MAMethodL, MAPrice);
        CopyBuffer(maSHandle, 0, 0, 3, maS);
        CopyBuffer(maLHandle, 0, 0, 3, maL);
        CopyClose(_Symbol, _Period, 0, 3, candleClose);

        if (((maS[1] < maL[1]) && (maS[0] > maL[0])) || ((maS[1] <= maL[1]) && (maS[0] > maL[0])) || ((maS[1] < maL[1]) && (maS[0] >= maL[0]))) {
            // cross up
            Print("Cross above!");
            closePosition();
            makePosition(orderBuy);

        } else if (((maS[1] > maL[1]) && (maS[0] < maL[0])) || ((maS[1] >= maL[1]) && (maS[0] < maL[0])) || ((maS[1] > maL[1]) && (maS[0] <= maL[0]))) {
            // cross down
            Print("Cross under!");
            closePosition();
            makePosition(orderSell);

        } else {
        }
    }
}

double OnTester() {
    if (test_criterion == MAXIMUM_FAVORABLE_EXCURSION) {
        return GetMaximumFavorableExcursionOnBalanceCurve();
    } else if (test_criterion == MEAN_ABSOLUTE_ERROR) {
        return GetMeanAbsoluteErrorOnBalanceCurve();
    } else if (test_criterion == ROOT_MEAN_SQUARED_ERROR) {
        return GetRootMeanSquareErrorOnBalanceCurve();
    } else if (test_criterion == R_SQUARED) {
        return GetR2onBalanceCurve();
    } else if (test_criterion == WIN_RATE) {
        return customized_max();
    } else {
        double profit = TesterStatistics(STAT_PROFIT);
        return sign(profit) * sqrt(fabs(profit)) * sqrt(TesterStatistics(STAT_PROFIT_FACTOR)) * sqrt(TesterStatistics(STAT_TRADES)) * sqrt(fabs(TesterStatistics(STAT_SHARPE_RATIO)));
    }
}

double sign(const double x) {
    return x > 0 ? +1 : (x < 0 ? -1 : 0);
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
    double criterion = (netProfit / maxDrawdown) * profitFactor * winRate;

    return criterion;
}