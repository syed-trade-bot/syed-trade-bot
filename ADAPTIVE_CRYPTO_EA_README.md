# Adaptive Crypto Multi EA v4.0 - Documentation

## Overview

The Adaptive Crypto Multi EA is a sophisticated Expert Advisor designed for trading cryptocurrency pairs (BTC/ETH) on MetaTrader 5. It features intelligent spread analysis, loss recovery mechanisms, tiered profit protection, and adaptive risk management.

## Key Features

### 1. **Dual Symbol Trading**
- Trades both BTC and ETH simultaneously
- Option to trade only when both signals align (correlation-based)
- Separate magic numbers for position tracking
- Independent recovery systems per symbol

### 2. **Adaptive Spread System**
- Real-time spread analysis and monitoring
- Adaptive maximum spread threshold (avg × multiplier)
- Historical spread analysis on initialization
- Automatic SL adjustment to cover spread costs
- Works in all market conditions

### 3. **Loss Recovery System**
- Automated loss detection and recovery
- Configurable multiplier (default 1.5x per level)
- Maximum recovery trade limits
- Cooldown period after recovery completion
- Optional same-direction or reversal recovery
- Persistent state across EA restarts

### 4. **Tiered Profit Protection**
- **Tier 1**: 1× ATR profit → Secure 20%
- **Tier 2**: 2× ATR profit → Secure 40%
- **Tier 3**: 3× ATR profit → Secure 60%
- Progressive protection as profit grows
- Prevents profit drawdown

### 5. **Trailing Stop System**
- ATR-based dynamic trailing
- Configurable start and step distances
- Independent from tiered protection
- Works in conjunction with profit security

### 6. **Risk Management**
- Percentage-based or fixed lot sizing
- ATR-based stop loss and take profit
- Micro account detection and adaptation
- Maximum daily loss protection
- Position size validation

### 7. **Technical Analysis**
- Fast/Slow EMA crossover signals
- RSI overbought/oversold confirmation
- ATR-based volatility measurement
- BTC/ETH correlation filtering

### 8. **Visual Dashboard**
- Real-time account information
- Signal status for both symbols
- Spread monitoring
- Position tracking
- Profit/loss display
- Protection tier status

## Configuration Guide

### General Settings
```mql5
InpMagicBTC = 100001         // Unique ID for BTC trades
InpMagicETH = 100002         // Unique ID for ETH trades
InpRiskPercent = 1.0         // Risk per trade (%)
InpTradeOnlyBoth = true      // Trade only when both signals align
```

### Loss Recovery Configuration
```mql5
InpUseLossRecovery = true              // Enable recovery system
InpRecoveryMultiplier = 1.5            // Increase lot by 50% per level
InpMaxRecoveryTrades = 3               // Max 3 recovery attempts
InpRecoverySameDirection = false       // Reverse direction on recovery
InpRecoveryTargetPercent = 100.0       // Recover 100% of loss
InpRecoveryCooldown = 2                // Wait 2 bars after recovery
InpResetOnProfit = true                // Reset on any profit
```

### Symbol Settings
```mql5
InpSymbolBTC = "BTCUSD"     // Bitcoin symbol name
InpSymbolETH = "ETHUSD"     // Ethereum symbol name
```

### Strategy Parameters
```mql5
InpTimeframe = PERIOD_H1    // Trading timeframe
InpMAPeriodFast = 20        // Fast EMA period
InpMAPeriodSlow = 50        // Slow EMA period
InpRSIPeriod = 14           // RSI calculation period
InpRSIOversold = 30.0       // RSI oversold level
InpRSIOverbought = 70.0     // RSI overbought level
```

### Adaptive Spread System
```mql5
InpAdaptiveSpread = true            // Enable adaptive spread
InpSpreadSamplePeriod = 100         // Historical samples
InpSpreadMultiplier = 2.5           // Max = Average × 2.5
InpFallbackMaxSpread = 1000         // Fallback limit (points)
InpAdjustSLForSpread = true         // Include spread in SL
```

