-- Local presentation only. Scores and winners always come from the server.
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local UIS=game:GetService('UserInputService')
local RunService=game:GetService('RunService')
local player=Players.LocalPlayer
local remote=RS:WaitForChild('OverlayGameData')
local CourseArt=require(RS:WaitForChild('CourseOverlayArt'))
local UI=require(RS:WaitForChild('StreamerUI'))
local Art=require(RS:WaitForChild('StreamerUIArt'))
local gui=Instance.new('ScreenGui')gui.Name='InGameOverlays'gui.ResetOnSpawn=false gui.DisplayOrder=15 gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling gui.Parent=player:WaitForChild('PlayerGui')
local mint=Color3.fromRGB(157,245,220)local gold=Color3.fromRGB(255,218,136)
local colors={Color3.fromRGB(255,224,152),mint,Color3.fromRGB(255,181,216),Color3.fromRGB(198,181,255)}
local function corner(f,n)local c=Instance.new('UICorner')c.CornerRadius=UDim.new(0,n)c.Parent=f end
local function label(parent,text,size,pos,fontSize,color)
 local l=Instance.new('TextLabel')l.BackgroundTransparency=1 l.Text=text l.RichText=false l.Font=Enum.Font.GothamBold l.TextSize=fontSize l.TextColor3=color or Color3.new(1,1,1)l.TextStrokeTransparency=.45 l.TextStrokeColor3=Color3.fromRGB(6,16,31)l.TextXAlignment=Enum.TextXAlignment.Left l.TextTruncate=Enum.TextTruncate.AtEnd l.Size=size l.Position=pos l.Parent=parent return l
end
local function panelArt(parent)
 parent.BackgroundTransparency=1
 local image=Instance.new('ImageLabel')image.Name='IllustratedPanel'image.BackgroundTransparency=1 image.Size=UDim2.fromScale(1,1)image.Image=Art.Panel image.ScaleType=Enum.ScaleType.Slice image.SliceCenter=Rect.new(222,204,788,802)image.SliceScale=.13 image.ZIndex=0 image.Parent=parent
end
local function controlLabel(l)l.Font=Enum.Font.FredokaOne l.TextColor3=UI.colors.text l.TextStrokeTransparency=1 end
local widgets={}
local openSettings
local function draggable(name,size,pos)
 local f=Instance.new('Frame')f.Name=name f.BackgroundTransparency=1 f.Size=UDim2.fromOffset(size.X,size.Y)f.Position=pos f.Parent=gui
 local scale=Instance.new('UIScale')scale.Parent=f
 local hit=Instance.new('TextButton')hit.Name='DragSurface'hit.Text=''hit.BackgroundTransparency=1 hit.AutoButtonColor=false hit.Size=UDim2.fromScale(1,1)hit.ZIndex=100 hit.Active=true hit.Parent=f
 local w={frame=f,scale=scale,size=size,factor=1}table.insert(widgets,w)
 local drag local lastClick=0
 local function clamp(x,y)
  local screen=gui.AbsoluteSize local bounds=f.AbsoluteSize
  -- Leave a reachable edge, while allowing the visible route to reach any screen position.
  f.Position=UDim2.fromOffset(math.clamp(x,24-bounds.X,math.max(0,screen.X-24)),math.clamp(y,24-bounds.Y,math.max(0,screen.Y-24)))
 end
 hit.InputBegan:Connect(function(input)
  if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
   drag={input=input,at=Vector2.new(input.Position.X,input.Position.Y),origin=Vector2.new(f.Position.X.Offset,f.Position.Y.Offset),moved=false}
  end
 end)
 UIS.InputChanged:Connect(function(input)
  if drag and(input==drag.input or input.UserInputType==Enum.UserInputType.MouseMovement)then
   local d=Vector2.new(input.Position.X,input.Position.Y)-drag.at
   if d.Magnitude>4 then drag.moved=true end
   if drag.moved then clamp(drag.origin.X+d.X,drag.origin.Y+d.Y)end
  end
 end)
 UIS.InputEnded:Connect(function(input)
  if drag and(input==drag.input or input.UserInputType==Enum.UserInputType.MouseButton1)then
   local clicked=not drag.moved drag=nil
   if clicked then local now=os.clock()if now-lastClick<.35 then lastClick=0 openSettings(w)else lastClick=now end end
  end
 end)
 function w.resize(factor)
  if factor then w.factor=math.clamp(factor,.3,1.8)end
  local screen=gui.AbsoluteSize
  scale.Scale=math.min(w.factor,math.max(.1,(screen.X-12)/w.size.X),math.max(.1,(screen.Y-12)/w.size.Y))
  task.defer(function()clamp(f.Position.X.Offset,f.Position.Y.Offset)end)
 end
 return f,w
