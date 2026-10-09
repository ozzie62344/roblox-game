-- Your gun: firing, aiming down sights, recoil, spread, reloading, scopes.
-- Shots are raycast here for instant feedback, then sent to the server, which
-- double-checks them and applies the damage.
-- Your current weapon follows the "Weapon" attribute the server sets (loadouts / dev panel).

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Abilities = require(ReplicatedStorage.Shared.Abilities)
local Config = require(ReplicatedStorage.Shared.MovementConfig)
local Sounds = require(ReplicatedStorage.Shared.Sounds)
local Weapons = require(ReplicatedStorage.Shared.Weapons)
local Sound3D = require(script.Parent.Parent.Audio.Sound3D)
local state = require(script.Parent.Parent.PlayerState)
local Effects = require(script.Parent.Effects)
local Hud = require(script.Parent.Hud)
local Viewmodel = require(script.Parent.Viewmodel)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local FireRemote = Remotes:WaitForChild("Fire") :: RemoteEvent
local ReloadRemote = Remotes:WaitForChild("Reload") :: RemoteEvent
local ShotFired = Remotes:WaitForChild("ShotFired") :: RemoteEvent
local HitConfirmed = Remotes:WaitForChild("HitConfirmed") :: RemoteEvent
local ReloadStarted = Remotes:WaitForChild("ReloadStarted") :: RemoteEvent

local player = Players.LocalPlayer
local random = Random.new()

local WeaponController = {}

local weapon = Weapons.Rifle
local ammo = weapon.MagazineSize
local reloading = false
local reloadToken = 0
local triggerHeld = false
local aimHeld = false
local nextFireTime = 0
local currentSpread = weapon.HipSpread
local viewmodel = nil

local function getAliveCharacter(): (Model?, Humanoid?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		return character, humanoid
	end
	return nil, nil
end

local function findHumanoid(part: Instance): Humanoid?
	local model = part:FindFirstAncestorOfClass("Model")
	while model do
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if humanoid then
			return humanoid
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil
end

local function computeSpread(): number
	local spread = weapon.HipSpread + (weapon.AdsSpread - weapon.HipSpread) * state.aimAlpha
	local moveAlpha = math.clamp(state.speed / Config.SprintSpeed, 0, 1)
	spread += weapon.MoveSpreadBonus * moveAlpha * (1 - state.aimAlpha * 0.7)
	if not state.grounded or state.sliding then
		spread += weapon.AirSpreadBonus
	elseif state.crouching then
		spread *= weapon.CrouchSpreadScale
	end
	return spread
end

-- Random direction inside a cone of `spreadDegrees` around `cframe`'s look direction
local function spreadDirection(cframe: CFrame, spreadDegrees: number): Vector3
	local spin = random:NextNumber(0, math.pi * 2)
	local tilt = math.rad(spreadDegrees) * math.sqrt(random:NextNumber())
	return (cframe * CFrame.Angles(0, 0, spin) * CFrame.Angles(tilt, 0, 0)).LookVector
end

local function randomPitch(): number
	local variation = Sounds.Guns.PitchVariation
	return 1 + random:NextNumber(-variation, variation)
end

local function updateAmmoHud()
	Hud.SetAmmo(ammo, weapon.MagazineSize, reloading)
end

local function updateLoadoutHud()
	local abilityName = player:GetAttribute("Ability")
	local ability = abilityName and Abilities[abilityName]
	local abilityText = nil
	if ability then
		abilityText = `[{ability.Key}] {ability.Name}`
		local charges = player:GetAttribute("AbilityCharges")
		if charges then
			-- ● for each charge left, ○ for each used
			abilityText ..= "  " .. string.rep("●", charges) .. string.rep("○", (ability.Charges or charges) - charges)
		end
	end
	Hud.SetLoadout(weapon.Name, abilityText)
end

local function setWeapon(weaponName: string)
	local newWeapon = Weapons[weaponName]
	if not newWeapon then
		return
	end
	weapon = newWeapon
	reloadToken += 1
	reloading = false
	ammo = weapon.MagazineSize
	triggerHeld = false
	state.recoilPitch, state.recoilYaw = 0, 0
	if viewmodel then
		viewmodel:Destroy()
	end
	viewmodel = Viewmodel.new(weapon)
	-- Reload sounds play at the matching moments of the animation (mag out, mag in, bolt...)
	viewmodel.OnAnimationEvent = function(_eventName: string)
		Effects.Sound(Sounds.Pick(weapon.ReloadSound), nil, Sounds.Guns.ReloadVolume, 0.95 + random:NextNumber() * 0.15)
	end
	viewmodel:PlayDraw()
	updateAmmoHud()
	updateLoadoutHud()
end

local function reload()
	if reloading or ammo >= weapon.MagazineSize or not getAliveCharacter() then
		return
	end
	reloading = true
	reloadToken += 1
	local token = reloadToken
	ReloadRemote:FireServer()
	-- The animation (and its sounds) lasts exactly as long as the reload
	if viewmodel then
		viewmodel:PlayReload(weapon.ReloadTime, ammo == 0, weapon.MagazineSize - ammo)
	end
	updateAmmoHud()

	task.delay(weapon.ReloadTime, function()
		if token == reloadToken then
			ammo = weapon.MagazineSize
			reloading = false
			updateAmmoHud()
		end
	end)
end

local function fire(character: Model)
	local now = os.clock()
	nextFireTime = now + 60 / weapon.RPM
	ammo -= 1
	state.lastShot = now

	local camera = Workspace.CurrentCamera
	local origin = camera.CFrame.Position
	-- One aim direction (spread), then each pellet scatters around it (shotguns)
	local aimDirection = spreadDirection(camera.CFrame, currentSpread)
	local aimCFrame = CFrame.lookAt(origin, origin + aimDirection)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }

	local shots = {}
	local hitKind: string? = nil
	for _ = 1, weapon.Pellets do
		local direction = if weapon.Pellets > 1 then spreadDirection(aimCFrame, weapon.PelletSpread) else aimDirection
		local result = Workspace:Raycast(origin, direction * weapon.Range, params)
		local endPosition = if result then result.Position else origin + direction * weapon.Range
		table.insert(shots, { direction, if result then result.Instance else nil, endPosition })

		-- Instant feedback (server confirms damage separately)
		if viewmodel and viewmodel.model.Parent then
			Effects.Tracer(viewmodel:GetMuzzlePosition(), endPosition)
		end
		if result then
			local humanoid = findHumanoid(result.Instance)
			if humanoid and humanoid.Health > 0 then
				if result.Instance.Name == "Head" then
					hitKind = "head"
				elseif not hitKind then
					hitKind = "body"
				end
			else
				Effects.Impact(result.Position, result.Normal)
			end
		end
	end
	FireRemote:FireServer(origin, shots)

	if hitKind then
		Hud.HitMarker(hitKind)
	end
	if viewmodel then
		viewmodel:Kick(weapon.ViewKick)
	end
	local volume = Sounds.Guns.OwnVolume * weapon.FireVolume
	Effects.Sound(Sounds.Pick(weapon.FireSound), nil, volume, weapon.FirePitch * randomPitch())
	if weapon.TailSound then
		Effects.Sound(Sounds.Pick(weapon.TailSound), nil, volume * 0.6, weapon.FirePitch)
	end

	-- Recoil: climb + consistent drift + random jitter, plus a visual camera jolt.
	-- Aiming controls it a bit better.
	local control = 1 - state.aimAlpha * 0.3
	state.recoilPitch =
		math.min(state.recoilPitch + math.rad(weapon.RecoilUp) * control, math.rad(weapon.RecoilMax))
	-- (negative yaw turns the camera right)
	local side = random:NextNumber(-1, 1) * weapon.RecoilSide + weapon.RecoilDrift
	state.recoilYaw -= math.rad(side) * control
	state.recoilRoll += math.rad(weapon.RecoilRoll) * (if random:NextNumber() < 0.5 then -1 else 1)

	if not weapon.Automatic then
		triggerHeld = false
	end
	updateAmmoHud()
