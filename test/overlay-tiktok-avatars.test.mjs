import test from 'node:test';
import assert from 'node:assert/strict';
import {validateSnapshot} from '../src/overlay.mjs';
const racer={id:'viewer:a',robloxId:'1',name:'Alice',distance:10,speed:16,rank:1,state:'Running',effects:[]};
const snapshot=url=>({round:'round1',phase:'Running',laps:2,metersPerStud:.28,route:{version:'r1',length:100,points:[[0,0],[1,0],[1,1],[0,1]]},racers:[{...racer,tiktokAvatarUrl:url,privateField:'never public'}]});
test('snapshots preserve only valid HTTPS TikTok CDN portraits and public racer fields',()=>{
 for(const url of ['https://p16.tiktokcdn.com/profile.webp?x=1','https://p16.tiktokcdn-us.com/profile.jpg','https://p16.tiktokcdn-eu.com/profile.jpg','https://p16.byteoversea.com/profile.jpg','https://p16.ibytedtos.com/profile.jpg','https://tiktokcdn.com/profile.jpg']){
  const output=validateSnapshot(snapshot(url)).racers[0];
  assert.equal(output.tiktokAvatarUrl,url);
  assert.deepEqual(Object.keys(output).sort(),['distance','effects','id','name','rank','robloxId','speed','state','tiktokAvatarUrl','topSpeed'].sort());
 }
 const base='https://p16.tiktokcdn.com/';const max=base+'a'.repeat(2048-base.length);
 assert.equal(validateSnapshot(snapshot(max)).racers[0].tiktokAvatarUrl,max);
});
test('malformed or untrusted TikTok portraits are dropped without rejecting the snapshot',()=>{
 for(const url of [undefined,null,23,{},'', 'not a url','https:p16.tiktokcdn.com/a','https:////p16.tiktokcdn.com/a','data:image/png;base64,abc','javascript:alert(1)','http://p16.tiktokcdn.com/a','https://evil.example/a','https://tiktokcdn.com.evil.example/a','https://eviltiktokcdn.com/a','https://user:secret@p16.tiktokcdn.com/a','https://user@p16.tiktokcdn.com/a','https://@p16.tiktokcdn.com/a','https://:@p16.tiktokcdn.com/a','\0https://p16.tiktokcdn.com/a','https://p16.tiktokcdn.com/'+'ก'.repeat(300),'https://p16.tiktokcdn.com:444/a',' https://p16.tiktokcdn.com/a','https://p16.tiktokcdn.com/a\n','https://p16.tiktokcdn.com/'+'a'.repeat(2048)]){
  const output=validateSnapshot(snapshot(url)).racers[0];assert.equal(Object.hasOwn(output,'tiktokAvatarUrl'),false,String(url));
 }
});
