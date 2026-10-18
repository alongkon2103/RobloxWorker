import test from 'node:test';
import assert from 'node:assert/strict';
import {EventWindow,EventFeed,EVENT_EFFECTS,EVENT_TTL} from '../public/overlay/event-renderer.js';
const now=1700000000000;
const event=(id='a',createdAt=now)=>({id,robloxId:'1',tiktokDisplayName:'หมาส้มส้ม',tiktokUsername:'viewer',effectKey:'gojo',count:1,createdAt});
test('deduplicates repeated polls and expires at original creation time',()=>{
 const window=new EventWindow();assert.equal(window.update([event()],now+1000).length,1);
 assert.equal(window.update([event()],now+11000).length,1);
 assert.equal(window.update([],now+EVENT_TTL).length,0);
 assert.equal(window.update([event()],now+EVENT_TTL+1).length,0,'old reconnect snapshots cannot replay expired events');
});
test('newest five only, and displaced events do not replay on reconnect',()=>{
 const window=new EventWindow(),events=Array.from({length:8},(_,i)=>event(String(i),now+i));
 assert.deepEqual(window.update(events,now+100).map(e=>e.id),['7','6','5','4','3']);
 assert.deepEqual(window.update(events.slice(0,3),now+200).map(e=>e.id),['7','6','5','4','3']);
});
test('rejects expired, future, unknown and invalid payloads',()=>{
 const window=new EventWindow();assert.deepEqual(window.update([event('old',now-EVENT_TTL),event('future',now+1),{...event(),effectKey:'__proto__'},{...event(),count:0},{...event(),count:1.5},{...event(),createdAt:'today'},null],now),[]);
 assert.deepEqual(window.update(null,now),[]);assert.equal(Object.keys(EVENT_EFFECTS).length,13);
});
class Element{
 constructor(tag){this.tagName=tag;this.children=[];this.dataset={};this.hidden=false;this.textContent='';this.className='';this.classList={add:()=>{},remove:()=>{}};}
 set innerHTML(value){throw new Error('Dynamic HTML is forbidden');}
 setAttribute(){}
 append(...nodes){for(const node of nodes){node.remove();node.parent=this;this.children.push(node);}}
 insertBefore(node,before){node.remove();node.parent=this;const i=this.children.indexOf(before);if(i<0)this.children.push(node);else this.children.splice(i,0,node);}
 replaceChildren(...nodes){this.children.forEach(n=>n.parent=null);this.children=[];this.append(...nodes);}
 remove(){if(this.parent){this.parent.children.splice(this.parent.children.indexOf(this),1);this.parent=null;}}
 querySelector(selector){return this.children.find(n=>n.className.split(' ').includes(selector.slice(1)));}
}
test('renders Thai action text safely and hides an empty feed',()=>{
 globalThis.document={createElement:tag=>new Element(tag)};
 const container=new Element('section'),avatars={load(){},get(){return null;}},feed=new EventFeed(container,avatars);
 feed.update([],now);assert.equal(container.hidden,true);
 const name='<img src=x onerror=alert(1)>';
 feed.update([{...event(),tiktokDisplayName:name}],now);assert.equal(container.hidden,false);assert.equal(container.children.length,1);
 const card=container.children[0],text=card.children[1];assert.equal(card.children.length,2,'Only sender portrait and text; no invented effect icons');assert.equal(text.children[0].textContent,name);assert.equal(text.children[1].textContent,' ส่ง Gojo ×1');
 feed.update([event()],now+1000);assert.equal(container.children[0],card,'polling must preserve the card');
 feed.render(now+EVENT_TTL);assert.equal(container.hidden,true);assert.equal(container.children.length,0);
});
test('avatar rendering uses the shared loader and forwards image failures',()=>{
 globalThis.document={createElement:tag=>new Element(tag)};
 let failed;const avatars={load(events){assert.equal(events[0]?.id,'a');},get(){return {url:'https://tr.rbxcdn.com/avatar.png'};},fallback(...args){failed=args;}};
 const container=new Element('section'),feed=new EventFeed(container,avatars);feed.update([event()],now);
 const image=container.children[0].children[0].children[0];assert.equal(image.tagName,'img');assert.equal(image.src,'https://tr.rbxcdn.com/avatar.png');image.onerror();assert.deepEqual(failed,['a',image.src]);
});

test('late portrait enrichment updates the active card without extending its lifetime',()=>{
 const window=new EventWindow();window.update([event()],now);
 const portrait='https://tr.rbxcdn.com/ready.png';
 assert.equal(window.update([{...event(),avatarUrl:portrait}],now+1000)[0].avatarUrl,portrait);
 assert.equal(window.update([event()],now+EVENT_TTL).length,0);
});
