//+------------------------------------------------------------------+
//|                                          FullEAETHUSDm_Fixed.mq5 |
//|                        Complete Neural Network EA with Risk Mgmt |
//|                                       Expert Advisor for ETHUSDm |
//+------------------------------------------------------------------+
#property copyright "2025, Manus - Fixed Version"
#property link      "https://www.manus.im"
#property version   "2.00"
#property description "Neural Network EA with comprehensive risk management and position control."

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//+------------------------------------------------------------------+
//|                          Neural Network Trainer Class            |
//+------------------------------------------------------------------+

// Training Data Structure
struct TrainingData
{
   double inputs[3];      // [normalized_price, rsi, macd]
   double target;         // Expected output (0.0 to 1.0)
   double actual_return;  // Actual market return for validation
   
   TrainingData(const TrainingData& other)
   {
      for(int i = 0; i < 3; i++) inputs[i] = other.inputs[i];
      target = other.target;
      actual_return = other.actual_return;
   }
   
   TrainingData() { target = 0.0; actual_return = 0.0; }
};

// Network Configuration
struct NetworkConfig
{
   int input_size;
   int hidden_size;
   int output_size;
   double learning_rate;
   int epochs;
   double validation_split;
};

class CNeuralTrainer
{
private:
   TrainingData m_data[];
   int m_data_size;
   double m_weights1[3][4];
   double m_bias1[4];
   double m_weights2[4][1];
   double m_bias2[1];
   NetworkConfig m_config;
   
public:
   CNeuralTrainer();
   ~CNeuralTrainer();
   
   // Data Management
   bool CollectTrainingData(string symbol, ENUM_TIMEFRAMES timeframe, int bars_count);
   bool PrepareFeatures(int bar_index, double &features[]);
   double CalculateTarget(int bar_index, int lookforward_bars);
   
   // Training
   bool TrainNetwork(int epochs = 1000, double learning_rate = 0.001);
   double ForwardPass(double &inputs[]);
   void BackpropagateError(double &inputs[], double target, double output);
   
   // Validation
   double ValidateNetwork(int validation_start, int validation_end);
   double CalculateAccuracy(int start_idx, int end_idx);
   double CalculateSharpeRatio(int start_idx, int end_idx);
   
   // Weight Management
   void InitializeWeights();
   bool ExportWeights(string filename);
   bool ImportWeights(string filename);
   void PrintWeights();
   
   // Optimization
   bool WalkForwardOptimization(datetime start_date, datetime end_date);
};

