local Players=game:GetService("Players")local RS=game:GetService("ReplicatedStorage")
local player=Players.LocalPlayer local remote=RS:WaitForChild("LiveSettingsControl")
local UI=require(RS:WaitForChild("StreamerUI"))local C=UI.colors local page=UI.page("Live")
local selected=player:GetAttribute("LiveProvider") or "direct"local joinMode=player:GetAttribute("PreferredJoinMode") or "both"local pending=false
local provider=UI.card(page,60)provider.Name="ProviderCard" provider.LayoutOrder=1
local direct=UI.button(provider,"Direct Live",UDim2.fromOffset(0,0),UDim2.new(.5,-6,0,40),"primary")direct.Name="Direct"
local tikkies=UI.button(provider,"Tikkies",UDim2.new(.5,6,0,0),UDim2.new(.5,-6,0,40))tikkies.Name="Tikkies"
local help=UI.text(provider,"",UDim2.fromOffset(0,42),UDim2.new(1,0,0,19),11,C.muted)
local username=UI.card(page,90)username.Name="UsernameCard" username.LayoutOrder=2
UI.text(username,"TikTok username",UDim2.new(),UDim2.new(1,0,0,22),14,C.text,true)
local input=UI.input(username,"@your_tiktok_name",UDim2.fromOffset(0,24),UDim2.new(1,0,0,40))input.Name="Username"input.Text=player:GetAttribute("PreferredTikTokUsername") or ""
local saveHint=UI.text(username,"Saved automatically",UDim2.fromOffset(0,67),UDim2.new(1,0,0,20),11,C.mint)
local tikkiesCard=UI.card(page,70)tikkiesCard.Name="TikkiesInstructions" tikkiesCard.LayoutOrder=2
UI.text(tikkiesCard,"Connect this map in Tikkies Games, then press Connect.",UDim2.new(),UDim2.new(1,0,1,0),14,C.text)
local connection=UI.card(page,128)connection.Name="ConnectionStatus" connection.LayoutOrder=4
local status=UI.text(connection,"Not connected",UDim2.new(),UDim2.new(1,0,0,23),15,C.text,true)
local detail=UI.text(connection,"",UDim2.fromOffset(0,26),UDim2.new(1,0,0,42),12,C.muted)
local connect=UI.button(connection,"Connect LIVE",UDim2.fromOffset(0,74),UDim2.new(1,0,0,48),"primary")connect.Name="Connect"
local joinCard=UI.card(page,100)joinCard.Name="JoinFormatCard"joinCard.LayoutOrder=3
UI.text(joinCard,"Viewer join settings",UDim2.new(),UDim2.new(1,0,0,22),13,C.text,true)
local modes={}
for i,item in {{key="at",label="With @"},{key="plain",label="Without @"},{key="both",label="Both"}}do local b=UI.button(joinCard,item.label,UDim2.new((i-1)/3,4,0,27),UDim2.new(1/3,-8,0,36))b.Name=item.key modes[item.key]=b end
local joinHelp=UI.text(joinCard,"",UDim2.fromOffset(4,67),UDim2.new(1,-8,0,30),12,C.text)
local gifts=UI.card(page,96)gifts.Name="DirectGiftEvents"gifts.LayoutOrder=5
UI.text(gifts,"LIVE events",UDim2.new(),UDim2.new(1,-100,0,24),15,C.text,true)
local reload=UI.button(gifts,"Refresh",UDim2.new(1,-94,0,0),UDim2.fromOffset(94,30))
local giftHint=UI.text(gifts,"",UDim2.fromOffset(0,31),UDim2.new(1,0,0,32),11,C.muted)
local giftList=Instance.new("Frame")giftList.Name="Mappings"giftList.BackgroundTransparency=1 giftList.Position=UDim2.fromOffset(0,68)giftList.Size=UDim2.new(1,0,0,0)giftList.Parent=gifts
local giftIcons=require(RS:WaitForChild("DirectGiftIcons"))
local labels={rainbow_cat="Speed V1",rocket="Rocket",naruto="Naruto",goku="Goku",asta="Asta",speed_boost="Speed Boost",fly="Fly",gojo="Gojo",shield="Shield",octopus="Octopus"}
local giftRevision,nextGiftRequest,queuedGift=0,0,0
local function requestGifts()
 queuedGift+=1 local queued=queuedGift
 if selected~="direct" then giftRevision+=1 return end
 if os.clock()<nextGiftRequest then task.delay(nextGiftRequest-os.clock(),function()if queuedGift==queued then requestGifts()end end)return end
 nextGiftRequest=os.clock()+2.3 giftRevision+=1
 giftHint.Text="Loading gift events…"
 remote:FireServer("get_gift_mappings",giftRevision)
