import test from 'node:test';import assert from 'node:assert/strict';
import {mkdtempSync,rmSync} from 'node:fs';import {tmpdir} from 'node:os';import {join} from 'node:path';
import {Store} from '../src/store.mjs';import {PublishedDefaults,validatePublication} from '../src/defaults.mjs';
const cfg={universeId:'10771081714',url:'https://backend.aclassstore.com/api/games/defaults/10771081714/published',token:'t'.repeat(43),refreshMs:60000};
const pub=(version='v1',mappings=[{giftId:'99',giftName:'Gift',eventKey:'rocket',value:1,enabled:true}])=>({schemaVersion:1,universeId:cfg.universeId,version,updatedAt:'2026-10-18T00:00:00Z',mappings});
test('publication validates all rows atomically and accepts deliberate empty',()=>{
 assert.deepEqual(validatePublication(pub(),cfg.universeId).giftMap,{99:{key:'rocket',value:1}});
 assert.deepEqual(validatePublication(pub('empty',[]),cfg.universeId).giftMap,{});
 for(const body of [{...pub(),universeId:'2'},{...pub(),schemaVersion:2},{...pub(),version:''},{...pub(),updatedAt:'invalid'},pub('x',[{giftId:'99',eventKey:'gilgamesh',value:1,enabled:true}]),pub('x',[{giftId:'99',eventKey:'rocket',value:2,enabled:true}]),pub('x',[...pub().mappings,...pub().mappings])])assert.throws(()=>validatePublication(body,cfg.universeId));
});
test('single refresh, durable last-good cache, immutable session versions and explicit overrides',async()=>{
 const dir=mkdtempSync(join(tmpdir(),'defaults-'));let store;try{
  store=new Store(join(dir,'db.sqlite'));let response=pub(),status=200,calls=0;
  const fetchFn=async(url,options)=>{calls++;assert.equal(url,cfg.url);assert.equal(options.headers.authorization,'Bearer '+cfg.token);assert.equal(options.redirect,'error');await Promise.resolve();return new Response(JSON.stringify(response),{status});};
  const defaults=new PublishedDefaults(store,cfg,{fetchFn});assert.throws(()=>defaults.snapshot({giftMap:null}),/defaults_not_ready/);
  await Promise.all([defaults.refresh(),defaults.refresh()]);assert.equal(calls,1);
  const create=(n,extra={})=>store.create({ownerRobloxId:String(n),jobId:'j',tiktokUsername:'live'+n,...defaults.snapshot({giftMap:null,...extra})});
  const a=create(1);assert.equal(a.giftMapVersion,'v1');
  response=pub('v2',[{giftId:'99',eventKey:'shield',giftName:'Gift',value:1,enabled:true}]);await defaults.refresh();
  assert.equal(store.effectiveGiftMap(a.id)['99'].key,'rocket');store.reset(a.id);assert.equal(store.effectiveGiftMap(a.id)['99'].key,'rocket');
  const b=create(2);assert.equal(b.giftMapVersion,'v2');assert.equal(store.effectiveGiftMap(b.id)['99'].key,'shield');
  const override=create(3,{giftMap:{99:{key:'fly',value:1}}});assert.equal(override.giftMapSource,'override');assert.equal(store.effectiveGiftMap(override.id)['99'].key,'fly');
  for(const code of [404,503]){status=code;await defaults.refresh();assert.equal(defaults.snapshot({giftMap:null}).giftMapVersion,'v2');}
  status=200;response={bad:true};await defaults.refresh();assert.equal(defaults.snapshot({giftMap:null}).giftMapVersion,'v2');
  assert.throws(()=>defaults.snapshot({giftMap:null,universeId:'2'}),/defaults_universe_forbidden/);
  response=pub('empty',[]);await defaults.refresh();assert.deepEqual(defaults.snapshot({giftMap:null}).giftMap,{});
  store.close();store=new Store(join(dir,'db.sqlite'));const restarted=new PublishedDefaults(store,cfg,{fetchFn:async()=>{throw Error('offline');}});await restarted.refresh();assert.equal(restarted.snapshot({giftMap:null}).giftMapVersion,'empty');
 }finally{store?.close();rmSync(dir,{recursive:true,force:true});}
});

