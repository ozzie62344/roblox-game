-- Abilities (gadgets). Each operator (Operators.luau) brings one of these as their gadget; the dev
-- panel can hand out any of them.
--   Abilities are used with X, run on the server (AbilityService / GadgetService), and have
--   charges per round. (There are no movement abilities: everyone moves the same, Siege-style,
--   only faster or slower by their operator's Speed rating. The old Dash / Wall Jump are gone;
--   an "Ability" attribute naming one just finds nothing here, like no ability.)
--   Side: what an ability is for: attacking tools ("Attack": breaching, grenades, finding
--   enemies) belong to attackers, holding tools ("Defend": fortifying, roaming quietly, holding an
--   angle) to defenders.

export type Ability = {
	Name: string,
	Key: string,
	Description: string,
	Kind: "Active",
	Side: ("Attack" | "Defend")?,
	Charges: number?, -- uses per round (active abilities)
	Detonates: boolean?, -- X again sets off what you placed (free, even with no charges left)
	Duration: number?, -- seconds the effect lasts
	Radius: number?, -- studs
}

local Abilities: { [string]: Ability } = {
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
		Description = "Your footsteps, vaults and landings are silent for 8 seconds.",
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

	-- Operator gadgets (GadgetService)
	HeartbeatSensor = {
		Name = "Heartbeat Sensor",
		Key = "X",
		Kind = "Active",
		Side = "Attack", -- finding the defenders, but only for yourself
		Charges = 2,
		Detonates = true, -- X again puts the sensor away early (free)
		Duration = 7, -- seconds of scanning: gun put away the whole time
		Radius = 32,
		Description = "Put your gun away and scan for 7 seconds: heartbeats within 32 studs pulse through walls and floors, for you only. They feel it.",
	},
	BarbedWire = {
		Name = "Barbed Wire",
		Key = "X",
		Kind = "Active",
		Side = "Defend",
		Charges = 2,
		Description = "Roll out a coil of wire on the floor. Anyone crossing it slows to a crawl and rattles it. Shoot or knife a stake to clear it.",
	},
	ImpactGrenade = {
		Name = "Impact Grenade",
		Key = "X",
		Kind = "Active",
		Side = "Defend",
		Charges = 3,
		Radius = 6, -- blast
		Description = "Goes off the moment it hits something: punches a hole in a soft wall or floor (murder holes, rotations) and hurts anyone close.",
	},

	-- Secondary gadgets (Siege's): every operator also brings one of these, picked from their
	-- Operators.Secondaries in operator select, and uses it with B (SecondaryKey). The Breach
	-- Charge above is one of the attackers' too.
	FragGrenade = {
		Name = "Frag Grenade",
		Key = "B",
		Kind = "Active",
		Side = "Attack",
		Charges = 2,
		Duration = 3, -- fuse
		Radius = 18, -- deadly within about a third of this, hurts out to all of it
		Description = "Bounces, then goes off after 3 seconds. Deadly up close, hurts further out, and breaks barricades and gadgets. Soft walls don't stop it.",
	},
	Claymore = {
		Name = "Claymore",
		Key = "B",
		Kind = "Active",
		Side = "Attack",
		Charges = 1,
		Radius = 10, -- blast, in front of it
		Description = "Set it on the floor facing where they'll come from. An enemy crossing its laser sets it off a moment later. Shoot it to clear it.",
	},
	NitroCell = {
		Name = "Nitro Cell",
		Key = "B",
		Kind = "Active",
		Side = "Defend",
		Charges = 1,
		Detonates = true, -- B again sets it off
		Radius = 12,
		Description = "Throw it to stick it anywhere, then B again to set it off. Kills through soft walls and floors.",
	},
	BulletproofCamera = {
		Name = "Bulletproof Camera",
		Key = "B",
		Kind = "Active",
		Side = "Defend",
		Charges = 1,
		Description = "Stick a camera on a wall: bullets bounce off it, a knife or an explosive breaks it, an EMP fries it. Watch it with your team's cameras (Z).",
	},
	ProximityAlarm = {
		Name = "Proximity Alarm",
		Key = "B",
		Kind = "Active",
		Side = "Defend",
		Charges = 2,
		Radius = 12,
		Description = "Stick it on a wall or floor. An enemy who comes close sets off a loud alarm and is shown to your team while they're near it.",
	},
}

return Abilities
