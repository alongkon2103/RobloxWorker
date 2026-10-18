export const EVENT_TTL=12000;
export const EVENT_EFFECTS={
 rainbow_cat:{label:'Rainbow Cat',tone:'mint'},rocket:{label:'Rocket',tone:'gold'},
 naruto:{label:'Naruto',tone:'gold'},goku:{label:'Goku',tone:'gold'},asta:{label:'Asta',tone:'violet'},
 speed_boost:{label:'Speed Boost',tone:'mint'},fly:{label:'Fly',tone:'mint'},gojo:{label:'Gojo',tone:'violet'},
 shield:{label:'Shield',tone:'mint'},octopus:{label:'Octopus',tone:'violet'},
 power:{label:'Power',tone:'gold'},jump:{label:'Jump',tone:'mint'},heal:{label:'Heal',tone:'mint'}
};
export class EventWindow{
 constructor(){this.entries=[];this.seen=new Map();}
 update(events,now){
  for(const [id,expires] of this.seen)if(expires<=now)this.seen.delete(id);
  for(const event of Array.isArray(events)?events:[]){
   if(!event||typeof event.id!=='string'||!event.id||!Object.hasOwn(EVENT_EFFECTS,event.effectKey)||!Number.isInteger(event.count)||event.count<1||!Number.isFinite(event.createdAt)||event.createdAt>now||event.createdAt+EVENT_TTL<=now)continue;
   if(this.seen.has(event.id)){
    const active=this.entries.find(item=>item.id===event.id);if(active){active.avatarUrl=event.avatarUrl||active.avatarUrl;active.tiktokAvatarUrl=event.tiktokAvatarUrl||active.tiktokAvatarUrl;}
    continue;
   }
   const expires=event.createdAt+EVENT_TTL;this.seen.set(event.id,expires);this.entries.push({...event,expires});
  }
  this.entries=this.entries.filter(event=>event.expires>now).sort((a,b)=>b.createdAt-a.createdAt||a.id.localeCompare(b.id)).slice(0,5);
  return this.entries;
 }
}
export class EventFeed{
 constructor(container,avatars){this.container=container;this.avatars=avatars;this.window=new EventWindow();this.cards=new Map();}
 update(events,now=Date.now()){this.window.update(events,now);this.render(now);}
 render(now=Date.now()){
  const events=this.window.update([],now),keep=new Set(events.map(event=>event.id));
  this.container.hidden=events.length===0;this.avatars.load(events);
  for(const [id,card] of this.cards)if(!keep.has(id)){card.remove();this.cards.delete(id);}
  for(const event of events){
   let card=this.cards.get(event.id);const effect=EVENT_EFFECTS[event.effectKey];
   if(!card){
    card=document.createElement('div');card.className='game-event';card.dataset.tone=effect.tone;
    const avatar=document.createElement('span');avatar.className='avatar event-avatar';
    const text=document.createElement('div');text.className='game-event-text';
    const name=document.createElement('strong');name.textContent=event.tiktokDisplayName||event.tiktokUsername||'ผู้ชม';
    const action=document.createElement('span');action.textContent=' ส่ง '+effect.label+' ×'+event.count;
    text.append(name,action);
    card.append(avatar,text);this.cards.set(event.id,card);
   }
   const avatar=card.querySelector('.avatar'),portrait=this.avatars.get(event.id);
   if(portrait&&avatar.dataset.url!==portrait.url){
    const img=document.createElement('img');img.alt='';img.decoding='async';img.referrerPolicy='no-referrer';const url=portrait.url;
    img.onerror=()=>this.avatars.fallback(event.id,url);img.src=url;avatar.replaceChildren(img);avatar.dataset.url=url;avatar.classList.add('has-avatar');
   }else if(!portrait&&avatar.dataset.url){avatar.replaceChildren();delete avatar.dataset.url;avatar.classList.remove('has-avatar');}
   // Move only when the order changes, so existing cards keep their entrance animation.
   const index=events.indexOf(event);if(this.container.children[index]!==card)this.container.insertBefore(card,this.container.children[index]??null);
  }
 }
}
