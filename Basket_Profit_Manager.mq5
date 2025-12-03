//+------------------------------------------------------------------+
//|                                          Basket_Profit_Manager.mq5 |
//|                        Basket Monitor & Manager - EDUCATIONAL USE |
//|                                    Fixed & Enhanced Version v2.00 |
//+------------------------------------------------------------------+
#property copyright "Educational Template - Enhanced"
#property version   "2.00"
#property description "Monitors & manages a basket of positions. DOES NOT OPEN TRADES."
#property description "FIXED: Basket equity calculation, P/L tracking, and optimization"

//+------------------------------------------------------------------+
//| INPUT PARAMETERS (Global Basket Rules)                           |
//+------------------------------------------------------------------+
input string   InpBasketName        = "MY_BASKET";      // Basket Identifier
input double   InpGlobalProfitTarget = 100.0;            // Global Profit Target (account currency)
input double   InpGlobalStopLoss    = -50.0;            // Global Stop Loss (account currency)
input bool     InpCloseAllOnTarget  = true;             // Close all on target/SL?
input string   InpWatchSymbols      = "EURUSD,GBPUSD,XAUUSD,USDJPY"; // Symbols to monitor (comma-separated)
input int      InpMagicNumberFilter = -1;               // Magic Number filter (-1 for all)
input int      InpDashboardUpdateSec = 1;               // Dashboard update frequency (seconds)
input bool     InpShowPerSymbolBreakdown = true;        // Show per-symbol breakdown?
input bool     InpEnableLogging     = true;             // Enable detailed logging?

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                 |
//+------------------------------------------------------------------+
string   watchSymbolsArray[];      // Array to store symbols to watch
double   totalNetProfit;           // Total P/L including swap and commission
double   totalFloatingPL;          // Unrealized profit only
int      totalPositions;           // Total positions in basket
datetime lastDashboardUpdate;      // Last time dashboard was updated
datetime lastCheckTime;            // Last time basket was checked

// Per-symbol tracking structure
struct SymbolMetrics
{
   string symbol;
   int positionCount;
   double netProfit;
   double floatingPL;
};

SymbolMetrics symbolMetrics[];

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Parse the watch symbols string into an array
   int symbolCount = StringSplit(InpWatchSymbols, ',', watchSymbolsArray);

   //--- Check if we have symbols to watch
   if(symbolCount < 1)
   {
      Print("ERROR: No symbols to watch. Check InpWatchSymbols parameter.");
      return(INIT_PARAMETERS_INCORRECT);
   }

   //--- Trim whitespace from all symbols and validate
   for(int i = 0; i < ArraySize(watchSymbolsArray); i++)
   {
      watchSymbolsArray[i] = StringTrim(watchSymbolsArray[i]);

      // Validate symbol exists
      if(!SymbolSelect(watchSymbolsArray[i], true))
      {
         Print("WARNING: Symbol ", watchSymbolsArray[i], " not found in Market Watch. Adding it...");
         SymbolSelect(watchSymbolsArray[i], true);
      }
   }

   //--- Initialize symbol metrics array
   ArrayResize(symbolMetrics, ArraySize(watchSymbolsArray));
   for(int i = 0; i < ArraySize(watchSymbolsArray); i++)
   {
      symbolMetrics[i].symbol = watchSymbolsArray[i];
      symbolMetrics[i].positionCount = 0;
      symbolMetrics[i].netProfit = 0.0;
      symbolMetrics[i].floatingPL = 0.0;
   }

   //--- Validate parameters
   if(InpGlobalProfitTarget <= 0)
   {
      Print("WARNING: Global Profit Target is <= 0. Profit target disabled.");
   }

   if(InpGlobalStopLoss >= 0)
   {
      Print("WARNING: Global Stop Loss should be negative. Current value: ", InpGlobalStopLoss);
   }

   //--- Print initialization info
   Print("╔════════════════════════════════════════════════════════════╗");
   Print("║        BASKET PROFIT MANAGER - INITIALIZED v2.00          ║");
   Print("╚════════════════════════════════════════════════════════════╝");
   Print("Basket Name: ", InpBasketName);
   Print("Monitoring ", ArraySize(watchSymbolsArray), " symbol(s): ", InpWatchSymbols);
   Print("Global Profit Target: ", InpGlobalProfitTarget, " | Global Stop Loss: ", InpGlobalStopLoss);
   Print("Magic Filter: ", (InpMagicNumberFilter == -1) ? "ALL" : IntegerToString(InpMagicNumberFilter));
   Print("Dashboard Update: Every ", InpDashboardUpdateSec, " second(s)");
   Print("Per-Symbol Breakdown: ", InpShowPerSymbolBreakdown ? "ENABLED" : "DISABLED");

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Calculate basket metrics on every tick for real-time monitoring
   CalculateBasketMetrics();

   //--- Check global rules (profit target / stop loss)
   CheckGlobalRules();

   //--- Update dashboard based on time interval
   datetime currentTime = TimeCurrent();
   if(currentTime - lastDashboardUpdate >= InpDashboardUpdateSec)
   {
      DisplayDashboard();
      lastDashboardUpdate = currentTime;
   }
}

