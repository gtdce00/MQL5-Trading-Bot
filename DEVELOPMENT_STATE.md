# Development State

- เวอร์ชันปัจจุบัน: v1.001
- Phase: Baseline runtime verification blocked
- เป้าหมายปัจจุบัน: รัน baseline Strategy Tester ให้ผ่านก่อนปรับกลยุทธ์
- งานล่าสุด: เปิด MT5 จริง, โหลด tester config และตรวจ log หลัง Strategy Tester ไม่เริ่ม
- ผล Compile: ผ่าน MetaEditor build 6180 บน Wine 10.0 — 0 errors, 0 warnings
- ผล MT5 Test: MT5 เปิดและอ่าน config ได้ แต่ Strategy Tester หยุดก่อนโหลด EA เพราะไม่มี account context
- ผล Backtest: ไม่เริ่ม — Profit Factor, Net Profit, Drawdown และจำนวน Trade เป็น N/A
- ปัญหาที่พบ: `tester not started because the account is not specified`; การสร้าง MetaQuotes-Demo ต้องใช้ข้อมูลส่วนบุคคลที่ automation ไม่มี
- สิ่งที่แก้ไข: จำกัดบัญชี hedging, จัดการ active orders, ปิด exposure ทุก Symbol เมื่อ breaker ทำงาน และใช้ `OrderCalcProfit` ที่ worst-case slippage
- ผลเปรียบเทียบ: v1.001 ลดความเสี่ยง runtime เทียบกับ v0.1.0 แต่ยังไม่มี baseline backtest สำหรับเปรียบเทียบ performance
- งานถัดไป: ใช้ terminal ที่มี authorized demo account แบบ hedging แล้วรัน `config/strategy-tester-v1.001.ini` เดิม; ห้ามปรับกลยุทธ์ก่อน baseline ผ่าน
- สถานะการพัฒนา: CONTINUE

> ห้ามใช้เอกสารนี้เป็นหลักฐานว่า EA พร้อมใช้งานจริง จนกว่าจะมีผล Compile และ Strategy Tester จาก MetaTrader 5
