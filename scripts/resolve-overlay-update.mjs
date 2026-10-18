// Resolve only the known pre-TOP-WIN overlay stash conflicts; keep unrelated edits.
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {join,resolve} from 'node:path';import {spawnSync} from 'node:child_process';import {fileURLToPath} from 'node:url';
function legacyApp(s){
 return s
  .replaceAll("['map','ranking','speed','top-win','all']","['map','ranking','speed','all']")
  .replaceAll("avatarImages.load([...(data.topWin?.rows??[]),...(data.snapshot?.racers??[])]);","if(data.snapshot)avatarImages.load(data.snapshot.racers);")
  .replaceAll("if(data.topWin){board('wins',data.topWin.rows,null,'wins');document.querySelector('#win-week').textContent='WEEK '+data.topWin.week+' · RESETS MONDAY 00:00 TH';}",'')
  .replaceAll("view==='top-win'?'':",'')
  .replaceAll("'Waiting for game'","'Enable your overlay in game'")
  .replaceAll("if(top==='wins')container.style.height=Math.max(50,Math.min(10,list.length)*46+4)+'px';",'')
  .replaceAll("list.slice(0,top==='wins'?10:5)",'list.slice(0,5)')
  .replaceAll("top==='wins'?'WEEKLY WINS':",'')
  .replaceAll("top==='wins'?r.wins:",'')
  .replaceAll("top==='wins'?'wins':'km/h'","'km/h'")
  .replaceAll("topWin:{week:'2026-10-12',rows:names.map((name,i)=>({id:'demo:'+i,robloxId:String(i+1),name,wins:28-i*3}))},",'');
}
export function resolveOverlayConflict(name,source){
 let count=0;
 let result=source.replace(/^<<<<<<< Updated upstream\r?\n([\s\S]*?)^=======\r?\n([\s\S]*?)^>>>>>>> Stashed changes(?:\r?\n|$)/gm,(_,up,local)=>{
  count++;
  const known=name==='server.mjs'
   ?up.includes("if(asset&&method==='GET')")&&up.replace("img-src 'self' data:","img-src 'self'").trim()===local.trim()
   :name==='app.js'&&legacyApp(up).trim()===legacyApp(local).trim();
  if(!known)throw Error(`Unknown conflict in ${name}, block ${count}; no files changed. Send the full git diff --cc for review.`);
  return up;
 });
 if(!count||/^(<<<<<<<|=======|>>>>>>>)/m.test(result))throw Error(`Unexpected conflict markers in ${name}; no files changed.`);
 if(name==='app.js'){
  // Git may keep both independent insertions of this exact import around the common import.
  let seen=false;result=result.split('\n').filter(line=>{
   if(line!=="import {RacerAvatars} from '/overlay/avatar-renderer.js';")return true;
   if(seen)return false;seen=true;return true;
  }).join('\n');
 }
 return result;
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 try{
  const root=resolve(process.argv[2]??'.');
  if(process.argv[3]){
   const relative='public/overlay/avatar-renderer.js';
   const original=readFileSync(join(resolve(root,process.argv[3]),relative));
   if(!original.equals(readFileSync(join(root,relative))))throw Error('Your saved avatar renderer differs from the update; no files changed. Keep the backup and send its diff for review.');
  }
  const items=['public/overlay/app.js','src/server.mjs'].map(relative=>{
   const path=join(root,relative),before=readFileSync(path,'utf8'),name=relative.split('/').at(-1);
   return {relative,path,before,after:resolveOverlayConflict(name,before)};
  });
  for(const item of items){
   const check=spawnSync(process.execPath,['--input-type=module','--check'],{input:item.after,encoding:'utf8'});
   if(check.status!==0)throw Error(`Syntax check failed in ${item.relative}; no files changed.`);
  }
  const backup=join(root,'data','overlay-conflict-backup-'+Date.now());mkdirSync(backup,{recursive:true,mode:0o700});
  for(const item of items){const target=join(backup,item.relative);mkdirSync(resolve(target,'..'),{recursive:true,mode:0o700});writeFileSync(target,item.before,{mode:0o600,flag:'wx'});}
  for(const item of items)writeFileSync(item.path,item.after);
  console.log('Known overlay conflicts resolved. TOP WIN, avatar fallback and unrelated edits retained.');
  console.log('Original files backed up in '+backup);
 }catch(error){console.error(error.message);process.exitCode=1;}
}
