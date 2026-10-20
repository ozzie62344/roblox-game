-- Everything a player keeps between sessions and servers (credits, skins), saved in a DataStore.
-- Loaded when they join, saved every few minutes, right after a purchase, and when they leave.
--
-- Players hop between servers a lot (lobby → match server → lobby), so the server that has
-- someone's data "locks" it: the next server waits for the old one to finish saving before
-- loading, instead of reading stale data and later overwriting what was earned or bought. A lock
-- left behind by a crashed server is taken over after a while.
--
-- No DataStore (Studio without "Enable Studio Access to API Services", or Roblox having an
-- outage): everyone gets fresh data that isn't saved, and the "DataOffline" attribute tells the
-- shop to say so.
--
-- Clients see the data as player attributes (Skins.luau): Credits, OwnedSkins, EquippedSkins,
-- plus TouchLayout (where they moved their phone buttons: SettingsService, MobileControls) and
-- Attachments (what's on each gun: shared/Attachments, ShopService) and LobbyWeapon (the gun you
-- hold in the lobby: SettingsService) and Settings (the SETTINGS menu: shared/PlayerSettings,
-- SettingsService, client ClientSettings), and progression (shared/Progression, ProgressService):
-- Xp, Level, Stats, DailyDay, DailyStreak, Challenges; and ranked (shared/Ranked, RankedService):
-- Mmr, RankedMatches, RankedWins, Rank, RankedPlacements; and the first-time tutorial
-- (TutorialService, client Match/Tutorial): TutorialDone, TutorialSeen.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Attachments = require(ReplicatedStorage.Shared.Attachments)
local MatchConfig = require(ReplicatedStorage.Shared.MatchConfig)
local PlayerSettings = require(ReplicatedStorage.Shared.PlayerSettings)
local Progression = require(ReplicatedStorage.Shared.Progression)
local Ranked = require(ReplicatedStorage.Shared.Ranked)
local Skins = require(ReplicatedStorage.Shared.Skins)
local Weapons = require(ReplicatedStorage.Shared.Weapons)

export type Data = {
	Credits: number,
	Skins: { [string]: boolean }, -- owned
	Equipped: { [string]: string }, -- item ("Rifle", "Knife") → skin id
	TouchLayout: string, -- JSON: moved phone buttons (SettingsService checks it), "" = the defaults
	Attachments: { [string]: { [string]: string } }, -- gun → slot → attachment id
	OwnedAttachments: { [string]: boolean }, -- bought (attachment id)
	LobbyWeapon: string, -- the gun you hold in the lobby, "" = the default
	Settings: string, -- JSON: the SETTINGS menu's choices (SettingsService checks it), "" = the defaults
	Xp: number, -- total XP ever earned (the level follows from it: Progression.LevelFor)
	RewardedLevel: number, -- the highest level whose track reward has been given
	Kills: number, -- career stats (leaderboards)
	Headshots: number,
	Wins: number, -- matches won
	Matches: number, -- matches finished
	TutorialDone: boolean, -- finished the first-time tutorial (and got its credits: TutorialService)
	TutorialSeen: boolean, -- was offered it (started or skipped): the lobby doesn't ask again
	DailyDay: number, -- UTC day (Progression.Day) the daily reward was last claimed, 0 = never
	DailyStreak: number, -- days in a row it had been claimed, as of DailyDay
	ChallengeDay: number, -- the UTC day the challenges are for (new ones when it changes)
	Challenges: { Progression.ChallengeState },
	Mmr: number, -- ranked skill rating (shared/Ranked)
	RankedMatches: number, -- ranked matches finished (or left: a loss)
	RankedWins: number,
	Purchases: { string }, -- Robux store (StoreService): PurchaseIds of receipts already granted, newest last
	StarterPackGranted: boolean, -- the Starter Pack pass's credits and skin have been given (StoreService)
	ClanId: string, -- the clan they're in (ClanService checks it against the clan), "" = none
}

local PlayerData = {}

