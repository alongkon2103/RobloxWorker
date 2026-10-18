import test from 'node:test';import assert from 'node:assert/strict';
import {Store} from '../src/store.mjs';import {createAPI} from '../src/server.mjs';import {PublishedDefaults} from '../src/defaults.mjs';import {GAME_EFFECT_KEYS} from '../src/effect-keys.mjs';
test('HTTP direct defaults snapshot, override and universe isolation; all ten keys pass ingest',async()=>{
 const store=new Store(':memory:');const cfg={bridgeKey:'b'.repeat(32),adminKey:'a'.repeat(32),tikkiesEnabled:true,giftMap:{}};
 const defaults=new PublishedDefaults(store,{universeId:'10771081714',url:'https://unused',token:'x'},{fetchFn:async()=>new Response(JSON.stringify({schemaVersion:1,universeId:'10771081714',version:'v1',updatedAt:'2026-10-18T00:00:00Z',mappings:GAME_EFFECT_KEYS.map((key,i)=>({giftId:String(i+1),giftName:"Gift "+i,eventKey:key,value:1,enabled:true}))}))});
 const server=createAPI(store,cfg,{defaults});await new Promise(r=>server.listen(0,'127.0.0.1',r));
 const req=async(path,key,body)=>{const r=await fetch(`http://127.0.0.1:${server.address().port}`+path,{method:body===undefined?'GET':'POST',headers:{authorization:'Bearer '+key,'content-type':'application/json'},body:JSON.stringify(body)});return {status:r.status,body:await r.json()};};
 try{
  const body={ownerRobloxId:'1',jobId:'job',tiktokUsername:'alice',universeId:'10771081714'};
  assert.equal((await req('/v1/sessions',cfg.bridgeKey,{...body,universeId:undefined})).status,400);
  assert.equal((await req('/v1/sessions',cfg.bridgeKey,body)).status,503);await defaults.refresh();
  assert.equal((await req('/v1/direct/gift-mappings','wrong')).status,401);
  const preview=await req('/v1/direct/gift-mappings',cfg.bridgeKey);assert.equal(preview.body.giftMappings[0].giftName,'Gift 0');
  const a=await req('/v1/sessions',cfg.bridgeKey,body);assert.equal(a.status,201);assert.equal(a.body.giftMapVersion,'v1');assert.equal(a.body.joinMode,'both');assert.equal(Object.keys(a.body.giftMap).length,10);
  assert.equal((await req('/v1/sessions',cfg.bridgeKey,{...body,ownerRobloxId:'2',tiktokUsername:'bob',universeId:'2'})).status,403);
  const custom=await req('/v1/sessions',cfg.bridgeKey,{...body,ownerRobloxId:'2',tiktokUsername:'bob',giftMap:{}});assert.deepEqual(custom.body.giftMap,{});assert.equal(custom.body.giftMapSource,'override');
  const t=(await req('/v1/sessions',cfg.bridgeKey,{...body,ownerRobloxId:'3',tiktokUsername:'carol',provider:'tikkies'})).body;
  assert.deepEqual(t.giftMappings,[]);
  assert.equal((await req(`/v1/sessions/${a.body.id}`,t.token)).status,401);
  const own=await req(`/v1/sessions/${a.body.id}`,a.body.token);assert.equal(own.body.giftMappings[0].giftName,'Gift 0');
  const actor={generation:1,actorKey:'tiktok:viewer',robloxId:'456',robloxUsername:'Runner',tiktokUsername:'viewer'};const path=`/v1/admin/sessions/${t.id}/ingest`;
  assert.equal((await req(path,cfg.adminKey,{...actor,eventId:'join',eventType:'join',effects:[]})).status,200);
  for(const key of GAME_EFFECT_KEYS)assert.equal((await req(path,cfg.adminKey,{...actor,eventId:key,eventType:'gift',effects:[{key,value:1,count:2}]})).status,200,key);
  assert.equal((await req(`/v1/admin/sessions/${a.body.id}/ingest`,cfg.adminKey,{...actor,eventId:'duplicate-source',eventType:'gift',effects:[{key:'rocket',value:1,count:1}]})).status,403);
 }finally{await new Promise(r=>server.close(r));store.close();}
});
