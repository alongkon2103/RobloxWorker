return function(Bridge)
 local player={UserId=123,Parent=true,attrs={}}function player:SetAttribute(k,v)self.attrs[k]=v end
 local bridge local changes={}local created,closed=0,0
 local function request(path,method,body)
  if path=="/v1/sessions"then created+=1 assert(body.joinMode=="both","New Direct connection does not default to Both")return {id="same-session",token="token",runId="same-run",generation=1,status="live",joinMode="both"},201 end
  if path:find("/join-mode",1,true)then
   table.insert(changes,body.joinMode)
   if body.joinMode=="at"then bridge:setJoinMode(player,"plain")end
   return {joinMode=body.joinMode},200
  end
  if method=="DELETE"then closed+=1 end
  return {events={},results={},status="live",runId="same-run",generation=1},200
 end
 bridge=Bridge.new({TikkiesEnabled=true},{clear=function()end},{request=request,spawn=function(fn)fn()end,now=function()return 1 end})
 assert(bridge:connect(player,"streamer","direct"))
 bridge:setJoinMode(player,"at")bridge:step()bridge:step()
 assert(changes[1]=="at"and changes[2]=="plain","Newer selection waited for an old update cooldown")
 assert(bridge.states[player].id=="same-session"and bridge.states[player].runId=="same-run")
 assert(created==1 and closed==0,"Changing join format reconnected LIVE")
 return "PASS: Both default; live changes and rapid selections keep the same session/run without reconnect"
end
