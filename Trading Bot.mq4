/*
The bot is working based on the signals of one of the most popular technical indicators - "Relative Strenght Index", or RSI to make things
simple. Below there are the parameters that the user can modify in order to make the bot do whatever the user wishes.

The bot also utilize (or rather allows user to implement if he/she wishes) martingale type of money management.
There are functions developed to prevent account from blowing up. The mechanism "equity protector" has been used. 
After every equity protector activation, the bot will wait 24h and start trading again autonomously.
A concept of averaging down has also been aplied, which means that the bot will keep buying when the price falls or keep selling 
when it rises.

"TS" stands for "trailing stop", which means that the stop loss order will follow along the price if it goes in favour of our
currently opened trades.
*/
extern double init_lot = 0.4;             //a position size that the bot will start to trade with 
extern double max_DD = -4000;             //a value that the loss is limited to 
extern double TP_value = 100;              
extern double lot_multiplier = 1.2;       //aa value that the position size will increase (multipling, martingale possible)
extern double order_distance = 20;       //a minimal value to place following orders
extern double distance_multiplier = 1.2;  
extern double distance_for_TS = 30;      
extern double RSI_long_period = 3;        //parameters of RSI indicator
extern double RSI_long_level = 15;        //parameters of RSI indicator
extern double RSI_short_period = 3;       //parameters of RSI indicator   
extern double RSI_short_level = 85;       //parameters of RSI indicator
extern int magicnumber = 11;              //parameter required by default MQL4 functions

double max_lots = 0;
double TS_distance = NormalizeDouble((distance_for_TS/2), Digits());

double bars_count = 0;
double m30_bars_count = 0;
bool main_long_in = False;
bool main_short_in = False;
datetime day_of_break;
datetime hour_of_break;
bool is_trading_allowed = True;
double EPs_hit = 0;

bool is_in_profit(string order_type)            //a function that checks if the trades on particular instrument are in profit overall
{                                            
   double result = 0;
   for (int i = OrdersTotal()-1; i >= 0; i--)
   {
      OrderSelect(i, SELECT_BY_POS, MODE_TRADES);
      if ((OrderSymbol() == ChartSymbol()) && (OrderType() == order_type))
      {
         result = result + OrderProfit();
      }  
   }
   if (result > 0)
   {
      return true;
   }
   else return false;
}

void closing(string order_type)                  //a function that closes all of the trades of the given type on particular instrument
{
   for (int i = OrdersTotal()-1; i >=0; i--)
   {
      OrderSelect(i, SELECT_BY_POS, MODE_TRADES);
      if ((OrderSymbol() == ChartSymbol()) && (OrderType() == order_type))
      {
         OrderClose(OrderTicket(), OrderLots(), OrderClosePrice(), 3, clrAqua);
      }
   }
}

double lot_calc(double orders)         //a function that calculates trade size (utilized when opening new trade)
{
   double lot = 0;
   if (orders == 0)
   {
      lot = init_lot;
   }
   else if (orders >= 1)
   {
      lot = NormalizeDouble((init_lot*MathPow(lot_multiplier, orders)), 2);
   }
   
   return (lot);
}

void DD_checking()                  //a function that checks whether the loss didn't reach the maximum level defined by user
{                                   
   double order_profit = 0;
   for (int x = OrdersTotal()-1; x >= 0; x--)
   {
      OrderSelect(x, SELECT_BY_POS, MODE_TRADES);
      if (OrderSymbol() == ChartSymbol())
      {
         order_profit = order_profit + OrderProfit();
      }
   }
   
   if (order_profit <= max_DD)      //if the maximum loss level is reached, all orders are closed and the parameters required
   {                                //to make bot not trade for next 24h are changed accordingly
      closing(OP_SELL);
      closing(OP_BUY);
      EPs_hit = EPs_hit + 1;
      is_trading_allowed = False;
      day_of_break = DayOfYear();
      hour_of_break = Hour();
   }
   
   if ((DayOfYear() > day_of_break) && (Hour() > hour_of_break))     //here after 24h of rest, bot is being allowed to trade again
   {
      is_trading_allowed = True;
   }
}

