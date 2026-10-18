-- ServerScriptService only. Event IDs are at-least-once; durable map rewards must be idempotent.
local Http = game:GetService("HttpService")
local Players = game:GetService("Players")
local Module = {}
function Module.start(config)
	assert(type(config.origin) == "string" and config.origin:match("^https://[%w%.%-]+$") and (type(config.credential) == "string" or typeof(config.credential) == "Secret"), "Invalid server configuration")
	assert(config.request or Http.HttpEnabled, "Enable HTTP Requests in Game Settings > Security")
	local origin = config.origin .. "/api/games/runtime/server/"
	local alive, token, revision = true, nil, 0
	local batchAck, allowCapabilities, pipeline = false, true, false
	local pending, actorQueues = {}, {}
	local pendingCount, legacyPending, ackRunning = 0, 0, false
	local acquire = config.acquire or require(script.Parent.LiveHttpBudget).acquire
	local nonce = Http:GenerateGUID(false):gsub("%-", "")
	local done, inflight, actors = {}, {}, {}
	local completedCount, inflightCount, actorCount, joinSequence = 0, 0, 0, 0
	local function roster()
        if config.roster then return config.roster() end
		local result = {}
		for _, player in Players:GetPlayers() do table.insert(result, tostring(player.UserId)) end
		assert(#result <= 100, "Tikkies v1 supports up to 100 players per server")
		return result
	end
	local function request(path, body, key)
		local ticket = revision
		local function current()
			if ticket ~= revision then return false end
			if path == "close" then return token == key end
			return alive and (path == "register" and token == nil or token == key)
		end
		local kind = path == "poll" and "tikkies_poll" or ((path == "ack" or path == "ack-batch") and "tikkies_ack" or "tikkies_heartbeat")
		if not acquire(kind, current) or not current() then return nil, 0, 2 end
		if config.request then
			local ok, data, status, retry = pcall(config.request, path, body, key)
			return ok and data or nil, ok and status or 0, retry or 2
		end
		local ok, response = pcall(function()
			return Http:RequestAsync({Url = origin .. path, Method = "POST", Headers = {["Content-Type"] = "application/json", Authorization = typeof(key)=="Secret" and key:AddPrefix("Bearer ") or "Bearer "..key}, Body = next(body) == nil and "{}" or Http:JSONEncode(body)})
		end)
		if not ok then return nil, 0, 2 end
		local parsedOk, parsed = pcall(Http.JSONDecode, Http, response.Body)
		return parsedOk and type(parsed) == "table" and parsed or nil, response.StatusCode, tonumber(response.Headers["retry-after"] or response.Headers["Retry-After"]) or 2
	end
	local function release(record)
		if pending[record.event.id] == record then pending[record.event.id] = nil; pendingCount -= 1 end
	end
	local function clearSession()
		token = nil
		revision += 1
		for _, record in pending do if not record.processing or not alive then release(record) end end
		for _, queue in actorQueues do
			for index = #queue.rows, 1, -1 do if pending[queue.rows[index].event.id] ~= queue.rows[index] then table.remove(queue.rows, index) end end
		end
		-- Refreshing a token keeps confirmed bindings scoped by owner/run/generation.
		if not alive then actors = {}; actorCount = 0 end
		if config.onStatus then config.onStatus("connecting") end
	end
	local function handle(event, sessionToken, ticket)
		if not alive or ticket ~= revision or type(event) ~= "table" or type(event.id) ~= "string" or type(event.receipt) ~= "string" or type(event.runId) ~= "string" or (type(event.generation) ~= "string" and type(event.generation) ~= "number") then return end
		local owner = tonumber(event.ownerRobloxId)
		if not owner or not Players:GetPlayerByUserId(owner) then return end
		local expires = DateTime.fromIsoDate(event.expiresAt)
		if not expires or expires.UnixTimestampMillis <= DateTime.now().UnixTimestampMillis then return end
		local key = event.runId .. ":" .. event.generation
		local actorKey = tostring(event.ownerRobloxId) .. ":" .. key .. ":" .. (event.actorKey or "")
		while inflight[event.id] and alive and ticket == revision do task.wait() end
		if not alive or ticket ~= revision then return end
		local result = done[event.id]
		if not result then
			if inflight[event.id] or inflightCount >= 32 or completedCount >= 10000 then return end
			inflight[event.id] = true
			inflightCount += 1
			local binding
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
					joinSequence += 1
					binding = {owner = event.ownerRobloxId, runId = event.runId, generation = event.generation, actorKey = event.actorKey, robloxId = data.robloxId, namespace = data.namespace, sequence = joinSequence}
					local accepted, failure = config.onViewerJoin(context)
					return accepted == true, failure
				end
				if not actors[actorKey] or actors[actorKey].robloxId ~= data.robloxId then return false, "viewer_not_joined" end
				if #data.effects == 0 then
                    if config.onViewerEvent then pcall(config.onViewerEvent, context) end
                    return true
                end
				if not config.onViewerEvent then return false, "unsupported_effect" end
				return config.onViewerEvent(context)
			end)
			inflight[event.id] = nil
			inflightCount -= 1
			result = {ok = ok and value == true, error = ok and reason or "handler_failed", binding = ok and value == true and binding or nil, untilTime = os.clock() + math.max(45, (expires.UnixTimestampMillis - DateTime.now().UnixTimestampMillis) / 1000 + 30)}
			if not result.ok and (type(result.error) ~= "string" or not result.error:match("^[a-z_]+$") or #result.error > 64) then result.error = "handler_failed" end
			done[event.id] = result
			completedCount += 1
		end
		if ticket ~= revision or not alive then return end
		if result.binding then
			local binding, data = result.binding, event.payload
			if event.eventType ~= "join" or event.ownerRobloxId ~= binding.owner or event.runId ~= binding.runId
				or event.generation ~= binding.generation or event.actorKey ~= binding.actorKey or type(data) ~= "table"
				or data.robloxId ~= binding.robloxId or data.namespace ~= binding.namespace or not Players:GetPlayerByUserId(owner) then return end
			local previous = actors[actorKey]
			-- A successful join may finish across token refresh; replay restores its binding without rejoining.
			if not previous or previous.sequence <= binding.sequence then
				if not previous then if actorCount >= 10000 then return end actorCount += 1 end
				actors[actorKey] = binding
			end
		end
		return {eventId = event.id, receipt = event.receipt, ok = result.ok, error = not result.ok and result.error or nil}
	end
	local function flushReady()
		if ackRunning then return end
		ackRunning = true
		task.spawn(function()
			task.wait(.05)
			while alive do
				local entries, receipts, ticket, sessionToken = {}, {}, revision, token
				for _, record in pending do
					if record.ready and record.ticket == ticket and record.token == sessionToken then
						table.insert(entries, {record = record, version = record.version})
						table.insert(receipts, record.ready)
						if #entries >= (batchAck and 32 or 1) then break end
					elseif record.ready and record.ticket ~= ticket then release(record) end
				end
				if #entries == 0 then break end
				local _, status = request(batchAck and "ack-batch" or "ack", batchAck and {receipts = receipts} or receipts[1], sessionToken)
				for _, entry in entries do if entry.record.version == entry.version then release(entry.record) end end
				if (status == 401 or status == 403) and ticket == revision then clearSession() end
			end
			ackRunning = false
		end)
	end
	local function queueRecord(record)
		if record.processing or record.queued then return end
		local actor = record.actor
		local queue = actorQueues[actor]
		if not queue then queue = {rows = {}, running = false}; actorQueues[actor] = queue end
		record.queued = true
		table.insert(queue.rows, record)
		if queue.running then return end
		queue.running = true
		task.spawn(function()
			while #queue.rows > 0 and alive do
				local item = table.remove(queue.rows, 1)
				item.queued = false
				if pending[item.event.id] == item then
					item.processing = true
					local ok, receipt, version
					repeat
						version = item.version
						ok, receipt = pcall(handle, item.event, item.token, item.ticket)
					until version == item.version or not alive or pending[item.event.id] ~= item
					item.processing = false
					if ok and receipt and item.ticket == revision and alive then item.ready = receipt; flushReady()
					else if not ok then warn("Tikkies: invalid event or receiver failure") end release(item) end
				end
			end
			if actorQueues[actor] == queue then actorQueues[actor] = nil end
		end)
	end
	local function dispatch(deliveries, sessionToken, ticket)
		for _, event in deliveries do
			if type(event) == "table" and type(event.id) == "string" then
				local record = pending[event.id]
				if not record and pendingCount + legacyPending < 32 then
					record = {event = event, actor = tostring(event.ownerRobloxId) .. ":" .. tostring(event.runId) .. ":" .. tostring(event.generation) .. ":" .. tostring(event.actorKey), version = 0}
					pending[event.id] = record; pendingCount += 1
				end
				if record then
					record.event = event; record.token = sessionToken; record.ticket = ticket
					record.version += 1; record.ready = nil
					queueRecord(record)
				end
			end
		end
	end
	local function processBatch(deliveries, sessionToken, ticket)
		local groups, receipts, pending = {}, {}, 0
		for _, event in deliveries do
			if type(event) == "table" then
				local actor = tostring(event.ownerRobloxId) .. ":" .. tostring(event.runId) .. ":" .. tostring(event.generation) .. ":" .. tostring(event.actorKey)
				groups[actor] = groups[actor] or {}
				table.insert(groups[actor], event)
				legacyPending += 1
			end
		end
		-- One slow avatar can yield without racing its own next event or blocking other actors.
		for _, events in groups do
			pending += 1
			task.spawn(function()
				for _, event in events do
					local ok, receipt = pcall(handle, event, sessionToken, ticket)
					if not ok then warn("Tikkies: invalid event or receiver failure")
					elseif receipt then
						if batchAck then table.insert(receipts, receipt)
						else
							local _, status = request("ack", receipt, sessionToken)
							if (status == 401 or status == 403) and ticket == revision then clearSession() end
						end
					end
					legacyPending -= 1
				end
				pending -= 1
			end)
		end
		while pending > 0 and alive and ticket == revision do task.wait() end
		if batchAck and #receipts > 0 and alive and ticket == revision then
			local _, status = request("ack-batch", {receipts = receipts}, sessionToken)
			if (status == 401 or status == 403) and ticket == revision then clearSession() end
		end
	end
	-- Separate presence task: a long poll never delays the 15-second heartbeat.
	task.spawn(function()
		while alive do
			if token then
				local sessionToken = token
				local _, status = request("heartbeat", {players = roster()}, sessionToken)
				if (status == 401 or status == 403) and token == sessionToken then clearSession() end
			end
			task.wait(15)
		end
	end)
	task.spawn(function()
		local failures = 0
		while alive do
			for id, result in done do if result.untilTime < os.clock() then done[id] = nil; completedCount -= 1 end end
			if not token then
				local result, status = request("register", {universeId = tostring(game.GameId), placeId = tostring(game.PlaceId), jobId = game.JobId ~= "" and game.JobId or "studio", instanceNonce = nonce, players = roster(), giftSource = config.giftSource, capabilities = allowCapabilities and {batchAck = true, receiptCacheV2 = true} or nil}, config.credential)
				if result and status == 200 and result.token then token = result.token; revision += 1; failures = 0
					batchAck = type(result.capabilities) == "table" and result.capabilities.batchAck == true
					pipeline = type(result.capabilities) == "table" and result.capabilities.boundedPipeline == true
                    if config.onStatus then config.onStatus("live") end
				elseif status == 400 and allowCapabilities and result and result.error == "invalid_input" then
					allowCapabilities = false -- Older backends strictly reject new registration fields.
				elseif status == 401 or status == 403 then warn("Tikkies: map credential rejected; check the administrator configuration"); alive = false
                    if config.onStatus then config.onStatus("error","tikkies_unauthorized") end
				else
                    if config.onStatus then config.onStatus("retrying",status==0 and "tikkies_network_error" or "tikkies_registration_failed") end
                    failures += 1; task.wait(math.min(20, 2 ^ math.min(failures, 4)) + math.random()) end
			elseif pendingCount + legacyPending >= 32 or (not pipeline and pendingCount > 0) then task.wait(.03)
			else
				local sessionToken, ticket = token, revision
				local result, status, retry = request("poll", pipeline and {limit = 32 - pendingCount - legacyPending} or {}, sessionToken)
				if ticket ~= revision then
					-- A heartbeat may replace the session while the previous poll is still returning.
				elseif result and status == 200 then
					failures = 0
					local deliveries = type(result.deliveries) == "table" and result.deliveries or {}
					if pipeline then dispatch(deliveries, sessionToken, ticket) else processBatch(deliveries, sessionToken, ticket) end
				elseif (status == 401 or status == 403) and ticket == revision then clearSession()
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
