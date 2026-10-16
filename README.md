# RobloxWorker / HyperRun Live Bridge

API กลางสำหรับ TikTok LIVE → VPS → Roblox รองรับหลายสตรีมเมอร์พร้อมกัน ใช้ Euler รับไลฟ์ และ PM2 รันโปรเซสที่พอร์ต **7435**

โปรเจกต์นี้เป็นฝั่ง VPS เท่านั้น ยังไม่ได้แก้ Roblox ให้เชื่อม API นี้ การทดสอบใช้ Euler จำลองและ HTTP/SQLite จริง ไม่มีคีย์ส่วนตัวใน repository

## เริ่มใช้งาน

ต้องใช้ **Node.js24 LTS รุ่น24.11ขึ้นไป** และ PM2 รุ่นที่รองรับ ecosystem config

```bash
cd RobloxWorker
./deploy.sh
```

ครั้งแรกจะสร้าง `.env` และสุ่ม `BRIDGE_API_KEY` / `ADMIN_API_KEY` คนละค่า โดยไม่แสดงคีย์ จากนั้นเปิด `.env` ใส่คีย์ของคุณ:

```dotenv
EULER_TOKEN=ใส่คีย์จริงที่นี่
PORT=7435
```

รองรับชื่อ `EULER_API_KEY` เดิมด้วย ให้ตั้งอย่างใดอย่างหนึ่ง อย่า commit `.env`

```bash
./deploy.sh
pm2 status hyperrun-live-bridge
curl http://127.0.0.1:7435/healthz
```

`deploy.sh` ตรวจ config และรัน tests ก่อนเริ่มผ่าน PM2 มี `start.sh` สำหรับเริ่ม/รีสตาร์ตอย่างเดียว:

```bash
./start.sh
# หรือโดยตรง
pm2 startOrRestart ecosystem.config.cjs --update-env
pm2 save
# รัน foreground เพื่อ debug
./start.sh --foreground
```

ตั้ง PM2 startup ตาม user บน VPS ของคุณ (`pm2 startup` แล้วใช้คำสั่งที่ PM2 แสดง) ค่าเริ่มต้น bind `127.0.0.1:7435` ให้วาง HTTPS reverse proxy มาที่พอร์ตนี้สำหรับ Roblox; เปลี่ยน `HOST=0.0.0.0` หากต้องการ bind ทุก interface

## หลายไลฟ์ / ส่งถูกคนถูก server

แต่ละ session ผูกกับ `ownerRobloxId` + `jobId` + ชื่อ TikTok มี bearer token แยก และคิว/ผู้แข่งแยกกัน แม้ TikTok viewer คนเดียวกันเข้าไลฟ์สองคนก็ไม่ปะปน

- `MAX_LIVE_CONNECTIONS=5`: จำนวน socket พร้อมกัน ปรับให้ตรงกับโควตา key Euler
- `MAX_CONNECT_ATTEMPTS_PER_MINUTE=5`: จำกัดการเปิด/reconnect ทั้งระบบ; เมื่อ Euler แจ้ง4429 จะพักการเปิดใหม่
- ไลฟ์เกินช่องที่มีจะอยู่คิวเชื่อมต่อ ส่วนไลฟ์ที่เชื่อมแล้วรับข้อมูลพร้อมกัน
- ประมวลผล inbox แบบหมุนเวียน เพื่อไม่ให้ไลฟ์เก่าที่มีงานเยอะกีดกันไลฟ์อื่น
- หนึ่ง owner และหนึ่งชื่อ TikTok มี active session ได้อย่างละหนึ่ง ปิด session เก่าก่อนย้าย server/เชื่อมใหม่
- ปิด session เมื่อเจ้าของออกเกม หาก server หายและไม่มี heartbeat จะหมดอายุใน90วินาที

`BRIDGE_API_KEY` ใช้เฉพาะ Roblox **ServerScript** สำหรับเปิด session และ batch poll/ACK อย่าส่งให้ LocalScript หรือ client ระบุ owner/job จาก Player.UserId และ game.JobId จริง ไม่รับค่าตามที่ client อ้างโดยตรง

`ADMIN_API_KEY` เป็นสิทธิ์จัดการ backend แยกต่างหาก ห้ามใส่ในเกมฝั่ง client

## คิวและความทนทาน

