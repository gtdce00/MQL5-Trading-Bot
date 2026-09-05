//+------------------------------------------------------------------+
//|                                              SafeEMACrossEA.mq5  |
//|                        Safety-first EMA crossover baseline EA     |
//+------------------------------------------------------------------+
#property copyright "MQL5 Trading Bot"
#property version   "0.1.0"
#property strict

#include <Trade/Trade.mqh>

input group "Trading authorization"
input bool   InpEnableTrading          = false;  // Live/demo trading opt-in; tester is enabled automatically
input long   InpMagicNumber            = 26090501;

input group "Signal"
input int    InpFastEMAPeriod          = 20;
input int    InpSlowEMAPeriod          = 50;
input int    InpATRPeriod              = 14;

input group "Risk management"
input double InpRiskPercent            = 0.50;
input double InpATRStopMultiplier      = 2.00;
input double InpRiskRewardRatio        = 2.00;
input double InpMaximumDailyLossPct    = 2.00;
input double InpMaximumDrawdownPct     = 10.00;
input int    InpMaximumPositions       = 1;

input group "Execution filters"
input int    InpMaximumSpreadPoints    = 30;
input int    InpSlippagePoints         = 10;
input int    InpSessionStartHour       = 0;
input int    InpSessionEndHour         = 23;

CTrade   g_trade;
int      g_fast_ema_handle = INVALID_HANDLE;
int      g_slow_ema_handle = INVALID_HANDLE;
int      g_atr_handle      = INVALID_HANDLE;
datetime g_last_bar_time   = 0;
double   g_daily_start_equity = 0.0;
double   g_peak_equity        = 0.0;
int      g_equity_day_id      = -1;
bool     g_risk_halt_logged   = false;

