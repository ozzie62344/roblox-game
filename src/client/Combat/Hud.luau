-- Crosshair (spreads with accuracy), hit markers, ammo and health.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Operators = require(ReplicatedStorage.Shared.Operators)
local state = require(script.Parent.Parent.PlayerState)

local player = Players.LocalPlayer

local Hud = {}

local gui: ScreenGui
local crosshairBars: { Frame } = {}
local hitMarkerBars: { Frame } = {}
local hitMarkerToken = 0
local crosshairSize = 1 -- the player's settings (ClientSettings → SetCrosshairStyle / SetHitMarkers)
local hitMarkersOn = true
local ammoLabel: TextLabel
local healthFill: Frame
local healthBack: Frame
local healthLabel: TextLabel
local loadoutLabel: TextLabel
local statusLabel: TextLabel
local statusToken = 0
local scope: Frame
local knifeBar: Frame
local knifeFill: Frame

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
	RunService.RenderStepped:Connect(function()
		gui.Enabled = not state.inLobby -- (gun put away there; the lobby menu has the screen)
	end)

	local center = UDim2.fromScale(0.5, 0.5)

	-- Scope overlay: a transparent circle whose huge black outline covers the rest of the screen
	scope = Instance.new("Frame")
	scope.AnchorPoint = Vector2.new(0.5, 0.5)
	scope.Position = center
	scope.Size = UDim2.fromScale(0.9, 0.9)
	scope.BackgroundTransparency = 1
	scope.ZIndex = 0
	scope.Visible = false
	scope.Parent = gui
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.DominantAxis = Enum.DominantAxis.Height
	aspect.Parent = scope
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.5, 0)
	round.Parent = scope
	local blackout = Instance.new("UIStroke")
	blackout.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	blackout.Color = Color3.new(0, 0, 0)
	blackout.Thickness = 4000
	blackout.Parent = scope
	for _, size in { UDim2.new(1, 0, 0, 1), UDim2.new(0, 1, 1, 0) } do
		local line = frame(scope, size, center, Color3.new(0, 0, 0))
		line.ZIndex = 0
	end

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

	-- Knife recharging: a thin bar under the crosshair that fills back up
	knifeBar = frame(gui, UDim2.fromOffset(44, 3), UDim2.new(0.5, 0, 0.5, 30), Color3.fromRGB(30, 30, 30))
	knifeBar.BackgroundTransparency = 0.4
	knifeBar.Visible = false
	knifeFill = frame(knifeBar, UDim2.fromScale(0, 1), UDim2.fromScale(0, 0.5), WHITE)
	knifeFill.AnchorPoint = Vector2.new(0, 0.5)

	ammoLabel = label(gui, UDim2.new(1, -40, 1, -40), Vector2.new(1, 1), 32)
	loadoutLabel = label(gui, UDim2.new(1, -40, 1, -78), Vector2.new(1, 1), 16)
	loadoutLabel.TextColor3 = Color3.fromRGB(200, 205, 215)
	loadoutLabel.Size = UDim2.fromOffset(440, 24) -- (room for the operator's name too)
	statusLabel = label(gui, UDim2.new(1, -40, 1, -104), Vector2.new(1, 1), 16)
	statusLabel.Size = UDim2.fromOffset(360, 24)
	statusLabel.Visible = false

	healthBack = frame(gui, UDim2.fromOffset(240, 10), UDim2.new(0, 160, 1, -40), Color3.fromRGB(30, 30, 30))
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

-- Touch screens: the ammo, loadout and status move to the bottom middle, out from under the
-- fire and jump buttons (MobileControls)
function Hud.SetTouchLayout(touch: boolean)
	-- Health goes to the top left (next to the dev button), clear of the thumbstick and the
	-- prompts in the middle
	local top = GuiService:GetGuiInset().Y + 26
	healthLabel.AnchorPoint = if touch then Vector2.new(0, 0.5) else Vector2.new(0, 1)
	healthLabel.Position = if touch then UDim2.fromOffset(64, top) else UDim2.new(0, 40, 1, -48)
	healthBack.Size = if touch then UDim2.fromOffset(110, 8) else UDim2.fromOffset(240, 10)
	healthBack.Position = if touch then UDim2.fromOffset(165, top) else UDim2.new(0, 160, 1, -40)
	local x, anchor = if touch then UDim.new(0.5, 0) else UDim.new(1, -40), if touch then Vector2.new(0.5, 1) else Vector2.new(1, 1)
	local bottom = if touch then -10 else -40
	for i, l in { ammoLabel, loadoutLabel, statusLabel } do
		l.AnchorPoint = anchor
		l.Position = UDim2.new(x, UDim.new(1, bottom - ({ 0, 38, 64 })[i]))
		l.TextXAlignment = if touch then Enum.TextXAlignment.Center else Enum.TextXAlignment.Right
	end
end

-- Short message above the loadout (e.g. "GHOST STEP — SILENT"), with a countdown if it lasts a while
function Hud.ShowStatus(text: string, duration: number, color: Color3?)
	statusToken += 1
	local token = statusToken
	local endsAt = os.clock() + duration
	statusLabel.TextColor3 = color or WHITE
	statusLabel.Visible = true
	task.spawn(function()
		while token == statusToken and os.clock() < endsAt do
			local remaining = endsAt - os.clock()
			statusLabel.Text = if duration >= 3 then `{text}  {math.ceil(remaining)}` else text
			task.wait(0.1)
		end
		if token == statusToken then
			statusLabel.Visible = false
		end
	end)
end

-- 0 = knife ready (bar hidden), 1 = just swung
function Hud.SetKnifeCooldown(remaining: number)
	knifeBar.Visible = remaining > 0
	knifeFill.Size = UDim2.fromScale(1 - remaining, 1)
end

function Hud.SetScoped(scoped: boolean)
	scope.Visible = scoped
end

-- e.g. "SMG" and "[F] Dash" → "SMG  ·  [F] Dash", led by your operator's name when you have one
-- ("VOLTA  ·  SMG  ·  [X] Shock Wire  ●●")
function Hud.SetLoadout(weaponName: string, abilityText: string?)
	local text = if abilityText then `{string.upper(weaponName)}  ·  {abilityText}` else string.upper(weaponName)
	local operator = Operators.ById[player:GetAttribute("Operator") or ""]
	if operator and operator.Gadget == player:GetAttribute("Ability") then -- (the dev panel can swap the gadget alone)
		text = `{string.upper(operator.Name)}  ·  {text}`
	end
	loadoutLabel.Text = text
end

-- gap = distance in pixels from the center to each bar
function Hud.SetCrosshair(gap: number, visible: boolean)
	local reach = gap + 4 * crosshairSize
	local offsets = {
		Vector2.new(0, -reach),
		Vector2.new(0, reach),
		Vector2.new(-reach, 0),
		Vector2.new(reach, 0),
	}
	for i, bar in crosshairBars do
		bar.Visible = visible
		bar.Position = UDim2.new(0.5, offsets[i].X, 0.5, offsets[i].Y)
	end
end

-- The player's crosshair settings: colour, and size (1 = normal; longer, and thicker when big)
function Hud.SetCrosshairStyle(color: Color3, size: number)
	crosshairSize = size
	local length = math.floor(8 * size + 0.5)
	local thickness = if size >= 1.5 then 3 else 2
	for i, bar in crosshairBars do
		bar.Size = if i <= 2 then UDim2.fromOffset(thickness, length) else UDim2.fromOffset(length, thickness)
		bar.BackgroundColor3 = color
	end
end

function Hud.SetHitMarkers(on: boolean)
	hitMarkersOn = on
end

-- Hit marker looks: colour, tick length and thickness, how long it stays, and how far out it
-- pops from before settling (a kill punches out and back in)
local HIT_MARKERS = {
	body = { color = WHITE, length = 9, thickness = 2, duration = 0.25, pop = 0 },
	head = { color = Color3.fromRGB(255, 120, 90), length = 10, thickness = 2, duration = 0.3, pop = 0 },
	down = { color = Color3.fromRGB(255, 185, 50), length = 12, thickness = 2, duration = 0.4, pop = 3 }, -- (downed them: DBNO)
	kill = { color = RED, length = 14, thickness = 2, duration = 0.4, pop = 4 },
	headkill = { color = RED, length = 16, thickness = 3, duration = 0.5, pop = 6 },
}

-- kind: "body", "head", "down" (put them down, not out), "kill" or "headkill" (a headshot that
-- killed: a bigger, bolder X)
function Hud.HitMarker(kind: string)
	if not hitMarkersOn then
		return
	end
	hitMarkerToken += 1
	local token = hitMarkerToken
	local look = HIT_MARKERS[kind] or HIT_MARKERS.body
	local length = look.length

	for i, bar in hitMarkerBars do
		local angle = math.rad(45 + (i - 1) * 90)
		local distance = 7 + length / 2
		local direction = Vector2.new(math.sin(angle), -math.cos(angle))
		local settled = UDim2.new(0.5, direction.X * distance, 0.5, direction.Y * distance)
		local popped = direction * (distance + look.pop)
		bar.Size = UDim2.fromOffset(look.thickness, length)
		bar.Position = if look.pop > 0 then UDim2.new(0.5, popped.X, 0.5, popped.Y) else settled
		bar.BackgroundColor3 = look.color
		bar.BackgroundTransparency = 0
		bar.Visible = true
		if look.pop > 0 then
			TweenService:Create(bar, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = settled }):Play()
		end
		TweenService:Create(bar, TweenInfo.new(look.duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { BackgroundTransparency = 1 }):Play()
	end
	task.delay(look.duration, function()
		if token == hitMarkerToken then
			for _, bar in hitMarkerBars do
				bar.Visible = false
			end
		end
	end)
end

function Hud.SetAmmoText(text: string)
	ammoLabel.Text = text
	ammoLabel.TextColor3 = WHITE
end

-- A round in the chamber on top of a full mag shows like Siege: "30+1 / 30"
function Hud.SetAmmo(current: number, max: number, reloading: boolean)
	local shown = if current > max then `{max}+{current - max}` else tostring(current)
	ammoLabel.Text = if reloading then "RELOADING" else `{shown} / {max}`
	ammoLabel.TextColor3 = if current == 0 and not reloading then RED else WHITE
end

return Hud
