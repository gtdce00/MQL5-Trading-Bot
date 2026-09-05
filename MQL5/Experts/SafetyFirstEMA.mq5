#property strict
#property copyright "2026 MQL5 Trading Bot contributors"
#property link      "https://github.com/gtdce00/MQL5-Trading-Bot"
#property version   "0.100"
#property description "Safety-first EMA crossover EA for controlled testing"

#include <Trade/Trade.mqh>

const string EA_VERSION = "0.1.0";

input group "Trading safety"
input bool   InpEnableLiveTrading        = false;
input ulong  InpMagicNumber              = 417001;
input double InpRiskPercent              = 0.50;
input double InpRiskCostBufferPercent    = 10.00;
input double InpMaxDailyLossPercent      = 2.00;
input double InpMaxEquityDrawdownPercent = 10.00;
input int    InpMaxPositions             = 1;
input double InpMaxSpreadPoints          = 30.0;
input int    InpMaxSlippagePoints        = 10;

input group "Trading session (server time; equal hours mean all day)"
input int InpSessionStartHour = 0;
input int InpSessionEndHour   = 0;

input group "Signal and exits"
input int    InpFastEmaPeriod = 20;
input int    InpSlowEmaPeriod = 50;
input int    InpAtrPeriod     = 14;
input double InpAtrStopMultiple = 2.0;
input double InpRewardRiskRatio = 2.0;

CTrade trade;

int      fast_ema_handle         = INVALID_HANDLE;
int      slow_ema_handle         = INVALID_HANDLE;
int      atr_handle              = INVALID_HANDLE;
datetime last_bar_time           = 0;
double   peak_equity             = 0.0;
double   day_start_equity        = 0.0;
int      tracked_day_key         = -1;
bool     daily_loss_locked       = false;
bool     equity_drawdown_locked  = false;
bool     exit_retry_pending      = false;
int      risk_state_lock_handle  = INVALID_HANDLE;

bool IsTester()
{
   return (MQLInfoInteger(MQL_TESTER) != 0);
}

bool AcquireRiskStateLock()
{
   if(IsTester())
      return true;

   const string lock_file =
      StringFormat("SafetyFirstEMA-%u.lock", RiskStateIdentityHash());
   ResetLastError();
   risk_state_lock_handle =
      FileOpen(lock_file, FILE_READ | FILE_WRITE | FILE_BIN | FILE_COMMON);
   if(risk_state_lock_handle == INVALID_HANDLE)
   {
      PrintFormat("Initialization blocked: another account-wide EA instance may be active. Error=%d",
                  GetLastError());
      return false;
   }

   return true;
}

int CurrentDayKey()
{
   MqlDateTime parts;
   if(!TimeToStruct(TimeCurrent(), parts))
      return -1;

   return parts.year * 1000 + parts.day_of_year;
}

datetime StartOfCurrentDay()
{
   MqlDateTime parts;
   if(!TimeToStruct(TimeCurrent(), parts))
      return 0;

   parts.hour = 0;
   parts.min  = 0;
   parts.sec  = 0;
   return StructToTime(parts);
}

bool ValidateInputs()
{
   if(InpMagicNumber == 0)
   {
      Print("Invalid configuration: InpMagicNumber must be non-zero.");
      return false;
   }
   if(InpRiskPercent <= 0.0 || InpRiskPercent > 5.0)
   {
      Print("Invalid configuration: InpRiskPercent must be in (0, 5].");
      return false;
   }
   if(InpRiskCostBufferPercent < 0.0 || InpRiskCostBufferPercent > 50.0)
   {
      Print("Invalid configuration: InpRiskCostBufferPercent must be in [0, 50].");
      return false;
   }
   if(InpMaxDailyLossPercent <= 0.0 || InpMaxDailyLossPercent > 20.0)
   {
      Print("Invalid configuration: InpMaxDailyLossPercent must be in (0, 20].");
      return false;
   }
   if(InpMaxEquityDrawdownPercent <= 0.0 || InpMaxEquityDrawdownPercent > 50.0)
   {
      Print("Invalid configuration: InpMaxEquityDrawdownPercent must be in (0, 50].");
      return false;
   }
   if(InpMaxPositions != 1)
   {
      Print("Invalid configuration: v0.1.0 requires InpMaxPositions=1.");
      return false;
   }
   if(InpMaxSpreadPoints <= 0.0 || InpMaxSlippagePoints < 0)
   {
      Print("Invalid configuration: spread and slippage controls must be non-negative.");
      return false;
   }
   if(InpSessionStartHour < 0 || InpSessionStartHour > 23 ||
      InpSessionEndHour < 0 || InpSessionEndHour > 23)
   {
      Print("Invalid configuration: session hours must be in [0, 23].");
      return false;
   }
   if(InpFastEmaPeriod < 2 || InpSlowEmaPeriod <= InpFastEmaPeriod)
   {
      Print("Invalid configuration: EMA periods require 2 <= fast < slow.");
      return false;
   }
   if(InpAtrPeriod < 2 || InpAtrStopMultiple <= 0.0 || InpRewardRiskRatio <= 0.0)
   {
      Print("Invalid configuration: ATR and reward/risk values must be positive.");
      return false;
   }

   return true;
}

