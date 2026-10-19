-- Manual integration test in Studio Play; cloned handlers/race use an isolated arena.
return function(source)
 assert(game:GetService("RunService"):IsStudio()and game:GetService("RunService"):IsRunning(),"Run in Studio Play")
 local S=game.ServerScriptService local owner=assert(game.Players:GetPlayers()[1],"No test player")
 local race=S.ViewerRace:Clone()race.Name="__ViewedEventsRace"
 race.Source=race.Source:gsub('local WhitelistAccess=require%(game.ServerScriptService.AccessControl%)','local WhitelistAccess={allowed=function()return true end}')race.Parent=S
 local proxy=Instance.new("ModuleScript")proxy.Name="__ViewedEventsRaceProxy"
 proxy.Source='local R=require(script.Parent.__ViewedEventsRace)local P={}function P.new(...)local r=R.new(...)P.latest=r return r end return P'proxy.Parent=S
 local clone=S.GameHandlers:Clone()clone.Name="__ViewedEventsHandlers"
 clone.Source=(source or clone.Source):gsub('local WhitelistAccess=require%(game.ServerScriptService.AccessControl%)','local WhitelistAccess={allowed=function()return true end}')
  :gsub('require%(script.Parent.ViewerRace%)','require(script.Parent.__ViewedEventsRaceProxy)')
  :gsub('folder.Name = "TikkiesDemoNPCs"','folder.Name = "__ViewedEventsNPCs"')
  :gsub('roundReset.Name="ViewerRoundReset"','roundReset.Name="__ViewedEventsReset"')clone.Parent=S
 local settings=S.DevTestConfig:Clone()settings.Name="__ViewedEventsConfig"settings.Parent=S
 clone.Source=clone.Source:gsub('require%(devConfigModule%)','require(script.Parent.__ViewedEventsConfig)')
 local config=require(settings)
 local H=require(clone)
 local ok,err=pcall(function()
  local context={ownerRobloxId=tostring(owner.UserId),robloxId="0",robloxUsername="",avatarType="bacon",namespace="live",runId="viewed-events-fixture",generation=1,actorKey="tiktok:fixture",tiktokUsername="fixture",tiktokDisplayName="ผู้ชม"}
  assert(H.join(context))local folder=workspace.__ViewedEventsNPCs local model=assert(folder:GetChildren()[1])
  local r=require(proxy).latest assert(r:start())r:beginRunning()
  local accepted,why=H.devEvent(owner,context.actorKey,"speed_boost")assert(accepted,"LIVE Bacon rejected: "..tostring(why))
  assert((model:GetAttribute("SpeedBoostStacks")or 0)==1,"Viewed racer did not receive boost")
  assert(H.devEvent(owner,context.actorKey,"fly"))assert((model:GetAttribute("FlyUntil")or 0)>workspace:GetServerTimeNow(),"Viewed racer did not receive Fly")
  local before=model:GetAttribute("SpeedBoostStacks")
  local enabled=config.Enabled config.Enabled=false
  local denied,code=H.devEvent(owner,context.actorKey,"speed_boost")config.Enabled=enabled
  assert(not denied and code=="dev_not_allowed","Disabled testing still granted an event")
  assert(not H.devEvent(owner,"tiktok:another-owner","speed_boost"),"Unknown/foreign actor accepted")
  assert(not H.devEvent(owner,context.actorKey,"invalid_effect"),"Invalid effect accepted")
  assert(model:GetAttribute("SpeedBoostStacks")==before,"Rejected target changed current racer")
  local generation=model:GetAttribute("Generation")model:SetAttribute("Generation","stale")
  assert(not H.devEvent(owner,context.actorKey,"speed_boost"),"Stale scope accepted")model:SetAttribute("Generation",generation)
  model:FindFirstChildOfClass("Humanoid").Health=0
  assert(not H.devEvent(owner,context.actorKey,"speed_boost"),"Dead racer accepted")
  H.clear(owner)
  local real=table.clone(context)real.robloxId=tostring(owner.UserId)real.robloxUsername=owner.Name real.avatarType="roblox"real.runId="viewed-real-fixture"
  assert(H.join(real))r=require(proxy).latest assert(r:start())r:beginRunning()
  assert(H.devEvent(owner,real.actorKey,"speed_boost"),"LIVE Roblox racer rejected")
  H.clear(owner)
  local joined,reason,actor=H.devJoin(owner,owner.UserId,1)assert(joined,reason)
  assert(H.devEvent(owner,actor,"speed_boost"),"Existing Dev racer no longer works")
  H.clear(owner)assert(not H.devEvent(owner,actor,"fly"),"Removed round accepted")
 end)
 H.clear(owner)
 local folder=workspace:FindFirstChild("__ViewedEventsNPCs")if folder then folder:Destroy()end
 local reset=S:FindFirstChild("__ViewedEventsReset")if reset then reset:Destroy()end
 clone:Destroy()proxy:Destroy()race:Destroy()settings:Destroy()
 assert(ok,err)
 return "PASS: viewed LIVE Bacon/Roblox and Dev racers receive events; invalid, foreign/missing, stale, dead and removed targets rejected"
end
