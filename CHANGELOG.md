# Changelog

## v1.001 - 2026-09-05

- จำกัดการทำงานไว้ที่บัญชี hedging เพื่อป้องกันการปิด net position ที่มีหลายกลยุทธ์ร่วมกัน
- เพิ่มการตรวจและยกเลิก active orders ที่ EA ไม่ได้ตั้งใจค้างไว้
- แก้ account risk breaker ให้ปิด positions และยกเลิก orders ของ Magic Number เดียวกันทุก Symbol
- ใช้ `OrderCalcProfit` ที่ worst-case slippage สำหรับคำนวณความเสี่ยงต่อ lot
- เพิ่ม free-margin safety allowance ก่อนส่งคำสั่ง
- คำนวณ take profit จาก stop distance หลัง normalize ตาม tick size
- ป้องกันการปิด position ทิศเดิมและยืนยัน trade-server retcode อย่างเข้มงวด

### Verification

- Static safety tests: ผ่าน 9 tests
- MetaEditor compile: ผ่าน build 6180, 0 errors, 0 warnings
- MetaTrader 5 Strategy Tester: ยังไม่ได้ทดสอบ

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
