import test from 'node:test';import assert from 'node:assert/strict';
import {Store} from '../src/store.mjs';import {Overlays} from '../src/overlay.mjs';import {createAPI} from '../src/server.mjs';
const route={version:'r1',length:100,points:[[0,0],[20,0],[20,20],[0,20]]};
const racer={id:'live:a',robloxId:'1',name:'Alice',distance:10,speed:16,topSpeed:20,rank:1,state:'Running',effects:[]};
const snapshot=(extra={})=>({round:'round1',phase:'Running',laps:2,metersPerStud:.28,route,racers:[{...racer}],...extra});
test('overlay isolation, exclusive leases, fresh takeover, stable profile, peaks and validation',()=>{
 const store=new Store(':memory:');let now=1000;const o=new Overlays(store.db,()=>now);
 try{
  const a=o.claim({ownerRobloxId:'1',jobId:'job1',claimId:'claim1'});const b=o.claim({ownerRobloxId:'2',jobId:'job2',claimId:'claim2'});
  assert.notEqual(a.readToken,b.readToken);assert.throws(()=>o.claim({ownerRobloxId:'1',jobId:'other',claimId:'other'}),/owner_busy/);
  o.publish(a.writeToken,{sequence:1,snapshot:snapshot()});assert.equal(o.read(b.readToken).snapshot,null);
  assert.throws(()=>o.publish(a.readToken,{sequence:2,snapshot:snapshot()}),/lease_expired/);
  assert.throws(()=>o.read(a.writeToken),/unauthorized/);assert.throws(()=>o.read('1'),/unauthorized/);
  now+=1000;o.publish(a.writeToken,{sequence:2,snapshot:snapshot({route:undefined,racers:[{...racer,topSpeed:16}]})});assert.equal(o.read(a.readToken).snapshot.racers[0].topSpeed,20);
  now+=1000;assert.throws(()=>o.publish(a.writeToken,{sequence:2,snapshot:snapshot()}),/stale/);
  assert.throws(()=>o.publish(a.writeToken,{sequence:3,snapshot:snapshot({racers:[{...racer,speed:1501}]})}),/invalid_racer/);
  o.publish(a.writeToken,{sequence:3,snapshot:snapshot({round:'round2',racers:[{...racer,topSpeed:16}]})});assert.equal(o.read(a.readToken).snapshot.racers[0].topSpeed,16);
  now+=1000;o.publish(a.writeToken,{sequence:100,snapshot:snapshot({racers:[{...racer,state:'Waiting'}]})});
  now+=46000;assert.equal(o.read(a.readToken).online,false);
  const renewed=o.claim({ownerRobloxId:'1',jobId:'job1',claimId:'claim1'});
  assert.notEqual(renewed.writeToken,a.writeToken);o.publish(renewed.writeToken,{sequence:1,snapshot:snapshot()});
  o.release(renewed.writeToken);
  const c=o.claim({ownerRobloxId:'1',jobId:'job3',claimId:'claim3'});
  assert.equal(c.readToken,a.readToken);assert.notEqual(c.writeToken,a.writeToken);assert.throws(()=>o.publish(a.writeToken,{sequence:4,snapshot:snapshot()}),/lease_expired/);
  const restarted=new Overlays(store.db,()=>now);const d=restarted.claim({ownerRobloxId:'1',jobId:'job3',claimId:'claim3'});assert.equal(d.readToken,a.readToken);
  assert.throws(()=>restarted.publish(d.writeToken,{sequence:1,snapshot:snapshot({route:undefined})}),/route_required/);
 }finally{store.close();}
});
test('overlay HTTP: bridge-only claim, read-only URL, static CSP and real snapshot',async()=>{
 const store=new Store(':memory:');const config={bridgeKey:'b'.repeat(32),adminKey:'a'.repeat(32),giftMap:{}};const server=createAPI(store,config,{thumbnailFetch:async()=>({ok:true,json:async()=>({data:[{targetId:1,state:'Completed',imageUrl:'https://tr.rbxcdn.com/avatar.png'}]})})});await new Promise(r=>server.listen(0,'127.0.0.1',r));const origin=`http://127.0.0.1:${server.address().port}`;
 const call=(path,key,body)=>fetch(origin+path,{method:body?'POST':'GET',headers:{authorization:`Bearer ${key}`,'content-type':'application/json'},body:body?JSON.stringify(body):undefined});
 try{
  assert.equal((await call('/v1/overlays/claim','bad',{ownerRobloxId:'1',jobId:'j',claimId:'c'})).status,401);
  const claim=await (await call('/v1/overlays/claim',config.bridgeKey,{ownerRobloxId:'1',jobId:'j',claimId:'c'})).json();
  assert.equal((await call('/v1/overlays/publish',claim.readToken,{sequence:1,snapshot:snapshot()})).status,401);
  assert.equal((await call('/v1/overlays/publish',claim.writeToken,{sequence:1,snapshot:snapshot()})).status,200);
  await new Promise(r=>setTimeout(r,410));
  assert.equal((await call('/v1/overlays/batch',config.bridgeKey,{items:[{writeToken:claim.writeToken,sequence:2,snapshot:snapshot({route:undefined})}],route})).status,200);
  const state=await (await call('/v1/overlay/state',claim.readToken)).json();assert.equal(state.snapshot.racers[0].name,'Alice');assert.equal(state.snapshot.racers[0].avatarUrl,'https://tr.rbxcdn.com/avatar.png');assert.equal(state.writeToken,undefined);
  const html=await fetch(origin+'/overlay?view=map');assert.equal(html.status,200);assert.match(html.headers.get('content-security-policy'),/default-src 'self'/);assert.match(await html.text(),/app.js/);
  assert.equal((await fetch(origin+'/overlay/../../.env')).status,404);
 }finally{server.closeAllConnections();await new Promise(r=>server.close(r));store.close();}
});