uint RiskStateIdentityHash()
{
   const long account_login = AccountInfoInteger(ACCOUNT_LOGIN);
   const string account_server = AccountInfoString(ACCOUNT_SERVER);
   const string identity =
      StringFormat("%I64d|%s", account_login, account_server);
   uint hash = 2166136261;
   const int length = StringLen(identity);
   for(int index = 0; index < length; index++)
   {
      hash ^= (uint)StringGetCharacter(identity, index);
      hash *= 16777619;
   }
   return hash;
}

string RiskStateKey(const string field)
{
   return StringFormat("SFEA.%s.%u", field, RiskStateIdentityHash());
}

string DailyRiskLockKey(const int day_key)
{
   return RiskStateKey(StringFormat("dl%d", day_key));
}

string DailyEquityKey(const int day_key)
{
   return RiskStateKey(StringFormat("de%d", day_key));
}

bool PersistMaximum(const string key, const double value)
{
   if(value <= 0.0)
      return false;

   for(int attempt = 0; attempt < 8; attempt++)
   {
      if(!GlobalVariableCheck(key))
      {
         if(GlobalVariableSet(key, 0.0) == 0)
            return false;
      }

      double stored_value = 0.0;
      if(!GlobalVariableGet(key, stored_value))
         return false;
      if(stored_value >= value)
         return true;
      if(GlobalVariableSetOnCondition(key, value, stored_value))
         return true;
   }

   return false;
}

bool ReadPersistentValue(const string key, double &value)
{
   ResetLastError();
   if(GlobalVariableGet(key, value))
      return true;

   daily_loss_locked = true;
   equity_drawdown_locked = true;
   PrintFormat("Risk-state read failed; trading locked. Key=%s Error=%d",
               key, GetLastError());
   return false;
}

bool PersistRiskState()
{
   if(IsTester())
      return true;

   ResetLastError();
   bool saved = true;
   if(equity_drawdown_locked &&
      GlobalVariableSet(RiskStateKey("ddlock"), 1.0) == 0)
      saved = false;
   if(daily_loss_locked &&
      GlobalVariableSet(DailyRiskLockKey(tracked_day_key), 1.0) == 0)
      saved = false;
   if(!PersistMaximum(DailyEquityKey(tracked_day_key), day_start_equity))
      saved = false;
   if(!PersistMaximum(RiskStateKey("peak"), peak_equity))
      saved = false;

   const int persistence_error = GetLastError();
   GlobalVariablesFlush();
   if(!saved)
      PrintFormat("Risk-state persistence failed; trading will lock. Error=%d",
                  persistence_error);
   return saved;
}

