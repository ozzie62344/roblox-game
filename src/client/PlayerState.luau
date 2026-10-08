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
	deployPitch = 0, -- radians, applied to the camera like recoil

	-- Weapon
	aiming = false,
	aimAlpha = 0, -- 0 = hip, 1 = fully aimed in
	adsFovScale = 1,
	lastShot = -math.huge,
	recoilPitch = 0, -- radians, applied to the camera
	recoilYaw = 0,
	recoilRoll = 0, -- radians, visual jolt only

	-- UI
	devPanelOpen = false,
	mouseUnlocked = false,
	draftOpen = false, -- loadout cards on screen
	spectating = false,
}
