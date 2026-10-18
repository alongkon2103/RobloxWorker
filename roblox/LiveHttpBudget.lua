-- One server-wide admission gate for LIVE, Tikkies and overlay HTTP starts.
local Budget={}
local Gate={}Gate.__index=Gate
function Budget.new(options)
 options=options or {}
 return setmetatable({now=options.now or os.clock,wait=options.wait or task.wait,
  queue={},head=1,tail=0,last=-math.huge,groups={}},Gate)
end
local function group(kind)
 if kind=="direct_poll"or kind=="direct_ack"then return "direct",60/210 end
 if kind=="tikkies_poll"or kind=="tikkies_ack"or kind=="tikkies_heartbeat"then return "tikkies",60/180 end
 return nil,0
end
function Gate:acquire(kind,isCurrent)
 self.tail+=1 local ticket=self.tail self.queue[ticket]=true
 local bucket,interval=group(kind)
 local function advance()
  while self.head<=self.tail and self.queue[self.head]==false do self.queue[self.head]=nil self.head+=1 end
  if self.head>self.tail then self.head=1 self.tail=0 end
 end
 while true do
  if isCurrent and not isCurrent()then self.queue[ticket]=false advance()return false end
  local now=self.now()
  local ready=math.max(self.last+60/360,bucket and(self.groups[bucket]or -math.huge)+interval or -math.huge)
  if ticket==self.head and now>=ready then
   self.last=now if bucket then self.groups[bucket]=now end
   self.queue[ticket]=false advance()
   return true
  end
  self.wait(ticket==self.head and math.max(.001,ready-now)or .02)
 end
end
local shared=Budget.new()
function Budget.acquire(kind,isCurrent)return shared:acquire(kind,isCurrent)end
return Budget
