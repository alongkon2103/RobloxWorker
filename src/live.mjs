import {compactMessage,joinUsername} from './events.mjs';
export function eulerURL(username,key){
 const url=new URL('wss://ws.eulerstream.com');
 for(const [name,value] of Object.entries({uniqueId:username,apiKey:key,'features.schemaVersion':'v2','features.bundleEvents':'true','features.rawMessages':'false','features.normalizeUniqueId':'true'}))url.searchParams.set(name,value);
 return url.toString();
}
export class LiveManager {
 constructor(store,translator,config,{Socket=WebSocket,log=()=>{}}={}){Object.assign(this,{store,translator,config,Socket,log});this.connections=new Map();this.processing=new Map();this.lookups=new Map();this.abort=new AbortController();this.stopped=false;this.attemptTimes=[];this.pauseUntil=0;this.lastProcessed=null;}
 start(){this.store.recover();this.tick();this.timer=setInterval(()=>this.tick(),250);this.pruner=setInterval(()=>this.store.prune(),60000);}
 tick(){
  if(this.stopped)return;
  try{
   this.store.expire();const now=this.store.now();
   for(const [id,c] of this.connections){
    const s=this.store.get(id);
    if(['closed','expired','error'].includes(s.status)){this.connections.delete(id);clearTimeout(c.timeout);c.socket.close();}
    else if(now-c.lastData>(this.config.idleTimeout??180000)){this.finish(id,c,1006);}
   }
   this.attemptTimes=this.attemptTimes.filter(time=>time>now-60000);
   for(const s of this.store.candidates()){
    if(this.connections.size>=this.config.maxConnections||now<this.pauseUntil||this.attemptTimes.length>=(this.config.maxConnectAttempts??5))break;
    if(!this.connections.has(s.id))this.connect(s);
   }
   const sessions=this.store.list(),at=sessions.findIndex(s=>s.id===this.lastProcessed);
   const fair=at<0?sessions:[...sessions.slice(at+1),...sessions.slice(0,at+1)];
   for(const s of fair){
    if(this.processing.size>=(this.config.maxProcessing??10))break;
    if(!this.processing.has(s.id)&&this.store.inbox(s.id,this.lookupActors(s.id))){
     const task=this.drain(s.id).catch(()=>this.log({event:'inbox_worker_error',sessionId:s.id})).finally(()=>this.processing.delete(s.id));
     this.processing.set(s.id,task);this.lastProcessed=s.id;
    }
   }
  }catch{this.log({event:'scheduler_error'});}
 }
 connect(s){
  this.attemptTimes.push(this.store.now());
  this.store.status(s.id,'connecting',null,0,s.attempts);
  let socket;
  try{socket=new this.Socket(eulerURL(s.tiktok,this.config.eulerKey));}catch{this.store.status(s.id,'retrying',1006,this.store.now()+30000,s.attempts+1);return;}
  const c={socket,lastData:this.store.now(),timeout:null};this.connections.set(s.id,c);
  c.timeout=setTimeout(()=>this.finish(s.id,c,1006),this.config.connectTimeout??45000);c.timeout.unref?.();
  socket.addEventListener('error',()=>this.finish(s.id,c,1006));
  socket.addEventListener('close',e=>this.finish(s.id,c,e.code||1006));
  socket.addEventListener('message',e=>{
   if(this.connections.get(s.id)!==c||this.stopped)return;
   try{
    if(typeof e.data!=='string'||Buffer.byteLength(e.data)>1048576)throw new Error('bad_frame');
    c.lastData=this.store.now();const payload=JSON.parse(e.data),messages=payload.messages??[payload];
    if(!Array.isArray(messages)||messages.length>500)throw new Error('bad_bundle');
    const incoming=[],catalogue=[];
    for(const message of messages){
     const state=message.data?.state;
     if(message.type==='tiktok.connect'||(message.type==='room.status'&&state==='connected')||message.type?.startsWith('Webcast')){
      clearTimeout(c.timeout);this.store.status(s.id,'live',null,0,0);
     }
     if(message.type==='tiktok.disconnect'||(message.type==='room.status'&&(message.data?.terminal||['offline','ended'].includes(state))&&state!=='connected')){
      this.finish(s.id,c,Number(message.data.code??message.data.reason??4404));return;
     }
     const m=compactMessage(message);
     if(m?.type==='WebcastGiftMessage')catalogue.push(m);
     if(m)incoming.push(m);
    }
    if(catalogue.length)this.store.catalogue(s.id,catalogue);
    if(incoming.length){const current=this.store.get(s.id);this.store.ingest(s.id,current.generation,incoming);}
   }catch(error){
    this.log({event:error.code==='inbox_full'?'inbox_backpressure':'invalid_euler_frame',sessionId:s.id});
    this.finish(s.id,c,error.code==='inbox_full'?1013:1006);
   }
  });
 }
 finish(id,c,code){
  if(this.connections.get(id)!==c)return;
  this.connections.delete(id);clearTimeout(c.timeout);
  if(c.socket.readyState!==3)c.socket.close();
  if(this.stopped)return;
  const s=this.store.get(id);if(['closed','expired'].includes(s.status))return;
  if([4400,4401,4403].includes(code)){this.store.status(id,'error',code);return;}
  if(code===4429)this.pauseUntil=Math.max(this.pauseUntil,this.store.now()+60000);
  const attempts=s.attempts+1,base=code===4404||code===4005||code===1000?30000:code===4429?60000:Math.min(30000,1000*2**Math.min(attempts,5));
  this.store.status(id,[4404,4005,1000].includes(code)?'offline':'retrying',code,this.store.now()+base+Math.floor(Math.random()*1000),attempts);
 }
 lookupActors(id){const generation=this.store.get(id).generation;return [...this.lookups.values()].filter(v=>v.id===id&&v.generation===generation).map(v=>v.actorKey);}
 async processRow(id,row){
  try{await this.translator.handle(id,row.generation,row,{signal:this.abort.signal});if(this.stopped)return false;this.store.finishInbox(row.seq);return true;}
  catch(error){
   if(this.stopped)return false;
   if(error.code==='queue_full')return false;
   if(error.status>=400&&error.status<500){this.log({event:'invalid_ingested_event',sessionId:id});this.store.finishInbox(row.seq);}
   else{this.log({event:'inbox_processing_retry',sessionId:id});this.store.deferInbox(row.seq);}
   return true;
  }
 }
 async drain(id){
  const started=performance.now(),waiting=new Set();
  for(let i=0;i<25&&!this.stopped;i++){
   const row=this.store.inbox(id,[...this.lookupActors(id),...waiting]);if(!row)return;
   try{this.translator.prepareDirectActor?.(id,row.generation,row,{signal:this.abort.signal});}catch(error){if(error.code==='queue_full')return;throw error;}
   const s=this.store.get(id),actor=this.store.actor(id,row.generation,`tiktok:${row.data?.user?.userId}`);
   if(joinUsername(row,s.join_mode)&&(s.provider!=='direct'||actor?.avatarType==='bacon')){
    waiting.add(row.actor_key);
    // Match the resolver's four network slots without blocking other actors.
    if(this.lookups.size<4){
     const task=this.processRow(id,row).catch(()=>this.log({event:'inbox_worker_error',sessionId:id})).finally(()=>this.lookups.delete(row.seq));
     this.lookups.set(row.seq,{id,generation:row.generation,actorKey:row.actor_key,task});
    }
   }else if(!await this.processRow(id,row))return;
   if(performance.now()-started>(this.config.sliceMs??20))return;
  }
 }
 async stop(){this.stopped=true;this.abort.abort();clearInterval(this.timer);clearInterval(this.pruner);for(const [id,c] of this.connections){this.connections.delete(id);clearTimeout(c.timeout);c.socket.close();}await Promise.allSettled([...this.processing.values(),...[...this.lookups.values()].map(v=>v.task)]);}
}
