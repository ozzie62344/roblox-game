-- Sound ids and how far each sound carries. Ranges are gameplay: they decide who can hear you.
-- The rbxasset:// ones are Roblox's built-in character sounds (placeholders that work out of the box).
-- Swap in better ones from the Studio Toolbox (Audio tab) with "rbxassetid://<id>".

local Sounds = {
	Footstep = {
		Id = "rbxasset://sounds/action_footsteps_plastic.mp3",
		-- How far away each kind of step can be heard (studs)
		SprintRange = 110,
		WalkRange = 60,
		CrouchRange = 18,
		SprintVolume = 0.9,
		WalkVolume = 0.55,
		CrouchVolume = 0.25,
		-- Studs travelled between steps
		SprintStride = 7,
		WalkStride = 5.5,
		CrouchStride = 4,
		Duration = 0.3, -- seconds of the sound to play per step
	},

	Jump = {
		Id = "rbxasset://sounds/action_jump.mp3",
		Range = 60,
		Volume = 0.5,
	},

	Land = {
		Id = "rbxasset://sounds/action_jump_land.mp3",
		Range = 90,
		Volume = 0.8,
		MinFallSpeed = 35, -- softer landings make no sound
	},

	-- Deployable cover starting to come out of the ground (placeholder: get-up sound, pitched down)
	CoverStart = {
		Id = "rbxasset://sounds/action_get_up.mp3",
		Range = 50,
		Volume = 0.8,
		Pitch = 0.7,
	},

	-- Deployable cover slamming into place (placeholder: the landing thud, pitched down to sound heavy)
	CoverDeploy = {
		Id = "rbxasset://sounds/action_jump_land.mp3",
		Range = 80,
		Volume = 1,
		Pitch = 0.55,
	},

	-- Planted charge beeping (beeps speed up as it gets close to detonating).
	-- Placeholder: swap in a real beep from the Toolbox if this one doesn't play.
	ChargeBeep = {
		Id = "rbxasset://sounds/electronicpingshort.wav",
		Range = 120,
		Volume = 0.5,
	},

	-- Sets of interchangeable sounds: one is picked at random each time so repeats don't sound copy-pasted.
	-- Weapons.luau refers to these by name (FireSound / TailSound / ReloadSound).
	-- These are Audioscape's licensed weapon sounds from the Creator Store (free to use).
	Sets = {
		GunShot = {
			"rbxassetid://77455268208044", -- AS_gun_shot-01
			"rbxassetid://128598607431847", -- AS_gun_shot-02
			"rbxassetid://86036041526253", -- AS_gun_shot-03
			"rbxassetid://124764074117990", -- AS_gun_shot-04
		},
		GunTail = { -- echo after a shot
			"rbxassetid://90852446208160", -- AS_gun_tail-01
			"rbxassetid://70527882874881", -- AS_gun_tail-02
			"rbxassetid://79289354458541", -- AS_gun_tail-03
			"rbxassetid://111187749925677", -- AS_gun_tail-04
		},
		GunFoley = { -- handling / magazine sounds, used for reloads
			"rbxassetid://101803348893194", -- AS_gun_foley-01
			"rbxassetid://92321876028160", -- AS_gun_foley-02
			"rbxassetid://135901981148051", -- AS_gun_foley-03
			"rbxassetid://73599108833500", -- AS_gun_foley-04
		},
		ShotgunShot = {
			"rbxassetid://99008924129683", -- AS_shotgun_shot-01
			"rbxassetid://82409501948316", -- AS_shotgun_shot-02
			"rbxassetid://106454770387605", -- AS_shotgun_shot-03
			"rbxassetid://84039532799719", -- AS_shotgun_shot-04
		},
		ShotgunTail = {
			"rbxassetid://75302784250672", -- AS_shotgun_tail-01
			"rbxassetid://116468550696572", -- AS_shotgun_tail-02
			"rbxassetid://125311341637563", -- AS_shotgun_tail-03
			"rbxassetid://99323994116525", -- AS_shotgun_tail-04
		},
		ShotgunFoley = {
			"rbxassetid://128663118150595", -- AS_shotgun_foley-01
			"rbxassetid://111442452811059", -- AS_shotgun_foley-02
			"rbxassetid://114280224323666", -- AS_shotgun_foley-03
			"rbxassetid://103060570812555", -- AS_shotgun_foley-04
		},
	},

	GunshotRange = 450, -- how far other players' shots carry
	Guns = {
		OwnVolume = 0.8, -- your own shots (not positional)
		OtherVolume = 1, -- other players' shots (positional, muffled through walls)
		PitchVariation = 0.05, -- each shot's pitch is randomly ±this, so full-auto doesn't sound robotic
		ReloadVolume = 0.6,
		ReloadRange = 40, -- you can hear enemies reloading nearby
	},

	-- Sounds behind walls get muffled (quieter + duller) so you can tell they're not in the open
	MuffleVolumeScale = 0.6,
}

-- A random sound id from a set (see Sets above), or "" if there's no such set
function Sounds.Pick(setName: string?): string
	local set = setName and Sounds.Sets[setName]
	if not set or #set == 0 then
		return ""
	end
	return set[math.random(#set)]
end

return Sounds
