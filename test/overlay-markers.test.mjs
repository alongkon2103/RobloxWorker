import test from 'node:test';import assert from 'node:assert/strict';import {separateMarkers} from '../public/overlay/marker-layout.js';
test('crowded portraits stack with a bounded stagger for 2–100 racers',()=>{
 for(const count of [2,5,30,50,100]){
  const source=Array.from({length:count},(_,i)=>({id:'actor:'+String(i).padStart(3,'0'),x:90,y:90,tx:0,ty:1,radius:i===0?26:22}));
  const result=separateMarkers(source);assert.equal(result.length,count);
  for(const a of result){assert.equal(a.anchorX,90);assert.equal(a.anchorY,90);assert.ok(Math.hypot(a.x-a.anchorX,a.y-a.anchorY)<=8.55,'Portrait drifted away from the road');}
  assert.ok(result.some(a=>a.x!==90||a.y!==90),'Coincident portraits should be slightly staggered');
  assert.deepEqual(separateMarkers([...source].reverse()),result,'Roster order must not reshuffle the portraits');
 }
});
test('separate racers remain on their real anchors',()=>{const source=[{id:'a',x:200,y:200,radius:22},{id:'b',x:500,y:500,radius:22}];for(const r of separateMarkers(source)){assert.equal(r.x,r.anchorX);assert.equal(r.y,r.anchorY);}});

test("waiting racers with no tangent still stagger slightly",()=>{const r=separateMarkers([{id:"a",x:100,y:100,tx:0,ty:0},{id:"b",x:100,y:100,tx:0,ty:0}]);assert.ok(r[1].x!==r[0].x||r[1].y!==r[0].y);});
