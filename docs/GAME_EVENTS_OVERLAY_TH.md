# Game Events Overlay — คู่มือติดตั้งและทดสอบ

18 ตุลาคม 2026 — โค้ดและตัวอย่างในเครื่องพร้อมทดสอบ; ติดตั้งโมดูลและแพตช์เฉพาะจุดใน Studio Edit แล้ว สำรองไว้ที่ ServerStorage.CodexMapBackups.BeforeGameEvents20261018_* ยังไม่ deploy VPS, Publish แมพ หรือ build EXE ใหม่

## หน้าตาและการทำงาน

`view=events` แสดงรูปผู้ส่ง + ชื่อ TikTok ที่เกมกรองแล้ว + ชื่อเอฟเฟกต์ เช่น “หมาส้มส้ม ส่ง Gojo ×1” ใช้ธีม Overlay เกมเดิม (mint/violet/gold + พื้น navy โปร่ง) ไม่มีไอคอนเอฟเฟกต์สมมติทางขวา แสดงล่าสุดไม่เกิน5รายการ แต่ละรายการอายุ12วินาที รองรับ reduced motion และตัวเลือก TikTok/Roblox avatar ของแต่ละลิงก์

บันทึกหลัง `GameHandlers.event` ใช้เอฟเฟกต์/บันทึก receipt/ทำงานส่วนเดิมจบก่อนคืน true เท่านั้น ไม่แจ้ง join, chat ที่ไม่มี effects, handler ที่คืน false หรือ retry ที่ติด receipt เดิม ตัว feed ไม่สั่งสกิลและไม่แก้ mapping/ACK/receipt/reset กรณี Gojo คืน false หรือ Octopus ไม่มีเป้าหมาย จะไม่ใส่สกิลนั้นใน feed แม้ handler เดิมจะรับ delivery แล้วก็ตาม

## เส้นทางข้อมูล

1. Roblox Server: `GameEventFeed.lua` เก็บรายการชั่วคราวแยก owner, จำกัด30รายการและ TTL12วินาที; `GameHandlers.lua` เรียกหลังสำเร็จ
2. `OverlayPublisher.lua` แนบ `snapshot.events=GameEventFeed.snapshot(ownerId)` ผ่าน scoped publishing เดิม
3. Worker ตรวจเฉพาะ public fields ผูกสิทธิ์กับ owner+Universe ของ lease เดิม ไม่มีการเพิ่มสิทธิ์ให้ read token; เติม Roblox avatar จาก cache ฝั่ง Worker
4. `/v1/overlay/state` คืนรายการที่ยังไม่หมดอายุและ publisher ออนไลน์ ตัดรายการเก่าก่อน initial claim/หลัง disconnect ไม่ replay feed ที่เก็บจากช่วงขาดการเชื่อม
5. `/overlay?view=events#<readToken>` แสดงผลด้วย module `event-renderer.js` (serve แบบ fingerprint เหมือน app/helpers เดิม)
6. Tikkies Backend รับ `urls.events` และ `urls.topWin` แบบ optional พร้อมตรวจ origin/path/query/hash เดียวกันกับ4ลิงก์เดิม Games มีการ์ดตัวอย่าง/Copy URL ถ้า Worker ยังไม่รองรับจะแจ้งเฉพาะการ์ดใหม่โดยไม่ทำให้4การ์ดเดิมพัง

### schema

```json
{"events":[{"id":"delivery-id:1","robloxId":"101","tiktokDisplayName":"หมาส้มส้ม","tiktokUsername":"example_viewer","effectKey":"gojo","count":1,"createdAt":1792296000000,"tiktokAvatarUrl":"https://p16.tiktokcdn.com/example.jpg"}]}
```

`id` เป็น delivery event ID + index ของ effect, `createdAt` เป็น UTC Unix milliseconds จาก Roblox Server; เกมและ VPS ต้องตั้งเวลาถูกต้อง ภาพ TikTok เป็น optional Worker ตรวจ CDN เดิม Roblox `avatarUrl` เติมจาก trusted thumbnail cache เท่านั้น ไม่รับ arbitrary avatar URL จาก publisher

