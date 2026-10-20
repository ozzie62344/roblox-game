-- Shared local-player state so movement, camera, lean and weapons can read each other
-- without requiring each other.

return {
	-- Movement
	speed = 0,
	velocity = Vector3.zero,
	grounded = true,
	sprinting = false,
	crouching = false,
	prone = false, -- lying down / crawling (double-tap crouch)
	vaulting = false, -- mid vault / climb (MovementController): the body is moved along a short arc
	vaultAlpha = 0, -- how far through the vault, 0..1 (CameraEffects dips the camera with it)
	canFire = true, -- false while sprinting or vaulting and for MovementConfig.SprintOutTime after (the gun coming back up)
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
	adsSensitivityScale = 1, -- the player's ADS sensitivity setting: scales the gun's aim slowdown (ClientSettings)
	invertY = false, -- the player's invert-look setting (ClientSettings; MouseUnlock, drone, cameras)
	deployPitch = 0, -- radians, applied to the camera like recoil
	gesturing = false, -- hands busy with a gadget / ability move (HandsAnimator): gun put away
	deafUntil = 0, -- os.clock(): a flashbang left your ears ringing (Sound3D muffles everything)
	deafStrength = 0, -- 0..1
	droning = false, -- driving your scout drone (DroneController) or watching defender cameras (CamsController): body rooted, gun put away
	downed = false, -- down but not out (DBNOController): on the floor crawling, no gun, no gadgets
	holdingWound = false, -- downed and holding your wound (F): slower bleed, no crawling

	-- Weapon
	aiming = false,
	aimAlpha = 0, -- 0 = hip, 1 = fully aimed in
	adsFovScale = 1,
	lastShot = -math.huge,
	fireHeld = false, -- the fire button is held with a gun out (WeaponController): it stops a sprint
	recoilPitch = 0, -- radians, applied to the camera
	recoilYaw = 0,
	recoilRoll = 0, -- radians, visual jolt only

	-- Where you are: in the lobby you're in third person with your gun put away
	inLobby = false,
	-- In the lobby's practice range (client PracticeRange): first person, gun out, so inLobby is false there
	inPractice = false,

	-- UI
	devPanelOpen = false,
	mouseUnlocked = false,
	draftOpen = false, -- loadout cards on screen (cursor free)
	voteOpen = false, -- map vote on screen (cursor free)
	modesOpen = false, -- lobby: the PLAY → MODES screen is up
	shopOpen = false, -- lobby: the SHOP is up (cursor free)
	partyOpen = false, -- lobby: the PARTY screen is up (cursor free)
	modsOpen = false, -- the MODS menu (attachments) is up, any time (cursor free, no shooting)
	settingsOpen = false, -- the SETTINGS menu is up, any time (SettingsMenu; cursor free, no shooting)
	touchControls = false, -- playing on a touch screen: MobileControls' buttons are showing
	lastPing = -math.huge, -- os.clock() of your last on-foot ping (TeamPing; the tutorial watches it)
	lookDrag = Vector2.zero, -- pixels the finger holding FIRE moved since last frame (MouseUnlock turns the camera)
	weaponSpin = 0, -- how far the gatling's barrels are spun up, 0..1 (WeaponController; you move slower)
	interactAction = nil :: string?, -- what HOLD [G] would do right now (ObjectiveController)
	loadoutWindow = false, -- you can still change your loadout (until the round starts)
	spectating = false,
	killCam = nil :: string?, -- just died (KillCam): "View" = it drives the camera, "Card" = only its card is up
	resultsOpen = false, -- the end-of-match results / MVP screen is up (MatchResults; cursor free)
}
