-- Hands every player an operator (Operators.luau) each round: their gadget and one of their guns.
--   Draft:  everyone sees their side's operators and picks one plus a gun (can change until the
--           timer ends); anyone who doesn't gets a random free one when the round starts
--   Random: everyone gets a random operator for their side, with a random gun from their list
-- Two teammates can't be the same operator: the first to pick gets it, and the others see that
-- card taken. Once you've used a charge of your gadget (defenders during setup), your operator is
-- locked in, so you can't swap through several operators' gadgets; you can still change guns.
-- Guns come from the operator, cut down to what the match's mode allows (Operators.WeaponsFor).
-- Clients are told through LoadoutOffer(offer) (sent again whenever a teammate picks) and pick
-- with DraftPick(operatorId, weapon).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Abilities = require(ReplicatedStorage.Shared.Abilities)
local GameRules = require(ReplicatedStorage.Shared.GameRules)
local Operators = require(ReplicatedStorage.Shared.Operators)
local Weapons = require(ReplicatedStorage.Shared.Weapons)
local AbilityService = require(script.Parent.AbilityService)
local WeaponService = require(script.Parent.WeaponService)

local Remotes = ReplicatedStorage.Remotes
local LoadoutOffer = Remotes.LoadoutOffer :: RemoteEvent
local DraftPick = Remotes.DraftPick :: RemoteEvent

-- What a client gets: its side's operators (with the guns each can take in this mode, and who on
-- the team already has them), its own pick, and whether it can still change
export type Offer = {
	Side: string,
	Random: boolean,
	Deadline: number,
	Operators: { { Id: string, Weapons: { string }, TakenBy: string? } },
	Pick: { Operator: string, Weapon: string }?,
	Locked: boolean, -- gadget already used: only the gun can change
}

local LoadoutService = {}

type Entry = { side: string, picked: boolean }
local entries: { [Player]: Entry } = {}
local roundMode = "Draft"
local roundDeadline = 0

-- "Attack" or "Defend" this round
local function sideOf(player: Player): string
	local attackTeam = ReplicatedStorage.MatchState:GetAttribute("AttackTeam")
	return if player.Team and player.Team.Name == attackTeam then "Attack" else "Defend"
end

local function sameTeam(a: Player, b: Player): boolean
	return a ~= b and a.Team ~= nil and a.Team == b.Team
end

-- The teammate playing `operatorId` this round, if any
local function takenBy(player: Player, operatorId: string): Player?
	for other in entries do
		if sameTeam(player, other) and other.Parent and other:GetAttribute("Operator") == operatorId then
			return other
		end
	end
	return nil
end

-- Used a charge of your gadget this round? Then you stay that operator.
local function gadgetUsed(player: Player): boolean
	local abilityName = player:GetAttribute("Ability")
	local ability = if typeof(abilityName) == "string" then Abilities[abilityName] else nil
	local charges = player:GetAttribute("AbilityCharges")
	return ability ~= nil and ability.Charges ~= nil and typeof(charges) == "number" and charges < ability.Charges
end

local function apply(player: Player, operator: Operators.Operator, weapon: string)
	WeaponService.SetWeapon(player, weapon)
	player:SetAttribute("Operator", operator.Id)
	if player:GetAttribute("Ability") ~= operator.Gadget then
		player:SetAttribute("Ability", operator.Gadget)
		AbilityService.ResetCharges(player) -- now, not when the attribute signal gets round to it (gadgetUsed reads them)
	end
end

local function sendOffer(player: Player)
	local entry = entries[player]
	if not entry then
		return
	end
	local list = {}
	for _, operator in Operators.ForSide(entry.side) do
		local holder = takenBy(player, operator.Id)
		table.insert(list, { Id = operator.Id, Weapons = Operators.WeaponsFor(operator), TakenBy = if holder then holder.DisplayName else nil })
	end
	local operatorId = player:GetAttribute("Operator")
	local offer: Offer = {
		Side = entry.side,
		Random = roundMode == "Random",
		Deadline = roundDeadline,
		Operators = list,
		Pick = if entry.picked and typeof(operatorId) == "string" then { Operator = operatorId, Weapon = player:GetAttribute("Weapon") } else nil,
		Locked = gadgetUsed(player),
	}
	LoadoutOffer:FireClient(player, offer)
