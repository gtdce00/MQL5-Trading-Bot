# TODO

## เสร็จแล้ว

- [x] สร้าง EA รุ่นฐาน v0.1.0
- [x] ปิด live/demo trading โดยค่าเริ่มต้น และอนุญาตคำสั่งซื้อขายอัตโนมัติเฉพาะ Strategy Tester
- [x] ใช้ EMA/ATR จากแท่งปิด (shift 1 และ 2) เพื่อป้องกัน look-ahead bias
- [x] เพิ่ม risk-based lot size, stop loss, take profit และ broker volume normalization
- [x] เพิ่ม daily loss/drawdown breaker, spread filter, session filter และ Magic Number
- [x] เพิ่ม static safety regression tests
- [x] จำกัด v1.001 ให้ใช้บัญชี hedging เพื่อป้องกัน mixed-ownership net positions
- [x] เพิ่ม active-order cleanup และ account-wide risk-breaker liquidation

## กำลังทำ

- [ ] จัดหา authorized demo account context เพื่อให้ baseline Strategy Tester เริ่มได้

## ต้องทำต่อ

- [x] ยืนยันว่า v1.001 Compile แบบไม่มี error/warning ด้วย MetaEditor
- [x] เปิด MT5 build 6180 และยืนยันว่า startup tester config ถูกโหลด
- [x] ตรวจ Terminal และ Tester logs ของรอบที่ล้มเหลว
- [ ] รัน MT5 Strategy Tester ด้วย historical tick data
- [ ] ตรวจ Journal, Experts และ Tester logs หลัง EA initialize
- [ ] บันทึก Symbol, Timeframe, date range, deposit, spread และ model
- [ ] บันทึก Net Profit, Profit Factor, Drawdown, Recovery Factor, Win Rate, Trades, Expected Payoff และ Sharpe Ratio
- [ ] สร้าง in-sample/out-of-sample baseline ก่อนปรับ parameter หรือกลยุทธ์
- [ ] เปรียบเทียบทุกเวอร์ชันใหม่กับผล baseline เดียวกัน

## ปัญหาที่ต้องแก้

- [ ] Strategy Tester ไม่เริ่มหากไม่มี account context
- [ ] MetaQuotes-Demo registration ต้องใช้ข้อมูลส่วนบุคคล; ห้ามสร้างข้อมูลจริงแทนผู้ใช้
- [ ] ตรวจสอบความถูกต้องของ filling mode, stop distance และ tick-value calculation กับหลายประเภท Symbol
- [ ] ทดสอบบัญชี netting และ hedging แยกกัน
- [ ] ออกแบบ netting ownership tracking ก่อนอนุญาตบัญชี netting

## สิ่งที่ควรปรับปรุง

- [x] เพิ่ม reproducible Strategy Tester configuration
- [ ] เพิ่ม Windows automation script สำหรับ terminal ที่มี demo account อยู่แล้ว
- [ ] เพิ่มการตรวจผลกระทบจาก deposit/withdrawal ต่อ persistent equity breaker
- [ ] เพิ่ม walk-forward และ multi-regime test หลัง baseline ผ่าน runtime validation
