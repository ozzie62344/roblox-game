-- Sound ids and how far each sound carries. Ranges are gameplay: they decide who can hear you.
-- The rbxasset:// ones are Roblox's built-in character sounds (placeholders that work out of the box).
-- Swap in better ones from the Studio Toolbox (Audio tab) with "rbxassetid://<id>".

return {
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

	-- Gunshots are set per weapon in Weapons.luau (FireSound); this is how far they carry
	GunshotRange = 450,

	-- Sounds behind walls get muffled (quieter + duller) so you can tell they're not in the open
	MuffleVolumeScale = 0.6,
}
