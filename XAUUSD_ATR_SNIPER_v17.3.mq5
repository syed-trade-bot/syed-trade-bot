//+------------------------------------------------------------------+
//|            XAUUSD ATR SNIPER v17.3 (ENHANCED DEBUG)              |
//|               COMPREHENSIVE MA GAP & SIGNAL ANALYSIS             |
//+------------------------------------------------------------------+
#property copyright "2025"
#property version   "17.3"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//==================================================================
// INPUTS
//==================================================================
input group    "Money Management"
input double   RiskPercent        = 2.0;
input double   MaxLots            = 1.0;

input group    "Strategy Settings"
input int      Magic              = 999888;
input bool     UseTrendFilter     = true;
input bool     UseADXFilter       = true;

input group    "ATR Trailing Settings"
input double   ATR_SL_Multiplier  = 2.0;
input double   ATR_Trail_Mult     = 1.5;
input bool     Trail_Immediate    = false;

input group    "Time Settings"
input bool     TradeLondonNY      = true;

input group    "Debug Settings"
input bool     EnableDebug        = true;
input bool     ShowDetailedDebug  = true;  // NEW: Show detailed analysis
input int      DebugFrequency     = 1;     // NEW: Print debug every N bars (1=every bar)

//==================================================================
// HANDLES & GLOBALS
//==================================================================
int h_RSI, h_FastMA, h_SlowMA, h_TrendMA, h_ATR, h_ADX;
int debugCounter = 0;

//==================================================================
// ONINIT
//==================================================================
int OnInit()
  {
   h_RSI     = iRSI(_Symbol, PERIOD_M15, 14, PRICE_CLOSE);
   h_FastMA  = iMA(_Symbol, PERIOD_M15, 8, 0, MODE_EMA, PRICE_CLOSE);
   h_SlowMA  = iMA(_Symbol, PERIOD_M15, 21, 0, MODE_EMA, PRICE_CLOSE);
   h_TrendMA = iMA(_Symbol, PERIOD_M15, 200, 0, MODE_EMA, PRICE_CLOSE);
   h_ATR     = iATR(_Symbol, PERIOD_M15, 14);
   h_ADX     = iADX(_Symbol, PERIOD_M15, 14);

   if(h_RSI==INVALID_HANDLE || h_FastMA==INVALID_HANDLE || h_SlowMA==INVALID_HANDLE ||
      h_TrendMA==INVALID_HANDLE || h_ATR==INVALID_HANDLE || h_ADX==INVALID_HANDLE)
     {
      Print("CRITICAL ERROR: Indicators failed to load.");
      return INIT_FAILED;
     }

   trade.SetExpertMagicNumber(Magic);
   trade.SetDeviationInPoints(20);
   trade.SetTypeFilling(ORDER_FILLING_FOK);

   Print("╔══════════════════════════════════════════════════════════════╗");
   Print("║     XAUUSD ATR SNIPER v17.3 :: ENHANCED DEBUG MODE          ║");
   Print("╠══════════════════════════════════════════════════════════════╣");
   PrintFormat("║ Risk: %.1f%% | MaxLots: %.2f | Magic: %d", RiskPercent, MaxLots, Magic);
   PrintFormat("║ Trend Filter: %s | ADX Filter: %s", UseTrendFilter?"ON":"OFF", UseADXFilter?"ON":"OFF");
   PrintFormat("║ Debug: %s | Detailed: %s | Frequency: Every %d bars",
               EnableDebug?"ON":"OFF", ShowDetailedDebug?"ON":"OFF", DebugFrequency);
   Print("╚══════════════════════════════════════════════════════════════╝");

   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   IndicatorRelease(h_RSI);
   IndicatorRelease(h_FastMA);
   IndicatorRelease(h_SlowMA);
   IndicatorRelease(h_TrendMA);
   IndicatorRelease(h_ATR);
   IndicatorRelease(h_ADX);
   Print(">>> XAUUSD ATR SNIPER v17.3 :: SHUTDOWN <<<");
  }

