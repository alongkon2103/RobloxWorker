import test from 'node:test';import assert from 'node:assert/strict';
import {Store} from '../src/store.mjs';import {EventTranslator,compactMessage} from '../src/events.mjs';
const raw=(type,id,extra={},user='viewer')=>({type,data:{common:{msgId:id},user:{userId:user,displayId:user},...extra}});
const like=(id,count,user)=>raw('WebcastLikeMessage',id,{count,total:999999},user);
const follow=id=>raw('WebcastSocialMessage',id,{common:{msgId:id,displayText:{key:'pm_main_follow_message_viewer_2'}}});
async function setup(store,owner='1'){
 const s=store.create({ownerRobloxId:owner,jobId:'j',tiktokUsername:'live'+owner});const tr=new EventTranslator(store,{resolve:async()=>({id:'42',name:'Runner'}),giftMap:{}});
 await tr.handle(s.id,s.generation,compactMessage(raw('WebcastChatMessage','join',{comment:'Runner'})));
 const e=store.poll(s.id);store.ack(s.id,e.eventId,e.receipt);return {s,tr,handle:m=>tr.handle(s.id,store.get(s.id).generation,compactMessage(m))};
}
const take=(store,id)=>{const e=store.poll(id);if(e)store.ack(id,e.eventId,e.receipt);return e;};
test('Direct likes count each viewer delta, carry remainder and deduplicate inside the same time bucket',async()=>{
 const store=new Store(':memory:');try{
  const a=await setup(store);await a.handle(like('a',19));assert.equal(take(store,a.s.id),null);
  await a.handle(like('b',1));assert.deepEqual(take(store,a.s.id).effects,[{key:'speed_boost',value:1,count:1}]);
  await a.handle(like('c',45));assert.equal(take(store,a.s.id).effects[0].count,2);
  await a.handle(like('c',45));assert.equal(take(store,a.s.id),null);
  await a.handle(like('d',15));assert.equal(take(store,a.s.id).effects[0].count,1);
  await a.handle(like('missing',20,'not-joined'));assert.equal(take(store,a.s.id),null);
 }finally{store.close();}
});
test('Follow awards Fly; shares, unrelated social messages and duplicates cannot award Fly',async()=>{
 const store=new Store(':memory:');try{
  const a=await setup(store);await a.handle(follow('f'));const e=take(store,a.s.id);assert.equal(e.eventType,'follow');assert.deepEqual(e.effects,[{key:'fly',value:1,count:1}]);
  await a.handle(follow('f'));assert.equal(take(store,a.s.id),null);
  await a.handle(raw('WebcastSocialMessage','share',{common:{msgId:'share',displayText:{key:'pm_main_share_message'}}}));assert.equal(take(store,a.s.id),null);
  await a.handle(raw('WebcastSocialMessage','unknown',{action:1}));assert.equal(take(store,a.s.id),null);
 }finally{store.close();}
});
test('Heart progress is owner scoped and queue backpressure never consumes a reward',async()=>{
 const store=new Store(':memory:',{maxQueue:1});try{
  const a=await setup(store),b=await setup(store,'2');await a.handle(like('a',19));await b.handle(like('b',1));assert.equal(take(store,b.s.id),null);
  store.enqueue(a.s.id,1,'busy',{eventType:'chat',effects:[]});await assert.rejects(a.handle(like('last',1)),/queue_full/);take(store,a.s.id);
  await a.handle(like('last',1));assert.equal(take(store,a.s.id).effects[0].count,1);
 }finally{store.close();}
});

