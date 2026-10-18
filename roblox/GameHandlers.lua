-- Viewer NPC handlers; transient effects and receipts remain scoped to each owner/run.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Handlers = {}
local Events=require(game.ReplicatedStorage.RaceEventConfig)
local GiftRosterInfo=require(game.ReplicatedStorage.GiftRosterInfo)
local Config = require(script.Parent.RaceConfig)
local Presentation = require(script.Parent.RacePresentation)
local ViewerRace = require(script.Parent.ViewerRace)
local GojoAbility=require(script.Parent.GojoAbility)
local OctopusAbility=require(script.Parent.OctopusAbility)
local ShieldGuard=require(game.ReplicatedStorage.ShieldGuard)
local arenas, npcCount = {}, 0
local blockedScopes={}
local folder = Instance.new("Folder")
folder.Name = "TikkiesDemoNPCs"
folder.Parent = workspace
local roundReset=Instance.new("BindableEvent")
roundReset.Name="ViewerRoundReset" roundReset.Parent=script.Parent

local function release(reservation)
	if not reservation.released then reservation.released=true npcCount-=1 end
end
local function removeArena(ownerId)
	local arena = arenas[ownerId]
	if not arena then return end
	if arena.race then arena.race:destroy() end
	for _,reservation in pairs(arena.pending) do
		release(reservation) if reservation.model then reservation.model:Destroy() end
	end
	for _, entry in pairs(arena.actors) do
		entry.model:Destroy()
		npcCount = npcCount - 1
	end
	arenas[ownerId] = nil
end

local function identity(context)
	local ownerId, robloxId = tonumber(context.ownerRobloxId), tonumber(context.robloxId)
	if not ownerId or not robloxId or ownerId <= 0 or robloxId <= 0
		or ownerId % 1 ~= 0 or robloxId % 1 ~= 0
		or type(context.runId) ~= "string" or context.generation == nil
		or type(context.actorKey) ~= "string" or not context.actorKey:match("^%a+:.+") then
		return nil
	end
	return tostring(ownerId), tostring(robloxId), context.runId .. ":" .. tostring(context.generation)
end


