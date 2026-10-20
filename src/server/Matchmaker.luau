-- Lobby queues (client MainMenu: PLAY → tick modes → START). Each mode ("2v2") has its own queue
-- and you can sit in several at once. A party (PartyService) is queued as one by its leader, only
-- for modes whose teams it fits in, and is never split up. As soon as a queue can make two full
-- teams, those players leave every queue and are teleported together to a brand-new private
-- match server (a reserved server of this same place; RoundService runs the match there and sends
-- them back). The teleport data says who plays on which team (a party always together) and which
-- parties there are, so they come back to the lobby together too.
-- Studio can't teleport, so there a full queue starts the match right here, for everyone (the
-- matched players on the teams made here).
-- Clients see the queues as MatchState attributes "Queue<mode>" = "userId,userId,...", and what
-- you're queued for (your party's leader picked) as your "Queued" attribute ("1v1,2v2").
-- RANKED (shared/Ranked) has a queue of its own per mode ("Ranked2v2", seen as MatchState
-- "QueueRanked2v2"; you have "QueuedRanked" = true), so ranked players only meet ranked players.
-- Only level 20+ can queue, and a party only if every member is. The teleport data says Ranked,
-- and the match server rates the match (RankedService).
-- CUSTOM matches skip the queues altogether (CustomMatchService): nobody in a custom lobby (player
-- attribute "CustomLobby") can queue, and going into one stops your party's search.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local MatchConfig = require(ReplicatedStorage.Shared.MatchConfig)
local Progression = require(ReplicatedStorage.Shared.Progression)
local Ranked = require(ReplicatedStorage.Shared.Ranked)
local PartyService = require(script.Parent.PartyService)
local PlayerData = require(script.Parent.PlayerData)
local RoundService = require(script.Parent.RoundService)

local Queue = ReplicatedStorage.Remotes.Queue :: RemoteEvent
local MatchState = ReplicatedStorage.MatchState

local Matchmaker = {}

-- One place in a queue: a party (leader first) or one player on their own. The same table sits
-- in every queue it's in.
type Unit = { Player }

local queues: { [string]: { Unit } } = {}
local lastRequest: { [Player]: number } = {}
-- Players on their way to a match server, until they leave this one (that's the teleport working).
-- A failed teleport is tried once more, then they go back to the front of the queue.
type Travel = { options: TeleportOptions, mode: string, ranked: boolean, unit: Unit, retried: boolean }
local travelling: { [Player]: Travel } = {}

local FAILED_REQUEUED = "MATCH COULDN'T START · BACK IN THE QUEUE"

local function teamSize(mode: string): number
	return tonumber(string.match(mode, "^(%d+)v")) :: number
end

-- The queue a mode's casual / ranked players wait in
local function queueKey(mode: string, ranked: boolean): string
	return if ranked then "Ranked" .. mode else mode
end

-- Why `unit` can't queue for ranked (someone under the level, or their data isn't in yet), or nil
local function rankedBlock(unit: Unit): string?
	for _, member in unit do
		local data = PlayerData.Get(member)
		if not data then
			return `{string.upper(member.DisplayName)} IS STILL LOADING · TRY AGAIN`
		end
		local level = Progression.LevelFor(data.Xp)
		if level < Ranked.MinLevel then
			local who = if #unit > 1 then `{string.upper(member.DisplayName)} IS` else "YOU'RE"
			return `{who} LEVEL {level} · RANKED NEEDS LEVEL {Ranked.MinLevel}`
		end
	end
	return nil
end

local function publish()
	for mode, list in queues do
		local ids = {}
		for _, unit in list do
			for _, player in unit do
				table.insert(ids, player.UserId)
			end
		end
		MatchState:SetAttribute("Queue" .. mode, table.concat(ids, ","))
	end
end

local function unitOf(player: Player): Unit?
	for _, list in queues do
		for _, unit in list do
			if table.find(unit, player) then
				return unit
			end
		end
	end
	return nil
end

