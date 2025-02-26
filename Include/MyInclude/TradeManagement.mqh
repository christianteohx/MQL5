//+------------------------------------------------------------------+
//|                                                    TradeManagement.mqh |
//|                                  Copyright 2024, Your Name or Team |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#ifndef TRADEMANAGEMENT_MQH
#define TRADEMANAGEMENT_MQH

#include <MyInclude/CommonEnums.mqh>
#include <Trade/AccountInfo.mqh>
#include <Trade/Trade.mqh>

// Structure to hold last closed position data (if needed)
struct closePosition {
    int buySell;  // 1 for buy, -1 for sell, 0 for none
    double price;
};

//+------------------------------------------------------------------+
//| Initialize ATR (call from Ma_Rsi.mq5 OnInit)                     |
//+------------------------------------------------------------------+
// void InitializeATR() {
//     atr_handle = iATR(_Symbol, _Period, atr_period);
//     if (atr_handle == INVALID_HANDLE) {
//         Print("Error creating ATR handle - error: ", GetLastError());
//         return;
//     }
// }

//+------------------------------------------------------------------+
//| Get Current ATR Value                                            |
//+------------------------------------------------------------------+
// double GetCurrentATR() {
//     if (atr_handle == INVALID_HANDLE) {
//         Print("ATR handle invalid, reinitializing...");
//         InitializeATR();
//         if (atr_handle == INVALID_HANDLE) {
//             Print("Failed to reinitialize ATR handle. Using default ATR (0.0).");
//             return 0.0;
//         }
//     }

//     if (CopyBuffer(atr_handle, 0, 0, 4, atr_buffer) < 4) {
//         Print("Failed to copy ATR data - error: ", GetLastError());
//         return 0.0;  // Return 0.0 as fallback, but log the issue
//     }
//     ArraySetAsSeries(atr_buffer, true);
//     return atr_buffer[1];  // Most recent ATR value (index 1 for safety)
// }

//+------------------------------------------------------------------+
//| Trade Execution Function with Dynamic SL/TP                      |
//+------------------------------------------------------------------+
void trade(bool Buy, bool Sell, double sl, double tp) {
    // Check volatility before trading
    // double current_atr = GetCurrentATR();
    // if (current_atr <= 0.0 || current_atr < min_volatility * SymbolInfoDouble(_Symbol, SYMBOL_POINT) ||
    //     current_atr > max_volatility * SymbolInfoDouble(_Symbol, SYMBOL_POINT)) {
    //     Print("Volatility out of bounds or invalid (ATR = ", current_atr / SymbolInfoDouble(_Symbol, SYMBOL_POINT),
    //           "). Skipping trade.");
    //     return;
    // }
    printf("Trade function called with Buy=%d, Sell=%d, SL=%f, TP=%f", Buy, Sell, sl, tp);
    if (Buy && PositionsTotal() == 0) {
        // Calculate lot size using optimized volume
        double lotSize = getVolume() / 10.0;  // Adjust based on your volume function output
        double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

        // Place buy order with dynamic SL and TP (in points, converted to price)
        if (ExtTrade.Buy(lotSize, _Symbol, price,
                         sl * SymbolInfoDouble(_Symbol, SYMBOL_POINT),
                         tp * SymbolInfoDouble(_Symbol, SYMBOL_POINT), "Buy Order")) {
            Print("Buy order executed successfully with SL=", sl, " TP=", tp);
        } else {
            Print("Buy order failed - error: ", GetLastError());
        }
    }
    else if (Sell && PositionsTotal() == 0) {
        // Calculate lot size using optimized volume
        double lotSize = getVolume() / 10.0;  // Adjust based on your volume function output
        double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);

        // Place sell order with dynamic SL and TP (in points, converted to price)
        if (ExtTrade.Sell(lotSize, _Symbol, price,
                          sl * SymbolInfoDouble(_Symbol, SYMBOL_POINT),
                          tp * SymbolInfoDouble(_Symbol, SYMBOL_POINT), "Sell Order")) {
            Print("Sell order executed successfully with SL=", sl, " TP=", tp);
        } else {
            Print("Sell order failed - error: ", GetLastError());
        }
    }
}

