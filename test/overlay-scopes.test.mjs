import test from 'node:test';import assert from 'node:assert/strict';
import {Store} from '../src/store.mjs';import {Overlays} from '../src/overlay.mjs';import {createAPI} from '../src/server.mjs';
const snapshot=name=>({round:'r',phase:'Running',laps:2,metersPerStud:.28,route:{version:'r',length:100,points:[[0,0],[1,0],[1,1],[0,1]]},racers:[{id:'a',robloxId:'1',name,distance:0,speed:16,rank:1,state:'Running',effects:[]}]});
test('scoped profiles preserve legacy and isolate owner across universes',()=>{
 const store=new Store(':memory:');let now=1000;const o=new Overlays(store.db,()=>now);
 try{
  const legacy=o.claim({ownerRobloxId:'1',jobId:'old',claimId:'old'});
  const a=o.profile('1','100'),b=o.profile('1','200');
  assert.notEqual(a.readToken,b.readToken);assert.notEqual(a.readToken,legacy.readToken);
  assert.equal(o.profile('1','100').readToken,a.readToken);assert.equal(o.live.size,1);
  const la=o.claim({ownerRobloxId:'1',universeId:'100',jobId:'a',claimId:'a'}),lb=o.claim({ownerRobloxId:'1',universeId:'200',jobId:'b',claimId:'b'});
  assert.equal(la.readToken,a.readToken);assert.equal(lb.readToken,b.readToken);
  o.publish(la.writeToken,{sequence:1,snapshot:snapshot('A')},'100');
  o.publish(lb.writeToken,{sequence:1,snapshot:snapshot('B')},'200');
  assert.equal(o.read(a.readToken).snapshot.racers[0].name,'A');assert.equal(o.read(b.readToken).snapshot.racers[0].name,'B');assert.equal(o.read(legacy.readToken).snapshot,null);
  assert.throws(()=>o.publish(la.writeToken,{sequence:2,snapshot:snapshot('bad')},'200'),/scope/);
  assert.equal(o.claim({ownerRobloxId:'1',universeId:'100',jobId:'a',claimId:'a'}).writeToken,la.writeToken);
  now+=5000;assert.equal(o.read(a.readToken).online,false);
  const restarted=new Overlays(store.db,()=>now);assert.equal(restarted.profile('1','100').readToken,a.readToken);
 }finally{store.close();}
});
test('HTTP integration authorization and credential-bound publisher without takeover',async()=>{
 const store=new Store(':memory:');const config={bridgeKey:'b'.repeat(32),adminKey:'a'.repeat(32),giftMap:{},overlayServiceKey:'s'.repeat(32),overlayOrigin:'https://rbworker.aclassstore.com',overlayUniverses:['100','200'],overlayMapKeys:{100:'x'.repeat(32),200:'y'.repeat(32)}};
 const server=createAPI(store,config);await new Promise(r=>server.listen(0,'127.0.0.1',r));const origin='http://127.0.0.1:'+server.address().port;
 const post=async(path,key,body)=>{const res=await fetch(origin+path,{method:'POST',headers:{authorization:'Bearer '+key,'content-type':'application/json'},body:JSON.stringify(body)});return {status:res.status,headers:res.headers,data:await res.json()};};
 const path='/v1/integrations/tikkies/overlay-links',body={ownerRobloxId:'1',universeId:'100'};
 try{
  for(const key of ['bad',config.bridgeKey,config.adminKey,config.overlayMapKeys[100]])assert.equal((await post(path,key,body)).status,401);
  assert.equal((await post(path,config.overlayServiceKey,{...body,universeId:'300'})).status,403);
  assert.equal((await post(path,config.overlayServiceKey,{...body,ownerRobloxId:1})).status,400);
  const results=await Promise.all(Array.from({length:8},()=>post(path,config.overlayServiceKey,body)));
  const a=results[0];assert.equal(a.status,200);assert.equal(a.data.schemaVersion,2);assert.equal(a.data.online,false);assert.equal(a.headers.get('cache-control'),'no-store');assert.equal(a.headers.get('referrer-policy'),'no-referrer');
  for(const r of results)assert.deepEqual(r.data.urls,a.data.urls);
  const tokens=new Set();for(const [view,link]of Object.entries(a.data.urls)){const u=new URL(link);assert.equal(u.origin,config.overlayOrigin);assert.equal(u.pathname,'/overlay');assert.equal(u.search,'?view='+view);assert.match(u.hash,/^#[A-Za-z0-9_-]{43}$/);tokens.add(u.hash);}
  assert.equal(tokens.size,1);const read=new URL(a.data.urls.map).hash.slice(1);
  const claimBody={...body,jobId:'j',claimId:'c'};
  assert.equal((await post('/v1/overlays/claim',config.bridgeKey,claimBody)).status,403);
  assert.equal((await post('/v1/overlays/claim',config.overlayMapKeys[200],claimBody)).status,403);
  const claim=(await post('/v1/overlays/claim',config.overlayMapKeys[100],claimBody)).data;
  assert.equal(claim.readToken,read);
  assert.equal((await post(path,config.overlayServiceKey,body)).data.online,false,"Claim alone is not published game data");
  assert.equal((await post('/v1/overlays/publish',read,{sequence:1,snapshot:snapshot('bad')})).status,401);
  const batch={items:[{writeToken:claim.writeToken,sequence:1,snapshot:snapshot('A')}]};
  for(const key of [config.overlayMapKeys[200],config.bridgeKey])assert.equal((await post('/v1/overlays/batch',key,batch)).data.results[0].error,'overlay_scope_mismatch');
  assert.equal((await post('/v1/overlays/batch',config.overlayMapKeys[100],batch)).data.results[0].ok,true);
  const online=await post(path,config.overlayServiceKey,body);assert.equal(online.data.online,true);assert.deepEqual(online.data.urls,a.data.urls);
  assert.equal((await post('/v1/overlays/claim',config.overlayMapKeys[100],claimBody)).data.writeToken,claim.writeToken);
  const otherOwner=await post(path,config.overlayServiceKey,{...body,ownerRobloxId:'2'});assert.notEqual(otherOwner.data.urls.map,a.data.urls.map);assert.equal(otherOwner.data.online,false);
  const other=await post(path,config.overlayServiceKey,{...body,universeId:'200'});assert.notEqual(other.data.urls.map,a.data.urls.map);assert.equal(other.data.online,false);
  assert.equal((await post('/v1/overlays/claim',read,{ownerRobloxId:'1',jobId:'bad',claimId:'bad'})).status,401);
  assert.equal((await post('/v1/overlays/claim',config.overlayMapKeys[100],{ownerRobloxId:'1',jobId:'bad',claimId:'bad'})).status,403);
  assert.equal((await post(path,config.overlayServiceKey,{...body,noise:'a'.repeat(5000)})).status,413);
  let last;for(let i=0;i<125;i++)last=await post(path,config.overlayServiceKey,body);assert.equal(last.status,429);
 }finally{server.closeAllConnections();await new Promise(r=>server.close(r));store.close();}
});
