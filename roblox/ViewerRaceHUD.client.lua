local Players=game:GetService("Players")local RS=game:GetService("ReplicatedStorage")local RunService=game:GetService("RunService")
local player=Players.LocalPlayer local folder=workspace:WaitForChild("TikkiesDemoNPCs")local control=RS:WaitForChild("ViewerRaceControl")
local UI=require(RS:WaitForChild("StreamerUI"))local C=UI.colors local page=UI.page("Race")
local hud=Instance.new("Frame")hud.Name="RaceStrip"hud.AnchorPoint=Vector2.new(.5,1)hud.Position=UDim2.new(.5,0,1,-16)hud.Size=UDim2.fromOffset(420,66)hud.BackgroundColor3=C.bg hud.BackgroundTransparency=.07 hud.BorderSizePixel=0 hud.Parent=UI.hud UI.corner(hud,15)UI.stroke(hud,C.line,.45)
local hudPhase=UI.text(hud,"Waiting for racers",UDim2.fromOffset(14,9),UDim2.new(1,-143,0,24),15,C.text,true)hudPhase.TextWrapped=false hudPhase.TextTruncate=Enum.TextTruncate.AtEnd
local hudCount=UI.text(hud,"ROUND 1 · 0 RACERS",UDim2.fromOffset(14,36),UDim2.new(1,-143,0,20),10,C.muted)hudCount.TextWrapped=false hudCount.TextTruncate=Enum.TextTruncate.AtEnd
local quickStart=UI.button(hud,"START",UDim2.new(1,-122,0,12),UDim2.fromOffset(108,42),"primary")quickStart.Name="QuickStart"
UI.section(page,"Race at your pace","Add test racers or connect your audience, then start when you are ready.")
local summary=UI.card(page,118)summary.Name="RaceSummary"
local phaseLabel=UI.text(summary,"Waiting for racers",UDim2.fromOffset(18,13),UDim2.new(1,-36,0,31),24,C.text,true)
local countLabel=UI.text(summary,"",UDim2.fromOffset(18,52),UDim2.new(1,-36,0,24),13,C.mint,true)
local info=UI.text(summary,"",UDim2.fromOffset(18,82),UDim2.new(1,-36,0,24),12,C.muted)
local actions=UI.card(page,82)actions.Name="RaceActions"
local start=UI.button(actions,"Start race",UDim2.fromOffset(16,19),UDim2.new(.5,-24,0,44),"primary")start.Name="StartRace"
local test=UI.button(actions,"+ Add test racers",UDim2.new(.5,8,0,19),UDim2.new(.5,-24,0,44))test.Name="OpenTest"
test.Activated:Connect(function()UI.open("Test")end)
local rosterTitle=UI.section(page,"Racers","Current order, lap and running speed.")
local rosterCard=UI.card(page,88)rosterCard.Name="RacerList"local empty=UI.text(rosterCard,"No racers yet. Open Test to add one without going LIVE.",UDim2.fromOffset(16,12),UDim2.new(1,-32,0,60),13,C.muted)
local rowViews={}
local resetCard=UI.card(page,106)resetCard.Name="ResetCard"
UI.text(resetCard,"Start fresh",UDim2.fromOffset(16,11),UDim2.new(1,-32,0,24),14,C.text,true)
UI.text(resetCard,"Clear all racers and begin a new round.",UDim2.fromOffset(16,39),UDim2.new(1,-188,0,48),12,C.muted)
local reset=UI.button(resetCard,"Reset round",UDim2.new(1,-165,0,48),UDim2.fromOffset(149,38),"danger")reset.Name="ResetRace"
local canStart=false local requestAt=0 local confirmUntil=0
local function startRace()if not canStart or os.clock()-requestAt<1 then return end requestAt=os.clock()control:FireServer("start")UI.close()end
start.Activated:Connect(startRace)quickStart.Activated:Connect(startRace)
reset.Activated:Connect(function()
 if os.clock()<confirmUntil then control:FireServer("reset")confirmUntil=0 reset.Text="Reset round"UI.toast("Starting a fresh round…")
 else confirmUntil=os.clock()+5 reset.Text="Confirm reset"UI.toast("Press Confirm reset to clear every racer.",true)task.delay(5,function()if os.clock()>=confirmUntil then reset.Text="Reset round"end end)end
end)
local function models()
 local list={}for _,m in folder:GetChildren()do local h=m:FindFirstChildOfClass("Humanoid")if m:GetAttribute("OwnerRobloxId")==tostring(player.UserId)and h and h.Health>0 then table.insert(list,m)end end
 table.sort(list,function(a,b)local ar,br=a:GetAttribute("RaceRank")or 999,b:GetAttribute("RaceRank")or 999 if ar~=br then return ar<br end return(a:GetAttribute("RaceSlot")or 0)<(b:GetAttribute("RaceSlot")or 0)end)return list
