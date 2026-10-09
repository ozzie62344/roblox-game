-- All the movement "feel" numbers live here. Tweak these while playtesting!
-- Speeds are in studs/second, accelerations in studs/second².

return {
	-- Running
	WalkSpeed = 18,
	SprintSpeed = 28,
	AimWalkSpeed = 12, -- speed while aiming down sights
	SprintBlockAfterShot = 0.35, -- can't sprint for this long after shooting
	GroundAccel = 220, -- how fast you reach your target speed
	GroundDecel = 260, -- how fast you stop when you let go of the keys
	MomentumFriction = 25, -- how fast extra speed (from slides/dashes) bleeds off on the ground

	-- Air
	AirAccel = 75, -- control when you're slower than run speed
	AirDrag = 4, -- how fast extra speed bleeds off in the air (low = keep momentum)
	AirSteer = 7, -- how quickly you can turn your momentum in the air

	-- Crouch (C / Left Ctrl when not sprinting — toggles)
	CrouchSpeed = 9,
	CrouchHeightDrop = 1.2, -- how far your body (and hitbox) lowers when crouching or sliding
	CrouchTransitionSpeed = 14,

	-- Slide (hold C / Left Ctrl while sprinting — lasts as long as you hold, up to SlideMaxDuration)
	SlideMinStartSpeed = 14, -- must be moving at least this fast to slide
	SlideBoost = 20, -- speed added when the slide starts
	SlideBoostCooldown = 0.8, -- seconds before another slide gives the boost again (stops slide spam)
	SlideMaxSpeed = 54,
	SlideFriction = 15,
	SlideBufferTime = 0.2, -- press slide this long before landing and it still triggers on touchdown
	SlideSteer = 2,
	SlideEndSpeed = 12, -- slide stops below this speed
	SlideMaxDuration = 0.7,
	SlideCooldown = 0.6, -- seconds after a slide ends before you can slide again

	-- Dash (X) — ability
	DashSpeed = 85,
	DashDuration = 0.14,
	DashExitSpeed = 34, -- speed you keep after the dash ends
	DashCooldown = 1.8,

	-- Abilities: dash and wall jump only work if the player has them.
	-- Later the loadout system gives one out per round. Use the dev panel (P) to give yourself one.
	-- Set this to true to give everyone every ability.
	TestAllAbilities = false,

	-- Safety
	MaxMoveAccel = 4000, -- caps the movement force (infinite force can fling you)
	MaxFallSpeed = 140,

	-- Lean (hold Q / E)
	LeanOffset = 1.4, -- how far the camera slides sideways
	LeanRoll = 12, -- degrees of camera tilt
	LeanBodyAngle = 22, -- degrees other players see your upper body tilt
	LeanSpeed = 26, -- how fast you lean in/out

	-- Wall jump (Space while in the air next to a wall) — ability
	WallJumpUp = 75, -- upward speed of a wall jump
	WallJumpPush = 30, -- how hard you're pushed away from the wall
	WallJumpSteerLock = 0.3, -- seconds after a wall jump where holding keys can't steer you back into the wall
	WallJumpKeepAlong = 0.9, -- how much of your speed along the wall you keep (1 = all)
	WallJumpMaxPerAir = 3, -- wall jumps allowed before you touch the ground again
	WallJumpCheckDistance = 3, -- how close to a wall you need to be
	WallJumpMinAirTime = 0.1, -- can't wall jump right after leaving the ground
	WallJumpFovKick = 5,

	-- Camera
	MouseSensitivity = 0.6, -- 1 = Roblox's normal speed; lower = slower turning (aiming is slower still, per gun)
	BaseFov = 80,
	FovSpeedBonus = 14, -- extra FOV at high speed
	FovMaxSpeed = 50, -- speed where the FOV bonus is maxed out
	DashFovKick = 8,
	SlideTilt = 5, -- degrees of camera roll while sliding
	StrafeTilt = 1.5, -- degrees of camera roll while strafing
}
