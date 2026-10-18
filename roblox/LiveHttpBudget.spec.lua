return function(Budget)
 local at,starts=0,{}
 local gate=Budget.new({now=function()return at end,wait=function(seconds)at+=seconds end})
 for i=1,720 do assert(gate:acquire("other"))table.insert(starts,at)end
 for i=361,#starts do assert(starts[i]-starts[i-360]>=60-.000001,"Global budget exceeded360/min")end
 for _,kind in {"direct_poll","tikkies_ack"}do
  at=0 local times={}
  local limit=kind=="direct_poll"and 210 or 180
  gate=Budget.new({now=function()return at end,wait=function(seconds)at+=seconds end})
  for i=1,limit*2 do gate:acquire(kind)table.insert(times,at)end
  for i=limit+1,#times do assert(times[i]-times[i-limit]>=60-.000001,"Provider budget exceeded")end
 end
 assert(not gate:acquire("other",function()return false end))
 assert(gate:acquire("other"),"A stale request blocked the gate")
 return "PASS: global360/min, Direct210/min, Tikkies180/min and stale cancellation"
end
