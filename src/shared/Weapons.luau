-- Weapon stats. Shared so the client (feel/effects) and server (validation/damage) agree.
-- The loadout system picks from every weapon in this list.
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
	Damage: number, -- per pellet for shotguns
	Pellets: number, -- bullets per shot (shotguns > 1)
	PelletSpread: number, -- degrees, shotgun pellet cone
	HeadshotMultiplier: number,
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
}

local DARK = Color3.fromRGB(45, 47, 52)

local Weapons: { [string]: Weapon } = {
	Rifle = {
		Name = "Rifle",
		Description = "Reliable all-rounder.",
		Automatic = true,
		RPM = 720,
		Damage = 34,
		Pellets = 1,
		PelletSpread = 0,
		HeadshotMultiplier = 3, -- headshots are lethal, Siege-style
		FalloffStart = 60,
		FalloffEnd = 150,
		MinDamageScale = 0.7,
		Range = 500,
		MagazineSize = 30,
		ReloadTime = 2.2,

		HipSpread = 1.2,
		AdsSpread = 0.1,
		MoveSpreadBonus = 1.2,
		AirSpreadBonus = 4,
		CrouchSpreadScale = 0.75,
		AdsFovScale = 0.75,
		AdsTime = 0.18,
		Scope = false,

		-- Steady climb that drifts right
		RecoilUp = 0.22,
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
		Damage = 22,
		Pellets = 1,
		PelletSpread = 0,
		HeadshotMultiplier = 2.5,
		FalloffStart = 25,
		FalloffEnd = 70,
		MinDamageScale = 0.6,
		Range = 300,
		MagazineSize = 32,
		ReloadTime = 1.8,

		HipSpread = 1.6,
		AdsSpread = 0.35,
		MoveSpreadBonus = 0.8,
		AirSpreadBonus = 3,
		CrouchSpreadScale = 0.75,
		AdsFovScale = 0.85,
		AdsTime = 0.14,
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
		RPM = 70,
		Damage = 14,
		Pellets = 8,
		PelletSpread = 4.5,
		HeadshotMultiplier = 1.5,
		FalloffStart = 10,
		FalloffEnd = 35,
		MinDamageScale = 0.3,
		Range = 120,
		MagazineSize = 6,
		ReloadTime = 2.6,

		HipSpread = 0,
		AdsSpread = 0,
		MoveSpreadBonus = 0.5,
		AirSpreadBonus = 1,
		CrouchSpreadScale = 1,
		AdsFovScale = 0.9,
		AdsTime = 0.16,
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
		RPM = 45,
		Damage = 95,
		Pellets = 1,
		PelletSpread = 0,
		HeadshotMultiplier = 3,
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
		AdsTime = 0.32,
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
		Description = "Hard-hitting, accurate, 6 shots.",
		Automatic = false,
		RPM = 160,
		Damage = 48,
		Pellets = 1,
		PelletSpread = 0,
		HeadshotMultiplier = 2.5,
		FalloffStart = 40,
		FalloffEnd = 100,
		MinDamageScale = 0.7,
		Range = 400,
		MagazineSize = 6,
		ReloadTime = 2.2,

		HipSpread = 0.9,
		AdsSpread = 0.1,
		MoveSpreadBonus = 1,
		AirSpreadBonus = 3,
		CrouchSpreadScale = 0.75,
		AdsFovScale = 0.8,
		AdsTime = 0.15,
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
}

return Weapons
