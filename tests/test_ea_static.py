"""Static safety regression checks for the MQL5 EA.

These checks do not replace MetaEditor compilation or MT5 Strategy Tester.
They prevent accidental removal of critical source-level safeguards in
environments where MetaTrader 5 is unavailable.
"""

from pathlib import Path
import re
import unittest


EA_SOURCE = (
    Path(__file__).resolve().parents[1]
    / "MQL5"
    / "Experts"
    / "SafeEMACrossEA.mq5"
)


class SafeEMACrossStaticTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.source = EA_SOURCE.read_text(encoding="utf-8")

    def test_live_trading_is_disabled_by_default(self) -> None:
        self.assertRegex(
            self.source,
            r"input\s+bool\s+InpEnableTrading\s*=\s*false\s*;",
        )

    def test_signals_read_closed_bars_only(self) -> None:
        self.assertIn(
            "CopyBuffer(g_fast_ema_handle, 0, 1, 2, fast_values)",
            self.source,
        )
        self.assertIn(
            "CopyBuffer(g_slow_ema_handle, 0, 1, 2, slow_values)",
            self.source,
        )
        self.assertIn(
            "CopyBuffer(g_atr_handle, 0, 1, 1, atr_values)",
            self.source,
        )
        self.assertNotRegex(
            self.source,
            r"CopyBuffer\(g_(?:fast_ema|slow_ema|atr)_handle,\s*0,\s*0,",
            "Indicator shift 0 would introduce an open-candle signal.",
        )

    def test_entry_path_has_required_safety_gates(self) -> None:
        on_tick = self.source.split("void OnTick()", maxsplit=1)[1]
        gates = [
            "RiskLimitsBreached",
            "TradingAuthorized",
            "IsWithinTradingSession",
            "InpMaximumSpreadPoints",
            "HasForeignPositionOnSymbol",
            "InpMaximumPositions",
        ]
        for gate in gates:
            with self.subTest(gate=gate):
                self.assertIn(gate, on_tick)

    def test_risk_volume_rounds_down(self) -> None:
        self.assertIn("MathFloor", self.source)
        self.assertNotIn("MathCeil(raw_volume", self.source)
        self.assertIn("raw_volume < volume_min", self.source)

    def test_trade_identity_is_configured(self) -> None:
        self.assertIn("SetExpertMagicNumber", self.source)
        self.assertGreaterEqual(
            len(re.findall(r"POSITION_MAGIC", self.source)),
            3,
        )

    def test_trade_server_retcode_is_verified(self) -> None:
        self.assertIn("TradeResultSucceeded", self.source)
        self.assertIn("TRADE_RETCODE_DONE", self.source)
        self.assertIn("TRADE_RETCODE_PLACED", self.source)

    def test_indicator_handles_are_released(self) -> None:
        release_calls = re.findall(r"IndicatorRelease\(", self.source)
        self.assertEqual(len(release_calls), 3)


if __name__ == "__main__":
    unittest.main()
