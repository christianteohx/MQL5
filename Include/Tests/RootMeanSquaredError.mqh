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

//------------------------------------------------------------------
// This function calculates the RMSE between two arrays (actual and predicted)
// but only penalizes when actual < predicted (i.e. losses). If actual exceeds
// predicted (profits), the error is set to zero.
//------------------------------------------------------------------
RMSEData RootMeanSquareError(const double &actual[], const double &predicted[]) {
    int size = MathMin(ArraySize(actual), ArraySize(predicted));
    if (size <= 1) return RMSEData();

    double sumErrorSquared = 0.0;
    int validCount = 0;

    for (int i = 0; i < size; ++i) {
        if (actual[i] == EMPTY_VALUE || predicted[i] == EMPTY_VALUE ||
            !MathIsValidNumber(actual[i]) || !MathIsValidNumber(predicted[i])) {
            continue;
        }

        double error = actual[i] - predicted[i];
        // Penalize only if actual is lower than the previous actual (loss), not just prediction
        if (i > 0 && actual[i] < actual[i - 1]) {  // Check for actual loss in balance
            error = MathAbs(actual[i] - predicted[i]);
        } else {
            error = 0;  // No penalty for profits or no loss
        }

        sumErrorSquared += error * error;
        validCount++;
    }

    RMSEData result;
    if (validCount > 0) {
        result.rmse = MathSqrt(sumErrorSquared / validCount);
        // Normalize by initial deposit or average balance for scale invariance
        double initialDeposit = TesterStatistics(STAT_INITIAL_DEPOSIT);
        if (initialDeposit > 0) result.rmse /= initialDeposit;
    } else {
        result.rmse = 0.0;
    }
    return result;
}

double RootMeanSquareErrorTest(const double &actual[], const double &predicted[]) {
    const RMSEData result = RootMeanSquareError(actual, predicted);
    return result.rmse;
}

double GetRootMeanSquareErrorOnBalanceCurve(double TP) {
    HistorySelect(0, INT_MAX);
    const ENUM_DEAL_PROPERTY_DOUBLE props[STAT_PROPS] = {
        DEAL_PROFIT, DEAL_SWAP, DEAL_COMMISSION, DEAL_FEE};
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
        double delta = 0.0;
        for (int j = 0; j < STAT_PROPS; ++j) {
            delta += expenses[i][j];
        }
        balance[i + 1] = balance[i] + delta;

        // Use TP as expected profit per trade
        double expectedProfit = TP * SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
        predictedBalance[i + 1] = predictedBalance[i] + MathMax(0, expectedProfit);  // Assume positive profit expectation
    }

    double rmse = RootMeanSquareErrorTest(balance, predictedBalance);
    return rmse;
}