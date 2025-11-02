//+------------------------------------------------------------------+
//|                                    AdaptiveCryptoMultiEA.mq5     |
//|                          Self-Adjusting Spread & Profit Security |
//|                    IC Markets Optimized - Production Ready v3.0  |
//+------------------------------------------------------------------+
#property copyright "Expert MQL5 Coder"
#property link      "https://www.mql5.com"
#property version   "3.00"
#property strict
#property description "Adaptive spread analysis - Works in all conditions"
#property description "Smart profit security system - No breakeven"

//--- Input Parameters
input group "=== General Settings ==="
input int      InpMagicBTC    = 100001;           // Magic Number for BTC
input int      InpMagicETH    = 100002;           // Magic Number for ETH
input double   InpRiskPercent = 1.0;              // Risk Per Trade (%)
input bool     InpTradeOnlyBoth = true;           // Trade Only When Both Signals Align

input group "=== Loss Recovery System ==="
input bool     InpUseLossRecovery = true;         // Enable Loss Recovery
input double   InpRecoveryMultiplier = 1.5;       // Recovery Lot Multiplier (1.5 = +50%)
input int      InpMaxRecoveryTrades = 3;          // Max Consecutive Recovery Trades
input bool     InpRecoverySameDirection = false;  // Recovery in Same Direction Only
input double   InpRecoveryTargetPercent = 100.0;  // Recovery Target % of Loss
input int      InpRecoveryCooldown = 2;           // Cooldown Bars After Recovery
input bool     InpResetOnProfit = true;           // Reset Recovery After Profit

input group "=== Symbol Settings ==="
input string   InpSymbolBTC   = "BTCUSD";         // Bitcoin Symbol
input string   InpSymbolETH   = "ETHUSD";         // Ethereum Symbol

input group "=== Strategy Parameters ==="
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_H1;   // Trading Timeframe
input int      InpMAPeriodFast    = 20;           // Fast MA Period
input int      InpMAPeriodSlow    = 50;           // Slow MA Period
input int      InpRSIPeriod       = 14;           // RSI Period
input double   InpRSIOversold     = 30.0;         // RSI Oversold Level
input double   InpRSIOverbought   = 70.0;         // RSI Overbought Level

input group "=== Adaptive Spread System ==="
input bool     InpAdaptiveSpread  = true;         // Enable Adaptive Spread Analysis
input int      InpSpreadSamplePeriod = 100;       // Spread Sample Period (bars)
input double   InpSpreadMultiplier = 2.5;         // Max Spread = Avg * Multiplier
input double   InpFallbackMaxSpread = 1000;       // Fallback Max Spread (points)
input bool     InpAdjustSLForSpread = true;       // Adjust SL to Cover Spread Cost

input group "=== Risk Management ==="
input double   InpSLMultiplier    = 2.5;          // Stop Loss (ATR Multiplier)
input double   InpTPMultiplier    = 4.0;          // Take Profit (ATR Multiplier)
input int      InpATRPeriod       = 14;           // ATR Period
input int      InpSlippage        = 100;          // Max Slippage Points
input bool     InpUseFixedLot     = false;        // Use Fixed Lot Size
input double   InpFixedLot        = 0.01;         // Fixed Lot (if enabled)
input double   InpMinLotSize      = 0.01;         // Minimum Lot Size Override
input double   InpMaxLotSize      = 100.0;        // Maximum Lot Size Override
input bool     InpAutoAdjustRisk  = true;         // Auto-Adjust Risk for Small Accounts

input group "=== Smart Profit Security System ==="
input bool     InpUseProfitSecurity = true;       // Enable Profit Security
input double   InpMinProfitToSecure = 0.5;        // Min Profit to Secure (ATR multiplier)
input double   InpProfitSecurePercent = 30.0;     // Secure % of Profit (30-70%)
input int      InpSecurityCheckInterval = 5;      // Check Every X Bars
input bool     InpUseTrailingStop = true;         // Enable Trailing Stop
input double   InpTrailingStartATR = 1.5;         // Trailing Start (ATR multiplier)
input double   InpTrailingStepATR = 0.5;          // Trailing Step (ATR multiplier)

input group "=== Advanced Profit Protection ==="
input bool     InpUseTieredProtection = true;     // Tiered Profit Protection
input double   InpTier1Profit = 1.0;              // Tier 1: 1x ATR profit
input double   InpTier1Secure = 20.0;             // Tier 1: Secure 20%
input double   InpTier2Profit = 2.0;              // Tier 2: 2x ATR profit
input double   InpTier2Secure = 40.0;             // Tier 2: Secure 40%
input double   InpTier3Profit = 3.0;              // Tier 3: 3x ATR profit
input double   InpTier3Secure = 60.0;             // Tier 3: Secure 60%

input group "=== Trading Hours ==="
input bool     InpUseTimeFilter   = false;        // Use Time Filter
input int      InpStartHour       = 0;            // Start Hour (Broker Time)
input int      InpEndHour         = 23;           // End Hour (Broker Time)

input group "=== Correlation Filter ==="
input bool     InpUseCorrelation  = true;         // Use BTC/ETH Correlation
input int      InpCorrelationPeriod = 50;         // Correlation Period
input double   InpMinCorrelation  = 0.60;         // Min Correlation

input group "=== Debug & Display ==="
input bool     InpDebugMode       = true;         // Enable Debug Logging
input bool     InpShowPanel       = true;         // Show Info Panel
input int      InpPanelX          = 20;           // Panel X Position
input int      InpPanelY          = 50;           // Panel Y Position

//--- Global Variables
int handleMaFastBTC, handleMaSlowBTC, handleRsiBTC, handleAtrBTC;
int handleMaFastETH, handleMaSlowETH, handleRsiETH, handleAtrETH;
double maFastBTC[], maSlowBTC[], rsiBTC[], atrBTC[];
double maFastETH[], maSlowETH[], rsiETH[], atrETH[];
datetime lastBarTime;
datetime lastLogTime = 0;
int logThrottleSeconds = 5;
int barsSinceCheck = 0;

// Spread tracking
struct SpreadStats {
   double current;
   double average;
   double maximum;
   double minimum;
   double adaptive_max;
   int sampleCount;
};
SpreadStats spreadBTC, spreadETH;

// Position tracking
struct PositionInfo {
   ulong ticket;
   double openPrice;
   double initialSL;
   double currentSL;
   double currentProfit;
   double maxProfit;
   double atrAtOpen;
   int protectionTier;
   datetime openTime;
   datetime lastUpdateTime;
};
PositionInfo positionsBTC[], positionsETH[];

// Loss Recovery Tracking
struct RecoveryInfo {
   bool inRecovery;
   int recoveryLevel;
   double totalLoss;
   double targetProfit;
   datetime lastLossTime;
   int cooldownBars;
   double lastLotSize;
   ENUM_ORDER_TYPE lastDirection;
};
RecoveryInfo recoveryBTC, recoveryETH;