function Handlers.join(context)
	local ownerId, robloxId, scope = identity(context)
	if not ownerId then return false, "invalid_actor" end
	if blockedScopes[ownerId]==scope then return false,"stale_round" end
	local owner = Players:GetPlayerByUserId(tonumber(ownerId))
	if not owner then return false, "owner_not_present" end
	local world = workspace:FindFirstChild("World")
	local map = world and world:FindFirstChild("Map")
	if not map or not map:FindFirstChild("Checkpoints") then return false, "spawn_unavailable" end
	local arena = arenas[ownerId]
	if arena and arena.scope ~= scope then return false,"stale_round" end
	if arena and arena.race.phase=="Results" then return false,"round_finishing" end
	if not arena then
		arena = {scope = scope, actors = {}, joining = {}, pending = {}, race = ViewerRace.new(owner,map,Config)}
		arenas[ownerId] = arena
		arena.race.onReset=function() blockedScopes[ownerId]=scope removeArena(ownerId) roundReset:Fire(owner) end
		arena.race.onFieldCleared=function()
			-- Release slots now; keep the arena in Results until the ceremony finishes.
			for _ in pairs(arena.actors) do npcCount-=1 end
			arena.actors={}
			for _,reservation in pairs(arena.pending) do
				release(reservation)
				if reservation.model then reservation.model:Destroy() end
			end
			arena.pending={} arena.joining={}
		end
	end
	local existing = arena.actors[context.actorKey]
	if existing and existing.robloxId == robloxId and existing.model.Parent and existing.humanoid.Health > 0 then
		existing.lastSeen = os.clock()
		Presentation.nameplate(existing.model,context.tiktokDisplayName or context.tiktokUsername or existing.username,existing.username)
		return true
	end
	if arena.joining[context.actorKey] then return false, "join_in_progress" end
	-- A superseded or dead avatar frees its slot before reserving the replacement.
	if existing then
		existing.model:Destroy()
		arena.actors[context.actorKey] = nil
		npcCount -= 1
	end
	local ownerCount = 0
	for _ in pairs(arena.actors) do ownerCount += 1 end
	for _ in pairs(arena.joining) do ownerCount += 1 end
	if npcCount >= Config.MaxViewersPerServer or ownerCount >= Config.MaxViewersPerOwner then
		return false, "viewer_limit"
	end
	arena.joining[context.actorKey] = true
	npcCount = npcCount + 1 -- Reserve before the avatar request yields.
	local reservation={released=false} arena.pending[context.actorKey]=reservation
	local began = os.clock()
	local ok, model = pcall(Players.CreateHumanoidModelFromUserIdAsync, Players, tonumber(robloxId))
	if ok then reservation.model=model end
	local humanoid = ok and model:FindFirstChildOfClass("Humanoid")
	local root = ok and model:FindFirstChild("HumanoidRootPart")
	if not ok or not humanoid or not root or os.clock() - began > 10
		or arenas[ownerId] ~= arena or not Players:GetPlayerByUserId(tonumber(ownerId)) then
		if ok then model:Destroy() end
		arena.joining[context.actorKey] = nil arena.pending[context.actorKey]=nil
		release(reservation)
		return false, "avatar_unavailable"
	end
	existing = arena.actors[context.actorKey] -- Idle cleanup may run while the avatar request yields.
	if existing then existing.model:Destroy(); npcCount = npcCount - 1 end
	local slot, occupied = 1, {}
	for _, entry in pairs(arena.actors) do occupied[entry.slot] = true end
	for _, reserved in pairs(arena.joining) do if type(reserved) == "number" then occupied[reserved] = true end end
	while occupied[slot] do slot = slot + 1 end
	if existing then slot = existing.slot end
	arena.joining[context.actorKey] = slot
	model.Name = "Viewer_" .. robloxId
	model:SetAttribute("OwnerRobloxId", ownerId)
	model:SetAttribute("RunId", context.runId)
	model:SetAttribute("Generation", tostring(context.generation))
	model:SetAttribute("ActorKey", context.actorKey)
	model:SetAttribute("RobloxId", robloxId)
	model:SetAttribute("Power", 0)
	model:SetAttribute("ViewerUsername", context.tiktokUsername or context.robloxUsername or robloxId)
	model:SetAttribute("ViewerRobloxUsername", context.robloxUsername or robloxId)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BaseScript") then descendant:Destroy() end
	end
	root.Anchored = true
	model.PrimaryPart = root
	model:PivotTo(CFrame.new(map.Checkpoints:FindFirstChild("Gate_001").Position))
	model.Parent = folder
	model.ModelStreamingMode=Enum.ModelStreamingMode.PersistentPerPlayer
	model:AddPersistentPlayer(owner)
	-- Wait for the avatar's Motor6Ds to assemble before measuring body geometry.
	RunService.Heartbeat:Wait()
	if arenas[ownerId] ~= arena or not owner.Parent then
		model:Destroy() arena.joining[context.actorKey] = nil arena.pending[context.actorKey]=nil release(reservation)
		return false, "owner_not_present"
	end
	local scaled = pcall(Presentation.scaleAvatar, model)
	if not scaled then
		model:Destroy() arena.joining[context.actorKey] = nil arena.pending[context.actorKey]=nil release(reservation)
		return false, "avatar_unavailable"
	end
	if arenas[ownerId] ~= arena or not owner.Parent or arena.race.destroyed or arena.race.phase=="Results" then
		model:Destroy() arena.joining[context.actorKey] = nil arena.pending[context.actorKey]=nil release(reservation)
		return false, "stale_round"
	end
	humanoid.UseJumpPower = true
	local entry = {model = model, humanoid = humanoid, robloxId = robloxId, slot = slot,
		username = context.robloxUsername or robloxId, lastSeen = os.clock(), receipts = {}}
	arena.actors[context.actorKey] = entry
	Presentation.nameplate(model, context.tiktokDisplayName or context.tiktokUsername or entry.username, entry.username)
	if arena.race.phase=="Lobby" then Presentation.arrive(model, owner)
	else Presentation.event(model,owner) end
	arena.race:add(entry)
	arena.joining[context.actorKey] = nil arena.pending[context.actorKey]=nil
	reservation.released=true -- Reservation transfers to the committed actor.
	return true
