-- Server-only presentation feed; it never triggers skills or changes gameplay receipts.
local TTL=12000
local MAX_ITEMS=30
local keys={rainbow_cat=true,rocket=true,naruto=true,goku=true,asta=true,speed_boost=true,fly=true,gojo=true,shield=true,octopus=true,power=true,jump=true,heal=true}
local function new(clock)
 clock=clock or function()return DateTime.now().UnixTimestampMillis end
 local owners={}
 local Feed={}
 local function clean(t)
  for owner,row in pairs(owners)do
   for id,untilAt in pairs(row.seen)do if untilAt<=t then row.seen[id]=nil end end
   for i=#row.items,1,-1 do if t-row.items[i].createdAt>=TTL then table.remove(row.items,i)end end
   if #row.items==0 and next(row.seen)==nil then owners[owner]=nil end
  end
 end
 local function label(value,fallback)
  if type(value)~="string"or value==""then return fallback end
  value=value:gsub("%c"," ")
  local ok,result=pcall(function()
   local units,last=0,0
   for offset,code in utf8.codes(value)do
    local cost=code>65535 and 2 or 1
    if units+cost>100 then break end
    units+=cost local nextOffset=utf8.offset(value,2,offset)last=nextOffset and nextOffset-1 or #value
   end
   return value:sub(1,last)
  end)
  return ok and result~=""and result or fallback
 end
 local function identity(value)return type(value)=="string"and #value<=16 and value:match("^[1-9]%d*$")~=nil end
 function Feed.record(context,filteredName)
  if type(context)~="table"or not identity(context.ownerRobloxId)or not(identity(context.robloxId)or(context.robloxId=="0"and context.avatarType=="bacon"))
   or type(context.eventId)~="string"or #context.eventId==0 or #context.eventId>180
   or type(context.effects)~="table"or #context.effects>200 then return 0 end
  local t=clock()clean(t)
  local row=owners[context.ownerRobloxId]
  if row and row.seen[context.eventId]then return 0 end
  if not row then
   local count=0 for _ in pairs(owners)do count+=1 end
   if count>=128 then return 0 end
   row={items={},seen={}}owners[context.ownerRobloxId]=row
  end
  local seenCount=0 for _ in pairs(row.seen)do seenCount+=1 end
  if seenCount>=256 then return 0 end
  local name=label(filteredName,"Viewer")
  local handle=label(context.tiktokUsername,"")
  local added=0
  for index,effect in ipairs(context.effects)do
   if type(effect)=="table"and keys[effect.key]and type(effect.count)=="number"and effect.count%1==0 and effect.count>=1 and effect.count<=10000 then
    local item={id=context.eventId..":"..index,robloxId=context.robloxId,avatarType=context.avatarType,tiktokDisplayName=name,tiktokUsername=handle,effectKey=effect.key,count=effect.count,createdAt=t}
    if type(context.tiktokAvatarUrl)=="string"and #context.tiktokAvatarUrl<=2048 then item.tiktokAvatarUrl=context.tiktokAvatarUrl end
    table.insert(row.items,1,item)if #row.items>MAX_ITEMS then table.remove(row.items)end
    added+=1
   end
  end
  if added>0 then row.seen[context.eventId]=t+TTL end
  return added
 end
 function Feed.snapshot(owner)
  local t=clock()clean(t)local result={}
  for _,item in ipairs(owners[owner]and owners[owner].items or {})do
   table.insert(result,table.clone(item))
  end
  return result
 end
 Feed.new=new
 return Feed
end
return new()
