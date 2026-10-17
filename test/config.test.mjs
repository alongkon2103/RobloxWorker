import test from 'node:test';import assert from 'node:assert/strict';import {loadConfig,validateGiftMap} from '../src/config.mjs';
const base={BRIDGE_API_KEY:'b'.repeat(32),ADMIN_API_KEY:'a'.repeat(32),EULER_TOKEN:'example-test-token'};
test('Euler token alias and configuration validation',()=>{
 const c=loadConfig(base);assert.equal(c.port,7435);assert.equal(c.eulerKey,'example-test-token');assert.equal(c.tikkiesEnabled,false);
 assert.equal(loadConfig({...base,EULER_API_KEY:''}).eulerKey,'example-test-token');
 assert.throws(()=>loadConfig({...base,ADMIN_API_KEY:base.BRIDGE_API_KEY}),/different/);
 assert.throws(()=>loadConfig({...base,PORT:'-1'}),/PORT/);
 assert.throws(()=>validateGiftMap({99:{key:'unknown',value:1}}),/gift_map/);
 assert.throws(()=>validateGiftMap({99:{key:'rocket',value:NaN}}),/gift_map/);
});
test('rainbow_cat can be mapped to a TikTok gift',()=>{
 assert.doesNotThrow(()=>validateGiftMap({123:{key:'rainbow_cat',value:1}}));
});
test('naruto can be mapped to a TikTok gift',()=>{
 assert.doesNotThrow(()=>validateGiftMap({777:{key:'naruto',value:1}}));
});

test('stacking speed boost can be mapped to a TikTok gift',()=>{assert.deepEqual(validateGiftMap({321:{key:'speed_boost',value:1}}),{321:{key:'speed_boost',value:1}});});

test('fly can be mapped to a TikTok gift',()=>{assert.deepEqual(validateGiftMap({322:{key:'fly',value:1}}),{322:{key:'fly',value:1}});});

test('scoped overlay config validates origin, allowlist and distinct map/service credentials',()=>{
 const env={...base,TIKKIES_OVERLAY_SERVICE_KEY:'s'.repeat(32),TIKKIES_OVERLAY_UNIVERSES:'100,200'};
 const c=loadConfig(env);assert.deepEqual(c.overlayUniverses,['100','200']);assert.equal(c.overlayOrigin,'https://rbworker.aclassstore.com');
 assert.throws(()=>loadConfig({...env,TIKKIES_OVERLAY_SERVICE_KEY:base.BRIDGE_API_KEY}),/different/);
 assert.throws(()=>loadConfig({...env,TIKKIES_OVERLAY_UNIVERSES:''}),/UNIVERSES/);
 for(const value of ['http://example.com','https://example.com/overlay','https://user:pass@example.com','https://example.com/#x'])assert.throws(()=>loadConfig({...env,OVERLAY_PUBLIC_ORIGIN:value}),/ORIGIN/);
 assert.throws(()=>loadConfig({...env,TIKKIES_OVERLAY_UNIVERSES:'100,100'}),/UNIVERSES/);
});