void SynchronizePersistentRiskState()
{
   if(IsTester())
      return;

   const string peak_key = RiskStateKey("peak");
   if(GlobalVariableCheck(peak_key))
   {
      double stored_peak = 0.0;
      if(!ReadPersistentValue(peak_key, stored_peak))
         return;
      peak_equity = MathMax(peak_equity, stored_peak);
   }
   if(!PersistMaximum(peak_key, peak_equity))
   {
      daily_loss_locked = true;
      equity_drawdown_locked = true;
   }

   const string drawdown_lock_key = RiskStateKey("ddlock");
   if(GlobalVariableCheck(drawdown_lock_key))
   {
      double stored_drawdown_lock = 0.0;
      if(!ReadPersistentValue(drawdown_lock_key, stored_drawdown_lock))
         return;
      if(stored_drawdown_lock > 0.5)
         equity_drawdown_locked = true;
   }

   const int today = CurrentDayKey();
   const string daily_lock_key = DailyRiskLockKey(today);
   if(GlobalVariableCheck(daily_lock_key))
   {
      double stored_daily_lock = 0.0;
      if(!ReadPersistentValue(daily_lock_key, stored_daily_lock))
         return;
      if(stored_daily_lock > 0.5)
         daily_loss_locked = true;
   }

   const string day_equity_key = DailyEquityKey(today);
   if(GlobalVariableCheck(day_equity_key))
   {
      double stored_day_equity = 0.0;
      if(!ReadPersistentValue(day_equity_key, stored_day_equity))
         return;
      day_start_equity =
         MathMax(day_start_equity, stored_day_equity);
      if(!PersistMaximum(day_equity_key, day_start_equity))
      {
         daily_loss_locked = true;
         equity_drawdown_locked = true;
      }
   }
}

bool CalculateDayStartBalance(double &result)
{
   const datetime day_start = StartOfCurrentDay();
   const datetime now       = TimeCurrent();
   if(day_start <= 0 || !HistorySelect(day_start, now))
   {
      PrintFormat("Risk control error: unable to select today's history. Error=%d", GetLastError());
      return false;
   }

   double account_balance_change = 0.0;
   const int deal_count = HistoryDealsTotal();
   for(int index = 0; index < deal_count; index++)
   {
      const ulong ticket = HistoryDealGetTicket(index);
      if(ticket == 0)
         continue;

      account_balance_change += HistoryDealGetDouble(ticket, DEAL_PROFIT);
      account_balance_change += HistoryDealGetDouble(ticket, DEAL_SWAP);
      account_balance_change += HistoryDealGetDouble(ticket, DEAL_COMMISSION);
      account_balance_change += HistoryDealGetDouble(ticket, DEAL_FEE);
   }

   result = AccountInfoDouble(ACCOUNT_BALANCE) - account_balance_change;
   return (result > 0.0);
}

void ResetDailyRiskState(const bool keep_locked = false)
{
   tracked_day_key   = CurrentDayKey();
   daily_loss_locked = keep_locked;

   double calculated_start_balance = 0.0;
   if(!CalculateDayStartBalance(calculated_start_balance))
   {
      day_start_equity = 0.0;
      daily_loss_locked = true;
      Print("Trading locked: daily-loss baseline could not be calculated.");
      if(!PersistRiskState())
         equity_drawdown_locked = true;
      return;
   }

   day_start_equity =
      MathMax(calculated_start_balance, AccountInfoDouble(ACCOUNT_EQUITY));
   PrintFormat("Daily risk state reset. Account-wide equity reference=%.2f",
               day_start_equity);
   if(!PersistRiskState())
   {
      daily_loss_locked = true;
      equity_drawdown_locked = true;
   }
}

void InitializeRiskState()
{
   const double current_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   peak_equity = current_equity;

   if(IsTester())
   {
      equity_drawdown_locked = false;
      ResetDailyRiskState();
      return;
   }

   const string peak_key = RiskStateKey("peak");
   if(GlobalVariableCheck(peak_key))
   {
      double stored_peak = 0.0;
      if(ReadPersistentValue(peak_key, stored_peak))
         peak_equity = MathMax(current_equity, stored_peak);
   }

   const string drawdown_lock_key = RiskStateKey("ddlock");
   if(GlobalVariableCheck(drawdown_lock_key))
   {
      double stored_drawdown_lock = 0.0;
      if(ReadPersistentValue(drawdown_lock_key, stored_drawdown_lock) &&
         stored_drawdown_lock > 0.5)
         equity_drawdown_locked = true;
   }

   const int today = CurrentDayKey();
   const string day_equity_key = DailyEquityKey(today);
   const string daily_lock_key = DailyRiskLockKey(today);
   bool persisted_daily_lock = false;
   if(GlobalVariableCheck(daily_lock_key))
   {
      double stored_daily_lock = 0.0;
      if(ReadPersistentValue(daily_lock_key, stored_daily_lock))
         persisted_daily_lock = (stored_daily_lock > 0.5);
   }
   if(GlobalVariableCheck(day_equity_key))
   {
      double stored_day_equity = 0.0;
      tracked_day_key  = today;
      if(ReadPersistentValue(day_equity_key, stored_day_equity))
         day_start_equity = stored_day_equity;
      else
         day_start_equity = current_equity;
      daily_loss_locked = (daily_loss_locked || persisted_daily_lock);
      PrintFormat("Persistent risk state restored. Day equity=%.2f Peak equity=%.2f",
                  day_start_equity, peak_equity);
   }
   else
   {
      ResetDailyRiskState(persisted_daily_lock);
   }
}

