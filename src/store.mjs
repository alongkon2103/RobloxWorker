import {LIKES_PER_BOOST} from './direct-rules.mjs';
import {DatabaseSync} from 'node:sqlite';
import {createHash,randomBytes,randomUUID,timingSafeEqual} from 'node:crypto';
import {mkdirSync} from 'node:fs';
import {dirname} from 'node:path';
export class Fault extends Error {constructor(code,status=400){super(code);this.code=code;this.status=status;}}
export const digest=x=>createHash('sha256').update(x).digest('hex');
export const constantEqual=(a,b)=>typeof a==='string'&&typeof b==='string'&&timingSafeEqual(Buffer.from(digest(a)),Buffer.from(digest(b)));
const terminal=['closed','expired'];
export class Store {
 constructor(file,{now=Date.now,eventTTL=120000,leaseMs=20000,maxQueue=1000,sessionTTL=90000,maxSessions=200,maxInbox=10000,maxActors=100}={}){
  this.now=now;this.eventTTL=eventTTL;this.leaseMs=leaseMs;this.maxQueue=maxQueue;this.sessionTTL=sessionTTL;this.maxSessions=maxSessions;this.maxInbox=maxInbox;this.maxActors=Math.min(100,maxActors);
  if(file!==':memory:')mkdirSync(dirname(file),{recursive:true,mode:0o700});
  this.db=new DatabaseSync(file);this.db.exec(`PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; PRAGMA busy_timeout=5000; PRAGMA foreign_keys=ON;
   CREATE TABLE IF NOT EXISTS sessions(id TEXT PRIMARY KEY,token_hash TEXT NOT NULL,owner_id TEXT NOT NULL,job_id TEXT NOT NULL,tiktok TEXT NOT NULL,provider TEXT NOT NULL,status TEXT NOT NULL,run_id TEXT NOT NULL,generation INTEGER NOT NULL,seen_at INTEGER NOT NULL,created_at INTEGER NOT NULL,retry_at INTEGER NOT NULL DEFAULT 0,attempts INTEGER NOT NULL DEFAULT 0,last_code INTEGER,gift_map TEXT);
   CREATE UNIQUE INDEX IF NOT EXISTS active_owner ON sessions(owner_id) WHERE status NOT IN ('closed','expired');
   CREATE UNIQUE INDEX IF NOT EXISTS active_live ON sessions(tiktok) WHERE status NOT IN ('closed','expired');
   CREATE TABLE IF NOT EXISTS events(seq INTEGER PRIMARY KEY AUTOINCREMENT,session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,generation INTEGER NOT NULL,event_id TEXT NOT NULL,payload TEXT NOT NULL,expires_at INTEGER NOT NULL,status TEXT NOT NULL DEFAULT 'pending',receipt TEXT,lease_until INTEGER,UNIQUE(session_id,generation,event_id));
   CREATE INDEX IF NOT EXISTS delivery ON events(session_id,generation,status,seq);
   CREATE TABLE IF NOT EXISTS actors(session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,generation INTEGER NOT NULL,actor_key TEXT NOT NULL,payload TEXT NOT NULL,PRIMARY KEY(session_id,generation,actor_key));
   CREATE TABLE IF NOT EXISTS controls(session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,request_id TEXT NOT NULL,response TEXT NOT NULL,created_at INTEGER NOT NULL,PRIMARY KEY(session_id,request_id));
   CREATE TABLE IF NOT EXISTS gifts(session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,gift_id TEXT NOT NULL,name TEXT NOT NULL,last_seen INTEGER NOT NULL,PRIMARY KEY(session_id,gift_id));
   CREATE TABLE IF NOT EXISTS inbox(seq INTEGER PRIMARY KEY AUTOINCREMENT,session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,generation INTEGER NOT NULL,source_id TEXT NOT NULL,payload TEXT NOT NULL,expires_at INTEGER NOT NULL,UNIQUE(session_id,generation,source_id));
   CREATE INDEX IF NOT EXISTS inbox_pending ON inbox(session_id,generation,seq);
   CREATE TABLE IF NOT EXISTS sources(session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,generation INTEGER NOT NULL,source_id TEXT NOT NULL,seen_at INTEGER NOT NULL,PRIMARY KEY(session_id,generation,source_id));
  `);
  this.db.exec(`CREATE TABLE IF NOT EXISTS defaults_access(universe_id TEXT PRIMARY KEY,denied INTEGER NOT NULL);
   CREATE TABLE IF NOT EXISTS published_gift_defaults(universe_id TEXT PRIMARY KEY,version TEXT NOT NULL,gift_map TEXT NOT NULL,updated_at TEXT NOT NULL,fetched_at INTEGER NOT NULL);
   CREATE TABLE IF NOT EXISTS gift_receipts(universe_id TEXT NOT NULL,streamer TEXT NOT NULL,source_hash TEXT NOT NULL,seen_at INTEGER NOT NULL,PRIMARY KEY(universe_id,streamer,source_hash));`);
  this.db.exec(`CREATE TABLE IF NOT EXISTS direct_social_progress(session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,generation INTEGER NOT NULL,actor_key TEXT NOT NULL,likes INTEGER NOT NULL,PRIMARY KEY(session_id,generation,actor_key));
   CREATE TABLE IF NOT EXISTS direct_social_receipts(universe_id TEXT NOT NULL,streamer TEXT NOT NULL,source_hash TEXT NOT NULL,seen_at INTEGER NOT NULL,PRIMARY KEY(universe_id,streamer,source_hash));`);
  const columns=new Set(this.db.prepare('PRAGMA table_info(sessions)').all().map(c=>c.name));
  if(!this.db.prepare('PRAGMA table_info(published_gift_defaults)').all().some(c=>c.name==='gift_names'))this.db.exec("ALTER TABLE published_gift_defaults ADD COLUMN gift_names TEXT NOT NULL DEFAULT '{}'");
  for(const [name,sql]of [['gift_names',"TEXT NOT NULL DEFAULT '{}'"],['universe_id',"TEXT NOT NULL DEFAULT ''"],['gift_map_version','TEXT'],['gift_map_source','TEXT']])if(!columns.has(name))this.db.exec(`ALTER TABLE sessions ADD COLUMN ${name} ${sql}`);
  if(!this.db.prepare('PRAGMA table_info(sessions)').all().some(c=>c.name==='join_mode'))this.db.exec("ALTER TABLE sessions ADD COLUMN join_mode TEXT NOT NULL DEFAULT 'both'");
  // Keep authenticated channel/job bindings after disposable session rows are pruned.
  this.db.exec(`CREATE TABLE IF NOT EXISTS direct_result_bindings(universe_id TEXT NOT NULL,owner_id TEXT NOT NULL,job_id TEXT NOT NULL,channel TEXT NOT NULL,PRIMARY KEY(universe_id,owner_id,job_id,channel));
   INSERT OR IGNORE INTO direct_result_bindings SELECT universe_id,owner_id,job_id,tiktok FROM sessions WHERE provider='direct';`);
 }
 tx(fn){this.db.exec('BEGIN IMMEDIATE');try{const result=fn();this.db.exec('COMMIT');return result;}catch(e){this.db.exec('ROLLBACK');throw e;}}
 get(id){const s=this.db.prepare('SELECT * FROM sessions WHERE id=?').get(id);if(!s)throw new Fault('session_not_found',404);return s;}
 public(s){return {id:s.id,ownerRobloxId:s.owner_id,jobId:s.job_id,tiktokUsername:s.tiktok,provider:s.provider,universeId:s.universe_id,giftMapVersion:s.gift_map_version,giftMapSource:s.gift_map_source??(s.gift_map===null?'static':'override'),joinMode:s.join_mode,status:s.status,runId:s.run_id,generation:s.generation,lastCode:s.last_code,queueDepth:this.db.prepare("SELECT COUNT(*) AS n FROM events WHERE session_id=? AND generation=? AND status='pending' AND expires_at>?").get(s.id,s.generation,this.now()).n};}
 create({ownerRobloxId,jobId,tiktokUsername,provider='direct',giftMap=null,giftNames={},joinMode='both',universeId='',giftMapVersion=null,giftMapSource=giftMap===null?'static':'override'}){
  return this.tx(()=>{
   this.expire();
   if(this.db.prepare("SELECT COUNT(*) AS n FROM sessions WHERE status NOT IN ('closed','expired')").get().n>=this.maxSessions)throw new Fault('session_capacity',429);
   if(this.db.prepare("SELECT id FROM sessions WHERE owner_id=? AND status NOT IN ('closed','expired')").get(ownerRobloxId))throw new Fault('owner_busy',409);
   if(this.db.prepare("SELECT id FROM sessions WHERE tiktok=? AND status NOT IN ('closed','expired')").get(tiktokUsername))throw new Fault('live_busy',409);
   const id=randomUUID(),token=randomBytes(32).toString('base64url'),runId=randomUUID(),now=this.now();
   this.db.prepare('INSERT INTO sessions(id,token_hash,owner_id,job_id,tiktok,provider,status,run_id,generation,seen_at,created_at,gift_map,join_mode) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)').run(id,digest(token),ownerRobloxId,jobId,tiktokUsername,provider,provider==='direct'?'queued':'live',runId,1,now,now,giftMap===null?null:JSON.stringify(giftMap),joinMode);
   this.db.prepare('UPDATE sessions SET universe_id=?,gift_map_version=?,gift_map_source=?,gift_names=? WHERE id=?').run(universeId,giftMapVersion,giftMapSource,JSON.stringify(giftNames),id);
   if(provider==='direct')this.db.prepare('INSERT OR IGNORE INTO direct_result_bindings VALUES(?,?,?,?)').run(universeId,ownerRobloxId,jobId,tiktokUsername);
   return {...this.public(this.get(id)),token};
  });
 }
 setJoinMode(id,mode){if(!['at','plain','both'].includes(mode))throw new Fault('invalid_join_mode');this.heartbeat(id);this.db.prepare('UPDATE sessions SET join_mode=? WHERE id=?').run(mode,id);return this.public(this.get(id));}
 authenticate(id,token){const s=this.get(id);if(typeof token!=='string'||!constantEqual(s.token_hash,digest(token)))throw new Fault('unauthorized',401);return s;}
 heartbeat(id){if(terminal.includes(this.get(id).status))throw new Fault('session_inactive',410);this.db.prepare('UPDATE sessions SET seen_at=? WHERE id=?').run(this.now(),id);return this.public(this.get(id));}
 reset(id,requestId=randomUUID()){return this.tx(()=>{const s=this.get(id);if(terminal.includes(s.status))throw new Fault('session_inactive',410);const saved=this.db.prepare('SELECT response FROM controls WHERE session_id=? AND request_id=?').get(id,requestId);if(saved)return JSON.parse(saved.response);this.db.prepare('UPDATE sessions SET generation=generation+1,run_id=?,seen_at=? WHERE id=?').run(randomUUID(),this.now(),id);for(const table of ['events','actors','sources','inbox','direct_social_progress'])this.db.prepare(`DELETE FROM ${table} WHERE session_id=?`).run(id);const response=this.public(this.get(id));this.db.prepare('INSERT INTO controls VALUES(?,?,?,?)').run(id,requestId,JSON.stringify(response),this.now());this.db.prepare('DELETE FROM controls WHERE session_id=? AND request_id NOT IN (SELECT request_id FROM controls WHERE session_id=? ORDER BY created_at DESC LIMIT 128)').run(id,id);return response;});}
 stop(id,status='closed'){this.db.prepare('UPDATE sessions SET status=? WHERE id=?').run(status,id);for(const table of ['events','actors','sources','inbox','direct_social_progress'])this.db.prepare(`DELETE FROM ${table} WHERE session_id=?`).run(id);}
 expire(){const stale=this.db.prepare("SELECT id FROM sessions WHERE status NOT IN ('closed','expired') AND seen_at<?").all(this.now()-this.sessionTTL);for(const s of stale)this.stop(s.id,'expired');return stale;}
 list(){return this.db.prepare("SELECT * FROM sessions WHERE status NOT IN ('closed','expired') ORDER BY created_at,rowid").all();}
 candidates(){return this.db.prepare("SELECT * FROM sessions WHERE provider='direct' AND status IN ('queued','retrying','offline') AND retry_at<=? ORDER BY retry_at,created_at,rowid").all(this.now());}
 status(id,status,code=null,retryAt=0,attempts=0){this.db.prepare("UPDATE sessions SET status=?,last_code=?,retry_at=?,attempts=? WHERE id=? AND status NOT IN ('closed','expired')").run(status,code,retryAt,attempts,id);}
 recover(){this.db.prepare("UPDATE sessions SET status='queued',retry_at=0 WHERE provider='direct' AND status IN ('connecting','live','error')").run();this.expire();}
 actor(id,generation,key){const a=this.db.prepare('SELECT payload FROM actors WHERE session_id=? AND generation=? AND actor_key=?').get(id,generation,key);return a?JSON.parse(a.payload):null;}
 seen(id,generation,source){return !!this.db.prepare('SELECT 1 FROM sources WHERE session_id=? AND generation=? AND source_id=?').get(id,generation,source);}
 enqueue(id,generation,eventId,payload,{actor,sourceId=eventId,giftIdentity=null}={}){
  return this.tx(()=>this.enqueueInside(id,generation,eventId,payload,{actor,sourceId,giftIdentity}));
 }
 enqueueInside(id,generation,eventId,payload,{actor,sourceId=eventId,giftIdentity=null}={}){
   const s=this.get(id);if(terminal.includes(s.status)||s.generation!==generation)return false;
   if(this.seen(id,generation,sourceId))return false;
   if(actor&&!this.actor(id,generation,actor.actorKey)&&this.actorCount(id,generation)>=this.maxActors)return false;
   if(giftIdentity&&this.db.prepare('SELECT 1 FROM gift_receipts WHERE universe_id=? AND streamer=? AND source_hash=?').get(s.universe_id,s.tiktok,giftIdentity))return false;
   const depth=this.db.prepare("SELECT COUNT(*) AS n FROM events WHERE session_id=? AND generation=? AND status='pending' AND expires_at>?").get(id,generation,this.now()).n;
   if(depth>=this.maxQueue)throw new Fault('queue_full',429);
   const binding=payload.actorKey?this.actor(id,generation,payload.actorKey):null;
   const context={...payload,...(payload.eventType!=="join"&&binding?{joinEventId:binding.joinEventId}:{}),eventId,ownerRobloxId:s.owner_id,runId:s.run_id,generation,liveSessionId:id,namespace:s.provider==='direct'?'live':'tikkies'};
   this.db.prepare('INSERT INTO events(session_id,generation,event_id,payload,expires_at) VALUES(?,?,?,?,?)').run(id,generation,eventId,JSON.stringify(context),this.now()+this.eventTTL);
   if(actor)actor={...actor,joinEventId:eventId};
   if(actor)this.db.prepare('INSERT INTO actors(session_id,generation,actor_key,payload) VALUES(?,?,?,?) ON CONFLICT DO UPDATE SET payload=excluded.payload').run(id,generation,actor.actorKey,JSON.stringify(actor));
   this.db.prepare('INSERT INTO sources VALUES(?,?,?,?)').run(id,generation,sourceId,this.now());
   if(giftIdentity)this.db.prepare('INSERT INTO gift_receipts VALUES(?,?,?,?)').run(s.universe_id,s.tiktok,giftIdentity,this.now());return true;
 }
 socialEvent(id,generation,actor,sourceId,identity,type,count){return this.tx(()=>{
  const s=this.get(id);if(s.provider!=='direct'||terminal.includes(s.status)||s.generation!==generation)return false;
  if(this.seen(id,generation,sourceId)||this.db.prepare('SELECT 1 FROM direct_social_receipts WHERE universe_id=? AND streamer=? AND source_hash=?').get(s.universe_id,s.tiktok,identity))return false;
  const old=this.db.prepare('SELECT likes FROM direct_social_progress WHERE session_id=? AND generation=? AND actor_key=?').get(id,generation,actor.actorKey)?.likes??0;
  const total=type==='like'?old+count:0,awards=type==='like'?Math.floor(total/LIKES_PER_BOOST):1;
  if(awards){
   const accepted=this.enqueueInside(id,generation,'social:'+identity,{...actor,eventType:type,effects:[{key:type==='like'?'speed_boost':'fly',value:1,count:awards}]},{sourceId});
   if(!accepted)return false;
  }else this.db.prepare('INSERT INTO sources VALUES(?,?,?,?)').run(id,generation,sourceId,this.now());
  if(type==='like')this.db.prepare('INSERT INTO direct_social_progress VALUES(?,?,?,?) ON CONFLICT DO UPDATE SET likes=excluded.likes').run(id,generation,actor.actorKey,total%LIKES_PER_BOOST);
  this.db.prepare('INSERT INTO direct_social_receipts VALUES(?,?,?,?)').run(s.universe_id,s.tiktok,identity,this.now());return true;
 });}
 poll(id){return this.tx(()=>{
  const s=this.get(id);if(terminal.includes(s.status))throw new Fault('session_inactive',410);
  this.heartbeat(id);const now=this.now();
  this.expireEvents(id);
  const e=this.db.prepare("SELECT * FROM events WHERE session_id=? AND generation=? AND status='pending' ORDER BY seq LIMIT 1").get(id,s.generation);
  if(!e||e.lease_until>now)return null;
  const receipt=randomBytes(24).toString('base64url');this.db.prepare('UPDATE events SET receipt=?,lease_until=? WHERE seq=?').run(receipt,now+this.leaseMs,e.seq);
  return {...JSON.parse(e.payload),receipt,expiresAt:new Date(e.expires_at).toISOString(),leaseUntil:new Date(now+this.leaseMs).toISOString()};
 });}
 ack(id,eventId,receipt,{success=true,retry=true}={}){return this.tx(()=>{
  const s=this.get(id);const e=this.db.prepare('SELECT * FROM events WHERE session_id=? AND generation=? AND event_id=?').get(id,s.generation,eventId);
  if(!e||!constantEqual(e.receipt,receipt))throw new Fault('invalid_receipt',409);
  if(e.status==='acked'||e.status==='failed')return {duplicate:true};
  if(e.expires_at<=this.now()||e.lease_until<=this.now())throw new Fault('receipt_expired',409);
  if(success||!retry){this.db.prepare('UPDATE events SET status=? WHERE seq=?').run(success?'acked':'failed',e.seq);if(!success&&JSON.parse(e.payload).eventType==='join')this.invalidateJoin(e);}
  else this.db.prepare('UPDATE events SET receipt=NULL,lease_until=NULL WHERE seq=?').run(e.seq);
  return {duplicate:false};
 });}
 invalidateJoin(event){
  const payload=JSON.parse(event.payload);if(!payload.actorKey)return;
  this.db.prepare("DELETE FROM actors WHERE session_id=? AND generation=? AND actor_key=? AND json_extract(payload,'$.joinEventId')=?").run(event.session_id,event.generation,payload.actorKey,event.event_id);
  this.db.prepare("UPDATE events SET status='failed',receipt=NULL,lease_until=NULL WHERE session_id=? AND generation=? AND status='pending' AND json_extract(payload,'$.joinEventId')=?").run(event.session_id,event.generation,event.event_id);
 }
 expireEvents(id){
  const where=(id?'session_id=? AND ':'')+"status='pending' AND expires_at<=?";
  const args=id?[id,this.now()]:[this.now()];
  const joins=this.db.prepare("SELECT * FROM events WHERE "+where+" AND json_extract(payload,'$.eventType')='join'").all(...args);
  for(const e of joins)this.invalidateJoin(e);
  this.db.prepare("UPDATE events SET status='expired',receipt=NULL,lease_until=NULL WHERE "+where).run(...args);
 }
 prune(){this.tx(()=>{
  this.expireEvents();this.db.prepare('DELETE FROM inbox WHERE expires_at<=?').run(this.now());const cut=this.now()-3600000;
  this.db.prepare("DELETE FROM events AS e WHERE expires_at<? AND status!='pending' AND NOT (json_extract(payload,'$.eventType')='join' AND (EXISTS(SELECT 1 FROM actors a WHERE a.session_id=e.session_id AND a.generation=e.generation AND json_extract(a.payload,'$.joinEventId')=e.event_id) OR EXISTS(SELECT 1 FROM events d WHERE d.session_id=e.session_id AND d.generation=e.generation AND d.status='pending' AND json_extract(d.payload,'$.joinEventId')=e.event_id)))").run(cut);
  this.db.prepare('DELETE FROM sources WHERE seen_at<?').run(cut);this.db.prepare('DELETE FROM direct_social_receipts WHERE seen_at<?').run(cut);this.db.prepare("DELETE FROM sessions WHERE status IN ('closed','expired','error') AND seen_at<?").run(this.now()-86400000);
 });}