end
reload.Activated:Connect(requestGifts)
remote.OnClientEvent:Connect(function(action,ticket,rows,reason)
 if action~="gift_mappings"or ticket~=giftRevision or selected~="direct"then return end
 if type(rows)~="table"then
  local reasons={worker_update_required="Update the Worker on your VPS, then press Refresh.",connecting="Connecting… Gift events will load when ready.",bridge_not_configured="The game connection is not configured yet.",unauthorized="The game could not verify the Worker connection.",defaults_not_ready="Publish gift defaults in Tikkies Admin first.",defaults_access_denied="The Worker could not verify gift defaults.",direct_only="Switch your active connection to Direct Live to see gift events."}
  giftHint.Text=reasons[reason]or "Gift events unavailable. Press Refresh to try again."return
 end
 giftHint.Text=#rows==0 and "No gifts are mapped yet."or player:GetAttribute("LiveEnabled")and "Active LIVE events. Likes count separately for each viewer."or "Default LIVE events. Likes count separately for each viewer."
 for _,child in giftList:GetChildren()do child:Destroy()end
 local records={}
 local ordering={rocket=1,rainbow_cat=2,naruto=3,goku=4,asta=5,speed_boost=6,fly=7,gojo=8,shield=9,octopus=10}
 for _,row in rows do table.insert(records,{sources={row},order=ordering[row.eventKey]or 99})end
 table.sort(records,function(a,b)return a.order<b.order end)
 local y=0
 for i,record in records do
  local height=#record.sources>1 and 64 or 52
  local line=Instance.new("Frame")line.BackgroundColor3=i%2==0 and C.raised or C.surface line.BorderSizePixel=0 line.Position=UDim2.fromOffset(0,y)line.Size=UDim2.new(1,0,0,height)line.Parent=giftList UI.corner(line,8)
  local names,effectNames,seenEffects={},{},{}
  for j,row in record.sources do
   local key=(row.sourceType=="like"or row.sourceType=="follow")and row.sourceType or tostring(row.giftId)
   local x=8+(j-1)*44
   local icon=Instance.new("ImageLabel")icon.Name="GiftImage"icon.BackgroundTransparency=1 icon.Position=UDim2.fromOffset(x,(height-40)/2)icon.Size=UDim2.fromOffset(40,40)icon.ScaleType=Enum.ScaleType.Fit icon.Parent=line
   local fallback=UI.text(line,"🎁",icon.Position,icon.Size,24,C.muted)fallback.Name="GiftImageFallback"fallback.TextXAlignment=Enum.TextXAlignment.Center
   local asset=giftIcons[key]
   if type(asset)=="string"and asset:match("^rbxassetid://%d+$")then icon.Image=asset fallback.Visible=false end
   table.insert(names,row.sourceType=="like"and tostring(row.likeCount or 20).." Likes"or row.giftName or("Gift #"..tostring(row.giftId)))
   if not seenEffects[row.eventKey]then seenEffects[row.eventKey]=true table.insert(effectNames,labels[row.eventKey]or row.eventKey)end
  end
  local nameX=14+#record.sources*44
  local name=UI.text(line,table.concat(names," / "),UDim2.fromOffset(nameX,0),UDim2.new(.52,-nameX,1,0),12,C.text,true)name.RichText=false
  UI.text(line,"→",UDim2.new(.52,0,0,0),UDim2.new(.08,0,1,0),16,C.muted)
  UI.text(line,table.concat(effectNames," / "),UDim2.new(.6,0,0,0),UDim2.new(.4,-8,1,0),12,C.mint,true)
  y+=height+4
 end
 giftList.Size=UDim2.new(1,0,0,y)gifts.Size=UDim2.new(1,0,0,math.max(96,76+y))
end)
local errors={defaults_universe_required="This game connection needs an update. Contact the map owner.",defaults_not_ready="Gift defaults are not ready. Publish them in Tikkies Admin first.",defaults_access_denied="Gift defaults could not be verified. Contact the map owner.",defaults_universe_forbidden="Gift defaults belong to a different game.",previous_connection_closing="Closing your previous connection. Please try again shortly.",invalid_username="Enter a TikTok username, not a link (2–24 characters).",owner_busy="Your previous connection is still closing. Please try again shortly.",live_busy="This TikTok account is connected in another room.",network_error="Connection interrupted. Trying again…",bridge_unauthorized="The game connection could not be verified. Contact the map owner.",bridge_not_configured="The map connection is not configured yet.",tikkies_unavailable="Tikkies is not available yet. Check your map connection.",tikkies_not_configured="The Tikkies map connection has not been set up.",tikkies_unauthorized="Tikkies could not verify this map connection.",tikkies_network_error="Could not reach Tikkies. Retrying…",tikkies_registration_failed="Preparing the Tikkies map connection…",reset_retrying="Preparing a fresh round. Please wait…",handler_failed="Could not connect. Please try again.",disconnect_first="Disconnect before changing your connection.",join_mode_update_failed="Could not update the join format. Please try again."}
local states={disconnected="Not connected",connecting="Connecting…",queued="Waiting to connect…",live="Connected",offline="Waiting for your TikTok LIVE",retrying="Reconnecting…",error="Connection needs attention",resetting="Preparing the next round…"}
local function refresh()
 local enabled=player:GetAttribute("LiveEnabled")==true local activeProvider=player:GetAttribute("LiveProvider") or "direct"local activeName=player:GetAttribute("LiveUsername") or ""local phase=player:GetAttribute("LiveStatus") or "disconnected"
 local same=enabled and activeProvider==selected and(selected=="tikkies" or activeName==input.Text:gsub("^@",""):lower())
 UI.select(direct,selected=="direct")UI.select(tikkies,selected=="tikkies",C.purple)
 username.Visible=selected=="direct"joinCard.Visible=selected=="direct" gifts.Visible=selected=="direct"
 tikkiesCard.Visible=selected=="tikkies"
 help.Text=selected=="direct"and "Read chat, gifts, likes and follows from your TikTok LIVE."or "Use the viewers and events you set up in Tikkies."
 local save=player:GetAttribute("UsernameSaveStatus")saveHint.Text=save=="saved"and "✓ Username saved"or save=="saving"and "Saving…"or save=="session"and "Remembered for this session"or "Saved automatically as you type"
 for key,b in modes do UI.select(b,key==joinMode)UI.enabled(b,not pending)UI.select(b,key==joinMode)end
 joinHelp.Text=joinMode=="at"and "Viewers type @RobloxUsername in chat."or joinMode=="plain"and "Viewers type RobloxUsername directly in chat."or "Viewers can type @RobloxUsername or RobloxUsername."
 status.Text=(states[phase]or phase)..(enabled and "  ·  "..(activeProvider=="direct"and "Direct Live"or "Tikkies")or "")status.TextColor3=phase=="live"and C.mint or phase=="error"and C.red or C.text
 local errorCode=player:GetAttribute("LiveError")detail.Text=errors[errorCode]or(enabled and (activeProvider=="direct"and "Viewers join with their Roblox username. Gifts, likes and follows power their racer."or "New viewers and gifts will appear in your race automatically.")or (selected=="direct"and "Enter your TikTok name above, then connect."or "Ready to use your Tikkies viewer and gift settings."))
 local available=selected~="tikkies"or player:GetAttribute("TikkiesAvailable")==true
 if not available then detail.Text=errors[player:GetAttribute("LiveTikkiesError")]or errors.tikkies_unavailable end
 connect.Text=pending and "Please wait…"or same and "Disconnect"or enabled and "Switch connection"or "Connect LIVE"
 connect:SetAttribute("Kind",same and "danger"or "primary")UI.enabled(connect,not pending and available)