void RefreshRiskState()
{
   bool state_changed = false;
   const int current_day_key = CurrentDayKey();
   if(current_day_key != tracked_day_key)
   {
      ResetDailyRiskState();
      state_changed = true;
   }
   SynchronizePersistentRiskState();

   const double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity > peak_equity)
   {
      peak_equity = equity;
      state_changed = true;
   }

   if(!daily_loss_locked && day_start_equity > 0.0)
   {
      const double daily_loss_percent =
         100.0 * MathMax(0.0, day_start_equity - equity) / day_start_equity;
      if(daily_loss_percent >= InpMaxDailyLossPercent)
      {
         daily_loss_locked = true;
         state_changed = true;
         PrintFormat("Trading locked: daily loss %.2f%% reached limit %.2f%%.",
                     daily_loss_percent, InpMaxDailyLossPercent);
      }
   }

   if(!equity_drawdown_locked && peak_equity > 0.0)
   {
      const double drawdown_percent =
         100.0 * MathMax(0.0, peak_equity - equity) / peak_equity;
      if(drawdown_percent >= InpMaxEquityDrawdownPercent)
      {
         equity_drawdown_locked = true;
         state_changed = true;
         PrintFormat("Trading locked: equity drawdown %.2f%% reached limit %.2f%%.",
                     drawdown_percent, InpMaxEquityDrawdownPercent);
      }
   }

   if(state_changed && !PersistRiskState())
   {
      daily_loss_locked = true;
      equity_drawdown_locked = true;
   }
}

bool TradeSubmissionEnabled()
{
   if(IsTester())
      return true;

   if(!InpEnableLiveTrading)
      return false;

   return (TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) != 0 &&
           MQLInfoInteger(MQL_TRADE_ALLOWED) != 0 &&
           AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) != 0 &&
           AccountInfoInteger(ACCOUNT_TRADE_EXPERT) != 0);
}

bool IsWithinTradingSession()
{
   if(InpSessionStartHour == InpSessionEndHour)
      return true;

   MqlDateTime parts;
   if(!TimeToStruct(TimeCurrent(), parts))
      return false;

   if(InpSessionStartHour < InpSessionEndHour)
      return (parts.hour >= InpSessionStartHour && parts.hour < InpSessionEndHour);

   return (parts.hour >= InpSessionStartHour || parts.hour < InpSessionEndHour);
}

bool GetUnprocessedBarTime(datetime &current_bar_time)
{
   current_bar_time = iTime(_Symbol, _Period, 0);
   if(current_bar_time <= 0)
      return false;
   if(last_bar_time == 0)
   {
      last_bar_time = current_bar_time;
      return false;
   }
   if(current_bar_time == last_bar_time)
      return false;

   return true;
}

bool ReadIndicatorValue(const int handle, const int shift, double &value)
{
   double buffer[1];
   ResetLastError();
   const int copied = CopyBuffer(handle, 0, shift, 1, buffer);
   if(copied != 1 || !MathIsValidNumber(buffer[0]) || buffer[0] == EMPTY_VALUE)
   {
      PrintFormat("Indicator read failed. Handle=%d Shift=%d Copied=%d Error=%d",
                  handle, shift, copied, GetLastError());
      return false;
   }

   value = buffer[0];
   return true;
}

