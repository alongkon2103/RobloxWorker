# Stream Overlay — ตั้งค่าและส่งต่องาน

อัปเดต 17 ตุลาคม 2026

ดีไซน์ล่าสุด: ทางลอยโปร่งใส ขอบขาวสีพาสเทล ไม่มีแผงทึบใหญ่ ตารางใช้แถบเล็กโปร่งแสงตามภาพอ้างอิงของผู้ใช้

## สิ่งที่ทำแล้ว

- Map: เส้นทางโค้งจริงจาก `Workspace.World.Map.Checkpoints` ผ่าน `RacePath` เดียวกับเกม (จุดเหล่านี้สร้างจาก `Workspace["ทาง"]`) สุ่มตัวอย่างตามระยะทาง 512 จุด แสดงผู้แข่ง หมายเลขอันดับ START/FINISH และอีเวนต์ที่กำลังทำงาน ปรับหมุนแผนที่ให้เข้าพื้นที่แนวตั้งโดยไม่เปลี่ยนรูปทาง
- Race Leaders: 5 อันดับแรก ความเร็วปัจจุบัน km/h และรอบที่วิ่ง
- Speed Legends: 5 อันดับความเร็วสูงสุดของตาปัจจุบัน ไม่ใช่สถิติตลอดชีพ
- รวมทั้งหมด: 3 ส่วนเรียงข้างกัน
- ปุ่ม OVERLAY บนขวาในเกม: เปิด/หยุด เลือกชนิด และเลือก URL เพื่อคัดลอกด้วย Ctrl+C / Cmd+C (Roblox ไม่มี clipboard API ปกติสำหรับผู้เล่น)
- ไม่มีการตั้ง API key ฝั่ง client. URL ประจำเจ้าของเป็น read-only; เข้าถึงด้วย ownerId อย่างเดียวไม่ได้

## ก่อนใช้จริงบน VPS

โค้ดติดตั้งใน Studio แล้ว แต่ API บน VPS ต้องอัปเดตก่อน URL จึงใช้งานได้ ไม่มีการ deploy VPS หรือ Publish place แทนเจ้าของในรอบนี้

อัปโหลดไฟล์จาก `bridge-api/` หรือแตก `bridge-api-overlay-update.zip` ทับโฟลเดอร์โปรเจกต์เดิมบน VPS (zip ไม่มี .env, data/, logs/, node_modules/). สำรองโค้ดเดิมก่อน ใช้ Node 24.11+ ตามระบบเดิม

```bash
cd /var/www/RobloxWorker/RobloxWorker
./deploy.sh
pm2 status hyperrun-live-bridge
curl -fsS http://127.0.0.1:7435/healthz
```

หาก deploy ด้วย git ให้ commit/push ไฟล์อัปเดตก่อนแล้ว pull บน VPS รอบนี้ไม่ได้ push GitHub อัตโนมัติ

Proxy HTTPS เดิมต้องส่งทั้ง `/overlay` และ `/v1/overlays/*`, `/v1/overlay/state` มาที่พอร์ต7435 ไม่ตัด `#fragment` ออกจาก URL ที่คัดลอก ส่วน fragment ไม่ถูกส่งไป proxy และใช้เป็น read credential เฉพาะในหน้า Overlay

API เพิ่มตาราง `overlay_profiles` อัตโนมัติใน SQLite เดิม ต้องเก็บ data/ และสำรอง DB เหมือนเดิมเพื่อลิงก์ไม่เปลี่ยนหลัง restart

## ใช้ใน OBS

1. เข้าเกม กด OVERLAY → เปิดใช้งาน
2. เลือก สนามแข่ง / อันดับแข่ง / Top Speed / รวมทั้งหมด
3. กดเลือก URL แล้ว Ctrl+C หรือ Cmd+C
4. OBS → Sources → Browser → วาง URL ส่วนตัวทั้งหมด
5. ขนาดแยกชิ้น 460×700, รวมทั้งหมด1360×700; Browser FPS60 ตามเครื่อง พื้นหลังหน้าเว็บโปร่งใส
6. อย่าแชร์ URL; URL อ่านได้เฉพาะข้อมูลการแข่งของเจ้าของ แต่ใครมีลิงก์ก็เปิดดูได้ ไม่มีคีย์เขียน/API key อยู่ในลิงก์

ลิงก์เดิมใช้ต่อได้เมื่อเปิดเกมรอบใหม่/API restart ตราบใดเก็บ SQLite เดิมไว้ มี lease45วินาทีป้องกัน ownerเดียวกันจากคนละห้องส่งทับกัน เมื่อออกเกมปล่อย lease; กรณีเซิร์ฟเวอร์ปิดฉับพลันห้องใหม่อาจต้องรอให้ leaseหมด

รูปและชื่อ: ใช้ RobloxId โหลด avatar-headshot จาก Roblox ครั้งละไม่เกิน100 IDs ผ่าน API, แคชmetadata6ชั่วโมง (รูปpending/ล้มเหลวรอ60วินาทีก่อนลองใหม่) ภาพโหลดจาก Roblox CDN โดยตรง ไม่ได้ขอรูปทุกเฟรม. ชื่ออ่านจาก ViewerRobloxUsername ที่ GameHandlers ตั้งจาก context.robloxUsername; ผู้แข่งที่สร้างก่อนติดตั้งต้องเริ่มรอบ/Playใหม่เพื่อมี attributeนี้. รูปยังไม่พร้อมใช้เงารูปคนแทน ไม่แสดงเลขในจุดผู้แข่ง

## ไฟล์

