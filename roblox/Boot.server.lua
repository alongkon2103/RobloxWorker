local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Config=require(script.Parent.LiveBridgeConfig)
-- Optional private Studio-only module; never include its populated source in Git.
local credentials=script.Parent:FindFirstChild("LiveCredentials")
if credentials then
 local private=require(credentials)
 Config.BridgeApiKey=private.BridgeApiKey
 Config.TikkiesCredential=private.TikkiesCredential
end
local Handlers=require(script.Parent.GameHandlers)
local Bridge=require(script.Parent.LiveBridge)
local receiver=Bridge.new(Config,Handlers)
local Preferences=require(script.Parent.LivePreferences)
local preferences=Preferences.new(game:GetService("DataStoreService"):GetDataStore("HyperRunLivePreferences_v1"))
local function tikkiesCredential()
 if type(Config.TikkiesCredential)=="string" and #Config.TikkiesCredential>0 then return true,Config.TikkiesCredential end
 return pcall(game:GetService("HttpService").GetSecret,game:GetService("HttpService"),Config.TikkiesSecretName)
end
local secretOk,tikkiesSecret=tikkiesCredential()
local remote=Instance.new("RemoteEvent") remote.Name="LiveSettingsControl" remote.Parent=ReplicatedStorage
local cooldown,busy={},{}
local operation={}
local disconnectCooldown={}
local legacy
local function reply(player,errorCode)
 if player.Parent then
  if errorCode then player:SetAttribute("LiveError",errorCode) end
  remote:FireClient(player,"updated")
 end
end
local function setup(player)
 receiver:publish(player,nil)
 player:SetAttribute("TikkiesAvailable",Config.TikkiesEnabled and secretOk)
 player:SetAttribute("LiveTikkiesError",secretOk and "" or "tikkies_not_configured")
 task.spawn(function()
  preferences:load(player)
  if player.Parent then receiver:setJoinMode(player,player:GetAttribute("PreferredJoinMode") or "both") end
 end)
end
for _,player in Players:GetPlayers() do setup(player) end
Players.PlayerAdded:Connect(setup)
remote.OnServerEvent:Connect(function(player,action,username,provider)
 local now=os.clock()
 if action=="save_username" then
  -- Preferences coalesces the latest validated value into one delayed write.
  preferences:set(player,username)
  return
 end
 if action=="set_join_mode" then
  if preferences:setJoinMode(player,username) then receiver:setJoinMode(player,username) end
  return
 end
 if action=="disconnect" then
  if now<(disconnectCooldown[player] or 0) then return end
  disconnectCooldown[player]=now+.5
  operation[player]=(operation[player] or 0)+1
  busy[player]=nil cooldown[player]=now+.25
  receiver:disconnect(player) reply(player) return
 end
 if busy[player] or (cooldown[player] or 0)>now then return end
 if action~="connect" and action~="disconnect" and action~="reset" then return end
 if action=="connect" and provider~="direct" and provider~="tikkies" then return end
 cooldown[player]=now+2
 local ticket=(operation[player] or 0)+1 operation[player]=ticket busy[player]=ticket
 local ok,errorCode=pcall(function()
  if action=="disconnect" then receiver:disconnect(player)
  elseif action=="reset" then
   Handlers.clear(player)
   receiver:reset(player)
  else
   if provider=="direct" then preferences:set(player,username) end
   local accepted,reason=receiver:connect(player,username,provider,player:GetAttribute("PreferredJoinMode") or "both")
   if not accepted then return reason end
  end
 end)
 if operation[player]==ticket then
  busy[player]=nil
  if ok then reply(player,errorCode) else reply(player,"handler_failed") end
 end
end)
Players.PlayerRemoving:Connect(function(p)
 cooldown[p]=nil busy[p]=nil operation[p]=nil disconnectCooldown[p]=nil
 task.spawn(function() preferences:remove(p) end)
end)
game:BindToClose(function()
 local jobs=0
 for p in preferences.records do jobs+=1 task.spawn(function() preferences:flush(p) jobs-=1 end) end
 local untilTime=os.clock()+20
 repeat task.wait(.1) until jobs==0 or os.clock()>untilTime
end)
script.Parent:WaitForChild("ViewerRoundReset").Event:Connect(function(player)
 task.spawn(function() receiver:reset(player) end)
end)
-- Only the selected owners are advertised to the optional legacy receiver.
local function tikkiesOwners()
 local list={}
 for player,state in receiver.states do if state.provider=="tikkies" and player.Parent then table.insert(list,tostring(player.UserId)) end end
 return list
end
local function tikkiesHandler(event,join)
 local player=Players:GetPlayerByUserId(tonumber(event.ownerRobloxId) or 0)
 local state=player and receiver.states[player]
 if not state or state.provider~="tikkies" then return false,"owner_not_present" end
 return receiver:legacyEvent(player,event,join)
end
receiver.onLegacyReset=function(player) if legacy and legacy.resetOwner then legacy.resetOwner(tostring(player.UserId)) end end
task.spawn(function()
 local nextSecretCheck=0
 while receiver.alive do
  if not secretOk and Config.TikkiesEnabled and os.clock()>=nextSecretCheck then
   nextSecretCheck=os.clock()+10
   secretOk,tikkiesSecret=tikkiesCredential()
   for _,p in Players:GetPlayers() do
    p:SetAttribute("TikkiesAvailable",Config.TikkiesEnabled and secretOk)
    p:SetAttribute("LiveTikkiesError",secretOk and "" or "tikkies_not_configured")
   end
  end
  local wanted=#tikkiesOwners()>0 and Config.TikkiesEnabled and secretOk
  if wanted and not legacy then
   local ok,result=pcall(function()
    return require(script.Parent.TikkiesGames).start({
     origin=Config.TikkiesOrigin,credential=tikkiesSecret,roster=tikkiesOwners,giftSource="tikkies",
     onStatus=function(status,errorCode)
      script:SetAttribute("TikkiesConnectionStatus",status)
      script:SetAttribute("TikkiesConnectionError",errorCode or "")
      if status=="live" then script:SetAttribute("TikkiesRegisteredAt",workspace:GetServerTimeNow()) end
      for p,s in receiver.states do if s.provider=="tikkies" then s.status=status receiver:publish(p,s,errorCode) end end
     end,
     onConnectionTest=function(context)
      local p=Players:GetPlayerByUserId(tonumber(context.ownerRobloxId) or 0)
      local s=p and receiver.states[p] if s and s.provider=="tikkies" then s.status="live" receiver:publish(p,s) end
     end,
     onViewerJoin=function(e) return tikkiesHandler(e,true) end,
     onViewerEvent=function(e) return tikkiesHandler(e,false) end,
    })
   end)
   if ok then legacy=result else
    for p,s in receiver.states do if s.provider=="tikkies" then s.status="error" receiver:publish(p,s,"tikkies_unavailable") end end
   end
  elseif not wanted and legacy then local old=legacy legacy=nil old.stop() end
  task.wait(3)
 end
end)
receiver:start()

-- Optional broadcast overlays use the existing server-only authenticated transport.
local overlayPublisher=require(script.Parent.OverlayPublisher).start(Config,receiver)
game:BindToClose(function() overlayPublisher.stop() end)
