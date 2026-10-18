local Players=game:GetService("Players")local RS=game:GetService("ReplicatedStorage")
local player=Players.LocalPlayer local remote=RS:WaitForChild("OverlayControl")
local UI=require(RS:WaitForChild("StreamerUI"))local C=UI.colors local page=UI.page("Overlays")
local selected="map"local urls local busy=false local enabled=false
UI.section(page,"Choose what your audience sees","Each view has its own private link. No LIVE connection is needed.")
local selectors=Instance.new("Frame")selectors.BackgroundTransparency=1 selectors.Size=UDim2.new(1,0,0,42)selectors.Parent=page
local definitions={{"topWin","TOP WIN","Weekly first-place champions.","Top 10 winners. Resets Monday at 00:00 Thailand time."},{"map","Race Map","Every racer on your real track.","The map follows race progress, with racer portraits and the top 5 below it."},{"ranking","Race Ranking","Who is closest to the finish?","The first 5 racers, their current lap and running speed."},{"speed","Live Speed","Who is fastest right now?","The current speed leaderboard. Boosts can move racers up or down."},{"all","All Views","Your complete race broadcast.","Race Map, Race Ranking and Live Speed together in one view."}}
local tabs={}
for i,d in definitions do local b=UI.button(selectors,d[2],UDim2.new((i-1)/#definitions,3,0,0),UDim2.new(1/#definitions,-6,0,40))b.Name=d[1]b.TextSize=12 b.TextWrapped=true tabs[d[1]]=b end
local preview=UI.card(page,196)preview.Name="OverlayPreview"
local canvas=Instance.new("Frame")canvas.Name="PreviewCanvas"canvas.Position=UDim2.fromOffset(16,16)canvas.Size=UDim2.new(.46,-24,1,-32)canvas.BackgroundColor3=C.bg canvas.BorderSizePixel=0 canvas.ClipsDescendants=true canvas.Parent=preview UI.corner(canvas,10)
local previewTitle=UI.text(preview,"",UDim2.new(.46,8,0,18),UDim2.new(.54,-24,0,26),17,C.mint,true)
local previewCaption=UI.text(preview,"",UDim2.new(.46,8,0,51),UDim2.new(.54,-24,0,34),13,C.text,true)
local previewDetail=UI.text(preview,"",UDim2.new(.46,8,0,92),UDim2.new(.54,-24,0,62),12,C.muted)
local previewHint=UI.text(preview,"SAMPLE LAYOUT",UDim2.new(.46,8,1,-29),UDim2.new(.54,-24,0,18),9,C.muted,true)
local function portrait(parent,id,pos,size)
 local image=Instance.new("ImageLabel")image.Position=pos image.Size=size image.BackgroundColor3=C.mint image.BorderSizePixel=0 image.Image="rbxthumb://type=AvatarHeadShot&id="..id.."&w=150&h=150"image.Parent=parent UI.corner(image,30)return image
end
local function miniMap(parent)
 local size=parent.AbsoluteSize if size.X<4 or size.Y<4 then parent:GetPropertyChangedSignal("AbsoluteSize"):Once(function()if parent.Parent then miniMap(parent)end end)return end
 local route=RS:FindFirstChild("ViewerRoute")local indexed={}if route then for _,g in route:GetChildren()do local index=g:GetAttribute("Index")if g:IsA("BasePart")and index then indexed[index]=g.Position end end end
 if #indexed<3 then UI.text(parent,"Your real track",UDim2.fromScale(.1,.3),UDim2.fromScale(.8,.4),12,C.mint)return end
 local minX,minZ,maxX,maxZ=math.huge,math.huge,-math.huge,-math.huge
 for _,p in indexed do minX=math.min(minX,p.X)maxX=math.max(maxX,p.X)minZ=math.min(minZ,p.Z)maxZ=math.max(maxZ,p.Z)end
 local scale=math.min((size.X-30)/math.max(1,maxX-minX),(size.Y-30)/math.max(1,maxZ-minZ))
 local function project(p)return Vector2.new(size.X/2+(p.X-(minX+maxX)/2)*scale,size.Y/2+(p.Z-(minZ+maxZ)/2)*scale)end
 local samples={}local step=math.max(1,math.floor(#indexed/90))for i=1,#indexed,step do table.insert(samples,project(indexed[i]))end table.insert(samples,samples[1])
 for i=1,#samples-1 do local a,b=samples[i],samples[i+1]local line=Instance.new("Frame")line.AnchorPoint=Vector2.new(.5,.5)line.Position=UDim2.fromOffset((a.X+b.X)/2,(a.Y+b.Y)/2)line.Size=UDim2.fromOffset((b-a).Magnitude+1,3)line.Rotation=math.deg(math.atan2(b.Y-a.Y,b.X-a.X))line.BackgroundColor3=i<#samples*.5 and C.mint or C.purple line.BorderSizePixel=0 line.Parent=parent end
 for i,id in {1,156,player.UserId}do local p=samples[math.clamp(4+i*5,1,#samples)]local image=portrait(parent,id,UDim2.fromOffset(p.X-7,p.Y-7),UDim2.fromOffset(14,14))UI.stroke(image,C.text,.15)end
end
local function miniRows(parent,speed)
 for i,id in {1,156,player.UserId}do
  local row=Instance.new("Frame")row.Position=UDim2.new(0,8,(i-1)/3,5)row.Size=UDim2.new(1,-16,1/3,-8)row.BackgroundColor3=C.raised row.BackgroundTransparency=.15 row.BorderSizePixel=0 row.Parent=parent UI.corner(row,5)
  local img=portrait(row,id,UDim2.fromOffset(6,4),UDim2.fromOffset(22,22))
  UI.text(row,tostring(i),UDim2.fromOffset(33,2),UDim2.new(1,-78,1,-4),11,C.text,true)
  UI.text(row,speed and({"240","120","16"})[i]or "LAP 1",UDim2.new(1,-49,0,2),UDim2.fromOffset(43,26),10,speed and C.gold or C.mint,true)
 end
end
local function paintPreview()
 for _,x in canvas:GetChildren()do if x:IsA("GuiObject")then x:Destroy()end end
 if selected=="map"then miniMap(canvas)
 elseif selected=="all"then
  local map=Instance.new("Frame")map.BackgroundTransparency=1 map.Size=UDim2.fromScale(.5,1)map.Parent=canvas miniMap(map)
  for i=1,2 do local board=Instance.new("Frame")board.BackgroundTransparency=1 board.Position=UDim2.fromScale(.5,(i-1)*.5)board.Size=UDim2.fromScale(.5,.5)board.Parent=canvas miniRows(board,i==2)end
 else miniRows(canvas,selected=="speed")end
end
local linkCard=UI.card(page,169)linkCard.Name="PrivateLink"
UI.text(linkCard,"YOUR PRIVATE LINK",UDim2.fromOffset(16,12),UDim2.new(1,-32,0,20),11,C.muted,true)
local link=UI.input(linkCard,"Preparing your private link…",UDim2.fromOffset(16,42),UDim2.new(1,-32,0,42))link.Name="OverlayURL"link.TextSize=11
local copy=UI.button(linkCard,"Select link",UDim2.fromOffset(16,96),UDim2.new(1,-32,0,38))copy.Name="SelectLink"
local status=UI.text(linkCard,"",UDim2.fromOffset(16,140),UDim2.new(1,-32,0,20),11,C.muted)
UI.notice(page,"Select the link, then press Ctrl+C or Cmd+C. Keep it private: anyone with your link can view your race.")
local testCard=UI.card(page,73)
UI.text(testCard,"Try it before going LIVE",UDim2.fromOffset(16,9),UDim2.new(1,-180,0,25),13,C.text,true)
UI.text(testCard,"Add a racer and watch your overlay update.",UDim2.fromOffset(16,36),UDim2.new(1,-32,0,25),11,C.muted)
local addTest=UI.button(testCard,"+ Test racer",UDim2.new(1,-151,0,10),UDim2.fromOffset(135,32))
local errors={overlay_map_not_configured="The game-specific overlay connection is not configured.",overlay_universe_required="Use the published experience for game-specific overlays.",overlay_scope_mismatch="The overlay credential does not match this experience.",deploy_required="The overlay service is not ready. Retrying…",bridge_not_configured="The map overlay connection is not configured.",overlay_owner_busy="Your overlay is active in another room.",unavailable="Connection interrupted. Retrying…",connecting="Preparing your link…",cooldown="Please wait a moment and try again.",disabled="Overlays are disabled."}
local function refresh()
 for _,d in definitions do UI.select(tabs[d[1]],selected==d[1])if selected==d[1]then previewTitle.Text=d[2]previewCaption.Text=d[3]previewDetail.Text=d[4]end end
 link.Text=urls and urls[selected]or ""
 UI.enabled(copy,urls~=nil and not busy)
end
local function request(action)
 if busy then return end busy=true status.Text="Connecting…"refresh()
 task.spawn(function()
  local ok,data=pcall(remote.InvokeServer,remote,action)busy=false
  if not ok or type(data)~="table"then status.Text="Could not reach the server."refresh()return end
  if data.enabled~=nil then enabled=data.enabled==true end if data.urls then urls=data.urls end
  status.Text=data.ok and(enabled and "Ready. This link shows only your room."or "Links stay active automatically.")or errors[data.error]or tostring(data.error)refresh()
 end)
end
for key,b in tabs do b.Activated:Connect(function()selected=key refresh()task.defer(paintPreview)end)end
local gameCard=UI.card(page,112)
UI.text(gameCard,"IN-GAME · Drag / Double-click to resize",UDim2.fromOffset(16,10),UDim2.new(1,-32,0,24),12,C.mint,true)
for i,d in {{'ShowCourseOverlay','Course line'},{'ShowTopWinOverlay','TOP WIN'}}do
 local b=UI.button(gameCard,d[2],UDim2.new((i-1)*.5,16,0,48),UDim2.new(.5,-24,0,38))
 local function paint()local on=player:GetAttribute(d[1])~=false b.Text=d[2]..(on and ' · ON'or ' · OFF')UI.select(b,on)end
 b.Activated:Connect(function()player:SetAttribute(d[1],player:GetAttribute(d[1])==false)paint()end)paint()
end
copy.Activated:Connect(function()if not urls then return end link.Text=urls[selected]link:CaptureFocus()link.CursorPosition=#link.Text+1 link.SelectionStart=1 status.Text="Link selected. Press Ctrl+C or Cmd+C."end)
link.FocusLost:Connect(refresh)
addTest.Activated:Connect(function()
 if not addTest.Active then return end UI.enabled(addTest,false)
 task.spawn(function()
  local control=RS:FindFirstChild("DevTestControl")local ok,data=pcall(function()return control and control:InvokeServer("spawn")end)
  UI.enabled(addTest,true)
  if ok and data and data.ok then UI.toast("Test racer added. Press Start when ready.")task.delay(.5,function()player:SetAttribute("DevTestFocusActor",data.actorKey)end)
  else UI.toast("Could not add a racer. Check the Test page for details.",true)end
 end)
end)
page:GetPropertyChangedSignal("Visible"):Connect(function()if page.Visible then request("info")task.defer(paintPreview)end end)
player:GetAttributeChangedSignal("OverlayStatus"):Connect(function()
 local value=player:GetAttribute("OverlayStatus")status.Text=({live="Connected. Updates every second.",ready="Your link is ready.",disabled="Links stay active automatically."})[value]or errors[value]or tostring(value)
 if(value=="ready"or value=="live")and enabled and not urls then task.delay(.6,function()if not urls and not busy then request("info")end end)end
end)
local function resize()
 local narrow=page.AbsoluteSize.X<480
 selectors.Size=UDim2.new(1,0,0,narrow and 134 or 42)
 for i,d in definitions do tabs[d[1]].Position=narrow and UDim2.new((i-1)%2*.5,3,0,math.floor((i-1)/2)*46)or UDim2.new((i-1)/#definitions,3,0,0)tabs[d[1]].Size=UDim2.new(narrow and .5 or 1/#definitions,-6,0,40)end
 local compact=page.AbsoluteSize.X<440 preview.Size=UDim2.new(1,0,0,compact and 252 or 196)
 canvas.Position=UDim2.fromOffset(16,16)canvas.Size=compact and UDim2.new(1,-32,0,102)or UDim2.new(.46,-24,1,-32)
 previewTitle.Position=compact and UDim2.fromOffset(16,127)or UDim2.new(.46,8,0,18)previewTitle.Size=UDim2.new(compact and 1 or .54,compact and -32 or -24,0,26)
 previewCaption.Position=compact and UDim2.fromOffset(16,157)or UDim2.new(.46,8,0,51)previewCaption.Size=UDim2.new(compact and 1 or .54,compact and -32 or -24,0,34)
 previewDetail.Position=compact and UDim2.fromOffset(16,194)or UDim2.new(.46,8,0,92)previewDetail.Size=UDim2.new(compact and 1 or .54,compact and -32 or -24,0,compact and 45 or 62)previewHint.Visible=not compact
 task.defer(paintPreview)
end
page:GetPropertyChangedSignal("AbsoluteSize"):Connect(resize)refresh()task.defer(resize)task.defer(function()request("info")end)

