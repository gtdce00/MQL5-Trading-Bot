//+------------------------------------------------------------------+
//|                                             SafeMACrossEA.mq5    |
//| Safety-first EMA crossover Expert Advisor for MetaTrader 5      |
//+------------------------------------------------------------------+
#property copyright "MQL5 Trading Bot"
#property version   "1.003"
#property strict

#include <Trade/Trade.mqh>

input group "Safety"
input bool   InpAllowLiveTrading       = false;
input ulong  InpMagicNumber            = 26090501;
input double InpRiskPerTradePercent     = 0.50;
input double InpFixedVolume             = 0.0;
input int    InpMaximumPositions        = 1;
input double InpMaximumDailyLossPercent = 2.0;
input double InpMaximumDrawdownPercent  = 10.0;
input int    InpMaximumSpreadPoints     = 30;
input int    InpMaximumSlippagePoints   = 10;

input group "Signal (closed bars only)"
input int             InpFastEmaPeriod = 20;
input int             InpSlowEmaPeriod = 50;
input ENUM_TIMEFRAMES InpSignalTimeframe = PERIOD_CURRENT;

input group "Exit and session"
input int    InpAtrPeriod         = 14;
input double InpStopAtrMultiplier = 2.0;
input double InpRiskRewardRatio   = 2.0;
input int    InpSessionStartHour  = 0;
input int    InpSessionEndHour    = 24;

CTrade trade;

int      fast_ema_handle = INVALID_HANDLE;
int      slow_ema_handle = INVALID_HANDLE;
int      atr_handle      = INVALID_HANDLE;
datetime last_bar_time   = 0;
datetime tracked_day     = 0;
double   day_start_equity = 0.0;
double   peak_equity      = 0.0;
bool     daily_loss_lock_active = false;
bool     drawdown_lock_active   = false;
string   risk_state_prefix      = "";

//+------------------------------------------------------------------+
//| Return midnight for a server timestamp                           |
//+------------------------------------------------------------------+
datetime StartOfDay(const datetime value)
{
   MqlDateTime parts;
   TimeToStruct(value, parts);
   parts.hour = 0;
   parts.min  = 0;
   parts.sec  = 0;
   return StructToTime(parts);
}

//+------------------------------------------------------------------+
//| Save live/demo risk state so an EA restart cannot clear a lock   |
//+------------------------------------------------------------------+
void PersistRiskState(const bool flush_to_disk = false)
{
   if(risk_state_prefix == "")
      return;

   GlobalVariableSet(risk_state_prefix + ".Peak", peak_equity);
   GlobalVariableSet(risk_state_prefix + ".Day", (double)tracked_day);
   GlobalVariableSet(risk_state_prefix + ".DayEq", day_start_equity);
   GlobalVariableSet(risk_state_prefix + ".DLock",
                     daily_loss_lock_active ? 1.0 : 0.0);
   GlobalVariableSet(risk_state_prefix + ".MLock",
                     drawdown_lock_active ? 1.0 : 0.0);

   if(flush_to_disk)
      GlobalVariablesFlush();
}

//+------------------------------------------------------------------+
//| Load persisted risk state outside Strategy Tester                |
//+------------------------------------------------------------------+
void InitializeRiskState(const double equity)
{
   tracked_day      = StartOfDay(TimeCurrent());
   day_start_equity = equity;
   peak_equity      = equity;

   if(MQLInfoInteger(MQL_TESTER))
      return;

   const long account_login = AccountInfoInteger(ACCOUNT_LOGIN);
   if(account_login <= 0)
      return;

   risk_state_prefix =
      StringFormat("SMAC.%I64d.%I64u", account_login, InpMagicNumber);

   const string peak_key = risk_state_prefix + ".Peak";
   if(GlobalVariableCheck(peak_key))
      peak_equity = MathMax(equity, GlobalVariableGet(peak_key));

   const string day_key = risk_state_prefix + ".Day";
   const string day_equity_key = risk_state_prefix + ".DayEq";
   if(GlobalVariableCheck(day_key) &&
      GlobalVariableCheck(day_equity_key) &&
      (datetime)GlobalVariableGet(day_key) == tracked_day)
   {
      const double stored_day_equity = GlobalVariableGet(day_equity_key);
      if(stored_day_equity > 0.0)
         day_start_equity = stored_day_equity;

      const string daily_lock_key = risk_state_prefix + ".DLock";
      if(GlobalVariableCheck(daily_lock_key))
         daily_loss_lock_active =
            GlobalVariableGet(daily_lock_key) > 0.5;
   }

   const string drawdown_lock_key = risk_state_prefix + ".MLock";
   if(GlobalVariableCheck(drawdown_lock_key))
      drawdown_lock_active =
         GlobalVariableGet(drawdown_lock_key) > 0.5;

   PersistRiskState(true);
}

