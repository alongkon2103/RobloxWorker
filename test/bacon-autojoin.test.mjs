import test from 'node:test';
import assert from 'node:assert/strict';
import {Store} from '../src/store.mjs';
import {EventTranslator,compactMessage} from '../src/events.mjs';
import {LiveManager} from '../src/live.mjs';
const raw=(type,id,extra={},user='viewer')=>compactMessage({type,data:{common:{msgId:id},user:{userId:user,displayId:'handle-'+user,nickname:'ผู้ชม '+user},...extra}});
const chat=(id,text,user)=>raw('WebcastChatMessage',id,{comment:text},user);
const gift=(id,giftId='99',user)=>raw('WebcastGiftMessage',id,{giftId,giftType:0,repeatCount:1},user);
const create=(s,extra={})=>s.create({ownerRobloxId:'1',jobId:'j',tiktokUsername:'live',universeId:'123',...extra});
const take=(s,id)=>{const e=s.poll(id);if(e)s.ack(id,e.eventId,e.receipt);return e;};
test('first ordinary chat or any gift joins Bacon immediately with TikTok identity; likes and follows cannot join',async()=>{
 const s=new Store(':memory:');let calls=0;const tr=new EventTranslator(s,{resolve:async()=>{calls++;return null;},giftMap:{99:{key:'rocket',value:1}}});const a=create(s);
 try{
  await tr.handle(a.id,1,raw('WebcastLikeMessage','like',{count:20},'likes-only'));await tr.handle(a.id,1,raw('WebcastFollowMessage','follow',{},'follow-only'));assert.equal(s.actorCount(a.id,1),0);
  await tr.handle(a.id,1,chat('hello','hello everyone!'));const bacon=take(s,a.id);assert.equal(bacon.avatarType,'bacon');assert.equal(bacon.robloxId,'0');assert.equal(bacon.robloxUsername,'');assert.equal(bacon.actorKey,'tiktok:viewer');assert.equal(bacon.tiktokDisplayName,'ผู้ชม viewer');assert.equal(calls,0);
  await tr.handle(a.id,1,gift('unknown','404','gift-viewer'));const other=take(s,a.id);assert.equal(other.avatarType,'bacon');assert.equal(other.actorKey,'tiktok:gift-viewer');assert.equal(take(s,a.id),null);
  await tr.handle(a.id,1,gift('known','99','paid-viewer'));assert.equal(take(s,a.id).avatarType,'bacon');const paid=take(s,a.id);assert.equal(paid.eventType,'gift');assert.equal(paid.robloxId,'0');assert.equal(paid.effects[0].key,'rocket');
 }finally{s.close();}
});
test('valid username creates Bacon before lookup, upgrades one identity, then ignores repeated names',async()=>{
 const s=new Store(':memory:');const a=create(s);let release,calls=0;const tr=new EventTranslator(s,{resolve:()=>{calls++;return new Promise(r=>release=r);},giftMap:{}});
 try{
  const pending=tr.handle(a.id,1,chat('name','@Runner'));const bacon=take(s,a.id);assert.equal(bacon?.avatarType,'bacon');assert.equal(s.actorCount(a.id,1),1);
  release({id:42,name:'Runner'});assert.equal(await pending,true);const upgrade=take(s,a.id);assert.equal(upgrade.avatarType,'roblox');assert.equal(upgrade.avatarUpdate,true);assert.equal(upgrade.robloxId,'42');assert.equal(upgrade.actorKey,bacon.actorKey);assert.equal(s.actorCount(a.id,1),1);
  await tr.handle(a.id,1,chat('repeat','@Runner'));await tr.handle(a.id,1,chat('another','@Other'));assert.equal(take(s,a.id),null);assert.equal(calls,1);assert.equal(s.actor(a.id,1,bacon.actorKey).robloxUsername,'Runner');
 }finally{s.close();}
});
test('invalid lookup leaves Bacon and actor lookup spam is gated for exactly thirty seconds',async()=>{
 let now=1000,calls=0;const s=new Store(':memory:',{now:()=>now});const a=create(s);const tr=new EventTranslator(s,{resolve:async()=>{calls++;return null;},giftMap:{}});
 try{
  await tr.handle(a.id,1,chat('first','@Missing'));assert.equal(take(s,a.id).avatarType,'bacon');
  await tr.handle(a.id,1,chat('spam','@Other'));assert.equal(calls,1);now+=29999;await tr.handle(a.id,1,chat('early','@Other'));assert.equal(calls,1);
  now++;await tr.handle(a.id,1,chat('due','@Other'));assert.equal(calls,2);assert.equal(s.actor(a.id,1,'tiktok:viewer').avatarType,'bacon');assert.equal(take(s,a.id),null);
 }finally{s.close();}
});
test('Bacon appears even when all four username lookup slots are occupied',async()=>{
 const s=new Store(':memory:');const a=create(s);const releases=[];const tr=new EventTranslator(s,{resolve:()=>new Promise(r=>releases.push(r)),giftMap:{}});const m=new LiveManager(s,tr,{sliceMs:1000,maxConnections:0});
 try{
  s.ingest(a.id,1,Array.from({length:5},(_,i)=>chat('name'+i,'@Runner','viewer'+i)));await m.drain(a.id);assert.equal(m.lookups.size,4);assert.equal(s.actorCount(a.id,1),5);const joins=s.pollActorBatch(a.id,32,{maxJoins:8});assert.equal(joins.length,5);assert.ok(joins.every(e=>e.avatarType==='bacon'));
 }finally{for(const release of releases)release(null);await m.stop();s.close();}
});
test('queue-full upgrade retries reuse the resolved lookup and failed upgrade restores Bacon with paid gifts intact',async()=>{
 const s=new Store(':memory:',{maxQueue:1});const a=create(s);let calls=0;const tr=new EventTranslator(s,{resolve:async()=>{calls++;return {id:42,name:'Runner'};},giftMap:{99:{key:'rocket',value:1}}});
 try{
  await assert.rejects(tr.handle(a.id,1,chat('name','@Runner')),/queue_full/);const bacon=take(s,a.id);assert.equal(bacon.avatarType,'bacon');await tr.handle(a.id,1,chat('name','@Runner'));assert.equal(calls,1);
  const upgrade=s.poll(a.id);s.ack(a.id,upgrade.eventId,upgrade.receipt,{success:false,retry:false});assert.equal(s.actor(a.id,1,'tiktok:viewer').avatarType,'bacon');
  await tr.handle(a.id,1,gift('paid'));const paid=take(s,a.id);assert.equal(paid.avatarType,'bacon');assert.equal(paid.joinEventId,bacon.eventId);assert.equal(paid.effects[0].key,'rocket');
 }finally{s.close();}
});
test('failed upgrade rebinds already queued paid effects to Bacon; expired initial Bacon cannot leave an orphan upgrade',async()=>{
 let now=1000;const s=new Store(':memory:',{now:()=>now,eventTTL:10000});const a=create(s);const tr=new EventTranslator(s,{resolve:async()=>({id:42,name:'Runner'}),giftMap:{99:{key:'rocket',value:1}}});
 try{
  await tr.handle(a.id,1,chat('name','@Runner'));const bacon=take(s,a.id);const upgrade=s.poll(a.id);await tr.handle(a.id,1,gift('paid'));s.ack(a.id,upgrade.eventId,upgrade.receipt,{success:false,retry:false});
  const paid=take(s,a.id);assert.equal(paid.effects[0].key,'rocket');assert.equal(paid.avatarType,'bacon');assert.equal(paid.robloxId,'0');assert.equal(paid.joinEventId,bacon.eventId);
  s.reset(a.id);let release;const delayed=new EventTranslator(s,{resolve:()=>new Promise(r=>release=r),giftMap:{}});const pending=delayed.handle(a.id,2,chat('fresh','@Runner'));now+=5000;release({id:42,name:'Runner'});await pending;now+=5001;assert.deepEqual(s.pollActorBatch(a.id,32,{maxJoins:8}),[]);assert.equal(s.actor(a.id,2,'tiktok:viewer'),null);
 }finally{s.close();}
});
test('Bacon gift combo and nineteen-heart progress survive the single identity upgrade',async()=>{
 const s=new Store(':memory:');const a=create(s);const tr=new EventTranslator(s,{resolve:async()=>({id:42,name:'Runner'}),giftMap:{99:{key:'rocket',value:1}}});
 const combo=id=>raw('WebcastGiftMessage',id,{giftId:'99',giftType:1,repeatCount:3,repeatEnd:true,groupId:'combo'});
 try{
  await tr.handle(a.id,1,combo('first'));assert.equal(take(s,a.id).avatarType,'bacon');assert.equal(take(s,a.id).effects[0].count,3);
  await tr.handle(a.id,1,raw('WebcastLikeMessage','nineteen',{count:19}));assert.equal(take(s,a.id),null);
  await tr.handle(a.id,1,chat('name','@Runner'));assert.equal(take(s,a.id).avatarUpdate,true);
  await tr.handle(a.id,1,raw('WebcastLikeMessage','one',{count:1}));assert.deepEqual(take(s,a.id).effects,[{key:'speed_boost',value:1,count:1}]);
  await tr.handle(a.id,1,combo('duplicate'));assert.equal(take(s,a.id),null);assert.equal(s.actorCount(a.id,1),1);
 }finally{s.close();}
});
test('expired cosmetic upgrade restores Bacon and notifies waiting delivery for newer paid effects',async()=>{
 let now=1000;const s=new Store(':memory:',{now:()=>now,eventTTL:10000});const a=create(s);const tr=new EventTranslator(s,{resolve:async()=>({id:42,name:'Runner'}),giftMap:{99:{key:'rocket',value:1}}});
 try{
  await tr.handle(a.id,1,chat('name','@Runner'));const bacon=take(s,a.id);now=7000;await tr.handle(a.id,1,gift('paid'));
  const notices=[];s.changes.on('change',id=>notices.push(id));now=11001;s.prune();assert.ok(notices.includes(a.id));
  const paid=take(s,a.id);assert.equal(paid.eventType,'gift');assert.equal(paid.avatarType,'bacon');assert.equal(paid.joinEventId,bacon.eventId);
 }finally{s.close();}
});