//+------------------------------------------------------------------+
//| CalculateBasketMetrics: Core function - calculates totals        |
//| FIXED: Corrected equity calculation and P/L tracking             |
//+------------------------------------------------------------------+
void CalculateBasketMetrics()
{
   // Reset all metrics
   totalNetProfit = 0.0;
   totalFloatingPL = 0.0;
   totalPositions = 0;

   // Reset per-symbol metrics
   for(int i = 0; i < ArraySize(symbolMetrics); i++)
   {
      symbolMetrics[i].positionCount = 0;
      symbolMetrics[i].netProfit = 0.0;
      symbolMetrics[i].floatingPL = 0.0;
   }

   //--- Loop through ALL open positions in the account
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;

      string posSymbol = PositionGetString(POSITION_SYMBOL);
      long posMagic = PositionGetInteger(POSITION_MAGIC);

      //--- Apply filters: check if position matches our basket criteria
      if(!IsPositionInBasket(posSymbol, posMagic))
         continue;

      //--- Get position metrics
      double posProfit = PositionGetDouble(POSITION_PROFIT);      // Unrealized P/L
      double posSwap = PositionGetDouble(POSITION_SWAP);          // Swap charges
      double posCommission = PositionGetDouble(POSITION_COMMISSION); // Commission

      //--- Calculate total net profit (includes swap and commission)
      double posNetProfit = posProfit + posSwap + posCommission;

      //--- Update basket totals
      totalNetProfit += posNetProfit;
      totalFloatingPL += posProfit;  // Only unrealized profit (no swap/commission)
      totalPositions++;

      //--- Update per-symbol metrics
      int symbolIndex = GetSymbolIndex(posSymbol);
      if(symbolIndex >= 0)
      {
         symbolMetrics[symbolIndex].positionCount++;
         symbolMetrics[symbolIndex].netProfit += posNetProfit;
         symbolMetrics[symbolIndex].floatingPL += posProfit;
      }

      //--- Log position details (if enabled)
      if(InpEnableLogging && totalPositions <= 5) // Log first 5 positions only
      {
         Print("Position #", ticket, " | ", posSymbol,
               " | Profit: ", DoubleToString(posProfit, 2),
               " | Swap: ", DoubleToString(posSwap, 2),
               " | Commission: ", DoubleToString(posCommission, 2),
               " | Net: ", DoubleToString(posNetProfit, 2));
      }
   }
}

//+------------------------------------------------------------------+
//| IsPositionInBasket: Check if position belongs to monitored basket|
//+------------------------------------------------------------------+
bool IsPositionInBasket(const string symbol, const long magic)
{
   //--- Check symbol filter
   bool symbolMatch = false;
   for(int i = 0; i < ArraySize(watchSymbolsArray); i++)
   {
      if(watchSymbolsArray[i] == symbol)
      {
         symbolMatch = true;
         break;
      }
   }

   if(!symbolMatch)
      return false;

   //--- Check magic number filter
   if(InpMagicNumberFilter != -1 && magic != InpMagicNumberFilter)
      return false;

   return true;
}

//+------------------------------------------------------------------+
//| GetSymbolIndex: Get index of symbol in symbolMetrics array       |
//+------------------------------------------------------------------+
int GetSymbolIndex(const string symbol)
{
   for(int i = 0; i < ArraySize(symbolMetrics); i++)
   {
      if(symbolMetrics[i].symbol == symbol)
         return i;
   }
   return -1;
}

