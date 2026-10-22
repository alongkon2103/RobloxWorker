-- Manual integration test in Studio Play; cloned handlers/race use an isolated arena.
return function(source)
 assert(game:GetService("RunService"):IsStudio()and game:GetService("RunService"):IsRunning(),"Run in Studio Play")
 local S=game.ServerScriptService local owner=assert(game.Players:GetPlayers()[1],"No test player")
 local race=S.ViewerRace:Clone()race.Name="__RoundSpeedRace"
 race.Source=race.Source:gsub('local WhitelistAccess=require%(game.ServerScriptService.AccessControl%)','local WhitelistAccess={allowed=function()return true end}')race.Parent=S
 local proxy=Instance.new("ModuleScript")proxy.Name="__RoundSpeedRaceProxy"
 proxy.Source='local R=require(script.Parent.__RoundSpeedRace)local P={}function P.new(...)local r=R.new(...)P.latest=r return r end return P'proxy.Parent=S
 local clone=S.GameHandlers:Clone()clone.Name="__RoundSpeedHandlers"
 clone.Source=(source or clone.Source):gsub('local WhitelistAccess=require%(game.ServerScriptService.AccessControl%)','local WhitelistAccess={allowed=function()return true end}')
  :gsub('require%(script.Parent.ViewerRace%)','require(script.Parent.__RoundSpeedRaceProxy)')
  :gsub('folder.Name = "TikkiesDemoNPCs"','folder.Name = "__RoundSpeedNPCs"')
  :gsub('roundReset.Name="ViewerRoundReset"','roundReset.Name="__RoundSpeedReset"')clone.Parent=S
 local settings=S.DevTestConfig:Clone()settings.Name="__RoundSpeedConfig"settings.Parent=S
 clone.Source=clone.Source:gsub('require%(devConfigModule%)','require(script.Parent.__RoundSpeedConfig)')
 local config=require(settings)
 local H=require(clone)
 local ok,err=pcall(function()
  local context={ownerRobloxId=tostring(owner.UserId),robloxId="0",robloxUsername="",avatarType="bacon",namespace="live",runId="round-speed-fixture",generation=1,actorKey="tiktok:fixture",tiktokUsername="fixture",tiktokDisplayName="ผู้ชม"}
  assert(H.join(context))local folder=workspace.__RoundSpeedNPCs local model=assert(folder:GetChildren()[1])
  local expected=0
  for index,item in ipairs({{"speed_boost",1,2},{"rainbow_cat",2,2},{"rocket",3,15},{"naruto",1,5},{"goku",1,10},{"asta",1,20}})do
   local event=table.clone(context)event.eventId="permanent-"..index event.effects={{key=item[1],value=1,count=item[2]}}
   assert(H.event(event))expected+=item[3]
   assert(model:GetAttribute("RoundSpeedBonus")==expected,item[1].." permanent quantity was lost")
   assert(H.event(event))assert(model:GetAttribute("RoundSpeedBonus")==expected,"Retry granted the same permanent award twice")
  end
  assert(expected==54)
  local upgrade=table.clone(context)upgrade.avatarType="roblox"upgrade.avatarUpdate=true upgrade.robloxId=tostring(owner.UserId)upgrade.robloxUsername=owner.Name
  assert(H.join(upgrade))assert(folder:GetChildren()[1]==model and model:GetAttribute("RoundSpeedBonus")==54,"Avatar upgrade lost permanent bonus")
  H.clear(owner)assert(H.join(context))local fresh=folder:GetChildren()[1]
  assert((fresh:GetAttribute("RoundSpeedBonus")or 0)==0,"New round retained permanent speed")
  local r=require(proxy).latest assert(r:start())r:beginRunning()
  local heart=table.clone(context)heart.eventId="running-heart"heart.effects={{key="speed_boost",value=1,count=1}}
  assert(H.event(heart))local now=workspace:GetServerTimeNow()
  local expires=fresh:GetAttribute("SpeedBoostUntil")assert(expires>now+4.5 and expires<=now+5.01,"First boost duration is not five seconds")
  local Stack=require(game.ReplicatedStorage.RaceEventStack)
  local _,active=Stack.evaluate(fresh,now,nil,20)local _,expired=Stack.evaluate(fresh,expires,nil,20)
  assert(math.abs(active*20-32)<.0001 and math.abs(expired*20-22)<.0001,"Real event did not produce32 then22")
 end)
 H.clear(owner)
 local folder=workspace:FindFirstChild("__RoundSpeedNPCs")if folder then folder:Destroy()end
 local reset=S:FindFirstChild("__RoundSpeedReset")if reset then reset:Destroy()end
 clone:Destroy()proxy:Destroy()race:Destroy()settings:Destroy()
 assert(ok,err)
 return "PASS: all six permanent gift values and quantities, duplicate receipts, same-model upgrade and round reset"
end
