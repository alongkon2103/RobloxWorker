import {Fault} from './store.mjs';
const day=86400000,thai=7*3600000;
const text=(x,n)=>typeof x==='string'&&x.length>0&&x.length<=n;
const id=x=>typeof x==='string'&&/^[1-9]\d{0,15}$/.test(x)&&BigInt(x)<=9007199254740991n;
export function weekAt(time){
 const d=new Date(time+thai),days=(d.getUTCDay()+6)%7;
 const start=Date.UTC(d.getUTCFullYear(),d.getUTCMonth(),d.getUTCDate()-days)-thai;
 return {start:new Date(start+thai).toISOString().slice(0,10),nextResetAt:start+7*day};
}
function channelFor(provider,channel,owner){
 if(provider==='tikkies')return 'owner:'+owner;
 if(provider!=='direct'||typeof channel!=='string'||! /^[a-z0-9._]{2,24}$/.test(channel))throw new Fault('invalid_win');
 return channel;
}
export class TopWin{
 constructor(db,now=Date.now){this.db=db;this.now=now;db.exec(`
 CREATE TABLE IF NOT EXISTS top_win_channels(universe_id TEXT NOT NULL,owner_id TEXT NOT NULL,provider TEXT NOT NULL,channel TEXT NOT NULL,PRIMARY KEY(universe_id,owner_id));
 CREATE TABLE IF NOT EXISTS top_win_receipts(universe_id TEXT NOT NULL,owner_id TEXT NOT NULL,job_id TEXT NOT NULL,race_id TEXT NOT NULL,finished_at INTEGER NOT NULL,PRIMARY KEY(universe_id,owner_id,job_id,race_id));
 CREATE TABLE IF NOT EXISTS top_win_scores(universe_id TEXT NOT NULL,owner_id TEXT NOT NULL,provider TEXT NOT NULL,channel TEXT NOT NULL,week TEXT NOT NULL,actor_id TEXT NOT NULL,name TEXT NOT NULL,roblox_id TEXT NOT NULL,wins INTEGER NOT NULL,last_win INTEGER NOT NULL,PRIMARY KEY(universe_id,owner_id,provider,channel,week,actor_id));`);}
 bind(universe,owner,provider,channel){
  if(!id(owner))throw new Fault('invalid_win');channel=channelFor(provider,channel,owner);
  this.db.prepare('INSERT INTO top_win_channels VALUES(?,?,?,?) ON CONFLICT(universe_id,owner_id) DO UPDATE SET provider=excluded.provider,channel=excluded.channel').run(universe,owner,provider,channel);
 }
 record(universe,b){
  if(!b||!id(b.ownerRobloxId)||!text(b.jobId,128)||!text(b.raceId,160)||!text(b.actorKey,160)||! /^(?:tiktok|live):[A-Za-z0-9._-]+$/.test(b.actorKey)||!(typeof b.name==='string'&&Array.from(b.name).length>0&&Array.from(b.name).length<=80)||!id(b.robloxId)||!Number.isSafeInteger(b.finishedAt)||b.finishedAt>this.now()+30000||b.finishedAt<this.now()-7*day)throw new Fault('invalid_win');
  const channel=channelFor(b.provider,b.channel,b.ownerRobloxId),week=weekAt(b.finishedAt).start;
  this.db.exec('BEGIN IMMEDIATE');try{
   const receipt=this.db.prepare('INSERT INTO top_win_receipts VALUES(?,?,?,?,?) ON CONFLICT DO NOTHING').run(universe,b.ownerRobloxId,b.jobId,b.raceId,b.finishedAt);
   if(receipt.changes){
    this.db.prepare(`INSERT INTO top_win_scores VALUES(?,?,?,?,?,?,?,?,1,?) ON CONFLICT(universe_id,owner_id,provider,channel,week,actor_id) DO UPDATE SET wins=wins+1,name=CASE WHEN excluded.last_win>=last_win THEN excluded.name ELSE name END,roblox_id=CASE WHEN excluded.last_win>=last_win THEN excluded.roblox_id ELSE roblox_id END,last_win=MAX(last_win,excluded.last_win)`).run(universe,b.ownerRobloxId,b.provider,channel,week,b.actorKey,b.name,b.robloxId,b.finishedAt);
    this.db.prepare('INSERT INTO top_win_channels VALUES(?,?,?,?) ON CONFLICT DO NOTHING').run(universe,b.ownerRobloxId,b.provider,channel);
   }
   this.db.exec('COMMIT');return {ok:true,counted:receipt.changes===1};
  }catch(e){this.db.exec('ROLLBACK');throw e;}
 }
 board(universe,owner){
  const week=weekAt(this.now()),scope=this.db.prepare('SELECT * FROM top_win_channels WHERE universe_id=? AND owner_id=?').get(universe,owner);
  const rows=scope?this.db.prepare('SELECT actor_id AS id,name,roblox_id AS robloxId,wins FROM top_win_scores WHERE universe_id=? AND owner_id=? AND provider=? AND channel=? AND week=? ORDER BY wins DESC,last_win ASC,actor_id ASC LIMIT 10').all(universe,owner,scope.provider,scope.channel,week.start):[];
  return {title:'TOP WIN',week:week.start,nextResetAt:week.nextResetAt,channel:scope?.channel??null,rows};
 }
}
