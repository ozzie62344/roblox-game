-- Siege's thrown-gadget warnings and arming beeps:
--   • a grenade (frag, flash, impact) or a nitro cell landing near you puts a warning on screen:
--     a red tag around the crosshair pointing at it, with how far away it is (the server tags
--     them with a "Warn" attribute, GadgetService)
--   • frags tick and placed breach charges beep while they're armed, from where they are, so you
--     can hear one coming through the wall

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Abilities = require(ReplicatedStorage.Shared.Abilities)
local Sounds = require(ReplicatedStorage.Shared.Sounds)
local Sound3D = require(script.Parent.Parent.Audio.Sound3D)

local player = Players.LocalPlayer

local GadgetWarnings = {}

-- How close a tagged gadget has to be (studs) to warn you: a bit past where it can hurt
local WARN_RANGE: { [string]: number } = {
	FRAG = (Abilities.FragGrenade.Radius or 18) + 4,
	FLASH = (Abilities.Flashbang.Radius or 20),
	IMPACT = (Abilities.ImpactGrenade.Radius or 6) + 4,
	NITRO = (Abilities.NitroCell.Radius or 12) + 4,
}
-- Armed gadgets that beep (model name → seconds between beeps)
local BEEP_EVERY: { [string]: number } = {
	FragGrenade = 0.5,
	BreachCharge = 1.1,
}
local MAX_TAGS = 4
local RING = 92 -- pixels from the crosshair
local RED = Color3.fromRGB(255, 70, 55)

local gui: ScreenGui
local tags: { Frame } = {}
-- (a plain table, pruned every frame: a weak one keyed by the device can lose its entry while the
-- device still exists, and then it beeps every frame)
local lastBeep: { [Instance]: number } = {}

local function buildTag(): Frame
	local tag = Instance.new("Frame")
	tag.AnchorPoint = Vector2.new(0.5, 0.5)
	tag.Size = UDim2.fromOffset(74, 38)
	tag.BackgroundTransparency = 1
	tag.Visible = false
	local arrow = Instance.new("TextLabel")
	arrow.Name = "Arrow"
	arrow.AnchorPoint = Vector2.new(0.5, 0.5)
	arrow.Position = UDim2.fromScale(0.5, 0.18)
	arrow.Size = UDim2.fromOffset(18, 18)
	arrow.BackgroundTransparency = 1
	arrow.Font = Enum.Font.GothamBlack
	arrow.TextSize = 18
	arrow.TextColor3 = RED
	arrow.Text = "▲"
	arrow.Parent = tag
	local text = Instance.new("TextLabel")
	text.Name = "Text"
	text.Position = UDim2.fromScale(0, 0.4)
	text.Size = UDim2.fromScale(1, 0.6)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBlack
	text.TextSize = 12
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextStrokeTransparency = 0.3
	text.Parent = tag
	tag.Parent = gui
	return tag
end

-- Where a tagged gadget is (a model's PrimaryPart, or the part itself)
local function positionOf(device: Instance): Vector3?
	if device:IsA("Model") then
		return if device.PrimaryPart then device.PrimaryPart.Position else nil
	elseif device:IsA("BasePart") then
		return device.Position
	end
	return nil
end

local function update()
	local folder = Workspace:FindFirstChild("Deployables")
	local camera = Workspace.CurrentCamera
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local alive = humanoid ~= nil and humanoid.Health > 0
	local warnings: { { label: string, offset: Vector3, distance: number } } = {}
	local now = os.clock()
	for device in lastBeep do
		if device.Parent ~= folder then
			lastBeep[device] = nil -- (went off, shot, or swept away by a new round)
		end
	end
	for _, device in if folder then folder:GetChildren() else {} do
		local position = positionOf(device)
		if not position then
			continue
		end
		-- Ticking / beeping while armed
		local every = BEEP_EVERY[device.Name]
		if every and now - (lastBeep[device] or 0) >= every then
			lastBeep[device] = now
			local beep = Sounds.ArmedBeep
			Sound3D.Play(beep.Id, position, { volume = beep.Volume, range = beep.Range, pitch = if device.Name == "FragGrenade" then beep.Pitch * 1.25 else beep.Pitch })
		end
		local label = device:GetAttribute("Warn")
		local range = typeof(label) == "string" and WARN_RANGE[label]
		if alive and range then
			local offset = position - camera.CFrame.Position
			if offset.Magnitude <= range then
				table.insert(warnings, { label = label :: string, offset = offset, distance = offset.Magnitude })
			end
		end
	end
	table.sort(warnings, function(a, b)
		return a.distance < b.distance
	end)
	local center = camera.ViewportSize / 2
	for i = 1, MAX_TAGS do
		local warning = warnings[i]
		local tag = tags[i]
		if not warning then
			tag.Visible = false
			continue
		end
		-- Round the crosshair toward it: up = in front of you, down = behind
		local here = camera.CFrame:VectorToObjectSpace(warning.offset)
		local angle = math.atan2(here.X, -here.Z)
		local direction = Vector2.new(math.sin(angle), -math.cos(angle))
		local spot = center + direction * RING
		tag.Position = UDim2.fromOffset(spot.X, spot.Y)
		local arrow = tag:FindFirstChild("Arrow") :: TextLabel
		arrow.Rotation = math.deg(angle)
		local text = tag:FindFirstChild("Text") :: TextLabel
		text.Text = `{warning.label}  {math.floor(warning.distance + 0.5)}m` -- (studs, like the other markers)
		tag.Visible = true
	end
end

function GadgetWarnings.Start()
	gui = Instance.new("ScreenGui")
	gui.Name = "GadgetWarnings"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 5
	gui.Parent = player:WaitForChild("PlayerGui")
	for i = 1, MAX_TAGS do
		tags[i] = buildTag()
	end
	RunService.RenderStepped:Connect(update)
end

return GadgetWarnings
