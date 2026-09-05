# Development State

- เวอร์ชันปัจจุบัน: v1.0.3
- Phase: Safety baseline verified; strategy research required
- เป้าหมายปัจจุบัน: รักษา risk controls ที่ผ่าน MT5 แล้วและแก้ความล้มเหลวของ EMA crossover โดยไม่สุ่มปรับ parameter
- งานล่าสุด: เก็บ peak equity, daily baseline และ lock flags ใน MT5 Terminal Global Variables เพื่อไม่ให้ restart ล้าง risk lock
- ผล Compile: MetaEditor Build 6180 — 0 errors, 0 warnings
- ผล MT5 Test: ผ่าน Strategy Tester จริง, expected-negative input test และ GUI chart smoke test บน MetaQuotes-Demo; Initialize, indicator buffers, order/position operations, no-trade safety mode, risk-state restart persistence และ shutdown สำเร็จ
- ผล Backtest: EURUSD H1, 2024-01-01 ถึง 2024-12-31, 99% real ticks, 20,364,690 ticks, 6,213 bars
- ปัญหาที่พบ: baseline ขาดทุน -964.71, Profit Factor 0.41, win rate 18.75% และ maximum equity drawdown 9.98%; กลยุทธ์ยังไม่เหมาะกับ live trading
- สิ่งที่แก้ไข: drawdown lock ทำงานเพียงครั้งเดียว; ปฏิเสธค่า risk รวมที่สูงกว่า daily-loss limit; daily-loss test ทำงาน 41 ครั้ง; risk state คงอยู่หลังปิดและเปิด MT5 ใหม่
- ผลเปรียบเทียบ: v1.0.0 ถึง v1.0.3 ให้ผล baseline เท่ากันทุก metric ตามคาด เพราะไม่มีการเปลี่ยน signal/parameter; รุ่นหลังปรับความปลอดภัยและ log เท่านั้น
- งานถัดไป: ออกแบบ trend/regime filter จากสมมติฐานที่ชัดเจน แล้วทดสอบ in-sample และ out-of-sample แยกกัน; ห้าม optimize จนกว่าจะกำหนดเกณฑ์ล่วงหน้า
- สถานะการพัฒนา: CONTINUE

รายละเอียด metric และหลักฐานการทดสอบอยู่ที่
`tests/backtests/2026-09-05-v1.0.3.md`
