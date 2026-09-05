//+------------------------------------------------------------------+
//|                                             SafeMACrossEA.mq5    |
//| Safety-first EMA crossover Expert Advisor for MetaTrader 5      |
//+------------------------------------------------------------------+
#property copyright "MQL5 Trading Bot"
#property version   "1.006"
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
input double InpRiskCostBufferPercent   = 10.0;

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
bool     persistence_failure_lock_active = false;
string   risk_state_prefix      = "";
string   entry_lock_key         = "";
double   entry_lock_owner_token = 0.0;
bool     live_instance_lock_acquired = false;

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
//| Stable server hash keeps terminal-global state account-specific  |
//+------------------------------------------------------------------+
uint ServerHash()
{
   const string server = AccountInfoString(ACCOUNT_SERVER);
   uint hash = 2166136261;
   for(int index = 0; index < StringLen(server); ++index)
   {
      hash ^= (uint)StringGetCharacter(server, index);
      hash *= 16777619;
   }
   return hash;
}

//+------------------------------------------------------------------+
//| Checked write for terminal-global risk state                     |
//+------------------------------------------------------------------+
bool StoreRiskValue(const string key, const double value)
{
   ResetLastError();
   if(GlobalVariableSet(key, value) != 0)
      return true;

   PrintFormat("Risk-state persistence failed. Key=%s Error=%d",
               key, GetLastError());
   persistence_failure_lock_active = true;
   return false;
}

//+------------------------------------------------------------------+
//| Raise a persisted monotonic value without lowering a newer value |
//+------------------------------------------------------------------+
bool StoreRiskMaximum(const string key, const double candidate)
{
   if(!GlobalVariableCheck(key) && !StoreRiskValue(key, candidate))
      return false;

   for(int attempt = 0; attempt < 3; ++attempt)
   {
      const double current = GlobalVariableGet(key);
      if(current >= candidate)
         return true;

      ResetLastError();
      if(GlobalVariableSetOnCondition(key, candidate, current))
         return true;
   }

   PrintFormat("Monotonic risk-state write failed. Key=%s Error=%d",
               key, GetLastError());
   persistence_failure_lock_active = true;
   return false;
}

//+------------------------------------------------------------------+
//| Save state monotonically so a stale chart cannot lower a lock    |
//+------------------------------------------------------------------+
bool PersistRiskState(const bool flush_to_disk = false)
{
   if(risk_state_prefix == "")
      return true;

   bool success = true;
   const string peak_key = risk_state_prefix + ".Peak";
   if(GlobalVariableCheck(peak_key))
      peak_equity = MathMax(peak_equity, GlobalVariableGet(peak_key));
   success = StoreRiskMaximum(peak_key, peak_equity) && success;

   const string day_key = risk_state_prefix + ".Day";
   const string day_equity_key = risk_state_prefix + ".DayEq";
   const string daily_lock_key = risk_state_prefix + ".DLock";
   const string ready_key = risk_state_prefix + ".Ready";
   const datetime stored_day =
      GlobalVariableCheck(day_key)
      ? (datetime)GlobalVariableGet(day_key)
      : 0;

   if(stored_day > tracked_day)
   {
      tracked_day = stored_day;
      if(GlobalVariableCheck(day_equity_key))
         day_start_equity = GlobalVariableGet(day_equity_key);
      if(GlobalVariableCheck(daily_lock_key))
         daily_loss_lock_active =
            GlobalVariableGet(daily_lock_key) > 0.5;
   }
   else if(stored_day == tracked_day && stored_day > 0)
   {
      if(GlobalVariableCheck(day_equity_key))
      {
         const double stored_equity = GlobalVariableGet(day_equity_key);
         if(stored_equity > 0.0)
            day_start_equity = MathMax(day_start_equity, stored_equity);
      }
      if(GlobalVariableCheck(daily_lock_key) &&
         GlobalVariableGet(daily_lock_key) > 0.5)
         daily_loss_lock_active = true;
   }
   else
   {
      // Publish the day marker last so readers never pair a new day
      // with the previous day's baseline.
      success = StoreRiskValue(day_equity_key, day_start_equity) && success;
      success = StoreRiskValue(daily_lock_key,
                               daily_loss_lock_active ? 1.0 : 0.0) && success;
      success = StoreRiskValue(day_key, (double)tracked_day) && success;
   }

   success = StoreRiskMaximum(day_equity_key, day_start_equity) && success;
   if(daily_loss_lock_active)
      success = StoreRiskMaximum(daily_lock_key, 1.0) && success;
   else if(!GlobalVariableCheck(daily_lock_key))
      success = StoreRiskValue(daily_lock_key, 0.0) && success;

   const string drawdown_lock_key = risk_state_prefix + ".MLock";
   if(GlobalVariableCheck(drawdown_lock_key) &&
      GlobalVariableGet(drawdown_lock_key) > 0.5)
      drawdown_lock_active = true;
   if(drawdown_lock_active)
      success = StoreRiskMaximum(drawdown_lock_key, 1.0) && success;
   else if(!GlobalVariableCheck(drawdown_lock_key))
      success = StoreRiskValue(drawdown_lock_key, 0.0) && success;

   if(success)
      success = StoreRiskValue(ready_key, (double)tracked_day) && success;
   else
      StoreRiskValue(ready_key, 0.0);

   if(flush_to_disk)
      GlobalVariablesFlush();
   return success;
}