-- Takes a whole party (or player) out of every queue. With a `reason`, tells them why (all but
-- `except`, who's leaving the game).
local function leaveUnit(unit: Unit, reason: string?, except: Player?)
	for _, list in queues do
		local index = table.find(list, unit)
		if index then
			table.remove(list, index)
		end
	end
	for _, player in unit do
		player:SetAttribute("Queued", nil)
		player:SetAttribute("QueuedRanked", nil)
		if reason and player ~= except and player.Parent then
			Queue:FireClient(player, "Stopped", reason)
		end
	end
end

local function leave(player: Player)
	local unit = unitOf(player)
	if unit then
		leaveUnit(unit)
	end
	player:SetAttribute("Queued", nil)
	player:SetAttribute("QueuedRanked", nil)
end

local check: () -> ()

-- Puts what's left of `unit` (the ones still in this server) back at the front of `mode`'s queue
-- and tells them why. A match that couldn't start isn't their fault: no waiting at the back.
local function requeue(unit: Unit, mode: string, ranked: boolean)
	local here = {}
	for _, player in unit do
		travelling[player] = nil
		if player.Parent then
			table.insert(here, player)
		end
	end
	if #here == 0 or unitOf(here[1]) then
		return -- (all gone, or already queued again)
	end
	table.insert(queues[queueKey(mode, ranked)], 1, here)
	for _, player in here do
		player:SetAttribute("Queued", mode)
		player:SetAttribute("QueuedRanked", if ranked then true else nil)
		Queue:FireClient(player, "Failed", FAILED_REQUEUED)
	end
	check()
end

-- `sides`: the units (parties / solo players) on each team, in MatchConfig.TeamOrder
local function launch(mode: string, sides: { { Unit } }, ranked: boolean)
	local group, teamOf, unitOfPlayer = {}, {}, {}
	for i, units in sides do
		for _, unit in units do
			for _, player in unit do
				table.insert(group, player)
				teamOf[player] = MatchConfig.TeamOrder[i]
				unitOfPlayer[player] = unit
			end
		end
	end
	local everyone = {}
	for _, player in group do
		table.insert(everyone, player.UserId)
	end
	for _, player in group do
		Queue:FireClient(player, "Found", mode, everyone, ranked)
	end
	if RunService:IsStudio() then
		-- shortcut: the whole test server plays (no teleports in Studio); fine for testing
		RoundService.ForceStart(teamOf, ranked)
		return
	end
	task.wait(2) -- MATCH FOUND on screen (clients set the loading screen as the teleport screen)

	local present, ids, teams = {}, {}, {}
	for _, name in MatchConfig.TeamOrder do
		teams[name] = {}
	end
	for _, player in group do
		if player.Parent then
			table.insert(present, player)
			table.insert(ids, player.UserId)
			table.insert(teams[teamOf[player]], player.UserId)
		end
	end
	local options = Instance.new("TeleportOptions")
	local ok, err = pcall(function()
		options.ReservedServerAccessCode = TeleportService:ReserveServer(game.PlaceId)
		-- Teams: who plays where (RoundService). Parties: so they come back together (PartyService).
		-- Ranked: the match is rated (RankedService).
		options:SetTeleportData({ Mode = mode, Players = ids, Teams = teams, Parties = PartyService.ForTeleport(present), Ranked = ranked })
		for _, player in present do
			travelling[player] = { options = options, mode = mode, ranked = ranked, unit = unitOfPlayer[player], retried = false }
		end
		TeleportService:TeleportAsync(game.PlaceId, present, options)
	end)
	if not ok then
		warn("Match teleport failed:", err)
		for _, units in sides do
			for _, unit in units do
				requeue(unit, mode, ranked)
			end
		end
	end
end

-- A teleport that didn't go through (TeleportInitFailed): one more try into the same match server
-- (it waits for late arrivals), then back to the front of the queue
local function onTeleportFailed(player: Player, result: Enum.TeleportResult, message: string)
	local travel = travelling[player]
	if not travel then
		return
	end
	warn(`Match teleport failed for {player.Name} ({result.Name}): {message}`)
	if not travel.retried then
		travel.retried = true
		task.wait(1)
		local ok = player.Parent ~= nil and pcall(TeleportService.TeleportAsync, TeleportService, game.PlaceId, { player }, travel.options)
		if ok then
			return -- (if this one fails too, TeleportInitFailed comes back here)
		end
	end
	-- The whole party goes back together (requeue skips the ones who made it: they've left)
	requeue(travel.unit, travel.mode, travel.ranked)
end

-- Two full teams of `size` from the front of `list` without splitting a party: the units on each
-- team, or nil if this queue can't make a match yet. Goes down the queue remembering one way to
-- reach every pair of team counts so far (at most (size + 1)² of them), so a party further back
-- can still fill a gap that the ones in front of it couldn't.
local function pickTeams(list: { Unit }, size: number): { { Unit } }?
	local stride = size + 1 -- key = (filled on team 1) × stride + (filled on team 2)
	local full = size * stride + size
	local ways: { [number]: { { Unit } } } = { [0] = { {}, {} } }
	for _, unit in list do
		local found = {}
		for key, sides in ways do
			local filled = { key // stride, key % stride }
			for side = 1, 2 do
				local newKey = key + #unit * (if side == 1 then stride else 1)
				if filled[side] + #unit <= size and not ways[newKey] and not found[newKey] then
					local copy = { table.clone(sides[1]), table.clone(sides[2]) }
					table.insert(copy[side], unit)
					found[newKey] = copy
				end
			end
		end
		for key, sides in found do
			ways[key] = sides
		end
		if ways[full] then
			return ways[full]
		end
	end
	return nil
end

-- Smallest mode first: whichever queue can make a match first goes (casual, then ranked)
function check()
	for _, ranked in { false, true } do
		for _, mode in MatchConfig.QueueModes do
			local sides = pickTeams(queues[queueKey(mode, ranked)], teamSize(mode))
			if sides then
				for _, units in sides do
					for _, unit in units do
						leaveUnit(unit)
					end
				end
				task.spawn(launch, mode, sides, ranked)
			end
		end
	end
	publish()
end

-- Stops the search `player` is in (their whole party's), telling the rest of the party `reason`:
-- CustomMatchService, when someone goes into a custom lobby
function Matchmaker.StopSearch(player: Player, reason: string)
	local unit = unitOf(player)
	if unit then
		leaveUnit(unit, reason, player)
		publish()
	end
end

function Matchmaker.Start()
	for _, mode in MatchConfig.QueueModes do
		queues[queueKey(mode, false)] = {}
		queues[queueKey(mode, true)] = {}
	end
	publish()

	-- Queue("Join", modes, ranked?) / Queue("Leave")
	Queue.OnServerEvent:Connect(function(player, action, modes, ranked)
		-- (a few requests a second is plenty for clicking around a menu)
		local now = os.clock()
		if now - (lastRequest[player] or 0) < 0.1 then
			return
		end
		lastRequest[player] = now
		-- Only a party's leader starts and stops its search
		if PartyService.LeaderOf(player) ~= player then
			return
		end
		if action == "Leave" then
			leave(player)
			publish()
			return
		end
		if action ~= "Join" or typeof(modes) ~= "table" or RoundService.IsMatchServer() or RoundService.IsMatchRunning() then
			return
		end
		local unit = PartyService.MembersOf(player)
		-- (in a custom lobby you play that match: CustomMatchService)
		for _, member in unit do
			if member:GetAttribute("CustomLobby") then
				local who = if member == player then "YOU'RE" else `{string.upper(member.DisplayName)} IS`
				Queue:FireClient(player, "Stopped", `{who} IN A CUSTOM LOBBY · LEAVE IT TO QUEUE`)
				return
			end
		end
		ranked = ranked == true
		local blocked = if ranked then rankedBlock(unit) else nil
		if blocked then
			Queue:FireClient(player, "Stopped", blocked)
			return
		end
		for _, member in unit do
			leave(member)
		end
		-- Only modes whose teams the whole party fits in
		local picked = {}
		for _, mode in MatchConfig.QueueModes do
			if table.find(modes, mode) and teamSize(mode) >= #unit then
				table.insert(queues[queueKey(mode, ranked)], unit)
				table.insert(picked, mode)
			end
		end
		for _, member in unit do
			member:SetAttribute("Queued", if #picked > 0 then table.concat(picked, ",") else nil)
			member:SetAttribute("QueuedRanked", if #picked > 0 and ranked then true else nil)
		end
		check()
	end)

	-- A party that changes (someone joins, leaves or is kicked) stops searching: its leader queues
	-- it again as it is now
	PartyService.OnChanged(function(players)
		local stopped = false
		for _, player in players do
			local unit = unitOf(player)
			if unit then
				leaveUnit(unit, "PARTY CHANGED · SEARCH STOPPED")
				stopped = true
			end
		end
		if stopped then
			publish()
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		local unit = unitOf(player)
		if unit then
			leaveUnit(unit, "PARTY CHANGED · SEARCH STOPPED", player)
		end
		lastRequest[player] = nil
		travelling[player] = nil -- (gone: the teleport worked, or they quit)
		publish()
	end)
	TeleportService.TeleportInitFailed:Connect(onTeleportFailed)
end

return Matchmaker
