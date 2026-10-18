import test from 'node:test';import assert from 'node:assert/strict';import {Store} from '../src/store.mjs';import {EventTranslator,compactMessage} from '../src/events.mjs';import {loadConfig} from '../src/config.mjs';
const env={BRIDGE_API_KEY:'b'.repeat(32),ADMIN_API_KEY:'a'.repeat(32),EULER_TOKEN:'test'};
const message=(n,comment='Runner_'+n)=>compactMessage({type:'WebcastChatMessage',data:{common:{msgId:'join-'+n},user:{userId:'tik-'+n,displayId:'handle'+n,nickname:'ผู้ชม '+n},comment}});
test('default viewer capacity is 100 with an absolute configured ceiling of 100',()=>{
 assert.equal(loadConfig(env).maxActors,100);assert.equal(loadConfig({...env,MAX_VIEWERS_PER_STREAM:'1000'}).maxActors,100);
});
test('100 joined TikTok viewers fit, viewer 101 is rejected, existing viewer can rejoin',async()=>{
 const store=new Store(':memory:');try{
  const s=store.create({ownerRobloxId:'1',jobId:'j',tiktokUsername:'live'});const tr=new EventTranslator(store,{resolve:async n=>({id:123,name:n}),giftMap:{}});
  for(let i=1;i<=100;i++)assert.equal(await tr.handle(s.id,1,message(i)),true,'viewer '+i);
  assert.equal(store.actorCount(s.id,1),100);assert.equal(await tr.handle(s.id,1,message(101)),false);assert.equal(store.actorCount(s.id,1),100);
  const again=message(1);again.sourceId='join-again';assert.equal(await tr.handle(s.id,1,again),true);assert.equal(store.actorCount(s.id,1),100);
  assert.equal(store.actor(s.id,1,'tiktok:tik-1').tiktokDisplayName,'ผู้ชม 1');
 }finally{store.close();}
});
test('concurrent username lookups cannot overbook the 100th slot',async()=>{
 const store=new Store(':memory:');try{
  const s=store.create({ownerRobloxId:'1',jobId:'j',tiktokUsername:'live'});const tr=new EventTranslator(store,{resolve:async n=>({id:123,name:n}),giftMap:{},maxActors:100});
  const results=await Promise.all(Array.from({length:105},(_,i)=>tr.handle(s.id,1,message(i+1))));assert.equal(results.filter(Boolean).length,100);assert.equal(store.actorCount(s.id,1),100);
 }finally{store.close();}
});
test('a gift or nickname alone cannot spawn an avatar; a valid Roblox username is required',async()=>{
 const store=new Store(':memory:');try{
  const s=store.create({ownerRobloxId:'1',jobId:'j',tiktokUsername:'live'});const tr=new EventTranslator(store,{resolve:async n=>n==='MissingUser'?null:{id:123,name:n},giftMap:{5655:{key:'rainbow_cat',value:1}}});
  for(const type of ['WebcastGiftMessage','WebcastLikeMessage','WebcastSocialMessage']){
   const raw={type,data:{common:{msgId:type,displayText:{key:'pm_main_follow_message_viewer'}},user:{userId:'tik-1',displayId:'handle1',nickname:'ผู้ชม 1'},giftId:'5655',giftType:0,repeatCount:1,count:20}};
   assert.equal(await tr.handle(s.id,1,compactMessage(raw)),false);
  }
  for(const name of ['ชื่อเล่นใน TikTok','Roblox: Runner_1','MissingUser'])assert.equal(await tr.handle(s.id,1,message(1,name)),false);
  assert.equal(store.actorCount(s.id,1),0);assert.equal(await tr.handle(s.id,1,message(1,'@Runner_1')),true);
 }finally{store.close();}
});
