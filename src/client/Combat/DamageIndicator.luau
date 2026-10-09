-- Getting hurt:
--   • a red ring around the edges of the screen that flashes when you lose health (bigger hit = stronger)
--   • a red arrow around the crosshair pointing toward where the shot/stab came from; it keeps
--     pointing at that spot as you turn, then fades
-- Also turns off Roblox's own health bar (we have our own in the bottom left).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")

local Damaged = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Damaged") :: RemoteEvent

local player = Players.LocalPlayer

local DamageIndicator = {}

local RED = Color3.fromRGB(220, 30, 30)
local ARROW_RADIUS = 110 -- pixels from the screen center
local ARROW_TIME = 1.6 -- seconds an arrow stays
local VIGNETTE_FADE = 2.2 -- how fast the red ring fades (per second)

local gui: ScreenGui
local vignette: Frame
local vignetteStroke: UIStroke
local vignetteAlpha = 0
local arrows: { { frame: Frame, from: Vector3, born: number } } = {}

-- Roblox's built-in health bar (top right). SetCoreGuiEnabled can fail if called too early, so retry.
local function hideRobloxHealthBar()
	for _ = 1, 20 do
		if pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Health, false) then
			return
		end
		task.wait(0.5)
	end
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "DamageIndicator"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 2
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Same trick as the sniper scope: a transparent circle with a very thick outline. Here the
	-- outline is red and see-through, so it tints only the edges of the screen.
	vignette = Instance.new("Frame")
	vignette.AnchorPoint = Vector2.new(0.5, 0.5)
	vignette.Position = UDim2.fromScale(0.5, 0.5)
	vignette.Size = UDim2.fromScale(0.85, 0.85) -- an oval slightly inside the screen edges
	vignette.BackgroundTransparency = 1
	vignette.Parent = gui
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1.6
	aspect.Parent = vignette
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.5, 0)
	round.Parent = vignette
	vignetteStroke = Instance.new("UIStroke")
	vignetteStroke.Color = RED
	vignetteStroke.Thickness = 900
	vignetteStroke.Transparency = 1
	vignetteStroke.Parent = vignette
end

local function addArrow(from: Vector3)
	local arrow = Instance.new("Frame")
	arrow.AnchorPoint = Vector2.new(0.5, 0.5)
	arrow.Size = UDim2.fromOffset(46, 8)
	arrow.BackgroundColor3 = RED
	arrow.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = arrow
	-- A small pointer on the outside edge
	local tip = Instance.new("Frame")
	tip.AnchorPoint = Vector2.new(0.5, 1)
	tip.Position = UDim2.new(0.5, 0, 0, 1)
	tip.Size = UDim2.fromOffset(10, 10)
	tip.Rotation = 45
	tip.BackgroundColor3 = RED
	tip.BorderSizePixel = 0
	tip.Parent = arrow
	arrow.Parent = gui
	table.insert(arrows, { frame = arrow, from = from, born = os.clock() })
end

local function update(dt: number)
	-- Red ring fades out
	vignetteAlpha = math.max(vignetteAlpha - VIGNETTE_FADE * dt, 0)
	vignetteStroke.Transparency = 1 - vignetteAlpha * 0.55

	-- Arrows: angle from where you're looking to where the damage came from
	local camera = Workspace.CurrentCamera
	local now = os.clock()
	for i = #arrows, 1, -1 do
		local info = arrows[i]
		local age = now - info.born
		if age >= ARROW_TIME then
			info.frame:Destroy()
			table.remove(arrows, i)
			continue
		end
		local localPos = camera.CFrame:PointToObjectSpace(info.from)
		local angle = math.atan2(localPos.X, -localPos.Z) -- 0 = straight ahead (top of the ring)
		info.frame.Position = UDim2.new(0.5, math.sin(angle) * ARROW_RADIUS, 0.5, -math.cos(angle) * ARROW_RADIUS)
		info.frame.Rotation = math.deg(angle)
		local fade = math.clamp((age - (ARROW_TIME - 0.5)) / 0.5, 0, 1)
		info.frame.BackgroundTransparency = 0.1 + fade * 0.9
		local tip = info.frame:FindFirstChildOfClass("Frame")
		if tip then
			tip.BackgroundTransparency = info.frame.BackgroundTransparency
		end
	end
end

local function watchHealth(character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local last = humanoid.Health
	humanoid.HealthChanged:Connect(function(health)
		local lost = last - health
		last = health
		if lost > 0 then
			-- Bigger hits flash harder; low health keeps a stronger ring
			vignetteAlpha = math.clamp(vignetteAlpha + lost / 60 + 0.25, 0, 1)
		end
	end)
end

function DamageIndicator.Start()
	task.spawn(hideRobloxHealthBar)
	build()
	Damaged.OnClientEvent:Connect(function(from: Vector3)
		if typeof(from) == "Vector3" then
			addArrow(from)
		end
	end)
	if player.Character then
		task.spawn(watchHealth, player.Character)
	end
	player.CharacterAdded:Connect(function(character)
		vignetteAlpha = 0
		for _, info in arrows do
			info.frame:Destroy()
		end
		table.clear(arrows)
		watchHealth(character)
	end)
	RunService.RenderStepped:Connect(update)
end

return DamageIndicator
