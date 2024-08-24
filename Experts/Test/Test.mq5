//+------------------------------------------------------------------+
//|                                                         Test.mq5 |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#include <Trade/AccountInfo.mqh>
//+------------------------------------------------------------------+
//| Input variables                                                  |
//+------------------------------------------------------------------+
input int fast_ema_period = 13;  // Fast EMA period
input int slow_ema_period = 48;  // Slow EMA period

input double SL = 100;  // Stop Loss
input double TP = 100;  // Take Profit

input int max_risk = 10;  // Maximum risk (%) per trade

//+------------------------------------------------------------------+
//| Variable for indicators                                          |
//+------------------------------------------------------------------+
int fast_ema_handle;       // Handle Fast EMA
double fast_ema_buffer[];  // Buffer Fast EMA

int slow_ema_handle;       // Handle Slow EMA
double slow_ema_buffer[];  // Buffer Slow EMA

//+------------------------------------------------------------------+
//| Variable for functions                                           |
//+------------------------------------------------------------------+
int magic_number = 50357114;  // Magic number

MqlRates candle[];  // Variable for storing candles
MqlTick tick;       // Variable for storing ticks

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
  // Create slow EMA
  fast_ema_handle = iMA(_Symbol, _Period, fast_ema_period, 0, MODE_EMA, PRICE_CLOSE);
  slow_ema_handle = iMA(_Symbol, _Period, slow_ema_period, 0, MODE_EMA, PRICE_CLOSE);

  // Check if the EMA was created successfully
  if (fast_ema_handle == INVALID_HANDLE || slow_ema_handle == INVALID_HANDLE) {
    Alert("Error trying to create Handles for indicator - error: ", GetLastError(), "!");

    return -1;
  }

  CopyRates(_Symbol, _Period, 0, 4, candle);
  ArraySetAsSeries(candle, true);

  ChartIndicatorAdd(0, 0, fast_ema_handle);
  ChartIndicatorAdd(0, 0, slow_ema_handle);

  return (INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
  IndicatorRelease(fast_ema_handle);
  IndicatorRelease(slow_ema_handle);
}
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
  CopyBuffer(fast_ema_handle, 0, 0, 4, fast_ema_buffer);
  CopyBuffer(slow_ema_handle, 0, 0, 4, slow_ema_buffer);

  // Feed candle buffers with data
  CopyRates(_Symbol, _Period, 0, 4, candle);
  ArraySetAsSeries(candle, true);

  // Sort the data vector
  ArraySetAsSeries(fast_ema_buffer, true);
  ArraySetAsSeries(slow_ema_buffer, true);

  SymbolInfoTick(_Symbol, tick);

  bool buy_ma_cross = fast_ema_buffer[0] > slow_ema_buffer[0] && fast_ema_buffer[1] < slow_ema_buffer[1];
  bool sell_ma_cross = fast_ema_buffer[0] < slow_ema_buffer[0] && fast_ema_buffer[1] > slow_ema_buffer[1];

  bool Buy = false;
  bool Sell = false;

  Buy = buy_ma_cross;
  Sell = sell_ma_cross;

  bool newBar = isNewBar();

  if (newBar) {
    if (Buy && PositionSelect(_Symbol) == false) {
      closeAllTrade();
      drawVerticalLine("Buy", candle[1].time, clrGreen);
      BuyAtMarket();
    }

    if (Sell && PositionSelect(_Symbol) == false) {
      closeAllTrade();
      drawVerticalLine("Sell", candle[1].time, clrRed);
      SellAtMarket();
    }
  }
}

//+------------------------------------------------------------------+
//| Useful functions                                                 |
//+------------------------------------------------------------------+
//--- for bar change
bool isNewBar() {
  static datetime last_time = 0;
  datetime lastbar_time = (datetime)SeriesInfoInteger(Symbol(), Period(), SERIES_LASTBAR_DATE);

  if (last_time == 0) {
    last_time = lastbar_time;
    return false;
  }

  if (last_time != lastbar_time) {
    last_time = lastbar_time;
    return true;
  }

  return false;
}

//+------------------------------------------------------------------+
//| FUNCTIONS TO ASSIST IN THE VISUALIZATION OF THE STRATEGY         |
//+------------------------------------------------------------------+
void drawVerticalLine(string name, datetime dt, color cor = clrAliceBlue) {
  ObjectDelete(0, name);
  ObjectCreate(0, name, OBJ_VLINE, 0, dt, 0);
  ObjectSetInteger(0, name, OBJPROP_COLOR, cor);
}