//+------------------------------------------------------------------+
//| CheckGlobalRules: Apply profit target/stop loss at basket level  |
//+------------------------------------------------------------------+
void CheckGlobalRules()
{
   //--- Check if we should close the entire basket
   bool closeBasket = false;
   string closeReason = "";

   //--- Global Profit Target check (only if positive)
   if(InpGlobalProfitTarget > 0 && totalNetProfit >= InpGlobalProfitTarget)
   {
      closeBasket = true;
      closeReason = StringFormat("PROFIT TARGET REACHED: %.2f >= %.2f",
                                  totalNetProfit, InpGlobalProfitTarget);
   }

   //--- Global Stop Loss check (only if negative)
   if(InpGlobalStopLoss < 0 && totalNetProfit <= InpGlobalStopLoss)
   {
      closeBasket = true;
      closeReason = StringFormat("STOP LOSS HIT: %.2f <= %.2f",
                                  totalNetProfit, InpGlobalStopLoss);
   }

   //--- Execute basket closure if triggered
   if(closeBasket && InpCloseAllOnTarget)
   {
      Print("╔════════════════════════════════════════════════════════════╗");
      Print("║           BASKET CLOSURE RULE TRIGGERED                   ║");
      Print("╚════════════════════════════════════════════════════════════╝");
      Print(closeReason);
      Print("Total Positions to Close: ", totalPositions);
      Print("Total Net Profit: ", DoubleToString(totalNetProfit, 2));

      CloseEntireBasket();
   }
}

//+------------------------------------------------------------------+
//| CloseEntireBasket: Close all positions in the monitored basket   |
//+------------------------------------------------------------------+
void CloseEntireBasket()
{
   Print("Initiating basket closure...");

   int successCount = 0;
   int failCount = 0;

   //--- Close from last to first to avoid index issues
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;

      string posSymbol = PositionGetString(POSITION_SYMBOL);
      long posMagic = PositionGetInteger(POSITION_MAGIC);

      //--- Check if position is in our basket
      if(!IsPositionInBasket(posSymbol, posMagic))
         continue;

      //--- Attempt to close position
      if(ClosePositionByTicket(ticket))
         successCount++;
      else
         failCount++;
   }

   //--- Print closure summary
   Print("════════════════════════════════════════════════════════════");
   Print("BASKET CLOSURE COMPLETE");
   Print("Successfully Closed: ", successCount);
   Print("Failed to Close: ", failCount);
   Print("════════════════════════════════════════════════════════════");
}

//+------------------------------------------------------------------+
//| ClosePositionByTicket: Helper to close individual position       |
//| FIXED: Enhanced error handling and logging                       |
//+------------------------------------------------------------------+
bool ClosePositionByTicket(ulong ticket)
{
   if(!PositionSelectByTicket(ticket))
   {
      Print("ERROR: Cannot select position #", ticket);
      return false;
   }

   MqlTradeRequest request = {};
   MqlTradeResult result = {};

   //--- Setup close request
   request.action = TRADE_ACTION_DEAL;
   request.position = ticket;
   request.symbol = PositionGetString(POSITION_SYMBOL);
   request.volume = PositionGetDouble(POSITION_VOLUME);
   request.deviation = 10; // Increased slippage tolerance
   request.magic = PositionGetInteger(POSITION_MAGIC);
   request.comment = InpBasketName + " Closure";

   //--- Determine close price based on position type
   ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

   if(posType == POSITION_TYPE_BUY)
   {
      request.type = ORDER_TYPE_SELL;
      request.price = SymbolInfoDouble(request.symbol, SYMBOL_BID);
   }
   else
   {
      request.type = ORDER_TYPE_BUY;
      request.price = SymbolInfoDouble(request.symbol, SYMBOL_ASK);
   }

   //--- Refresh symbol quotes before closing
   if(!SymbolInfoTick(request.symbol, MqlTick{}))
   {
      Print("WARNING: Failed to refresh tick for ", request.symbol);
   }

   //--- Send close order
   bool success = OrderSend(request, result);

   if(success && (result.retcode == TRADE_RETCODE_DONE || result.retcode == TRADE_RETCODE_PLACED))
   {
      Print("✓ Closed #", ticket, " | ", request.symbol,
            " | Volume: ", request.volume,
            " | Profit: ", DoubleToString(PositionGetDouble(POSITION_PROFIT), 2));
      return true;
   }
   else
   {
      Print("✗ FAILED to close #", ticket, " | ", request.symbol,
            " | Error: ", GetLastError(),
            " | RetCode: ", result.retcode,
            " | ", GetRetcodeDescription(result.retcode));
      return false;
   }
}

