import test from 'node:test';import assert from 'node:assert/strict';import {AvatarCache} from '../src/overlay-avatars.mjs';
test('headshots batch by Roblox ID, cache results and reject non-Roblox image URLs',async()=>{
 let calls=0;const cache=new AvatarCache({fetcher:async url=>{calls++;assert.match(url,/userIds=1,2/);return {ok:true,json:async()=>({data:[{targetId:1,state:'Completed',imageUrl:'https://tr.rbxcdn.com/avatar.png'},{targetId:2,state:'Completed',imageUrl:'https://evil.example/image.png'}]})};}});
 try{cache.enqueue(['1','1','2']);await cache.flush();assert.equal(calls,1);assert.equal(cache.get('1'),'https://tr.rbxcdn.com/avatar.png');assert.equal(cache.get('2'),null);cache.enqueue(['1','2']);await cache.flush();assert.equal(calls,1);}finally{cache.close();}
});
