//+------------------------------------------------------------------+
//|       Smart Single-Direction Grid EA v3.25 (OPTIMIZED SCALPER)  |
//|               Optimized for M1, M5, M15 Timeframes               |
//+------------------------------------------------------------------+
#property copyright "Smart Grid Pro v3.25 – Optimized Scalper Edition"
#property version   "3.25"
#property strict
#property description "Single-direction ATR Grid + Basket Protection (M1-M15) - Performance Optimized"

#include <Trade\Trade.mqh>
CTrade trade;

//+------------------------------------------------------------------+
//| INPUTS                                                           |
//+------------------------------------------------------------------+
input group "=== Trading Settings ==="
input ENUM_ORDER_TYPE   TradingDirection      = ORDER_TYPE_BUY;
input double            RiskPercentPerOrder   = 0.5;
input double            MaxTotalRiskPercent   = 10.0;

input group "=== Grid & Timeframe ==="
input ENUM_TIMEFRAMES   Timeframe             = PERIOD_CURRENT;
input int               MaxGridOrders         = 10;
input double            GridMultiplier        = 3.0;
input double            TPMultiplier          = 0.0;

input group "=== Basket Protection (Scalping Mode) ==="
input bool              UseBasketBreakeven    = true;
input double            BasketBE_TriggerPips  = 120;
input double            BasketBE_OffsetPips   = 15;

input bool              UseBasketTrailing     = true;
input double            BasketTrail_StartPips = 180;
input double            BasketTrail_Distance  = 100;

input group "=== Classic Backup Protection ==="
input bool              EnableClassicBE       = true;
input double            ClassicBE_TriggerPips = 80;
input double            ClassicBE_OffsetPips  = 10;

input bool              EnableClassicTrailing = true;
input double            ClassicTrail_StartPips = 150;
input double            ClassicTrail_StepPips = 50;
input double            ClassicTrail_DistancePips = 100;

input group "=== Safety ==="
input bool              EnableSpreadFilter    = true;
input double            MaxSpreadPips         = 3.0;        // FIX: Now in pips, clear meaning
input double            MaxDDPercentage       = 20.0;
input int               MagicNumber           = 999100;

input group "=== Performance Tuning ==="
input int               ProtectionCheckInterval = 500;      // NEW: Ms between protection checks (M1=500, M5=1000)
input bool              EnablePerformanceLog   = false;     // NEW: Log execution times

//+------------------------------------------------------------------+
//| GLOBALS                                                          |
//+------------------------------------------------------------------+
string   Sym;
double   PointSize, PipSize;
int      DigitsCount;
double   ContractSize, MinLot, MaxLot, LotStep;
double   CurrentATR, GridStep, LotSize;

int      atrHandle = INVALID_HANDLE;
datetime lastBarTime = 0;
datetime lastRecalc   = 0;
ulong    lastProtectionCheck = 0;                           // NEW: Throttle protection logic

// Performance cache
struct PositionCache
  {
   int      count;
   double   totalProfitPips;
   double   avgPrice;
   double   currentSL;
   ulong    lastUpdate;
  };
PositionCache posCache;

