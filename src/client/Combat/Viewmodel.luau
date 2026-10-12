-- The gun you see in first person: a detailed gun model (GunModels) held in gloved hands, with
-- arms that come from your shoulders (below and behind your eyes) and bend at the elbow to reach
-- the hands. Follows the camera with hip / aim / sprint poses, walk bob and shot kick, and plays
-- animations (ReloadAnimations): per-gun reloads and pulling the gun out.
--
-- What moves on its own:
--   • the gun
--   • its moving pieces ("groups": Magazine, Bolt, Pump, Cylinder, ChargingHandle, CockingHandle,
--     FeedCover, Slide, plus a loose shotgun shell and a revolver speedloader that only show up
--     during reloads)
--   • each hand (normally on its grip, but animations can move it anywhere)
--   • the arms, worked out every frame from shoulder → elbow → wrist ("two-bone IK")
-- Every part is anchored and repositioned each frame in one batch (Workspace:BulkMoveTo).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Skins = require(ReplicatedStorage.Shared.Skins)
local Weapons = require(ReplicatedStorage.Shared.Weapons)
local GunModels = require(script.Parent.GunModels)
local ReloadAnimations = require(script.Parent.ReloadAnimations)

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
-- Sprint: muzzle swung down and to the left
local SPRINT_POSE = CFrame.new(0, -0.06, 0.05) * CFrame.Angles(math.rad(-25), math.rad(35), math.rad(10))
-- Up against a wall: gun pulled back toward you and the muzzle tipped up, so it doesn't poke
-- through. How far depends on how much of the gun would be inside the wall.
local TUCK_POSE = CFrame.new(0.04, -0.06, 0.45) * CFrame.Angles(math.rad(55), math.rad(-12), math.rad(-8))
-- Crawling: gun pulled in low and canted, rocking with each pull forward
local CRAWL_POSE = CFrame.new(0.05, -0.14, 0.12) * CFrame.Angles(math.rad(-12), math.rad(18), math.rad(28))

local SLEEVE_COLOR = Color3.fromRGB(62, 68, 56)
local GLOVE_COLOR = Color3.fromRGB(28, 28, 30)
-- Shared with HandsAnimator / the knife so all hands match
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
local SHELL_HULL = GunModels.Finish(Color3.fromRGB(170, 30, 30), Enum.Material.Plastic)
local BRASS = GunModels.Finish(Color3.fromRGB(196, 156, 74), Enum.Material.Metal, nil, 0.1)
local LOADER = GunModels.Finish(Color3.fromRGB(30, 30, 32), Enum.Material.Plastic)

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

-- Arms: fixed-length bones from a shoulder (in camera space: below and behind your eyes)
local FOREARM_LENGTH = 1.15
local UPPER_ARM_LENGTH = 1.25
local SHOULDER = {
	Right = Vector3.new(0.72, -1.05, 0.4),
	Left = Vector3.new(-0.72, -1.05, 0.4),
}
-- Which way each elbow bends (camera space): out to the side and down
local ELBOW_POLE = {
	Right = Vector3.new(0.9, -1.1, 0.3),
	Left = Vector3.new(-0.9, -1.1, 0.3),
}
-- Cylinder parts lie along their X axis; this turns X to point down -Z (along a bone)
local ALONG_Z = CFrame.Angles(0, math.rad(90), 0)

