# Changelog

## v1.0.3 - 2026-09-05

- เก็บ peak equity, daily equity baseline และ lock flags ใน MT5 Terminal
  Global Variables สำหรับ demo/live mode
- ป้องกันการ restart EA หรือ terminal แล้วล้าง daily-loss/drawdown lock
- แยก risk-state ของแต่ละ account และ magic number
- ยืนยันด้วย no-trade GUI chart test และ restart persistence test
- เพิ่ม expected-negative test สำหรับ aggregate-risk validation
- ยืนยัน baseline regression ด้วย 99% real ticks และ 0 runtime/trade errors

## v1.0.2 - 2026-09-05

- เพิ่ม validation ไม่ให้ risk ต่อ trade คูณ maximum positions สูงกว่า
  maximum daily loss
- เพิ่ม Strategy Tester profile สำหรับทดสอบ daily-loss circuit breaker
- ยืนยัน baseline และ safety test ด้วย MT5 Build 6180, 99% real ticks
- Compile ผ่านด้วย 0 errors และ 0 warnings

## v1.0.1 - 2026-09-05

- แยก daily-loss lock ที่ reset รายวันออกจาก permanent drawdown lock
- แก้ Journal spam ที่เคย activate drawdown lock ซ้ำทุกวัน
- ยืนยัน regression ว่า order และ performance metrics ไม่เปลี่ยนจาก v1.0.0

## v1.0.0 - 2026-09-05

- สร้าง `SafeMACrossEA` รุ่นแรกด้วย EMA crossover จากแท่งที่ปิดแล้ว
- เพิ่ม ATR stop loss และ take profit ตาม risk/reward
- เพิ่ม position sizing ตาม equity risk โดยปัด volume ลง
- เพิ่ม daily-loss และ maximum-drawdown circuit breakers
- เพิ่ม spread, slippage, trading-session และ maximum-position filters
- เพิ่ม magic-number และ duplicate-position protection
- ปิด live/demo order submission โดยค่าเริ่มต้น
- สร้าง baseline จาก MT5 Strategy Tester จริง
