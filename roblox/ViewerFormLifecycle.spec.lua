-- The production module runs with an isolated render service and real unparented rigs.
return function(run)
 local environment=setmetatable({game={GetService=function(_,name)
  assert(name=="RunService")return {BindToRenderStep=function()end}
 end}},{__index=getfenv()})
 setfenv(run,environment)local Forms=run()
 local bin=Instance.new("Folder")
 local model=Instance.new("Model")model.Parent=bin
 local original=Instance.new("Part")original.Name="Head"original.Parent=model
 local tag=Instance.new("BillboardGui")tag.Name="ViewerNameplate"tag.Adornee=original tag.Parent=original
 local form=Instance.new("Model")form.Parent=bin
 local formHead=Instance.new("Part")formHead.Name="Head"formHead.Parent=form
 local record={form=form,started=123}
 model:SetAttribute("NarutoUntil",9999)
 local ok,message=pcall(function()
  Forms.acquire(model,record,"NarutoVisualActive")
  assert(tag.Adornee==formHead,"Initial label did not follow the active form")
  original:Destroy()
  local replacement=Instance.new("Part")replacement.Name="Head"
  replacement.Transparency=.25 replacement.LocalTransparencyModifier=.5 replacement.Parent=model
  model:SetAttribute("AvatarRevision",1)
  -- The publisher creates this label after the revision increment.
  local fresh=Instance.new("BillboardGui")fresh.Name="ViewerNameplate"fresh.Adornee=replacement fresh.Parent=replacement
  task.wait()
  assert(replacement.Transparency==1 and replacement.LocalTransparencyModifier==1,"Replacement avatar was not hidden")
  assert(fresh.Adornee==formHead,"Replacement label did not follow the active form")
  assert(record.form==form and form.Parent==bin and record.started==123 and model:GetAttribute("NarutoUntil")==9999,"Refreshing the label restarted the form")
  Forms.release(model,record)
  assert(fresh.Adornee==replacement and fresh.Adornee.Parent==model,"Form release restored the destroyed old head")
  assert(replacement.Transparency==.25 and replacement.LocalTransparencyModifier==.5,"Form release lost replacement visibility")
 end)
 if not record.released then Forms.release(model,record)end
 bin:Destroy()
 assert(ok,message)
 return "PASS: active form adopts the replacement nameplate and restores its new head without restarting the form"
end
