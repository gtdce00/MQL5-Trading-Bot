# MQL5 Trading Bot

Safety-first automated trading research for MetaTrader 5. The project is in
active development and is not approved for live trading.

## Current Expert Advisor

`MQL5/Experts/SafeMACrossEA.mq5` is an EMA-crossover baseline with:

- signals calculated only from completed candles (buffer shifts 2 and 1);
- ATR-based stop loss and fixed risk/reward take profit;
- risk-based volume calculated with `OrderCalcProfit` at the stop price,
  worst configured entry slippage, and a configurable cost reserve, then
  rounded down to the broker's volume step;
- protective prices rounded outward to the symbol's executable tick grid;
- persistent daily-loss and account-drawdown circuit breakers outside the
  Strategy Tester;
- spread, slippage, session, position-count, and magic-number controls;
- account-wide position limits per magic number and protection from foreign
  or manual positions on the chart symbol;
- one fail-closed live-enabled instance per terminal/server/account/magic,
  with monotonic risk state;
- fail-closed startup without a trustworthy current-day risk baseline, and
  live/demo execution rejection on netting or exchange execution accounts;
- live/demo order submission disabled by default while Strategy Tester
  execution remains available.

No profitability claim is made. See `DEVELOPMENT_STATE.md` for the exact
compile and MetaTrader 5 test evidence from the latest development cycle.

## Project Structure

- `MQL5/Experts/` — Expert Advisor source
- `config/` — Strategy Tester configuration
- `tests/` — static safety checks and backtest records
- `DEVELOPMENT_STATE.md` — latest verified development state
- `TODO.md` — prioritized work
- `CHANGELOG.md` — version history

## Safety

`InpAllowLiveTrading` defaults to `false`. Do not enable it until the EA has
passed compilation, Strategy Tester regression tests, out-of-sample tests,
and a supervised demo-account trial. This software is experimental and is
not financial advice.