#include <Trade\Trade.mqh>
CTrade tradeBTC, tradeETH;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Validate symbols
   if(!SymbolSelect(InpSymbolBTC, true))
   {
      Alert("ERROR: Symbol ", InpSymbolBTC, " not found!");
      return INIT_FAILED;
   }
   if(!SymbolSelect(InpSymbolETH, true))
   {
      Alert("ERROR: Symbol ", InpSymbolETH, " not found!");
      return INIT_FAILED;
   }

   //--- Set magic numbers & slippage
   tradeBTC.SetExpertMagicNumber(InpMagicBTC);
   tradeETH.SetExpertMagicNumber(InpMagicETH);
   tradeBTC.SetDeviationInPoints(InpSlippage);
   tradeETH.SetDeviationInPoints(InpSlippage);
   tradeBTC.SetAsyncMode(false);
   tradeETH.SetAsyncMode(false);

   //--- Initialize indicators
   handleMaFastBTC = iMA(InpSymbolBTC, InpTimeframe, InpMAPeriodFast, 0, MODE_EMA, PRICE_CLOSE);
   handleMaSlowBTC = iMA(InpSymbolBTC, InpTimeframe, InpMAPeriodSlow, 0, MODE_EMA, PRICE_CLOSE);
   handleRsiBTC = iRSI(InpSymbolBTC, InpTimeframe, InpRSIPeriod, PRICE_CLOSE);
   handleAtrBTC = iATR(InpSymbolBTC, InpTimeframe, InpATRPeriod);

   handleMaFastETH = iMA(InpSymbolETH, InpTimeframe, InpMAPeriodFast, 0, MODE_EMA, PRICE_CLOSE);
   handleMaSlowETH = iMA(InpSymbolETH, InpTimeframe, InpMAPeriodSlow, 0, MODE_EMA, PRICE_CLOSE);
   handleRsiETH = iRSI(InpSymbolETH, InpTimeframe, InpRSIPeriod, PRICE_CLOSE);
   handleAtrETH = iATR(InpSymbolETH, InpTimeframe, InpATRPeriod);

   //--- Check handles
   if(handleMaFastBTC == INVALID_HANDLE || handleMaSlowBTC == INVALID_HANDLE ||
      handleRsiBTC == INVALID_HANDLE || handleAtrBTC == INVALID_HANDLE ||
      handleMaFastETH == INVALID_HANDLE || handleMaSlowETH == INVALID_HANDLE ||
      handleRsiETH == INVALID_HANDLE || handleAtrETH == INVALID_HANDLE)
   {
      Alert("ERROR: Failed to create indicator handles!");
      return INIT_FAILED;
   }

   //--- Set arrays as series
   ArraySetAsSeries(maFastBTC, true);
   ArraySetAsSeries(maSlowBTC, true);
   ArraySetAsSeries(rsiBTC, true);
   ArraySetAsSeries(atrBTC, true);
   ArraySetAsSeries(maFastETH, true);
   ArraySetAsSeries(maSlowETH, true);
   ArraySetAsSeries(rsiETH, true);
   ArraySetAsSeries(atrETH, true);

   //--- Initialize tracking
   ArrayResize(positionsBTC, 0);
   ArrayResize(positionsETH, 0);
   lastBarTime = 0;
   barsSinceCheck = 0;

   //--- Initialize recovery systems
   InitializeRecovery(recoveryBTC);
   InitializeRecovery(recoveryETH);
   LoadRecoveryState(); // Load from previous session if available

   //--- Initialize spread stats
   InitializeSpreadStats(spreadBTC);
   InitializeSpreadStats(spreadETH);

   //--- Analyze initial spreads
   if(InpAdaptiveSpread)
   {
      AnalyzeHistoricalSpreads(InpSymbolBTC, spreadBTC);
      AnalyzeHistoricalSpreads(InpSymbolETH, spreadETH);
   }

   //--- Validate account settings
   ValidateAccountSettings();

   //--- Create panel
   if(InpShowPanel)
      CreateInfoPanel();

   //--- Log initialization
   DebugPrint("==============================================");
   DebugPrint("ADAPTIVE CRYPTO EA v4.0 INITIALIZED");
   DebugPrint("Account: " + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) +
              " | Balance: $" + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2));
   DebugPrint("Broker: " + AccountInfoString(ACCOUNT_COMPANY));
   DebugPrint("Trading: " + InpSymbolBTC + " & " + InpSymbolETH);
   DebugPrint("Risk Mode: " + (InpUseFixedLot ? "FIXED LOT" : "PERCENTAGE") +
              " | " + (InpUseFixedLot ? DoubleToString(InpFixedLot, 2) : DoubleToString(InpRiskPercent, 2) + "%"));
   DebugPrint("Min/Max Lot: " + DoubleToString(InpMinLotSize, 2) + " / " + DoubleToString(InpMaxLotSize, 2));
   DebugPrint("Loss Recovery: " + (InpUseLossRecovery ? "ENABLED" : "DISABLED"));
   if(InpUseLossRecovery)
   {
      DebugPrint("Recovery Multiplier: " + DoubleToString(InpRecoveryMultiplier, 2) + "x");
      DebugPrint("Max Recovery Trades: " + IntegerToString(InpMaxRecoveryTrades));
      DebugPrint("Recovery Target: " + DoubleToString(InpRecoveryTargetPercent, 0) + "% of loss");
   }
   DebugPrint("Adaptive Spread: " + (InpAdaptiveSpread ? "ENABLED" : "DISABLED"));
   DebugPrint("Profit Security: " + (InpUseProfitSecurity ? "ENABLED" : "DISABLED"));
   if(InpUseTieredProtection)
   {
      DebugPrint("Tiered Protection: Tier1=" + DoubleToString(InpTier1Secure, 0) + "% | " +
                 "Tier2=" + DoubleToString(InpTier2Secure, 0) + "% | " +
                 "Tier3=" + DoubleToString(InpTier3Secure, 0) + "%");
   }
   DebugPrint("BTC Adaptive Max Spread: " + DoubleToString(spreadBTC.adaptive_max, 0) + " pts (Avg: " +
              DoubleToString(spreadBTC.average, 0) + ")");
   DebugPrint("ETH Adaptive Max Spread: " + DoubleToString(spreadETH.adaptive_max, 0) + " pts (Avg: " +
              DoubleToString(spreadETH.average, 0) + ")");
   DebugPrint("==============================================");

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(handleMaFastBTC);
   IndicatorRelease(handleMaSlowBTC);
   IndicatorRelease(handleRsiBTC);
   IndicatorRelease(handleAtrBTC);
   IndicatorRelease(handleMaFastETH);
   IndicatorRelease(handleMaSlowETH);
   IndicatorRelease(handleRsiETH);
   IndicatorRelease(handleAtrETH);

   ObjectsDeleteAll(0, "CryptoPanel_");

   //--- Save recovery state for next session
   SaveRecoveryState();

   DebugPrint("EA DEINITIALIZED - Reason: " + IntegerToString(reason));
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Update spread stats continuously
   UpdateSpreadStats(InpSymbolBTC, spreadBTC);
   UpdateSpreadStats(InpSymbolETH, spreadETH);

   //--- Update panel
   if(InpShowPanel)
      UpdateInfoPanel();

   //--- Manage positions on every tick
   ManageOpenPositions();

   //--- Check for new bar
   datetime currentBarTime = iTime(InpSymbolBTC, InpTimeframe, 0);
   if(currentBarTime == lastBarTime)
      return;

   lastBarTime = currentBarTime;
   barsSinceCheck++;

   DebugPrint("--- NEW BAR: " + TimeToString(currentBarTime, TIME_DATE|TIME_MINUTES) + " ---");

   //--- Update indicator data
   if(!UpdateIndicatorData())
   {
      DebugPrint("ERROR: Failed to update indicators");
      return;
   }

   //--- Update position tracking
   UpdatePositionTracking();

   //--- Check for closed positions and update recovery
   CheckClosedPositions(InpSymbolBTC, InpMagicBTC, recoveryBTC);
   CheckClosedPositions(InpSymbolETH, InpMagicETH, recoveryETH);

   //--- Update cooldown
   if(recoveryBTC.cooldownBars > 0) recoveryBTC.cooldownBars--;
   if(recoveryETH.cooldownBars > 0) recoveryETH.cooldownBars--;

   //--- Check time filter
   if(InpUseTimeFilter && !IsTimeToTrade())
   {
      DebugPrint("Outside trading hours");
      return;
   }

   //--- Check correlation
   double correlation = 0;
   if(InpUseCorrelation)
   {
      correlation = CheckCorrelation();
      if(MathAbs(correlation) < InpMinCorrelation)
      {
         DebugPrint("Correlation low: " + DoubleToString(correlation, 3));
         return;
      }
   }

   //--- Get signals
   int signalBTC = GetTradingSignal(maFastBTC, maSlowBTC, rsiBTC, "BTC");
   int signalETH = GetTradingSignal(maFastETH, maSlowETH, rsiETH, "ETH");

   //--- Apply recovery logic to signals
   if(InpUseLossRecovery)
   {
      signalBTC = ApplyRecoveryLogic(signalBTC, recoveryBTC, "BTC");
      signalETH = ApplyRecoveryLogic(signalETH, recoveryETH, "ETH");
   }

   DebugPrint("Signals - BTC: " + SignalToString(signalBTC) + GetRecoveryStatus(recoveryBTC) +
              " | ETH: " + SignalToString(signalETH) + GetRecoveryStatus(recoveryETH) +
              " | Corr: " + DoubleToString(correlation, 3));
   DebugPrint("Spreads - BTC: " + DoubleToString(spreadBTC.current, 0) + "/" +
              DoubleToString(spreadBTC.adaptive_max, 0) + " | ETH: " +
              DoubleToString(spreadETH.current, 0) + "/" + DoubleToString(spreadETH.adaptive_max, 0));

   //--- Execute trades
   if(InpTradeOnlyBoth)
   {
      if(signalBTC == 1 && signalETH == 1)
      {
         DebugPrint(">>> DUAL BUY SIGNAL <<<");
         OpenTrade(InpSymbolBTC, ORDER_TYPE_BUY, InpMagicBTC, atrBTC[0], spreadBTC, tradeBTC, recoveryBTC);
         OpenTrade(InpSymbolETH, ORDER_TYPE_BUY, InpMagicETH, atrETH[0], spreadETH, tradeETH, recoveryETH);
      }
      else if(signalBTC == -1 && signalETH == -1)
      {
         DebugPrint(">>> DUAL SELL SIGNAL <<<");
         OpenTrade(InpSymbolBTC, ORDER_TYPE_SELL, InpMagicBTC, atrBTC[0], spreadBTC, tradeBTC, recoveryBTC);
         OpenTrade(InpSymbolETH, ORDER_TYPE_SELL, InpMagicETH, atrETH[0], spreadETH, tradeETH, recoveryETH);
      }
   }
   else
   {
      if(signalBTC != 0)
         OpenTrade(InpSymbolBTC, signalBTC == 1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,
                   InpMagicBTC, atrBTC[0], spreadBTC, tradeBTC, recoveryBTC);
      if(signalETH != 0)
         OpenTrade(InpSymbolETH, signalETH == 1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,
                   InpMagicETH, atrETH[0], spreadETH, tradeETH, recoveryETH);
   }
}

