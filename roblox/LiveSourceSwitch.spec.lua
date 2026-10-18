return function(Bridge)
 local p={UserId=123,Parent=true}function p:SetAttribute()end
 local deletingFails=true local waiting={}
 local function request(path,method)
  if path=="/v1/sessions"then return {id="id",token="token",runId="run",generation=1,status="live"},201 end
  if method=="DELETE"then if deletingFails then return nil,0 end return {ok=true},200 end
 end
 local b=Bridge.new({TikkiesEnabled=true},{clear=function()end},{request=request,spawn=function(fn)table.insert(waiting,fn)end})
 assert(b:connect(p,"streamer","direct"))b:disconnect(p)
 local ok,reason=b:connect(p,"","tikkies")assert(not ok and reason=="previous_connection_closing","Tikkies started before Direct closed")
 deletingFails=false assert(b:connect(p,"","tikkies"))assert(b.states[p].provider=="tikkies")
 b:disconnect(p)
 return "PASS: changing source waits for Direct shutdown confirmation"
end
