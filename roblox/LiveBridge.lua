-- Server only. Session tokens and the bridge key never leave this module.
local Http=game:GetService("HttpService")
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local Bridge={}
Bridge.__index=Bridge
local transient={avatar_unavailable=true,join_in_progress=true,handler_failed=true,event_limit=true,spawn_unavailable=true}
local function normalize(value)
 if type(value)~="string" or #value>32 then return nil end
 value=value:match("^%s*(.-)%s*$"):gsub("^@",""):lower()
 if #value<2 or #value>24 or value:find("[^%w._]") then return nil end
 return value
end
function Bridge.new(config,handlers,options)
 options=options or {}
 local self=setmetatable({config=config,handlers=handlers,states={},closing={},pending={},inflight=0,alive=true,
  jobId=options.jobId or (game.JobId~="" and game.JobId or "studio-"..Http:GenerateGUID(false)),
  spawn=options.spawn or task.spawn,now=options.now or os.clock,statusCursor=0,
  bridgeKey=options.request and "fake-transport-key" or nil},Bridge)
 self.request=options.request or function(path,method,body,key)
  local ok,response=pcall(function()
   return Http:RequestAsync({Url=config.Origin..path,Method=method,
    Headers={["Content-Type"]="application/json",Authorization=typeof(key)=="Secret" and key:AddPrefix("Bearer ") or "Bearer "..key},
    Body=method~="GET" and method~="DELETE" and (next(body or {}) and Http:JSONEncode(body) or "{}") or nil})
  end)
  if not ok then return nil,0 end
  local parsed,data=pcall(Http.JSONDecode,Http,response.Body)
  return parsed and data or nil,response.StatusCode
 end
 return self
end
function Bridge:publish(player,state,errorCode)
 if not player.Parent then return end
 player:SetAttribute("LiveEnabled",state~=nil)
 player:SetAttribute("LiveProvider",state and state.provider or self.config.Provider or "direct")
 player:SetAttribute("LiveUsername",state and state.username or "")
 player:SetAttribute("LiveStatus",state and (state.resetting and "resetting" or state.status) or "disconnected")
 player:SetAttribute("LiveError",errorCode or state and state.joinModeError or "")
 player:SetAttribute("LiveQueueDepth",state and state.queueDepth or 0)
 player:SetAttribute("LiveGiftMapVersion",state and state.giftMapVersion or nil)
 player:SetAttribute("LiveGiftMapSource",state and state.giftMapSource or nil)
 player:SetAttribute("LiveGameRunId",state and (state.provider=="tikkies" and "tikkies-game-"..state.legacyEpoch or state.runId) or nil)
 player:SetAttribute("LiveGameGeneration",state and (state.provider=="tikkies" and 1 or state.generation) or nil)
end
function Bridge:closeDirect(player,s)
 if not s.id or not s.token then return false end
 local _,code=self.request("/v1/sessions/"..s.id,"DELETE",nil,s.token)
 if code==200 or code==404 or code==410 then
  if self.closing[player]==s then self.closing[player]=nil end
  return true
 end
 return false
end
function Bridge:disconnect(player)
 local s=self.states[player]
 self.states[player]=nil
 self.handlers.clear(player)
 self:publish(player,nil)
 if not s then return true end
 for key,item in self.pending do if item.state==s then self.pending[key]=nil end end
 if s.provider=="tikkies" then if self.onTikkiesChanged then self.onTikkiesChanged() end return true end
 self.closing[player]=s
 if s.id and s.token then
  self.spawn(function()
   for attempt=1,3 do
    if self:closeDirect(player,s) then return end
    task.wait(attempt)
   end
  end)
 end
 return true
end
function Bridge:ensureBridgeKey()
 if not self.bridgeKey then
  local ok,secret
  if type(self.config.BridgeApiKey)=="string" and #self.config.BridgeApiKey>=32 then ok,secret=true,self.config.BridgeApiKey
  else ok,secret=pcall(Http.GetSecret,Http,self.config.BridgeSecretName or "BRIDGE_API_KEY") end
  if not ok then return false,"bridge_not_configured" end
  self.bridgeKey=secret
 end
 return true
