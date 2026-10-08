-- Hands out a weapon + ability to every player each round.
--   Draft:  each player is offered 3 loadouts and picks one (can change until the timer ends)
--   Random: each player gets a random loadout
-- Clients are told through LoadoutOffer(options, deadline, isRandom) and pick with DraftPick(index).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Abilities = require(ReplicatedStorage.Shared.Abilities)
local MatchConfig = require(ReplicatedStorage.Shared.MatchConfig)
local Weapons = require(ReplicatedStorage.Shared.Weapons)
local WeaponService = require(script.Parent.WeaponService)

local Remotes = ReplicatedStorage.Remotes
local LoadoutOffer = Remotes.LoadoutOffer :: RemoteEvent
local DraftPick = Remotes.DraftPick :: RemoteEvent

export type Loadout = { Weapon: string, Ability: string }

local LoadoutService = {}

local offers: { [Player]: { options: { Loadout }, picked: boolean } } = {}

local function keysOf(t: { [string]: any }): { string }
	local keys = {}
	for key in t do
		table.insert(keys, key)
	end
	table.sort(keys) -- stable order before shuffling
	return keys
end

local function shuffle<T>(list: { T }): { T }
	for i = #list, 2, -1 do
		local j = math.random(i)
		list[i], list[j] = list[j], list[i]
	end
	return list
end

local function randomAbility(): string
	local names = keysOf(Abilities)
	return names[math.random(#names)]
end

-- Different weapons on every card so the choice actually matters
local function generateOptions(count: number): { Loadout }
	local weaponNames = shuffle(keysOf(Weapons))
	local options = {}
	for i = 1, math.min(count, #weaponNames) do
		table.insert(options, { Weapon = weaponNames[i], Ability = randomAbility() })
	end
	return options
end

local function apply(player: Player, loadout: Loadout)
	WeaponService.SetWeapon(player, loadout.Weapon)
	player:SetAttribute("Ability", loadout.Ability)
end

-- Called by RoundService at the start of each round's freeze
function LoadoutService.StartRound(players: { Player }, mode: string, duration: number)
	table.clear(offers)
	local deadline = Workspace:GetServerTimeNow() + duration
	for _, player in players do
		if mode == "Random" then
			local loadout = generateOptions(1)[1]
			apply(player, loadout)
			LoadoutOffer:FireClient(player, { loadout }, deadline, true)
		else
			local options = generateOptions(MatchConfig.DraftOptions)
			offers[player] = { options = options, picked = false }
			LoadoutOffer:FireClient(player, options, deadline, false)
		end
	end
end

-- Called when the freeze ends: anyone who didn't pick gets a random card from their offer
function LoadoutService.FinishRound()
	for player, offer in offers do
		if not offer.picked and player.Parent then
			apply(player, offer.options[math.random(#offer.options)])
		end
	end
	table.clear(offers)
end

-- Back to the free-roam default between matches
function LoadoutService.Reset(player: Player)
	WeaponService.SetWeapon(player, WeaponService.DefaultWeapon)
	player:SetAttribute("Ability", nil)
end

function LoadoutService.Start()
	DraftPick.OnServerEvent:Connect(function(player, index)
		local offer = offers[player]
		if not offer or typeof(index) ~= "number" then
			return
		end
		local loadout = offer.options[index]
		if loadout then
			apply(player, loadout)
			offer.picked = true
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		offers[player] = nil
	end)
end

return LoadoutService
