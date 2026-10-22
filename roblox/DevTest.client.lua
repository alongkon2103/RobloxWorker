local Players=game:GetService("Players")local UIS=game:GetService("UserInputService")local RS=game:GetService("ReplicatedStorage")local RunService=game:GetService("RunService")
local player=Players.LocalPlayer local Events=require(RS:WaitForChild("RaceEventConfig"))local Catalog=require(RS:WaitForChild("DevTestCatalog"))local keys=Catalog.list(Events)
local octopusSlot=table.find(keys,"octopus")
if octopusSlot then table.insert(keys,octopusSlot,"__trip")else table.insert(keys,"__trip")end
local UI=require(RS:WaitForChild("StreamerUI"))local C=UI.colors local page=UI.page("Test")local messageUntil=0
local labels={octopus="Octopus",shield="Shield",gojo="Gojo / Purple",fly="Fly",speed_boost="Speed Boost",rocket="Rocket",rainbow_cat="Rainbow Cat",naruto="Naruto",goku="Goku",asta="Asta"}
UI.section(page,"Racer events","Use events on the LIVE viewer or test racer you are watching. Octopus keeps its random-target rule.")
local addCard=UI.card(page,92)addCard.Name="AddRacerCard"
UI.text(addCard,"Add a test racer",UDim2.fromOffset(16,10),UDim2.new(1,-180,0,28),15,C.text,true)
UI.text(addCard,"No LIVE connection needed. Shortcut: K",UDim2.fromOffset(16,43),UDim2.new(1,-32,0,32),11,C.muted)
local add=UI.button(addCard,"+ Add racer",UDim2.new(1,-160,0,16),UDim2.fromOffset(144,40),"primary")add.Name="AddRacer"
local targetCard=UI.card(page,98)targetCard.Name="TestTarget"
local avatar=Instance.new("ImageLabel")avatar.BackgroundColor3=C.raised avatar.BorderSizePixel=0 avatar.Position=UDim2.fromOffset(16,20)avatar.Size=UDim2.fromOffset(56,56)avatar.Parent=targetCard UI.corner(avatar,28)
UI.text(targetCard,"VIEWED RACER",UDim2.fromOffset(86,12),UDim2.new(1,-102,0,20),10,C.mint,true)
local targetName=UI.text(targetCard,"No racer selected",UDim2.fromOffset(86,36),UDim2.new(1,-102,0,24),16,C.text,true)
local Trip=require(RS:WaitForChild("RaceTrip"))local Stack=require(RS:WaitForChild("RaceEventStack"))
local targetHelp=UI.text(targetCard,"Use Q / E to choose a racer.",UDim2.fromOffset(86,65),UDim2.new(1,-102,0,20),11,C.muted)
UI.section(page,"Gift playground","Press 1–9, 0 for Trip, or - for Octopus. You can also choose an action below. Each number always selects the same action.")
local grid=Instance.new("Frame")grid.Name="EventButtons"grid.BackgroundTransparency=1 grid.Size=UDim2.new(1,0,0,240)grid.Parent=page
local eventButtons={}for slot=1,#keys do local b=UI.button(grid,"",UDim2.new(),UDim2.fromOffset(100,70))b.Name="Event"..slot b.TextWrapped=true b.TextSize=13 eventButtons[slot]=b end
local status=UI.notice(page,"K  Add racer   •   1–9 / 0  Actions   •   -  Octopus")
local errors={trip_not_running="Start the race before testing a fall.",trip_not_available="Wait for ordinary running, without a form or obstacle action.",dev_target_missing="Choose a racer with Q / E first.",dev_actor_not_found="Choose one of your room racers.",dev_scope_conflict="This room is using a LIVE race. Use a fresh test round to add test racers.",dev_not_allowed="Testing is disabled for this room.",dev_cooldown="Please wait a moment.",dev_join_pending="A racer is already loading…",dev_live_not_ready="Please wait for the connection to finish.",viewer_limit="This room has reached its racer limit.",round_finishing="Wait until this round has finished.",avatar_unavailable="Could not load this avatar. Please try again."}
local function ownModels()
 local list={}local folder=workspace:FindFirstChild("TikkiesDemoNPCs")if not folder then return list end
 for _,m in folder:GetChildren()do local h=m:FindFirstChildOfClass("Humanoid")if m:GetAttribute("OwnerRobloxId")==tostring(player.UserId)and h and h.Health>0 and m:FindFirstChild("HumanoidRootPart")then table.insert(list,m)end end return list
