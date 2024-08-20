//+------------------------------------------------------------------+
//|                                              Moving Averages.mq5 |
//|                             Copyright 2000-2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2000-2024, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade\Trade.mqh>
#include <Arrays\ArrayObj.mqh>
#include <Arrays\ArrayLong.mqh>

input double MaximumRisk        = 0.02;    // Maximum Risk in percentage
input double DecreaseFactor     = 3;       // Descrease factor
input int    MovingPeriod       = 12;      // Moving Average period
input int    MovingShift        = 6;       // Moving Average shift
input double stopLossAmount      = 15;    // Stop Loss point

CArrayObj *openBacklog = new CArrayObj;
CArrayLong    *closeBacklog=new CArrayLong;
CArrayObj *newOpenBacklog = new CArrayObj;
CArrayLong *newCloseBacklog=new CArrayLong;

int max_log_len = 10;

int    ExtHandle=0;
bool   ExtHedging=false;

CTrade ExtTrade;

MqlTradeRequest request;
MqlTradeResult result;
MqlTradeCheckResult checkResult;

#define MA_MAGIC 1234501

class CTradeRequestWrapper : public CObject {
   public:
      MqlTradeRequest request; // MqlTradeRequest structure

      // Constructor
      CTradeRequestWrapper() {
         ZeroMemory(request); // Initialize the request to zero
      }
      
      // Copy constructor (optional)
      CTradeRequestWrapper(const CTradeRequestWrapper &src) {
         this.request = src.request;
      }

};

//+------------------------------------------------------------------+
//| Calculate optimal lot size                                       |
//+------------------------------------------------------------------+
double TradeSizeOptimized(void) {

   double price=0.0;
   double margin=0.0;

//--- select lot size
   if(!SymbolInfoDouble(_Symbol,SYMBOL_ASK,price))
      return(0.0);

   if(!OrderCalcMargin(ORDER_TYPE_BUY,_Symbol,1.0,price,margin))
      return(0.0);

   if(margin<=0.0)
      return(0.0);

   double lot=NormalizeDouble(AccountInfoDouble(ACCOUNT_MARGIN_FREE)*MaximumRisk/margin,2);

//--- calculate number of losses orders without a break1
   if(DecreaseFactor>0){

      //--- select history for access
      HistorySelect(0,TimeCurrent());
      //---
      int    orders=HistoryDealsTotal();  // total history deals
      int    losses=0;                    // number of losses orders without a break

      for(int i=orders-1;i>=0;i--){

         ulong ticket=HistoryDealGetTicket(i);

         if(ticket==0){

            Print("HistoryDealGetTicket failed, no trade history");
            break;
         }

         //--- check symbol
         if(HistoryDealGetString(ticket,DEAL_SYMBOL)!=_Symbol)
            continue;

         //--- check Expert Magic number
         if(HistoryDealGetInteger(ticket,DEAL_MAGIC)!=MA_MAGIC)
            continue;

         //--- check profit
         double profit=HistoryDealGetDouble(ticket,DEAL_PROFIT);

         if(profit>0.0)
            break;

         if(profit<0.0)
            losses++;

      }

      if(losses>1)
         lot=NormalizeDouble(lot-lot*losses/DecreaseFactor,1);

   }

//--- normalize and check limits
   double stepvol=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   lot=stepvol*NormalizeDouble(lot/stepvol,0);

   double minvol=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);

   if(lot<minvol)
      lot=minvol;

   double maxvol=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);

   if(lot>maxvol)
      lot=maxvol;

//--- return trading volume
   return(lot);
}