//==================================================================
// ONTICK
//==================================================================
void OnTick()
  {
   if(PositionsTotal() > 0) ManageATRTrailing();
   if(!IsNewBar()) return;

   debugCounter++;

   if(!IsTimeOK())
     {
      if(EnableDebug && debugCounter % DebugFrequency == 0)
         Print("[TIME FILTER] Outside trading hours");
      return;
     }

   if(HasPosition())
     {
      if(EnableDebug && debugCounter % DebugFrequency == 0)
         Print("[POSITION] Already in trade - monitoring");
      return;
     }

   // --- DATA COLLECTION ---
   double rsi[], fast[], slow[], trend[], adx[], atr[];
   ArraySetAsSeries(rsi,true); ArraySetAsSeries(fast,true);
   ArraySetAsSeries(slow,true); ArraySetAsSeries(trend,true);
   ArraySetAsSeries(adx,true); ArraySetAsSeries(atr,true);

   if(CopyBuffer(h_RSI,0,0,3,rsi)<0 || CopyBuffer(h_FastMA,0,0,3,fast)<0 ||
      CopyBuffer(h_SlowMA,0,0,3,slow)<0 || CopyBuffer(h_TrendMA,0,0,3,trend)<0 ||
      CopyBuffer(h_ADX,0,0,2,adx)<0 || CopyBuffer(h_ATR,0,0,2,atr)<0)
     {
      if(EnableDebug) Print("[ERROR] Failed to copy indicator buffers");
      return;
     }

   // --- CALCULATE KEY METRICS ---
   double maGap_Current  = fast[1] - slow[1];  // Current bar gap
   double maGap_Previous = fast[2] - slow[2];  // Previous bar gap
   double maGap_Pips     = maGap_Current / _Point;
   double maGap_Change   = maGap_Current - maGap_Previous;

   double trendDistance  = fast[1] - trend[1];
   double trendDist_Pips = trendDistance / _Point;

   bool isUptrend        = (fast[1] > trend[1]);
   bool isDowntrend      = (fast[1] < trend[1]);
   bool hasMomentum      = (adx[1] > 20);

   // Check for MA crossovers
   bool fastCrossedAboveSlow = (fast[1] > slow[1] && fast[2] <= slow[2]);
   bool fastCrossedBelowSlow = (fast[1] < slow[1] && fast[2] >= slow[2]);

   // --- DETAILED DEBUG OUTPUT ---
   if(EnableDebug && debugCounter % DebugFrequency == 0)
     {
      Print("┌────────────────────────────────────────────────────────────┐");
      PrintFormat("│ BAR #%d | %s", debugCounter, TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES));
      Print("├────────────────────────────────────────────────────────────┤");

      // MA GAP ANALYSIS
      string gapDirection = maGap_Current > 0 ? "BULLISH" : (maGap_Current < 0 ? "BEARISH" : "NEUTRAL");
      string gapTrend = maGap_Change > 0 ? "↑ EXPANDING" : (maGap_Change < 0 ? "↓ CONTRACTING" : "→ STABLE");

      PrintFormat("│ MA GAP: %.2f pips [%s] %s", maGap_Pips, gapDirection, gapTrend);
      PrintFormat("│   FastMA(8):  %.5f", fast[1]);
      PrintFormat("│   SlowMA(21): %.5f", slow[1]);
      PrintFormat("│   Gap Change: %.2f pips", (maGap_Change/_Point));
      Print("├────────────────────────────────────────────────────────────┤");

      // TREND ANALYSIS
      string trendStatus = isUptrend ? "UPTREND ▲" : (isDowntrend ? "DOWNTREND ▼" : "RANGING ─");
      PrintFormat("│ TREND: %s", trendStatus);
      PrintFormat("│   FastMA vs TrendMA(200): %.2f pips", trendDist_Pips);
      PrintFormat("│   TrendMA(200): %.5f", trend[1]);
      Print("├────────────────────────────────────────────────────────────┤");

      // MOMENTUM & OSCILLATORS
      string rsiStatus = rsi[1] >= 70 ? "OVERBOUGHT" : (rsi[1] <= 30 ? "OVERSOLD" : "NEUTRAL");
      string adxStatus = hasMomentum ? "STRONG" : "WEAK";

      PrintFormat("│ RSI(14):  %.1f [%s]", rsi[1], rsiStatus);
      PrintFormat("│ ADX(14):  %.1f [%s TREND]", adx[1], adxStatus);
      PrintFormat("│ ATR(14):  %.5f (%.1f pips)", atr[0], atr[0]/_Point);
      Print("├────────────────────────────────────────────────────────────┤");

      // CROSSOVER DETECTION
      if(fastCrossedAboveSlow)
         Print("│ *** BULLISH MA CROSS DETECTED! ***");
      else if(fastCrossedBelowSlow)
         Print("│ *** BEARISH MA CROSS DETECTED! ***");
      else if(MathAbs(maGap_Pips) < 5)
         Print("│ ⚠ MAs CONVERGING - Potential crossover soon");
      else
         PrintFormat("│ No crossover | Gap: %.1f pips from cross", MathAbs(maGap_Pips));

      Print("└────────────────────────────────────────────────────────────┘");
     }

   // --- ENTRY LOGIC WITH DETAILED BLOCKING REASONS ---
   double currentATR = atr[0];
   double slDist     = currentATR * ATR_SL_Multiplier;
   double lot        = GetLotSize(slDist);

   // BUY SIGNAL
   if(fastCrossedAboveSlow)
     {
      if(EnableDebug) Print("[SIGNAL] 🔔 BULLISH MA CROSSOVER DETECTED!");

      string blockReason = "";
      bool canTrade = true;

      if(UseTrendFilter && !isUptrend)
        {
         blockReason = StringFormat("Trend Filter (FastMA %.2f pips BELOW TrendMA)", -trendDist_Pips);
         canTrade = false;
        }
      else if(UseADXFilter && !hasMomentum)
        {
         blockReason = StringFormat("ADX Filter (ADX=%.1f < 20)", adx[1]);
         canTrade = false;
        }
      else if(rsi[1] >= 70)
        {
         blockReason = StringFormat("RSI Overbought (RSI=%.1f >= 70)", rsi[1]);
         canTrade = false;
        }

      if(canTrade)
        {
         double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double sl    = price - slDist;
         double tp    = price + (slDist * 1.5);

         if(EnableDebug)
           {
            Print("╔════════════════════════════════════════════════════════════╗");
            Print("║                    🚀 EXECUTING BUY TRADE                  ║");
            Print("╠════════════════════════════════════════════════════════════╣");
            PrintFormat("║ Entry:  %.5f | Lot: %.2f", price, lot);
            PrintFormat("║ SL:     %.5f (%.1f pips)", sl, slDist/_Point);
            PrintFormat("║ TP:     %.5f (%.1f pips)", tp, (slDist*1.5)/_Point);
            PrintFormat("║ Risk:   $%.2f (%.1f%%)", AccountInfoDouble(ACCOUNT_BALANCE) * (RiskPercent/100), RiskPercent);
            Print("╚════════════════════════════════════════════════════════════╝");
           }

         trade.Buy(lot, _Symbol, price, sl, tp, "ATR Sniper Buy");

         if(trade.ResultRetcode() != TRADE_RETCODE_DONE)
            PrintFormat("[ERROR] Trade failed: %s (%d)", trade.ResultRetcodeDescription(), trade.ResultRetcode());
        }
      else
        {
         if(EnableDebug)
            PrintFormat("[BLOCKED] ❌ BUY signal blocked by: %s", blockReason);
        }
     }

   // SELL SIGNAL
   if(fastCrossedBelowSlow)
     {
      if(EnableDebug) Print("[SIGNAL] 🔔 BEARISH MA CROSSOVER DETECTED!");

      string blockReason = "";
      bool canTrade = true;

      if(UseTrendFilter && !isDowntrend)
        {
         blockReason = StringFormat("Trend Filter (FastMA %.2f pips ABOVE TrendMA)", trendDist_Pips);
         canTrade = false;
        }
      else if(UseADXFilter && !hasMomentum)
        {
         blockReason = StringFormat("ADX Filter (ADX=%.1f < 20)", adx[1]);
         canTrade = false;
        }
      else if(rsi[1] <= 30)
        {
         blockReason = StringFormat("RSI Oversold (RSI=%.1f <= 30)", rsi[1]);
         canTrade = false;
        }

      if(canTrade)
        {
         double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double sl    = price + slDist;
         double tp    = price - (slDist * 1.5);

         if(EnableDebug)
           {
            Print("╔════════════════════════════════════════════════════════════╗");
            Print("║                    🚀 EXECUTING SELL TRADE                 ║");
            Print("╠════════════════════════════════════════════════════════════╣");
            PrintFormat("║ Entry:  %.5f | Lot: %.2f", price, lot);
            PrintFormat("║ SL:     %.5f (%.1f pips)", sl, slDist/_Point);
            PrintFormat("║ TP:     %.5f (%.1f pips)", tp, (slDist*1.5)/_Point);
            PrintFormat("║ Risk:   $%.2f (%.1f%%)", AccountInfoDouble(ACCOUNT_BALANCE) * (RiskPercent/100), RiskPercent);
            Print("╚════════════════════════════════════════════════════════════╝");
           }

         trade.Sell(lot, _Symbol, price, sl, tp, "ATR Sniper Sell");

         if(trade.ResultRetcode() != TRADE_RETCODE_DONE)
            PrintFormat("[ERROR] Trade failed: %s (%d)", trade.ResultRetcodeDescription(), trade.ResultRetcode());
        }
      else
        {
         if(EnableDebug)
            PrintFormat("[BLOCKED] ❌ SELL signal blocked by: %s", blockReason);
        }
     }

   // Show detailed convergence/divergence analysis if enabled
   if(ShowDetailedDebug && EnableDebug && debugCounter % DebugFrequency == 0)
     {
      PrintMaConvergenceStatus(maGap_Current, maGap_Previous, maGap_Pips);
     }
  }

