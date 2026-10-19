return function(Avatar)
 local model=assert(Avatar.bacon())model.Parent=workspace
 model.PrimaryPart.CFrame=CFrame.new(13,17,29)
 model:SetAttribute("ActorKey","tiktok:fixture")model:SetAttribute("RouteDistance",1234)
 model:SetAttribute("RaceRank",4)model:SetAttribute("FlyUntil",7777)
 local original=model local prepared=assert(Avatar.bacon())
 prepared:FindFirstChildOfClass("BodyColors").HeadColor3=Color3.fromRGB(255,0,0)
 local hum,root=Avatar.replace(model,prepared)
 assert(model==original and model:GetAttribute("ActorKey")=="tiktok:fixture")
 assert(model:GetAttribute("RouteDistance")==1234 and model:GetAttribute("RaceRank")==4)
 assert(model:GetAttribute("FlyUntil")==7777 and (root.Position-Vector3.new(13,17,29)).Magnitude<.001)
 assert(hum.Parent==model and model.Head.Color==Color3.fromRGB(255,0,0))
 local invalid=Instance.new("Model")local before=root
 assert(not pcall(Avatar.replace,model,invalid))assert(model.PrimaryPart==before and hum.Parent==model)
 invalid:Destroy()model:Destroy()
 return "PASS: cached Bacon, stable actor/model, race progress/rank/boost and position retained, invalid replacement leaves rig intact"
end
