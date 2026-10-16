import {readFileSync} from 'node:fs';import {resolve} from 'node:path';import {Fault} from './store.mjs';
export function validateGiftMap(value){
 if(!value||typeof value!=='object'||Array.isArray(value)||Object.keys(value).length>200)throw new Fault('invalid_gift_map');
 const result={};for(const [id,effect] of Object.entries(value)){
  if(!/^\d{1,20}$/.test(id)||!effect||!['rocket','rainbow_cat','jump','heal','power'].includes(effect.key)||!Number.isFinite(effect.value)||effect.value<0||effect.value>1e9)throw new Fault('invalid_gift_map');
  result[id]={key:effect.key,value:effect.value};
 }return result;
}
export function loadConfig(env=process.env){
 const number=(key,fallback,min,max)=>{const n=Number(env[key]??fallback);if(!Number.isInteger(n)||n<min||n>max)throw new Error(`Invalid ${key}`);return n;};
 const key=name=>{const value=env[name];if(!value||value.length<32)throw new Error(`Set ${name} to a random secret of at least32 characters`);return value;};
 const bridgeKey=key('BRIDGE_API_KEY'),adminKey=key('ADMIN_API_KEY');if(bridgeKey===adminKey)throw new Error('Use different bridge and admin keys');
 const eulerKey=env.EULER_API_KEY?.trim()||env.EULER_TOKEN?.trim();
 if(!eulerKey)throw new Error('Set EULER_TOKEN (or EULER_API_KEY)');
 let giftMap={};if(env.GIFT_MAP_FILE)giftMap=validateGiftMap(JSON.parse(readFileSync(resolve(env.GIFT_MAP_FILE),'utf8')));
 return {port:number('PORT',7435,1,65535),host:env.HOST||'127.0.0.1',dbPath:resolve(env.DB_PATH||'data/bridge.sqlite'),bridgeKey,adminKey,eulerKey,
  giftMap,tikkiesEnabled:env.TIKKIES_ENABLED==='true',maxConnections:number('MAX_LIVE_CONNECTIONS',5,1,100),maxConnectAttempts:number('MAX_CONNECT_ATTEMPTS_PER_MINUTE',5,1,1000),maxProcessing:number('MAX_PROCESSING',10,1,100),
  maxSessions:number('MAX_SESSIONS',200,1,1000),maxActors:number('MAX_VIEWERS_PER_STREAM',30,1,1000),maxQueue:number('MAX_EVENTS_PER_STREAM',1000,10,100000),
  maxInbox:number('MAX_INBOX_PER_STREAM',10000,100,100000),eventTTL:number('EVENT_TTL_MS',120000,10000,3600000),leaseMs:number('DELIVERY_LEASE_MS',20000,5000,120000),
  sessionTTL:number('SESSION_TTL_MS',90000,30000,3600000),connectTimeout:number('CONNECT_TIMEOUT_MS',45000,5000,120000),idleTimeout:number('LIVE_IDLE_TIMEOUT_MS',180000,30000,3600000)};
}
