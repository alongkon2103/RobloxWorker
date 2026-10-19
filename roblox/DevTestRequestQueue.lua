-- FIFO for test controls. Cooldown responses retain the same item until accepted.
local Queue={}
Queue.__index=Queue
function Queue.new(send,complete,interval)
 return setmetatable({send=send,complete=complete,interval=interval or .22,
  items={},first=1,last=0,count=0,running=false,closed=false,nextSend=0},Queue)
end
function Queue:push(item)
 if self.closed then return false end
 self.last+=1 self.items[self.last]=item self.count+=1
 if not self.running then
  self.running=true
  task.defer(function()
   while not self.closed and self.first<=self.last do
    local item=self.items[self.first]
    local waitFor=self.nextSend-os.clock()
    if waitFor>0 then task.wait(waitFor) end
    if self.closed then break end
    local ok,result
    if item.valid and not item.valid() then
     ok=true result={ok=false,code="dev_target_expired"}
    else
     ok,result=pcall(self.send,item)
     self.nextSend=os.clock()+self.interval
    end
    if self.closed then break end
    if ok and type(result)=="table" and result.code=="dev_cooldown" then
     self.nextSend=os.clock()+math.max(.02,tonumber(result.retryAfter) or self.interval)
    else
     self.items[self.first]=nil self.first+=1 self.count-=1
     local notified,err=pcall(self.complete,item,ok,result)
     if not notified then warn("[DevTestQueue] "..tostring(err)) end
    end
   end
   self.running=false
   if self.first>self.last then self.items={}self.first=1 self.last=0 end
  end)
 end
 return true
end
function Queue:destroy()
 self.closed=true self.items={}self.count=0
end
return Queue
