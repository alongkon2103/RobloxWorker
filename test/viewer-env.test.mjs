import test from 'node:test';import assert from 'node:assert/strict';import {mkdtempSync,writeFileSync,readFileSync,readdirSync,rmSync} from 'node:fs';import {tmpdir} from 'node:os';import {resolve,join} from 'node:path';import {execFileSync} from 'node:child_process';
test('viewer capacity env migration preserves all other settings, backs up and is idempotent',()=>{
 const dir=mkdtempSync(join(tmpdir(),'viewer-env-'));try{
  const path=join(dir,'.env'),before='BRIDGE_API_KEY=private-test-value\nMAX_VIEWERS_PER_STREAM=30\nOTHER="keep this $value"\n';writeFileSync(path,before);
  for(let i=0;i<2;i++)execFileSync(process.execPath,[resolve('scripts/set-viewer-capacity.mjs'),path]);
  const value=readFileSync(path,'utf8');assert.equal(value,'BRIDGE_API_KEY=private-test-value\nOTHER="keep this $value"\nMAX_VIEWERS_PER_STREAM=100\n');
  const backups=readdirSync(dir).filter(n=>n.startsWith('.env.before-'));assert.equal(backups.length,1);assert.equal(readFileSync(join(dir,backups[0]),'utf8'),before);
 }finally{rmSync(dir,{recursive:true,force:true});}
});
