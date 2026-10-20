-- A match's details (mode, who's coming and on which team, ranked, a custom match's settings),
-- kept where players can't touch them. Teleport data travels through the players' clients, so a
-- modified client could change it (make a ranked match unrated, swap the teams); the lobby
-- writes the same table here under the reserved server's id before teleporting (Matchmaker,
-- CustomMatchService) and the match server reads it back (RoundService).

local MemoryStoreService = game:GetService("MemoryStoreService")

local MatchTicket = {}

local MAP_NAME = "MatchTickets_v1"
local EXPIRY = 15 * 60 -- seconds: long after everyone has arrived
local WRITE_TRIES = 3
local READ_TRIES = 6 -- (the first player can land before the lobby's write has gone through)
local RETRY_WAIT = 1

local function map(): MemoryStoreHashMap?
	local ok, result = pcall(MemoryStoreService.GetHashMap, MemoryStoreService, MAP_NAME)
	return if ok then result else nil
end

-- Saves `ticket` for the match server `privateServerId` (ReserveServer's second result). True if
-- it's stored.
function MatchTicket.Write(privateServerId: string, ticket: { [string]: any }): boolean
	local store = map()
	if not store or privateServerId == "" then
		return false
	end
	for attempt = 1, WRITE_TRIES do
		local ok, err = pcall(store.SetAsync, store, privateServerId, ticket, EXPIRY)
		if ok then
			return true
		end
		warn(`MatchTicket: couldn't save ({attempt}/{WRITE_TRIES}): {err}`)
		task.wait(RETRY_WAIT)
	end
	return false
end

-- This match server's ticket, or nil if there isn't one (or MemoryStore can't be reached).
-- Read once and remembered; callers arriving while it's being read wait for it.
local loaded = false
local loading = false
local cached: { [string]: any }? = nil
function MatchTicket.Read(privateServerId: string): { [string]: any }?
	while loading do
		task.wait(0.1)
	end
	if loaded then
		return cached
	end
	loading = true
	local store = map()
	for attempt = 1, if store and privateServerId ~= "" then READ_TRIES else 0 do
		local ok, value = pcall((store :: MemoryStoreHashMap).GetAsync, store, privateServerId)
		if ok and typeof(value) == "table" then
			cached = value
			break
		end
		if attempt < READ_TRIES then
			task.wait(RETRY_WAIT)
		end
	end
	loaded, loading = true, false
	return cached
end

return MatchTicket
