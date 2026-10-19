import test from 'node:test';import assert from 'node:assert/strict';
import {Store} from '../src/store.mjs';import {EventTranslator,compactMessage} from '../src/events.mjs';
const make=s=>s.create({ownerRobloxId:'123',jobId:'j',tiktokUsername:'streamer',provider:'direct'});
const chat=(id,text)=>({type:'WebcastChatMessage',data:{common:{msgId:id},user:{userId:'90071992547409999',displayId:'viewer'},comment:text}});
const gift=(id,end,count=1)=>({type:'WebcastGiftMessage',data:{common:{msgId:id},user:{userId:'90071992547409999',displayId:'viewer'},giftId:99,groupId:'combo-1',giftDetails:{giftType:1},repeatEnd:end,repeatCount:count}});
test('join then mapped final combo only once and round cancels pending lookup',async()=>{
 const s=new Store(':memory:');const session=make(s);const translator=new EventTranslator(s,{resolve:async n=>({id:'321',name:n}),giftMap:{99:{key:'rocket',value:1}},maxActors:30});
 await translator.handle(session.id,session.generation,compactMessage(chat('1','@ Cute_Runner')));
 const bacon=s.poll(session.id);assert.equal(bacon.avatarType,'bacon');s.ack(session.id,bacon.eventId,bacon.receipt);
 const join=s.poll(session.id);assert.equal(join.eventType,'join');assert.equal(join.robloxId,'321');assert.equal(join.actorKey,'tiktok:90071992547409999');s.ack(session.id,join.eventId,join.receipt);
 await translator.handle(session.id,1,compactMessage(gift('2',false,2)));assert.equal(s.poll(session.id),null);
 await translator.handle(session.id,1,compactMessage(gift('3',true,3)));const g=s.poll(session.id);assert.equal(g.effects[0].count,3);s.ack(session.id,g.eventId,g.receipt);
 await translator.handle(session.id,1,compactMessage(gift('4',true,3)));assert.equal(s.poll(session.id),null);
 let release;const delayed=new EventTranslator(s,{resolve:()=>new Promise(r=>release=r),giftMap:{},maxActors:30});
 s.reset(session.id);const pending=delayed.handle(session.id,2,compactMessage(chat('5','@Other_User')));s.reset(session.id);release({id:'555',name:'Other_User'});await pending;
 assert.equal(s.poll(session.id),null);assert.equal(s.actor(session.id,3,'tiktok:90071992547409999'),null);s.close();
});
test('durable inbox persists retry at queue capacity',()=>{
 const s=new Store(':memory:',{maxQueue:1});const a=make(s);
 s.ingest(a.id,a.generation,[compactMessage(chat('1','@Runner_1'))]);
 assert.equal(s.inbox(a.id).sourceId,'WebcastChatMessage:1');
 s.ingest(a.id,a.generation,[compactMessage(chat('1','@Runner_1'))]);assert.equal(s.inboxDepth(a.id),1);
 s.finishInbox(s.inbox(a.id).seq);assert.equal(s.inbox(a.id),null);s.close();
});
test('rejects unacknowledgeable IDs and preserves large string user IDs',()=>{
 assert.equal(compactMessage(chat('\n','@Runner')),null);
 const unsafe=chat('ok','@Runner');unsafe.data.user.userId=90071992547409999;assert.equal(compactMessage(unsafe),null);
 assert.equal(compactMessage(chat('ok','@Runner')).data.user.userId,'90071992547409999');
});

test('gift combo receipts survive round reset, session replacement and SQLite restart',async()=>{
 const {mkdtempSync,rmSync}=await import('node:fs');const {tmpdir}=await import('node:os');const {join}=await import('node:path');
 const dir=mkdtempSync(join(tmpdir(),'gift-receipts-'));let s;
 try{
  s=new Store(join(dir,'db.sqlite'));let session=make(s);let tr=new EventTranslator(s,{resolve:async()=>({id:'321',name:'Runner'}),giftMap:{99:{key:'gojo',value:1}}});
  const joinActor=async()=>{await tr.handle(session.id,s.get(session.id).generation,compactMessage(chat('join','hello everyone!')));const e=s.poll(session.id);s.ack(session.id,e.eventId,e.receipt);};
  await joinActor();await tr.handle(session.id,1,compactMessage(gift('first',true,3)));let e=s.poll(session.id);s.ack(session.id,e.eventId,e.receipt);
  s.reset(session.id);await joinActor();await tr.handle(session.id,2,compactMessage(gift('retry',true,3)));assert.equal(s.poll(session.id),null,'Combo replayed after round reset');
  s.stop(session.id);s.close();s=new Store(join(dir,'db.sqlite'));session=make(s);tr=new EventTranslator(s,{resolve:async()=>({id:'321',name:'Runner'}),giftMap:{99:{key:'gojo',value:1}}});await joinActor();
  await tr.handle(session.id,1,compactMessage(gift('reconnected',true,3)));assert.equal(s.poll(session.id),null,'Combo replayed after reconnect/restart');
  const newCombo=gift('new',true,1);newCombo.data.groupId='combo-2';await tr.handle(session.id,1,compactMessage(newCombo));assert.equal(s.poll(session.id).effects[0].key,'gojo');
 }finally{s?.close();rmSync(dir,{recursive:true,force:true});}
});
