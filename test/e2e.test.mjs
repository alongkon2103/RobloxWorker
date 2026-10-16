import test from 'node:test';import assert from 'node:assert/strict';import {Store} from '../src/store.mjs';import {EventTranslator} from '../src/events.mjs';import {LiveManager} from '../src/live.mjs';import {createAPI} from '../src/server.mjs';
class Socket extends EventTarget{static list=[];constructor(url){super();this.url=url;this.readyState=1;Socket.list.push(this);}message(message){const e=new Event('message');e.data=JSON.stringify(message);this.dispatchEvent(e);}close(){this.readyState=3;}}
const eventually=async fn=>{for(let i=0;i<100;i++){const value=fn();if(value)return value;await new Promise(r=>setTimeout(r,10));}throw new Error('condition timeout');};
test('two mock Euler lives deliver join/gift to exact owners and jobs through HTTP',async()=>{
 const store=new Store(':memory:');const config={bridgeKey:'b'.repeat(32),adminKey:'a'.repeat(32),eulerKey:'mock-secret-not-live',giftMap:{99:{key:'rocket',value:1}},maxConnections:2,maxProcessing:2,tikkiesEnabled:false};
 const manager=new LiveManager(store,new EventTranslator(store,{resolve:async name=>({id:name==='RunnerA'?'111':'222',name}),giftMap:config.giftMap}),config,{Socket});
 const server=createAPI(store,config);await new Promise(r=>server.listen(0,'127.0.0.1',r));const base=`http://127.0.0.1:${server.address().port}`;
 const request=async(path,key,body)=>{const r=await fetch(base+path,{method:'POST',headers:{authorization:`Bearer ${key}`,'content-type':'application/json'},body:JSON.stringify(body)});assert.ok(r.ok,await r.clone().text());return r.json();};
 try{
  const a=await request('/v1/sessions',config.bridgeKey,{ownerRobloxId:'1',jobId:'job-A',tiktokUsername:'live_a'}),b=await request('/v1/sessions',config.bridgeKey,{ownerRobloxId:'2',jobId:'job-B',tiktokUsername:'live_b'});
  manager.start();await eventually(()=>Socket.list.length===2);
  for(const [i,socket] of Socket.list.entries())socket.message({messages:[{type:'WebcastChatMessage',data:{common:{msgId:'chat-'+i},user:{userId:'same-viewer',displayId:'viewer'},comment:i===0?'@RunnerA':'@RunnerB'}}]});
  await eventually(()=>store.actor(a.id,1,'tiktok:same-viewer')&&store.actor(b.id,1,'tiktok:same-viewer'));
  const [ea,eb]=await Promise.all([request('/v1/servers/job-A/poll',config.bridgeKey,{}),request('/v1/servers/job-B/poll',config.bridgeKey,{})]);
  assert.equal(ea.events[0].event.ownerRobloxId,'1');assert.equal(ea.events[0].event.robloxId,'111');assert.equal(eb.events[0].event.ownerRobloxId,'2');assert.equal(eb.events[0].event.robloxId,'222');
  for(const [s,packet] of [[a,ea],[b,eb]]){const event=packet.events[0].event;await request(`/v1/sessions/${s.id}/ack`,s.token,{eventId:event.eventId,receipt:event.receipt,success:true});}
  const gift={type:'WebcastGiftMessage',data:{common:{msgId:'one-gift'},user:{userId:'same-viewer',displayId:'viewer'},giftId:99,repeatCount:1,giftDetails:{giftType:0}}};
  Socket.list[0].message({messages:[gift]});Socket.list[0].message({messages:[gift]});
  await eventually(()=>store.public(store.get(a.id)).queueDepth===1);
  const ga=await request(`/v1/sessions/${a.id}/poll`,a.token,{}),gb=await request(`/v1/sessions/${b.id}/poll`,b.token,{});
  assert.equal(ga.event.effects[0].key,'rocket');assert.equal(ga.event.ownerRobloxId,'1');assert.equal(gb.event,null);
  const listed=store.gifts(a.id);assert.equal(listed[0].giftId,'99');assert.equal(store.gifts(b.id).length,0);
 }finally{await manager.stop();await new Promise(r=>server.close(r));store.close();Socket.list=[];}
});