PlayerData.PurchaseHistory = 200 -- receipts remembered in Purchases (the oldest are dropped)

local STORE_NAME = "PlayerData_v1"
local AUTOSAVE_INTERVAL = 60 -- every autosave also renews the lock
local LOCK_EXPIRY = 150 -- seconds: a lock older than this was left by a crashed server
-- A live server's lock must never look abandoned, even after one failed autosave
assert(LOCK_EXPIRY > AUTOSAVE_INTERVAL * 2, "PlayerData: LOCK_EXPIRY must outlast two autosaves")
local RELEASE_TRIES = 3 -- the last save when a player leaves is retried this many times
local RELEASE_RETRY = 2 -- seconds between those tries
local LOAD_RETRY = 2 -- seconds between tries while another server still holds the lock
local LOAD_TRIES = 15 -- then take it anyway
-- Studio test sessions stop abruptly and all share JobId "", so they don't lock
local USE_LOCKS = not RunService:IsStudio()

type Session = {
	data: Data,
	saving: boolean, -- false: no DataStore, nothing is written
	dirty: boolean,
	saveQueued: boolean,
	leaving: boolean, -- the last save has started: autosaves still in flight write nothing
}

local sessions: { [Player]: Session } = {}

local store: DataStore? = nil
do
	local ok, result = pcall(DataStoreService.GetDataStore, DataStoreService, STORE_NAME)
	if ok then
		store = result
	end
end

local function newData(): Data
	return {
		Credits = MatchConfig.Credits.Starting, Skins = {}, Equipped = {}, TouchLayout = "", Attachments = {}, OwnedAttachments = {}, LobbyWeapon = "", Settings = "",
		Xp = 0, RewardedLevel = 1, Kills = 0, Headshots = 0, Wins = 0, Matches = 0, DailyDay = 0, DailyStreak = 0, ChallengeDay = 0, Challenges = {},
		TutorialDone = false, TutorialSeen = false,
		Mmr = Ranked.StartMmr, RankedMatches = 0, RankedWins = 0,
		Purchases = {}, StarterPackGranted = false,
		ClanId = "",
	}
end

-- A stored count: a whole number, never below 0 (anything else → `default`)
local function count(value: any, default: number): number
	return if typeof(value) == "number" and value == value then math.clamp(math.floor(value), 0, 1e12) else default
end

