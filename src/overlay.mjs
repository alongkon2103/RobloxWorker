import {randomBytes} from 'node:crypto';
import {Fault,constantEqual} from './store.mjs';
const token=()=>randomBytes(32).toString('base64url');
const finite=(n,min,max)=>typeof n==='number'&&Number.isFinite(n)&&n>=min&&n<=max;
const text=(s,max)=>typeof s==='string'&&s.length>0&&s.length<=max;
const id=s=>typeof s==='string'&&/^[1-9]\d{0,15}$/.test(s)&&BigInt(s)<=9007199254740991n;
export function validateSnapshot(s,hasRoute=false){
 if(!s||!text(s.round,160)||!['Lobby','Countdown','Running','Results'].includes(s.phase)||!finite(s.laps,1,100)||!finite(s.metersPerStud,.001,10)||!Array.isArray(s.racers)||s.racers.length>100)throw new Fault('invalid_overlay');
 if(s.route!==undefined){
  const r=s.route;
  if(!r||!text(r.version,100)||!finite(r.length,1,1e8)||!Array.isArray(r.points)||r.points.length<4||r.points.length>2048||r.points.some(p=>!Array.isArray(p)||p.length!==2||p.some(n=>!finite(n,-1e7,1e7))))throw new Fault('invalid_route');
 }else if(!hasRoute)throw new Fault('route_required',409);
 const seen=new Set();
 for(const r of s.racers){
  if(!r||!text(r.id,200)||seen.has(r.id)||!id(r.robloxId)||!text(r.name,80)||!finite(r.distance,-1e5,1e10)||!finite(r.speed,0,1500)||!finite(r.topSpeed,0,1500)||!finite(r.rank,0,100)||!['Lobby','Waiting','Queued','Countdown','Running','Finished','DNF'].includes(r.state)||!Array.isArray(r.effects)||r.effects.length>32)throw new Fault('invalid_racer');
  seen.add(r.id);
  for(const e of r.effects)if(!e||!text(e.key,64)||!finite(e.remaining,0,1e9)||!finite(e.tier,-1e6,1e6))throw new Fault('invalid_effect');
 }
 // Copy only the public presentation fields, never forward arbitrary publisher data.
 return {round:s.round,phase:s.phase,laps:s.laps,metersPerStud:s.metersPerStud,
  ...(s.route?{route:{version:s.route.version,length:s.route.length,points:s.route.points}}:{}),
  racers:s.racers.map(r=>({id:r.id,robloxId:r.robloxId,name:r.name,distance:r.distance,speed:r.speed,topSpeed:r.topSpeed,rank:r.rank,state:r.state,effects:r.effects.map(e=>({key:e.key,remaining:e.remaining,tier:e.tier}))}))};
}
export class Overlays{
 constructor(db,now=Date.now){
  this.db=db;this.now=now;this.live=new Map();
  db.exec('CREATE TABLE IF NOT EXISTS overlay_profiles(owner_id TEXT PRIMARY KEY,read_token TEXT UNIQUE NOT NULL)');
 }
 claim(b){
  if(!b||!id(b.ownerRobloxId)||!text(b.jobId,128)||!text(b.claimId,128))throw new Fault('invalid_overlay_claim');
  const now=this.now();this.sweep();const current=this.live.get(b.ownerRobloxId);
  if(current&&now-current.seen<45000&&(current.jobId!==b.jobId||current.claimId!==b.claimId))throw new Fault('overlay_owner_busy',409);
  let p=this.db.prepare('SELECT read_token FROM overlay_profiles WHERE owner_id=?').get(b.ownerRobloxId);
  if(!p){p={read_token:token()};this.db.prepare('INSERT INTO overlay_profiles VALUES(?,?)').run(b.ownerRobloxId,p.read_token);}
  if(!current||now-current.seen>=45000||current.jobId!==b.jobId||current.claimId!==b.claimId){
   if(!current&&this.live.size>=200)throw new Fault('overlay_capacity',429);
   this.live.set(b.ownerRobloxId,{jobId:b.jobId,claimId:b.claimId,writeToken:token(),seen:now,sequence:0,state:null});
  }
  const l=this.live.get(b.ownerRobloxId);l.seen=now;
  return {readToken:p.read_token,writeToken:l.writeToken,interval:1};
 }
 publish(key,b){
  let l;for(const entry of this.live.values())if(constantEqual(entry.writeToken,key)){l=entry;break;}
  if(!l||this.now()-l.seen>=45000)throw new Fault('overlay_lease_expired',401);
  if(l.lastPublish!==undefined&&this.now()-l.lastPublish<400)throw new Fault('overlay_rate_limited',429);
  if(!Number.isSafeInteger(b?.sequence)||b.sequence<=l.sequence)throw new Fault('stale_overlay_snapshot',409);
  const state=validateSnapshot(b.snapshot,!!l.state?.route);
  const previous=l.state;
  const reset=!previous||previous.round!==state.round;
  // Keep observed peaks for this round, even if a publisher omits a transient peak.
  for(const r of state.racers){const old=!reset&&previous.racers.find(x=>x.id===r.id);r.topSpeed=Math.max(r.speed,r.topSpeed,old?.topSpeed??0);}
  l.state={...state,route:state.route??previous.route};l.sequence=b.sequence;l.seen=this.now();l.lastPublish=l.seen;
  return {ok:true};
 }
 release(key){
  for(const [id,l]of this.live)if(constantEqual(l.writeToken,key)){this.live.delete(id);return {ok:true};}
  throw new Fault('overlay_lease_expired',401);
 }
 read(key){
  if(typeof key!=='string'||!/^[A-Za-z0-9_-]{43}$/.test(key))throw new Fault('unauthorized',401);
  const p=this.db.prepare('SELECT owner_id FROM overlay_profiles WHERE read_token=?').get(key);if(!p)throw new Fault('unauthorized',401);
  const l=this.live.get(p.owner_id);const age=l?this.now()-l.seen:Infinity;
  return {online:!!l&&age<5000,sequence:l?.sequence??0,ageMs:Number.isFinite(age)?age:null,snapshot:l?.state??null};
 }
 sweep(){for(const [id,l]of this.live)if(this.now()-l.seen>300000)this.live.delete(id);}
}
