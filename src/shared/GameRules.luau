-- Game modes on top of the objective (MatchConfig GameMode: bomb or elimination): which guns are
-- in the loadout draft, plus a few rule changes. Voted on with the map before every match
-- (RoundService.voteMap, client MapVote); the winner is MatchState's "Rules" attribute until the
-- match ends (free roam is always Classic).
-- Knives Only takes the guns away: your "weapon" is the knife (Weapon attribute = GameRules.NoGun),
-- the fire button stabs too, and the knife recharges faster.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MatchConfig = require(script.Parent.MatchConfig)

export type Rules = {
	Id: string,
	Name: string,
	Description: string,
	Weapons: { string }?, -- only these in the draft (nil = every gun, empty = no guns at all)
	HeadshotsOnly: boolean?, -- body shots do nothing
	MeleeCooldown: number?, -- seconds between knife swings (MatchConfig.MeleeCooldown otherwise)
	Colors: { Color3 }, -- vote card (dark → light)
}

local GameRules = {}

GameRules.NoGun = "Knife" -- the Weapon attribute when you have no gun

local function rules(id: string, name: string, description: string, colors: { Color3 }, extra: { [string]: any }?): Rules
	local r: any = { Id = id, Name = name, Description = description, Colors = colors }
	for key, value in extra or {} do
		r[key] = value
	end
	return r
end

local rgb = Color3.fromRGB

-- Vote order
GameRules.List = {
	rules("Classic", "Classic", "Draft any gun", { rgb(40, 45, 60), rgb(110, 120, 150) }),
	rules("Snipers", "Snipers Only", "Everyone gets a sniper", { rgb(30, 55, 40), rgb(110, 170, 100) }, { Weapons = { "Sniper" } }),
	rules("Shotguns", "Shotguns Only", "Close quarters, big pellets", { rgb(70, 35, 25), rgb(210, 110, 60) }, { Weapons = { "Shotgun" } }),
	rules("Pistols", "Pistols Only", "Revolvers and autopistols", { rgb(45, 40, 70), rgb(150, 120, 220) }, { Weapons = { "Revolver", "Autopistol" } }),
	rules("Gatlings", "Gatlings Only", "Everyone spins up a minigun", { rgb(50, 52, 58), rgb(230, 150, 50) }, { Weapons = { "Gatling" } }),
	rules("Knives", "Knives Only", "No guns. One stab kills", { rgb(70, 20, 30), rgb(220, 70, 80) }, { Weapons = {}, MeleeCooldown = 0.6 }),
	rules("Headshots", "Headshots Only", "Body shots do nothing", { rgb(60, 50, 15), rgb(230, 190, 60) }, { HeadshotsOnly = true }),
}

GameRules.ById = {} :: { [string]: Rules }
for _, r in GameRules.List do
	GameRules.ById[r.Id] = r
end

-- The rules this match is played with (Classic outside a match)
function GameRules.Current(): Rules
	local state = ReplicatedStorage:FindFirstChild("MatchState")
	local id = state and state:GetAttribute("Rules")
	return GameRules.ById[id] or GameRules.ById.Classic
end

function GameRules.MeleeCooldown(): number
	return GameRules.Current().MeleeCooldown or MatchConfig.MeleeCooldown
end

return GameRules
