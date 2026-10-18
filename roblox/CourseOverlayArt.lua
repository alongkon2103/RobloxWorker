-- Render once at 3x resolution; positions remain separate live UI markers.
local Art={}
local active=setmetatable({}, {__mode='k'})
function Art.draw(parent,points,colors)
 if active[parent]then active[parent]:Destroy()active[parent]=nil end
 local ok,img=pcall(function()return game:GetService('AssetService'):CreateEditableImage({Size=Vector2.new(990,900)})end)
 if not ok or not img then return false end
 local drawn=pcall(function()
  local layers={{width=6,color=Color3.fromRGB(13,26,45)},{width=4.4,color=Color3.fromRGB(255,249,231)},{width=3,color=false}}
  for _,layer in layers do
   for i,a in points do
    local b=points[i%#points+1]local length=(b-a).Magnitude*3
    local steps=math.max(1,math.ceil(length/1.5))
    local color=layer.color or colors[math.min(4,math.floor((i-1)/#points*4)+1)]
    for k=0,steps do img:DrawCircle(a:Lerp(b,k/steps)*3,layer.width*1.5,color,0,Enum.ImageCombineType.BlendSourceOver)end
    if i%128==0 then task.wait()end
   end
  end
  local image=Instance.new('ImageLabel')image.Name='SmoothRoute'image.BackgroundTransparency=1 image.Size=UDim2.fromScale(1,1)image.ImageContent=Content.fromObject(img)image.ZIndex=3 image.Parent=parent
 end)
 if not drawn then img:Destroy()return false end
 active[parent]=img return true
end
return Art