//+------------------------------------------------------------------+
//| INIT                                                             |
//+------------------------------------------------------------------+
int OnInit()
  {
   Sym = _Symbol;
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(30);
   trade.SetAsyncMode(false);                               // Ensure synchronous for M1 stability

   if(!SymbolInfoDouble(Sym,SYMBOL_POINT,PointSize)) return INIT_FAILED;
   DigitsCount = (int)SymbolInfoInteger(Sym,SYMBOL_DIGITS);
   ContractSize = SymbolInfoDouble(Sym,SYMBOL_TRADE_CONTRACT_SIZE);
   MinLot      = SymbolInfoDouble(Sym,SYMBOL_VOLUME_MIN);
   MaxLot      = SymbolInfoDouble(Sym,SYMBOL_VOLUME_MAX);
   LotStep     = SymbolInfoDouble(Sym,SYMBOL_VOLUME_STEP);

   // Smart PipSize detection
   if(StringFind(Sym,"BTC")!=-1 || StringFind(Sym,"ETH")!=-1)
      PipSize = 1.0;
   else if(StringFind(Sym,"XAU")!=-1 || StringFind(Sym,"XAG")!=-1)
      PipSize = 0.01;
   else if(StringFind(Sym,"JPY")!=-1)
      PipSize = 0.01;
   else
      PipSize = (DigitsCount==3||DigitsCount==5) ? 0.00010 : 0.00001;

   // Initialize ATR
   atrHandle = iATR(Sym,Timeframe,14);
   if(atrHandle==INVALID_HANDLE)
     {
      Print("ERROR: Cannot create ATR indicator");
      return INIT_FAILED;
     }

   string tfName = EnumToString(Timeframe);
   if(Timeframe == PERIOD_CURRENT)
      tfName = EnumToString((ENUM_TIMEFRAMES)Period());

   Print("╔════════════════════════════════════════════════════════════╗");
   Print("║  Smart Scalper v3.25 OPTIMIZED                            ║");
   Print("╠════════════════════════════════════════════════════════════╣");
   Print("║  Symbol: ",Sym,"  |  TF: ",tfName,"                        ║");
   Print("║  Direction: ",(TradingDirection==ORDER_TYPE_BUY?"BUY":"SELL"),"  |  Magic: ",MagicNumber,"                   ║");
   Print("║  Protection Interval: ",ProtectionCheckInterval,"ms                      ║");
   Print("╚════════════════════════════════════════════════════════════╝");

   RecalculateParameters();
   InvalidateCache();

   EventSetTimer(60);
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   if(atrHandle!=INVALID_HANDLE)
      IndicatorRelease(atrHandle);

   Print("EA Stopped. Reason: ",reason);
  }

//+------------------------------------------------------------------+
//| MAIN TICK HANDLER - OPTIMIZED                                   |
//+------------------------------------------------------------------+
void OnTick()
  {
   ulong tickTime = GetTickCount64();

   // ═══════════════════════════════════════════════════════════════
   // CRITICAL SAFETY - Always Check
   // ═══════════════════════════════════════════════════════════════
   if(CheckMaxDrawdown())
     {
      CloseAllAndStop();
      return;
     }

   // ═══════════════════════════════════════════════════════════════
   // PROTECTION LOGIC - Throttled for Performance
   // ═══════════════════════════════════════════════════════════════
   if(tickTime - lastProtectionCheck >= ProtectionCheckInterval)
     {
      if(EnablePerformanceLog)
         Print("[PERF] Protection check started at ",tickTime);

      if(UseBasketBreakeven || UseBasketTrailing)
         ProcessBasketProtection();

      if(EnableClassicBE)
         ProcessClassicBreakeven();

      if(EnableClassicTrailing)
         ProcessClassicTrailing();

      lastProtectionCheck = tickTime;

      if(EnablePerformanceLog)
         Print("[PERF] Protection check completed in ",(GetTickCount64()-tickTime),"ms");
     }

   // ═══════════════════════════════════════════════════════════════
   // NEW BAR LOGIC - Grid Management
   // ═══════════════════════════════════════════════════════════════
   datetime cur = iTime(Sym,Timeframe,0);
   if(cur == lastBarTime) return;
   lastBarTime = cur;

   // Spread filter blocks NEW grid orders only
   if(EnableSpreadFilter && !IsSpreadOK())
     {
      if(EnablePerformanceLog)
         Print("[WARN] Spread too high, skipping grid placement");
      return;
     }

   // Periodic recalculation (every 6 hours)
   if(TimeCurrent()-lastRecalc > 21600)
     {
      RecalculateParameters();
      lastRecalc = TimeCurrent();
     }

   // Grid maintenance
   MaintainDynamicGrid();

   if(EnablePerformanceLog)
      Print("[PERF] OnTick total time: ",(GetTickCount64()-tickTime),"ms");
  }

void OnTimer()
  {
   // Timer-based backup protection check
   if(UseBasketBreakeven || UseBasketTrailing)
      ProcessBasketProtection();
  }

