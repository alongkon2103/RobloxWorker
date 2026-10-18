return function(Stack)
 local model=Instance.new("Model")
 local events={
  speed_boost={Attribute="SpeedBoost",StackMode="TimedMultiplier",SpeedMultiplier=1.2,Duration=5,MaxSpeed=40,MaxStacks=32},
  rocket={Attribute="Rocket",SpeedMultiplier=2.5,Tier=1},
 }
 local function speed(at,base)
  local _,m,active=Stack.evaluate(model,at,events,base or 16)
  assert(#active==(model:GetAttribute("RocketUntil")and 1 or 0),"Passive boost must not replace a form")
  return m*(base or 16)
 end
 assert(speed(100)==16)
 model:SetAttribute("SpeedBoostUntil",105)
 model:SetAttribute("SpeedBoostStacks",1) assert(math.abs(speed(100)-19.2)<.0001)
 model:SetAttribute("SpeedBoostStacks",2) assert(math.abs(speed(100)-23.04)<.0001)
 model:SetAttribute("SpeedBoostStacks",32) assert(speed(100)==40)
 assert(speed(105)==16,"Boost must expire exactly at five seconds")
 assert(speed(100,50)==50,"Boost must not slow a faster base speed")
 model:SetAttribute("RocketUntil",120)
 assert(speed(100)==100,"Rocket must retain its multiplier outside the boost cap")
 assert(speed(105)==40,"Rocket continues after passive boost expires")
 model:Destroy()
 return "PASS: x1.2 stacks, 40 cap, 5s expiry, stale stacks ignored, rocket preserved"
end
