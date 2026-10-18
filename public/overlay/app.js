import {RacerAvatars} from '/overlay/avatar-renderer.js';
import {separateMarkers} from '/overlay/marker-layout.js';
import {EventFeed} from '/overlay/event-renderer.js';
const params=new URLSearchParams(location.search),root=document.querySelector('#overlay'),canvas=document.querySelector('#map'),ctx=canvas.getContext('2d');
const view=['map','ranking','speed','top-win','events','all'].includes(params.get('view'))?params.get('view'):'map';root.className=view;
let key=location.hash.slice(1),frames=[],latest=null,lastSequence=-1,lastRound='',lastUI=0,failures=0,route=null,project=null;
const palette=['#9df5dc','#ffda88','#c5b0ff','#ffb9c4','#9cdcff','#e2f5a6'];
const avatarImages=new RacerAvatars(params.get('avatar'));
const eventFeed=new EventFeed(document.querySelector('#game-events'),new RacerAvatars(params.get('avatar')));
const connectionText=text=>{document.querySelector('#connection').textContent=view==='events'?'':text;};
const labels={rocket:'ROCKET',rainbow_cat:'RAINBOW CAT',naruto:'NARUTO',goku:'GOKU',asta:'ASTA'};
const hash=s=>{let h=0;for(const c of s)h=(h*31+c.charCodeAt(0))>>>0;return h;};
const color=r=>palette[hash(r.id)%palette.length];
const number=n=>Number(n).toLocaleString('en-US',{maximumFractionDigits:0});
function setState(data){
 const now=performance.now();
 if(view==='events'||view==='all'){const racers=[...(data.snapshot?.racers??[]),...(data.topWin?.rows??[])];eventFeed.update((data.snapshot?.events??[]).map(event=>({...event,avatarUrl:event.avatarUrl||racers.find(r=>r.robloxId===event.robloxId)?.avatarUrl})));}
 avatarImages.load([...(data.topWin?.rows??[]),...(data.snapshot?.racers??[])]);latest=data;if(data.topWin){board('wins',data.topWin.rows,null,'wins');document.querySelector('#win-week').textContent='WEEK '+data.topWin.week+' · RESETS MONDAY 00:00 TH';}root.classList.toggle('stale',!data.online);
 connectionText(data.online?'':view==='top-win'?'':data.snapshot?'Signal interrupted · waiting for game':'Waiting for game');
 if(!data.snapshot||data.sequence===lastSequence)return;
 const s=data.snapshot;if(s.round!==lastRound){frames=[];lastRound=s.round;}
 lastSequence=data.sequence;frames.push({at:now,s});while(frames.length>5)frames.shift();
 if(!route||route.version!==s.route.version){route=s.route;const xs=route.points.map(p=>p[0]),ys=route.points.map(p=>p[1]);const minX=Math.min(...xs),maxX=Math.max(...xs),minY=Math.min(...ys),maxY=Math.max(...ys),scale=Math.min(720/Math.max(1,maxX-minX),680/Math.max(1,maxY-minY));project=p=>[450+(p[0]-(minX+maxX)/2)*scale,430+(p[1]-(minY+maxY)/2)*scale];}
 document.querySelector('#round').textContent='ROUND '+s.round.split(':').at(-1);
 document.querySelector('#count').textContent=s.racers.length+' RUNNERS';document.querySelector('#phase').textContent={Lobby:'WAITING',Countdown:'GET READY',Running:'RACING',Results:'FINISH!'}[s.phase];
 document.querySelector('#empty').style.display=s.racers.length?'none':'flex';

}
function rendered(){
 if(!frames.length)return null;
 const t=performance.now()-1100;let a=frames[0],b=frames.at(-1);
 if(t<a.at)return a.s;
 for(let i=1;i<frames.length;i++)if(t<=frames[i].at){a=frames[i-1];b=frames[i];break;}
 const delta=b.at-a.at,blend=delta>0?Math.max(0,Math.min(1,(t-a.at)/delta)):1;
 return {...b.s,racers:b.s.racers.map(r=>{const old=a.s.racers.find(x=>x.id===r.id)??r;const extra=latest.online?Math.max(0,Math.min(.8,(t-b.at)/1000)):0;return {...r,distance:Math.min(b.s.route.length*b.s.laps,old.distance+(r.distance-old.distance)*blend+(r.state==='Running'?r.speed*extra:0)),speed:old.speed+(r.speed-old.speed)*blend};})};
}
function point(distance){
 const n=route.points.length,d=((Math.max(0,distance)%route.length)/route.length)*n,i=Math.floor(d)%n,f=d-Math.floor(d),a=route.points[i],b=route.points[(i+1)%n];return project([a[0]+(b[0]-a[0])*f,a[1]+(b[1]-a[1])*f]);
}
const markerOffsets=new Map();let lastDraw=0,lastPortraitMeta=0;
function draw(s,now){
 const blend=1-Math.exp(-Math.min(.1,(now-lastDraw)/1000)*14);lastDraw=now;
 ctx.clearRect(0,0,900,880);if(!route||!project)return;
 ctx.beginPath();route.points.forEach((p,i)=>{const [x,y]=project(p);i?ctx.lineTo(x,y):ctx.moveTo(x,y);});ctx.closePath();ctx.lineJoin='round';ctx.lineCap='round';
 ctx.shadowColor='#081525a0';ctx.shadowBlur=7;ctx.strokeStyle='#18223bd9';ctx.lineWidth=26;ctx.stroke();ctx.shadowBlur=0;ctx.strokeStyle='#fff9e7';ctx.lineWidth=21;ctx.stroke();
 const trackColors=['#ffe098','#9df5dc','#ffb5d8','#c6b5ff'];
 for(let segment=0;segment<4;segment++){
  ctx.beginPath();const from=Math.floor(segment*route.points.length/4),to=Math.floor((segment+1)*route.points.length/4);
  for(let i=from;i<=to;i++){const [x,y]=project(route.points[i%route.points.length]);i===from?ctx.moveTo(x,y):ctx.lineTo(x,y);}
  ctx.strokeStyle=trackColors[segment];ctx.lineWidth=12;ctx.stroke();
 }
 ctx.beginPath();route.points.forEach((p,i)=>{const [x,y]=project(p);i?ctx.lineTo(x,y):ctx.moveTo(x,y);});ctx.closePath();ctx.strokeStyle='#ffffff80';ctx.lineWidth=2;ctx.stroke();
 const start=point(0);ctx.fillStyle='#fff';ctx.fillRect(start[0]-12,start[1]-14,24,28);ctx.fillStyle='#101c31';for(let i=0;i<3;i++)for(let j=0;j<4;j++)if((i+j)%2===0)ctx.fillRect(start[0]-12+i*8,start[1]-14+j*7,8,7);
 if(!s)return;
 const anchors=s.racers.map(r=>{const [x,y]=point(r.distance);const before=point(r.distance-1),after=point(r.distance+1);return {id:r.id,racer:r,x,y,tx:after[0]-before[0],ty:after[1]-before[1],radius:r.rank===1?26:22};});
 const markers=separateMarkers(anchors);
 const keep=new Set(markers.map(m=>m.id));
 for(const id of markerOffsets.keys())if(!keep.has(id))markerOffsets.delete(id);
 for(const m of markers){
  const target={x:m.x-m.anchorX,y:m.y-m.anchorY},offset=markerOffsets.get(m.id)??target;
  offset.x+=(target.x-offset.x)*blend;offset.y+=(target.y-offset.y)*blend;markerOffsets.set(m.id,offset);
  m.x=m.anchorX+offset.x;m.y=m.anchorY+offset.y;
 }
 if(now-lastPortraitMeta>250){canvas.dataset.portraits=JSON.stringify(markers.map(m=>({id:m.id,x:Math.round(m.x),y:Math.round(m.y)})));lastPortraitMeta=now;}

 for(const m of [...markers].sort((a,b)=>(b.racer.rank||999)-(a.racer.rank||999)||a.id.localeCompare(b.id))){
  const r=m.racer,x=m.x,y=m.y,size=m.radius;ctx.shadowColor='#0008';ctx.shadowBlur=6;ctx.beginPath();ctx.arc(x,y,size+3,0,Math.PI*2);ctx.fillStyle='#122239';ctx.fill();ctx.beginPath();ctx.arc(x,y,size,0,Math.PI*2);ctx.fillStyle=color(r);ctx.fill();ctx.shadowBlur=0;const avatar=avatarImages.get(r.id)?.img;
  ctx.save();ctx.beginPath();ctx.arc(x,y,size-1,0,Math.PI*2);ctx.clip();
  if(avatar?.complete&&avatar.naturalWidth>0)ctx.drawImage(avatar,x-size,y-size,size*2,size*2);
  else{ctx.fillStyle='#263c54';ctx.beginPath();ctx.arc(x,y-4,size*.3,0,Math.PI*2);ctx.fill();ctx.beginPath();ctx.ellipse(x,y+size*.65,size*.65,size*.5,0,0,Math.PI*2);ctx.fill();}
  ctx.restore();
 }
}
const boards=new Map();
function board(id,list,s,top){
 const container=document.getElementById(id);if(top==='wins')container.style.height=Math.max(50,Math.min(10,list.length)*46+4)+'px';let rows=boards.get(id);if(!rows){rows=new Map();boards.set(id,rows);}const keep=new Set();
 list.slice(0,top==='wins'?10:5).forEach((r,i)=>{keep.add(r.id);let row=rows.get(r.id);if(!row){row=document.createElement('div');row.className='row';row.innerHTML='<span class="place"></span><span class="avatar"></span><div class="identity"><div class="name"></div><div class="badge"></div></div><div class="metric"></div>';container.append(row);rows.set(r.id,row);}row.style.transform=`translateY(${i*46+4}px)`;row.dataset.place=String(i+1);row.querySelector('.place').textContent=i+1;row.querySelector('.name').textContent=r.name;const av=row.querySelector('.avatar');av.style.background=color(r);const avatar=avatarImages.get(r.id);if(avatar&&av.dataset.url!==avatar.url){av.replaceChildren();const img=document.createElement('img');img.alt='';img.decoding='async';const url=avatar.url;img.onerror=()=>avatarImages.fallback(r.id,url);img.src=url;av.append(img);av.dataset.url=avatar.url;av.classList.add('has-avatar');}else if(!avatar&&av.dataset.url){av.replaceChildren();delete av.dataset.url;av.classList.remove('has-avatar');}row.querySelector('.badge').textContent=top==='wins'?'WEEKLY WINS':top?'CURRENT SPEED':r.state==='Finished'?'FINISHED':`LAP ${Math.min(s.laps,Math.floor(Math.max(0,r.distance)/s.route.length)+1)} / ${s.laps}`;const kmh=top==='wins'?r.wins:r.speed*s.metersPerStud*3.6;row.querySelector('.metric').textContent=number(kmh);const unit=document.createElement('small');unit.textContent=top==='wins'?'wins':'km/h';row.querySelector('.metric').append(unit);});
 for(const [key,row]of rows)if(!keep.has(key)){row.remove();rows.delete(key);}
}
let lastEventUI=0;
function animate(now){if((view==='events'||view==='all')&&now-lastEventUI>100){lastEventUI=now;eventFeed.render();}const s=rendered();if(view==='map'||view==='all')draw(s,now);if(s&&now-lastUI>100){lastUI=now;if(view==='map'||view==='all')board('map-ranks',[...s.racers].sort((a,b)=>(a.rank||999)-(b.rank||999)),s,false);if(view==='ranking'||view==='all')board('ranks',[...s.racers].sort((a,b)=>(a.rank||999)-(b.rank||999)),s,false);if(view==='speed'||view==='all')board('speeds',[...s.racers].sort((a,b)=>b.speed-a.speed||a.id.localeCompare(b.id)),s,true);}requestAnimationFrame(animate);}requestAnimationFrame(animate);
async function poll(){
 if(!key){connectionText('Open your private URL from the in-game OVERLAY button');return;}
 try{const r=await fetch('/v1/overlay/state',{headers:{authorization:'Bearer '+key},cache:'no-store',signal:AbortSignal.timeout(5000)});if(r.status===401){connectionText('Invalid link · get your URL from the game');return;}if(!r.ok)throw new Error();setState(await r.json());failures=0;}
 catch{failures++;if(latest)latest.online=false;root.classList.add('stale');connectionText('Reconnecting…');}
 setTimeout(poll,Math.min(10000,1000*2**Math.min(3,failures)));
}
if(params.get('preview')==='1'){
 document.body.classList.add('preview');
 const points=Array.from({length:200},(_,i)=>{const t=i/200*Math.PI*2;return [Math.cos(t)*(200+80*Math.cos(3*t)),Math.sin(t)*(290+45*Math.sin(5*t))];});
 const previewStarted=Date.now();
 const previewEvents=[['หมาส้มส้ม','gojo'],['MintRunner','rainbow_cat'],['CloudNine','shield'],['SunnyCat','rocket'],['NinjaSky','octopus']];
 const names=['shrimpvry11','MintRunner','kalexd_a','CloudNine','RocketBoy','LilacDash','NinjaSky','SunnyCat'];let seq=0;
 setInterval(()=>{const time=performance.now()/1000;setState({online:true,sequence:++seq,topWin:{week:'2026-10-12',rows:names.map((name,i)=>({id:'demo:'+i,robloxId:String(i+1),name,wins:28-i*3}))},snapshot:{events:previewEvents.map(([name,effectKey],i)=>({id:'preview-event:'+Math.floor((Date.now()-previewStarted)/10000)+':'+i,robloxId:String(i+1),tiktokDisplayName:name,tiktokUsername:name,effectKey,count:i===1?3:1,createdAt:previewStarted+Math.floor((Date.now()-previewStarted)/10000)*10000-i*800})),round:'preview:1',phase:'Running',laps:2,metersPerStud:.28,route:{version:'preview',length:2400,points},racers:names.map((name,i)=>({id:'demo:'+i,robloxId:String(i+1),name,rank:i+1,distance:1800-i*155+time*16,speed:i===0?240:16+i*9,topSpeed:560-i*55,state:'Running',effects:i===0?[{key:'asta',tier:4,remaining:15}]:[]}))}});},1000);
}else poll();
window.addEventListener('hashchange',()=>location.reload());