//+------------------------------------------------------------------+
//| Validate user-controlled safety and strategy parameters          |
//+------------------------------------------------------------------+
bool InputsAreValid()
{
   if(InpMagicNumber == 0)
   {
      Print("Invalid configuration: Magic Number must be non-zero.");
      return false;
   }
   if(InpRiskPerTradePercent <= 0.0 || InpRiskPerTradePercent > 5.0)
   {
      Print("Invalid configuration: risk per trade must be in (0, 5].");
      return false;
   }
   if(InpFixedVolume < 0.0 || InpMaximumPositions < 1)
   {
      Print("Invalid configuration: volume or maximum positions.");
      return false;
   }
   if(InpMaximumDailyLossPercent <= 0.0 ||
      InpMaximumDailyLossPercent > InpMaximumDrawdownPercent ||
      InpMaximumDrawdownPercent > 50.0)
   {
      Print("Invalid configuration: daily loss/drawdown limits.");
      return false;
   }
   if(InpRiskPerTradePercent * InpMaximumPositions >
      InpMaximumDailyLossPercent)
   {
      Print("Invalid configuration: aggregate position risk exceeds daily loss limit.");
      return false;
   }
   if(InpMaximumSpreadPoints < 0 || InpMaximumSlippagePoints < 0)
   {
      Print("Invalid configuration: spread/slippage must be non-negative.");
      return false;
   }
   if(InpFastEmaPeriod < 2 || InpSlowEmaPeriod <= InpFastEmaPeriod ||
      InpAtrPeriod < 2)
   {
      Print("Invalid configuration: EMA or ATR periods.");
      return false;
   }
   if(InpStopAtrMultiplier <= 0.0 || InpRiskRewardRatio <= 0.0)
   {
      Print("Invalid configuration: stop and reward multipliers.");
      return false;
   }
   if(InpSessionStartHour < 0 || InpSessionStartHour > 23 ||
      InpSessionEndHour < 1 || InpSessionEndHour > 24 ||
      InpSessionStartHour >= InpSessionEndHour)
   {
      Print("Invalid configuration: session must be within 00:00-24:00.");
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Initialize the Expert Advisor                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   if(!InputsAreValid())
      return INIT_PARAMETERS_INCORRECT;

   fast_ema_handle = iMA(_Symbol, InpSignalTimeframe, InpFastEmaPeriod,
                         0, MODE_EMA, PRICE_CLOSE);
   slow_ema_handle = iMA(_Symbol, InpSignalTimeframe, InpSlowEmaPeriod,
                         0, MODE_EMA, PRICE_CLOSE);
   atr_handle = iATR(_Symbol, InpSignalTimeframe, InpAtrPeriod);

   if(fast_ema_handle == INVALID_HANDLE ||
      slow_ema_handle == INVALID_HANDLE ||
      atr_handle == INVALID_HANDLE)
   {
      PrintFormat("Indicator handle creation failed. Error=%d", GetLastError());
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpMaximumSlippagePoints);
   if(!trade.SetTypeFillingBySymbol(_Symbol))
   {
      PrintFormat("Unable to select symbol filling mode. Error=%d",
                  GetLastError());
      return INIT_FAILED;
   }

   const double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   InitializeRiskState(equity);

   if(!MQLInfoInteger(MQL_TESTER) && !InpAllowLiveTrading)
      Print("SAFETY MODE: live/demo trading disabled. Strategy Tester remains enabled.");

   PrintFormat("SafeMACrossEA v1.0.3 initialized on %s, timeframe=%s, tester=%s",
               _Symbol,
               EnumToString(InpSignalTimeframe),
               MQLInfoInteger(MQL_TESTER) ? "true" : "false");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Release indicator resources                                     |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   PersistRiskState(true);

   if(fast_ema_handle != INVALID_HANDLE)
      IndicatorRelease(fast_ema_handle);
   if(slow_ema_handle != INVALID_HANDLE)
      IndicatorRelease(slow_ema_handle);
   if(atr_handle != INVALID_HANDLE)
      IndicatorRelease(atr_handle);

   PrintFormat("SafeMACrossEA deinitialized. Reason=%d", reason);
}

//+------------------------------------------------------------------+
//| True once for each newly opened signal-timeframe bar             |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   const datetime current_bar = iTime(_Symbol, InpSignalTimeframe, 0);
   if(current_bar <= 0 || current_bar == last_bar_time)
      return false;

   last_bar_time = current_bar;
   return true;
}