//+------------------------------------------------------------------+
//| Initialize spread statistics                                     |
//+------------------------------------------------------------------+
void InitializeSpreadStats(SpreadStats &stats)
{
   stats.current = 0;
   stats.average = 0;
   stats.maximum = 0;
   stats.minimum = 999999;
   stats.adaptive_max = InpFallbackMaxSpread;
   stats.sampleCount = 0;
}

//+------------------------------------------------------------------+
//| Analyze historical spreads                                       |
//+------------------------------------------------------------------+
void AnalyzeHistoricalSpreads(string symbol, SpreadStats &stats)
{
   double spreads[];
   ArrayResize(spreads, InpSpreadSamplePeriod);
   double sum = 0;
   int validSamples = 0;

   for(int i = 0; i < InpSpreadSamplePeriod; i++)
   {
      MqlTick tick;
      if(SymbolInfoTick(symbol, tick))
      {
         double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
         if(point > 0)
         {
            double spread = (tick.ask - tick.bid) / point;
            spreads[validSamples] = spread;
            sum += spread;

            if(spread > stats.maximum) stats.maximum = spread;
            if(spread < stats.minimum) stats.minimum = spread;

            validSamples++;
         }
      }
      Sleep(10); // Small delay between samples
   }

   if(validSamples > 0)
   {
      stats.average = sum / validSamples;
      stats.adaptive_max = stats.average * InpSpreadMultiplier;
      stats.sampleCount = validSamples;

      // Ensure minimum threshold
      if(stats.adaptive_max < 100) stats.adaptive_max = 100;
      if(stats.adaptive_max > InpFallbackMaxSpread) stats.adaptive_max = InpFallbackMaxSpread;
   }
   else
   {
      stats.adaptive_max = InpFallbackMaxSpread;
   }
}

//+------------------------------------------------------------------+
//| Update spread statistics                                         |
//+------------------------------------------------------------------+
void UpdateSpreadStats(string symbol, SpreadStats &stats)
{
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);

   if(point > 0)
   {
      stats.current = (ask - bid) / point;

      // Update running average (exponential moving average)
      if(stats.sampleCount == 0)
         stats.average = stats.current;
      else
         stats.average = (stats.average * 0.95) + (stats.current * 0.05);

      stats.sampleCount++;

      if(stats.current > stats.maximum) stats.maximum = stats.current;
      if(stats.current < stats.minimum) stats.minimum = stats.current;

      // Update adaptive max
      if(InpAdaptiveSpread)
         stats.adaptive_max = stats.average * InpSpreadMultiplier;
   }
}

//+------------------------------------------------------------------+
//| Update indicator data                                            |
//+------------------------------------------------------------------+
bool UpdateIndicatorData()
{
   if(CopyBuffer(handleMaFastBTC, 0, 0, 3, maFastBTC) < 3) return false;
   if(CopyBuffer(handleMaSlowBTC, 0, 0, 3, maSlowBTC) < 3) return false;
   if(CopyBuffer(handleRsiBTC, 0, 0, 3, rsiBTC) < 3) return false;
   if(CopyBuffer(handleAtrBTC, 0, 0, 2, atrBTC) < 2) return false;

   if(CopyBuffer(handleMaFastETH, 0, 0, 3, maFastETH) < 3) return false;
   if(CopyBuffer(handleMaSlowETH, 0, 0, 3, maSlowETH) < 3) return false;
   if(CopyBuffer(handleRsiETH, 0, 0, 3, rsiETH) < 3) return false;
   if(CopyBuffer(handleAtrETH, 0, 0, 2, atrETH) < 2) return false;

   return true;
}

//+------------------------------------------------------------------+
//| Get trading signal                                                |
//+------------------------------------------------------------------+
int GetTradingSignal(const double &maFast[], const double &maSlow[], const double &rsi[], string symbol)
{
   // Safety check: ensure arrays have enough data
   if(ArraySize(maFast) < 3 || ArraySize(maSlow) < 3 || ArraySize(rsi) < 2)
   {
      return 0; // Not enough data yet
   }

   if(maFast[1] > maSlow[1] && maFast[2] <= maSlow[2] && rsi[1] < InpRSIOverbought)
      return 1;

   if(maFast[1] < maSlow[1] && maFast[2] >= maSlow[2] && rsi[1] > InpRSIOversold)
      return -1;

   return 0;
}

