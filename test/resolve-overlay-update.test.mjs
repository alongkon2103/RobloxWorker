import test from 'node:test';import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,mkdtempSync,mkdirSync,rmSync,existsSync} from 'node:fs';import {spawnSync} from 'node:child_process';import {resolve,join} from 'node:path';import {tmpdir} from 'node:os';
import {resolveOverlayConflict} from '../scripts/resolve-overlay-update.mjs';
const block=(a,b)=>`<<<<<<< Updated upstream\n${a}\n=======\n${b}\n>>>>>>> Stashed changes\n`;
function fixture(root){
 const before=readFileSync('test/fixtures/pre-avatars-app.js.txt','utf8'),current=readFileSync('public/overlay/app.js','utf8'),local=readFileSync('test/fixtures/pre-top-win-app.js.txt','utf8')+'\n// preserve VPS custom edit\n';
 for(const [name,text]of [['base',before],['new',current],['local',local]])writeFileSync(join(root,name),text);
 const merged=spawnSync('git',['merge-file','-p','-L','Updated upstream','-L','BASE','-L','Stashed changes',join(root,'new'),join(root,'base'),join(root,'local')],{encoding:'utf8'});assert.ok(merged.status>0&&merged.status<128,merged.stderr);
 return merged.stdout;
}
test('resolves the real overlay stash merge, retaining TOP WIN, avatar fallback and unrelated VPS edits',()=>{
 const root=mkdtempSync(join(tmpdir(),'overlay-conflict-'));try{
 const source=fixture(root),result=resolveOverlayConflict('app.js',source);
 assert.doesNotMatch(result,/^<<<<<<<|^=======|^>>>>>>>/m);assert.match(result,/top==='wins'\?10:5/);assert.match(result,/avatarImages.fallback/);assert.match(result,/preserve VPS custom edit/);assert.equal(result.match(/^import \{RacerAvatars\}/gm).length,1);
 const check=spawnSync(process.execPath,['--input-type=module','--check'],{input:result,encoding:'utf8'});assert.equal(check.status,0,check.stderr);
 }finally{rmSync(root,{recursive:true,force:true});}
});
test('CSP conflict retains data and CDN support, refusing unexpected changes',()=>{
 const up=`if(asset&&method==='GET'){const policy="img-src 'self' data: https://*.rbxcdn.com https://*.tiktokcdn.com";}`;
 assert.match(resolveOverlayConflict('server.mjs',block(up,up.replace(" data:",''))),/data:/);
 assert.throws(()=>resolveOverlayConflict('server.mjs',block(up,up+'unknown()')));
 assert.throws(()=>resolveOverlayConflict('app.js',block('unexpected()','other()')));
});
for(const unknown of [false,true])test(`CLI ${unknown?'refuses unknown hunks atomically':'backs up both files before resolving'}`,()=>{
 const root=mkdtempSync(join(tmpdir(),'overlay-cli-'));try{
 mkdirSync(join(root,'public/overlay'),{recursive:true});mkdirSync(join(root,'src'));
 const app=fixture(root)+(unknown?block('bad()','other()'):'');
 const policy=`if(asset&&method==='GET'){const policy="img-src 'self' data: https://*.tiktokcdn.com";}`;const server=block(policy,policy.replace(' data:',''));
 writeFileSync(join(root,'public/overlay/app.js'),app);writeFileSync(join(root,'src/server.mjs'),server);
 const run=spawnSync(process.execPath,[resolve('scripts/resolve-overlay-update.mjs'),root],{encoding:'utf8'});assert.equal(run.status,unknown?1:0,run.stdout+run.stderr);
 if(unknown){assert.equal(readFileSync(join(root,'public/overlay/app.js'),'utf8'),app);assert.equal(readFileSync(join(root,'src/server.mjs'),'utf8'),server);assert.equal(existsSync(join(root,'data')),false);}
 else{assert.equal(existsSync(join(root,'data')),true);assert.doesNotMatch(readFileSync(join(root,'public/overlay/app.js'),'utf8'),/<<<<<<<|>>>>>>>/);}
 }finally{rmSync(root,{recursive:true,force:true});}
});

test('CLI refuses an unrecognized saved avatar renderer without modifying conflicted files',()=>{
 const root=mkdtempSync(join(tmpdir(),'overlay-original-'));try{
 mkdirSync(join(root,'public/overlay'),{recursive:true});mkdirSync(join(root,'backup/public/overlay'),{recursive:true});
 writeFileSync(join(root,'public/overlay/avatar-renderer.js'),'incoming');writeFileSync(join(root,'backup/public/overlay/avatar-renderer.js'),'custom');
 const result=spawnSync(process.execPath,[resolve('scripts/resolve-overlay-update.mjs'),root,'backup'],{encoding:'utf8'});
 assert.equal(result.status,1);assert.match(result.stderr,/saved avatar renderer differs/);assert.equal(existsSync(join(root,'data')),false);
 }finally{rmSync(root,{recursive:true,force:true});}
});
