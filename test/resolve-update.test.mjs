import test from 'node:test';import assert from 'node:assert/strict';import {resolveKnownConflict} from '../scripts/resolve-direct-update.mjs';
const block=(up,local)=>`<<<<<<< Updated upstream\n${up}\n=======\n${local}\n>>>>>>> Stashed changes\n`;
test('known conflicts retain defaults and local overlay image policy',()=>{
 const source='// keep other edits\n'+block('export function defaultsConfig(env,privilegedKeys){ return null; }','')+block(' const overlays=overlayConfig(env,bridgeKey,adminKey);\n return {...overlays,defaults:defaultsConfig(env,[])};',' return {...overlayConfig(env,bridgeKey,adminKey)};');
 const config=resolveKnownConflict('config.mjs',source);assert.match(config,/defaults:defaultsConfig/);assert.match(config,/keep other edits/);assert.doesNotMatch(config,/<<<<<<</);
 const server='// keep other edits\n'+block("if(asset&&method==='GET'){const policy='https://*.rbxcdn.com';}","if(asset&&method==='GET'){const policy='https://*.rbxcdn.com https://*.tiktokcdn.com';}");
 const result=resolveKnownConflict('server.mjs',server);assert.match(result,/https:\/\/\*\.tiktokcdn.com/);assert.match(result,/keep other edits/);
});
test('resolver refuses different, incomplete and already resolved conflicts',()=>{
 for(const source of ['',block('different','different'),block('export function defaultsConfig(env,keys){}','')])assert.throws(()=>resolveKnownConflict('config.mjs',source));
 assert.throws(()=>resolveKnownConflict('server.mjs',block('different','different')));
});

import {mkdtempSync,mkdirSync,writeFileSync,readFileSync,readdirSync,rmSync} from 'node:fs';import {tmpdir} from 'node:os';import {join,resolve} from 'node:path';import {spawnSync} from 'node:child_process';
for(const invalid of [false,true])test(`resolver CLI ${invalid?'refuses invalid syntax before writing':'backs up both files and preserves other edits'}`,()=>{
 const root=mkdtempSync(join(tmpdir(),'resolve-worker-'));
 try{
  mkdirSync(join(root,'src'));
  const config='// retained\n'+block('export function defaultsConfig(env,privilegedKeys){return null;}','')+'export function loadConfig(env){\n'+block(' const overlays=overlayConfig(env,bridgeKey,adminKey);\n return {...overlays,defaults:defaultsConfig(env,[])};',' return {...overlayConfig(env,bridgeKey,adminKey)};')+'}\n';
  const server=block(`if(asset&&method==='GET'){const policy='https://*.rbxcdn.com';}`,`if(asset&&method==='GET'){const policy='https://*.tiktokcdn.com';${invalid?' BAD SYNTAX !!!':''}}`);
  writeFileSync(join(root,'src','config.mjs'),config);writeFileSync(join(root,'src','server.mjs'),server);
  const result=spawnSync(process.execPath,[resolve('scripts/resolve-direct-update.mjs'),root],{encoding:'utf8'});assert.equal(result.status,invalid?1:0,result.stdout+result.stderr);
  if(invalid){assert.equal(readFileSync(join(root,'src','config.mjs'),'utf8'),config);assert.equal(readFileSync(join(root,'src','server.mjs'),'utf8'),server);}
  else{const folder=readdirSync(join(root,'data'))[0];assert.equal(readFileSync(join(root,'data',folder,'config.mjs'),'utf8'),config);assert.match(readFileSync(join(root,'src','server.mjs'),'utf8'),/tiktokcdn/);}
 }finally{rmSync(root,{recursive:true,force:true});}
});
