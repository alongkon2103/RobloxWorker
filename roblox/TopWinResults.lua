-- Server-only first-finish receipts. Never infer a win from a leaderboard snapshot.
local Http=game:GetService('HttpService')
local Players=game:GetService('Players')
local RunService=game:GetService('RunService')
local Results={}
local pending={} local saving={} local deleting={} local loaded={} local transport,key local busy=false
local started=false
local durable=not RunService:IsStudio()
local outbox=game:GetService('DataStoreService'):GetDataStore('HyperRunTopWinOutboxV1')
function Results.payload(owner,model,raceId,jobId,now)
 local actor=model:GetAttribute('ActorKey')
 if not owner:GetAttribute('LiveEnabled')or model:GetAttribute('RaceState')~='Finished'
  or type(actor)~='string'or not(actor:match('^tiktok:[%w._-]+$')or actor:match('^live:[%w._-]+$'))then return nil end
 local provider=owner:GetAttribute('LiveProvider')
 local channel=owner:GetAttribute('LiveUsername')or ''
 if provider~='direct'and provider~='tikkies'then return nil end
 if provider=='direct'and channel==''then return nil end
 return {ownerRobloxId=tostring(owner.UserId),jobId=jobId,raceId=raceId,actorKey=actor,
  name=model:GetAttribute('ViewerDisplayName')or 'Viewer',robloxId=tostring(model:GetAttribute('RobloxId')),
  provider=provider,channel=channel,finishedAt=now}
end
local function persist(id,b)
 if not durable or saving[id]then return end saving[id]=true
 task.spawn(function()
  local ok=pcall(function()outbox:UpdateAsync('owner:'..b.ownerRobloxId,function(items)
   items=type(items)=='table'and items or {} items[id]=b return items
  end)end)
  saving[id]=nil
  if ok and pending[id]then pending[id].saved=true end
 end)
end
local function erase(id,b)
 if not durable or deleting[id]then return end deleting[id]=true
 task.spawn(function()
  local ok=pcall(function()outbox:UpdateAsync('owner:'..b.ownerRobloxId,function(items)
   items=type(items)=='table'and items or {} items[id]=nil return items
  end)end)
  deleting[id]=nil
  if not ok then task.delay(10,function()erase(id,b)end)end
 end)
end
function Results.record(owner,model,raceId,finishTime)
 if RunService:IsStudio()then return false end -- Studio/dev races never change paid LIVE statistics.
 local b=Results.payload(owner,model,raceId,transport and transport.jobId or game.JobId,math.round(DateTime.now().UnixTimestampMillis-math.max(0,workspace:GetServerTimeNow()-(finishTime or workspace:GetServerTimeNow()))*1000))
 if not b then return false end
 local id=b.jobId..':'..raceId
 if pending[id]then return true end
 local count=0 for _ in pending do count+=1 end
 if count>=200 then warn('TOP WIN: result outbox full; check Worker connection')return false end
 pending[id]={body=b,attempt=0,nextAt=0}persist(id,b)return true
end
function Results.flush()
 if busy or not transport or not key then return end busy=true
 local sent=0
 for id,item in pending do
  if os.clock()>=item.nextAt then
   if not item.saved then persist(id,item.body)end
   local requested,data,code=pcall(transport.request,'/v1/overlays/top-win/result','POST',item.body,key)
   if not requested then data=nil code=0 end
   if code==200 and data and data.ok then
    -- Let an in-flight persistence write finish before deleting its durable receipt.
    if not saving[id]then pending[id]=nil erase(id,item.body)end
   elseif code==400 and DateTime.now().UnixTimestampMillis-item.body.finishedAt>7*86400000 then pending[id]=nil erase(id,item.body)
   else item.attempt+=1 item.nextAt=os.clock()+math.min(60,2^math.min(6,item.attempt))end
   sent+=1 if sent>=5 then break end
  end
 end
 busy=false
end
function Results.start(t,k)
 transport=t key=k
 if started then return end started=true
 local function load(owner)
  if not durable or loaded[owner.UserId]then return end loaded[owner.UserId]=true
  task.spawn(function()
   local ok,items=pcall(outbox.GetAsync,outbox,'owner:'..owner.UserId)
   if not ok then loaded[owner.UserId]=nil task.delay(15,function()if owner.Parent then load(owner)end end)return end
   if type(items)=='table'then for id,b in items do
    if type(id)=='string'and type(b)=='table'and b.ownerRobloxId==tostring(owner.UserId)and type(b.finishedAt)=='number'then
     pending[id]=pending[id]or {body=b,saved=true,attempt=0,nextAt=0}
    end
   end end
  end)
 end
 for _,p in Players:GetPlayers()do load(p)end Players.PlayerAdded:Connect(load)
 game:BindToClose(function()
  local untilAt=os.clock()+15
  repeat Results.flush()task.wait(.2)until next(pending)==nil or os.clock()>untilAt
 end)
end
return Results
