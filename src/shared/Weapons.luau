-- Weapon stats. Shared so the client (feel/effects) and server (validation/damage) agree.
-- Operators (shared/Operators) pick their guns from this list.
--
-- Damage rules (Siege; WeaponService applies them):
--   • A bullet to the head kills outright, from any gun at any range (HeadshotKills). Shotgun
--     pellets and the Gatling are the exceptions: each pellet / bullet does HeadshotDamage instead.
--   • Body shots do Damage, arms and legs 75% of it.
--   • Armor (the operator's 1 / 2 / 3 rating) takes body and limb damage down to ×1 / ×0.9 / ×0.8.
--   • Range: full Damage up to FalloffStart, then a straight line down to MinDamageScale of it at
--     FalloffEnd (and beyond). Studs here are short (the maps are about a third of Siege's size in
--     studs-per-metre), so "25 studs" plays like Siege's 20-odd metres.
-- Body shots to kill up close (100 health; 1-armor / 2-armor / 3-armor) and time to kill:
--   Rifle 3/3/4 (0.17 s / 0.26 s), SMG 4/4/5 (0.2 s), LMG 3/3/3 (0.2 s), Marksman 2/2/3,
--   Sniper 1/1/2, Revolver 2/2/3, Autopistol 5/5/6 (0.22 s), Shotgun one pump inside ~6 studs
--   (6 / 7 / 7 of 8 pellets), Gatling 7/8/9 (0.3 s once its barrels have spun up, 0.7 s first).
--
-- Recoil is a learnable pattern, not random kick (WeaponController.fire): the first shot of a
-- burst snaps up by RecoilFirstShot + RecoilUp, every shot after by RecoilUp, and sideways by
-- RecoilDrift (a steady lean) plus a slow left-right wave (RecoilSway, one full wave every
-- RecoilSwayPeriod shots). The sideways part starts gentle and grows to full over the first
-- RecoilRamp shots, so the opening shots of a spray go mostly straight up. RecoilJitter is the
-- random part on top (0.12 = ±12%), so it never feels robotic. Aimed in, all of it is ×AdsRecoil.
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
	Damage: number, -- body shot damage (per pellet for shotguns), before armor / range
	Pellets: number, -- bullets per shot (shotguns > 1)
	PelletSpread: number, -- degrees, shotgun pellet cone
	HeadshotKills: boolean, -- a bullet to the head kills outright (Siege)
	HeadshotDamage: number?, -- per pellet, only when HeadshotKills is false (shotgun pellets)
	FalloffStart: number, -- studs: full damage until here
	FalloffEnd: number, -- studs: minimum damage from here
	MinDamageScale: number, -- damage multiplier at FalloffEnd
	Range: number,
	MagazineSize: number,
	Chamber: number, -- 1: a tactical reload keeps a round in the chamber (30+1); 0: open bolt / revolver
	ReloadTime: number, -- tactical reload (rounds left in the mag): seconds
	EmptyReloadTime: number, -- empty mag: slower, the bolt / slide / pump has to be worked too

	HipSpread: number, -- degrees, standing still at the hip
	AdsSpread: number,
	HipBloom: number, -- extra hip spread degrees each shot adds (mostly gone aimed in)
	HipBloomMax: number, -- bloom can't grow past this
	MoveSpreadBonus: number, -- extra degrees at full sprint speed
	AirSpreadBonus: number, -- extra degrees while airborne or sliding
	CrouchSpreadScale: number, -- spread multiplier while crouched (lower = more accurate)
	AdsFovScale: number, -- FOV multiplier while aiming with the gun's own sights (optics change it)
	AdsTime: number, -- seconds to aim in
	Scope: boolean, -- full scope overlay when aimed in
	SprintOutTime: number, -- seconds after a sprint before the gun can fire (heavier = longer)

	-- Recoil: each gun's "personality" (see the top)
	RecoilFirstShot: number, -- extra degrees up on the first shot of a burst
	RecoilUp: number, -- degrees of camera climb per shot
	RecoilDrift: number, -- steady sideways degrees per shot (+ = right)
	RecoilSway: number, -- sideways wave on top of the drift: degrees per shot at its widest
	RecoilSwayPeriod: number, -- shots for one full left-right wave
	RecoilRamp: number, -- shots for the sideways recoil to grow to full
	RecoilJitter: number, -- random part on top (fraction)
	RecoilMax: number, -- recoil can't climb higher than this many degrees
	RecoilRecover: number, -- how fast recoil (and hip bloom) returns once you stop shooting
	RecoilRoll: number, -- degrees of camera jolt (visual only, doesn't move your aim)
	AdsRecoil: number, -- recoil multiplier when fully aimed in (hip fire = 1)
	ViewKick: number, -- how much the on-screen gun jolts per shot

	Sway: number, -- the gun drifting at the hip (visual; heavier guns more), 1 = normal
	Breath: number, -- degrees the aim drifts with your breathing when aimed in (tiny)

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
		RPM = 700,
		Damage = 40, -- 3 body shots on light / medium armor, 4 on heavy
		Pellets = 1,
		PelletSpread = 0,
		HeadshotKills = true,
		FalloffStart = 25,
		FalloffEnd = 40,
		MinDamageScale = 0.65, -- 26 at range: 4-5 shots
		Range = 500,
		MagazineSize = 30,
		Chamber = 1,
		ReloadTime = 2.2,
		EmptyReloadTime = 2.8, -- + slap the bolt release

		HipSpread = 1.2,
		AdsSpread = 0.08,
		HipBloom = 0.25,
		HipBloomMax = 2,
		MoveSpreadBonus = 1.2,
		AirSpreadBonus = 4,
		CrouchSpreadScale = 0.75,
		AdsFovScale = 0.84,
		AdsTime = 0.28,
		Scope = false,
		SprintOutTime = 0.25,

		-- A firm first shot, a steady climb, a slow wander right then left every ten shots
		RecoilFirstShot = 0.5,
		RecoilUp = 0.2,
		RecoilDrift = 0.03,
		RecoilSway = 0.12,
		RecoilSwayPeriod = 10,
		RecoilRamp = 6,
		RecoilJitter = 0.12,
		RecoilMax = 4.5,
		RecoilRecover = 9,
		RecoilRoll = 0.4,
		AdsRecoil = 0.8,
		ViewKick = 0.03,

		Sway = 1,
		Breath = 0.02,

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
		RPM = 880,
		Damage = 28, -- 4 body shots on light / medium armor, 5 on heavy
		Pellets = 1,
		PelletSpread = 0,
		HeadshotKills = true,
		FalloffStart = 18,
		FalloffEnd = 32,
		MinDamageScale = 0.6, -- 17 at range: 6-7 shots
		Range = 300,
		MagazineSize = 30,
		Chamber = 1,
		ReloadTime = 2,
		EmptyReloadTime = 2.6, -- + lock the cocking handle back and slap it

		HipSpread = 0.9, -- better hip fire than the rifle
		AdsSpread = 0.22,
		HipBloom = 0.15,
		HipBloomMax = 1.4,
		MoveSpreadBonus = 0.8,
		AirSpreadBonus = 3,
		CrouchSpreadScale = 0.75,
		AdsFovScale = 0.88,
		AdsTime = 0.22,
		Scope = false,
		SprintOutTime = 0.18,

		-- Low climb with a quick left-right shimmy (every six shots)
		RecoilFirstShot = 0.3,
		RecoilUp = 0.11,
		RecoilDrift = -0.01,
		RecoilSway = 0.14,
		RecoilSwayPeriod = 6,
		RecoilRamp = 8,
		RecoilJitter = 0.15,
		RecoilMax = 2.6,
		RecoilRecover = 13,
		RecoilRoll = 0.25,
		AdsRecoil = 0.8,
		ViewKick = 0.02,

		Sway = 0.7,
		Breath = 0.015,

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
		Damage = 18, -- per pellet: 6 / 7 / 7 of 8 kill (light / medium / heavy armor)
		Pellets = 8,
		PelletSpread = 4.2,
		HeadshotKills = false, -- (Siege: pellets don't one-shot to the head)
		HeadshotDamage = 30, -- per pellet
		FalloffStart = 6,
		FalloffEnd = 18,
		MinDamageScale = 0.2, -- steep: past ~18 studs it barely tickles
		Range = 120,
		MagazineSize = 6,
		Chamber = 1,
		ReloadTime = 2.6,
		EmptyReloadTime = 3.2, -- + rack the pump

		HipSpread = 0,
		AdsSpread = 0,
		HipBloom = 0,
		HipBloomMax = 0,
		MoveSpreadBonus = 0.5,
		AirSpreadBonus = 1,
		CrouchSpreadScale = 1,
		AdsFovScale = 0.9,
		AdsTime = 0.28,
		Scope = false,
		SprintOutTime = 0.25,

		-- One big punch per shot, kicking left and right in turn
		RecoilFirstShot = 0.4,
		RecoilUp = 2.8,
		RecoilDrift = 0.15,
		RecoilSway = 0.4,
		RecoilSwayPeriod = 2,
		RecoilRamp = 1,
		RecoilJitter = 0.15,
		RecoilMax = 6,
		RecoilRecover = 7,
		RecoilRoll = 3,
		AdsRecoil = 0.85,
		ViewKick = 0.2,

		Sway = 1.1,
		Breath = 0.02,

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
		Description = "Scoped. One body shot kills unless they're heavily armored.",
		Automatic = false,
		RPM = 50,
		Damage = 120, -- one body shot on light / medium armor (96 on heavy: two)
		Pellets = 1,
		PelletSpread = 0,
		HeadshotKills = true,
		FalloffStart = 1000, -- no drop-off
		FalloffEnd = 1001,
		MinDamageScale = 1,
		Range = 1000,
		MagazineSize = 5,
		Chamber = 1,
		ReloadTime = 2.8,
		EmptyReloadTime = 3.4,

		HipSpread = 5,
		AdsSpread = 0,
		HipBloom = 0,
		HipBloomMax = 0,
		MoveSpreadBonus = 3,
		AirSpreadBonus = 6,
		CrouchSpreadScale = 0.7,
		AdsFovScale = 0.3,
		AdsTime = 0.5,
		Scope = true,
		SprintOutTime = 0.38,

		-- Huge kick, slow to settle
		RecoilFirstShot = 1,
		RecoilUp = 4.2,
		RecoilDrift = 0.2,
		RecoilSway = 0.3,
		RecoilSwayPeriod = 2,
		RecoilRamp = 1,
		RecoilJitter = 0.15,
		RecoilMax = 8,
		RecoilRecover = 4,
		RecoilRoll = 2,
		AdsRecoil = 0.85,
		ViewKick = 0.25,

		Sway = 1.6,
		Breath = 0.06, -- you see it through the scope: hold steady between breaths

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
		Damage = 56, -- 2 body shots on light / medium armor, 3 on heavy
		Pellets = 1,
		PelletSpread = 0,
		HeadshotKills = true,
		FalloffStart = 18,
		FalloffEnd = 36,
		MinDamageScale = 0.6,
		Range = 400,
		MagazineSize = 6,
		Chamber = 0, -- (a cylinder: nothing to keep in a chamber)
		ReloadTime = 2.4,
		EmptyReloadTime = 2.4, -- every reload dumps the whole cylinder anyway

		HipSpread = 0.9,
		AdsSpread = 0.1,
		HipBloom = 0.5,
		HipBloomMax = 2,
		MoveSpreadBonus = 1,
		AirSpreadBonus = 3,
		CrouchSpreadScale = 0.75,
		AdsFovScale = 0.86,
		AdsTime = 0.22,
		Scope = false,
		SprintOutTime = 0.15,

		-- Sharp snap up and to the right
		RecoilFirstShot = 0.6,
		RecoilUp = 2,
		RecoilDrift = 0.2,
		RecoilSway = 0.15,
		RecoilSwayPeriod = 3,
		RecoilRamp = 2,
		RecoilJitter = 0.12,
		RecoilMax = 5,
		RecoilRecover = 10,
		RecoilRoll = 2.5,
		AdsRecoil = 0.8,
		ViewKick = 0.15,

		Sway = 0.8,
		Breath = 0.02,

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
		Damage = 44, -- 3 body shots on any armor
		Pellets = 1,
		PelletSpread = 0,
		HeadshotKills = true,
		FalloffStart = 28,
		FalloffEnd = 45,
		MinDamageScale = 0.7,
		Range = 500,
		MagazineSize = 75,
		Chamber = 0, -- (open bolt)
		ReloadTime = 4.2,
		EmptyReloadTime = 4.8, -- + work the charging handle

		HipSpread = 2.2,
		AdsSpread = 0.22,
		HipBloom = 0.3,
		HipBloomMax = 3,
		MoveSpreadBonus = 2,
		AirSpreadBonus = 5,
		CrouchSpreadScale = 0.6, -- settle in and it's accurate
		AdsFovScale = 0.84,
		AdsTime = 0.42,
		Scope = false,
		SprintOutTime = 0.35,

		-- A heavy climb that goes straight up at first, then wanders right the longer you hold it
		RecoilFirstShot = 0.7,
		RecoilUp = 0.21,
		RecoilDrift = 0.06,
		RecoilSway = 0.1,
		RecoilSwayPeriod = 14,
		RecoilRamp = 10,
		RecoilJitter = 0.12,
		RecoilMax = 5,
		RecoilRecover = 8,
		RecoilRoll = 0.5,
		AdsRecoil = 0.8,
		ViewKick = 0.04,

		Sway = 1.5,
		Breath = 0.03,

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
		Description = "Semi-auto with a scope. 2 body shots on all but heavy armor.",
		Automatic = false,
		RPM = 300,
		Damage = 62, -- 2 body shots on light / medium armor, 3 on heavy
		Pellets = 1,
		PelletSpread = 0,
		HeadshotKills = true,
		FalloffStart = 45,
		FalloffEnd = 80,
		MinDamageScale = 0.85, -- barely drops
		Range = 800,
		MagazineSize = 15,
		Chamber = 1,
		ReloadTime = 2.4,
		EmptyReloadTime = 3, -- + slap the bolt release

		HipSpread = 2.5,
		AdsSpread = 0.03,
		HipBloom = 0.6,
		HipBloomMax = 3,
		MoveSpreadBonus = 2,
		AirSpreadBonus = 5,
		CrouchSpreadScale = 0.7,
		AdsFovScale = 0.55, -- through the prism scope, not a full-screen one
		AdsTime = 0.34,
		Scope = false,
		SprintOutTime = 0.3,

		-- A firm kick per shot that settles quickly, nudging right
		RecoilFirstShot = 0.3,
		RecoilUp = 1.1,
		RecoilDrift = 0.08,
		RecoilSway = 0.12,
		RecoilSwayPeriod = 4,
		RecoilRamp = 3,
		RecoilJitter = 0.12,
		RecoilMax = 5,
		RecoilRecover = 9,
		RecoilRoll = 1,
		AdsRecoil = 0.85,
		ViewKick = 0.08,

		Sway = 1.2,
		Breath = 0.035,

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
		Damage = 23, -- 5 body shots on light / medium armor, 6 on heavy
		Pellets = 1,
		PelletSpread = 0,
		HeadshotKills = true,
		FalloffStart = 14,
		FalloffEnd = 28,
		MinDamageScale = 0.55,
		Range = 250,
		MagazineSize = 20,
		Chamber = 1,
		ReloadTime = 1.6,
		EmptyReloadTime = 2.1, -- + rack the slide

		HipSpread = 0.9,
		AdsSpread = 0.45,
		HipBloom = 0.12,
		HipBloomMax = 1.5,
		MoveSpreadBonus = 0.5,
		AirSpreadBonus = 2,
		CrouchSpreadScale = 0.8,
		AdsFovScale = 0.9,
		AdsTime = 0.16,
		Scope = false,
		SprintOutTime = 0.12,

		-- Light climb, lots of buzz side to side
		RecoilFirstShot = 0.25,
		RecoilUp = 0.15,
		RecoilDrift = 0.04,
		RecoilSway = 0.2,
		RecoilSwayPeriod = 4,
		RecoilRamp = 4,
		RecoilJitter = 0.2,
		RecoilMax = 3.2,
		RecoilRecover = 15,
		RecoilRoll = 0.6,
		AdsRecoil = 0.85,
		ViewKick = 0.05,

		Sway = 0.6,
		Breath = 0.015,

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
		Damage = 15, -- 7 / 8 / 9 body shots, about a third of a second of fire...
		Pellets = 1,
		PelletSpread = 0,
		HeadshotKills = false, -- (like shotgun pellets: no one-shot to the head, it fires too fast)
		HeadshotDamage = 30, -- per bullet to the head: 4 head hits kill
		FalloffStart = 22,
		FalloffEnd = 40,
		MinDamageScale = 0.6,
		Range = 400,
		MagazineSize = 150,
		Chamber = 0, -- (motor-driven: nothing to chamber)
		ReloadTime = 5.5,
		EmptyReloadTime = 5.5,

		HipSpread = 2.6, -- ...but it sprays, and you can't aim it fine
		AdsSpread = 1.1,
		HipBloom = 0.05,
		HipBloomMax = 1,
		MoveSpreadBonus = 2.5,
		AirSpreadBonus = 6,
		CrouchSpreadScale = 0.6, -- brace it and it tightens up
		AdsFovScale = 0.88,
		AdsTime = 0.6,
		Scope = false,
		SprintOutTime = 0.45,

		-- A constant shake rather than a climb (mostly jitter)
		RecoilFirstShot = 0,
		RecoilUp = 0.05,
		RecoilDrift = 0.02,
		RecoilSway = 0.1,
		RecoilSwayPeriod = 3,
		RecoilRamp = 1,
		RecoilJitter = 0.6,
		RecoilMax = 2.5,
		RecoilRecover = 8,
		RecoilRoll = 0.15,
		AdsRecoil = 0.85,
		ViewKick = 0.012,

		Sway = 1.8,
		Breath = 0.03,

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