-- Moving pieces of a gun, recognised by part name (see GunModels)
local function memberOf(groupName: string, partName: string): boolean
	if groupName == "Magazine" then
		return string.match(partName, "^Mag%d+$") ~= nil or partName == "MagBase" or partName == "Magazine"
	elseif groupName == "Bolt" then
		return partName == "BoltHandle" or partName == "BoltKnob" or partName == "Bolt" or partName == "BoltBody"
	elseif groupName == "Pump" then
		return partName == "Pump" or partName == "PumpGroove"
	elseif groupName == "Cylinder" then
		return partName == "Cylinder" or partName == "CylinderFlute"
	elseif groupName == "ChargingHandle" then
		return partName == "ChargingHandle" or partName == "ChargingLatch"
	elseif groupName == "CockingHandle" then
		return partName == "CockingHandle" or partName == "CockingKnob"
	elseif groupName == "FeedCover" or groupName == "Slide" then
		return string.sub(partName, 1, #groupName) == groupName -- the LMG's cover (with its sight), the pistol's slide
	end
	return false
end
local GROUP_NAMES = { "Magazine", "Bolt", "Pump", "Cylinder", "ChargingHandle", "CockingHandle", "FeedCover", "Slide" }
-- Named gun parts whose positions animations use as targets
local POINT_NAMES = { "BoltCatch", "BoltShroud", "BoltKnob", "Shell", "CylinderLatch", "ChargingHandle", "Magwell" }

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
	local frame = grip.CFrame -- gun space (Body sits at the origin while the viewmodel is built)
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
			local tip = trigger.CFrame.Position
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

-- Muzzle flash: a glowing core, a short plume and two crossed petals (hidden until a shot)
local function buildFlash(model: Model, muzzle: Attachment): { BasePart }
	local at = muzzle.CFrame -- gun space
	local petal = Vector3.new(0.32, 0.04, 0.012)
	local petalCFrame = at * CFrame.new(0, 0, -0.04)
	return {
		GunModels.Ball(model, "FlashCore", 0.13, (at * CFrame.new(0, 0, -0.06)).Position, FLASH),
		GunModels.MakePart(model, "FlashPlume", Vector3.new(0.06, 0.06, 0.34), at * CFrame.new(0, 0, -0.18), FLASH),
		GunModels.MakePart(model, "FlashPetal", petal, petalCFrame, FLASH),
		GunModels.MakePart(model, "FlashPetal", petal, petalCFrame * CFrame.Angles(0, 0, math.pi / 2), FLASH),
	}
end

-- A cylinder bone segment, positioned each frame (its length never changes)
local function segment(parent: Instance, name: string, length: number, diameter: number, look: GunModels.Finish): Part
	return GunModels.MakePart(parent, name, Vector3.new(length, diameter, diameter), CFrame.new(), look, Enum.PartType.Cylinder)
end

local function rodCFrame(a: Vector3, b: Vector3): CFrame
	return CFrame.lookAt((a + b) / 2, b) * ALONG_Z
end

-- Two-bone IK: from `a`, bones of length l1 and l2, reach for `target`; the middle joint bends
-- toward `pole`. Returns the middle joint and the end point.
local function solveTwoBone(a: Vector3, target: Vector3, l1: number, l2: number, pole: Vector3): (Vector3, Vector3)
	local offset = target - a
	local distance = math.clamp(offset.Magnitude, math.abs(l1 - l2) + 0.01, (l1 + l2) * 0.999)
	local dir = if offset.Magnitude > 1e-4 then offset.Unit else Vector3.new(0, -1, 0)
	local along = (l1 * l1 - l2 * l2 + distance * distance) / (2 * distance)
	local bowOut = math.sqrt(math.max(l1 * l1 - along * along, 0))
	local bend = pole - dir * pole:Dot(dir)
	bend = if bend.Magnitude > 1e-4 then bend.Unit else Vector3.zAxis
	return a + dir * along + bend * bowOut, a + dir * distance
end

local EASES: { [string]: (number) -> number } = {
	linear = function(x)
		return x
	end,
	["in"] = function(x)
		return x * x
	end,
	out = function(x)
		return 1 - (1 - x) * (1 - x)
	end,
	inOut = function(x)
		return x * x * (3 - 2 * x)
	end,
	-- Overshoots a little and settles: snappy seats and slaps
	back = function(x)
		local c = 1.6
		return 1 + (c + 1) * (x - 1) ^ 3 + c * (x - 1) ^ 2
	end,
}

type Group = {
	parts: { BasePart },
	offsets: { CFrame },
	rest: CFrame, -- where the piece normally is (gun space, gun axes)
	size: Vector3,
	transparency: { number },
	extra: boolean, -- only visible during animations (loose shell, speedloader)
	hidden: boolean,
}
type Hand = { parts: { BasePart }, offsets: { CFrame }, rest: CFrame, wrist: Vector3, outward: Vector3 }
type Arm = { [string]: Part }

-- Splits the gun's moving pieces out of the main part list
local function collectGroups(model: Model, body: BasePart): ({ [string]: Group }, { [BasePart]: boolean })
	local groups: { [string]: Group } = {}
	local taken: { [BasePart]: boolean } = {}
	for _, groupName in GROUP_NAMES do
		local members = {}
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") and memberOf(groupName, part.Name) then
				table.insert(members, part)
			end
		end
		if #members == 0 then
			continue
		end
		-- Rest frame: the middle of the pieces, lined up with the gun's axes
		local min, max = Vector3.one * math.huge, -Vector3.one * math.huge
		for _, part in members do
			local cf = body.CFrame:ToObjectSpace(part.CFrame)
			local half = part.Size / 2
			local r = cf.Rotation
			local extent = Vector3.new(
				math.abs(r.XVector.X) * half.X + math.abs(r.YVector.X) * half.Y + math.abs(r.ZVector.X) * half.Z,
				math.abs(r.XVector.Y) * half.X + math.abs(r.YVector.Y) * half.Y + math.abs(r.ZVector.Y) * half.Z,
				math.abs(r.XVector.Z) * half.X + math.abs(r.YVector.Z) * half.Y + math.abs(r.ZVector.Z) * half.Z
			)
			min = min:Min(cf.Position - extent)
			max = max:Max(cf.Position + extent)
		end
		local rest = CFrame.new((min + max) / 2)
		local group: Group = { parts = {}, offsets = {}, rest = rest, size = max - min, transparency = {}, extra = false, hidden = false }
		for _, part in members do
			table.insert(group.parts, part)
			table.insert(group.offsets, rest:ToObjectSpace(body.CFrame:ToObjectSpace(part.CFrame)))
			table.insert(group.transparency, part.Transparency)
			taken[part] = true
		end
		groups[groupName] = group
	end
	return groups, taken
end

-- Extra pieces that only appear during reloads
local function extraGroup(model: Model, name: string, rest: CFrame, build: (parent: Model) -> ()): Group
	local holder = Instance.new("Model")
	holder.Name = name
	holder.Parent = model
	build(holder)
	local group: Group = { parts = {}, offsets = {}, rest = rest, size = Vector3.one * 0.2, transparency = {}, extra = true, hidden = true }
	for _, part in holder:GetDescendants() do
		if part:IsA("BasePart") then
			table.insert(group.parts, part)
			table.insert(group.offsets, rest:ToObjectSpace(part.CFrame))
			table.insert(group.transparency, part.Transparency)
			part.Transparency = 1
		end
	end
	return group
end

local function buildArm(parent: Model, side: string): Arm
	local arm: Arm = {
		wristBall = GunModels.Ball(parent, `{side}Wrist`, 0.2, Vector3.zero, GLOVE),
		cuff = segment(parent, `{side}GloveCuff`, 0.19, 0.235, GLOVE_CUFF),
		hem = segment(parent, `{side}SleeveHem`, 0.08, 0.3, SLEEVE_HEM),
		forearm = segment(parent, `{side}Forearm`, 0.44, 0.285, SLEEVE),
		forearmUpper = segment(parent, `{side}ForearmUpper`, FOREARM_LENGTH - 0.62, 0.33, SLEEVE),
		elbow = GunModels.Ball(parent, `{side}Elbow`, 0.34, Vector3.zero, SLEEVE),
		upperArm = segment(parent, `{side}UpperArm`, UPPER_ARM_LENGTH, 0.37, SLEEVE),
	}
	if side == "Left" then
		-- Wristwatch over the glove cuff, face on the inside of the wrist where you can see it
		arm.watchBand = segment(parent, "WatchBand", 0.06, 0.25, WATCH_BAND)
		arm.watchCase = segment(parent, "WatchCase", 0.03, 0.1, WATCH_CASE)
		arm.watchGlass = segment(parent, "WatchGlass", 0.006, 0.078, WATCH_GLASS)
	end
	return arm
end

-- Builds the gun for this weapon (GunModels, in the given skin), its moving pieces, the hands and
-- the arms
function Viewmodel.new(weapon: Weapons.Weapon, skin: Skins.Skin?)
	local model = GunModels.Build(weapon.Name, weapon.Look.Color, skin)
	model.Name = "Viewmodel"
	local body = model.PrimaryPart :: Part

	-- Muzzle flash parts belong to the gun
	local muzzle = body:FindFirstChild("Muzzle") :: Attachment
	local flashLight = Instance.new("PointLight")
	flashLight.Color = Color3.fromRGB(255, 200, 120)
	flashLight.Range = 12
	flashLight.Brightness = 3
	flashLight.Enabled = false
	flashLight.Parent = muzzle
	local flashParts = buildFlash(model, muzzle)

	-- Positions of named parts that animations aim the hands at
	local points: { [string]: Vector3 } = {}
	for _, pointName in POINT_NAMES do
		local part = model:FindFirstChild(pointName, true)
		if part and part:IsA("BasePart") then
			points[pointName] = body.CFrame:PointToObjectSpace(part.CFrame.Position)
		end
	end

	-- Moving pieces, then everything else that rides with the gun
	local groups, taken = collectGroups(model, body)
	if weapon.Name == "Shotgun" then
		local at = CFrame.new(points.Shell or Vector3.new(-0.12, 0, 0.35))
		groups.LooseShell = extraGroup(model, "LooseShell", at, function(parent)
			GunModels.MakePart(parent, "Hull", Vector3.new(0.26, 0.085, 0.085), at * ALONG_Z, SHELL_HULL, Enum.PartType.Cylinder)
			GunModels.MakePart(parent, "Base", Vector3.new(0.06, 0.092, 0.092), at * CFrame.new(0, 0, 0.14) * ALONG_Z, BRASS, Enum.PartType.Cylinder)
		end)
	elseif weapon.Name == "Revolver" and groups.Cylinder then
		local cylinder = groups.Cylinder
		local ring = math.min(cylinder.size.X, cylinder.size.Y) * 0.3
		local at = cylinder.rest * CFrame.new(0, 0, cylinder.size.Z / 2 + 0.3)
		groups.Speedloader = extraGroup(model, "Speedloader", at, function(parent)
			GunModels.MakePart(parent, "Body", Vector3.new(0.06, ring * 2.4, ring * 2.4), at * ALONG_Z, LOADER, Enum.PartType.Cylinder)
			GunModels.MakePart(parent, "Knob", Vector3.new(0.1, 0.07, 0.07), at * CFrame.new(0, 0, 0.07) * ALONG_Z, LOADER, Enum.PartType.Cylinder)
			for i = 1, 6 do
				local angle = i * math.pi / 3
				local spot = at * CFrame.new(math.cos(angle) * ring, math.sin(angle) * ring, -0.08)
				GunModels.MakePart(parent, "Round", Vector3.new(0.14, 0.05, 0.05), spot * ALONG_Z, BRASS, Enum.PartType.Cylinder)
			end
		end)
	end
	for _, group in groups do
		for _, part in group.parts do
			taken[part] = true
		end
	end
	local gunParts, gunOffsets = {}, {}
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and not taken[part] then
			table.insert(gunParts, part)
			table.insert(gunOffsets, body.CFrame:ToObjectSpace(part.CFrame))
		end
	end

	-- Hands: built around their grips, then remembered relative to the grip so they can move
	local hands: { [string]: Hand } = {}
	local arms: { [string]: Arm } = {}
	local trigger = body:FindFirstChild("Trigger") :: Attachment?
	for _, side in { "Right", "Left" } do
		local grip = body:FindFirstChild(`{side}Grip`) :: Attachment?
		if not grip then
			continue
		end
		local handModel = Instance.new("Model")
		handModel.Name = `{side}Hand`
		handModel.Parent = model
		local useTrigger = if side == "Right" and grip:GetAttribute("TriggerFinger") then trigger else nil
		local wrist, _, outward = buildHand(handModel, side, grip, useTrigger)
		local rest = grip.CFrame -- grip frame in gun space (Body is at the origin while building)
		local hand: Hand = { parts = {}, offsets = {}, rest = rest, wrist = rest:PointToObjectSpace(wrist), outward = rest:VectorToObjectSpace(outward) }
		for _, part in handModel:GetDescendants() do
			if part:IsA("BasePart") then
				table.insert(hand.parts, part)
				table.insert(hand.offsets, rest:ToObjectSpace(part.CFrame))
			end
		end
		hands[side] = hand
		local armModel = Instance.new("Model")
		armModel.Name = `{side}Arm`
		armModel.Parent = model
		arms[side] = buildArm(armModel, side)
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

	model.Parent = Workspace.CurrentCamera

	local self = setmetatable({
		model = model,
		weaponName = weapon.Name,
		muzzle = muzzle,
		flashLight = flashLight,
		flashParts = flashParts,
		flashId = 0,
		aimOffset = aimOffset,
		hipOffset = hipOffset,
		-- How far in front of your eyes the muzzle reaches at the hip
		reach = -(hipOffset * muzzle.CFrame).Position.Z,
		gunParts = gunParts,
		gunOffsets = gunOffsets,
		groups = groups,
		hands = hands,
		arms = arms,
		points = points,
		kick = 0,
		bobTime = 0,
		sprintAlpha = 0,
		crawlAlpha = 0,
		tuckAlpha = 0,
		crawlTime = 0,
		-- Animation playing (reload / draw)
		clip = nil :: { any }?,
		clipStart = 0,
		clipDuration = 1,
		clipLastT = 0,
		OnAnimationEvent = nil :: ((string) -> ())?,
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

-- ── Animations ──────────────────────────────────────────────────────────────────

-- Fills in each keyframe with whatever it left out (carried over from the keyframe before)
local function completeKeyframes(keys: { any }): { any }
	local full = {}
	local gun, left, right = CFrame.new(), { "grip" }, { "grip" }
	local groups: { [string]: any } = {}
	for _, key in keys do
		gun = key.gun or gun
		left = key.left or left
		right = key.right or right
		local merged = table.clone(groups)
		for name, spec in key.groups or {} do
			merged[name] = spec
		end
		groups = merged
		table.insert(full, { t = key.t, ease = key.ease or "inOut", gun = gun, left = left, right = right, groups = groups, hide = key.hide or {}, events = key.events or {} })
	end
	return full
end

function Viewmodel:Play(keys: { any }, duration: number)
	self.clip = completeKeyframes(keys)
	self.clipStart = os.clock()
	self.clipDuration = math.max(duration, 0.05)
	self.clipLastT = -1
end

function Viewmodel:PlayReload(duration: number, empty: boolean, rounds: number)
	local groupInfo = {}
	for name, group in self.groups do
		groupInfo[name] = { rest = group.rest, size = group.size }
	end
	local info = {
		empty = empty,
		rounds = rounds,
		grips = {
			Left = if self.hands.Left then self.hands.Left.rest else CFrame.new(),
			Right = if self.hands.Right then self.hands.Right.rest else CFrame.new(),
		},
		groups = groupInfo,
		points = self.points,
	}
	self:Play(ReloadAnimations.Reload(self.weaponName, info), duration)
end

function Viewmodel:PlayDraw()
	self:Play(ReloadAnimations.Draw(), 0.45)
end

function Viewmodel:StopAnimation()
	self.clip = nil
end

-- Where everything is for one keyframe (world space)
function Viewmodel:_resolve(key: any, gunCF: CFrame, cameraCF: CFrame)
	local groupWorld: { [string]: CFrame } = {}
	local handWorld: { [string]: CFrame } = {}
	local busy: { [string]: boolean } = {}
	local getGroup: (string) -> CFrame
	local getHand: (string) -> CFrame

	getGroup = function(name)
		if groupWorld[name] then
			return groupWorld[name]
		end
		local group = self.groups[name]
		if not group then
			return gunCF
		end
		local spec = key.groups[name] or { "rest" }
		local result
		if busy[name] then
			result = gunCF * group.rest -- a loop (hand holds piece holds hand): fall back to rest
		else
			busy[name] = true
			if spec[1] == "gun" then
				result = gunCF * group.rest * spec[2]
			elseif spec[1] == "hand" then
				result = getHand(spec[2]) * spec[3]
			elseif spec[1] == "on" then
				result = getGroup(spec[2]) * spec[3]
			else
				result = gunCF * group.rest
			end
			busy[name] = nil
		end
		groupWorld[name] = result
		return result
	end

	getHand = function(side)
		if handWorld[side] then
			return handWorld[side]
		end
		local hand = self.hands[side]
		if not hand then
			return gunCF
		end
		local spec = (if side == "Left" then key.left else key.right) or { "grip" }
		local result
		local busyKey = "hand" .. side
		if busy[busyKey] then
			result = gunCF * hand.rest
		else
			busy[busyKey] = true
			if spec[1] == "gun" then
				result = gunCF * spec[2]
			elseif spec[1] == "camera" then
				result = cameraCF * spec[2]
			elseif spec[1] == "group" and self.groups[spec[2]] then
				local group = self.groups[spec[2]]
				result = getGroup(spec[2]) * (spec[3] or group.rest:Inverse() * hand.rest)
			else
				result = gunCF * hand.rest
			end
			busy[busyKey] = nil
		end
		handWorld[side] = result
		return result
	end

	for name in self.groups do
		getGroup(name)
	end
	getHand("Left")
	getHand("Right")
	return groupWorld, handWorld
end

type Pose = {
	aimAlpha: number,
	sprinting: boolean,
	crawling: boolean,
	reloading: boolean,
	speed: number,
	grounded: boolean,
}

-- 0 = nothing in front of you, 1 = right up against a wall: how much of the gun's reach is blocked
local tuckParams = RaycastParams.new()
tuckParams.FilterType = Enum.RaycastFilterType.Exclude
function Viewmodel:WallTuck(cameraCFrame: CFrame): number
	local character = Players.LocalPlayer.Character
	tuckParams.FilterDescendantsInstances = { Workspace.CurrentCamera, character :: Instance }
	local hit = Workspace:Raycast(cameraCFrame.Position, cameraCFrame.LookVector * self.reach, tuckParams)
	if not hit or not hit.Instance.CanCollide or hit.Instance.Transparency > 0.9 then
		return 0 -- (invisible map boundaries don't count)
	end
	return math.clamp((self.reach - hit.Distance) / (self.reach * 0.7), 0, 1)
end

function Viewmodel:Update(dt: number, cameraCFrame: CFrame, pose: Pose)
	local function approach(current: number, target: number, sharpness: number): number
		return current + (target - current) * (1 - math.exp(-sharpness * dt))
	end

	self.sprintAlpha = approach(self.sprintAlpha, if pose.sprinting and not self.clip then 1 else 0, 10)
	self.tuckAlpha = approach(self.tuckAlpha, self:WallTuck(cameraCFrame), 12)
	self.crawlAlpha = approach(self.crawlAlpha, if pose.crawling and not self.clip then 1 - pose.aimAlpha else 0, 8)
	self.crawlTime += dt * math.clamp(pose.speed, 0, 6) * 1.8
	self.kick = approach(self.kick, 0, 25)

	-- Walk bob, mostly gone while aiming
	local moving = if pose.grounded then math.clamp(pose.speed / 28, 0, 1) else 0
	self.bobTime += dt * (6 + 6 * moving)
	local bobAmount = 0.05 * moving * (1 - pose.aimAlpha * 0.85)
	local bob = CFrame.new(math.sin(self.bobTime) * bobAmount, math.abs(math.cos(self.bobTime)) * bobAmount, 0)

	-- Ease the hip -> aim move so the sight glides in and settles exactly on center
	local aim = pose.aimAlpha * pose.aimAlpha * (3 - 2 * pose.aimAlpha)
	local offset = self.hipOffset:Lerp(self.aimOffset, aim)
	local rock = math.sin(self.crawlTime)
	local crawlPose = CRAWL_POSE * CFrame.new(rock * 0.04, math.abs(math.cos(self.crawlTime)) * 0.05, 0) * CFrame.Angles(0, 0, rock * 0.1)
	local action = CFrame.new():Lerp(SPRINT_POSE, self.sprintAlpha)
		* CFrame.new():Lerp(crawlPose, self.crawlAlpha)
		* CFrame.new():Lerp(TUCK_POSE, self.tuckAlpha)
	local kick = CFrame.new(0, 0, self.kick) * CFrame.Angles(self.kick * 0.15, 0, 0)
	local base = cameraCFrame * offset * bob * action * kick

	-- Animation: find the two keyframes we're between and blend them
	local gunCF = base
	local groupWorld: { [string]: CFrame } = {}
	local handWorld: { [string]: CFrame } = {}
	local hidden: { [string]: boolean } = {}
	local clip = self.clip
	if clip then
		local t = (os.clock() - self.clipStart) / self.clipDuration
		if t >= 1 then
			self.clip = nil
			clip = nil
			t = 1
		end
		if clip then
			-- Events for keyframes we just passed (sounds)
			for _, key in clip do
				if key.t > self.clipLastT and key.t <= t then
					for _, eventName in key.events do
						if self.OnAnimationEvent then
							task.spawn(self.OnAnimationEvent, eventName)
						end
					end
				end
			end
			self.clipLastT = t
			local a, b = clip[1], clip[#clip]
			for i = 1, #clip - 1 do
				if t >= clip[i].t and t < clip[i + 1].t then
					a, b = clip[i], clip[i + 1]
					break
				end
			end
			local span = b.t - a.t
			local alpha = if span > 0 then math.clamp((t - a.t) / span, 0, 1) else 1
			alpha = (EASES[b.ease] or EASES.inOut)(alpha)
			hidden = a.hide
			local gunA, gunB = base * a.gun, base * b.gun
			gunCF = gunA:Lerp(gunB, alpha)
			local groupsA, handsA = self:_resolve(a, gunCF, cameraCFrame)
			local groupsB, handsB = self:_resolve(b, gunCF, cameraCFrame)
			for name, cf in groupsA do
				groupWorld[name] = cf:Lerp(groupsB[name] or cf, alpha)
			end
			for side, cf in handsA do
				handWorld[side] = cf:Lerp(handsB[side] or cf, alpha)
			end
		end
	end

	-- Collect every part's new CFrame and move them all at once
	local parts: { BasePart } = {}
	local cframes: { CFrame } = {}
	local function place(list: { BasePart }, offsets: { CFrame }, frame: CFrame)
		for i, part in list do
			table.insert(parts, part)
			table.insert(cframes, frame * offsets[i])
		end
	end
	place(self.gunParts, self.gunOffsets, gunCF)

	for name, group in self.groups do
		-- Extra pieces (loose shell, speedloader) only show during an animation
		local shouldHide = hidden[name] == true or (group.extra and not clip)
		if shouldHide ~= group.hidden then
			group.hidden = shouldHide
			for i, part in group.parts do
				part.Transparency = if shouldHide then 1 else group.transparency[i]
			end
		end
		place(group.parts, group.offsets, groupWorld[name] or gunCF * group.rest)
	end

	for side, hand in self.hands do
		local frame = handWorld[side] or gunCF * hand.rest
		place(hand.parts, hand.offsets, frame)

		-- Arm: shoulder (fixed below/behind your eyes) → elbow → wrist
		local arm = self.arms[side]
		local wrist = frame * hand.wrist
		local reach = (FOREARM_LENGTH + UPPER_ARM_LENGTH) * 0.98
		local shoulder = cameraCFrame * SHOULDER[side]
		if (shoulder - wrist).Magnitude > reach then
			-- Reaching far: the shoulder comes forward with it (like a real one would)
			shoulder = wrist + (shoulder - wrist).Unit * reach
		end
		local pole = cameraCFrame:VectorToWorldSpace(ELBOW_POLE[side])
		local elbow = solveTwoBone(wrist, shoulder, FOREARM_LENGTH, UPPER_ARM_LENGTH, pole)
		local up = (elbow - wrist).Unit -- from the wrist up the forearm
		local function along(distance: number): Vector3
			return wrist + up * distance
		end
		local shoulderPoint = elbow + (shoulder - elbow).Unit * UPPER_ARM_LENGTH
		table.insert(parts, arm.wristBall)
		table.insert(cframes, CFrame.new(wrist))
		table.insert(parts, arm.cuff)
		table.insert(cframes, rodCFrame(along(-0.02), along(0.17)))
		table.insert(parts, arm.hem)
		table.insert(cframes, rodCFrame(along(0.14), along(0.22)))
		table.insert(parts, arm.forearm)
		table.insert(cframes, rodCFrame(along(0.21), along(0.65)))
		table.insert(parts, arm.forearmUpper)
		table.insert(cframes, rodCFrame(along(0.62), elbow))
		table.insert(parts, arm.elbow)
		table.insert(cframes, CFrame.new(elbow))
		table.insert(parts, arm.upperArm)
		table.insert(cframes, rodCFrame(elbow, shoulderPoint))
		if arm.watchBand then
			local outward = frame:VectorToWorldSpace(hand.outward)
			local inside = outward - up * outward:Dot(up)
			inside = if inside.Magnitude > 1e-3 then -inside.Unit else Vector3.yAxis
			local face = along(0.09) + inside * 0.122
			table.insert(parts, arm.watchBand)
			table.insert(cframes, rodCFrame(along(0.06), along(0.12)))
			table.insert(parts, arm.watchCase)
			table.insert(cframes, rodCFrame(face - inside * 0.012, face + inside * 0.018))
			table.insert(parts, arm.watchGlass)
			table.insert(cframes, rodCFrame(face + inside * 0.018, face + inside * 0.024))
		end
	end

	Workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
end

function Viewmodel:Destroy()
	self.model:Destroy()
end

return Viewmodel