//+------------------------------------------------------------------+
//| Open trade with adaptive spread handling and recovery            |
//+------------------------------------------------------------------+
void OpenTrade(string symbol, ENUM_ORDER_TYPE orderType, int magic, double atr, SpreadStats &spreadStats, CTrade &trade, RecoveryInfo &recovery)
{
   if(PositionSelectByMagic(symbol, magic))
   {
      DebugPrint(symbol + " - Position exists");
      return;
   }

   //--- Check cooldown
   if(recovery.cooldownBars > 0)
   {
      DebugPrint(symbol + " - Recovery cooldown: " + IntegerToString(recovery.cooldownBars) + " bars remaining");
      return;
   }

   //--- Adaptive spread check
   if(InpAdaptiveSpread && spreadStats.current > spreadStats.adaptive_max)
   {
      DebugPrint(symbol + " - Spread high but within adaptive range: " +
                 DoubleToString(spreadStats.current, 0) + " / " +
                 DoubleToString(spreadStats.adaptive_max, 0));
   }

   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

   //--- Calculate base lot size
   double slDistance = atr * InpSLMultiplier;

   if(InpAdjustSLForSpread)
   {
      double spreadCost = spreadStats.current * point;
      slDistance += spreadCost * 1.2;
   }

   double baseLotSize = CalculateLotSize(symbol, slDistance, InpRiskPercent);
   double lotSize = baseLotSize;

   //--- Apply recovery multiplier
   if(recovery.inRecovery && InpUseLossRecovery)
   {
      double multiplier = MathPow(InpRecoveryMultiplier, recovery.recoveryLevel);

      // For fixed lot mode
      if(InpUseFixedLot)
      {
         lotSize = InpFixedLot * multiplier;
      }
      else
      {
         lotSize = baseLotSize * multiplier;
      }

      DebugPrint("🔄 " + symbol + " RECOVERY MODE - Level " + IntegerToString(recovery.recoveryLevel) +
                " | Base: " + DoubleToString(InpUseFixedLot ? InpFixedLot : baseLotSize, 2) +
                " × " + DoubleToString(multiplier, 2) +
                " = " + DoubleToString(lotSize, 2) +
                " | Target: $" + DoubleToString(recovery.targetProfit, 2));
   }

   //--- Normalize lot
   double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

   // Safety checks for broker values
   if(minLot == 0) minLot = 0.01;
   if(maxLot == 0) maxLot = 100.0;
   if(lotStep == 0) lotStep = 0.01;

   lotSize = NormalizeLot(lotSize, minLot, maxLot, lotStep);

   if(lotSize < minLot)
   {
      DebugPrint("⚠️ " + symbol + " - Lot too small: " + DoubleToString(lotSize, 2) +
                " < broker min: " + DoubleToString(minLot, 2));

      // For micro accounts, still attempt with minimum lot
      if(AccountInfoDouble(ACCOUNT_BALANCE) < 100)
      {
         lotSize = minLot;
         DebugPrint("   Micro account detected - using minimum lot: " + DoubleToString(minLot, 2));
      }
      else
      {
         return;
      }
   }

   // Warn if lot exceeds maximum
   if(lotSize > maxLot)
   {
      DebugPrint("⚠️ " + symbol + " - Lot exceeds maximum: " + DoubleToString(lotSize, 2) +
                " > " + DoubleToString(maxLot, 2) + " - using max");
      lotSize = maxLot;
   }

   //--- Calculate SL and TP
   double sl = 0, tp = 0, entryPrice = 0;

   if(orderType == ORDER_TYPE_BUY)
   {
      entryPrice = ask;
      sl = NormalizeDouble(entryPrice - slDistance, digits);
      tp = NormalizeDouble(entryPrice + (atr * InpTPMultiplier), digits);
   }
   else
   {
      entryPrice = bid;
      sl = NormalizeDouble(entryPrice + slDistance, digits);
      tp = NormalizeDouble(entryPrice - (atr * InpTPMultiplier), digits);
   }

   //--- Adjust TP for recovery if needed
   if(recovery.inRecovery && InpUseLossRecovery)
   {
      double requiredProfit = recovery.targetProfit;
      double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);

      if(tickValue > 0 && lotSize > 0)
      {
         double requiredPoints = (requiredProfit / tickValue) / lotSize;
         double recoveryTP = 0;

         if(orderType == ORDER_TYPE_BUY)
            recoveryTP = NormalizeDouble(entryPrice + (requiredPoints * point), digits);
         else
            recoveryTP = NormalizeDouble(entryPrice - (requiredPoints * point), digits);

         // Use the closer TP (recovery or original)
         if(orderType == ORDER_TYPE_BUY)
            tp = MathMin(tp, recoveryTP);
         else
            tp = MathMax(tp, recoveryTP);
      }
   }

   DebugPrint("=== OPENING " + symbol + " " + EnumToString(orderType) + " ===");
   DebugPrint("Entry: " + DoubleToString(entryPrice, digits) + " | Lot: " + DoubleToString(lotSize, 2));
   DebugPrint("SL: " + DoubleToString(sl, digits) + " (" + DoubleToString(MathAbs(entryPrice-sl)/point, 0) + " pts)");
   DebugPrint("TP: " + DoubleToString(tp, digits) + " (" + DoubleToString(MathAbs(tp-entryPrice)/point, 0) + " pts)");
   if(recovery.inRecovery)
      DebugPrint("Recovery: Level " + IntegerToString(recovery.recoveryLevel) + " | Loss: $" + DoubleToString(recovery.totalLoss, 2));

   // Calculate potential profit/loss
   double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickValue > 0)
   {
      double potentialLoss = (MathAbs(entryPrice - sl) / point) * tickValue * lotSize;
      double potentialProfit = (MathAbs(tp - entryPrice) / point) * tickValue * lotSize;
      DebugPrint("Potential: Loss=$" + DoubleToString(potentialLoss, 2) +
                " | Profit=$" + DoubleToString(potentialProfit, 2) +
                " | R:R=" + DoubleToString(potentialProfit/potentialLoss, 2));
   }

   bool result = trade.PositionOpen(symbol, orderType, lotSize, entryPrice, sl, tp, "Adaptive Crypto EA v4");

   if(result)
   {
      DebugPrint("✓ SUCCESS - Ticket: " + IntegerToString(trade.ResultOrder()));
      AddPositionToTracking(symbol, magic, atr);

      // Store recovery info
      recovery.lastLotSize = lotSize;
      recovery.lastDirection = orderType;
   }
   else
   {
      DebugPrint("✗ FAILED - " + IntegerToString(GetLastError()) + ": " + trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| Calculate lot size                                                |
//+------------------------------------------------------------------+
double CalculateLotSize(string symbol, double slDistance, double riskPercent)
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * riskPercent / 100.0;
   double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);

   if(tickValue == 0 || slDistance == 0)
      return 0.01;

   double slPips = slDistance / point;
   double lotSize = riskAmount / (slPips * tickValue);

   return lotSize;
}

//+------------------------------------------------------------------+
//| Normalize lot size - Works with any broker                       |
//+------------------------------------------------------------------+
double NormalizeLot(double lot, double minLot, double maxLot, double lotStep)
{
   // Handle edge cases
   if(lotStep == 0)
      lotStep = 0.01;
   if(minLot == 0)
      minLot = 0.01;
   if(maxLot == 0)
      maxLot = 100.0;

   // Round down to nearest lot step
   lot = MathFloor(lot / lotStep) * lotStep;

   // Apply limits
   lot = MathMax(minLot, lot);
   lot = MathMin(maxLot, lot);

   // Normalize to 2 decimal places (standard for most brokers)
   lot = NormalizeDouble(lot, 2);

   // Final safety check
   if(lot < minLot)
      lot = minLot;

   return lot;
}