test('heart progress persists after database restart, resets with race, and old packets cannot replay',async()=>{
 const {mkdtempSync,rmSync}=await import('node:fs'),{tmpdir}=await import('node:os'),{join}=await import('node:path');const dir=mkdtempSync(join(tmpdir(),'social-'));let store;
 try{
  store=new Store(join(dir,'db'));const a=await setup(store);await a.handle(like('old19',19));store.close();store=new Store(join(dir,'db'));
  let tr=new EventTranslator(store,{resolve:async()=>({id:'42',name:'Runner'}),giftMap:{}});await tr.handle(a.s.id,1,compactMessage(like('last1',1)));assert.equal(take(store,a.s.id).effects[0].count,1);
  const next=store.reset(a.s.id);await tr.handle(a.s.id,next.generation,compactMessage(raw('WebcastChatMessage','join2',{comment:'Runner'})));take(store,a.s.id);
  await tr.handle(a.s.id,next.generation,compactMessage(like('old19',19)));await tr.handle(a.s.id,next.generation,compactMessage(like('fresh1',1)));assert.equal(take(store,a.s.id),null);
  await tr.handle(a.s.id,next.generation,compactMessage(like('fresh19',19)));assert.equal(take(store,a.s.id).effects[0].count,1);
 }finally{store?.close();rmSync(dir,{recursive:true,force:true});}
});

test('dedicated follow messages are supported; invalid counts and room total are never counted',()=>{
 assert.equal(compactMessage(raw('WebcastFollowMessage','follow')).data.socialType,'follow');
 for(const count of [undefined,0,-1,1.5,'bad',200001])assert.equal(compactMessage(like('invalid',count)),null);
 assert.equal(compactMessage(like('delta','2')).data.likeCount,2);
});
test('Direct social defaults never apply to Tikkies provider sessions',async()=>{
 const store=new Store(':memory:');try{
  const s=store.create({ownerRobloxId:'7',jobId:'j',tiktokUsername:'tikkies',provider:'tikkies'});const tr=new EventTranslator(store,{resolve:async()=>({id:'42',name:'Runner'}),giftMap:{}});
  await tr.handle(s.id,1,compactMessage(raw('WebcastChatMessage','join',{comment:'Runner'})));take(store,s.id);
  await tr.handle(s.id,1,compactMessage(like('likes',20)));await tr.handle(s.id,1,compactMessage(follow('follow')));assert.equal(take(store,s.id),null);
 }finally{store.close();}
});
test('ordinary Direct chat cannot fill the effects queue or delay hearts',async()=>{
 const store=new Store(':memory:',{maxQueue:1});try{
  const a=await setup(store);await a.handle(raw('WebcastChatMessage','chat',{comment:'hello everyone!'}));
  await a.handle(like('hearts',20));assert.equal(take(store,a.s.id).eventType,'like');assert.equal(take(store,a.s.id),null);
  await a.handle(raw('WebcastChatMessage','explicit',{comment:'@New_Runner'}));assert.equal(take(store,a.s.id).eventType,'join');
 }finally{store.close();}
});
test('100 joined actors chatting and sending two heart waves drain before expiry in bounded batches',async()=>{
 let now=1000;const store=new Store(':memory:',{now:()=>now});try{
  const s=store.create({ownerRobloxId:'1',jobId:'j',tiktokUsername:'live'});const tr=new EventTranslator(store,{resolve:async name=>({id:42,name}),giftMap:{}});
  for(let i=0;i<100;i++){await tr.handle(s.id,1,compactMessage(raw('WebcastChatMessage','join-'+i,{comment:'@Runner'},'viewer'+i)));take(store,s.id);}
  for(let wave=0;wave<2;wave++)for(let i=0;i<100;i++){
   await tr.handle(s.id,1,compactMessage(raw('WebcastChatMessage','chat-'+wave+'-'+i,{comment:'Go go!!'},'viewer'+i)));
   await tr.handle(s.id,1,compactMessage(like('hearts-'+wave+'-'+i,20,'viewer'+i)));
  }
  let delivered=0,polls=0;while(store.public(store.get(s.id)).queueDepth){const batch=store.pollBatch(s.id,32);assert.ok(batch.length>0&&batch.length<=32);for(const e of batch){assert.deepEqual(e.effects,[{key:'speed_boost',value:1,count:1}]);store.ack(s.id,e.eventId,e.receipt);delivered++;}now+=500;polls++;}
  assert.equal(delivered,200);assert.equal(polls,7);assert.equal(store.db.prepare("SELECT COUNT(*) AS n FROM events WHERE status='expired'").get().n,0);
 }finally{store.close();}
});
