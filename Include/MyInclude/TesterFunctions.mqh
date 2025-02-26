#ifndef INCLUDE_TESTERFUNCTIONS
#define INCLUDE_TESTERFUNCTIONS

#include <MQL5Book/DealFilter.mqh>
#include <MyInclude/CommonEnums.mqh>
#include <Tests/MaximumFavorableExcursion.mqh>
#include <Tests/MeanAbsoluteError.mqh>
#include <Tests/RSquared.mqh>
#include <Tests/RootMeanSquaredError.mqh>
#define STAT_PROPS 4

double getTradeDrawdownPercent(ulong ticket) {
    double entryPrice = HistoryDealGetDouble(ticket, DEAL_PRICE);
    datetime entryTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);

    // Find the exit deal for this trade
    HistorySelect(0, INT_MAX);
    ulong exitTicket = 0;
    for (int i = HistoryDealsTotal() - 1; i >= 0; i--) {
        ulong deal = HistoryDealGetTicket(i);
        if (HistoryDealGetInteger(deal, DEAL_ENTRY) == DEAL_ENTRY_OUT &&
            HistoryDealGetInteger(deal, DEAL_TICKET) != ticket) {
            exitTicket = deal;
            break;
        }
    }
    datetime exitTime = exitTicket ? (datetime)HistoryDealGetInteger(exitTicket, DEAL_TIME) : entryTime + 3600;

    int barsToFetch = (int)((exitTime - entryTime) / PeriodSeconds(_Period));
    if (barsToFetch < 1) return 0.0;

    MqlRates rates[];
    if (CopyRates(_Symbol, _Period, entryTime, barsToFetch, rates) <= 0) return 0.0;

    double minPrice = rates[0].low;
    for (int i = 0; i < ArraySize(rates); i++) {
        if (rates[i].low < minPrice) minPrice = rates[i].low;
    }

    return (entryPrice - minPrice) / entryPrice;
}

double profit_minus_loss() {
    HistorySelect(0, INT_MAX);
    const ENUM_DEAL_PROPERTY_DOUBLE props[STAT_PROPS] = {DEAL_PROFIT, DEAL_SWAP, DEAL_COMMISSION, DEAL_FEE};
    double expenses[][STAT_PROPS];
    ulong tickets[];
    DealFilter filter;
    filter.let(DEAL_TYPE, (1 << DEAL_TYPE_BUY) | (1 << DEAL_TYPE_SELL), IS::OR_BITWISE)
        .let(DEAL_ENTRY, (1 << DEAL_ENTRY_OUT) | (1 << DEAL_ENTRY_INOUT) | (1 << DEAL_ENTRY_OUT_BY), IS::OR_BITWISE)
        .select(props, tickets, expenses);

    int n = ArraySize(tickets);
    double balance[];
    ArrayResize(balance, n + 1);
    balance[0] = TesterStatistics(STAT_INITIAL_DEPOSIT);

    double penaltySum = 0.0;
    for (int i = 0; i < n; ++i) {
        double result = 0.0;
        for (int j = 0; j < STAT_PROPS; j++) result += expenses[i][j];
        balance[i + 1] = balance[i] + result;
        if (result < 0) {
            double balanceBefore = MathMax(balance[i], 1.0);
            penaltySum += MathAbs(result);  // Linear penalty
        }
    }

    double netProfit = balance[n] - balance[0];
    double ddPercent = TesterStatistics(STAT_BALANCEDD_PERCENT) / 100.0;
    return (netProfit - penaltySum) * (1.0 - ddPercent);
}

double highGrowth() {
    double netProfit = TesterStatistics(STAT_PROFIT);
    double maxDrawdownPercent = MathMax(TesterStatistics(STAT_BALANCEDD_PERCENT), 0.1);
    double score = netProfit / maxDrawdownPercent;  // Simplified scaling
    return (netProfit < 0) ? -MathAbs(score) : score;
}

double GetBalanceRecoverySharpeRatio() {
    double netProfit = TesterStatistics(STAT_PROFIT);
    double recoveryFactor = TesterStatistics(STAT_RECOVERY_FACTOR);
    double sharpeRatio = TesterStatistics(STAT_SHARPE_RATIO);

    double score = (0.5 * netProfit / 1000.0) + (0.3 * recoveryFactor / 10.0) + (0.2 * sharpeRatio / 5.0);
    return (netProfit < 0 || recoveryFactor < 1 || sharpeRatio < 0.5) ? score * 0.1 : score;
}

