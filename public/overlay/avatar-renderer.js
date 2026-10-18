// One portrait per racer: several TikTok viewers can share the same Roblox account.
export class RacerAvatars{
 constructor(mode,createImage=()=>new Image()){this.mode=mode;this.createImage=createImage;this.images=new Map();}
 load(racers){
  const keep=new Set();
  for(const r of racers){
   keep.add(r.id);const primary=(this.mode==='tiktok'&&r.tiktokAvatarUrl)||r.avatarUrl||null,fallback=r.avatarUrl||null;
   const previous=this.images.get(r.id);if(previous?.primary===primary&&previous?.fallback===fallback)continue;
   const entry={id:r.id,primary,fallback,url:null,img:null};this.images.set(r.id,entry);if(primary)this.start(entry,primary);
  }
  for(const id of this.images.keys())if(!keep.has(id))this.images.delete(id);
 }
 start(entry,url){
  const img=this.createImage();entry.img=img;entry.url=url;img.decoding='async';
  img.onerror=()=>{if(this.images.get(entry.id)===entry&&entry.img===img)this.fallback(entry.id,url);};img.src=url;
 }
 fallback(id,failedURL){
  const entry=this.images.get(id);if(!entry||entry.url!==failedURL)return;
  if(entry.fallback&&entry.fallback!==failedURL)this.start(entry,entry.fallback);
  else{entry.img=null;entry.url=null;}
 }
 get(id){const entry=this.images.get(id);return entry?.img?.complete&&entry.img.naturalWidth>0?entry:null;}
}
