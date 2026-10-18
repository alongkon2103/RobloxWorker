return function(Results)
 local function object(attrs)return {GetAttribute=function(_,k)return attrs[k]end}end
 local owner=object({LiveEnabled=true,LiveProvider='direct',LiveUsername='streamer'})owner.UserId=1
 local attrs={ActorKey='tiktok:123',RaceState='Finished',ViewerDisplayName='ชื่อเล่น',RobloxId='2'}
 local m=object(attrs)
 local b=Results.payload(owner,m,'round-guid','job',1000)
 assert(b.name=='ชื่อเล่น'and b.actorKey=='tiktok:123'and b.finishedAt==1000)
 attrs.RaceState='DNF'assert(Results.payload(owner,m,'round-guid','job',1000)==nil)
 attrs.RaceState='Finished'attrs.ActorKey='dev:1'assert(Results.payload(owner,m,'round-guid','job',1000)==nil)
 attrs.ActorKey='test:1'assert(Results.payload(owner,m,'round-guid','job',1000)==nil)
 attrs.ActorKey='live:123'assert(Results.payload(owner,m,'round-guid','job',1000)~=nil)
 return 'TOP WIN payload: finish only, stable identity, filtered names, no dev/test wins'
end