end
local function updateRows(list)
 local keep={}empty.Visible=#list==0 rosterCard.Size=UDim2.new(1,0,0,#list==0 and 88 or 20+#list*54)
 for i,m in list do
  keep[m]=true local row=rowViews[m]
  if not row then
   local frame=Instance.new("Frame")frame.BackgroundTransparency=1 frame.Size=UDim2.new(1,-28,0,50)frame.Parent=rosterCard
   local rank=UI.text(frame,"",UDim2.new(),UDim2.fromOffset(25,50),13,C.gold,true)
   local image=Instance.new("ImageLabel")image.Position=UDim2.fromOffset(31,7)image.Size=UDim2.fromOffset(36,36)image.BackgroundColor3=C.raised image.Image="rbxthumb://type=AvatarHeadShot&id="..tostring(m:GetAttribute("RobloxId")or 1).."&w=150&h=150"image.Parent=frame UI.corner(image,18)
   local name=UI.text(frame,"",UDim2.fromOffset(79,4),UDim2.new(1,-166,0,22),13,C.text,true)name.TextWrapped=false name.TextTruncate=Enum.TextTruncate.AtEnd
   local meta=UI.text(frame,"",UDim2.fromOffset(79,26),UDim2.new(1,-166,0,17),10,C.muted)
   local speed=UI.text(frame,"",UDim2.new(1,-83,0,9),UDim2.fromOffset(83,31),12,C.mint,true)speed.TextXAlignment=Enum.TextXAlignment.Right
   row={frame=frame,rank=rank,name=name,meta=meta,speed=speed}rowViews[m]=row
  end
  row.frame.Position=UDim2.fromOffset(14,10+(i-1)*54)row.rank.Text=tostring(m:GetAttribute("RaceRank")or i)
  row.name.Text=m:GetAttribute("ViewerRobloxUsername")or m:GetAttribute("ViewerUsername")or m.Name
  local state=m:GetAttribute("RaceState")or "Waiting"row.meta.Text=state=="Running"and("LAP "..(m:GetAttribute("RaceLap")or 1).." / "..(m:GetAttribute("RaceLaps")or 2))or state
  row.speed.Text=math.floor((m:GetAttribute("RouteSpeed")or 0)*(player:GetAttribute("ViewerMetersPerStud")or .28)*3.6+.5).." km/h"
 end
 for m,row in rowViews do if not keep[m]then row.frame:Destroy()rowViews[m]=nil end end
end
-- Only the countdown digits overlay the race during the finishing window.
local TweenService=game:GetService("TweenService")
local finishBanner=Instance.new("Frame")
finishBanner.Name="FinishCountdown" finishBanner.AnchorPoint=Vector2.new(.5,0)
finishBanner.Position=UDim2.fromScale(.5,.12) finishBanner.Size=UDim2.fromOffset(160,130)
finishBanner.BackgroundTransparency=1 finishBanner.BorderSizePixel=0
finishBanner.Visible=false finishBanner.Parent=UI.hud
local finishNumber=Instance.new("TextLabel")
finishNumber.Name="Seconds" finishNumber.Size=UDim2.fromScale(1,1)
finishNumber.BackgroundTransparency=1 finishNumber.BorderSizePixel=0
finishNumber.Text="10" finishNumber.Font=Enum.Font.GothamBlack finishNumber.TextSize=92
finishNumber.TextColor3=Color3.new(1,1,1)
finishNumber.TextStrokeColor3=Color3.fromRGB(45,30,12) finishNumber.TextStrokeTransparency=.25
finishNumber.TextXAlignment=Enum.TextXAlignment.Center
finishNumber.TextYAlignment=Enum.TextYAlignment.Center finishNumber.Parent=finishBanner
local finishGradient=Instance.new("UIGradient")
finishGradient.Rotation=90
finishGradient.Color=ColorSequence.new({
 ColorSequenceKeypoint.new(0,Color3.fromRGB(255,255,255)),
 ColorSequenceKeypoint.new(.45,Color3.fromRGB(255,240,185)),
 ColorSequenceKeypoint.new(1,Color3.fromRGB(255,189,65)),
})
finishGradient.Parent=finishNumber
local finishScale=Instance.new("UIScale") finishScale.Parent=finishNumber
local finishTick=nil local finishTween=nil

