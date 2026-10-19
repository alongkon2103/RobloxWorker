-- Appearance only. TikTok actor identity and race state stay on the existing model.
local Players=game:GetService("Players")
local Storage=game:GetService("ServerStorage")
local Avatar={}
local building=false
local function prepare(model)
 assert(model:IsA("Model")and model:FindFirstChildOfClass("Humanoid")and model:FindFirstChild("HumanoidRootPart"),"Invalid avatar rig")
 for _,item in model:GetDescendants()do if item:IsA("BaseScript")then item:Destroy()end end
 model.PrimaryPart=model.HumanoidRootPart
 model.PrimaryPart.Anchored=true
 return model
end
function Avatar.bacon()
 local template=Storage:FindFirstChild("DirectBaconTemplate")
 if not template then
  if building then return nil end
  building=true
  local description=Instance.new("HumanoidDescription")
  description.HairAccessory="63690008" -- Roblox Pal Hair.
  description.HeadColor=Color3.fromRGB(234,184,146)
  description.LeftArmColor=description.HeadColor description.RightArmColor=description.HeadColor
  description.TorsoColor=Color3.fromRGB(35,71,139)
  description.LeftLegColor=Color3.fromRGB(45,48,58)description.RightLegColor=description.LeftLegColor
  local ok,result=pcall(Players.CreateHumanoidModelFromDescriptionAsync,Players,description,Enum.HumanoidRigType.R15)
  description:Destroy()building=false
  if not ok then return nil end
  template=prepare(result)template.Name="DirectBaconTemplate"template.Parent=Storage
 end
 return prepare(template:Clone())
end
function Avatar.roblox(userId)
 return prepare(Players:CreateHumanoidModelFromUserIdAsync(userId))
end
function Avatar.replace(model,prepared)
 -- Validate the entire new rig before touching the running avatar; no yields in this swap.
 local replacement=assert(prepared:FindFirstChildOfClass("Humanoid"),"Missing humanoid")
 local root=assert(prepared:FindFirstChild("HumanoidRootPart"),"Missing root")
 local oldRoot=assert(model:FindFirstChild("HumanoidRootPart"),"Missing current root")
 local current=assert(model:FindFirstChildOfClass("Humanoid"),"Missing current humanoid")
 local frame,anchored,health=oldRoot.CFrame,oldRoot.Anchored,current.Health
 for _,item in model:GetChildren()do item:Destroy()end
 for _,item in prepared:GetChildren()do item.Parent=model end
 model.PrimaryPart=root root.Anchored=anchored
 model:PivotTo(frame*root.PivotOffset)
 replacement.Health=math.min(replacement.MaxHealth,health)
 prepared:Destroy()
 return replacement,root
end
return Avatar
