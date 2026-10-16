import test from 'node:test';import assert from 'node:assert/strict';
import {Store} from '../src/store.mjs';import {createAPI} from '../src/server.mjs';
const config={bridgeKey:'b'.repeat(32),adminKey:'a'.repeat(32),tikkiesEnabled:false,giftMap:{}};
test('HTTP auth, owner sessions, scoped delivery, idempotent reset and job batching',async()=>{
 const store=new Store(':memory:');const server=createAPI(store,config);await new Promise(r=>server.listen(0,'127.0.0.1',r));
 const url=`http://127.0.0.1:${server.address().port}`;
 const req=async(path,key,body,method=body?'POST':'GET')=>{const r=await fetch(url+path,{method,headers:{authorization:`Bearer ${key}`,'content-type':'application/json'},body:body?JSON.stringify(body):undefined});return {status:r.status,data:await r.json()};};
 try{
  assert.equal((await req('/v1/sessions','bad',{ownerRobloxId:'1',jobId:'job',tiktokUsername:'alice'})).status,401);
  const a=(await req('/v1/sessions',config.bridgeKey,{ownerRobloxId:'1',jobId:'job',tiktokUsername:'alice'})).data;
  const b=(await req('/v1/sessions',config.bridgeKey,{ownerRobloxId:'2',jobId:'other',tiktokUsername:'bob'})).data;
  assert.ok(a.token);assert.equal((await req('/v1/admin/sessions',config.bridgeKey)).status,401);
  assert.equal((await req(`/v1/sessions/${a.id}/join-mode`,b.token,{joinMode:'both'})).status,401);
  assert.equal((await req(`/v1/sessions/${a.id}/join-mode`,a.token,{joinMode:'invalid'})).status,400);
  assert.equal((await req(`/v1/sessions/${a.id}/join-mode`,a.token,{joinMode:'both'})).data.joinMode,'both');
  const orphan=(await req('/v1/sessions',config.bridgeKey,{ownerRobloxId:'4',jobId:'job',tiktokUsername:'orphan'})).data;
  const seenBefore=store.get(orphan.id).seen_at;
  store.now=()=>seenBefore+1000;
  assert.equal((await req('/v1/servers/job/poll',config.bridgeKey,{sessionIds:[a.id]})).status,200);
  assert.equal(store.get(orphan.id).seen_at,seenBefore,'batch revived an unowned orphan');
  assert.equal((await req('/v1/servers/job/poll',config.bridgeKey,{sessionIds:[b.id]})).status,403);
  assert.equal((await req('/v1/servers/job/poll',config.bridgeKey,{sessionIds:[null]})).status,400);
  assert.equal((await req(`/v1/sessions/${a.id}`,b.token)).status,401);
  store.enqueue(a.id,a.generation,'evt',{eventType:'join',effects:[]});store.enqueue(b.id,b.generation,'other-event',{});
  const batch=(await req('/v1/servers/job/poll',config.bridgeKey,{})).data.events;
  assert.equal(batch.length,1);assert.equal(batch[0].event.eventId,'evt');
  const e=batch[0].event;assert.equal((await req(`/v1/sessions/${a.id}/ack`,a.token,{eventId:e.eventId,receipt:'wrong',success:true})).status,409);
  assert.equal((await req(`/v1/sessions/${a.id}/ack`,a.token,{eventId:e.eventId,receipt:e.receipt,success:true})).status,200);
  const reset={requestId:'reset-one'};const one=(await req(`/v1/sessions/${a.id}/reset`,a.token,reset)).data;
  const twice=(await req(`/v1/sessions/${a.id}/reset`,a.token,reset)).data;assert.equal(one.generation,twice.generation);
  assert.equal((await req('/v1/sessions',config.bridgeKey,{ownerRobloxId:'3',jobId:'job',tiktokUsername:'carol',provider:'tikkies'})).status,403);
  const health=await req('/healthz','');assert.equal(health.status,200);assert.ok(!JSON.stringify(health.data).includes(config.bridgeKey));
  assert.equal((await req(`/v1/sessions/${a.id}`,a.token,undefined,'DELETE')).status,200);
  assert.equal((await req(`/v1/sessions/${a.id}/poll`,a.token,{})).status,410);
 }finally{await new Promise(r=>server.close(r));store.close();}
});
test('Tikkies fallback stays authenticated, scoped and off unless enabled',async()=>{
 const store=new Store(':memory:');const server=createAPI(store,{...config,tikkiesEnabled:true,maxActors:1});await new Promise(r=>server.listen(0,'127.0.0.1',r));const base=`http://127.0.0.1:${server.address().port}`;
 const post=async(path,key,body)=>{const r=await fetch(base+path,{method:'POST',headers:{authorization:`Bearer ${key}`,'content-type':'application/json'},body:JSON.stringify(body)});return {status:r.status,data:await r.json()};};
 try{
  const session=(await post('/v1/sessions',config.bridgeKey,{ownerRobloxId:'12',jobId:'job',tiktokUsername:'fallback',provider:'tikkies'})).data;
  const actor={generation:1,eventId:'vendor-join',eventType:'join',actorKey:'tiktok:viewer',robloxId:'456',robloxUsername:'Runner',tiktokUsername:'viewer',effects:[]};
  const route=`/v1/admin/sessions/${session.id}/ingest`;
  assert.equal((await post(route,config.bridgeKey,actor)).status,401);assert.equal((await post(route,config.adminKey,actor)).data.accepted,true);
  assert.equal((await post(route,config.adminKey,actor)).data.accepted,false);
  const join=store.poll(session.id);store.ack(session.id,join.eventId,join.receipt);
  assert.equal((await post(route,config.adminKey,{...actor,eventId:'vendor-gift',eventType:'gift',effects:[{key:'rocket',value:1,count:1}]})).status,200);
  assert.equal((await post(route,config.adminKey,{...actor,eventId:'cat-gift',eventType:'gift',effects:[{key:'rainbow_cat',value:1,count:1}]})).status,200);
  assert.equal((await post(route,config.adminKey,{...actor,eventId:'naruto-gift',eventType:'gift',effects:[{key:'naruto',value:1,count:1}]})).status,200);
  assert.equal((await post(route,config.adminKey,{...actor,eventId:'stale',generation:0})).status,409);
  assert.equal((await post('/v1/servers/job/ack',config.bridgeKey,{receipts:[null]})).status,400);
 }finally{await new Promise(r=>server.close(r));store.close();}
});
