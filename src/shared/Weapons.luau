-- Weapon stats. Shared so the client (feel/effects) and server (validation/damage) agree.
-- Add new guns here; the loadout system will pick from this list later.
--
-- Sounds: paste a Roblox sound asset id like "rbxassetid://123456" to enable.
-- (Find gunshot/reload sounds in the Studio Toolbox → Audio.)

export type Weapon = {
	Name: string,
	Automatic: boolean,
	RPM: number, -- rounds per minute
	Damage: number,
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

	RecoilUp: number, -- degrees of camera kick per shot
	RecoilSide: number, -- max random sideways degrees per shot
	RecoilMax: number, -- recoil can't climb higher than this many degrees
	RecoilRecover: number, -- how fast recoil returns to center
	ViewKick: number,

	FireSound: string,
	ReloadSound: string,
}

local Weapons: { [string]: Weapon } = {
	Rifle = {
		Name = "Rifle",
		Automatic = true,
		RPM = 720,
		Damage = 34,
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

		RecoilUp = 0.22,
		RecoilSide = 0.1,
		RecoilMax = 3,
		RecoilRecover = 12,
		ViewKick = 0.03, -- how much the on-screen gun jolts per shot

		FireSound = "",
		ReloadSound = "",
	},
}

return Weapons