//+------------------------------------------------------------------+
//| Calculate stop loss position                               |
//+------------------------------------------------------------------+
double CalculateStopLossPoints(double lotSize) {

    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double stopLossPoints = (stopLossAmount / lotSize) / tickValue;

    return NormalizeDouble(stopLossPoints, _Digits);
}
//+------------------------------------------------------------------+
//| Check for open position conditions                               |
//+------------------------------------------------------------------+
bool CheckForOpen(void){
   MqlRates rt[2];

//--- go trading only for first ticks of new bar
   if(CopyRates(_Symbol,_Period,0,2,rt)!=2) {

      Print("CopyRates of ",_Symbol," failed, no history");
      return false;
   }

   if(rt[1].tick_volume>1)
      return false;

//--- get current Moving Average 
   double   ma[1];

   if(CopyBuffer(ExtHandle,0,0,1,ma)!=1) {

      Print("CopyBuffer from iMA failed, no data");
      return false;
   }

//--- check signals
   ENUM_ORDER_TYPE signal = WRONG_VALUE;
   double stopLossPrice = 0;
   double lotSize = TradeSizeOptimized();
   double stopLossPoints = CalculateStopLossPoints(lotSize);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE); // Use tickSize in the calculation

   bool order = false;

   ZeroMemory(request);  

   // request.magic = MA_MAGIC;
   
   if (rt[0].open > ma[0] && rt[0].close < ma[0]) {

      request.type=ORDER_TYPE_SELL;
      request.symbol=_Symbol;
      request.volume=lotSize;
      request.action=TRADE_ACTION_DEAL;
      request.type_filling=ORDER_FILLING_FOK;
      request.price=SymbolInfoDouble(_Symbol,SYMBOL_BID);
      request.sl=SymbolInfoDouble(_Symbol, SYMBOL_BID) + (stopLossPoints * tickSize);
      request.comment = "Cross down, Short";

      order = true;

      Print("Cross down, sell signal detected!");
   } else {
   
      if (rt[0].open < ma[0] && rt[0].close > ma[0]) {

         request.type=ORDER_TYPE_BUY;
         request.symbol=_Symbol;
         request.volume=lotSize;
         request.action=TRADE_ACTION_DEAL;
         request.type_filling=ORDER_FILLING_FOK;
         request.price=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
         request.sl=SymbolInfoDouble(_Symbol, SYMBOL_ASK) - (stopLossPoints * tickSize);
         request.comment = "Cross up, Long";

         order = true;

         Print("Cross up, buy signal detected!");
      }
   }
   //--- additional checking
   
   if (order) {
      if(OrderCheck(request,checkResult)){
         Print("Checked!");
      }else{
         Print("Not correct! ERROR :"+IntegerToString(checkResult.retcode));

         if (checkResult.retcode == TRADE_RETCODE_NO_MONEY) {
            ExpertRemove();  // This will stop the EA
            return false;
         }

         CTradeRequestWrapper *tradeRequestWrapper = new CTradeRequestWrapper();
         tradeRequestWrapper.request = request;
         openBacklog.Add(tradeRequestWrapper);

         delete tradeRequestWrapper;
         tradeRequestWrapper = NULL;
   
         return false;
      }

      if(OrderSend(request,result)){
         Print("Successful send!");
      }else{
         Print("Error order not send!");

         CTradeRequestWrapper *tradeRequestWrapper = new CTradeRequestWrapper();

         tradeRequestWrapper.request = request;
         openBacklog.Add(tradeRequestWrapper);

         delete tradeRequestWrapper;
         tradeRequestWrapper = NULL;

         return false;
      }

      if(result.retcode==TRADE_RETCODE_DONE || result.retcode==TRADE_RETCODE_PLACED){
         Print("Trade Placed!");
         return true;
      }else{

         CTradeRequestWrapper *tradeRequestWrapper = new CTradeRequestWrapper();

         tradeRequestWrapper.request = request;
         openBacklog.Add(tradeRequestWrapper);

         delete tradeRequestWrapper;
         tradeRequestWrapper = NULL;

         return false;
      }   
   }
   return true;
}

