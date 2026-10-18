local Players=game:GetService("Players")local RS=game:GetService("ReplicatedStorage")
local player=Players.LocalPlayer local remote=RS:WaitForChild("LiveSettingsControl")
local UI=require(RS:WaitForChild("StreamerUI"))local C=UI.colors local page=UI.page("Live")
local selected=player:GetAttribute("LiveProvider") or "direct"local joinMode=player:GetAttribute("PreferredJoinMode") or "at"local pending=false
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
local errors={defaults_universe_required="This game connection needs an update. Contact the map owner.",defaults_not_ready="Gift defaults are not ready. Publish them in Tikkies Admin first.",defaults_access_denied="Gift defaults could not be verified. Contact the map owner.",defaults_universe_forbidden="Gift defaults belong to a different game.",previous_connection_closing="Closing your previous connection. Please try again shortly.",invalid_username="Enter a TikTok username, not a link (2–24 characters).",owner_busy="Your previous connection is still closing. Please try again shortly.",live_busy="This TikTok account is connected in another room.",network_error="Connection interrupted. Trying again…",bridge_unauthorized="The game connection could not be verified. Contact the map owner.",bridge_not_configured="The map connection is not configured yet.",tikkies_unavailable="Tikkies is not available yet. Check your map connection.",tikkies_not_configured="The Tikkies map connection has not been set up.",tikkies_unauthorized="Tikkies could not verify this map connection.",tikkies_network_error="Could not reach Tikkies. Retrying…",tikkies_registration_failed="Preparing the Tikkies map connection…",reset_retrying="Preparing a fresh round. Please wait…",handler_failed="Could not connect. Please try again.",disconnect_first="Disconnect before changing your connection.",join_mode_update_failed="Could not update the join format. Please try again."}
local states={disconnected="Not connected",connecting="Connecting…",queued="Waiting to connect…",live="Connected",offline="Waiting for your TikTok LIVE",retrying="Reconnecting…",error="Connection needs attention",resetting="Preparing the next round…"}
local function refresh()
 local enabled=player:GetAttribute("LiveEnabled")==true local activeProvider=player:GetAttribute("LiveProvider") or "direct"local activeName=player:GetAttribute("LiveUsername") or ""local phase=player:GetAttribute("LiveStatus") or "disconnected"
 local same=enabled and activeProvider==selected and(selected=="tikkies" or activeName==input.Text:gsub("^@",""):lower())
 UI.select(direct,selected=="direct")UI.select(tikkies,selected=="tikkies",C.purple)
 username.Visible=selected=="direct"joinCard.Visible=selected=="direct"
 tikkiesCard.Visible=selected=="tikkies"
 help.Text=selected=="direct"and "Read chat and gifts from your TikTok LIVE."or "Use the viewers and events you set up in Tikkies."
 local save=player:GetAttribute("UsernameSaveStatus")saveHint.Text=save=="saved"and "✓ Username saved"or save=="saving"and "Saving…"or save=="session"and "Remembered for this session"or "Saved automatically as you type"
 for key,b in modes do UI.select(b,key==joinMode)UI.enabled(b,not pending)UI.select(b,key==joinMode)end
 joinHelp.Text=joinMode=="at"and "Viewers type @RobloxUsername in chat."or joinMode=="plain"and "Viewers type RobloxUsername directly in chat."or "Viewers can type @RobloxUsername or RobloxUsername."
 status.Text=(states[phase]or phase)..(enabled and "  ·  "..(activeProvider=="direct"and "Direct Live"or "Tikkies")or "")status.TextColor3=phase=="live"and C.mint or phase=="error"and C.red or C.text
 local errorCode=player:GetAttribute("LiveError")detail.Text=errors[errorCode]or(enabled and "New viewers and gifts will appear in your race automatically."or (selected=="direct"and "Enter your TikTok name above, then connect."or "Ready to use your Tikkies viewer and gift settings."))
 local available=selected~="tikkies"or player:GetAttribute("TikkiesAvailable")==true
 if not available then detail.Text=errors[player:GetAttribute("LiveTikkiesError")]or errors.tikkies_unavailable end
 connect.Text=pending and "Please wait…"or same and "Disconnect"or enabled and "Switch connection"or "Connect LIVE"
 connect:SetAttribute("Kind",same and "danger"or "primary")UI.enabled(connect,not pending and available)
end
for mode,b in modes do b.Activated:Connect(function()if pending then return end joinMode=mode remote:FireServer("set_join_mode",mode)refresh()end)end
direct.Activated:Connect(function()if not pending then selected="direct"refresh()end end)tikkies.Activated:Connect(function()if not pending then selected="tikkies"refresh()end end)
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
player:GetAttributeChangedSignal("PreferredJoinMode"):Connect(function()joinMode=player:GetAttribute("PreferredJoinMode")or "at"refresh()end)
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
