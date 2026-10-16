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
