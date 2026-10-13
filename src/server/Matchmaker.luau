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

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local MatchConfig = require(ReplicatedStorage.Shared.MatchConfig)
local PartyService = require(script.Parent.PartyService)
local RoundService = require(script.Parent.RoundService)

local Queue = ReplicatedStorage.Remotes.Queue :: RemoteEvent
local MatchState = ReplicatedStorage.MatchState

local Matchmaker = {}

-- One place in a queue: a party (leader first) or one player on their own. The same table sits
-- in every queue it's in.
type Unit = { Player }

local queues: { [string]: { Unit } } = {}
local lastRequest: { [Player]: number } = {}

local function teamSize(mode: string): number
	return tonumber(string.match(mode, "^(%d+)v")) :: number
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
end

-- `sides`: the players on each team, in MatchConfig.TeamOrder
local function launch(mode: string, sides: { { Player } })
	local group, teamOf = {}, {}
	for i, side in sides do
		for _, player in side do
			table.insert(group, player)
			teamOf[player] = MatchConfig.TeamOrder[i]
		end
	end
	local everyone = {}
	for _, player in group do
		table.insert(everyone, player.UserId)
	end
	for _, player in group do
		Queue:FireClient(player, "Found", mode, everyone)
	end
	if RunService:IsStudio() then
		-- shortcut: the whole test server plays (no teleports in Studio); fine for testing
		RoundService.ForceStart(teamOf)
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
	local ok, err = pcall(function()
		local options = Instance.new("TeleportOptions")
		options.ReservedServerAccessCode = TeleportService:ReserveServer(game.PlaceId)
		-- Teams: who plays where (RoundService). Parties: so they come back together (PartyService).
		options:SetTeleportData({ Mode = mode, Players = ids, Teams = teams, Parties = PartyService.ForTeleport(present) })
		TeleportService:TeleportAsync(game.PlaceId, present, options)
	end)
	if not ok then
		warn("Match teleport failed:", err)
		for _, player in present do
			Queue:FireClient(player, "Failed")
		end
	end
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

-- Smallest mode first: whichever queue can make a match first goes
local function check()
	for _, mode in MatchConfig.QueueModes do
		local sides = pickTeams(queues[mode], teamSize(mode))
		if sides then
			local players = {}
			for i, units in sides do
				players[i] = {}
				for _, unit in units do
					leaveUnit(unit)
					table.move(unit, 1, #unit, #players[i] + 1, players[i])
				end
			end
			task.spawn(launch, mode, players)
		end
	end
	publish()
end

function Matchmaker.Start()
	for _, mode in MatchConfig.QueueModes do
		queues[mode] = {}
	end
	publish()

	Queue.OnServerEvent:Connect(function(player, action, modes)
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
		for _, member in unit do
			leave(member)
		end
		-- Only modes whose teams the whole party fits in
		local picked = {}
		for _, mode in MatchConfig.QueueModes do
			if table.find(modes, mode) and teamSize(mode) >= #unit then
				table.insert(queues[mode], unit)
				table.insert(picked, mode)
			end
		end
		for _, member in unit do
			member:SetAttribute("Queued", if #picked > 0 then table.concat(picked, ",") else nil)
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
		publish()
	end)
end

return Matchmaker