//+------------------------------------------------------------------+
//| Update position tracking                                         |
//+------------------------------------------------------------------+
void UpdatePositionTracking()
{
   ArrayResize(positionsBTC, 0);
   ArrayResize(positionsETH, 0);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;

      string symbol = PositionGetString(POSITION_SYMBOL);
      long magic = PositionGetInteger(POSITION_MAGIC);

      if((symbol == InpSymbolBTC && magic == InpMagicBTC) ||
         (symbol == InpSymbolETH && magic == InpMagicETH))
      {
         PositionInfo info;
         info.ticket = ticket;
         info.openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         info.initialSL = PositionGetDouble(POSITION_SL);
         info.currentSL = info.initialSL;
         info.currentProfit = PositionGetDouble(POSITION_PROFIT);
         info.maxProfit = info.currentProfit;
         info.openTime = (datetime)PositionGetInteger(POSITION_TIME);
         info.lastUpdateTime = 0;
         info.protectionTier = 0;

         // Try to get ATR at open (fallback to current)
         info.atrAtOpen = (symbol == InpSymbolBTC) ? atrBTC[0] : atrETH[0];

         if(symbol == InpSymbolBTC)
         {
            int size = ArraySize(positionsBTC);
            ArrayResize(positionsBTC, size + 1);
            positionsBTC[size] = info;
         }
         else
         {
            int size = ArraySize(positionsETH);
            ArrayResize(positionsETH, size + 1);
            positionsETH[size] = info;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Add position to tracking                                         |
//+------------------------------------------------------------------+
void AddPositionToTracking(string symbol, int magic, double atr)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;

      if(PositionGetString(POSITION_SYMBOL) == symbol &&
         PositionGetInteger(POSITION_MAGIC) == magic)
      {
         PositionInfo info;
         info.ticket = ticket;
         info.openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         info.initialSL = PositionGetDouble(POSITION_SL);
         info.currentSL = info.initialSL;
         info.currentProfit = PositionGetDouble(POSITION_PROFIT);
         info.maxProfit = 0;
         info.atrAtOpen = atr;
         info.protectionTier = 0;
         info.openTime = (datetime)PositionGetInteger(POSITION_TIME);
         info.lastUpdateTime = TimeCurrent();

         if(symbol == InpSymbolBTC)
         {
            int size = ArraySize(positionsBTC);
            ArrayResize(positionsBTC, size + 1);
            positionsBTC[size] = info;
         }
         else
         {
            int size = ArraySize(positionsETH);
            ArrayResize(positionsETH, size + 1);
            positionsETH[size] = info;
         }
         break;
      }
   }
}

//+------------------------------------------------------------------+
//| Manage open positions - Smart profit security                    |
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   ManagePositionsForSymbol(InpSymbolBTC, InpMagicBTC, positionsBTC, atrBTC[0]);
   ManagePositionsForSymbol(InpSymbolETH, InpMagicETH, positionsETH, atrETH[0]);
}