SQLite WAL + synchronous FULL เก็บ session, raw inbox, actor bindings, delivery queue และ receipts ลงดิสก์ก่อนยืนยันรับงาน ไม่ใช้คิวในหน่วยความจำอย่างเดียว

- FIFO ต่อ session: join มาก่อน gift ของผู้เล่นนั้น
- งานมี lease20วินาที; ไม่มี ACK จะส่งงานเดิมใหม่ด้วย `eventId` เดิมและ receipt ใหม่
- ACK ต้องตรง session/receipt; receipt เก่าใช้ไม่ได้ และ ACK ซ้ำหลังสำเร็จไม่ทำงานซ้ำ
- reset ทำ transaction เปลี่ยน `runId`/`generation`, ล้างคิวและ actor bindings งาน lookup ที่ยังค้างไม่กลับเข้าตาใหม่
- reset ใช้ `requestId` เดิมเมื่อ retry เพื่อไม่เพิ่มรอบซ้ำ
- join ที่หมดอายุหรือถูก ACK ว่าล้มเหลวถาวร จะล้าง binding และยกเลิก gift ที่พึ่ง join นั้น
- เก็บ inbox10000งาน และ delivery1000งานต่อไลฟ์ตาม config; คิวเต็มจะแสดง backpressure และปิด/พักการเชื่อมต่อ ไม่ขยาย RAM ไม่จำกัด

การส่งเป็น **at-least-once** ไม่ใช่การรับประกัน effect ทำครั้งเดียวโดยไม่ร่วมมือกับเกม Roblox ต้อง dedupe `liveSessionId + runId + generation + eventId` และเก็บผลจนพ้น `EVENT_TTL_MS + DELIVERY_LEASE_MS` อย่าใช้ receipt เป็นตัว dedupe เพราะ receipt เปลี่ยนเมื่อ retry

คิวที่บันทึกสำเร็จทนการรีสตาร์ตได้ แต่ไม่สามารถกู้ข้อมูลที่ Euler/TikTok ไม่ได้ส่งมา หรือข้อมูลใหม่เมื่อ storage/inbox เต็ม งานเกมชั่วคราวหมดอายุตาม TTL

รัน PM2 **fork1เท่านั้น** API process เดียวเปิดหลาย socket พร้อมกันได้ มี worker lock กันโปรเซสซ้ำ ฐานข้อมูลอยู่ `data/bridge.sqlite` พร้อม WAL อย่าลบ `data/` ตอนอัปเดต ทำ backup แบบ SQLite backup/snapshot ที่สอดคล้องกัน ไม่คัดลอกเฉพาะไฟล์ DB ที่กำลังเขียนโดยทิ้ง WAL

นี่เป็นรุ่นหนึ่ง VPS; หากต้องรันหลายเครื่อง/หลาย PM2 workers ต้องเปลี่ยน store เป็น shared queue และ distributed connection ownership ก่อน

## คนดูเข้าร่วมและ Rocket

เลือก `joinMode` ต่อ session ได้ 3 ค่า: `at` ต้องมี@ (ค่าเริ่มต้น), `plain` พิมพ์ชื่อ Roblox ตรงๆ, `both` รับทั้งสองแบบ บันทึกใน SQLite และคงค่าเมื่อ reset รอบ เปลี่ยนทันทีด้วย POST `/v1/sessions/:id/join-mode` body `{ "joinMode": "both" }` ใช้ session token


คนดูพิมพ์ `@RobloxUsername` / `@ RobloxUsername` ตามค่าเริ่มต้น API จะ resolve บัญชี Roblox และผูกกับ TikTok user ID ของผู้พิมพ์ ไม่ใช้ชื่อแสดงผลเป็นตัวระบุคน

ค่าเริ่มต้น `gift-map.json` เป็น `{}` เพื่อไม่เดาว่าของขวัญไหนควรเป็น Rocket หลังไลฟ์ได้รับ gift ให้ดู `GET /v1/sessions/:id/gifts` เพื่อหา giftId/ชื่อ แล้วตั้ง map:

```json
{
  "ใส่ตัวเลข giftId จริง": { "key": "rocket", "value": 1 }
}
```

แทนข้อความด้วย giftId ตัวเลขจริงก่อนใช้งาน ตั้งแบบส่วนกลางใน `gift-map.json` แล้ว restart หรือใช้ API `gift-map` ตั้งเฉพาะ session โดยไม่ต้อง restart