end
local function target()
 local models=ownModels()
 if player:GetAttribute("ViewerCameraMode")~="Free"and not player:GetAttribute("ViewerCameraBusy")then local actor=player:GetAttribute("ViewerSpectatedActor")for _,m in models do if m:GetAttribute("ActorKey")==actor then return m end end end
 local camera=workspace.CurrentCamera if not camera then return end local best,score local radius=math.min(camera.ViewportSize.X,camera.ViewportSize.Y)*.18
 for _,m in models do local point,visible=camera:WorldToViewportPoint(m.HumanoidRootPart.Position+Vector3.yAxis)local delta=(Vector2.new(point.X,point.Y)-camera.ViewportSize*.5).Magnitude if visible and point.Z>0 and delta<=radius and(not score or delta<score)then best=m score=delta end end return best
end
local function tell(text,error)status.Text=text messageUntil=os.clock()+3 UI.toast(text,error)end
local remote=RS:WaitForChild("DevTestControl")
local Queue=require(RS:WaitForChild("DevTestRequestQueue"))
local queue
queue=Queue.new(function(item)
 return remote:InvokeServer(item.action,item.actor,item.key)
end,function(item,ok,result)
 if not ok or type(result)~="table"then tell("Test request failed. Please try again.",true)return end
 if not result.ok then
  -- A removed racer/finished round must never send old gifts into a new round.
  if result.code~="dev_target_expired" then tell(errors[result.code]or result.code or "Test failed.",true)end
  return
 end
 if item.action=="spawn"then
  task.spawn(function()
   for _=1,50 do
    if queue.closed then return end
    for _,m in ownModels()do
     if m:GetAttribute("ActorKey")==result.actorKey then player:SetAttribute("DevTestFocusActor",result.actorKey)return end
    end
    task.wait(.1)
   end
  end)
 end
end,math.max(.02,remote:GetAttribute("RequestInterval")or .2)+.02)
local function request(action,actor,key)
 local item={action=action,actor=actor,key=key}
 if action~="spawn"then
  local captured
  for _,m in ownModels()do if m:GetAttribute("ActorKey")==actor then captured=m break end end
  if not captured then return end
  local run,generation=captured:GetAttribute("RunId"),captured:GetAttribute("Generation")
  item.valid=function()
   return captured.Parent~=nil and captured:GetAttribute("RunId")==run
    and captured:GetAttribute("Generation")==generation
    and player:GetAttribute("ViewerRacePhase")~="Results"
  end
 end
 queue:push(item)
end
script.Destroying:Connect(function()queue:destroy()end)
local function fire(index)
 local key=keys[index]if not key then return end local m=target()if not m then tell("Choose a racer with Q / E first.",true)return end
 if key=="__trip" then request("trip",m:GetAttribute("ActorKey"))
 else request("event",m:GetAttribute("ActorKey"),key) end
end
for slot,b in eventButtons do b.Activated:Connect(function()fire(slot)end)end
add.Activated:Connect(function()request("spawn")end)
local function updateCatalog()
 for slot,b in eventButtons do
  local key=keys[slot] local e=key and Events[key]
  if key=="__trip" then b.Text=slot.."   Trip / Fall\nOrdinary running · 1s"
  elseif e then
   local detail
   if e.Kind=="Debuff" then detail="Random racer · -10% speed · "..e.Duration.."s"
   elseif e.Kind=="Defense" then detail="Protection · "..e.Duration.."s"
   elseif e.Kind=="Attack" then detail="Purple · knockdown "..e.StunDuration.."s"
   elseif e.StackMode=="TimedFlatSpeed" then detail="+"..e.SpeedBonus.." speed · "..e.Duration.."s"
   elseif e.StackMode=="TimedMultiplier" then detail="×"..(e.SpeedMultiplier or 1).." · "..(e.Duration or 0).."s · max "..(e.MaxSpeed or "—")
   elseif e.StackMode=="RoundMultiplier" then detail="×"..(e.SpeedMultiplier or 1).." per gift · this round"
   else detail="×"..(e.SpeedMultiplier or 1).." speed · "..(e.Duration or 0).."s" end
   if e.RoundSpeedPerGift then detail..=" · +"..e.RoundSpeedPerGift.." this round / gift"end
   b.Text=(key=="octopus"and "-"or tostring(slot)).."   "..(labels[key]or key:gsub("_"," ")).."\n"..detail
  else b.Text="" end
  b.Visible=key~=nil
 end
