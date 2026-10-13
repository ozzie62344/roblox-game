-- Weapon stats. Shared so the client (feel/effects) and server (validation/damage) agree.
-- Operators (shared/Operators) pick their guns from this list.
--
-- Balance (100 health, Siege rule: a headshot kills with anything but shotgun pellets). Body
-- shots to kill up close / time to kill: SMG 5 / 0.27 s, Rifle 4 / 0.28 s, LMG 4 / 0.30 s,
-- Autopistol 7 / 0.33 s, Marksman 3 / 0.40 s, Revolver 2 / 0.46 s, Sniper 2 / 1.2 s, Shotgun
-- one shot inside ~8 studs, Gatling 8 / 0.3 s once its barrels have spun up (0.7 s first).
-- The gatling pays for that: you carry it at 60% speed (about 40% while it's spinning), it sprays,
-- and its headshots don't kill outright (a stray one out of 23 bullets a second would be a free
-- kill). Range is the trade-off: SMG / Autopistol / Shotgun fall off fast,
-- Rifle / LMG hold up to mid range, Marksman / Sniper barely fall off at all.
--
-- Sounds: FireSound / TailSound / ReloadSound name a set in Sounds.luau (Sets); a random one from the set plays.

-- First-person looks: client/Combat/GunModels builds each weapon's detailed model by name.
-- Color is its main finish (receiver, wood, stock or stainless steel depending on the gun).
export type Look = {
	Color: Color3,
}