//+------------------------------------------------------------------+
//| Check for close position conditions                              |
//+------------------------------------------------------------------+
bool CheckForClose(void) {
   MqlRates rt[2];

   //--- go trading only for first ticks of new bar
   if(CopyRates(_Symbol,_Period,0,2,rt)!=2) {
      Print("CopyRates of ",_Symbol," failed, no history");
      return false;
   }
   
   if(rt[1].tick_volume>1)
      return false;

//--- get current Moving Average 
   double   ma[1];
   if(CopyBuffer(ExtHandle,0,0,1,ma)!=1) {
      Print("CopyBuffer from iMA failed, no data");
      return false;
   }

   int total_positions = PositionsTotal();

   int direction = 0; // 1 to close buy, 2 to close sell  

   if (rt[0].open > ma[0] && rt[0].close < ma[0]) {
      direction = 1;
      // Print("Cross down");
   } else {
      if (rt[0].open < ma[0] && rt[0].close > ma[0]) {
         direction = 2;
         // Print("Cross up");
      }
   }

   // Print("Direction: " + direction);

   if (direction == 0) {
      return false;
   }

   // Print("Total positions: " + total_positions);

   for (int i = total_positions-1; i > -1; i--) {
      // printf("Position %d", i);

      ZeroMemory(request);
      ZeroMemory(result);

      ulong position_ticket = PositionGetTicket(i);
      // Print("Position ticket: " + IntegerToString(position_ticket));

      if (PositionSelectByTicket(position_ticket)) { 
         
         // Print("Position selected");
         // Print("close position magic: " + IntegerToString(PositionGetInteger(POSITION_MAGIC)));
         // if (PositionGetInteger(POSITION_MAGIC) != MA_MAGIC) {

            long position_direction = PositionGetInteger(POSITION_TYPE);
            // Print("Position direction: " + IntegerToString(position_direction));        
            // Print("Position volume: " + DoubleToString(request.volume));
            
            if (direction == 1 && position_direction == POSITION_TYPE_BUY) {
               request.type = ORDER_TYPE_SELL;
               request.comment = "Cross down, Close buy position";
               // Print("Close sell position");

            } else if (direction == 2 && position_direction == POSITION_TYPE_SELL) {
                  request.type = ORDER_TYPE_BUY;
                  request.comment = "Cross up, Close sell position";
                  // Print("Close buy position");
                  
            } else {
               continue;
            }

            request.action = TRADE_ACTION_DEAL;
            request.position = position_ticket;
            request.symbol = _Symbol;
            request.volume = PositionGetDouble(POSITION_VOLUME);
            request.deviation = 10;
            request.type_filling=ORDER_FILLING_FOK;    

         // }

         if (OrderCheck(request, checkResult)) {
            Print("Checked!");
         } else {
            Print("Not correct! ERROR :" + IntegerToString(checkResult.retcode));

            if (checkResult.retcode == TRADE_RETCODE_NO_MONEY) {
            ExpertRemove();  // This will stop the EA
            return false;
            }

            closeBacklog.Add(position_ticket);
            continue;
         }

         if (OrderSend(request, result)) {
            Print("Successful send!");
         } else {
            Print("Error order not send!");
            closeBacklog.Add(position_ticket);
            continue;
         }

         if (result.retcode == TRADE_RETCODE_DONE || result.retcode == TRADE_RETCODE_PLACED) {
            Print("Trade Placed!");
         } else {
            closeBacklog.Add(position_ticket);
         }
      }
   }

   return true;
}

//+------------------------------------------------------------------+
//| Position select depending on netting or hedging                  |
//+------------------------------------------------------------------+
bool SelectPosition() {
   bool res=false;

   //--- check position in Hedging mode
   if(ExtHedging) {
      uint total=PositionsTotal();
      for(uint i=0; i<total; i++)
         {
         string position_symbol=PositionGetSymbol(i);
         if(_Symbol==position_symbol && MA_MAGIC==PositionGetInteger(POSITION_MAGIC))
            {
            res=true;
            break;
            }
         }
      }

//--- check position in Netting mode
   else {
      if(!PositionSelect(_Symbol))
         return(false);
      else
         return(PositionGetInteger(POSITION_MAGIC)==MA_MAGIC); //---check Magic number
      }

//--- result for Hedging mode
   return(res);
}