//+------------------------------------------------------------------+
//| Threshold-Based Trade Execution with Dynamic SL/TP               |
//+------------------------------------------------------------------+
void thresholdTrade(double buy_confidence, double sell_confidence, double buy_threshold, double sell_threshold, double sl, double tp) {
    // Check volatility before trading
    // double current_atr = GetCurrentATR();
    // if (current_atr <= 0.0 || current_atr < min_volatility * SymbolInfoDouble(_Symbol, SYMBOL_POINT) ||
    //     current_atr > max_volatility * SymbolInfoDouble(_Symbol, SYMBOL_POINT)) {
    //     Print("Volatility out of bounds or invalid (ATR = ", current_atr / SymbolInfoDouble(_Symbol, SYMBOL_POINT),
    //           "). Skipping trade.");
    //     return;
    // }

    if (buy_confidence >= buy_threshold && PositionsTotal() == 0) {
        // Calculate lot size using optimized volume
        double lotSize = getVolume() / 10.0;  // Adjust based on your volume function output
        double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

        // Place buy order with dynamic SL and TP (in points, converted to price)
        if (ExtTrade.Buy(lotSize, _Symbol, price,
                         sl * SymbolInfoDouble(_Symbol, SYMBOL_POINT),
                         tp * SymbolInfoDouble(_Symbol, SYMBOL_POINT), "Threshold Buy Order")) {
            Print("Threshold Buy order executed successfully with SL=", sl, " TP=", tp);
        } else {
            Print("Threshold Buy order failed - error: ", GetLastError());
        }
    } else if (sell_confidence >= sell_threshold && PositionsTotal() == 0) {
        // Calculate lot size using optimized volume
        double lotSize = getVolume() / 10.0;  // Adjust based on your volume function output
        double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);

        // Place sell order with dynamic SL and TP (in points, converted to price)
        if (ExtTrade.Sell(lotSize, _Symbol, price,
                          sl * SymbolInfoDouble(_Symbol, SYMBOL_POINT),
                          tp * SymbolInfoDouble(_Symbol, SYMBOL_POINT), "Threshold Sell Order")) {
            Print("Threshold Sell order executed successfully with SL=", sl, " TP=", tp);
        } else {
            Print("Threshold Sell order failed - error: ", GetLastError());
        }
    }
}

