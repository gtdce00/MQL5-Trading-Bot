# TODO

## เสร็จแล้ว

- [x] สร้าง EA รุ่นเริ่มต้น v1.0.0
- [x] ปิด live trading โดยค่าเริ่มต้น แต่อนุญาตเฉพาะ Strategy Tester
- [x] ใช้ EMA และ ATR จากแท่งปิดเท่านั้น (shift 1 และ 2)
- [x] เพิ่ม risk-based lot sizing และปัด volume ลงตาม volume step
- [x] เพิ่ม Stop Loss, Take Profit, spread/session filters และ magic number
- [x] เพิ่ม duplicate-position, daily-loss และ equity-drawdown protection
- [x] เพิ่ม static safety tests และ Strategy Tester baseline config
- [x] บังคับ hedging account เพื่อป้องกันการรวม netting position
- [x] Persist daily/drawdown locks และ peak equity ข้าม terminal restart
- [x] เพิ่ม singleton lock ต่อ account/server และ monotonic persistence
- [x] แก้ stop-distance quote side และตรวจ close completion/retry
- [x] กำหนด real-tick model และ parameter set แบบ explicit

## กำลังทำ

- [ ] ติดตั้ง/ค้นหา MetaTrader 5 test environment
- [ ] Compile v1.0.0 ด้วย MetaEditor และแก้ error/warning
- [ ] รัน Strategy Tester จริงและตรวจทุก log

## ต้องทำต่อ

- [ ] บันทึก Net Profit, Profit Factor, Maximum Drawdown และจำนวน trades
- [ ] บันทึก Recovery Factor, Win Rate, Average Trade และ Expected Payoff
- [ ] บันทึก Sharpe, long/short, wins/losses และ consecutive results
- [ ] สร้าง out-of-sample และ multi-regime baseline หลัง v1.0.0 ผ่าน runtime test
- [ ] เปรียบเทียบผลกับรุ่นถัดไปโดยไม่ปรับ parameter แบบสุ่ม

## ปัญหาที่ต้องแก้

- [ ] Environment เริ่มต้นยังไม่พบ Wine, MetaEditor หรือ MetaTrader 5
- [ ] ยังไม่ได้ทดสอบ EA ใน MetaTrader 5 จริง
- [ ] ยังไม่มี historical-data backtest report

## สิ่งที่ควรปรับปรุง

- [ ] เพิ่ม automated parser สำหรับ Strategy Tester report
- [ ] เพิ่ม walk-forward test configuration
- [ ] ทดสอบการ restore drawdown lock หลัง terminal restart บน demo terminal
