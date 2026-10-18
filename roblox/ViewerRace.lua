local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Presentation = require(script.Parent.RacePresentation)
local Motion = require(script.Parent.ViewerMotion)
local AwardService = require(script.Parent.AwardCeremonyService)
local EventStack=require(ReplicatedStorage.RaceEventStack)
local EventConfig=require(ReplicatedStorage.RaceEventConfig)
local RaceAction=require(ReplicatedStorage.RaceAction)
local Obstacles=require(script.Parent.RaceObstacles)
local RacePath=require(ReplicatedStorage.RacePath)
local GojoAbility=require(script.Parent.GojoAbility)
local TripState=require(script.Parent.TripState)
local pathRemote=ReplicatedStorage:FindFirstChild("ViewerPathSnapshot") or Instance.new("RemoteEvent")
pathRemote.Name="ViewerPathSnapshot" pathRemote.Parent=ReplicatedStorage
local WinResults=require(script.Parent.TopWinResults)
local Http=game:GetService('HttpService')
local Race = {}
Race.__index = Race
local owned = {}
local control = ReplicatedStorage:FindFirstChild("ViewerRaceControl") or Instance.new("RemoteEvent")
control.Name = "ViewerRaceControl"
control.Parent = ReplicatedStorage
pcall(function() PhysicsService:RegisterCollisionGroup("ViewerRacers") end)
PhysicsService:CollisionGroupSetCollidable("ViewerRacers","ViewerRacers",false)

local function alive(entry)
	return entry.model.Parent and entry.humanoid.Health > 0 and entry.model:FindFirstChild("HumanoidRootPart")