//+------------------------------------------------------------------+
//| Clear back log                                                   |
//+------------------------------------------------------------------+
void clearBacklog() {

   // Print("Clearing backlog");

   if (openBacklog.Total() == 0 && closeBacklog.Total() == 0) {
      return;
   }

   for (int i = 0; i < openBacklog.Total(); i++) {
      // Print("Placing pending order from backlog");

      double stopLossPrice = 0;
      double lotSize = TradeSizeOptimized();
      double stopLossPoints = CalculateStopLossPoints(lotSize);
      double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

      CTradeRequestWrapper *tradeRequestWrapper = new CTradeRequestWrapper();
      tradeRequestWrapper = (CTradeRequestWrapper *)openBacklog.At(i);

      if (tradeRequestWrapper != NULL) {
      

         if (tradeRequestWrapper.request.type == ORDER_TYPE_BUY) {
            tradeRequestWrapper.request.price=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
            tradeRequestWrapper.request.sl=SymbolInfoDouble(_Symbol, SYMBOL_ASK) - (stopLossPoints * tickSize);
            tradeRequestWrapper.request.comment = "Cross up, Long (Backlog)";
         } else if (tradeRequestWrapper.request.type == ORDER_TYPE_SELL) {
            tradeRequestWrapper.request.price=SymbolInfoDouble(_Symbol,SYMBOL_BID);
            tradeRequestWrapper.request.sl=SymbolInfoDouble(_Symbol, SYMBOL_BID) + (stopLossPoints * tickSize);
            tradeRequestWrapper.request.comment = "Cross down, Short (Backlog)";
         }

         if (OrderSend(tradeRequestWrapper.request, result)) {
            // Print("Pending order from backlog placed successfully with ticket: ", result.order);
            // delete openBacklog.At(i); // Delete the processed wrapper
         } else {

            if (result.retcode == TRADE_RETCODE_NO_MONEY) {
            ExpertRemove();  // This will stop the EA
            return;
            }

            if (result.retcode == TRADE_RETCODE_MARKET_CLOSED) {

               delete tradeRequestWrapper;
               tradeRequestWrapper = NULL;
               return;
            }

               newOpenBacklog.Add(tradeRequestWrapper);
            // Print("Failed to place pending order from backlog. Error code: ", GetLastError());
         }

      }

      delete tradeRequestWrapper;
      tradeRequestWrapper = NULL;
   }

   for (int i = 0; i < closeBacklog.Total(); i++) {

      // Print("Closing position from backlog");
      ZeroMemory(request);
      ZeroMemory(result);

      ulong position_ticket = closeBacklog.At(i);

      if (PositionSelectByTicket(position_ticket)) {

         // Print("position magic: " + IntegerToString(PositionGetInteger(POSITION_MAGIC)));
         // if (PositionGetInteger(POSITION_MAGIC) != MA_MAGIC) {

            long position_direction = PositionGetInteger(POSITION_TYPE);

            if (position_direction == POSITION_TYPE_BUY) {
               request.type = ORDER_TYPE_SELL;
               request.comment = "Close buy position (Backlog)";
            } else if (position_direction == POSITION_TYPE_SELL) {
                  request.type = ORDER_TYPE_BUY;
                  request.comment = "Close sell position (Backlog)";
            } else {
               continue;
            }

            request.action = TRADE_ACTION_DEAL;
            request.position = position_ticket;
            request.symbol = _Symbol;
            request.volume = PositionGetDouble(POSITION_VOLUME);
            request.deviation = 10;
            request.type_filling=ORDER_FILLING_FOK;

         if (OrderCheck(request, checkResult)) {
            Print("Checked!");
         } else {

            if (checkResult.retcode == TRADE_RETCODE_NO_MONEY) {
            ExpertRemove();  // This will stop the EA
            return;
            }

            if (checkResult.retcode == TRADE_RETCODE_MARKET_CLOSED) {
               break;
            }

            newCloseBacklog.Add(position_ticket);

            Print("Not correct! ERROR :" + IntegerToString(checkResult.retcode));
            continue;
         }

         if (OrderSend(request, result)) {
            Print("Successful send!");
         } else {
            if (newCloseBacklog.Total() < max_log_len) {
               newCloseBacklog.Add(position_ticket);
            }
            Print("Error order not send!");
            continue;
         }

         if (result.retcode == TRADE_RETCODE_DONE || result.retcode == TRADE_RETCODE_PLACED) {
            Print("Trade Placed!");
            continue;
         } else {

            newCloseBacklog.Add(position_ticket);
            continue;
         }
         // }
      }
   }

   openBacklog.Clear();
   closeBacklog.Clear();

   openBacklog = newOpenBacklog;
   closeBacklog = newCloseBacklog;

   newOpenBacklog.Clear();
   newCloseBacklog.Clear();
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+

int OnInit(void) {

   //--- prepare trade class to control positions if hedging mode is active
   ExtHedging=((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE)==ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);
   ExtTrade.SetExpertMagicNumber(MA_MAGIC);
   ExtTrade.SetMarginMode();
   ExtTrade.SetTypeFillingBySymbol(Symbol());

   //--- Moving Average indicator
   ExtHandle=iMA(_Symbol,_Period,MovingPeriod,MovingShift,MODE_EMA,PRICE_CLOSE);
   if(ExtHandle==INVALID_HANDLE)
      {
      printf("Error creating MA indicator");
      return(INIT_FAILED);
      }

   //--- ok
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+

void OnTick(void) {
   CheckForClose();
   CheckForOpen();
   clearBacklog();

//---
//   if(SelectPosition()){
//      CheckForClose();
//      CheckForOpen();
//   }
//   else
//      CheckForOpen();
//---
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+

void OnDeinit(const int reason)
 {
 }

//+------------------------------------------------------------------+