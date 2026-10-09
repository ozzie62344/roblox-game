-- The gun you see in first person: a detailed gun model (GunModels) held in gloved hands.
-- Follows the camera with hip / aim / sprint / reload poses, walk bob and shot kick.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Weapons = require(ReplicatedStorage.Shared.Weapons)
local GunModels = require(script.Parent.GunModels)

local Viewmodel = {}
Viewmodel.__index = Viewmodel

-- Hip pose: the sight sits this far right / down / further out than when aimed in, turned a
-- little so the muzzle points in toward the crosshair
local HIP_SHIFT = Vector3.new(0.68, -0.23, -0.5)
local HIP_TILT = CFrame.Angles(math.rad(-1), math.rad(9), math.rad(4))
local DEFAULT_EYE_RELIEF = 0.7 -- studs from your eye to the sight when aimed in (guns set their own)
-- The camera doesn't draw anything closer than its near clipping plane. The guns' eye reliefs
-- are tuned for a plane 0.1 studs out, but Camera.NearPlaneZ can be up to 0.5 studs on some
-- platforms, which would cut away the sight and hands when aimed.
local TUNED_NEAR_PLANE = 0.1
-- Sprint: muzzle swung down and to the left. Reload: gun lowered and rolled so the magazine
-- well faces you.
local SPRINT_POSE = CFrame.new(0, -0.06, 0.05) * CFrame.Angles(math.rad(-25), math.rad(35), math.rad(10))
local RELOAD_POSE = CFrame.new(-0.12, -0.12, 0.05) * CFrame.Angles(math.rad(18), math.rad(12), math.rad(-32))

local SLEEVE_COLOR = Color3.fromRGB(62, 68, 56)
local GLOVE_COLOR = Color3.fromRGB(28, 28, 30)
-- Shared with DeployArms so both sets of arms match
Viewmodel.SleeveColor = SLEEVE_COLOR
Viewmodel.GloveColor = GLOVE_COLOR

local SLEEVE = GunModels.Finish(SLEEVE_COLOR, Enum.Material.Fabric)
local SLEEVE_HEM = GunModels.Finish(SLEEVE_COLOR:Lerp(Color3.new(0, 0, 0), 0.2), Enum.Material.Fabric)
local GLOVE = GunModels.Finish(GLOVE_COLOR, Enum.Material.Leather)
local GLOVE_CUFF = GunModels.Finish(Color3.fromRGB(36, 36, 38), Enum.Material.Fabric)
local KNUCKLE_PAD = GunModels.Finish(Color3.fromRGB(44, 44, 47), Enum.Material.Rubber)
local WATCH_BAND = GunModels.Finish(Color3.fromRGB(24, 24, 25), Enum.Material.Rubber)
local WATCH_CASE = GunModels.Finish(Color3.fromRGB(60, 62, 64), Enum.Material.Metal)
local WATCH_GLASS = GunModels.Finish(Color3.fromRGB(30, 60, 50), Enum.Material.Glass, 0.2, 0.3)
local FLASH = GunModels.Finish(Color3.fromRGB(255, 196, 110), Enum.Material.Neon, 1)

-- Hands
local PALM_LENGTH = 0.3 -- wrist to knuckles
local PALM_WIDTH = 0.3
local PALM_THICKNESS = 0.105
-- Each finger: { offset across the palm (+ = index finger side), length scale, thickness }
local FINGERS = {
	{ 0.105, 1, 0.068 },
	{ 0.035, 1.07, 0.07 },
	{ -0.035, 1, 0.067 },
	{ -0.103, 0.82, 0.06 },
}
local FINGER_BONES = { 0.1, 0.11, 0.09 } -- length of each finger segment, knuckle to tip

