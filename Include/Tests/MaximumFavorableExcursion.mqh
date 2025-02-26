//+------------------------------------------------------------------+
//|                                       MaximumFavorableExcursion.mqh |
//|                             Copyright 2000-2024, MetaQuotes Ltd.  |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#include <MQL5Book/DealFilter.mqh>
#define STAT_PROPS 4

struct MFEData {
    double mfe;
    MFEData() : mfe(0) {}
};

MFEData MaximumFavorableExcursion(double &data[]) {
    int size = ArraySize(data);
    if (size <= 1) return MFEData();

    double startPrice = data[0];
    double maxExcursion = 0;

    for (int i = 1; i < size; ++i) {
        if (data[i] == EMPTY_VALUE || !MathIsValidNumber(data[i])) continue;
        double excursion = data[i] - startPrice;  // Gain from starting point
        maxExcursion = MathMax(maxExcursion, excursion);
    }

    MFEData result;
    result.mfe = maxExcursion;
    return result;
}

double GetMaximumFavorableExcursionOnBalanceCurve() {
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

    double balance[];
    ArrayResize(balance, n + 1);
    balance[0] = TesterStatistics(STAT_INITIAL_DEPOSIT);

    for (int i = 0; i < n; ++i) {
        double result = 0;
        for (int j = 0; j < STAT_PROPS; ++j) {
            result += expenses[i][j];
        }
        balance[i + 1] = balance[i] + result;
    }

    MFEData result = MaximumFavorableExcursion(balance);
    return result.mfe;
}
