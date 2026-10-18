-- Studio-only capacity test: production join logic with tiny stand-in avatar and race services.
return function()
 local S=game.ServerScriptService
 local realPlayers=game:GetService("Players")
 local owner=assert(realPlayers:GetPlayers()[1])
 local template=Instance.new("Model")template.Name="CapacityStandIn"
 for _,name in {"HumanoidRootPart","Torso","Head"}do local p=Instance.new("Part")p.Name=name p.Anchored=true p.CanCollide=false p.Transparency=1 p.Parent=template end
 local hum=Instance.new("Humanoid")hum.RequiresNeck=false hum.Parent=template
 template.Parent=game.ServerStorage
 local module=S.GameHandlers:Clone()module.Name="HundredCapacityTest"
 module.Source=module.Source:gsub('local Players = game:GetService%("Players"%)',[[local NativePlayers=game:GetService("Players")
 local Players={PlayerRemoving=NativePlayers.PlayerRemoving,
 GetPlayerByUserId=function(_,id)return NativePlayers:GetPlayerByUserId(id)end,
 CreateHumanoidModelFromUserIdAsync=function()return game.ServerStorage.CapacityStandIn:Clone()end}]])
 module.Source=module.Source:gsub('local Presentation = require%(script.Parent.RacePresentation%)',[[local Presentation={scaleAvatar=function()end,nameplate=function()end,arrive=function()end,event=function()end}]])
 module.Source=module.Source:gsub('local ViewerRace = require%(script.Parent.ViewerRace%)',[[local ViewerRace={new=function()return {phase="Lobby",add=function()end,destroy=function(self)self.destroyed=true end}end}]])
 module.Parent=S
 local handlers=require(module)
 local function context(i)return {ownerRobloxId=tostring(owner.UserId),robloxId="1",runId="capacity-100-test",generation=1,actorKey="test:"..i,tiktokUsername="viewer"..i,tiktokDisplayName="Viewer "..i,robloxUsername="Builderman"}end
 local ok,err=pcall(function()
  local cfg=require(S.RaceConfig)assert(cfg.MaxViewersPerOwner==100 and cfg.MaxViewersPerServer==100)
  local completed,accepted,errors=0,0,{}
  for i=1,101 do task.spawn(function()local success,reason=handlers.join(context(i))if success then accepted+=1 else table.insert(errors,reason)end completed+=1 end)end
  local deadline=os.clock()+20 repeat task.wait(.05)until completed==101 or os.clock()>deadline
  assert(completed==101 and accepted==100,"Expected exactly 100 accepted joins, got "..accepted)
  assert(#errors==1 and errors[1]=="viewer_limit")
  assert(handlers.join(context(1)),"Existing viewer cannot rejoin at capacity")
 end)
 handlers.clear(owner)module:Destroy()template:Destroy()
 assert(ok,err)
 return "PASS: 101 concurrent Roblox joins accepted exactly 100; duplicate rejoin succeeds"
end