//+------------------------------------------------------------------+
//| RECALCULATE PARAMETERS - WITH VALIDATION                        |
//+------------------------------------------------------------------+
void RecalculateParameters()
  {
   ulong startTime = GetTickCount64();

   double atr[];
   ArraySetAsSeries(atr,true);

   if(CopyBuffer(atrHandle,0,0,1,atr)<=0)
     {
      Print("[ERROR] Failed to copy ATR buffer");
      return;
     }

   double newATR = atr[0];

   // Validate ATR
   if(newATR <= 0 || newATR > 1000.0 * PipSize)
     {
      Print("[ERROR] Invalid ATR value: ",newATR," - skipping recalculation");
      return;
     }

   CurrentATR = newATR;
   GridStep = CurrentATR * GridMultiplier;

   // ═══════════════════════════════════════════════════════════════
   // CRITICAL M1/M5 SAFETY: Minimum Grid Step
   // ═══════════════════════════════════════════════════════════════
   double spread = SymbolInfoInteger(Sym,SYMBOL_SPREAD) * PointSize;
   double stopLevel = SymbolInfoInteger(Sym,SYMBOL_TRADE_STOPS_LEVEL) * PointSize;
   double minStep = MathMax(spread * 4.0, stopLevel * 1.5);

   if(GridStep < minStep)
     {
      Print("[SAFETY] GridStep adjusted: ",DoubleToString(GridStep/PipSize,1),
            " → ",DoubleToString(minStep/PipSize,1)," pips (spread protection)");
      GridStep = minStep;
     }

   // ═══════════════════════════════════════════════════════════════
   // LOT SIZE CALCULATION - Optimized
   // ═══════════════════════════════════════════════════════════════
   double slPrice = GridStep * 2.0;
   double slPoints = slPrice / PointSize;

   double tickValue = SymbolInfoDouble(Sym,SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(Sym,SYMBOL_TRADE_TICK_SIZE);

   if(tickSize <= 0)
     {
      Print("[ERROR] Invalid tick size");
      return;
     }

   double valuePerPoint = tickValue / tickSize;
   double riskMoney = AccountInfoDouble(ACCOUNT_BALANCE) * RiskPercentPerOrder / 100.0;

   if(slPoints > 0 && valuePerPoint > 0)
      LotSize = riskMoney / (slPoints * valuePerPoint);
   else
      LotSize = MinLot;

   LotSize = NormalizeLot(LotSize);

   // Validate final lot size
   if(LotSize < MinLot || LotSize > MaxLot)
     {
      Print("[WARN] Calculated lot ",LotSize," out of range [",MinLot,"-",MaxLot,"]");
      LotSize = MathMax(MinLot, MathMin(LotSize, MaxLot));
     }

   InvalidateCache();

   Print("┌─────────────────────────────────────────────────────────┐");
   Print("│ PARAMETERS UPDATED                                      │");
   Print("├─────────────────────────────────────────────────────────┤");
   Print("│ ATR:      ",DoubleToString(CurrentATR/PipSize,1)," pips                              │");
   Print("│ GridStep: ",DoubleToString(GridStep/PipSize,1)," pips                              │");
   Print("│ LotSize:  ",DoubleToString(LotSize,3),"                                  │");
   Print("│ Spread:   ",DoubleToString(spread/PipSize,1)," pips                              │");
   Print("│ Time:     ",(GetTickCount64()-startTime),"ms                                 │");
   Print("└─────────────────────────────────────────────────────────┘");
  }

//+------------------------------------------------------------------+
//| DYNAMIC GRID - Enhanced Validation                              |
//+------------------------------------------------------------------+
void MaintainDynamicGrid()
  {
   CancelAllPending();

   double price = (TradingDirection==ORDER_TYPE_BUY) ? SymbolInfoDouble(Sym,SYMBOL_ASK)
                                                    : SymbolInfoDouble(Sym,SYMBOL_BID);

   if(price <= 0)
     {
      Print("[ERROR] Invalid price for grid placement");
      return;
     }

   int stopLevel = (int)SymbolInfoInteger(Sym,SYMBOL_TRADE_STOPS_LEVEL);
   double minDist = stopLevel * PointSize;
   int ordersPlaced = 0;

   for(int i=1; i<=MaxGridOrders; i++)
     {
      double level = 0.0;
      double tp = 0.0;

      if(TradingDirection==ORDER_TYPE_BUY)
        {
         level = NormalizeDouble(price - i*GridStep, DigitsCount);

         // Validate distance
         if(price - level < minDist)
           {
            if(EnablePerformanceLog && i==1)
               Print("[WARN] Grid level ",i," too close to price (",DoubleToString((price-level)/PipSize,1)," pips)");
            continue;
           }

         if(TPMultiplier > 0.0)
            tp = NormalizeDouble(level + GridStep * TPMultiplier, DigitsCount);

         if(trade.BuyLimit(LotSize, level, Sym, 0.0, tp, ORDER_TIME_GTC, 0, "Grid #"+(string)i))
            ordersPlaced++;
        }
      else
        {
         level = NormalizeDouble(price + i*GridStep, DigitsCount);

         // Validate distance
         if(level - price < minDist)
           {
            if(EnablePerformanceLog && i==1)
               Print("[WARN] Grid level ",i," too close to price (",DoubleToString((level-price)/PipSize,1)," pips)");
            continue;
           }

         if(TPMultiplier > 0.0)
            tp = NormalizeDouble(level - GridStep * TPMultiplier, DigitsCount);

         if(trade.SellLimit(LotSize, level, Sym, 0.0, tp, ORDER_TIME_GTC, 0, "Grid #"+(string)i))
            ordersPlaced++;
        }
     }

   if(EnablePerformanceLog)
      Print("[GRID] Placed ",ordersPlaced,"/",MaxGridOrders," orders");
  }

//+------------------------------------------------------------------+
//| BASKET PROTECTION - Cached for Performance                      |
//+------------------------------------------------------------------+
void ProcessBasketProtection()
  {
   UpdatePositionCache();

   if(posCache.count == 0) return;

   double curPrice = (TradingDirection==ORDER_TYPE_BUY) ? SymbolInfoDouble(Sym,SYMBOL_BID)
                                                        : SymbolInfoDouble(Sym,SYMBOL_ASK);

   // ═══════════════════════════════════════════════════════════════
   // BASKET BREAKEVEN
   // ═══════════════════════════════════════════════════════════════
   if(UseBasketBreakeven && posCache.totalProfitPips >= BasketBE_TriggerPips)
     {
      double newSL = NormalizeDouble(posCache.avgPrice +
                     (TradingDirection==ORDER_TYPE_BUY?1:-1) * BasketBE_OffsetPips * PipSize,
                     DigitsCount);

      // Validate minimum distance from current price
      double slDist = MathAbs(curPrice - newSL) / PipSize;
      if(slDist < 5.0)
        {
         if(EnablePerformanceLog)
            Print("[WARN] Basket BE SL too close to price (",DoubleToString(slDist,1)," pips)");
         return;
        }

      bool shouldUpdate = false;

      if(TradingDirection==ORDER_TYPE_BUY && newSL > posCache.currentSL)
         shouldUpdate = true;
      else if(TradingDirection==ORDER_TYPE_SELL && (posCache.currentSL==0 || newSL < posCache.currentSL))
         shouldUpdate = true;

      if(shouldUpdate)
        {
         ModifyAllSL(newSL);
         Print("✓ BASKET BREAKEVEN → SL = ",DoubleToString(newSL,DigitsCount)," (",DoubleToString(posCache.totalProfitPips,1)," pips profit)");
        }
     }

   // ═══════════════════════════════════════════════════════════════
   // BASKET TRAILING
   // ═══════════════════════════════════════════════════════════════
   if(UseBasketTrailing && posCache.totalProfitPips >= BasketTrail_StartPips)
     {
      double trailSL = NormalizeDouble(curPrice - (TradingDirection==ORDER_TYPE_BUY?1:-1) *
                                      BasketTrail_Distance * PipSize, DigitsCount);

      // Validate minimum distance
      double slDist = MathAbs(curPrice - trailSL) / PipSize;
      if(slDist < BasketTrail_Distance * 0.5)
        {
         if(EnablePerformanceLog)
            Print("[WARN] Basket Trail SL too aggressive");
         return;
        }

      bool shouldUpdate = false;

      if(TradingDirection==ORDER_TYPE_BUY && trailSL > posCache.currentSL)
         shouldUpdate = true;
      else if(TradingDirection==ORDER_TYPE_SELL && (posCache.currentSL==0 || trailSL < posCache.currentSL))
         shouldUpdate = true;

      if(shouldUpdate)
        {
         ModifyAllSL(trailSL);
         if(EnablePerformanceLog)
            Print("✓ BASKET TRAILING → SL = ",DoubleToString(trailSL,DigitsCount));
        }
     }
  }

//+------------------------------------------------------------------+
//| CLASSIC BREAKEVEN                                                |
//+------------------------------------------------------------------+
void ProcessClassicBreakeven()
  {
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket==0) continue;

      if(PositionGetInteger(POSITION_MAGIC)!=MagicNumber ||
         PositionGetString(POSITION_SYMBOL)!=Sym) continue;

      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double cur  = PositionGetDouble(POSITION_PRICE_CURRENT);
      double sl   = PositionGetDouble(POSITION_SL);

      double profitPips = (TradingDirection==ORDER_TYPE_BUY) ? (cur-open)/PipSize
                                                              : (open-cur)/PipSize;

      if(profitPips >= ClassicBE_TriggerPips && sl == 0)
        {
         double newSL = NormalizeDouble(open + (TradingDirection==ORDER_TYPE_BUY?1:-1) *
                                       ClassicBE_OffsetPips * PipSize, DigitsCount);

         if(trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP)))
           {
            if(EnablePerformanceLog)
               Print("✓ Classic BE applied to #",ticket);
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| CLASSIC TRAILING                                                 |
//+------------------------------------------------------------------+
void ProcessClassicTrailing()
  {
   double trailStart = ClassicTrail_StartPips * PipSize;
   double trailStep = ClassicTrail_StepPips * PipSize;
   double trailDist = ClassicTrail_DistancePips * PipSize;

   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket==0) continue;

      if(PositionGetInteger(POSITION_MAGIC)!=MagicNumber ||
         PositionGetString(POSITION_SYMBOL)!=Sym) continue;

      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double cur  = PositionGetDouble(POSITION_PRICE_CURRENT);
      double sl   = PositionGetDouble(POSITION_SL);

      double profitPrice = (TradingDirection==ORDER_TYPE_BUY) ? (cur-open) : (open-cur);

      if(profitPrice < trailStart) continue;

      double newSL = (TradingDirection==ORDER_TYPE_BUY) ? cur - trailDist : cur + trailDist;
      newSL = NormalizeDouble(newSL, DigitsCount);

      if((TradingDirection==ORDER_TYPE_BUY && newSL > sl + trailStep) ||
         (TradingDirection==ORDER_TYPE_SELL && (sl==0 || newSL < sl - trailStep)))
        {
         trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP));
        }
     }
  }

