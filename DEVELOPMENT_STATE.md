# Development State

- เวอร์ชันปัจจุบัน: v1.0.6
- Phase: Trading-safety hardening verified; strategy research required
- เป้าหมายปัจจุบัน: รักษา risk controls ที่ผ่าน MT5 และทดสอบ trend/regime
  hypothesis โดยไม่สุ่มปรับ parameter
- งานล่าสุด: ทำ persisted risk state ให้ monotonic/fail-closed, จำกัดหนึ่ง
  live instance ต่อ terminal/server/account/magic, เพิ่ม risk timer,
  ตรวจ full close, ปฏิเสธ
  netting/exchange live execution และเผื่อ slippage/cost reserve
- ผล Compile: MetaEditor Build 6180 — 0 errors, 0 warnings
- ผล MT5 Test: v1.0.6 ผ่าน Strategy Tester จริงและ non-trading demo-chart
  smoke test บน MetaQuotes-Demo; Initialize, EMA/ATR buffers,
  order/position operations และ shutdown สำเร็จโดยไม่พบ EA error
- ผล Backtest: EURUSD H1, 2024-01-01 ถึง 2024-12-31, every tick based on
  real ticks, history quality 99%, 20,364,690 ticks, 6,213 bars
- ปัญหาที่พบ: baseline v1.0.6 ยังขาดทุน -977.03, Profit Factor 0.37,
  win rate 17.65% และ maximum equity drawdown 1,008.71 (10.06%);
  กลยุทธ์ยังไม่เหมาะกับ live trading
- สิ่งที่แก้ไข: persisted locks ไม่ถูก instance เก่าลดค่า; startup ที่ไม่มี
  daily baseline ปิดความเสี่ยงถึงวันถัดไป; live instance ใช้ atomic owner;
  partial close ไม่ถูกนับว่าเสร็จ; live netting/exchange ถูกปฏิเสธ;
  gross stop risk เผื่อ slippage และ cost buffer 10%
- ผลเปรียบเทียบ: เทียบ v1.0.5 แล้ว v1.0.6 ลด volume เพื่อเพิ่ม safety reserve;
  net profit เปลี่ยน -964.80 เป็น -977.03, Profit Factor 0.41 เป็น 0.37,
  equity drawdown 9.98% เป็น 10.06% และ trades 48 เป็น 51;
  กลยุทธ์ไม่ได้ดีขึ้นและความเสี่ยงยังไม่ผ่านเกณฑ์ live
- งานถัดไป: กำหนด trend/regime-filter hypothesis และ acceptance criteria
  ล่วงหน้า จากนั้นทดสอบ in-sample/out-of-sample และหลาย market regimes
- สถานะการพัฒนา: CONTINUE

รายละเอียด metric และหลักฐานการทดสอบอยู่ที่
`tests/backtests/2026-09-05-v1.0.6.md`
