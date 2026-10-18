-- TikTok nicknames are external text; only broadcast-filtered strings reach labels.
local Names={}
function Names.filter(value,ownerId,service)
 if type(value)~="string"or type(ownerId)~="number"or ownerId<=0 then return "Viewer",false end
 value=value:gsub("%c"," "):match("^%s*(.-)%s*$")
 local length=utf8.len(value)
 if not length or length==0 then return "Viewer",false end
 if length>60 then value=value:sub(1,utf8.offset(value,61)-1)end
 local ok,filtered=pcall(function()
  local result=(service or game:GetService("TextService")):FilterStringAsync(value,ownerId,Enum.TextFilterContext.PublicChat)
  return result:GetNonChatStringForBroadcastAsync()
 end)
 if ok and type(filtered)=="string"and filtered~=""then return filtered,true end
 return "Viewer",false
end
return Names
