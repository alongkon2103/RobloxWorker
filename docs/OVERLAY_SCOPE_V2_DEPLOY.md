# เปิดใช้ Tikkies Overlay schema v2
วันที่ 17 ตุลาคม 2026

## โค้ดที่เพิ่มแล้ว
Worker มี POST /v1/integrations/tikkies/overlay-links รับ ownerRobloxId/universeId เป็น string คืน schemaVersion=2, online และ URL 4 แบบตามสัญญา Tikkies

ตารางใหม่ overlay_profiles_v2 ใช้ primary key (universe_id,owner_id) และ read_token unique ใช้ INSERT ON CONFLICT แล้วอ่านค่าที่บันทึกจริง แยก live lease และ snapshot ตามขอบเขตเดียวกัน เก็บตาราง owner-only และลิงก์เก่าแยกไว้ ไม่คัดลอก token หรือข้อมูลข้ามเกม

Integration สร้าง/อ่านเฉพาะ read profile ไม่แตะ claim/write token/lease; online=true เมื่อมีการ publish snapshot จริงภายใน 5 วินาที การ claim อย่างเดียวไม่ถือว่าออนไลน์

## Worker environment
เพิ่มใน .env โดยไม่เปลี่ยนคีย์เดิม:
```dotenv
OVERLAY_PUBLIC_ORIGIN=https://rbworker.aclassstore.com
TIKKIES_OVERLAY_SERVICE_KEY=<new-random-service-key>
TIKKIES_OVERLAY_UNIVERSES=10771081714
OVERLAY_MAP_KEYS_FILE=./data/overlay-map-keys.json
```
Universe ของแมพปัจจุบันคือ 10771081714 ไม่ใช้ Place ID 71201643655847 แทน

สร้างไฟล์ JSON บน VPS โดยตัวอย่างนี้เป็น placeholder เท่านั้น:
```json
{"10771081714":"<new-random-map-key>"}
```
เก็บใต้ data/ ซึ่ง gitignore อยู่แล้ว ตั้งสิทธิ์ไฟล์ 600 ห้าม commit คีย์จริง สร้างคีย์แบบสุ่มอย่างน้อย 32 ตัวและไม่ซ้ำกัน: service key, คีย์ของแต่ละแมพ, bridge key และ admin key ต้องต่างกัน ห้ามใช้ Euler token

หลายเกมให้ใส่ allowlist คั่น comma และเพิ่ม map key ไม่ซ้ำต่อ Universe ใน JSON Allowlist ใช้ให้สิทธิ์ขอ read profile ส่วน map key ใช้ให้สิทธิ์ publisher ของแมพนั้น

## TikkiesAuthBackEnd environment
```dotenv
ROBLOX_WORKER_ORIGIN=https://rbworker.aclassstore.com
TIKKIES_OVERLAY_SERVICE_KEY=<same-service-key-as-worker>
```
Tikkies ต้องตรวจ session/device/entitlement ก่อนเรียก Worker และดึง owner+universe จากสิทธิ์ซื้อที่เชื่อถือได้ Worker ไม่ได้รับ Tikkies user ID และไม่ตรวจ entitlement แทน Tikkies

## สัญญา request
```http
POST /v1/integrations/tikkies/overlay-links
Authorization: Bearer <TIKKIES_OVERLAY_SERVICE_KEY>
Content-Type: application/json

{"ownerRobloxId":"42","universeId":"10771081714"}
```
Response: ok, schemaVersion=2, ownerRobloxId, universeId, online, urls.map/ranking/speed/all

URL ใช้ trusted OVERLAY_PUBLIC_ORIGIN, path /overlay, query view และ fragment #readToken 43 ตัว ทุก view ใช้ token เดียวกัน ไม่มี write token ใน response

ข้อผิดพลาด: 400 invalid_overlay_claim, 401 unauthorized, 403 overlay_universe_forbidden/overlay_scope_mismatch, 413 body_too_large, 429 rate_limited, 503 integration_disabled เมื่อไม่ได้ตั้ง service key

Endpoint จำกัด body 4096 bytes และ 120 คำขอ/นาที/service key ส่ง no-store/no-referrer ไม่ log body/header/token และไม่คืน raw internal error

## เปิดใช้แมพหลัง deploy Worker
1. Deploy Worker พร้อม environment/ไฟล์คีย์ก่อน
2. ตั้ง Roblox Secret ชื่อ OVERLAY_MAP_API_KEY เท่ากับคีย์ใน JSON ของ Universe นี้ จำกัดโดเมน rbworker.aclassstore.com ตั้งทั้ง Local Secrets สำหรับ Studio และ Secret ของ experience สำหรับเกมจริงตามการใช้งาน
3. ตั้ง ServerScriptService.OverlayConfig.ScopedPublishingEnabled=true
4. ทดสอบ URL จากเกมและ Tikkies ต้องตรงกันสำหรับ owner+Universe เดียวกัน ตรวจสองเกม/สองบัญชี
5. เมื่อผ่านจึง Publish แมพและ deploy Tikkies ตามวิธีเดิม

ตอนนี้ติดตั้งตัวส่งใน Studio แต่ ScopedPublishingEnabled=false เพื่อรักษาการใช้งานเดิมก่อน deploy เปิด true แล้วจะส่ง universeId=tostring(game.GameId), ใช้ map Secret และตรวจ schema/universe ใน response ไม่มี fallback owner-only เมื่อ scoped ผิดพลาด

ห้ามใช้ config.OverlayMapApiKey literal ใน production ช่องนี้มีไว้สำหรับ server mock tests ใช้ Secret จริงตามขั้นตอนข้างบน ยังไม่มีคีย์จริงถูกสร้างหรือติดตั้งในงานนี้

## ลิงก์เดิม
ลิงก์เก่ายัง valid แต่ไม่อ่าน snapshot v2 โดยตั้งใจ เมื่อแมพเปลี่ยนเป็น v2 ลิงก์เก่าจะแสดงรอข้อมูล ผู้ใช้ต้องคัดลอก URL v2 ใหม่ การแยกเกมตามสัญญาไม่อนุญาตให้ย้าย snapshot กลับเข้า owner-only

## ไฟล์และสถานะ
Worker: src/overlay.mjs, src/server.mjs, src/config.mjs, .env.example, test/overlay-scopes.test.mjs, test/config.test.mjs
Roblox: roblox/OverlayPublisher.lua, roblox/OverlayConfig.lua, roblox/OverlayPanel.client.lua

ยังไม่ deploy VPS, ไม่ Publish แมพ และไม่ตั้งคีย์จริง ต้องทดสอบ Tikkies ร่วมกับแมพหลังตั้งค่าข้างบน

## ผลตรวจล่าสุด
- API regression 29/29 ผ่าน รวม isolation สอง universes, หลาย owners, token เดิมเมื่อขอพร้อมกัน, legacy read, credential ผิด/ข้ามเกม, read-only token, lease ไม่ถูกแย่ง, body limit, rate limit และ config validation
- Studio mock publisher ส่ง claimUniverse=10771081714 ด้วย map credential และส่ง scoped batch สำเร็จ 4 ครั้ง ไม่มี HTTP จริงในการทดสอบนี้
- ยังไม่ได้ทดสอบ Tikkies production ร่วมกับ VPS และยังไม่ได้ตั้ง Secret จริง