end
function Bridge:giftMappings(player)
 local state=self.states[player]
 if state and state.provider~="direct" then return nil,"direct_only" end
 if state and (not state.id or not state.token) then return nil,"connecting" end
 local ok,reason=self:ensureBridgeKey() if not ok then return nil,reason end
 local path=state and "/v1/sessions/"..state.id or "/v1/direct/gift-mappings"
 local data,code=self.request(path,"GET",nil,state and state.token or self.bridgeKey)
 if self.states[player]~=state then return nil,"cancelled" end
 if code~=200 or type(data)~="table" or type(data.giftMappings)~="table" then return nil,data and data.error or "network_error" end
 return data.giftMappings
end
function Bridge:connect(player,username,provider,joinMode)
 if not self.alive or (provider~="direct" and provider~="tikkies") then return false,"invalid_provider" end
 if self.closing[player] and not self:closeDirect(player,self.closing[player]) then return false,"previous_connection_closing" end
 username=normalize(username)
 if provider=="direct" and not username then return false,"invalid_username" end
 if provider=="tikkies" and not self.config.TikkiesEnabled then return false,"tikkies_unavailable" end
 joinMode=joinMode or "both"
 if joinMode~="at" and joinMode~="plain" and joinMode~="both" then return false,"invalid_join_mode" end
 local previous=self.states[player]
 if previous then return false,"disconnect_first" end
 if provider=="direct" then local ok,reason=self:ensureBridgeKey() if not ok then self:publish(player,nil,reason) return false,reason end end
 local s={provider=provider,username=username or "",status="connecting",joinMode=joinMode,desiredJoinMode=joinMode,
  done={},doneCount=0,nextStatus=0,legacyEpoch=Http:GenerateGUID(false),legacyActors={}}
 -- A disconnected dev arena must not retain its scope when LIVE takes over.
 self.handlers.clear(player)
 self.states[player]=s self:publish(player,s)
 if provider=="tikkies" then
  if self.onTikkiesChanged then self.onTikkiesChanged() end
  return true
 end
 local data,code=self.request("/v1/sessions","POST",{ownerRobloxId=tostring(player.UserId),jobId=self.jobId,
  tiktokUsername=username,provider="direct",joinMode=joinMode,universeId=tostring(game.GameId)},self.bridgeKey)
 if self.states[player]~=s or not player.Parent or not self.alive then
  if data and data.id and data.token then
   s.id=data.id s.token=data.token self.closing[player]=s self:closeDirect(player,s)
  elseif self.closing[player]==s then self.closing[player]=nil end
  return false,"cancelled"
 end
 if code~=201 or type(data)~="table" or type(data.id)~="string" or type(data.token)~="string"
  or type(data.runId)~="string" or type(data.generation)~="number" then
  self.states[player]=nil self:publish(player,nil,data and data.error or "network_error")
  return false,data and data.error or "network_error"
 end
 s.id=data.id s.token=data.token s.runId=data.runId s.generation=data.generation
 s.joinMode=data.joinMode or "both"
 s.giftMapVersion=data.giftMapVersion s.giftMapSource=data.giftMapSource
 s.status=data.status or "queued" self:publish(player,s)
 return true
end
function Bridge:setJoinMode(player,mode)
 if mode~="at" and mode~="plain" and mode~="both" then return false end
 local s=self.states[player]
 if s then s.desiredJoinMode=mode s.nextModeUpdate=0 end
 return true
end
function Bridge:reset(player)
 local s=self.states[player]
 if not s then return true end
 if s.provider=="tikkies" then
  -- A race round is not a live session: keep transport, source bindings and receiver dedupe.
  s.legacyEpoch=Http:GenerateGUID(false) s.legacyRoundActors={}
  s.resetting=false s.legacyReadyAt=nil
  self.handlers.clear(player) self:publish(player,s)
  return true
 end
 if not s.id then return false end
 if s.resetBusy then return false end
 s.resetting=true s.resetBusy=true s.resetId=s.resetId or Http:GenerateGUID(false)
 self.handlers.clear(player) self:publish(player,s)
 for key,item in self.pending do if item.state==s then self.pending[key]=nil end end
 local data,code=self.request("/v1/sessions/"..s.id.."/reset","POST",{requestId=s.resetId},s.token)
 s.resetBusy=false
 if self.states[player]~=s then return false end
 if code==200 and data and type(data.runId)=="string" and type(data.generation)=="number" then
  s.runId=data.runId s.generation=data.generation s.done={} s.doneCount=0
  s.resetting=false s.resetId=nil s.status=data.status or s.status self:publish(player,s) return true
 end
 if code==410 or code==404 or code==401 then self:disconnect(player) return false end
 s.nextReset=self.now()+3 self:publish(player,s,"reset_retrying") return false
