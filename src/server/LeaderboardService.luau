-- Global top players: most kills, most matches won and highest level. Shown on the big board on
-- the lobby's east wall (Maps/Lobby builds it empty: "Leaderboard" → SurfaceGui "Board", columns
-- Kills / Wins / Level, rows Row1..Row10) and on the PROGRESS screen's TOP tab (client
-- Match/ProgressMenu).
--
-- Kept in OrderedDataStores, one per board, keyed by UserId (the Level board ranks by total XP).
-- A stored number only ever goes up, so a server with stale data can't knock anyone down.
--   Writing: a player's numbers are noted when they change (ProgressService) and written every
--            couple of minutes, when they leave and when the server shuts down, only if they changed.
--   Reading: the top of each board every few minutes, names looked up once and cached.
-- Every request is pcall'd. With no DataStore (Studio without API access, an outage) or before
-- the first read, the boards show the players in this server; players in this server always
-- show their live numbers (so a kill shows up on the board in seconds, not minutes).
--
-- Clients read ReplicatedStorage.Leaderboards: attributes Kills / Wins / Level (JSON lists of
-- {Id, Name, Value}, best first; Level's Value is the level) and Live (false: this server only).

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserService = game:GetService("UserService")
local Workspace = game:GetService("Workspace")

local Progression = require(ReplicatedStorage.Shared.Progression)
local PlayerData = require(script.Parent.PlayerData)

local LeaderboardService = {}

type Entry = { Id: number, Name: string, Value: number }

local BOARDS = { "Kills", "Wins", "Level" }
local STORE_NAMES = { Kills = "TopKills_v1", Wins = "TopWins_v1", Level = "TopXp_v1" }
local SHOWN = 10 -- rows per board
local WRITE_INTERVAL = 120 -- seconds between writes of changed numbers
local READ_INTERVAL = 300 -- seconds between reads of the top players
local SHOW_INTERVAL = 10 -- seconds between rebuilding what's shown (no requests: cached + live)

local stores: { [string]: OrderedDataStore } = {}
for board, name in STORE_NAMES do
	local ok, result = pcall(DataStoreService.GetOrderedDataStore, DataStoreService, name)
	if ok then
		stores[board] = result
	end
end

local pending: { [number]: { [string]: number } } = {} -- UserId → board → number not written yet
local written: { [number]: { [string]: number } } = {} -- what was last written (skip unchanged)
local stored: { [string]: { Entry } } = { Kills = {}, Wins = {}, Level = {} } -- last read
local names: { [number]: string } = {}
local live = false -- a read has worked
local warned = false
local folder: Folder

local function warnOnce(message: string)
	if not warned then
		warned = true
		warn(`LeaderboardService: {message} (leaderboards show this server only)`)
	end
end

-- A player's number on each board (Level: total XP, so ties in level still have an order)
local function numbersOf(data: PlayerData.Data): { [string]: number }
	return { Kills = data.Kills, Wins = data.Wins, Level = data.Xp }
end

local function write(userId: number)
	local values = pending[userId]
	if not values then
		return
	end
	pending[userId] = nil
	local last = written[userId] or {}
	written[userId] = last
	for board, value in values do
		local store = stores[board]
		if not store or value <= 0 or last[board] == value then
			continue
		end
		local ok, err = pcall(function()
			store:UpdateAsync(tostring(userId), function(old)
				return math.max(if typeof(old) == "number" then old else 0, value)
			end)
		end)
		if ok then
			last[board] = value
		else
			warnOnce(`couldn't write: {err}`)
			pending[userId] = pending[userId] or values -- (try again next time, unless newer ones came)
			return
		end
	end
end

-- Writes everyone's pending numbers at once. Returns a function: how many are still going.
local function writeAll(): () -> number
	local ids = {}
	for userId in pending do
		table.insert(ids, userId)
	end
	local going = #ids
	for _, userId in ids do
		task.spawn(function()
			write(userId)
			going -= 1
		end)
	end
	return function()
		return going
	end
end

local function lookUpNames(ids: { number })
	local missing = {}
	for _, id in ids do
		if not names[id] and id > 0 then
			table.insert(missing, id)
		end
	end
	if #missing == 0 then
		return
	end
	local ok, infos = pcall(UserService.GetUserInfosByUserIdsAsync, UserService, missing)
	if ok and typeof(infos) == "table" then
		for _, info in infos do
			names[info.Id] = info.DisplayName
		end
	end
end

local function read()
	local ids = {}
	for board, store in stores do
		local ok, result = pcall(function()
			return store:GetSortedAsync(false, SHOWN):GetCurrentPage()
		end)
		if not ok then
			warnOnce(`couldn't read: {result}`)
			continue
		end
		local entries = {}
		for _, item in result do
			local id = tonumber(item.key)
			if id and typeof(item.value) == "number" then
				table.insert(entries, { Id = id, Name = "", Value = item.value })
				table.insert(ids, id)
			end
		end
		stored[board] = entries
		live = true
	end
	lookUpNames(ids)
end

-- The fixed, published lists: stored top players, with everyone here at their live numbers
local function show()
	local lists: { [string]: { Entry } } = {}
	for _, board in BOARDS do
		local byId: { [number]: Entry } = {}
		for _, entry in stored[board] do
			byId[entry.Id] = { Id = entry.Id, Name = names[entry.Id] or "Player", Value = entry.Value }
		end
		for _, player in Players:GetPlayers() do
			local data = PlayerData.Get(player)
			local value = data and numbersOf(data)[board]
			-- (everyone here is on the level board, even at level 1; kills / wins once they have some)
			if value and (value > 0 or board == "Level") then
				local entry = byId[player.UserId]
				if not entry or value >= entry.Value then
					byId[player.UserId] = { Id = player.UserId, Name = player.DisplayName, Value = value }
				end
			end
		end
		local list = {}
		for _, entry in byId do
			table.insert(list, entry)
		end
		table.sort(list, function(a, b)
			return if a.Value ~= b.Value then a.Value > b.Value else a.Id < b.Id
		end)
		for i = #list, SHOWN + 1, -1 do
			list[i] = nil
		end
		if board == "Level" then
			for _, entry in list do
				entry.Value = (Progression.LevelFor(entry.Value))
			end
		end
		lists[board] = list
		folder:SetAttribute(board, HttpService:JSONEncode(list))
	end
	folder:SetAttribute("Live", live)

	-- The board in the lobby
	local lobby = Workspace:FindFirstChild("Lobby")
	local panel = lobby and lobby:FindFirstChild("Leaderboard", true)
	local gui = panel and panel:FindFirstChild("Board")
	if not gui then
		return
	end
	for _, board in BOARDS do
		local column = gui:FindFirstChild(board)
		for i = 1, SHOWN do
			local row = column and column:FindFirstChild("Row" .. i) :: Frame?
			if not row then
				continue
			end
			local entry = lists[board][i]
			row.Visible = entry ~= nil
			if entry then
				(row:FindFirstChild("Who") :: TextLabel).Text = entry.Name;
				(row:FindFirstChild("Value") :: TextLabel).Text = if board == "Level" then `LV {entry.Value}` else tostring(entry.Value);
				(row:FindFirstChild("Face") :: ImageLabel).Image = if entry.Id > 0 then `rbxthumb://type=AvatarHeadShot&id={entry.Id}&w=48&h=48` else ""
			end
		end
	end
	local status = gui:FindFirstChild("Status", true) :: TextLabel?
	if status then
		status.Text = if live then "TOP PLAYERS WORLDWIDE · UPDATED EVERY FEW MINUTES" else "LEADERBOARDS OFFLINE · SHOWING THIS SERVER"
	end
end

-- A player's numbers changed (or they just joined): written with the next batch
function LeaderboardService.Note(player: Player)
	local data = PlayerData.Get(player)
	-- (offline data is fresh, not theirs: never written; Studio's test players have ids ≤ 0)
	if not data or player.UserId <= 0 or not PlayerData.IsSaving(player) then
		return
	end
	pending[player.UserId] = numbersOf(data)
end

function LeaderboardService.Start()
	folder = Instance.new("Folder")
	folder.Name = "Leaderboards"
	folder:SetAttribute("Live", false)
	folder.Parent = ReplicatedStorage

	Players.PlayerRemoving:Connect(function(player)
		LeaderboardService.Note(player)
		local userId = player.UserId
		task.spawn(function()
			write(userId)
			if not pending[userId] then
				written[userId] = nil
			end
		end)
	end)

	task.spawn(function()
		local lastWrite, lastRead = os.clock(), -math.huge
		while true do
			if next(stores) and os.clock() - lastRead >= READ_INTERVAL then
				lastRead = os.clock()
				read()
			end
			if os.clock() - lastWrite >= WRITE_INTERVAL then
				lastWrite = os.clock()
				writeAll()
			end
			show()
			task.wait(SHOW_INTERVAL)
		end
	end)

	-- Server shutting down: write what's left (PlayerData keeps the server up while it saves)
	game:BindToClose(function()
		local left = writeAll()
		local deadline = os.clock() + 15
		while left() > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return LeaderboardService
