// Only server-observed Roblox IDs are queued. Metadata is batched; image bytes go direct to Roblox CDN.
export class AvatarCache{
 constructor({fetcher=fetch,now=Date.now}={}){this.fetcher=fetcher;this.now=now;this.cache=new Map();this.pending=new Set();this.running=false;this.closed=false;}
 get(id){return this.cache.get(id)?.url??null;}
 enqueue(ids){
  if(this.closed)return;
  for(const id of ids){if(typeof id!=='string'||!/^[1-9]\d{0,15}$/.test(id)||BigInt(id)>9007199254740991n)continue;const item=this.cache.get(id);if(!item||item.until<=this.now())this.pending.add(id);}
  if(!this.timer&&!this.running&&this.pending.size){this.timer=setTimeout(()=>{this.timer=null;void this.flush();},100);this.timer.unref();}
 }
 async flush(){
  if(this.closed||this.running||!this.pending.size)return;this.running=true;
  const ids=[...this.pending].slice(0,100);for(const id of ids)this.pending.delete(id);
  for(const id of ids)this.cache.set(id,{url:this.cache.get(id)?.url??null,until:this.now()+60000});
  try{
   this.controller=new AbortController();const timeout=setTimeout(()=>this.controller?.abort(),3000);timeout.unref();
   try{
    const res=await this.fetcher('https://thumbnails.roblox.com/v1/users/avatar-headshot?userIds='+ids.join(',')+'&size=150x150&format=Png&isCircular=false',{signal:this.controller.signal});
    if(res.ok){const body=await res.json();for(const row of body.data??[]){const id=String(row.targetId);if(!ids.includes(id)||row.state!=='Completed'||typeof row.imageUrl!=='string')continue;const url=new URL(row.imageUrl);if(url.protocol!=='https:'||!/(^|\.)rbxcdn\.com$/.test(url.hostname)||url.username||url.password)continue;this.cache.set(id,{url:url.href,until:this.now()+21600000});}}
   }finally{clearTimeout(timeout);}
  }catch{}finally{
   this.controller=null;this.running=false;
   while(this.cache.size>2000)this.cache.delete(this.cache.keys().next().value);
   if(this.pending.size)this.enqueue([]);
  }
 }
 close(){this.closed=true;clearTimeout(this.timer);this.controller?.abort();this.pending.clear();}
}
