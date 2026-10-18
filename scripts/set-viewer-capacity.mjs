import {readFileSync,writeFileSync,copyFileSync,chmodSync} from 'node:fs';
import {resolve} from 'node:path';
const path=resolve(process.argv[2]??'.env'),before=readFileSync(path,'utf8');
const lines=before.split(/\r?\n/).filter(line=>! /^[ \t]*(?:export[ \t]+)?MAX_VIEWERS_PER_STREAM[ \t]*=/.test(line));
while(lines.at(-1)==='')lines.pop();
const after=lines.join('\n')+'\nMAX_VIEWERS_PER_STREAM=100\n';
if(after!==before){const backup=path+'.before-100-viewers-'+Date.now();copyFileSync(path,backup);chmodSync(backup,0o600);writeFileSync(path,after,{mode:0o600});chmodSync(path,0o600);}
console.log('Viewer capacity set to 100. Other environment settings preserved.');