//+------------------------------------------------------------------+
//| Update daily-loss and account-drawdown circuit breakers          |
//+------------------------------------------------------------------+
void UpdateRiskState()
{
   const datetime today  = StartOfDay(TimeCurrent());
   const double   equity = AccountInfoDouble(ACCOUNT_EQUITY);
   bool state_changed = false;

   if(today != tracked_day)
   {
      tracked_day      = today;
      day_start_equity = equity;
      daily_loss_lock_active = false;
      state_changed = true;
      PrintFormat("Daily risk baseline reset. Equity=%.2f", equity);
   }

   if(equity > peak_equity)
   {
      peak_equity = equity;
      state_changed = true;
   }

   const double daily_loss =
      day_start_equity > 0.0
      ? 100.0 * (day_start_equity - equity) / day_start_equity
      : 0.0;
   const double drawdown =
      peak_equity > 0.0 ? 100.0 * (peak_equity - equity) / peak_equity : 0.0;

   if(!daily_loss_lock_active &&
      daily_loss >= InpMaximumDailyLossPercent)
   {
      daily_loss_lock_active = true;
      state_changed = true;
      PrintFormat("DAILY LOSS LOCK activated. DailyLoss=%.2f%%",
                  daily_loss);
   }

   if(!drawdown_lock_active &&
      drawdown >= InpMaximumDrawdownPercent)
   {
      drawdown_lock_active = true;
      state_changed = true;
      PrintFormat("DRAWDOWN LOCK activated permanently. Drawdown=%.2f%%",
                  drawdown);
   }

   if(state_changed)
      PersistRiskState(daily_loss_lock_active || drawdown_lock_active);
}

//+------------------------------------------------------------------+
//| Identify positions owned by this EA                              |
//+------------------------------------------------------------------+
bool IsManagedPosition(const ulong ticket)
{
   if(ticket == 0 || !PositionSelectByTicket(ticket))
      return false;

   return PositionGetString(POSITION_SYMBOL) == _Symbol &&
          (ulong)PositionGetInteger(POSITION_MAGIC) == InpMagicNumber;
}

//+------------------------------------------------------------------+
//| Confirm a synchronous market request reached a completed state   |
//+------------------------------------------------------------------+
bool TradeRequestCompleted()
{
   const uint retcode = trade.ResultRetcode();
   return retcode == TRADE_RETCODE_DONE ||
          retcode == TRADE_RETCODE_DONE_PARTIAL;
}

//+------------------------------------------------------------------+
//| Count positions owned by this EA                                 |
//+------------------------------------------------------------------+
int ManagedPositionCount()
{
   int count = 0;
   for(int index = PositionsTotal() - 1; index >= 0; --index)
   {
      const ulong ticket = PositionGetTicket(index);
      if(IsManagedPosition(ticket))
         ++count;
   }
   return count;
}

//+------------------------------------------------------------------+
//| Close all EA positions, used by risk circuit breakers            |
//+------------------------------------------------------------------+
bool CloseManagedPositions(const string reason)
{
   bool all_closed = true;
   for(int index = PositionsTotal() - 1; index >= 0; --index)
   {
      const ulong ticket = PositionGetTicket(index);
      if(!IsManagedPosition(ticket))
         continue;

      if(!trade.PositionClose(ticket) || !TradeRequestCompleted())
      {
         PrintFormat("Position close failed. Ticket=%I64u Retcode=%u %s",
                     ticket, trade.ResultRetcode(),
                     trade.ResultRetcodeDescription());
         all_closed = false;
      }
      else
      {
         PrintFormat("Position closed. Ticket=%I64u Reason=%s",
                     ticket, reason);
      }
   }
   return all_closed;
}