//==================================================================
// CONVERGENCE ANALYSIS
//==================================================================
void PrintMaConvergenceStatus(double currentGap, double prevGap, double gapPips)
  {
   Print("┌─── MA CONVERGENCE ANALYSIS ───────────────────────────────┐");

   double gapChangePercent = (prevGap != 0) ? ((currentGap - prevGap) / MathAbs(prevGap)) * 100 : 0;

   if(MathAbs(gapPips) < 2)
     {
      Print("│ STATUS: ⚠️  CRITICAL ZONE - MAs very close!");
      Print("│ ACTION: High probability of crossover imminent");
     }
   else if(MathAbs(gapPips) < 5)
     {
      Print("│ STATUS: ⚡ WARNING - MAs converging");
      Print("│ ACTION: Monitor closely for potential crossover");
     }
   else if(MathAbs(gapChangePercent) > 10)
     {
      string direction = (currentGap > prevGap) ? "expanding" : "contracting";
      PrintFormat("│ STATUS: 📊 Gap %s rapidly (%.1f%% change)", direction, MathAbs(gapChangePercent));
     }
   else
     {
      Print("│ STATUS: ✓ MAs stable - No immediate crossover expected");
     }

   PrintFormat("│ Distance to Cross: %.2f pips", MathAbs(gapPips));
   Print("└───────────────────────────────────────────────────────────┘");
  }

