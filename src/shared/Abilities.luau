-- Abilities that can show up in loadouts (every ability here is in the draft/random pool).
--   Movement abilities live in MovementController (Dash on X, Wall Jump on Space).
--   Active abilities are used with X, run on the server (AbilityService / GadgetService), and
--   have charges per round.
--   Side: what an ability is for decides who can roll it: attacking tools ("Attack": breaching,
--   grenades, finding enemies) only go to attackers, holding tools ("Defend": fortifying, roaming
--   quietly, holding an angle) only to defenders. Only plain movement (no Side) goes to either.

export type Ability = {
	Name: string,
	Key: string,
	Description: string,
	Kind: "Movement" | "Active",
	Side: ("Attack" | "Defend")?,
	Charges: number?, -- uses per round (active abilities)
	Detonates: boolean?, -- X again sets off what you placed (free, even with no charges left)
	Duration: number?, -- seconds the effect lasts
	Radius: number?, -- studs
}

local Abilities: { [string]: Ability } = {
	Dash = {
		Name = "Dash",
		Key = "X",
		Kind = "Movement",
		Description = "Burst in the direction you're moving. Works once in the air.",
	},
	WallJump = {
		Name = "Wall Jump",
		Key = "Space",
		Kind = "Movement",
		Description = "Jump off walls while in the air. Bounce between two walls to climb.",
	},
	ReconPulse = {
		Name = "Recon Pulse",
		Key = "X",
		Kind = "Active",
		Side = "Attack", -- finding the defenders
		Charges = 2,
		Duration = 3,
		Radius = 60,
		Description = "Reveal nearby enemies through walls to your team. They know they've been scanned.",
	},
	GhostStep = {
		Name = "Ghost Step",
		Key = "X",
		Kind = "Active",
		Side = "Defend", -- roaming without being heard
		Charges = 2,
		Duration = 8,
		Description = "Your footsteps, jumps and landings are silent for 8 seconds.",
	},
	DeployableCover = {
		Name = "Deployable Cover",
		Key = "X",
		Kind = "Active",
		Side = "Defend", -- holding an angle
		Charges = 2,
		Duration = 1.2, -- deploy time: you can't move or shoot while pulling it up
		Description = "Pull a waist-high bulletproof shield out of the ground. Crouch behind it or shoot over it.",
	},

	-- Siege gadgets (GadgetService). Counters: jammer beats breach charges, shock wire beats hard
	-- breaches, EMP beats both, explosives beat armor panels.
	BreachCharge = {
		Name = "Breach Charge",
		Key = "X",
		Kind = "Active",
		Side = "Attack",
		Charges = 2,
		Detonates = true,
		Radius = 10, -- blast
		Description = "Stick it on a soft wall, barricade or armor panel, then X again to blow a hole you can walk through. Hurts anyone on the other side.",
	},
	HardBreach = {
		Name = "Hard Breach",
		Key = "X",
		Kind = "Active",
		Side = "Attack",
		Charges = 2,
		Duration = 3, -- burn time
		Description = "Thermite charge that burns through a REINFORCED wall in 3 seconds. A shock wire fries it.",
	},
	EmpGrenade = {
		Name = "EMP Grenade",
		Key = "X",
		Kind = "Active",
		Side = "Attack",
		Charges = 2,
		Radius = 14,
		Description = "Throw it to fry enemy electronics nearby, even through walls: shock wires, signal jammers and cameras.",
	},
	SmokeGrenade = {
		Name = "Smoke Grenade",
		Key = "X",
		Kind = "Active",
		Side = "Attack",
		Charges = 2,
		Duration = 14, -- how long it pours out smoke
		Radius = 11, -- of the cloud
		Description = "Throw it to fill the area with thick smoke for 14 seconds. Nobody can see through it: cover a plant or a push.",
	},
	Flashbang = {
		Name = "Flashbang",
		Key = "X",
		Kind = "Active",
		Side = "Attack",
		Charges = 2,
		Duration = 4, -- longest blinding (close by, looking right at it)
		Radius = 20,
		Description = "Bounces, then goes off after 1.5 seconds: anyone who can see it is blinded and deafened for up to 4 seconds. Teammates (and you) too.",
	},
	ShockWire = {
		Name = "Shock Wire",
		Key = "X",
		Kind = "Active",
		Side = "Defend",
		Charges = 2,
		Description = "Electrify a reinforced wall: any charge put on it gets fried. Beaten by an EMP.",
	},
	SignalJammer = {
		Name = "Signal Jammer",
		Key = "X",
		Kind = "Active",
		Side = "Defend",
		Charges = 2,
		Radius = 10,
		Description = "Drop it near a wall: breach charges close to it can't be set off and drones lose their signal. Can be shot or EMP'd.",
	},
	ArmorPanel = {
		Name = "Armor Panel",
		Key = "X",
		Kind = "Active",
		Side = "Defend",
		Charges = 2,
		Description = "Bulletproof barricade for a doorway or window. Takes 10 knife hits or an explosive to break.",
	},
}

return Abilities
