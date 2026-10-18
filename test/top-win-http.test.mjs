import test from 'node:test';import assert from 'node:assert/strict';import {Store} from '../src/store.mjs';import {createAPI} from '../src/server.mjs';
test('TOP WIN map authority, read-only access and per-universe integration links',async()=>{
 let now=Date.now();const s=new Store(':memory:',{now:()=>now});const config={bridgeKey:'b'.repeat(32),adminKey:'a'.repeat(32),giftMap:{},overlayMapKeys:{10:'m'.repeat(32),11:'n'.repeat(32)},overlayServiceKey:'i'.repeat(32),overlayUniverses:['10'],overlayOrigin:'https://example.com'};
 const server=createAPI(s,config);await new Promise(r=>server.listen(0,'127.0.0.1',r));const base=`http://127.0.0.1:${server.address().port}`;
 const call=async(path,key,body)=>{const r=await fetch(base+path,{method:body?'POST':'GET',headers:{authorization:'Bearer '+key,'content-type':'application/json'},body:body?JSON.stringify(body):undefined});return {status:r.status,data:await r.json()};};
 try{
  s.create({ownerRobloxId:'1',jobId:'job',tiktokUsername:'streamer',universeId:'10'});
  const b={ownerRobloxId:'1',jobId:'job',raceId:'race',actorKey:'tiktok:123',name:'คนชนะ',robloxId:'2',provider:'direct',channel:'streamer',finishedAt:s.now()};
  assert.equal((await call('/v1/overlays/top-win/result','bad',b)).status,401);
  assert.equal((await call('/v1/overlays/top-win/result',config.overlayMapKeys['10'],b)).data.counted,true);
  assert.equal((await call('/v1/overlays/top-win/result',config.overlayMapKeys['11'],b)).status,403);
  const claim=(await call('/v1/overlays/claim',config.overlayMapKeys['10'],{ownerRobloxId:'1',jobId:'job',claimId:'claim',universeId:'10'})).data;
  assert.equal((await call('/v1/overlays/top-win/result',claim.readToken,b)).status,401);
  const state=(await call('/v1/overlay/state',claim.readToken)).data;assert.equal(state.topWin.rows[0].name,'คนชนะ');assert.equal(state.snapshot,null);
  const board=(await call('/v1/overlays/top-win/board',config.overlayMapKeys['10'],{ownerRobloxId:'1',jobId:'job',provider:'direct',channel:'streamer'})).data;assert.equal(board.rows[0].wins,1);
  assert.equal((await call('/v1/overlays/top-win/result',config.bridgeKey,{...b,raceId:'legacy'})).status,200);
  s.db.prepare("UPDATE sessions SET status='closed'").run();now+=2*86400000;s.prune();assert.equal(s.list().length,0);
  assert.equal((await call('/v1/overlays/top-win/result',config.overlayMapKeys['10'],{...b,raceId:'delayed'})).data.counted,true);
  const links=(await call('/v1/integrations/tikkies/overlay-links',config.overlayServiceKey,{ownerRobloxId:'1',universeId:'10'})).data.urls;assert.match(links.topWin,/view=top-win#/);
 }finally{server.closeAllConnections();await new Promise(r=>server.close(r));s.close();}
});
