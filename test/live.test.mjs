import test from 'node:test';import assert from 'node:assert/strict';
import {Store} from '../src/store.mjs';import {LiveManager} from '../src/live.mjs';
class Socket extends EventTarget{
 static sockets=[];constructor(url){super();this.url=url;this.readyState=0;Socket.sockets.push(this);}
 emit(type,properties={}){const e=new Event(type);Object.assign(e,properties);this.dispatchEvent(e);}
 close(){this.readyState=3;this.emit('close',{code:1000});}
}
test('concurrency, fair queue, offline backoff and obsolete callbacks',async()=>{
 const s=new Store(':memory:',{now:()=>now});let now=1000;
 const cfg={maxConnections:1,eulerKey:'key-for-test',connectTimeout:45000,maxProcessing:2};
 const translator={handle:async()=>{}};const m=new LiveManager(s,translator,cfg,{Socket});
 const a=s.create({ownerRobloxId:'1',jobId:'j1',tiktokUsername:'live1'}),b=s.create({ownerRobloxId:'2',jobId:'j2',tiktokUsername:'live2'});
 m.tick();assert.equal(Socket.sockets.length,1);assert.equal(s.get(a.id).status,'connecting');
 const first=Socket.sockets[0];first.emit('open');first.emit('message',{data:JSON.stringify({messages:[{type:'room.status',data:{state:'connected'}}]})});assert.equal(s.get(a.id).status,'live');
 first.emit('close',{code:4404});assert.equal(s.get(a.id).status,'offline');m.tick();assert.equal(Socket.sockets.length,2);assert.equal(s.get(b.id).status,'connecting');
 first.emit('message',{data:JSON.stringify({messages:[{type:'room.status',data:{state:'connected'}}]})});assert.equal(s.get(a.id).status,'offline');
 s.stop(b.id);m.tick();assert.equal(m.connections.size,0);assert.equal(s.get(b.id).status,'closed');
 await m.stop();s.close();Socket.sockets=[];
});
test('inbox workers rotate fairly when processing slots are full',async()=>{
 const s=new Store(':memory:');const sessions=['1','2','3'].map(n=>s.create({ownerRobloxId:n,jobId:'j'+n,tiktokUsername:'live'+n}));
 for(const a of sessions)s.ingest(a.id,1,[{sourceId:'row',type:'WebcastChatMessage',data:{}}]);
 const calls=[],wait=[];const translator={handle:async id=>{calls.push(id);await new Promise(r=>wait.push(r));}};
 const m=new LiveManager(s,translator,{maxConnections:1,maxProcessing:1,eulerKey:'test',sliceMs:0},{Socket});
 m.tick();assert.equal(calls[0],sessions[0].id);wait.shift()();await Promise.all(m.processing.values());
 s.ingest(sessions[0].id,1,[{sourceId:'backlog',type:'WebcastChatMessage',data:{}}]);
 m.tick();assert.equal(calls[1],sessions[1].id);wait.shift()();await Promise.all(m.processing.values());
 m.tick();assert.equal(calls[2],sessions[2].id);wait.shift()();await Promise.all(m.processing.values());
 await m.stop();s.close();Socket.sockets=[];
});
test('failed avatar lookup defers one actor durably while other actors continue in order',async()=>{
 const {EventTranslator,compactMessage}=await import('../src/events.mjs');const {Fault}=await import('../src/store.mjs');
 const {mkdtempSync,rmSync}=await import('node:fs'),{tmpdir}=await import('node:os'),{join}=await import('node:path');
 const dir=mkdtempSync(join(tmpdir(),'inbox-retry-'));let now=1000,s,m;let available=false,attempts=0;
 const raw=(type,id,user,extra)=>compactMessage({type,data:{common:{msgId:id},user:{userId:user,displayId:user},...extra}});
 const resolver=async name=>{if(name==='Unavailable'){attempts++;if(!available)throw new Fault('avatar_lookup_unavailable',503);}return {id:42,name};};
 try{
  s=new Store(join(dir,'db'),{now:()=>now});const a=s.create({ownerRobloxId:'1',jobId:'j',tiktokUsername:'live'});
  let tr=new EventTranslator(s,{resolve:resolver,giftMap:{99:{key:'rocket',value:1}}});
  await tr.handle(a.id,1,raw('WebcastChatMessage','joined','ready',{comment:'@Runner'}));let e=s.poll(a.id);s.ack(a.id,e.eventId,e.receipt);
  s.ingest(a.id,1,[raw('WebcastChatMessage','slow','waiting',{comment:'@Unavailable'}),raw('WebcastLikeMessage','wait-likes','waiting',{count:20}),raw('WebcastGiftMessage','wait-gift','waiting',{giftId:99,giftType:0}),raw('WebcastLikeMessage','ready-likes','ready',{count:20})]);
  m=new LiveManager(s,tr,{sliceMs:1000,maxConnections:0});await m.drain(a.id);
  e=s.poll(a.id);assert.equal(e.eventType,'like');assert.equal(e.actorKey,'tiktok:ready');s.ack(a.id,e.eventId,e.receipt);assert.equal(s.inboxDepth(a.id),3);
  await m.drain(a.id);assert.equal(attempts,1,'lookup retried without backoff');s.close();s=new Store(join(dir,'db'),{now:()=>now});
  tr=new EventTranslator(s,{resolve:resolver,giftMap:{99:{key:'rocket',value:1}}});m=new LiveManager(s,tr,{sliceMs:1000,maxConnections:0});await m.drain(a.id);assert.equal(attempts,1,'restart lost retry time');
  now+=1000;available=true;await m.drain(a.id);await Promise.all([...m.lookups.values()].map(v=>v.task));await m.drain(a.id);assert.equal(s.inboxDepth(a.id),0);
  e=s.poll(a.id);assert.equal(e.eventType,'join');s.ack(a.id,e.eventId,e.receipt);
  e=s.poll(a.id);assert.equal(e.eventType,'like');s.ack(a.id,e.eventId,e.receipt);
  e=s.poll(a.id);assert.equal(e.eventType,'gift');assert.equal(e.effects[0].key,'rocket');assert.equal(attempts,2);
 }finally{if(m)await m.stop();s?.close();rmSync(dir,{recursive:true,force:true});}
});
test('joined actor hearts reach delivery before slow lookups from other actors',async()=>{
 const {EventTranslator,compactMessage}=await import('../src/events.mjs');
 const raw=(id,user,extra,type='WebcastChatMessage')=>compactMessage({type,data:{common:{msgId:id},user:{userId:user,displayId:user},...extra}});
 const s=new Store(':memory:');const a=s.create({ownerRobloxId:'1',jobId:'j',tiktokUsername:'live'});let release;
 const tr=new EventTranslator(s,{resolve:async name=>name==='Slow'?new Promise(r=>release=r):{id:42,name},giftMap:{}});
 const m=new LiveManager(s,tr,{sliceMs:1000,maxConnections:0});let pending;
 try{
  await tr.handle(a.id,1,raw('joined','ready',{comment:'@Runner'}));let e=s.poll(a.id);s.ack(a.id,e.eventId,e.receipt);
  s.ingest(a.id,1,[raw('slow','waiting',{comment:'@Slow'}),raw('hearts','ready',{count:20},'WebcastLikeMessage')]);
  pending=m.drain(a.id);await new Promise(r=>setImmediate(r));e=s.poll(a.id);assert.equal(e?.eventType,'like');
 }finally{release?.({id:43,name:'Slow'});await pending;await m.stop();s.close();}
});
test('queue full keeps the durable award and same actor order until space returns',async()=>{
 const {EventTranslator,compactMessage}=await import('../src/events.mjs');
 const raw=(type,id,extra)=>compactMessage({type,data:{common:{msgId:id},user:{userId:'viewer',displayId:'viewer'},...extra}});
 const s=new Store(':memory:',{maxQueue:1});const a=s.create({ownerRobloxId:'1',jobId:'j',tiktokUsername:'live'});
 const tr=new EventTranslator(s,{resolve:async name=>({id:42,name}),giftMap:{99:{key:'rocket',value:1}}});const m=new LiveManager(s,tr,{sliceMs:1000,maxConnections:0});
 const take=()=>{const e=s.poll(a.id);if(e)s.ack(a.id,e.eventId,e.receipt);return e;};
 try{
  await tr.handle(a.id,1,raw('WebcastChatMessage','join',{comment:'@Runner'}));take();
  await tr.handle(a.id,1,raw('WebcastLikeMessage','progress',{count:19}));s.enqueue(a.id,1,'busy',{eventType:'gift'});
  s.ingest(a.id,1,[raw('WebcastLikeMessage','award',{count:1}),raw('WebcastGiftMessage','gift',{giftId:99,giftType:0})]);
  await m.drain(a.id);assert.equal(s.inboxDepth(a.id),2);take();
  await m.drain(a.id);assert.equal(take().eventType,'like');assert.equal(s.inboxDepth(a.id),1);
  await m.drain(a.id);assert.equal(take().eventType,'gift');assert.equal(s.inboxDepth(a.id),0);
 }finally{await m.stop();s.close();}
});
test('reset while a deferred lookup is in flight cannot affect the next generation inbox',async()=>{
 const {EventTranslator,compactMessage}=await import('../src/events.mjs');const {Fault}=await import('../src/store.mjs');let release;
 const s=new Store(':memory:');const a=s.create({ownerRobloxId:'1',jobId:'j',tiktokUsername:'live'});
 const tr=new EventTranslator(s,{resolve:()=>new Promise((resolve,reject)=>release=()=>reject(new Fault('avatar_lookup_unavailable',503))),giftMap:{}});const m=new LiveManager(s,tr,{sliceMs:1000,maxConnections:0});
 const row=id=>compactMessage({type:'WebcastChatMessage',data:{common:{msgId:id},user:{userId:'viewer'},comment:'@Runner'}});
 try{
  s.ingest(a.id,1,[row('old')]);const pending=m.drain(a.id);s.reset(a.id);s.ingest(a.id,2,[row('new')]);
  m.stopped=true;release();await pending;assert.equal(s.inbox(a.id).sourceId,'WebcastChatMessage:new');assert.equal(s.inbox(a.id).generation,2);
 }finally{await m.stop();s.close();}
});
test('failed lookups obey the same worker time slice as successful messages',async()=>{
 const {EventTranslator,compactMessage}=await import('../src/events.mjs');const {Fault}=await import('../src/store.mjs');
 const s=new Store(':memory:');const a=s.create({ownerRobloxId:'1',jobId:'j',tiktokUsername:'live'});
 const tr=new EventTranslator(s,{resolve:async()=>{throw new Fault('avatar_lookup_unavailable',503);},giftMap:{}});const m=new LiveManager(s,tr,{sliceMs:0});
 try{
  s.ingest(a.id,1,['first','second'].map(id=>compactMessage({type:'WebcastChatMessage',data:{common:{msgId:id},user:{userId:id},comment:'@Runner'}})));
  await m.drain(a.id);await Promise.all([...m.lookups.values()].map(v=>v.task));assert.equal(s.inbox(a.id)?.sourceId,'WebcastChatMessage:second');
 }finally{await m.stop();s.close();}
});
test('fresh joined-actor hearts and gifts bypass an unresolved lookup while its actor stays ordered',async()=>{
 const {EventTranslator,compactMessage}=await import('../src/events.mjs');
 const raw=(type,id,user,extra)=>compactMessage({type,data:{common:{msgId:id},user:{userId:user,displayId:user},...extra}});
 const s=new Store(':memory:');const a=s.create({ownerRobloxId:'1',jobId:'j',tiktokUsername:'live'});let release;
 const tr=new EventTranslator(s,{resolve:async name=>name==='Slow'?new Promise(r=>release=r):{id:42,name},giftMap:{99:{key:'rocket',value:1}}});const m=new LiveManager(s,tr,{sliceMs:1000,maxConnections:0});
 const take=()=>{const e=s.poll(a.id);if(e)s.ack(a.id,e.eventId,e.receipt);return e;};let pending;
 try{
  await tr.handle(a.id,1,raw('WebcastChatMessage','ready','ready',{comment:'@Runner'}));take();
  s.ingest(a.id,1,[raw('WebcastChatMessage','slow','waiting',{comment:'@Slow'}),raw('WebcastGiftMessage','wait-gift','waiting',{giftId:99,giftType:0})]);
  m.tick();await new Promise(r=>setImmediate(r));
  s.ingest(a.id,1,[raw('WebcastLikeMessage','hearts','ready',{count:20}),raw('WebcastGiftMessage','ready-gift','ready',{giftId:99,giftType:0})]);
  m.tick();await new Promise(r=>setImmediate(r));assert.equal(take()?.eventType,'like');assert.equal(take()?.eventType,'gift');assert.equal(take(),null);assert.equal(s.inboxDepth(a.id),2);
  release({id:43,name:'Slow'});await pending;await Promise.all([...m.lookups.values()].map(v=>v.task));await m.drain(a.id);assert.equal(take()?.eventType,'join');assert.equal(take()?.eventType,'gift');
 }finally{release?.({id:43,name:'Slow'});await pending;await m.stop();s.close();}
});
test('background username lookups are bounded globally while all sessions can serve joined hearts',async()=>{
 const {EventTranslator,compactMessage}=await import('../src/events.mjs');const s=new Store(':memory:');let active=0,peak=0;const releases=[];
 const tr=new EventTranslator(s,{resolve:async name=>{if(name==='Runner')return {id:42,name};active++;peak=Math.max(peak,active);await new Promise(r=>releases.push(r));active--;return {id:43,name};},giftMap:{}});
 const m=new LiveManager(s,tr,{sliceMs:1000,maxProcessing:10,maxConnections:0});const raw=(type,id,user,extra)=>compactMessage({type,data:{common:{msgId:id},user:{userId:user},...extra}});
 try{
  const sessions=Array.from({length:8},(_,i)=>s.create({ownerRobloxId:String(i+1),jobId:'j',tiktokUsername:'live'+i}));
  for(const a of sessions){await tr.handle(a.id,1,raw('WebcastChatMessage','ready','ready',{comment:'@Runner'}));const e=s.poll(a.id);s.ack(a.id,e.eventId,e.receipt);s.ingest(a.id,1,[raw('WebcastChatMessage','slow','waiting',{comment:'@Slow'})]);}
  m.tick();await new Promise(r=>setImmediate(r));assert.equal(active,4);assert.equal(peak,4);
  for(const a of sessions)s.ingest(a.id,1,[raw('WebcastLikeMessage','hearts','ready',{count:20})]);m.tick();await Promise.all(m.processing.values());
  for(const a of sessions)assert.equal(s.poll(a.id)?.eventType,'like');assert.equal(peak,4);
 }finally{while(releases.length)releases.shift()();await m.stop();s.close();}
});
test('shutdown waits for background lookups and preserves their raw rows without late enqueue',async()=>{
 const {EventTranslator,compactMessage}=await import('../src/events.mjs');const s=new Store(':memory:');const a=s.create({ownerRobloxId:'1',jobId:'j',tiktokUsername:'live'});let release;
 const tr=new EventTranslator(s,{resolve:()=>new Promise(r=>release=r),giftMap:{}});const m=new LiveManager(s,tr,{sliceMs:1000,maxConnections:0});
 try{
  s.ingest(a.id,1,[compactMessage({type:'WebcastChatMessage',data:{common:{msgId:'slow'},user:{userId:'viewer'},comment:'@Runner'}})]);await m.drain(a.id);let closed=false;const closing=m.stop().then(()=>closed=true);await new Promise(r=>setImmediate(r));assert.equal(closed,false);
  release({id:42,name:'Runner'});await closing;assert.equal(s.public(s.get(a.id)).queueDepth,0);assert.equal(s.inboxDepth(a.id),1);assert.equal(s.actorCount(a.id,1),0);
 }finally{release?.({id:42,name:'Runner'});await m.stop();s.close();}
});
test('reset permits a fresh lookup for the same actor while obsolete lookup cannot enqueue',async()=>{
 const {EventTranslator,compactMessage}=await import('../src/events.mjs');const s=new Store(':memory:');const a=s.create({ownerRobloxId:'1',jobId:'j',tiktokUsername:'live'});const releases=new Map();
 const tr=new EventTranslator(s,{resolve:name=>new Promise(r=>releases.set(name,r)),giftMap:{}});const m=new LiveManager(s,tr,{sliceMs:1000,maxConnections:0});
 const row=(id,name)=>compactMessage({type:'WebcastChatMessage',data:{common:{msgId:id},user:{userId:'viewer'},comment:'@'+name}});
 try{
  s.ingest(a.id,1,[row('old','Old')]);await m.drain(a.id);s.reset(a.id);s.ingest(a.id,2,[row('new','New')]);await m.drain(a.id);assert.equal(m.lookups.size,2);
  releases.get('New')({id:43,name:'New'});await new Promise(r=>setImmediate(r));releases.get('Old')({id:42,name:'Old'});await Promise.all([...m.lookups.values()].map(v=>v.task));
  const e=s.poll(a.id);assert.equal(e.robloxUsername,'New');assert.equal(e.generation,2);s.ack(a.id,e.eventId,e.receipt);assert.equal(s.poll(a.id),null);assert.equal(s.inboxDepth(a.id),0);
 }finally{for(const release of releases.values())release({id:42,name:'Old'});await m.stop();s.close();}
});
test('rebind lookup blocks its own gifts, and concurrent queue full never consumes another actor join',async()=>{
 const {EventTranslator,compactMessage}=await import('../src/events.mjs');const s=new Store(':memory:',{maxQueue:1});const a=s.create({ownerRobloxId:'1',jobId:'j',tiktokUsername:'live'});const releases=new Map();
 const tr=new EventTranslator(s,{resolve:async name=>name==='Runner'?{id:42,name}:new Promise(r=>releases.set(name,r)),giftMap:{99:{key:'rocket',value:1}}});const m=new LiveManager(s,tr,{sliceMs:1000,maxConnections:0});
 const raw=(type,id,user,extra)=>compactMessage({type,data:{common:{msgId:id},user:{userId:user},...extra}});
 try{
  await tr.handle(a.id,1,raw('WebcastChatMessage','join','viewer',{comment:'@Runner'}));let e=s.poll(a.id);s.ack(a.id,e.eventId,e.receipt);
  s.ingest(a.id,1,[raw('WebcastChatMessage','rebind','viewer',{comment:'@New'}),raw('WebcastGiftMessage','gift','viewer',{giftId:99,giftType:0}),raw('WebcastChatMessage','other','other',{comment:'@Other'})]);await m.drain(a.id);assert.equal(s.poll(a.id),null);assert.equal(s.inboxDepth(a.id),3);
  releases.get('New')({id:43,name:'New'});releases.get('Other')({id:44,name:'Other'});await Promise.all([...m.lookups.values()].map(v=>v.task));
  assert.equal(s.actorCount(a.id,1),1);assert.equal(s.inboxDepth(a.id),2);assert.equal(s.actor(a.id,1,'tiktok:other'),null);
  e=s.poll(a.id);assert.equal(e.robloxUsername,'New');s.ack(a.id,e.eventId,e.receipt);await m.drain(a.id);e=s.poll(a.id);assert.equal(e.eventType,'gift');assert.equal(e.robloxId,'43');s.ack(a.id,e.eventId,e.receipt);
 }finally{for(const release of releases.values())release({id:42,name:'Runner'});await m.stop();s.close();}
});
test('queued rebinds cannot hide a ready actor heart behind a full lookup pool',async()=>{
 const {EventTranslator,compactMessage}=await import('../src/events.mjs');const s=new Store(':memory:');const a=s.create({ownerRobloxId:'1',jobId:'j',tiktokUsername:'live'});const releases=[];
 const tr=new EventTranslator(s,{resolve:async name=>name==='Runner'?{id:42,name}:new Promise(r=>releases.push(r)),giftMap:{}});const m=new LiveManager(s,tr,{sliceMs:1000,maxConnections:0});
 const raw=(type,id,user,extra)=>compactMessage({type,data:{common:{msgId:id},user:{userId:user},...extra}});
 try{
  for(let i=0;i<35;i++){await tr.handle(a.id,1,raw('WebcastChatMessage','join'+i,'viewer'+i,{comment:'@Runner'}));const e=s.poll(a.id);s.ack(a.id,e.eventId,e.receipt);}
  s.ingest(a.id,1,Array.from({length:34},(_,i)=>raw('WebcastChatMessage','rebind'+i,'viewer'+i,{comment:'@Slow'})));m.tick();await new Promise(r=>setImmediate(r));assert.equal(m.lookups.size,4);
  s.ingest(a.id,1,[raw('WebcastLikeMessage','hearts','viewer34',{count:20})]);m.tick();await new Promise(r=>setImmediate(r));assert.equal(s.poll(a.id)?.eventType,'like');
 }finally{for(const release of releases)release({id:43,name:'Slow'});await m.stop();s.close();}
});
