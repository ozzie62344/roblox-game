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

-- Builds a blocky gun from the weapon's Look (body / barrel / stock lengths, mag size, color)
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
