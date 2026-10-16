import test from 'node:test';import assert from 'node:assert/strict';import {spawn} from 'node:child_process';
import {createServer} from 'node:net';import {mkdtempSync,rmSync,existsSync} from 'node:fs';import {tmpdir} from 'node:os';import {join} from 'node:path';
const cwd=new URL('..',import.meta.url).pathname;
const port=async()=>{const s=createServer();await new Promise(r=>s.listen(0,'127.0.0.1',r));const p=s.address().port;await new Promise(r=>s.close(r));return p;};
function launch(env){const p=spawn(process.execPath,['src/main.mjs'],{cwd,env,stdio:['ignore','pipe','pipe','ipc']});let out='';p.stdout.on('data',d=>out+=d);p.stderr.on('data',d=>out+=d);return {p,get out(){return out;}};}
const exit=p=>new Promise(r=>p.once('exit',(code,signal)=>r({code,signal})));
test('actual startup readiness, duplicate worker rejection, graceful stop and restart',async()=>{
 const dir=mkdtempSync(join(tmpdir(),'bridge-main-'));const db=join(dir,'data.sqlite');const listenPort=await port();
 const env={...process.env,PORT:String(listenPort),HOST:'127.0.0.1',DB_PATH:db,EULER_TOKEN:'test-only-no-live-session',EULER_API_KEY:'',BRIDGE_API_KEY:'b'.repeat(32),ADMIN_API_KEY:'a'.repeat(32),GIFT_MAP_FILE:''};let running;
 try{
  const first=launch(env);running=first.p;
  await Promise.race([new Promise((resolve,reject)=>{first.p.on('message',m=>m==='ready'&&resolve());first.p.once('exit',()=>reject(new Error(first.out)));}),new Promise((_,reject)=>setTimeout(()=>reject(new Error('ready timeout')),5000).unref())]);
  assert.equal((await fetch(`http://127.0.0.1:${listenPort}/healthz`)).status,200);
  const second=launch({...env,PORT:String(await port())});assert.equal((await exit(second.p)).code,1);assert.match(second.out,/worker already/);
  const stopped=exit(first.p);first.p.kill('SIGTERM');assert.equal((await stopped).code,0);running=null;assert.equal(existsSync(db+'.lock'),false);
  const restart=launch(env);running=restart.p;await new Promise((resolve,reject)=>{restart.p.on('message',m=>m==='ready'&&resolve());restart.p.once('exit',()=>reject(new Error(restart.out)));});
  const done=exit(restart.p);restart.p.kill('SIGTERM');assert.equal((await done).code,0);running=null;
 }finally{if(running){const stopped=exit(running);running.kill('SIGKILL');await stopped;}rmSync(dir,{recursive:true,force:true});}
});