//+------------------------------------------------------------------+
//| Load persisted risk state outside Strategy Tester                |
//+------------------------------------------------------------------+
bool InitializeRiskState(const double equity)
{
   tracked_day      = StartOfDay(TimeCurrent());
   day_start_equity = equity;
   peak_equity      = equity;

   if(MQLInfoInteger(MQL_TESTER))
      return true;

   const long account_login = AccountInfoInteger(ACCOUNT_LOGIN);
   if(account_login <= 0 || AccountInfoString(ACCOUNT_SERVER) == "")
   {
      Print("Risk-state persistence unavailable: account identity is incomplete.");
      persistence_failure_lock_active = true;
      return false;
   }

   risk_state_prefix =
      StringFormat("SMAC.%08X.%I64d.%I64u",
                   ServerHash(), account_login, InpMagicNumber);
   entry_lock_key = risk_state_prefix + ".Entry";
   entry_lock_owner_token = MathAbs((double)ChartID());

   const string peak_key = risk_state_prefix + ".Peak";
   if(GlobalVariableCheck(peak_key))
      peak_equity = MathMax(equity, GlobalVariableGet(peak_key));

   const string day_key = risk_state_prefix + ".Day";
   const string day_equity_key = risk_state_prefix + ".DayEq";
   const string daily_lock_key = risk_state_prefix + ".DLock";
   const string drawdown_lock_key = risk_state_prefix + ".MLock";
   const string ready_key = risk_state_prefix + ".Ready";
   const bool any_persisted_state =
      GlobalVariableCheck(day_key) ||
      GlobalVariableCheck(day_equity_key) ||
      GlobalVariableCheck(daily_lock_key) ||
      GlobalVariableCheck(drawdown_lock_key) ||
      GlobalVariableCheck(peak_key) ||
      GlobalVariableCheck(ready_key);
   const bool valid_daily_state =
      GlobalVariableCheck(day_key) &&
      GlobalVariableCheck(day_equity_key) &&
      GlobalVariableCheck(daily_lock_key) &&
      GlobalVariableCheck(drawdown_lock_key) &&
      GlobalVariableCheck(peak_key) &&
      GlobalVariableCheck(ready_key) &&
      (datetime)GlobalVariableGet(day_key) == tracked_day &&
      (datetime)GlobalVariableGet(ready_key) == tracked_day &&
      GlobalVariableGet(day_equity_key) > 0.0;
   if(valid_daily_state)
   {
      const double stored_day_equity = GlobalVariableGet(day_equity_key);
      if(stored_day_equity > 0.0)
         day_start_equity = stored_day_equity;

      daily_loss_lock_active =
         GlobalVariableGet(daily_lock_key) > 0.5;
   }
   else
   {
      // A safe midnight-equity baseline cannot be reconstructed reliably
      // after a mid-session first attachment. Lock until the next day.
      daily_loss_lock_active = true;
      if(any_persisted_state)
      {
         drawdown_lock_active = true;
         Print("DRAWDOWN LOCK activated: persisted risk state is incomplete.");
      }
      else
      {
         Print("DAILY LOSS LOCK activated: no trustworthy current-day baseline.");
      }
   }

   if(GlobalVariableCheck(drawdown_lock_key) &&
      GlobalVariableGet(drawdown_lock_key) > 0.5)
      drawdown_lock_active = true;

   return PersistRiskState(true);
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
   if(InpRiskCostBufferPercent < 0.0 ||
      InpRiskCostBufferPercent > 100.0)
   {
      Print("Invalid configuration: risk cost buffer must be in [0, 100].");
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

   if(!MQLInfoInteger(MQL_TESTER) && InpAllowLiveTrading)
   {
      const ENUM_ACCOUNT_MARGIN_MODE margin_mode =
         (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
      if(margin_mode != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      {
         Print("Live/demo execution rejected: only hedging accounts provide safe position ownership.");
         return INIT_FAILED;
      }

      const ENUM_SYMBOL_TRADE_EXECUTION execution_mode =
         (ENUM_SYMBOL_TRADE_EXECUTION)SymbolInfoInteger(
            _Symbol, SYMBOL_TRADE_EXEMODE);
      if(execution_mode == SYMBOL_TRADE_EXECUTION_EXCHANGE)
      {
         Print("Live/demo execution rejected: exchange pending fills are unsupported.");
         return INIT_FAILED;
      }
   }

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
   if(!InitializeRiskState(equity) && InpAllowLiveTrading)
      return INIT_FAILED;

   if(InpAllowLiveTrading && !AcquireLiveInstanceLock())
   {
      Print("Live/demo execution rejected: account/magic instance lock is busy.");
      return INIT_FAILED;
   }

   if(!MQLInfoInteger(MQL_TESTER) && !EventSetTimer(1))
   {
      PrintFormat("Risk timer initialization failed. Error=%d", GetLastError());
      ReleaseLiveInstanceLock();
      if(InpAllowLiveTrading)
         return INIT_FAILED;
   }

   if(!MQLInfoInteger(MQL_TESTER) && !InpAllowLiveTrading)
      Print("SAFETY MODE: live/demo trading disabled. Strategy Tester remains enabled.");

   PrintFormat("SafeMACrossEA v1.0.6 initialized on %s, timeframe=%s, tester=%s",
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
   EventKillTimer();
   ReleaseLiveInstanceLock();
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
//| Keep account risk baselines current even when this symbol is idle|
//+------------------------------------------------------------------+
void OnTimer()
{
   if(MQLInfoInteger(MQL_TESTER))
      return;

   UpdateRiskState();
   if(!InpAllowLiveTrading || !LiveInstanceOwnershipValid())
      return;

   if(daily_loss_lock_active || drawdown_lock_active ||
      persistence_failure_lock_active)
   {
      const string reason =
         persistence_failure_lock_active
         ? "risk-state persistence failure"
         : (drawdown_lock_active
            ? "maximum drawdown circuit breaker"
            : "daily loss circuit breaker");
      CloseManagedPositions(reason);
   }
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
//| Merge monotonic state written by another account/magic instance  |
//+------------------------------------------------------------------+
void SynchronizeRiskState()
{
   if(risk_state_prefix == "")
      return;

   const string peak_key = risk_state_prefix + ".Peak";
   if(GlobalVariableCheck(peak_key))
      peak_equity = MathMax(peak_equity, GlobalVariableGet(peak_key));

   const string drawdown_lock_key = risk_state_prefix + ".MLock";
   if(GlobalVariableCheck(drawdown_lock_key) &&
      GlobalVariableGet(drawdown_lock_key) > 0.5)
      drawdown_lock_active = true;

   const string day_key = risk_state_prefix + ".Day";
   const string day_equity_key = risk_state_prefix + ".DayEq";
   const string daily_lock_key = risk_state_prefix + ".DLock";
   const string ready_key = risk_state_prefix + ".Ready";
   if(!GlobalVariableCheck(day_key) ||
      !GlobalVariableCheck(day_equity_key) ||
      !GlobalVariableCheck(daily_lock_key) ||
      !GlobalVariableCheck(ready_key))
   {
      persistence_failure_lock_active = true;
      return;
   }

   const datetime stored_day = (datetime)GlobalVariableGet(day_key);
   if(stored_day != StartOfDay(TimeCurrent()))
      return;
   if((datetime)GlobalVariableGet(ready_key) != stored_day)
   {
      persistence_failure_lock_active = true;
      return;
   }

   const bool adopting_new_day = stored_day > tracked_day;
   tracked_day = stored_day;
   const double stored_equity = GlobalVariableGet(day_equity_key);
   if(stored_equity <= 0.0)
   {
      persistence_failure_lock_active = true;
      return;
   }
   day_start_equity =
      adopting_new_day
      ? stored_equity
      : MathMax(day_start_equity, stored_equity);

   const bool stored_daily_lock =
      GlobalVariableGet(daily_lock_key) > 0.5;
   daily_loss_lock_active =
      adopting_new_day
      ? stored_daily_lock
      : (daily_loss_lock_active || stored_daily_lock);
}

//+------------------------------------------------------------------+
//| Update daily-loss and account-drawdown circuit breakers          |
//+------------------------------------------------------------------+
void UpdateRiskState()
{
   SynchronizeRiskState();

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
//| Identify account positions owned by this magic number            |
//+------------------------------------------------------------------+
bool IsMagicPosition(const ulong ticket)
{
   if(ticket == 0 || !PositionSelectByTicket(ticket))
      return false;

   return (ulong)PositionGetInteger(POSITION_MAGIC) == InpMagicNumber;
}

//+------------------------------------------------------------------+
//| Identify this EA's positions for the current chart symbol        |
//+------------------------------------------------------------------+
bool IsManagedSymbolPosition(const ulong ticket)
{
   return IsMagicPosition(ticket) &&
          PositionGetString(POSITION_SYMBOL) == _Symbol;
}

//+------------------------------------------------------------------+
//| Confirm a synchronous market request reached a completed state   |
//+------------------------------------------------------------------+
bool TradeRequestCompleted()
{
   const uint retcode = trade.ResultRetcode();
   return retcode == TRADE_RETCODE_DONE;
}

//+------------------------------------------------------------------+
//| Count positions account-wide for this magic number               |
//+------------------------------------------------------------------+
int ManagedPositionCount()
{
   int count = 0;
   for(int index = PositionsTotal() - 1; index >= 0; --index)
   {
      const ulong ticket = PositionGetTicket(index);
      if(IsMagicPosition(ticket))
         ++count;
   }
   return count;
}

//+------------------------------------------------------------------+
//| Detect positions on this symbol that belong to another owner     |
//+------------------------------------------------------------------+
bool HasForeignSymbolPosition()
{
   for(int index = PositionsTotal() - 1; index >= 0; --index)
   {
      const ulong ticket = PositionGetTicket(index);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         (ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Acquire one fail-closed live instance per server/account/magic   |
//+------------------------------------------------------------------+
bool AcquireLiveInstanceLock()
{
   if(MQLInfoInteger(MQL_TESTER) || !InpAllowLiveTrading)
      return true;
   if(entry_lock_key == "" || entry_lock_owner_token <= 0.0)
      return false;

   ResetLastError();
   if(!GlobalVariableCheck(entry_lock_key) &&
      !GlobalVariableTemp(entry_lock_key))
   {
      PrintFormat("Instance lock creation failed. Error=%d", GetLastError());
      return false;
   }

   ResetLastError();
   live_instance_lock_acquired =
      GlobalVariableSetOnCondition(entry_lock_key,
                                   entry_lock_owner_token, 0.0);
   if(!live_instance_lock_acquired)
      PrintFormat("Instance lock acquisition failed. Error=%d", GetLastError());
   return live_instance_lock_acquired;
}

//+------------------------------------------------------------------+
//| Confirm this EA still owns the fail-closed live instance lock    |
//+------------------------------------------------------------------+
bool LiveInstanceOwnershipValid()
{
   if(MQLInfoInteger(MQL_TESTER))
      return true;
   return live_instance_lock_acquired &&
          GlobalVariableCheck(entry_lock_key) &&
          GlobalVariableGet(entry_lock_key) == entry_lock_owner_token;
}

//+------------------------------------------------------------------+
//| Release only the live instance lock owned by this EA             |
//+------------------------------------------------------------------+
void ReleaseLiveInstanceLock()
{
   if(!live_instance_lock_acquired || entry_lock_key == "" ||
      entry_lock_owner_token <= 0.0)
      return;

   ResetLastError();
   if(!GlobalVariableSetOnCondition(entry_lock_key, 0.0,
                                    entry_lock_owner_token))
   {
      PrintFormat("Entry lock release skipped: ownership changed. Error=%d",
                  GetLastError());
   }
   live_instance_lock_acquired = false;
}

//+------------------------------------------------------------------+
//| Close all magic-owned account positions for a risk lock          |
//+------------------------------------------------------------------+
bool CloseManagedPositions(const string reason)
{
   bool all_closed = true;
   for(int index = PositionsTotal() - 1; index >= 0; --index)
   {
      const ulong ticket = PositionGetTicket(index);
      if(!IsMagicPosition(ticket))
         continue;

      const bool sent = trade.PositionClose(ticket);
      const bool fully_closed =
         sent && TradeRequestCompleted() && !PositionSelectByTicket(ticket);
      if(!fully_closed)
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
//| Round a protective price outward to the symbol's tick grid       |
//+------------------------------------------------------------------+
double NormalizeProtectivePrice(const double price, const bool round_up)
{
   const double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   const int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   if(price <= 0.0 || tick_size <= 0.0)
      return 0.0;

   const double ticks = price / tick_size;
   const double rounded_ticks =
      round_up ? MathCeil(ticks - 1e-12) : MathFloor(ticks + 1e-12);
   return NormalizeDouble(rounded_ticks * tick_size, digits);
}

//+------------------------------------------------------------------+
//| Calculate volume from broker profit at the actual stop price     |
//+------------------------------------------------------------------+
double EntryVolume(const ENUM_ORDER_TYPE order_type,
                   const double entry, const double stop_loss)
{
   const double minimum = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   const double maximum = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(entry <= 0.0 || stop_loss <= 0.0 ||
      minimum <= 0.0 || maximum < minimum)
   {
      Print("Volume calculation failed: invalid price or volume properties.");
      return 0.0;
   }

   const double reference_volume =
      MathMax(minimum, MathMin(1.0, maximum));
   double stop_profit = 0.0;
   ResetLastError();
   if(!OrderCalcProfit(order_type, _Symbol, reference_volume,
                       entry, stop_loss, stop_profit) ||
      stop_profit >= 0.0)
   {
      PrintFormat("Volume calculation failed at stop price. Error=%d",
                  GetLastError());
      return 0.0;
   }

   const double risk_money =
      AccountInfoDouble(ACCOUNT_EQUITY) * InpRiskPerTradePercent / 100.0;
   const double money_per_lot = MathAbs(stop_profit) / reference_volume;
   const double buffered_money_per_lot =
      money_per_lot * (1.0 + InpRiskCostBufferPercent / 100.0);
   if(risk_money <= 0.0 || buffered_money_per_lot <= 0.0)
      return 0.0;

   const double risk_limited_volume = risk_money / buffered_money_per_lot;
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
      if(!IsManagedSymbolPosition(ticket))
         continue;

      const ENUM_POSITION_TYPE type =
         (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      const bool opposite =
         (signal > 0 && type == POSITION_TYPE_SELL) ||
         (signal < 0 && type == POSITION_TYPE_BUY);
      if(!opposite)
         continue;

      const bool sent = trade.PositionClose(ticket);
      const bool fully_closed =
         sent && TradeRequestCompleted() && !PositionSelectByTicket(ticket);
      if(!fully_closed)
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
void OpenPositionLocked(const int signal, const double atr_value,
                        const MqlTick &tick)
{
   if(ManagedPositionCount() >= InpMaximumPositions)
   {
      PrintFormat("Entry skipped: account-wide magic position limit %d reached.",
                  InpMaximumPositions);
      return;
   }

   if(HasForeignSymbolPosition())
   {
      Print("Entry skipped: current symbol has a foreign or manual position.");
      return;
   }

   const double stop_distance = SafeStopDistance(atr_value,
                                                 tick.ask - tick.bid);
   const int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   const double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   const double entry = signal > 0 ? tick.ask : tick.bid;
   const ENUM_ORDER_TYPE order_type =
      signal > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   const double stop_loss = NormalizeProtectivePrice(
      signal > 0 ? entry - stop_distance : entry + stop_distance,
      signal < 0);
   const double take_profit = NormalizeProtectivePrice(
      signal > 0
      ? entry + stop_distance * InpRiskRewardRatio
      : entry - stop_distance * InpRiskRewardRatio,
      signal > 0);
   if(stop_loss <= 0.0 || take_profit <= 0.0)
   {
      Print("Entry skipped: protective prices cannot be normalized.");
      return;
   }

   const double slippage_distance =
      MathMax(0, InpMaximumSlippagePoints) * point;
   const double risk_entry =
      signal > 0 ? entry + slippage_distance : entry - slippage_distance;
   const double volume = EntryVolume(order_type, risk_entry, stop_loss);
   if(volume <= 0.0)
   {
      Print("Entry skipped: calculated volume is below the symbol minimum.");
      return;
   }

   double required_margin = 0.0;
   if(!OrderCalcMargin(order_type, _Symbol, volume, entry, required_margin) ||
      required_margin > AccountInfoDouble(ACCOUNT_MARGIN_FREE))
   {
      PrintFormat("Entry skipped: insufficient margin or calculation failure. Error=%d",
                  GetLastError());
      return;
   }

   const bool sent =
      signal > 0
      ? trade.Buy(volume, _Symbol, entry, stop_loss, take_profit,
                  "SafeMACross long")
      : trade.Sell(volume, _Symbol, entry, stop_loss, take_profit,
                   "SafeMACross short");

   const uint retcode = trade.ResultRetcode();
   const bool accepted =
      retcode == TRADE_RETCODE_DONE ||
      retcode == TRADE_RETCODE_DONE_PARTIAL;
   if(!sent || !accepted)
   {
      PrintFormat("Trade request failed. Retcode=%u %s",
                  retcode, trade.ResultRetcodeDescription());
      return;
   }

   PrintFormat("Entry accepted. Signal=%d Volume=%.8f SL=%.*f TP=%.*f Deal=%I64u Retcode=%u",
               signal, volume, digits, stop_loss, digits, take_profit,
               trade.ResultDeal(), retcode);
}

//+------------------------------------------------------------------+
//| Open one position while holding the account/magic entry lock     |
//+------------------------------------------------------------------+
void OpenPosition(const int signal, const double atr_value,
                  const MqlTick &tick)
{
   if(!LiveInstanceOwnershipValid())
   {
      Print("Entry skipped: live instance ownership is not valid.");
      return;
   }

   UpdateRiskState();
   if(daily_loss_lock_active || drawdown_lock_active ||
      persistence_failure_lock_active)
   {
      Print("Entry skipped: risk lock activated during signal processing.");
      return;
   }

   OpenPositionLocked(signal, atr_value, tick);
}

//+------------------------------------------------------------------+
//| Tick handler                                                     |
//+------------------------------------------------------------------+
void OnTick()
{
   UpdateRiskState();

   // This gate precedes every trade method, including protective closes.
   // With the default false setting the EA observes risk state only.
   if(!MQLInfoInteger(MQL_TESTER) && !InpAllowLiveTrading)
      return;

   if(daily_loss_lock_active || drawdown_lock_active ||
      persistence_failure_lock_active)
   {
      const string reason =
         persistence_failure_lock_active
         ? "risk-state persistence failure"
         : (drawdown_lock_active
            ? "maximum drawdown circuit breaker"
            : "daily loss circuit breaker");
      CloseManagedPositions(reason);
      return;
   }

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