-- Whatever came out of the store, cleaned up (unknown skins dropped, missing fields filled)
local function fromStored(stored: any): Data
	local data = newData()
	if typeof(stored) ~= "table" then
		return data
	end
	if typeof(stored.Credits) == "number" then
		data.Credits = math.max(0, math.floor(stored.Credits))
	end
	if typeof(stored.Skins) == "table" then
		for id, owned in stored.Skins do
			if owned == true and Skins.ById[id] then
				data.Skins[id] = true
			end
		end
	end
	if typeof(stored.Equipped) == "table" then
		for item, id in stored.Equipped do
			-- Dev and exclusive skins aren't bought, so they're kept as they are (they only show for
			-- the players they're for: Skins.EquippedFor). Dropping them here took them off you
			-- every time you joined a server, a match server included.
			local skin = Skins.ById[id]
			if table.find(Skins.Items, item) and skin and (data.Skins[id] or skin.DevOnly or skin.OnlyFor) then
				data.Equipped[item] = id
			end
		end
	end
	if typeof(stored.TouchLayout) == "string" and #stored.TouchLayout <= 4000 then
		data.TouchLayout = stored.TouchLayout
	end
	if typeof(stored.LobbyWeapon) == "string" and Weapons[stored.LobbyWeapon] then
		data.LobbyWeapon = stored.LobbyWeapon
	end
	if typeof(stored.Settings) == "string" and #stored.Settings <= PlayerSettings.MaxJson then
		data.Settings = stored.Settings
	end
	if typeof(stored.OwnedAttachments) == "table" then
		for id, owned in stored.OwnedAttachments do
			if owned == true and Attachments.ById[id] then
				data.OwnedAttachments[id] = true
			end
		end
	end
	if typeof(stored.Attachments) == "table" then
		for weaponName, onGun in stored.Attachments do
			if typeof(weaponName) ~= "string" or typeof(onGun) ~= "table" then
				continue
			end
			for slot, id in onGun do
				if typeof(id) == "string" and data.OwnedAttachments[id] and Attachments.Fits(weaponName, id) and Attachments.ById[id].Slot == slot then
					data.Attachments[weaponName] = data.Attachments[weaponName] or {}
					data.Attachments[weaponName][slot] = id
				end
			end
		end
	end
	data.Xp = count(stored.Xp, 0)
	data.RewardedLevel = math.max(1, count(stored.RewardedLevel, 1))
	data.Kills = count(stored.Kills, 0)
	data.Headshots = count(stored.Headshots, 0)
	data.Wins = count(stored.Wins, 0)
	data.Matches = count(stored.Matches, 0)
	data.DailyDay = count(stored.DailyDay, 0)
	data.DailyStreak = count(stored.DailyStreak, 0)
	data.ChallengeDay = count(stored.ChallengeDay, 0)
	data.Mmr = count(stored.Mmr, Ranked.StartMmr)
	data.RankedMatches = count(stored.RankedMatches, 0)
	data.RankedWins = count(stored.RankedWins, 0)
	-- (anyone who has already played a match counts as having done the tutorial: no prompt, no credits)
	data.TutorialDone = stored.TutorialDone == true or data.Matches > 0
	data.TutorialSeen = stored.TutorialSeen == true or data.TutorialDone
	if typeof(stored.Challenges) == "table" then
		for _, entry in stored.Challenges do
			local challenge = typeof(entry) == "table" and Progression.ChallengeById[entry.Id]
			if challenge and #data.Challenges < Progression.ChallengesPerDay then
				table.insert(data.Challenges, { Id = challenge.Id, Progress = math.min(count(entry.Progress, 0), challenge.Goal) })
			end
		end
	end
	if typeof(stored.Purchases) == "table" then
		for _, id in stored.Purchases do
			if typeof(id) == "string" and #id <= 100 then
				table.insert(data.Purchases, id)
			end
		end
		while #data.Purchases > PlayerData.PurchaseHistory do
			table.remove(data.Purchases, 1)
		end
	end
	if typeof(stored.ClanId) == "string" and #stored.ClanId <= 64 then
		data.ClanId = stored.ClanId
	end
	data.StarterPackGranted = stored.StarterPackGranted == true
	return data
end

local function key(player: Player): string
	return "Player_" .. player.UserId
end

-- Copies the data into the player's attributes for clients to read
local function publish(player: Player, data: Data)
	local owned = {}
	for _, skin in Skins.List do
		if data.Skins[skin.Id] then
			table.insert(owned, skin.Id)
		end
	end
	player:SetAttribute("Credits", data.Credits)
	player:SetAttribute("OwnedSkins", table.concat(owned, ","))
	player:SetAttribute("EquippedSkins", HttpService:JSONEncode(data.Equipped))
	player:SetAttribute("TouchLayout", data.TouchLayout)
	player:SetAttribute("Attachments", HttpService:JSONEncode(data.Attachments))
	local ownedAttachments = {}
	for _, attachment in Attachments.List do
		if data.OwnedAttachments[attachment.Id] then
			table.insert(ownedAttachments, attachment.Id)
		end
	end
	player:SetAttribute("OwnedAttachments", table.concat(ownedAttachments, ","))
	player:SetAttribute("LobbyWeapon", data.LobbyWeapon)
	player:SetAttribute("Settings", data.Settings)
	player:SetAttribute("Xp", data.Xp)
	player:SetAttribute("Level", (Progression.LevelFor(data.Xp)))
	player:SetAttribute("Stats", HttpService:JSONEncode({ Kills = data.Kills, Headshots = data.Headshots, Wins = data.Wins, Matches = data.Matches }))
	player:SetAttribute("DailyDay", data.DailyDay)
	player:SetAttribute("DailyStreak", data.DailyStreak)
	player:SetAttribute("TutorialDone", data.TutorialDone)
	player:SetAttribute("TutorialSeen", data.TutorialSeen)
	player:SetAttribute("Challenges", HttpService:JSONEncode({ Day = data.ChallengeDay, List = data.Challenges }))
	local placed = Ranked.IsPlaced(data.RankedMatches)
	player:SetAttribute("Mmr", data.Mmr)
	player:SetAttribute("RankedMatches", data.RankedMatches)
	player:SetAttribute("RankedWins", data.RankedWins)
	player:SetAttribute("Rank", if placed then Ranked.RankName(data.Mmr) else "")
	player:SetAttribute("RankedPlacements", if placed then nil else data.RankedMatches)
end

-- Claims the player's data. Returns it, or nil if the DataStore can't be reached.
local function load(player: Player): Data?
	local dataStore = store
	if not dataStore then
		return nil
	end
	for attempt = 1, LOAD_TRIES do
		local blocked = false
		local stored = nil
		local ok, err = pcall(function()
			dataStore:UpdateAsync(key(player), function(old)
				blocked = false
				stored = old
				local lock = typeof(old) == "table" and old.Lock or nil
				local mine = typeof(lock) == "table" and lock.Job == game.JobId
				local fresh = typeof(lock) == "table" and typeof(lock.At) == "number" and os.time() - lock.At < LOCK_EXPIRY
				if USE_LOCKS and lock and not mine and fresh and attempt < LOAD_TRIES then
					blocked = true -- the server they just left is still saving
					return nil
				end
				local new = if typeof(old) == "table" then old else {}
				new.Lock = if USE_LOCKS then { Job = game.JobId, At = os.time() } else nil
				return new
			end)
		end)
		if not ok then
			warn(`PlayerData: couldn't load {player.Name}: {err}`)
			if RunService:IsStudio() or not player.Parent then
				return nil -- (Studio: usually "API access is not enabled", no point retrying)
			end
		elseif not blocked then
			return fromStored(stored)
		end
		task.wait(LOAD_RETRY)
		if not player.Parent then
			return nil
		end
	end
	return nil
end

-- Returns true once the data is in the DataStore (or there was nothing new to save)
local function save(player: Player, release: boolean): boolean
	local session = sessions[player]
	local dataStore = store
	if not session or not session.saving or not dataStore then
		return false
	end
	if release then
		session.leaving = true
	end
	-- (saved even when nothing changed: the write renews the lock)
	session.dirty = false
	local data = session.data
	local written = false
	local ok, err = pcall(function()
		dataStore:UpdateAsync(key(player), function(old)
			if session.leaving and not release then
				written = false
				return nil -- they've left: the last save has the data, and this would lock them again
			end
			local lock = typeof(old) == "table" and old.Lock or nil
			if USE_LOCKS and typeof(lock) == "table" and lock.Job ~= game.JobId then
				written = false
				return nil -- another server has taken over: its copy is the real one now
			end
			written = true
			return {
				Credits = data.Credits,
				Skins = data.Skins,
				Equipped = data.Equipped,
				TouchLayout = data.TouchLayout,
				Attachments = data.Attachments,
				OwnedAttachments = data.OwnedAttachments,
				LobbyWeapon = data.LobbyWeapon,
				Settings = data.Settings,
				Xp = data.Xp,
				RewardedLevel = data.RewardedLevel,
				Kills = data.Kills,
				Headshots = data.Headshots,
				Wins = data.Wins,
				Matches = data.Matches,
				TutorialDone = data.TutorialDone,
				TutorialSeen = data.TutorialSeen,
				DailyDay = data.DailyDay,
				DailyStreak = data.DailyStreak,
				ChallengeDay = data.ChallengeDay,
				Challenges = data.Challenges,
				Mmr = data.Mmr,
				RankedMatches = data.RankedMatches,
				RankedWins = data.RankedWins,
				Purchases = data.Purchases,
				StarterPackGranted = data.StarterPackGranted,
				ClanId = data.ClanId,
				Lock =if USE_LOCKS and not release then { Job = game.JobId, At = os.time() } else nil,
			}
		end)
	end)
	if not ok then
		session.dirty = true
		warn(`PlayerData: couldn't save {player.Name}: {err}`)
	end
	return ok and written
end

-- The player's data, or nil if it hasn't loaded yet. Change it with Update, not directly.
function PlayerData.Get(player: Player): Data?
	local session = sessions[player]
	return session and session.data
end

-- Changes a player's data: `change` edits it in place. Clients see the result right away; it's
-- saved soon after if `saveSoon` (purchases), otherwise with the next autosave or on leaving.
-- Returns false if their data isn't loaded yet.
function PlayerData.Update(player: Player, change: (Data) -> (), saveSoon: boolean?): boolean
	local session = sessions[player]
	if not session then
		return false
	end
	change(session.data)
	session.dirty = true
	publish(player, session.data)
	if saveSoon and not session.saveQueued then
		session.saveQueued = true
		task.delay(2, function() -- (several purchases in a row → one save)
			session.saveQueued = false
			if sessions[player] == session then
				save(player, false)
			end
		end)
	end
	return true
end

-- False when there's no DataStore: changes are lost when the player leaves
function PlayerData.IsSaving(player: Player): boolean
	local session = sessions[player]
	return session ~= nil and session.saving
end

-- Saves right now and waits for it (StoreService: a Robux purchase is only confirmed to Roblox
-- once it's saved). True if the DataStore has the data as it is now.
function PlayerData.SaveNow(player: Player): boolean
	local session = sessions[player]
	if not session then
		return false
	end
	session.dirty = true -- (even if an autosave is already on its way: that one might fail)
	return save(player, false)
end

-- Runs `hook` when a player is leaving, before their data's last save (RankedService: leaving a
-- ranked match early is a loss). Changes made there with Update are in that save.
local leavingHooks: { (Player) -> () } = {}
function PlayerData.OnLeaving(hook: (Player) -> ())
	table.insert(leavingHooks, hook)
end

-- The last save (player leaving, server closing), retried: one failure would lose everything
-- since the last autosave
local function releaseSave(player: Player)
	for attempt = 1, RELEASE_TRIES do
		local session = sessions[player]
		if not session or not session.saving or save(player, true) then
			return
		end
		if attempt < RELEASE_TRIES then
			task.wait(RELEASE_RETRY)
		end
	end
	warn(`PlayerData: gave up saving {player.Name} after {RELEASE_TRIES} tries`)
end

local function onPlayerRemoving(player: Player)
	if sessions[player] then
		for _, hook in leavingHooks do
			local ok, err = pcall(hook, player)
			if not ok then
				warn(`PlayerData: leaving hook failed for {player.Name}: {err}`)
			end
		end
	end
	releaseSave(player)
	sessions[player] = nil
end

local function onPlayerAdded(player: Player)
	local data = load(player)
	local saving = data ~= nil
	sessions[player] = { data = data or newData(), saving = saving, dirty = false, saveQueued = false, leaving = false }
	if not player.Parent then
		onPlayerRemoving(player) -- left while loading: hand the lock back
		return
	end
	player:SetAttribute("DataOffline", not saving)
	publish(player, sessions[player].data)
end

function PlayerData.Start()
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_INTERVAL)
			for player in sessions do
				task.spawn(save, player, false)
			end
		end
	end)

	-- Server shutting down: save everyone before it goes (Roblox gives up to 30 seconds)
	game:BindToClose(function()
		local pending = 0
		for player in sessions do
			pending += 1
			task.spawn(function()
				releaseSave(player)
				pending -= 1
			end)
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return PlayerData
