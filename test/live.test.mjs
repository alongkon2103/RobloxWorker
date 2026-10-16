import test from 'node:test';import assert from 'node:assert/strict';
import {Store} from '../src/store.mjs';import {LiveManager} from '../src/live.mjs';
class Socket extends EventTarget{
 static sockets=[];constructor(url){super();this.url=url;this.readyState=0;Socket.sockets.push(this);}
 emit(type,properties={}){const e=new Event(type);Object.assign(e,properties);this.dispatchEvent(e);}
 close(){this.readyState=3;this.emit('close',{code:1000});}
}
test('concurrency, fair queue, offline backoff and obsolete callbacks',async()=>{
 const s=new Store(':memory:',{now:()=>now});let now=1000;
 const cfg={maxConnections:1,eulerKey:'key-for-test',connectTimeout:45000,maxProcessing:2};
 const translator={handle:async()=>{}};const m=new LiveManager(s,translator,cfg,{Socket});
 const a=s.create({ownerRobloxId:'1',jobId:'j1',tiktokUsername:'live1'}),b=s.create({ownerRobloxId:'2',jobId:'j2',tiktokUsername:'live2'});
 m.tick();assert.equal(Socket.sockets.length,1);assert.equal(s.get(a.id).status,'connecting');
 const first=Socket.sockets[0];first.emit('open');first.emit('message',{data:JSON.stringify({messages:[{type:'room.status',data:{state:'connected'}}]})});assert.equal(s.get(a.id).status,'live');
 first.emit('close',{code:4404});assert.equal(s.get(a.id).status,'offline');m.tick();assert.equal(Socket.sockets.length,2);assert.equal(s.get(b.id).status,'connecting');
 first.emit('message',{data:JSON.stringify({messages:[{type:'room.status',data:{state:'connected'}}]})});assert.equal(s.get(a.id).status,'offline');
 s.stop(b.id);m.tick();assert.equal(m.connections.size,0);assert.equal(s.get(b.id).status,'closed');
 await m.stop();s.close();Socket.sockets=[];
});
test('inbox workers rotate fairly when processing slots are full',async()=>{
 const s=new Store(':memory:');const sessions=['1','2','3'].map(n=>s.create({ownerRobloxId:n,jobId:'j'+n,tiktokUsername:'live'+n}));
 for(const a of sessions)s.ingest(a.id,1,[{sourceId:'row',type:'WebcastChatMessage',data:{}}]);
 const calls=[],wait=[];const translator={handle:async id=>{calls.push(id);await new Promise(r=>wait.push(r));}};
 const m=new LiveManager(s,translator,{maxConnections:1,maxProcessing:1,eulerKey:'test',sliceMs:0},{Socket});
 m.tick();assert.equal(calls[0],sessions[0].id);wait.shift()();await Promise.all(m.processing.values());
 s.ingest(sessions[0].id,1,[{sourceId:'backlog',type:'WebcastChatMessage',data:{}}]);
 m.tick();assert.equal(calls[1],sessions[1].id);wait.shift()();await Promise.all(m.processing.values());
 m.tick();assert.equal(calls[2],sessions[2].id);wait.shift()();await Promise.all(m.processing.values());
 await m.stop();s.close();Socket.sockets=[];
});
