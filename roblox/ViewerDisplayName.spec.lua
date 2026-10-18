return function(Names)
 local calls=0
 local service={FilterStringAsync=function(_,raw,owner)
  calls+=1 assert(owner==42)assert(raw=="ชื่อเล่น ทดสอบ")
  return {GetNonChatStringForBroadcastAsync=function()return "ชื่อเล่น ทดสอบ"end}
 end}
 local value,ok=Names.filter("  ชื่อเล่น\nทดสอบ  ",42,service)
 assert(ok and value=="ชื่อเล่น ทดสอบ"and calls==1)
 value,ok=Names.filter("unsafe text",42,{FilterStringAsync=function()error("unavailable")end})
 assert(not ok and value=="Viewer","Never display the raw name on filter failure")
 value,ok=Names.filter("",42,service)assert(not ok and value=="Viewer")
 return true
end