end
for mode,b in modes do b.Activated:Connect(function()if pending then return end joinMode=mode remote:FireServer("set_join_mode",mode)refresh()end)end
direct.Activated:Connect(function()if not pending then selected="direct"refresh()requestGifts()end end)tikkies.Activated:Connect(function()if not pending then selected="tikkies"refresh()requestGifts()end end)
local typed,applying=false,false local revision,lastSent=0,nil
local function saveName()
 local value=input.Text:match("^%s*(.-)%s*$"):gsub("^@",""):lower()
 if #value>=2 and #value<=24 and not value:find("[^%w._]")and value~=lastSent then lastSent=value remote:FireServer("save_username",value)end
end
input:GetPropertyChangedSignal("Text"):Connect(function()
 if #input.Text>32 then input.Text=input.Text:sub(1,32)end
 if not applying then typed=true revision+=1 local current=revision task.delay(1.3,function()if revision==current then saveName()end end)end refresh()
end)input.FocusLost:Connect(saveName)
player:GetAttributeChangedSignal("PreferredTikTokUsername"):Connect(function()if not typed then applying=true input.Text=player:GetAttribute("PreferredTikTokUsername")or ""applying=false end refresh()end)
player:GetAttributeChangedSignal("PreferredJoinMode"):Connect(function()joinMode=player:GetAttribute("PreferredJoinMode")or "both"refresh()end)
connect.Activated:Connect(function()
 if pending or not connect.Active then return end
 local name=input.Text:match("^%s*(.-)%s*$"):gsub("^@",""):lower()
 if selected=="direct"and(#name<2 or #name>24 or name:find("[^%w._]"))then detail.Text=errors.invalid_username UI.toast(errors.invalid_username,true)return end
 local enabled=player:GetAttribute("LiveEnabled")==true
 local same=enabled and player:GetAttribute("LiveProvider")==selected and(selected=="tikkies"or player:GetAttribute("LiveUsername")==name)
 pending=true refresh()
 if enabled then remote:FireServer("disconnect")if not same then local untilTime=os.clock()+12 repeat task.wait(.1)until not player:GetAttribute("LiveEnabled")or os.clock()>untilTime if not player:GetAttribute("LiveEnabled")then task.wait(2.1)remote:FireServer("connect",name,selected)end end
 else remote:FireServer("connect",name,selected)end
 task.wait(2.5)pending=false refresh()
end)
for _,name in {"LiveEnabled","LiveProvider","LiveUsername","LiveStatus","LiveError","LiveQueueDepth","TikkiesAvailable","LiveTikkiesError","UsernameSaveStatus"}do player:GetAttributeChangedSignal(name):Connect(refresh)end
remote.OnClientEvent:Connect(refresh)refresh()

local scheduled=0
for _,attribute in {"LiveEnabled","LiveProvider","LiveGiftMapVersion","LiveStatus"}do player:GetAttributeChangedSignal(attribute):Connect(function()scheduled+=1 local version=scheduled task.delay(2.2,function()if version==scheduled then requestGifts()end end)end)end
task.delay(1,requestGifts)

-- Opening the supplied guide posters never changes the LIVE connection.
do
 local guides={
  tikkies={th={image="rbxassetid://112142545916610",ratio=1491/1055},en={image="rbxassetid://71832756023478",ratio=1}},
  direct={th={image="rbxassetid://79344935340389",ratio=1},en={image="rbxassetid://117412900142181",ratio=1}},
 }
 local howCard=UI.card(page,42)howCard.Name="HowToCard"howCard.LayoutOrder=0
 UI.text(howCard,"LIVE connection guide",UDim2.new(),UDim2.new(1,-126,1,-4),12,C.muted)
 local open=UI.button(howCard,"HOW TO",UDim2.new(1,-120,0,0),UDim2.fromOffset(120,36))open.Name="HowTo"
 local modal=Instance.new("ScreenGui")modal.Name="LiveHowTo"modal.ResetOnSpawn=false modal.DisplayOrder=UI.gui.DisplayOrder+5 modal.ZIndexBehavior=Enum.ZIndexBehavior.Sibling modal.Enabled=false modal.Parent=UI.gui.Parent
 local shade=Instance.new("TextButton")shade.Name="Shade"shade.Text=""shade.AutoButtonColor=false shade.BackgroundColor3=Color3.fromRGB(8,25,42)shade.BackgroundTransparency=.22 shade.Size=UDim2.fromScale(1,1)shade.Parent=modal
 local window=Instance.new("Frame")window.Name="Window"window.AnchorPoint=Vector2.new(.5,.5)window.Position=UDim2.fromScale(.5,.5)window.Size=UDim2.new(1,-20,1,-20)window.BackgroundTransparency=1 window.Active=true window.Parent=shade
 local limit=Instance.new("UISizeConstraint")limit.MaxSize=Vector2.new(1000,900)limit.Parent=window
 local art=require(RS:WaitForChild("StreamerUIArt"))
 local board=Instance.new("ImageLabel")board.Name="IllustratedBoard"board.Image=art.Panel board.BackgroundTransparency=1 board.ScaleType=Enum.ScaleType.Slice board.SliceCenter=Rect.new(222,204,788,802)board.SliceScale=.22 board.Size=UDim2.fromScale(1,1)board.ZIndex=0 board.Parent=window
 local title=UI.text(window,"HOW TO",UDim2.fromOffset(24,20),UDim2.new(1,-88,0,30),21,C.text,true)
 local close=UI.button(window,"×",UDim2.new(1,-62,0,18),UDim2.fromOffset(38,34))close.Name="Close"close.TextSize=23
 local tools=Instance.new("Frame")tools.Name="Controls"tools.BackgroundTransparency=1 tools.Position=UDim2.fromOffset(24,59)tools.Size=UDim2.new(1,-48,0,76)tools.Parent=window
 local thai=UI.button(tools,"ไทย",UDim2.new(),UDim2.new(.5,-4,0,32))thai.Name="Thai"thai.Font=Enum.Font.GothamBold
 local english=UI.button(tools,"English",UDim2.new(.5,4,0,0),UDim2.new(.5,-4,0,32))english.Name="English"
 local minus=UI.button(tools,"−",UDim2.fromOffset(0,40),UDim2.fromOffset(32,30))minus.Name="ZoomOut"
 local zoomText=UI.text(tools,"100%",UDim2.fromOffset(36,40),UDim2.fromOffset(44,30),13,C.text,true)zoomText.Name="Zoom"zoomText.TextXAlignment=Enum.TextXAlignment.Center
 local plus=UI.button(tools,"+",UDim2.fromOffset(84,40),UDim2.fromOffset(32,30))plus.Name="ZoomIn"
 local fit=UI.button(tools,"Fit width",UDim2.new(1,-96,0,40),UDim2.fromOffset(96,30))fit.Name="FitWidth"
 local view=Instance.new("ScrollingFrame")view.Name="PosterView"view.Position=UDim2.fromOffset(24,139)view.Size=UDim2.new(1,-48,1,-166)view.BackgroundColor3=Color3.fromRGB(8,25,50)view.BorderSizePixel=0 view.ScrollBarThickness=7 view.ScrollBarImageColor3=C.mint view.ScrollingDirection=Enum.ScrollingDirection.XY view.CanvasSize=UDim2.new()view.Parent=window UI.corner(view,8)
 local poster=Instance.new("ImageLabel")poster.Name="Poster"poster.BackgroundTransparency=1 poster.ScaleType=Enum.ScaleType.Fit poster.Parent=view
 local loading=UI.text(view,"",UDim2.fromOffset(12,12),UDim2.new(1,-24,0,48),14,Color3.new(1,1,1))loading.Name="Loading"loading.ZIndex=2
 local language,zoom,guideProvider="th",1,selected
 local function layout()
  local width=math.max(1,view.AbsoluteSize.X-12)*zoom
  local height=width*guides[guideProvider][language].ratio
  poster.Size=UDim2.fromOffset(width,height)
  view.CanvasSize=UDim2.fromOffset(width+4,height+4)
  zoomText.Text=tostring(math.floor(zoom*100+.5)).."%"
  UI.enabled(minus,zoom>1)UI.enabled(plus,zoom<3)
 end
 local function choose(key)
  language=key zoom=1 view.CanvasPosition=Vector2.zero
  poster.Image=guides[guideProvider][key].image
  title.Text="HOW TO · "..(guideProvider=="direct"and "Direct Live"or "Tikkies")
  loading.Text=key=="th"and "กำลังโหลดรูปคู่มือ…"or "Loading guide…"
  loading.Visible=not poster.IsLoaded
  UI.select(thai,key=="th")UI.select(english,key=="en")layout()
  local asset=poster.Image
  task.spawn(function()
   pcall(function()game:GetService("ContentProvider"):PreloadAsync({asset})end)
   if poster.Image==asset then
    loading.Visible=not poster.IsLoaded
    if loading.Visible then loading.Text=key=="th"and "ยังโหลดรูปไม่ได้ ลองเปิดคู่มือใหม่อีกครั้ง"or "Image unavailable. Please reopen the guide to retry."end
   end
  end)
 end
 local function resizeZoom(value)
  local previous=zoom zoom=math.clamp(value,1,3)
  local position=view.CanvasPosition
  layout()view.CanvasPosition=position*(zoom/previous)
 end
 poster:GetPropertyChangedSignal("IsLoaded"):Connect(function()loading.Visible=not poster.IsLoaded end)
 view:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
 open.Activated:Connect(function()guideProvider=selected choose(language)modal.Enabled=true layout()end)
 thai.Activated:Connect(function()choose("th")end)english.Activated:Connect(function()choose("en")end)
 plus.Activated:Connect(function()resizeZoom(zoom+.25)end)minus.Activated:Connect(function()resizeZoom(zoom-.25)end)
 fit.Activated:Connect(function()resizeZoom(1)view.CanvasPosition=Vector2.zero end)
 close.Activated:Connect(function()modal.Enabled=false end)shade.Activated:Connect(function()modal.Enabled=false end)
 page:GetPropertyChangedSignal("Visible"):Connect(function()if not page.Visible then modal.Enabled=false end end)
 player:GetAttributeChangedSignal("StreamerMenuOpen"):Connect(function()if not player:GetAttribute("StreamerMenuOpen")then modal.Enabled=false end end)
end
