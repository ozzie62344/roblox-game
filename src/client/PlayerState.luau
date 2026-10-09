-- Shared local-player state so movement, camera, lean and weapons can read each other
-- without requiring each other.

return {
	-- Movement
	speed = 0,
	velocity = Vector3.zero,
	grounded = true,
	sprinting = false,
	sliding = false,
	crouching = false,
	dashing = false,
	lastWallJump = -math.huge,

	-- Lean: -1 (left) .. 1 (right), smoothed
	lean = 0,
	leanOffset = 0, -- studs the camera is shifted sideways (shortened if a wall is in the way)
	leaning = false,

	-- Deploying cover: locked in place, gun lowered, camera looks down then follows the cover up
	deploying = false,
	interacting = false, -- planting / defusing: also locks you in place
	meleeing = false, -- knife swing in progress (gun lowered, can't shoot)
	aimSensitivity = 1, -- mouse speed multiplier while aiming (set by the gun)
	deployPitch = 0, -- radians, applied to the camera like recoil
	gesturing = false, -- hands busy with a gadget / ability move (HandsAnimator): gun put away

	-- Weapon
	aiming = false,
	aimAlpha = 0, -- 0 = hip, 1 = fully aimed in
	adsFovScale = 1,
	lastShot = -math.huge,
	recoilPitch = 0, -- radians, applied to the camera
	recoilYaw = 0,
	recoilRoll = 0, -- radians, visual jolt only

	-- Where you are: in the lobby you're in third person with your gun put away
	inLobby = false,

	-- UI
	devPanelOpen = false,
	mouseUnlocked = false,
	draftOpen = false, -- loadout cards on screen (cursor free)
	loadoutWindow = false, -- you can still change your loadout (until the round starts)
	spectating = false,
}