end
function Race.new(owner,map,config)
	local gates = map.Checkpoints:GetChildren()
	table.sort(gates,function(a,b) return a:GetAttribute("Index") < b:GetAttribute("Index") end)
	assert(#gates >= 2,"Viewer race needs an ordered route")
	local self = setmetatable({cornerLimits={},owner=owner,map=map,config=config,gates=gates,entries={},participants={},
		winRaceId=Http:GenerateGUID(false),phase="Lobby",round=owner:GetAttribute("ViewerRaceRound") or 1,finished=0,elapsed=0,deadline=0,cumulative={0},length=0},Race)
	for i=1,#gates do
		assert(gates[i]:GetAttribute("Index")==i,"Checkpoint route must be contiguous")
		local nextGate = gates[i % #gates+1]
		self.length += (nextGate.Position-gates[i].Position).Magnitude
		self.cumulative[i+1] = self.length
	end
	for i=1,#gates do
		local a=gates[(i-2)%#gates+1].Position
		local b=gates[i].Position
		local c=gates[i%#gates+1].Position
		local ab=(b-a)*Vector3.new(1,0,1) local bc=(c-b)*Vector3.new(1,0,1)
		local cross=math.abs(ab:Cross(bc).Y)
		if cross>.001 then
			local radius=ab.Magnitude*bc.Magnitude*((c-a)*Vector3.new(1,0,1)).Magnitude/(2*cross)
			self.cornerLimits[i]=math.sqrt(math.max(2,radius-5)*(config.CornerLateralAcceleration or 180))
		end
	end
	self.path=RacePath.new(gates,config)
	self.laps=math.max(1,math.floor(config.Laps or 1))
	if config.PathDrivenMovement then self.length=self.path.length self.cumulative=self.path.cumulative end
	self.totalLength=self.length*self.laps
	self.obstacles=self.config.ObstaclesEnabled~=false and map:FindFirstChild("RaceObstacles") and map.RaceObstacles:GetChildren() or {}
	self.snapshotElapsed=0
	owned[owner] = self
	self:sync()
	self.connection = RunService.Heartbeat:Connect(function(dt)
		self.frameAt=workspace:GetServerTimeNow()
		-- Advance checkpoints before steering, even when a fast runner crosses several per frame.
		if self.phase=="Running" and (not self.finishDeadline or self.frameAt<self.finishDeadline) then
			local now=workspace:GetServerTimeNow()
			for _,entry in self.participants do
				if entry.model:GetAttribute("RaceState")=="Running" then
					self:updateRunner(entry,now)
					if entry.model:GetAttribute("RaceState")=="Running" then self:steer(entry,now,dt) end
				elseif entry.model:GetAttribute("RaceState")=="Finished" then
					self:driveFinishRun(entry,now,dt)
				end
			end
		end
		if self.phase=="Running" then GojoAbility.update(self,self.frameAt) end
		self.snapshotElapsed+=dt
		if self.snapshotElapsed>=.05 then self.snapshotElapsed=0 self:publishPath() end
		self.elapsed+=dt
		if self.elapsed>=.1 or (self.phase=="Running" and self.finished>0 and self.finishDeadline and self.frameAt>=self.finishDeadline) then self.elapsed=0 self:step(true) end
	end)
	return self
end
function Race:sync()
	if not self.owner.Parent then return end
	local count,active=0,0
	for _,entry in self.entries do if alive(entry) then count+=1 end end
	for _,entry in self.participants do if alive(entry) and entry.model:GetAttribute("RaceState")=="Running" then active+=1 end end
	self.owner:SetAttribute("ViewerRacePhase",self.phase)
	self.owner:SetAttribute("ViewerRacePhaseEndsAt",self.deadline)
	self.owner:SetAttribute("ViewerRaceCountdownStepSeconds",self.config.CountdownStepSeconds or 1)
	self.owner:SetAttribute("ViewerRaceFinishEndsAt",self.phase=="Running" and self.finishDeadline or 0)
	self.owner:SetAttribute("ViewerRaceFinishWaitSeconds",self.config.FinishWaitSeconds or 10)
	self.owner:SetAttribute("ViewerRaceRound",self.round)
	self.owner:SetAttribute("ViewerRaceCount",count)
	self.owner:SetAttribute("ViewerRaceCapacity",self.config.MaxViewersPerOwner)
	self.owner:SetAttribute("ViewerRaceSpectate",self.config.AutoFollowRacers)
	self.owner:SetAttribute("ViewerFreeCameraSpeed",self.config.FreeCameraSpeed)
	self.owner:SetAttribute("ViewerRaceActive",active)
	self.owner:SetAttribute("ViewerRaceFinished",self.finished)
	self.owner:SetAttribute("ViewerRaceLaps",self.laps)
	self.owner:SetAttribute("ViewerMetersPerStud",self.config.MetersPerStud or .28)
	self.owner:SetAttribute("ViewerPathRenderDelay",self.config.PathRenderDelay or .08)
end
function Race:ground(entry,gate,position)
	local ignore={entry.model,self.map.Checkpoints}
	local folder=workspace:FindFirstChild("TikkiesDemoNPCs") if folder then table.insert(ignore,folder) end
	if self.map:FindFirstChild("Gameplay") then table.insert(ignore,self.map.Gameplay) end
	for _,player in Players:GetPlayers() do if player.Character then table.insert(ignore,player.Character) end end
	local ray=RaycastParams.new() ray.FilterType=Enum.RaycastFilterType.Exclude ray.FilterDescendantsInstances=ignore
	local hit=workspace:Raycast(Vector3.new(position.X,gate.Position.Y+30,position.Z),Vector3.new(0,-100,0),ray)
	local floor=hit and hit.Position.Y or gate.Position.Y-gate.Size.Y/2
	local low=Presentation.bodyBounds(entry.model)
	return Vector3.new(position.X,floor-low.Y+.08,position.Z)
end
-- Keep the same lane before and after launch instead of squeezing the grid inward.
function Race:laneOffset(entry)
 local columns=self.config.GridColumns or 5
 return ((entry.slot-1)%columns-(columns-1)/2)*(self.config.LaneSpacing or self.config.GridSpacing or 6)
end
function Race:place(entry)
	local root=alive(entry) if not root then return end
	entry.model.PrimaryPart=root
	local start=self.gates[1]
	local forward=(self.gates[2].Position-start.Position)*Vector3.new(1,0,1)
	forward=forward.Unit
	local heading=CFrame.lookAt(start.Position,start.Position+forward)
	local columns=self.config.GridColumns
	local row=math.floor((entry.slot-1)/columns)
	local position=start.Position+heading.RightVector*self:laneOffset(entry)-forward*(14+row*(self.config.GridRowSpacing or self.config.GridSpacing))
	position=self:ground(entry,start,position)
	root.Anchored=true
	entry.humanoid.AutoRotate=false
	entry.humanoid:Move(Vector3.zero)
	entry.model:PivotTo(CFrame.lookAt(position,position+forward))
	root.AssemblyLinearVelocity=Vector3.zero root.AssemblyAngularVelocity=Vector3.zero
end
function Race:add(entry)
	for i=#self.entries,1,-1 do if not alive(self.entries[i]) then table.remove(self.entries,i) end end
	table.insert(self.entries,entry)
	-- Anchored preview rigs can enter FallingDown and retain it when released.
	entry.humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown,false)
	entry.humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll,false)
	entry.humanoid.Sit=false entry.humanoid.PlatformStand=false
	entry.motion=Motion.attach(entry.model,self.config)
	entry.model:SetAttribute("RaceSlot",entry.slot)
	for _,part in entry.model:GetDescendants() do
		if part:IsA("BasePart") then part.CollisionGroup="ViewerRacers" end
	end
	entry.model:SetAttribute("RaceProgress",0)
	entry.model:SetAttribute("RaceLap",1)
	entry.model:SetAttribute("RaceLaps",self.laps)
	entry.model:SetAttribute("RaceRank",nil)
	entry.model:SetAttribute("RaceRound",self.round)
	if self.phase=="Running" then
		self:joinRunning(entry)
	else
		entry.model:SetAttribute("RaceState",self.phase=="Countdown" and "Countdown" or "Waiting")
		self:place(entry)
		entry.humanoid:ChangeState(Enum.HumanoidStateType.Running)
		if self.phase=="Countdown" then
			entry.passed=0 entry.nextGate=1 entry.progress=0
			table.insert(self.participants,entry)
		end
	end
	if self.config.RaceAutoStart and self.phase=="Lobby" and self.deadline==0 then self.deadline=workspace:GetServerTimeNow()+self.config.LobbySeconds end
	self:sync()
end
function Race:joinRunning(entry)
	local now=workspace:GetServerTimeNow()
	local tailDistance
	local start=self.gates[1].Position
	local initialForward=((self.gates[2].Position-start)*Vector3.new(1,0,1)).Unit
	for _,other in self.participants do
		local otherRoot=alive(other)
		if otherRoot and other.model:GetAttribute("RaceState")=="Running" then
			local distance=other.routeDistance or (other.progress or 0)*self.totalLength
			if (other.passed or 0)==0 then distance=(otherRoot.Position-start):Dot(initialForward) end
			tailDistance=tailDistance and math.min(tailDistance,distance) or distance
		end
	end
	local distance=(tailDistance or 0)-(self.config.LateJoinGap or 8)
	local pose,index=self.path:sample(distance,0,0)
	local position,forward,gate=pose.Position,pose.LookVector,self.gates[index]
	entry.passed=distance<0 and 0 or math.floor(distance/self.length)*#self.gates+index
	entry.nextGate=entry.passed%#self.gates+1
	entry.progress=math.max(0,distance/self.totalLength)
	if self.config.PathDrivenMovement then entry.routeDistance=distance end
	local lane=self:laneOffset(entry)
	position+=forward:Cross(Vector3.yAxis)*lane
	position=self:ground(entry,gate,position)
	local root=alive(entry)
	root.Anchored=true entry.model:PivotTo(CFrame.lookAt(position,position+forward))
	entry.model:SetAttribute("PassedCheckpoints",entry.passed)
	entry.model:SetAttribute("RaceProgress",entry.progress)
	table.insert(self.participants,entry)
	self:release(entry,now)
end
function Race:release(entry,now)
	local root=alive(entry) if not root then return end
	-- Gifts queued in the lobby/countdown get their full duration at the starting gun.
	for _,boost in EventConfig do
		local seconds=entry.model:GetAttribute(boost.Attribute.."PendingSeconds") or 0
		if seconds>0 then
			entry.model:SetAttribute(boost.Attribute.."StartedAt",now)
			entry.model:SetAttribute(boost.Attribute.."Until",now+seconds)
			entry.model:SetAttribute(boost.Attribute.."PendingSeconds",nil)
		end
	end
	root.AssemblyLinearVelocity=Vector3.zero root.AssemblyAngularVelocity=Vector3.zero
	if self.config.PathDrivenMovement then
		local start=self.gates[1].Position
		local forward=((self.gates[2].Position-start)*Vector3.new(1,0,1)).Unit
		entry.routeDistance=entry.routeDistance or ((entry.passed or 0)>0 and (entry.progress or 0)*self.totalLength or (root.Position-start):Dot(forward))
		local low=Presentation.bodyBounds(entry.model)
		entry.routeHeight=-low.Y+.08
		entry.routeLane=self:laneOffset(entry)
		local frame=self.path:sample(entry.routeDistance,0,entry.routeHeight)
		entry.startLane=(root.Position-frame.Position):Dot(frame.RightVector)
		entry.model:SetAttribute("PathDriven",true)
		entry.model:SetAttribute("RouteTotalDistance",self.totalLength)
		entry.model:SetAttribute("SlideDepth",entry.humanoid.RigType==Enum.HumanoidRigType.R15 and 1.0 or 1.65)
		entry.model:SetAttribute("RouteHeight",entry.routeHeight)
		entry.model:SetAttribute("RouteLane",entry.routeLane)
		entry.model:SetAttribute("RouteStartLane",entry.startLane)
		root.Anchored=true
	else root.Anchored=false root:SetNetworkOwner(nil) end
	entry.humanoid.Sit=false entry.humanoid.PlatformStand=false
	entry.humanoid:ChangeState(Enum.HumanoidStateType.Running)
	entry.humanoid.AutoRotate=not self.config.PathDrivenMovement entry.humanoid.WalkSpeed=0
	entry.humanoid.UseJumpPower=true entry.humanoid.JumpPower=50
	entry.currentSpeed=0 entry.startedAt=now
	entry.lastGatePosition=root.Position
	entry.lastPosition=root.Position entry.lastMoved=now entry.lastJump=0
	entry.model:SetAttribute("RaceState","Running")
end
function Race:start()
	if self.destroyed or self.phase~="Lobby" then return false end
	local now=workspace:GetServerTimeNow()
	self.finishDeadline=nil
	local participants={} local deadline=now+self.config.CountdownSeconds
	for _,entry in self.entries do
		if alive(entry) then
			table.insert(participants,entry)
			deadline=math.max(deadline,(entry.model:GetAttribute("IntroEndsAt") or 0)+.2)
		end
	end
	if #participants<self.config.MinimumRacers then return false end
	self.participants=participants self.finished=0
	self.phase="Countdown" self.deadline=deadline
	self.owner:SetAttribute("ViewerRaceWinner",nil)
	for _,entry in participants do
		entry.passed=0 entry.nextGate=1 entry.finishOrder=nil entry.progress=0 entry.routeDistance=nil
		entry.model:SetAttribute("RaceState","Countdown")
	end
	self:sync()
	return true
end
function Race:beginRunning()
	self.phase="Running" self.started=workspace:GetServerTimeNow()
	self.deadline=0
	for _,entry in self.participants do self:release(entry,self.started) end
	self:sync()
end
function Race:recover(entry)
	local previous=self.gates[entry.passed>0 and ((entry.passed-1)%#self.gates+1) or 1]
	local position=self:ground(entry,previous,previous.Position)
	local nextGate=self.gates[entry.nextGate]
	local forward=(nextGate.Position-position)*Vector3.new(1,0,1)
	if forward.Magnitude<.1 then forward=self.gates[2].Position-self.gates[1].Position end
	entry.model:PivotTo(CFrame.lookAt(position,position+forward))
	local root=entry.model.HumanoidRootPart
	root.AssemblyLinearVelocity=Vector3.zero root.AssemblyAngularVelocity=Vector3.zero
	entry.lastGatePosition=position
	entry.lastMoved=workspace:GetServerTimeNow() entry.lastPosition=position
	entry.model:SetAttribute("RaceRecoveries",(entry.model:GetAttribute("RaceRecoveries") or 0)+1)
end
-- Keep official results fixed while finishers jog beyond the line.
function Race:beginFinishRun(entry,now)
 local root=alive(entry) if not root then return end
 entry.finishedAt=entry.finishedAt or now
 entry.finishRunSpeed=math.clamp(entry.currentSpeed or self.config.BaseRunSpeed,8,48)
 entry.currentSpeed=entry.finishRunSpeed
 entry.routeDistance=self.totalLength
 entry.routeHeight=entry.routeHeight or -Presentation.bodyBounds(entry.model).Y+.08
 local frame=self.path:sample(self.totalLength,0,entry.routeHeight)
 entry.routeLane=entry.routeLane or (root.Position-frame.Position):Dot(frame.RightVector)
 entry.model:SetAttribute("RouteHeight",entry.routeHeight)
 entry.model:SetAttribute("RouteLane",entry.routeLane)
 entry.model:SetAttribute("FinishRunStartedAt",now)
 entry.model:SetAttribute("FinishRunUntil",self.finishDeadline or now+(self.config.FinishWaitSeconds or 10))
 entry.model:SetAttribute("RouteActionKind",nil)
 entry.model:SetAttribute("RouteActionStart",nil)
 entry.model:SetAttribute("RouteActionEnd",nil)
 entry.model:SetAttribute("RouteJumpAt",nil)
 entry.model:SetAttribute("RouteJumpHeight",nil)
 entry.model:SetAttribute("RouteDistance",entry.routeDistance)
 entry.model:SetAttribute("RouteSpeed",entry.currentSpeed)
 root.Anchored=true entry.humanoid:Move(Vector3.zero)
end
function Race:driveFinishRun(entry,now,dt)
 local root=alive(entry) if not root then return end
 if now>=(entry.model:GetAttribute("FinishRunUntil") or 0) then return end
 local age=math.max(0,now-(entry.model:GetAttribute("FinishRunStartedAt") or now))
 local speed=8+((entry.finishRunSpeed or 8)-8)*math.exp(-age/1.2)
 local previous=entry.currentSpeed or speed
 entry.routeDistance=(entry.routeDistance or self.totalLength)+(previous+speed)*.5*dt
 entry.currentSpeed=speed entry.humanoid.WalkSpeed=speed
 entry.model:SetAttribute("RouteDistance",entry.routeDistance)
 entry.model:SetAttribute("RouteSpeed",speed)
 root.CFrame=self.path:sample(entry.routeDistance,entry.routeLane or 0,entry.routeHeight or 2.8)
end
function Race:updateRunner(entry,now)
	local root=alive(entry)
	if not root then entry.model:SetAttribute("RaceState","DNF") return end
	if self.config.PathDrivenMovement then self:updatePathProgress(entry,now) return end
	local gate=self.gates[entry.nextGate]
	local previous=entry.lastGatePosition or root.Position
	entry.lastGatePosition=root.Position
	local segmentFraction=0
	local function crossed(g)
		local a=g.CFrame:PointToObjectSpace(previous)
		local b=g.CFrame:PointToObjectSpace(root.Position)
		local d=b-a local half=g.Size/2+Vector3.new(1,2,2)
		local lo,hi=segmentFraction,1
		for _,axis in {"X","Y","Z"} do
			if math.abs(d[axis])<.0001 then if math.abs(a[axis])>half[axis] then return false end
			else
				local x,y=(-half[axis]-a[axis])/d[axis],(half[axis]-a[axis])/d[axis]
				lo=math.max(lo,math.min(x,y)) hi=math.min(hi,math.max(x,y))
				if lo>hi then return false end
			end
		end
		segmentFraction=hi
		return true
	end
	local accepted=0
	while accepted<#self.gates and crossed(gate) do
		accepted+=1
		entry.passed+=1
		entry.model:SetAttribute("PassedCheckpoints",entry.passed)
		entry.model:SetAttribute("RaceStage",gate:GetAttribute("Stage") or 1)
		if entry.passed>#self.gates*self.laps then
			self.finished+=1 entry.finishOrder=self.finished entry.progress=1
			entry.model:SetAttribute("RaceState","Finished")
			entry.model:SetAttribute("FinishTime",(entry.finishedAt or now)-self.started)
			entry.model:SetAttribute("RaceProgress",1)
			entry.humanoid:Move(Vector3.zero) root.Anchored=true
			if self.finished==1 then
             self.finishDeadline=(entry.finishedAt or now)+(self.config.FinishWaitSeconds or 10)
             self.owner:SetAttribute("ViewerRaceWinner",entry.model:GetAttribute("ViewerUsername") or entry.username)
            end
			self:beginFinishRun(entry,now)
			return
		end
		entry.model:SetAttribute("RaceLap",math.min(self.laps,math.floor((entry.passed-1)/#self.gates)+1))
		entry.nextGate=entry.passed%#self.gates+1
		gate=self.gates[entry.nextGate]
	end
	if entry.passed>0 then
		local a=self.gates[(entry.nextGate-2)%#self.gates+1].Position
		local b=gate.Position
		local delta=b-a
		local fraction=delta.Magnitude>0 and math.clamp((root.Position-a):Dot(delta)/delta:Dot(delta),0,1) or 0
		entry.progress=math.clamp((math.floor((entry.passed-1)/#self.gates)*self.length+self.cumulative[(entry.nextGate-2)%#self.gates+1]+fraction*delta.Magnitude)/self.totalLength,0,.9999)
	else entry.progress=0 end
	entry.model:SetAttribute("RaceProgress",entry.progress)
	if (root.Position-entry.lastPosition).Magnitude>1 then entry.lastMoved=now entry.lastPosition=root.Position end
	if now-entry.lastMoved>1.2 and now-entry.lastJump>1 then entry.humanoid.Jump=true entry.lastJump=now end
	if root.Position.Y<(self.map:GetAttribute("OceanHeight") or -500)+3 or now-entry.lastMoved>self.config.StuckRecoverySeconds then self:recover(entry) end
end
function Race:updatePathProgress(entry,now)
	local distance=entry.routeDistance or -14
	if distance>=self.totalLength then
		if entry.model:GetAttribute("RaceState")~="Running" then return end
		self.finished+=1 entry.finishOrder=self.finished entry.progress=1
		entry.model:SetAttribute("PassedCheckpoints",#self.gates*self.laps+1)
		entry.model:SetAttribute("RaceState","Finished") entry.model:SetAttribute("FinishTime",(entry.finishedAt or now)-self.started)
		entry.model:SetAttribute("RaceProgress",1) entry.model:SetAttribute("RouteDistance",self.totalLength)
		if self.finished==1 then
             self.finishDeadline=(entry.finishedAt or now)+(self.config.FinishWaitSeconds or 10)
             self.owner:SetAttribute("ViewerRaceWinner",entry.model:GetAttribute("ViewerUsername") or entry.username)
            end
			self:beginFinishRun(entry,now)
		return
	end
	entry.passed=distance<0 and 0 or math.floor(distance/self.length)*#self.gates+self.path:index(distance)
	entry.model:SetAttribute("RaceLap",math.min(self.laps,math.floor(math.max(0,distance)/self.length)+1))
	entry.nextGate=entry.passed%#self.gates+1
	entry.progress=math.clamp(distance/self.totalLength,0,.9999)
	entry.model:SetAttribute("PassedCheckpoints",entry.passed)
end
function Race:publishPath()
	if not self.config.PathDrivenMovement or not self.owner.Parent then return end
	local frames={} local now=self.frameAt or workspace:GetServerTimeNow()
	for _,entry in self.entries do
		if alive(entry) and entry.routeDistance then
			local state=entry.model:GetAttribute("RaceState")
			local moving=state=="Running" or (state=="Finished" and now<(entry.model:GetAttribute("FinishRunUntil") or 0))
			local speed=moving and entry.currentSpeed or 0
			entry.model:SetAttribute("RouteDistance",entry.routeDistance)
			entry.model:SetAttribute("RouteSpeed",speed)
			table.insert(frames,{entry.model,entry.routeDistance,speed})
		end
	end
	if #frames>0 then pathRemote:FireClient(self.owner,now,frames) end
end
function Race:drivePath(entry,now,dt)
	local root=alive(entry) if not root then return end
	if GojoAbility.isStunned(entry,now) then
		entry.currentSpeed=0 entry.humanoid.WalkSpeed=0 entry.lastMoved=now
		local height=RaceAction.sample(entry.model,entry.routeDistance or -14)
		root.CFrame=self.path:sample(entry.routeDistance or -14,entry.routeLane or 0,(entry.routeHeight or 2.8)+height)
		return
	end
	if entry.tripUntil then
		if now<entry.tripUntil then
			entry.currentSpeed=0 entry.humanoid.WalkSpeed=0 entry.lastMoved=now
			local height=RaceAction.sample(entry.model,entry.routeDistance or -14)
			root.CFrame=self.path:sample(entry.routeDistance or -14,entry.routeLane or 0,(entry.routeHeight or 2.8)+height)
			return
		end
		TripState.clear(entry)
	end
	local ramp=math.clamp((now-(entry.startedAt or self.started))/math.max(.05,self.config.LaunchAccelerationSeconds or .6),0,1)
	ramp=ramp*ramp*(3-2*ramp)
	local primary,multiplier=EventStack.evaluate(entry.model,now,nil,self.config.BaseRunSpeed)
	local primaryConfig=primary and EventConfig[primary]
	local isFlying=primaryConfig~=nil and (tonumber(primaryConfig.FlightHeight) or 0)>0
	local consumed
	entry.routeDistance,entry.currentSpeed,consumed=self.path:advance(entry.routeDistance or -14,entry.currentSpeed or 0,self.config.BaseRunSpeed*ramp*multiplier,dt)
	if entry.routeDistance>=self.totalLength then entry.finishedAt=now-dt+consumed end
	entry.humanoid.WalkSpeed=entry.currentSpeed
	if isFlying then
		-- Flight only changes obstacle movement, never race distance/speed.
		entry.humanoid.Jump=false
		entry.model:SetAttribute("RouteJumpAt",nil)
		entry.model:SetAttribute("RouteJumpHeight",nil)
		-- Clear any ongoing obstacle action once when flight begins.
		if not entry.flyingOverObstacles then
			entry.model:SetAttribute("RouteActionKind",nil)
			entry.model:SetAttribute("RouteActionStart",nil)
			entry.model:SetAttribute("RouteActionEnd",nil)
		end
	elseif entry.humanoid.Jump then
		entry.humanoid.Jump=false entry.model:SetAttribute("RouteJumpAt",now)
		entry.model:SetAttribute("RouteJumpHeight",math.clamp(entry.humanoid.JumpPower*.05,2.5,6))
	end
	entry.flyingOverObstacles=isFlying
	local jump=0
	if not isFlying then
		local elapsed=now-(entry.model:GetAttribute("RouteJumpAt") or -math.huge)
		if elapsed>=0 and elapsed<.7 then jump=math.sin(elapsed/.7*math.pi)*(entry.model:GetAttribute("RouteJumpHeight") or 3) end
	end
	local actionHeight=0
	if not isFlying then
		Obstacles.update(entry,self.obstacles,entry.routeDistance,entry.currentSpeed,self.length)
		actionHeight=RaceAction.sample(entry.model,entry.routeDistance)
	end
	local lane=entry.routeLane+(entry.startLane-entry.routeLane)*math.clamp(-entry.routeDistance/14,0,1)
	local frame=self.path:sample(entry.routeDistance,lane,entry.routeHeight+jump+actionHeight)
	root.CFrame=frame
	self:updatePathProgress(entry,now)
end
function Race:cornerSpeed(entry,requested)
	local braking=self.config.CornerBrakeAcceleration or 220
	local speed=entry.currentSpeed or requested
	local distance=(entry.progress or 0)*self.length
	if (entry.passed or 0)==0 then
		local forward=((self.gates[2].Position-self.gates[1].Position)*Vector3.new(1,0,1)).Unit
		distance=(entry.model.HumanoidRootPart.Position-self.gates[1].Position):Dot(forward)
	end
	local margin=speed*.15+4
	local horizon=requested*requested/(2*braking)+margin+20
	local allowed=requested
	for hop=0,#self.gates-1 do
		local raw=entry.nextGate+hop local index=(raw-1)%#self.gates+1
		local ahead=self.cumulative[index]+(raw>#self.gates and self.length or 0)-distance
		if ahead>horizon then break end
		local limit=self.cornerLimits and self.cornerLimits[index]
		if limit then allowed=math.min(allowed,math.sqrt(limit*limit+2*braking*math.max(0,ahead-margin))) end
	end
	return allowed
end
function Race:steer(entry,now,dt)
	if self.config.PathDrivenMovement then self:drivePath(entry,now,dt) return end
	if GojoAbility.isStunned(entry,now) then entry.currentSpeed=0 entry.humanoid.WalkSpeed=0 entry.humanoid:Move(Vector3.zero) entry.lastMoved=now return end
	local root=alive(entry) if not root then return end
	if entry.tripUntil then
		if now<entry.tripUntil then entry.currentSpeed=0 entry.humanoid.WalkSpeed=0 entry.humanoid:Move(Vector3.zero) entry.lastMoved=now return end
		TripState.clear(entry)
	end
	local ramp=math.clamp((now-(entry.startedAt or self.started))/math.max(.05,self.config.LaunchAccelerationSeconds or .6),0,1)
	ramp=ramp*ramp*(3-2*ramp)
	local _,multiplier=EventStack.evaluate(entry.model,now,nil,self.config.BaseRunSpeed)
	local desired=self:cornerSpeed(entry,self.config.BaseRunSpeed*ramp*multiplier)
	entry.currentSpeed=entry.currentSpeed or 0
	if desired<entry.currentSpeed then
		entry.currentSpeed=math.max(desired,entry.currentSpeed-(self.config.CornerBrakeAcceleration or 220)*dt)
	else
		entry.currentSpeed+=(desired-entry.currentSpeed)*(1-math.exp(-dt/math.max(.05,self.config.BoostBlendSeconds or .25)))
	end
	entry.humanoid.WalkSpeed=entry.currentSpeed
	local gate=self.gates[entry.nextGate]
	local lane=self:laneOffset(entry)
	local function point(index)
		local g=self.gates[(index-1)%#self.gates+1]
		return (g.Position+g.CFrame.RightVector*lane)*Vector3.new(1,0,1)
	end
	local position=root.Position*Vector3.new(1,0,1)
	local target=point(entry.nextGate)
	local previous=entry.passed>0 and point(entry.nextGate-1) or position
	local segment=target-previous
	local fraction=segment.Magnitude>.01 and math.clamp((position-previous):Dot(segment)/segment:Dot(segment),0,1) or 0
	local cursor=previous+segment*fraction
	local remaining=math.clamp(entry.currentSpeed*(self.config.SteeringLookAheadSeconds or .1),5,32)
	local index=entry.nextGate
	for _=1,#self.gates do
		local delta=target-cursor
		if delta.Magnitude>=remaining and delta.Magnitude>.001 then target=cursor+delta.Unit*remaining break end
		remaining-=delta.Magnitude cursor=target index+=1 target=point(index)
	end
	local direction=target-position
	entry.humanoid:Move(direction.Magnitude>.01 and direction.Unit or Vector3.zero,false)
end
function Race:rank()
	local ranked={}
	for _,entry in self.participants do if alive(entry) then table.insert(ranked,entry) end end
	table.sort(ranked,function(a,b)
		if a.finishOrder or b.finishOrder then
			if a.finishOrder and b.finishOrder then return (a.finishedAt or a.finishOrder)<(b.finishedAt or b.finishOrder) end
			return a.finishOrder~=nil
		end
		if a.progress~=b.progress then return a.progress>b.progress end
		return a.slot<b.slot
	end)
	for i,entry in ranked do
		if entry.finishOrder then entry.finishOrder=i end
		entry.model:SetAttribute("RaceRank",i) entry.model:SetAttribute("RaceProgress",entry.progress)
	end
	local leader=ranked[1]
	if leader then
		self.owner.ReplicationFocus=leader.model:FindFirstChild("HumanoidRootPart")
		if leader.finishOrder and not self.winRecorded then self.winRecorded=true WinResults.record(self.owner,leader.model,self.winRaceId,leader.finishedAt)end
		if leader.finishOrder then self.owner:SetAttribute("ViewerRaceWinner",leader.model:GetAttribute("ViewerUsername") or leader.username) end
	end
	self.owner:SetAttribute("ViewerRaceLeader",leader and (leader.model:GetAttribute("ViewerUsername") or leader.username) or "")
end
-- Snapshots own the podium avatars, so the field can be cleared immediately.
function Race:clearField()
 GojoAbility.clear(self)
 local entries=self.entries
 self.entries={} self.participants={}
 local focuses=workspace:FindFirstChild("StreamerCameraFocus")
 local focus=focuses and focuses:FindFirstChild(tostring(self.owner.UserId))
 self.owner.ReplicationFocus=focus
 for _,entry in entries do
  if entry.motion then entry.motion:destroy() end
  entry.model:Destroy()
 end
 if self.onFieldCleared then self.onFieldCleared() end
 self:sync()
end
function Race:reset()
 GojoAbility.clear(self)
	if self.destroyed then return end
	AwardService.clear(self.owner)
	self.winRaceId=Http:GenerateGUID(false) self.winRecorded=false
 self.round+=1 self.phase="Lobby" self.participants={} self.finished=0
	self.deadline=0 self.finishDeadline=nil self.owner:SetAttribute("ViewerRaceWinner",nil)
	local focuses=workspace:FindFirstChild("StreamerCameraFocus")
	local focus=focuses and focuses:FindFirstChild(tostring(self.owner.UserId))
	if focus then self.owner.ReplicationFocus=focus end
	for _,entry in self.entries do
		if entry.motion then entry.motion:destroy() end
		entry.model:Destroy()
	end
	self.entries={}
	self.owner:SetAttribute("ViewerRaceLeader",nil)
	self:sync()
	if self.onReset then self.onReset() end
	self:sync()
end
function Race:step(runnersUpdated)
	if self.destroyed then return end
	if not self.owner.Parent then self:destroy() return end
	local now=workspace:GetServerTimeNow()
	if self.phase=="Lobby" then
		if self.config.RaceAutoStart and self.deadline>0 and now>=self.deadline then self:start() end
	elseif self.phase=="Countdown" then
		if now>=self.deadline then self:beginRunning() end
	elseif self.phase=="Running" then
		for _,entry in self.participants do
			if not runnersUpdated and entry.model:GetAttribute("RaceState")=="Running" then self:updateRunner(entry,now) end
		end
		self:rank()
		if self.finished>0 and not self.finishDeadline then self.finishDeadline=now+(self.config.FinishWaitSeconds or 10) end
		if self.finished>0 and self.finishDeadline and now>=self.finishDeadline then
			for _,entry in self.participants do
				if alive(entry) and entry.model:GetAttribute("RaceState")=="Finished" then
					entry.currentSpeed=0 entry.humanoid.WalkSpeed=0
					entry.model:SetAttribute("RouteSpeed",0) entry.model:SetAttribute("FinishRunUntil",0)
				end
				if alive(entry) and entry.model:GetAttribute("RaceState")=="Running" then
					entry.model:SetAttribute("RaceState","DNF") entry.model:SetAttribute("RouteSpeed",0) entry.model.HumanoidRootPart.Anchored=true entry.humanoid:Move(Vector3.zero)
				end
			end
			self.phase="Results" self.finishDeadline=nil self.deadline=now+math.max(self.config.ResultsSeconds or 8,13)
            self:sync()
            local awardOK,awardError=pcall(AwardService.present,self)
            if not awardOK then warn("[AwardCeremony] "..tostring(awardError)) end
            self:clearField()
		end
	elseif self.phase=="Results" and now>=self.deadline then self:reset() end
	self:sync()
end
function Race:destroy()
	if self.destroyed then return end
	GojoAbility.clear(self)
	AwardService.clear(self.owner)
	self.destroyed=true
	self.finishDeadline=nil
	if self.owner.Parent then self.owner:SetAttribute("ViewerRaceFinishEndsAt",0) end
	if self.connection then self.connection:Disconnect() end
	if owned[self.owner]==self then
		owned[self.owner]=nil
		local focuses=workspace:FindFirstChild("StreamerCameraFocus")
		local focus=focuses and focuses:FindFirstChild(tostring(self.owner.UserId))
		if focus then self.owner.ReplicationFocus=focus end
	end
	for _,entry in self.entries do if alive(entry) then entry.humanoid:Move(Vector3.zero) entry.model.HumanoidRootPart.Anchored=true end end
	for _,entry in self.entries do if entry.motion then entry.motion:destroy() end end
end
function Race.forceTrip(owner,actorKey)
 local race=owned[owner]
 if not race or race.destroyed or race.phase~="Running" then return false,"trip_not_running" end
 for _,entry in race.participants do
  if entry.model:GetAttribute("ActorKey")==actorKey and alive(entry) then
   local now=workspace:GetServerTimeNow()
   local primary=EventStack.evaluate(entry.model,now,nil,race.config.BaseRunSpeed)
   return TripState.request(entry,now,race.config,primary)
  end
 end
 return false,"dev_target_missing"
end
local cooldown={}
control.OnServerEvent:Connect(function(player,action,round)
	local now=os.clock()
	if (cooldown[player] or 0)>now then return end
	cooldown[player]=now+.5
	local race=owned[player]
	if not race then return end
	if action=="start" then race:start()
 elseif action=="reset" then race:reset()
 elseif action=="new_game" and race.phase=="Results" and round==race.round
  and race.owner:GetAttribute("ViewerAwardRestartAt")
  and workspace:GetServerTimeNow()>=race.owner:GetAttribute("ViewerAwardRestartAt") then
  race:reset()
 end
end)
Players.PlayerRemoving:Connect(function(player) cooldown[player]=nil local race=owned[player] if race then race:destroy() end end)
return Race