-- Arms: the forearm partly follows the hand and partly heads back toward the body (down and
-- behind the camera, so the elbows and shoulders stay off screen)
local FOREARM_LENGTH = 1.15
local UPPER_ARM_LENGTH = 1.2
local WRIST_FOLLOW = 0.3 -- 0 = straight toward the body, 1 = straight in line with the hand (grips can override)
local FOREARM_DIRECTION = {
	Right = Vector3.new(0.25, -0.75, 1).Unit,
	Left = Vector3.new(-0.4, -1.1, 0.55).Unit,
}
local UPPER_ARM_DIRECTION = {
	Right = Vector3.new(0.15, 0.3, 1).Unit,
	Left = Vector3.new(0.45, 0.25, 1).Unit,
}

local random = Random.new()

local function numberAttribute(instance: Instance, name: string, default: number): number
	local value = instance:GetAttribute(name)
	if typeof(value) == "number" then
		return value
	end
	return default
end

-- A finger / thumb segment, stretched a little past both joints so the bends look solid
local function bone(arms: Model, name: string, a: Vector3, b: Vector3, thickness: number)
	local direction = (b - a).Unit
	GunModels.Rod(arms, name, a - direction * thickness * 0.35, b + direction * thickness * 0.35, thickness, GLOVE)
end

-- Builds a gloved hand wrapped around a grip attachment (see GunModels for what the grip's
-- axes and attributes mean). Returns the wrist position, the direction from the wrist to the
-- knuckles, and the direction the back of the hand faces.
local function buildHand(arms: Model, side: string, grip: Attachment, trigger: Attachment?): (Vector3, Vector3, Vector3)
	local frame = grip.WorldCFrame
	local mirror = if side == "Left" then -1 else 1
	local radiusX = numberAttribute(grip, "RadiusX", 0.06)
	local radiusZ = numberAttribute(grip, "RadiusZ", 0.06)
	local palmAngle = math.rad(numberAttribute(grip, "PalmAngle", 20))

	-- Hand space: x = toward the back of the hand, y = along the handle toward the thumb,
	-- z = away from the fingers. The left hand is the mirror image.
	local function point(x: number, y: number, z: number): Vector3
		return frame:PointToWorldSpace(Vector3.new(x * mirror, y, z))
	end
	local function direction(x: number, y: number, z: number): Vector3
		return frame:VectorToWorldSpace(Vector3.new(x * mirror, y, z))
	end
	-- A point on a ring around the handle: angle 0 = palm side, growing the way fingers curl
	local function around(angle: number, pad: number, height: number): Vector3
		return point((radiusX + pad) * math.cos(angle), height, -(radiusZ + pad) * math.sin(angle))
	end

	-- Palm: a slab against the side of the handle, turned a little toward the thumb, with
	-- rounded knuckles and heel so it doesn't look like a box
	local palmSpot = math.rad(-15)
	local palmCenter = around(palmSpot, PALM_THICKNESS / 2, -0.005)
	local outward = direction(math.cos(palmSpot), 0, -math.sin(palmSpot))
	local curl = direction(-math.sin(palmSpot), 0, -math.cos(palmSpot))
	local handle = direction(0, 1, 0)
	local forward = (curl * math.cos(palmAngle) + handle * math.sin(palmAngle)).Unit
	local across = handle - forward * handle:Dot(forward)
	across = (across - outward * across:Dot(outward)).Unit -- toward the index finger
	local palmCFrame = CFrame.lookAt(palmCenter, palmCenter + forward, outward)
	local palmSize = Vector3.new(PALM_WIDTH - 0.03, PALM_THICKNESS - 0.012, PALM_LENGTH - 0.09)
	GunModels.MakePart(arms, `{side}Palm`, palmSize, palmCFrame, GLOVE)
	local knuckles = palmCenter + forward * (PALM_LENGTH / 2 - 0.05)
	GunModels.Rod(arms, `{side}Knuckles`, knuckles - across * 0.135, knuckles + across * 0.135, 0.1, GLOVE)
	local heel = palmCenter - forward * (PALM_LENGTH / 2 - 0.05)
	GunModels.Rod(arms, `{side}Heel`, heel - across * 0.12, heel + across * 0.12, 0.1, GLOVE)
	local padCenter = knuckles + outward * 0.046 - forward * 0.012
	local padCFrame = CFrame.lookAt(padCenter, padCenter + forward, outward)
	GunModels.MakePart(arms, `{side}KnucklePad`, Vector3.new(0.25, 0.02, 0.065), padCFrame, KNUCKLE_PAD)

	-- Fingers curl around the handle; the index finger goes to the trigger instead if asked
	for index, finger in FINGERS do
		local spread, scale, thickness = finger[1], finger[2], finger[3]
		local knuckle = palmCenter + forward * (PALM_LENGTH / 2 - thickness * 0.4) + across * spread
		local name = `{side}Finger{index}`
		if index == 1 and trigger then
			local tip = trigger.WorldPosition
			local middle = knuckle:Lerp(tip, 0.55) + outward * 0.03
			bone(arms, name, knuckle, middle, thickness)
			bone(arms, name, middle, tip, thickness * 0.92)
		else
			local knuckleLocal = frame:PointToObjectSpace(knuckle)
			local pad = thickness / 2
			local angle = math.atan2(-knuckleLocal.Z / (radiusZ + pad), knuckleLocal.X * mirror / (radiusX + pad))
			local radius = (radiusX + radiusZ) / 2 + pad
			local joint = knuckle
			for segment, length in FINGER_BONES do
				angle += length * scale / radius
				local nextJoint = around(angle, pad, knuckleLocal.Y)
				bone(arms, name, joint, nextJoint, thickness * (1 - segment * 0.05))
				joint = nextJoint
			end
		end
	end

	-- Thumb: from the base of the palm around the back of the handle
	local thumbAngle = math.rad(numberAttribute(grip, "ThumbAngle", 150))
	local thumbLift = numberAttribute(grip, "ThumbLift", 0.06)
	local thumbBase = palmCenter + across * 0.12 - forward * 0.07
	local baseHeight = frame:PointToObjectSpace(thumbBase).Y
	local thumbMiddle = around(-(math.rad(35) + thumbAngle) / 2, 0.04, baseHeight + thumbLift * 0.5)
	local thumbTip = around(-thumbAngle, 0.035, baseHeight + thumbLift)
	bone(arms, `{side}Thumb`, thumbBase, thumbMiddle, 0.085)
	bone(arms, `{side}Thumb`, thumbMiddle, thumbTip, 0.07)

	return palmCenter - forward * (PALM_LENGTH / 2), forward, outward
