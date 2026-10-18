import test from 'node:test';import assert from 'node:assert/strict';import {Store} from '../src/store.mjs';import {EventTranslator} from '../src/events.mjs';import {LiveManager} from '../src/live.mjs';import {createAPI} from '../src/server.mjs';
class Socket extends EventTarget{static list=[];constructor(url){super();this.url=url;this.readyState=1;Socket.list.push(this);}message(message){const e=new Event('message');e.data=JSON.stringify(message);this.dispatchEvent(e);}close(){this.readyState=3;}}
const eventually=async fn=>{for(let i=0;i<100;i++){const value=fn();if(value)return value;await new Promise(r=>setTimeout(r,10));}throw new Error('condition timeout');};
test('two mock Euler lives deliver joins, gifts, likes and follows to exact owners through HTTP',async()=>{
 const store=new Store(':memory:');const config={bridgeKey:'b'.repeat(32),adminKey:'a'.repeat(32),eulerKey:'mock-secret-not-live',giftMap:Object.fromEntries(Object.entries({99:'rocket',8913:'rocket',5655:'rainbow_cat',5658:'naruto',5660:'goku',5586:'asta',5585:'gojo',5879:'shield',5487:'octopus'}).map(([id,key])=>[id,{key,value:1}])),maxConnections:2,maxProcessing:2,tikkiesEnabled:false};
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
  await request(`/v1/sessions/${a.id}/ack`,a.token,{eventId:ga.event.eventId,receipt:ga.event.receipt,success:true});
  const socialUser={userId:'same-viewer',displayId:'viewer'};
  const like={type:'WebcastLikeMessage',data:{common:{msgId:'likes'},user:socialUser,count:20,total:9000000}};
  const follow={type:'WebcastSocialMessage',data:{common:{msgId:'follow',displayText:{key:'pm_main_follow_message_viewer'}},user:socialUser}};
  Socket.list[0].message({messages:[like,follow,like,follow]});
  await eventually(()=>store.public(store.get(a.id)).queueDepth===2);
  const boost=await request(`/v1/sessions/${a.id}/poll`,a.token,{});assert.deepEqual(boost.event.effects,[{key:'speed_boost',value:1,count:1}]);
  await request(`/v1/sessions/${a.id}/ack`,a.token,{eventId:boost.event.eventId,receipt:boost.event.receipt,success:true});
  const flying=await request(`/v1/sessions/${a.id}/poll`,a.token,{});assert.equal(flying.event.eventType,'follow');assert.deepEqual(flying.event.effects,[{key:'fly',value:1,count:1}]);
  assert.equal((await request(`/v1/sessions/${b.id}/poll`,b.token,{})).event,null);
  const listed=store.gifts(a.id);assert.equal(listed[0].giftId,'99');assert.equal(store.gifts(b.id).length,0);
  await request(`/v1/sessions/${a.id}/ack`,a.token,{eventId:flying.event.eventId,receipt:flying.event.receipt,success:true});
  const published=Object.entries(config.giftMap).filter(([id])=>id!=='99');
  Socket.list[0].message({messages:published.map(([id])=>({type:'WebcastGiftMessage',data:{common:{msgId:'published-'+id},user:socialUser,giftId:id,repeatCount:1,giftType:0}}))});
  await eventually(()=>store.public(store.get(a.id)).queueDepth===8);
  for(const [giftId,effect] of published){const packet=await request(`/v1/sessions/${a.id}/poll`,a.token,{});assert.equal(packet.event.giftId,giftId);assert.deepEqual(packet.event.effects,[{key:effect.key,value:1,count:1}]);await request(`/v1/sessions/${a.id}/ack`,a.token,{eventId:packet.event.eventId,receipt:packet.event.receipt,success:true});}
  assert.equal(store.public(store.get(a.id)).queueDepth,0);
 }finally{await manager.stop();await new Promise(r=>server.close(r));store.close();Socket.list=[];}
});
