-- Clans (rules: shared/Clans; the lobby's CLAN screen: client Match/ClanMenu). A clan's tag shows
-- as "[TAG]" before its members' names in chat (client Match/ChatTags), on the Tab scoreboard and
-- on the leaderboards (LeaderboardService asks TagOf).
--   Clan:FireServer("Create", name, tag, settings)   level Clans.CreateLevel+, Clans.CreateCost
--                                                    credits; name, tag and description go
--                                                    through Roblox's text filter, the tag must be free
--   Clan:FireServer("Settings", settings)    owner / officers: { Type, MinLevel, MinRank,
--                                            Description, Badge } (any of them)
--   Clan:FireServer("Join", clanId)          an Open clan whose requirements you meet
--   Clan:FireServer("Request", clanId, message?)     ask to join a Request clan
--   Clan:FireServer("AcceptRequest", userId) / ("DeclineRequest", userId)   owner / officers
--   Clan:FireServer("Invite", player)        owner / officers: someone in this server (popup)
--   Clan:FireServer("Accept", inviter) / ("Decline", inviter)
--   Clan:FireServer("Leave")                 (the owner hands the clan on first, unless alone:
--                                            then leaving disbands it)
--   Clan:FireServer("Kick", userId)          owner: anyone; officers: members
--   Clan:FireServer("Promote" / "Demote" / "Transfer", userId)   owner
--   Clan:FireServer("Disband")               owner
--   Clan:FireServer("Refresh" / "Browse")    your clan again / the recommended clans
--   Clan:FireServer("Search", text)          clans by name, or the one with that exact tag
--   Clan:FireClient(player, "Info", info?)   your clan (nil: none), with its log, and its join
--                                            requests for the owner and officers
--   Clan:FireClient(player, "Invite", inviter, tag, name, badge, seconds)   (JOIN / NO popup)
--   Clan:FireClient(player, "Sent", invitee, seconds) / ("Answered", invitee)
--   Clan:FireClient(player, "Browse" / "Search", list)   clan summaries (Requested: yours pending)
--   Clan:FireClient(player, "Requested", clanId) / ("Created") / ("Notice", text)
-- Player attributes: ClanId, ClanTag, ClanBadge, ClanRole (nil when not in one).
-- ReplicatedStorage.ClanBoard: attributes Wins / Kills (JSON lists of clan summaries, best first),
-- Live (false: this server's clans only) and Available (false: no DataStore, no clans).
--
-- Storage, all pcall'd and retried (a failure never touches anyone's PlayerData):
--   Clans_v1 (DataStore)   "<clan id>"         the clan (Record below); every change is an
--                                              UpdateAsync that checks the fresh copy (roles,
--                                              room, requirements), so servers can't undo each
--                                              other. Disbanding leaves { Disbanded = true }.
--                          "tag_<TAG>"         the clan id holding that tag ("" once released)
--                          "player_<userId>"   a join request was accepted while they were away
--                                              (or in another server): they join from it
--   TopClans_v1 / TopClanKills_v1 (Ordered)   clan id → total match wins / kills
--   ClanIndex_v1 (Ordered)   joinable clans (Open / Request, not full) → minute last active:
--                            the recommended list in the browser
-- The player's PlayerData.ClanId points at their clan; the clan's member list is the truth (a
-- ClanId whose clan doesn't list them any more is cleared when they join or it's re-read).
-- Servers with members online re-read their clan every minute and when told about a change
-- (MessagingService "clan_<id>"); accepted join requests are announced on "ClanJoins".
-- Members' match kills and wins (ProgressService → Note) are added up and written once a minute.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local Clans = require(ReplicatedStorage.Shared.Clans)
local Progression = require(ReplicatedStorage.Shared.Progression)
local Ranked = require(ReplicatedStorage.Shared.Ranked)
local PlayerData = require(script.Parent.PlayerData)
local ShopService = require(script.Parent.ShopService)

local MatchState = ReplicatedStorage.MatchState

local ClanService = {}

local STORE_NAME = "Clans_v1"
local BOARD_NAMES = { Wins = "TopClans_v1", Kills = "TopClanKills_v1" }
local INDEX_NAME = "ClanIndex_v1"
local JOIN_TOPIC = "ClanJoins"
local INVITE_TIME = 30 -- seconds an invite can be answered
local REFRESH_INTERVAL = 60 -- seconds between re-reads of the clans with members here (and stat writes)
local LISTS_INTERVAL = 120 -- seconds between reads of the top clans and the recommended ones
local SHOW_INTERVAL = 15 -- seconds between rebuilding ClanBoard (no requests)
local SUMMARY_AGE = 300 -- a browsed clan is read again after this long
local INDEX_AGE = 300 -- a clan's place in ClanIndex is written at most this often (unless it changes)
local SHOWN = 10 -- clans per board
local RECOMMENDED = 15
local TRIES = 3
local LOAD_WAIT = 120 -- seconds to wait for someone's data to load
local GONE = "That clan doesn't exist anymore"
local UNREACHABLE = "Couldn't reach the clan servers, try again"
local OFFLINE = "Clans are offline right now"

type Member = { Role: string, Joined: number, Name: string }
type Request = { Id: number, Name: string, Message: string, At: number }
type LogEntry = { At: number, Kind: string, Who: string, By: string? }
type Record = {
	Name: string,
	Tag: string,
	Description: string,
	Badge: number,
	Type: string,
	MinLevel: number,
	MinRank: number,
	OwnerId: number,
	Created: number,
	Kills: number,
	Wins: number,
	Version: number, -- +1 on every write: an older read never replaces a newer copy
	Members: { [string]: Member }, -- tostring(UserId) →
	Requests: { Request }, -- oldest first
	Log: { LogEntry }, -- oldest first
}
-- What the browser and the boards show of a clan (members: server only, for TagOf)
type Summary = {
	at: number,
	members: { [string]: Member },
	requesters: { [number]: boolean },
	info: { [string]: any },
}

local store: DataStore? = nil
local boardStores: { [string]: OrderedDataStore } = {}
local indexStore: OrderedDataStore? = nil
do
	local ok, result = pcall(DataStoreService.GetDataStore, DataStoreService, STORE_NAME)
	if ok then
		store = result
	end
	for board, name in BOARD_NAMES do
		local okBoard, ordered = pcall(DataStoreService.GetOrderedDataStore, DataStoreService, name)
		if okBoard then
			boardStores[board] = ordered
		end
	end
	local okIndex, ordered = pcall(DataStoreService.GetOrderedDataStore, DataStoreService, INDEX_NAME)
	if okIndex then
		indexStore = ordered
	end
end

local Clan: RemoteEvent
local boardFolder: Folder

local cache: { [string]: Record } = {} -- clans with members here, as last read / written
local gone: { [string]: boolean } = {} -- disbanded (an old read finishing late can't bring it back)
local clanOf: { [Player]: string } = {} -- checked against the clan's member list
local summaries: { [string]: Summary } = {}
local subscriptions: { [string]: any } = {} -- clan id → connection (true while subscribing)
local pendingStats: { [string]: { Kills: number, Wins: number } } = {}
local invites: { [Player]: { [Player]: { id: string, ends: number } } } = {} -- invitee → inviter →
local pointerChecked: { [Player]: boolean } = {}
local indexed: { [string]: { at: number, joinable: boolean } } = {}
local refreshing: { [string]: boolean } = {}
local busy: { [Player]: boolean } = {}
local lastRequest: { [Player]: number } = {}
local lastLookup: { [Player]: number } = {}
local boards: { [string]: { { id: string, value: number } } } = { Wins = {}, Kills = {} }
local recommended: { string } = {} -- clan ids, most recently active first
local live = false

local apply: (id: string, record: Record?) -> ()

-- ─── Helpers ───────────────────────────────────────────────────────────────────

local function count(value: any, default: number): number
	return if typeof(value) == "number" and value == value then math.clamp(math.floor(value), 0, 1e12) else default
end

local function userId(value: any): number
	return if typeof(value) == "number" and value == value then math.floor(value) else 0
end

local function notice(player: Player, text: string)
	if player.Parent then
		Clan:FireClient(player, "Notice", string.upper(text))
	end
end

-- Runs `attempt` until it doesn't error (a few tries, waiting longer each time)
local function retry(attempt: () -> ()): boolean
	for try = 1, TRIES do
		local ok, err = pcall(attempt)
		if ok then
			return true
		end
		warn(`ClanService: {err}`)
		if try < TRIES then
			task.wait(try)
		end
	end
	return false
end

-- (ok, value) from Clans_v1; `fresh` skips Roblox's few-second read cache
local function get(key: string, fresh: boolean): (boolean, any)
	local dataStore = store
	if not dataStore then
		return false, nil
	end
	local value = nil
	local ok = retry(function()
		if fresh then
			local options = Instance.new("DataStoreGetOptions")
			options.UseCache = false
			value = dataStore:GetAsync(key, options)
		else
			value = dataStore:GetAsync(key)
		end
	end)
	return ok, value
end

local function update(key: string, transform: (any) -> any): boolean
	local dataStore = store
	if not dataStore then
		return false
	end
	return retry(function()
		dataStore:UpdateAsync(key, transform)
	end)
end

-- Whatever came out of the store, cleaned up; nil if it's not a clan (or a disbanded one)
local function clean(stored: any): Record?
	if typeof(stored) ~= "table" or stored.Disbanded == true or typeof(stored.Name) ~= "string" or typeof(stored.Tag) ~= "string" or typeof(stored.Members) ~= "table" then
		return nil
	end
	local record: Record = {
		Name = stored.Name,
		Tag = stored.Tag,
		Description = if typeof(stored.Description) == "string" then stored.Description else "",
		Badge = Clans.BadgeById(stored.Badge).Id,
		Type = if Clans.IsType(stored.Type) then stored.Type else "Invite",
		MinLevel = math.clamp(count(stored.MinLevel, 1), 1, Clans.MaxLevelRequirement),
		MinRank = math.clamp(count(stored.MinRank, 0), 0, #Ranked.Tiers),
		OwnerId = userId(stored.OwnerId),
		Created = count(stored.Created, 0),
		Kills = count(stored.Kills, 0),
		Wins = count(stored.Wins, 0),
		Version = count(stored.Version, 0),
		Members = {},
		Requests = {},
		Log = {},
	}
	for key, member in stored.Members do
		if typeof(key) == "string" and tonumber(key) and typeof(member) == "table" and Clans.Roles[member.Role] then
			record.Members[key] = {
				Role = member.Role,
				Joined = count(member.Joined, 0),
				Name = if typeof(member.Name) == "string" then string.sub(member.Name, 1, 40) else "Player",
			}
		end
	end
	if typeof(stored.Requests) == "table" then
		for _, request in stored.Requests do
			if typeof(request) == "table" and typeof(request.Id) == "number" and #record.Requests < Clans.MaxRequests then
				table.insert(record.Requests, {
					Id = userId(request.Id),
					Name = if typeof(request.Name) == "string" then string.sub(request.Name, 1, 40) else "Player",
					Message = if typeof(request.Message) == "string" then string.sub(request.Message, 1, 400) else "",
					At = count(request.At, 0),
				})
			end
		end
	end
	if typeof(stored.Log) == "table" then
		for _, entry in stored.Log do
			if typeof(entry) == "table" and typeof(entry.Kind) == "string" and typeof(entry.Who) == "string" and #record.Log < Clans.MaxLog then
				table.insert(record.Log, {
					At = count(entry.At, 0),
					Kind = entry.Kind,
					Who = string.sub(entry.Who, 1, 40),
					By = if typeof(entry.By) == "string" then string.sub(entry.By, 1, 40) else nil,
				})
			end
		end
	end
	return record
end

local function memberCount(record: Record): number
	local n = 0
	for _ in record.Members do
		n += 1
	end
	return n
end

local function addLog(record: Record, kind: string, who: string, by: string?)
	table.insert(record.Log, { At = os.time(), Kind = kind, Who = who, By = by })
	while #record.Log > Clans.MaxLog do
		table.remove(record.Log, 1)
	end
end

local function removeRequest(record: Record, id: number): Request?
	for i, request in record.Requests do
		if request.Id == id then
			return table.remove(record.Requests, i)
		end
	end
	return nil
end

local function isJoinable(record: Record): boolean
	return record.Type ~= "Invite" and memberCount(record) < Clans.MaxMembers
end

-- A player's level and ranked tier (Clans.TierIndex), from their saved data
local function standing(player: Player): (number, number)
	local data = PlayerData.Get(player)
	if not data then
		return 0, 0
	end
	return (Progression.LevelFor(data.Xp)), Clans.TierIndex(data.Mmr, data.RankedMatches)
end

-- Why `player` can't join `record` by its requirements (nil: they can)
local function unmet(record: Record, level: number, tier: number): string?
	local levelOk, rankOk = Clans.Meets(level, tier, record.MinLevel, record.MinRank)
	if not levelOk then
		return `You need to be level {record.MinLevel}`
	elseif not rankOk then
		return `You need {Clans.RankLabel(record.MinRank)} rank or higher`
	end
	return nil
end

-- Roblox's text filter (as seen by everyone in the game). nil: the filter couldn't be reached.
local function filtered(player: Player, text: string): string?
	if text == "" then
		return ""
	end
	local ok, result = pcall(function()
		local filterResult = TextService:FilterStringAsync(text, player.UserId, Enum.TextFilterContext.PublicChat)
		return filterResult:GetNonChatStringForBroadcastAsync()
	end)
	return if ok and typeof(result) == "string" then result else nil
end

-- True if the filter leaves `text` exactly as it is; nil if it couldn't be checked
local function passes(player: Player, text: string): boolean?
	local result = filtered(player, text)
	if result == nil then
		return nil
	end
	return result == text and not string.find(result, "#", 1, true)
end

-- ─── What clients see ──────────────────────────────────────────────────────────

local function summaryInfo(id: string, record: Record): { [string]: any }
	local pending = pendingStats[id]
	return {
		Id = id,
		Name = record.Name,
		Tag = record.Tag,
		Badge = record.Badge,
		Type = record.Type,
		MinLevel = record.MinLevel,
		MinRank = record.MinRank,
		Description = record.Description,
		Members = memberCount(record),
		Kills = record.Kills + (if pending then pending.Kills else 0),
		Wins = record.Wins + (if pending then pending.Wins else 0),
	}
end

local function noteSummary(id: string, record: Record)
	local requesters = {}
	for _, request in record.Requests do
		requesters[request.Id] = true
	end
	summaries[id] = { at = os.clock(), members = record.Members, requesters = requesters, info = summaryInfo(id, record) }
end

-- Everything the clan page shows (the join requests only for the owner and officers)
local function infoFor(id: string, record: Record, role: string): { [string]: any }
	local info = summaryInfo(id, record)
	info.OwnerId = record.OwnerId
	info.Created = record.Created
	info.Role = role
	info.Max = Clans.MaxMembers
	info.Log = record.Log
	local members = {}
	for key, member in record.Members do
		table.insert(members, { Id = tonumber(key), Name = member.Name, Role = member.Role, Joined = member.Joined })
	end
	info.MemberList = members
	info.Requests = if role ~= "Member" then record.Requests else {}
	return info
end

-- Keeps a MessagingService subscription for every clan with someone here
local function watch()
	local wanted = {}
	for _, id in clanOf do
		wanted[id] = true
	end
	for id, connection in subscriptions do
		if not wanted[id] then
			subscriptions[id] = nil
			if typeof(connection) == "RBXScriptConnection" then
				connection:Disconnect()
			end
		end
	end
	for id in wanted do
		if subscriptions[id] then
			continue
		end
		subscriptions[id] = true
		task.spawn(function()
			local ok, connection = pcall(MessagingService.SubscribeAsync, MessagingService, "clan_" .. id, function(message)
				local data = message.Data
				if typeof(data) == "table" and data.Job == game.JobId then
					return -- (our own change: already applied)
				end
				task.spawn(function()
					if not refreshing[id] then
						refreshing[id] = true
						local okRead, stored = get(id, true)
						refreshing[id] = nil
						if okRead then
							apply(id, clean(stored))
						end
					end
				end)
			end)
			if ok and subscriptions[id] == true then
				subscriptions[id] = connection
			else
				if ok then
					connection:Disconnect()
				end
				if subscriptions[id] == true then
					subscriptions[id] = nil -- (tried again with the next refresh)
				end
			end
		end)
	end
end

-- Tells the other servers with members online that clan `id` changed
local function broadcast(id: string)
	task.spawn(pcall, MessagingService.PublishAsync, MessagingService, "clan_" .. id, { Job = game.JobId })
end

-- Puts `player` in clan `id` here (or in none, also when it doesn't list them): their saved
-- ClanId, their attributes and their menu
local function show(player: Player, id: string?, record: Record?)
	local member = if id and record then record.Members[tostring(player.UserId)] else nil
	if not member then
		id, record = nil, nil
	end
	if id then
		clanOf[player] = id
	else
		clanOf[player] = nil
	end
	local data = PlayerData.Get(player)
	if data and data.ClanId ~= (id or "") then
		PlayerData.Update(player, function(d)
			d.ClanId = id or ""
		end, true)
	end
	player:SetAttribute("ClanId", id)
	player:SetAttribute("ClanTag", if record then record.Tag else nil)
	player:SetAttribute("ClanBadge", if record then record.Badge else nil)
	player:SetAttribute("ClanRole", if member then member.Role else nil)
	if player.Parent then
		Clan:FireClient(player, "Info", if id and record and member then infoFor(id, record, member.Role) else nil)
	end
	watch()
end

-- Clan `id` as just read or written (nil: it's gone): everyone here in it sees the change
apply = function(id: string, record: Record?)
	if record and gone[id] then
		return
	end
	local known = cache[id]
	if record and known and record.Version < known.Version then
		record = known -- (an older read finishing late)
	end
	if record then
		cache[id] = record
		noteSummary(id, record)
	else
		cache[id] = nil
		summaries[id] = nil
	end
	for _, player in Players:GetPlayers() do
		local data = PlayerData.Get(player)
		if clanOf[player] == id or (data and data.ClanId == id) then
			local was = clanOf[player]
			show(player, id, record)
			if was == id and not clanOf[player] then
				notice(player, if record then `You're no longer in [{record.Tag}]` else "Your clan was disbanded")
			end
		end
	end
end

-- Clan `id`'s place in the recommended list (ClanIndex): there while it's joinable, by when it
-- was last active (written at most every few minutes unless that changes)
local function index(id: string, record: Record?)
	local ordered = indexStore
	if not ordered then
		return
	end
	local joinable = record ~= nil and isJoinable(record)
	local last = indexed[id]
	if last and last.joinable == joinable and (not joinable or os.clock() - last.at < INDEX_AGE) then
		return
	end
	indexed[id] = { at = os.clock(), joinable = joinable }
	task.spawn(function()
		local ok, err = pcall(function()
			if joinable then
				ordered:SetAsync(id, math.floor(os.time() / 60))
			else
				ordered:RemoveAsync(id)
			end
		end)
		if not ok then
			indexed[id] = nil
			warn(`ClanService: couldn't update the clan index: {err}`)
		end
	end)
end

-- Changes clan `id` with UpdateAsync: `change(record)` gets the copy fresh from the store and
-- edits it, or returns why it can't (nothing is written then). Returns the clan as written, or
-- nil and what to tell the player. Everyone here sees the change at once; other servers with
-- members online are told, unless `quiet`.
local function mutate(id: string, change: (Record) -> string?, quiet: boolean?): (Record?, string?)
	local problem: string? = nil
	local result: Record? = nil
	local ok = update(id, function(old)
		problem, result = nil, nil
		local record = clean(old)
		if not record then
			problem = GONE
			return nil
		end
		problem = change(record)
		if problem then
			return nil
		end
		record.Version += 1
		result = record
		return record
	end)
	if not ok then
		return nil, UNREACHABLE
	end
	if problem == GONE then
		gone[id] = true
		apply(id, nil)
	end
	local record = result
	if not record then
		return nil, problem
	end
	apply(id, record)
	index(id, record)
	if not quiet then
		broadcast(id)
	end
	return record, nil
end

-- ─── Joining ───────────────────────────────────────────────────────────────────

local function inClan(player: Player): boolean
	local data = PlayerData.Get(player)
	return clanOf[player] ~= nil or data == nil or data.ClanId ~= ""
end

-- "player_<userId>": the clans that accepted their join requests and haven't been picked up yet
local function pointerList(value: any): { string }
	local ids = {}
	if typeof(value) == "table" then
		for _, id in value do
			if typeof(id) == "string" and #ids < 10 then
				table.insert(ids, id)
			end
		end
	end
	return ids
end

-- A join request of `player`'s was accepted (while they were away, or in this server or another):
-- they're in the clan now, unless they're in one already (then they step out of the new one)
local function claimPointer(player: Player)
	local data = PlayerData.Get(player)
	if not data or (not clanOf[player] and data.ClanId ~= "") then
		return -- (the clan they have isn't sorted out yet: next time)
	end
	local key = "player_" .. player.UserId
	local ok, value = get(key, true)
	if not ok then
		return
	end
	pointerChecked[player] = true
	local ids = pointerList(value)
	if #ids == 0 then
		return
	end
	local userKey = tostring(player.UserId)
	local name = player.DisplayName
	for _, id in ids do
		if clanOf[player] == id then
			continue
		elseif not clanOf[player] and data.ClanId == "" then
			local okRead, stored = get(id, true)
			if not okRead then
				pointerChecked[player] = nil -- (try again: nothing's been cleared)
				return
			end
			local record = clean(stored)
			if record and record.Members[userKey] then
				apply(id, record)
				show(player, id, record)
				notice(player, `You joined [{record.Tag}] {record.Name}`)
			end
		else
			mutate(id, function(record)
				local member = record.Members[userKey]
				if not member or member.Role == "Owner" then
					return "Not in it"
				end
				record.Members[userKey] = nil
				addLog(record, "Left", name)
				return nil
			end)
		end
	end
	update(key, function(old)
		local left = {}
		for _, id in pointerList(old) do
			if not table.find(ids, id) then
				table.insert(left, id)
			end
		end
		return left
	end)
end

local function onJoinMessage(message: any)
	local data = message.Data
	local who = if typeof(data) == "table" and typeof(data.UserId) == "number" then Players:GetPlayerByUserId(data.UserId) else nil
	if who and PlayerData.Get(who) then
		task.spawn(claimPointer, who)
	end
end

local function join(player: Player, id: any)
	if typeof(id) ~= "string" or not string.match(id, "^%x+$") or #id > 40 then
		return
	end
	if inClan(player) then
		notice(player, "Leave your clan first")
		return
	end
	local level, tier = standing(player)
	local name = player.DisplayName
	local userKey = tostring(player.UserId)
	local record, problem = mutate(id, function(r)
		if r.Type ~= "Open" then
			return if r.Type == "Request" then "That clan takes requests" else "That clan is invite only"
		elseif memberCount(r) >= Clans.MaxMembers then
			return "That clan is full"
		elseif r.Members[userKey] then
			return nil
		end
		local why = unmet(r, level, tier)
		if why then
			return why
		end
		r.Members[userKey] = { Role = "Member", Joined = os.time(), Name = name }
		removeRequest(r, player.UserId)
		addLog(r, "Joined", name)
		return nil
	end)
	if record then
		show(player, id, record)
		notice(player, `You joined [{record.Tag}] {record.Name}`)
	else
		notice(player, problem or UNREACHABLE)
	end
end

local function request(player: Player, id: any, message: any)
	if typeof(id) ~= "string" or not string.match(id, "^%x+$") or #id > 40 then
		return
	end
	local text = if message == nil then "" else Clans.CleanText(message, Clans.MaxMessage)
	if not text then
		notice(player, "That message is too long")
		return
	end
	if inClan(player) then
		notice(player, "Leave your clan first")
		return
	end
	local shown = filtered(player, text) -- (a message keeps Roblox's ### rather than being refused)
	if not shown then
		notice(player, UNREACHABLE)
		return
	end
	local level, tier = standing(player)
	local name = player.DisplayName
	local record, problem = mutate(id, function(r)
		if r.Type ~= "Request" then
			return if r.Type == "Open" then "That clan is open: just join" else "That clan is invite only"
		elseif memberCount(r) >= Clans.MaxMembers then
			return "That clan is full"
		end
		local why = unmet(r, level, tier)
		if why then
			return why
		end
		removeRequest(r, player.UserId)
		table.insert(r.Requests, { Id = player.UserId, Name = name, Message = shown, At = os.time() })
		while #r.Requests > Clans.MaxRequests do
			table.remove(r.Requests, 1)
		end
		return nil
	end)
	if record then
		Clan:FireClient(player, "Requested", id)
		notice(player, `Request sent to [{record.Tag}]`)
	else
		notice(player, problem or UNREACHABLE)
	end
end

-- The role `player` has in their clan here (from the last copy: the store's copy decides)
local function roleOf(player: Player): (string?, Record?, string?)
	local id = clanOf[player]
	local record = id and cache[id]
	local member = record and record.Members[tostring(player.UserId)]
	return id, record or nil, if member then member.Role else nil
end

local function answerRequest(player: Player, target: any, accept: boolean)
	if typeof(target) ~= "number" or target ~= math.floor(target) then
		return
	end
	local id, _, role = roleOf(player)
	if not id or role == "Member" or not role then
		return
	end
	local actorKey = tostring(player.UserId)
	local actor = player.DisplayName
	if not accept then
		mutate(id, function(r)
			local me = r.Members[actorKey]
			if not me or me.Role == "Member" then
				return "Only the owner and officers can do that"
			end
			return if removeRequest(r, target) then nil else "That request is gone"
		end)
		return
	end
	-- Where they'll find it, in whichever server they're in (or next time they play)
	if not update("player_" .. target, function(old)
		local ids = pointerList(old)
		if not table.find(ids, id) then
			table.insert(ids, id)
		end
		while #ids > 10 do
			table.remove(ids, 1)
		end
		return ids
	end) then
		notice(player, UNREACHABLE)
		return
	end
	local joinedName = ""
	local record, problem = mutate(id, function(r)
		local me = r.Members[actorKey]
		if not me or me.Role == "Member" then
			return "Only the owner and officers can do that"
		end
		local wanted = removeRequest(r, target)
		if not wanted then
			return "That request is gone"
		elseif memberCount(r) >= Clans.MaxMembers then
			return "Your clan is full"
		end
		joinedName = wanted.Name
		r.Members[tostring(target)] = { Role = "Member", Joined = os.time(), Name = wanted.Name }
		addLog(r, "Joined", wanted.Name, actor)
		return nil
	end)
	if not record then
		notice(player, problem or UNREACHABLE)
		return
	end
	notice(player, `{joinedName} joined the clan`)
	local here = Players:GetPlayerByUserId(target)
	if here then
		task.spawn(claimPointer, here)
	else
		task.spawn(pcall, MessagingService.PublishAsync, MessagingService, JOIN_TOPIC, { UserId = target })
	end
end

-- ─── Invites (players in this server) ──────────────────────────────────────────

local function invite(player: Player, target: Player)
	local id, record, role = roleOf(player)
	if not id or not record or not role or role == "Member" then
		return
	end
	if inClan(target) then
		notice(player, `{target.DisplayName} is already in a clan`)
		return
	elseif memberCount(record) >= Clans.MaxMembers then
		notice(player, "Your clan is full")
		return
	end
	local now = os.clock()
	local theirs = invites[target] or {}
	if theirs[player] and theirs[player].ends > now then
		return -- (asked already)
	end
	theirs[player] = { id = id, ends = now + INVITE_TIME }
	invites[target] = theirs
	Clan:FireClient(target, "Invite", player, record.Tag, record.Name, record.Badge, INVITE_TIME)
	Clan:FireClient(player, "Sent", target, INVITE_TIME)
end

local function answerInvite(player: Player, inviter: Player, accept: boolean)
	local theirs = invites[player]
	local pending = theirs and theirs[inviter]
	if not theirs or not pending then
		return
	end
	theirs[inviter] = nil
	Clan:FireClient(inviter, "Answered", player)
	if not accept then
		notice(inviter, `{player.DisplayName} said no`)
		return
	elseif pending.ends < os.clock() then
		notice(player, "That invite ran out")
		return
	elseif inClan(player) then
		notice(player, "Leave your clan first")
		return
	end
	local inviterKey = tostring(inviter.UserId)
	local userKey = tostring(player.UserId)
	local name = player.DisplayName
	local by = inviter.DisplayName
	-- (an invite gets you in whatever the clan's type and requirements)
	local record, problem = mutate(pending.id, function(r)
		local them = r.Members[inviterKey]
		if not them or them.Role == "Member" then
			return `{by} can't invite anymore`
		elseif memberCount(r) >= Clans.MaxMembers then
			return "That clan is full"
		end
		r.Members[userKey] = { Role = "Member", Joined = os.time(), Name = name }
		removeRequest(r, player.UserId)
		addLog(r, "Joined", name, by)
		return nil
	end)
	if record then
		show(player, pending.id, record)
		notice(player, `You joined [{record.Tag}] {record.Name}`)
		notice(inviter, `{name} joined the clan`)
	else
		notice(player, problem or UNREACHABLE)
	end
end

-- ─── Managing ──────────────────────────────────────────────────────────────────

-- Owner / officer moves on another member (`action`: "Kick", "Promote", "Demote", "Transfer")
local function manage(player: Player, action: string, target: any)
	if typeof(target) ~= "number" or target ~= math.floor(target) or target == player.UserId then
		return
	end
	local id = clanOf[player]
	if not id then
		return
	end
	local actorKey = tostring(player.UserId)
	local targetKey = tostring(target)
	local actor = player.DisplayName
	local record, problem = mutate(id, function(r)
		local me = r.Members[actorKey]
		local them = r.Members[targetKey]
		if not me or not them then
			return "They're not in the clan anymore"
		end
		if action == "Kick" then
			-- (the owner kicks anyone; officers kick members)
			if Clans.Roles[me.Role] <= Clans.Roles[them.Role] or me.Role == "Member" then
				return "You can't kick them"
			end
			r.Members[targetKey] = nil
			addLog(r, "Kicked", them.Name, actor)
		elseif me.Role ~= "Owner" then
			return "Only the owner can do that"
		elseif action == "Promote" and them.Role == "Member" then
			them.Role = "Officer"
			addLog(r, "Promoted", them.Name, actor)
		elseif action == "Demote" and them.Role == "Officer" then
			them.Role = "Member"
			addLog(r, "Demoted", them.Name, actor)
		elseif action == "Transfer" then
			them.Role = "Owner"
			me.Role = "Officer"
			r.OwnerId = target
			addLog(r, "Owner", them.Name, actor)
		else
			return "Nothing to change"
		end
		return nil
	end)
	if not record then
		notice(player, problem or UNREACHABLE)
	end
end

local function settings(player: Player, raw: any)
	if typeof(raw) ~= "table" then
		return
	end
	local id, _, role = roleOf(player)
	if not id or not role or role == "Member" then
		return
	end
	local changes = {}
	if raw.Type ~= nil then
		if not Clans.IsType(raw.Type) then
			return
		end
		changes.Type = raw.Type
	end
	if raw.MinLevel ~= nil then
		if typeof(raw.MinLevel) ~= "number" or raw.MinLevel ~= raw.MinLevel then
			return
		end
		changes.MinLevel = math.clamp(math.floor(raw.MinLevel), 1, Clans.MaxLevelRequirement)
	end
	if raw.MinRank ~= nil then
		if typeof(raw.MinRank) ~= "number" or raw.MinRank ~= raw.MinRank then
			return
		end
		changes.MinRank = math.clamp(math.floor(raw.MinRank), 0, #Ranked.Tiers)
	end
	if raw.Badge ~= nil then
		if typeof(raw.Badge) ~= "number" or not Clans.Badges[raw.Badge] then
			return
		end
		changes.Badge = raw.Badge
	end
	if raw.Description ~= nil then
		local text = Clans.CleanText(raw.Description, Clans.MaxDescription)
		if not text then
			notice(player, `The description can be up to {Clans.MaxDescription} characters`)
			return
		end
		local ok = passes(player, text)
		if ok == nil then
			notice(player, UNREACHABLE)
			return
		elseif not ok then
			notice(player, "That description isn't allowed")
			return
		end
		changes.Description = text
	end
	if not next(changes) then
		return
	end
	local actorKey = tostring(player.UserId)
	local record, problem = mutate(id, function(r)
		local me = r.Members[actorKey]
		if not me or me.Role == "Member" then
			return "Only the owner and officers can do that"
		end
		local fields: any = r
		for field, value in changes do
			fields[field] = value
		end
		return nil
	end)
	notice(player, if record then "Clan settings saved" else problem or UNREACHABLE)
end

-- Gone for good: the record says so, the tag is free again, it's off the boards and the index
local function disband(player: Player)
	local id = clanOf[player]
	if not id then
		return
	end
	local actorKey = tostring(player.UserId)
	local problem: string? = nil
	local tag: string? = nil
	local ok = update(id, function(old)
		problem, tag = nil, nil
		local record = clean(old)
		if not record then
			problem = GONE
			return nil
		end
		local me = record.Members[actorKey]
		if not me or me.Role ~= "Owner" then
			problem = "Only the owner can disband the clan"
			return nil
		end
		tag = record.Tag
		return { Disbanded = true, Name = record.Name, Tag = record.Tag, Version = record.Version + 1, At = os.time() }
	end)
	if not ok then
		notice(player, UNREACHABLE)
		return
	elseif problem and problem ~= GONE then
		notice(player, problem)
		return
	end
	gone[id] = true
	pendingStats[id] = nil
	apply(id, nil)
	notice(player, "Clan disbanded")
	broadcast(id)
	index(id, nil)
	task.spawn(function()
		if tag then
			update("tag_" .. tag, function(old)
				return if old == id then "" else nil
			end)
		end
		for _, ordered in boardStores do
			pcall(ordered.RemoveAsync, ordered, id)
		end
	end)
end

local function leave(player: Player)
	local id, record, role = roleOf(player)
	if not id or not record or not role then
		return
	end
	if role == "Owner" then
		if memberCount(record) > 1 then
			notice(player, "Make someone else owner first (or disband)")
		else
			disband(player)
		end
		return
	end
	local userKey = tostring(player.UserId)
	local name = player.DisplayName
	local result, problem = mutate(id, function(r)
		local me = r.Members[userKey]
		if not me then
			return nil -- (already out)
		elseif me.Role == "Owner" then
			return "Make someone else owner first (or disband)"
		end
		r.Members[userKey] = nil
		addLog(r, "Left", name)
		return nil
	end)
	if result then
		show(player, nil, nil)
		notice(player, `You left [{result.Tag}]`)
	else
		notice(player, problem or UNREACHABLE)
	end
end

-- ─── Creating ──────────────────────────────────────────────────────────────────

local function create(player: Player, rawName: any, rawTag: any, raw: any)
	local name = Clans.CleanName(rawName)
	local tag = Clans.CleanTag(rawTag)
	if not name then
		notice(player, "Names are 3-20 letters, numbers and spaces")
		return
	elseif not tag then
		notice(player, "Tags are 2-4 letters or numbers")
		return
	end
	local options = if typeof(raw) == "table" then raw else {}
	local clanType = if Clans.IsType(options.Type) then options.Type else "Open"
	local minLevel = if typeof(options.MinLevel) == "number" and options.MinLevel == options.MinLevel then math.clamp(math.floor(options.MinLevel), 1, Clans.MaxLevelRequirement) else 1
	local minRank = if typeof(options.MinRank) == "number" and options.MinRank == options.MinRank then math.clamp(math.floor(options.MinRank), 0, #Ranked.Tiers) else 0
	local badge = if typeof(options.Badge) == "number" and Clans.Badges[options.Badge] then options.Badge else 1
	local description = if options.Description == nil then "" else Clans.CleanText(options.Description, Clans.MaxDescription)
	if not description then
		notice(player, `The description can be up to {Clans.MaxDescription} characters`)
		return
	end

	local data = PlayerData.Get(player)
	if not store or not data or not PlayerData.IsSaving(player) then
		notice(player, OFFLINE)
		return
	elseif inClan(player) then
		notice(player, "Leave your clan first")
		return
	elseif Progression.LevelFor(data.Xp) < Clans.CreateLevel then
		notice(player, `Reach level {Clans.CreateLevel} to found a clan`)
		return
	elseif data.Credits < Clans.CreateCost then
		notice(player, `You need {Clans.CreateCost} credits`)
		return
	end
	for _, check in { { name, "That name" }, { tag, "That tag" }, { description, "That description" } } do
		local ok = passes(player, check[1])
		if ok == nil then
			notice(player, UNREACHABLE)
			return
		elseif not ok then
			notice(player, `{check[2]} isn't allowed`)
			return
		end
	end

	-- Is the tag free? (held by a clan that's gone, or a create that never finished, counts as free)
	local tagKey = "tag_" .. tag
	local okTag, holder = get(tagKey, true)
	if not okTag then
		notice(player, UNREACHABLE)
		return
	end
	local stale = ""
	if typeof(holder) == "string" and holder ~= "" then
		local okHolder, stored = get(holder, true)
		if not okHolder then
			notice(player, UNREACHABLE)
			return
		elseif clean(stored) then
			notice(player, `[{tag}] is taken`)
			return
		end
		stale = holder
	end

	-- The clan first (so the tag never points at nothing a moment later), then the tag
	local id = string.lower((string.gsub(HttpService:GenerateGUID(false), "-", "")))
	local record: Record = {
		Name = name,
		Tag = tag,
		Description = description,
		Badge = badge,
		Type = clanType,
		MinLevel = minLevel,
		MinRank = minRank,
		OwnerId = player.UserId,
		Created = os.time(),
		Kills = 0,
		Wins = 0,
		Version = 1,
		Members = { [tostring(player.UserId)] = { Role = "Owner", Joined = os.time(), Name = player.DisplayName } },
		Requests = {},
		Log = {},
	}
	addLog(record, "Created", player.DisplayName)
	local function undo()
		update(id, function(old)
			return if typeof(old) == "table" then { Disbanded = true, Tag = tag, Name = name, Version = 2 } else nil
		end)
	end
	if not update(id, function(old)
		return if old == nil then record else nil
	end) then
		notice(player, UNREACHABLE)
		return
	end
	local taken = false
	if not update(tagKey, function(old)
		taken = typeof(old) == "string" and old ~= "" and old ~= stale
		return if taken then nil else id
	end) or taken then
		undo()
		notice(player, if taken then `[{tag}] is taken` else UNREACHABLE)
		return
	end

	-- Pay last: if they left, or spent the credits meanwhile, nothing is lost
	if not player.Parent or not ShopService.Spend(player, Clans.CreateCost) then
		undo()
		update(tagKey, function(old)
			return if old == id then "" else nil
		end)
		notice(player, `You need {Clans.CreateCost} credits`)
		return
	end
	gone[id] = nil
	apply(id, record)
	show(player, id, record)
	index(id, record)
	Clan:FireClient(player, "Created")
	notice(player, `You founded [{tag}] {name}`)
end

-- ─── Browsing ──────────────────────────────────────────────────────────────────

-- Summaries for `player` (Requested: they've asked to join and haven't heard back)
local function listFor(player: Player, ids: { string }): { { [string]: any } }
	local list = {}
	for _, id in ids do
		local summary = summaries[id]
		if summary then
			local info = table.clone(summary.info)
			info.Requested = summary.requesters[player.UserId] == true
			table.insert(list, info)
		end
	end
	return list
end

-- A clan's summary, read if it isn't known or is old. Returns whether one is known, and whether
-- the clan is gone (disbanded: not just unreachable).
local function summaryOf(id: string): (boolean, boolean)
	local summary = summaries[id]
	if summary and os.clock() - summary.at < SUMMARY_AGE then
		return true, false
	end
	local ok, stored = get(id, false)
	if not ok then
		return summary ~= nil, false
	end
	local record = clean(stored)
	if not record then
		summaries[id] = nil
		return false, true
	end
	if cache[id] then
		apply(id, record)
	else
		noteSummary(id, record)
	end
	return true, false
end

local function browse(player: Player)
	local level, tier = standing(player)
	local ids, seen = {}, {}
	for _, id in recommended do
		seen[id] = true
		table.insert(ids, id)
	end
	for id in cache do -- (clans with members here, so a quiet server isn't empty)
		if not seen[id] then
			table.insert(ids, id)
		end
	end
	local list = {}
	for _, info in listFor(player, ids) do
		if info.Type ~= "Invite" and info.Members < Clans.MaxMembers then
			local levelOk, rankOk = Clans.Meets(level, tier, info.MinLevel, info.MinRank)
			info.Meets = levelOk and rankOk
			table.insert(list, info)
		end
	end
	-- Ones you can join first (otherwise most recently active first, as they came)
	local order = {}
	for i, info in list do
		order[info] = i
	end
	table.sort(list, function(a, b)
		if a.Meets ~= b.Meets then
			return a.Meets
		end
		return order[a] < order[b]
	end)
	for i = #list, RECOMMENDED + 1, -1 do
		list[i] = nil
	end
	Clan:FireClient(player, "Browse", list)
end

local function search(player: Player, text: any)
	if typeof(text) ~= "string" or #text > 30 then
		return
	end
	local query = string.lower((string.gsub(string.gsub(text, "^%s+", ""), "%s+$", "")))
	if #query < 2 then
		Clan:FireClient(player, "Search", {})
		return
	end
	local ids = {}
	-- An exact tag
	local tag = Clans.CleanTag(query)
	if tag then
		local ok, holder = get("tag_" .. tag, false)
		if ok and typeof(holder) == "string" and holder ~= "" and summaryOf(holder) then
			table.insert(ids, holder)
		end
	end
	-- Names (and tags) among the clans this server knows: recommended, the boards, members here
	for id, summary in summaries do
		if #ids >= 10 then
			break
		end
		local info = summary.info
		if not table.find(ids, id) and (string.find(string.lower(info.Name), query, 1, true) or string.lower(info.Tag) == query) then
			table.insert(ids, id)
		end
	end
	Clan:FireClient(player, "Search", listFor(player, ids))
end

-- ─── Stats and lists ───────────────────────────────────────────────────────────

-- Adds up the kills / wins noted since last time into each clan (and its places on the boards)
local function flushStats(): () -> number
	local going = 0
	for id, delta in pendingStats do
		pendingStats[id] = nil
		going += 1
		task.spawn(function()
			local record, problem = mutate(id, function(r)
				r.Kills += delta.Kills
				r.Wins += delta.Wins
				return nil
			end, true)
			if record then
				for board, ordered in boardStores do
					local value = if board == "Wins" then record.Wins else record.Kills
					if value > 0 then
						pcall(ordered.SetAsync, ordered, id, value)
					end
				end
			elseif problem == UNREACHABLE then
				local now = pendingStats[id] or { Kills = 0, Wins = 0 } -- (try again next time)
				now.Kills += delta.Kills
				now.Wins += delta.Wins
				pendingStats[id] = now
			end
			going -= 1
		end)
	end
	return function()
		return going
	end
end

local function readLists()
	local ids = {}
	for board, ordered in boardStores do
		local ok, page = pcall(function()
			return ordered:GetSortedAsync(false, SHOWN):GetCurrentPage()
		end)
		if not ok then
			continue
		end
		local entries = {}
		for _, item in page do
			if typeof(item.key) == "string" and typeof(item.value) == "number" then
				table.insert(entries, { id = item.key, value = item.value })
				table.insert(ids, item.key)
			end
		end
		boards[board] = entries
		live = true
	end
	local ordered = indexStore
	if ordered then
		local ok, page = pcall(function()
			return ordered:GetSortedAsync(false, 30):GetCurrentPage()
		end)
		if ok then
			local list = {}
			for _, item in page do
				if typeof(item.key) == "string" then
					table.insert(list, item.key)
					table.insert(ids, item.key)
				end
			end
			recommended = list
		end
	end
	for _, id in ids do
		local _, isGone = summaryOf(id)
		if isGone then
			-- (disbanded: off the lists)
			for _, board in boardStores do
				pcall(board.RemoveAsync, board, id)
			end
			if ordered then
				pcall(ordered.RemoveAsync, ordered, id)
			end
		end
	end
end

-- ClanBoard for the CLAN screen's TOP tab: stored numbers, with clans here at their live ones
local function showBoards()
	for _, board in { "Wins", "Kills" } do
		local byId: { [string]: { [string]: any } } = {}
		for _, entry in boards[board] do
			local summary = summaries[entry.id]
			if summary then
				local info = table.clone(summary.info)
				info[board] = math.max(info[board], entry.value)
				byId[entry.id] = info
			end
		end
		for id, record in cache do
			local info = summaryInfo(id, record)
			if info[board] > 0 and (not byId[id] or info[board] >= byId[id][board]) then
				byId[id] = info
			end
		end
		local list = {}
		for _, info in byId do
			table.insert(list, info)
		end
		table.sort(list, function(a, b)
			return if a[board] ~= b[board] then a[board] > b[board] else a.Id < b.Id
		end)
		for i = #list, SHOWN + 1, -1 do
			list[i] = nil
		end
		boardFolder:SetAttribute(board, HttpService:JSONEncode(list))
	end
	boardFolder:SetAttribute("Live", live)
end

-- ─── Outside ───────────────────────────────────────────────────────────────────

-- `player`'s clan tag, or a known one for a user who isn't here (nil: none / not known)
function ClanService.TagOf(id: number): string?
	local here = Players:GetPlayerByUserId(id)
	if here then
		local tag = here:GetAttribute("ClanTag")
		return if typeof(tag) == "string" and tag ~= "" then tag else nil
	end
	local key = tostring(id)
	for _, summary in summaries do
		if summary.members[key] then
			return summary.info.Tag
		end
	end
	return nil
end

-- Something worth counting for the clan happened to `player` in a match (ProgressService.Record)
function ClanService.Note(player: Player, event: string)
	local id = clanOf[player]
	if not id or (event ~= "Kill" and event ~= "MatchWin") then
		return
	end
	local stats = pendingStats[id] or { Kills = 0, Wins = 0 }
	if event == "Kill" then
		stats.Kills += 1
	else
		stats.Wins += 1
	end
	pendingStats[id] = stats
end

-- Once their data is in: is the clan they had still theirs? Any join request accepted meanwhile?
local function onPlayerAdded(player: Player)
	local waited = 0
	while player.Parent and not PlayerData.Get(player) and waited < LOAD_WAIT do
		waited += task.wait(0.5)
	end
	local data = PlayerData.Get(player)
	if not data or not store or not player.Parent then
		return
	end
	local id = data.ClanId
	if id ~= "" then
		local ok, stored = get(id, true)
		if not ok then
			return -- (tried again with the next refresh)
		end
		apply(id, clean(stored))
	end
	claimPointer(player)
end

function ClanService.Start()
	Clan = Instance.new("RemoteEvent")
	Clan.Name = "Clan"
	Clan.Parent = ReplicatedStorage:WaitForChild("Remotes")
	boardFolder = Instance.new("Folder")
	boardFolder.Name = "ClanBoard"
	boardFolder:SetAttribute("Live", false)
	boardFolder:SetAttribute("Available", store ~= nil)
	boardFolder:SetAttribute("Wins", "[]")
	boardFolder:SetAttribute("Kills", "[]")
	boardFolder.Parent = ReplicatedStorage

	Clan.OnServerEvent:Connect(function(player, action, a, b, c)
		-- (a few requests a second is plenty for clicking around a menu; one store request at a time)
		local now = os.clock()
		if typeof(action) ~= "string" or now - (lastRequest[player] or 0) < 0.25 or busy[player] then
			return
		end
		lastRequest[player] = now
		if action == "Refresh" then
			local id = clanOf[player]
			local record = if id then cache[id] else nil
			if id and record then
				show(player, id, record)
			else
				Clan:FireClient(player, "Info", nil) -- (a clan that couldn't be read yet stays saved)
			end
			return
		end
		if not store then
			notice(player, OFFLINE)
			return
		end
		if action == "Browse" or action == "Search" then
			if now - (lastLookup[player] or 0) < 2 then
				return
			end
			lastLookup[player] = now
		end
		local other = if typeof(a) == "Instance" and a:IsA("Player") and a.Parent == Players and a ~= player then a :: Player else nil
		busy[player] = true
		local ok, err = pcall(function()
			if action == "Create" then
				create(player, a, b, c)
			elseif action == "Settings" then
				settings(player, a)
			elseif action == "Join" then
				join(player, a)
			elseif action == "Request" then
				request(player, a, b)
			elseif action == "AcceptRequest" or action == "DeclineRequest" then
				answerRequest(player, a, action == "AcceptRequest")
			elseif action == "Invite" and other then
				invite(player, other)
			elseif (action == "Accept" or action == "Decline") and other then
				answerInvite(player, other, action == "Accept")
			elseif action == "Leave" then
				leave(player)
			elseif action == "Disband" then
				disband(player)
			elseif action == "Kick" or action == "Promote" or action == "Demote" or action == "Transfer" then
				manage(player, action, a)
			elseif action == "Browse" then
				browse(player)
			elseif action == "Search" then
				search(player, a)
			end
		end)
		busy[player] = nil
		if not ok then
			warn(`ClanService: {action} failed for {player.Name}: {err}`)
		end
	end)

	if store then
		task.spawn(function()
			local ok, err = pcall(MessagingService.SubscribeAsync, MessagingService, JOIN_TOPIC, onJoinMessage)
			if not ok then
				warn(`ClanService: couldn't listen for accepted requests: {err}`)
			end
		end)
	end

	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		clanOf[player] = nil
		invites[player] = nil
		for _, theirs in invites do
			theirs[player] = nil
		end
		pointerChecked[player] = nil
		busy[player] = nil
		lastRequest[player] = nil
		lastLookup[player] = nil
		watch()
	end)

	-- Every minute: stats written, clans with members here re-read (and anyone whose clan couldn't
	-- be read yet, or whose accepted requests couldn't be checked, tried again); the lists less often
	task.spawn(function()
		local lastLists = -math.huge
		while store do
			task.wait(REFRESH_INTERVAL)
			flushStats()
			local ids = {}
			for _, player in Players:GetPlayers() do
				local data = PlayerData.Get(player)
				local id = clanOf[player] or (if data and data.ClanId ~= "" then data.ClanId else nil)
				if id then
					ids[id] = true
				end
				if data and not pointerChecked[player] and (clanOf[player] or data.ClanId == "") then
					task.spawn(claimPointer, player)
				end
			end
			for id in ids do
				task.spawn(function()
					if refreshing[id] then
						return
					end
					refreshing[id] = true
					local ok, stored = get(id, true)
					refreshing[id] = nil
					if ok then
						apply(id, clean(stored))
					end
				end)
			end
			watch()
			if MatchState:GetAttribute("ServerKind") ~= "Match" and os.clock() - lastLists >= LISTS_INTERVAL then
				lastLists = os.clock()
				task.spawn(readLists)
			end
		end
	end)
	task.spawn(function()
		while true do
			showBoards()
			task.wait(SHOW_INTERVAL)
		end
	end)

	-- Server shutting down: write the kills / wins still waiting
	game:BindToClose(function()
		local left = flushStats()
		local deadline = os.clock() + 15
		while left() > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return ClanService