end

local function amount(effect)
	if type(effect) ~= "table" or (effect.key ~= "power" and effect.key ~= "jump" and effect.key ~= "heal" and not Events[effect.key]) then return nil end
	local value, count = effect.value, effect.count
	if type(value) ~= "number" or type(count) ~= "number" or value ~= value or count ~= count
		or value < 0 or value > 1000000000 or count < 1 or count > 1000000000 or count % 1 ~= 0 then return nil end
	return value * count
end

function Handlers.event(context)
	local ownerId, robloxId, scope = identity(context)
	if not ownerId or not Players:GetPlayerByUserId(tonumber(ownerId)) then return false, "invalid_actor" end
	local arena = arenas[ownerId]
	local entry = arena and arena.scope == scope and arena.actors[context.actorKey]
	if not entry or entry.robloxId ~= robloxId or not entry.model.Parent or entry.humanoid.Health <= 0 then return false, "viewer_not_joined" end
	if type(context.eventId) ~= "string" or context.eventId == "" or type(context.effects) ~= "table" or #context.effects > 200 then return false, "invalid_event" end
	local now, receiptCount = os.clock(), 0
	if #context.effects==0 then
		entry.signals=entry.signals or {}
		if entry.signals[context.eventId] then return true end
		local count,oldest,oldestTime=0,nil,math.huge
		for id,time in pairs(entry.signals) do
			if time<now-60 then entry.signals[id]=nil
			else count+=1 if time<oldestTime then oldest,oldestTime=id,time end end
		end
		if count>=128 then entry.signals[oldest]=nil end
		entry.signals[context.eventId]=now
		Presentation.event(entry.model,Players:GetPlayerByUserId(tonumber(ownerId)))
		return true
	end
	for id, expires in pairs(entry.receipts) do
		if expires <= now then entry.receipts[id] = nil else receiptCount = receiptCount + 1 end
	end
	if entry.receipts[context.eventId] then return true end
	if receiptCount >= 2048 then return false, "event_limit" end
	for _, effect in ipairs(context.effects) do
		if not amount(effect) then return false, "unsupported_effect" end
	end
	-- Validate all effects first; no yielding between applying effects and recording the receipt.
	local speedGift=false
	local astaGift=false
 local cameraEvent=false
	for _, effect in ipairs(context.effects) do
		local value = amount(effect)
  if effect.key~="speed_boost" then cameraEvent=true end
		local boost=Events[effect.key]
		if effect.key=="asta"then astaGift=true end
		if boost and type(boost.SpeedMultiplier)=="number" and boost.SpeedMultiplier>1
			and boost.Kind~="Attack" and boost.Kind~="Defense" then speedGift=true end
		if boost and boost.Kind=="Debuff" then
			OctopusAbility.cast(arena.race,entry)
		elseif boost and boost.Kind=="Attack" then
			GojoAbility.queue(arena.race,entry,effect.count)
		elseif boost and boost.Kind=="Defense" then
   local eventNow=workspace:GetServerTimeNow()
   if arena.race.phase=="Lobby" or arena.race.phase=="Countdown" then
    entry.model:SetAttribute("ShieldPendingSeconds",boost.Duration)
    entry.model:SetAttribute("ShieldUntil",0)
   else ShieldGuard.activate(entry,eventNow) end
  elseif boost and boost.StackMode=="RoundMultiplier" then
			local attribute=boost.Attribute.."Stacks"
			local stacks=entry.model:GetAttribute(attribute) or 0
			entry.model:SetAttribute(attribute,math.min(boost.MaxStacks or 32,stacks+effect.count))
		elseif boost then
			local eventNow=workspace:GetServerTimeNow()
			local paused=arena.race.phase=="Lobby" or arena.race.phase=="Countdown"
			local previousUntil=paused and (eventNow+(entry.model:GetAttribute(boost.Attribute.."PendingSeconds") or 0))
				or (entry.model:GetAttribute(boost.Attribute.."Until") or 0)
			if boost.StackMode=="TimedAdditiveSpeed" then
				local stacks=previousUntil>eventNow and (entry.model:GetAttribute(boost.Attribute.."Stacks") or 1) or 0
				entry.model:SetAttribute(boost.Attribute.."Stacks",stacks+effect.count)
			end
			if not paused and previousUntil<=eventNow then entry.model:SetAttribute(boost.Attribute.."StartedAt",eventNow) end
			local expiresAt
			if boost.TimerMode=="CappedExtension" then
				local remaining=math.max(0,previousUntil-eventNow)
				local extraGifts=effect.count
				if remaining==0 then
					remaining=boost.Duration
					extraGifts-=1
				end
				expiresAt=eventNow+math.min(boost.MaxRemainingSeconds,
					remaining+extraGifts*boost.SecondsPerExtraGift)
			elseif boost.TimerMode=="Refresh" then
				expiresAt=eventNow+boost.Duration
			else
				expiresAt=math.max(eventNow,previousUntil)+boost.Duration*effect.count
			end
			if paused then
				entry.model:SetAttribute(boost.Attribute.."PendingSeconds",expiresAt-eventNow)
				entry.model:SetAttribute(boost.Attribute.."Until",0)
			else
				entry.model:SetAttribute(boost.Attribute.."PendingSeconds",nil)
				entry.model:SetAttribute(boost.Attribute.."Until",expiresAt)
			end
		elseif effect.key == "power" then
			entry.model:SetAttribute("Power", math.min(1000000, entry.model:GetAttribute("Power") + value))
		elseif effect.key == "heal" then
			entry.humanoid.Health = math.min(entry.humanoid.MaxHealth, entry.humanoid.Health + value)
		elseif effect.key == "jump" then
			-- One jump per delivery; combo count increases strength up to the demo cap.
			entry.humanoid.JumpPower = math.min(120, 50 + value)
			entry.humanoid.Jump = true
		end
	end
	entry.receipts[context.eventId] = now + 60
 -- Accepted, deduplicated gifts update the roster; social signals do not.
 entry.model:SetAttribute("ViewerLastGiftText",GiftRosterInfo.summarize(context.effects))
 entry.model:SetAttribute("ViewerLastGiftAt",workspace:GetServerTimeNow())
 entry.model:SetAttribute("ViewerLastGiftRevision",(entry.model:GetAttribute("ViewerLastGiftRevision")or 0)+1)
 if astaGift then
  -- Dedicated revision counts accepted deliveries even with a capped or paused timer.
  entry.model:SetAttribute("AstaCutsceneAt",workspace:GetServerTimeNow())
  entry.model:SetAttribute("AstaCutsceneRevision",(entry.model:GetAttribute("AstaCutsceneRevision")or 0)+1)
 end
	if speedGift then
		-- One authored burst per accepted delivery, including repeats at the timer cap.
		entry.model:SetAttribute("SpeedGiftAt",workspace:GetServerTimeNow())
		entry.model:SetAttribute("SpeedGiftRevision",(entry.model:GetAttribute("SpeedGiftRevision") or 0)+1)
	end
	entry.lastSeen = now
 -- SpeedBoost applies normally without requesting an Auto camera shot.
 if cameraEvent then Presentation.event(entry.model,Players:GetPlayerByUserId(tonumber(ownerId))) end
	return true