//+------------------------------------------------------------------+
//| PERFORMANCE CACHE MANAGEMENT                                     |
//+------------------------------------------------------------------+
void UpdatePositionCache()
  {
   ulong now = GetTickCount64();

   // Cache valid for 100ms on M1, 200ms on M5+
   if(now - posCache.lastUpdate < 100)
      return;

   posCache.count = 0;
   posCache.totalProfitPips = 0;
   posCache.avgPrice = 0;
   posCache.currentSL = (TradingDirection==ORDER_TYPE_BUY) ? 0 : 999999;

   double sumPrice = 0, sumVol = 0;

   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      if(PositionGetTicket(i)==0) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=MagicNumber ||
         PositionGetString(POSITION_SYMBOL)!=Sym) continue;

      posCache.count++;

      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double cur  = PositionGetDouble(POSITION_PRICE_CURRENT);
      double vol  = PositionGetDouble(POSITION_VOLUME);
      double sl   = PositionGetDouble(POSITION_SL);

      // Profit calculation
      double diff = (TradingDirection==ORDER_TYPE_BUY) ? (cur-open) : (open-cur);
      posCache.totalProfitPips += diff / PipSize;

      // Average price
      sumPrice += open * vol;
      sumVol += vol;

      // Current SL
      if(sl != 0)
        {
         if(TradingDirection==ORDER_TYPE_BUY && sl > posCache.currentSL)
            posCache.currentSL = sl;
         else if(TradingDirection==ORDER_TYPE_SELL && sl < posCache.currentSL)
            posCache.currentSL = sl;
        }
     }

   if(sumVol > 0)
      posCache.avgPrice = sumPrice / sumVol;

   posCache.lastUpdate = now;
  }