### Risk Management
```mql5
InpSLMultiplier = 2.5       // SL = 2.5 × ATR
InpTPMultiplier = 4.0       // TP = 4.0 × ATR
InpATRPeriod = 14           // ATR calculation period
InpSlippage = 100           // Max slippage in points
InpUseFixedLot = false      // Use percentage risk
InpFixedLot = 0.01          // Fixed lot if enabled
InpMinLotSize = 0.01        // Minimum lot override
InpMaxLotSize = 100.0       // Maximum lot limit
```

### Profit Security System
```mql5
InpUseProfitSecurity = true         // Enable profit protection
InpMinProfitToSecure = 0.5          // Min 0.5× ATR to activate
InpProfitSecurePercent = 30.0       // Secure 30% by default
InpSecurityCheckInterval = 5        // Check every 5 bars
InpUseTrailingStop = true           // Enable trailing
InpTrailingStartATR = 1.5           // Start at 1.5× ATR
InpTrailingStepATR = 0.5            // Trail by 0.5× ATR
```

### Tiered Protection
```mql5
InpUseTieredProtection = true       // Enable tiered system
InpTier1Profit = 1.0                // Tier 1 at 1× ATR
InpTier1Secure = 20.0               // Secure 20%
InpTier2Profit = 2.0                // Tier 2 at 2× ATR
InpTier2Secure = 40.0               // Secure 40%
InpTier3Profit = 3.0                // Tier 3 at 3× ATR
InpTier3Secure = 60.0               // Secure 60%
```

### Correlation Filter
```mql5
InpUseCorrelation = true            // Enable correlation check
InpCorrelationPeriod = 50           // Lookback period
InpMinCorrelation = 0.60            // Minimum correlation
```

## Trading Logic

### Signal Generation
1. **Buy Signal**: Fast EMA crosses above Slow EMA + RSI < 70
2. **Sell Signal**: Fast EMA crosses below Slow EMA + RSI > 30
3. **Correlation Check**: BTC/ETH correlation must be ≥ 0.60
4. **Spread Check**: Current spread ≤ Adaptive maximum

### Position Management Flow
```
1. New bar detected
2. Update indicators (MA, RSI, ATR)
3. Check for closed positions → Update recovery state
4. Evaluate trading conditions:
   - Time filter (if enabled)
   - Correlation threshold
   - Spread limits
5. Generate signals for BTC and ETH
6. Apply recovery logic to signals
7. Execute trades if conditions met
8. Manage open positions:
   - Update tiered protection
   - Adjust trailing stops
   - Monitor profit levels
```

### Recovery System Workflow
```
LOSS DETECTED → Activate Recovery Mode
  ↓
Recovery Level 1: Base Lot × 1.5
  ↓ (if loss again)
Recovery Level 2: Base Lot × 2.25
  ↓ (if loss again)
Recovery Level 3: Base Lot × 3.375
  ↓
Max Level Reached → Reset + Cooldown
  OR
PROFIT ACHIEVED → Reset System
```

### Tiered Protection Logic
```
Position Opens → Monitor Profit
  ↓
Profit ≥ 1× ATR → Tier 1: Move SL to breakeven + 20%
  ↓
Profit ≥ 2× ATR → Tier 2: Move SL to breakeven + 40%
  ↓
Profit ≥ 3× ATR → Tier 3: Move SL to breakeven + 60%
  ↓
Continue Trailing Until TP or SL Hit
```

## Account Size Recommendations

### Micro Accounts ($10-$100)
- Use fixed lot mode: `0.01`
- Disable recovery or set multiplier to `1.2`
- Increase minimum correlation to `0.70`
- Risk per trade: `0.5%`

### Small Accounts ($100-$1,000)
- Use percentage risk: `0.5-1.0%`
- Recovery multiplier: `1.3-1.5`
- Max recovery trades: `2`
- Standard settings work well

### Standard Accounts ($1,000-$10,000)
- Use percentage risk: `1.0-2.0%`
- Recovery multiplier: `1.5`
- Max recovery trades: `3`
- All features fully functional

