import test from 'node:test';import assert from 'node:assert/strict';import {Store} from '../src/store.mjs';import {TopWin,weekAt} from '../src/top-win.mjs';
const at=Date.parse('2026-10-18T16:59:59Z');
const result=(extra={})=>({ownerRobloxId:'1',jobId:'job',raceId:'race1',actorKey:'tiktok:123',name:'ชื่อเล่น',robloxId:'2',provider:'direct',channel:'streamer',finishedAt:at,...extra});
test('week changes exactly at Monday midnight Thailand',()=>{assert.equal(weekAt(at).start,'2026-10-12');assert.equal(weekAt(at+1000).start,'2026-10-19');});
test('weekly wins are durable, isolated and exact once per race, including changed winner retries',()=>{const s=new Store(':memory:');let now=at;const w=new TopWin(s.db,()=>now);try{
 assert.equal(w.record('10',result()).counted,true);assert.equal(w.record('10',result()).counted,false);
 assert.equal(w.record('10',result({actorKey:'tiktok:456'})).counted,false);
 w.record('10',result({raceId:'race2',name:'ชื่อใหม่'}));
 assert.equal(w.board('10','1').rows[0].wins,2);assert.equal(w.board('10','1').rows[0].name,'ชื่อใหม่');
 assert.equal(w.board('11','1').rows.length,0);assert.equal(w.board('10','2').rows.length,0);
 const restarted=new TopWin(s.db,()=>now);assert.equal(restarted.board('10','1').rows[0].wins,2);
 now+=1000;assert.equal(restarted.board('10','1').rows.length,0);
 restarted.record('10',result({raceId:'late'}));assert.equal(restarted.board('10','1').rows.length,0);
 restarted.record('10',result({raceId:'next',finishedAt:now}));assert.equal(restarted.board('10','1').rows[0].wins,1);
 w.bind('10','1','direct','other');assert.equal(w.board('10','1').rows.length,0);
 w.bind('10','1','direct','streamer');assert.equal(w.board('10','1').rows[0].wins,1);
 }finally{s.close();}});
test('test racers, invalid dates and channel input cannot create wins; ties stay stable and top ten',()=>{const s=new Store(':memory:');const w=new TopWin(s.db,()=>at);try{
 for(const bad of [{actorKey:'dev:1'},{actorKey:'test:2'},{finishedAt:at+60000},{finishedAt:at-8*86400000},{channel:'../other'},{name:''}])assert.throws(()=>w.record('10',result(bad)),/invalid_win/);
 for(let i=1;i<=12;i++)w.record('10',result({raceId:'r'+i,actorKey:'tiktok:'+i}));
 const b=w.board('10','1');assert.equal(b.rows.length,10);assert.equal(b.rows[0].id,'tiktok:1');assert.equal(b.nextResetAt,Date.parse('2026-10-18T17:00:00Z'));
 }finally{s.close();}});

test('Unicode nicknames retain emoji without exceeding the visible-character limit',()=>{const s=new Store(':memory:');try{const w=new TopWin(s.db,()=>at);w.record('10',result({name:'🚀'.repeat(60)}));assert.equal(w.board('10','1').rows[0].name,'🚀'.repeat(60));}finally{s.close();}});
