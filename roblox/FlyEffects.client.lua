-- Local flight pose and bounded wind effects; authoritative route remains server-owned.
local Flight=require(game:GetService("ReplicatedStorage"):WaitForChild("ViewerFlightHeight"))
local RunService=game:GetService("RunService")
local storage=game:GetService("ReplicatedStorage")
local Stack=require(storage:WaitForChild("RaceEventStack"))
local Fly=require(storage:WaitForChild("FlyMotion"))
local Rig=require(storage:WaitForChild("ViewerRigPose"))
local config=require(storage:WaitForChild("RaceEventConfig")).fly
local runners=workspace:WaitForChild("TikkiesDemoNPCs")
local visuals=Instance.new("Folder")visuals.Name="ViewerFlyVisuals"visuals.Parent=workspace
local active={}
local function restore(r)
 for _,w in r.writes do
  if w.object.Parent and w.object[w.property]==w.after then w.object[w.property]=w.before end
 end
 table.clear(r.writes)
end
local function write(r,object,property,value,before)
 before=before or object[property]
 object[property]=value
 table.insert(r.writes,{object=object,property=property,before=before,after=object[property]})
end

local function bindRig(model,root,hum,r)
 r.root=root r.hum=hum r.revision=model:GetAttribute("AvatarRevision")
 r.r6=hum.RigType==Enum.HumanoidRigType.R6 r.joints={}
 for _,joint in model:GetDescendants()do
  if joint:IsA("Motor6D")then
   local base=joint:GetAttribute("ViewerBoostBaseC0")or joint:GetAttribute("ViewerActionBaseC0")or joint.C0
   if not joint:GetAttribute("ViewerBoostBaseC0")then joint:SetAttribute("ViewerBoostBaseC0",base)end
   table.insert(r.joints,{joint=joint,base=base,basis=base.Rotation,motor=true,name=joint.Name:gsub(" ","")})
  elseif joint:IsA("AnimationConstraint")and joint.Attachment0 and joint.Attachment1 then
   local base=joint:GetAttribute("ViewerActionBaseC0")or joint.Attachment0.CFrame
   table.insert(r.joints,{joint=joint,basis=base.Rotation,motor=false,name=joint.Name:gsub(" ","")})
  end
 end
end
local function create(model,root,hum,now)
 local r={writes={},started=now,bank=0}
 bindRig(model,root,hum,r)
 local part=Instance.new("Part")part.Name="Fly_"..model.Name part.Size=Vector3.one part.Transparency=1
 part.Anchored=true part.CanCollide=false part.CanTouch=false part.CanQuery=false part.CastShadow=false part.CFrame=root.CFrame part.Parent=visuals r.part=part r.trails={}
 for _,side in {-1,1}do
  local a=Instance.new("Attachment")a.Position=Vector3.new(side*.85,.1,0)a.Parent=part
  local b=Instance.new("Attachment")b.Position=Vector3.new(side*1.05,.1,0)b.Parent=part
  local t=Instance.new("Trail")t.Attachment0=a t.Attachment1=b t.FaceCamera=true t.Lifetime=.3 t.MaxLength=12 t.MinLength=.1
  t.Color=ColorSequence.new(Color3.fromRGB(95,232,255),Color3.new(1,1,1))
  t.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.12),NumberSequenceKeypoint.new(1,1)})t.LightEmission=.7 t.Parent=part table.insert(r.trails,t)
 end
 local a=Instance.new("Attachment")a.Parent=part
 local e=Instance.new("ParticleEmitter")e.Texture="rbxasset://textures/particles/sparkles_main.dds"e.Color=ColorSequence.new(Color3.fromRGB(169,244,255))
 e.Rate=8 e.Lifetime=NumberRange.new(.2,.4)e.Speed=NumberRange.new(1,3)e.SpreadAngle=Vector2.new(30,30)e.EmissionDirection=Enum.NormalId.Back
 e.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.16),NumberSequenceKeypoint.new(1,0)})e.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.1),NumberSequenceKeypoint.new(1,1)})e.LightEmission=.7 e.Parent=a e:Emit(12)r.emitter=e
 return r
end
local function clear(model,r)
 restore(r)r.part:Destroy()active[model]=nil
 Flight.clear(model,"fly")
 if model.Parent then model:SetAttribute("RenderedFlyWeight",nil)end
end
local preAnimation=RunService.PreAnimation:Connect(function()for _,r in active do restore(r)end end)
RunService:BindToRenderStep("ViewerFlyRender",Enum.RenderPriority.Camera.Value+4,function(dt)
 local now=workspace:GetServerTimeNow()local seen={}
 for _,model in runners:GetChildren()do
  local root=model:FindFirstChild("HumanoidRootPart")local hum=model:FindFirstChildOfClass("Humanoid")
  if root and hum and hum.Health>0 and Stack.isPrimary(model,"fly",now)and now>(model:GetAttribute("IntroEndsAt")or 0)+.1 then
   seen[model]=true local r=active[model]
   if not r then r=create(model,root,hum,now)active[model]=r end
   restore(r)
   if r.root~=root or r.hum~=hum or r.revision~=model:GetAttribute("AvatarRevision")then bindRig(model,root,hum,r)end
   local expires=model:GetAttribute("FlyUntil")or now
   local sample=Fly.sample(now,r.started,expires,config,model)
   if r.lastExpires and expires>r.lastExpires+.01 and r.sample and r.sample.weight<1 then r.extension={at=now,from=r.sample}end
   if r.extension then
    local t=math.clamp((now-r.extension.at)/.2,0,1)t=t*t*(3-2*t)
    for _,key in {"weight","height","bob"}do sample[key]=r.extension.from[key]+(sample[key]-r.extension.from[key])*t end
    if t>=1 then r.extension=nil end
   end
   r.lastExpires=expires r.sample=sample
   Flight.publish(model,"fly",sample.height)
   local forward=root.CFrame.LookVector local turn=0
   if r.forward then turn=math.atan2(r.forward:Cross(forward).Y,math.clamp(r.forward:Dot(forward),-1,1))/math.max(dt,.001)end
   r.forward=forward r.bank+=(math.clamp(-turn*.08,-.2,.2)-r.bank)*(1-math.exp(-math.min(dt,.1)*9))
   for _,saved in r.joints do local joint=saved.joint if joint.Parent then
    local offset=Fly.pose(saved.name,sample,r.r6,r.bank)local canonical=saved.basis:Inverse()*offset*saved.basis
    if saved.motor then write(r,joint,"C0",saved.base*canonical,saved.base)write(r,joint,"Transform",joint.Transform:Lerp(CFrame.identity,sample.weight))
    else write(r,joint,"Transform",joint.Transform:Lerp(CFrame.identity,sample.weight)*canonical)end
   end end
   Rig.apply(model)
   r.part.CFrame=root.CFrame*CFrame.new(0,sample.height+sample.bob,0)
   local moving=model:GetAttribute("RaceState")=="Running"
   r.emitter.Rate=moving and 8*sample.weight or 0
   for _,trail in r.trails do trail.Enabled=moving and sample.weight>.1 end
   model:SetAttribute("RenderedFlyWeight",sample.weight)
  end
 end
 for model,r in active do if not seen[model]then clear(model,r)end end
end)
script.Destroying:Connect(function()
 preAnimation:Disconnect()RunService:UnbindFromRenderStep("ViewerFlyRender")
 for model,r in active do clear(model,r)end visuals:Destroy()
end)
