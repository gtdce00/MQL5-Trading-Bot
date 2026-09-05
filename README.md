# MQL5 Trading Bot

AI-assisted Expert Advisor development for MetaTrader 5.

## Current EA

`MQL5/Experts/SafetyFirstEMA.mq5` is a safety-first EMA crossover
baseline. It:

- derives signals only from closed bars (indicator shifts 1 and 2);
- sizes volume down from account equity, stop distance, configured risk, and a
  cost/slippage reserve;
- uses ATR-based stop loss and reward/risk-based take profit;
- filters excessive spread and trading sessions;
- prevents duplicate positions by symbol and magic number;
- locks trading at account-wide daily-loss or equity-drawdown limits;
- persists live risk locks and the equity high-water mark across restarts;
- permits one live EA instance per broker account/server so shared safety state
  cannot be overwritten concurrently;
- requires a hedging account to avoid modifying aggregated netting positions;
  and
- defaults `InpEnableLiveTrading` to `false`.

Strategy Tester execution is allowed independently of the live-trading
switch. When disabled outside the tester, the switch blocks every EA trade
operation; existing broker-side SL/TP remain active. Enabling live trading
remains an explicit operator action and should only be considered on a demo
account after testing.

## Project structure

- `MQL5/Experts/` — Expert Advisors
- `tests/` — static checks and MT5 Strategy Tester configuration
- `docs/test-results/` — compile, terminal, tester, and backtest evidence
- `DEVELOPMENT_STATE.md` — current development and verification state
- `TODO.md` — prioritized follow-up work
- `CHANGELOG.md` — version history

## Verification

Run repository-level static safety checks:

```bash
python3 -m unittest discover -s tests -p 'test_*.py'
```

Compile with MetaEditor:

```text
metaeditor64.exe /compile:MQL5\Experts\SafetyFirstEMA.mq5 /log:compile.log
```

Before running the Strategy Tester, copy:

- `MQL5/Experts/SafetyFirstEMA.mq5` (and its compiled `.ex5`) into the
  terminal's `MQL5/Experts/` directory;
- `tests/mt5/SafetyFirstEMA-v1.0.0.set` into
  `MQL5/Profiles/Tester/`; and
- the selected `.ini` file to a path visible inside the Wine prefix.

Then run the deterministic baseline:

```text
terminal64.exe /portable /config:tests\mt5\strategy_tester.ini
```

The checked-in tester baseline uses EURUSD M15, real historical dates
2024-01-01 through 2024-12-31, every-tick modeling, USD 10,000 initial
capital, and 1:100 leverage. The terminal must already contain an authorized
hedging demo account; the repository deliberately contains no broker
credentials. Reports and logs must be reviewed before changing the development
state from unverified. Repeat with
`strategy_tester_latency.ini`, which enables random execution delay, before any
demo-account decision.
