-- Shared tier/speed rules; gift counts extend each event's timer in GameHandlers.
local config=require(script.Parent.RaceEventConfig)
local Stack={FadeOutSeconds=2,FadeOutMinSpeed=60}
function Stack.evaluate(model,now,events,baseSpeed,maxSpeed)
 if (model:GetAttribute("GojoStunnedUntil") or 0)>now then return nil,1,{} end
 baseSpeed=baseSpeed or 20
 local active={} local total=0 local roundMultiplier=1
 local timedMultiplier,timedCap=1,math.huge
 local timedBonus=0
 local roundBonus=math.max(0,model:GetAttribute("RoundSpeedBonus")or 0)
 for key,boost in events or config do
  if boost.Kind=="Attack" or boost.Kind=="Defense" or boost.Kind=="Debuff" then
   -- Attack and defense actions do not replace speed forms.
  elseif boost.StackMode=="RoundMultiplier" then
   local stacks=math.clamp(model:GetAttribute(boost.Attribute.."Stacks") or 0,0,boost.MaxStacks or 32)
   roundMultiplier*=boost.SpeedMultiplier^stacks
  elseif boost.StackMode=="TimedFlatSpeed" then
   if (model:GetAttribute(boost.Attribute.."Until")or 0)>now then timedBonus+=boost.SpeedBonus or 0 end
  elseif boost.StackMode=="TimedMultiplier" then
   if (model:GetAttribute(boost.Attribute.."Until")or 0)>now then
    local stacks=math.clamp(model:GetAttribute(boost.Attribute.."Stacks")or 1,0,boost.MaxStacks or 32)
    timedMultiplier*=boost.SpeedMultiplier^stacks
    timedCap=math.min(timedCap,boost.MaxSpeed or math.huge)
   end
  elseif (model:GetAttribute(boost.Attribute.."Until") or 0)>now then
   local multiplier=boost.SpeedMultiplier
   if boost.StackMode=="TimedAdditiveSpeed" then
    local stacks=math.max(1,model:GetAttribute(boost.Attribute.."Stacks") or 1)
    multiplier+=(stacks-1)*(boost.SpeedPerExtraGift or 2)/baseSpeed
    if boost.MaxSpeed then multiplier=math.min(multiplier,boost.MaxSpeed/baseSpeed) end
   end
   local weight=1
   local fadeSeconds=boost.FadeOutSeconds or Stack.FadeOutSeconds
   if multiplier*baseSpeed>=(boost.FadeOutMinSpeed or Stack.FadeOutMinSpeed) and fadeSeconds>0
    and (model:GetAttribute(boost.Attribute.."PendingSeconds") or 0)<=0 then
    local remaining=(model:GetAttribute(boost.Attribute.."Until") or 0)-now
    weight=math.clamp(remaining/fadeSeconds,0,1)
    weight=weight*weight*(3-2*weight)
   end
   table.insert(active,{key=key,tier=boost.Tier or 0,multiplier=multiplier,config=boost,fadeWeight=weight})
  end
 end
 table.sort(active,function(a,b)
  if a.tier~=b.tier then return a.tier>b.tier end
  if a.multiplier~=b.multiplier then return a.multiplier>b.multiplier end
  return a.key<b.key
 end)
 local primary=active[1] and active[1].key or nil
 local slow=1
 if (model:GetAttribute("OctopusUntil")or 0)>now
  and not(model:GetAttribute("RaceState")=="Running"and(model:GetAttribute("ShieldUntil")or 0)>now)then
  slow=(events or config).octopus and (events or config).octopus.SlowMultiplier or .9
 end
 -- Fade only the expiring gift, preserving the other gifts and form priority.
 -- Blend in ordinary running when the last active gift fades away.
 local strongestWeight=0
 local boostedBase=math.max(baseSpeed,math.min(baseSpeed*timedMultiplier,timedCap))
 local passiveMultiplier=boostedBase/baseSpeed
 local cap=math.max(1,(maxSpeed or 1500)/(baseSpeed*roundMultiplier*slow*passiveMultiplier))
 for _,event in active do
  local weight=event.fadeWeight
  local multiplier=event.multiplier
  -- Fade from the usable speed rather than an uncapped stack value; otherwise
  -- a large stack would stay at the cap until its very last frames.
  if weight<1 then multiplier=math.min(multiplier,cap) end
  total+=multiplier*weight
  strongestWeight=math.max(strongestWeight,weight)
 end
 return primary,((total+1-strongestWeight)*roundMultiplier*passiveMultiplier+(roundBonus+timedBonus)/baseSpeed)*slow,active
end
function Stack.isPrimary(model,key,now)
 return Stack.evaluate(model,now)==key
end
return Stack
