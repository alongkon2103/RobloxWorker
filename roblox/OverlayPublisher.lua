-- Server owns all race data and write credentials. Clients only receive their own read URL.
local Players=game:GetService("Players")
local Http=game:GetService("HttpService")
local RS=game:GetService("ReplicatedStorage")
local Settings=require(script.Parent.OverlayConfig)
local RaceConfig=require(script.Parent.RaceConfig)
local Events=require(RS.RaceEventConfig)
local WinResults=require(script.Parent.TopWinResults)
local Names=require(script.Parent.ViewerDisplayName)
local Publisher={}
function Publisher.start(config,transport)
 local entries={} local cooldown={} local active=true local sending=false
 local route,path,routeVersion local routeDirty=true local rebuilding=false
 local remote=Instance.new("RemoteFunction") remote.Name="OverlayControl" remote.Parent=RS
 local scoped=Settings.ScopedPublishingEnabled==true
 local function bridgeKey()
  if scoped then
   if type(config.OverlayMapApiKey)=="string"and #config.OverlayMapApiKey>=32 then return config.OverlayMapApiKey end
   local ok,mapKey=pcall(Http.GetSecret,Http,Settings.MapSecretName or "OVERLAY_MAP_API_KEY")
   return ok and mapKey or nil
  end
  if type(config.BridgeApiKey)=="string" and #config.BridgeApiKey>=32 then return config.BridgeApiKey end
  local ok,key=pcall(Http.GetSecret,Http,config.BridgeSecretName or "BRIDGE_API_KEY")
  return ok and key or nil
 end
 local key=bridgeKey()
 local function ensure(p)
  if not entries[p]then entries[p]={claimId=Http:GenerateGUID(false),enabled=true,nextBoard=0}end
  return entries[p]
 end
 for _,p in Players:GetPlayers()do ensure(p)end
 local joined=Players.PlayerAdded:Connect(ensure)
 WinResults.start(transport,key)
 local gameRemote=Instance.new('RemoteFunction')gameRemote.Name='OverlayGameData'gameRemote.Parent=RS
 local gameCooldown={}
 gameRemote.OnServerInvoke=function(p,version)
  if (gameCooldown[p]or 0)>os.clock()then return nil end gameCooldown[p]=os.clock()+.75
  local e=ensure(p)
  local board=e.topWin
  if board and board.nextResetAt and DateTime.now().UnixTimestampMillis>=board.nextResetAt then board=nil e.nextBoard=0 end
  return {route=route and version~=routeVersion and route or nil,topWin=board}
 end
 local function rebuild()
  if rebuilding then return end rebuilding=true
  local gatesFolder=RS:FindFirstChild("ViewerRoute")
  if not gatesFolder then rebuilding=false return end
  local gates={} for _,g in gatesFolder:GetChildren()do local i=g:GetAttribute("Index") if g:IsA("BasePart") and type(i)=="number"then gates[i]=g end end
  if #gates<2 then rebuilding=false return end
  local ok,result=pcall(function()return require(RS.RacePath).new(gates,RaceConfig)end)
  if ok then
   path=result local points={} local count=math.clamp(Settings.RouteSamples or 1024,32,2048)
   for i=0,count-1 do local p=path:sample(path.length*i/count,0,0).Position table.insert(points,{math.round(p.X*100)/100,math.round(p.Z*100)/100})end
   routeVersion=Http:GenerateGUID(false)
   route={version=routeVersion,length=path.length,points=points} routeDirty=false
  end
  rebuilding=false
 end
 local function status(p,value)if p.Parent then p:SetAttribute("OverlayStatus",value)end end
 local function claim(p,e)
  if e.claiming or os.clock()<(e.retryAt or 0)then return false end
  if not key then key=bridgeKey()end
  if not key then status(p,scoped and "overlay_map_not_configured"or "bridge_not_configured")e.retryAt=os.clock()+10 return false end
  e.claiming=true
  local body={ownerRobloxId=tostring(p.UserId),jobId=transport.jobId,claimId=e.claimId}
  if scoped then
   if game.GameId<=0 then e.claiming=false status(p,"overlay_universe_required")e.retryAt=os.clock()+10 return false end
   body.universeId=tostring(game.GameId)
  end
  local data,code=transport.request("/v1/overlays/claim","POST",body,key)
  e.claiming=false
  if entries[p]~=e then return false end
  if code==200 and data and type(data.readToken)=="string" and type(data.writeToken)=="string"
   and(not scoped or(data.schemaVersion==2 and data.universeId==tostring(game.GameId)))then
   e.readToken=data.readToken e.writeToken=data.writeToken e.sequence=0 e.needsRoute=true status(p,"ready")return true
  end
  e.retryAt=os.clock()+10 status(p,code==404 and "deploy_required" or data and data.error or "unavailable")return false
 end
 local function url(e,view)
  return Settings.PublicOrigin:gsub("/$","").."/overlay?view="..view.."#"..e.readToken
 end
 remote.OnServerInvoke=function(p,action)
  local now=os.clock()if now<(cooldown[p] or 0)then return {ok=false,error="cooldown"}end cooldown[p]=now+.5
  if not Settings.Enabled then return {ok=false,error="disabled"}end
  if action~="enable" and action~="info"then return {ok=false,error="invalid_action"}end
  local e=ensure(p)
  if not e.readToken and not claim(p,e)then return {ok=false,enabled=true,error=p:GetAttribute("OverlayStatus")}end
  if not e.readToken then return {ok=false,error="connecting"}end
  return {ok=true,enabled=true,urls={map=url(e,"map"),ranking=url(e,"ranking"),speed=url(e,"speed"),topWin=url(e,"top-win"),all=url(e,"all")}}
 end
 local function sample(p,e)
  local round=tostring(p:GetAttribute("ViewerRaceRound") or 1)
  local folder=workspace:FindFirstChild("TikkiesDemoNPCs") local racers={}
  local runScope="empty"
  if folder then for _,m in folder:GetChildren()do
   if m:GetAttribute("OwnerRobloxId")==tostring(p.UserId)then
    local actor=m:GetAttribute("ActorKey") local hum=m:FindFirstChildOfClass("Humanoid")
    if actor and hum and hum.Health>0 then
     runScope=tostring(m:GetAttribute("RunId") or "")..":"..tostring(m:GetAttribute("Generation") or 1)
     local rid=runScope..":"..round
     e.round=rid
     local speed=math.clamp(m:GetAttribute("RouteSpeed") or 0,0,1500)
     local effects={} local now=workspace:GetServerTimeNow()
     for name,c in Events do local untilAt=m:GetAttribute(c.Attribute.."Until") or 0 if untilAt>now then table.insert(effects,{key=name,remaining=untilAt-now,tier=c.Tier or 0})end end
     table.insert(racers,{id=actor,robloxId=tostring(m:GetAttribute("RobloxId")),name=tostring(m:GetAttribute("ViewerDisplayName") or "Viewer"),distance=m:GetAttribute("RouteDistance") or -14,speed=speed,topSpeed=speed,rank=m:GetAttribute("RaceRank") or 0,state=m:GetAttribute("RaceState") or "Lobby",effects=effects,tiktokAvatarUrl=m:GetAttribute("ViewerTikTokAvatarUrl")})
    end
   end
  end end
  if #racers==0 then local rid="empty:"..round e.round=rid end
  return {round=e.round or "empty:1",phase=p:GetAttribute("ViewerRacePhase") or "Lobby",laps=RaceConfig.Laps or 2,metersPerStud=RaceConfig.MetersPerStud or .28,racers=racers}
 end
 local function send()
  if sending then return end sending=true
  task.spawn(function()
   local ok=pcall(function()
    if key then WinResults.start(transport,key)WinResults.flush()end
    if routeDirty or not route then rebuild()end if not route then return end
    local items,owners={} ,{} local includeRoute=false
    for p,e in entries do if p.Parent and e.enabled and not e.claiming then
     if not e.writeToken then claim(p,e)end
     if os.clock()>=(e.nextBoard or 0)then
      e.nextBoard=os.clock()+10
      local body={ownerRobloxId=tostring(p.UserId),jobId=transport.jobId}
      if p:GetAttribute('LiveEnabled')then body.provider=p:GetAttribute('LiveProvider')body.channel=p:GetAttribute('LiveUsername')end
      if body.provider=='direct'and(not body.channel or body.channel=='')then body.provider=nil end
      local board,code=transport.request('/v1/overlays/top-win/board','POST',body,key)
      if code==200 and board and type(board.rows)=='table'then
       e.names=e.names or {}
       for _,r in board.rows do
        local cache=e.names[r.id]
        if not cache or cache.input~=r.name or os.clock()>cache.untilAt then
         local filtered=Names.filter(r.name,p.UserId)
         cache={input=r.name,value=filtered,untilAt=os.clock()+90}e.names[r.id]=cache
        end
        r.name=cache.value
       end
       e.topWin=board
      end
     end
     if e.writeToken then
      e.sequence+=1 local snapshot=sample(p,e)
      table.insert(items,{writeToken=e.writeToken,sequence=e.sequence,snapshot=snapshot})table.insert(owners,{p=p,e=e})
      if e.needsRoute or e.routeVersion~=routeVersion then includeRoute=true end
     end
    end end
    if #items==0 then return end
    local batches={} local batch={items={},owners={}}
    local routeBytes=includeRoute and #Http:JSONEncode(route) or 0
    local bytes=routeBytes+100
    for i,item in items do
     local size=#Http:JSONEncode(item)+1
     if #batch.items>0 and bytes+size>200000 then table.insert(batches,batch)batch={items={},owners={}}bytes=routeBytes+100 end
     table.insert(batch.items,item)table.insert(batch.owners,owners[i])bytes+=size
    end
    if #batch.items>0 then table.insert(batches,batch)end
    for _,packet in batches do
    local data,code=transport.request("/v1/overlays/batch","POST",{items=packet.items,route=includeRoute and route or nil},key)
    for i,owner in packet.owners do local e=owner.e if entries[owner.p]==e then
     local result=data and data.results and data.results[i]
     if code==200 and result and result.ok then e.needsRoute=false e.routeVersion=routeVersion status(owner.p,"live")
     elseif result and (result.error=="overlay_lease_expired" or result.error=="route_required")then e.writeToken=nil e.retryAt=0 status(owner.p,"reconnecting")
     else status(owner.p,code==404 and "deploy_required" or code==200 and result and result.error or "unavailable")end
    end end
    end
   end)
   if not ok then for p in entries do status(p,"unavailable")end end
   sending=false
  end)
 end
 local gates=RS:WaitForChild("ViewerRoute")
 local changed=gates.DescendantAdded:Connect(function()routeDirty=true end)
 local removed=gates.DescendantRemoving:Connect(function()routeDirty=true end)
 local leave=Players.PlayerRemoving:Connect(function(p)
  local e=entries[p] entries[p]=nil cooldown[p]=nil gameCooldown[p]=nil
  if e and e.writeToken then task.spawn(function()transport.request("/v1/overlays/release","POST",{},e.writeToken)end)end
 end)
 task.spawn(function()
  while active do
   task.wait(math.max(1,Settings.PublishInterval or 1))
   if active then send()end
  end
 end)
 return {stop=function()active=false changed:Disconnect()removed:Disconnect()leave:Disconnect()joined:Disconnect()remote:Destroy()gameRemote:Destroy()end}
end
return Publisher
