-- Run with a fresh cloned TikkiesGames module in an isolated Studio session; no provider traffic.
return function(Module)
 local Players=game:GetService("Players")
 local owner=assert(Players:GetPlayers()[1],"A Studio player is required")
 local function exercise(batchCapable)
  local sequence,active,acks={}, {},0
  local polls,completed,parallel,firstFinished=0,0,false,false
  local tested,receiver=false,nil
  local function packet(id,actor)
   return {id=id,receipt="receipt-"..id,ownerRobloxId=tostring(owner.UserId),runId="fixture",generation="one",actorKey="test:"..actor,eventType="join",expiresAt=DateTime.fromUnixTimestampMillis(DateTime.now().UnixTimestampMillis+120000):ToIsoDate(),payload={namespace="test",robloxId=tostring(owner.UserId),effects={}}}
  end
  local deliveries={packet("first","a"),packet("second","a"),packet("other","b")}
  receiver=Module.start({origin="https://fixture.invalid",credential="fixture-credential",roster=function()return{tostring(owner.UserId)}end,
   acquire=function(kind,current)assert(kind:match("^tikkies_"));return current()end,
   request=function(path,body)
    if path=="register"then
     if not batchCapable and body.capabilities then return{error="invalid_input"},400 end
     if batchCapable then assert(body.capabilities and body.capabilities.batchAck==true and body.capabilities.receiptCacheV2==true,"New receiver did not advertise its durable receipt cache") end
     return{token="fixture-session",capabilities=batchCapable and {batchAck=true} or nil},200
    end
    if path=="heartbeat"or path=="close"then return{ok=true},200 end
    if path=="poll"then
     polls+=1
     if polls==1 then return{deliveries=deliveries},200 end
     assert(completed==3 and acks==3,"Next poll overtook unfinished handlers or acknowledgements")
     tested=true task.wait(.05) return{deliveries={}},200
    end
    if path=="ack-batch"then
     assert(batchCapable and completed==3 and #body.receipts==3,"Batch ACK was not negotiated or omitted an event")
     for _,receipt in body.receipts do assert(receipt.ok==true) end
     acks+=#body.receipts return{results={}},200
    end
    assert(path=="ack"and not batchCapable,"Old backend received an unsupported batch request")
    assert(body.ok==true) acks+=1 return{ok=true},200
   end,
   onViewerJoin=function(context)
    assert(not active[context.actorKey],"Same actor handlers overlapped")
    active[context.actorKey]=true table.insert(sequence,context.eventId)
    if context.eventId=="first"then task.wait(.05) firstFinished=true
    elseif context.eventId=="second"then assert(firstFinished,"Actor order changed")
    elseif context.eventId=="other"then parallel=not firstFinished end
    active[context.actorKey]=nil completed+=1 return true
   end})
  local deadline=os.clock()+2
  repeat task.wait()until tested or os.clock()>deadline
  receiver.stop()
  assert(tested,"Fake transport was not used or batch did not drain")
  assert(parallel,"One slow actor blocked an independent actor")
  assert(completed==3 and acks==3)
 end
 local function reconnect()
  local polls,registrations,joins,gifts,giftAcks=0,0,0,0,0
  local tested=false
  local function packet(id,eventType)
   return {id=id,receipt="receipt-"..id,ownerRobloxId=tostring(owner.UserId),runId="same-run",generation="same-generation",actorKey="test:retained",eventType=eventType,expiresAt=DateTime.fromUnixTimestampMillis(DateTime.now().UnixTimestampMillis+120000):ToIsoDate(),payload={namespace="test",robloxId=tostring(owner.UserId),quantity=7,effects=eventType=="join"and{}or{{key="power",value=1,count=7}}}}
  end
  local receiver=Module.start({origin="https://fixture.invalid",credential="fixture-credential",roster=function()return{tostring(owner.UserId)}end,
   acquire=function(_,current)return current()end,
   request=function(path,body)
    if path=="register"then registrations+=1 return{token="session-"..registrations,capabilities={batchAck=true}},200 end
    if path=="heartbeat"or path=="close"then return{ok=true},200 end
    if path=="ack-batch"then
     for _,receipt in body.receipts do
      if receipt.eventId=="foreign"then assert(receipt.ok==false and receipt.error=="viewer_not_joined","Bindings leaked across source runs")
      else assert(receipt.ok==true,"Re-registering forgot a confirmed actor") end
      if receipt.eventId=="gift"then giftAcks+=1 if giftAcks==1 then return nil,503 end end
     end
     return{results={}},200
    end
    assert(path=="poll")polls+=1
    if polls==1 then return{deliveries={packet("join","join")}},200 end
    if polls==2 then return nil,401 end
    if polls==3 or polls==4 then local gift=packet("gift","gift")gift.receipt="gift-receipt-"..polls return{deliveries={gift}},200 end
    if polls==5 then local foreign=packet("foreign","gift")foreign.runId="foreign-run"return{deliveries={foreign}},200 end
    if polls==6 then local newer=packet("newer-join","join")newer.payload.robloxId="987"return{deliveries={newer}},200 end
    if polls==7 then
     local gift=packet("rebound-gift","gift")gift.payload.robloxId="987"
     return{deliveries={packet("join","join"),gift}},200
    end
    tested=true task.wait(.05)return{deliveries={}},200
   end,
   onViewerJoin=function()joins+=1 return true end,
   onViewerEvent=function(context)assert(context.quantity==7 and context.effects[1].count==7,"Gift combo quantity changed")gifts+=1 return true end})
  local deadline=os.clock()+2 repeat task.wait()until tested or os.clock()>deadline
  receiver.stop()
  assert(tested and registrations==2 and joins==2 and gifts==2 and giftAcks==2,"A refreshed session lost its owner/run/generation actor binding")
 end
 local function refreshDuringJoin()
  local registrations,polls,joins,gifts,reconciled,foreign=0,0,0,0,0,0
  local tested,expired=false,false
  local function packet(id,eventType)
   return {id=id,receipt="receipt-"..id,ownerRobloxId=tostring(owner.UserId),runId="yield-run",generation="yield-generation",actorKey="test:yielded",eventType=eventType,expiresAt=DateTime.fromUnixTimestampMillis(DateTime.now().UnixTimestampMillis+120000):ToIsoDate(),payload={namespace="test",robloxId=tostring(owner.UserId),effects=eventType=="join"and{}or{{key="power",value=1,count=1}}}}
  end
  local receiver=Module.start({origin="https://fixture.invalid",credential="fixture-credential",roster=function()return{tostring(owner.UserId)}end,
   acquire=function(_,current)return current()end,
   request=function(path,body)
    if path=="register"then registrations+=1 return{token="yield-session-"..registrations,capabilities={batchAck=true,boundedPipeline=true}},200 end
    if path=="heartbeat"then if not expired then expired=true return nil,401 end return{ok=true},200 end
    if path=="close"then return{ok=true},200 end
    if path=="ack-batch"then
     for _,receipt in body.receipts do
      if receipt.eventId=="foreign-run"or receipt.eventId=="foreign-generation"then assert(receipt.ok==false,"A stale join bound another run or generation")foreign+=1
      else assert(receipt.ok==true,"Cached successful join was acknowledged without restoring its binding")reconciled+=1 end
     end
     return{results={}},200
    end
    assert(path=="poll")polls+=1
    if polls==1 then return{deliveries={packet("yielded-join","join")}},200 end
    if polls==2 then while not expired do task.wait(.01)end return nil,401 end
    if polls==3 then
     local replay=packet("yielded-join","join")replay.receipt="current-receipt"
     return{deliveries={replay,packet("yielded-gift","gift")}},200
    end
    if polls==4 then
     while reconciled<2 do task.wait(.01)end
     local otherRun=packet("foreign-run","gift")otherRun.runId="other-run"
     local runReplay=packet("yielded-join","join")runReplay.runId="other-run"
     local otherGeneration=packet("foreign-generation","gift")otherGeneration.generation="other-generation"
     local generationReplay=packet("yielded-join","join")generationReplay.generation="other-generation"
     return{deliveries={runReplay,otherRun,generationReplay,otherGeneration}},200
    end
    tested=true task.wait(.05)return{deliveries={}},200
   end,
   onViewerJoin=function()joins+=1 task.wait(15.1)return true end,
   onViewerEvent=function()gifts+=1 return true end})
  local deadline=os.clock()+20 repeat task.wait()until (tested and reconciled==2 and foreign==2)or os.clock()>deadline
  receiver.stop()
  assert(tested and registrations==2 and joins==1 and gifts==1 and reconciled==2 and foreign==2,"Heartbeat refresh lost the binding of an in-progress successful join")
 end
 local function boundedPipeline(batchCapable)
  local polls,acks,gifts=0,0,0
  local joinedB,slowDone,fastGift,limited=false,false,false,false
  local function packet(id,actor,eventType)
   return {id=id,receipt="receipt-"..id,ownerRobloxId=tostring(owner.UserId),runId="pipeline",generation="one",actorKey="test:"..actor,eventType=eventType,expiresAt=DateTime.fromUnixTimestampMillis(DateTime.now().UnixTimestampMillis+120000):ToIsoDate(),payload={namespace="test",robloxId=tostring(owner.UserId),effects=eventType=="join"and{}or{{key="power",value=1,count=1}}}}
  end
  local function acknowledge(receipts)
   for _,receipt in receipts do assert(receipt.ok==true,"An actor event overtook its queued join")if receipt.eventId=="join-b"then joinedB=true end acks+=1 end
   return{results={}},200
  end
  local receiver=Module.start({origin="https://fixture.invalid",credential="fixture-credential",roster=function()return{tostring(owner.UserId)}end,
   acquire=function(_,current)return current()end,
   request=function(path,body)
    if path=="register"then return{token="pipeline-session",capabilities={batchAck=batchCapable,boundedPipeline=true}},200 end
    if path=="heartbeat"or path=="close"then return{ok=true},200 end
    if path=="ack-batch"then assert(batchCapable)return acknowledge(body.receipts)end
    if path=="ack"then assert(not batchCapable)return acknowledge({body})end
    assert(path=="poll")polls+=1
    if body.limit~=nil then assert(body.limit>=1 and body.limit<=32)limited=true end
    if polls==1 then return{deliveries={packet("join-a","a","join"),packet("join-b","b","join")}},200 end
    if polls==2 then
     while not joinedB do task.wait(.01)end
     return{deliveries={packet("gift-a","a","gift"),packet("gift-b","b","gift")}},200
    end
    task.wait(.03)return{deliveries={}},200
   end,
   onViewerJoin=function(context)if context.actorKey=="test:a"then task.wait(.4)slowDone=true end return true end,
   onViewerEvent=function(context)
    if context.actorKey=="test:b"then fastGift=not slowDone
    else assert(slowDone,"Same actor ran before its join finished")end
    gifts+=1 return true
   end})
  local deadline=os.clock()+3 repeat task.wait()until acks==4 or os.clock()>deadline
  receiver.stop()
  assert(fastGift,"A later ready actor waited behind another actor's slow avatar")
  assert(limited and gifts==2 and acks==4,"Bounded pipeline lost a delivery or failed to advertise remaining capacity")
 end
 local function pipelineCapacity()
  local polls,acks,joins,active,maximum=0,0,0,0,0
  local receiver=Module.start({origin="https://fixture.invalid",credential="fixture-credential",roster=function()return{tostring(owner.UserId)}end,
   acquire=function(_,current)return current()end,
   request=function(path,body)
    if path=="register"then return{token="capacity-session",capabilities={batchAck=true,boundedPipeline=true}},200 end
    if path=="heartbeat"or path=="close"then return{ok=true},200 end
    if path=="ack-batch"then assert(#body.receipts<=32)for _,receipt in body.receipts do assert(receipt.ok==true)acks+=1 end return{results={}},200 end
    assert(path=="poll"and body.limit>=1 and body.limit<=32)polls+=1
    if polls<=3 then
     assert(body.limit==32,"Another poll claimed work while all32 slots were still reserved")
     local deliveries={}
     for index=1,32 do
      local id=(polls==3 and "next-"or"first-")..index
      table.insert(deliveries,{id=id,receipt="receipt-"..polls.."-"..id,ownerRobloxId=tostring(owner.UserId),runId="capacity",generation="one",actorKey="test:"..id,eventType="join",expiresAt=DateTime.fromUnixTimestampMillis(DateTime.now().UnixTimestampMillis+120000):ToIsoDate(),payload={namespace="test",robloxId=tostring(owner.UserId),effects={}}})
     end
     return{deliveries=deliveries},200
    end
    task.wait(.03)return{deliveries={}},200
   end,
   onViewerJoin=function()joins+=1 active+=1 maximum=math.max(maximum,active)assert(active<=32,"Unbounded in-flight handlers")task.wait(.15)active-=1 return true end})
  local deadline=os.clock()+3 repeat task.wait()until acks==96 or os.clock()>deadline
  receiver.stop()
  assert(acks==96 and joins==64 and maximum==32,"Receipt retries leaked reservations or repeated join handlers")
 end
 exercise(true)exercise(false)reconnect()refreshDuringJoin()boundedPipeline(true)boundedPipeline(false)pipelineCapacity()
 return "PASS Tikkies: negotiated batch ACK, old-server fallback, actor FIFO, parallel actors, bounded poll batches, reconnect scope and ACK retry dedupe"
end
