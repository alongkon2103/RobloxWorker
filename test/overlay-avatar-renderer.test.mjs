import test from 'node:test';
import assert from 'node:assert/strict';
import {RacerAvatars} from '../public/overlay/avatar-renderer.js';
function harness(mode){
 const images=[];
 const avatars=new RacerAvatars(mode,()=>{const image={complete:false,naturalWidth:0,load(){this.complete=true;this.naturalWidth=150;this.onload?.();},fail(){this.complete=true;this.naturalWidth=0;this.onerror?.();}};images.push(image);return image;});
 return {avatars,images};
}
const a={id:'viewer:a',robloxId:'1',avatarUrl:'https://tr.rbxcdn.com/a.png',tiktokAvatarUrl:'https://p16.tiktokcdn.com/a.jpg'};
test('Roblox is the default and unrecognized avatar modes use Roblox',()=>{
 for(const mode of [undefined,null,'roblox','invalid','TikTok']){const {avatars,images}=harness(mode);avatars.load([a]);assert.equal(images[0].src,a.avatarUrl);images[0].load();assert.equal(avatars.get(a.id).url,a.avatarUrl);}
});
test('TikTok mode selects each racer portrait even when Roblox IDs are shared',()=>{
 const {avatars,images}=harness('tiktok');const b={...a,id:'viewer:b',tiktokAvatarUrl:'https://p16.tiktokcdn.com/b.jpg'};
 avatars.load([a,b]);assert.equal(images.length,2);images.forEach(image=>image.load());
 assert.equal(avatars.get(a.id).url,a.tiktokAvatarUrl);assert.equal(avatars.get(b.id).url,b.tiktokAvatarUrl);
 avatars.load([a,b]);assert.equal(images.length,2,'unchanged snapshots must reuse loaded portraits');
});
test('missing TikTok portraits immediately select Roblox',()=>{
 const {avatars,images}=harness('tiktok');avatars.load([{...a,tiktokAvatarUrl:undefined}]);assert.equal(images[0].src,a.avatarUrl);
});
test('a failed TikTok load selects Roblox once, then shows a placeholder if Roblox also fails',()=>{
 const {avatars,images}=harness('tiktok');avatars.load([a]);assert.equal(avatars.get(a.id),null);images[0].fail();assert.equal(images[1].src,a.avatarUrl);images[1].load();assert.equal(avatars.get(a.id).url,a.avatarUrl);
 avatars.load([a]);assert.equal(images.length,2);images[1].fail();assert.equal(avatars.get(a.id),null);avatars.load([a]);assert.equal(images.length,2);
});
test('a board image error uses the same Roblox fallback as the canvas',()=>{
 const {avatars,images}=harness('tiktok');avatars.load([a]);images[0].load();avatars.fallback(a.id,a.tiktokAvatarUrl);assert.equal(images[1].src,a.avatarUrl);images[1].load();assert.equal(avatars.get(a.id).img,images[1]);
});
test('updated portraits replace cached images and late errors cannot replace the newer portrait',()=>{
 const {avatars,images}=harness('tiktok');avatars.load([a]);const changed={...a,tiktokAvatarUrl:'https://p16.tiktokcdn.com/new.jpg'};avatars.load([changed]);images[0].fail();assert.equal(images.length,2);images[1].load();assert.equal(avatars.get(a.id).url,changed.tiktokAvatarUrl);
 avatars.fallback(a.id,a.tiktokAvatarUrl);assert.equal(avatars.get(a.id).url,changed.tiktokAvatarUrl);avatars.load([]);assert.equal(avatars.get(a.id),null);
});
