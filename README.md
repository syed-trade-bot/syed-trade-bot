# Neural Network Trading Bot (MQL5)

A sophisticated MetaTrader 5 Expert Advisor that uses neural networks for algorithmic trading with comprehensive risk management.

## Overview

This EA implements a custom neural network that learns from market data to make trading decisions. It features advanced risk management, market condition filtering, and adaptive learning capabilities.

## Features

### Neural Network Engine
- **3-Layer Neural Network**: Input layer (3 neurons), hidden layer (4 neurons), output layer (1 neuron)
- **Technical Indicators**: RSI, MACD, and price deviation from moving average
- **Backpropagation Training**: Custom implementation with early stopping
- **Weight Persistence**: Save/load trained weights to files
- **Walk-Forward Optimization**: Adaptive learning over time

### Risk Management
- **Position Sizing**: Dynamic lot calculation based on account risk percentage
- **Stop Loss/Take Profit**: Configurable pip-based levels
- **Daily Loss Limits**: Automatic trading suspension on loss thresholds
- **Maximum Positions**: Concurrent position limits
- **Drawdown Monitoring**: Real-time performance tracking

### Market Condition Filters
- **Spread Control**: Maximum spread filtering
- **Volatility Filter**: ATR-based minimum volatility requirements
- **News Avoidance**: Configurable news event filtering (placeholder)

### Advanced Features
- **Periodic Retraining**: Automatic network retraining on schedule
- **Performance Analytics**: Accuracy, Sharpe ratio, and P&L tracking
- **Detailed Logging**: Comprehensive trade and decision logging
- **Backtesting Support**: Special modes for historical testing

## Configuration Parameters

### Trading Parameters
- `Lots`: Base lot size (default: 0.01)
- `BuyThreshold`: Neural network output threshold for buy signals (default: 0.65)
- `SellThreshold`: Neural network output threshold for sell signals (default: 0.35)
- `MagicNumber`: Unique identifier for EA trades (default: 12345)

### Risk Management
- `StopLossPips`: Stop loss distance in pips (default: 50.0)
- `TakeProfitPips`: Take profit distance in pips (default: 100.0)
- `MaxPositions`: Maximum concurrent positions (default: 1)
- `MaxDailyLoss`: Daily loss limit in account currency (default: 100.0)
- `MaxRiskPerTrade`: Risk per trade as percentage of account (default: 2.0%)

### Neural Network Settings
- `BarsToTrain`: Number of historical bars for training (default: 2000)
- `EnableRetraining`: Enable periodic retraining (default: true)
- `RetrainInterval`: Hours between retraining sessions (default: 168)
- `Timeframe`: Data collection timeframe (default: current chart)

### Market Filters
- `MaxSpreadPoints`: Maximum allowed spread in points (default: 30)
- `MinVolatility`: Minimum volatility threshold (default: 0.0005)
- `EnableNewsFilter`: Enable news filtering (default: true)
- `NewsAvoidMinutes`: Minutes to avoid trading around news (default: 30)

## Installation

1. Copy `FullEAETHUSDm_Fixed.mq5` to your MetaTrader 5 `MQL5/Experts/` directory
2. Compile the EA in MetaEditor
3. Attach to your desired chart (recommended: ETHUSD or similar crypto pairs)
4. Configure parameters according to your risk tolerance
5. Enable automated trading in MetaTrader 5

## Usage

### Initial Training
On first run, the EA will:
1. Collect historical market data
2. Train the neural network (may take several minutes)
3. Save trained weights to a file
4. Begin live trading

### Ongoing Operation
The EA will:
- Monitor market conditions continuously
- Generate predictions using the trained network
- Execute trades based on configurable thresholds
- Manage existing positions with stop loss/take profit
- Retrain the network periodically for adaptation

### Monitoring
Check the Experts tab in MetaTrader 5 for:
- Training progress and accuracy metrics
- Trade execution logs
- Performance statistics
- Error messages and warnings

## Technical Details

### Neural Network Architecture
```
Input Layer (3): [Price/MA, RSI/100, MACD_Histogram]
Hidden Layer (4): Sigmoid activation
Output Layer (1): Sigmoid activation (0.0 = strong sell, 1.0 = strong buy)
```

### Training Process
1. **Data Collection**: Gather OHLC, RSI, MACD data
2. **Feature Engineering**: Normalize inputs to [0,1] range
3. **Target Calculation**: Future return-based targets
4. **Training**: Backpropagation with validation split
5. **Early Stopping**: Prevents overfitting

### File Structure
- `NN_Weights_[SYMBOL]_[TIMEFRAME].txt`: Saved neural network weights
- Logs in MetaTrader 5 Experts tab

## Risk Warnings

⚠️ **Important**: This EA is for educational and research purposes. Trading involves significant risk of loss.

- Always test thoroughly on demo accounts
- Use appropriate position sizing
- Monitor performance regularly
- Be aware of market conditions and news events
- Past performance does not guarantee future results

## Requirements

- MetaTrader 5 platform
- Sufficient historical data for training
- Stable internet connection for live trading
- Adequate account balance for risk management

## License

This project is provided as-is for educational purposes. Use at your own risk.

## Contributing

Contributions and improvements are welcome! Please test thoroughly before submitting changes.

## Support

For questions or issues, please refer to the MetaTrader 5 documentation or MQL5 community forums.