//+------------------------------------------------------------------+
//| GetRetcodeDescription: Human-readable trade return codes         |
//+------------------------------------------------------------------+
string GetRetcodeDescription(uint retcode)
{
   switch(retcode)
   {
      case TRADE_RETCODE_DONE: return "Request completed";
      case TRADE_RETCODE_PLACED: return "Order placed";
      case TRADE_RETCODE_REJECT: return "Request rejected";
      case TRADE_RETCODE_CANCEL: return "Request canceled";
      case TRADE_RETCODE_ERROR: return "Request processing error";
      case TRADE_RETCODE_TIMEOUT: return "Request timeout";
      case TRADE_RETCODE_INVALID: return "Invalid request";
      case TRADE_RETCODE_INVALID_VOLUME: return "Invalid volume";
      case TRADE_RETCODE_INVALID_PRICE: return "Invalid price";
      case TRADE_RETCODE_INVALID_STOPS: return "Invalid stops";
      case TRADE_RETCODE_TRADE_DISABLED: return "Trade disabled";
      case TRADE_RETCODE_MARKET_CLOSED: return "Market closed";
      case TRADE_RETCODE_NO_MONEY: return "Insufficient funds";
      case TRADE_RETCODE_PRICE_CHANGED: return "Price changed";
      case TRADE_RETCODE_PRICE_OFF: return "No quotes";
      case TRADE_RETCODE_INVALID_EXPIRATION: return "Invalid expiration";
      case TRADE_RETCODE_ORDER_CHANGED: return "Order changed";
      case TRADE_RETCODE_TOO_MANY_REQUESTS: return "Too many requests";
      case TRADE_RETCODE_NO_CHANGES: return "No changes";
      case TRADE_RETCODE_SERVER_DISABLES_AT: return "Auto-trading disabled";
      case TRADE_RETCODE_CLIENT_DISABLES_AT: return "Auto-trading disabled by client";
      case TRADE_RETCODE_LOCKED: return "Request locked";
      case TRADE_RETCODE_FROZEN: return "Order frozen";
      case TRADE_RETCODE_INVALID_FILL: return "Invalid fill type";
      case TRADE_RETCODE_CONNECTION: return "No connection";
      case TRADE_RETCODE_ONLY_REAL: return "Only real accounts allowed";
      case TRADE_RETCODE_LIMIT_ORDERS: return "Order limit reached";
      case TRADE_RETCODE_LIMIT_VOLUME: return "Volume limit reached";
      default: return "Unknown error";
   }
}