//+------------------------------------------------------------------+
//| Update Stop Loss and Take Profit with Dynamic SL/TP              |
//+------------------------------------------------------------------+
void updateSLTP(MqlTick &tick) {  // Pass tick as parameter to access bid/ask
    MqlTradeRequest request;
    MqlTradeResult response;

    int total = PositionsTotal();
    // double current_atr = GetCurrentATR();

    for (int i = 0; i < total; i++) {
        //--- parameters of the order
        ulong position_ticket = PositionGetTicket(i);                 // ticket of the position
        string position_symbol = PositionGetString(POSITION_SYMBOL);  // symbol

        double profit = PositionGetDouble(POSITION_PROFIT);  // open price

        if (profit > 0.00) {
            double prev_stop_loss = PositionGetDouble(POSITION_SL);
            double prev_take_profit = PositionGetDouble(POSITION_TP);

            double stop_loss = prev_stop_loss;
            double take_profit = prev_take_profit;

            if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
                if (trailing_sl && (stop_loss < tick.bid - (current_atr * atr_sl_multiplier) || stop_loss == 0)) {
                    stop_loss = NormalizeDouble(tick.bid - (current_atr * atr_sl_multiplier), decimal);
                }

                if (TP > 0) {
                    take_profit = NormalizeDouble(tick.bid + (current_atr * atr_tp_multiplier), decimal);
                } else {
                    take_profit = NormalizeDouble(0, decimal);
                }

                if (stop_loss == prev_stop_loss && take_profit == prev_take_profit) {
                    continue;
                }

                if (!ExtTrade.PositionModify(position_ticket, stop_loss, take_profit)) {
                    //--- failure message
                    Print("Modify buy SL failed. Return code=", ExtTrade.ResultRetcode(),
                          ". Code description: ", ExtTrade.ResultRetcodeDescription());
                    Print("Bid: ", tick.bid, " SL: ", stop_loss, " TP: ", take_profit);
                } else {
                    Print("Order Update Stop Loss Buy Executed successfully with SL=", stop_loss, " TP=", take_profit);
                }
            } else {
                if (trailing_sl && (stop_loss > tick.ask + (current_atr * atr_sl_multiplier) || stop_loss == 0)) {
                    stop_loss = NormalizeDouble(tick.ask + (current_atr * atr_sl_multiplier), decimal);
                }

                if (TP > 0) {
                    take_profit = NormalizeDouble(tick.ask - (current_atr * atr_tp_multiplier), decimal);
                } else {
                    take_profit = NormalizeDouble(0, decimal);
                }

                if (stop_loss == prev_stop_loss && take_profit == prev_take_profit) {
                    continue;
                }

                if (!ExtTrade.PositionModify(position_ticket, stop_loss, take_profit)) {
                    //--- failure message
                    Print("Modify sell SL failed. Return code=", ExtTrade.ResultRetcode(),
                          ". Code description: ", ExtTrade.ResultRetcodeDescription());
                    Print("Ask: ", tick.ask, " SL: ", stop_loss, " TP: ", take_profit);
                } else {
                    Print("Order Update Stop Loss Sell Executed successfully with SL=", stop_loss, " TP=", take_profit);
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Check for Open Trades                                            |
//+------------------------------------------------------------------+
bool CheckForOpenTrade() {
    int total = PositionsTotal();

    if (total > 0) {
        return true;
    }

    last_close_position.buySell = NULL;

    return false;
}

//+------------------------------------------------------------------+
//| Check Percent Change with Volatility Filter                      |
//+------------------------------------------------------------------+
void CheckPercentChange() {
    double last_price = last_close_position.price;

    // Skip if volatility is out of bounds
    if (current_atr < min_volatility * SymbolInfoDouble(_Symbol, SYMBOL_POINT) ||
        current_atr > max_volatility * SymbolInfoDouble(_Symbol, SYMBOL_POINT)) {
        Print("Volatility out of bounds (ATR = ", current_atr / SymbolInfoDouble(_Symbol, SYMBOL_POINT),
              "). Skipping percent change check.");
        return;
    }

    double change = ((SymbolInfoDouble(_Symbol, SYMBOL_BID) - last_price) / last_price) * 100;

    if (MathAbs(change) > percent_change) {
        closeAllTrade();
        if (last_close_position.buySell == NULL) {
            if (change > 0) {
                printf("Buying after %.2f%% change", change);
                BuyAtMarket("Continue buy", current_atr * atr_sl_multiplier, current_atr * atr_tp_multiplier);  // Use dynamic SL/TP
            } else {
                printf("Selling after %.2f%% change", change);
                SellAtMarket("Continue sell", current_atr * atr_sl_multiplier, current_atr * atr_tp_multiplier);  // Use dynamic SL/TP
            }
        } else if (last_close_position.buySell == POSITION_TYPE_BUY) {
            printf("Rebuying after %.2f%% change", change);
            BuyAtMarket("Continue buy", current_atr * atr_sl_multiplier, current_atr * atr_tp_multiplier);  // Use dynamic SL/TP
        } else {
            printf("Reselling after %.2f%% change", change);
            SellAtMarket("Continue sell", current_atr * atr_sl_multiplier, current_atr * atr_tp_multiplier);  // Use dynamic SL/TP
        }
    }
}

//+------------------------------------------------------------------+
//| Get Volume with Volatility Adjustment                            |
//+------------------------------------------------------------------+
int getVolume() {
    if (current_atr < min_volatility * SymbolInfoDouble(_Symbol, SYMBOL_POINT) ||
        current_atr > max_volatility * SymbolInfoDouble(_Symbol, SYMBOL_POINT)) {
        Print("Volatility out of bounds (ATR = ", current_atr / SymbolInfoDouble(_Symbol, SYMBOL_POINT),
              "). Using default volume.");
        return 1;  // Default to minimal volume in extreme volatility
    }

    if (boost == true && boost_target > 0) {
        if (ACCOUNT_BALANCE < boost_target) {
            return boostVol();
        } else {
            return optimizedVol();
        }
    }

    if (risk_management == OPTIMIZED) {
        return optimizedVol();
    } else if (risk_management == FIXED_PERCENTAGE) {
        return fixedPercentageVol();
    } else {
        return 1;
    }
}

//+------------------------------------------------------------------+
//| Fixed Percentage Volume with Volatility Scaling                  |
//+------------------------------------------------------------------+
int fixedPercentageVol() {
    double cur_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double contract_price = cur_price * (contract_size / 10) / 3.67;
    double free_margin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
    double risk = max_risk;

    // Scale risk based on volatility (reduce risk in high volatility)
    double volatility_factor = MathMin(1.0, current_atr / (atr_period * SymbolInfoDouble(_Symbol, SYMBOL_POINT)));  // 0-1 scale
    risk *= (1.0 - volatility_factor * 0.5);                                                                        // Reduce risk by up to 50% in high volatility

    double volume = free_margin * (risk / 100) / contract_price;

    double min_vol = 0.01;
    double max_vol = 300;

    if (volume < min_vol) {
        volume = min_vol;
    } else if (volume > max_vol) {
        volume = max_vol;
    }

    return (int)volume;
}

//+------------------------------------------------------------------+
//| Calculate Optimal Lot Size with Volatility Scaling               |
//+------------------------------------------------------------------+
int optimizedVol(void) {
    double price = 0.0;
    double margin = 0.0;

    //--- select lot size
    if (!SymbolInfoDouble(_Symbol, SYMBOL_ASK, price))
        return (0.0);

    if (!OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, 1.0, price, margin))
        return (0.0);

    if (margin <= 0.0)
        return (0.0);

    double volatility_factor = MathMin(1.0, current_atr / (atr_period * SymbolInfoDouble(_Symbol, SYMBOL_POINT)));  // 0-1 scale
    double effective_max_risk = max_risk * (1.0 - volatility_factor * 0.5);                                         // Reduce risk by up to 50% in high volatility

    double volume = NormalizeDouble(AccountInfoDouble(ACCOUNT_MARGIN_FREE) * effective_max_risk / margin, 2);

    //--- calculate number of losses orders without a break
    if (decrease_factor > 0) {
        //--- select history for access
        HistorySelect(0, TimeCurrent());
        //---
        int orders = HistoryDealsTotal();  // total history deals
        int losses = 0;                    // number of losses orders without a break

        for (int i = orders - 1; i >= 0; i--) {
            ulong ticket = HistoryDealGetTicket(i);

            if (ticket == 0) {
                Print("HistoryDealGetTicket failed, no trade history");
                break;
            }

            //--- check symbol
            if (HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol)
                continue;

            //--- check profit
            double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);

            if (profit > 0.0)
                break;

            if (profit < 0.0)
                losses++;
        }

        if (losses > 1)
            volume = NormalizeDouble(volume - volume * losses / decrease_factor, 1);
    }

    //--- normalize and check limits
    double stepvol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    volume = stepvol * NormalizeDouble(volume / stepvol, 0);
    volume = NormalizeDouble(volume * 0.01 / 2, 2);

    double minvol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

    if (volume < minvol)
        volume = minvol;

    double maxvol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

    if (volume > maxvol)
        volume = maxvol;

    Print("Optimized Volume (Volatility Adjusted): ", volume);
    return (int)volume;
}

//+------------------------------------------------------------------+
//| Boost Volume with Volatility Scaling                             |
//+------------------------------------------------------------------+
int boostVol(void) {
    double cur_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double contract_price = cur_price * (contract_size / 10);
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);

    int minRisk = 10;

    double volatility_factor = MathMin(1.0, current_atr / (atr_period * SymbolInfoDouble(_Symbol, SYMBOL_POINT)));  // 0-1 scale
    double risk = MathMin(MathSqrt(MathPow(boost_target, 2) / MathPow(balance, 2)) * minRisk, 100);
    risk *= (1.0 - volatility_factor * 0.5);  // Reduce risk by up to 50% in high volatility

    double volume = equity * (risk / 100) / contract_price;

    printf("Risk (Volatility Adjusted): %.2f", risk);
    printf("Volume (Volatility Adjusted): %.2f", volume);

    double min_vol = 1;
    double max_vol = 300;

    if (volume < min_vol) {
        volume = min_vol;
    } else if (volume > max_vol) {
        volume = max_vol;
    }

    Print("Boost Volume (Volatility Adjusted): ", volume);

    return (int)volume;
}

//+------------------------------------------------------------------+
//| Market Buy Order with Dynamic SL/TP                              |
//+------------------------------------------------------------------+
void BuyAtMarket(string comment, double sl, double tp) {
    double lotSize = getVolume() / 10.0;  // Adjust based on your volume function output
    double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

    if (ExtTrade.Buy(lotSize, _Symbol, price,
                     sl * SymbolInfoDouble(_Symbol, SYMBOL_POINT),
                     tp * SymbolInfoDouble(_Symbol, SYMBOL_POINT), comment)) {
        Print("Market Buy executed successfully with SL=", sl, " TP=", tp);
    } else {
        Print("Market Buy failed - error: ", GetLastError());
    }
}

//+------------------------------------------------------------------+
//| Market Sell Order with Dynamic SL/TP                             |
//+------------------------------------------------------------------+
void SellAtMarket(string comment, double sl, double tp) {
    double lotSize = getVolume() / 10.0;  // Adjust based on your volume function output
    double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);

    if (ExtTrade.Sell(lotSize, _Symbol, price,
                      sl * SymbolInfoDouble(_Symbol, SYMBOL_POINT),
                      tp * SymbolInfoDouble(_Symbol, SYMBOL_POINT), comment)) {
        Print("Market Sell executed successfully with SL=", sl, " TP=", tp);
    } else {
        Print("Market Sell failed - error: ", GetLastError());
    }
}

//+------------------------------------------------------------------+
//| Close All Trades Function                                        |
//+------------------------------------------------------------------+
void closeAllTrade() {
    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        if (PositionSelectByTicket(PositionGetTicket(i))) {
            if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
                ExtTrade.PositionClose(PositionGetTicket(i));
            } else if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL) {
                ExtTrade.PositionClose(PositionGetTicket(i));
            }
        }
    }
}

#endif  // TRADEMANAGEMENT_MQH