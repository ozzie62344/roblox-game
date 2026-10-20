-- CUSTOM matches (lobby servers): a private lobby for you and your friends, with a 6-character
-- code (client Match/CustomMatchMenu; settings and their options: shared/CustomMatch).
--   CustomMatch:FireServer("Create")                  open a lobby (you host it)
--   CustomMatch:FireServer("Join", code)              join by code: a lobby on this server right
--                                                     away; one on another lobby server sends you
--                                                     there first (TeleportAsync to its JobId) and
--                                                     you join when you land
--   CustomMatch:FireServer("Leave")                   the host leaving hands the lobby to the next one in
--   CustomMatch:FireServer("Invite", player)          ask someone in this server (any member can)
--   CustomMatch:FireServer("Accept", code) / ("Decline", code)
--   CustomMatch:FireServer("Kick", player)            host only (they can't come back to that lobby)
--   CustomMatch:FireServer("Move", player, team)      host only: "Blue", "Orange" or "Spectate"
--   CustomMatch:FireServer("MoveSelf", team)          ...the host moving themselves
--   CustomMatch:FireServer("Shuffle")                 host only: everyone on a team, mixed up evenly
--   CustomMatch:FireServer("Set", key, value)         host only: one of shared/CustomMatch's settings
--   CustomMatch:FireServer("Start")                   host only: at least one player on a team
--   CustomMatch:FireClient(player, "State", view?)    your lobby as it is now (nil: you're not in one)
--   CustomMatch:FireClient(player, "Invite", from, code, seconds)
--   CustomMatch:FireClient(player, "Notice", text)
--   CustomMatch:FireClient(player, "Starting", travel?)   the match is starting (or, travel = true,
--                                                     you're off to the lobby's server): loading screen
-- The host's server owns the lobby. Its code points at this server in a MemoryStore hash map
-- (code → { JobId, PlaceId }), refreshed while the lobby is open and removed when it closes, so
-- players on other lobby servers can find it. START works like a full queue (Matchmaker): a
-- reserved match server, everyone teleported with { Custom = true, Players, Teams, Parties,
-- Settings }; RoundService plays it there with the host's settings and no rewards, then sends
-- everyone back to a lobby. Players the host left off both teams go along as spectators.
-- Studio can't teleport: there START plays the match right here (RoundService.ForceStart with the
-- teams and settings), and codes only work on this server.
-- Members have the "CustomLobby" attribute (the code): Matchmaker won't queue them.

local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local CustomMatch = require(ReplicatedStorage.Shared.CustomMatch)
local MatchConfig = require(ReplicatedStorage.Shared.MatchConfig)
local MapService = require(script.Parent.MapService)
local MatchTicket = require(script.Parent.MatchTicket)
local Matchmaker = require(script.Parent.Matchmaker)
local PartyService = require(script.Parent.PartyService)
local RoundService = require(script.Parent.RoundService)

local MatchState = ReplicatedStorage.MatchState

local CustomMatchService = {}

local INVITE_TIME = 30 -- seconds an invite can be answered
local SNOOZE_TIME = 30 -- after a NO, that lobby can't ask the same person again for this long
local START_DELAY = 2 -- "MATCH STARTING" on screen before the teleport
local CODE_LIFETIME = 3 * 60 * 60 -- seconds a code stays in the MemoryStore without a refresh
local REFRESH_EVERY = 10 * 60
local LOOKUP_COOLDOWN = 2 -- seconds between one player's Create / Join (MemoryStore calls)
local TEAMS = MatchConfig.TeamOrder

type Lobby = {
	code: string,
	members: { Player }, -- host first, then in the order they came
	team: { [Player]: string? }, -- "Blue" / "Orange"; not in here = spectating
	settings: CustomMatch.Settings,
	kicked: { [number]: boolean }, -- UserIds the host kicked (they can't come back)
	starting: boolean,
}

type Invite = { from: Player, ends: number }

local Remote: RemoteEvent
local codeMap: MemoryStoreHashMap? = nil -- (nil in Studio, or if MemoryStores aren't available)

local lobbies: { [string]: Lobby } = {}
local lobbyOf: { [Player]: Lobby } = {}
local invites: { [Player]: { [string]: Invite } } = {} -- invitee → code → the invite
local snoozed: { [Player]: { [string]: number } } = {} -- invitee → code → no new invites until then
local lastRequest: { [Player]: number } = {}
local lastLookup: { [Player]: number } = {}
local busy: { [Player]: boolean } = {} -- a Create / Join is waiting on the MemoryStore
local travelling: { [Player]: boolean } = {} -- being teleported (to a lobby's server or a match)

-- Lobbies are only made and changed on a lobby server, between matches
local function canUse(): boolean
	return MatchState:GetAttribute("ServerKind") == "Lobby" and MatchState:GetAttribute("Phase") == "Waiting"
		and not RoundService.IsMatchRunning()
end

local function notice(player: Player, text: string)
	if player.Parent then
		Remote:FireClient(player, "Notice", string.upper(text))
	end
end

local function noticeAll(lobby: Lobby, text: string, except: Player?)
	for _, member in lobby.members do
		if member ~= except then
			notice(member, text)
		end
	end
end

local function count(lobby: Lobby, teamName: string): number
	local n = 0
	for _, member in lobby.members do
		if lobby.team[member] == teamName then
			n += 1
		end
	end
	return n
end

-- The emptier team with room left, or nil (both full: spectate)
local function openTeam(lobby: Lobby): string?
	local best, fewest = nil, CustomMatch.TeamSize
	for _, name in TEAMS do
		local n = count(lobby, name)
		if n < fewest then
			best, fewest = name, n
		end
	end
	return best
end

-- Sends every member the lobby as it is now
local function publish(lobby: Lobby)
	local members = {}
	for _, member in lobby.members do
		table.insert(members, { Player = member, Team = lobby.team[member] or "" })
	end
	local view = {
		Code = lobby.code,
		Host = lobby.members[1],
		Members = members,
		Settings = table.clone(lobby.settings),
		Maps = MapService.MapNames,
		TeamSize = CustomMatch.TeamSize,
		MaxPlayers = CustomMatch.MaxPlayers,
		Starting = lobby.starting,
	}
	for _, member in lobby.members do
		member:SetAttribute("CustomLobby", lobby.code)
		Remote:FireClient(member, "State", view)
	end
end

-- ─── Codes (MemoryStore) ───────────────────────────────────────────────────────

local function randomCode(): string
	local alphabet = CustomMatch.CodeAlphabet
	local chars = {}
	for i = 1, CustomMatch.CodeLength do
		local at = math.random(#alphabet)
		chars[i] = string.sub(alphabet, at, at)
	end
	return table.concat(chars)
end

-- A code in the right shape (any case), uppercased; nil if it can't be one
local function cleanCode(raw: any): string?
	if typeof(raw) ~= "string" or #raw ~= CustomMatch.CodeLength then
		return nil
	end
	local code = string.upper(raw)
	for i = 1, #code do
		if not string.find(CustomMatch.CodeAlphabet, string.sub(code, i, i), 1, true) then
			return nil
		end
	end
	return code
end

-- Claims `code` for this server in the MemoryStore: false if another server already has it.
-- (No MemoryStore: true, the code just only works on this server.)
local function claim(code: string): boolean
	local map = codeMap
	if not map then
		return true
	end
	local ok, result = pcall(function()
		return map:UpdateAsync(code, function(old)
			if old ~= nil then
				return nil -- (taken: leave it alone)
			end
			return { JobId = game.JobId, PlaceId = game.PlaceId }
		end, CODE_LIFETIME)
	end)
	if not ok then
		warn("Custom lobby code couldn't be registered:", result)
		return true
	end
	return result ~= nil
end

local function release(code: string)
	local map = codeMap
	if map then
		task.spawn(pcall, function()
			map:RemoveAsync(code)
		end)
	end
end

-- Where `code`'s lobby is: its server's JobId, or nil (no such lobby, or no MemoryStore)
local function lookUp(code: string): string?
	local map = codeMap
	if not map then
		return nil
	end
	local ok, value = pcall(function()
		return map:GetAsync(code)
	end)
	if ok and typeof(value) == "table" and value.PlaceId == game.PlaceId and typeof(value.JobId) == "string" and value.JobId ~= "" then
		return value.JobId
	end
	return nil
end

-- ─── Lobbies ───────────────────────────────────────────────────────────────────

local function close(lobby: Lobby)
	if lobbies[lobby.code] ~= lobby then
		return
	end
	lobbies[lobby.code] = nil
	release(lobby.code)
	for _, member in lobby.members do
		if lobbyOf[member] == lobby then
			lobbyOf[member] = nil
			member:SetAttribute("CustomLobby", nil)
			if member.Parent then
				Remote:FireClient(member, "State", nil)
			end
		end
	end
	table.clear(lobby.members)
end

-- Takes `player` out of their lobby and tells the rest (`message`). The next one in hosts if the
-- host left; nobody left closes it.
local function remove(player: Player, message: string?)
	local lobby = lobbyOf[player]
	if not lobby then
		return
	end
	local wasHost = lobby.members[1] == player
	table.remove(lobby.members, table.find(lobby.members, player) :: number)
	lobby.team[player] = nil
	lobbyOf[player] = nil
	player:SetAttribute("CustomLobby", nil)
	if player.Parent then
		Remote:FireClient(player, "State", nil)
	end
	if #lobby.members == 0 then
		close(lobby)
		return
	end
	if message then
		noticeAll(lobby, if wasHost then `{message} · {lobby.members[1].DisplayName} hosts now` else message)
	end
	publish(lobby)
end

-- Puts `player` in `lobby` (out of the one they're in first), on the emptier team if there's room
local function add(lobby: Lobby, player: Player): boolean
	if lobbyOf[player] == lobby then
		return true
	elseif lobby.starting then
		notice(player, "That match is already starting")
		return false
	elseif #lobby.members >= CustomMatch.MaxPlayers then
		notice(player, "That lobby is full")
		return false
	elseif lobby.kicked[player.UserId] then
		notice(player, "You were kicked from that lobby")
		return false
	end
	if lobbyOf[player] then
		remove(player, `{player.DisplayName} left the lobby`)
	end
	Matchmaker.StopSearch(player, `{player.DisplayName} went into a custom lobby · search stopped`)
	noticeAll(lobby, `{player.DisplayName} joined the lobby`)
	table.insert(lobby.members, player)
	lobby.team[player] = openTeam(lobby)
	lobbyOf[player] = lobby
	publish(lobby)
	return true
end

local function create(player: Player)
	local code: string? = nil
	for _ = 1, 8 do
		local candidate = randomCode()
		if not lobbies[candidate] and claim(candidate) then
			code = candidate
			break
		end
	end
	if not code or not player.Parent or not canUse() then
		if code then
			release(code)
		end
		notice(player, "Couldn't open a lobby · try again")
		return
	end
	local lobby: Lobby = {
		code = code,
		members = {},
		team = {},
		settings = CustomMatch.Defaults(),
		kicked = {},
		starting = false,
	}
	lobbies[code] = lobby
	if not add(lobby, player) then
		close(lobby)
	end
end

-- Off to the server `code`'s lobby is on; joins it there when they land (onPlayerAdded)
local function travel(player: Player, code: string, jobId: string)
	travelling[player] = true
	Remote:FireClient(player, "Starting", true)
	local ok, err = pcall(function()
		local options = Instance.new("TeleportOptions")
		options.ServerInstanceId = jobId
		options:SetTeleportData({ CustomCode = code })
		TeleportService:TeleportAsync(game.PlaceId, { player }, options)
	end)
	if not ok then
		travelling[player] = nil
		warn("Teleport to a custom lobby failed:", err)
		notice(player, "Couldn't reach that lobby's server · try again")
	end
end

local function join(player: Player, code: string)
	local lobby = lobbies[code]
	if lobby then
		add(lobby, player)
		return
	end
	local jobId = lookUp(code)
	if not player.Parent or not canUse() then
		return
	end
	lobby = lobbies[code] -- (it may have opened here while we looked)
	if lobby then
		add(lobby, player)
	elseif jobId and jobId ~= game.JobId then
		if lobbyOf[player] then
			remove(player, `{player.DisplayName} left the lobby`)
		end
		notice(player, "Joining that lobby's server...")
		travel(player, code, jobId)
	else
		notice(player, `No lobby with the code {code}`)
	end
end

local function invite(player: Player, target: Player)
	local lobby = lobbyOf[player]
	if not lobby or lobby.starting or lobbyOf[target] == lobby then
		return
	end
	if #lobby.members >= CustomMatch.MaxPlayers then
		notice(player, "Your lobby is full")
		return
	end
	local now = os.clock()
	local theirs = invites[target] or {}
	local quiet = snoozed[target]
	local pending = theirs[lobby.code]
	if (pending and pending.ends > now) or (quiet and (quiet[lobby.code] or 0) > now) then
		return -- (asked already, or they just said no)
	end
	theirs[lobby.code] = { from = player, ends = now + INVITE_TIME }
	invites[target] = theirs
	Remote:FireClient(target, "Invite", player, lobby.code, INVITE_TIME)
	notice(player, `Invite sent to {target.DisplayName}`)
end

local function answer(player: Player, code: string, accepted: boolean)
	local theirs = invites[player]
	local pending = theirs and theirs[code]
	if not theirs or not pending then
		return
	end
	theirs[code] = nil
	local lobby = lobbies[code]
	if not accepted then
		local quiet = snoozed[player] or {}
		quiet[code] = os.clock() + SNOOZE_TIME
		snoozed[player] = quiet
		if pending.from.Parent then
			notice(pending.from, `{player.DisplayName} said no`)
		end
	elseif pending.ends < os.clock() then
		notice(player, "That invite ran out")
	elseif not lobby then
		notice(player, "That lobby closed")
	else
		add(lobby, player)
	end
end

-- The host's own changes: only while the lobby isn't starting
local function hosted(player: Player): Lobby?
	local lobby = lobbyOf[player]
	if lobby and lobby.members[1] == player and not lobby.starting then
		return lobby
	end
	return nil
end

local function kick(player: Player, target: Player)
	local lobby = hosted(player)
	if lobby and target ~= player and lobbyOf[target] == lobby then
		lobby.kicked[target.UserId] = true
		remove(target, `{target.DisplayName} was kicked`)
		notice(target, `{player.DisplayName} kicked you from the lobby`)
	end
end

local function move(player: Player, target: Player, teamName: any)
	local lobby = hosted(player)
	if not lobby or lobbyOf[target] ~= lobby or (teamName ~= "Spectate" and not table.find(TEAMS, teamName)) then
		return
	end
	if teamName == "Spectate" then
		lobby.team[target] = nil
	elseif lobby.team[target] ~= teamName then
		if count(lobby, teamName) >= CustomMatch.TeamSize then
			notice(player, `{teamName} is full`)
			return
		end
		lobby.team[target] = teamName
	end
	publish(lobby)
end

-- Everyone on a team, mixed up and dealt out evenly (spectators stay spectators)
local function shuffle(player: Player)
	local lobby = hosted(player)
	if not lobby then
		return
	end
	local playing = {}
	for _, member in lobby.members do
		if lobby.team[member] then
			table.insert(playing, member)
		end
	end
	for i = #playing, 2, -1 do
		local j = math.random(i)
		playing[i], playing[j] = playing[j], playing[i]
	end
	local first = math.random(2) -- (with an odd number, either team can get the extra player)
	for i, member in playing do
		lobby.team[member] = TEAMS[(i + first) % 2 + 1]
	end
	publish(lobby)
end

local function set(player: Player, key: any, value: any)
	local lobby = hosted(player)
	if not lobby or typeof(key) ~= "string" or not CustomMatch.ByKey[key] then
		return
	end
	if value ~= nil and table.find(CustomMatch.Options(key, MapService.MapNames), value) then
		lobby.settings[key] = value
		publish(lobby)
	end
end

-- START: everyone in the lobby goes to a match server of their own (Studio: plays it right here)
local function start(player: Player)
	local lobby = hosted(player)
	if not lobby then
		return
	end
	if not canUse() then
		notice(player, "Can't start right now")
		return
	end
	if count(lobby, TEAMS[1]) + count(lobby, TEAMS[2]) == 0 then
		notice(player, "Put someone on a team first")
		return
	end
	lobby.starting = true
	publish(lobby)
	for _, member in lobby.members do
		Matchmaker.StopSearch(member, `{member.DisplayName} is starting a custom match · search stopped`)
		Remote:FireClient(member, "Starting")
	end

	if RunService:IsStudio() then
		-- shortcut: the match runs on this server (no teleports in Studio); the rest of the server
		-- spectates (RoundService doesn't put anyone the host didn't pick on a team)
		local teamOf = {}
		for _, member in lobby.members do
			teamOf[member] = lobby.team[member]
		end
		local settings = lobby.settings
		close(lobby)
		RoundService.ForceStart(teamOf, false, settings)
		return
	end

	task.wait(START_DELAY) -- (MATCH STARTING on screen; clients set the loading screen as the teleport screen)
	if lobbies[lobby.code] ~= lobby then
		return -- (everyone left meanwhile)
	end
	local present, ids, teams = {}, {}, {}
	for _, name in TEAMS do
		teams[name] = {}
	end
	for _, member in lobby.members do
		if member.Parent then
			table.insert(present, member)
			table.insert(ids, member.UserId)
			local teamName = lobby.team[member]
			if teamName then
				table.insert(teams[teamName], member.UserId)
			end
		end
	end
	local ok, err = pcall(function()
		local options = Instance.new("TeleportOptions")
		local accessCode, privateServerId = TeleportService:ReserveServer(game.PlaceId)
		options.ReservedServerAccessCode = accessCode
		-- Custom + Settings: RoundService plays it the host's way, with no rewards. Players: who's
		-- coming (spectators too). Teams: who plays where. Parties: so they come back together.
		-- (the match server takes all but Parties from the ticket, which players can't change)
		MatchTicket.Write(privateServerId, { Custom = true, Players = ids, Teams = teams, Settings = table.clone(lobby.settings) })
		options:SetTeleportData({
			Custom = true,
			Players = ids,
			Teams = teams,
			Parties = PartyService.ForTeleport(present),
			Settings = table.clone(lobby.settings),
		})
		TeleportService:TeleportAsync(game.PlaceId, present, options)
	end)
	if ok then
		-- The lobby stays (still "starting", so nobody joins) until they've all left this server:
		-- if someone's teleport fails, they're still in it and the host can start again
		for _, member in present do
			travelling[member] = true
		end
	else
		warn("Custom match teleport failed:", err)
		lobby.starting = false
		noticeAll(lobby, "Couldn't start the match · the host can try again")
		publish(lobby)
	end
end

-- Teleported here to join a lobby by its code (travel, from another lobby server)
local function onPlayerAdded(player: Player)
	local joinData = player:GetJoinData()
	local data = joinData.TeleportData
	if joinData.SourcePlaceId ~= game.PlaceId or typeof(data) ~= "table" then
		return
	end
	local code = cleanCode(data.CustomCode)
	if not code or not canUse() then
		return
	end
	local lobby = lobbies[code]
	if lobby then
		add(lobby, player)
	else
		notice(player, "That lobby closed before you got here")
	end
end

function CustomMatchService.Start()
	Remote = Instance.new("RemoteEvent")
	Remote.Name = "CustomMatch"
	Remote.Parent = ReplicatedStorage:WaitForChild("Remotes")

	-- Codes are shared between lobby servers (not in Studio: it can't teleport anyway)
	if not RunService:IsStudio() and not RoundService.IsMatchServer() then
		local ok, map = pcall(MemoryStoreService.GetHashMap, MemoryStoreService, "CustomLobbies_v1")
		codeMap = if ok then map else nil
	end

	Remote.OnServerEvent:Connect(function(player, action, a, b)
		-- (a few requests a second is plenty for clicking around a menu)
		local now = os.clock()
		if typeof(action) ~= "string" or now - (lastRequest[player] or 0) < 0.12 or busy[player] or travelling[player] then
			return
		end
		lastRequest[player] = now
		if action == "Leave" then
			remove(player, `{player.DisplayName} left the lobby`)
			return
		end
		if not canUse() then
			return
		end
		if action == "Create" or action == "Join" then
			-- (each one may wait on the MemoryStore: one at a time, and not too often)
			if now - (lastLookup[player] or 0) < LOOKUP_COOLDOWN then
				notice(player, "One moment...")
				return
			end
			local code = if action == "Join" then cleanCode(a) else nil
			if action == "Join" and not code then
				notice(player, `A code is {CustomMatch.CodeLength} letters and numbers`)
				return
			end
			lastLookup[player] = now
			busy[player] = true
			if action == "Create" then
				if lobbyOf[player] then
					remove(player, `{player.DisplayName} left the lobby`)
				end
				create(player)
			else
				join(player, code :: string)
			end
			busy[player] = nil
			return
		elseif action == "Accept" or action == "Decline" then
			local code = cleanCode(a)
			if code then
				answer(player, code, action == "Accept")
			end
			return
		elseif action == "Shuffle" then
			shuffle(player)
			return
		elseif action == "Set" then
			set(player, a, b)
			return
		elseif action == "Start" then
			start(player)
			return
		elseif action == "MoveSelf" then
			move(player, player, a) -- (the host putting themselves on a team, or spectating)
			return
		end
		-- Everything else is about another player in this server
		if typeof(a) ~= "Instance" or not a:IsA("Player") or a.Parent ~= Players or a == player then
			return
		end
		local other = a :: Player
		if action == "Invite" then
			invite(player, other)
		elseif action == "Kick" then
			kick(player, other)
		elseif action == "Move" then
			move(player, other, b)
		end
	end)
	-- A teleport that didn't go through: they're still here
	TeleportService.TeleportInitFailed:Connect(function(player)
		if travelling[player] then
			travelling[player] = nil
			local lobby = lobbyOf[player]
			if lobby and lobby.starting then
				-- Off to the match but didn't make it: back in the lobby, which can start again
				-- (whoever's left; the ones who made it are gone)
				lobby.starting = false
				noticeAll(lobby, `{player.DisplayName}'s teleport failed · the host can start again`)
				publish(lobby)
			else
				notice(player, "The teleport failed · try again")
			end
		end
	end)

	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		remove(player, `{player.DisplayName} left the game`)
		invites[player] = nil
		snoozed[player] = nil
		for _, theirs in invites do
			for code, pending in theirs do
				if pending.from == player then
					theirs[code] = nil
				end
			end
		end
		lastRequest[player] = nil
		lastLookup[player] = nil
		busy[player] = nil
		travelling[player] = nil
	end)

	-- Keep open lobbies' codes alive; give them all up when the server closes
	task.spawn(function()
		while true do
			task.wait(REFRESH_EVERY)
			local map = codeMap
			if map then
				for code in lobbies do
					pcall(function()
						map:SetAsync(code, { JobId = game.JobId, PlaceId = game.PlaceId }, CODE_LIFETIME)
					end)
				end
			end
		end
	end)
	game:BindToClose(function()
		local map = codeMap
		if map then
			for code in lobbies do
				pcall(function()
					map:RemoveAsync(code)
				end)
			end
		end
	end)
end

return CustomMatchService