### Large Accounts ($10,000+)
- Use percentage risk: `1.0-1.5%`
- Recovery multiplier: `1.3-1.5`
- Max recovery trades: `3-5`
- Consider reducing risk per trade

## Performance Optimization

### For Volatile Markets
- Increase `InpATRPeriod` to 21
- Increase `InpSLMultiplier` to 3.0
- Reduce `InpRecoveryMultiplier` to 1.3
- Enable time filters during news

### For Ranging Markets
- Decrease `InpSLMultiplier` to 2.0
- Increase `InpTPMultiplier` to 5.0
- Increase `InpMinCorrelation` to 0.70
- Enable correlation filter

### For Fast Execution
- Disable visual panel during live trading
- Reduce `InpSpreadSamplePeriod` to 50
- Use `InpDebugMode = false` in production

## Risk Warnings

⚠️ **Critical Warnings:**

1. **Recovery System Risk**: The loss recovery system uses position sizing multiplication. With `InpRecoveryMultiplier = 1.5` and `InpMaxRecoveryTrades = 3`, the final lot size could be 3.375× the base lot. Ensure sufficient account balance.

2. **Martingale Elements**: The recovery system has martingale-like characteristics. Set strict limits on `InpMaxRecoveryTrades` and always enable `InpRecoveryCooldown`.

3. **Correlation Dependency**: The EA relies on BTC/ETH correlation. During market decorrelation periods, signals may be suppressed.

4. **Spread Sensitivity**: Crypto spreads can widen dramatically during volatility. The adaptive spread system helps but may allow trades during suboptimal conditions.

5. **Broker Requirements**: Ensure your broker allows:
   - Cryptocurrency trading
   - Hedging (if using separate symbols)
   - Sufficient leverage
   - Minimum lot size compatible with account balance

## Troubleshooting

### Common Issues

**Issue**: "Symbol not found" error
- **Solution**: Verify symbol names match your broker's format (e.g., "BTCUSD", "BTC/USD", "BTCUSD.m")

**Issue**: "Lot too small" warning
- **Solution**: Increase risk percentage, use fixed lot mode, or deposit more funds

**Issue**: No trades executing
- **Solution**: Check correlation threshold, spread limits, and time filters

**Issue**: Recovery level not resetting
- **Solution**: Ensure trades are closing at profit. Check `InpResetOnProfit` setting

**Issue**: Excessive spread warnings
- **Solution**: Increase `InpSpreadMultiplier` or `InpFallbackMaxSpread`

### Debug Mode
Enable `InpDebugMode = true` to see detailed logs:
- Signal generation
- Spread analysis
- Recovery state changes
- Position modifications
- Error messages

## Files Generated

The EA creates the following files in the terminal data folder:

1. **CryptoEA_Recovery.dat**: Binary file storing recovery state
   - Persists between EA restarts
   - Ensures recovery continuity
   - Location: `MQL5/Files/`

## Version History

### v4.0 (Current)
- Added adaptive spread analysis
- Implemented loss recovery system
- Added tiered profit protection
- Enhanced position tracking
- Improved risk management
- Added visual dashboard
- Account validation on init
- Recovery state persistence

### v3.0
- Multi-symbol support
- Correlation filtering
- Basic profit security
- Trailing stops

## Credits

**Developer**: Expert MQL5 Coder
**Version**: 4.0
**Platform**: MetaTrader 5
**License**: Proprietary

## Disclaimer

This Expert Advisor is for educational and informational purposes. Cryptocurrency trading involves substantial risk of loss. Past performance does not guarantee future results. Always test thoroughly on a demo account before live trading. The developers assume no responsibility for trading losses.

## Support

For issues, questions, or customization requests, refer to the source code comments or contact the developer through the MQL5 community.

---

**Last Updated**: 2025-11-02
**Compatible With**: MetaTrader 5 Build 3815+
**Recommended Broker**: IC Markets (or any broker with tight crypto spreads)