รองรับ keys `rocket`, `rainbow_cat`, `jump`, `heal`, `power` แบบเดียวกับ handler เกม นับ combo gift ตอนจบและกัน group ซ้ำเมื่อ upstream มี groupId; gift ที่ไม่อยู่ใน map จะบันทึกใน catalogue แต่ไม่สร้าง effect และผู้ส่งต้อง join ก่อน

## API

ทุก POST ใช้ `Content-Type: application/json` และทุก endpoint ยกเว้น health ใช้ `Authorization: Bearer ...`

| Endpoint | Key | หน้าที่ |
| --- | --- | --- |
| `GET /healthz` | ไม่ต้อง | readiness ของ HTTP/DB |
| `POST /v1/sessions` | Bridge key | เปิด session |
| `GET /v1/sessions/:id` | Session token | สถานะ/คิว/รอบ/map |
| `POST /v1/sessions/:id/heartbeat` | Session token | ต่อ lease90วินาที |
| `POST /v1/sessions/:id/poll` | Session token | รับหนึ่งงาน หรือ `event:null`; ต่อ heartbeat |
| `POST /v1/sessions/:id/ack` | Session token | ยืนยัน/ขอลองใหม่/ปฏิเสธถาวร |
| `POST /v1/sessions/:id/reset` | Session token | ล้างตาใหม่แบบ idempotent |
| `POST /v1/sessions/:id/reconnect` | Session token | ลองใหม่หลัง connection error |
| `DELETE /v1/sessions/:id` | Session token | ปิด session/ล้างงาน |
| `GET /v1/sessions/:id/gifts` | Session token | gift catalogue ของไลฟ์นี้ |
| `POST /v1/sessions/:id/join-mode` | Session token | ตั้งรูปแบบเข้าร่วม at/plain/both |
| `POST /v1/sessions/:id/gift-map` | Session token | ตั้ง `{gifts:{giftId:{key,value}}}` เฉพาะ session |
| `POST /v1/servers/:jobId/poll` | Bridge key | batch poll ทุก session ใน Roblox server นี้ |
| `POST /v1/servers/:jobId/ack` | Bridge key | batch ACK ของ server นี้ |
| `GET /v1/admin/sessions` | Admin key | ดูทุก session ไม่แสดง tokens |
| `POST /v1/admin/sessions/:id/ingest` | Admin key | Tikkies normalized ingress เมื่อเปิด provider |

เปิด session:

```json
{
  "ownerRobloxId": "123456",
  "jobId": "Roblox-game-JobId",
  "tiktokUsername": "ชื่อสตรีมเมอร์ไม่ใส่@ก็ได้",
  "provider": "direct",
  "joinMode": "at"
}
```

ใช้ username ตัวอักษร/ตัวเลข/จุด/underscore จริง จะได้ `id`, `token`, `runId`, `generation`, `status` เก็บ token เฉพาะบน server

งานจาก poll:

```json
{
  "event": {
    "eventId": "WebcastChatMessage:upstream-id",
    "liveSessionId": "session-uuid",
    "ownerRobloxId": "123456",
    "runId": "run-uuid",
    "generation": 1,
    "namespace": "live",
    "actorKey": "tiktok:viewer-id",
    "robloxId": "789",
    "robloxUsername": "Runner",
    "tiktokUsername": "viewer",
    "eventType": "join",
    "effects": [],
    "receipt": "opaque-receipt",
    "expiresAt": "ISO-8601",
    "leaseUntil": "ISO-8601"
  }
}
```

ให้ Roblox เรียก `GameHandlers.join(context)` สำหรับ join และ `GameHandlers.event(context)` สำหรับ effect แล้ว ACK หลังสำเร็จ; ตรวจ owner ยังอยู่ใน server, run/generation ปัจจุบันและเวลาหมดอายุก่อนทำงาน

```json
{ "eventId": "event-id", "receipt": "receipt-from-poll", "success": true }
```

ผิดพลาดชั่วคราวใช้ `success:false,retry:true` ถาวรใช้ `success:false,retry:false` เช่น unsupported effect อย่า ACK สำเร็จก่อน effect ถูกทำ

reset:

```json
{ "requestId": "unique-id-for-this-reset-reuse-on-retry" }
```

หลายสตรีมเมอร์ใน Roblox server เดียว แนะนำ batch poll ทุก2วินาทีและรวม ACK เพื่อลด HTTP requests:

