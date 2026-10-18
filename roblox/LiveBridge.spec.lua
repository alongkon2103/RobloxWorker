return function(Bridge)
 local calls,handled,failAck,resets={},0,true,0
 local player={UserId=123,Parent=true,attrs={}}
 function player:SetAttribute(k,v) self.attrs[k]=v end
 local packet
 local handler={clear=function() end,join=function() handled+=1 return true end,event=function() handled+=1 return true end}
 local function request(path,method,body,key)
  table.insert(calls,{path=path,body=body})
  if path=="/v1/sessions" then return {id="session-a",token="private-session",runId="run-a",generation=1,status="live"},201 end
  if path:find("/reset") then resets+=1 if resets==1 then return nil,0 end return {runId="run-b",generation=2,status="live"},200 end
  if path:find("/ack") then if failAck then failAck=false return nil,0 end return {results={}},200 end
  if path:find("/poll") then return {events=packet and {{sessionId="session-a",event=packet}} or {}},200 end
  return {status="live",runId=resets>=2 and "run-b" or "run-a",generation=resets>=2 and 2 or 1,queueDepth=0},200
 end
 local b=Bridge.new({Origin="https://example.com",BridgeApiKey="fake-test-only-key",Provider="direct"},handler,
  {request=request,jobId="job-a",spawn=function(fn) fn() end,now=function() return 1000 end})
 assert(b:connect(player,"@Streamer.Name","direct"))
 assert(calls[1].body.universeId==tostring(game.GameId),"Direct sessions must include the game Universe ID")
 assert(calls[1].body.ownerRobloxId=="123" and calls[1].body.jobId=="job-a")
 local function event(owner,run,generation)
  return {eventId="evt-a",receipt="receipt-a",liveSessionId="session-a",ownerRobloxId=owner,runId=run,generation=generation,
   eventType="join",actorKey="tiktok:viewer",robloxId="456",effects={},expiresAt="2099-01-01T00:00:00Z"}
 end
 packet=event("999","run-a",1) b:step() assert(handled==0,"cross-owner event applied")
 packet=event("123","wrong-run",1) b:step() assert(handled==0,"old-round event applied")
 packet=event("123","run-a",1) b:step() assert(handled==1)
 b:step() b:step() assert(handled==1,"ACK retry duplicated gameplay")
 assert(not b:reset(player)) assert(b.states[player].resetting)
 local firstId=calls[#calls].body.requestId
 assert(b:reset(player)) assert(calls[#calls].body.requestId==firstId,"reset retry changed requestId")
 packet=event("123","run-a",1) b:step() assert(handled==1,"reset leaked old event")
 packet=event("123","run-b",2) b:step() assert(handled==2)
 assert(not b:connect(player,"bad/name","direct"))
 b:disconnect(player) assert(not b.states[player])
 return "LiveBridge routing, ACK dedupe, reset barrier and validation passed"
end
