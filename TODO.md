# TODO

## เสร็จแล้ว

- [x] สร้างโครงสร้างโปรเจกต์และ EA รุ่นฐาน v1.0.0
- [x] ปิด live/demo order submission โดยค่าเริ่มต้น
- [x] ใช้ EMA/ATR จากแท่งที่ปิดแล้วเพื่อลด look-ahead bias
- [x] เพิ่ม risk-sized volume, SL/TP และ magic-number filtering
- [x] เพิ่ม daily-loss, drawdown, spread และ position-count protection
- [x] Compile v1.0.3 ด้วย MetaEditor: 0 errors, 0 warnings
- [x] รัน MT5 Strategy Tester บน EURUSD H1 ด้วย 99% real ticks
- [x] ตรวจ Journal, Experts และ Tester logs โดยไม่พบ EA runtime/trade error
- [x] ทดสอบ maximum-drawdown lock และ daily-loss lock จริง
- [x] ยืนยัน no-trade GUI chart load และ risk-state persistence หลัง restart
- [x] ยืนยัน expected-negative aggregate-risk validation test
- [x] บันทึก baseline และ regression comparison

## กำลังทำ

- [ ] วิเคราะห์ trend/regime filter เพื่อลด false crossover โดยกำหนดสมมติฐานและเกณฑ์ก่อนทดสอบ

## ต้องทำต่อ

- [ ] แบ่งข้อมูล in-sample/out-of-sample โดยไม่ปรับ parameter แบบสุ่ม
- [ ] ทดสอบหลาย market regimes และทำ walk-forward validation
- [ ] ทดสอบบน demo account แบบควบคุมก่อนพิจารณา live trading

## ปัญหาที่ต้องแก้

- [ ] baseline Profit Factor 0.41 และ net profit -964.71
- [ ] win rate ต่ำ: long 8.33%, short 29.17%
- [ ] ยังไม่มี out-of-sample หรือ walk-forward evidence
- [ ] ยังไม่ผ่าน supervised demo forward test

## สิ่งที่ควรปรับปรุง

- [ ] เพิ่ม automated regression parser สำหรับ Strategy Tester report
- [ ] เพิ่ม unit tests สำหรับ volume rounding และ risk circuit breakers
- [ ] ประเมิน transaction cost sensitivity โดยใช้ spread หลายระดับ
