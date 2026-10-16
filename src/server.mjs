import {createServer} from 'node:http';
import {Fault,constantEqual} from './store.mjs';import {validateGiftMap} from './config.mjs';
const string=(x,pattern,name)=>{if(typeof x!=='string'||!pattern.test(x))throw new Fault(`invalid_${name}`);return x;};
const positiveID=(x,name)=>{const s=string(x,/^[0-9]{1,16}$/,name);if(BigInt(s)<1n||BigInt(s)>9007199254740991n)throw new Fault(`invalid_${name}`);return String(BigInt(s));};
const job=x=>string(x,/^[A-Za-z0-9._-]{1,128}$/,'job_id');
const eventID=x=>string(x,/^[A-Za-z0-9:._-]{1,200}$/,'event_id');
function sessionBody(body){
 const tiktokUsername=string(typeof body.tiktokUsername==='string'?body.tiktokUsername.trim().replace(/^@/,'').toLowerCase():null,/^[a-z0-9._]{2,24}$/,'tiktok_username');
 const provider=body.provider??'direct';if(!['direct','tikkies'].includes(provider))throw new Fault('invalid_provider');
 const joinMode=body.joinMode??'at';if(!['at','plain','both'].includes(joinMode))throw new Fault('invalid_join_mode');
 return {joinMode,ownerRobloxId:positiveID(body.ownerRobloxId,'owner_id'),jobId:job(body.jobId),tiktokUsername,provider,giftMap:body.giftMap===undefined?null:validateGiftMap(body.giftMap)};
}
async function readJSON(req){
 if(!/^application\/json(?:\s*;|$)/i.test(req.headers['content-type']??''))throw new Fault('json_required',415);
 let size=0;const chunks=[];for await(const chunk of req){size+=chunk.length;if(size>65536)throw new Fault('body_too_large',413);chunks.push(chunk);}
 try{const body=JSON.parse(Buffer.concat(chunks).toString('utf8')||'{}');if(!body||typeof body!=='object'||Array.isArray(body))throw new Error();return body;}catch{throw new Fault('invalid_json');}
}
export function createAPI(store,config,{log=()=>{}}={}){
 const rates=new Map();
 function rate(key,max){const now=store.now();const r=rates.get(key);if(!r||r.until<=now){rates.set(key,{n:1,until:now+60000});return;}if(++r.n>max)throw new Fault('rate_limited',429);}
 const housekeeping=setInterval(()=>{for(const [key,r] of rates)if(r.until<store.now())rates.delete(key);},60000);housekeeping.unref();
 const server=createServer({maxHeaderSize:8192,requestTimeout:15000,headersTimeout:10000,keepAliveTimeout:5000},async(req,res)=>{
  const send=(status,data)=>{if(res.destroyed)return;res.writeHead(status,{'content-type':'application/json; charset=utf-8','cache-control':'no-store','x-content-type-options':'nosniff',...(status===429?{'retry-after':'60'}:{})});res.end(JSON.stringify(data));};
  try{
   const url=new URL(req.url,'http://bridge.internal'),path=url.pathname,method=req.method;
   if(path==='/healthz'&&method==='GET'){store.db.prepare('SELECT 1').get();send(200,{ok:true,service:'hyperrun-live-bridge'});return;}
   const token=req.headers.authorization?.match(/^Bearer ([^\s]+)$/)?.[1];
   const privileged=key=>{if(!constantEqual(token,key))throw new Fault('unauthorized',401);};
   const view=s=>({...store.public(s),giftMap:store.effectiveGiftMap(s.id,config.giftMap)});
   if(path==='/v1/sessions'&&method==='POST'){
    privileged(config.bridgeKey);rate('create',120);const body=sessionBody(await readJSON(req));
    if(body.provider==='tikkies'&&!config.tikkiesEnabled)throw new Fault('provider_disabled',403);
    const created=store.create(body);send(201,{...created,giftMap:store.effectiveGiftMap(created.id,config.giftMap)});return;
   }
   if(path==='/v1/admin/sessions'&&method==='GET'){privileged(config.adminKey);send(200,{sessions:store.list().map(view)});return;}
   const serverMatch=path.match(/^\/v1\/servers\/([A-Za-z0-9._-]{1,128})\/(poll|ack)$/);
   if(serverMatch&&method==='POST'){
    privileged(config.bridgeKey);rate(`server:${serverMatch[1]}`,240);const body=await readJSON(req),jobId=serverMatch[1];
    if(serverMatch[2]==='poll'){
     let requested=null;
     if(body.sessionIds!==undefined){
      if(!Array.isArray(body.sessionIds)||body.sessionIds.length>100||body.sessionIds.some(id=>typeof id!=='string'||! /^[0-9a-f-]{36}$/.test(id)))throw new Fault('invalid_sessions');
      requested=new Set(body.sessionIds);
      for(const id of requested){if(store.get(id).job_id!==jobId)throw new Fault('job_mismatch',403);}
     }
     const events=[];for(const s of store.list()){if(s.job_id!==jobId||(requested&&!requested.has(s.id)))continue;const event=store.poll(s.id);if(event)events.push({sessionId:s.id,event});}
     send(200,{events});return;
    }
    if(!Array.isArray(body.receipts)||body.receipts.length>100)throw new Fault('invalid_receipts');
    for(const ack of body.receipts){if(!ack||typeof ack!=="object"||typeof ack.sessionId!=="string"||! /^[0-9a-f-]{36}$/.test(ack.sessionId))throw new Fault("invalid_receipts");if(store.get(ack.sessionId).job_id!==jobId)throw new Fault('job_mismatch',403);}
    const results=body.receipts.map(ack=>{try{return {sessionId:ack.sessionId,eventId:ack.eventId,...acknowledge(store,ack.sessionId,ack)};}catch(error){return {sessionId:ack.sessionId,eventId:ack.eventId,error:error.code??'internal_error'};}});
    send(200,{results});return;
   }
   const ingress=path.match(/^\/v1\/admin\/sessions\/([0-9a-f-]{36})\/ingest$/);
   if(ingress&&method==='POST'){
    privileged(config.adminKey);rate('ingress',600);const s=store.get(ingress[1]);
    if(!config.tikkiesEnabled||s.provider!=='tikkies')throw new Fault('provider_disabled',403);
    const body=await readJSON(req);if(body.generation!==s.generation)throw new Fault('stale_round',409);
    const actor={actorKey:string(body.actorKey,/^[a-z]+:[A-Za-z0-9._-]{1,128}$/,'actor_key'),robloxId:positiveID(body.robloxId,'roblox_id'),robloxUsername:string(body.robloxUsername,/^[A-Za-z0-9_]{3,20}$/,'roblox_username'),tiktokUsername:string(body.tiktokUsername,/^.{1,64}$/u,'tiktok_username')};
    if(!['join','gift','like','chat','follow','share'].includes(body.eventType))throw new Fault('invalid_event_type');
    const effects=validateEffects(body.effects);
    if(body.eventType==='join'&&effects.length)throw new Fault('invalid_join');
    if(body.eventType!=='join'&&store.actor(s.id,s.generation,actor.actorKey)?.robloxId!==actor.robloxId)throw new Fault('viewer_not_joined',409);
    if(body.eventType==='join'&&!store.actor(s.id,s.generation,actor.actorKey)&&store.actorCount(s.id,s.generation)>=(config.maxActors??30))throw new Fault('viewer_limit',429);
    const accepted=store.enqueue(s.id,s.generation,eventID(body.eventId),{...actor,eventType:body.eventType,effects},{actor:body.eventType==='join'?actor:undefined});send(200,{accepted});return;
   }
   const match=path.match(/^\/v1\/sessions\/([0-9a-f-]{36})(?:\/(heartbeat|poll|ack|reset|reconnect|gifts|gift-map|join-mode))?$/);
   if(!match)throw new Fault('not_found',404);
   const id=match[1],action=match[2];const s=store.authenticate(id,token);rate(`session:${id}`,300);
   if(!action&&method==='GET'){send(200,view(s));return;}
   if(!action&&method==='DELETE'){store.stop(id);send(200,{ok:true});return;}
   if(action==='gifts'&&method==='GET'){send(200,{gifts:store.gifts(id)});return;}
   if(method!=='POST')throw new Fault('method_not_allowed',405);
   const body=await readJSON(req);
   if(action==='heartbeat'){send(200,store.heartbeat(id));return;}
   if(action==='poll'){send(200,{event:store.poll(id)});return;}
   if(action==='ack'){send(200,acknowledge(store,id,body));return;}
   if(action==='reset'){send(200,store.reset(id,string(body.requestId,/^[A-Za-z0-9._:-]{1,128}$/,'request_id')));return;}
   if(action==='reconnect'){store.heartbeat(id);if(s.status==='error')store.status(id,'queued');send(200,view(store.get(id)));return;}
   if(action==='join-mode'){send(200,store.setJoinMode(id,body.joinMode));return;}
   if(action==='gift-map'){store.heartbeat(id);const gifts=validateGiftMap(body.gifts);store.setGiftMap(id,gifts);send(200,{gifts});return;}
   throw new Fault('not_found',404);
  }catch(error){const status=error instanceof Fault?error.status:500;if(status===500)log({event:'http_internal_error'});send(status,{error:error instanceof Fault?error.code:'internal_error'});}
 });
 server.on('close',()=>clearInterval(housekeeping));return server;
}
function validateEffects(effects){
 if(!Array.isArray(effects)||effects.length>200)throw new Fault('invalid_effects');
 return effects.map(e=>{if(!e||!['rocket','jump','heal','power'].includes(e.key)||!Number.isFinite(e.value)||e.value<0||e.value>1e9||!Number.isSafeInteger(e.count)||e.count<1||e.count>10000)throw new Fault('invalid_effects');return {key:e.key,value:e.value,count:e.count};});
}
function acknowledge(store,id,body){
 const eventId=eventID(body.eventId),receipt=string(body.receipt,/^[A-Za-z0-9_-]{1,128}$/,'receipt');
 if(typeof body.success!=='boolean'||(body.retry!==undefined&&typeof body.retry!=='boolean'))throw new Fault('invalid_ack');
 return store.ack(id,eventId,receipt,{success:body.success,retry:body.retry??true});
}
