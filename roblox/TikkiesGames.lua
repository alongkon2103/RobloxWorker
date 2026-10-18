-- ServerScriptService only. Event IDs are at-least-once; durable map rewards must be idempotent.
local Http = game:GetService("HttpService")
local Players = game:GetService("Players")
local Module = {}
function Module.start(config)
	assert(type(config.origin) == "string" and config.origin:match("^https://[%w%.%-]+$") and (type(config.credential) == "string" or typeof(config.credential) == "Secret"), "Invalid server configuration")
	assert(Http.HttpEnabled, "Enable HTTP Requests in Game Settings > Security")
	local origin = config.origin .. "/api/games/runtime/server/"
	local alive, token, revision = true, nil, 0
	local nonce = Http:GenerateGUID(false):gsub("%-", "")
	local done, inflight, actors = {}, {}, {}
	local completedCount, inflightCount, actorCount = 0, 0, 0
	local function roster()
        if config.roster then return config.roster() end
		local result = {}
		for _, player in Players:GetPlayers() do table.insert(result, tostring(player.UserId)) end
		assert(#result <= 100, "Tikkies v1 supports up to 100 players per server")
		return result
	end
	local function request(path, body, key)
		local ok, response = pcall(function()
			return Http:RequestAsync({Url = origin .. path, Method = "POST", Headers = {["Content-Type"] = "application/json", Authorization = typeof(key)=="Secret" and key:AddPrefix("Bearer ") or "Bearer "..key}, Body = next(body) == nil and "{}" or Http:JSONEncode(body)})
		end)
		if not ok then return nil, 0, 2 end
		local parsedOk, parsed = pcall(Http.JSONDecode, Http, response.Body)
		return parsedOk and parsed or nil, response.StatusCode, tonumber(response.Headers["retry-after"] or response.Headers["Retry-After"]) or 2
	end
	local function clearSession()
		token = nil
		revision += 1
		actors = {}
		actorCount = 0
		if config.onStatus then config.onStatus("connecting") end
	end
	local function handle(event, sessionToken, ticket)
		if not alive or ticket ~= revision or type(event.id) ~= "string" or type(event.receipt) ~= "string" then return end
		local owner = tonumber(event.ownerRobloxId)
		if not owner or not Players:GetPlayerByUserId(owner) then return end
		local expires = DateTime.fromIsoDate(event.expiresAt)
		if not expires or expires.UnixTimestampMillis <= DateTime.now().UnixTimestampMillis then return end
		local key = event.runId .. ":" .. event.generation
		local actorKey = tostring(event.ownerRobloxId) .. ":" .. key .. ":" .. (event.actorKey or "")
		local result = done[event.id]
		if not result then
			if inflight[event.id] or inflightCount >= 32 or completedCount >= 10000 then return end
			inflight[event.id] = true
			inflightCount += 1
			local ok, value, reason = pcall(function()
				if event.eventType == "connection_test" then
					if config.onConnectionTest then config.onConnectionTest({ownerRobloxId = event.ownerRobloxId, runId = event.runId}) end
					return true
				end
				local data = event.payload
				if type(data) ~= "table" or (data.namespace ~= "test" and data.namespace ~= "live") or not event.actorKey or not event.actorKey:match("^" .. data.namespace .. ":") then return false, "invalid_actor" end
				local context = {eventId = event.id, runId = event.runId, generation = event.generation, ownerRobloxId = event.ownerRobloxId, actorKey = event.actorKey, namespace = data.namespace, robloxId = data.robloxId, robloxUsername = data.robloxUsername, tiktokUsername = data.tiktokUsername, tiktokDisplayName = data.tiktokDisplayName or data.tiktokNickname or data.tiktokUsername, eventType = event.eventType, effects = data.effects, comment = data.comment, giftId = data.giftId, quantity = data.quantity, tiktokAvatarUrl = data.tiktokAvatarUrl}
				if event.eventType == "join" then
					if not actors[actorKey] and actorCount >= 10000 then return false, "viewer_limit" end
					if not config.onViewerJoin then return false, "unsupported_effect" end
					local accepted, failure = config.onViewerJoin(context)
					if accepted == true and ticket == revision and alive then
						if not actors[actorKey] then actorCount += 1 end
						actors[actorKey] = data.robloxId
					end
					return accepted == true, failure
				end
				if actors[actorKey] ~= data.robloxId then return false, "viewer_not_joined" end
				if #data.effects == 0 then
                    if config.onViewerEvent then pcall(config.onViewerEvent, context) end
                    return true
                end
				if not config.onViewerEvent then return false, "unsupported_effect" end
				return config.onViewerEvent(context)
			end)
			inflight[event.id] = nil
			inflightCount -= 1
			result = {ok = ok and value == true, error = ok and reason or "handler_failed", untilTime = os.clock() + 45}
			if not result.ok and (type(result.error) ~= "string" or not result.error:match("^[a-z_]+$") or #result.error > 64) then result.error = "handler_failed" end
			done[event.id] = result
			completedCount += 1
		end
		if ticket ~= revision or not alive then return end
		request("ack", {eventId = event.id, receipt = event.receipt, ok = result.ok, error = not result.ok and result.error or nil}, sessionToken)
	end
	-- Separate presence task: a long poll never delays the 15-second heartbeat.
	task.spawn(function()
		while alive do
			if token then
				local _, status = request("heartbeat", {players = roster()}, token)
				if status == 401 or status == 403 then clearSession() end
			end
			task.wait(15)
		end
	end)
	task.spawn(function()
		local failures = 0
		while alive do
			for id, result in done do if result.untilTime < os.clock() then done[id] = nil; completedCount -= 1 end end
			if not token then
				local result, status = request("register", {universeId = tostring(game.GameId), placeId = tostring(game.PlaceId), jobId = game.JobId ~= "" and game.JobId or "studio", instanceNonce = nonce, players = roster(), giftSource = config.giftSource}, config.credential)
				if result and status == 200 and result.token then token = result.token; revision += 1; failures = 0
                    if config.onStatus then config.onStatus("live") end
				elseif status == 401 or status == 403 then warn("Tikkies: map credential rejected; check the administrator configuration"); alive = false
                    if config.onStatus then config.onStatus("error","tikkies_unauthorized") end
				else
                    if config.onStatus then config.onStatus("retrying",status==0 and "tikkies_network_error" or "tikkies_registration_failed") end
                    failures += 1; task.wait(math.min(20, 2 ^ math.min(failures, 4)) + math.random()) end
			else
				local sessionToken, ticket = token, revision
				local result, status, retry = request("poll", {}, sessionToken)
				if result and status == 200 then
					failures = 0
					for _, event in result.deliveries or {} do task.spawn(function() local ok = pcall(handle, event, sessionToken, ticket); if not ok then warn("Tikkies: invalid event or receiver failure") end end) end
				elseif status == 401 or status == 403 then clearSession()
				else failures += 1; task.wait(math.min(20, math.max(retry, 2 ^ math.min(failures, 4))) + math.random()) end
			end
		end
	end)
	local function stop()
		if not alive then return end
		alive = false
		if token then request("close", {}, token) end
		clearSession()
	end
	game:BindToClose(stop)
	local function resetOwner(ownerId)
        local prefix=ownerId..":"
        for key in actors do if key:sub(1,#prefix)==prefix then actors[key]=nil actorCount-=1 end end
    end
	return {stop = stop,resetOwner=resetOwner}
end
return Module