void long_signal()                    //a function that checks whether the criteria for main signal for BUY order are met
{                                     //also if there is/are existing SELL order(s) this function closes them
   double longs = 0;
   double lowest_long = 0;
   double shorts = 0;
   
   for (int i = OrdersTotal()-1; i >= 0; i--)
   {
      OrderSelect(i, SELECT_BY_POS, MODE_TRADES);
      if ((OrderSymbol() == ChartSymbol()) && (OrderType() == OP_BUY))
      {
         longs = longs+1;
         if (lowest_long == 0)
         {
            lowest_long = OrderOpenPrice();
         }
         else if (lowest_long != 0)
         {
            if (OrderOpenPrice() < lowest_long)
            {
               lowest_long = OrderOpenPrice();
            }
         }
      }
      else if ((OrderSymbol() == ChartSymbol()) && (OrderType() == OP_SELL))
      {
         shorts = shorts +1;
      } 
   }
   
   if ((iRSI(NULL, PERIOD_M30, RSI_long_period, 0, 1) < RSI_long_level) && (iRSI(NULL, PERIOD_M30, RSI_long_period, 0, 2) >= RSI_long_level))
   {
      if ((longs == 0) && (shorts == 0))
      {
         OrderSend(NULL, OP_BUY, lot_calc(longs), Ask, 3, NULL, Ask + TP_value, "main long", magicnumber, NULL, clrBlue);
         main_long_in = True;
      }
      if ((shorts >0) && (is_in_profit(OP_SELL) == True))
      {
         closing(OP_SELL);
         OrderSend(NULL, OP_BUY, lot_calc(longs), Ask, 3, NULL, Ask + TP_value, "main long", magicnumber, NULL, clrBlue);
         main_long_in = True;
      }
   }
}

void long_signal_m1()            //a function that checks if the criteria for additional trades are met 
{                                //       (only if the main trade from main signal is active)
   double longs = 0;
   double lowest_long = 0;
   double required_distance = 0;
   double multip = 0;
   
   for (int i = OrdersTotal()-1; i >= 0; i--)
   {
      OrderSelect(i, SELECT_BY_POS, MODE_TRADES);
      if ((OrderSymbol() == ChartSymbol()) && (OrderType() == OP_BUY))
      {
         longs = longs+1;
         if (lowest_long == 0)
         {
            lowest_long = OrderOpenPrice();
         }
         
         else if (lowest_long != 0)
         {
            if (OrderOpenPrice() < lowest_long)
            {
               lowest_long = OrderOpenPrice();
            }
         }
      }
   }
   
   if (longs == 1)
   {
      required_distance = order_distance;
   }
   else if (longs > 1)
   {
      multip = MathPow(distance_multiplier, longs-1);
      multip = NormalizeDouble(multip, 2);
      required_distance = NormalizeDouble((order_distance*multip), Digits());
   }
   
   if ((iRSI(NULL, PERIOD_M1, RSI_long_period, 0, 1) < RSI_long_level))
   {     
       if ((main_long_in == True) && (lowest_long - Ask >= required_distance))
      {
         OrderSend(NULL, OP_BUY, lot_calc(longs), Ask, 3, NULL, NULL, "M1 long", magicnumber, NULL, clrBlue);
      }
   }
}

