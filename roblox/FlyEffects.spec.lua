-- Runs the actual client source against isolated services; never binds a live render step.
return function(run)
 local now,render,destroyed=100,nil,nil
 local function signal(callback)
  return {Connect=function(_,fn)if callback then callback(fn)end return {Disconnect=function()end}end}
 end
 local function joint()
  local attributes={}
  return {Name="RightShoulder",Parent=true,C0=CFrame.identity,Transform=CFrame.identity,
   IsA=function(_,kind)return kind=="Motor6D"end,
   GetAttribute=function(_,key)return attributes[key]end,
   SetAttribute=function(_,key,value)attributes[key]=value end}
 end
 local root={CFrame=CFrame.identity}
 local hum={Health=100,RigType=Enum.HumanoidRigType.R15}
 local currentJoint=joint()
 local attributes={FlyUntil=200,RaceState="Running"}
 local model={Name="Fixture",Parent=true,
  FindFirstChild=function(_,name)if name=="HumanoidRootPart"then return root end end,
  FindFirstChildOfClass=function(_,kind)if kind=="Humanoid"then return hum end end,
  GetDescendants=function()return {currentJoint}end,
  GetAttribute=function(_,key)return attributes[key]end,
  SetAttribute=function(_,key,value)attributes[key]=value end}
 local runners={GetChildren=function()return {model}end}
 local world={WaitForChild=function()return runners end,GetServerTimeNow=function()return now end}
 local lastStarted
 local modules={
  ViewerFlightHeight={clear=function()end,publish=function()end},
  RaceEventStack={isPrimary=function()return true end},
  FlyMotion={sample=function(_,started)lastStarted=started return {weight=1,height=8,bob=0}end,
   pose=function()return CFrame.Angles(.4,0,0)end},
  ViewerRigPose={apply=function()end},RaceEventConfig={fly={}}
 }
 local services={ReplicatedStorage={WaitForChild=function(_,name)return name end},RunService={
  PreAnimation=signal(),BindToRenderStep=function(_,_,_,fn)render=fn end,UnbindFromRenderStep=function()end}}
 local environment=setmetatable({workspace=world,game={GetService=function(_,name)return assert(services[name])end},
  require=function(name)return assert(modules[name],name)end,
  script={Destroying=signal(function(fn)destroyed=fn end)},
  Instance={new=function()return {Destroy=function()end,Emit=function()end}end}
 },{__index=getfenv()})
 assert(type(run)=="function","Pass the FlyEffects source wrapped in a function")setfenv(run,environment)
 local ok,message=pcall(function()
  run()assert(render,"Fly did not register its isolated render callback")render(.016)
  assert(currentJoint.C0~=CFrame.identity,"Initial Fly pose was not applied")
  local started=lastStarted
  for _,change in {"replacement","revision","humanoid","root"}do
   local previous=currentJoint previous.Parent=nil currentJoint=joint()
   if change=="replacement"or change=="root"then root={CFrame=CFrame.identity}end
   if change=="replacement"or change=="humanoid"then hum={Health=100,RigType=Enum.HumanoidRigType.R6}end
   if change=="replacement"or change=="revision"then attributes.AvatarRevision=(attributes.AvatarRevision or 0)+1 end
   now+=1 render(.016)
   assert(currentJoint.C0~=CFrame.identity,"Active Fly lost its pose after "..change)
   assert(lastStarted==started,"Avatar replacement restarted the Fly timer")
  end
 end)
 if destroyed then destroyed()end
 assert(ok,message)
 return "PASS: active Fly rebinds new joints on avatar revision, humanoid or root replacement without restarting its effect"
end
