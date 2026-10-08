-- Your gun: firing, aiming down sights, recoil, spread, reloading.
-- Shots are raycast here for instant feedback, then sent to the server, which
-- double-checks them and applies the damage.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

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

-- Random direction inside a cone of `spreadDegrees` around the camera's aim
local function spreadDirection(cameraCFrame: CFrame, spreadDegrees: number): Vector3
	local spin = random:NextNumber(0, math.pi * 2)
	local tilt = math.rad(spreadDegrees) * math.sqrt(random:NextNumber())
	return (cameraCFrame * CFrame.Angles(0, 0, spin) * CFrame.Angles(tilt, 0, 0)).LookVector
end

local function updateAmmoHud()
	Hud.SetAmmo(ammo, weapon.MagazineSize, reloading)
end

local function reload()
	if reloading or ammo >= weapon.MagazineSize or not getAliveCharacter() then
		return
	end
	reloading = true
	reloadToken += 1
	local token = reloadToken
	ReloadRemote:FireServer()
	Effects.Sound(weapon.ReloadSound)
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
	local direction = spreadDirection(camera.CFrame, currentSpread)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local result = Workspace:Raycast(origin, direction * weapon.Range, params)

	local endPosition = if result then result.Position else origin + direction * weapon.Range
	local hitPart = if result then result.Instance else nil
	FireRemote:FireServer(origin, direction, hitPart, endPosition)

	-- Instant feedback (server confirms damage separately)
	if viewmodel then
		Effects.Tracer(viewmodel:GetMuzzlePosition(), endPosition)
		viewmodel:Kick(weapon.ViewKick)
	end
	Effects.Sound(weapon.FireSound)
	if result then
		local humanoid = findHumanoid(result.Instance)
		if humanoid and humanoid.Health > 0 then
			Hud.HitMarker(if result.Instance.Name == "Head" then "head" else "body")
		else
			Effects.Impact(result.Position, result.Normal)
		end
	end

	-- Recoil: aiming controls it a bit better
	local control = 1 - state.aimAlpha * 0.3
	state.recoilPitch =
		math.min(state.recoilPitch + math.rad(weapon.RecoilUp) * control, math.rad(weapon.RecoilMax))
	state.recoilYaw += math.rad(random:NextNumber(-1, 1) * weapon.RecoilSide) * control

	if not weapon.Automatic then
		triggerHeld = false
	end
	updateAmmoHud()
end

local function update(dt: number)
	local character = getAliveCharacter()
	if viewmodel then
		viewmodel:SetVisible(character ~= nil)
	end
	if not character then
		state.aiming = false
		state.aimAlpha = 0
		Hud.SetCrosshair(0, false)
		return
	end

	state.aiming = aimHeld and not reloading and not state.devPanelOpen and not state.mouseUnlocked
	local aimStep = dt / weapon.AdsTime
	state.aimAlpha = math.clamp(state.aimAlpha + (if state.aiming then aimStep else -aimStep), 0, 1)
	state.adsFovScale = weapon.AdsFovScale

	-- Recoil recovers once you stop shooting
	local now = os.clock()
	if now - state.lastShot > 60 / weapon.RPM * 1.5 then
		local recover = 1 - math.exp(-weapon.RecoilRecover * dt)
		state.recoilPitch -= state.recoilPitch * recover
		state.recoilYaw -= state.recoilYaw * recover
	end

	currentSpread = computeSpread()

	-- Frozen during the pre-round countdown
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local frozen = root ~= nil and root.Anchored

	local uiOpen = state.devPanelOpen or state.mouseUnlocked
	if triggerHeld and not frozen and not uiOpen and not reloading and now >= nextFireTime then
		if ammo > 0 then
			fire(character)
		else
			reload()
		end
	end

	-- Crosshair gap in pixels for the current spread
	local camera = Workspace.CurrentCamera
	local halfFov = math.rad(camera.FieldOfView / 2)
	local gap = math.tan(math.rad(currentSpread)) / math.tan(halfFov) * camera.ViewportSize.Y / 2
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
	ammo = weapon.MagazineSize
	updateAmmoHud()
end

function WeaponController.Start()
	viewmodel = Viewmodel.new()

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
	end)

	-- Other players' shots: tracer, impact and 3D gunshot sound
	ShotFired.OnClientEvent:Connect(function(shooter: Player, origin: Vector3, endPosition: Vector3, weaponName: string)
		if shooter == player then
			return
		end
		local shooterWeapon = Weapons[weaponName]
		Effects.Tracer(origin, endPosition)
		Effects.Impact(endPosition)
		if shooterWeapon then
			Sound3D.Play(shooterWeapon.FireSound, origin, { volume = 1, range = Sounds.GunshotRange })
		end
	end)

	HitConfirmed.OnClientEvent:Connect(function(_damage: number, _headshot: boolean, killed: boolean)
		if killed then
			Hud.HitMarker("kill")
		end
	end)

	updateAmmoHud()
	RunService:BindToRenderStep("Weapon", Enum.RenderPriority.Camera.Value + 3, update)
end

return WeaponController