void InvalidateCache()
  {
   posCache.lastUpdate = 0;
  }

//+------------------------------------------------------------------+
//| HELPER FUNCTIONS                                                 |
//+------------------------------------------------------------------+
void ModifyAllSL(double sl)
  {
   int modified = 0;

   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket==0) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=MagicNumber ||
         PositionGetString(POSITION_SYMBOL)!=Sym) continue;

      double currentSL = PositionGetDouble(POSITION_SL);

      // Only modify if different by at least 1 point
      if(MathAbs(currentSL - sl) > PointSize)
        {
         if(trade.PositionModify(ticket, sl, PositionGetDouble(POSITION_TP)))
            modified++;
        }
     }

   if(modified > 0)
      InvalidateCache();
  }

void CancelAllPending()
  {
   for(int i=OrdersTotal()-1; i>=0; i--)
     {
      ulong t = OrderGetTicket(i);
      if(OrderGetInteger(ORDER_MAGIC)==MagicNumber &&
         OrderGetString(ORDER_SYMBOL)==Sym)
         trade.OrderDelete(t);
     }
  }

bool IsSpreadOK()
  {
   long spreadPoints = SymbolInfoInteger(Sym,SYMBOL_SPREAD);
   if(spreadPoints <= 0) return true;

   double spreadPips = spreadPoints * PointSize / PipSize;

   bool ok = spreadPips <= MaxSpreadPips;

   if(!ok && EnablePerformanceLog)
      Print("[SPREAD] Current: ",DoubleToString(spreadPips,1)," pips | Max: ",MaxSpreadPips," pips");

   return ok;
  }