end

Players.PlayerRemoving:Connect(function(player) local id=tostring(player.UserId) removeArena(id) blockedScopes[id]=nil end)
function Handlers.clear(player)
	removeArena(tostring(player.UserId))
	player:SetAttribute("ViewerRaceCount",0)
	player:SetAttribute("ViewerRacePhase","Lobby")
	player:SetAttribute("ViewerRacePhaseEndsAt",0)
	player:SetAttribute("ViewerRaceWinner",nil)
	player:SetAttribute("ViewerRaceLeader",nil)
end
local function cleanup()
	for ownerId, arena in pairs(arenas) do
		if not Players:GetPlayerByUserId(tonumber(ownerId)) then removeArena(ownerId)
		else
			for actorKey, entry in pairs(arena.actors) do
				local state=entry.model:GetAttribute("RaceState")
				local racing=state=="Running" or state=="Countdown"
				if not entry.model.Parent or (not racing and os.clock() - entry.lastSeen >= Config.ViewerIdleSeconds) then
					entry.model:Destroy()
					arena.actors[actorKey] = nil
					npcCount = npcCount - 1
				end
			end
		end
	end
	task.delay(30, cleanup)
end
task.delay(30, cleanup)
-- shortcut: demo state and receipts live only in this server process; use durable event IDs for paid rewards.

