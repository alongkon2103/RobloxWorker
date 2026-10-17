-- Isolated Play-only fixture. All HTTP calls are mocked; no real credentials.
local RS=game:GetService("ReplicatedStorage")
local server=game:GetService("ServerScriptService")
-- Prepare cloned modules/config with plugin privileges before starting this fixture.
local fixture=server:WaitForChild("ScopedOverlayFixture")
local publisher=fixture:WaitForChild("OverlayPublisher")
local original=RS:FindFirstChild("OverlayControl")
local key=string.rep("test-only-",4)
local transport={jobId="scoped-publisher-test"}
transport.request=function(path,method,body,credential)
 if path=="/v1/overlays/claim"then
  assert(credential==key,"Must use map credential")
  assert(body.universeId==tostring(game.GameId),"Missing actual universe")
  script:SetAttribute("ClaimUniverse",body.universeId)
  return {schemaVersion=2,universeId=body.universeId,readToken=string.rep("r",43),writeToken=string.rep("w",43)},200
 elseif path=="/v1/overlays/batch"then
  assert(credential==key,"Batch must use map credential")
  assert(#body.items>0)
  script:SetAttribute("Batches",(script:GetAttribute("Batches")or 0)+1)
  local results={}for _ in body.items do table.insert(results,{ok=true})end
  return {results=results},200
 end
 return {ok=true},200
end
local service=require(publisher).start({OverlayMapApiKey=key},transport)
for _,remote in RS:GetChildren()do if remote.Name=="OverlayControl"and remote~=original then remote.Name="ScopedOverlayTestControl"end end
script.Destroying:Connect(function()service.stop()fixture:Destroy()end)
script:SetAttribute("Ready",true)
