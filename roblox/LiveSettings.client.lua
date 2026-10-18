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
