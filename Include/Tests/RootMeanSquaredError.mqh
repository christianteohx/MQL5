//+------------------------------------------------------------------+
//|                                                RootMeanSquareError.mqh |
//|                             Copyright 2000-2024, MetaQuotes Ltd.  |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#include <MQL5Book/DealFilter.mqh>
#define STAT_PROPS 4

struct RMSEData {
    double rmse;
    RMSEData() : rmse(0) {}
};

RMSEData RootMeanSquareError(const double &actual[], const double &predicted[]) {
    int size = MathMin(ArraySize(actual), ArraySize(predicted));
    if (size <= 1)
        return RMSEData();

    double sumErrorSquared = 0;

    for (int i = 0; i < size; ++i) {
        if (actual[i] == EMPTY_VALUE || predicted[i] == EMPTY_VALUE ||
            !MathIsValidNumber(actual[i]) || !MathIsValidNumber(predicted[i]))
            continue;

        double error = actual[i] - predicted[i];
        sumErrorSquared += error * error;
    }

    RMSEData result;
    result.rmse = MathSqrt(sumErrorSquared / size);
    return result;
}

double RootMeanSquareErrorTest(const double &actual[], const double &predicted[]) {
    const RMSEData result = RootMeanSquareError(actual, predicted);
    return result.rmse;
}

double GetRootMeanSquareErrorOnBalanceCurve() {
    HistorySelect(0, INT_MAX);
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
    double balance[], predictedBalance[];

    // Dummy values for predicted balance (to be replaced with actual prediction model)
    ArrayResize(balance, n + 1);
    ArrayResize(predictedBalance, n + 1);

    balance[0] = TesterStatistics(STAT_INITIAL_DEPOSIT);
    predictedBalance[0] = balance[0];  // Start prediction with initial deposit

    for (int i = 0; i < n; ++i) {
        double result = 0;
        for (int j = 0; j < STAT_PROPS; ++j) {
            result += expenses[i][j];
        }
        balance[i + 1] = result + balance[i];

        // Replace this with your own prediction logic
        predictedBalance[i + 1] = balance[i + 1] + (MathRand() % 100 - 50);  // Example predicted value
    }

    const double rmse = RootMeanSquareErrorTest(balance, predictedBalance);

    ArrayFree(balance);
    ArrayFree(predictedBalance);
    
    return rmse;
}
