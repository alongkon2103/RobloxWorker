// Crowded portraits stay stacked on the route, with only a small bounded stagger.
export function separateMarkers(anchors,width=900,height=880){
 const placed=[];
 for(const a of [...anchors].sort((a,b)=>a.id.localeCompare(b.id))){
  const nearby=placed.filter(p=>Math.hypot(p.anchorX-a.x,p.anchorY-a.y)<(a.radius??22)+p.radius);
  const index=nearby.length;
  const along=index===0?0:((index*5)%17)-8;
  const across=index===0?0:((index*3)%7)-3;
  const vx=a.tx??1,vy=a.ty??0,length=Math.hypot(vx,vy);
  const tx=length>.001?vx/length:1,ty=length>.001?vy/length:0;
  const radius=a.radius??22;
  const x=Math.max(radius+4,Math.min(width-radius-4,a.x+tx*along-ty*across));
  const y=Math.max(radius+4,Math.min(height-radius-4,a.y+ty*along+tx*across));
  placed.push({...a,x,y,radius,anchorX:a.x,anchorY:a.y});
 }
 return placed;
}