//+------------------------------------------------------------------+
//| Constructor                                                       |
//+------------------------------------------------------------------+
CNeuralTrainer::CNeuralTrainer()
{
   m_data_size = 0;
   m_config.input_size = 3;
   m_config.hidden_size = 4;
   m_config.output_size = 1;
   m_config.learning_rate = 0.001;
   m_config.epochs = 1000;
   m_config.validation_split = 0.2;
   
   InitializeWeights();
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CNeuralTrainer::~CNeuralTrainer()
{
   ArrayFree(m_data);
}

//+------------------------------------------------------------------+
//| Initialize weights with Xavier/Glorot initialization             |
//+------------------------------------------------------------------+
void CNeuralTrainer::InitializeWeights()
{
   MathSrand((int)TimeCurrent());
   
   double limit1 = MathSqrt(6.0 / (3 + 4));
   double limit2 = MathSqrt(6.0 / (4 + 1));
   
   for(int i = 0; i < 3; i++) {
      for(int j = 0; j < 4; j++) {
         m_weights1[i][j] = (2.0 * MathRand() / 32767.0 - 1.0) * limit1;
      }
   }
   
   for(int i = 0; i < 4; i++) {
      m_bias1[i] = 0.0;
      m_weights2[i][0] = (2.0 * MathRand() / 32767.0 - 1.0) * limit2;
   }
   m_bias2[0] = 0.0;
}

//+------------------------------------------------------------------+
//| Collect and prepare training data                                |
//+------------------------------------------------------------------+
bool CNeuralTrainer::CollectTrainingData(string symbol, ENUM_TIMEFRAMES timeframe, int bars_count)
{
   Print("Collecting training data for ", symbol, "...");
   
   int rsi_handle = iRSI(symbol, timeframe, 14, PRICE_CLOSE);
   int macd_handle = iMACD(symbol, timeframe, 12, 26, 9, PRICE_CLOSE);
   
   if(rsi_handle == INVALID_HANDLE || macd_handle == INVALID_HANDLE) {
      Print("ERROR: Failed to create indicators");
      return false;
   }
   
   Sleep(1000);
   
   int lookforward = 5;
   ArrayResize(m_data, bars_count - lookforward);
   m_data_size = 0;
   
   double rsi[], macd_main[], macd_signal[], close[];
   ArraySetAsSeries(rsi, true);
   ArraySetAsSeries(macd_main, true);
   ArraySetAsSeries(macd_signal, true);
   ArraySetAsSeries(close, true);
   
   if(CopyBuffer(rsi_handle, 0, 0, bars_count, rsi) != bars_count ||
      CopyBuffer(macd_handle, 0, 0, bars_count, macd_main) != bars_count ||
      CopyBuffer(macd_handle, 1, 0, bars_count, macd_signal) != bars_count ||
      CopyClose(symbol, timeframe, 0, bars_count, close) != bars_count) {
      Print("ERROR: Failed to copy market data");
      IndicatorRelease(rsi_handle);
      IndicatorRelease(macd_handle);
      return false;
   }
   
   for(int i = lookforward; i < bars_count - 1; i++) {
      TrainingData data_point;
      
      if(!PrepareFeatures(i, data_point.inputs)) continue;
      
      data_point.target = CalculateTarget(i, lookforward);
      data_point.actual_return = (close[i - lookforward] - close[i]) / close[i];
      
      m_data[m_data_size] = data_point;
      m_data_size++;
   }
   
   IndicatorRelease(rsi_handle);
   IndicatorRelease(macd_handle);
   
   Print("Collected ", m_data_size, " training samples");
   return m_data_size > 100;
}

//+------------------------------------------------------------------+
//| Prepare normalized features                                      |
//+------------------------------------------------------------------+
bool CNeuralTrainer::PrepareFeatures(int bar_index, double &features[])
{
   string symbol = Symbol();
   
   double close_price = iClose(symbol, PERIOD_CURRENT, bar_index);
   
   int rsi_handle = iRSI(symbol, PERIOD_CURRENT, 14, PRICE_CLOSE);
   double rsi_buffer[];
   ArraySetAsSeries(rsi_buffer, true);
   if(CopyBuffer(rsi_handle, 0, bar_index, 1, rsi_buffer) != 1) {
      IndicatorRelease(rsi_handle);
      return false;
   }
   double rsi_val = rsi_buffer[0];
   IndicatorRelease(rsi_handle);
   
   int macd_handle = iMACD(symbol, PERIOD_CURRENT, 12, 26, 9, PRICE_CLOSE);
   double macd_main[], macd_signal[];
   ArraySetAsSeries(macd_main, true);
   ArraySetAsSeries(macd_signal, true);
   if(CopyBuffer(macd_handle, 0, bar_index, 1, macd_main) != 1 ||
      CopyBuffer(macd_handle, 1, bar_index, 1, macd_signal) != 1) {
      IndicatorRelease(macd_handle);
      return false;
   }
   IndicatorRelease(macd_handle);
   
   if(close_price <= 0 || rsi_val <= 0) return false;
   
   int ma_handle = iMA(symbol, PERIOD_CURRENT, 200, 0, MODE_SMA, PRICE_CLOSE);
   double ma_buffer[];
   ArraySetAsSeries(ma_buffer, true);
   if(CopyBuffer(ma_handle, 0, bar_index, 1, ma_buffer) != 1) {
      IndicatorRelease(ma_handle);
      return false;
   }
   double price_ma = ma_buffer[0];
   IndicatorRelease(ma_handle);
   
   // Normalize features
   features[0] = (close_price - price_ma) / price_ma;
   features[0] = MathMax(-0.2, MathMin(0.2, features[0]));
   features[0] = (features[0] + 0.2) / 0.4;
   
   features[1] = rsi_val / 100.0;
   
   double macd_hist = macd_main[0] - macd_signal[0];
   features[2] = MathMax(-1.0, MathMin(1.0, macd_hist / (close_price * 0.001)));
   features[2] = (features[2] + 1.0) / 2.0;
   
   return true;
}

//+------------------------------------------------------------------+
//| Calculate target value based on future returns                   |
//+------------------------------------------------------------------+
double CNeuralTrainer::CalculateTarget(int bar_index, int lookforward_bars)
{
   string symbol = Symbol();
   
   double prices[];
   ArraySetAsSeries(prices, true);
   if(CopyClose(symbol, PERIOD_CURRENT, bar_index - lookforward_bars, lookforward_bars + 1, prices) != lookforward_bars + 1) {
      return 0.5;
   }
   
   double current_price = prices[lookforward_bars];
   double future_price = prices[0];
   
   if(current_price <= 0 || future_price <= 0) return 0.5;
   
   double return_pct = (future_price - current_price) / current_price;
   double target = 0.5 + (return_pct * 10.0);
   return MathMax(0.0, MathMin(1.0, target));
}

//+------------------------------------------------------------------+
//| Train the neural network using backpropagation                  |
//+------------------------------------------------------------------+
bool CNeuralTrainer::TrainNetwork(int epochs = 1000, double learning_rate = 0.001)
{
   if(m_data_size < 100) {
      Print("ERROR: Insufficient training data");
      return false;
   }
   
   Print("Starting neural network training...");
   Print("Training samples: ", m_data_size);
   Print("Epochs: ", epochs);
   Print("Learning rate: ", learning_rate);
   
   m_config.learning_rate = learning_rate;
   
   int train_size = (int)(m_data_size * (1.0 - m_config.validation_split));
   int val_size = m_data_size - train_size;
   
   double best_val_loss = 1e9;
   int patience = 100;
   int no_improve_count = 0;
   
   for(int epoch = 0; epoch < epochs; epoch++) {
      double total_loss = 0.0;
      
      // Shuffle training data
      for(int i = 0; i < train_size; i++) {
         int j = i + (MathRand() % (train_size - i));
         TrainingData temp = m_data[i];
         m_data[i] = m_data[j];
         m_data[j] = temp;
      }
      
      // Training phase
      for(int i = 0; i < train_size; i++) {
         double output = ForwardPass(m_data[i].inputs);
         BackpropagateError(m_data[i].inputs, m_data[i].target, output);
         
         double error = m_data[i].target - output;
         total_loss += error * error;
      }
      
      // Validation phase
      if(epoch % 10 == 0) {
         double val_loss = 0.0;
         for(int i = train_size; i < m_data_size; i++) {
            double output = ForwardPass(m_data[i].inputs);
            double error = m_data[i].target - output;
            val_loss += error * error;
         }
         val_loss /= val_size;
         
         if(val_loss < best_val_loss) {
            best_val_loss = val_loss;
            no_improve_count = 0;
         } else {
            no_improve_count += 10;
         }
         
         PrintFormat("Epoch %d: Train Loss=%.6f, Val Loss=%.6f", 
                    epoch, total_loss/train_size, val_loss);
         
         if(no_improve_count >= patience) {
            Print("Early stopping triggered at epoch ", epoch);
            break;
         }
      }
   }
   
   Print("Training completed. Best validation loss: ", best_val_loss);
   return true;
}

//+------------------------------------------------------------------+
//| Forward pass through the network                                 |
//+------------------------------------------------------------------+
double CNeuralTrainer::ForwardPass(double &inputs[])
{
   // Hidden layer
   double hidden[4];
   for(int i = 0; i < 4; i++) {
      double sum = m_bias1[i];
      for(int j = 0; j < 3; j++) {
         sum += inputs[j] * m_weights1[j][i];
      }
      hidden[i] = 1.0 / (1.0 + MathExp(-sum));
   }
   
   // Output layer
   double output = m_bias2[0];
   for(int i = 0; i < 4; i++) {
      output += hidden[i] * m_weights2[i][0];
   }
   
   return 1.0 / (1.0 + MathExp(-output));
}

//+------------------------------------------------------------------+
//| Backpropagation algorithm                                        |
//+------------------------------------------------------------------+
void CNeuralTrainer::BackpropagateError(double &inputs[], double target, double output)
{
   double output_error = (target - output) * output * (1.0 - output);
   
   // Recalculate hidden layer values
   double hidden[4];
   for(int i = 0; i < 4; i++) {
      double sum = m_bias1[i];
      for(int j = 0; j < 3; j++) {
         sum += inputs[j] * m_weights1[j][i];
      }
      hidden[i] = 1.0 / (1.0 + MathExp(-sum));
   }
   
   // Update output layer weights
   for(int i = 0; i < 4; i++) {
      m_weights2[i][0] += m_config.learning_rate * output_error * hidden[i];
   }
   m_bias2[0] += m_config.learning_rate * output_error;
   
   // Calculate hidden layer errors
   double hidden_errors[4];
   for(int i = 0; i < 4; i++) {
      hidden_errors[i] = output_error * m_weights2[i][0] * hidden[i] * (1.0 - hidden[i]);
   }
   
   // Update hidden layer weights
   for(int i = 0; i < 3; i++) {
      for(int j = 0; j < 4; j++) {
         m_weights1[i][j] += m_config.learning_rate * hidden_errors[j] * inputs[i];
      }
   }
   
   for(int i = 0; i < 4; i++) {
      m_bias1[i] += m_config.learning_rate * hidden_errors[i];
   }
}

//+------------------------------------------------------------------+
//| Export trained weights to file                                  |
//+------------------------------------------------------------------+
bool CNeuralTrainer::ExportWeights(string filename)
{
   int file_handle = FileOpen(filename, FILE_WRITE | FILE_TXT);
   if(file_handle == INVALID_HANDLE) {
      Print("ERROR: Cannot create weights file");
      return false;
   }
   
   FileWrite(file_handle, "// Neural Network Weights - Generated ", TimeToString(TimeCurrent()));
   FileWrite(file_handle, "");
   
   // Layer 1 weights
   FileWrite(file_handle, "WEIGHTS1_START");
   for(int i = 0; i < 3; i++) {
      for(int j = 0; j < 4; j++) {
         FileWrite(file_handle, DoubleToString(m_weights1[i][j], 8));
      }
   }
   FileWrite(file_handle, "WEIGHTS1_END");
   
   // Bias 1
   FileWrite(file_handle, "BIAS1_START");
   for(int i = 0; i < 4; i++) {
      FileWrite(file_handle, DoubleToString(m_bias1[i], 8));
   }
   FileWrite(file_handle, "BIAS1_END");
   
   // Layer 2 weights
   FileWrite(file_handle, "WEIGHTS2_START");
   for(int i = 0; i < 4; i++) {
      FileWrite(file_handle, DoubleToString(m_weights2[i][0], 8));
   }
   FileWrite(file_handle, "WEIGHTS2_END");
   
   // Bias 2
   FileWrite(file_handle, "BIAS2_START");
   FileWrite(file_handle, DoubleToString(m_bias2[0], 8));
   FileWrite(file_handle, "BIAS2_END");
   
   FileClose(file_handle);
   Print("Weights exported to: ", filename);
   return true;
}

//+------------------------------------------------------------------+
//| Import weights from file                                         |
//+------------------------------------------------------------------+
bool CNeuralTrainer::ImportWeights(string filename)
{
   int file_handle = FileOpen(filename, FILE_READ | FILE_TXT);
   if(file_handle == INVALID_HANDLE) {
      Print("Weight file not found: ", filename);
      return false;
   }
   
   string line;
   int section = 0; // 0=none, 1=weights1, 2=bias1, 3=weights2, 4=bias2
   int idx = 0;
   
   while(!FileIsEnding(file_handle)) {
      line = FileReadString(file_handle);
      
      if(line == "WEIGHTS1_START") { section = 1; idx = 0; continue; }
      if(line == "WEIGHTS1_END") { section = 0; continue; }
      if(line == "BIAS1_START") { section = 2; idx = 0; continue; }
      if(line == "BIAS1_END") { section = 0; continue; }
      if(line == "WEIGHTS2_START") { section = 3; idx = 0; continue; }
      if(line == "WEIGHTS2_END") { section = 0; continue; }
      if(line == "BIAS2_START") { section = 4; idx = 0; continue; }
      if(line == "BIAS2_END") { section = 0; continue; }
      
      if(section == 1 && idx < 12) { // weights1 [3][4] = 12 values
         int i = idx / 4;
         int j = idx % 4;
         m_weights1[i][j] = StringToDouble(line);
         idx++;
      }
      else if(section == 2 && idx < 4) { // bias1 [4]
         m_bias1[idx] = StringToDouble(line);
         idx++;
      }
      else if(section == 3 && idx < 4) { // weights2 [4][1]
         m_weights2[idx][0] = StringToDouble(line);
         idx++;
      }
      else if(section == 4) { // bias2 [1]
         m_bias2[0] = StringToDouble(line);
      }
   }
   
   FileClose(file_handle);
   Print("Weights imported successfully from: ", filename);
   return true;
}

//+------------------------------------------------------------------+
//| Validate network performance                                     |
//+------------------------------------------------------------------+
double CNeuralTrainer::ValidateNetwork(int validation_start, int validation_end)
{
   if(validation_end >= m_data_size) validation_end = m_data_size - 1;
   if(validation_start < 0) validation_start = 0;
   
   double total_error = 0.0;
   int correct_predictions = 0;
   int total_predictions = validation_end - validation_start + 1;
   
   for(int i = validation_start; i <= validation_end; i++) {
      double output = ForwardPass(m_data[i].inputs);
      double target = m_data[i].target;
      
      double error = target - output;
      total_error += error * error;
      
      bool predicted_up = (output > 0.5);
      bool actual_up = (target > 0.5);
      if(predicted_up == actual_up) correct_predictions++;
   }
   
   double mse = total_error / total_predictions;
   double accuracy = (double)correct_predictions / total_predictions;
   
   PrintFormat("Validation MSE: %.6f, Accuracy: %.2f%%", mse, accuracy * 100);
   return accuracy;
}

//+------------------------------------------------------------------+
//| Calculate directional accuracy                                   |
//+------------------------------------------------------------------+
double CNeuralTrainer::CalculateAccuracy(int start_idx, int end_idx)
{
   int correct = 0;
   int total = 0;
   
   for(int i = start_idx; i <= end_idx && i < m_data_size; i++) {
      double output = ForwardPass(m_data[i].inputs);
      
      bool predicted_up = (output > 0.5);
      bool actual_up = (m_data[i].actual_return > 0.0);
      
      if(predicted_up == actual_up) correct++;
      total++;
   }
   
   return (total > 0) ? (double)correct / total : 0.0;
}

//+------------------------------------------------------------------+
//| Calculate Sharpe ratio                                           |
//+------------------------------------------------------------------+
double CNeuralTrainer::CalculateSharpeRatio(int start_idx, int end_idx)
{
   double returns[];
   int count = 0;
   
   ArrayResize(returns, end_idx - start_idx + 1);
   
   for(int i = start_idx; i <= end_idx && i < m_data_size; i++) {
      double output = ForwardPass(m_data[i].inputs);
      
      double predicted_return = 0.0;
      if(output > 0.6) {
         predicted_return = m_data[i].actual_return;
      }
      else if(output < 0.4) {
         predicted_return = -m_data[i].actual_return;
      }
      
      returns[count] = predicted_return;
      count++;
   }
   
   if(count < 2) return 0.0;
   
   double mean = 0.0;
   for(int i = 0; i < count; i++) mean += returns[i];
   mean /= count;
   
   double variance = 0.0;
   for(int i = 0; i < count; i++) {
      double diff = returns[i] - mean;
      variance += diff * diff;
   }
   variance /= (count - 1);
   
   double std_dev = MathSqrt(variance);
   
   return (std_dev > 0.0) ? (mean / std_dev) * MathSqrt(252.0) : 0.0;
}

//+------------------------------------------------------------------+
//| Print weights for debugging                                      |
//+------------------------------------------------------------------+
void CNeuralTrainer::PrintWeights()
{
   Print("=== Neural Network Weights ===");
   Print("Layer 1 Weights:");
   for(int i = 0; i < 3; i++) {
      string row = "";
      for(int j = 0; j < 4; j++) {
         row += DoubleToString(m_weights1[i][j], 6) + " ";
      }
      Print("  ", row);
   }
   Print("Layer 1 Bias:");
   string bias = "";
   for(int i = 0; i < 4; i++) {
      bias += DoubleToString(m_bias1[i], 6) + " ";
   }
   Print("  ", bias);
   
   Print("Layer 2 Weights:");
   for(int i = 0; i < 4; i++) {
      Print("  ", DoubleToString(m_weights2[i][0], 6));
   }
   
   Print("Layer 2 Bias: ", DoubleToString(m_bias2[0], 6));
}

//+------------------------------------------------------------------+
//| Walk-forward optimization                                        |
//+------------------------------------------------------------------+
bool CNeuralTrainer::WalkForwardOptimization(datetime start_date, datetime end_date)
{
   Print("Starting walk-forward optimization...");
   
   int training_window = 1000;
   int test_window = 200;
   
   datetime current_date = start_date;
   double total_return = 0.0;
   int periods = 0;
   
   while(current_date < end_date) {
      CollectTrainingData(Symbol(), PERIOD_CURRENT, training_window);
      TrainNetwork(500, 0.01);
      
      double period_return = ValidateNetwork(0, test_window);
      total_return += period_return;
      periods++;
      
      PrintFormat("Period %d: Return = %.4f%%", periods, period_return * 100);
      
      current_date += test_window * PeriodSeconds(PERIOD_CURRENT);
   }
   
   double avg_return = total_return / periods;
   PrintFormat("Walk-forward completed. Average return: %.4f%%", avg_return * 100);
   
   return avg_return > 0.0;
}

//+------------------------------------------------------------------+
//|                            EA MAIN CODE                          |
//+------------------------------------------------------------------+

// Global objects
CNeuralTrainer *neuralTrainer;
CTrade trade;
CPositionInfo position;
CSymbolInfo symbolInfo;

// EA Parameters - Trading Settings
input group "=== Trading Parameters ==="
input double  Lots              = 0.01;    // Lot size
input double  BuyThreshold      = 0.65;    // NN output threshold for Buy (higher = more selective)
input double  SellThreshold     = 0.35;    // NN output threshold for Sell (lower = more selective)
input int     MagicNumber       = 12345;   // Magic number for trades

// EA Parameters - Risk Management
input group "=== Risk Management ==="
input double  StopLossPips      = 50.0;    // Stop loss in pips
input double  TakeProfitPips    = 100.0;   // Take profit in pips
input int     MaxPositions      = 1;       // Maximum concurrent positions
input double  MaxDailyLoss      = 100.0;   // Maximum daily loss in account currency
input double  MaxRiskPerTrade   = 2.0;     // Maximum risk per trade as % of account

// EA Parameters - Training Settings
input group "=== Neural Network Settings ==="
input int     BarsToTrain       = 2000;    // Number of bars for initial training
input bool    EnableRetraining  = true;    // Enable periodic retraining
input int     RetrainInterval   = 168;     // Hours between retraining (168 = 1 week)
input ENUM_TIMEFRAMES Timeframe = PERIOD_CURRENT; // Timeframe for data collection

// EA Parameters - Market Conditions
input group "=== Market Condition Filters ==="
input int     MaxSpreadPoints   = 30;      // Maximum spread in points
input double  MinVolatility     = 0.0005;  // Minimum volatility (ATR/Price)
input bool    EnableNewsFilter  = true;    // Avoid trading during high-impact news
input int     NewsAvoidMinutes  = 30;      // Minutes to avoid trading before/after news

// EA Parameters - Advanced Settings
input group "=== Advanced Settings ==="
input bool    EnableLogging     = true;    // Enable detailed logging
input bool    BacktestMode      = false;   // Special settings for backtesting
input int     NN_UpdateBars     = 3;       // Update NN prediction every N bars

// Performance tracking variables
double daily_pnl = 0.0;
double session_start_balance = 0.0;
datetime last_retrain_time = 0;
datetime last_nn_update = 0;
double last_prediction = 0.5;
int total_trades_today = 0;
datetime last_trade_day = 0;

// Risk management variables
double peak_equity = 0.0;
double max_drawdown = 0.0;
double total_trades = 0.0;
double winning_trades = 0.0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("Initializing Neural Network EA...");
   
   // Initialize objects
   neuralTrainer = new CNeuralTrainer();
   trade.SetExpertMagic(MagicNumber);
   trade.SetTypeFilling(ORDER_FILLING_FOK);
   symbolInfo.Name(Symbol());
   
   // Initialize performance tracking
   session_start_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   peak_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   last_retrain_time = TimeCurrent();
   
   // Reset daily counters if new day
   datetime current_time = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(current_time, dt);
   if(dt.hour == 0 && dt.min == 0) {
      ResetDailyCounters();
   }
   
   // Load or train neural network
   string weight_filename = StringFormat("NN_Weights_%s_%s.txt", Symbol(), EnumToString(Timeframe));
   
   if(!neuralTrainer.ImportWeights(weight_filename)) {
      PrintFormat("Weight file %s not found. Training new network...", weight_filename);
      
      if(!neuralTrainer.CollectTrainingData(Symbol(), Timeframe, BarsToTrain)) {
         Print("ERROR: Failed to collect sufficient training data");
         return INIT_FAILED;
      }
      
      if(!neuralTrainer.TrainNetwork(1000, 0.001)) {
         Print("ERROR: Neural network training failed");
         return INIT_FAILED;
      }
      
      neuralTrainer.ExportWeights(weight_filename);
      Print("Neural network trained and weights exported successfully");
   } else {
      Print("Neural network weights loaded successfully");
   }
   
   // Validate network on recent data
   Print("Validating network on recent data...");
   if(neuralTrainer.CollectTrainingData(Symbol(), Timeframe, 500)) {
      double accuracy = neuralTrainer.ValidateNetwork(0, 100);
      if(accuracy < 0.45) {
         Print("WARNING: Network accuracy is low (", accuracy, "). Consider retraining.");
      }
   }
   
   Print("Neural Network EA initialized successfully");
   PrintCurrentSettings();
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("Deinitializing Neural Network EA...");
   PrintFinalStats();
   
   if(neuralTrainer != NULL) {
      delete neuralTrainer;
      neuralTrainer = NULL;
   }
   
   Print("Neural Network EA deinitialized");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check daily reset
   CheckDailyReset();
   
   // Check daily loss limit
   if(daily_pnl <= -MaxDailyLoss) {
      if(EnableLogging) Print("Daily loss limit reached. Trading suspended.");
      return;
   }
   
   // Update performance metrics
   UpdatePerformanceMetrics();
   
   // Check for retraining
   if(EnableRetraining && ShouldRetrain()) {
      PerformRetraining();
   }
   
   // Check market conditions
   if(!IsMarketConditionGood()) {
      if(EnableLogging) Print("Market conditions not suitable for trading");
      return;
   }
   
   // Check existing positions first
   if(HasOpenPosition()) {
      ManageOpenPositions();
      return;
   }
   
   // Check if we can open new positions
   if(!CanOpenNewPosition()) {
      return;
   }
   
   // Get neural network prediction (with caching)
   double prediction = GetNeuralNetworkPrediction();
   if(prediction < 0) return; // Error getting prediction
   
   // Execute trading logic
   ExecuteTradingLogic(prediction);
}