//+------------------------------------------------------------------+
//| FUNCTIONS FOR SENDING ORDERS                                     |
//+------------------------------------------------------------------+
void BuyAtMarket() {
  MqlTradeRequest request;
  MqlTradeResult response;

  ZeroMemory(request);
  ZeroMemory(response);

  request.action = TRADE_ACTION_DEAL;
  request.magic = magic_number;
  request.symbol = _Symbol;
  request.volume = get_volume();
  request.price = NormalizeDouble(tick.ask, _Digits);
  if (SL > 0)
    request.sl = NormalizeDouble(tick.ask - (SL / _Point), _Digits);
  if (TP > 0)
    request.tp = NormalizeDouble(tick.ask + (TP / _Point), _Digits);
  request.deviation = 0;
  request.type = ORDER_TYPE_BUY;
  request.type_filling = ORDER_FILLING_FOK;

  OrderSend(request, response);

  if (response.retcode == 10008 || response.retcode == 10009) {
    Print(("Order Buy Executed successfully!"));
  } else {
    Print("Error sending Order to Buy. Error = ", GetLastError());
    ResetLastError();
  }
}

void SellAtMarket() {
  MqlTradeRequest request;
  MqlTradeResult response;

  ZeroMemory(request);
  ZeroMemory(response);

  request.action = TRADE_ACTION_DEAL;
  request.magic = magic_number;
  request.symbol = _Symbol;
  request.volume = get_volume();
  request.price = NormalizeDouble(tick.bid, _Digits);
  if (SL > 0)
    request.sl = NormalizeDouble(tick.ask - (SL / _Point), _Digits);
  if (TP > 0)
    request.tp = NormalizeDouble(tick.ask + (TP / _Point), _Digits);
  request.deviation = 0;
  request.type = ORDER_TYPE_SELL;
  request.type_filling = ORDER_FILLING_FOK;

  OrderSend(request, response);

  if (response.retcode == 10008 || response.retcode == 10009) {
    Print(("Order Sell Executed successfully!"));
  } else {
    Print("Error sending Order to Sell. Error = ", GetLastError());
    ResetLastError();
  }
}

void CloseBuy(double lot_size = 0.01) {
  MqlTradeRequest request;
  MqlTradeResult response;

  ZeroMemory(request);
  ZeroMemory(response);

  request.action = TRADE_ACTION_DEAL;
  request.magic = magic_number;
  request.symbol = _Symbol;
  request.volume = lot_size;
  request.price = NormalizeDouble(tick.bid, _Digits);
  request.type = ORDER_TYPE_SELL;
  request.type_filling = ORDER_FILLING_FOK;

  OrderSend(request, response);

  if (response.retcode == 10008 || response.retcode == 10009) {
    Print(("Order Close Buy Executed successfully!"));
  } else {
    Print("Error sending Order to Close Buy. Error = ", GetLastError());
    ResetLastError();
  }
}

void CloseSell(double lot_size = 0.01) {
  MqlTradeRequest request;
  MqlTradeResult response;

  ZeroMemory(request);
  ZeroMemory(response);

  request.action = TRADE_ACTION_DEAL;
  request.magic = magic_number;
  request.symbol = _Symbol;
  request.volume = lot_size;
  request.price = NormalizeDouble(tick.ask, _Digits);
  request.type = ORDER_TYPE_BUY;
  request.type_filling = ORDER_FILLING_FOK;

  OrderSend(request, response);

  if (response.retcode == 10008 || response.retcode == 10009) {
    Print(("Order Close Sell Executed successfully!"));
  } else {
    Print("Error sending Order to Close Sell. Error = ", GetLastError());
    ResetLastError();
  }
}

double get_volume() {
  double cur_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
  double contract_price = cur_price * 0.01 / 3.67;

  double free_margin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);

  double volume = free_margin * (max_risk / 100) / contract_price * 0.01;

  double min_vol = 0.01;
  double max_vol = 300;

  Print("Volume: ", volume);
  Print("Free Margin: ", free_margin);
  Print("Max Volume: ", max_vol);

  if (volume < min_vol) {
    volume = min_vol;
  } else if (volume > max_vol) {
    volume = max_vol;
  }

  return volume;
}

void closeAllTrade() {
  int total = PositionsTotal();
  for (int i = 0; i < total; i++) {
    ulong ticket = PositionGetTicket(i);
    if (PositionSelectByTicket(ticket)) {
      double lot_size = PositionGetDouble(POSITION_VOLUME);

      if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
        //  get the volume of the position
        CloseBuy(lot_size);
      } else {
        CloseSell(lot_size);
      }
    }
  }
}