bool GetClosedBarSignal(int &signal, double &atr_value)
{
   signal = 0;

   double fast_closed;
   double fast_previous;
   double slow_closed;
   double slow_previous;

   if(!ReadIndicatorValue(fast_ema_handle, 1, fast_closed) ||
      !ReadIndicatorValue(fast_ema_handle, 2, fast_previous) ||
      !ReadIndicatorValue(slow_ema_handle, 1, slow_closed) ||
      !ReadIndicatorValue(slow_ema_handle, 2, slow_previous) ||
      !ReadIndicatorValue(atr_handle, 1, atr_value))
      return false;

   if(atr_value <= 0.0)
      return false;

   if(fast_previous <= slow_previous && fast_closed > slow_closed)
      signal = 1;
   else if(fast_previous >= slow_previous && fast_closed < slow_closed)
      signal = -1;

   return true;
}

int CountManagedPositions()
{
   int count = 0;
   for(int index = PositionsTotal() - 1; index >= 0; index--)
   {
      const ulong ticket = PositionGetTicket(index);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;
      count++;
   }
   return count;
}

int CountManagedOrders()
{
   int count = 0;
   for(int index = OrdersTotal() - 1; index >= 0; index--)
   {
      const ulong ticket = OrderGetTicket(index);
      if(ticket == 0)
         continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC) != InpMagicNumber)
         continue;
      count++;
   }
   return count;
}

int ManagedPositionDirection()
{
   for(int index = PositionsTotal() - 1; index >= 0; index--)
   {
      const ulong ticket = PositionGetTicket(index);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;

      const ENUM_POSITION_TYPE type =
         (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      return (type == POSITION_TYPE_BUY ? 1 : -1);
   }
   return 0;
}

bool CancelManagedOrders(const string reason)
{
   bool all_canceled = true;
   for(int index = OrdersTotal() - 1; index >= 0; index--)
   {
      const ulong ticket = OrderGetTicket(index);
      if(ticket == 0)
         continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC) != InpMagicNumber)
         continue;

      ResetLastError();
      const bool requested = trade.OrderDelete(ticket);
      const bool still_active = OrderSelect(ticket);
      if(!requested || trade.ResultRetcode() != TRADE_RETCODE_DONE || still_active)
      {
         all_canceled = false;
         PrintFormat("Order not fully canceled. Ticket=%I64u Retcode=%u (%s) Active=%s Error=%d",
                     ticket, trade.ResultRetcode(), trade.ResultRetcodeDescription(),
                     (still_active ? "true" : "false"), GetLastError());
      }
      else
      {
         PrintFormat("Managed order canceled. Ticket=%I64u Reason=%s", ticket, reason);
      }
   }
   return all_canceled;
}

bool IsSuccessfulEntryRetcode()
{
   const uint retcode = trade.ResultRetcode();
   return (retcode == TRADE_RETCODE_DONE ||
           retcode == TRADE_RETCODE_DONE_PARTIAL);
}

bool CloseManagedPositions(const string reason)
{
   bool all_closed = true;
   for(int index = PositionsTotal() - 1; index >= 0; index--)
   {
      const ulong ticket = PositionGetTicket(index);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;

      ResetLastError();
      const bool requested = trade.PositionClose(ticket);
      const bool still_open = PositionSelectByTicket(ticket);
      if(!requested || trade.ResultRetcode() != TRADE_RETCODE_DONE || still_open)
      {
         all_closed = false;
         PrintFormat("Position not fully closed. Ticket=%I64u Retcode=%u (%s) StillOpen=%s Error=%d",
                     ticket, trade.ResultRetcode(), trade.ResultRetcodeDescription(),
                     (still_open ? "true" : "false"), GetLastError());
      }
      else
      {
         PrintFormat("Managed position closed. Ticket=%I64u Reason=%s", ticket, reason);
      }
   }
   return all_closed;
}

bool FlattenManagedExposure(const string reason)
{
   const bool orders_canceled = CancelManagedOrders(reason);
   const bool positions_closed = CloseManagedPositions(reason);
   return (orders_canceled &&
           positions_closed &&
           CountManagedOrders() == 0 &&
           CountManagedPositions() == 0);
}

int VolumeDigits(const double step)
{
   for(int digits = 0; digits <= 8; digits++)
   {
      if(MathAbs(NormalizeDouble(step, digits) - step) < 1e-10)
         return digits;
   }
   return 8;
}