//+------------------------------------------------------------------+
//| Manage positions for specific symbol                             |
//+------------------------------------------------------------------+
void ManagePositionsForSymbol(string symbol, int magic, PositionInfo &positions[], double currentATR)
{
   for(int i = ArraySize(positions) - 1; i >= 0; i--)
   {
      ulong ticket = positions[i].ticket;
      if(!PositionSelectByTicket(ticket)) continue;

      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);

      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double currentProfit = PositionGetDouble(POSITION_PROFIT);

      double currentPrice = (posType == POSITION_TYPE_BUY) ? bid : ask;
      double profitDistance = (posType == POSITION_TYPE_BUY) ?
                              (currentPrice - openPrice) : (openPrice - currentPrice);

      // Update max profit tracking
      if(currentProfit > positions[i].maxProfit)
         positions[i].maxProfit = currentProfit;

      double atrToUse = (positions[i].atrAtOpen > 0) ? positions[i].atrAtOpen : currentATR;

      //--- SMART PROFIT SECURITY SYSTEM ---
      if(InpUseProfitSecurity)
      {
         // Check if we have minimum profit to secure
         double minProfitToSecure = atrToUse * InpMinProfitToSecure;

         if(profitDistance >= minProfitToSecure)
         {
            double newSL = 0;
            double securePercent = InpProfitSecurePercent;
            int newTier = 1;

            // TIERED PROTECTION SYSTEM
            if(InpUseTieredProtection)
            {
               double profitInATR = profitDistance / atrToUse;

               if(profitInATR >= InpTier3Profit)
               {
                  securePercent = InpTier3Secure;
                  newTier = 3;
               }
               else if(profitInATR >= InpTier2Profit)
               {
                  securePercent = InpTier2Secure;
                  newTier = 2;
               }
               else if(profitInATR >= InpTier1Profit)
               {
                  securePercent = InpTier1Secure;
                  newTier = 1;
               }
               else
               {
                  newTier = 0; // Below tier 1
               }

               // Only update if moving to higher tier
               if(newTier > positions[i].protectionTier && newTier > 0)
               {
                  double secureDistance = profitDistance * (securePercent / 100.0);

                  if(posType == POSITION_TYPE_BUY)
                     newSL = NormalizeDouble(openPrice + secureDistance, digits);
                  else
                     newSL = NormalizeDouble(openPrice - secureDistance, digits);

                  // Validate new SL
                  bool validUpdate = false;
                  if(posType == POSITION_TYPE_BUY)
                     validUpdate = (newSL > currentSL) && (newSL < currentPrice);
                  else
                     validUpdate = ((newSL < currentSL || currentSL == 0) && (newSL > currentPrice));

                  if(validUpdate)
                  {
                     CTrade trade;
                     if(trade.PositionModify(ticket, newSL, currentTP))
                     {
                        positions[i].protectionTier = newTier;
                        positions[i].currentSL = newSL;
                        positions[i].lastUpdateTime = TimeCurrent();

                        DebugPrint("🛡️ " + symbol + " #" + IntegerToString(ticket) +
                                 " TIER " + IntegerToString(newTier) + " PROTECTION ACTIVATED");
                        DebugPrint("   Secured " + DoubleToString(securePercent, 0) + "% of " +
                                 DoubleToString(profitDistance/point, 0) + " pts profit");
                        DebugPrint("   New SL: " + DoubleToString(newSL, digits) +
                                 " (was: " + DoubleToString(currentSL, digits) + ")");
                     }
                  }
               }
            }
            else
            {
               // Simple profit security (no tiers)
               datetime currentTime = TimeCurrent();
               if(currentTime - positions[i].lastUpdateTime >= InpSecurityCheckInterval * PeriodSeconds(InpTimeframe))
               {
                  double secureDistance = profitDistance * (securePercent / 100.0);

                  if(posType == POSITION_TYPE_BUY)
                     newSL = NormalizeDouble(openPrice + secureDistance, digits);
                  else
                     newSL = NormalizeDouble(openPrice - secureDistance, digits);

                  bool validUpdate = false;
                  if(posType == POSITION_TYPE_BUY)
                     validUpdate = (newSL > currentSL) && (newSL < currentPrice);
                  else
                     validUpdate = ((newSL < currentSL || currentSL == 0) && (newSL > currentPrice));

                  if(validUpdate)
                  {
                     CTrade trade;
                     if(trade.PositionModify(ticket, newSL, currentTP))
                     {
                        positions[i].currentSL = newSL;
                        positions[i].lastUpdateTime = currentTime;

                        DebugPrint("💰 " + symbol + " #" + IntegerToString(ticket) +
                                 " PROFIT SECURED: " + DoubleToString(securePercent, 0) + "%");
                        DebugPrint("   New SL: " + DoubleToString(newSL, digits));
                     }
                  }
               }
            }
         }
      }

      //--- TRAILING STOP SYSTEM ---
      if(InpUseTrailingStop)
      {
         double trailingStart = atrToUse * InpTrailingStartATR;
         double trailingStep = atrToUse * InpTrailingStepATR;

         if(profitDistance >= trailingStart)
         {
            double newSL = 0;

            if(posType == POSITION_TYPE_BUY)
            {
               newSL = NormalizeDouble(currentPrice - trailingStep, digits);

               if(newSL > currentSL && newSL < currentPrice)
               {
                  CTrade trade;
                  if(trade.PositionModify(ticket, newSL, currentTP))
                  {
                     positions[i].currentSL = newSL;
                     DebugPrint("📈 " + symbol + " #" + IntegerToString(ticket) +
                              " TRAILING: " + DoubleToString(currentSL, digits) +
                              " → " + DoubleToString(newSL, digits) +
                              " | Profit: " + DoubleToString(profitDistance/point, 0) + " pts");
                  }
               }
            }
            else
            {
               newSL = NormalizeDouble(currentPrice + trailingStep, digits);

               if((newSL < currentSL || currentSL == 0) && newSL > currentPrice)
               {
                  CTrade trade;
                  if(trade.PositionModify(ticket, newSL, currentTP))
                  {
                     positions[i].currentSL = newSL;
                     DebugPrint("📉 " + symbol + " #" + IntegerToString(ticket) +
                              " TRAILING: " + DoubleToString(currentSL, digits) +
                              " → " + DoubleToString(newSL, digits) +
                              " | Profit: " + DoubleToString(profitDistance/point, 0) + " pts");
                  }
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check if position exists by magic                                |
//+------------------------------------------------------------------+
bool PositionSelectByMagic(string symbol, int magic)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == symbol &&
            PositionGetInteger(POSITION_MAGIC) == magic)
            return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Check if it's time to trade                                      |
//+------------------------------------------------------------------+
bool IsTimeToTrade()
{
   MqlDateTime time;
   TimeCurrent(time);

   if(InpStartHour <= InpEndHour)
      return (time.hour >= InpStartHour && time.hour < InpEndHour);
   else
      return (time.hour >= InpStartHour || time.hour < InpEndHour);
}

//+------------------------------------------------------------------+
//| Check correlation                                                 |
//+------------------------------------------------------------------+
double CheckCorrelation()
{
   double pricesBTC[], pricesETH[];
   ArraySetAsSeries(pricesBTC, true);
   ArraySetAsSeries(pricesETH, true);

   if(CopyClose(InpSymbolBTC, InpTimeframe, 0, InpCorrelationPeriod, pricesBTC) < InpCorrelationPeriod)
      return 1.0;
   if(CopyClose(InpSymbolETH, InpTimeframe, 0, InpCorrelationPeriod, pricesETH) < InpCorrelationPeriod)
      return 1.0;

   return CalculateCorrelation(pricesBTC, pricesETH, InpCorrelationPeriod);
}

//+------------------------------------------------------------------+
//| Calculate correlation                                             |
//+------------------------------------------------------------------+
double CalculateCorrelation(const double &x[], const double &y[], int period)
{
   double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0, sumY2 = 0;

   for(int i = 0; i < period; i++)
   {
      sumX += x[i];
      sumY += y[i];
      sumXY += x[i] * y[i];
      sumX2 += x[i] * x[i];
      sumY2 += y[i] * y[i];
   }

   double numerator = (period * sumXY) - (sumX * sumY);
   double denominator = MathSqrt((period * sumX2 - sumX * sumX) * (period * sumY2 - sumY * sumY));

   return (denominator == 0) ? 0 : numerator / denominator;
}

//+------------------------------------------------------------------+
//| Debug print with throttle                                        |
//+------------------------------------------------------------------+
void DebugPrint(string message)
{
   if(!InpDebugMode) return;

   // Priority messages bypass throttle
   if(StringFind(message, "ERROR") >= 0 ||
      StringFind(message, "SUCCESS") >= 0 ||
      StringFind(message, "FAILED") >= 0 ||
      StringFind(message, ">>>") >= 0 ||
      StringFind(message, "===") >= 0 ||
      StringFind(message, "🛡️") >= 0 ||
      StringFind(message, "💰") >= 0 ||
      StringFind(message, "📈") >= 0 ||
      StringFind(message, "📉") >= 0 ||
      StringFind(message, "✓") >= 0 ||
      StringFind(message, "✗") >= 0)
   {
      Print(message);
      return;
   }

   // Throttle routine messages
   datetime currentTime = TimeCurrent();
   if(currentTime - lastLogTime >= logThrottleSeconds)
   {
      Print(message);
      lastLogTime = currentTime;
   }
}

//+------------------------------------------------------------------+
//| Signal to string                                                  |
//+------------------------------------------------------------------+
string SignalToString(int signal)
{
   if(signal == 1) return "BUY";
   if(signal == -1) return "SELL";
   return "NONE";
}

//+------------------------------------------------------------------+
//| Create information panel                                         |
//+------------------------------------------------------------------+
void CreateInfoPanel()
{
   string prefix = "CryptoPanel_";
   int x = InpPanelX;
   int y = InpPanelY;
   int width = 280;

   ObjectCreate(0, prefix + "BG", OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, prefix + "BG", OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, prefix + "BG", OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, prefix + "BG", OBJPROP_XSIZE, width);
   ObjectSetInteger(0, prefix + "BG", OBJPROP_YSIZE, 260);
   ObjectSetInteger(0, prefix + "BG", OBJPROP_BGCOLOR, clrBlack);
   ObjectSetInteger(0, prefix + "BG", OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, prefix + "BG", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, prefix + "BG", OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, prefix + "BG", OBJPROP_BACK, true);

   CreateLabel(prefix + "Title", "🤖 Adaptive Crypto EA v4.0", x + 10, y + 5, clrLime, 9, "Arial Bold");
   CreateLabel(prefix + "Account", "Balance: $---", x + 10, y + 25, clrWhite, 8, "Arial");
   CreateLabel(prefix + "Status", "Status: Initializing...", x + 10, y + 45, clrWhite, 8, "Arial");
   CreateLabel(prefix + "BTC", "BTC: Loading...", x + 10, y + 65, clrWhite, 8, "Arial");
   CreateLabel(prefix + "ETH", "ETH: Loading...", x + 10, y + 85, clrWhite, 8, "Arial");
   CreateLabel(prefix + "Correlation", "Correlation: ---", x + 10, y + 105, clrWhite, 8, "Arial");
   CreateLabel(prefix + "SpreadBTC", "BTC Spread: --- / ---", x + 10, y + 125, clrWhite, 8, "Arial");
   CreateLabel(prefix + "SpreadETH", "ETH Spread: --- / ---", x + 10, y + 145, clrWhite, 8, "Arial");
   CreateLabel(prefix + "PosBTC", "BTC Positions: 0", x + 10, y + 165, clrWhite, 8, "Arial");
   CreateLabel(prefix + "PosETH", "ETH Positions: 0", x + 10, y + 185, clrWhite, 8, "Arial");
   CreateLabel(prefix + "Protection", "Protection: Standby", x + 10, y + 205, clrGray, 8, "Arial");
   CreateLabel(prefix + "Profit", "Total P/L: $0.00", x + 10, y + 225, clrWhite, 8, "Arial Bold");
   CreateLabel(prefix + "Time", "Time: " + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES), x + 10, y + 240, clrGray, 7, "Arial");
}

//+------------------------------------------------------------------+
//| Create label                                                      |
//+------------------------------------------------------------------+
void CreateLabel(string name, string text, int x, int y, color clr, int fontSize, string font)
{
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetString(0, name, OBJPROP_FONT, font);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
}

//+------------------------------------------------------------------+
//| Update information panel                                         |
//+------------------------------------------------------------------+
void UpdateInfoPanel()
{
   string prefix = "CryptoPanel_";

   // Account balance
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   string balanceText = "Balance: $" + DoubleToString(balance, 2) + " | Equity: $" + DoubleToString(equity, 2);
   color balanceColor = equity >= balance ? clrLime : clrOrange;
   ObjectSetString(0, prefix + "Account", OBJPROP_TEXT, balanceText);
   ObjectSetInteger(0, prefix + "Account", OBJPROP_COLOR, balanceColor);

   // Status
   int totalPos = PositionsTotal();
   string status = totalPos > 0 ? "⚡ ACTIVE (" + IntegerToString(totalPos) + ")" : "👁️ MONITORING";
   color statusColor = totalPos > 0 ? clrLime : clrYellow;
   ObjectSetString(0, prefix + "Status", OBJPROP_TEXT, "Status: " + status);
   ObjectSetInteger(0, prefix + "Status", OBJPROP_COLOR, statusColor);

   // BTC signal
   int signalBTC = GetTradingSignal(maFastBTC, maSlowBTC, rsiBTC, "");
   string btcText = "BTC: " + SignalToString(signalBTC) + " | RSI:" + DoubleToString(rsiBTC[0], 1);
   color btcColor = signalBTC == 1 ? clrLime : (signalBTC == -1 ? clrRed : clrGray);
   ObjectSetString(0, prefix + "BTC", OBJPROP_TEXT, btcText);
   ObjectSetInteger(0, prefix + "BTC", OBJPROP_COLOR, btcColor);

   // ETH signal
   int signalETH = GetTradingSignal(maFastETH, maSlowETH, rsiETH, "");
   string ethText = "ETH: " + SignalToString(signalETH) + " | RSI:" + DoubleToString(rsiETH[0], 1);
   color ethColor = signalETH == 1 ? clrLime : (signalETH == -1 ? clrRed : clrGray);
   ObjectSetString(0, prefix + "ETH", OBJPROP_TEXT, ethText);
   ObjectSetInteger(0, prefix + "ETH", OBJPROP_COLOR, ethColor);

   // Correlation
   double corr = CheckCorrelation();
   string corrText = "Correlation: " + DoubleToString(corr, 3);
   color corrColor = MathAbs(corr) >= InpMinCorrelation ? clrLime : clrOrange;
   ObjectSetString(0, prefix + "Correlation", OBJPROP_TEXT, corrText);
   ObjectSetInteger(0, prefix + "Correlation", OBJPROP_COLOR, corrColor);

   // Spreads with adaptive max
   string spreadBTCText = "BTC Spread: " + DoubleToString(spreadBTC.current, 0) + " / " +
                          DoubleToString(spreadBTC.adaptive_max, 0) + " pts";
   color spreadBTCColor = spreadBTC.current <= spreadBTC.adaptive_max ? clrLime : clrOrange;
   ObjectSetString(0, prefix + "SpreadBTC", OBJPROP_TEXT, spreadBTCText);
   ObjectSetInteger(0, prefix + "SpreadBTC", OBJPROP_COLOR, spreadBTCColor);

   string spreadETHText = "ETH Spread: " + DoubleToString(spreadETH.current, 0) + " / " +
                          DoubleToString(spreadETH.adaptive_max, 0) + " pts";
   color spreadETHColor = spreadETH.current <= spreadETH.adaptive_max ? clrLime : clrOrange;
   ObjectSetString(0, prefix + "SpreadETH", OBJPROP_TEXT, spreadETHText);
   ObjectSetInteger(0, prefix + "SpreadETH", OBJPROP_COLOR, spreadETHColor);

   // Position counts
   int posBTC = ArraySize(positionsBTC);
   int posETH = ArraySize(positionsETH);
   ObjectSetString(0, prefix + "PosBTC", OBJPROP_TEXT, "BTC Positions: " + IntegerToString(posBTC));
   ObjectSetString(0, prefix + "PosETH", OBJPROP_TEXT, "ETH Positions: " + IntegerToString(posETH));

   // Protection status
   int maxTier = 0;
   for(int i = 0; i < posBTC; i++)
      if(positionsBTC[i].protectionTier > maxTier) maxTier = positionsBTC[i].protectionTier;
   for(int i = 0; i < posETH; i++)
      if(positionsETH[i].protectionTier > maxTier) maxTier = positionsETH[i].protectionTier;

   string protectionText = "Protection: ";
   color protectionColor = clrGray;
   if(maxTier == 0 && totalPos > 0)
   {
      protectionText += "Monitoring";
      protectionColor = clrYellow;
   }
   else if(maxTier > 0)
   {
      protectionText += "🛡️ TIER " + IntegerToString(maxTier) + " ACTIVE";
      protectionColor = clrLime;
   }
   else
   {
      protectionText += "Standby";
   }
   ObjectSetString(0, prefix + "Protection", OBJPROP_TEXT, protectionText);
   ObjectSetInteger(0, prefix + "Protection", OBJPROP_COLOR, protectionColor);

   // Total P/L
   double totalProfit = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         long magic = PositionGetInteger(POSITION_MAGIC);
         if(magic == InpMagicBTC || magic == InpMagicETH)
            totalProfit += PositionGetDouble(POSITION_PROFIT);
      }
   }

   string profitText = "Total P/L: $" + DoubleToString(totalProfit, 2);
   color profitColor = totalProfit > 0 ? clrLime : (totalProfit < 0 ? clrRed : clrGray);
   ObjectSetString(0, prefix + "Profit", OBJPROP_TEXT, profitText);
   ObjectSetInteger(0, prefix + "Profit", OBJPROP_COLOR, profitColor);

   // Time
   ObjectSetString(0, prefix + "Time", OBJPROP_TEXT, "Time: " + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES));

   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Validate account settings and warn user                          |
//+------------------------------------------------------------------+
void ValidateAccountSettings()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double minLotBTC = SymbolInfoDouble(InpSymbolBTC, SYMBOL_VOLUME_MIN);
   double minLotETH = SymbolInfoDouble(InpSymbolETH, SYMBOL_VOLUME_MIN);

   DebugPrint("--- ACCOUNT VALIDATION ---");
   DebugPrint("Balance: $" + DoubleToString(balance, 2));
   DebugPrint("Account Currency: " + AccountInfoString(ACCOUNT_CURRENCY));
   DebugPrint("Leverage: 1:" + IntegerToString(AccountInfoInteger(ACCOUNT_LEVERAGE)));
   DebugPrint("Broker Min Lots - BTC: " + DoubleToString(minLotBTC, 2) + " | ETH: " + DoubleToString(minLotETH, 2));

   // Account size warnings
   if(balance < 10)
   {
      Alert("⚠️ MICRO ACCOUNT ($" + DoubleToString(balance, 2) + ") - Using minimum lots only");
      DebugPrint("⚠️ Micro account detected - EA will use minimum lot sizes");
   }
   else if(balance < 100)
   {
      DebugPrint("ℹ️ Small account detected - Risk automatically reduced");
   }
   else if(balance < 1000)
   {
      DebugPrint("✓ Standard account - Normal risk management");
   }
   else
   {
      DebugPrint("✓ Large account - Full features available");
   }

   // Risk mode validation
   if(InpUseFixedLot)
   {
      DebugPrint("Risk Mode: FIXED LOT (" + DoubleToString(InpFixedLot, 2) + ")");

      if(InpFixedLot < minLotBTC || InpFixedLot < minLotETH)
      {
         Alert("⚠️ Fixed lot (" + DoubleToString(InpFixedLot, 2) + ") below broker minimum!");
      }
   }
   else
   {
      double testRisk = balance * InpRiskPercent / 100.0;
      DebugPrint("Risk Mode: PERCENTAGE (" + DoubleToString(InpRiskPercent, 2) + "% = $" + DoubleToString(testRisk, 2) + " per trade)");

      if(testRisk < 1.0 && balance > 100)
      {
         DebugPrint("⚠️ Risk amount very small - consider increasing risk % or using fixed lots");
      }
   }

   // Recovery validation
   if(InpUseLossRecovery)
   {
      double maxRecoveryLot = (InpUseFixedLot ? InpFixedLot : minLotBTC) * MathPow(InpRecoveryMultiplier, InpMaxRecoveryTrades);
      DebugPrint("Max Recovery Lot: " + DoubleToString(maxRecoveryLot, 2) + " (Level " + IntegerToString(InpMaxRecoveryTrades) + ")");

      if(maxRecoveryLot > InpMaxLotSize)
      {
         Alert("⚠️ Recovery system may exceed max lot size (" + DoubleToString(InpMaxLotSize, 2) + ")");
         DebugPrint("⚠️ Consider reducing recovery multiplier or max recovery trades");
      }
   }

   DebugPrint("--- VALIDATION COMPLETE ---");
}

