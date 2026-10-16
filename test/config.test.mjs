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