double CalculateRiskBasedVolume(const ENUM_ORDER_TYPE order_type,
                                const double entry_price,
                                const double stop_price)
{
   double one_lot_profit = 0.0;
   ResetLastError();
   if(!OrderCalcProfit(order_type, _Symbol, 1.0, entry_price, stop_price,
                       one_lot_profit) ||
      one_lot_profit >= 0.0)
   {
      PrintFormat("Volume calculation failed. Profit=%.2f Error=%d",
                  one_lot_profit, GetLastError());
      return 0.0;
   }

   const double risk_amount =
      AccountInfoDouble(ACCOUNT_EQUITY) * InpRiskPercent / 100.0 *
      (1.0 - InpRiskCostBufferPercent / 100.0);
   const double raw_volume = risk_amount / MathAbs(one_lot_profit);
   const double min_volume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   const double max_volume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   const double step       = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(risk_amount <= 0.0 || min_volume <= 0.0 || max_volume <= 0.0 || step <= 0.0)
   {
      Print("Volume calculation failed: invalid account or symbol limits.");
      return 0.0;
   }

   double normalized_volume = MathFloor(raw_volume / step + 1e-9) * step;
   normalized_volume = MathMin(normalized_volume, max_volume);
   normalized_volume = NormalizeDouble(normalized_volume, VolumeDigits(step));

   if(normalized_volume < min_volume)
   {
      PrintFormat("Order skipped: risk-based volume %.8f is below minimum %.8f.",
                  normalized_volume, min_volume);
      return 0.0;
   }

   return normalized_volume;
}

double FloorPriceToTick(const double price)
{
   double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick_size <= 0.0)
      tick_size = _Point;
   return NormalizeDouble(MathFloor(price / tick_size + 1e-9) * tick_size, _Digits);
}

double CeilPriceToTick(const double price)
{
   double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick_size <= 0.0)
      tick_size = _Point;
   return NormalizeDouble(MathCeil(price / tick_size - 1e-9) * tick_size, _Digits);
}

bool SpreadIsAcceptable(const MqlTick &tick)
{
   if(_Point <= 0.0)
      return false;

   const double spread_points = (tick.ask - tick.bid) / _Point;
   if(spread_points > InpMaxSpreadPoints)
   {
      PrintFormat("Entry skipped: spread %.1f points exceeds %.1f.",
                  spread_points, InpMaxSpreadPoints);
      return false;
   }
   return true;
}

