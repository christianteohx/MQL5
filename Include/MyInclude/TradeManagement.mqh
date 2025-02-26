#ifndef MYINCLUDE_TRADEMANAGEMENT_MQH
#define MYINCLUDE_TRADEMANAGEMENT_MQH

#include <MyInclude/CommonEnums.mqh>
#include <Trade/Trade.mqh>

struct closePosition {
    int buySell;
    double price;
};

void trade(bool buy, bool sell) {
    printf("Trade function called with buy: %d, sell: %d", buy, sell);
    if (buy) {
        closeAllTrade();
        BuyAtMarket();
    } else if (sell) {
        closeAllTrade();
        SellAtMarket();
    }
}

void thresholdTrade(double buy_confidence, double sell_confidence, double buy_threshold, double sell_threshold) {
    // Debug logging: print current confidence levels
    Print("Buy Confidence: ", buy_confidence, " Sell Confidence: ", sell_confidence);

    // Check if neither signal meets its threshold
    if (buy_confidence < buy_threshold && sell_confidence < sell_threshold) {
        Print("No sufficient confidence to execute trade.");
        return;
    }

    // If both signals exceed their thresholds, check if the difference is significant
    if (buy_confidence >= buy_threshold && sell_confidence >= sell_threshold) {
        double diff = MathAbs(buy_confidence - sell_confidence);
        const double minDiff = 0.05;  // Minimum difference required to trigger a trade, adjust as needed
        if (diff < minDiff) {
            Print("Confidence levels are too close (diff = ", diff, "); holding position.");
            return;
        }
    }

    // Execute trade based on which signal is stronger
    if (buy_confidence > sell_confidence && buy_confidence >= buy_threshold) {
        Print("Buy confidence is higher and exceeds the threshold. Executing Buy...");
        closeAllTrade();  // Ensure no conflicting trades are open
        BuyAtMarket("High confidence buy");
    } else if (sell_confidence > buy_confidence && sell_confidence >= sell_threshold) {
        Print("Sell confidence is higher and exceeds the threshold. Executing Sell...");
        closeAllTrade();  // Ensure no conflicting trades are open
        SellAtMarket("High confidence sell");
    }
}

void BuyAtMarket(string comments = "") {
    double sl = 0;
    double tp = 0;

    printf("Buy with SL: %.2f, TP: %.2f", SL, TP);

    if (SL > 0)
        sl = NormalizeDouble(tick.ask - (SL), decimal);
    if (TP > 0)
        tp = NormalizeDouble(tick.ask + (TP), decimal);

    if (!ExtTrade.PositionOpen(_Symbol, ORDER_TYPE_BUY, getVolume(), tick.ask, sl, tp, comments)) {
        Print("Buy Order failed. Return code=", ExtTrade.ResultRetcode(),
              ". Code description: ", ExtTrade.ResultRetcodeDescription());
        Print("Ask: ", tick.ask, " SL: ", sl, " TP: ", tp);

    } else {
        // Print("Order Buy Executed successfully!");
        const string message = "Buy Signal for " + _Symbol;
        SendNotification(message);
    }
}

void SellAtMarket(string comments = "", double SL = 0, double TP = 0) {
    double sl = 0;
    double tp = 0;

    if (SL > 0)
        sl = NormalizeDouble(tick.bid + (SL), decimal);
    if (TP > 0)
        tp = NormalizeDouble(tick.bid - (TP), decimal);

    if (!ExtTrade.PositionOpen(_Symbol, ORDER_TYPE_SELL, getVolume(), tick.bid, sl, tp, comments)) {
        Print("Sell Order failed. Return code=", ExtTrade.ResultRetcode(),
              ". Code description: ", ExtTrade.ResultRetcodeDescription());
        Print("Bid: ", tick.bid, " SL: ", sl, " TP: ", tp);
    } else {
        // Print(("Order Sell Executed successfully!"));
        const string message = "Sell Signal for " + _Symbol;
        SendNotification(message);
    }
}

