import test from 'node:test';
import assert from 'node:assert/strict';
import {Store} from '../src/store.mjs';
import {createAPI} from '../src/server.mjs';
const config={bridgeKey:'b'.repeat(32),adminKey:'a'.repeat(32),giftMap:{},tikkiesEnabled:false};
const waitFor=async predicate=>{const deadline=performance.now()+2000;while(!predicate()){if(performance.now()>deadline)assert.fail('long-poll subscription did not reach expected state');await new Promise(r=>setTimeout(r,1));}};
async function fixture(){
 const store=new Store(':memory:');const server=createAPI(store,config);await new Promise(r=>server.listen(0,'127.0.0.1',r));
 const create=(owner,jobId='job')=>store.create({ownerRobloxId:owner,jobId,tiktokUsername:'live'+owner});
 const post=async(body,{key=config.bridgeKey,signal}={})=>{const r=await fetch(`http://127.0.0.1:${server.address().port}/v1/servers/job/poll`,{method:'POST',headers:{authorization:`Bearer ${key}`,'content-type':'application/json'},body:JSON.stringify(body),signal});return {status:r.status,...await r.json()};};
 const listeners=()=>store.changes?.listenerCount('change')??0;
 return {store,server,create,post,listeners,close:async()=>{await new Promise(r=>server.close(r));store.close();}};
}
test('bounded long poll waits for an empty timeout, and queued events return immediately',async()=>{
 const f=await fixture();try{
  const a=f.create('1');const start=performance.now();const pending=f.post({sessionIds:[a.id],waitMs:200,maxEventsPerSession:32});await waitFor(()=>f.listeners()===1);const empty=await pending;
  assert.deepEqual(empty.events,[]);assert.ok(performance.now()-start>=175,'empty poll returned before its wait');assert.equal(f.listeners(),0);
  f.store.enqueue(a.id,1,'ready',{eventType:'like'});const result=await f.post({sessionIds:[a.id],waitMs:10000,maxEventsPerSession:32},{signal:AbortSignal.timeout(2000)});assert.equal(result.events[0].event.eventId,'ready');assert.equal(f.listeners(),0);
  for(const waitMs of [-1,10001,1.5,'10',null])assert.equal((await f.post({waitMs})).status,400);
 }finally{await f.close();}
});
test('long poll wakes on committed events for selected job sessions only',async()=>{
 const f=await fixture();try{
  const a=f.create('1'),otherOwner=f.create('2'),otherJob=f.create('3','foreign');let settled=false;
  const pending=f.post({sessionIds:[a.id],waitMs:10000,maxEventsPerSession:32}).then(r=>{settled=true;return r;});await waitFor(()=>f.listeners()===1);
  assert.throws(()=>f.store.tx(()=>{f.store.enqueueInside(a.id,1,'rolled-back',{eventType:'gift'});throw new Error('rollback');}),/rollback/);
  f.store.enqueue(otherOwner.id,1,'other-owner',{eventType:'gift'});f.store.enqueue(otherJob.id,1,'other-job',{eventType:'like'});
  await new Promise(r=>setImmediate(r));assert.equal(settled,false);assert.equal(f.listeners(),1);
  f.store.enqueue(a.id,1,'wanted',{eventType:'follow'});const result=await pending;assert.equal(result.events.length,1);assert.equal(result.events[0].sessionId,a.id);assert.equal(result.events[0].event.eventId,'wanted');assert.equal(f.listeners(),0);
 }finally{await f.close();}
});
test('acknowledging a leased join wakes the next batch without bypassing its barrier',async()=>{
 const f=await fixture();try{
  const a=f.create('1');f.store.enqueue(a.id,1,'join',{eventType:'join'});f.store.enqueue(a.id,1,'gift',{eventType:'gift'});
  const join=f.store.poll(a.id);const pending=f.post({sessionIds:[a.id],waitMs:10000,maxEventsPerSession:32});await waitFor(()=>f.listeners()===1);
  f.store.ack(a.id,join.eventId,join.receipt);const result=await pending;assert.deepEqual(result.events.map(e=>e.event.eventId),['gift']);assert.equal(f.listeners(),0);
 }finally{await f.close();}
});
test('aborted, unauthorized and foreign-job long polls leave no subscriptions',async()=>{
 const f=await fixture();try{
  const a=f.create('1'),foreign=f.create('2','foreign');
  assert.equal((await f.post({sessionIds:[a.id],waitMs:10000},{key:'wrong'})).status,401);
  assert.equal((await f.post({sessionIds:[foreign.id],waitMs:10000})).status,403);assert.equal(f.listeners(),0);
  const controller=new AbortController();const pending=f.post({sessionIds:[a.id],waitMs:10000},{signal:controller.signal});await waitFor(()=>f.listeners()===1);controller.abort();await assert.rejects(pending,{name:'AbortError'});await waitFor(()=>f.listeners()===0);
 }finally{await f.close();}
});
test('reset and stop wake waiting polls, and stale generation events cannot wake the next poll',async()=>{
 const f=await fixture();try{
  const a=f.create('1');let pending=f.post({sessionIds:[a.id],waitMs:10000});await waitFor(()=>f.listeners()===1);f.store.reset(a.id);assert.deepEqual((await pending).events,[]);assert.equal(f.listeners(),0);
  pending=f.post({sessionIds:[a.id],waitMs:10000});await waitFor(()=>f.listeners()===1);assert.equal(f.store.enqueue(a.id,1,'stale',{eventType:'like'}),false);assert.equal(f.listeners(),1);
  f.store.enqueue(a.id,2,'fresh',{eventType:'like'});const current=await pending;assert.equal(current.events[0].event.generation,2);assert.equal(current.events[0].event.eventId,'fresh');
  const e=current.events[0].event;f.store.ack(a.id,e.eventId,e.receipt);pending=f.post({sessionIds:[a.id],waitMs:10000});await waitFor(()=>f.listeners()===1);f.store.stop(a.id);assert.deepEqual((await pending).events,[]);assert.equal(f.listeners(),0);
 }finally{await f.close();}
});
test('shutdown cancels pending long polls before the HTTP grace deadline',async()=>{
 const f=await fixture();try{
  const a=f.create('1');const pending=f.post({sessionIds:[a.id],waitMs:10000});await waitFor(()=>f.listeners()===1);f.server.closePendingPolls();assert.deepEqual((await pending).events,[]);assert.equal(f.listeners(),0);
 }finally{await f.close();}
});