//+------------------------------------------------------------------+
//| Validate all externally supplied parameters                       |
//+------------------------------------------------------------------+
bool ValidateInputs()
{
   if(InpMagicNumber <= 0)
   {
      Print("Initialization failed: Magic Number must be positive.");
      return false;
   }
   if(InpFastEMAPeriod < 2 || InpSlowEMAPeriod <= InpFastEMAPeriod)
   {
      Print("Initialization failed: EMA periods must satisfy 2 <= fast < slow.");
      return false;
   }
   if(InpATRPeriod < 2 || InpATRStopMultiplier <= 0.0 || InpRiskRewardRatio <= 0.0)
   {
      Print("Initialization failed: ATR and risk/reward parameters must be positive.");
      return false;
   }
   if(InpRiskPercent <= 0.0 || InpRiskPercent > 5.0)
   {
      Print("Initialization failed: Risk percent must be in (0, 5].");
      return false;
   }
   if(InpMaximumDailyLossPct <= 0.0 || InpMaximumDailyLossPct > 20.0 ||
      InpMaximumDrawdownPct <= 0.0 || InpMaximumDrawdownPct > 50.0)
   {
      Print("Initialization failed: Account protection limits are outside safe bounds.");
      return false;
   }
   if(InpMaximumPositions < 1 || InpMaximumPositions > 10)
   {
      Print("Initialization failed: Maximum positions must be in [1, 10].");
      return false;
   }
   if(InpMaximumSpreadPoints < 0 || InpSlippagePoints < 0)
   {
      Print("Initialization failed: Spread and slippage limits cannot be negative.");
      return false;
   }
   if(InpSessionStartHour < 0 || InpSessionStartHour > 23 ||
      InpSessionEndHour < 0 || InpSessionEndHour > 23)
   {
      Print("Initialization failed: Session hours must be in [0, 23].");
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Create a stable day identifier from trade-server time             |
//+------------------------------------------------------------------+
int CurrentDayId()
{
   MqlDateTime parts;
   TimeToStruct(TimeTradeServer(), parts);
   return parts.year * 1000 + parts.day_of_year;
}

//+------------------------------------------------------------------+
//| Keys for persistent live/demo account protection state            |
//+------------------------------------------------------------------+
string RiskStateKey(const string suffix)
{
   return StringFormat("SafeEMA_%I64d_%I64d_%s",
                       AccountInfoInteger(ACCOUNT_LOGIN),
                       InpMagicNumber,
                       suffix);
}

//+------------------------------------------------------------------+
//| Persist protection state outside Strategy Tester                  |
//+------------------------------------------------------------------+
void SaveRiskState()
{
   if(MQLInfoInteger(MQL_TESTER))
      return;

   GlobalVariableSet(RiskStateKey("day"), (double)g_equity_day_id);
   GlobalVariableSet(RiskStateKey("daily"), g_daily_start_equity);
   GlobalVariableSet(RiskStateKey("peak"), g_peak_equity);
}

//+------------------------------------------------------------------+
//| Initialize account protection state                               |
//+------------------------------------------------------------------+
void InitializeRiskState()
{
   const double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   const int day_id = CurrentDayId();

   g_equity_day_id = day_id;
   g_daily_start_equity = equity;
   g_peak_equity = equity;

   if(!MQLInfoInteger(MQL_TESTER))
   {
      const string day_key = RiskStateKey("day");
      const string daily_key = RiskStateKey("daily");
      const string peak_key = RiskStateKey("peak");

      if(GlobalVariableCheck(day_key) &&
         GlobalVariableCheck(daily_key) &&
         (int)GlobalVariableGet(day_key) == day_id)
      {
         g_daily_start_equity = GlobalVariableGet(daily_key);
      }
      if(GlobalVariableCheck(peak_key))
      {
         g_peak_equity = MathMax(equity, GlobalVariableGet(peak_key));
      }
   }
   SaveRiskState();
}

//+------------------------------------------------------------------+
//| Update daily and peak equity reference values                     |
//+------------------------------------------------------------------+
void UpdateRiskState()
{
   const double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   const int day_id = CurrentDayId();
   bool changed = false;

   if(day_id != g_equity_day_id)
   {
      g_equity_day_id = day_id;
      g_daily_start_equity = equity;
      changed = true;
   }
   if(equity > g_peak_equity)
   {
      g_peak_equity = equity;
      changed = true;
   }
   if(changed)
      SaveRiskState();
}

//+------------------------------------------------------------------+
//| Detect account-level loss breakers                                |
//+------------------------------------------------------------------+
bool RiskLimitsBreached(string &reason)
{
   UpdateRiskState();
   const double equity = AccountInfoDouble(ACCOUNT_EQUITY);

   if(g_daily_start_equity > 0.0)
   {
      const double daily_loss_pct =
         100.0 * (g_daily_start_equity - equity) / g_daily_start_equity;
      if(daily_loss_pct >= InpMaximumDailyLossPct)
      {
         reason = StringFormat("daily equity loss %.2f%% reached limit %.2f%%",
                               daily_loss_pct, InpMaximumDailyLossPct);
         return true;
      }
   }

   if(g_peak_equity > 0.0)
   {
      const double drawdown_pct =
         100.0 * (g_peak_equity - equity) / g_peak_equity;
      if(drawdown_pct >= InpMaximumDrawdownPct)
      {
         reason = StringFormat("equity drawdown %.2f%% reached limit %.2f%%",
                               drawdown_pct, InpMaximumDrawdownPct);
         return true;
      }
   }
   reason = "";
   return false;
}

//+------------------------------------------------------------------+
//| Live/demo orders require opt-in; Strategy Tester is always safe   |
//+------------------------------------------------------------------+
bool TradingAuthorized()
{
   return InpEnableTrading || (bool)MQLInfoInteger(MQL_TESTER);
}

//+------------------------------------------------------------------+
//| Restrict new entries to the configured server-time session        |
//+------------------------------------------------------------------+
bool IsWithinTradingSession()
{
   MqlDateTime parts;
   TimeToStruct(TimeTradeServer(), parts);

   if(InpSessionStartHour <= InpSessionEndHour)
      return parts.hour >= InpSessionStartHour && parts.hour <= InpSessionEndHour;

   return parts.hour >= InpSessionStartHour || parts.hour <= InpSessionEndHour;
}

//+------------------------------------------------------------------+
//| Process a signal once per chart bar                               |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   const datetime current_bar_time = iTime(_Symbol, _Period, 0);
   if(current_bar_time <= 0)
      return false;
   if(g_last_bar_time == 0)
   {
      g_last_bar_time = current_bar_time;
      return false;
   }
   if(current_bar_time == g_last_bar_time)
      return false;

   g_last_bar_time = current_bar_time;
   return true;
}

//+------------------------------------------------------------------+
//| Count positions belonging to this EA and symbol                   |
//+------------------------------------------------------------------+
int CountOwnPositions()
{
   int count = 0;
   for(int index = PositionsTotal() - 1; index >= 0; --index)
   {
      const ulong ticket = PositionGetTicket(index);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
      {
         ++count;
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| Avoid altering a netting position owned by another strategy       |
//+------------------------------------------------------------------+
bool HasForeignPositionOnSymbol()
{
   for(int index = PositionsTotal() - 1; index >= 0; --index)
   {
      const ulong ticket = PositionGetTicket(index);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
      {
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Confirm that the trade server accepted an operation               |
//+------------------------------------------------------------------+
bool TradeResultSucceeded()
{
   const uint retcode = g_trade.ResultRetcode();
   return retcode == TRADE_RETCODE_DONE ||
          retcode == TRADE_RETCODE_DONE_PARTIAL ||
          retcode == TRADE_RETCODE_PLACED;
}

//+------------------------------------------------------------------+
//| Close every position owned by this EA                             |
//+------------------------------------------------------------------+
bool CloseOwnPositions()
{
   bool all_closed = true;
   for(int index = PositionsTotal() - 1; index >= 0; --index)
   {
      const ulong ticket = PositionGetTicket(index);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol ||
         PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
      {
         continue;
      }

      if(!g_trade.PositionClose(ticket, (ulong)InpSlippagePoints) ||
         !TradeResultSucceeded())
      {
         PrintFormat("Position close failed: ticket=%I64u retcode=%u %s",
                     ticket, g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
         all_closed = false;
      }
   }
   return all_closed;
}

//+------------------------------------------------------------------+
//| Read only closed candles: [0] is shift 2, [1] is shift 1          |
//+------------------------------------------------------------------+
bool ReadClosedBarSignal(int &signal, double &atr_value)
{
   double fast_values[2];
   double slow_values[2];
   double atr_values[1];

   if(BarsCalculated(g_fast_ema_handle) < InpSlowEMAPeriod + 2 ||
      BarsCalculated(g_slow_ema_handle) < InpSlowEMAPeriod + 2 ||
      BarsCalculated(g_atr_handle) < InpATRPeriod + 2)
   {
      return false;
   }

   ResetLastError();
   if(CopyBuffer(g_fast_ema_handle, 0, 1, 2, fast_values) != 2 ||
      CopyBuffer(g_slow_ema_handle, 0, 1, 2, slow_values) != 2 ||
      CopyBuffer(g_atr_handle, 0, 1, 1, atr_values) != 1)
   {
      PrintFormat("Indicator CopyBuffer failed: error=%d", GetLastError());
      return false;
   }

   signal = 0;
   if(fast_values[0] <= slow_values[0] && fast_values[1] > slow_values[1])
      signal = 1;
   else if(fast_values[0] >= slow_values[0] && fast_values[1] < slow_values[1])
      signal = -1;

   atr_value = atr_values[0];
   return MathIsValidNumber(atr_value) && atr_value > 0.0;
}

//+------------------------------------------------------------------+
//| Derive decimal precision for non-power-of-ten volume steps         |
//+------------------------------------------------------------------+
int VolumeDigits(const double volume_step)
{
   double scaled_step = volume_step;
   int digits = 0;
   while(digits < 8 && MathAbs(scaled_step - MathRound(scaled_step)) > 1e-8)
   {
      scaled_step *= 10.0;
      ++digits;
   }
   return digits;
}

//+------------------------------------------------------------------+
//| Convert risk at stop distance to broker-valid volume              |
//+------------------------------------------------------------------+
double CalculateRiskVolume(const double entry_price, const double stop_price)
{
   const double stop_distance = MathAbs(entry_price - stop_price);
   const double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   const double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tick_value <= 0.0)
      tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);

   const double volume_min = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   const double volume_max = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   const double volume_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(stop_distance <= 0.0 || equity <= 0.0 || tick_size <= 0.0 ||
      tick_value <= 0.0 || volume_min <= 0.0 || volume_max < volume_min ||
      volume_step <= 0.0)
   {
      Print("Volume calculation failed: invalid symbol/account properties.");
      return 0.0;
   }

   const double risk_amount = equity * InpRiskPercent / 100.0;
   const double loss_per_lot = (stop_distance / tick_size) * tick_value;
   if(loss_per_lot <= 0.0)
      return 0.0;

   const double raw_volume = risk_amount / loss_per_lot;
   if(raw_volume < volume_min)
   {
      PrintFormat("Entry skipped: minimum lot %.4f would exceed %.2f%% risk.",
                  volume_min, InpRiskPercent);
      return 0.0;
   }

   double volume = MathMin(raw_volume, volume_max);
   volume = MathFloor((volume + 1e-12) / volume_step) * volume_step;
   return NormalizeDouble(volume, VolumeDigits(volume_step));
}

//+------------------------------------------------------------------+
//| Round a price outward to the symbol's executable tick grid         |
//+------------------------------------------------------------------+
double NormalizePriceToTick(const double price, const bool round_up)
{
   const double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   const int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   if(tick_size <= 0.0)
      return NormalizeDouble(price, digits);

   const double tick_count = price / tick_size;
   const double normalized =
      (round_up ? MathCeil(tick_count - 1e-10) : MathFloor(tick_count + 1e-10)) *
      tick_size;
   return NormalizeDouble(normalized, digits);
}

//+------------------------------------------------------------------+
//| Submit an entry with server-distance-aware stop and target         |
//+------------------------------------------------------------------+
bool OpenPosition(const int signal, const double atr_value)
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick) || tick.ask <= 0.0 || tick.bid <= 0.0)
   {
      PrintFormat("Entry skipped: no valid market tick, error=%d", GetLastError());
      return false;
   }

   const int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   const long stops_level_points = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   const double broker_min_distance = (double)stops_level_points * _Point;
   const double spread_distance = tick.ask - tick.bid;
   const double stop_distance =
      MathMax(atr_value * InpATRStopMultiplier,
              broker_min_distance + spread_distance + _Point);

   const double entry_price = signal > 0 ? tick.ask : tick.bid;
   const double stop_price = NormalizePriceToTick(
      signal > 0 ? entry_price - stop_distance : entry_price + stop_distance,
      signal < 0);
   const double target_price = NormalizePriceToTick(
      signal > 0
         ? entry_price + stop_distance * InpRiskRewardRatio
         : entry_price - stop_distance * InpRiskRewardRatio,
      signal > 0);
   const double volume = CalculateRiskVolume(entry_price, stop_price);
   if(volume <= 0.0)
      return false;

   bool submitted = false;
   if(signal > 0)
      submitted = g_trade.Buy(volume, _Symbol, 0.0, stop_price, target_price, "SafeEMA buy");
   else
      submitted = g_trade.Sell(volume, _Symbol, 0.0, stop_price, target_price, "SafeEMA sell");

   if(!submitted || !TradeResultSucceeded())
   {
      PrintFormat("Entry failed: signal=%d volume=%.4f retcode=%u %s",
                  signal, volume, g_trade.ResultRetcode(),
                  g_trade.ResultRetcodeDescription());
      return false;
   }

   PrintFormat("Entry accepted: signal=%d volume=%.4f stop=%.*f target=%.*f deal=%I64u",
               signal, volume, digits, stop_price, digits, target_price,
               g_trade.ResultDeal());
   return true;
}

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   if(!ValidateInputs())
      return INIT_PARAMETERS_INCORRECT;

   g_fast_ema_handle = iMA(_Symbol, _Period, InpFastEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   g_slow_ema_handle = iMA(_Symbol, _Period, InpSlowEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   g_atr_handle = iATR(_Symbol, _Period, InpATRPeriod);

   if(g_fast_ema_handle == INVALID_HANDLE ||
      g_slow_ema_handle == INVALID_HANDLE ||
      g_atr_handle == INVALID_HANDLE)
   {
      PrintFormat("Initialization failed: indicator handle error=%d", GetLastError());
      return INIT_FAILED;
   }

   g_trade.SetExpertMagicNumber((ulong)InpMagicNumber);
   g_trade.SetDeviationInPoints((ulong)InpSlippagePoints);
   g_trade.SetAsyncMode(false);
   if(!g_trade.SetTypeFillingBySymbol(_Symbol))
      Print("Warning: unable to configure symbol filling policy.");

   InitializeRiskState();
   PrintFormat("SafeEMACrossEA v0.1.0 initialized. Trading authorized=%s tester=%s",
               TradingAuthorized() ? "true" : "false",
               MQLInfoInteger(MQL_TESTER) ? "true" : "false");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   SaveRiskState();
   if(g_fast_ema_handle != INVALID_HANDLE)
      IndicatorRelease(g_fast_ema_handle);
   if(g_slow_ema_handle != INVALID_HANDLE)
      IndicatorRelease(g_slow_ema_handle);
   if(g_atr_handle != INVALID_HANDLE)
      IndicatorRelease(g_atr_handle);
}

//+------------------------------------------------------------------+
//| Main event loop                                                    |
//+------------------------------------------------------------------+
void OnTick()
{
   string risk_reason;
   if(RiskLimitsBreached(risk_reason))
   {
      if(!g_risk_halt_logged)
      {
         PrintFormat("Risk breaker active: %s. New entries are blocked.", risk_reason);
         g_risk_halt_logged = true;
      }
      if(TradingAuthorized() && CountOwnPositions() > 0)
         CloseOwnPositions();
      return;
   }
   g_risk_halt_logged = false;

   if(!IsNewBar())
      return;

   int signal = 0;
   double atr_value = 0.0;
   if(!ReadClosedBarSignal(signal, atr_value) || signal == 0)
      return;

   if(!TradingAuthorized())
   {
      Print("Signal ignored: trading is disabled outside Strategy Tester.");
      return;
   }

   const int own_positions = CountOwnPositions();
   if(own_positions > 0)
   {
      if(!CloseOwnPositions())
         return;
      if(CountOwnPositions() > 0)
         return;
   }

   if(!IsWithinTradingSession())
   {
      Print("Entry skipped: outside configured trading session.");
      return;
   }

   const long spread_points = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread_points < 0 || spread_points > InpMaximumSpreadPoints)
   {
      PrintFormat("Entry skipped: spread=%d points, maximum=%d.",
                  spread_points, InpMaximumSpreadPoints);
      return;
   }
   if(HasForeignPositionOnSymbol())
   {
      Print("Entry skipped: another strategy owns a position on this symbol.");
      return;
   }
   if(CountOwnPositions() >= InpMaximumPositions)
   {
      Print("Entry skipped: maximum position count reached.");
      return;
   }

   OpenPosition(signal, atr_value);
}
//+------------------------------------------------------------------+
