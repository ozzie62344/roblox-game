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
-- hold in the lobby: SettingsService).

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Attachments = require(ReplicatedStorage.Shared.Attachments)
local MatchConfig = require(ReplicatedStorage.Shared.MatchConfig)
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
}

local PlayerData = {}

local STORE_NAME = "PlayerData_v1"
local AUTOSAVE_INTERVAL = 180
local LOCK_EXPIRY = 120 -- seconds: a lock older than this was left by a crashed server
local LOAD_RETRY = 2 -- seconds between tries while another server still holds the lock
local LOAD_TRIES = 15 -- then take it anyway
-- Studio test sessions stop abruptly and all share JobId "", so they don't lock
local USE_LOCKS = not RunService:IsStudio()

type Session = {
	data: Data,
	saving: boolean, -- false: no DataStore, nothing is written
	dirty: boolean,
	saveQueued: boolean,
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
	return { Credits = MatchConfig.Credits.Starting, Skins = {}, Equipped = {}, TouchLayout = "", Attachments = {}, OwnedAttachments = {}, LobbyWeapon = "" }
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

local function save(player: Player, release: boolean)
	local session = sessions[player]
	local dataStore = store
	if not session or not session.saving or not dataStore then
		return
	end
	if not session.dirty and not release then
		return
	end
	session.dirty = false
	local data = session.data
	local ok, err = pcall(function()
		dataStore:UpdateAsync(key(player), function(old)
			local lock = typeof(old) == "table" and old.Lock or nil
			if USE_LOCKS and typeof(lock) == "table" and lock.Job ~= game.JobId then
				return nil -- another server has taken over: its copy is the real one now
			end
			return {
				Credits = data.Credits,
				Skins = data.Skins,
				Equipped = data.Equipped,
				TouchLayout = data.TouchLayout,
				Attachments = data.Attachments,
				OwnedAttachments = data.OwnedAttachments,
				LobbyWeapon = data.LobbyWeapon,
				Lock = if USE_LOCKS and not release then { Job = game.JobId, At = os.time() } else nil,
			}
		end)
	end)
	if not ok then
		session.dirty = true
		warn(`PlayerData: couldn't save {player.Name}: {err}`)
	end
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

local function onPlayerRemoving(player: Player)
	save(player, true)
	sessions[player] = nil
end

local function onPlayerAdded(player: Player)
	local data = load(player)
	local saving = data ~= nil
	sessions[player] = { data = data or newData(), saving = saving, dirty = false, saveQueued = false }
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
				save(player, true)
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