end
local digit={[Enum.KeyCode.One]=1,[Enum.KeyCode.Two]=2,[Enum.KeyCode.Three]=3,[Enum.KeyCode.Four]=4,[Enum.KeyCode.Five]=5,[Enum.KeyCode.Six]=6,[Enum.KeyCode.Seven]=7,[Enum.KeyCode.Eight]=8,[Enum.KeyCode.Nine]=9,[Enum.KeyCode.Zero]=10,
 [Enum.KeyCode.KeypadOne]=1,[Enum.KeyCode.KeypadTwo]=2,[Enum.KeyCode.KeypadThree]=3,[Enum.KeyCode.KeypadFour]=4,[Enum.KeyCode.KeypadFive]=5,[Enum.KeyCode.KeypadSix]=6,[Enum.KeyCode.KeypadSeven]=7,[Enum.KeyCode.KeypadEight]=8,[Enum.KeyCode.KeypadNine]=9,[Enum.KeyCode.KeypadZero]=10}
UIS.InputBegan:Connect(function(input,processed)
 if processed or UIS:GetFocusedTextBox()or not player:GetAttribute("DevTestAvailable")or(UI.isOpen()and not UI.isOpen("Test"))then return end
 if input.KeyCode==Enum.KeyCode.K then request("spawn")elseif input.KeyCode==Enum.KeyCode.Minus then fire(table.find(keys,"octopus"))elseif digit[input.KeyCode]then fire(digit[input.KeyCode])end
end)
local elapsed=0
RunService.Heartbeat:Connect(function(dt)
 elapsed+=dt if elapsed<.2 then return end elapsed=0 local available=player:GetAttribute("DevTestAvailable")==true UI.enabled(add,available)
 if not page.Visible then return end local m=target()
 local primary=m and Stack.evaluate(m,workspace:GetServerTimeNow())
 targetName.Text=m and(m:GetAttribute("ViewerDisplayName")or m:GetAttribute("ViewerUsername")or "Viewer")or "No racer selected"
 targetHelp.Text=m and "Boosts target this racer. Octopus picks a random racer."or "Use Q / E or aim at a racer in Free Cam."
 local id=m and tonumber(m:GetAttribute("RobloxId"))or 0
 local portrait=id and id>0 and("rbxthumb://type=AvatarHeadShot&id="..tostring(id).."&w=150&h=150")or ""
 if avatar.Image~=portrait then avatar.Image=portrait end
 for slot,b in eventButtons do
  local enabled=available and m~=nil and keys[slot]~=nil
  if enabled and keys[slot]=="__trip" then enabled=Trip.canStart(m,m:GetAttribute("RouteDistance")or -14,primary,workspace:GetServerTimeNow()) end
  UI.enabled(b,enabled)
 end
 if os.clock()>messageUntil then status.Text=available and "K  Add racer   •   1–9 / 0  Actions   •   -  Octopus"or "Testing is not available for this room."end
end)
local function resize()local columns=page.AbsoluteSize.X<420 and 1 or 3 for slot,b in eventButtons do local col=(slot-1)%columns local row=math.floor((slot-1)/columns)b.Position=UDim2.new(col/columns,col==0 and 0 or 6,0,row*80)b.Size=UDim2.new(1/columns,columns==1 and 0 or -6,0,70)end grid.Size=UDim2.new(1,0,0,math.ceil(#keys/columns)*80-10)end
page:GetPropertyChangedSignal("AbsoluteSize"):Connect(resize)updateCatalog()task.defer(resize)