-- ============================================================
-- Dev Test adapter (server-side only)
-- Reuses the production join/event pipeline; no client authority.
-- DevTestServer checks UI access before calling these functions.
-- ============================================================
local HttpService = game:GetService("HttpService")
local devConfigModule = script.Parent:FindFirstChild("DevTestConfig")
local DevTestConfig = devConfigModule and require(devConfigModule)
	or {Enabled = false, StudioOnly = true, AllowedUserIds = {}}
local devSessions = {}

local DevAccess=require(script.Parent.DevTestAccess)
local function devAllowed(player)
 if typeof(player)~="Instance" or not player:IsA("Player") or not player.Parent then return false end
 return DevAccess.allowed(DevTestConfig,player.UserId,RunService:IsStudio())
end

local function devSession(player, create)
	local ownerId = tostring(player.UserId)
	local current = devSessions[ownerId]
	local arena = arenas[ownerId]

	if arena then
		if not current or arena.scope ~= current.scope then
			return nil, "dev_scope_conflict"
		end
		return current
	end
	if not create then return nil, "dev_session_expired" end

	-- No active arena: new scope, including after a normal round reset.
	local runId = "dev-" .. HttpService:GenerateGUID(false)
	local session = {
		runId = runId,
		generation = 1,
		scope = runId .. ":1",
		actors = {},
	}
	devSessions[ownerId] = session
	return session
end

function Handlers.devJoin(player, avatarUserId, slotIndex)
	if not devAllowed(player) then return false, "dev_not_allowed" end
	if type(avatarUserId) ~= "number" or avatarUserId <= 0
		or avatarUserId % 1 ~= 0 then
		return false, "invalid_avatar"
	end
	if type(slotIndex) ~= "number" or slotIndex <= 0
		or slotIndex % 1 ~= 0 then
		return false, "invalid_slot"
	end

	local session, err = devSession(player, true)
	if not session then return false, err end

	local actorKey = "dev:" .. tostring(slotIndex)
	local context = {
		ownerRobloxId = tostring(player.UserId),
		robloxId = tostring(avatarUserId),
		runId = session.runId,
		generation = session.generation,
		actorKey = actorKey,
		robloxUsername = "Dev_" .. tostring(slotIndex),
		tiktokUsername = "Dev_" .. tostring(slotIndex),
	}

	local success, reason = Handlers.join(context)
	if not success then return false, reason end

	session.actors[actorKey] = tostring(avatarUserId)
	return true, "spawned", actorKey
end

function Handlers.devEvent(player, actorKey, eventKey)
	if not devAllowed(player) then return false, "dev_not_allowed" end
	if type(actorKey) ~= "string" or #actorKey > 200 then
		return false, "invalid_actor"
	end
	if type(eventKey) ~= "string" or not Events[eventKey] then
		return false, "invalid_event_key"
	end

	local session, err = devSession(player, false)
	if not session then return false, err end
	local robloxId = session.actors[actorKey]
	if not robloxId then return false, "dev_actor_not_found" end

	local arena = arenas[tostring(player.UserId)]
	if not arena or arena.scope ~= session.scope then
		return false, "dev_session_expired"
	end

	return Handlers.event({
		ownerRobloxId = tostring(player.UserId),
		robloxId = robloxId,
		runId = session.runId,
		generation = session.generation,
		actorKey = actorKey,
		eventId = "dev-event-" .. HttpService:GenerateGUID(false),
		effects = {{key = eventKey, value = 1, count = 1}},
	})
end

Players.PlayerRemoving:Connect(function(player)
	devSessions[tostring(player.UserId)] = nil
end)
-- ============================================================

return Handlers