```json
// POST /v1/servers/:jobId/poll
{ "sessionIds": ["session-uuid"] }
// response
{ "events": [{ "sessionId": "uuid", "event": {} }] }
// POST /v1/servers/:jobId/ack
{ "receipts": [{ "sessionId": "uuid", "eventId": "id", "receipt": "opaque", "success": true }] }
```

`sessionIds` เป็นรายการ session ที่ Roblox ถือ token อยู่จริง (สูงสุด100) API จะ poll/ต่อ heartbeat เฉพาะรายการนี้ และปฏิเสธ session ของ job อื่น วิธีนี้ทำให้ orphan จากคำตอบ create ที่สูญหายหมดอายุตามปกติ; client เดิมส่ง `{}` ยังใช้งานแบบ poll ทั้ง job ได้

รหัสทั่วไป:401คีย์ไม่ตรง,403provider/jobไม่อนุญาต,409owner/liveใช้งานอยู่หรือreceipt/รอบเก่า,410sessionหมดอายุ,429quota/queueเต็ม

## Tikkies ทางเลือกที่สอง

`TIKKIES_ENABLED=false` เป็นค่าเริ่มต้น ไม่เปิด Euler และ Tikkies ให้ session เดียวกันพร้อมกัน

เมื่อเปิด flag จะสร้าง `provider:tikkies` ได้ และต้องมีฝั่ง server ที่ได้รับอนุญาตส่ง normalized packet เข้า admin ingress:

```json
{
  "generation": 1,
  "eventId": "tikkies-delivery-id",
  "eventType": "join",
  "actorKey": "tiktok:viewer-id",
  "robloxId": "789",
  "robloxUsername": "Runner",
  "tiktokUsername": "viewer",
  "effects": []
}
```

gift ใช้ actor เดิมและ `effects:[{key:"rocket",value:1,count:1}]` ไม่มีการเชื่อมบัญชี Tikkies อัตโนมัติในโปรเจกต์นี้ ตัวรับ Tikkies เดิมในเกมจะเลือกใช้แทน Direct ได้ตอนทำ Roblox integration

## ตรวจและดูแล

```bash
npm test
pm2 logs hyperrun-live-bridge --lines 100
pm2 restart hyperrun-live-bridge --update-env
```

ไม่มี dependencies runtime เพิ่ม ใช้ HTTP/WebSocket/SQLite ใน Node24 (Node24.11แสดง experimental warning สำหรับ node:sqlite; API ที่ใช้ทดสอบผ่านบน24.11.1) PM2 logs ไม่พิมพ์ Euler URL, API key หรือ request bodies และไฟล์ `.env` มี permission600

ทดสอบ: durable restart/lease/ACK, session+job isolation, round reset/stale async, expired join cleanup, fair scheduler, two-live mock Euler→HTTP flow, startup/duplicate-worker/graceful shutdown และ start/deploy script setup

ยังไม่ทดสอบ Euler LIVE จริงด้วย key ของคุณ, ไม่ deploy VPS และไม่แก้ Roblox ในขั้นนี้

อ้างอิง protocol: [Euler WebSocket API](https://www.eulerstream.com/docs/api/tiktok-web-socket-api), [Euler WebSocket SDK](https://github.com/EulerStream/Euler-WebSocket-SDK)

ถ้า VPS ยังไม่มีระบบหมุน log ของ PM2 ให้ตั้ง `pm2-logrotate` ตามนโยบายพื้นที่ของคุณ เช่น max_size10M และ retain7 เพื่อไม่ให้ log โตตลอดเวลา

Rainbow Cat: map giftId จริงไปยัง `{ "key": "rainbow_cat", "value": 1 }` เกมจะให้ขี่แมวเร็ว ×2.5 นาน 10 วินาที ค่าความเร็วและเวลาแก้ที่ `ReplicatedStorage.RaceEventConfig` ใน Roblox ไม่ใช่ `value` ใน gift map

Naruto: map giftId จริงไปยัง `{ "key": "naruto", "value": 1 }` ค่าในเกมปัจจุบันแปลงร่าง5วินาที เร็ว×7.5 และของขวัญหลายชิ้นต่อเวลาสะสม แก้ที่ `ReplicatedStorage.RaceEventConfig` ต้องอัปเดต bridge รุ่นที่รองรับ `naruto` ก่อนใช้ผ่าน Direct Live
