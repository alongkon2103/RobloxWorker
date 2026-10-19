-- Manual Play-mode integration fixture; uses isolated clones and cleans its own arena.
return function()
 assert(game:GetService('RunService'):IsStudio() and game:GetService('RunService'):IsRunning(), 'Run this fixture in Studio Play mode')
local S=game.ServerScriptService local p=game.Players:GetPlayers()[1]assert(p,"No test player")
local rigRace=S.ViewerRace:Clone()rigRace.Name="__BaconRaceActual"rigRace.Source=rigRace.Source:gsub('local WhitelistAccess=require%(game.ServerScriptService.AccessControl%)','local WhitelistAccess={allowed=function()return true end}')rigRace.Parent=S
local proxy=Instance.new("ModuleScript")proxy.Name="__BaconRaceProxy"proxy.Source="local R=require(script.Parent.__BaconRaceActual)local P={}function P.new(...)local r=R.new(...)P.latest=r return r end return P"proxy.Parent=S
local clone=S.GameHandlers:Clone()clone.Name="__BaconHandlersSpec"clone.Source=clone.Source:gsub('local WhitelistAccess=require%(game.ServerScriptService.AccessControl%)','local WhitelistAccess={allowed=function()return true end}'):gsub('require%(script.Parent.ViewerRace%)','require(script.Parent.__BaconRaceProxy)'):gsub('folder.Name = "TikkiesDemoNPCs"','folder.Name = "__BaconSpecNPCs"'):gsub('roundReset.Name="ViewerRoundReset"','roundReset.Name="__BaconSpecReset"')clone.Parent=S
local H=require(clone)local result local ok,err=pcall(function()
 local c={ownerRobloxId=tostring(p.UserId),robloxId="0",robloxUsername="",avatarType="bacon",namespace="live",liveSessionId="fixture",runId="bacon-fixture",generation=1,actorKey="tiktok:bacon_fixture",tiktokUsername="fixture_viewer",tiktokDisplayName="ชื่อทดสอบ"}
 local joined,reason=H.join(c)assert(joined,reason)
 local folder=workspace.__BaconSpecNPCs local model=folder:GetChildren()[1]assert(model and model:GetAttribute("RobloxId")=="0")
 local head=model.Head:FindFirstChild("ViewerNameplate")assert(head)assert(not head:FindFirstChild("RobloxUsername",true).Visible)
 local race=require(proxy).latest assert(race:start())race:beginRunning()
 local event=table.clone(c)event.eventId="boost-before-avatar"event.eventType="like"event.effects={{key="speed_boost",value=1,count=5},{key="fly",value=1,count=1}}assert(H.event(event))
 task.wait(.25)local before=model:GetAttribute("RouteDistance")local untilAt=model:GetAttribute("SpeedBoostUntil")local flyAt=model:GetAttribute("FlyUntil")local stacks=model:GetAttribute("SpeedBoostStacks")local slot=model:GetAttribute("RaceSlot")
 local upgrade=table.clone(c)upgrade.avatarType="roblox"upgrade.avatarUpdate=true upgrade.robloxId=tostring(p.UserId)upgrade.robloxUsername=p.Name
 local changed,why=H.join(upgrade)assert(changed,why)
 assert(folder:GetChildren()[1]==model and #folder:GetChildren()==1,"Avatar change duplicated/replaced model")
 assert(model:GetAttribute("RouteDistance")>=before and model:GetAttribute("RaceSlot")==slot,"Race progress/slot reset")
 assert(model:GetAttribute("SpeedBoostUntil")==untilAt and model:GetAttribute("FlyUntil")==flyAt and model:GetAttribute("SpeedBoostStacks")==stacks,"Active effects reset")
 assert(model:GetAttribute("AvatarType")=="roblox"and model:GetAttribute("RobloxId")==tostring(p.UserId))
 assert(model.Head:FindFirstChild("ViewerNameplate"):FindFirstChild("RobloxUsername",true).Visible)
 task.wait(.15)assert(model:GetAttribute("RouteDistance")>before,"Racer stopped after avatar change")
 result="PASS native game: Bacon joins, Roblox line hidden, real avatar upgrades same model, running progress/slot and SpeedBoost/Fly timers retained, new rig keeps moving (access mocked only in isolated fixture clones)"
end)
H.clear(p)local folder=workspace:FindFirstChild("__BaconSpecNPCs")if folder then folder:Destroy()end local reset=S:FindFirstChild("__BaconSpecReset")if reset then reset:Destroy()end clone:Destroy()proxy:Destroy()rigRace:Destroy()assert(ok,err)return result
end
