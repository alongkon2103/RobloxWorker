-- Run in Edit after CourseSetup.build(); this does not replace the road or city.
return function(start,floor)
 local map=workspace.World.Map
 local old=map:FindFirstChild("LiveStart") if old then old:Destroy() end
 local model=Instance.new("Model") model.Name="LiveStart"
 model.ModelStreamingMode=Enum.ModelStreamingMode.Persistent
 local navy=Color3.fromRGB(30,37,68)
 local mint=Color3.fromRGB(129,246,214)
 local pink=Color3.fromRGB(255,147,193)
 local gold=Color3.fromRGB(255,220,122)
 local white=Color3.fromRGB(245,248,255)
 local function part(name,size,position,color,material)
  local p=Instance.new("Part") p.Name=name p.Size=size p.Position=position p.Color=color
  p.Material=material or Enum.Material.SmoothPlastic p.Anchored=true p.CanCollide=false p.CanTouch=false p.CanQuery=false
  p.TopSurface=Enum.SurfaceType.Smooth p.BottomSurface=Enum.SurfaceType.Smooth p.Parent=model return p
 end
 local function panel(p,face,title,subtitle)
  local gui=Instance.new("SurfaceGui") gui.Face=face gui.CanvasSize=Vector2.new(1400,400)
  gui.LightInfluence=0 gui.Parent=p
  local bg=Instance.new("Frame") bg.Size=UDim2.fromScale(1,1) bg.BackgroundColor3=navy bg.BorderSizePixel=0 bg.Parent=gui
  local corner=Instance.new("UICorner") corner.CornerRadius=UDim.new(0,45) corner.Parent=bg
  local line=Instance.new("UIStroke") line.Color=mint line.Thickness=9 line.Parent=bg
  local t=Instance.new("TextLabel") t.BackgroundTransparency=1 t.Size=UDim2.fromScale(1,.65)
  t.Position=UDim2.fromScale(0,.05) t.Font=Enum.Font.GothamBlack t.Text=title t.TextColor3=white t.TextSize=170 t.Parent=bg
  local sub=t:Clone() sub.Position=UDim2.fromScale(0,.7) sub.Size=UDim2.fromScale(1,.22)
  sub.Font=Enum.Font.GothamBold sub.TextSize=37 sub.TextColor3=mint sub.Text=subtitle sub.Parent=bg
 end
 -- Keep the existing truss, cover the old checker sign with a clear two-sided title.
 local board=part("StartHeader",Vector3.new(45,13.6,9.1),Vector3.new(start.X,floor+31,start.Z-.3),navy)
 panel(board,Enum.NormalId.Front,"HYPER RUN","LIVE RACE   /   YOUR CHAT. YOUR RUNNERS.")
 panel(board,Enum.NormalId.Back,"START","READY  •  SET  •  RUN!")
 for _,side in {-1,1} do
  local x=start.X+side*22.5
  part("MintEdge",Vector3.new(.45,13.8,9.3),Vector3.new(x,floor+31,start.Z-.3),mint,Enum.Material.Neon)
  local post=part("StartPylon",Vector3.new(2.8,14,3),Vector3.new(start.X+side*21.5,floor+7,start.Z+2),navy)
  part("PylonGlow",Vector3.new(.35,10,3.12),post.Position,side<0 and mint or pink,Enum.Material.Neon)
  local ball=part("PylonCap",Vector3.new(3.3,3.3,3.3),post.Position+Vector3.yAxis*7.5,gold)
  ball.Shape=Enum.PartType.Ball
 end
 for row=0,1 do for column=0,11 do
  part("StartTile",Vector3.new(3.3,.05,2.4),
   Vector3.new(start.X+(column-5.5)*3.3,floor+.04,start.Z+(row-.5)*2.4),
   (column+row)%2==0 and white or navy)
 end end
 local config=require(game.ServerScriptService.RaceConfig)
 local columns=config.GridColumns
 local capacity=config.MaxViewersPerOwner
 local rows=math.ceil(capacity/columns)
 local laneSpacing=config.LaneSpacing or config.GridSpacing
 local rowSpacing=config.GridRowSpacing or config.GridSpacing
 local forward=map:GetAttribute("StartForward")or Vector3.new(0,0,-1)
 local heading=CFrame.lookAt(Vector3.new(start.X,floor,start.Z),Vector3.new(start.X,floor,start.Z)+forward)
 for slot=1,capacity do
  local row=math.floor((slot-1)/columns)
  local col=(slot-1)%columns-(columns-1)/2
  local frame=heading*CFrame.new(col*laneSpacing,.055,14+row*rowSpacing)
  local color=({mint,pink,gold})[(row+(slot-1)%columns)%3+1]
  local line=part("GridSlot",Vector3.new(3.4,.05,.22),frame.Position,color)
  line.CFrame=frame line:SetAttribute("RaceSlot",slot)
  for _,side in {-1,1}do
   local wing=part("GridWing",Vector3.new(.22,.05,1.5),frame.Position,color)
   wing.CFrame=frame*CFrame.new(side*1.6,0,.64)
  end
 end
 local first,last=10,14+(rows-1)*rowSpacing+4
 for _,side in {-1,1}do
  local frame=heading*CFrame.new(side*18.4,.05,(first+last)/2)
  local border=part("GridBorder",Vector3.new(.16,.05,last-first),frame.Position,mint,Enum.Material.Neon)
  border.CFrame=frame
 end
 for i=-1,1 do
  local lamp=part("CountdownLight",Vector3.new(2,2,.65),Vector3.new(start.X+i*3,floor+21,start.Z+4.6),gold,Enum.Material.Neon)
  lamp.Shape=Enum.PartType.Ball
 end
 model.Parent=map
 return model
end