void closeAllTrade() {
    int total = PositionsTotal();
    for (int i = 0; i < total; i++) {
        ulong ticket = PositionGetTicket(i);

        if (!ExtTrade.PositionClose(ticket)) {
            Print("Close trade failed. Return code=", ExtTrade.ResultRetcode(),
                  ". Code description: ", ExtTrade.ResultRetcodeDescription());
        } else {
            if (PositionGetDouble(POSITION_PROFIT) > 0) {
                last_close_position.buySell = int(PositionGetInteger(POSITION_TYPE));
                last_close_position.price = PositionGetDouble(POSITION_PRICE_CURRENT);
            }
            // Print("Close position successfully!");
        }
    }
}

void updateSLTP() {
    MqlTradeRequest request;
    MqlTradeResult response;

    int total = PositionsTotal();

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
                if (trailing_sl && (stop_loss < tick.bid - (SL) || stop_loss == 0)) {
                    stop_loss = NormalizeDouble(tick.bid - (SL), decimal);
                }

                if (TP > 0) {
                    take_profit = NormalizeDouble(tick.bid + (TP), decimal);
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
                    // Print(("Order Update Stop Loss Buy Executed successfully!"));
                }
            } else {
                if (trailing_sl && (stop_loss > tick.ask + (SL) || stop_loss == 0)) {
                    stop_loss = NormalizeDouble(tick.ask + (SL), decimal);
                }

                if (TP > 0) {
                    take_profit = NormalizeDouble(tick.ask - (TP), decimal);
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
                    // Print(("Order Update Stop Loss Sell Executed successfully!"));
                }
            }
        }
    }
}

bool CheckForOpenTrade() {
    int total = PositionsTotal();

    if (total > 0) {
        return true;
    }

    last_close_position.buySell = NULL;

    return false;
}

void CheckPercentChange() {
    double last_price = last_close_position.price;

    double change = ((SymbolInfoDouble(_Symbol, SYMBOL_BID) - last_price) / last_price) * 100;

    if (MathAbs(change) > percent_change) {
        closeAllTrade();
        if (last_close_position.buySell == NULL) {
            if (change > 0) {
                printf("Buying after %.2f%% change", change);
                BuyAtMarket("Continue buy");
            } else {
                printf("Selling after %.2f%% change", change);
                SellAtMarket("Continue sell");
            }
        }

        if (last_close_position.buySell == POSITION_TYPE_BUY) {
            printf("Rebuying after %.2f%% change", change);
            BuyAtMarket("Continue buy");
        } else {
            printf("Reselling after %.2f%% change", change);
            SellAtMarket("Continue sell");
        }
    }
}

int getVolume() {
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

int fixedPercentageVol() {
    double cur_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double contract_price = cur_price * (contract_size / 10) / 3.67;
    double free_margin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
    double risk = max_risk;
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
//| Calculate optimal lot size                                       |
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

    double volume = NormalizeDouble(AccountInfoDouble(ACCOUNT_MARGIN_FREE) * max_risk / margin, 2);

    //--- calculate number of losses orders without a break1
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

    //--- return trading volume

    Print("Optimized Volume: ", volume);
    return (int)volume;
}

int boostVol(void) {
    double cur_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double contract_price = cur_price * (contract_size / 10);
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);

    int minRisk = 10;

    double risk = MathMin(MathSqrt(MathPow(boost_target, 2) / MathPow(balance, 2)) * minRisk, 100);
    double volume = equity * (risk / 100) / contract_price;

    printf("Risk: %.2f", risk);
    printf("Volume: %.2f", volume);

    double min_vol = 1;
    double max_vol = 300;

    if (volume < min_vol) {
        volume = min_vol;
    } else if (volume > max_vol) {
        volume = max_vol;
    }

    Print("Boost Volume: ", volume);

    return int(volume);
}

#endif  // MYINCLUDE_TRADEMANAGEMENT_MQH