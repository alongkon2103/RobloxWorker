// Resolve only the exact known conflicts from the Direct defaults update.
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {resolve,join} from 'node:path';import {spawnSync} from 'node:child_process';
export function resolveKnownConflict(name,source){
 let count=0;
 const result=source.replace(/^<<<<<<< Updated upstream\r?\n([\s\S]*?)^=======\r?\n([\s\S]*?)^>>>>>>> Stashed changes\r?\n/gm,(_,upstream,local)=>{
  count++;
  if(name==='config.mjs'){
   const defaults=upstream.includes('export function defaultsConfig(')&&!local.trim();
   const returning=upstream.includes('defaults:defaultsConfig(')&&upstream.includes('const overlays=overlayConfig(')&&local.includes('return {...overlayConfig(');
   if(!defaults&&!returning)throw Error('Unexpected config conflict; nothing changed.');
   return upstream;
  }
  if(name==='server.mjs'&&upstream.includes("if(asset&&method==='GET')")&&local.includes("if(asset&&method==='GET')")&&local.includes('https://*.tiktokcdn.com')&&!upstream.includes('https://*.tiktokcdn.com'))return local;
  throw Error('Unexpected server conflict; nothing changed.');
 });
 if(count!==(name==='config.mjs'?2:1)||/^(<<<<<<<|=======|>>>>>>>)/m.test(result))throw Error('Conflict layout changed; nothing changed.');
 return result;
}
if(process.argv[1]&&resolve(process.argv[1])===resolve(import.meta.filename)){
 const root=resolve(process.argv[2]??'.'),names=['config.mjs','server.mjs'];
 const items=names.map(name=>{const path=join(root,'src',name),before=readFileSync(path,'utf8');return {name,path,before,after:resolveKnownConflict(name,before)};});
 for(const item of items){const check=spawnSync(process.execPath,['--input-type=module','--check'],{input:item.after,encoding:'utf8'});if(check.status!==0)throw Error('Syntax check failed for '+item.name+'; nothing changed.');}
 const backup=join(root,'data','update-conflict-backup-'+Date.now());mkdirSync(backup,{recursive:true,mode:0o700});
 for(const item of items)writeFileSync(join(backup,item.name),item.before,{mode:0o600,flag:'wx'});
 for(const item of items)writeFileSync(item.path,item.after);
 console.log('Resolved known conflicts. Kept Direct defaults and your overlay image policy.');console.log('Original conflicted files backed up in '+backup);
 console.log('Review git diff, then git add src/config.mjs src/server.mjs and run ./deploy.sh.');
}
