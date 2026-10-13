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
	prone = false, -- lying down / crawling (double-tap crouch)
	dashing = false,
	lastWallJump = -math.huge,
	rappelling = false, -- hanging on a rope on the outside of a building (RappelController)
	rappelSpeed = 0, -- studs/second you're moving along the wall on the rope

	-- Lean: -1 (left) .. 1 (right), smoothed
	lean = 0,
	leanOffset = 0, -- studs the camera is shifted sideways (shortened if a wall is in the way)
	leaning = false,
	leanToggle = true, -- tap Q / E to lean and again to stop (false: lean only while held); dev panel

	-- Deploying cover: locked in place, gun lowered, camera looks down then follows the cover up
	deploying = false,
	interacting = false, -- planting / disabling: also locks you in place
	meleeing = false, -- knife swing in progress (gun lowered, can't shoot)
	aimSensitivity = 1, -- mouse speed multiplier while aiming (set by the gun)
	deployPitch = 0, -- radians, applied to the camera like recoil
	gesturing = false, -- hands busy with a gadget / ability move (HandsAnimator): gun put away
	deafUntil = 0, -- os.clock(): a flashbang left your ears ringing (Sound3D muffles everything)
	deafStrength = 0, -- 0..1
	droning = false, -- driving your scout drone (DroneController) or watching defender cameras (CamsController): body rooted, gun put away

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
	voteOpen = false, -- map vote on screen (cursor free)
	modesOpen = false, -- lobby: the PLAY → MODES screen is up
	shopOpen = false, -- lobby: the SHOP is up (cursor free)
	partyOpen = false, -- lobby: the PARTY screen is up (cursor free)
	touchControls = false, -- playing on a touch screen: MobileControls' buttons are showing
	lookDrag = Vector2.zero, -- pixels the finger holding FIRE moved since last frame (MouseUnlock turns the camera)
	weaponSpin = 0, -- how far the gatling's barrels are spun up, 0..1 (WeaponController; you move slower)
	interactAction = nil :: string?, -- what HOLD [G] would do right now (ObjectiveController)
	loadoutWindow = false, -- you can still change your loadout (until the round starts)
	spectating = false,
}
