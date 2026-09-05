# TODO

## เสร็จแล้ว

- [x] สร้างโครงสร้างโปรเจกต์และ EA รุ่นฐาน v1.0.0
- [x] ปิด live/demo order submission โดยค่าเริ่มต้น
- [x] ใช้ EMA/ATR จากแท่งที่ปิดแล้วเพื่อลด look-ahead bias
- [x] เพิ่ม risk-sized volume, SL/TP และ magic-number filtering
- [x] เพิ่ม daily-loss, drawdown, spread และ position-count protection
- [x] Persist risk baselines/locks ข้าม EA restart นอก Strategy Tester
- [x] ปิด trade methods ทั้งหมดเมื่อ live/demo trading disabled
- [x] จำกัด position แบบ account-wide ต่อ magic และ block foreign position
- [x] ใช้ exact stop-risk sizing และ tick-grid protective prices
- [x] ทำ persisted locks แบบ monotonic พร้อม integrity marker
- [x] fail closed เมื่อไม่มี current-day baseline ที่เชื่อถือได้
- [x] serialize entry และ verify full position close
- [x] ปฏิเสธ live netting/exchange execution account
- [x] เผื่อ slippage และ cost reserve ใน gross stop-risk sizing
- [x] Compile v1.0.6 ด้วย MetaEditor: 0 errors, 0 warnings
- [x] ผ่าน static safety regression 21 tests
- [x] รัน MT5 Strategy Tester บน EURUSD H1 ด้วย 99% real ticks
- [x] ตรวจ Journal, Experts และ Tester logs โดยไม่พบ EA runtime/trade error
- [x] ทดสอบ maximum-drawdown lock และ daily-loss lock จริง
- [x] ทดสอบ non-trading demo chart โดยไม่มี order/deal ใหม่
- [x] บันทึก baseline และ regression comparison

## กำลังทำ

- [ ] วิเคราะห์ trend/regime filter เพื่อลด false crossover โดยกำหนดสมมติฐานและเกณฑ์ก่อนทดสอบ

## ต้องทำต่อ

- [ ] แบ่งข้อมูล in-sample/out-of-sample โดยไม่ปรับ parameter แบบสุ่ม
- [ ] ทดสอบหลาย market regimes และทำ walk-forward validation
- [ ] ทดสอบบน demo account แบบควบคุมก่อนพิจารณา live trading
- [ ] เพิ่ม test profile ที่ยืนยันว่า aggregate-risk validation ปฏิเสธค่าที่ไม่ปลอดภัย
- [ ] เพิ่ม behavioral multi-instance test สำหรับ account-wide magic limit,
  live instance lock และ persisted-state rollover
- [ ] ทดสอบ exact risk sizing บน symbol ที่ tick size/contract ต่างจาก EURUSD

## ปัญหาที่ต้องแก้

- [ ] baseline v1.0.6 Profit Factor 0.37 และ net profit -977.03
- [ ] win rate ต่ำ: long 7.69%, short 28.00%
- [ ] ยังไม่มี out-of-sample หรือ walk-forward evidence
- [ ] ยังไม่ผ่าน supervised demo forward test

## สิ่งที่ควรปรับปรุง

- [ ] เพิ่ม automated regression parser สำหรับ Strategy Tester report
- [ ] เพิ่ม unit tests สำหรับ volume rounding และ risk circuit breakers
- [ ] ประเมิน transaction cost sensitivity โดยใช้ spread หลายระดับ
