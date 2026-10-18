# ติดตั้ง Direct Live + Tikkies published gift defaults

วันที่ 18 ตุลาคม 2026

## สิ่งที่ทำแล้ว

- Direct ยังคงรับของขวัญจาก Euler โดยตรง ใช้ Tikkies เพียงอ่านตารางจับคู่ที่ Admin เผยแพร่ ไม่ต้องเปิดโปรแกรม Tikkies สำหรับ Direct
- อ่าน API รอบละ60วินาที ใช้คีย์อ่านเฉพาะ Universe10771081714 ตรวจข้อมูลก่อนบันทึกลง SQLite
- เก็บ last-known-good เมื่อ network/503/404/ข้อมูลผิด;200พร้อมรายการว่างเท่านั้นจึงล้างจริง
-401/403 ระงับการสร้าง Direct session ใหม่ ทั้ง default และ override จนอ่านสำเร็จอีกครั้ง สถานะนี้อยู่ต่อหลัง restart; session เดิมไม่ถูกเปลี่ยน mapping
- Session ใหม่ snapshot mapping/version; การ reset สนามและ reconnect transport ภายใน session ไม่เปลี่ยน mapping ให้ disconnect/connect เพื่อสร้าง session ใหม่และรับ published version ล่าสุด
- ค่าที่ผู้ใช้ override ไว้ยังใช้ของตนเอง; session เก่าก่อนอัปเกรดตรึงค่าเดิมไว้
- รองรับ10key และป้องกันคอมโบเดิมข้าม reset/reconnect/restart ด้วย receipt ใน SQLite
- Roblox ส่ง Universe ตอนเปิด Direct และ giftSource=tikkies เฉพาะ receiver ของ Tikkies รอ Worker ยืนยันปิด Direct ก่อนเปลี่ยนแหล่งรับ
- เปลี่ยนเฉพาะตัวรับ ไม่เปลี่ยนค่าหรือเอฟเฟคอีเว้นในแมพ

## วิธีนำขึ้น VPS

1. ใช้ Node24.11ขึ้นไปในสาย24 และหยุด Worker เดิมก่อนสำรองฐานข้อมูล SQLite ให้ครบทั้ง database/WAL/SHM หรือใช้ SQLite backup ที่ถูกต้อง
2. แตก `bridge-api-direct-defaults-update.zip` ในโฟลเดอร์แม่ของ `bridge-api` ให้โค้ดใหม่แทนของเดิม เก็บ `.env`, `data/`, DB และคีย์เดิมของ VPS ไว้ ห้ามลบทิ้ง
3. เพิ่ม3ตัวแปรจากไฟล์ `Tikkies-Worker.env` ใน zip ส่งต่อเดิมลง `.env` ของ VPS:

```dotenv
TIKKIES_DEFAULTS_URL=https://backend.aclassstore.com/api/games/defaults/10771081714/published
TIKKIES_DEFAULTS_UNIVERSE_ID=10771081714
TIKKIES_DEFAULTS_READ_TOKEN=<คีย์อ่านจริงจากไฟล์ส่งต่อเดิม>
```

อย่าใช้ placeholder เป็นคีย์จริง ไม่เปลี่ยน BRIDGE_API_KEY,ADMIN_API_KEY,EULER_TOKEN หรือคีย์ overlay เดิม คีย์อ่านเก็บที่ Worker เท่านั้น ไม่ใส่ใน Roblox/หน้าเว็บ/Git

4. Publish เกมที่อัปเดตตัวรับแล้ว และเริ่มเซิร์ฟเวอร์ Roblox ใหม่ รุ่นเก่าไม่ส่ง Universe ID จึงเปิด Direct session ใหม่กับการตั้งค่าใหม่นี้ไม่ได้ (defaults_universe_required)
5. เปิด Worker ใหม่ด้วยขั้นตอนเดิม `./start.sh` หรือ `pm2 restart hyperrun-live-bridge --update-env` จากโฟลเดอร์ Worker migration SQLite จะเพิ่มตาราง/คอลัมน์ให้เอง ไม่ลบข้อมูลเดิม
6. ตรวจ log `defaults_refreshed` พร้อม version/mappingCount ไม่มี secret จากนั้นเชื่อม Direct ใหม่เพื่อรับ mapping versionนั้น
7. ส่งของขวัญจริงจากบัญชีทดสอบ ตรวจว่าได้สกิลตามที่จับคู่ และสลับ Direct/Tikkies หลัง disconnect โดยไม่ซ้อนกัน

