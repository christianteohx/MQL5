#ifndef INCLUDE_TESTERFUNCTIONS
#define INCLUDE_TESTERFUNCTIONS

#include <MyInclude/CommonEnums.mqh>
#include <Tests/MaximumFavorableExcursion.mqh>
#include <Tests/MeanAbsoluteError.mqh>
#include <Tests/RSquared.mqh>
#include <Tests/RootMeanSquaredError.mqh>
#include <MQL5Book/DealFilter.mqh>
#define STAT_PROPS 4

// extern TEST_CRITERION test_criterion;

// double OnTester() {
//     double score = 0.0;

//     if (test_criterion == BALANCExRECOVERYxSHARPE) {
//         score = GetBalanceRecoverySharpeRatio();
//     } else if (test_criterion == MAXIMUM_FAVORABLE_EXCURSION) {
//         score = GetMaximumFavorableExcursionOnBalanceCurve();
//     } else if (test_criterion == MEAN_ABSOLUTE_ERROR) {
//         score = GetMeanAbsoluteErrorOnBalanceCurve();
//     } else if (test_criterion == ROOT_MEAN_SQUARED_ERROR) {
//         score = GetRootMeanSquareErrorOnBalanceCurve();
//     } else if (test_criterion == R_SQUARED) {
//         score = GetR2onBalanceCurve();
//     } else if (test_criterion == CUSTOMIZED_MAX) {
//         score = customized_max();
//     } else if (test_criterion == WIN_RATE) {
//         double totalTrades = TesterStatistics(STAT_TRADES);       // Total number of trades
//         double wonTrades = TesterStatistics(STAT_PROFIT_TRADES);  // Number of winning trades

//         if (TesterStatistics(STAT_TRADES) == 0) {
//             score = 0;
//         } else {
//             score = wonTrades / totalTrades;
//         }
//     } else if (test_criterion == BALANCE_DRAWDOWN) {
//         double profit = TesterStatistics(STAT_PROFIT);
//         // Profit*1-BalanceDDrel
//         if (profit >= 0) {
//             score = TesterStatistics(STAT_PROFIT) * (100 - TesterStatistics(STAT_BALANCE_DDREL_PERCENT) / 100);
//         } else {
//             score = TesterStatistics(STAT_PROFIT) * (100 + TesterStatistics(STAT_BALANCE_DDREL_PERCENT) / 100);
//         }
//     } else if (test_criterion == HIGH_GROWTH) {
//         score = highGrowth();
//     } else if (test_criterion == PROFIT_MINUS_LOSS) {
//         score = profit_minus_loss();
//     } else if (test_criterion == NONE) {
//         score = none();
//     }

//     return score;
// }

double getTradeDrawdownPercent(ulong ticket)
{
    // Get the entry price of the trade from the deal.
    double entryPrice = HistoryDealGetDouble(ticket, DEAL_PRICE);
    
    // Retrieve the trade's open time using HistoryDealGetInteger with DEAL_TIME.
    datetime entryTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
    
    // For this example, we assume a trade duration of 1 hour (3600 seconds).
    // In practice, you'll want to calculate the actual exit time.
    datetime exitTime = entryTime + 3600; 

    // Calculate the number of bars to fetch for 1-minute timeframe.
    int barsToFetch = (int)((exitTime - entryTime) / 60);
    
    if(barsToFetch < 1)
       return 0.0;
       
    // Allocate an array for rate data.
    MqlRates rates[];
    ArrayResize(rates, barsToFetch);
    
    int copied = CopyRates(_Symbol, PERIOD_M1, entryTime, barsToFetch, rates);
    if(copied <= 0)
       return 0.0;
       
    // Find the minimum low price during the trade period.
    double minPrice = rates[0].low;
    for (int i = 0; i < copied; i++) {
       if(rates[i].low < minPrice)
           minPrice = rates[i].low;
    }
    
    // Calculate drawdown percentage relative to the entry price.
    double ddPercent = (entryPrice - minPrice) / entryPrice;
    return ddPercent;
}

double profit_minus_loss() {
    // Select the full deal history.
    HistorySelect(0, INT_MAX);
    
    // Define the properties we want from each deal.
    const ENUM_DEAL_PROPERTY_DOUBLE props[STAT_PROPS] = {
        DEAL_PROFIT, DEAL_SWAP, DEAL_COMMISSION, DEAL_FEE
    };
    
    // Arrays to store the expense data and deal tickets.
    double expenses[][STAT_PROPS];
    ulong tickets[];
    
    // Use DealFilter to select both buy and sell deals.
    DealFilter filter;
    filter.let(DEAL_TYPE, (1 << DEAL_TYPE_BUY) | (1 << DEAL_TYPE_SELL), IS::OR_BITWISE)
          .let(DEAL_ENTRY, (1 << DEAL_ENTRY_OUT) | (1 << DEAL_ENTRY_INOUT) | (1 << DEAL_ENTRY_OUT_BY), IS::OR_BITWISE)
          .select(props, tickets, expenses);
    
    const int n = ArraySize(tickets);
    double balance[];
    ArrayResize(balance, n + 1);
    
    // Start with the initial deposit.
    balance[0] = TesterStatistics(STAT_INITIAL_DEPOSIT);
    
    double penaltySum = 0.0;
    
    // Loop through each deal, building the balance curve and calculating penalties for losing trades.
    for (int i = 0; i < n; ++i) {
        double result = 0.0;
        for (int j = 0; j < STAT_PROPS; ++j) {
            result += expenses[i][j];
        }
        balance[i + 1] = balance[i] + result;
        
        // If the trade result is negative (a loss), calculate the penalty.
        if (result < 0) {
            // Approximate the loss percentage relative to the balance before the trade.
            // Ensure we do not divide by zero.
            double balanceBefore = balance[i];
            if (balanceBefore <= 0) balanceBefore = 1.0;
            double lossPct = MathAbs(result) / balanceBefore;
            double penalty = MathAbs(result) * lossPct;
            penaltySum += penalty;
        }
    }
    
    // Net profit is the total change in balance.
    double netProfit = balance[n] - balance[0];
    
    // Return score: positive if profitable, negative if not.
    double score = netProfit - penaltySum;
    // Return score times 1 minus drawdown percentage
    return score * (1 - TesterStatistics(STAT_BALANCEDD_PERCENT) / 100);
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

double profit_with_tiebreaker() {
    double profit = TesterStatistics(STAT_PROFIT);
    double drawdown = TesterStatistics(STAT_BALANCE_DD);
    double profitFactor = TesterStatistics(STAT_PROFIT_FACTOR);  // Example statistic
    double winRate = TesterStatistics(STAT_PROFIT_TRADES) / TesterStatistics(STAT_TRADES); // Example
  
    // Choose multipliers that are orders of magnitude smaller than the typical profit differences.
    const double epsilon_dd = 1e-6;
    const double epsilon_pf = 1e-7;
    const double epsilon_wr = 1e-7;
  
    // Combine metrics: profit is dominant, then drawdown, then profit factor and win rate as minor tie-breakers.
    double score = profit 
                   - epsilon_dd * drawdown 
                   + epsilon_pf * profitFactor 
                   + epsilon_wr * winRate;
    return score;
}


#endif