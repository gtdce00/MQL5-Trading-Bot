from pathlib import Path
import re
import unittest


SOURCE = (
    Path(__file__).resolve().parents[1]
    / "MQL5"
    / "Experts"
    / "SafeMACrossEA.mq5"
).read_text(encoding="utf-8")


def function_body(name: str) -> str:
    match = re.search(rf"\b{name}\s*\([^)]*\)\s*\{{", SOURCE)
    if not match:
        raise AssertionError(f"function not found: {name}")

    depth = 1
    cursor = match.end()
    while cursor < len(SOURCE) and depth:
        if SOURCE[cursor] == "{":
            depth += 1
        elif SOURCE[cursor] == "}":
            depth -= 1
        cursor += 1
    if depth:
        raise AssertionError(f"unterminated function: {name}")
    return SOURCE[match.end() : cursor - 1]


class SafeMACrossStaticTests(unittest.TestCase):
    def test_expected_version_is_under_test(self) -> None:
        self.assertIn('#property version   "1.006"', SOURCE)

    def test_live_trading_is_disabled_by_default(self) -> None:
        self.assertIn("input bool   InpAllowLiveTrading       = false;", SOURCE)

    def test_no_trade_method_precedes_live_gate(self) -> None:
        body = function_body("OnTick")
        gate = body.index(
            "if(!MQLInfoInteger(MQL_TESTER) && !InpAllowLiveTrading)"
        )
        for method in ("CloseManagedPositions(", "CloseOppositePositions(", "OpenPosition("):
            self.assertGreater(body.index(method), gate)

    def test_signals_use_only_closed_bars(self) -> None:
        body = function_body("ClosedBarSignal")
        self.assertIn("CopyBuffer(fast_ema_handle, 0, 1, 2", body)
        self.assertIn("CopyBuffer(slow_ema_handle, 0, 1, 2", body)
        self.assertIn("CopyBuffer(atr_handle, 0, 1, 1", body)
        self.assertNotRegex(body, r"CopyBuffer\([^,]+,\s*0,\s*0,")

    def test_position_limit_is_account_wide_for_magic(self) -> None:
        body = function_body("ManagedPositionCount")
        self.assertIn("IsMagicPosition(ticket)", body)
        self.assertNotIn("IsManagedSymbolPosition(ticket)", body)

    def test_risk_lock_closes_all_magic_positions(self) -> None:
        body = function_body("CloseManagedPositions")
        self.assertIn("IsMagicPosition(ticket)", body)
        self.assertNotIn("IsManagedSymbolPosition(ticket)", body)

    def test_signal_close_remains_symbol_scoped(self) -> None:
        body = function_body("CloseOppositePositions")
        self.assertIn("IsManagedSymbolPosition(ticket)", body)

    def test_foreign_symbol_positions_block_entry(self) -> None:
        body = function_body("OpenPositionLocked")
        self.assertIn("HasForeignSymbolPosition()", body)

    def test_risk_volume_uses_broker_profit_at_actual_stop(self) -> None:
        body = function_body("EntryVolume")
        self.assertIn("OrderCalcProfit(", body)
        self.assertIn("entry, stop_loss, stop_profit", body)
        self.assertNotIn("SYMBOL_TRADE_TICK_VALUE", body)

    def test_protective_prices_are_rounded_to_tick_grid(self) -> None:
        normalizer = function_body("NormalizeProtectivePrice")
        entry = function_body("OpenPositionLocked")
        self.assertIn("SYMBOL_TRADE_TICK_SIZE", normalizer)
        self.assertIn("MathCeil(", normalizer)
        self.assertIn("MathFloor(", normalizer)
        self.assertGreaterEqual(entry.count("NormalizeProtectivePrice("), 2)

    def test_risk_sizing_reserves_slippage_and_costs(self) -> None:
        entry = function_body("OpenPositionLocked")
        sizing = function_body("EntryVolume")
        self.assertIn("InpMaximumSlippagePoints", entry)
        self.assertIn("risk_entry", entry)
        self.assertIn("InpRiskCostBufferPercent", sizing)

    def test_partial_close_is_not_reported_as_complete(self) -> None:
        completed = function_body("TradeRequestCompleted")
        close_all = function_body("CloseManagedPositions")
        self.assertNotIn("TRADE_RETCODE_DONE_PARTIAL", completed)
        self.assertIn("!PositionSelectByTicket(ticket)", close_all)

    def test_live_execution_rejects_unsafe_account_models(self) -> None:
        init = function_body("OnInit")
        self.assertIn("ACCOUNT_MARGIN_MODE_RETAIL_HEDGING", init)
        self.assertIn("SYMBOL_TRADE_EXECUTION_EXCHANGE", init)

    def test_persisted_locks_are_monotonic_and_checked(self) -> None:
        persistence = function_body("PersistRiskState")
        initialization = function_body("InitializeRiskState")
        self.assertIn("StoreRiskMaximum(peak_key", persistence)
        self.assertIn("StoreRiskMaximum(daily_lock_key", persistence)
        self.assertIn("StoreRiskMaximum(drawdown_lock_key", persistence)
        self.assertIn("ready_key", initialization)

    def test_live_instance_is_exclusive_outside_tester(self) -> None:
        init = function_body("OnInit")
        entry = function_body("OpenPosition")
        acquire = function_body("AcquireLiveInstanceLock")
        release = function_body("ReleaseLiveInstanceLock")
        self.assertIn("AcquireLiveInstanceLock()", init)
        self.assertIn("LiveInstanceOwnershipValid()", entry)
        self.assertIn("UpdateRiskState()", entry)
        self.assertIn("entry_lock_owner_token", acquire)
        self.assertIn("GlobalVariableCheck(entry_lock_key)", acquire)
        self.assertIn("GlobalVariableTemp(entry_lock_key)", acquire)
        self.assertIn("GlobalVariableSetOnCondition", release)

    def test_new_day_sync_replaces_previous_daily_lock_generation(self) -> None:
        sync = function_body("SynchronizeRiskState")
        self.assertIn("adopting_new_day", sync)
        self.assertIn("? stored_daily_lock", sync)

    def test_entry_submits_the_price_used_for_sizing(self) -> None:
        entry = function_body("OpenPositionLocked")
        self.assertIn("trade.Buy(volume, _Symbol, entry", entry)
        self.assertIn("trade.Sell(volume, _Symbol, entry", entry)
        self.assertNotIn("trade.Buy(volume, _Symbol, 0.0", entry)
        self.assertNotIn("trade.Sell(volume, _Symbol, 0.0", entry)

    def test_account_risk_updates_on_timer(self) -> None:
        init = function_body("OnInit")
        timer = function_body("OnTimer")
        self.assertIn("EventSetTimer(1)", init)
        self.assertIn("UpdateRiskState()", timer)
        self.assertIn("CloseManagedPositions(reason)", timer)

    def test_corrupt_persisted_state_activates_permanent_lock(self) -> None:
        initialization = function_body("InitializeRiskState")
        self.assertIn("any_persisted_state", initialization)
        self.assertIn("drawdown_lock_active = true", initialization)

    def test_aggregate_configured_risk_is_bounded(self) -> None:
        self.assertIn(
            "InpRiskPerTradePercent * InpMaximumPositions >\n"
            "      InpMaximumDailyLossPercent",
            function_body("InputsAreValid"),
        )

    def test_tester_does_not_persist_terminal_global_state(self) -> None:
        body = function_body("InitializeRiskState")
        tester_return = body.index("if(MQLInfoInteger(MQL_TESTER))")
        prefix_setup = body.index("risk_state_prefix =")
        self.assertLess(tester_return, prefix_setup)


if __name__ == "__main__":
    unittest.main()
