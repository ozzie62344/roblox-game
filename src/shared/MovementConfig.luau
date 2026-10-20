-- All the movement "feel" numbers live here. Tweak these while playtesting!
-- Speeds are in studs/second, accelerations in studs/second².

return {
	-- Running (Siege-style: no jumping, sliding or dashing; you get over things by vaulting).
	-- These are a 2-speed operator's; SpeedRating scales them for 1- and 3-speeds.
	WalkSpeed = 13,
	SprintSpeed = 20, -- (Shift / L3 / thumbstick all the way forward; only while moving forward)
	AimWalkSpeed = 8, -- speed while aiming down sights
	StrafeScale = 0.9, -- moving sideways is a little slower than forward...
	BackpedalScale = 0.8, -- ...and backing up slower still
	SprintBlockAfterShot = 0.35, -- can't sprint for this long after shooting
	SprintOutTime = 0.25, -- seconds after a sprint (or a vault) ends before you can fire (state.canFire): the gun coming back up
	GroundAccel = 70, -- how fast you reach your target speed (weighty: ~0.2 s from standing to a walk)
	GroundDecel = 80, -- how fast you stop when you let go of the keys (a short glide, no instant stops)
	MomentumFriction = 25, -- how fast extra speed (pushing off a rope, a fast vault) bleeds off on the ground
	LobbySlideSpeed = 30, -- crouching mid-sprint in the lobby (only there) slides off at this speed
	SprintThreshold = 16, -- others count as sprinting above this speed (loud footsteps, gun-down pose):
	-- between the fastest walk (3-speed: 14.3) and the slowest sprint (1-speed: 18)

	-- Armor / speed ratings (Operators.luau): 3-speed operators move ~10% faster, 1-speed ~10%
	-- slower, in everything (walk, sprint, crouch, crawl). No operator = 2.
	SpeedRating = { 0.9, 1, 1.1 }, -- by Speed: 1, 2, 3

	-- Air (falling off a ledge, pushing off a rope: there's no jumping)
	AirAccel = 40, -- control when you're slower than run speed
	AirDrag = 4, -- how fast extra speed bleeds off in the air (low = keep momentum)
	AirSteer = 4, -- how quickly you can turn your momentum in the air

	-- Crouch (tap C / Left Ctrl to toggle; sprinting stands you up)
	CrouchSpeed = 7.5,
	CrouchHeightDrop = 1.2, -- how far your body (and hitbox) lowers when crouching
	CrouchTransitionSpeed = 14,

	-- Prone (tap C / Left Ctrl twice quickly; C again → crouch, Space or sprint → stand up)
	ProneSpeed = 2.5,
	ProneDoubleTap = 0.35, -- most seconds between the two taps
	ProneHipHeight = 0.1, -- lying on the floor (the hitbox drops this low too)
	ProneCameraDrop = 1.4, -- extra drop for your eyes (your body lies flat, so they're near the floor)

	-- Vault (Space / gamepad A / the phone's VAULT button, facing low cover or a window): a short
	-- scripted hop over it, or up onto it if it's too deep to clear. Not while aiming, reloading or
	-- lying down; it ends a sprint. Heights are from your feet to the top of the cover.
	VaultReach = 2.8, -- studs from your middle to the cover's face (about an arm's length in front)
	VaultMinHeight = 1.2, -- lower than this you just walk over it
	VaultMaxHeight = 4.5, -- the highest you can vault over or climb onto (the old jump height: no new roofs)
	VaultMaxThickness = 2.4, -- deeper than this and you climb up onto it instead of over
	VaultMinGap = 3.6, -- room needed above the cover / sill to get through (windows are 4)
	VaultMaxDrop = 8, -- how far below the top the far side's floor can be (further: you drop off)
	VaultTime = 0.6, -- seconds for a vault from a walk...
	VaultFastTime = 0.42, -- ...or from a sprint (a quick speed vault)
	ClimbTime = 0.75, -- seconds to climb up onto a ledge / crate
	VaultExitSpeed = 4, -- speed you land with after a normal vault...
	VaultFastExitSpeed = 11, -- ...and after a speed vault (you keep running)
	VaultCameraDip = 0.45, -- studs the camera dips mid-vault
	VaultCameraRoll = 4, -- degrees of camera roll mid-vault

	-- Safety
	MaxMoveAccel = 4000, -- caps the movement force (infinite force can fling you)
	MaxFallSpeed = 140,

	-- Lean (hold Q / E)
	LeanOffset = 1.4, -- how far the camera slides sideways
	LeanRoll = 12, -- degrees of camera tilt
	LeanBodyAngle = 22, -- degrees other players see your upper body tilt
	LeanSpeed = 26, -- how fast you lean in/out

	-- Camera
	MouseSensitivity = 0.6, -- 1 = Roblox's normal speed; lower = slower turning (aiming is slower still, per gun)
	BaseFov = 80,
	FovSpeedBonus = 4, -- extra FOV at a full sprint (subtle)
	FovMaxSpeed = 22, -- speed where the FOV bonus is maxed out
	StrafeTilt = 1.5, -- degrees of camera roll while strafing
}