end

local function update(dt: number)
	local character = getAliveCharacter()
	-- In the lobby the gun is put away (you're in third person, holding it on your body instead)
	if not character or state.inLobby then
		if viewmodel then
			viewmodel:SetVisible(false)
		end
		state.aiming = false
		state.aimAlpha = 0
		state.aimSensitivity = 1
		Hud.SetCrosshair(0, false)
		Hud.SetScoped(false)
		return
	end

	local uiOpen = state.devPanelOpen or state.mouseUnlocked or state.draftOpen
	local handsBusy = state.deploying or state.interacting or state.meleeing -- cover / plant / defuse / knife
	state.aiming = aimHeld and not reloading and not uiOpen and not handsBusy
	local aimStep = dt / weapon.AdsTime
	state.aimAlpha = math.clamp(state.aimAlpha + (if state.aiming then aimStep else -aimStep), 0, 1)
	state.adsFovScale = weapon.AdsFovScale

	-- Recoil recovers once you stop shooting (single-shot guns settle between shots)
	local now = os.clock()
	if now - state.lastShot > math.min(60 / weapon.RPM * 1.5, 0.15) then
		local recover = 1 - math.exp(-weapon.RecoilRecover * dt)
		state.recoilPitch -= state.recoilPitch * recover
		state.recoilYaw -= state.recoilYaw * recover
	end
	state.recoilRoll -= state.recoilRoll * (1 - math.exp(-18 * dt))

	-- Slower mouse while aimed in (especially scoped) for precise aiming (MouseUnlock applies it)
	state.aimSensitivity = 1 + (weapon.AdsSensitivity - 1) * state.aimAlpha

	currentSpread = computeSpread()

	-- Frozen during the pre-round countdown
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local frozen = root ~= nil and root.Anchored

	if triggerHeld and not frozen and not uiOpen and not handsBusy and not reloading and now >= nextFireTime then
		if ammo > 0 then
			fire(character)
		else
			reload()
		end
	end

	-- Scoped weapons swap the gun model for a scope overlay once fully aimed in
	local scoped = weapon.Scope and state.aimAlpha > 0.9
	Hud.SetScoped(scoped)
	if viewmodel then
		-- While deploying cover / knifing, those show their own hands instead
		viewmodel:SetVisible(not scoped and not handsBusy)
	end

	-- Crosshair gap in pixels for the current spread (shotguns show their pellet cone)
	local camera = Workspace.CurrentCamera
	local halfFov = math.rad(camera.FieldOfView / 2)
	local shownSpread = currentSpread + (if weapon.Pellets > 1 then weapon.PelletSpread else 0)
	local gap = math.tan(math.rad(shownSpread)) / math.tan(halfFov) * camera.ViewportSize.Y / 2
	Hud.SetCrosshair(gap, state.aimAlpha < 0.5)

	if viewmodel then
		viewmodel:Update(dt, camera.CFrame, {
			aimAlpha = state.aimAlpha,
			sprinting = state.sprinting,
			reloading = reloading,
			speed = state.speed,
			grounded = state.grounded,
		})
	end
end

function WeaponController.Refill()
	reloadToken += 1
	reloading = false
	if viewmodel then
		viewmodel:StopAnimation()
	end
	ammo = weapon.MagazineSize
	updateAmmoHud()
end

function WeaponController.Start()
	setWeapon(player:GetAttribute("Weapon") or "Rifle")
	player:GetAttributeChangedSignal("Weapon"):Connect(function()
		setWeapon(player:GetAttribute("Weapon") or "Rifle")
	end)
	player:GetAttributeChangedSignal("Ability"):Connect(updateLoadoutHud)
	player:GetAttributeChangedSignal("AbilityCharges"):Connect(updateLoadoutHud)

	ContextActionService:BindAction("Fire", function(_, inputState)
		triggerHeld = inputState == Enum.UserInputState.Begin
		return Enum.ContextActionResult.Pass
	end, false, Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2)

	ContextActionService:BindAction("Aim", function(_, inputState)
		aimHeld = inputState == Enum.UserInputState.Begin
		return Enum.ContextActionResult.Pass
	end, false, Enum.UserInputType.MouseButton2, Enum.KeyCode.ButtonL2)

	ContextActionService:BindAction("Reload", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			reload()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.R, Enum.KeyCode.ButtonX)

	player.CharacterAdded:Connect(function()
		WeaponController.Refill()
		triggerHeld, aimHeld = false, false
		state.recoilPitch, state.recoilYaw = 0, 0
		if viewmodel then
			viewmodel:PlayDraw() -- pull the gun out on spawn
		end
	end)

	-- Other players' shots: tracers, impacts and a 3D gunshot sound
	ShotFired.OnClientEvent:Connect(
		function(shooter: Player, origin: Vector3, endPositions: { Vector3 }, weaponName: string)
			if shooter == player then
				return
			end
			for _, endPosition in endPositions do
				Effects.Tracer(origin, endPosition)
				Effects.Impact(endPosition)
			end
			local shooterWeapon = Weapons[weaponName]
			if shooterWeapon then
				local volume = Sounds.Guns.OtherVolume * shooterWeapon.FireVolume
				Sound3D.Play(Sounds.Pick(shooterWeapon.FireSound), origin, {
					volume = volume,
					range = Sounds.GunshotRange,
					pitch = shooterWeapon.FirePitch * randomPitch(),
				})
				if shooterWeapon.TailSound then
					Sound3D.Play(Sounds.Pick(shooterWeapon.TailSound), origin, {
						volume = volume * 0.6,
						range = Sounds.GunshotRange,
						pitch = shooterWeapon.FirePitch,
					})
				end
			end
		end
	)

	-- Other players reloading nearby (a sound cue: they're vulnerable right now)
	ReloadStarted.OnClientEvent:Connect(function(reloader: Player, weaponName: string)
		local head = reloader.Character and reloader.Character:FindFirstChild("Head") :: BasePart?
		local reloaderWeapon = Weapons[weaponName]
		if reloader == player or not head or not reloaderWeapon then
			return
		end
		Sound3D.Play(Sounds.Pick(reloaderWeapon.ReloadSound), head.Position, {
			volume = Sounds.Guns.ReloadVolume,
			range = Sounds.Guns.ReloadRange,
		})
	end)

	HitConfirmed.OnClientEvent:Connect(function(_damage: number, _headshot: boolean, killed: boolean)
		if killed then
			Hud.HitMarker("kill")
		end
	end)

	RunService:BindToRenderStep("Weapon", Enum.RenderPriority.Camera.Value + 3, update)
end

return WeaponController
