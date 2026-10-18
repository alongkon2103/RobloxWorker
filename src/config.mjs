import {EFFECT_KEYS} from './effect-keys.mjs';
import {readFileSync} from 'node:fs';import {resolve} from 'node:path';import {Fault} from './store.mjs';
export function validateGiftMap(value){
 if(!value||typeof value!=='object'||Array.isArray(value)||Object.keys(value).length>200)throw new Fault('invalid_gift_map');
 const result={};for(const [id,effect] of Object.entries(value)){
  if(!/^\d{1,20}$/.test(id)||!effect||!EFFECT_KEYS.includes(effect.key)||!Number.isFinite(effect.value)||effect.value<0||effect.value>1e9)throw new Fault('invalid_gift_map');
  result[id]={key:effect.key,value:effect.value};
 }return result;
}
export function overlayConfig(env,bridgeKey,adminKey){
 const overlayServiceKey=env.TIKKIES_OVERLAY_SERVICE_KEY?.trim()||null;
 const validID=x=>typeof x==='string'&&/^[1-9]\d{0,15}$/.test(x)&&BigInt(x)<=9007199254740991n;
 const validKey=x=>typeof x==='string'&&x.length>=32&&x.length<=256&&!/\s/.test(x);
 let overlayOrigin;
 try{const u=new URL(env.OVERLAY_PUBLIC_ORIGIN||'https://rbworker.aclassstore.com');if(u.protocol!=='https:'||u.username||u.password||u.pathname!=='/'||u.search||u.hash)throw new Error();overlayOrigin=u.origin;}catch{throw new Error('Invalid OVERLAY_PUBLIC_ORIGIN; use an HTTPS origin');}
 const overlayUniverses=(env.TIKKIES_OVERLAY_UNIVERSES||'').split(',').map(x=>x.trim()).filter(Boolean);
 if(overlayUniverses.length>100||overlayUniverses.some(x=>!validID(x))||new Set(overlayUniverses).size!==overlayUniverses.length)throw new Error('Invalid TIKKIES_OVERLAY_UNIVERSES');
 let overlayMapKeys={};
 if(env.OVERLAY_MAP_KEYS_FILE)overlayMapKeys=JSON.parse(readFileSync(resolve(env.OVERLAY_MAP_KEYS_FILE),'utf8'));
 if(!overlayMapKeys||typeof overlayMapKeys!=='object'||Array.isArray(overlayMapKeys)||Object.keys(overlayMapKeys).length>100)throw new Error('Invalid OVERLAY_MAP_KEYS_FILE');
 const keys=[bridgeKey,adminKey];
 if(overlayServiceKey){if(!validKey(overlayServiceKey)||!overlayUniverses.length)throw new Error('Set a unique TIKKIES_OVERLAY_SERVICE_KEY and TIKKIES_OVERLAY_UNIVERSES');keys.push(overlayServiceKey);}
 for(const [universe,key]of Object.entries(overlayMapKeys)){if(!validID(universe)||!validKey(key))throw new Error('Invalid overlay map credential');keys.push(key);}
 if(new Set(keys).size!==keys.length)throw new Error('Overlay service/map credentials must be different from each other and bridge/admin keys');
 return {overlayServiceKey,overlayOrigin,overlayUniverses,overlayMapKeys};
}
export function defaultsConfig(env,privilegedKeys){
 const names=['TIKKIES_DEFAULTS_URL','TIKKIES_DEFAULTS_UNIVERSE_ID','TIKKIES_DEFAULTS_READ_TOKEN'];
 if(!names.some(k=>env[k]?.trim()))return null;
 const [url,universeId,token]=names.map(k=>env[k]?.trim());
 const fail=()=>{throw new Error('Invalid TIKKIES_DEFAULTS configuration; use the pinned HTTPS endpoint, Universe and a separate read token');};
 if(!/^[1-9]\d{0,15}$/.test(universeId??'')||BigInt(universeId)>9007199254740991n||!token||token.length<32||token.length>256||/\s/.test(token)||privilegedKeys.includes(token))fail();
 let endpoint;try{endpoint=new URL(url);}catch{fail();}
 if(endpoint.origin!=='https://backend.aclassstore.com'||endpoint.username||endpoint.password||endpoint.search||endpoint.hash||endpoint.pathname!==`/api/games/defaults/${universeId}/published`)fail();
 return {url:endpoint.href,universeId,token,refreshMs:60000};
}
export function loadConfig(env=process.env){
 const number=(key,fallback,min,max)=>{const n=Number(env[key]??fallback);if(!Number.isInteger(n)||n<min||n>max)throw new Error(`Invalid ${key}`);return n;};
 const key=name=>{const value=env[name];if(!value||value.length<32)throw new Error(`Set ${name} to a random secret of at least32 characters`);return value;};
 const bridgeKey=key('BRIDGE_API_KEY'),adminKey=key('ADMIN_API_KEY');if(bridgeKey===adminKey)throw new Error('Use different bridge and admin keys');
 const eulerKey=env.EULER_API_KEY?.trim()||env.EULER_TOKEN?.trim();
 if(!eulerKey)throw new Error('Set EULER_TOKEN (or EULER_API_KEY)');
 let giftMap={};if(env.GIFT_MAP_FILE)giftMap=validateGiftMap(JSON.parse(readFileSync(resolve(env.GIFT_MAP_FILE),'utf8')));
 const overlays=overlayConfig(env,bridgeKey,adminKey);
 return {...overlays,defaults:defaultsConfig(env,[bridgeKey,adminKey,overlays.overlayServiceKey,...Object.values(overlays.overlayMapKeys)]),port:number('PORT',7435,1,65535),host:env.HOST||'127.0.0.1',dbPath:resolve(env.DB_PATH||'data/bridge.sqlite'),bridgeKey,adminKey,eulerKey,
  giftMap,tikkiesEnabled:env.TIKKIES_ENABLED==='true',maxConnections:number('MAX_LIVE_CONNECTIONS',5,1,100),maxConnectAttempts:number('MAX_CONNECT_ATTEMPTS_PER_MINUTE',5,1,1000),maxProcessing:number('MAX_PROCESSING',10,1,100),
  maxSessions:number('MAX_SESSIONS',200,1,1000),maxActors:number('MAX_VIEWERS_PER_STREAM',30,1,1000),maxQueue:number('MAX_EVENTS_PER_STREAM',1000,10,100000),
  maxInbox:number('MAX_INBOX_PER_STREAM',10000,100,100000),eventTTL:number('EVENT_TTL_MS',120000,10000,3600000),leaseMs:number('DELIVERY_LEASE_MS',20000,5000,120000),
  sessionTTL:number('SESSION_TTL_MS',90000,30000,3600000),connectTimeout:number('CONNECT_TIMEOUT_MS',45000,5000,120000),idleTimeout:number('LIVE_IDLE_TIMEOUT_MS',180000,30000,3600000)};
}
