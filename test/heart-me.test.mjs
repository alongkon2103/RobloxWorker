import test from 'node:test';
import assert from 'node:assert/strict';
import {Store} from '../src/store.mjs';
import {EventTranslator,compactMessage} from '../src/events.mjs';
import {validatePublication} from '../src/defaults.mjs';
test('published Heart Me 7934 joins its viewer and awards Fly once for the final gift quantity',async()=>{
 const publication=validatePublication({schemaVersion:1,universeId:'123',version:'heart-me',updatedAt:'2026-10-22T00:00:00Z',mappings:[{giftId:'7934',giftName:'Heart Me',eventKey:'fly',value:1,enabled:true}]},'123');
 const store=new Store(':memory:');
 try{
  const session=store.create({ownerRobloxId:'1',jobId:'job',tiktokUsername:'live',universeId:'123',giftMap:publication.giftMap,giftNames:publication.giftNames});
  const translator=new EventTranslator(store,{resolve:async()=>null,giftMap:{}});
  const raw=id=>compactMessage({type:'WebcastGiftMessage',data:{common:{msgId:id,roomId:'room'},user:{userId:'viewer',displayId:'viewer'},giftId:'7934',giftType:1,repeatCount:3,repeatEnd:true,groupId:'heart-combo'}});
  await translator.handle(session.id,1,raw('first'));
  const join=store.poll(session.id);assert.equal(join.avatarType,'bacon');store.ack(session.id,join.eventId,join.receipt);
  const event=store.poll(session.id);assert.equal(event.giftId,'7934');assert.deepEqual(event.effects,[{key:'fly',value:1,count:3}]);store.ack(session.id,event.eventId,event.receipt);
  await translator.handle(session.id,1,raw('duplicate'));assert.equal(store.poll(session.id),null);
 }finally{store.close();}
});