end
function Bridge:legacyEvent(player,context,join)
 local s=self.states[player]
 if not s or s.provider~="tikkies" then return false,"owner_not_present" end
 if s.resetting then return false,"stale_round" end
 if context.ownerRobloxId~=tostring(player.UserId) then return false,"invalid_actor" end
 local epoch=s.legacyEpoch
 local binding=s.legacyActors[context.actorKey]
 if not join and (not binding or binding.robloxId~=context.robloxId
  or binding.runId~=context.runId or binding.generation~=context.generation) then return false,"viewer_not_joined" end
 s.legacyRoundActors=s.legacyRoundActors or {}
 local copy=table.clone(context)
 copy.runId="tikkies-game-"..epoch
 copy.generation=1
 if not join and s.legacyRoundActors[context.actorKey]~=context.robloxId then
  if type(copy.effects)=="table" and #copy.effects==0 then return true end
  -- The source already confirmed this viewer; recreate only their fresh race actor.
  local joining=table.clone(copy) joining.eventType="join" joining.effects={}
  local accepted,reason=self.handlers.join(joining)
  if self.states[player]~=s or s.legacyEpoch~=epoch or s.resetting then return false,"stale_round" end
  if not accepted then return false,reason end
  s.legacyRoundActors[context.actorKey]=context.robloxId
 end
 local accepted,reason=(join and self.handlers.join or self.handlers.event)(copy)
 if self.states[player]~=s or s.legacyEpoch~=epoch or s.resetting then return false,"stale_round" end
 if join and accepted then
  s.legacyActors[context.actorKey]={robloxId=context.robloxId,runId=context.runId,generation=context.generation}
  s.legacyRoundActors[context.actorKey]=context.robloxId
 end
 return accepted,reason
end
function Bridge:handle(player,s,event)
 if self.states[player]~=s or s.resetting or not player.Parent then return end
 if type(event)~="table" or type(event.eventId)~="string" or #event.eventId>200
  or type(event.receipt)~="string" or event.liveSessionId~=s.id
  or event.ownerRobloxId~=tostring(player.UserId) or event.runId~=s.runId or event.generation~=s.generation then return end
 local parsed,expires=pcall(DateTime.fromIsoDate,event.expiresAt)
 if not parsed or not expires or expires.UnixTimestampMillis<=DateTime.now().UnixTimestampMillis then return end
 local key=s.id..":"..s.runId..":"..s.generation..":"..event.eventId
 if s.busyEvent then return end
 local result=s.done[key]
 if not result then
  if self.inflight>=8 or s.doneCount>=2000 then return end
  s.busyEvent=true self.inflight+=1
  local ok,accepted,reason=pcall(function()
   if event.eventType=="join" then return self.handlers.join(event) end
   if event.eventType=="gift" or event.eventType=="like" or event.eventType=="chat"
    or event.eventType=="follow" or event.eventType=="share" or event.eventType=="social" then return self.handlers.event(event) end
   return false,"unsupported_event"
  end)
  s.busyEvent=false self.inflight-=1
  if self.states[player]~=s or s.resetting or event.runId~=s.runId or event.generation~=s.generation then return end
  reason=ok and reason or "handler_failed"
  result={success=ok and accepted==true,retry=transient[reason]==true,
   expires=expires.UnixTimestampMillis/1000+60}
  if result.success or not result.retry then s.done[key]=result s.doneCount+=1 end
 end
 self.pending[key]={state=s,body={sessionId=s.id,eventId=event.eventId,receipt=event.receipt,
  success=result.success,retry=result.retry}}