| ไฟล์ | ตำแหน่ง Studio / หน้าที่ |
|---|---|
| roblox/OverlayConfig.lua | ServerScriptService.OverlayConfig: เปิดระบบ, ความถี่ส่ง/วัดpeak, จำนวนจุด, PublicOrigin |
| roblox/OverlayPublisher.lua | ServerScriptService.OverlayPublisher: เก็บเฉพาะ NPC ของเจ้าของ, สร้างเส้นทาง/peak, claim, publish และ RemoteFunction |
| roblox/OverlayPanel.client.lua | StarterPlayerScripts.OverlayPanel: หน้าต่างและเลือก URL ส่วนตัว |
| roblox/GameHandlers.lua | เพิ่มเฉพาะ ViewerRobloxUsername attribute ให้ Overlayใช้ชื่อRoblox |
| roblox/Boot.server.lua | เพิ่มบรรทัดเริ่ม Publisher ด้วย authenticated transport เดิม; ไม่เปลี่ยน logic แข่ง |
| bridge-api/src/overlay-avatars.mjs | แคชและโหลดรูปหัว Roblox แบบbatch ไม่รอรูปก่อนเผยแพร่ตำแหน่ง |
| bridge-api/src/overlay.mjs | schema validation, persistent read token, expiring write lease, round peak, in-memory snapshots |
| bridge-api/src/server.mjs | API และ static assets |
| bridge-api/public/overlay/ | HTML/CSS/canvas animation และ art.png |
| bridge-api/test/overlay.test.mjs | ownership/read-write isolation, lease recovery, round peak, API restart, HTTP/static |

Remotes: `ReplicatedStorage.OverlayControl` RemoteFunction รับ action enable/info/disable. Server ใช้ Player ที่เรียกเอง ไม่มีรับ ownerId จาก client. คืนเฉพาะ URLอ่านให้เจ้าของผ่าน response ไม่ใช้ Player attribute เก็บ URL. `OverlayStatus` attributeมีเพียงสถานะ

Routes: POST /v1/overlays/claim (Bridge key), POST /v1/overlays/batch (Bridge key + per-owner write token), POST /v1/overlays/publish (write token), POST /v1/overlays/release (write token), GET /v1/overlay/state (read token), GET /overlay?view=map|ranking|speed|all#READ_TOKEN

## โหลดและความลื่น

- ส่งรวมทุกเจ้าของที่เปิดใช้งานครั้งเดียวต่อวินาทีต่อเกมเซิร์ฟเวอร์ แบ่ง packetเมื่อขนาดเกิน200KB (API cap256KiB) ไม่เขียน SQLite ทุกเฟรม
- ส่งเส้นทางเฉพาะ claimแรก/reclaim/routeเปลี่ยน; snapshotเก็บในRAM หยุดส่งเมื่อปิดOverlay
- วัด peak10ครั้ง/วินาที; peakที่สั้นกว่าช่วงsampleอาจไม่ถูกเก็บ
- Browser ดึง1ครั้ง/วินาทีต่อ Browser Source, buffer1.1วินาทีแล้ว interpolate บนเส้นทาง; ภาพหน่วงเล็กน้อยเพื่อให้ลื่น ตัด extrapolationที่0.8วินาทีและหยุดเดาเมื่อoffline
- เก็บข้อมูลเฉพาะวงแข่งปัจจุบัน ไม่เพิ่ม dependency websocket และไม่เชื่อม Eulerซ้ำ
- เปลี่ยนแมพใน Edit แล้ว Play ใหม่จะสร้างpathใหม่อัตโนมัติ Runtimeเปลี่ยนchild checkpointsจะ rebuild; การแก้Positionของgateเดิมระหว่างPlayอย่างเดียวต้องเริ่มPlayใหม่

## หลักฐานทดสอบ

- Node24.19.0: ชุด API20 testsผ่านทั้งหมด รวม routingเก่า, Euler mock, Tikkies, overlays
- Studio Play: mock transport ด้วยทางจริง512จุด, Waiting racer, peak240 studs/s, ตรวจpublish11ครั้ง ใช้claimเดียว, routeส่งครั้งเดียว; เปิด/ปิด/เปิดใหม่สำเร็จ, clientไม่รับwriteToken, UIสร้างได้
- StudioจบกลับEdit ไม่มีfixtureทดสอบค้าง และ compileไฟล์ใหม่/Bootผ่าน
- Browser: ตรวจพื้นหลัง rgba(0,0,0,0), Top5ครบทั้ง3ตำแหน่ง, รูปRoblox CDNโหลดจริง และแสดงทั้งสามส่วนด้วยรูปทางจริงและผู้แข่งจำลอง; ภาพ docs/overlay-preview.png ไม่ใช่ข้อมูล LIVEจริง
- ยังไม่ได้ทดสอบ end-to-end ผ่าน VPS production, OBSจริง, หรือโหลดหลายเซิร์ฟเวอร์พร้อมกัน จึงยังไม่รับรองFPSของเครื่องสตรีมเมอร์

## ภาพตกแต่ง

`bridge-api/public/overlay/art.png` สร้างด้วย built-in imagegen เป็น PNGโปร่งใส ใช้promptแนว: “glossy mint winged running shoe, golden trophy, checkered flag, lilac sparkles and speed ribbon; polished playful toy-like 3D; transparent; no text”. ธีมcompactล่าสุดซ่อนภาพตกแต่งนี้ตามคำขอให้เรียบง่าย ตัวเลข/ชื่อ/ทางทั้งหมดเป็นข้อมูลสด ไม่ฝังในรูป
