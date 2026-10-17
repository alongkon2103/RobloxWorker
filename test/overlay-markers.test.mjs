import test from 'node:test';import assert from 'node:assert/strict';import {separateMarkers} from '../public/overlay/marker-layout.js';
test('coincident portraits remain visible and keep true route anchors at full capacity',()=>{
 for(const count of [2,5,30,100]){
  const source=Array.from({length:count},(_,i)=>({id:'actor:'+String(i).padStart(3,'0'),x:90,y:90,radius:i===0?26:22}));
  const result=separateMarkers(source);assert.equal(result.length,count);
  for(let i=0;i<count;i++){const a=result[i];assert.equal(a.anchorX,90);assert.equal(a.anchorY,90);assert.ok(a.x>=a.radius+4&&a.x<=900-a.radius-4);assert.ok(a.y>=a.radius+4&&a.y<=880-a.radius-4);for(let j=0;j<i;j++){const b=result[j];assert.ok(Math.hypot(a.x-b.x,a.y-b.y)>=a.radius+b.radius+6.99);}}
  assert.deepEqual(separateMarkers([...source].reverse()),result,'Roster order must not reshuffle the portraits');
 }
});
test('separate racers remain on their real anchors',()=>{const source=[{id:'a',x:200,y:200,radius:22},{id:'b',x:500,y:500,radius:22}];const result=separateMarkers(source);for(const r of result){assert.equal(r.x,r.anchorX);assert.equal(r.y,r.anchorY);}});