Top Win ใช้ owner-scoped ตามเดิม ไม่เพิ่ม `streamerTikTokUserId`/`streamerTikTokUsername`, ไม่ย้ายคะแนนเก่าหรือเปลี่ยนคีย์

## ไฟล์ที่ต้องนำขึ้น

ฝั่ง Worker (`HyperRunRace/bridge-api/`):
- `src/overlay.mjs`, `src/server.mjs`
- `public/overlay/app.js`, `index.html`, `overlay.css`, **`event-renderer.js` ใหม่** (ไฟล์ใหม่ต้องขึ้นพร้อมกัน)

ฝั่งแมพ (`HyperRunRace/roblox/`):
- **`GameEventFeed.lua` ใหม่** เป็น ModuleScript ใน ServerScriptService ใกล้ GameHandlers/OverlayPublisher
- แพตช์ `GameHandlers.lua` และ `OverlayPublisher.lua` ตามโค้ดในเครื่อง (Studio ปัจจุบันติดตั้งเฉพาะจุดแล้ว)
- ไม่ควรคัดลอก GameHandlers ทั้งไฟล์ทับ Studio หากมีการแก้เพิ่มที่ไม่ได้เซฟลงไฟล์ ให้ merge เฉพาะ require + การเก็บ overlayEffects ที่ใช้สำเร็จ + call ท้าย handler และ require + snapshot.events + urls.events ของ Publisher; Studio ปัจจุบันมี gate WhitelistAccess ที่ต้องรักษาไว้ ห้ามแทนทั้งไฟล์ด้วยสำเนาในเครื่องที่อาจเก่ากว่า
- ใช้ข้อมูลชื่อที่กรองแล้วจาก attribute `ViewerDisplayName`; อย่าส่ง nickname ดิบเข้า public Overlay

ฝั่ง Tikkies:
- deploy Auth backend ก่อน (รับ optional URLs และ `tiktokDisplayName` จากงานก่อนหน้า)
- อัปเดตโปรแกรม Desktop ที่มีการ์ด/renderer ใหม่
- ไม่ต้องเพิ่ม environment หรือคีย์ใหม่ เว็บ Admin ไม่มีการแก้สำหรับ feature นี้

## ลำดับปล่อย

1. ตรวจและ deploy Worker พร้อมไฟล์ static ใหม่
2. Deploy Tikkies Auth backend ก่อน Desktop เพื่อรับ nickname เพิ่ม
3. Merge/ทดสอบ adapter และ hook ใน Studio แล้ว Publish แมพ
4. Build Desktop รุ่นใหม่ แล้วเปิด Games > Overlays > Game Events > Copy URL
5. เพิ่ม URL เป็น OBS Browser Source; พื้นโปร่ง แนะนำเริ่มกว้าง420px สูง320px แล้วปรับตามพื้นที่ไลฟ์

## ตรวจรับจริง

ทดสอบส่ง Gojo/สกิลอื่นสำเร็จเห็นรายการเดียว ชื่อกรองและภาพถูกผู้ส่ง, combo ×N ไม่แตกซ้ำ, retry ไม่ขึ้นอีก, failed/viewer_not_joined/empty-effect ไม่แจ้ง, รายการหายหลัง12วินาที, ไม่เห็นรายการของ owner/Universe อื่น, disconnect ไม่ replay, เปลี่ยนรูป TikTok/Roblox ได้, หายไปเมื่อไม่มีรายการและไม่มีแผงรอทับเกม

**ที่ผ่านแล้วในเครื่อง:** Worker full suite90ข้อ, Tikkies Games/API isolation tests, GameEventFeed unit tests และ regression จากฟังก์ชัน GameHandlers.event จริงใน Studio Edit (สกิลถูกปฏิเสธ/รับสำเร็จ/retry), ภาพตัวอย่างในเบราว์เซอร์ด้วยข้อมูลสมมติ ส่วนการเล่นครบเส้นทางกับ LIVE/แมพจริงหลัง Publish ยังต้องตรวจหลัง deploy
