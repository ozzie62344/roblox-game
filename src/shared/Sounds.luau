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
		OwnVolumeScale = 0.55, -- your own steps are quieter, so other people's stand out
		-- What you're walking on changes the step (Footsteps picks one from the floor's material):
		-- pitch, loudness and reach multipliers, tone (dB), and an extra layer from Sets
		Surfaces = {
			Hard = { Pitch = 1, Volume = 1, Range = 1, Treble = 2 }, -- concrete, tile, asphalt, brick
			Metal = { Pitch = 1.12, Volume = 1.15, Range = 1.35, Treble = 5, Layer = "MetalStep", LayerVolume = 0.3 }, -- catwalks, stairs, containers
			Wood = { Pitch = 0.8, Volume = 1.05, Range = 1.1, Bass = 5, Treble = -3 }, -- floorboards: deeper, hollow
			Soft = { Pitch = 0.88, Volume = 0.5, Range = 0.6, Treble = -16 }, -- carpet, grass, dirt: muffled, short reach
			Gravel = { Pitch = 1.3, Volume = 1, Range = 1.05, Treble = 6 }, -- gravel, cobbles: sharp and crunchy
		},
	},

	-- Grenades (GrenadeEffects)
	SmokeHiss = { -- the canister pouring out smoke (Pro Sound Effects "Aerosol Spray 2", looped, pitched down)
		Id = "rbxassetid://9113044265",
		Range = 60,
		Volume = 0.6,
		Pitch = 0.55,
	},
	Flashbang = { -- the bang (an Explosion pitched up: sharper)
		Range = 280,
		Volume = 1.3,
		Pitch = 1.6,
	},
	EarRing = { -- your ears ringing after a flash (a plain high tone)
		Id = "rbxassetid://135972012837371",
		Volume = 0.18,
	},

	-- Drones whine as they drive (DroneHum); louder the faster they go
	DroneMotor = {
		Id = "rbxassetid://9118377325", -- Robot Servo 4 (Pro Sound Effects)
		Range = 45,
		Volume = 0.5,
		Pitch = 1.6,
	},

	-- The gatling's barrels whirring (WeaponController): the pitch climbs as they spin up
	GatlingSpin = {
		Id = "rbxassetid://9118377325", -- Robot Servo 4 (Pro Sound Effects), like the drone
		Volume = 0.4,
		Pitch = 1.2,
	},

	-- Rappelling (RappelController): the carabiner clipping onto the rope, and the rope zipping
	-- through it as you hook up and let go. Everyone near hears it (through walls, muffled).
	Rappel = {
		Clip = "rbxassetid://9118138519", -- Relay Clicks 10 (Pro Sound Effects)
		Zip = "rbxassetid://9113828720", -- Cloth Rip Rapid 7 (Pro Sound Effects)
		Range = 70,
		Volume = 0.7,
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

	-- Vaulting over cover / climbing onto a ledge (Footsteps): hands and kit slapping onto it (the
	-- footstep, pitched down) with a scuff of cloth, then a step as you land. Carries like a sprint.
	Vault = {
		Id = "rbxasset://sounds/action_footsteps_plastic.mp3",
		Cloth = "rbxassetid://9113828720", -- Cloth Rip Rapid 7 (Pro Sound Effects), like the rope
		Range = 90,
		Volume = 0.9,
		Pitch = 0.7,
		ClothVolume = 0.35,
		Duration = 0.25, -- seconds of the footstep sound per thump
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

	-- Planted defuser beeping (beeps speed up as it gets close to defusing the bomb).
	-- Placeholder: swap in a real beep from the Toolbox if this one doesn't play.
	ChargeBeep = {
		Id = "rbxasset://sounds/electronicpingshort.wav",
		Range = 120,
		Volume = 0.5,
	},

	-- Proximity alarm going off: the beep, loud and shrill, three quick ones a second, heard
	-- through walls by both teams (that's the point: the attacker knows they've been caught too)
	ProximityAlarm = {
		Id = "rbxasset://sounds/electronicpingshort.wav",
		Range = 110,
		Volume = 1,
		Pitch = 2.1,
		Repeats = 3,
	},
	-- A claymore's laser tripped: the relay click just before it goes off
	ClaymoreTrip = {
		Id = "rbxassetid://9118138519", -- Relay Clicks 10 (Pro Sound Effects), like the rappel clip
		Range = 45,
		Volume = 1,
		Pitch = 0.8,
	},

	-- A teammate's ping (TeamPing): the same beep, softer and pitched up so it isn't mistaken for
	-- the defuser. Plays flat (not from the spot), like a radio blip.
	Ping = {
		Id = "rbxasset://sounds/electronicpingshort.wav",
		Volume = 0.3,
		Pitch = 1.6,
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
		DrywallBreak = { -- Pro Sound Effects (licensed, Creator Store)
			"rbxassetid://9114199583", -- Drywall Crunch 1
			"rbxassetid://9114199593", -- Drywall Crunch 2
			"rbxassetid://9114199757", -- Drywall Crunch 3
			"rbxassetid://9114199750", -- Drywall Crunch 4
		},
		WoodBreak = { -- barricades (Creator Store)
			"rbxassetid://138044840389379", -- wood_plank_break2
			"rbxassetid://126645609816652", -- wood_plank_break3
			"rbxassetid://114129279405032", -- wood_plank_break4
		},
		Explosion = { -- breach charges (Creator Store)
			"rbxassetid://101767123218902", -- Grenade_Explosion_Close
			"rbxassetid://134825578212679", -- Grenade Explosion_01
			"rbxassetid://139210252225248", -- grenade explosion
		},
		Zap = { -- shock wires, EMP, gadgets getting fried (Pro Sound Effects)
			"rbxassetid://9116279560", -- Lightning Flashes Quick Electrical Bursts 56
			"rbxassetid://9116275293", -- Lightning Flashes Quick Electrical Bursts 3
			"rbxassetid://9116276051", -- Lightning Flashes Quick Electrical Bursts 11
		},
		MetalStep = { -- layered under steps on metal (Pro Sound Effects "Metal Grab, Hollow Metal Impact")
			"rbxassetid://9116634359",
			"rbxassetid://9116632805",
			"rbxassetid://9116634384",
		},
		GlassBreak = { -- windows (Creator Store)
			"rbxassetid://118987440163311", -- glass_shatter_01
			"rbxassetid://138326537963545", -- glass_shatter_05
			"rbxassetid://132457128699700", -- glass_shatter_07
			"rbxassetid://139826391278483", -- glass_shatter_09
		},
	},

	-- Walls, barricades and windows breaking (DestructionEffects). Breaking things is loud on
	-- purpose, like in Siege: you hear people opening up walls.
	Destruction = {
		Range = 140,
		HoleVolume = 0.2, -- a bullet punching through
		ChunkVolume = 0.9, -- a knife knocking a chunk out
		SmashVolume = 1.1, -- a whole barricade broken down
		GlassVolume = 0.9,
		BlastVolume = 1.4, -- breach charge / thermite going off
		BlastRange = 350,
		ZapVolume = 0.8,
	},

	-- Thermite burning through steel (Pro Sound Effects "Tesla Coil 4": arcing, welding-like)
	ThermiteBurn = {
		Id = "rbxassetid://9119992790",
		Range = 90,
		Volume = 0.9,
	},

	-- Knife (F). Placeholders: Roblox's built-in classic sword sounds.
	Knife = {
		Swing = "rbxasset://sounds/swordlunge.wav",
		Hit = "rbxasset://sounds/swordslash.wav",
		Volume = 0.7,
	},

	-- Your hits, once the server confirms them (WeaponController → Hud hit markers): a quiet tick
	-- for a body hit, a sharper higher one for the head, a lower chime for a kill. Placeholders:
	-- Roblox's built-in ping, pitched.
	HitMarker = {
		Id = "rbxasset://sounds/electronicpingshort.wav",
		Body = { Volume = 0.22, Pitch = 2.6 },
		Head = { Volume = 0.3, Pitch = 3.2 },
		Kill = { Volume = 0.4, Pitch = 1.35 },
	},

	-- Shop: buying a skin, and credits coming in. Placeholders: Roblox's built-in ping.
	Shop = {
		Buy = "rbxasset://sounds/electronicpingshort.wav",
		Credits = "rbxasset://sounds/electronicpingshort.wav",
		Volume = 0.45,
	},

	GunshotRange = 450, -- how far other players' shots carry
	Guns = {
		OwnVolume = 0.8, -- your own shots (not positional)
		OtherVolume = 1, -- other players' shots (positional, muffled through walls)
		PitchVariation = 0.05, -- each shot's pitch is randomly ±this, so full-auto doesn't sound robotic
		ReloadVolume = 0.6,
		ReloadRange = 40, -- you can hear enemies reloading nearby
	},

	-- Sounds behind walls get muffled (quieter + duller) so you can tell they're not in the open.
	-- Each wall in the way muffles more (up to MaxWalls); through a floor or ceiling it's a deep,
	-- bassy thump instead, so you can tell someone is above or below you.
	MuffleVolumeScale = 0.6, -- per wall
	MaxWalls = 3,
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
