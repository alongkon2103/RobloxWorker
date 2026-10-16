import {mkdirSync,openSync,closeSync,readFileSync,writeFileSync,unlinkSync,chmodSync} from 'node:fs';
import {dirname} from 'node:path';
import {loadConfig} from './config.mjs';import {Store} from './store.mjs';import {EventTranslator,robloxResolver} from './events.mjs';import {LiveManager} from './live.mjs';import {createAPI} from './server.mjs';
const log=data=>console.log(JSON.stringify({time:new Date().toISOString(),...data}));
let config;
try{config=loadConfig();}catch(error){console.error(error.message);process.exit(1);}
mkdirSync(dirname(config.dbPath),{recursive:true,mode:0o700});
const lockPath=config.dbPath+'.lock';
let bootId=null;try{bootId=readFileSync('/proc/sys/kernel/random/boot_id','utf8').trim();}catch{}
function acquireLock(){
 try{const fd=openSync(lockPath,'wx',0o600);writeFileSync(fd,JSON.stringify({pid:process.pid,bootId}));closeSync(fd);return;}
 catch(error){if(error.code!=='EEXIST')throw error;}
 let old;try{old=JSON.parse(readFileSync(lockPath,'utf8'));}catch{throw new Error('Invalid worker lock; check running processes before removing '+lockPath);}
 let alive=true;if(bootId&&old.bootId&&bootId!==old.bootId)alive=false;
 else{try{process.kill(old.pid,0);}catch(error){if(error.code==='ESRCH')alive=false;}}
 if(alive)throw new Error('A bridge worker already owns this database; use one PM2 fork instance');
 unlinkSync(lockPath);const fd=openSync(lockPath,'wx',0o600);writeFileSync(fd,JSON.stringify({pid:process.pid,bootId}));closeSync(fd);
}
try{acquireLock();}catch(error){console.error(error.message);process.exit(1);}
const releaseLock=()=>{try{if(JSON.parse(readFileSync(lockPath,'utf8')).pid===process.pid)unlinkSync(lockPath);}catch{}};
let store,manager,server,closing=false;
async function shutdown(code=0){
 if(closing)return;closing=true;
 const force=setTimeout(()=>{log({event:'shutdown_timeout'});releaseLock();process.exit(1);},10000);force.unref();
 try{const httpClosed=server?.listening?new Promise(resolve=>{server.close(resolve);server.closeIdleConnections();}):Promise.resolve();await manager?.stop();await httpClosed;store?.close();}
 catch{code=1;}finally{releaseLock();clearTimeout(force);process.exit(code);}
}
try{
 store=new Store(config.dbPath,config);chmodSync(config.dbPath,0o600);
 manager=new LiveManager(store,new EventTranslator(store,{resolve:robloxResolver(),giftMap:config.giftMap,maxActors:config.maxActors}),config,{log});
 server=createAPI(store,config,{log});
 server.once('error',error=>{log({event:'listen_error',code:error.code});void shutdown(1);});
 server.listen(config.port,config.host,()=>{manager.start();log({event:'ready',port:config.port,host:config.host});process.send?.('ready');});
}catch{log({event:'startup_error'});void shutdown(1);}
process.once('SIGTERM',()=>void shutdown());process.once('SIGINT',()=>void shutdown());
process.on('message',message=>{if(message==='shutdown')void shutdown();});
process.on('uncaughtException',()=>{log({event:'fatal_exception'});void shutdown(1);});
process.on('unhandledRejection',()=>{log({event:'fatal_rejection'});void shutdown(1);});