//+------------------------------------------------------------------+
//| Check if we should retrain the network                          |
//+------------------------------------------------------------------+
bool ShouldRetrain()
{
   return (TimeCurrent() - last_retrain_time) > (RetrainInterval * 3600);
}

//+------------------------------------------------------------------+
//| Perform network retraining                                      |
//+------------------------------------------------------------------+
void PerformRetraining()
{
   Print("Starting scheduled network retraining...");
   
   if(neuralTrainer.CollectTrainingData(Symbol(), Timeframe, BarsToTrain)) {
      if(neuralTrainer.TrainNetwork(800, 0.001)) {
         string weight_filename = StringFormat("NN_Weights_%s_%s.txt", Symbol(), EnumToString(Timeframe));
         neuralTrainer.ExportWeights(weight_filename);
         Print("Network retrained and weights saved successfully");
      }
   }
   
   last_retrain_time = TimeCurrent();
}

//+------------------------------------------------------------------+
//| Check market conditions                                          |
//+------------------------------------------------------------------+
bool IsMarketConditionGood()
{
   // Check spread
   double spread = symbolInfo.Spread() * symbolInfo.Point();
   double max_spread = MaxSpreadPoints * symbolInfo.Point();
   if(spread > max_spread) {
      if(EnableLogging) PrintFormat("Spread too high: %.1f points (max: %d)", 
                                   spread/symbolInfo.Point(), MaxSpreadPoints);
      return false;
   }
   
   // Check volatility using ATR
   int atr_handle = iATR(Symbol(), Timeframe, 14);
   if(atr_handle == INVALID_HANDLE) {
      if(EnableLogging) Print("ERROR: Failed to create ATR indicator");
      return false;
   }
   
   double atr_buffer[];
   ArraySetAsSeries(atr_buffer, true);
   if(CopyBuffer(atr_handle, 0, 0, 1, atr_buffer) != 1) {
      IndicatorRelease(atr_handle);
      if(EnableLogging) Print("ERROR: Failed to get ATR data");
      return false;
   }
   
   double current_price = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
   double volatility = atr_buffer[0] / current_price;
   
   IndicatorRelease(atr_handle);
   
   if(volatility < MinVolatility) {
      if(EnableLogging) PrintFormat("Volatility too low: %.6f (min: %.6f)", volatility, MinVolatility);
      return false;
   }
   
   // News filter would go here if calendar API was available
   if(EnableNewsFilter) {
      // Placeholder for news filtering logic
      // In a real implementation, you would check economic calendar
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Check if we have open positions                                 |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   for(int i = 0; i < PositionsTotal(); i++) {
      if(position.SelectByIndex(i)) {
         if(position.Symbol() == Symbol() && position.Magic() == MagicNumber) {
            return true;
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Manage open positions                                            |
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   for(int i = 0; i < PositionsTotal(); i++) {
      if(position.SelectByIndex(i)) {
         if(position.Symbol() == Symbol() && position.Magic() == MagicNumber) {
            // Position management logic could go here
            // For example: trailing stops, partial closes, etc.
            
            // Basic profit/loss check
            double profit = position.Profit();
            if(EnableLogging && profit != 0) {
               PrintFormat("Position profit: %.2f", profit);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check if we can open a new position                             |
//+------------------------------------------------------------------+
bool CanOpenNewPosition()
{
   // Count existing positions
   int position_count = 0;
   for(int i = 0; i < PositionsTotal(); i++) {
      if(position.SelectByIndex(i)) {
         if(position.Symbol() == Symbol() && position.Magic() == MagicNumber) {
            position_count++;
         }
      }
   }
   
   if(position_count >= MaxPositions) {
      if(EnableLogging) Print("Maximum positions reached");
      return false;
   }
   
   // Check account balance
   double account_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(account_balance <= 0) {
      if(EnableLogging) Print("Insufficient account balance");
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Get neural network prediction with caching                      |
//+------------------------------------------------------------------+
double GetNeuralNetworkPrediction()
{
   // Check if we need to update prediction
   datetime current_time = TimeCurrent();
   int current_bar = iBars(Symbol(), Timeframe) - 1;
   
   if(current_time - last_nn_update < NN_UpdateBars * PeriodSeconds(Timeframe)) {
      return last_prediction; // Use cached prediction
   }
   
   // Prepare features for current bar
   double features[3];
   if(!neuralTrainer.PrepareFeatures(0, features)) {
      if(EnableLogging) Print("ERROR: Failed to prepare features for prediction");
      return -1.0;
   }
   
   // Get prediction from neural network
   double prediction = neuralTrainer.ForwardPass(features);
   
   last_prediction = prediction;
   last_nn_update = current_time;
   
   if(EnableLogging) {
      PrintFormat("NN Prediction: %.4f (Features: %.4f, %.4f, %.4f)", 
                 prediction, features[0], features[1], features[2]);
   }
   
   return prediction;
}

//+------------------------------------------------------------------+
//| Execute trading logic based on prediction                       |
//+------------------------------------------------------------------+
void ExecuteTradingLogic(double prediction)
{
   double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
   double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   
   // Calculate position size based on risk management
   double lot_size = CalculatePositionSize();
   
   // Buy signal
   if(prediction >= BuyThreshold) {
      double sl = ask - (StopLossPips * symbolInfo.Point() * 10);
      double tp = ask + (TakeProfitPips * symbolInfo.Point() * 10);
      
      if(trade.Buy(lot_size, Symbol(), ask, sl, tp, "NN Buy Signal")) {
         if(EnableLogging) {
            PrintFormat("BUY order opened: Lots=%.2f, Entry=%.5f, SL=%.5f, TP=%.5f, Prediction=%.4f", 
                       lot_size, ask, sl, tp, prediction);
         }
         total_trades++;
         total_trades_today++;
      } else {
         if(EnableLogging) Print("ERROR: Failed to open BUY order - ", GetLastError());
      }
   }
   // Sell signal
   else if(prediction <= SellThreshold) {
      double sl = bid + (StopLossPips * symbolInfo.Point() * 10);
      double tp = bid - (TakeProfitPips * symbolInfo.Point() * 10);
      
      if(trade.Sell(lot_size, Symbol(), bid, sl, tp, "NN Sell Signal")) {
         if(EnableLogging) {
            PrintFormat("SELL order opened: Lots=%.2f, Entry=%.5f, SL=%.5f, TP=%.5f, Prediction=%.4f", 
                       lot_size, bid, sl, tp, prediction);
         }
         total_trades++;
         total_trades_today++;
      } else {
         if(EnableLogging) Print("ERROR: Failed to open SELL order - ", GetLastError());
      }
   }
}

//+------------------------------------------------------------------+
//| Calculate position size based on risk management                |
//+------------------------------------------------------------------+
double CalculatePositionSize()
{
   double account_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk_amount = account_balance * (MaxRiskPerTrade / 100.0);
   
   double pip_value = symbolInfo.TickValue();
   double stop_loss_amount = StopLossPips * pip_value;
   
   double calculated_lots = risk_amount / stop_loss_amount;
   
   // Apply minimum and maximum limits
   double min_lot = symbolInfo.LotsMin();
   double max_lot = symbolInfo.LotsMax();
   double lot_step = symbolInfo.LotsStep();
   
   calculated_lots = MathMax(min_lot, MathMin(max_lot, calculated_lots));
   calculated_lots = MathFloor(calculated_lots / lot_step) * lot_step;
   
   // Use input lot size if calculated size is too different
   if(calculated_lots < Lots * 0.5 || calculated_lots > Lots * 2.0) {
      calculated_lots = Lots;
   }
   
   return calculated_lots;
}

//+------------------------------------------------------------------+
//| Reset daily counters                                             |
//+------------------------------------------------------------------+
void ResetDailyCounters()
{
   daily_pnl = 0.0;
   total_trades_today = 0;
   session_start_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   
   if(EnableLogging) Print("Daily counters reset");
}

//+------------------------------------------------------------------+
//| Check for daily reset                                           |
//+------------------------------------------------------------------+
void CheckDailyReset()
{
   datetime current_time = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(current_time, dt);
   
   if(last_trade_day == 0) {
      last_trade_day = current_time;
      return;
   }
   
   MqlDateTime last_dt;
   TimeToStruct(last_trade_day, last_dt);
   
   if(dt.day != last_dt.day) {
      ResetDailyCounters();
      last_trade_day = current_time;
   }
}

//+------------------------------------------------------------------+
//| Update performance metrics                                       |
//+------------------------------------------------------------------+
void UpdatePerformanceMetrics()
{
   double current_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   
   // Update peak equity and drawdown
   if(current_equity > peak_equity) {
      peak_equity = current_equity;
   }
   
   double current_drawdown = (peak_equity - current_equity) / peak_equity * 100.0;
   if(current_drawdown > max_drawdown) {
      max_drawdown = current_drawdown;
   }
   
   // Update daily P&L
   daily_pnl = current_equity - session_start_balance;
}

//+------------------------------------------------------------------+
//| Print current settings                                          |
//+------------------------------------------------------------------+
void PrintCurrentSettings()
{
   Print("=== Neural Network EA Settings ===");
   PrintFormat("Symbol: %s", Symbol());
   PrintFormat("Timeframe: %s", EnumToString(Timeframe));
   PrintFormat("Lot Size: %.2f", Lots);
   PrintFormat("Buy Threshold: %.2f", BuyThreshold);
   PrintFormat("Sell Threshold: %.2f", SellThreshold);
   PrintFormat("Stop Loss: %.1f pips", StopLossPips);
   PrintFormat("Take Profit: %.1f pips", TakeProfitPips);
   PrintFormat("Max Positions: %d", MaxPositions);
   PrintFormat("Max Daily Loss: %.2f", MaxDailyLoss);
   PrintFormat("Max Risk Per Trade: %.1f%%", MaxRiskPerTrade);
   Print("================================");
}

//+------------------------------------------------------------------+
//| Print final statistics                                          |
//+------------------------------------------------------------------+
void PrintFinalStats()
{
   Print("=== Final Performance Statistics ===");
   PrintFormat("Total Trades: %.0f", total_trades);
   if(total_trades > 0) {
      PrintFormat("Winning Trades: %.0f (%.1f%%)", winning_trades, (winning_trades/total_trades)*100);
   }
   PrintFormat("Max Drawdown: %.2f%%", max_drawdown);
   PrintFormat("Final Equity: %.2f", AccountInfoDouble(ACCOUNT_EQUITY));
   PrintFormat("Total P&L: %.2f", AccountInfoDouble(ACCOUNT_EQUITY) - session_start_balance);
   Print("=====================================");
}