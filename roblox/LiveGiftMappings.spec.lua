-- Run in Studio with a fresh LiveBridge module and a fake transport.
return function(Bridge)
 local calls={}
 local bridge=Bridge.new({}, {}, {request=function(path,method,body,key)
  table.insert(calls,{path=path,key=key})
  return {giftMappings={{giftId="1",giftName="Rose",eventKey="shield"}}},200
 end})
 local player={}
 assert(bridge:giftMappings(player)[1].giftName=="Rose")
 assert(calls[1].path=="/v1/direct/gift-mappings")
 bridge.states[player]={provider="tikkies"}
 local rows,reason=bridge:giftMappings(player)
 assert(rows==nil and reason=="direct_only" and #calls==1)
 bridge.states[player]={provider="direct",id="owner",token="owner-token"}
 assert(bridge:giftMappings(player))
 assert(calls[2].path=="/v1/sessions/owner" and calls[2].key=="owner-token")
 bridge.request=function()bridge.states[player]=nil return {giftMappings={}},200 end
 rows,reason=bridge:giftMappings(player)
 assert(rows==nil and reason=="cancelled")
 return true
end
