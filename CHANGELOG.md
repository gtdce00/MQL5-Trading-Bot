# Changelog

## v0.1.0 - 2026-09-05

- สร้าง `SafeEMACrossEA` รุ่นฐานโดยใช้ EMA crossover จากแท่งปิด
- เพิ่ม ATR stop loss และ take profit ตาม risk/reward
- เพิ่ม position sizing ตาม equity risk พร้อมปัด volume ลงตาม broker step
- เพิ่ม maximum daily loss และ maximum equity drawdown breakers
- เพิ่ม spread, slippage, session, maximum-position และ foreign-position filters
- เพิ่ม Magic Number และ persistent protection state สำหรับ live/demo terminal
- ปิด live/demo trading โดยค่าเริ่มต้น ขณะที่ Strategy Tester ทำงานได้อัตโนมัติ
- เพิ่ม static regression tests สำหรับ safety invariants และ look-ahead protection

### Verification

- MetaEditor compile: ยังไม่ได้ทดสอบ (ไม่มี MetaEditor ใน environment)
- MetaTrader 5 Strategy Tester: ยังไม่ได้ทดสอบ
- Backtest comparison: ไม่มีเวอร์ชันก่อนหน้า