end

-- Glove cuff, sleeve, elbow and upper arm running from the wrist back toward the body
local function buildArm(
	arms: Model,
	side: string,
	grip: Attachment,
	wrist: Vector3,
	handForward: Vector3,
	handOutward: Vector3
)
	local follow = numberAttribute(grip, "ForearmFollow", WRIST_FOLLOW)
	-- Guns can pick their own direction toward the body (a Vector3 attribute on the grip)
	local towardBody = FOREARM_DIRECTION[side]
	local customDirection = grip:GetAttribute("ForearmDirection")
	if typeof(customDirection) == "Vector3" then
		towardBody = customDirection.Unit
	end
	local forearm = (-handForward * follow + towardBody * (1 - follow)).Unit
	local elbow = wrist + forearm * FOREARM_LENGTH
	local shoulder = elbow + UPPER_ARM_DIRECTION[side] * UPPER_ARM_LENGTH
	local function along(distance: number): Vector3
		return wrist + forearm * distance
	end

	GunModels.Ball(arms, `{side}Wrist`, 0.2, wrist, GLOVE)
	GunModels.Rod(arms, `{side}GloveCuff`, along(-0.02), along(0.17), 0.235, GLOVE_CUFF)
	GunModels.Rod(arms, `{side}SleeveHem`, along(0.14), along(0.22), 0.3, SLEEVE_HEM)
	GunModels.Rod(arms, `{side}Forearm`, along(0.21), along(0.65), 0.285, SLEEVE)
	GunModels.Rod(arms, `{side}ForearmUpper`, along(0.62), elbow, 0.33, SLEEVE)
	GunModels.Ball(arms, `{side}Elbow`, 0.34, elbow, SLEEVE)
	GunModels.Rod(arms, `{side}UpperArm`, elbow, shoulder, 0.37, SLEEVE)

	if side == "Left" then
		-- Wristwatch over the glove cuff, face on the inside of the wrist where you can see it
		local inside = -(handOutward - forearm * handOutward:Dot(forearm)).Unit
		GunModels.Rod(arms, "WatchBand", along(0.06), along(0.12), 0.25, WATCH_BAND)
		local face = along(0.09) + inside * 0.122
		GunModels.Rod(arms, "WatchCase", face - inside * 0.012, face + inside * 0.018, 0.1, WATCH_CASE)
		GunModels.Rod(arms, "WatchGlass", face + inside * 0.018, face + inside * 0.024, 0.078, WATCH_GLASS)
	end