export type Weapon = {
	Name: string,
	Description: string,
	Automatic: boolean,
	RPM: number, -- rounds per minute
	Damage: number, -- body shot damage (per pellet for shotguns)
	Pellets: number, -- bullets per shot (shotguns > 1)
	PelletSpread: number, -- degrees, shotgun pellet cone
	HeadshotDamage: number, -- damage of a headshot (per pellet for shotguns), before range falloff
	FalloffStart: number, -- studs: full damage until here
	FalloffEnd: number, -- studs: minimum damage from here
	MinDamageScale: number, -- damage multiplier at FalloffEnd
	Range: number,
	MagazineSize: number,
	ReloadTime: number,

	HipSpread: number, -- degrees
	AdsSpread: number,
	MoveSpreadBonus: number, -- extra degrees at full sprint speed
	AirSpreadBonus: number, -- extra degrees while airborne or sliding
	CrouchSpreadScale: number, -- spread multiplier while crouched (lower = more accurate)
	AdsFovScale: number, -- FOV multiplier while aiming
	AdsTime: number, -- seconds to aim in
	Scope: boolean, -- full scope overlay when aimed in

	-- Recoil: each gun's "personality"
	RecoilUp: number, -- degrees of camera kick per shot
	RecoilSide: number, -- max random sideways degrees per shot (jitter)
	RecoilDrift: number, -- consistent sideways degrees per shot (+ = right), the pattern you learn to pull against
	RecoilMax: number, -- recoil can't climb higher than this many degrees
	RecoilRecover: number, -- how fast recoil returns to center after you stop shooting
	RecoilRoll: number, -- degrees of camera jolt (visual only, doesn't move your aim)
	ViewKick: number, -- how much the on-screen gun jolts per shot

	AdsSensitivity: number, -- mouse sensitivity multiplier when fully aimed in (lower = slower)

	Look: Look,
	FireSound: string, -- sound set (Sounds.Sets) for each shot
	TailSound: string?, -- optional echo after each shot (semi-auto guns)
	ReloadSound: string, -- sound set for reloads (plays at the start and near the end)
	FirePitch: number, -- lower = deeper, heavier gun
	FireVolume: number,

	SpinUp: number?, -- seconds the barrels take to spin up before it fires (the gatling)
	SpinSlow: number?, -- with the barrels spinning you're this much slower again (0..1)
	MoveSpeedScale: number?, -- heavy guns slow you down (walking and sprinting), 1 = not at all
}

local DARK = Color3.fromRGB(45, 47, 52)

local Weapons: { [string]: Weapon } = {
	Rifle = {
		Name = "Rifle",
		Description = "Reliable all-rounder.",
		Automatic = true,
		RPM = 650,
		Damage = 25, -- body shots: 4 to kill
		Pellets = 1,
		PelletSpread = 0,
		HeadshotDamage = 102, -- headshots are lethal, Siege-style
		FalloffStart = 50,
		FalloffEnd = 130,
		MinDamageScale = 0.7,
		Range = 500,
		MagazineSize = 30,
		ReloadTime = 2.2,

		HipSpread = 1.4,
		AdsSpread = 0.1,
		MoveSpreadBonus = 1.2,
		AirSpreadBonus = 4,
		CrouchSpreadScale = 0.75,
		AdsFovScale = 0.75,
		AdsTime = 0.27,
		Scope = false,

		-- Steady climb that drifts right
		RecoilUp = 0.25,
		RecoilSide = 0.06,
		RecoilDrift = 0.06,
		RecoilMax = 3.5,
		RecoilRecover = 10,
		RecoilRoll = 0.4,
		ViewKick = 0.03,

		AdsSensitivity = 0.7,

		Look = {
			Color = DARK, -- anodized receiver
		},
		FireSound = "GunShot",
		FirePitch = 1,
		FireVolume = 1,
		ReloadSound = "GunFoley",
	},

	SMG = {
		Name = "SMG",
		Description = "Shreds up close, weak at range.",
		Automatic = true,
		RPM = 900,
		Damage = 20, -- 5 to kill: a hair faster than the rifle up close
		Pellets = 1,
		PelletSpread = 0,
		HeadshotDamage = 102,
		FalloffStart = 20,
		FalloffEnd = 55,
		MinDamageScale = 0.5,
		Range = 300,
		MagazineSize = 32,
		ReloadTime = 1.8,

		HipSpread = 1.0, -- better hip fire than the rifle
		AdsSpread = 0.35,
		MoveSpreadBonus = 0.8,
		AirSpreadBonus = 3,
		CrouchSpreadScale = 0.75,
		AdsFovScale = 0.85,
		AdsTime = 0.22,
		Scope = false,

		-- Low climb, jittery side to side
		RecoilUp = 0.12,
		RecoilSide = 0.22,
		RecoilDrift = -0.02,
		RecoilMax = 2.2,
		RecoilRecover = 14,
		RecoilRoll = 0.25,
		ViewKick = 0.02,

		AdsSensitivity = 0.8,

		Look = {
			Color = Color3.fromRGB(35, 36, 40), -- stamped steel receiver
		},
		FireSound = "GunShot",
		FirePitch = 1.2, -- lighter, snappier
		FireVolume = 0.8,
		ReloadSound = "GunFoley",
	},

	Shotgun = {
		Name = "Shotgun",
		Description = "8 pellets. One-shots up close.",
		Automatic = false,
		RPM = 75,
		Damage = 15, -- per pellet: 7 of 8 kill
		Pellets = 8,
		PelletSpread = 4.2,
		HeadshotDamage = 28, -- per pellet
		FalloffStart = 8,
		FalloffEnd = 28,
		MinDamageScale = 0.25,
		Range = 120,
		MagazineSize = 6,
		ReloadTime = 2.6,

		HipSpread = 0,
		AdsSpread = 0,
		MoveSpreadBonus = 0.5,
		AirSpreadBonus = 1,
		CrouchSpreadScale = 1,
		AdsFovScale = 0.9,
		AdsTime = 0.25,
		Scope = false,

		-- One big punch per shot
		RecoilUp = 3.2,
		RecoilSide = 0.8,
		RecoilDrift = 0,
		RecoilMax = 6,
		RecoilRecover = 7,
		RecoilRoll = 3,
		ViewKick = 0.2,

		AdsSensitivity = 0.85,

		Look = {
			Color = Color3.fromRGB(70, 52, 38), -- walnut stock and pump
		},
		FireSound = "ShotgunShot",
		TailSound = "ShotgunTail",
		FirePitch = 1,
		FireVolume = 1.1,
		ReloadSound = "ShotgunFoley",
	},

	Sniper = {
		Name = "Sniper",
		Description = "Scoped. Headshots kill at any range.",
		Automatic = false,
		RPM = 50,
		Damage = 80, -- two body shots (one if they're already hurt)
		Pellets = 1,
		PelletSpread = 0,
		HeadshotDamage = 285,
		FalloffStart = 1000,
		FalloffEnd = 1001,
		MinDamageScale = 1,
		Range = 1000,
		MagazineSize = 5,
		ReloadTime = 3,

		HipSpread = 5,
		AdsSpread = 0,
		MoveSpreadBonus = 3,
		AirSpreadBonus = 6,
		CrouchSpreadScale = 0.7,
		AdsFovScale = 0.3,
		AdsTime = 0.5,
		Scope = true,

		-- Huge kick, slow to settle
		RecoilUp = 5,
		RecoilSide = 0.3,
		RecoilDrift = 0,
		RecoilMax = 8,
		RecoilRecover = 4,
		RecoilRoll = 2,
		ViewKick = 0.25,

		AdsSensitivity = 0.15, -- slow, precise aiming while scoped

		Look = {
			Color = Color3.fromRGB(55, 62, 48), -- olive drab stock
		},
		FireSound = "GunShot",
		TailSound = "GunTail",
		FirePitch = 0.7, -- deep and heavy
		FireVolume = 1.2,
		ReloadSound = "GunFoley",
	},

	Revolver = {
		Name = "Revolver",
		Description = "Two body shots up close. 6 rounds.",
		Automatic = false,
		RPM = 130,
		Damage = 50,
		Pellets = 1,
		PelletSpread = 0,
		HeadshotDamage = 120,
		FalloffStart = 30,
		FalloffEnd = 80,
		MinDamageScale = 0.6,
		Range = 400,
		MagazineSize = 6,
		ReloadTime = 2.4,

		HipSpread = 0.9,
		AdsSpread = 0.1,
		MoveSpreadBonus = 1,
		AirSpreadBonus = 3,
		CrouchSpreadScale = 0.75,
		AdsFovScale = 0.8,
		AdsTime = 0.24,
		Scope = false,

		-- Sharp snap up and to the right
		RecoilUp = 2.4,
		RecoilSide = 0.3,
		RecoilDrift = 0.25,
		RecoilMax = 5,
		RecoilRecover = 10,
		RecoilRoll = 2.5,
		ViewKick = 0.15,

		AdsSensitivity = 0.75,

		Look = {
			Color = Color3.fromRGB(150, 150, 158), -- stainless steel
		},
		FireSound = "GunShot",
		TailSound = "GunTail",
		FirePitch = 0.85,
		FireVolume = 1.1,
		ReloadSound = "GunFoley",
	},

	LMG = {
		Name = "LMG",
		Description = "75-round belt. Slow to aim and reload.",
		Automatic = true,
		RPM = 600,
		Damage = 25,
		Pellets = 1,
		PelletSpread = 0,
		HeadshotDamage = 102,
		FalloffStart = 60,
		FalloffEnd = 160,
		MinDamageScale = 0.75,
		Range = 500,
		MagazineSize = 75,
		ReloadTime = 4.2,

		HipSpread = 2.2,
		AdsSpread = 0.25,
		MoveSpreadBonus = 2,
		AirSpreadBonus = 5,
		CrouchSpreadScale = 0.6, -- settle in and it's accurate
		AdsFovScale = 0.75,
		AdsTime = 0.42,
		Scope = false,

		-- Slow, heavy climb that wanders right the longer you hold it
		RecoilUp = 0.2,
		RecoilSide = 0.1,
		RecoilDrift = 0.08,
		RecoilMax = 4,
		RecoilRecover = 8,
		RecoilRoll = 0.5,
		ViewKick = 0.04,

		AdsSensitivity = 0.65,

		Look = {
			Color = Color3.fromRGB(58, 62, 50), -- olive polymer furniture and ammo box
		},
		FireSound = "GunShot",
		FirePitch = 0.85,
		FireVolume = 1.15,
		ReloadSound = "GunFoley",
	},

	Marksman = {
		Name = "Marksman",
		Description = "Semi-auto with a 4x scope. 3 body shots at any range.",
		Automatic = false,
		RPM = 300,
		Damage = 45,
		Pellets = 1,
		PelletSpread = 0,
		HeadshotDamage = 102,
		FalloffStart = 120,
		FalloffEnd = 260,
		MinDamageScale = 0.85,
		Range = 800,
		MagazineSize = 15,
		ReloadTime = 2.6,

		HipSpread = 2.5,
		AdsSpread = 0.03,
		MoveSpreadBonus = 2,
		AirSpreadBonus = 5,
		CrouchSpreadScale = 0.7,
		AdsFovScale = 0.55, -- through the prism scope, not a full-screen one
		AdsTime = 0.34,
		Scope = false,

		-- A firm kick per shot that settles quickly
		RecoilUp = 1.2,
		RecoilSide = 0.15,
		RecoilDrift = 0.1,
		RecoilMax = 4,
		RecoilRecover = 9,
		RecoilRoll = 1,
		ViewKick = 0.08,

		AdsSensitivity = 0.5,

		Look = {
			Color = Color3.fromRGB(150, 128, 96), -- tan stock and grip
		},
		FireSound = "GunShot",
		TailSound = "GunTail",
		FirePitch = 0.9,
		FireVolume = 1.15,
		ReloadSound = "GunFoley",
	},

	Autopistol = {
		Name = "Autopistol",
		Description = "Full-auto pistol. Fastest to aim and reload.",
		Automatic = true,
		RPM = 1100,
		Damage = 15,
		Pellets = 1,
		PelletSpread = 0,
		HeadshotDamage = 102,
		FalloffStart = 12,
		FalloffEnd = 40,
		MinDamageScale = 0.5,
		Range = 250,
		MagazineSize = 20,
		ReloadTime = 1.5,

		HipSpread = 0.9,
		AdsSpread = 0.5,
		MoveSpreadBonus = 0.5,
		AirSpreadBonus = 2,
		CrouchSpreadScale = 0.8,
		AdsFovScale = 0.88,
		AdsTime = 0.16,
		Scope = false,

		-- Light climb, lots of buzz side to side
		RecoilUp = 0.16,
		RecoilSide = 0.3,
		RecoilDrift = 0.04,
		RecoilMax = 3,
		RecoilRecover = 15,
		RecoilRoll = 0.6,
		ViewKick = 0.05,

		AdsSensitivity = 0.85,

		Look = {
			Color = Color3.fromRGB(38, 38, 42), -- black polymer frame
		},
		FireSound = "GunShot",
		FirePitch = 1.35, -- small and snappy
		FireVolume = 0.7,
		ReloadSound = "GunFoley",
	},

	Gatling = {
		Name = "Gatling",
		Description = "Six spinning barrels. Spins up, then shreds. Very heavy.",
		Automatic = true,
		RPM = 1400,
		Damage = 14, -- 8 to kill, a third of a second of fire...
		Pellets = 1,
		PelletSpread = 0,
		HeadshotDamage = 35, -- (not a one-shot: see the top)
		FalloffStart = 30,
		FalloffEnd = 90,
		MinDamageScale = 0.55,
		Range = 400,
		MagazineSize = 150,
		ReloadTime = 5.5,

		HipSpread = 2.6, -- ...but it sprays, and you can't aim it fine
		AdsSpread = 1.1,
		MoveSpreadBonus = 2.5,
		AirSpreadBonus = 6,
		CrouchSpreadScale = 0.6, -- brace it and it tightens up
		AdsFovScale = 0.85,
		AdsTime = 0.6,
		Scope = false,

		-- A constant shake rather than a climb
		RecoilUp = 0.06,
		RecoilSide = 0.12,
		RecoilDrift = 0.02,
		RecoilMax = 2.5,
		RecoilRecover = 8,
		RecoilRoll = 0.15,
		ViewKick = 0.012,

		AdsSensitivity = 0.7,

		Look = {
			Color = Color3.fromRGB(62, 64, 68), -- gunmetal housing
		},
		FireSound = "GunShot",
		FirePitch = 1.15,
		FireVolume = 0.7,
		ReloadSound = "GunFoley",

		SpinUp = 0.7,
		SpinSlow = 0.35,
		MoveSpeedScale = 0.6,
	},
}

return Weapons