//+------------------------------------------------------------------+
//| DisplayDashboard: Shows basket status on chart                   |
//| FIXED: Corrected display logic and added per-symbol breakdown    |
//+------------------------------------------------------------------+
void DisplayDashboard()
{
   //--- Build dashboard text
   string dashboardText = "";

   //--- Header
   dashboardText += "╔═══════════════════════════════════════╗\n";
   dashboardText += "║   " + InpBasketName + " BASKET STATUS\n";
   dashboardText += "╚═══════════════════════════════════════╝\n";

   //--- Account info
   dashboardText += "Account Equity: " + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2) + "\n";
   dashboardText += "Account Balance: " + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) + "\n";
   dashboardText += "Time: " + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES|TIME_SECONDS) + "\n";
   dashboardText += "───────────────────────────────────────\n";

   //--- Basket metrics
   dashboardText += "Total Positions: " + IntegerToString(totalPositions) + "\n";
   dashboardText += "Net P/L (with swap/comm): " + FormatProfit(totalNetProfit) + "\n";
   dashboardText += "Floating P/L: " + FormatProfit(totalFloatingPL) + "\n";
   dashboardText += "───────────────────────────────────────\n";

   //--- Targets
   color targetColor = (totalNetProfit >= InpGlobalProfitTarget) ? clrLime : clrYellow;
   color slColor = (totalNetProfit <= InpGlobalStopLoss) ? clrRed : clrYellow;

   dashboardText += "Profit Target: " + DoubleToString(InpGlobalProfitTarget, 2);
   if(InpGlobalProfitTarget > 0)
   {
      double progressPct = (totalNetProfit / InpGlobalProfitTarget) * 100.0;
      dashboardText += " (" + DoubleToString(progressPct, 1) + "%)";
   }
   dashboardText += "\n";

   dashboardText += "Stop Loss: " + DoubleToString(InpGlobalStopLoss, 2);
   if(InpGlobalStopLoss < 0)
   {
      double slProgressPct = (totalNetProfit / InpGlobalStopLoss) * 100.0;
      dashboardText += " (" + DoubleToString(slProgressPct, 1) + "%)";
   }
   dashboardText += "\n";

   //--- Per-symbol breakdown
   if(InpShowPerSymbolBreakdown && totalPositions > 0)
   {
      dashboardText += "───────────────────────────────────────\n";
      dashboardText += "PER-SYMBOL BREAKDOWN:\n";

      for(int i = 0; i < ArraySize(symbolMetrics); i++)
      {
         if(symbolMetrics[i].positionCount > 0)
         {
            dashboardText += "  " + symbolMetrics[i].symbol + ": " +
                           IntegerToString(symbolMetrics[i].positionCount) + " pos | " +
                           FormatProfit(symbolMetrics[i].netProfit) + "\n";
         }
      }
   }

   //--- Status indicator
   dashboardText += "───────────────────────────────────────\n";
   string status = "MONITORING";
   if(totalNetProfit >= InpGlobalProfitTarget && InpGlobalProfitTarget > 0)
      status = "⚠ TARGET REACHED";
   else if(totalNetProfit <= InpGlobalStopLoss && InpGlobalStopLoss < 0)
      status = "⚠ STOP LOSS HIT";

   dashboardText += "Status: " + status + "\n";

   //--- Create or update chart label
   string objName = "BasketDashboard";

   if(ObjectFind(0, objName) < 0)
   {
      ObjectCreate(0, objName, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, objName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, objName, OBJPROP_XDISTANCE, 10);
      ObjectSetInteger(0, objName, OBJPROP_YDISTANCE, 20);
      ObjectSetInteger(0, objName, OBJPROP_FONTSIZE, 9);
      ObjectSetString(0, objName, OBJPROP_FONT, "Courier New");
   }

   //--- Update text and color
   ObjectSetString(0, objName, OBJPROP_TEXT, dashboardText);

   // Set color based on P/L
   color textColor = clrWhite;
   if(totalNetProfit > 0)
      textColor = clrLime;
   else if(totalNetProfit < 0)
      textColor = clrOrange;

   ObjectSetInteger(0, objName, OBJPROP_COLOR, textColor);

   //--- Refresh chart
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| FormatProfit: Format profit/loss with color indicators           |
//+------------------------------------------------------------------+
string FormatProfit(double value)
{
   string formatted = DoubleToString(value, 2);

   if(value > 0)
      return "+" + formatted;
   else
      return formatted;
}

//+------------------------------------------------------------------+
//| StringTrim: Helper to trim whitespace from string                |
//+------------------------------------------------------------------+
string StringTrim(const string str)
{
   string result = str;
   StringTrimLeft(result);
   StringTrimRight(result);
   return result;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- Clean up chart objects
   ObjectDelete(0, "BasketDashboard");

   //--- Print deinitalization reason
   string reasonText = "";
   switch(reason)
   {
      case REASON_PROGRAM: reasonText = "EA stopped by user"; break;
      case REASON_REMOVE: reasonText = "EA removed from chart"; break;
      case REASON_RECOMPILE: reasonText = "EA recompiled"; break;
      case REASON_CHARTCHANGE: reasonText = "Chart symbol/period changed"; break;
      case REASON_CHARTCLOSE: reasonText = "Chart closed"; break;
      case REASON_PARAMETERS: reasonText = "Input parameters changed"; break;
      case REASON_ACCOUNT: reasonText = "Account changed"; break;
      default: reasonText = "Unknown reason (" + IntegerToString(reason) + ")"; break;
   }

   Print("╔════════════════════════════════════════════════════════════╗");
   Print("║      BASKET PROFIT MANAGER - DEINITIALIZED                ║");
   Print("╚════════════════════════════════════════════════════════════╝");
   Print("Reason: ", reasonText);
   Print("Final Net P/L: ", DoubleToString(totalNetProfit, 2));
   Print("Total Positions at Exit: ", totalPositions);
}
//+------------------------------------------------------------------+
