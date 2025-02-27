//+------------------------------------------------------------------+
//|                                            MeanAbsoluteError.mqh |
//|                            Copyright 2000-2024, MetaQuotes Ltd.  |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#include <MQL5Book/DealFilter.mqh>
#define STAT_PROPS 4

struct MAEData {
    double mae;
    MAEData() : mae(0) {}
};

MAEData MeanAbsoluteError(double &actual[], double &predicted[]) {
    int size = MathMin(ArraySize(actual), ArraySize(predicted));
    if (size <= 1) return MAEData();

    double sumError = 0;
    int validCount = 0;

    for (int i = 0; i < size; ++i) {
        if (actual[i] == EMPTY_VALUE || predicted[i] == EMPTY_VALUE ||
            !MathIsValidNumber(actual[i]) || !MathIsValidNumber(predicted[i])) {
            continue;
        }
        sumError += MathAbs(actual[i] - predicted[i]);
        validCount++;
    }

    MAEData result;
    result.mae = (validCount > 0) ? sumError / validCount : 0.0;
    return result;
}

double MeanAbsoluteErrorTest(double &actual[], double &predicted[]) {
    const MAEData result = MeanAbsoluteError(actual, predicted);
    return result.mae;
}
double GetMeanAbsoluteErrorOnBalanceCurve() {
    HistorySelect(0, INT_MAX);
    const ENUM_DEAL_PROPERTY_DOUBLE props[STAT_PROPS] = {DEAL_PROFIT, DEAL_SWAP, DEAL_COMMISSION, DEAL_FEE};
    double expenses[][STAT_PROPS];
    ulong tickets[];
    DealFilter filter;
    filter.let(DEAL_TYPE, (1 << DEAL_TYPE_BUY) | (1 << DEAL_TYPE_SELL), IS::OR_BITWISE)
          .let(DEAL_ENTRY, (1 << DEAL_ENTRY_OUT) | (1 << DEAL_ENTRY_INOUT) | (1 << DEAL_ENTRY_OUT_BY), IS::OR_BITWISE)
          .select(props, tickets, expenses);

    int n = ArraySize(tickets);
    if (n == 0) return 0.0;

    double balance[], predictedBalance[];
    ArrayResize(balance, n + 1);
    ArrayResize(predictedBalance, n + 1);

    balance[0] = TesterStatistics(STAT_INITIAL_DEPOSIT);
    predictedBalance[0] = balance[0];

    for (int i = 0; i < n; ++i) {
        double result = 0;
        for (int j = 0; j < STAT_PROPS; ++j) {
            result += expenses[i][j];
        }
        balance[i + 1] = balance[i] + result;

        // Example prediction: Assume a fixed expected profit based on strategy
        double expectedProfit = 50.0; // Replace with logic (e.g., TP target or indicator-based forecast)
        predictedBalance[i + 1] = predictedBalance[i] + expectedProfit;
    }

    double mae = MeanAbsoluteErrorTest(balance, predictedBalance);
    return mae;
}