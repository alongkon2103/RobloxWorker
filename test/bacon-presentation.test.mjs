import test from 'node:test';
import assert from 'node:assert/strict';
import {Store} from '../src/store.mjs';
import {Overlays,validateSnapshot} from '../src/overlay.mjs';
import {TopWin} from '../src/top-win.mjs';
import {AvatarCache} from '../src/overlay-avatars.mjs';
import {RacerAvatars} from '../public/overlay/avatar-renderer.js';
import {EventWindow} from '../public/overlay/event-renderer.js';

const now=Date.parse('2026-10-19T06:00:00Z');
const bacon={id:'tiktok:123',robloxId:'0',avatarType:'bacon',name:'นักวิ่ง',distance:10,speed:20,rank:1,state:'Running',effects:[]};
const event=(extra={})=>({id:'gift:123',robloxId:'0',avatarType:'bacon',tiktokDisplayName:'นักวิ่ง',tiktokUsername:'runner',effectKey:'speed_boost',count:1,createdAt:now,...extra});
const snapshot=(extra={})=>({round:'run:1',phase:'Running',laps:2,metersPerStud:.28,route:{version:'v1',length:100,points:[[0,0],[1,0],[1,1],[0,1]]},racers:[bacon],events:[event()],...extra});
const win=(extra={})=>({ownerRobloxId:'1',jobId:'job',raceId:'race1',actorKey:'tiktok:123',name:'นักวิ่ง',robloxId:'0',avatarType:'bacon',provider:'direct',channel:'streamer',finishedAt:now,...extra});

test('mixed Bacon and Roblox racers and event feed retain safe avatar metadata',()=>{
 const store=new Store(':memory:');try{
  const overlays=new Overlays(store.db,()=>now),lease=overlays.claim({ownerRobloxId:'1',universeId:'10',jobId:'job',claimId:'claim'});
  overlays.publish(lease.writeToken,{sequence:1,snapshot:snapshot({
   racers:[{...bacon,private:'secret'},{...bacon,id:'tiktok:456',robloxId:'42',avatarType:'roblox'}],
   events:[event({private:'secret'}),event({id:'gift:456',robloxId:'42',avatarType:'roblox'})]
  })},'10');
  const state=overlays.read(lease.readToken).snapshot;
  assert.deepEqual(state.racers.map(r=>[r.id,r.robloxId,r.avatarType]),[['tiktok:123','0','bacon'],['tiktok:456','42','roblox']]);
  assert.deepEqual(state.events.map(e=>[e.id,e.robloxId,e.avatarType]),[['gift:123','0','bacon'],['gift:456','42','roblox']]);
  assert.ok(state.racers.every(r=>!Object.hasOwn(r,'private')));assert.ok(state.events.every(e=>!Object.hasOwn(e,'private')));
  const feed=new EventWindow();assert.deepEqual(feed.update(state.events,now).map(e=>e.avatarType),['bacon','roblox']);
 }finally{store.close();}
});

test('zero Roblox IDs require explicit Bacon metadata in racers, events and winners',()=>{
 const store=new Store(':memory:');try{
  const wins=new TopWin(store.db,()=>now);
  for(const avatarType of [undefined,'roblox','unknown',null,1]){
   assert.throws(()=>validateSnapshot(snapshot({racers:[{...bacon,avatarType}],events:[]})),/invalid_racer/);
   assert.throws(()=>validateSnapshot(snapshot({racers:[],events:[event({avatarType})]})),/invalid_overlay_event/);
   assert.throws(()=>wins.record('10',win({avatarType})),/invalid_win/);
  }
  for(const invalid of [{robloxId:0},{robloxId:'-1'},{robloxId:'00'},{robloxId:'42',avatarType:'bacon'},{robloxId:'42',avatarType:'unknown'}]){
   assert.throws(()=>validateSnapshot(snapshot({racers:[{...bacon,...invalid}],events:[]})),/invalid_racer/);
   assert.throws(()=>validateSnapshot(snapshot({racers:[],events:[event(invalid)]})),/invalid_overlay_event/);
   assert.throws(()=>wins.record('10',win(invalid)),/invalid_win/);
  }
  assert.throws(()=>wins.record('10',win({ownerRobloxId:'0'})),/invalid_win/);
 }finally{store.close();}
});

test('Bacon wins survive restart and avatar upgrades retain the TikTok actor totals and scopes',()=>{
 const store=new Store(':memory:');try{
  let wins=new TopWin(store.db,()=>now);
  assert.equal(wins.record('10',win()).counted,true);assert.equal(wins.record('10',win()).counted,false);
  wins=new TopWin(store.db,()=>now);
  assert.deepEqual(wins.board('10','1').rows,[{id:'tiktok:123',name:'นักวิ่ง',robloxId:'0',avatarType:'bacon',wins:1}]);
  assert.deepEqual(wins.board('11','1').rows,[]);assert.deepEqual(wins.board('10','2').rows,[]);
  wins.record('10',win({raceId:'race2',robloxId:'42',avatarType:'roblox',finishedAt:now+1}));
  assert.deepEqual(wins.board('10','1').rows.map(r=>({...r})),[{id:'tiktok:123',name:'นักวิ่ง',robloxId:'42',wins:2}]);
  wins.record('10',win({raceId:'late-bacon'}));
  assert.deepEqual(wins.board('10','1').rows.map(r=>({...r})),[{id:'tiktok:123',name:'นักวิ่ง',robloxId:'42',wins:3}]);
  wins.bind('10','1','direct','other');assert.deepEqual(wins.board('10','1').rows,[]);
  wins.bind('10','1','direct','streamer');assert.equal(wins.board('10','1').rows[0].wins,3);
 }finally{store.close();}
});

test('Bacon IDs never request Roblox headshots and real IDs still enrich normally',async()=>{
 const urls=[],cache=new AvatarCache({fetcher:async url=>{urls.push(url);return {ok:true,json:async()=>({data:[{targetId:42,state:'Completed',imageUrl:'https://tr.rbxcdn.com/avatar.png'}]})};}});
 try{
  cache.enqueue(['0','-1','00',0,null,undefined,'9007199254740992']);await cache.flush();assert.deepEqual(urls,[]);
  cache.enqueue(['0','42','42']);await cache.flush();assert.equal(urls.length,1);assert.match(urls[0],/userIds=42&/);
  assert.equal(cache.get('0'),null);assert.equal(cache.get('42'),'https://tr.rbxcdn.com/avatar.png');
 }finally{cache.close();}
});

test('Bacon portraits show a placeholder and the same actor can upgrade to a Roblox headshot',()=>{
 const images=[],avatars=new RacerAvatars('roblox',()=>{const image={complete:true,naturalWidth:150};images.push(image);return image;});
 avatars.load([{...bacon,avatarUrl:null}]);assert.equal(images.length,0);assert.equal(avatars.get(bacon.id),null);
 avatars.load([{...bacon,robloxId:'42',avatarType:'roblox',avatarUrl:'https://tr.rbxcdn.com/avatar.png'}]);
 assert.equal(images.length,1);assert.equal(avatars.get(bacon.id).url,'https://tr.rbxcdn.com/avatar.png');
});
