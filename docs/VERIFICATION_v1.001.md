# Verification Report — SafeEMACrossEA v1.001

Date: 2026-09-05 UTC

## Environment

- MetaTrader 5 x64 build 6180
- MetaEditor build 6180
- Wine 10.0 on Ubuntu 24.04 x86_64
- Live/AutoTrading was not enabled

## Compile

- Source: `MQL5/Experts/SafeEMACrossEA.mq5`
- Result: **0 errors, 0 warnings**
- Target: X64 Regular
- Compile time: 692 ms

## Strategy Tester configuration

- Config: `config/strategy-tester-v1.001.ini`
- Symbol: EURUSD
- Timeframe: H1
- Period: 2025-01-01 through 2025-12-31
- Initial deposit: 10,000 USD
- Leverage: 1:100
- Model: Every tick based on real ticks (`Model=4`)
- Local agents only; MQL5 Cloud disabled

## MT5 test outcome

MetaTrader 5 opened and loaded the startup configuration. Strategy
Tester then stopped before loading or initializing the EA:

```text
tester not started because the account is not specified
```

A MetaQuotes-Demo hedging account registration was attempted using
clearly non-personal test data. The registration form rejected the
reserved fictional phone number and requires personal-data fields, so
no account was created.

The EA has therefore **not** completed a real Strategy Tester run.
Indicator handles, runtime behavior, entries, exits, stops, trade
retcodes, and risk breakers remain unverified in MT5.

## Backtest metrics

- Net Profit: N/A
- Profit Factor: N/A
- Maximum Drawdown: N/A
- Recovery Factor: N/A
- Win Rate: N/A
- Trades: N/A
- Average Trade: N/A
- Expected Payoff: N/A
- Sharpe Ratio: N/A
- Long/Short and consecutive win/loss statistics: N/A

No comparison or strategy optimization is valid until a preconfigured,
authorized demo account context is available and this exact baseline
test completes.