end
local screen=gui.AbsoluteSize
local course=draggable('CourseLine',Vector2.new(330,300),UDim2.fromOffset(16,math.max(10,screen.Y-405)))
local weekly,weeklyWidget=draggable('TopWin',Vector2.new(300,110),UDim2.fromOffset(math.max(0,screen.X-318),12))
label(weekly,'TOP WIN',UDim2.new(1,-12,0,27),UDim2.fromOffset(8,0),20,gold)
local weekLabel=label(weekly,'THIS WEEK · RESETS MONDAY 00:00 TH',UDim2.new(1,-12,0,18),UDim2.fromOffset(8,29),8,Color3.fromRGB(225,237,248))
weekLabel.TextSize=9 weekLabel.TextStrokeTransparency=.75 weekLabel.Font=Enum.Font.GothamMedium
local empty=label(weekly,'Waiting for TOP WIN…',UDim2.new(1,-24,0,50),UDim2.fromOffset(12,65),12,mint)
local rowFrames={}
for i=1,10 do
 local row=Instance.new('Frame')row.Name='Place'..i row.Position=UDim2.fromOffset(8,49+(i-1)*31)row.Size=UDim2.fromOffset(284,28)row.BackgroundColor3=Color3.fromRGB(20,33,57)row.BackgroundTransparency=.32 row.BorderSizePixel=0 row.Visible=false row.Parent=weekly
 local outline=Instance.new('UIStroke')outline.Color=Color3.fromRGB(244,251,255)outline.Transparency=.6 outline.Thickness=1 outline.Parent=row
 local stripe=Instance.new('Frame')stripe.BorderSizePixel=0 stripe.BackgroundColor3=gold stripe.Size=UDim2.new(0,3,1,0)stripe.Parent=row
 label(row,tostring(i),UDim2.fromOffset(23,28),UDim2.fromOffset(8,0),i==1 and 16 or 12,i==1 and gold or Color3.new(1,1,1))
 local image=Instance.new('ImageLabel')image.Name='Avatar'image.BackgroundColor3=mint image.Size=UDim2.fromOffset(22,22)image.Position=UDim2.fromOffset(34,3)image.Parent=row corner(image,20)
 local name=label(row,'Viewer',UDim2.fromOffset(159,28),UDim2.fromOffset(64,0),11)
 local wins=label(row,'0',UDim2.fromOffset(50,28),UDim2.fromOffset(224,0),15,gold)wins.TextXAlignment=Enum.TextXAlignment.Right
 rowFrames[i]={frame=row,image=image,name=name,wins=wins}
