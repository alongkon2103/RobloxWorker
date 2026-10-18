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
 local safeService={FilterStringAsync=function(_,raw)
  return {GetNonChatStringForBroadcastAsync=function()return raw=='ชื่อที่ถูกกรอง'and '############'or raw end}
 end}
 value,ok=Names.filter('ชื่อที่ถูกกรอง',42,safeService,'runner_thai')
 assert(ok and value=='runner_thai','A fully masked nickname must use the separately filtered TikTok handle')
 value,ok=Names.filter('นักวิ่งสายฟ้า',42,safeService,'runner_thai')
 assert(ok and value=='นักวิ่งสายฟ้า','Readable Thai must remain Thai')
 value,ok=Names.filter('ชื่อที่ถูกกรอง',42,safeService,'ชื่อที่ถูกกรอง')
 assert(not ok and value=='Viewer','Never reveal a masked nickname or masked fallback')
 value,ok=Names.filter('ชื่อที่ถูกกรอง',42,{FilterStringAsync=function()error('unavailable')end},'runner_thai')
 assert(not ok and value=='Viewer','Filter failures must never expose the fallback')
 value,ok=Names.filter(string.char(255),42,safeService,'runner_thai')
 assert(ok and value=='runner_thai','Invalid UTF-8 must fall back safely')
 value,ok=Names.filter(string.rep('ก',61),42,safeService)
 assert(ok and utf8.len(value)==60,'Thai truncation must preserve UTF-8')
 local filteredInputs={}
 local fallbackService={FilterStringAsync=function(_,raw)
  table.insert(filteredInputs,raw)
  return {GetNonChatStringForBroadcastAsync=function()
   return raw=='handle_safe'and 'safe_handle_filtered'or '########'
  end}
 end}
 value,ok=Names.filter('blocked_nickname',42,fallbackService,'handle_safe')
 assert(ok and value=='safe_handle_filtered' and #filteredInputs==2 and filteredInputs[2]=='handle_safe',
  'Fallback must use the filter output, never the raw handle')
 value,ok=Names.filter('blocked_nickname',42,fallbackService,'other_blocked_handle')
 assert(not ok and value=='Viewer','A separately masked handle must remain hidden')
 return true
end
