local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Http = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local Config = require(script.Parent.RaceConfig)
local Presentation = {}
local DisplayName=require(script.Parent.ViewerDisplayName)
local nameInputs=setmetatable({}, {__mode="k"})
local palettes = {
 {"SUNSHINE", "F4C477", "AE8B35", "83F3E3"},
 {"BUBBLEGUM", "FFA3CD", "B34BD2", "FFE18C"},
 {"LAGOON", "7CDDEC", "347DBC", "A2FFE0"},
 {"MATCHA", "B9E68C", "548D65", "FDE6A2"},
 {"PEACH", "FFC8A1", "E37792", "ADDBFF"},
 {"LAVENDER", "C7B4FA", "7863BE", "9EF0E5"},
 {"BERRY", "F68E9B", "A34878", "CFF79B"},
 {"MIDNIGHT", "6C86C7", "393461", "FFB7E2"},
}
local function look(model, avatarName)
 local key = tostring(model:GetAttribute("OwnerRobloxId") or "") .. ":" ..
  tostring(model:GetAttribute("ActorKey") or model:GetAttribute("RobloxId") or avatarName)
 local seed = 5381
 for i = 1, #key do seed = (seed * 33 + key:byte(i)) % 2147483647 end
 local palette = palettes[seed % #palettes + 1]
 local style = math.floor(seed / #palettes) % 3 + 1
 model:SetAttribute("NameplatePalette", palette[1])
 model:SetAttribute("NameplateStyle", style)
 return palette, style
end
local remote = ReplicatedStorage:FindFirstChild("ViewerArrival") or Instance.new("RemoteEvent")
remote.Name = "ViewerArrival"
remote.Parent = ReplicatedStorage

local function corner(parent, radius)
 local item = Instance.new("UICorner")
 item.CornerRadius = UDim.new(0, radius)
 item.Parent = parent
end
local function text(parent, name, value, size, position, color)
 local item = Instance.new("TextLabel")
 item.Name = name
 item.BackgroundTransparency = 1
 item.Position = position
 item.Size = UDim2.new(1, -68, 0, 23)
 item.Text = value
 item.TextColor3 = color
 item.Font = Enum.Font.FredokaOne
 item.TextSize = size
 item.TextTruncate = Enum.TextTruncate.AtEnd
 item.TextXAlignment = Enum.TextXAlignment.Center
 item.Parent = parent
 return item
end
function Presentation.nameplate(model, viewerName, avatarName)
 local head = model:FindFirstChild("Head")
 local hum = model:FindFirstChildOfClass("Humanoid")
 if not head or not hum then return end
 local previous=nameInputs[model]
 if head:FindFirstChild("ViewerNameplate")and previous and previous.viewer==viewerName and previous.avatar==avatarName then return end
 nameInputs[model]={viewer=viewerName,avatar=avatarName}
 local palette, style = look(model, avatarName)
 hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
 local old = head:FindFirstChild("ViewerNameplate")
 if old then old:Destroy() end
 local tag = Instance.new("BillboardGui")
 tag.Name = "ViewerNameplate"
 tag.Adornee = head
 tag.Size = UDim2.new(5.4, 0, 5.4*154/260, 0)
 tag.StudsOffsetWorldSpace = Vector3.new(0, 3.63, 0)
 tag.MaxDistance = Config.NameplateMaxDistance
 tag.AlwaysOnTop = false
 tag.LightInfluence = 0
 local canvas = Instance.new("Frame")
 canvas.Name = "Canvas"
 canvas.Size = UDim2.fromScale(1,1)
 canvas.BackgroundTransparency = 1
 canvas.Parent = tag
 local design = Instance.new("Frame")
 design.Name = "Design"
 design.Size = UDim2.fromOffset(260,154)
 design.BackgroundTransparency = 1
 design.Parent = canvas
 local designScale = Instance.new("UIScale")
 designScale.Name = "DesignScale"
 designScale.Parent = design
 local card = Instance.new("Frame")
 card.Name = "NameCapsule"
 card.Position = UDim2.fromOffset(3, 36)
 card.Size = UDim2.new(1, -6, 0, 50)
 card.BackgroundColor3 = Color3.new(1, 1, 1)
 card.BorderSizePixel = 0
 card.Parent = design
 corner(card, 25)
 local gradient = Instance.new("UIGradient")
 gradient.Rotation = 90
 gradient.Color = ColorSequence.new(Color3.fromHex(palette[2]), Color3.fromHex(palette[3]))
 gradient.Rotation = style == 3 and 30 or 90
 gradient.Parent = card
 local accent = Color3.fromHex(palette[4])
 local decorations = Instance.new("Frame")
 decorations.Name = "Decorations"
 decorations.BackgroundTransparency = 1
 decorations.Position = UDim2.fromOffset(48, 8)
 decorations.Size = UDim2.new(1, -80, 1, -16)
 decorations.ClipsDescendants = true
 decorations.Parent = card
 corner(decorations, 17)
 if style == 1 then
  for i = 1, 3 do
   local dot = Instance.new("Frame")
   dot.Name = "Confetti"
   dot.Size = UDim2.fromOffset(5, 5)
   dot.Position = UDim2.new(1, -9 - i * 7, 0, i % 2 == 0 and 5 or 25)
   dot.BackgroundColor3 = accent
   dot.BackgroundTransparency = .15
   dot.BorderSizePixel = 0
   dot.Parent = decorations
   corner(dot, 3)
  end
 elseif style == 2 then
  local sparkle = text(decorations, "Sparkle", "✦", 15, UDim2.new(1, -21, 0, 4), accent)
  sparkle.Size = UDim2.fromOffset(18, 24)
 else
  for i = 1, 3 do
   local stripe = Instance.new("Frame")
   stripe.Name = "Ribbon"
   stripe.Position = UDim2.new(1, -5 - i * 11, 0, 7)
   stripe.Size = UDim2.fromOffset(4, 20)
   stripe.Rotation = 25
   stripe.BackgroundColor3 = accent
   stripe.BackgroundTransparency = .65
   stripe.BorderSizePixel = 0
   stripe.Parent = decorations
  end
 end
 local badge = Instance.new("TextLabel")
 badge.Name = "Rank"
 badge.Position = UDim2.fromOffset(2, 2)
 badge.Size = UDim2.fromOffset(42, 46)
 badge.BackgroundColor3 = Color3.fromRGB(19, 16, 26)
 badge.Font = Enum.Font.GothamBold
 badge.TextSize = 18
 badge.TextColor3 = Color3.fromRGB(255, 248, 235)
 badge.BorderSizePixel = 0
 badge.Parent = card
 corner(badge, 21)
 local function updateRank()
  local rank = model:GetAttribute("RaceRank")
  badge.Text = type(rank) == "number" and rank > 0 and rank % 1 == 0 and "#" .. tostring(rank) or "#–"
 end
 updateRank()
 local connection = model:GetAttributeChangedSignal("RaceRank"):Connect(updateRank)
 tag.Destroying:Connect(function() connection:Disconnect() end)
 local name = text(card, "Viewer", "Viewer", 18, UDim2.fromOffset(50, 3), Color3.new(1, 1, 1))
 name.Size = UDim2.new(1, -75, 0, 25)
 name.Font = Enum.Font.GothamBold
 name.RichText=false
 name.TextColor3=palette[1]=="MIDNIGHT" and Color3.new(1,1,1) or Color3.fromRGB(43,35,62)
 local avatar=text(card,"RobloxUsername","Roblox: "..tostring(avatarName or ""),11,UDim2.fromOffset(50,28),name.TextColor3)
 avatar.Size=UDim2.new(1,-75,0,15)avatar.Font=Enum.Font.GothamMedium avatar.RichText=false
 local speed = Instance.new("TextLabel")
 speed.Name="RunnerSpeed"
 speed.AnchorPoint=Vector2.new(.5,0)
 speed.Position=UDim2.new(.5,0,0,2)
 speed.Size=UDim2.fromOffset(126,27)
 speed.BackgroundColor3=Color3.fromRGB(25,30,49)
 speed.BorderSizePixel=0
 speed.Font=Enum.Font.GothamBold
 speed.TextSize=16
 speed.TextColor3=accent
 speed.Text="0.0 km/h"
 speed.Parent=design
 corner(speed,14)
 local outline=Instance.new("UIStroke")
 outline.Color=accent outline.Thickness=1.5 outline.Transparency=.2 outline.Parent=speed
 local portrait = Instance.new("ImageLabel")
 portrait.Name = "Portrait"
 portrait.AnchorPoint = Vector2.new(.5, 0)
 portrait.Position = UDim2.new(.5, 0, 0, 94)
 portrait.Size = UDim2.fromOffset(54, 54)
 portrait.BackgroundColor3 = Color3.fromRGB(36, 40, 55)
 portrait.BorderSizePixel = 0
 portrait.ScaleType = Enum.ScaleType.Crop
 local robloxId = tonumber(model:GetAttribute("RobloxId"))
 portrait.Image = robloxId and "rbxthumb://type=AvatarHeadShot&id=" .. robloxId .. "&w=150&h=150" or ""
 portrait.Parent = design
 local round = Instance.new("UICorner")
 round.CornerRadius = UDim.new(1, 0)
 round.Parent = portrait
 tag.Parent = head
 task.defer(function()
  if not tag.Parent or not model.Parent then return end
  local filtered,success=DisplayName.filter(viewerName,tonumber(model:GetAttribute("OwnerRobloxId")))
  if tag.Parent and model.Parent then
   if not success then nameInputs[model]=nil end
   name.Text=filtered
   model:SetAttribute("ViewerDisplayName",filtered)
  end
 end)
end
function Presentation.bodyBounds(model)
 local root = model:FindFirstChild("HumanoidRootPart")
 local origin = root and root.CFrame or model:GetPivot()
 local low, high = Vector3.new(math.huge,math.huge,math.huge), Vector3.new(-math.huge,-math.huge,-math.huge)
 for _,part in model:GetChildren() do
  if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
   local relative = origin:ToObjectSpace(part.CFrame)
   for _,x in {-1,1} do for _,y in {-1,1} do for _,z in {-1,1} do
    local point = relative:PointToWorldSpace(part.Size * Vector3.new(x,y,z) * .5)
    low = low:Min(point) high = high:Max(point)
   end end end
  end
 end
 return low, high
end
function Presentation.scaleAvatar(model)
 local humanoid=model:FindFirstChildOfClass("Humanoid")
 local head=model:FindFirstChild("Head")
 if not humanoid or not head or model:GetAttribute("AvatarNormalized") then return end
 model.PrimaryPart=model:FindFirstChild("HumanoidRootPart")
 -- The avatar loader already supplies the user's authored proportions, head,
 -- FaceControls and accessory attachments. Preserve them without manual resizing
 -- or a forced common height (including modern RigidConstraint accessories).
 local low,high=Presentation.bodyBounds(model)
 local height=high.Y-low.Y
 assert(height>0 and height<100,"Invalid avatar body dimensions")
 model:SetAttribute("AvatarNormalized",true)
 model:SetAttribute("CuteClassicAvatar",false)
 model:SetAttribute("AvatarOriginalAppearance",true)
 model:SetAttribute("AvatarTargetHeight",height)
end
local eventCamera = ReplicatedStorage:FindFirstChild("ViewerEventCamera") or Instance.new("RemoteEvent")
eventCamera.Name="ViewerEventCamera" eventCamera.Parent=ReplicatedStorage
function Presentation.event(model,owner)
 model:SetAttribute("LastViewerEventAt",workspace:GetServerTimeNow())
 eventCamera:FireClient(owner,model:GetAttribute("ActorKey"),Config.EventCameraDuration,Config.EventCameraFieldOfView)
end
function Presentation.arrive(model, owner)
 if not Config.ArrivalEnabled then return end
 local id = Http:GenerateGUID(false)
 model:SetAttribute("ArrivalId", id)
 model:SetAttribute("ArrivalDuration", Config.ArrivalDuration)
 model:SetAttribute("ArrivalStartedAt", workspace:GetServerTimeNow())
 model:SetAttribute("ArrivalPoseAt", workspace:GetServerTimeNow() + .55)
 model:SetAttribute("IntroEndsAt", workspace:GetServerTimeNow() + Config.ArrivalDuration)
 remote:FireClient(owner, id, Config.ArrivalDuration, Config.ArrivalFieldOfView)
end
return Presentation