 inboxDepth(id){return this.db.prepare('SELECT COUNT(*) AS n FROM inbox WHERE session_id=? AND expires_at>?').get(id,this.now()).n;}
 ingest(id,generation,messages){return this.tx(()=>{
  const s=this.get(id);if(terminal.includes(s.status)||s.generation!==generation)return 0;
  const depth=this.inboxDepth(id);let added=0;
  for(const message of messages){
   if(!message||this.seen(id,generation,message.sourceId))continue;
   if(this.db.prepare('SELECT 1 FROM inbox WHERE session_id=? AND generation=? AND source_id=?').get(id,generation,message.sourceId))continue;
   if(depth+added>=this.maxInbox)throw new Fault('inbox_full',429);
   this.db.prepare('INSERT INTO inbox(session_id,generation,source_id,payload,expires_at) VALUES(?,?,?,?,?)').run(id,generation,message.sourceId,JSON.stringify(message),this.now()+this.eventTTL);added++;
  }
  return added;
 });}
 inbox(id){const s=this.get(id);const row=this.db.prepare('SELECT * FROM inbox WHERE session_id=? AND generation=? AND expires_at>? ORDER BY seq LIMIT 1').get(id,s.generation,this.now());return row?{...row,...JSON.parse(row.payload),generation:row.generation}:null;}
 finishInbox(seq){this.db.prepare('DELETE FROM inbox WHERE seq=?').run(seq);}
 actorCount(id,generation){return this.db.prepare('SELECT COUNT(*) AS n FROM actors WHERE session_id=? AND generation=?').get(id,generation).n;}
 freezeLegacyGiftMaps(map,universeId){this.tx(()=>{this.db.prepare("UPDATE sessions SET gift_map=?,gift_map_source='static' WHERE provider='direct' AND gift_map IS NULL").run(JSON.stringify(map));this.db.prepare("UPDATE sessions SET universe_id=? WHERE provider='direct' AND universe_id=''").run(universeId);});}
 cachedDefaults(universe){const row=this.db.prepare('SELECT * FROM published_gift_defaults WHERE universe_id=?').get(universe);return row?{giftMap:JSON.parse(row.gift_map),giftNames:JSON.parse(row.gift_names),giftMapVersion:row.version,updatedAt:row.updated_at}:null;}
 defaultsDenied(universe){return this.db.prepare('SELECT denied FROM defaults_access WHERE universe_id=?').get(universe)?.denied===1;}
 setDefaultsDenied(universe,denied){this.db.prepare('INSERT INTO defaults_access VALUES(?,?) ON CONFLICT(universe_id) DO UPDATE SET denied=excluded.denied').run(universe,denied?1:0);}
 saveDefaults(universe,data){return this.tx(()=>{this.db.prepare('INSERT INTO published_gift_defaults(universe_id,version,gift_map,updated_at,fetched_at,gift_names) VALUES(?,?,?,?,?,?) ON CONFLICT(universe_id) DO UPDATE SET version=excluded.version,gift_map=excluded.gift_map,updated_at=excluded.updated_at,fetched_at=excluded.fetched_at,gift_names=excluded.gift_names').run(universe,data.giftMapVersion,JSON.stringify(data.giftMap),data.updatedAt,this.now(),JSON.stringify(data.giftNames??{}));this.setDefaultsDenied(universe,false);});}
 giftMappings(id,fallback={}){const s=this.get(id),names=JSON.parse(s.gift_names);const observed=new Map(this.gifts(id).map(g=>[g.giftId,g.name]));return Object.entries(this.effectiveGiftMap(id,fallback)).map(([giftId,e])=>({giftId,giftName:names[giftId]||observed.get(giftId)||`Gift #${giftId}`,eventKey:e.key}));}
 effectiveGiftMap(id,fallback={}){const s=this.get(id);return s.gift_map===null?fallback:JSON.parse(s.gift_map);}
 setGiftMap(id,map){this.db.prepare("UPDATE sessions SET gift_map=?,gift_map_source='override',gift_map_version=NULL,gift_names='{}' WHERE id=?").run(JSON.stringify(map),id);}
 catalogue(id,messages){this.tx(()=>{for(const m of messages){if(m.type==='WebcastGiftMessage'&&m.data.giftId)this.db.prepare('INSERT INTO gifts VALUES(?,?,?,?) ON CONFLICT DO UPDATE SET name=excluded.name,last_seen=excluded.last_seen').run(id,m.data.giftId,m.data.giftName||m.data.giftId,this.now());}this.db.prepare('DELETE FROM gifts WHERE session_id=? AND gift_id NOT IN (SELECT gift_id FROM gifts WHERE session_id=? ORDER BY last_seen DESC LIMIT 200)').run(id,id);});}
 gifts(id){return this.db.prepare('SELECT gift_id AS giftId,name,last_seen AS lastSeenAt FROM gifts WHERE session_id=? ORDER BY last_seen DESC').all(id);}
 close(){this.db.close();}
}
