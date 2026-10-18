-- TikTok nicknames are external text; only broadcast-filtered strings reach labels.
local Names={}
local function filteredName(value,ownerId,service)
 if type(value)~="string"then return nil end
 value=value:gsub("%c"," "):match("^%s*(.-)%s*$")
 local length=utf8.len(value)
 if not length or length==0 then return nil end
 if length>60 then value=value:sub(1,utf8.offset(value,61)-1)end
 local ok,filtered=pcall(function()
  local result=service:FilterStringAsync(value,ownerId,Enum.TextFilterContext.PublicChat)
  return result:GetNonChatStringForBroadcastAsync()
 end)
 -- A name made entirely of filter hashes or punctuation is not a readable label.
 if ok and type(filtered)=="string"and filtered:find("[^#%s%p]")then return filtered end
 return nil
end
function Names.filter(value,ownerId,service,fallback)
 if type(ownerId)~="number"or ownerId<=0 then return "Viewer",false end
 service=service or game:GetService("TextService")
 local primary=value
 if primary=="Viewer"and type(fallback)=="string"and fallback~=""then primary=nil end
 local filtered=filteredName(primary,ownerId,service)
 if not filtered and fallback~=primary then filtered=filteredName(fallback,ownerId,service)end
 if filtered then return filtered,true end
 return "Viewer",false
end
return Names
