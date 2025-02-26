//+------------------------------------------------------------------+
//|                                            MonteCarloSimulation.mqh |
//|                             Copyright 2025, Your Name or Team     |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#include <MQL5Book/DealFilter.mqh>
#define MONTE_CARLO_ITERATIONS 1000  // Number of simulations (adjust as needed)

double GetMonteCarloRobustness() {
    double totalProfit = 0;
    double maxDrawdown = 0;
    int wins = 0;
    int totalDeals = 0;

    // Collect historical trade data
    HistorySelect(0, TimeCurrent());
    totalDeals = HistoryDealsTotal();
    if (totalDeals <= 0) {
        Print("No historical deals found for Monte Carlo simulation. Returning 0.");
        return 0.0;
    }

    // Loop through Monte Carlo iterations
    for (int i = 0; i < MONTE_CARLO_ITERATIONS; i++) {
        double simulatedProfit = 0;
        double currentBalance = TesterStatistics(STAT_INITIAL_DEPOSIT);
        double maxBalance = currentBalance;
        double minBalance = currentBalance;

        // Simulate each trade with random perturbations for crypto markets
        for (int j = 0; j < totalDeals; j++) {
            ulong ticket = HistoryDealGetTicket(j);
            if (ticket == 0) continue;

            if (HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol) continue;

            double dealProfit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
            double dealVolume = HistoryDealGetDouble(ticket, DEAL_VOLUME);
            datetime dealTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);

            // Random perturbations for crypto volatility (adjust for BTCUSD/ETHUSD)
            double priceSlippage = (MathRand() / 32767.0 - 0.5) * 0.10; // -5% to +5%
            double volumeVariation = (MathRand() / 32767.0 - 0.5) * 0.15; // -7.5% to +7.5%
            double spreadImpact = (MathRand() / 32767.0) * 0.002; // Random spread increase (0-0.2%)

            double perturbedProfit = dealProfit * (1.0 + priceSlippage) * (1.0 + volumeVariation) * (1.0 - spreadImpact);
            simulatedProfit += perturbedProfit;

            // Update balance for drawdown calculation
            currentBalance += perturbedProfit;
            maxBalance = MathMax(maxBalance, currentBalance);
            minBalance = MathMin(minBalance, currentBalance);

            // Track wins
            if (perturbedProfit > 0) wins++;
        }

        totalProfit += simulatedProfit;
        double drawdown = (maxBalance - minBalance) / maxBalance * 100.0; // Relative drawdown in percent
        maxDrawdown = MathMax(maxDrawdown, drawdown);
    }

    // Calculate statistics
    double avgProfit = totalProfit / MONTE_CARLO_ITERATIONS;
    double winProbability = (wins * 100.0) / (MONTE_CARLO_ITERATIONS * totalDeals);

    // Create a score (0-100) prioritizing average profit, penalizing drawdowns, and rewarding win probability
    double robustnessScore = (avgProfit / 1000.0) * 0.6 - // Normalize profit, prioritize heavily
                            (maxDrawdown / 100.0) * 0.3 + // Penalize drawdown (0-1 scale)
                            (winProbability / 100.0) * 0.1; // Reward win probability (0-1 scale)
    double finalScore = MathMax(0.0, MathMin(1.0, robustnessScore)) * 100.0; // Scale to 0-100

    Print("Monte Carlo Robustness Score: ", finalScore,
          " (Avg Profit: ", avgProfit, 
          " Max Drawdown: ", maxDrawdown, 
          " Win Probability: ", winProbability, ")");

    return finalScore;
}