// Keep true route anchors; separate only the portrait centers when racers coincide.
export function separateMarkers(anchors,width=900,height=880){
 const placed=[],cells=new Map(),cellSize=Math.max(1,...anchors.map(a=>2*(a.radius??22)+7));
 const cell=(x,y)=>[Math.floor(x/cellSize),Math.floor(y/cellSize)];
 for(const a of [...anchors].sort((a,b)=>a.id.localeCompare(b.id))){
  const radius=a.radius??22;
  const fits=(x,y)=>{
   if(x<radius+4||y<radius+4||x>width-radius-4||y>height-radius-4)return false;
   const [cx,cy]=cell(x,y);
   for(let dx=-1;dx<=1;dx++)for(let dy=-1;dy<=1;dy++)for(const p of cells.get((cx+dx)+":"+(cy+dy))??[])if(Math.hypot(x-p.x,y-p.y)<radius+p.radius+7)return false;
   return true;
  };
  let x=a.x,y=a.y,found=fits(x,y);
  for(let ring=1;!found&&ring<=Math.ceil(Math.sqrt(anchors.length))+5;ring++){
   const count=ring*6;
   for(let i=0;i<count;i++){
    const angle=i/count*Math.PI*2,cx=a.x+Math.cos(angle)*ring*59,cy=a.y+Math.sin(angle)*ring*59;
    if(fits(cx,cy)){x=cx;y=cy;found=true;break;}
   }
  }
  const marker={...a,x,y,radius,anchorX:a.x,anchorY:a.y};placed.push(marker);
  const [cx,cy]=cell(x,y),key=cx+":"+cy;if(!cells.has(key))cells.set(key,[]);cells.get(key).push(marker);
 }
 return placed;
}
