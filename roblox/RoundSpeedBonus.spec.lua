return function(Stack,events)
 local model=Instance.new("Model")
 local function speed(at)
  local _,multiplier=Stack.evaluate(model,at,events,20)
  return multiplier*20
 end
 local function near(actual,wanted)assert(math.abs(actual-wanted)<.0001,tostring(actual).." ~= "..tostring(wanted))end
 near(speed(100),20)
 model:SetAttribute("RoundSpeedBonus",2)model:SetAttribute("SpeedBoostUntil",105)model:SetAttribute("SpeedBoostStacks",1)
 near(speed(100),32)near(speed(105),22)
 model:SetAttribute("RoundSpeedBonus",4)model:SetAttribute("SpeedBoostUntil",110)model:SetAttribute("SpeedBoostStacks",2)
 near(speed(106),34)near(speed(110),24)
 model:SetAttribute("RoundSpeedBonus",100)near(speed(106),130)near(speed(110),120)
 model:SetAttribute("RocketUntil",120)model:SetAttribute("RocketStacks",1)
 local primary=Stack.evaluate(model,111,events,20)assert(primary=="rocket","Permanent bonus replaced the active form")
 near(speed(111),events.rocket.SpeedMultiplier*20+100)
 near(speed(120),120)
 local normal=Instance.new("Model")local _,m=Stack.evaluate(normal,120,events,20)near(m*20,20)
 normal:Destroy()model:Destroy()
 return "PASS: 20→32→22, repeated +2 stays flat and permanent, no 40 cap on accumulated base, forms preserved, fresh racer starts at20"
end