//+------------------------------------------------------------------+
//| Return +1 long crossover, -1 short crossover, or 0               |
//| CopyBuffer starts at shift 1: only completed bars are consumed.  |
//+------------------------------------------------------------------+
int ClosedBarSignal(double &atr_value)
{
   if(BarsCalculated(fast_ema_handle) < InpSlowEmaPeriod + 2 ||
      BarsCalculated(slow_ema_handle) < InpSlowEmaPeriod + 2 ||
      BarsCalculated(atr_handle) < InpAtrPeriod + 2)
   {
      Print("Indicators are not ready.");
      return 0;
   }

   double fast_values[2];
   double slow_values[2];
   double atr_values[1];
   ResetLastError();

   if(CopyBuffer(fast_ema_handle, 0, 1, 2, fast_values) != 2 ||
      CopyBuffer(slow_ema_handle, 0, 1, 2, slow_values) != 2 ||
      CopyBuffer(atr_handle, 0, 1, 1, atr_values) != 1)
   {
      PrintFormat("Indicator buffer read failed. Error=%d", GetLastError());
      return 0;
   }

   // Physical array order is oldest to newest: [shift 2, shift 1].
   const double fast_previous = fast_values[0];
   const double fast_closed   = fast_values[1];
   const double slow_previous = slow_values[0];
   const double slow_closed   = slow_values[1];
   atr_value = atr_values[0];

   if(atr_value <= 0.0)
      return 0;
   if(fast_previous <= slow_previous && fast_closed > slow_closed)
      return 1;
   if(fast_previous >= slow_previous && fast_closed < slow_closed)
      return -1;
   return 0;
}

//+------------------------------------------------------------------+
//| Check execution-hour, spread and symbol trade permissions        |
//+------------------------------------------------------------------+
bool MarketConditionsAllowEntry(const int signal, const MqlTick &tick)
{
   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);
   if(now.hour < InpSessionStartHour || now.hour >= InpSessionEndHour)
      return false;

   const double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(point <= 0.0)
      return false;

   const double spread_points = (tick.ask - tick.bid) / point;
   if(spread_points > InpMaximumSpreadPoints)
   {
      PrintFormat("Entry skipped: spread %.1f exceeds limit %d.",
                  spread_points, InpMaximumSpreadPoints);
      return false;
   }

   const ENUM_SYMBOL_TRADE_MODE mode =
      (ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE);
   if(mode == SYMBOL_TRADE_MODE_DISABLED ||
      (signal > 0 && mode == SYMBOL_TRADE_MODE_SHORTONLY) ||
      (signal < 0 && mode == SYMBOL_TRADE_MODE_LONGONLY) ||
      mode == SYMBOL_TRADE_MODE_CLOSEONLY)
   {
      PrintFormat("Entry skipped: symbol trade mode %s.",
                  EnumToString(mode));
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Normalize volume downward so requested risk is never exceeded    |
//+------------------------------------------------------------------+
double NormalizeVolumeDown(const double requested)
{
   const double minimum = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   const double maximum = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   const double step    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(minimum <= 0.0 || maximum < minimum || step <= 0.0 ||
      requested < minimum)
      return 0.0;

   const double capped = MathMin(requested, maximum);
   double normalized = MathFloor((capped + 1e-12) / step) * step;
   normalized = NormalizeDouble(normalized, 8);
   return normalized >= minimum ? normalized : 0.0;
}

//+------------------------------------------------------------------+
//| Calculate volume from stop distance and configured account risk  |
//+------------------------------------------------------------------+
double EntryVolume(const double stop_distance)
{
   const double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tick_value <= 0.0)
      tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);

   if(stop_distance <= 0.0 || tick_size <= 0.0 || tick_value <= 0.0)
   {
      Print("Volume calculation failed: invalid symbol tick properties.");
      return 0.0;
   }

   const double risk_money =
      AccountInfoDouble(ACCOUNT_EQUITY) * InpRiskPerTradePercent / 100.0;
   const double money_per_lot = (stop_distance / tick_size) * tick_value;
   if(risk_money <= 0.0 || money_per_lot <= 0.0)
      return 0.0;

   const double risk_limited_volume = risk_money / money_per_lot;
   const double requested =
      InpFixedVolume > 0.0
      ? MathMin(InpFixedVolume, risk_limited_volume)
      : risk_limited_volume;
   return NormalizeVolumeDown(requested);
}