end
local route,version,projection
local routeLayer=Instance.new('Frame')routeLayer.Name='Route'routeLayer.Size=UDim2.fromScale(1,1)routeLayer.BackgroundTransparency=1 routeLayer.Parent=course
local markerLayer=routeLayer:Clone()markerLayer.Name='Racers'markerLayer.Parent=course
local function paintRoute(r)
 route=r version=r.version
 for _,x in routeLayer:GetChildren()do x:Destroy()end
 local minX,minY,maxX,maxY=math.huge,math.huge,-math.huge,-math.huge
 for _,p in r.points do minX=math.min(minX,p[1])maxX=math.max(maxX,p[1])minY=math.min(minY,p[2])maxY=math.max(maxY,p[2])end
 local scale=math.min(720/math.max(1,maxX-minX),680/math.max(1,maxY-minY))
 projection=function(p)return Vector2.new((450+(p[1]-(minX+maxX)/2)*scale)*330/900,(430+(p[2]-(minY+maxY)/2)*scale)*300/880)end
 local function segment(a,b,width,color,z)
  local f=Instance.new('Frame')f.AnchorPoint=Vector2.new(.5,.5)f.Position=UDim2.fromOffset((a.X+b.X)/2,(a.Y+b.Y)/2)f.Size=UDim2.fromOffset((b-a).Magnitude+1,width)f.Rotation=math.deg(math.atan2(b.Y-a.Y,b.X-a.X))f.BackgroundColor3=color f.BorderSizePixel=0 f.ZIndex=z f.Parent=routeLayer corner(f,width/2)
 end
 local projected={}for _,p in r.points do table.insert(projected,projection(p))end
 if not CourseArt.draw(routeLayer,projected,colors)then
  -- Draw complete layers in order, so neighboring segment outlines never cut the color.
  for layer=1,3 do
   for i,a in projected do
    local b=projected[i%#projected+1]
    local color=layer==1 and Color3.fromRGB(13,26,45)or layer==2 and Color3.fromRGB(255,249,231)or colors[math.min(4,math.floor((i-1)/#projected*4)+1)]
    segment(a,b,({6,4.4,3})[layer],color,layer)
   end
  end
 end
 local start=projection(r.points[1])local flag=label(routeLayer,'🏁',UDim2.fromOffset(24,24),UDim2.fromOffset(start.X-12,start.Y-12),16)flag.ZIndex=4
end
local function point(distance)
 local n=#route.points local d=(math.max(0,distance)%route.length)/route.length*n local i=math.floor(d)local f=d-i local a,b=route.points[i%n+1],route.points[(i+1)%n+1]
 return projection({a[1]+(b[1]-a[1])*f,a[2]+(b[2]-a[2])*f})
end
local function showBoard(b)
 if not b then return end
 local count=math.min(10,#b.rows)
 weeklyWidget.size=Vector2.new(300,count>0 and 55+count*31 or 110)weekly.Size=UDim2.fromOffset(weeklyWidget.size.X,weeklyWidget.size.Y)weeklyWidget.resize()
 weekLabel.Text='WEEK '..b.week..' · RESETS MONDAY 00:00 TH'
 empty.Visible=#b.rows==0 empty.Text='No winners this week'
 for i,row in rowFrames do
  local r=b.rows[i]row.frame.Visible=r~=nil
  if r then row.name.Text=r.name row.wins.Text=tostring(r.wins)row.image.Image='rbxthumb://type=AvatarHeadShot&id='..r.robloxId..'&w=150&h=150'end
 end
 weekly:SetAttribute('NextResetAt',b.nextResetAt)
end
local markers={}local elapsed=0
RunService.RenderStepped:Connect(function(dt)
 if not route or not projection then return end
 elapsed+=dt if elapsed<1/30 then return end local blend=1-math.exp(-elapsed*16)elapsed=0
 local folder=workspace:FindFirstChild('TikkiesDemoNPCs')local keep={}local anchors={}
 if folder then for _,m in folder:GetChildren()do
  if m:GetAttribute('OwnerRobloxId')==tostring(player.UserId)then
   local id=m:GetAttribute('ActorKey')local hum=m:FindFirstChildOfClass('Humanoid')
   if id and hum and hum.Health>0 then
    local distance=m:GetAttribute('RouteDistance')or (m:GetAttribute('RaceProgress')or 0)*route.length
    table.insert(anchors,{id=id,model=m,point=point(distance)})keep[id]=true
   end
  end
 end end
 table.sort(anchors,function(a,b)return a.id<b.id end)
 local cells={}
 for _,a in anchors do
  local cell=math.floor(a.point.X/10)..':'..math.floor(a.point.Y/10)local count=cells[cell]or 0 cells[cell]=count+1
  local offset=Vector2.new(math.sin(count*2.4)*math.min(8,count*.7),math.cos(count*2.4)*math.min(8,count*.7))
  local target=a.point+offset local image=markers[a.id]
  if not image then
   image=Instance.new('ImageLabel')image.Name='Racer'image.AnchorPoint=Vector2.new(.5,.5)image.Size=UDim2.fromOffset(18,18)image.BackgroundColor3=mint image.Image='rbxthumb://type=AvatarHeadShot&id='..tostring(a.model:GetAttribute('RobloxId'))..'&w=150&h=150'image.Position=UDim2.fromOffset(target.X,target.Y)image.ZIndex=6 image.Parent=markerLayer corner(image,20)
   local stroke=Instance.new('UIStroke')stroke.Color=Color3.fromRGB(255,249,231)stroke.Thickness=1.5 stroke.Parent=image markers[a.id]=image
  end
  local old=Vector2.new(image.Position.X.Offset,image.Position.Y.Offset)local pos=old:Lerp(target,blend)image.Position=UDim2.fromOffset(pos.X,pos.Y)
 end
 for id,image in markers do if not keep[id]then image:Destroy()markers[id]=nil end end
end)
-- One small settings popover shared by both widgets; double-click/tap any visible part.
local settingsGui=Instance.new('ScreenGui')settingsGui.Name='OverlayWidgetSettings'settingsGui.ResetOnSpawn=false settingsGui.DisplayOrder=150 settingsGui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling settingsGui.Parent=gui.Parent
local settings=Instance.new('Frame')settings.Name='WidgetSettings'settings.Size=UDim2.fromOffset(302,194)settings.BackgroundColor3=Color3.fromRGB(20,33,57)settings.BorderSizePixel=0 settings.ZIndex=200 settings.Visible=false settings.Active=true settings.Parent=settingsGui corner(settings,12)
panelArt(settings)
local title=label(settings,'Overlay settings',UDim2.fromOffset(224,27),UDim2.fromOffset(14,8),14,mint)
local function settingsButton(text,pos,size)
 local b=UI.button(settings,text,pos,size)b.TextSize=12 return b
end
controlLabel(title)title.Position=UDim2.fromOffset(18,17)
local close=settingsButton('×',UDim2.fromOffset(252,14),UDim2.fromOffset(31,31))close.Activated:Connect(function()settings.Visible=false end)
local amount=label(settings,'SIZE · 100%',UDim2.fromOffset(258,23),UDim2.fromOffset(20,54),11)
controlLabel(amount)
local rail=Instance.new('TextButton')rail.Name='SizeSlider'rail.Text=''rail.BackgroundColor3=Color3.fromRGB(161,190,180)rail.Size=UDim2.fromOffset(252,8)rail.Position=UDim2.fromOffset(25,94)rail.ZIndex=202 rail.Parent=settings corner(rail,4)
local fill=Instance.new('Frame')fill.BackgroundColor3=Color3.fromRGB(13,191,231) fill.BorderSizePixel=0 fill.Size=UDim2.fromScale(.5,1)fill.ZIndex=203 fill.Parent=rail corner(fill,4)
local knob=Instance.new('Frame')knob.Name='Knob'knob.AnchorPoint=Vector2.new(.5,.5)knob.Size=UDim2.fromOffset(18,18)knob.Position=UDim2.fromScale(.5,.5)knob.BackgroundColor3=Color3.new(1,1,1)knob.ZIndex=204 knob.Parent=rail corner(knob,20)
local toggle=settingsButton('Hide overlay',UDim2.fromOffset(18,133),UDim2.fromOffset(129,38))
local reset=settingsButton('Reset size',UDim2.fromOffset(154,133),UDim2.fromOffset(129,38))

local selected,sliding
local function refreshSize()
 if not selected then return end local f=(selected.factor-.3)/1.5 fill.Size=UDim2.fromScale(f,1)knob.Position=UDim2.fromScale(f,.5)amount.Text='SIZE · '..math.round(selected.scale.Scale*100)..'%'
end
openSettings=function(w)
 selected=w title.Text=w.frame.Name=='TopWin'and 'TOP WIN'or 'Course line'
 local screen=gui.AbsoluteSize local pos=w.frame.AbsolutePosition
 settings.Position=UDim2.fromOffset(math.clamp(pos.X,8,math.max(8,screen.X-310)),math.clamp(pos.Y,8,math.max(8,screen.Y-202)))settings.Visible=true refreshSize()
end
local function slide(input)
 if selected then local fraction=math.clamp((input.Position.X-rail.AbsolutePosition.X)/rail.AbsoluteSize.X,0,1)selected.resize(.3+fraction*1.5)refreshSize()end
end
rail.InputBegan:Connect(function(input)
 if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then sliding=input slide(input)end
end)
UIS.InputChanged:Connect(function(input)if sliding and(input==sliding or input.UserInputType==Enum.UserInputType.MouseMovement)then slide(input)end end)
UIS.InputEnded:Connect(function(input)if sliding and(input==sliding or input.UserInputType==Enum.UserInputType.MouseButton1)then sliding=nil end end)
toggle.Activated:Connect(function()if selected then player:SetAttribute(selected.frame.Name=='TopWin'and 'ShowTopWinOverlay'or 'ShowCourseOverlay',false)settings.Visible=false end end)
reset.Activated:Connect(function()if selected then selected.resize(1)refreshSize()end end)
local function visibility()course.Visible=player:GetAttribute('ShowCourseOverlay')~=false weekly.Visible=player:GetAttribute('ShowTopWinOverlay')~=false end
player:GetAttributeChangedSignal('ShowCourseOverlay'):Connect(visibility)player:GetAttributeChangedSignal('ShowTopWinOverlay'):Connect(visibility)visibility()
-- Always reachable, even after both widgets have been hidden.
local recover=UI.button(settingsGui,'OVERLAYS',UDim2.new(1,-16,1,-16),UDim2.fromOffset(128,38))recover.Name='OverlayControls'recover.AnchorPoint=Vector2.new(1,1)recover.TextSize=13
local controls=Instance.new('Frame')controls.Name='VisibilityControls'controls.AnchorPoint=Vector2.new(1,1)controls.Position=UDim2.new(1,-16,1,-58)controls.Size=UDim2.fromOffset(266,224)controls.BackgroundColor3=Color3.fromRGB(20,33,57)controls.BorderSizePixel=0 controls.Visible=false controls.Parent=settingsGui panelArt(controls)
local controlsTitle=label(controls,'IN-GAME OVERLAYS',UDim2.fromOffset(230,26),UDim2.fromOffset(22,27),13,UI.colors.text)controlLabel(controlsTitle)
for i,d in {{'ShowCourseOverlay','Course line'},{'ShowTopWinOverlay','TOP WIN'}}do
 local b=UI.button(controls,d[2],UDim2.fromOffset(16,60+(i-1)*46),UDim2.fromOffset(234,40))b.Name=d[1]b.TextSize=13
 local function paint()local on=player:GetAttribute(d[1])~=false b.Text=d[2]..(on and ' · ON'or ' · OFF')UI.select(b,on)end
 b.Activated:Connect(function()player:SetAttribute(d[1],player:GetAttribute(d[1])==false)end)player:GetAttributeChangedSignal(d[1]):Connect(paint)paint()
end
local restore=UI.button(controls,'Reset position and size',UDim2.fromOffset(16,152),UDim2.fromOffset(234,40))restore.Name='ResetLayout'restore.TextSize=11
restore.Activated:Connect(function()
 course.Position=UDim2.fromOffset(16,math.max(10,gui.AbsoluteSize.Y-405))weekly.Position=UDim2.fromOffset(math.max(0,gui.AbsoluteSize.X-318),12)
 for _,w in widgets do w.resize(gui.AbsoluteSize.Y<600 and .75 or 1)end
 player:SetAttribute('ShowCourseOverlay',true)player:SetAttribute('ShowTopWinOverlay',true)settings.Visible=false
end)
recover.Activated:Connect(function()controls.Visible=not controls.Visible settings.Visible=false end)
gui:GetPropertyChangedSignal('AbsoluteSize'):Connect(function()for _,w in widgets do w.resize()end end)
for _,w in widgets do w.resize()end
if screen.Y<600 then for _,w in widgets do w.resize(.75)end end
task.spawn(function()
 while gui.Parent do
  local ok,data=pcall(remote.InvokeServer,remote,version)
  if ok and type(data)=='table'then if data.route then paintRoute(data.route)end showBoard(data.topWin)end
  local reset=weekly:GetAttribute('NextResetAt')if reset and DateTime.now().UnixTimestampMillis>=reset then for _,r in rowFrames do r.frame.Visible=false end weeklyWidget.size=Vector2.new(300,110)weekly.Size=UDim2.fromOffset(300,110)weeklyWidget.resize()empty.Visible=true empty.Text='No winners this week'end
  task.wait(2)
 end
end)
