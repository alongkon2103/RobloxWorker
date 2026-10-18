import test from 'node:test';
import assert from 'node:assert/strict';
import {Store} from '../src/store.mjs';
import {createAPI} from '../src/server.mjs';
const create=(s,owner='1',jobId='job')=>s.create({ownerRobloxId:owner,jobId,tiktokUsername:'live'+owner});
const actor=key=>({actorKey:'tiktok:'+key,robloxId:'42',robloxUsername:'Runner',tiktokUsername:key});
const add=(s,id,eventId,key,type)=>s.enqueue(id,s.get(id).generation,eventId,{...actor(key),eventType:type,effects:type==='join'?[]:[{key:'speed_boost',value:1,count:1}]},{actor:type==='join'?actor(key):undefined});
const ack=(s,id,e)=>s.ack(id,e.eventId,e.receipt);
const joined=(s,id,key)=>{add(s,id,'joined-'+key,key,'join');ack(s,id,s.poll(id));};
test('actor queues bypass another leased join while its own dependent effects remain blocked',()=>{
 const s=new Store(':memory:');try{
  const a=create(s);joined(s,a.id,'ready');add(s,a.id,'join-waiting','waiting','join');add(s,a.id,'waiting-like','waiting','like');add(s,a.id,'ready-like','ready','like');add(s,a.id,'ready-gift','ready','gift');
  const join=s.poll(a.id);assert.equal(join.eventId,'join-waiting');assert.equal(s.poll(a.id),null,'legacy FIFO bypassed leased join');
  const effects=s.pollActorBatch(a.id,32,{maxJoins:0});assert.deepEqual(effects.map(e=>e.eventId),['ready-like','ready-gift']);for(const e of effects)ack(s,a.id,e);
  assert.deepEqual(s.pollActorBatch(a.id,32,{maxJoins:0}),[]);ack(s,a.id,join);assert.equal(s.pollActorBatch(a.id,32,{maxJoins:0})[0].eventId,'waiting-like');
 }finally{s.close();}
});
test('actor queues cap new joins, serve effects with no join slots, and invalidate failed join dependents',()=>{
 const s=new Store(':memory:');try{
  const a=create(s);joined(s,a.id,'ready');for(let i=0;i<12;i++){add(s,a.id,'join'+i,'new'+i,'join');add(s,a.id,'gift'+i,'new'+i,'gift');}add(s,a.id,'ready-like','ready','like');
  const first=s.pollActorBatch(a.id,32,{maxJoins:8});assert.equal(first.filter(e=>e.eventType==='join').length,8);assert.equal(first.filter(e=>e.eventType==='gift').length,0);const ready=first.find(e=>e.eventId==='ready-like');assert.ok(ready);ack(s,a.id,ready);
  add(s,a.id,'ready-gift','ready','gift');assert.deepEqual(s.pollActorBatch(a.id,32,{maxJoins:0}).map(e=>e.eventId),['ready-gift']);
  const failed=first.find(e=>e.eventId==='join0');s.ack(a.id,failed.eventId,failed.receipt,{success:false,retry:false});assert.equal(s.actor(a.id,1,'tiktok:new0'),null);assert.deepEqual(s.pollActorBatch(a.id,32,{maxJoins:0}),[]);
 }finally{s.close();}
});
test('actor queues rotate actor prefixes fairly and retry blocks only its own actor',()=>{
 let now=1000;const s=new Store(':memory:',{now:()=>now,leaseMs:5000});try{
  const a=create(s);joined(s,a.id,'a');joined(s,a.id,'b');add(s,a.id,'a1','a','like');add(s,a.id,'a2','a','gift');add(s,a.id,'b1','b','like');add(s,a.id,'b2','b','gift');
  const batch=s.pollActorBatch(a.id,32,{maxJoins:0});assert.deepEqual(batch.map(e=>e.eventId),['a1','b1','a2','b2']);
  s.ack(a.id,batch[0].eventId,batch[0].receipt,{success:false,retry:true});ack(s,a.id,batch[1]);ack(s,a.id,batch[3]);add(s,a.id,'b3','b','follow');
  const retry=s.pollActorBatch(a.id,32,{maxJoins:0});assert.deepEqual(retry.map(e=>e.eventId),['a1','b3']);for(const e of retry)ack(s,a.id,e);
  assert.deepEqual(s.pollActorBatch(a.id,32,{maxJoins:0}),[]);now+=5001;assert.equal(s.pollActorBatch(a.id,32,{maxJoins:0})[0].eventId,'a2');
  s.reset(a.id);assert.deepEqual(s.pollActorBatch(a.id,32,{maxJoins:8}),[]);assert.throws(()=>s.ack(a.id,batch[2].eventId,batch[2].receipt),/invalid_receipt/);
 }finally{s.close();}
});
const config={bridgeKey:'b'.repeat(32),adminKey:'a'.repeat(32),giftMap:{},tikkiesEnabled:false};
test('HTTP actor queue mode validates input and shares eight new join slots across selected sessions',async()=>{
 const s=new Store(':memory:');const server=createAPI(s,config);await new Promise(r=>server.listen(0,'127.0.0.1',r));
 const post=async body=>{const r=await fetch(`http://127.0.0.1:${server.address().port}/v1/servers/job/poll`,{method:'POST',headers:{authorization:`Bearer ${config.bridgeKey}`,'content-type':'application/json'},body:JSON.stringify(body)});return {status:r.status,...await r.json()};};
 try{
  const sessions=[create(s,'1'),create(s,'2')],foreign=create(s,'3','foreign');for(const a of sessions){joined(s,a.id,'ready');for(let i=0;i<10;i++)add(s,a.id,'join'+i,'new'+i,'join');add(s,a.id,'like','ready','like');}add(s,foreign.id,'foreign','viewer','join');
  for(const body of [{actorQueues:1},{actorQueues:null},{actorQueues:true,maxJoins:-1},{actorQueues:true,maxJoins:9},{actorQueues:true,maxJoins:'8'}])assert.equal((await post(body)).status,400);
  const first=await post({actorQueues:true,maxEventsPerSession:32,maxJoins:8,sessionIds:sessions.map(a=>a.id)});assert.equal(first.events.filter(e=>e.event.eventType==='join').length,8);assert.equal(first.events.filter(e=>e.event.eventType==='like').length,2);assert.ok(first.events.every(e=>sessions.some(a=>a.id===e.sessionId)));
  for(const a of sessions)assert.equal(first.events.filter(e=>e.sessionId===a.id&&e.event.eventType==='join').length,4);
  for(const {sessionId,event:e}of first.events.filter(e=>e.event.eventType==='like'))ack(s,sessionId,e);
  for(const a of sessions)add(s,a.id,'gift','ready','gift');const next=await post({actorQueues:true,maxEventsPerSession:32,maxJoins:0,sessionIds:sessions.map(a=>a.id)});assert.equal(next.events.length,2);assert.ok(next.events.every(e=>e.event.eventType==='gift'));
  for(const {sessionId,event:e}of first.events.filter(e=>e.event.eventType==='join'))ack(s,sessionId,e);
  const one=await post({actorQueues:true,maxEventsPerSession:32,maxJoins:1,sessionIds:sessions.map(a=>a.id)}),two=await post({actorQueues:true,maxEventsPerSession:32,maxJoins:1,sessionIds:sessions.map(a=>a.id)});assert.equal(one.events.length,1);assert.equal(two.events.length,1);assert.notEqual(one.events[0].sessionId,two.events[0].sessionId);
 }finally{await new Promise(r=>server.close(r));s.close();}
});
test('actor queue lease renewal and join expiry preserve binding cleanup and run isolation',()=>{
 let now=1000;const s=new Store(':memory:',{now:()=>now,eventTTL:10000,leaseMs:5000});try{
  const a=create(s);joined(s,a.id,'ready');add(s,a.id,'slow','waiting','join');const first=s.pollActorBatch(a.id,1,{maxJoins:1})[0];now+=5001;
  const renewed=s.pollActorBatch(a.id,1,{maxJoins:1})[0];assert.equal(renewed.eventId,first.eventId);assert.notEqual(renewed.receipt,first.receipt);assert.throws(()=>ack(s,a.id,first),/invalid_receipt/);
  now=7000;add(s,a.id,'dependent','waiting','gift');add(s,a.id,'unrelated','ready','gift');now=11001;
  const next=s.pollActorBatch(a.id,32,{maxJoins:0});assert.deepEqual(next.map(e=>e.eventId),['unrelated']);assert.equal(s.actor(a.id,1,'tiktok:waiting'),null);
  s.reset(a.id);assert.deepEqual(s.pollActorBatch(a.id,32,{maxJoins:8}),[]);assert.throws(()=>ack(s,a.id,next[0]),/invalid_receipt/);s.stop(a.id);assert.throws(()=>s.pollActorBatch(a.id,32,{maxJoins:8}),/session_inactive/);
 }finally{s.close();}
});
const waitFor=async predicate=>{const until=performance.now()+2000;while(!predicate()){if(performance.now()>until)assert.fail('actor long poll did not subscribe');await new Promise(r=>setTimeout(r,1));}};
test('actor long poll wakes for another ready actor and ACK renews a zero-join-quota wait',async()=>{
 const s=new Store(':memory:');const server=createAPI(s,config);await new Promise(r=>server.listen(0,'127.0.0.1',r));
 const a=create(s);const post=async maxJoins=>{const r=await fetch(`http://127.0.0.1:${server.address().port}/v1/servers/job/poll`,{method:'POST',headers:{authorization:`Bearer ${config.bridgeKey}`,'content-type':'application/json'},body:JSON.stringify({sessionIds:[a.id],actorQueues:true,maxJoins,maxEventsPerSession:32,waitMs:10000})});return r.json();};
 try{
  joined(s,a.id,'ready');add(s,a.id,'slow','waiting','join');const slow=s.poll(a.id);add(s,a.id,'pending','next','join');
  let pending=post(0);await waitFor(()=>s.changes.listenerCount('change')===1);add(s,a.id,'ready-effect','ready','gift');const ready=await pending;assert.deepEqual(ready.events.map(e=>e.event.eventId),['ready-effect']);ack(s,a.id,ready.events[0].event);
  pending=post(0);await waitFor(()=>s.changes.listenerCount('change')===1);ack(s,a.id,slow);assert.deepEqual((await pending).events,[]);assert.equal(s.changes.listenerCount('change'),0);
  assert.equal((await post(1)).events[0].event.eventId,'pending');
 }finally{server.closePendingPolls();await new Promise(r=>server.close(r));s.close();}
});
test('HTTP actor queue mode distributes the total event cap fairly across sessions',async()=>{
 const s=new Store(':memory:');const server=createAPI(s,config);await new Promise(r=>server.listen(0,'127.0.0.1',r));
 try{
  const sessions=['1','2','3','4'].map(owner=>create(s,owner));for(const a of sessions){joined(s,a.id,'ready');for(let i=0;i<40;i++)add(s,a.id,'gift'+i,'ready','gift');}
  const r=await fetch(`http://127.0.0.1:${server.address().port}/v1/servers/job/poll`,{method:'POST',headers:{authorization:`Bearer ${config.bridgeKey}`,'content-type':'application/json'},body:JSON.stringify({actorQueues:true,maxJoins:0,maxEventsPerSession:32})});const {events}=await r.json();assert.equal(events.length,100);for(const a of sessions)assert.equal(events.filter(e=>e.sessionId===a.id).length,25);
 }finally{await new Promise(r=>server.close(r));s.close();}
});
test('idle sibling channels do not waste available avatar join slots',async()=>{
 const s=new Store(':memory:');const server=createAPI(s,config);await new Promise(r=>server.listen(0,'127.0.0.1',r));
 try{
  const busy=create(s,'1');create(s,'2');for(let i=0;i<12;i++)add(s,busy.id,'join'+i,'new'+i,'join');
  const r=await fetch(`http://127.0.0.1:${server.address().port}/v1/servers/job/poll`,{method:'POST',headers:{authorization:`Bearer ${config.bridgeKey}`,'content-type':'application/json'},body:JSON.stringify({actorQueues:true,maxJoins:8,maxEventsPerSession:32})});const {events}=await r.json();assert.equal(events.length,8);assert.ok(events.every(e=>e.event.eventType==='join'&&e.sessionId===busy.id));
 }finally{await new Promise(r=>server.close(r));s.close();}
});
