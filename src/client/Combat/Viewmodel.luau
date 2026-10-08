-- The gun you see in first person. Built from parts for now (swap in a real model later).
-- Follows the camera with hip / aim / sprint / reload poses, walk bob and shot kick.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Weapons = require(ReplicatedStorage.Shared.Weapons)

local Viewmodel = {}
Viewmodel.__index = Viewmodel

-- Where the gun sits relative to the camera
local HIP_OFFSET = CFrame.new(0.75, -0.6, -1.5)
local AIM_OFFSET = CFrame.new(0, -0.3, -1.1) -- lines the sight up with the center of the screen
local SPRINT_ROTATION = CFrame.Angles(math.rad(-25), math.rad(35), math.rad(10))
local RELOAD_ROTATION = CFrame.Angles(math.rad(-30), 0, math.rad(-25))

local GUN_COLOR = Color3.fromRGB(45, 47, 52)
local SLEEVE_COLOR = Color3.fromRGB(62, 68, 56)
local GLOVE_COLOR = Color3.fromRGB(28, 28, 30)
-- Shared with DeployArms so both sets of arms match
Viewmodel.SleeveColor = SLEEVE_COLOR
Viewmodel.GloveColor = GLOVE_COLOR

local function makePart(model: Model, name: string, size: Vector3, offset: CFrame, color: Color3?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = offset
	part.Color = color or GUN_COLOR
	part.Material = Enum.Material.Metal
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = model
	return part
end

-- A block stretched from point a to point b (for arm segments)
local function limb(model: Model, name: string, a: Vector3, b: Vector3, thickness: number, color: Color3): Part
	local part = makePart(
		model,
		name,
		Vector3.new(thickness, thickness, (b - a).Magnitude),
		CFrame.lookAt((a + b) / 2, b),
		color
	)
	part.Material = Enum.Material.Fabric
	return part
end

-- Sleeves + gloved hands: right hand on the grip, left hand under the front of the gun.
-- The shoulders end up below/behind the camera, so only forearms and hands are on screen.
local function buildArms(model: Model, bodyLength: number)
	local function arm(side: string, hand: Vector3, elbow: Vector3, shoulder: Vector3)
		limb(model, side .. "UpperArm", shoulder, elbow, 0.34, SLEEVE_COLOR)
		limb(model, side .. "Forearm", elbow, hand, 0.3, SLEEVE_COLOR)
		local glove = makePart(model, side .. "Hand", Vector3.new(0.3, 0.32, 0.38), CFrame.lookAt(hand, hand + (hand - elbow)), GLOVE_COLOR)
		glove.Material = Enum.Material.Fabric
	end
	local grip = bodyLength * 0.25
	local front = -bodyLength * 0.5
	arm("Right", Vector3.new(0.05, -0.3, grip), Vector3.new(0.4, -0.85, grip + 1.1), Vector3.new(0.6, -1.3, grip + 2.3))
	arm("Left", Vector3.new(-0.05, -0.2, front), Vector3.new(-0.6, -0.8, front + 1), Vector3.new(-0.95, -1.3, front + 2.3))
end

-- Builds a blocky gun from the weapon's Look (body / barrel / stock lengths, mag size, color), plus arms
function Viewmodel.new(weapon: Weapons.Weapon)
	local look = weapon.Look
	local model = Instance.new("Model")
	model.Name = "Viewmodel"

	local bodyLength, barrelLength, stockLength = look.BodyLength, look.BarrelLength, look.StockLength
	local body = makePart(model, "Body", Vector3.new(0.25, 0.35, bodyLength), CFrame.new(), look.Color)
	local barrel = makePart(
		model,
		"Barrel",
		Vector3.new(0.1, 0.1, barrelLength),
		CFrame.new(0, 0.06, -(bodyLength + barrelLength) / 2),
		look.Color
	)
	makePart(
		model,
		"Mag",
		look.MagSize,
		CFrame.new(0, -0.15 - look.MagSize.Y / 2, -bodyLength * 0.15) * CFrame.Angles(0.15, 0, 0),
		look.Color
	)
	if stockLength > 0 then
		makePart(
			model,
			"Stock",
			Vector3.new(0.2, 0.3, stockLength),
			CFrame.new(0, -0.05, (bodyLength + stockLength) / 2),
			look.Color
		)
	end
	makePart(model, "Sight", Vector3.new(0.08, 0.12, 0.2), CFrame.new(0, 0.24, -0.1), Color3.fromRGB(20, 20, 22))
	local sightDot =
		makePart(model, "SightDot", Vector3.new(0.02, 0.02, 0.02), CFrame.new(0, 0.3, -0.1), Color3.fromRGB(255, 60, 60))
	sightDot.Material = Enum.Material.Neon
	model.PrimaryPart = body
	buildArms(model, bodyLength)

	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.Position = Vector3.new(0, 0, -barrelLength / 2 - 0.02)
	muzzle.Parent = barrel

	local flash = Instance.new("PointLight")
	flash.Color = Color3.fromRGB(255, 200, 120)
	flash.Range = 12
	flash.Brightness = 3
	flash.Enabled = false
	flash.Parent = muzzle

	model.Parent = Workspace.CurrentCamera

	local self = setmetatable({
		model = model,
		muzzle = muzzle,
		flash = flash,
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
	self.flash.Enabled = true
	task.delay(0.04, function()
		self.flash.Enabled = false
	end)
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

	local offset = HIP_OFFSET:Lerp(AIM_OFFSET, pose.aimAlpha)
	local rotation = CFrame.new():Lerp(SPRINT_ROTATION, self.sprintAlpha):Lerp(RELOAD_ROTATION, self.reloadAlpha)
	local kick = CFrame.new(0, 0, self.kick) * CFrame.Angles(self.kick * 0.15, 0, 0)

	self.model:PivotTo(cameraCFrame * offset * bob * rotation * kick)
end

function Viewmodel:Destroy()
	self.model:Destroy()
end

return Viewmodel