void short_signal()                  //a function that checks whether the criteria for main signal for SELL order are met
{                                    //also if there is/are existing BUY order(s) this function closes them
   double shorts = 0;
   double highest_short = 0;
   double longs = 0;
   
   for (int i = OrdersTotal()-1; i >= 0; i--)
   {
      OrderSelect(i, SELECT_BY_POS, MODE_TRADES);
      if ((OrderSymbol() == ChartSymbol()) && (OrderType() == OP_SELL))
      {
         shorts = shorts+1;
         if (OrderOpenPrice() > highest_short)
         {
            highest_short = OrderOpenPrice();
         }
      }
      else if ((OrderSymbol() == ChartSymbol()) && (OrderType() == OP_BUY))
      {
         longs = longs +1;
      }
   }
   
   if ((iRSI(NULL, PERIOD_M30, RSI_short_period, 0, 1) > RSI_short_level) && (iRSI(NULL, PERIOD_M30, RSI_short_period, 0, 2) <= RSI_short_level))
   {
      if ((longs > 0 ) && (is_in_profit(OP_BUY)))
      {
         closing(OP_BUY);
         OrderSend(NULL, OP_SELL, lot_calc(shorts), Bid, 3, NULL, Bid - TP_value, "main short", magicnumber, NULL, clrRed);
         main_short_in = True;
      }
      if ((shorts == 0) && (longs == 0))
      {
      OrderSend(NULL, OP_SELL, lot_calc(shorts), Bid, 3, NULL, Bid - TP_value, "main short", magicnumber, NULL, clrRed);
      main_short_in = True;
      }
   }
}

void short_signal_m1()              //a function that checks if the criteria for additional SELL trades are met 
{                                   //       (only if the main trade from main signal is active)
   double shorts = 0;
   double highest_short = 0;
   double required_distance = 0;
   double multip = 0; 
   
   for (int i = OrdersTotal()-1; i >= 0; i--)
   {
      OrderSelect(i, SELECT_BY_POS, MODE_TRADES);
      if ((OrderSymbol() == ChartSymbol()) && (OrderType() == OP_SELL))
      {
         shorts = shorts+1;
      }
      
      if (OrderOpenPrice() > highest_short)
      {
         highest_short = OrderOpenPrice();
      }
   }
   
   if (shorts == 1)
   {
      required_distance = order_distance;
   }
   else if (shorts > 1)
   {
      multip = MathPow(distance_multiplier, shorts-1);
      multip = NormalizeDouble(multip, 2);
      required_distance = NormalizeDouble((order_distance*multip), Digits());
   }
   
   if ((iRSI(NULL, PERIOD_M1, RSI_short_period, 0, 1) > RSI_short_level))
   {     
       if ((main_short_in == True) && (Bid - highest_short >= required_distance))
      {
         OrderSend(NULL, OP_SELL, lot_calc(shorts), Bid, 3, NULL, NULL, "M1 short", magicnumber, NULL, clrRed);
      }
   }
}

