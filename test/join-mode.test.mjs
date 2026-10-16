import test from 'node:test';import assert from 'node:assert/strict';
import {Store} from '../src/store.mjs';import {EventTranslator,compactMessage} from '../src/events.mjs';
test('per-session at/plain/both join modes survive reset and do not leak',async()=>{
 const store=new Store(':memory:');const translate=new EventTranslator(store,{resolve:async name=>({id:123,name}),giftMap:{}});
 try{
  for(const [mode,accepted] of [['at',[true,false]],['plain',[false,true]],['both',[true,true]]]){
   const s=store.create({ownerRobloxId:String(100+accepted.length+['at','plain','both'].indexOf(mode)),jobId:'job',tiktokUsername:'stream_'+mode,joinMode:mode});
   assert.equal(s.joinMode,mode);
   for(const [i,text] of ['@Runner_Name','Runner_Name'].entries()){
    const m=compactMessage({type:'WebcastChatMessage',data:{msgId:mode+i,user:{userId:String(i+1),uniqueId:'viewer'},comment:text}});
    assert.equal(await translate.handle(s.id,1,m),accepted[i],mode+': '+text);
   }
   store.reset(s.id,'reset-mode');assert.equal(store.public(store.get(s.id)).joinMode,mode);
   store.setJoinMode(s.id,'both');assert.equal(store.get(s.id).join_mode,'both');
  }
 }finally{store.close();}
});
