-- Weapon stats. Shared so the client (feel/effects) and server (validation/damage) agree.
-- The loadout system picks from every weapon in this list.
--
-- Sounds: paste a Roblox sound asset id like "rbxassetid://123456" to enable.
-- (Find gunshot/reload sounds in the Studio Toolbox → Audio.)

export type Look = {
	BodyLength: number,
	BarrelLength: number,
	StockLength: number,
	MagSize: Vector3,
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

	RecoilUp: number, -- degrees of camera kick per shot
	RecoilSide: number, -- max random sideways degrees per shot
	RecoilMax: number, -- recoil can't climb higher than this many degrees
	RecoilRecover: number, -- how fast recoil returns to center
	ViewKick: number, -- how much the on-screen gun jolts per shot

	Look: Look,
	FireSound: string,
	ReloadSound: string,
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

		RecoilUp = 0.22,
		RecoilSide = 0.1,
		RecoilMax = 3,
		RecoilRecover = 12,
		ViewKick = 0.03,

		Look = {
			BodyLength = 1.4,
			BarrelLength = 0.8,
			StockLength = 0.5,
			MagSize = Vector3.new(0.18, 0.45, 0.25),
			Color = DARK,
		},
		FireSound = "",
		ReloadSound = "",
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

		RecoilUp = 0.16,
		RecoilSide = 0.14,
		RecoilMax = 2.5,
		RecoilRecover = 14,
		ViewKick = 0.02,

		Look = {
			BodyLength = 0.9,
			BarrelLength = 0.4,
			StockLength = 0.3,
			MagSize = Vector3.new(0.14, 0.55, 0.18),
			Color = Color3.fromRGB(35, 36, 40),
		},
		FireSound = "",
		ReloadSound = "",
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

		RecoilUp = 3,
		RecoilSide = 0.6,
		RecoilMax = 6,
		RecoilRecover = 7,
		ViewKick = 0.2,

		Look = {
			BodyLength = 1.2,
			BarrelLength = 1.1,
			StockLength = 0.55,
			MagSize = Vector3.new(0.16, 0.16, 0.9), -- pump tube under the barrel
			Color = Color3.fromRGB(70, 52, 38),
		},
		FireSound = "",
		ReloadSound = "",
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

		RecoilUp = 4,
		RecoilSide = 0.5,
		RecoilMax = 8,
		RecoilRecover = 5,
		ViewKick = 0.25,

		Look = {
			BodyLength = 1.6,
			BarrelLength = 1.3,
			StockLength = 0.6,
			MagSize = Vector3.new(0.16, 0.25, 0.25),
			Color = Color3.fromRGB(55, 62, 48),
		},
		FireSound = "",
		ReloadSound = "",
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

		RecoilUp = 2,
		RecoilSide = 0.4,
		RecoilMax = 5,
		RecoilRecover = 9,
		ViewKick = 0.15,

		Look = {
			BodyLength = 0.5,
			BarrelLength = 0.6,
			StockLength = 0,
			MagSize = Vector3.new(0.3, 0.3, 0.3), -- the cylinder
			Color = Color3.fromRGB(150, 150, 158),
		},
		FireSound = "",
		ReloadSound = "",
	},
}

return Weapons