void managing()                           //the function that makes "TS" working with all necessary calculations required
{                                         //is also detects whether the "main signals" are active, thanks to it the functions
   double longs_avg_price = 0;            //that execute additional signals can work properly
   double longs_counter = 0;
   double longs_lots = 0;
   double lots = 0;
   double shorts_avg_price = 0;
   double shorts_counter = 0;
   double shorts_lots = 0;
   
   double single_long_price = 0;
   double single_short_price = 0;
   
   double current_SL = 0;
   double upcoming_SL = 0;
   double upcoming_TP = 0;
   
   for (int i = OrdersTotal()-1; i >= 0; i--)
      {
         OrderSelect(i, SELECT_BY_POS, MODE_TRADES);
         if (OrderSymbol() == ChartSymbol())
         {
            lots = lots + OrderLots();
         }
         if ((OrderSymbol() == ChartSymbol()) && (OrderType() == OP_BUY))
         {
            longs_counter = longs_counter + 1;
            longs_lots = longs_lots + OrderLots();
            longs_avg_price = longs_avg_price + (OrderOpenPrice()*OrderLots());
            single_long_price = OrderOpenPrice();
         }
         else if ((OrderSymbol() == ChartSymbol()) && (OrderType() == OP_SELL))
         {
            shorts_counter = shorts_counter + 1;
            shorts_lots = shorts_lots + OrderLots();
            shorts_avg_price = shorts_avg_price + (OrderOpenPrice()*OrderLots());
            single_short_price = OrderOpenPrice();
         }
      }
      
   if (longs_counter == 1)
   {
      if ((Bid - single_long_price) >= distance_for_TS)
      {
         upcoming_SL = Bid - TS_distance;
         for (int u = OrdersTotal()-1; u >= 0; u--)
         {
            OrderSelect(u, SELECT_BY_POS, MODE_TRADES);
            if ((upcoming_SL > OrderStopLoss()) && (OrderSymbol() == ChartSymbol()) && (OrderType() == OP_BUY) && (upcoming_SL > OrderOpenPrice()))
            {
               OrderModify(OrderTicket(), NULL, upcoming_SL, NULL, NULL, clrPink);       
            }
         }
      }
   }
   
   if (shorts_counter == 1)
   {
      if ((single_short_price - Ask) >= distance_for_TS)
      {
         upcoming_SL = Ask + TS_distance;
         for (int z = OrdersTotal()-1; z >= 0; z--)
         {
            OrderSelect(z, SELECT_BY_POS, MODE_TRADES);
            if ((OrderSymbol() == ChartSymbol()) && (OrderType() == OP_SELL))
            {
               if (OrderStopLoss() == 0)
               {
                  OrderModify(OrderTicket(), NULL, upcoming_SL, NULL, NULL, clrPink);
               }
               else if ((OrderStopLoss() != 0) && (OrderStopLoss() > upcoming_SL))
               {
                  OrderModify(OrderTicket(), NULL, upcoming_SL, NULL, NULL, clrPink);
               }
            }
         }    
      }  
   }
   
   if (longs_counter > 1)
   {
      longs_avg_price = NormalizeDouble((longs_avg_price/longs_lots), Digits());

      if ((Bid - longs_avg_price) > distance_for_TS)       
      {
      upcoming_SL = Bid - TS_distance;
      upcoming_TP = longs_avg_price + TP_value;    
         for (int x = OrdersTotal()-1; x >= 0; x--)
         {
            OrderSelect(x, SELECT_BY_POS, MODE_TRADES);
            if ((OrderSymbol() == ChartSymbol()) && (OrderType() == OP_BUY) && (OrderStopLoss() < upcoming_SL))
            {
               OrderModify(OrderTicket(), NULL, upcoming_SL, upcoming_TP, NULL, clrPink);
            }
         }
      }
   }
   
   if (shorts_counter > 1)
   {
      shorts_avg_price = NormalizeDouble((shorts_avg_price/shorts_lots), Digits());

      if ((shorts_avg_price - Ask) > distance_for_TS)
      {
         upcoming_SL = Ask + TS_distance;
         upcoming_TP = shorts_avg_price - TP_value;
         for (int y = OrdersTotal()-1; y >= 0; y--)
         {
            OrderSelect(y, SELECT_BY_POS, MODE_TRADES);
            if ((OrderSymbol() == ChartSymbol()) && (OrderType() == OP_SELL))
            {
               if (OrderStopLoss() == 0)
                  OrderModify(OrderTicket(), NULL, upcoming_SL, upcoming_TP, NULL, clrPink);
               else if ((OrderStopLoss() != 0) && (OrderStopLoss() > upcoming_SL))
                  OrderModify(OrderTicket(), NULL, upcoming_SL, upcoming_TP, NULL, clrPink);
            }
         }
      }
   }
   
   if (shorts_counter == 0) 
   {
      main_short_in = False;
   }
   
   if (longs_counter == 0)
   {
      main_long_in = False;
   }
   if (lots > max_lots)
   {
      max_lots = lots;
   }
}

void OnTick()                 //the main function that is executed on every tick, which means "on every new quote that comes from the server"
{                             //most important functions such as 'managing()' and 'DD_checking()' are executed on every tick as they are responsible
  managing();                 //for stuff that can change within the second, so we want to be sure that we can capture that
  DD_checking();              
   if (Bars > bars_count)     //functions that open trades are executed everytime when new candle occurs on the chart 
   {
      long_signal_m1();
      short_signal_m1();
      Comment(main_long_in + "\n" + main_short_in);
      if ((iBars(NULL, PERIOD_M30) > m30_bars_count) && (is_trading_allowed == True))
      {
      long_signal();
      short_signal();
      
      m30_bars_count = iBars(NULL, PERIOD_M30);
      }
      
   bars_count = Bars;
   }
}