bool PlaceRiskControlledOrder(const int signal, const double atr_value)
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick) || tick.ask <= 0.0 || tick.bid <= 0.0)
   {
      PrintFormat("Entry skipped: no valid symbol tick. Error=%d", GetLastError());
      return false;
   }
   if(!SpreadIsAcceptable(tick))
      return false;

   const double broker_stop_distance =
      (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   const double stop_distance =
      MathMax(atr_value * InpAtrStopMultiple, broker_stop_distance + _Point);

   const ENUM_ORDER_TYPE order_type =
      (signal > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
   const double entry_price = (signal > 0 ? tick.ask : tick.bid);
   const double stop_price =
      (signal > 0 ? FloorPriceToTick(tick.bid - stop_distance)
                  : CeilPriceToTick(tick.ask + stop_distance));
   const double actual_risk_distance = MathAbs(entry_price - stop_price);
   const double target_distance = actual_risk_distance * InpRewardRiskRatio;
   const double target_price =
      (signal > 0 ? CeilPriceToTick(entry_price + target_distance)
                  : FloorPriceToTick(entry_price - target_distance));

   const double volume =
      CalculateRiskBasedVolume(order_type, entry_price, stop_price);
   if(volume <= 0.0)
      return false;

   ResetLastError();
   bool requested = false;
   if(signal > 0)
      requested = trade.Buy(volume, _Symbol, 0.0, stop_price, target_price,
                            "SafetyFirstEMA buy");
   else
      requested = trade.Sell(volume, _Symbol, 0.0, stop_price, target_price,
                             "SafetyFirstEMA sell");

   if(!requested || !IsSuccessfulEntryRetcode())
   {
      PrintFormat("Order failed. Direction=%d Volume=%.4f Retcode=%u (%s) Error=%d",
                  signal, volume, trade.ResultRetcode(),
                  trade.ResultRetcodeDescription(), GetLastError());
      return false;
   }

   PrintFormat("Order placed. Direction=%d Volume=%.4f SL=%.*f TP=%.*f",
               signal, volume, _Digits, stop_price, _Digits, target_price);
   return true;
}

int OnInit()
{
   if(!ValidateInputs())
      return INIT_PARAMETERS_INCORRECT;

   const ENUM_ACCOUNT_MARGIN_MODE margin_mode =
      (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   if(margin_mode != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
   {
      PrintFormat("Initialization blocked: hedging account required; margin mode=%s.",
                  EnumToString(margin_mode));
      return INIT_FAILED;
   }

   fast_ema_handle = iMA(_Symbol, _Period, InpFastEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   slow_ema_handle = iMA(_Symbol, _Period, InpSlowEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   atr_handle      = iATR(_Symbol, _Period, InpAtrPeriod);
   if(fast_ema_handle == INVALID_HANDLE ||
      slow_ema_handle == INVALID_HANDLE ||
      atr_handle == INVALID_HANDLE)
   {
      PrintFormat("Initialization failed: indicator handle error=%d", GetLastError());
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpMaxSlippagePoints);
   if(!trade.SetTypeFillingBySymbol(_Symbol))
   {
      PrintFormat("Initialization failed: no supported filling policy for %s.", _Symbol);
      return INIT_FAILED;
   }
   trade.SetAsyncMode(false);

   if(!AcquireRiskStateLock())
      return INIT_FAILED;

   last_bar_time = iTime(_Symbol, _Period, 0);
   InitializeRiskState();

   PrintFormat("SafetyFirstEMA v%s initialized on %s/%s. Tester=%s LiveTrading=%s",
               EA_VERSION, _Symbol, EnumToString(_Period),
               (IsTester() ? "true" : "false"),
               (InpEnableLiveTrading ? "true" : "false"));
   if(!IsTester() && !InpEnableLiveTrading)
      Print("All live trade operations are disabled; broker-side SL/TP remain active.");

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   PersistRiskState();
   if(!IsTester())
      GlobalVariablesFlush();

   if(fast_ema_handle != INVALID_HANDLE)
      IndicatorRelease(fast_ema_handle);
   if(slow_ema_handle != INVALID_HANDLE)
      IndicatorRelease(slow_ema_handle);
   if(atr_handle != INVALID_HANDLE)
      IndicatorRelease(atr_handle);
   if(risk_state_lock_handle != INVALID_HANDLE)
   {
      FileClose(risk_state_lock_handle);
      risk_state_lock_handle = INVALID_HANDLE;
   }

   PrintFormat("SafetyFirstEMA deinitialized. Reason=%d", reason);
}

void OnTick()
{
   RefreshRiskState();

   if(!TradeSubmissionEnabled())
      return;

   if(daily_loss_locked || equity_drawdown_locked)
   {
      FlattenManagedExposure("risk limit reached");
      return;
   }

   if(exit_retry_pending)
   {
      if(FlattenManagedExposure("retry incomplete signal exit"))
         exit_retry_pending = false;
      return;
   }

   datetime current_bar_time = 0;
   if(!GetUnprocessedBarTime(current_bar_time))
      return;

   int signal = 0;
   double atr_value = 0.0;
   if(!GetClosedBarSignal(signal, atr_value))
      return;

   last_bar_time = current_bar_time;
   if(signal == 0)
      return;

   const int current_direction = ManagedPositionDirection();
   if(current_direction != 0)
   {
      if(current_direction != signal)
      {
         if(!FlattenManagedExposure("opposite closed-bar signal"))
            exit_retry_pending = true;
      }
      return;
   }

   if(!IsWithinTradingSession())
   {
      Print("Entry skipped: outside configured trading session.");
      return;
   }
   if(CountManagedPositions() >= InpMaxPositions)
   {
      Print("Entry skipped: maximum managed positions reached.");
      return;
   }
   if(CountManagedOrders() > 0)
   {
      Print("Entry skipped: an existing managed order is still active.");
      return;
   }

   PlaceRiskControlledOrder(signal, atr_value);
}