//+------------------------------------------------------------------+
//| Ensure stop distances satisfy broker constraints                 |
//+------------------------------------------------------------------+
double SafeStopDistance(const double atr_value, const double spread)
{
   const double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   const long stops_level = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   const double broker_minimum =
      (double)(stops_level + 1) * point + MathMax(spread, 0.0);
   return MathMax(atr_value * InpStopAtrMultiplier, broker_minimum);
}

//+------------------------------------------------------------------+
//| Close positions opposed to a new crossover                       |
//+------------------------------------------------------------------+
bool CloseOppositePositions(const int signal)
{
   bool all_closed = true;
   for(int index = PositionsTotal() - 1; index >= 0; --index)
   {
      const ulong ticket = PositionGetTicket(index);
      if(!IsManagedPosition(ticket))
         continue;

      const ENUM_POSITION_TYPE type =
         (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      const bool opposite =
         (signal > 0 && type == POSITION_TYPE_SELL) ||
         (signal < 0 && type == POSITION_TYPE_BUY);
      if(!opposite)
         continue;

      if(!trade.PositionClose(ticket) || !TradeRequestCompleted())
      {
         PrintFormat("Opposite position close failed. Ticket=%I64u Retcode=%u %s",
                     ticket, trade.ResultRetcode(),
                     trade.ResultRetcodeDescription());
         all_closed = false;
      }
   }
   return all_closed;
}

//+------------------------------------------------------------------+
//| Open one fully protected market position                         |
//+------------------------------------------------------------------+
void OpenPosition(const int signal, const double atr_value,
                  const MqlTick &tick)
{
   if(ManagedPositionCount() >= InpMaximumPositions)
      return;

   const double stop_distance = SafeStopDistance(atr_value,
                                                 tick.ask - tick.bid);
   const double volume = EntryVolume(stop_distance);
   if(volume <= 0.0)
   {
      Print("Entry skipped: calculated volume is below the symbol minimum.");
      return;
   }

   const int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   const double entry = signal > 0 ? tick.ask : tick.bid;
   const double stop_loss = NormalizeDouble(
      signal > 0 ? entry - stop_distance : entry + stop_distance, digits);
   const double take_profit = NormalizeDouble(
      signal > 0
      ? entry + stop_distance * InpRiskRewardRatio
      : entry - stop_distance * InpRiskRewardRatio,
      digits);

   double required_margin = 0.0;
   const ENUM_ORDER_TYPE order_type =
      signal > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!OrderCalcMargin(order_type, _Symbol, volume, entry, required_margin) ||
      required_margin > AccountInfoDouble(ACCOUNT_MARGIN_FREE))
   {
      PrintFormat("Entry skipped: insufficient margin or calculation failure. Error=%d",
                  GetLastError());
      return;
   }

   const bool sent =
      signal > 0
      ? trade.Buy(volume, _Symbol, 0.0, stop_loss, take_profit,
                  "SafeMACross long")
      : trade.Sell(volume, _Symbol, 0.0, stop_loss, take_profit,
                   "SafeMACross short");

   if(!sent || !TradeRequestCompleted())
   {
      PrintFormat("Trade request failed. Retcode=%u %s",
                  trade.ResultRetcode(), trade.ResultRetcodeDescription());
      return;
   }

   PrintFormat("Entry accepted. Signal=%d Volume=%.8f SL=%.*f TP=%.*f Deal=%I64u",
               signal, volume, digits, stop_loss, digits, take_profit,
               trade.ResultDeal());
}

//+------------------------------------------------------------------+
//| Tick handler                                                     |
//+------------------------------------------------------------------+
void OnTick()
{
   UpdateRiskState();
   if(daily_loss_lock_active || drawdown_lock_active)
   {
      CloseManagedPositions(drawdown_lock_active
                            ? "maximum drawdown circuit breaker"
                            : "daily loss circuit breaker");
      return;
   }

   if(!MQLInfoInteger(MQL_TESTER) && !InpAllowLiveTrading)
      return;

   if(!IsNewBar())
      return;

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick) || tick.ask <= 0.0 || tick.bid <= 0.0)
   {
      PrintFormat("Tick read failed. Error=%d", GetLastError());
      return;
   }

   double atr_value = 0.0;
   const int signal = ClosedBarSignal(atr_value);
   if(signal == 0)
      return;

   if(!CloseOppositePositions(signal))
      return;
   if(!MarketConditionsAllowEntry(signal, tick))
      return;

   OpenPosition(signal, atr_value, tick);
}
//+------------------------------------------------------------------+
