import {Fault} from './store.mjs';
import {GAME_EFFECT_KEYS} from './effect-keys.mjs';
export function validatePublication(body,universeId){
 const invalid=()=>{throw new Fault('invalid_defaults_publication',502);};
 if(!body||body.schemaVersion!==1||body.universeId!==universeId||typeof body.version!=='string'||!body.version.trim()||body.version.length>256||typeof body.updatedAt!=='string'||!/^\d{4}-\d\d-\d\dT/.test(body.updatedAt)||!Number.isFinite(Date.parse(body.updatedAt))||!Array.isArray(body.mappings)||body.mappings.length>200)invalid();
 const giftMap={};const seen=new Set();
 for(const m of body.mappings){
  if(!m||typeof m.giftId!=='string'||!/^\d{1,20}$/.test(m.giftId)||seen.has(m.giftId)||!GAME_EFFECT_KEYS.includes(m.eventKey)||m.value!==1||m.enabled!==true)invalid();
  seen.add(m.giftId);giftMap[m.giftId]={key:m.eventKey,value:1};
 }
 return {giftMap,giftMapVersion:body.version,updatedAt:body.updatedAt};
}
export class PublishedDefaults{
 constructor(store,config,{fetchFn=fetch,log=()=>{}}={}){Object.assign(this,{store,config,fetchFn,log});this.pending=null;this.stopped=false;this.blocked=store.defaultsDenied(config.universeId);}
 refresh(){
  if(this.pending)return this.pending;
  this.pending=this.fetchPublication().finally(()=>{this.pending=null;});return this.pending;
 }
 async fetchPublication(){
  try{
   const response=await this.fetchFn(this.config.url,{headers:{authorization:'Bearer '+this.config.token,'user-agent':'HyperRunRace-Worker/1.0'},redirect:'error',signal:AbortSignal.timeout(5000)});
   if(!response.ok){if([401,403].includes(response.status)){this.blocked=true;this.store.setDefaultsDenied(this.config.universeId,true);}this.log({event:'defaults_refresh_failed',status:response.status,universeId:this.config.universeId});return false;}
   const chunks=[];let size=0;
   for await(const chunk of response.body){size+=chunk.length;if(size>131072)throw new Error('oversized');chunks.push(chunk);}
   const data=validatePublication(JSON.parse(Buffer.concat(chunks).toString('utf8')),this.config.universeId);
   if(this.stopped)return false;
   this.store.saveDefaults(this.config.universeId,data);this.blocked=false;
   this.log({event:'defaults_refreshed',universeId:this.config.universeId,version:data.giftMapVersion,mappingCount:Object.keys(data.giftMap).length});return true;
  }catch{this.log({event:'defaults_refresh_failed',universeId:this.config.universeId});return false;}
 }
 snapshot(body){
  if(body.universeId&&body.universeId!==this.config.universeId)throw new Fault('defaults_universe_forbidden',403);
  const universeId=this.config.universeId;
  if(this.blocked)throw new Fault('defaults_access_denied',503);
  if(body.giftMap!==null&&body.giftMap!==undefined)return {universeId,giftMap:body.giftMap,giftMapVersion:null,giftMapSource:'override'};
  const cache=this.store.cachedDefaults(universeId);if(!cache)throw new Fault('defaults_not_ready',503);
  return {universeId,giftMap:cache.giftMap,giftMapVersion:cache.giftMapVersion,giftMapSource:'tikkies-defaults'};
 }
 async start(){await this.refresh();if(!this.stopped){this.timer=setInterval(()=>void this.refresh(),this.config.refreshMs);this.timer.unref();}}
 async stop(){this.stopped=true;clearInterval(this.timer);await this.pending;}
}