double customized_max() {
    double netProfit = TesterStatistics(STAT_PROFIT);
    double maxDrawdown = MathMax(TesterStatistics(STAT_EQUITY_DD_RELATIVE), 1.0);
    double profitFactor = TesterStatistics(STAT_PROFIT_FACTOR);
    double winRate = TesterStatistics(STAT_PROFIT_TRADES) / MathMax(TesterStatistics(STAT_TRADES), 1);

    return (netProfit / maxDrawdown) * (profitFactor * winRate);
}

double none() {
    double netProfit = TesterStatistics(STAT_PROFIT);                        // Net Profit
    double maxDrawdown = TesterStatistics(STAT_EQUITY_DD_RELATIVE) / 100.0;  // Maximum Drawdown
    double profitFactor = TesterStatistics(STAT_PROFIT_FACTOR);              // Profit Factor
    double sharpeRatio = TesterStatistics(STAT_SHARPE_RATIO);                // Sharpe Ratio
    double recoveryFactor = TesterStatistics(STAT_RECOVERY_FACTOR);          // Recovery Factor
    double totalTrades = TesterStatistics(STAT_TRADES);                      // Total Number of Trades

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

double profit_with_tiebreaker() {
    double profit = TesterStatistics(STAT_PROFIT);
    double drawdown = TesterStatistics(STAT_BALANCE_DD);
    double profitFactor = TesterStatistics(STAT_PROFIT_FACTOR);
    double winRate = TesterStatistics(STAT_TRADES) > 0 ? TesterStatistics(STAT_PROFIT_TRADES) / TesterStatistics(STAT_TRADES) : 0;

    const double epsilon_dd = 1e-6;
    const double epsilon_pf = 1e-7;
    const double epsilon_wr = 1e-7;

    return profit - epsilon_dd * drawdown + epsilon_pf * profitFactor + epsilon_wr * winRate;
}

double GrowthWithDrawdownPenalty() {
    double netProfit = TesterStatistics(STAT_PROFIT);          // Total net profit (primary focus)
    double maxDrawdown = TesterStatistics(STAT_BALANCE_DD_RELATIVE); // Relative drawdown (0-100%)
    double grossProfit = TesterStatistics(STAT_GROSS_PROFIT);  // Total profit from winning trades
    double grossLoss = MathAbs(TesterStatistics(STAT_GROSS_LOSS)); // Absolute total loss from losing trades
    double totalTrades = TesterStatistics(STAT_TRADES);        // Total number of trades
    double winRate = totalTrades > 0 ? TesterStatistics(STAT_PROFIT_TRADES) / totalTrades : 0; // Win rate

    // Avoid division by zero or edge cases
    if (totalTrades <= 0) return -1000.0; // Large negative score for no trades
    if (maxDrawdown <= 0) maxDrawdown = 0.1; // Minimum drawdown for scaling

    // Adjusted weights: prioritize profit heavily, minimize drawdown impact
    double weightProfit = 0.9;    // Significantly higher weight for profit
    double weightDrawdown = 0.05; // Much lower weight for drawdown
    double weightLoss = 0.03;     // Minimal weight for losses
    double weightWinRate = 0.02;  // Slight reward for consistency

    // Normalize metrics for scale invariance, adjusting based on typical profit range
    double normalizedProfit = netProfit / 10000.0; // Adjust based on your profit scale (e.g., /5000.0 or /10000.0)
    double normalizedDrawdown = MathMin(maxDrawdown / 100.0, 0.5); // Cap drawdown at 0.5 (50%) to limit its impact
    double normalizedLoss = grossLoss / 10000.0;     // Normalize losses
    double normalizedWinRate = winRate;             // Already 0-1

    // Calculate score: profit dominates, with minimal penalties for drawdown and losses
    double score = (weightProfit * normalizedProfit) -
                   (weightDrawdown * normalizedDrawdown * 10.0) - // Controlled drawdown penalty
                   (weightLoss * normalizedLoss) +
                   (weightWinRate * normalizedWinRate * 10.0);

    // Ensure profit always takes precedence:
    // If profit is positive, cap drawdown penalty to prevent overriding profit
    if (netProfit > 0) {
        score = MathMax(score, normalizedProfit * 0.9); // Ensure profit drives the score
        // Cap total drawdown penalty to 10% of profit contribution
        double maxDrawdownPenalty = normalizedProfit * 0.1;
        score = MathMax(score, (weightProfit * normalizedProfit) - maxDrawdownPenalty);
    }

    // Penalize negative profit heavily, but still allow profit to dominate comparisons
    if (netProfit < 0) {
        score *= 0.01; // Severe penalty for losses, but scaled to avoid masking profit differences
    }

    // Optional: Cap the score to prevent extreme values
    return MathMax(-10.0, MathMin(10.0, score)); // Limits score range for stability
}

#endif