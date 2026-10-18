import test from 'node:test';import assert from 'node:assert/strict';
import {Store} from '../src/store.mjs';import {Overlays,validateSnapshot} from '../src/overlay.mjs';import {createAPI} from '../src/server.mjs';
const snapshot=(extra={})=>({round:'r',phase:'Running',laps:2,metersPerStud:.28,route:{version:'r',length:100,points:[[0,0],[1,0],[1,1],[0,1]]},racers:[],...extra});
const event=(extra={})=>({id:'gift:1:1',robloxId:'1',tiktokDisplayName:'Alice',tiktokUsername:'alice',effectKey:'gojo',count:1,createdAt:100000,...extra});
test('optional public events preserve old publishers and strip private fields',()=>{
 assert.deepEqual(validateSnapshot(snapshot()).events,[]);
 const input=event({tiktokUsername:'',tiktokAvatarUrl:'https://p16.tiktokcdn.com/avatar.jpg',ownerRobloxId:'2',actorKey:'private',secret:'private',avatarUrl:'https://evil.test/a.png'});
 assert.deepEqual(validateSnapshot(snapshot({events:[input]})).events,[{id:'gift:1:1',robloxId:'1',tiktokDisplayName:'Alice',tiktokUsername:'',effectKey:'gojo',count:1,createdAt:100000,tiktokAvatarUrl:'https://p16.tiktokcdn.com/avatar.jpg'}]);
 for(const effectKey of ['rainbow_cat','rocket','naruto','goku','asta','speed_boost','fly','gojo','shield','octopus','power','jump','heal'])assert.equal(validateSnapshot(snapshot({events:[event({effectKey})]})).events[0].effectKey,effectKey);
 assert.equal(validateSnapshot(snapshot({events:Array.from({length:30},(_,i)=>event({id:String(i)}))})).events.length,30);
 assert.equal(validateSnapshot(snapshot({events:[event({tiktokDisplayName:'😀'.repeat(50),count:10000,createdAt:Number.MAX_SAFE_INTEGER})]})).events.length,1);
});
test('event validation rejects malformed records and unsafe avatars',()=>{
 for(const events of [null,{},'events',Array(31).fill(event())])assert.throws(()=>validateSnapshot(snapshot({events})),/invalid_overlay_event/);
 const bad=[null,{},...Object.entries({id:['','x'.repeat(201),1],robloxId:['0','-1',1,'9007199254740992'],tiktokDisplayName:['','😀'.repeat(51),null],tiktokUsername:[null,1,'x'.repeat(101)],effectKey:['unknown','Gojo',''],count:[0,10001,1.5,'1'],createdAt:[0,-1,1.5,Infinity,Number.MAX_SAFE_INTEGER+1,'100000'],tiktokAvatarUrl:['https://evil.test/a.png','http://p16.tiktokcdn.com/a.png','https://tiktokcdn.com.evil.test/a.png','https://user@tiktokcdn.com/a.png',null]}).flatMap(([key,values])=>values.map(value=>event({[key]:value})))];
 for(const entry of bad)assert.throws(()=>validateSnapshot(snapshot({events:[entry]})),/invalid_overlay_event/,JSON.stringify(entry));
});
test('event reads isolate owner and universe and expire stale or offline records',()=>{
 const store=new Store(':memory:');let now=100000;const o=new Overlays(store.db,()=>now);
 try{
  const claim=(ownerRobloxId,universeId)=>o.claim({ownerRobloxId,universeId,jobId:'j',claimId:'c'});
  const a=claim('1','100'),b=claim('2','100'),c=claim('1','200');
  o.publish(a.writeToken,{sequence:1,snapshot:snapshot({events:[event()]})},'100');
  assert.equal(o.read(a.readToken).snapshot.events[0].effectKey,'gojo');
  assert.equal(o.read(b.readToken).snapshot,null);assert.equal(o.read(c.readToken).snapshot,null);
  assert.throws(()=>o.publish(a.readToken,{sequence:2,snapshot:snapshot()}),/lease_expired/);
  assert.throws(()=>o.publish(a.writeToken,{sequence:2,snapshot:snapshot()},'200'),/scope_mismatch/);
  now+=4000;o.publish(a.writeToken,{sequence:2,snapshot:snapshot({events:[event()]})},'100');
  now+=4000;o.publish(a.writeToken,{sequence:3,snapshot:snapshot({events:[event()]})},'100');
  now+=4000;o.publish(a.writeToken,{sequence:4,snapshot:snapshot({events:[event()]})},'100');
  assert.equal(o.read(a.readToken).snapshot.events.length,1);
  now++;assert.deepEqual(o.read(a.readToken).snapshot.events,[]);
  now+=5000;assert.equal(o.read(a.readToken).online,false);assert.deepEqual(o.read(a.readToken).snapshot.events,[]);
  o.publish(a.writeToken,{sequence:5,snapshot:snapshot({events:[event()]})},'100');assert.deepEqual(o.read(a.readToken).snapshot.events,[]);
  now+=400;o.publish(a.writeToken,{sequence:6,snapshot:snapshot({events:[event({id:'fresh',createdAt:now})]})},'100');assert.equal(o.read(a.readToken).snapshot.events[0].id,'fresh');
  now+=45000;assert.throws(()=>o.publish(a.writeToken,{sequence:7,snapshot:snapshot()}),/lease_expired/);
 }finally{store.close();}
});
test('offline reconnect does not revive recent events from the previous connection',()=>{
 const store=new Store(':memory:');let now=100000;const o=new Overlays(store.db,()=>now);
 try{const lease=o.claim({ownerRobloxId:'1',universeId:'100',jobId:'j',claimId:'c'});
  o.publish(lease.writeToken,{sequence:1,snapshot:snapshot({events:[event()]})},'100');
  now+=5000;assert.deepEqual(o.read(lease.readToken).snapshot.events,[]);
  o.publish(lease.writeToken,{sequence:2,snapshot:snapshot({events:[event()]})},'100');
  assert.deepEqual(o.read(lease.readToken).snapshot.events,[]);
 }finally{store.close();}
});
test('scoped events URL shares the read token and cannot publish',async()=>{
 const store=new Store(':memory:',{now:()=>100000});const config={bridgeKey:'b'.repeat(32),adminKey:'a'.repeat(32),giftMap:{},overlayServiceKey:'s'.repeat(32),overlayOrigin:'https://rbworker.aclassstore.com',overlayUniverses:['100'],overlayMapKeys:{100:'m'.repeat(32)}};
 let fetched;const thumbnailFetched=new Promise(resolve=>{fetched=resolve;});const server=createAPI(store,config,{thumbnailFetch:async()=>{fetched();return {ok:true,json:async()=>({data:[{targetId:1,state:'Completed',imageUrl:'https://tr.rbxcdn.com/avatar.png'}]})};}});await new Promise(r=>server.listen(0,'127.0.0.1',r));const origin='http://127.0.0.1:'+server.address().port;
 const post=async(path,key,body)=>{const res=await fetch(origin+path,{method:'POST',headers:{authorization:'Bearer '+key,'content-type':'application/json'},body:JSON.stringify(body)});return {status:res.status,data:await res.json()};};
 try{
  const links=await post('/v1/integrations/tikkies/overlay-links',config.overlayServiceKey,{ownerRobloxId:'1',universeId:'100'});
  assert.equal(links.status,200);const url=new URL(links.data.urls.events);assert.equal(url.origin,config.overlayOrigin);assert.equal(url.pathname,'/overlay');assert.equal(url.search,'?view=events');assert.equal(url.hash,new URL(links.data.urls.map).hash);
  const read=url.hash.slice(1);const claim=await post('/v1/overlays/claim',config.overlayMapKeys[100],{ownerRobloxId:'1',universeId:'100',jobId:'j',claimId:'c'});
  assert.equal((await post('/v1/overlays/publish',read,{sequence:1,snapshot:snapshot({events:[event()]})})).status,401);
  assert.equal((await post('/v1/overlays/batch',config.overlayMapKeys[100],{items:[{writeToken:claim.data.writeToken,sequence:1,snapshot:snapshot({events:[event({ownerRobloxId:'secret',avatarUrl:'https://evil.test/a.png'})]})}]})).data.results[0].ok,true);
  const res=await fetch(origin+'/v1/overlay/state',{headers:{authorization:'Bearer '+read}});const state=await res.json();assert.equal(res.status,200);assert.deepEqual(state.snapshot.events,[event({avatarUrl:null})]);
  await thumbnailFetched;const cached=await (await fetch(origin+'/v1/overlay/state',{headers:{authorization:'Bearer '+read}})).json();assert.equal(cached.snapshot.events[0].avatarUrl,'https://tr.rbxcdn.com/avatar.png');
 }finally{server.closeAllConnections();await new Promise(r=>server.close(r));store.close();}
});
