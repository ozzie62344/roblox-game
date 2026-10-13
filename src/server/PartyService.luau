-- Parties: up to 5 friends who queue and play together (client Match/PartyMenu).
--   Party:FireServer("Invite", player)     ask someone in this lobby to join your party
--   Party:FireServer("Accept", inviter)    join the inviter's party (leaving the one you're in)
--   Party:FireServer("Decline", inviter)
--   Party:FireServer("Leave")              the leader leaving hands the party to the next one in
--   Party:FireServer("Kick", player)       leader only
--   Party:FireClient(player, "Invite", inviter, seconds)   someone wants you in (JOIN / NO popup)
--   Party:FireClient(player, "Sent", invitee, seconds)     your invite went out
--   Party:FireClient(player, "Answered", invitee)          they said yes or no
--   Party:FireClient(player, "Notice", text)               what happened ("BOB LEFT THE PARTY")
-- Everyone in a party has the "PartyLeader" attribute (the leader's UserId), so every client can
-- see who's with whom. Only the leader invites, kicks and queues: Matchmaker queues the party as
-- one and keeps it on one team. Parties are only made in the lobby; they travel to the match and
-- back in the teleport data (ForTeleport) and form again on the server they land on.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Party = ReplicatedStorage.Remotes.Party :: RemoteEvent
local MatchState = ReplicatedStorage.MatchState

local PartyService = {}

local MAX_SIZE = 5
local INVITE_TIME = 30 -- seconds an invite can be answered
local SNOOZE_TIME = 30 -- after a NO, the same person can't ask again for this long
local REJOIN_TIME = 60 -- after landing from a teleport, how long the rest of your party can still find you

PartyService.MaxSize = MAX_SIZE

-- The party a teleported player came with: its key in the teleport data and who was in it
type Origin = { key: string, ids: { number } }

type Party = {
	members: { Player }, -- leader first, then in the order they joined
	origin: Origin?, -- formed again after a teleport (more of it may still be arriving)
}

local partyOf: { [Player]: Party } = {}
local invites: { [Player]: { [Player]: number } } = {} -- invitee → inviter → when it runs out (os.clock)
local snoozed: { [Player]: { [Player]: number } } = {} -- invitee → inviter → no new invites until then
local arrivals: { [Player]: Origin } = {} -- just teleported in with a party
local byKey: { [string]: Party } = {} -- parties formed again after a teleport, by their key
local lastRequest: { [Player]: number } = {}
local listeners: { (players: { Player }) -> () } = {}

-- Parties are only made in the lobby, between matches
local function canChange(): boolean
	return MatchState:GetAttribute("ServerKind") == "Lobby" and MatchState:GetAttribute("Phase") == "Waiting"
end

local function notice(player: Player, text: string)
	if player.Parent then
		Party:FireClient(player, "Notice", string.upper(text))
	end
end

-- Tells Matchmaker (OnChanged) who was in a party that just changed
local function changed(players: { Player })
	local copy = table.clone(players)
	for _, callback in listeners do
		task.spawn(callback, copy)
	end
end

-- Clients read the parties from every member's "PartyLeader" attribute
local function publish(party: Party)
	local leaderId = party.members[1].UserId
	for _, member in party.members do
		member:SetAttribute("PartyLeader", leaderId)
	end
end

-- Takes `player` out of their party and tells the rest (`message`). The next one in leads if the
-- leader left; a party of one is no party, so it breaks up.
local function remove(player: Player, message: string?)
	local party = partyOf[player]
	if not party then
		return
	end
	local before = table.clone(party.members)
	local wasLeader = party.members[1] == player
	table.remove(party.members, table.find(party.members, player) :: number)
	partyOf[player] = nil
	player:SetAttribute("PartyLeader", nil)

	local rest = party.members
	if message then
		local text = if wasLeader and #rest >= 2 then `{message} · {rest[1].DisplayName} leads now` else message
		for _, member in rest do
			notice(member, text)
		end
	end
	if #rest >= 2 then
		publish(party)
	else
		for _, member in rest do
			partyOf[member] = nil
			member:SetAttribute("PartyLeader", nil)
		end
		table.clear(rest)
		if party.origin and byKey[party.origin.key] == party then
			byKey[party.origin.key] = nil
		end
	end
	changed(before)
end

-- Puts `player` in `party` (out of the one they're in first)
local function add(party: Party, player: Player)
	if partyOf[player] then
		remove(player, `{player.DisplayName} left the party`)
	end
	table.insert(party.members, player)
	partyOf[player] = party
	publish(party)
	changed(party.members)
end

-- A new party: `players` in that order, the first one leads
local function create(players: { Player }, origin: Origin?): Party
	local party: Party = { members = {}, origin = origin }
	for _, player in players do
		if partyOf[player] then
			remove(player, `{player.DisplayName} left the party`)
		end
		table.insert(party.members, player)
		partyOf[player] = party
	end
	publish(party)
	if origin then
		byKey[origin.key] = party
	end
	changed(party.members)
	return party
end

local function invite(player: Player, target: Player)
	local party = partyOf[player]
	if party and (party.members[1] ~= player or table.find(party.members, target)) then
		return -- only the leader invites (and not who's already in)
	end
	if party and #party.members >= MAX_SIZE then
		notice(player, "Your party is full")
		return
	end
	local now = os.clock()
	local theirs = invites[target] or {}
	local quiet = snoozed[target]
	if (theirs[player] or 0) > now or (quiet and (quiet[player] or 0) > now) then
		return -- asked already (or they just said no)
	end
	theirs[player] = now + INVITE_TIME
	invites[target] = theirs
	Party:FireClient(target, "Invite", player, INVITE_TIME)
	Party:FireClient(player, "Sent", target, INVITE_TIME)
end

local function accept(player: Player, inviter: Player)
	local theirs = invites[player]
	local expires = if theirs then theirs[inviter] else nil
	if not theirs or not expires then
		return
	end
	theirs[inviter] = nil
	Party:FireClient(inviter, "Answered", player)

	local party = partyOf[inviter]
	if expires < os.clock() then
		notice(player, "That invite ran out")
	elseif party and table.find(party.members, player) then
		return -- (already in it)
	elseif party and party.members[1] ~= inviter then
		notice(player, `{inviter.DisplayName} isn't leading a party anymore`)
	elseif party and #party.members >= MAX_SIZE then
		notice(player, `{inviter.DisplayName}'s party is full`)
	else
		if party then
			for _, member in party.members do
				notice(member, `{player.DisplayName} joined the party`)
			end
			add(party, player)
		else
			notice(inviter, `{player.DisplayName} joined your party`)
			create({ inviter, player })
		end
		notice(player, `You joined {inviter.DisplayName}'s party`)
	end
end

local function decline(player: Player, inviter: Player)
	local theirs = invites[player]
	if not theirs or not theirs[inviter] then
		return
	end
	theirs[inviter] = nil
	local quiet = snoozed[player] or {}
	quiet[inviter] = os.clock() + SNOOZE_TIME
	snoozed[player] = quiet
	Party:FireClient(inviter, "Answered", player)
	notice(inviter, `{player.DisplayName} said no`)
end

local function kick(player: Player, target: Player)
	local party = partyOf[player]
	if party and party.members[1] == player and partyOf[target] == party then
		remove(target, `{target.DisplayName} was kicked`)
		notice(target, `{player.DisplayName} kicked you from the party`)
	end
end

local function leave(player: Player)
	arrivals[player] = nil -- (the rest of an old party arriving late won't pull you back in)
	if partyOf[player] then
		remove(player, `{player.DisplayName} left the party`)
		notice(player, "You left the party")
	end
end

-- The party `player` was in when they were teleported here (Matchmaker → match server, or
-- RoundService → back to a lobby), from the "Parties" ForTeleport put in the teleport data
local function originOf(player: Player): Origin?
	local data = player:GetJoinData().TeleportData
	local list = if typeof(data) == "table" then data.Parties else nil
	if typeof(list) ~= "table" then
		return nil
	end
	for _, entry in list do
		if typeof(entry) == "table" and typeof(entry.Key) == "string" and typeof(entry.Ids) == "table" then
			local ids = {}
			for _, id in entry.Ids do
				if typeof(id) == "number" and #ids < MAX_SIZE then
					table.insert(ids, id)
				end
			end
			if table.find(ids, player.UserId) then
				return { key = entry.Key, ids = ids }
			end
		end
	end
	return nil
end

-- Teleported players land one by one: their party forms again as soon as two of it are here,
-- and the rest join it as they arrive (the old leader leads again when they do)
local function arrive(player: Player)
	local origin = originOf(player)
	if not origin then
		return
	end
	arrivals[player] = origin
	task.delay(REJOIN_TIME, function()
		if arrivals[player] == origin then
			arrivals[player] = nil
		end
	end)

	local party = byKey[origin.key]
	if party then
		local from = party.origin
		if not partyOf[player] and #party.members < MAX_SIZE and from and table.find(from.ids, player.UserId) then
			add(party, player)
			if from.ids[1] == player.UserId then
				table.remove(party.members)
				table.insert(party.members, 1, player)
				publish(party)
			end
		end
		return
	end

	local here = {}
	for _, other in Players:GetPlayers() do
		local theirs = arrivals[other]
		if theirs and theirs.key == origin.key and not partyOf[other] and table.find(origin.ids, other.UserId) then
			table.insert(here, other)
		end
	end
	if #here >= 2 then
		table.sort(here, function(a, b)
			return (table.find(origin.ids, a.UserId) :: number) < (table.find(origin.ids, b.UserId) :: number)
		end)
		create(here, origin)
	end
end

-- Everyone in `player`'s party, leader first (just them if they're on their own)
function PartyService.MembersOf(player: Player): { Player }
	local party = partyOf[player]
	return if party then table.clone(party.members) else { player }
end

-- Who decides for `player`: their party's leader (themselves if they're on their own)
function PartyService.LeaderOf(player: Player): Player
	local party = partyOf[player]
	return if party then party.members[1] else player
end

-- `callback(players)` whenever a party changes (someone joins, leaves or is kicked): everyone
-- who was in it
function PartyService.OnChanged(callback: (players: { Player }) -> ())
	table.insert(listeners, callback)
end

-- The parties among `players` for a teleport's data ("Parties"): who's in each (leader first)
-- under a key of its own, so the server they land on can put them back together (arrive)
function PartyService.ForTeleport(players: { Player }): { { Key: string, Ids: { number } } }
	local list, seen = {}, {}
	for _, player in players do
		local party = partyOf[player]
		if party and not seen[party] then
			seen[party] = true
			local ids = {}
			for _, member in party.members do
				if table.find(players, member) then
					table.insert(ids, member.UserId)
				end
			end
			if #ids >= 2 then
				table.insert(list, { Key = HttpService:GenerateGUID(false), Ids = ids })
			end
		end
	end
	return list
end

function PartyService.Start()
	MatchState:SetAttribute("PartyMaxSize", MAX_SIZE)

	Party.OnServerEvent:Connect(function(player, action, target)
		-- (a few requests a second is plenty for clicking around a menu)
		local now = os.clock()
		if now - (lastRequest[player] or 0) < 0.1 then
			return
		end
		lastRequest[player] = now
		if action == "Leave" then
			leave(player)
			return
		end
		-- Everything else is about another player in this lobby
		if not canChange() or typeof(target) ~= "Instance" or not target:IsA("Player") or target.Parent ~= Players or target == player then
			return
		end
		local other = target :: Player
		if action == "Invite" then
			invite(player, other)
		elseif action == "Accept" then
			accept(player, other)
		elseif action == "Decline" then
			decline(player, other)
		elseif action == "Kick" then
			kick(player, other)
		end
	end)

	for _, player in Players:GetPlayers() do
		task.spawn(arrive, player)
	end
	Players.PlayerAdded:Connect(arrive)
	Players.PlayerRemoving:Connect(function(player)
		remove(player, `{player.DisplayName} left the game`)
		invites[player] = nil
		snoozed[player] = nil
		for _, theirs in invites do
			theirs[player] = nil
		end
		for _, theirs in snoozed do
			theirs[player] = nil
		end
		arrivals[player] = nil
		lastRequest[player] = nil
	end)
end

return PartyService
