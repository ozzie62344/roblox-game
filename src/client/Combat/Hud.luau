-- Crosshair (spreads with accuracy), hit markers, ammo and health.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer

local Hud = {}

local gui: ScreenGui
local crosshairBars: { Frame } = {}
local hitMarkerBars: { Frame } = {}
local hitMarkerToken = 0
local ammoLabel: TextLabel
local healthFill: Frame
local healthLabel: TextLabel

local WHITE = Color3.new(1, 1, 1)
local RED = Color3.fromRGB(255, 70, 70)

local function frame(parent: Instance, size: UDim2, position: UDim2, color: Color3): Frame
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Size = size
	f.Position = position
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.Parent = parent
	return f
end

local function label(parent: Instance, position: UDim2, anchor: Vector2, textSize: number): TextLabel
	local l = Instance.new("TextLabel")
	l.AnchorPoint = anchor
	l.Position = position
	l.Size = UDim2.fromOffset(240, 40)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextSize = textSize
	l.TextColor3 = WHITE
	l.TextStrokeTransparency = 0.5
	l.TextXAlignment = if anchor.X > 0.5 then Enum.TextXAlignment.Right else Enum.TextXAlignment.Left
	l.Parent = parent
	return l
end

function Hud.Start()
	gui = Instance.new("ScreenGui")
	gui.Name = "CombatHud"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local center = UDim2.fromScale(0.5, 0.5)

	-- Crosshair: 4 bars around the center (top, bottom, left, right)
	for i = 1, 4 do
		local vertical = i <= 2
		local size = if vertical then UDim2.fromOffset(2, 8) else UDim2.fromOffset(8, 2)
		local bar = frame(gui, size, center, WHITE)
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 1
		stroke.Transparency = 0.6
		stroke.Parent = bar
		crosshairBars[i] = bar
	end

	-- Hit marker: 4 diagonal ticks
	for i = 1, 4 do
		local bar = frame(gui, UDim2.fromOffset(2, 9), center, WHITE)
		bar.Rotation = 45 + (i - 1) * 90
		bar.Visible = false
		hitMarkerBars[i] = bar
	end

	ammoLabel = label(gui, UDim2.new(1, -40, 1, -40), Vector2.new(1, 1), 32)

	local healthBack = frame(gui, UDim2.fromOffset(240, 10), UDim2.new(0, 160, 1, -40), Color3.fromRGB(30, 30, 30))
	healthBack.BackgroundTransparency = 0.3
	healthFill = frame(healthBack, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0.5), WHITE)
	healthFill.AnchorPoint = Vector2.new(0, 0.5)
	healthLabel = label(gui, UDim2.new(0, 40, 1, -48), Vector2.new(0, 1), 20)

	local function watchHealth(character: Model)
		local humanoid = character:WaitForChild("Humanoid") :: Humanoid
		local function refresh()
			local alpha = math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
			healthFill.Size = UDim2.fromScale(alpha, 1)
			healthFill.BackgroundColor3 = if alpha < 0.35 then RED else WHITE
			healthLabel.Text = tostring(math.ceil(humanoid.Health))
		end
		humanoid.HealthChanged:Connect(refresh)
		refresh()
	end
	if player.Character then
		task.spawn(watchHealth, player.Character)
	end
	player.CharacterAdded:Connect(watchHealth)
end

-- gap = distance in pixels from the center to each bar
function Hud.SetCrosshair(gap: number, visible: boolean)
	local offsets = {
		Vector2.new(0, -(gap + 4)),
		Vector2.new(0, gap + 4),
		Vector2.new(-(gap + 4), 0),
		Vector2.new(gap + 4, 0),
	}
	for i, bar in crosshairBars do
		bar.Visible = visible
		bar.Position = UDim2.new(0.5, offsets[i].X, 0.5, offsets[i].Y)
	end
end

-- kind: "body", "head" or "kill"
function Hud.HitMarker(kind: string)
	hitMarkerToken += 1
	local token = hitMarkerToken
	local color = if kind == "body" then WHITE else RED
	local length = if kind == "kill" then 14 else 9

	for i, bar in hitMarkerBars do
		local angle = math.rad(45 + (i - 1) * 90)
		local distance = 7 + length / 2
		bar.Size = UDim2.fromOffset(2, length)
		bar.Position = UDim2.new(0.5, math.sin(angle) * distance, 0.5, -math.cos(angle) * distance)
		bar.BackgroundColor3 = color
		bar.BackgroundTransparency = 0
		bar.Visible = true
		TweenService:Create(bar, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()
	end
	task.delay(0.25, function()
		if token == hitMarkerToken then
			for _, bar in hitMarkerBars do
				bar.Visible = false
			end
		end
	end)
end

function Hud.SetAmmo(current: number, max: number, reloading: boolean)
	ammoLabel.Text = if reloading then "RELOADING" else `{current} / {max}`
	ammoLabel.TextColor3 = if current == 0 and not reloading then RED else WHITE
end

return Hud
