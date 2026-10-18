return function(Bridge)
 local function exercise(retryFirst)
  local p={UserId=42,Parent=true,SetAttribute=function()end}
  local supplied,polls,acks,handled=false,{}, {},{}
  local function event(id,kind)
   return {eventId=id,receipt='receipt-'..id,liveSessionId='session',ownerRobloxId='42',runId='run',generation=1,
    eventType=kind,actorKey='tiktok:viewer',effects={},expiresAt='2099-01-01T00:00:00Z'}
  end
  local joined=false
  local bridge=Bridge.new({},{clear=function()end,join=function()
   table.insert(handled,'join-start')task.wait(.05)joined=true table.insert(handled,'join-end')return true
  end,event=function(context)
   assert(retryFirst or joined,'An effect overtook its join')
   table.insert(handled,context.eventId)
   if retryFirst then return false,'handler_failed'end
   return true
  end},{jobId='fixture',now=function()return 1000 end,request=function(path,method,body)
   if path=='/v1/sessions'then return {id='session',token='fixture',runId='run',generation=1},201 end
   if path:find('/ack',1,true)then for _,ack in body.receipts do table.insert(acks,ack)end return {results={}},200 end
   if path:find('/poll',1,true)then
    table.insert(polls,body)
    assert(body.maxEventsPerSession==32 and body.actorQueues==true and body.maxJoins<=8)
    if supplied then return {events={}},200 end supplied=true
    local events={}
    for i=1,3 do table.insert(events,{sessionId='session',event=event(tostring(i),not retryFirst and i==1 and 'join'or 'like')})end
    return {events=events},200
   end
   return {runId='run',generation=1,status='live'},200
  end})
  assert(bridge:connect(p,'fixture_live','direct','both'))
  bridge:step()
  if not retryFirst then
   assert(bridge.states[p].deliveryBusy)
   local count=#polls bridge:step()assert(#polls==count+1,'Other actors in a busy session were not polled')
   assert(polls[#polls].waitMs==0 and polls[#polls].maxJoins==7)
   task.wait(.1)bridge:step()
   assert(table.concat(handled,',')=='join-start,join-end,2,3','Batch order changed')
   assert(#acks==3)for _,ack in acks do assert(ack.success)end
  else
   bridge:step()
   assert(#handled==1,'A retryable event was bypassed')
   assert(#acks==3,'Untouched batch suffix was left leased')
   for _,ack in acks do assert(not ack.success and ack.retry)end
  end
  bridge:disconnect(p)
 end
 exercise(false)exercise(true)
 -- An idle owner must not hold another owner's completed join behind a10s poll.
 local p={UserId=42,Parent=true,SetAttribute=function()end}
 local q={UserId=43,Parent=true,SetAttribute=function()end}
 local supplied=false
 local b=Bridge.new({},{clear=function()end,join=function()task.wait(.05)return true end,event=function()return true end},
  {jobId='two-owner-fixture',now=function()return 1000 end,request=function(path,method,body)
   if path=='/v1/sessions'then return {id=body.ownerRobloxId,token='fixture',runId='run',generation=1},201 end
   if path:find('/ack',1,true)then return {results={}},200 end
   if path:find('/poll',1,true)then
    if supplied then
     assert(body.waitMs==0,'Idle owner delayed a busy owner with a long poll')
     return {events={}},200
    end
    supplied=true
    return {events={{sessionId='42',event={eventId='join',receipt='fixture',liveSessionId='42',ownerRobloxId='42',runId='run',generation=1,eventType='join',expiresAt='2099-01-01T00:00:00Z'}}}},200
   end
   return {runId='run',generation=1,status='live'},200
  end})
 assert(b:connect(p,'first_live','direct'))assert(b:connect(q,'other_live','direct'))
 b:step()assert(b.states[p].deliveryBusy)b:step()
 task.wait(.1)b:disconnect(p)b:disconnect(q)
 -- A yielding avatar must not block an already joined actor in the same channel.
 local started,finished,effect=false,false,false
 local polls,acks=0,{}
 local p={UserId=42,Parent=true,SetAttribute=function()end}
 local function packet(id,actor,kind)
  return {sessionId='session',event={eventId=id,receipt='receipt-'..id,liveSessionId='session',ownerRobloxId='42',
   runId='run',generation=1,eventType=kind,actorKey=actor,expiresAt='2099-01-01T00:00:00Z'}}
 end
 local b=Bridge.new({},{clear=function()end,join=function()
  started=true task.wait(.12)finished=true return true
 end,event=function(e)
  if e.actorKey=='B'then assert(started and not finished,'Ready actor waited behind avatar creation')effect=true
  else assert(finished,'An actor overtook its own join')end
  return true
 end},{jobId='actor-fixture',now=function()return 1000 end,request=function(path,method,body)
  if path=='/v1/sessions'then return {id='session',token='fixture',runId='run',generation=1},201 end
  if path:find('/ack',1,true)then for _,a in body.receipts do table.insert(acks,a)end return {},200 end
  if path:find('/poll',1,true)then
   polls+=1
   assert(body.actorQueues==true and body.maxJoins==(polls==1 and 8 or 7))
   if polls==1 then return {events={packet('joinA','A','join')}},200 end
   if polls==2 then return {events={packet('heartB','B','like')}},200 end
   return {events={}},200
  end
  return {runId='run',generation=1,status='live'},200
 end})
 assert(b:connect(p,'actor_live','direct'))
 b:step()assert(started and not finished)b:step()assert(effect,'Ready actor effect was not applied immediately')
 task.wait(.15)b:flush()assert(finished and #acks==2)b:disconnect(p)
 return 'PASS: per-actor FIFO, same-channel parallel delivery, bounded avatar starts, long-poll negotiation and retry release'
end
