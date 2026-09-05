# Changelog

## v0.1.0 — 2026-09-05

- สร้าง `SafetyFirstEMA` Expert Advisor รุ่นแรก
- เพิ่ม EMA crossover signal จากแท่งปิดเท่านั้นเพื่อลด look-ahead bias
- เพิ่ม ATR Stop Loss และ reward/risk Take Profit
- เพิ่ม position sizing จาก equity risk พร้อมปัด lot ลงอย่างปลอดภัย
- เพิ่ม cost/slippage reserve ใน position sizing
- เพิ่ม account-wide maximum daily loss และ maximum equity drawdown locks
- Persist daily/drawdown locks และ peak equity แบบ monotonic ข้าม terminal restart
- เพิ่ม account/server singleton lock ป้องกันหลาย instance เขียน safety state ทับกัน
- เพิ่ม spread, slippage, trading-session และ maximum-position controls
- เพิ่ม magic-number isolation และ duplicate-position protection
- บังคับใช้ hedging account เพื่อไม่ให้ EA รวมกับ netting position อื่น
- ตรวจสอบ close completion และ retry เมื่อปิด position ไม่สมบูรณ์
- คำนวณ minimum stop จาก quote side ที่ broker ใช้ตรวจจริง
- ปิด live trading โดยค่าเริ่มต้นและแยก permission ของ Strategy Tester
- เพิ่ม static safety tests, explicit parameter set และ EURUSD M15 real-tick baseline
