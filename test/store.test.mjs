import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {Store} from '../src/store.mjs';
const make=(s,owner='1')=>s.create({ownerRobloxId:owner,jobId:'job-'+owner,tiktokUsername:'live'+owner,provider:'direct'});
test('durable FIFO, scoped auth/receipts, reset and expired lease',()=>{
 const dir=mkdtempSync(join(tmpdir(),'bridge-')); const file=join(dir,'db.sqlite'); let now=1000;
 let s=new Store(file,{now:()=>now,eventTTL:60000,leaseMs:5000,maxQueue:2,sessionTTL:90000});
 try {
  const a=make(s), b=make(s,'2');
  assert.throws(()=>make(s),/owner_busy/);
  assert.throws(()=>s.authenticate(a.id,b.token),/unauthorized/);
  s.enqueue(a.id,a.generation,'e1',{eventType:'join'});
  s.enqueue(a.id,a.generation,'e1',{eventType:'join'});
  s.enqueue(a.id,a.generation,'e2',{eventType:'gift'});
  assert.throws(()=>s.enqueue(a.id,a.generation,'e3',{}),/queue_full/);
  const first=s.poll(a.id); assert.equal(first.eventId,'e1'); assert.equal(s.poll(a.id),null);
  assert.throws(()=>s.ack(b.id,first.eventId,first.receipt),/invalid_receipt/);
  s.close(); s=new Store(file,{now:()=>now,eventTTL:60000,leaseMs:5000,maxQueue:2,sessionTTL:90000});
  assert.equal(s.poll(a.id),null); now+=5001;
  const retry=s.poll(a.id); assert.equal(retry.eventId,'e1'); assert.notEqual(retry.receipt,first.receipt);
  assert.throws(()=>s.ack(a.id,'e1',first.receipt),/invalid_receipt/);
  s.ack(a.id,'e1',retry.receipt); s.ack(a.id,'e1',retry.receipt);
  assert.equal(s.poll(a.id).eventId,'e2');
  s.reset(a.id); assert.equal(s.poll(a.id),null);
  assert.equal(s.enqueue(a.id,a.generation,'old',{}),false);
  assert.equal(s.get(a.id).generation,2);
  now+=90001; s.expire(); assert.equal(s.get(a.id).status,'expired');
 }finally{s.close();rmSync(dir,{recursive:true,force:true});}
});
test('expired join clears actor and dependent gifts in poll and prune',()=>{
 for(const via of ['poll','prune']){
  let now=1000;const s=new Store(':memory:',{now:()=>now,eventTTL:10000});const a=make(s);
  const actor={actorKey:'tiktok:viewer',robloxId:'321',robloxUsername:'Runner',tiktokUsername:'viewer'};
  s.enqueue(a.id,1,'join-1',{...actor,eventType:'join',effects:[]},{actor});
  now+=5000;s.enqueue(a.id,1,'gift-1',{...actor,eventType:'gift',effects:[{key:'rocket',value:1,count:1}]});
  now+=5001;s.heartbeat(a.id);if(via==='prune')s.prune();
  assert.equal(s.poll(a.id),null);assert.equal(s.actor(a.id,1,actor.actorKey),null);
  s.enqueue(a.id,1,'join-2',{...actor,eventType:'join',effects:[]},{actor});
  const event=s.poll(a.id);assert.equal(event.eventId,'join-2');s.ack(a.id,event.eventId,event.receipt);s.close();
 }
});
test('batch delivery preserves FIFO, active leases, join barriers and partial retries',()=>{
 let now=1000;const s=new Store(':memory:',{now:()=>now,leaseMs:5000});const a=make(s);
 try{
  const actor={actorKey:'tiktok:viewer',robloxId:'321'};
  s.enqueue(a.id,1,'join',{...actor,eventType:'join'},{actor});
  s.enqueue(a.id,1,'gift',{...actor,eventType:'gift'});
  s.enqueue(a.id,1,'like',{...actor,eventType:'like'});
  assert.deepEqual(s.pollBatch(a.id,32).map(e=>e.eventId),['join']);
  assert.deepEqual(s.pollBatch(a.id,32),[]);
  now+=5001;const join=s.poll(a.id);s.ack(a.id,join.eventId,join.receipt);
  const effects=s.pollBatch(a.id,32);assert.deepEqual(effects.map(e=>e.eventId),['gift','like']);
  s.ack(a.id,effects[0].eventId,effects[0].receipt,{success:false,retry:true});
  const retry=s.pollBatch(a.id,32);assert.deepEqual(retry.map(e=>e.eventId),['gift']);
  s.ack(a.id,retry[0].eventId,retry[0].receipt);assert.deepEqual(s.pollBatch(a.id,32),[]);
  now+=5001;const last=s.poll(a.id);assert.equal(last.eventId,'like');s.ack(a.id,last.eventId,last.receipt);
  s.enqueue(a.id,1,'before',{eventType:'gift'});s.enqueue(a.id,1,'rejoin',{...actor,eventType:'join'},{actor});s.enqueue(a.id,1,'after',{...actor,eventType:'gift'});
  const batch=s.pollBatch(a.id,32);assert.deepEqual(batch.map(e=>e.eventId),['before','rejoin']);
  s.ack(a.id,batch[0].eventId,batch[0].receipt);s.ack(a.id,batch[1].eventId,batch[1].receipt,{success:false,retry:false});
  assert.deepEqual(s.pollBatch(a.id,32),[]);assert.equal(s.actor(a.id,1,actor.actorKey),null);
 }finally{s.close();}
});
test('existing inbox migration retains raw messages and actor order with bounded retry backoff',async()=>{
 const {DatabaseSync}=await import('node:sqlite');const dir=mkdtempSync(join(tmpdir(),'inbox-migration-'));const file=join(dir,'db');let now=1000,s;
 try{
  s=new Store(file,{now:()=>now});const a=make(s);const message=(sourceId,user)=>({sourceId,type:'WebcastChatMessage',data:{user:{userId:user},comment:'@Runner'}});
  s.ingest(a.id,1,[message('first','waiting'),message('same-actor','waiting'),message('other-actor','ready')]);s.close();
  const old=new DatabaseSync(file);old.exec('DROP INDEX inbox_actor; ALTER TABLE inbox DROP COLUMN actor_key; ALTER TABLE inbox DROP COLUMN retry_at; ALTER TABLE inbox DROP COLUMN attempts');old.close();
  s=new Store(file,{now:()=>now});const first=s.inbox(a.id);assert.equal(first.sourceId,'first');assert.equal(first.data.comment,'@Runner');s.deferInbox(first.seq);
  assert.equal(s.inbox(a.id).sourceId,'other-actor');s.finishInbox(s.inbox(a.id).seq);assert.equal(s.inbox(a.id),null);
  now+=1000;assert.equal(s.inbox(a.id).sourceId,'first');
  for(let i=0;i<7;i++){s.deferInbox(first.seq);const row=s.db.prepare('SELECT retry_at,expires_at FROM inbox WHERE seq=?').get(first.seq);assert.ok(row.retry_at-now<=30000);assert.ok(row.retry_at<=row.expires_at);now=row.retry_at;}
  assert.equal(s.inbox(a.id),null);assert.equal(s.inboxDepth(a.id),0);
 }finally{s?.close();rmSync(dir,{recursive:true,force:true});}
});