test('missing publication cannot create defaults, auth failures stay blocked, old static sessions freeze',async()=>{
 const store=new Store(':memory:');try{
  const old=store.create({ownerRobloxId:'1',jobId:'j',tiktokUsername:'old'});const custom=store.create({ownerRobloxId:'2',jobId:'j',tiktokUsername:'custom',giftMap:{99:{key:'fly',value:1}}});store.freezeLegacyGiftMaps({99:{key:'rocket',value:1}},cfg.universeId);
  assert.equal(store.get(custom.id).universe_id,cfg.universeId);assert.equal(store.effectiveGiftMap(custom.id)[99].key,'fly');
  assert.equal(store.effectiveGiftMap(old.id,{99:{key:'gojo',value:1}})[99].key,'rocket');
  let status=404;const defaults=new PublishedDefaults(store,cfg,{fetchFn:async()=>new Response(JSON.stringify(pub()),{status})});
  await defaults.refresh();assert.throws(()=>defaults.snapshot({giftMap:null}),/defaults_not_ready/);
  status=200;await defaults.refresh();status=403;await defaults.refresh();assert.throws(()=>defaults.snapshot({giftMap:null}),/defaults_access_denied/);
  status=503;await defaults.refresh();assert.throws(()=>defaults.snapshot({giftMap:null}),/defaults_access_denied/);
  status=200;await defaults.refresh();assert.equal(defaults.snapshot({giftMap:null}).giftMapVersion,'v1');
 }finally{store.close();}
});

test('auth denial survives service/database restart and cannot be bypassed with an override',async()=>{
 const dir=mkdtempSync(join(tmpdir(),'defaults-denial-'));let store;
 try{
  store=new Store(join(dir,'db'));let status=200;
  const fetchFn=async()=>new Response(JSON.stringify(pub()),{status});let defaults=new PublishedDefaults(store,cfg,{fetchFn});
  await defaults.refresh();status=403;await defaults.refresh();
  assert.throws(()=>defaults.snapshot({giftMap:{}}),/defaults_access_denied/);
  store.close();store=new Store(join(dir,'db'));defaults=new PublishedDefaults(store,cfg,{fetchFn});status=503;await defaults.refresh();
  assert.throws(()=>defaults.snapshot({giftMap:null}),/defaults_access_denied/);
  assert.throws(()=>defaults.snapshot({giftMap:{}}),/defaults_access_denied/);
  status=200;await defaults.refresh();assert.equal(defaults.snapshot({giftMap:{}}).giftMapSource,'override');
 }finally{store?.close();rmSync(dir,{recursive:true,force:true});}
});

test('Direct translator emits all ten published effects with actual quantity',async()=>{
 const {GAME_EFFECT_KEYS}=await import('../src/effect-keys.mjs');const {EventTranslator,compactMessage}=await import('../src/events.mjs');
 const store=new Store(':memory:');try{
  const mappings=GAME_EFFECT_KEYS.map((eventKey,i)=>({giftId:String(i+1),eventKey,value:1,enabled:true}));
  const defaults=new PublishedDefaults(store,cfg,{fetchFn:async()=>new Response(JSON.stringify(pub('all10',mappings)))});await defaults.refresh();
  const session=store.create({ownerRobloxId:'1',jobId:'job',tiktokUsername:'streamer',...defaults.snapshot({giftMap:null})});
  const tr=new EventTranslator(store,{resolve:async()=>({id:'123',name:'Runner'}),giftMap:{}});
  await tr.handle(session.id,1,compactMessage({type:'WebcastChatMessage',data:{common:{msgId:'join'},user:{userId:'viewer'},comment:'@Runner'}}));let e=store.poll(session.id);store.ack(session.id,e.eventId,e.receipt);
  for(const [i,key]of GAME_EFFECT_KEYS.entries()){
   await tr.handle(session.id,1,compactMessage({type:'WebcastGiftMessage',data:{common:{msgId:'gift-'+i,roomId:'room'},user:{userId:'viewer'},giftId:String(i+1),giftDetails:{giftType:0},repeatCount:3}}));
   e=store.poll(session.id);assert.deepEqual(e.effects,[{key,value:1,count:3}]);assert.equal(e.ownerRobloxId,'1');store.ack(session.id,e.eventId,e.receipt);
  }
 }finally{store.close();}
});
