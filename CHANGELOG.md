# Changelog

## v1.0.6 - 2026-09-05

- ทำ persisted peak/locks ให้เขียนแบบ monotonic พร้อม server/account/magic
  scope และ integrity marker
- fail closed ถึงวันถัดไปเมื่อไม่มี current-day baseline ที่เชื่อถือได้
- จำกัดหนึ่ง live instance ต่อ terminal/server/account/magic และตรวจ risk
  lock ซ้ำก่อนส่ง
- timer ตรวจ account risk และสั่ง protective close แม้ chart ไม่มี tick
- ยอมรับ protective close ว่าสำเร็จเฉพาะ full fill และ position หายแล้ว
- ปฏิเสธ live/demo execution บน netting และ exchange execution account
- เผื่อ configured slippage กับ cost reserve 10% ใน gross stop-risk sizing
- เพิ่ม static safety regression รวมเป็น 21 tests
- Compile และ MT5 baseline/daily-loss/demo smoke test ผ่านโดยไม่มี EA error

## v1.0.5 - 2026-09-05

- เปลี่ยน position sizing ให้ใช้ `OrderCalcProfit` ที่ entry และ stop loss
  จริงแทนการประมาณด้วย tick value
- ปัด stop loss และ take profit ออกด้านปลอดภัยตาม tick size ของ symbol
- เพิ่ม static safety regression รวมเป็น 12 tests
- ยืนยันด้วย MT5 Build 6180: baseline และ daily-loss test ผ่านบน 99% real ticks
- ยืนยัน demo-chart safety mode โดยไม่มี order/deal ใหม่
- Compile ผ่านด้วย 0 errors และ 0 warnings

## v1.0.4 - 2026-09-05

- ย้าย live-trading gate ให้อยู่ก่อน trade method ทุกตัว รวม protective close
- บังคับ maximum positions แบบ account-wide สำหรับ magic number เดียวกัน
- ให้ circuit breaker ปิดทุก position ของ magic number ในบัญชี
- คง opposite-signal close เฉพาะ symbol และไม่เปิดทับ foreign/manual position
- ยืนยัน non-trading demo-chart smoke test โดยไม่มี order/deal ใหม่

## v1.0.3 - 2026-09-05

- เก็บ peak equity, daily baseline และ risk-lock state ด้วย Terminal Global
  Variables แบบ account/magic scoped
- restore risk state หลัง EA restart; ปิด persistence ใน Strategy Tester
  เพื่อให้ backtest แยกจากกันและทำซ้ำได้
- ยืนยัน baseline regression ด้วย MT5 จริงโดยผลเท่ากับ v1.0.2

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