end

-- Everyone on `player`'s team sees the new picks
local function sendToTeam(player: Player)
	for other in entries do
		if other == player or sameTeam(player, other) then
			sendOffer(other)
		end
	end
end

-- A random operator for `player`'s side that no teammate has, with a random gun of theirs
local function assignRandom(player: Player)
	local entry = entries[player]
	local free = {}
	for _, operator in Operators.ForSide(entry.side) do
		if not takenBy(player, operator.Id) then
			table.insert(free, operator)
		end
	end
	if #free == 0 then
		free = Operators.ForSide(entry.side) -- (bigger team than roster: share)
	end
	local operator = free[math.random(#free)]
	local guns = Operators.WeaponsFor(operator)
	apply(player, operator, guns[math.random(#guns)])
	entry.picked = true
end

-- Called by RoundService at the start of each round's freeze
function LoadoutService.StartRound(players: { Player }, mode: string, duration: number)
	table.clear(entries)
	roundMode = mode
	roundDeadline = Workspace:GetServerTimeNow() + duration
	for _, player in players do
		entries[player] = { side = sideOf(player), picked = false }
		-- Last round's operator may be on the other side now: nobody is anyone until they pick
		player:SetAttribute("Operator", nil)
		player:SetAttribute("Ability", nil)
	end
	-- Random: handed out in a random order, so nobody always gets first dibs
	local order = table.clone(players)
	for i = #order, 2, -1 do
		local j = math.random(i)
		order[i], order[j] = order[j], order[i]
	end
	for _, player in order do
		if mode == "Random" then
			assignRandom(player)
		else
			-- Until they pick, nobody holds a gun this mode doesn't allow (no rifle in Knives Only)
			local allowed = GameRules.Current().Weapons
			if allowed and not table.find(allowed, player:GetAttribute("Weapon")) then
				WeaponService.SetWeapon(player, allowed[1] or GameRules.NoGun)
			end
		end
	end
	for player in entries do
		sendOffer(player)
	end
end

-- Called when the freeze ends: anyone who didn't pick gets a random free operator
function LoadoutService.FinishRound()
	for player, entry in entries do
		if not entry.picked and player.Parent then
			assignRandom(player)
		end
	end
	table.clear(entries)
end

-- Back to the gun they picked for the lobby (or the default) between matches
function LoadoutService.Reset(player: Player)
	local picked = player:GetAttribute("LobbyWeapon")
	WeaponService.SetWeapon(player, if typeof(picked) == "string" and Weapons[picked] then picked else WeaponService.DefaultWeapon)
	player:SetAttribute("Operator", nil)
	player:SetAttribute("Ability", nil)
end

local function onPick(player: Player, operatorId: any, weapon: any)
	local entry = entries[player]
	if not entry or roundMode == "Random" or typeof(operatorId) ~= "string" or Workspace:GetServerTimeNow() > roundDeadline then
		return
	end
	local operator = Operators.ById[operatorId]
	if not operator or operator.Side ~= entry.side then
		return
	end
	local current = player:GetAttribute("Operator")
	if takenBy(player, operator.Id) or (current ~= operator.Id and current ~= nil and gadgetUsed(player)) then
		sendOffer(player) -- refused: put their screen back the way it is
		return
	end
	local guns = Operators.WeaponsFor(operator)
	if typeof(weapon) ~= "string" or not table.find(guns, weapon) then
		local holding = player:GetAttribute("Weapon")
		weapon = if table.find(guns, holding) then holding else guns[1]
	end
	apply(player, operator, weapon)
	entry.picked = true
	sendToTeam(player)
end

function LoadoutService.Start()
	DraftPick.OnServerEvent:Connect(onPick)
	Players.PlayerRemoving:Connect(function(player)
		if entries[player] then
			player:SetAttribute("Operator", nil) -- (frees the operator for the team)
			entries[player] = nil
			for other in entries do
				if other.Team == player.Team then
					sendOffer(other)
				end
			end
		end
	end)
end

return LoadoutService
