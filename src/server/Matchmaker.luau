-- Lobby queues (client MainMenu: PLAY → tick modes → START). Each mode ("2v2") has its own queue
-- and you can sit in several at once. As soon as one has enough players for both teams, the first
-- ones in it leave every queue and are teleported together to a brand-new private match server
-- (a reserved server of this same place; RoundService runs the match there and sends them back).
-- Studio can't teleport, so there a full queue starts the match right here, for everyone.
-- Clients see the queues as MatchState attributes "Queue<mode>" = "userId,userId,...", and what
-- you're queued for as your "Queued" attribute ("1v1,2v2").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local MatchConfig = require(ReplicatedStorage.Shared.MatchConfig)
local RoundService = require(script.Parent.RoundService)

local Queue = ReplicatedStorage.Remotes.Queue :: RemoteEvent
local MatchState = ReplicatedStorage.MatchState

local Matchmaker = {}

local queues: { [string]: { Player } } = {}

local function teamSize(mode: string): number
	return tonumber(string.match(mode, "^(%d+)v")) :: number
end

local function publish()
	for mode, list in queues do
		local ids = {}
		for _, player in list do
			table.insert(ids, player.UserId)
		end
		MatchState:SetAttribute("Queue" .. mode, table.concat(ids, ","))
	end
end

local function leave(player: Player)
	for _, list in queues do
		local index = table.find(list, player)
		if index then
			table.remove(list, index)
		end
	end
	player:SetAttribute("Queued", nil)
end

local function launch(mode: string, group: { Player })
	local everyone = {}
	for _, player in group do
		table.insert(everyone, player.UserId)
	end
	for _, player in group do
		Queue:FireClient(player, "Found", mode, everyone)
	end
	if RunService:IsStudio() then
		-- shortcut: the whole test server plays (no teleports in Studio); fine for testing
		RoundService.ForceStart()
		return
	end
	task.wait(2) -- MATCH FOUND on screen (clients set the loading screen as the teleport screen)

	local present, ids = {}, {}
	for _, player in group do
		if player.Parent then
			table.insert(present, player)
			table.insert(ids, player.UserId)
		end
	end
	local ok, err = pcall(function()
		local options = Instance.new("TeleportOptions")
		options.ReservedServerAccessCode = TeleportService:ReserveServer(game.PlaceId)
		options:SetTeleportData({ Mode = mode, Players = ids })
		TeleportService:TeleportAsync(game.PlaceId, present, options)
	end)
	if not ok then
		warn("Match teleport failed:", err)
		for _, player in present do
			Queue:FireClient(player, "Failed")
		end
	end
end

-- Smallest mode first: whichever queue fills first goes
local function check()
	for _, mode in MatchConfig.QueueModes do
		local needed = teamSize(mode) * 2
		if #queues[mode] >= needed then
			local group = table.move(queues[mode], 1, needed, 1, {})
			for _, player in group do
				leave(player)
			end
			task.spawn(launch, mode, group)
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
		if action == "Leave" then
			leave(player)
			publish()
			return
		end
		if action ~= "Join" or typeof(modes) ~= "table" or RoundService.IsMatchServer() or RoundService.IsMatchRunning() then
			return
		end
		leave(player)
		local picked = {}
		for _, mode in MatchConfig.QueueModes do
			if table.find(modes, mode) then
				table.insert(queues[mode], player)
				table.insert(picked, mode)
			end
		end
		player:SetAttribute("Queued", if #picked > 0 then table.concat(picked, ",") else nil)
		check()
	end)

	Players.PlayerRemoving:Connect(function(player)
		leave(player)
		publish()
	end)
end

return Matchmaker