local function refresh()
 local count=player:GetAttribute("ViewerRaceCount")or 0 local capacity=player:GetAttribute("ViewerRaceCapacity")or 100 local phase=player:GetAttribute("ViewerRacePhase")or "Lobby"local round=player:GetAttribute("ViewerRaceRound")or 1 local laps=player:GetAttribute("ViewerRaceLaps")or 2
 local stepSeconds=phase=="Countdown"and math.max(.1,player:GetAttribute("ViewerRaceCountdownStepSeconds")or 2)or 1
 local remaining=math.max(0,math.ceil(((player:GetAttribute("ViewerRacePhaseEndsAt")or 0)-workspace:GetServerTimeNow())/stepSeconds))
 local finishEndsAt=player:GetAttribute("ViewerRaceFinishEndsAt")or 0
 local finishSeconds=math.max(0,finishEndsAt-workspace:GetServerTimeNow())
 local finishing=phase=="Running" and finishEndsAt>0
 finishBanner.Visible=finishing and not player:GetAttribute("AwardCutsceneActive")
 local tick=math.ceil(finishSeconds)
 if finishBanner.Visible then
  finishNumber.Text=tostring(tick)
  if finishTick~=tick then
   finishTick=tick
   if finishTween then finishTween:Cancel() end
   finishScale.Scale=1.16
   finishTween=TweenService:Create(finishScale,TweenInfo.new(.24,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1})
   finishTween:Play()
  end
 else
  finishTick=nil
  if finishTween then finishTween:Cancel() finishTween=nil end
  finishScale.Scale=1
 end
 local heading=phase=="Lobby"and(count>0 and "Ready to race"or "Waiting for racers")or phase=="Countdown"and("Starting in "..remaining)or phase=="Running"and "Race in progress"or "Round finished"
 phaseLabel.Text=heading hudPhase.Text=heading countLabel.Text=count.." / "..capacity.." racers  ·  "..laps.." laps  ·  Round "..round
 hudCount.Text=hud.AbsoluteSize.X<300 and("R"..round.."  ·  "..count.." / "..capacity)or("ROUND "..round.."  ·  "..laps.." LAPS  ·  "..count.." / "..capacity.." RACERS")
 info.Text=phase=="Results"and("Winner: "..(player:GetAttribute("ViewerRaceWinner")or "—"))or phase=="Running"and "Late arrivals join behind the last racer."or phase=="Countdown"and "Get ready. The race is about to begin."or "The race starts only when you press Start."
 canStart=phase=="Lobby"and count>0 UI.enabled(start,canStart)UI.enabled(quickStart,canStart)
 start.Text=canStart and "Start race  →"or phase=="Lobby"and "Add a racer first"or phase=="Countdown"and "Starting…"or phase=="Running"and "Race running"or "Showing results"
 quickStart.Text=canStart and "START  →"or phase=="Running"and "RACING"or phase=="Countdown"and tostring(remaining)or "WAITING"
 if page.Visible then updateRows(models())end
end
local function resize()
 local camera=workspace.CurrentCamera
 if camera then hud.Position=UDim2.new(.5,0,1,-16)hud.Size=UDim2.fromOffset(math.clamp(camera.ViewportSize.X-484,240,360),66)end
end
resize()if workspace.CurrentCamera then workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(resize)end
local elapsed=0 RunService.Heartbeat:Connect(function(dt)elapsed+=dt if elapsed>=.2 then elapsed=0 refresh()end end)page:GetPropertyChangedSignal("Visible"):Connect(refresh)refresh()

