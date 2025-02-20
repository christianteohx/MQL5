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
   if(size <= 1)
      return RMSEData();

   double sumErrorSquared = 0.0;
   int validCount = 0;
   
   for(int i = 0; i < size; ++i) {
      if(actual[i] == EMPTY_VALUE || predicted[i] == EMPTY_VALUE ||
         !MathIsValidNumber(actual[i]) || !MathIsValidNumber(predicted[i]))
         continue;
      
      double error = actual[i] - predicted[i];
      // Only penalize losses: if actual exceeds predicted, set error to 0.
      if(error > 0)
         error = 0;
      else
         error = -error; // Convert negative error to positive loss value
      
      sumErrorSquared += error * error;
      validCount++;
   }
   
   RMSEData result;
   if(validCount > 0)
      result.rmse = MathSqrt(sumErrorSquared / validCount);
   else
      result.rmse = 0.0;
   return result;
}

double RootMeanSquareErrorTest(const double &actual[], const double &predicted[]) {
   const RMSEData result = RootMeanSquareError(actual, predicted);
   return result.rmse;
}

double GetRootMeanSquareErrorOnBalanceCurve() {
   HistorySelect(0, INT_MAX);
   const ENUM_DEAL_PROPERTY_DOUBLE props[STAT_PROPS] = {
      DEAL_PROFIT, DEAL_SWAP, DEAL_COMMISSION, DEAL_FEE
   };
   double expenses[][STAT_PROPS];
   ulong tickets[];  // Useful for debugging or further filtering
   DealFilter filter;
   filter.let(DEAL_TYPE, (1 << DEAL_TYPE_BUY) | (1 << DEAL_TYPE_SELL), IS::OR_BITWISE)
         .let(DEAL_ENTRY,
              (1 << DEAL_ENTRY_OUT) | (1 << DEAL_ENTRY_INOUT) | (1 << DEAL_ENTRY_OUT_BY), IS::OR_BITWISE)
         .select(props, tickets, expenses);
   
   const int n = ArraySize(tickets);
   double balance[], predictedBalance[];
   // Resize arrays for n+1 data points (starting with the initial deposit)
   ArrayResize(balance, n + 1);
   ArrayResize(predictedBalance, n + 1);
   
   balance[0] = TesterStatistics(STAT_INITIAL_DEPOSIT);
   predictedBalance[0] = balance[0];  // Use the same starting value
   
   // Build the balance curve and a dummy "predicted" curve.
   for(int i = 0; i < n; ++i) {
      double delta = 0.0;
      for(int j = 0; j < STAT_PROPS; ++j) {
         delta += expenses[i][j];
      }
      balance[i + 1] = balance[i] + delta;
      
      // For now, the predicted curve is simply the actual balance plus a random adjustment.
      // Replace this with your own prediction logic.
      predictedBalance[i + 1] = balance[i + 1] + (MathRand() % 100 - 50);
   }
   
   double rmse = RootMeanSquareErrorTest(balance, predictedBalance);
   
   ArrayFree(balance);
   ArrayFree(predictedBalance);
   
   return rmse;
}

//+------------------------------------------------------------------+
//| OnTester() function for optimization testing                     |
//| It returns a fitness score where a lower RMSE (penalizing only     |
//| losses) gives a higher score.                                      |
//+------------------------------------------------------------------+
// double OnTester() {
//    double rmse = GetRootMeanSquareErrorOnBalanceCurve();
//    // Invert the RMSE (adding a small constant to avoid division by zero)
//    double fitness = 1.0 / (rmse + 0.0001);
//    return fitness;
// }