//==================================================================
// TRAILING & UTILS
//==================================================================
void ManageATRTrailing()
  {
   double atrArr[];
   ArraySetAsSeries(atrArr, true);
   if(CopyBuffer(h_ATR, 0, 0, 1, atrArr) <= 0) return;
   double trailDist  = atrArr[0] * ATR_Trail_Mult;

   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetInteger(POSITION_MAGIC) != Magic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl        = PositionGetDouble(POSITION_SL);
      double tp        = PositionGetDouble(POSITION_TP);
      long   type      = PositionGetInteger(POSITION_TYPE);

      if(type == POSITION_TYPE_BUY)
        {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double profit = bid - openPrice;

         if(!Trail_Immediate && profit < trailDist) continue;

         double newSL = bid - trailDist;
         if(newSL > sl + _Point)
           {
            trade.PositionModify(ticket, newSL, tp);
            if(EnableDebug)
               PrintFormat("[TRAIL] BUY #%d | New SL: %.5f | Profit: %.1f pips",
                          ticket, newSL, profit/_Point);
           }
        }
      else
        {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double profit = openPrice - ask;

         if(!Trail_Immediate && profit < trailDist) continue;

         double newSL = ask + trailDist;
         if(newSL < sl - _Point || sl == 0)
           {
            trade.PositionModify(ticket, newSL, tp);
            if(EnableDebug)
               PrintFormat("[TRAIL] SELL #%d | New SL: %.5f | Profit: %.1f pips",
                          ticket, newSL, profit/_Point);
           }
        }
     }
  }

double GetLotSize(double slDistance)
  {
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk    = balance * (RiskPercent / 100.0);
   double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double slPoints = slDistance / _Point;
   if(slPoints == 0 || tickVal == 0) return 0.01;
   double lot = risk / (slPoints * tickVal);
   lot = NormalizeDouble(lot, 2);
   if(lot < 0.01) lot = 0.01;
   if(lot > MaxLots) lot = MaxLots;
   return lot;
  }

bool IsNewBar()
  {
   static datetime lastTime = 0;
   datetime timeArr[];
   if(CopyTime(_Symbol, PERIOD_M15, 0, 1, timeArr) <= 0) return false;
   if(timeArr[0] != lastTime) { lastTime = timeArr[0]; return true; }
   return false;
  }

bool IsTimeOK()
  {
   if(!TradeLondonNY) return true;
   MqlDateTime dt;
   TimeCurrent(dt);
   return (dt.hour >= 8 && dt.hour <= 20);
  }

bool HasPosition()
  {
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      if(PositionGetTicket(i) > 0)
         if(PositionGetInteger(POSITION_MAGIC) == Magic && PositionGetString(POSITION_SYMBOL) == _Symbol)
            return true;
     }
   return false;
  }
//+------------------------------------------------------------------+
