import test from 'node:test';import assert from 'node:assert/strict';
import {mkdtempSync,mkdirSync,writeFileSync,readFileSync,rmSync,existsSync} from 'node:fs';import {tmpdir} from 'node:os';import {join,resolve} from 'node:path';import {execFileSync,spawnSync} from 'node:child_process';
const updater=resolve('scripts/update-worker-safely.sh');
for(const conflict of [false,true])test(`safe VPS update preserves local changes and ${conflict?'stops on conflict':'deploys merged changes'}`,()=>{
 const dir=mkdtempSync(join(tmpdir(),'worker-update-'));const origin=join(dir,'origin'),upstream=join(dir,'upstream'),local=join(dir,'local');
 const git=(cwd,...args)=>execFileSync('git',args,{cwd,stdio:['ignore','pipe','pipe'],env:{...process.env,GIT_CONFIG_NOSYSTEM:'1'}}).toString().trim();
 try{
  mkdirSync(origin);git(origin,'init','--bare','--initial-branch=main');git(dir,'clone',origin,upstream);
  git(upstream,'config','user.name','Test');git(upstream,'config','user.email','test@example.invalid');
  writeFileSync(join(upstream,'shared'),'base\n');writeFileSync(join(upstream,'custom'),'base\n');
  writeFileSync(join(upstream,'deploy.sh'),'#!/usr/bin/env bash\nprintf deployed > deployed\n',{mode:0o755});
  git(upstream,'add','.');git(upstream,'commit','-m','base');git(upstream,'push','origin','main');git(dir,'clone',origin,local);
  git(local,'config','user.name','Test');git(local,'config','user.email','test@example.invalid');
  writeFileSync(join(local,conflict?'shared':'custom'),'local-edit\n');writeFileSync(join(local,'.env'),'PRIVATE=test\n');
  writeFileSync(join(upstream,'shared'),'upstream-edit\n');git(upstream,'add','shared');git(upstream,'commit','-m','update');git(upstream,'push','origin','main');
  const result=spawnSync('bash',[updater,local],{encoding:'utf8'});
  assert.equal(result.status,conflict?1:0,result.stdout+result.stderr);
  assert.equal(existsSync(join(local,'deployed')),!conflict);
  assert.equal(readFileSync(join(local,'.env'),'utf8'),'PRIVATE=test\n');
  assert.match(git(local,'stash','show','-p'),/local-edit/);
  if(conflict)assert.equal(git(local,'diff','--name-only','--diff-filter=U'),'shared');
  else assert.equal(readFileSync(join(local,'custom'),'utf8'),'local-edit\n');
 }finally{rmSync(dir,{recursive:true,force:true});}
});
