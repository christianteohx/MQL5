//+------------------------------------------------------------------+
//|                                                     RSquared.mqh |
//|                             Copyright 2000-2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#include <MQL5Book/DealFilter.mqh>
#define STAT_PROPS 4

struct R2A {
    double r2;
    double angle;
    R2A() : r2(0), angle(0) {}
};

R2A RSquared(const double &data[]) {
    int size = ArraySize(data);
    if (size <= 2)
        return R2A();
    double x, y, div;
    int k = 0;
    double Sx = 0, Sy = 0, Sxy = 0, Sx2 = 0, Sy2 = 0;
    for (int i = 0; i < size; ++i) {
        if (data[i] == EMPTY_VALUE || !MathIsValidNumber(data[i]))
            continue;
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
    if (fabs(div) < DBL_EPSILON)
        return R2A();
    R2A result;
    result.r2 = (Sxy - SxSy) * (Sxy - SxSy) / div;
    result.angle = (Sxy - SxSy) / (Sx2 - Sx22);
    return result;
}

double RSquaredTest(const double &data[]) {
    const R2A result = RSquared(data);
    const double weight = 1.0 - 1.0 / sqrt(ArraySize(data) + 1);
    if (result.angle < 0)
        return -fabs(result.r2) * weight;
    return result.r2 * weight;
}

double GetR2onBalanceCurve() {
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

    ArrayFree(balance);
    
    return r2 * 100;
}
