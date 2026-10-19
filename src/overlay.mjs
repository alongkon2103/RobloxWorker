import {TopWin} from './top-win.mjs';
import {randomBytes} from 'node:crypto';
import {Fault,constantEqual} from './store.mjs';
const token=()=>randomBytes(32).toString('base64url');
const finite=(n,min,max)=>typeof n==='number'&&Number.isFinite(n)&&n>=min&&n<=max;
const text=(s,max)=>typeof s==='string'&&s.length>0&&s.length<=max;
const id=s=>typeof s==='string'&&/^[1-9]\d{0,15}$/.test(s)&&BigInt(s)<=9007199254740991n;
const avatar=r=>r.avatarType==='bacon'?r.robloxId==='0':(r.avatarType===undefined||r.avatarType==='roblox')&&id(r.robloxId);
const eventEffects=new Set(['rainbow_cat','rocket','naruto','goku','asta','speed_boost','fly','gojo','shield','octopus','power','jump','heal']);
const tiktokCDNs=['tiktokcdn.com','tiktokcdn-us.com','tiktokcdn-eu.com','byteoversea.com','ibytedtos.com'];
function tiktokAvatar(value){
 if(typeof value!=='string'||value.length>2048||/[\s\\\u0000-\u001f\u007f]/.test(value)||!/^https:\/\/[^/?#@]+(?:[/?#]|$)/i.test(value))return null;
 try{const url=new URL(value);return url.href.length<=2048&&url.protocol==='https:'&&!url.username&&!url.password&&!url.port&&tiktokCDNs.some(host=>url.hostname===host||url.hostname.endsWith('.'+host))?url.href:null;}catch{return null;}
}
export function validateSnapshot(s,hasRoute=false){
 if(!s||!text(s.round,160)||!['Lobby','Countdown','Running','Results'].includes(s.phase)||!finite(s.laps,1,100)||!finite(s.metersPerStud,.001,10)||!Array.isArray(s.racers)||s.racers.length>100)throw new Fault('invalid_overlay');
 if(s.route!==undefined){
  const r=s.route;
  if(!r||!text(r.version,100)||!finite(r.length,1,1e8)||!Array.isArray(r.points)||r.points.length<4||r.points.length>2048||r.points.some(p=>!Array.isArray(p)||p.length!==2||p.some(n=>!finite(n,-1e7,1e7))))throw new Fault('invalid_route');
 }else if(!hasRoute)throw new Fault('route_required',409);
 const seen=new Set();
 for(const r of s.racers){
  if(!r||!text(r.id,200)||seen.has(r.id)||!avatar(r)||!(typeof r.name==='string'&&Array.from(r.name).length>0&&Array.from(r.name).length<=80)||!finite(r.distance,-1e5,1e10)||!finite(r.speed,0,1500)||!finite(r.rank,0,100)||!['Lobby','Waiting','Queued','Countdown','Running','Finished','DNF'].includes(r.state)||!Array.isArray(r.effects)||r.effects.length>32)throw new Fault('invalid_racer');
  seen.add(r.id);
  for(const e of r.effects)if(!e||!text(e.key,64)||!finite(e.remaining,0,1e9)||!finite(e.tier,-1e6,1e6))throw new Fault('invalid_effect');
 }
 const events=s.events===undefined?[]:s.events;
 if(!Array.isArray(events)||events.length>30)throw new Fault('invalid_overlay_event');
 for(const e of events)if(!e||!text(e.id,200)||!avatar(e)||!text(e.tiktokDisplayName,100)||typeof e.tiktokUsername!=='string'||e.tiktokUsername.length>100||!eventEffects.has(e.effectKey)||!Number.isInteger(e.count)||e.count<1||e.count>10000||!Number.isSafeInteger(e.createdAt)||e.createdAt<=0||(e.tiktokAvatarUrl!==undefined&&!tiktokAvatar(e.tiktokAvatarUrl)))throw new Fault('invalid_overlay_event');
 // Copy only the public presentation fields, never forward arbitrary publisher data.
 return {round:s.round,phase:s.phase,laps:s.laps,metersPerStud:s.metersPerStud,
  ...(s.route?{route:{version:s.route.version,length:s.route.length,points:s.route.points}}:{}),
  events:events.map(e=>({id:e.id,robloxId:e.robloxId,...(e.avatarType!==undefined?{avatarType:e.avatarType}:{}),tiktokDisplayName:e.tiktokDisplayName,tiktokUsername:e.tiktokUsername,effectKey:e.effectKey,count:e.count,createdAt:e.createdAt,...(e.tiktokAvatarUrl!==undefined?{tiktokAvatarUrl:tiktokAvatar(e.tiktokAvatarUrl)}:{})})),
  racers:s.racers.map(r=>{const tiktokAvatarUrl=tiktokAvatar(r.tiktokAvatarUrl);return {id:r.id,robloxId:r.robloxId,...(r.avatarType!==undefined?{avatarType:r.avatarType}:{}),name:r.name,distance:r.distance,speed:r.speed,topSpeed:r.speed,rank:r.rank,state:r.state,...(tiktokAvatarUrl?{tiktokAvatarUrl}:{}),effects:r.effects.map(e=>({key:e.key,remaining:e.remaining,tier:e.tier}))};})};
}
export class Overlays{
 constructor(db,now=Date.now){
  this.db=db;this.now=now;this.live=new Map();this.topWin=new TopWin(db,now);
  db.exec('CREATE TABLE IF NOT EXISTS overlay_profiles(owner_id TEXT PRIMARY KEY,read_token TEXT UNIQUE NOT NULL)');
  db.exec('CREATE TABLE IF NOT EXISTS overlay_profiles_v2(universe_id TEXT NOT NULL,owner_id TEXT NOT NULL,read_token TEXT UNIQUE NOT NULL,PRIMARY KEY(universe_id,owner_id))');
 }
 scope(owner,universe){return universe===undefined?'legacy:'+owner:'game:'+universe+':'+owner;}
 profile(owner,universe){
  if(!id(owner)||(universe!==undefined&&!id(universe)))throw new Fault('invalid_overlay_claim');
  let p;
  if(universe===undefined){
   this.db.prepare('INSERT INTO overlay_profiles(owner_id,read_token) VALUES(?,?) ON CONFLICT(owner_id) DO NOTHING').run(owner,token());
   p=this.db.prepare('SELECT read_token FROM overlay_profiles WHERE owner_id=?').get(owner);
  }else{
   this.db.prepare('INSERT INTO overlay_profiles_v2(universe_id,owner_id,read_token) VALUES(?,?,?) ON CONFLICT(universe_id,owner_id) DO NOTHING').run(universe,owner,token());
   p=this.db.prepare('SELECT read_token FROM overlay_profiles_v2 WHERE universe_id=? AND owner_id=?').get(universe,owner);
  }
  const l=this.live.get(this.scope(owner,universe));
  return {readToken:p.read_token,online:!!l&&l.lastPublish!==undefined&&this.now()-l.lastPublish<5000};
 }
 claim(b){
  if(!b||!id(b.ownerRobloxId)||(b.universeId!==undefined&&!id(b.universeId))||!text(b.jobId,128)||!text(b.claimId,128))throw new Fault('invalid_overlay_claim');
  const now=this.now();this.sweep();const scope=this.scope(b.ownerRobloxId,b.universeId),current=this.live.get(scope);
  if(current&&now-current.seen<45000&&(current.jobId!==b.jobId||current.claimId!==b.claimId))throw new Fault('overlay_owner_busy',409);
  const p=this.profile(b.ownerRobloxId,b.universeId);
  if(!current||now-current.seen>=45000||current.jobId!==b.jobId||current.claimId!==b.claimId){
   if(!current&&this.live.size>=200)throw new Fault('overlay_capacity',429);
   this.live.set(scope,{universeId:b.universeId,jobId:b.jobId,claimId:b.claimId,writeToken:token(),seen:now,sequence:0,state:null,eventsAfter:now});
  }
  const l=this.live.get(scope);l.seen=now;
  return {readToken:p.readToken,writeToken:l.writeToken,interval:1,...(b.universeId?{schemaVersion:2,universeId:b.universeId}:{})};
 }
 publish(key,b,expectedUniverse){
  let l;for(const entry of this.live.values())if(constantEqual(entry.writeToken,key)){l=entry;break;}
  if(!l||this.now()-l.seen>=45000)throw new Fault('overlay_lease_expired',401);
  // Batch credentials can only publish their own universe; empty string is legacy-only.
  if(expectedUniverse!==undefined&&(l.universeId??'')!==expectedUniverse)throw new Fault('overlay_scope_mismatch',403);
  if(b?.universeId!==undefined&&b.universeId!==l.universeId)throw new Fault('overlay_scope_mismatch',403);
  if(l.lastPublish!==undefined&&this.now()-l.lastPublish<400)throw new Fault('overlay_rate_limited',429);
  if(!Number.isSafeInteger(b?.sequence)||b.sequence<=l.sequence)throw new Fault('stale_overlay_snapshot',409);
  const state=validateSnapshot(b.snapshot,!!l.state?.route),previous=l.state;
  if(l.lastPublish!==undefined&&this.now()-l.lastPublish>=5000)l.eventsAfter=this.now();
  l.state={...state,route:state.route??previous.route};l.sequence=b.sequence;l.seen=this.now();l.lastPublish=l.seen;
  return {ok:true};
 }
 release(key){
  for(const [scope,l]of this.live)if(constantEqual(l.writeToken,key)){this.live.delete(scope);return {ok:true};}
  throw new Fault('overlay_lease_expired',401);
 }
 read(key){
  if(typeof key!=='string'||!/^[A-Za-z0-9_-]{43}$/.test(key))throw new Fault('unauthorized',401);
  const scoped=this.db.prepare('SELECT owner_id,universe_id FROM overlay_profiles_v2 WHERE read_token=?').get(key);
  const p=scoped??this.db.prepare('SELECT owner_id FROM overlay_profiles WHERE read_token=?').get(key);if(!p)throw new Fault('unauthorized',401);
  const l=this.live.get(this.scope(p.owner_id,p.universe_id)),age=l?this.now()-l.seen:Infinity;
  const online=!!l&&l.lastPublish!==undefined&&this.now()-l.lastPublish<5000;
  const snapshot=l?.state?{...l.state,events:online?(l.state.events??[]).filter(e=>e.createdAt>=l.eventsAfter&&this.now()-e.createdAt<=12000):[]}:null;
  return {topWin:this.topWin.board(p.universe_id??'',p.owner_id),online,sequence:l?.sequence??0,ageMs:Number.isFinite(age)?age:null,snapshot};
 }
 sweep(){for(const [key,l]of this.live)if(this.now()-l.seen>300000)this.live.delete(key);}
}