แพ็กเกจใหม่ไม่มี `.env` หรือคีย์จริง ไม่มีฐานข้อมูลของคุณ ไฟล์ `.env` ในเครื่องพัฒนามีเพียงค่าที่เตรียมในเครื่องนี้ ไม่ได้อัปเดต environment บน VPS ให้อัตโนมัติ

## สถานะ API จริงที่ตรวจแล้ว

อ่านด้วย Worker HTTP client และตัวตรวจ publication/cache จริงสำเร็จ200:

- Universe:10771081714
- version:`a47dfd88-b184-40bb-8b1c-ad02e9d1827b`
- จำนวนของขวัญที่จับคู่:8รายการ (ไม่ใช่จำนวนชนิดอีเว้นที่รองรับ)

ทดสอบโดยใช้ฐานข้อมูลชั่วคราว ไม่ได้แก้/เผยแพร่ mapping ของ Admin และไม่ได้สร้าง LIVE session จริง การตรวจด้วย Python client ก่อนหน้าตอบ403แบบ HTML แต่ Node Worker client อ่านและตรวจ schema ได้สำเร็จแล้ว

## การทำงานและข้อผิดพลาด

- defaults_not_ready: ไม่มี publication ที่ผ่านการตรวจและไม่มี cache; ตรวจว่า Admin เผยแพร่แล้วและ Worker เข้าถึง API ได้
- defaults_access_denied: API ตอบ401/403; ตรวจ/ออกคีย์อ่านใหม่ให้ตรง Universe แล้วรอ refreshสำเร็จ
- defaults_universe_forbidden / defaults_universe_required: ตัวรับเกมไม่ตรง Universe หรือยังเป็นรุ่นเก่า
- previous_connection_closing: Worker ยังไม่ยืนยันปิด Direct เดิม; รอการเชื่อมต่อกลับมาแล้วลองใหม่ ไม่เปิดอีกแหล่งซ้อน
- APIว่างแบบตั้งใจ200+mappings[]: sessionใหม่จะไม่มีของขวัญที่จับคู่; sessionเก่าคง snapshotเดิม

คีย์อ่านถ้าใช้ไม่ได้จะไม่ถูกนำไปแทนคีย์เชื่อมเกม การทดสอบ Admin/runtime ของ Tikkies ยังเป็นคนละเส้นทางกับการ sync defaults ของ Direct

## ขอบเขตที่ยังต้องทำตอนใช้งานจริง

โค้ด Worker และแพตช์ Studio พร้อมแล้ว แต่ยังไม่ deploy VPS และยังไม่ Publish เกมจากงานนี้ ต้องทดสอบของขวัญ TikTok/Euler จริงหลัง deploy; การทดสอบอัตโนมัติและ GET publication ไม่ได้ใช้ของขวัญเงินจริง

## Direct Live gift list

Connect LIVE → Direct Live now shows **Gift events** (gift name → game event).
Before connecting, it reads the published defaults. While connected, it reads
that owner's actual session snapshot. Refresh reloads the list without reconnecting.
The card is hidden for Tikkies, whose users configure their own mappings.

Deploy the Worker update and publish the updated Roblox scripts together:
`LiveBridge`, `Boot.server`, and `LiveSettings`. No new environment variables.
SQLite adds name metadata columns automatically; existing mappings are preserved.
Old sessions without stored names show `Gift #ID` until a provider name is observed;
new sessions store the published names with their mapping version.
The preview endpoint `/v1/direct/gift-mappings` requires the bridge credential;
session mappings require that session's token. Credentials remain server-only.
