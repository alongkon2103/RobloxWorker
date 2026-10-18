local Preferences={}
Preferences.__index=Preferences
function Preferences.validJoinMode(value)
 return value=="at" or value=="plain" or value=="both"
end
function Preferences.normalize(value)
 if type(value)~="string" or #value>32 then return nil end
 value=value:match("^%s*(.-)%s*$"):gsub("^@",""):lower()
 if #value<2 or #value>24 or value:find("[^%w._]") then return nil end
 return value
end
function Preferences.new(store,options)
 options=options or {}
 return setmetatable({store=store,records={},delay=options.delay or task.delay,wait=options.wait or task.wait},Preferences)
end
function Preferences:record(player)
 local r=self.records[player]
 if not r then r={name="",revision=0,nameRevision=0,modeRevision=0,dirty=false} self.records[player]=r end
 return r
end
function Preferences:load(player)
 local r=self:record(player) local nameRevision,modeRevision=r.nameRevision,r.modeRevision
 player:SetAttribute("PreferredTikTokUsername",r.name)
 player:SetAttribute("PreferredJoinMode",r.joinMode or "both")
 local ok,data=pcall(self.store.GetAsync,self.store,tostring(player.UserId))
 if self.records[player]~=r then return end
 local name=ok and Preferences.normalize(type(data)=="table" and data.username or data) or nil
 if name and r.nameRevision==nameRevision then r.name=name end
 if ok and r.modeRevision==modeRevision then r.joinMode=type(data)=="table" and Preferences.validJoinMode(data.joinMode) and data.joinMode or "both" end
 if player.Parent then
  player:SetAttribute("PreferredTikTokUsername",r.name)
  player:SetAttribute("PreferredJoinMode",r.joinMode or "both")
  if not r.dirty then player:SetAttribute("UsernameSaveStatus",ok and (name and "saved" or "") or "session") end
 end
end
function Preferences:set(player,value)
 local name=Preferences.normalize(value) if not name then return false end
 local r=self:record(player)
 if r.name==name and ((r.saved and not r.dirty) or r.scheduled or r.writing) then return true end
 r.name=name r.nameRevision+=1
 self:changed(player,r)
 return true
end
function Preferences:setJoinMode(player,mode)
 if not Preferences.validJoinMode(mode) then return false end
 local r=self:record(player)
 if r.joinMode==mode then return true end
 r.joinMode=mode r.modeRevision+=1 self:changed(player,r) return true
end
function Preferences:changed(player,r)
 r.revision+=1 r.dirty=true
 player:SetAttribute("PreferredTikTokUsername",r.name)
 player:SetAttribute("PreferredJoinMode",r.joinMode or "both")
 player:SetAttribute("UsernameSaveStatus","saving")
 if not r.scheduled then
  r.scheduled=true
  self.delay(2,function() r.scheduled=false if self.records[player]==r then self:flush(player) end end)
 end
end
function Preferences:flush(player)
 local r=self.records[player] if not r or not r.dirty or r.writing then return end
 r.writing=true
 for _=1,3 do
  local revision,name,joinMode=r.revision,r.name,r.joinMode
  local writtenAt=DateTime.now().UnixTimestampMillis
  local ok,saved=pcall(self.store.UpdateAsync,self.store,tostring(player.UserId),function(previous)
   if type(previous)=="table" and type(previous.updatedAt)=="number" and previous.updatedAt>writtenAt then return nil end
   return {username=name~="" and name or type(previous)=="table" and previous.username or "",
    joinMode=joinMode or type(previous)=="table" and previous.joinMode or "both",updatedAt=writtenAt}
  end)
  if ok and type(saved)=="table" and (name=="" or saved.username==name) and r.revision==revision then
   if r.name=="" then r.name=Preferences.normalize(saved.username) or "" end
   r.joinMode=saved.joinMode
   r.dirty=false r.saved=true
   if player.Parent then
    player:SetAttribute("PreferredTikTokUsername",r.name) player:SetAttribute("PreferredJoinMode",r.joinMode)
    player:SetAttribute("UsernameSaveStatus","saved")
   end
   break
  end
  self.wait(1)
 end
 r.writing=false
 if r.dirty and player.Parent then player:SetAttribute("UsernameSaveStatus","session") end
end
function Preferences:remove(player)
 self:flush(player)
 self.records[player]=nil
end
return Preferences
