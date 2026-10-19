import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,rmSync} from 'node:fs';import {tmpdir} from 'node:os';import {join} from 'node:path';
import {Store} from '../src/store.mjs';import {EventTranslator,compactMessage} from '../src/events.mjs';
const actor={actorKey:'tiktok:viewer',avatarType:'bacon',robloxId:'0',robloxUsername:'',tiktokUsername:'viewer'};
const follow=id=>compactMessage({type:'WebcastFollowMessage',data:{common:{msgId:id,roomId:'room'},user:{userId:'viewer',displayId:'viewer'}}});
const make=(s,owner='1',stream='live',universeId='123')=>{const a=s.create({ownerRobloxId:owner,jobId:'j',tiktokUsername:stream,universeId});s.enqueue(a.id,a.generation,'join',{...actor,eventType:'join',effects:[]},{actor});const e=s.poll(a.id);s.ack(a.id,e.eventId,e.receipt);return a;};
const take=(s,id)=>{const e=s.poll(id);if(e)s.ack(id,e.eventId,e.receipt);return e;};
test('Follow cooldown is exactly600 seconds per channel, universe and TikTok actor',async()=>{
 let now=1000;const s=new Store(':memory:',{now:()=>now,sessionTTL:10000000});const a=make(s),b=make(s,'2','other');const tr=new EventTranslator(s,{resolve:async()=>null,giftMap:{}});
 try{
  await tr.handle(a.id,1,follow('first'));assert.equal(take(s,a.id).eventType,'follow');now+=599999;await tr.handle(a.id,1,follow('early'));assert.equal(take(s,a.id),null);
  await tr.handle(b.id,1,follow('channel'));assert.equal(take(s,b.id).eventType,'follow');
  const other={...actor,actorKey:'tiktok:other',tiktokUsername:'other'};s.enqueue(a.id,1,'join-other',{...other,eventType:'join',effects:[]},{actor:other});take(s,a.id);
  await tr.handle(a.id,1,compactMessage({type:'WebcastFollowMessage',data:{common:{msgId:'other-actor'},user:{userId:'other'}}}));assert.equal(take(s,a.id).eventType,'follow');
  now++;await tr.handle(a.id,1,follow('due'));assert.equal(take(s,a.id).eventType,'follow');await tr.handle(a.id,1,follow('early'));assert.equal(take(s,a.id),null);
 }finally{s.close();}
});
test('Follow cooldown survives reset, session replacement and process restart without consuming a queue-full reward',async()=>{
 let now=1000,s;const dir=mkdtempSync(join(tmpdir(),'follow-cooldown-'));const file=join(dir,'db');let a;
 const translator=()=>new EventTranslator(s,{resolve:async()=>null,giftMap:{}});
 try{
  s=new Store(file,{now:()=>now,maxQueue:1,sessionTTL:10000000});a=make(s);s.enqueue(a.id,1,'busy',{eventType:'gift'});await assert.rejects(translator().handle(a.id,1,follow('award')),/queue_full/);take(s,a.id);
  await translator().handle(a.id,1,follow('award'));assert.equal(take(s,a.id).eventType,'follow');s.reset(a.id);s.enqueue(a.id,2,'join2',{...actor,eventType:'join',effects:[]},{actor});take(s,a.id);await translator().handle(a.id,2,follow('reset'));assert.equal(take(s,a.id),null);
  s.stop(a.id);s.close();s=new Store(file,{now:()=>now,maxQueue:1,sessionTTL:10000000});a=make(s,'1','live');await translator().handle(a.id,1,follow('restart'));assert.equal(take(s,a.id),null);now+=600000;await translator().handle(a.id,1,follow('next'));assert.equal(take(s,a.id).eventType,'follow');
  s.stop(a.id);const otherUniverse=make(s,'1','live','456');await translator().handle(otherUniverse.id,1,follow('new-universe'));assert.equal(take(s,otherUniverse.id).eventType,'follow');
 }finally{s?.close();rmSync(dir,{recursive:true,force:true});}
});
test('old database gains cooldown tables without changing session authentication or existing actors',async()=>{
 const {DatabaseSync}=await import('node:sqlite');const dir=mkdtempSync(join(tmpdir(),'bacon-migration-'));const file=join(dir,'db');let s;
 try{
  s=new Store(file);const a=s.create({ownerRobloxId:'1',jobId:'j',tiktokUsername:'live',universeId:'123'});const legacy={actorKey:actor.actorKey,robloxId:'42',robloxUsername:'Runner',tiktokUsername:'viewer'};s.enqueue(a.id,1,'legacy-join',{...legacy,eventType:'join',effects:[]},{actor:legacy});take(s,a.id);s.close();const old=new DatabaseSync(file);old.exec('DROP TABLE direct_follow_cooldowns; DROP TABLE direct_avatar_lookups');old.close();
  s=new Store(file);assert.equal(s.authenticate(a.id,a.token).owner_id,'1');assert.equal(s.actor(a.id,1,actor.actorKey).robloxId,'42');assert.equal(s.actor(a.id,1,actor.actorKey).avatarType,undefined);
  const tr=new EventTranslator(s,{resolve:async()=>null,giftMap:{}});await tr.handle(a.id,1,follow('first-after-migration'));assert.equal(take(s,a.id).eventType,'follow');
 }finally{s?.close();rmSync(dir,{recursive:true,force:true});}
});