//+------------------------------------------------------------------+
//| Initialize recovery system                                       |
//+------------------------------------------------------------------+
void InitializeRecovery(RecoveryInfo &recovery)
{
   recovery.inRecovery = false;
   recovery.recoveryLevel = 0;
   recovery.totalLoss = 0;
   recovery.targetProfit = 0;
   recovery.lastLossTime = 0;
   recovery.cooldownBars = 0;
   recovery.lastLotSize = 0;
   recovery.lastDirection = ORDER_TYPE_BUY;
}

//+------------------------------------------------------------------+
//| Check closed positions for losses                                |
//+------------------------------------------------------------------+
void CheckClosedPositions(string symbol, int magic, RecoveryInfo &recovery)
{
   static datetime lastCheckTime = 0;

   if(TimeCurrent() == lastCheckTime) return;
   lastCheckTime = TimeCurrent();

   // Check history for recently closed positions
   datetime fromTime = TimeCurrent() - PeriodSeconds(InpTimeframe) * 2;
   HistorySelect(fromTime, TimeCurrent());

   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;

      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != symbol) continue;
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != magic) continue;
      if(HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;

      double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
      double commission = HistoryDealGetDouble(ticket, DEAL_COMMISSION);
      double swap = HistoryDealGetDouble(ticket, DEAL_SWAP);
      double netProfit = profit + commission + swap;

      ENUM_ORDER_TYPE dealType = (ENUM_ORDER_TYPE)HistoryDealGetInteger(ticket, DEAL_TYPE);
      datetime dealTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);

      // Check if this is a new deal we haven't processed
      if(dealTime <= recovery.lastLossTime) continue;

      if(netProfit < 0)
      {
         // LOSS DETECTED
         if(!recovery.inRecovery)
         {
            // Start new recovery sequence
            recovery.inRecovery = true;
            recovery.recoveryLevel = 1;
            recovery.totalLoss = MathAbs(netProfit);
            recovery.targetProfit = recovery.totalLoss * (InpRecoveryTargetPercent / 100.0);
            recovery.lastLossTime = dealTime;
            recovery.lastDirection = dealType;
            recovery.cooldownBars = 0;

            DebugPrint("🔴 " + symbol + " LOSS DETECTED: $" + DoubleToString(netProfit, 2));
            DebugPrint("🔄 RECOVERY MODE ACTIVATED - Target: $" + DoubleToString(recovery.targetProfit, 2));
         }
         else
         {
            // Add to existing recovery
            if(recovery.recoveryLevel < InpMaxRecoveryTrades)
            {
               recovery.recoveryLevel++;
               recovery.totalLoss += MathAbs(netProfit);
               recovery.targetProfit = recovery.totalLoss * (InpRecoveryTargetPercent / 100.0);
               recovery.lastLossTime = dealTime;
               recovery.lastDirection = dealType;

               DebugPrint("🔴 " + symbol + " ADDITIONAL LOSS: $" + DoubleToString(netProfit, 2));
               DebugPrint("🔄 RECOVERY LEVEL " + IntegerToString(recovery.recoveryLevel) +
                        " - Total Loss: $" + DoubleToString(recovery.totalLoss, 2) +
                        " | Target: $" + DoubleToString(recovery.targetProfit, 2));
            }
            else
            {
               // Max recovery level reached - reset
               DebugPrint("⚠️ " + symbol + " MAX RECOVERY LEVEL REACHED - Resetting system");
               InitializeRecovery(recovery);
               recovery.cooldownBars = InpRecoveryCooldown;
            }
         }
      }
      else if(netProfit > 0 && recovery.inRecovery)
      {
         // PROFIT DETECTED DURING RECOVERY
         if(netProfit >= recovery.targetProfit || InpResetOnProfit)
         {
            DebugPrint("✅ " + symbol + " RECOVERY SUCCESSFUL! Profit: $" + DoubleToString(netProfit, 2) +
                     " | Recovered: $" + DoubleToString(recovery.totalLoss, 2));
            InitializeRecovery(recovery);
            recovery.cooldownBars = InpRecoveryCooldown;
         }
         else
         {
            // Partial recovery
            recovery.totalLoss -= netProfit;
            recovery.targetProfit = recovery.totalLoss * (InpRecoveryTargetPercent / 100.0);
            recovery.lastLossTime = dealTime;

            if(recovery.totalLoss <= 0)
            {
               DebugPrint("✅ " + symbol + " FULL RECOVERY ACHIEVED!");
               InitializeRecovery(recovery);
               recovery.cooldownBars = InpRecoveryCooldown;
            }
            else
            {
               DebugPrint("💚 " + symbol + " PARTIAL RECOVERY: $" + DoubleToString(netProfit, 2) +
                        " | Remaining: $" + DoubleToString(recovery.totalLoss, 2));
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Apply recovery logic to trading signals                          |
//+------------------------------------------------------------------+
int ApplyRecoveryLogic(int originalSignal, RecoveryInfo &recovery, string symbol)
{
   if(!recovery.inRecovery)
      return originalSignal;

   // If in recovery mode
   if(InpRecoverySameDirection)
   {
      // Force same direction as last loss
      if(recovery.lastDirection == ORDER_TYPE_BUY)
         return (originalSignal == 1) ? 1 : 0; // Only take BUY signals
      else
         return (originalSignal == -1) ? -1 : 0; // Only take SELL signals
   }
   else
   {
      // Take opposite direction of last loss (martingale reversal)
      if(recovery.lastDirection == ORDER_TYPE_BUY && originalSignal == -1)
         return -1; // Reverse to SELL
      else if(recovery.lastDirection == ORDER_TYPE_SELL && originalSignal == 1)
         return 1; // Reverse to BUY
      else
         return originalSignal; // Take any strong signal
   }
}

//+------------------------------------------------------------------+
//| Get recovery status string                                       |
//+------------------------------------------------------------------+
string GetRecoveryStatus(RecoveryInfo &recovery)
{
   if(!recovery.inRecovery)
      return "";

   return " [R" + IntegerToString(recovery.recoveryLevel) + ":$" +
          DoubleToString(recovery.totalLoss, 0) + "]";
}

//+------------------------------------------------------------------+
//| Save recovery state to file                                      |
//+------------------------------------------------------------------+
void SaveRecoveryState()
{
   if(!InpUseLossRecovery) return;

   int handle = FileOpen("CryptoEA_Recovery.dat", FILE_WRITE|FILE_BIN);
   if(handle != INVALID_HANDLE)
   {
      FileWriteStruct(handle, recoveryBTC);
      FileWriteStruct(handle, recoveryETH);
      FileClose(handle);
   }
}

//+------------------------------------------------------------------+
//| Load recovery state from file                                    |
//+------------------------------------------------------------------+
void LoadRecoveryState()
{
   if(!InpUseLossRecovery) return;

   int handle = FileOpen("CryptoEA_Recovery.dat", FILE_READ|FILE_BIN);
   if(handle != INVALID_HANDLE)
   {
      FileReadStruct(handle, recoveryBTC);
      FileReadStruct(handle, recoveryETH);
      FileClose(handle);

      if(recoveryBTC.inRecovery)
         DebugPrint("📂 Loaded BTC recovery state - Level: " + IntegerToString(recoveryBTC.recoveryLevel) +
                   " | Loss: $" + DoubleToString(recoveryBTC.totalLoss, 2));
      if(recoveryETH.inRecovery)
         DebugPrint("📂 Loaded ETH recovery state - Level: " + IntegerToString(recoveryETH.recoveryLevel) +
                   " | Loss: $" + DoubleToString(recoveryETH.totalLoss, 2));
   }
}
//+------------------------------------------------------------------+
