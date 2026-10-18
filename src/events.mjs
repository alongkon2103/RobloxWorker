import {createHash} from 'node:crypto';
import {Fault} from './store.mjs';
const idString=value=>typeof value==='string'&&/^[A-Za-z0-9._:-]{1,128}$/.test(value)?value:Number.isSafeInteger(value)?String(value):null;
export function compactMessage(message){
 const type=message?.type,d=message?.data;
 if(!d||!['WebcastChatMessage','WebcastGiftMessage','WebcastLikeMessage','WebcastSocialMessage','WebcastFollowMessage'].includes(type))return null;
 const msgId=idString(d.common?.msgId??d.msgId),userId=idString(d.user?.userId??d.user?.id);
 if(!msgId||!userId)return null;
 const user={userId,displayId:String(d.user.displayId??d.user.uniqueId??userId).slice(0,64)};
 const nickname=typeof d.user.nickname==='string'?Array.from(d.user.nickname.trim()).slice(0,80).join(''):'';
 if(nickname)user.nickname=nickname;
 const data={user};
 if(type==='WebcastLikeMessage'){
  const count=Number(d.count??d.likeCount);
  if(!Number.isSafeInteger(count)||count<1||count>200000)return null;
  data.likeCount=count;
 }
 if(type==='WebcastSocialMessage'||type==='WebcastFollowMessage'){
  const display=String(d.common?.displayText?.key??d.displayType??'').toLowerCase();
  data.socialType=type==='WebcastFollowMessage'||display.includes('follow')&&!display.includes('unfollow')?'follow':display.includes('share')?'share':'unknown';
 }
 data.roomId=idString(d.common?.roomId??d.roomId);
 if(type==='WebcastChatMessage')data.comment=String(d.comment??d.content??'').slice(0,200);
 if(type==='WebcastGiftMessage'){
  data.giftId=idString(d.giftId);data.giftName=String(d.giftDetails?.giftName??d.giftDetails?.name??d.gift?.name??d.giftName??d.giftId??"").slice(0,80);data.groupId=idString(d.groupId);data.roomId=idString(d.common?.roomId??d.roomId);data.repeatCount=Number(d.repeatCount??1);
  data.repeatEnd=d.repeatEnd===true||d.repeatEnd===1||d.repeatEnd==='1';
  data.giftType=Number(d.giftType??d.giftDetails?.giftType??d.giftDetails?.type??d.gift?.type??NaN);
 }
 return {type,data,sourceId:`${data.socialType==='follow'?'follow':type}:${msgId}`};
}
export class EventTranslator {
 constructor(store,{resolve,giftMap,maxActors=100,signalInterval=5000}){Object.assign(this,{store,resolve,giftMap,maxActors:Math.min(100,maxActors),signalInterval});}
 async handle(id,generation,message){
  const {type,data:d,sourceId}=message;const s=this.store.get(id);
  if(s.generation!==generation||['closed','expired'].includes(s.status))return false;
  const actorKey=`tiktok:${d.user.userId}`;
  let actor=this.store.actor(id,generation,actorKey);
  if(type==='WebcastChatMessage'){
   const pattern=s.join_mode==='plain'?/^([A-Za-z0-9_]{3,20})$/:s.join_mode==='both'?/^(?:@\s*)?([A-Za-z0-9_]{3,20})$/:/^@\s*([A-Za-z0-9_]{3,20})$/;
   const command=d.comment.trim().match(pattern);
   if(command){
    if(this.store.seen(id,generation,sourceId))return false;
    if(!actor&&this.store.actorCount(id,generation)>=this.maxActors)return false;
    const found=await this.resolve(command[1]);if(!found)return false;
    actor={actorKey,robloxId:String(found.id),robloxUsername:found.name,tiktokUsername:d.user.displayId,tiktokDisplayName:d.user.nickname||d.user.displayId};
    return this.store.enqueue(id,generation,sourceId,{...actor,eventType:'join',effects:[]},{actor,sourceId});
   }
  }
  if(!actor)return false;
  if(type==='WebcastGiftMessage'){
   const effect=this.store.effectiveGiftMap(id,this.giftMap)[d.giftId];if(!effect)return false;
   if(!Number.isSafeInteger(d.repeatCount)||d.repeatCount<1||d.repeatCount>10000)throw new Fault('invalid_gift_count');
   if(!Number.isSafeInteger(d.giftType)||d.giftType<0||d.giftType===1&&!d.repeatEnd)return false;
   const key=d.giftType===1&&d.groupId&&d.groupId!=='0'?`combo:${actorKey}:${d.giftId}:${d.groupId}`:sourceId;
   const giftIdentity=createHash('sha256').update(JSON.stringify([d.roomId??'',key])).digest('hex');
   const eventId=`gift:${giftIdentity}`;
   return this.store.enqueue(id,generation,eventId,{...actor,eventType:'gift',giftId:d.giftId,effects:[{key:effect.key,value:effect.value,count:d.repeatCount}]},{sourceId:key,giftIdentity});
  }
  if(type==='WebcastLikeMessage'||type==='WebcastSocialMessage'||type==='WebcastFollowMessage'){
   if(s.provider!=='direct')return false;
   if(type!=='WebcastLikeMessage'&&d.socialType!=='follow')return false;
   const identity=createHash('sha256').update(JSON.stringify([d.roomId??'',actorKey,sourceId])).digest('hex');
   return this.store.socialEvent(id,generation,actor,sourceId,identity,type==='WebcastLikeMessage'?'like':'follow',d.likeCount);
  }
  const bucket=Math.floor(this.store.now()/this.signalInterval);
  const key=`signal:${actorKey}:${bucket}`;
  return this.store.enqueue(id,generation,key,{...actor,eventType:type==='WebcastLikeMessage'?'like':type==='WebcastSocialMessage'?'social':'chat',effects:[]},{sourceId:key});
 }
}
export function robloxResolver({fetchFn=fetch,maxParallel=4}={}){
 const cache=new Map(),inflight=new Map(),waiters=[];let active=0;
 return async name=>{
  const key=name.toLowerCase(),hit=cache.get(key);if(hit&&hit.until>Date.now())return hit.value;
  if(inflight.has(key))return inflight.get(key);
  const request=(async()=>{
   if(active>=maxParallel)await new Promise(resolve=>waiters.push(resolve));active++;
   try{
    const response=await fetchFn('https://users.roblox.com/v1/usernames/users',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({usernames:[name],excludeBannedUsers:true}),signal:AbortSignal.timeout(4000)});
    if(!response.ok)throw new Fault('avatar_lookup_unavailable',503);
    const value=(await response.json()).data?.[0]??null;
    if(value&&(!Number.isSafeInteger(value.id)||!value.name))throw new Fault('invalid_avatar_response',502);
    if(cache.size>=1000)cache.delete(cache.keys().next().value);
    cache.set(key,{value,until:Date.now()+(value?600000:30000)});return value;
   }finally{active--;waiters.shift()?.();}
  })();inflight.set(key,request);
  try{return await request;}finally{inflight.delete(key);}
 };
}
