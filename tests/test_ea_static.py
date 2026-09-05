import pathlib
import re
import unittest
from configparser import ConfigParser


EA_PATH = (
    pathlib.Path(__file__).resolve().parents[1]
    / "MQL5"
    / "Experts"
    / "SafetyFirstEMA.mq5"
)
MT5_TEST_DIR = pathlib.Path(__file__).resolve().parent / "mt5"


class SafetyFirstEMAStaticTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.source = EA_PATH.read_text(encoding="utf-8")

    def test_live_trading_defaults_to_disabled(self) -> None:
        self.assertRegex(
            self.source,
            r"input\s+bool\s+InpEnableLiveTrading\s*=\s*false\s*;",
        )

    def test_signals_only_read_closed_indicator_bars(self) -> None:
        signal_body = re.search(
            r"bool\s+GetClosedBarSignal\(.*?\n\}",
            self.source,
            flags=re.DOTALL,
        )
        self.assertIsNotNone(signal_body)
        shifts = re.findall(
            r"ReadIndicatorValue\([^,]+,\s*(\d+)\s*,",
            signal_body.group(0),
        )
        self.assertTrue(shifts)
        self.assertNotIn("0", shifts)
        self.assertIn("1", shifts)
        self.assertIn("2", shifts)

    def test_safety_controls_are_present(self) -> None:
        required_controls = (
            "InpRiskPercent",
            "InpRiskCostBufferPercent",
            "InpMaxDailyLossPercent",
            "InpMaxEquityDrawdownPercent",
            "InpMaxPositions",
            "InpMaxSpreadPoints",
            "InpMaxSlippagePoints",
            "InpMagicNumber",
        )
        for control in required_controls:
            with self.subTest(control=control):
                self.assertIn(control, self.source)

    def test_order_volume_is_rounded_down(self) -> None:
        self.assertRegex(
            self.source,
            r"normalized_volume\s*=\s*MathFloor\(",
        )
        self.assertIn("normalized_volume < min_volume", self.source)
        self.assertIn("1.0 - InpRiskCostBufferPercent / 100.0", self.source)

    def test_tester_is_allowed_without_enabling_live_trading(self) -> None:
        permission_body = re.search(
            r"bool\s+TradeSubmissionEnabled\(\).*?\n\}",
            self.source,
            flags=re.DOTALL,
        )
        self.assertIsNotNone(permission_body)
        self.assertRegex(
            permission_body.group(0),
            r"if\(IsTester\(\)\)\s+return true;",
        )

    def test_hedging_account_is_required(self) -> None:
        self.assertRegex(
            self.source,
            r"margin_mode\s*!=\s*ACCOUNT_MARGIN_MODE_RETAIL_HEDGING",
        )

    def test_stop_distance_uses_protective_quote_side(self) -> None:
        self.assertIn("FloorPriceToTick(tick.bid - stop_distance)", self.source)
        self.assertIn("CeilPriceToTick(tick.ask + stop_distance)", self.source)

    def test_risk_locks_are_persisted_outside_tester(self) -> None:
        self.assertIn('RiskStateKey("peak")', self.source)
        self.assertIn("DailyRiskLockKey(", self.source)
        self.assertIn('RiskStateKey("ddlock")', self.source)
        self.assertIn("GlobalVariableSetOnCondition(", self.source)
        self.assertIn("GlobalVariablesFlush()", self.source)
        self.assertIn("AcquireRiskStateLock()", self.source)
        self.assertRegex(
            self.source,
            r"GlobalVariableGet\(key,\s*value\)",
        )

    def test_tester_config_uses_real_ticks_and_explicit_parameters(self) -> None:
        parser = ConfigParser()
        parser.optionxform = str
        parser.read(MT5_TEST_DIR / "strategy_tester.ini", encoding="utf-8")
        tester = parser["Tester"]
        self.assertEqual("4", tester["Model"])
        self.assertEqual("0", tester["Optimization"])
        self.assertEqual("SafetyFirstEMA-v0.1.0.set", tester["ExpertParameters"])
        self.assertNotIn("/", tester["Report"])
        self.assertNotIn("\\", tester["Report"])

    def test_tester_parameter_file_fixes_every_input(self) -> None:
        set_text = (MT5_TEST_DIR / "SafetyFirstEMA-v0.1.0.set").read_text(
            encoding="utf-8"
        )
        parameter_lines = [
            line
            for line in set_text.splitlines()
            if line and not line.startswith(";")
        ]
        input_names = re.findall(r"input\s+\w+\s+(Inp\w+)\s*=", self.source)
        configured_names = {
            line.split("=", 1)[0]
            for line in parameter_lines
        }
        self.assertEqual(set(input_names), configured_names)
        for line in parameter_lines:
            with self.subTest(parameter=line):
                fields = line.split("=", 1)[1].split("||")
                self.assertEqual(5, len(fields))
                self.assertEqual("N", fields[-1])

    def test_latency_robustness_config_uses_random_delay(self) -> None:
        parser = ConfigParser()
        parser.optionxform = str
        parser.read(
            MT5_TEST_DIR / "strategy_tester_latency.ini",
            encoding="utf-8",
        )
        tester = parser["Tester"]
        self.assertEqual("4", tester["Model"])
        self.assertEqual("-1", tester["ExecutionMode"])


if __name__ == "__main__":
    unittest.main()
