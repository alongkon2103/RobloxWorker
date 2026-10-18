return function(Preferences)
 local data,jobs,writes={}, {},0
 local store={}
 function store:GetAsync(k) return data[k] end
 function store:UpdateAsync(k,fn) writes+=1 data[k]=fn(data[k]) return data[k] end
 local function player(id)
  local p={UserId=id,Parent=true,attrs={}}
  function p:SetAttribute(k,v) self.attrs[k]=v end
  return p
 end
 local p,q=player(123),player(456)
 local options={delay=function(_,fn)table.insert(jobs,fn)end,wait=function()end}
 local prefs=Preferences.new(store,options)
 prefs:load(p) prefs:load(q)
 assert(q.attrs.PreferredJoinMode=="both","New viewer settings must default to Both")
 assert(prefs:set(p," @First_Name "))
 assert(prefs:set(p,"@shrimprvy11"))
 assert(not prefs:set(q,"https://bad.example"))
 for _,fn in jobs do fn() end jobs={}
 assert(writes==1,"typing burst wrote more than once")
 assert(p.attrs.PreferredTikTokUsername=="shrimprvy11" and p.attrs.UsernameSaveStatus=="saved")
 local again=Preferences.new(store,options)
 local rejoined=player(123)
 again:load(rejoined)
 assert(rejoined.attrs.PreferredTikTokUsername=="shrimprvy11","name did not survive rejoin")
 assert(q.attrs.PreferredTikTokUsername=="","preferences leaked to another owner")
 assert(prefs:set(p,"first_edit"))
 assert(prefs:set(p,"last_edit"))
 assert(prefs:set(p,"last_edit"))
 for _,fn in jobs do fn() end jobs={}
 assert(data["123"].username=="last_edit" and writes==2,"rapid FocusLost/debounce edit was lost")
 assert(prefs:setJoinMode(p,"both")) assert(not prefs:setJoinMode(p,"arbitrary"))
 for _,fn in jobs do fn() end jobs={}
 local savedMode=player(123) Preferences.new(store,options):load(savedMode)
 assert(savedMode.attrs.PreferredJoinMode=="both" and savedMode.attrs.PreferredTikTokUsername=="last_edit")
 local early=Preferences.new(store,options) local earlyPlayer=player(123)
 early:setJoinMode(earlyPlayer,"plain")
 for _,fn in jobs do fn() end jobs={}
 assert(data["123"].username=="last_edit","mode-only save erased stored username")
 local raceStore={}
 function raceStore:GetAsync() prefs:set(p,"new_name") return {username="old_name"} end
 function raceStore:UpdateAsync(_,fn) return fn(nil) end
 prefs=Preferences.new(raceStore,options) prefs:load(p)
 assert(p.attrs.PreferredTikTokUsername=="new_name","late load overwrote typed name")
 data["900"]={username="saved_user",joinMode="at"}
 local explicit=player(900)Preferences.new(store,options):load(explicit)assert(explicit.attrs.PreferredJoinMode=="at","Saved selection was overwritten by default")
 local failStore={GetAsync=function()error("offline")end,UpdateAsync=function()error("offline")end}
 local failed=Preferences.new(failStore,options)
 local f=player(789) failed:load(f) failed:set(f,"remember_me")
 failed:flush(f)
 assert(f.attrs.PreferredTikTokUsername=="remember_me" and f.attrs.UsernameSaveStatus=="session")
 return "Username preferences: durable rejoin, isolation, debounce, late-load race and storage failure passed"
end