bool CheckMaxDrawdown()
  {
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   if(bal <= 0) return false;

   double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
   double ddPercent = (bal - eq) / bal * 100.0;

   if(ddPercent >= MaxDDPercentage)
     {
      Print("╔═══════════════════════════════════════════════════════════╗");
      Print("║               MAXIMUM DRAWDOWN REACHED!                   ║");
      Print("╠═══════════════════════════════════════════════════════════╣");
      Print("║  Drawdown: ",DoubleToString(ddPercent,2),"% / Max: ",MaxDDPercentage,"%                  ║");
      Print("║  Balance:  $",DoubleToString(bal,2),"                                ║");
      Print("║  Equity:   $",DoubleToString(eq,2),"                                ║");
      Print("╚═══════════════════════════════════════════════════════════╝");
      return true;
     }

   return false;
  }

void CloseAllAndStop()
  {
   Print("⚠ EMERGENCY SHUTDOWN - Closing all positions...");

   int closed = 0;

   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
        {
         if(PositionGetString(POSITION_SYMBOL)==Sym &&
            PositionGetInteger(POSITION_MAGIC)==MagicNumber)
           {
            if(trade.PositionClose(ticket))
               closed++;
           }
        }
     }

   CancelAllPending();

   Print("✓ Closed ",closed," positions. EA removed.");
   ExpertRemove();
  }

double NormalizeLot(double lot)
  {
   lot = MathFloor(lot/LotStep) * LotStep;
   if(lot < MinLot) lot = MinLot;
   if(lot > MaxLot) lot = MaxLot;
   return NormalizeDouble(lot, (lot>=1) ? 1 : 2);
  }

int PositionsTotalByEA()
  {
   int c = 0;
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      if(PositionGetTicket(i)==0) continue;
      if(PositionGetString(POSITION_SYMBOL)==Sym &&
         PositionGetInteger(POSITION_MAGIC)==MagicNumber)
         c++;
     }
   return c;
  }

//+------------------------------------------------------------------+
//|                         END OF EA                                |
//+------------------------------------------------------------------+
