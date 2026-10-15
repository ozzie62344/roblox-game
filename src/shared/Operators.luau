-- Operators: the named characters you pick at the start of every round (LoadoutPicker on the
-- client, LoadoutService on the server).
--   Each one plays one side (Attack or Defend), has Armor / Speed ratings (1-3, adding up to 4),
--   always brings the same gadget (an ability from
--   Abilities.luau, used with X) and takes one gun from a short list, picked with the operator.
--   Two teammates can't be the same operator in a round (LoadoutService enforces it).
--   Game modes that restrict guns (GameRules Weapons) win over the list: it's cut down to the
--   mode's guns, or replaced by them when none overlap (Snipers Only: everyone gets the sniper).

local GameRules = require(script.Parent.GameRules)
local Weapons = require(script.Parent.Weapons)

export type Operator = {
	Id: string,
	Name: string,
	Side: "Attack" | "Defend",
	-- Siege-style ratings, Armor + Speed = 4: 3-armor anchors are tanky and slow, 3-speed roamers
	-- and entry fraggers fast and fragile. Speed scales movement (MovementConfig.SpeedRating);
	-- Armor is for damage taken (WeaponService).
	Armor: number, -- 1-3
	Speed: number, -- 1-3
	Bio: string, -- one line on the card
	Gadget: string, -- Abilities key
	Weapons: { string }, -- Weapons keys, in card order
	Color: Color3, -- card accent
}

local rgb = Color3.fromRGB

local Operators = {}

-- Card order
Operators.List = {
	-- Attack
	{ Id = "Ram", Name = "Ram", Side = "Attack", Armor = 2, Speed = 2, Gadget = "BreachCharge", Weapons = { "Rifle", "Shotgun", "Revolver" }, Color = rgb(220, 120, 50),
		Bio = "Opens soft walls the loud way and walks in through the dust." },
	{ Id = "Cinder", Name = "Cinder", Side = "Attack", Armor = 2, Speed = 2, Gadget = "HardBreach", Weapons = { "Rifle", "LMG", "Autopistol" }, Color = rgb(235, 90, 40),
		Bio = "Burns through reinforced steel so the team has a way in." },
	{ Id = "Static", Name = "Static", Side = "Attack", Armor = 2, Speed = 2, Gadget = "EmpGrenade", Weapons = { "SMG", "Marksman", "Shotgun" }, Color = rgb(90, 170, 255),
		Bio = "Fries wires, jammers and cameras so the breachers can work." },
	{ Id = "Nova", Name = "Nova", Side = "Attack", Armor = 1, Speed = 3, Gadget = "Flashbang", Weapons = { "SMG", "Rifle", "Revolver" }, Color = rgb(240, 225, 140),
		Bio = "Blinds the room, then clears it before anyone can see again." },
	{ Id = "Haze", Name = "Haze", Side = "Attack", Armor = 3, Speed = 1, Gadget = "SmokeGrenade", Weapons = { "LMG", "Marksman", "Autopistol" }, Color = rgb(170, 180, 170),
		Bio = "Walls of smoke for the push and the plant." },
	{ Id = "Trace", Name = "Trace", Side = "Attack", Armor = 1, Speed = 3, Gadget = "HeartbeatSensor", Weapons = { "Sniper", "Marksman", "SMG" }, Color = rgb(255, 80, 90),
		Bio = "Hears heartbeats through walls and calls out who's hiding where." },

	-- Defend
	{ Id = "Volta", Name = "Volta", Side = "Defend", Armor = 1, Speed = 3, Gadget = "ShockWire", Weapons = { "SMG", "Shotgun", "Autopistol" }, Color = rgb(230, 190, 40),
		Bio = "Electrifies reinforced walls: charges on them just fizzle." },
	{ Id = "Hush", Name = "Hush", Side = "Defend", Armor = 2, Speed = 2, Gadget = "SignalJammer", Weapons = { "SMG", "Shotgun", "Marksman" }, Color = rgb(80, 200, 120),
		Bio = "Jams breach charges and drones so attackers come in blind." },
	{ Id = "Bastion", Name = "Bastion", Side = "Defend", Armor = 3, Speed = 1, Gadget = "ArmorPanel", Weapons = { "Rifle", "Shotgun", "Gatling" }, Color = rgb(200, 120, 40),
		Bio = "Seals doorways with steel and holds them with whatever's heaviest." },
	{ Id = "Anvil", Name = "Anvil", Side = "Defend", Armor = 3, Speed = 1, Gadget = "DeployableCover", Weapons = { "LMG", "Rifle", "Sniper" }, Color = rgb(140, 150, 170),
		Bio = "Pulls a shield out of the floor and holds the long angle." },
	{ Id = "Bramble", Name = "Bramble", Side = "Defend", Armor = 2, Speed = 2, Gadget = "BarbedWire", Weapons = { "Shotgun", "LMG", "Revolver" }, Color = rgb(150, 160, 90),
		Bio = "Wires the doorways. You'll hear them stumble in." },
	{ Id = "Fuse", Name = "Fuse", Side = "Defend", Armor = 1, Speed = 3, Gadget = "ImpactGrenade", Weapons = { "Rifle", "Shotgun", "Revolver" }, Color = rgb(255, 120, 70),
		Bio = "Blows murder holes and rotations wherever the site needs them." },
} :: { Operator }

Operators.ById = {} :: { [string]: Operator }
for _, operator in Operators.List do
	Operators.ById[operator.Id] = operator
end

-- Everyone on `side`, in card order
function Operators.ForSide(side: string): { Operator }
	local list = {}
	for _, operator in Operators.List do
		if operator.Side == side then
			table.insert(list, operator)
		end
	end
	return list
end

-- The guns `operator` can take in this match's mode (Knives Only: just the knife)
function Operators.WeaponsFor(operator: Operator): { string }
	local allowed = GameRules.Current().Weapons
	if allowed and #allowed == 0 then
		return { GameRules.NoGun }
	end
	local list = {}
	for _, name in operator.Weapons do
		if Weapons[name] and (not allowed or table.find(allowed, name)) then
			table.insert(list, name)
		end
	end
	if #list == 0 and allowed then
		return table.clone(allowed) -- none of theirs in this mode: the mode's guns it is
	end
	return list
end

return Operators
