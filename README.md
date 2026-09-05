# MQL5 Trading Bot

AI-assisted automated trading system for MetaTrader 5.

## Project Structure

- `MQL5/Experts/` - Expert Advisors
- `tests/` - source-level safety regression tests
- `DEVELOPMENT_STATE.md` - latest verified development state
- `TODO.md` - prioritized work and known issues
- `CHANGELOG.md` - version history

## Current EA

`MQL5/Experts/SafeEMACrossEA.mq5` is a safety-first EMA crossover
baseline. It uses only closed candles for signals and sizes orders from
the configured equity risk and ATR stop distance.

Live/demo trading is disabled by default:

```mql5
InpEnableTrading = false
```

The EA automatically permits order submission inside MT5 Strategy
Tester. Enabling it on a demo or live chart requires an explicit input
change. Do not enable it on a live account before completing independent
MetaEditor compilation and Strategy Tester validation.

## Local static checks

```bash
python3 -m unittest discover -s tests -v
```

These checks guard source-level safety properties only. They do not
compile MQL5 and do not replace a real MetaTrader 5 Strategy Tester run.

## Verification status

See `DEVELOPMENT_STATE.md`. No claim of operational readiness is made
without MetaEditor compile output and MetaTrader 5 Strategy Tester logs.