end
function Bridge:flush()
 local batch,keys={},{}
 for key,item in self.pending do
  if #batch>=100 then break end
  table.insert(batch,item.body) table.insert(keys,key)
 end
 if #batch==0 then return end
 local data,code=self.request("/v1/servers/"..self.jobId.."/ack","POST",{receipts=batch},self.bridgeKey)
 if code==200 and data then
  for i,key in keys do if self.pending[key] and self.pending[key].body==batch[i] then self.pending[key]=nil end end
 end
end
function Bridge:step()
 if not self.alive then return end
 self:flush()
 local byId,active={},{}
 for player,s in self.states do
  if s.provider=="direct" and s.id then
   if s.desiredJoinMode~=s.joinMode and not s.modeBusy and self.now()>=(s.nextModeUpdate or 0) then
    s.modeBusy=true local wanted=s.desiredJoinMode
    self.spawn(function()
     local data,code=self.request("/v1/sessions/"..s.id.."/join-mode","POST",{joinMode=wanted},s.token)
     s.modeBusy=false
     if self.states[player]~=s then return end
     if code==200 and data and data.joinMode==wanted then s.joinMode=wanted s.joinModeError=nil s.nextModeUpdate=0
     else s.joinModeError="join_mode_update_failed" s.nextModeUpdate=self.now()+10 end
     self:publish(player,s)
    end)
   end
   byId[s.id]={player=player,state=s} table.insert(active,{player=player,state=s})
   for key,result in s.done do
    if result.expires<DateTime.now().UnixTimestamp then s.done[key]=nil s.doneCount-=1 end
   end
   if s.resetting and not s.resetBusy and self.now()>=(s.nextReset or 0) then
    s.nextReset=self.now()+3 self.spawn(function() self:reset(player) end)
   end
  end
 end
 if #active==0 then return end
 local sessionIds={}
 for id in byId do table.insert(sessionIds,id) end
 local data,code=self.request("/v1/servers/"..self.jobId.."/poll","POST",{sessionIds=sessionIds},self.bridgeKey)
 if code==200 and data and type(data.events)=="table" then
  for i,item in data.events do
   if i>100 then break end
   local pair=byId[item.sessionId]
   if pair then self.spawn(function() self:handle(pair.player,pair.state,item.event) end) end
  end
 elseif code==401 or code==403 then
  for _,pair in active do pair.state.status="error" self:publish(pair.player,pair.state,"bridge_unauthorized") end
 elseif code~=200 then
  for _,pair in active do self:publish(pair.player,pair.state,"network_error") end
 end
 -- Round-robin status reads cap HTTP use even with many owners in one job.
 for _=1,math.min(2,#active) do
  self.statusCursor=self.statusCursor%#active+1
  local pair=active[self.statusCursor] local s,player=pair.state,pair.player
  if not s.resetting and self.now()>=s.nextStatus then
   s.nextStatus=self.now()+15
   local generation=s.generation
   local status,response=self.request("/v1/sessions/"..s.id,"GET",nil,s.token)
   if self.states[player]==s and s.generation==generation and not s.resetting then
    if response==200 and status then
     if status.runId~=s.runId or status.generation~=s.generation then
      self.handlers.clear(player) s.done={} s.doneCount=0
      s.runId=status.runId s.generation=status.generation
     end
     if status.status=="closed" or status.status=="expired" then self:disconnect(player)
     else s.status=status.status s.queueDepth=status.queueDepth self:publish(player,s) end
    elseif response==410 or response==404 or response==401 then self:disconnect(player) end
   end
  end
 end
 self:flush()
end
function Bridge:start()
 self.removing=Players.PlayerRemoving:Connect(function(p) self:disconnect(p) end)
 task.spawn(function()
  while self.alive do
   local ok=pcall(function() self:step() end)
   if not ok then warn("LiveBridge: receiver step failed; retrying") end
   task.wait(math.max(1,self.config.PollSeconds or 1))
  end
 end)
 game:BindToClose(function()
  self.alive=false
  for p in self.states do self:disconnect(p) end
  task.wait(2)
 end)
end
return Bridge