end

-- Muzzle flash: a glowing core, a short plume and two crossed petals (hidden until a shot)
local function buildFlash(model: Model, muzzle: Attachment): { BasePart }
	local at = muzzle.WorldCFrame
	local petal = Vector3.new(0.32, 0.04, 0.012)
	local petalCFrame = at * CFrame.new(0, 0, -0.04)
	return {
		GunModels.Ball(model, "FlashCore", 0.13, (at * CFrame.new(0, 0, -0.06)).Position, FLASH),
		GunModels.MakePart(model, "FlashPlume", Vector3.new(0.06, 0.06, 0.34), at * CFrame.new(0, 0, -0.18), FLASH),
		GunModels.MakePart(model, "FlashPetal", petal, petalCFrame, FLASH),
		GunModels.MakePart(model, "FlashPetal", petal, petalCFrame * CFrame.Angles(0, 0, math.pi / 2), FLASH),
	}
end

-- Builds the gun for this weapon (GunModels) plus the arms holding it
function Viewmodel.new(weapon: Weapons.Weapon)
	local model = GunModels.Build(weapon.Name, weapon.Look.Color)
	model.Name = "Viewmodel"
	local body = model.PrimaryPart :: Part

	-- Arms: each hand goes on its grip attachment
	local arms = Instance.new("Model")
	arms.Name = "Arms"
	arms.Parent = model
	local trigger = body:FindFirstChild("Trigger") :: Attachment?
	for _, side in { "Right", "Left" } do
		local grip = body:FindFirstChild(`{side}Grip`) :: Attachment?
		if grip then
			local useTrigger = if side == "Right" and grip:GetAttribute("TriggerFinger") then trigger else nil
			local wrist, forward, outward = buildHand(arms, side, grip, useTrigger)
			buildArm(arms, side, grip, wrist, forward, outward)
		end
	end

	-- Aiming in: place the gun so its AimPoint sits straight ahead of your eye, eyeRelief studs
	-- out, with the sight line pointing where the camera points. AimPoint is relative to Body
	-- (the model's pivot), so we want  camera * aimOffset * aimPoint = camera * (0, 0, -eyeRelief),
	-- which gives  aimOffset = (0, 0, -eyeRelief) * inverse(aimPoint).
	local aimPoint = body:FindFirstChild("AimPoint") :: Attachment?
	local aimLocal = CFrame.new(0, 0.2, 0)
	local eyeRelief = DEFAULT_EYE_RELIEF
	local hipShift = HIP_SHIFT
	if aimPoint then
		aimLocal = aimPoint.CFrame
		eyeRelief = numberAttribute(aimPoint, "EyeRelief", DEFAULT_EYE_RELIEF)
		if typeof(aimPoint:GetAttribute("HipShift")) == "Vector3" then
			hipShift = aimPoint:GetAttribute("HipShift")
		end
	end
	-- On platforms that clip further out, push the whole gun out by the difference so everything
	-- is just as far past the near plane as it is on a 0.1-stud one (the gun looks a bit smaller)
	eyeRelief += math.max(0, -Workspace.CurrentCamera.NearPlaneZ - TUNED_NEAR_PLANE)
	local aimOffset = CFrame.new(0, 0, -eyeRelief) * aimLocal:Inverse()
	-- Hip fire: the same, but with the sight shifted right / down / out and tilted slightly
	local hipOffset = CFrame.new(hipShift + Vector3.new(0, 0, -eyeRelief)) * HIP_TILT * aimLocal:Inverse()

	local muzzle = body:FindFirstChild("Muzzle") :: Attachment
	local flashLight = Instance.new("PointLight")
	flashLight.Color = Color3.fromRGB(255, 200, 120)
	flashLight.Range = 12
	flashLight.Brightness = 3
	flashLight.Enabled = false
	flashLight.Parent = muzzle
	local flashParts = buildFlash(model, muzzle)

	model:PivotTo(Workspace.CurrentCamera.CFrame * hipOffset)
	model.Parent = Workspace.CurrentCamera

	local self = setmetatable({
		model = model,
		muzzle = muzzle,
		flashLight = flashLight,
		flashParts = flashParts,
		flashId = 0,
		aimOffset = aimOffset,
		hipOffset = hipOffset,
		kick = 0,
		bobTime = 0,
		sprintAlpha = 0,
		reloadAlpha = 0,
	}, Viewmodel)
	return self
end

function Viewmodel:GetMuzzlePosition(): Vector3
	return self.muzzle.WorldPosition
end

function Viewmodel:Kick(amount: number)
	self.kick = math.min(self.kick + amount, amount * 3)

	-- Muzzle flash for a moment (each shot gets a slightly different look)
	self.flashLight.Enabled = true
	for _, part in self.flashParts do
		part.Transparency = random:NextNumber(0, 0.35)
	end
	self.flashId += 1
	local flashId = self.flashId
	local function hideFlash()
		if self.flashId == flashId then
			self.flashLight.Enabled = false
			for _, part in self.flashParts do
				part.Transparency = 1
			end
		end
	end
	task.delay(0.045, hideFlash)
end

function Viewmodel:SetVisible(visible: boolean)
	local parent = if visible then Workspace.CurrentCamera else nil
	if self.model.Parent ~= parent then
		self.model.Parent = parent
	end
end

type Pose = {
	aimAlpha: number,
	sprinting: boolean,
	reloading: boolean,
	speed: number,
	grounded: boolean,
}

function Viewmodel:Update(dt: number, cameraCFrame: CFrame, pose: Pose)
	local function approach(current: number, target: number, sharpness: number): number
		return current + (target - current) * (1 - math.exp(-sharpness * dt))
	end

	self.sprintAlpha = approach(self.sprintAlpha, if pose.sprinting then 1 else 0, 10)
	self.reloadAlpha = approach(self.reloadAlpha, if pose.reloading then 1 else 0, 10)
	self.kick = approach(self.kick, 0, 25)

	-- Walk bob, mostly gone while aiming
	local moving = if pose.grounded then math.clamp(pose.speed / 28, 0, 1) else 0
	self.bobTime += dt * (6 + 6 * moving)
	local bobAmount = 0.05 * moving * (1 - pose.aimAlpha * 0.85)
	local bob = CFrame.new(math.sin(self.bobTime) * bobAmount, math.abs(math.cos(self.bobTime)) * bobAmount, 0)

	-- Ease the hip -> aim move so the sight glides in and settles exactly on center
	local aim = pose.aimAlpha * pose.aimAlpha * (3 - 2 * pose.aimAlpha)
	local offset = self.hipOffset:Lerp(self.aimOffset, aim)
	local action = CFrame.new():Lerp(SPRINT_POSE, self.sprintAlpha):Lerp(RELOAD_POSE, self.reloadAlpha)
	local kick = CFrame.new(0, 0, self.kick) * CFrame.Angles(self.kick * 0.15, 0, 0)

	self.model:PivotTo(cameraCFrame * offset * bob * action * kick)
end

function Viewmodel:Destroy()
	self.model:Destroy()
end

return Viewmodel
