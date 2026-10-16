import test from 'node:test';import assert from 'node:assert/strict';import {mkdtempSync,cpSync,readFileSync,writeFileSync,rmSync,existsSync} from 'node:fs';import {tmpdir} from 'node:os';import {join} from 'node:path';import {spawnSync} from 'node:child_process';
test('deploy creates distinct secrets without printing them and rejects missing Euler token',()=>{
 const dir=mkdtempSync(join(tmpdir(),'bridge-deploy-'));try{
  cpSync(new URL('..',import.meta.url),dir,{recursive:true,filter:path=>!/[\\/](?:data|logs|node_modules|\.env)$/.test(path)});
  const first=spawnSync('bash',['deploy.sh'],{cwd:dir,encoding:'utf8'});assert.equal(first.status,0);assert.ok(existsSync(join(dir,'.env')));
  const env=readFileSync(join(dir,'.env'),'utf8'),a=env.match(/^BRIDGE_API_KEY=(.+)$/m)[1],b=env.match(/^ADMIN_API_KEY=(.+)$/m)[1];assert.notEqual(a,b);assert.equal(a.length,64);assert.ok(!first.stdout.includes(a));
  const next=spawnSync('bash',['start.sh','--foreground'],{cwd:dir,encoding:'utf8',env:{...process.env,EULER_TOKEN:'',EULER_API_KEY:''}});assert.equal(next.status,1);assert.match(next.stderr,/Set EULER/);
 }finally{rmSync(dir,{recursive:true,force:true});}
});
