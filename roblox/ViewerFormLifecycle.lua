-- Shared ownership of avatar visibility while cosmetic forms change.
-- Old and new form callbacks can run in either order within a frame.
local Forms = {}
local states = {}
local RunService=game:GetService("RunService")
local function hideItem(state,item)
 if item:IsA("BasePart") then
  if state.parts[item]==nil then
   state.parts[item]={modifier=item.LocalTransparencyModifier,transparency=item.Transparency}
  end
  -- The standard CameraSubject controller can reset LocalTransparencyModifier.
  -- A local Transparency override keeps the underlying racer invisible as well.
  item.Transparency=1 item.LocalTransparencyModifier=1
 elseif item:IsA("Decal") or item:IsA("Texture") then
  if state.decals[item]==nil then state.decals[item]=item.Transparency end
  item.Transparency=1
 end
end
RunService:BindToRenderStep("ViewerFormVisibility",Enum.RenderPriority.Camera.Value+9,function()
 for model,state in states do
  if model.Parent then
   for part in state.parts do
    if part.Parent then part.Transparency=1 part.LocalTransparencyModifier=1 end
   end
   for decal in state.decals do if decal.Parent then decal.Transparency=1 end end
  end
 end
end)

function Forms.acquire(model, record, attribute)
 local state = states[model]
 if not state then
  local head = model:FindFirstChild("Head")
  local tag = head and head:FindFirstChild("ViewerNameplate")
  state = {parts = {}, decals = {}, records = {}, tag = tag,
   originalAdornee = tag and tag.Adornee}
  states[model] = state
  state.added=model.DescendantAdded:Connect(function(item)
   hideItem(state,item)
   if item:IsA("BillboardGui")and item.Name=="ViewerNameplate"then
    state.tag=item state.originalAdornee=model:FindFirstChild("Head")or item.Adornee
    local current=state.current
    local head=current and current.form:FindFirstChild("Head")
    if head then item.Adornee=head end
   end
  end)
 end
 for _, item in model:GetDescendants() do hideItem(state,item) end
 record.visualAttribute = attribute
 state.records[record] = true
 state.current = record
 local head = record.form:FindFirstChild("Head")
 if state.tag and state.tag.Parent and head then state.tag.Adornee = head end
 model:SetAttribute(attribute, true)
end

function Forms.release(model, record)
 if record.released then return end
 record.released = true
 local state = states[model]
 if state then
  state.records[record] = nil
  if state.current == record then state.current = next(state.records) end
  if state.current then
   local head = state.current.form:FindFirstChild("Head")
   if state.tag and state.tag.Parent then state.tag.Adornee = head or state.originalAdornee end
  else
   states[model] = nil
   if state.added then state.added:Disconnect() state.added=nil end
   for part, value in state.parts do
    if part.Parent then
     part.Transparency=value.transparency part.LocalTransparencyModifier=value.modifier
    end
   end
   for decal, value in state.decals do
    if decal.Parent then decal.Transparency = value end
   end
   if state.tag and state.tag.Parent then state.tag.Adornee = state.originalAdornee end
  end
 end
 if record.visualAttribute then
  local stillActive = false
  if state then
   for other in state.records do
    if other.visualAttribute == record.visualAttribute then stillActive = true break end
   end
  end
  if not stillActive then model:SetAttribute(record.visualAttribute, nil) end
 end
 -- Remove the cosmetic rig even if optional animation cleanup fails.
 record.form:Destroy()
 local moon = record.moon
 record.moon = nil
 if moon then
  local ok, err = pcall(function() moon:destroy() end)
  if not ok then warn("[ViewerForms] Animation cleanup failed: " .. tostring(err)) end
 end
end

function Forms.getVisibleHead(model)
 local state=states[model]
 local record=state and state.current
 local form=record and record.form
 return form and form.Parent and form:FindFirstChild("Head") or model:FindFirstChild("Head")
end
return Forms
