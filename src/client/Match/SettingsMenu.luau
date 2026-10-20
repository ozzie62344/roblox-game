-- SETTINGS: O (or F1), the gear at the bottom left in a match (above your health: Roblox's chat
-- has the top left), SETTINGS in the lobby (under the SHOP) or the SETTINGS button on a phone.
-- Four pages:
--   CONTROLS  mouse / touch look / aiming sensitivity, invert look, lean tap or hold, EDIT BUTTONS
--             (phones), and the keybinds (read only)
--   VIDEO     field of view, performance mode, the FPS / ping readout
--   AUDIO     master, effects, music and menu sound volumes
--   GAMEPLAY  crosshair colour and size, hit markers
-- Every change applies right away and is saved with your data a moment later (ClientSettings),
-- so it follows you to every server; RESET TO DEFAULTS puts everything back. The mouse is free and
-- you can't shoot while it's open.
-- Also here: the small FPS / ping readout in the bottom left corner (top left, under your health,
-- on a phone) when VIDEO → SHOW FPS & PING is on.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local PlayerSettings = require(ReplicatedStorage.Shared.PlayerSettings)
local state = require(script.Parent.Parent.PlayerState)
local ClientSettings = require(script.Parent.Parent.ClientSettings)
local Actions = require(script.Parent.Parent.Input.Actions)
local LobbyIntro = require(script.Parent.LobbyIntro)
local MenuStyle = require(script.Parent.MenuStyle)
local ModsMenu = require(script.Parent.ModsMenu)

local MatchState = ReplicatedStorage:WaitForChild("MatchState")

local player = Players.LocalPlayer

local SettingsMenu = {}

type Row = {
	kind: "slider" | "toggle" | "colors" | "button" | "header" | "note" | "keys",
	key: string?, -- the setting (ClientSettings / shared PlayerSettings)
	label: string?,
	format: ((number) -> string)?, -- sliders: how the value reads
	on: string?, -- toggles: the button's words (default ON / OFF)
	off: string?,
	press: (() -> ())?, -- buttons
	show: (() -> boolean)?, -- only on some devices
}

local PANEL_SIZE = Vector2.new(780, 540)
local CONTROL_X = 320 -- where the sliders / buttons start in a row
local TRACK = Color3.fromRGB(46, 50, 60)
local SOFT_TEXT = Color3.fromRGB(170, 176, 190)
local GOLD = Color3.fromRGB(255, 196, 60)
local CONFIRM_TIME = 3 -- seconds RESET waits for the second press

-- Everything the game binds (Actions.Bind in the controllers): action, keyboard / mouse, gamepad
local KEYBINDS = {
	{ "MOVE", "W A S D", "LEFT STICK" },
	{ "VAULT · CLIMB (GET UP FROM PRONE)", "SPACE", "A" },
	{ "SPRINT (HOLD)", "LEFT SHIFT", "L3" },
	{ "CROUCH (2 TAPS: PRONE)", "C / LEFT CTRL", "B" },
	{ "ABILITY (GADGET)", "X", "L1" },
	{ "FIRE", "LEFT MOUSE", "R2" },
	{ "AIM", "RIGHT MOUSE", "L2" },
	{ "RELOAD", "R", "X" },
	{ "KNIFE", "F", "R3" },
	{ "LEAN LEFT / RIGHT", "Q / E", "D-PAD LEFT / RIGHT" },
	{ "DRONE · CAMERAS", "Z", "D-PAD UP" },
	{ "RAPPEL", "V", "D-PAD DOWN" },
	{ "PLANT · DISABLE · FORTIFY (HOLD)", "G", "Y" },
	{ "PING", "MIDDLE MOUSE / T", "-" },
	{ "SCOREBOARD (HOLD)", "TAB", "-" },
	{ "MODS (ATTACHMENTS)", "M", "-" },
	{ "FREE MOUSE · LOADOUT", "LEFT ALT", "-" },
	{ "SETTINGS", "O / F1", "-" },
}

local gui: ScreenGui
local screen: Frame
local panel: Frame
local list: ScrollingFrame
local tabButtons: { [string]: TextButton } = {}
local resetButton: TextButton
local statusLabel: TextLabel
local hud: ScreenGui
local gear: TextButton
local gearTip: TextLabel
local lobbyHolder: Frame
local statsLabel: TextLabel

local currentPage = "Controls"
local refreshers: { () -> () } = {}
local dragging: { input: InputObject, set: (number) -> () }? = nil
local resetArmedAt = -math.huge

local function hasMouse(): boolean
	return UserInputService.MouseEnabled or UserInputService.KeyboardEnabled
end

local function hasTouch(): boolean
	return UserInputService.TouchEnabled
end

local function times(value: number): string
	return string.format("%.2f", value)
end

local function percent(value: number): string
	return `{math.floor(value * 100 + 0.5)}%`
end

local function editButtons()
	SettingsMenu.Close()
	-- (required here, not at the top: MobileControls requires this module)
	local MobileControls = require(script.Parent.Parent.Input.MobileControls) :: any
	MobileControls.EditButtons()
end

local PAGES: { { name: string, rows: { Row } } } = {
	{
		name = "Controls",
		rows = {
			{ kind = "slider", key = "MouseSensitivity", label = "MOUSE SENSITIVITY", format = times, show = hasMouse },
			{ kind = "slider", key = "TouchSensitivity", label = "TOUCH LOOK SENSITIVITY", format = times, show = hasTouch },
			{ kind = "slider", key = "AdsSensitivity", label = "AIMING SENSITIVITY", format = times },
			{ kind = "toggle", key = "InvertY", label = "INVERT LOOK UP / DOWN" },
			{ kind = "toggle", key = "LeanToggle", label = "LEAN", on = "TAP", off = "HOLD" },
			{ kind = "button", label = "PHONE BUTTONS", on = "EDIT", press = editButtons, show = hasTouch },
			{ kind = "header", label = "KEYBINDS" },
			{ kind = "keys" },
		},
	},
	{
		name = "Video",
		rows = {
			{
				kind = "slider", key = "Fov", label = "FIELD OF VIEW",
				format = function(value)
					return tostring(math.floor(value + 0.5))
				end,
			},
			{ kind = "toggle", key = "PerformanceMode", label = "PERFORMANCE MODE" },
			{ kind = "note", label = "PERFORMANCE MODE TURNS OFF BLOOM, SUN RAYS AND CLOUDS. GRAPHICS QUALITY ITSELF IS IN THE ROBLOX MENU (ESC)." },
			{ kind = "toggle", key = "ShowStats", label = "SHOW FPS & PING" },
		},
	},
	{
		name = "Audio",
		rows = {
			{ kind = "slider", key = "MasterVolume", label = "MASTER VOLUME", format = percent },
			{ kind = "slider", key = "EffectsVolume", label = "EFFECTS", format = percent },
			{ kind = "slider", key = "MusicVolume", label = "MUSIC", format = percent },
			{ kind = "slider", key = "UiVolume", label = "MENU SOUNDS", format = percent },
		},
	},
	{
		name = "Gameplay",
		rows = {
			{ kind = "colors", key = "CrosshairColor", label = "CROSSHAIR COLOUR" },
			{
				kind = "slider", key = "CrosshairSize", label = "CROSSHAIR SIZE",
				format = function(value)
					return string.format("%.1fx", value)
				end,
			},
			{ kind = "toggle", key = "HitMarkers", label = "HIT MARKERS" },
		},
	},
}

-- Smaller text needs a thinner outline than MenuStyle's chunky one
local function thinOutline(label: TextLabel, thickness: number)
	(label:FindFirstChildOfClass("UIStroke") :: UIStroke).Thickness = thickness
end

local function leftText(parent: Instance, text: string, size: UDim2, position: UDim2, anchor: Vector2?): TextLabel
	local label = MenuStyle.Text(parent, text, size, position, anchor)
	label.TextXAlignment = Enum.TextXAlignment.Left
	return label
end

local function newRow(order: number, height: number, label: string?): Frame
	local row = Instance.new("Frame")
	row.LayoutOrder = order
	row.Size = UDim2.new(1, -12, 0, height)
	row.BackgroundTransparency = 1
	row.Parent = list
	if label then
		thinOutline(leftText(row, label, UDim2.fromOffset(CONTROL_X - 20, 22), UDim2.new(0, 4, 0.5, 0), Vector2.new(0, 0.5)), 2)
	end
	return row
end

local function sliderRow(row: Frame, item: Row)
	local key = item.key :: string
	local def = PlayerSettings.ByKey[key]
	local min, max = def.Min :: number, def.Max :: number
	-- A tall invisible button over the thin track, so it's easy to grab (and drag) with a finger
	local hit = Instance.new("TextButton")
	hit.AnchorPoint = Vector2.new(0, 0.5)
	hit.Position = UDim2.new(0, CONTROL_X, 0.5, 0)
	hit.Size = UDim2.fromOffset(280, 40)
	hit.BackgroundTransparency = 1
	hit.Text = ""
	hit.Parent = row
	local track = Instance.new("Frame")
	track.AnchorPoint = Vector2.new(0, 0.5)
	track.Position = UDim2.fromScale(0, 0.5)
	track.Size = UDim2.new(1, 0, 0, 10)
	track.BackgroundColor3 = TRACK
	MenuStyle.Corner(track, UDim.new(1, 0))
	MenuStyle.Rim(track, MenuStyle.Outline, 2)
	track.Parent = hit
	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = MenuStyle.Blue
	MenuStyle.Corner(fill, UDim.new(1, 0))
	fill.Parent = track
	local knob = Instance.new("Frame")
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Size = UDim2.fromOffset(24, 24)
	knob.BackgroundColor3 = Color3.new(1, 1, 1)
	MenuStyle.Corner(knob, UDim.new(1, 0))
	MenuStyle.Rim(knob, MenuStyle.Outline, 3)
	knob.Parent = track
	local valueLabel = MenuStyle.Text(row, "", UDim2.fromOffset(110, 22), UDim2.new(1, -4, 0.5, 0), Vector2.new(1, 0.5))
	valueLabel.TextXAlignment = Enum.TextXAlignment.Right
	thinOutline(valueLabel, 2)

	local function refresh()
		local value = ClientSettings.Get(key)
		local alpha = math.clamp((value - min) / (max - min), 0, 1)
		fill.Size = UDim2.fromScale(alpha, 1)
		knob.Position = UDim2.fromScale(alpha, 0.5)
		valueLabel.Text = if item.format then item.format(value) else tostring(value)
	end
	local function set(x: number)
		local alpha = math.clamp((x - hit.AbsolutePosition.X) / math.max(hit.AbsoluteSize.X, 1), 0, 1)
		ClientSettings.Set(key, min + alpha * (max - min))
	end
	hit.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = { input = input, set = set }
			list.ScrollingEnabled = false -- (a finger sliding along it shouldn't scroll the page)
			set(input.Position.X)
		end
	end)
	table.insert(refreshers, refresh)
	refresh()
end

local function toggleRow(row: Frame, item: Row)
	local key = item.key :: string
	local button = MenuStyle.Button(row, "", MenuStyle.Grey, UDim2.fromOffset(150, 40), UDim2.new(0, CONTROL_X, 0.5, 0), Vector2.new(0, 0.5))
	local label = button:FindFirstChild("Label") :: TextLabel
	local function refresh()
		local on = ClientSettings.Get(key) == true
		label.Text = if on then item.on or "ON" else item.off or "OFF"
		MenuStyle.SetButtonColor(button, if on then MenuStyle.Green else MenuStyle.Grey)
	end
	button.Activated:Connect(function()
		ClientSettings.Set(key, not ClientSettings.Get(key))
	end)
	table.insert(refreshers, refresh)
	refresh()
end

-- Crosshair colours: a round swatch each, and a little preview of the crosshair on the right
local function colorsRow(row: Frame, item: Row)
	local key = item.key :: string
	local swatches: { [string]: UIStroke } = {}
	for i, name in PlayerSettings.CrosshairColorOrder do
		local swatch = Instance.new("TextButton")
		swatch.AnchorPoint = Vector2.new(0, 0.5)
		swatch.Position = UDim2.new(0, CONTROL_X + (i - 1) * 48, 0.5, 0)
		swatch.Size = UDim2.fromOffset(38, 38)
		swatch.Text = ""
		swatch.AutoButtonColor = false
		swatch.BackgroundColor3 = PlayerSettings.CrosshairColors[name]
		MenuStyle.Corner(swatch, UDim.new(1, 0))
		swatches[name] = MenuStyle.Rim(swatch, MenuStyle.Outline, 3)
		swatch.Activated:Connect(function()
			ClientSettings.Set(key, name)
		end)
		swatch.Parent = row
	end
	local preview = Instance.new("Frame")
	preview.AnchorPoint = Vector2.new(1, 0.5)
	preview.Position = UDim2.new(1, -4, 0.5, 0)
	preview.Size = UDim2.fromOffset(56, 56)
	preview.BackgroundColor3 = Color3.fromRGB(70, 78, 70)
	MenuStyle.Corner(preview, UDim.new(0, 10))
	MenuStyle.Rim(preview, MenuStyle.Outline, 2)
	preview.Parent = row
	local bars = {}
	for i = 1, 4 do
		local bar = Instance.new("Frame")
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.BorderSizePixel = 0
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 1
		stroke.Transparency = 0.6
		stroke.Parent = bar
		bar.Parent = preview
		bars[i] = bar
	end
	local function refresh()
		local chosen = ClientSettings.Get(key)
		for name, rim in swatches do
			rim.Color = if name == chosen then GOLD else MenuStyle.Outline
			rim.Thickness = if name == chosen then 4 else 3
		end
		-- (the same shape Hud draws: Hud.SetCrosshairStyle)
		local size = ClientSettings.Get("CrosshairSize")
		local length = math.floor(8 * size + 0.5)
		local thickness = if size >= 1.5 then 3 else 2
		local reach = 4 + 4 * size
		local color = PlayerSettings.CrosshairColors[chosen] or Color3.new(1, 1, 1)
		for i, bar in bars do
			local vertical = i <= 2
			local sign = if i % 2 == 1 then -1 else 1
			bar.Size = if vertical then UDim2.fromOffset(thickness, length) else UDim2.fromOffset(length, thickness)
			bar.Position = if vertical then UDim2.new(0.5, 0, 0.5, sign * reach) else UDim2.new(0.5, sign * reach, 0.5, 0)
			bar.BackgroundColor3 = color
		end
	end
	table.insert(refreshers, refresh)
	refresh()
end

-- The keybinds: action, keyboard / mouse, gamepad
local function keysRows(order: number)
	local function line(rowOrder: number, cells: { string }, color: Color3)
		local row = newRow(rowOrder, 24)
		for i, x in { 4, CONTROL_X, 560 } do
			local cell = leftText(row, cells[i], UDim2.fromOffset(if i == 1 then CONTROL_X - 16 else 230, 17), UDim2.new(0, x, 0.5, 0), Vector2.new(0, 0.5))
			cell.TextColor3 = color
			thinOutline(cell, 1.5)
		end
	end
	line(order, { "ACTION", "KEYBOARD / MOUSE", "GAMEPAD" }, SOFT_TEXT)
	for i, bind in KEYBINDS do
		line(order + i, bind, Color3.new(1, 1, 1))
	end
end

local function buildPage()
	dragging = nil
	list.ScrollingEnabled = true
	table.clear(refreshers)
	for _, child in list:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	list.CanvasPosition = Vector2.zero
	for name, button in tabButtons do
		MenuStyle.SetButtonColor(button, if name == currentPage then MenuStyle.Blue else MenuStyle.Grey)
	end
	local page
	for _, entry in PAGES do
		if entry.name == currentPage then
			page = entry
		end
	end
	local order = 0
	for _, item in page.rows do
		if item.show and not item.show() then
			continue
		end
		order += 1
		if item.kind == "keys" then
			keysRows(order * 100)
		elseif item.kind == "header" then
			local row = newRow(order * 100, 40)
			local title = leftText(row, item.label :: string, UDim2.fromOffset(300, 26), UDim2.new(0, 4, 1, -4), Vector2.new(0, 1))
			title.TextColor3 = GOLD
		elseif item.kind == "note" then
			local row = newRow(order * 100, 34)
			local note = leftText(row, item.label :: string, UDim2.new(1, -8, 1, -4), UDim2.new(0, 4, 0.5, 0), Vector2.new(0, 0.5))
			note.TextWrapped = true
			note.TextColor3 = SOFT_TEXT
			thinOutline(note, 1)
		else
			local row = newRow(order * 100, if item.kind == "colors" then 60 else 52, item.label)
			if item.kind == "slider" then
				sliderRow(row, item)
			elseif item.kind == "toggle" then
				toggleRow(row, item)
			elseif item.kind == "colors" then
				colorsRow(row, item)
			elseif item.kind == "button" then
				local button = MenuStyle.Button(row, item.on or "", MenuStyle.Blue, UDim2.fromOffset(150, 40), UDim2.new(0, CONTROL_X, 0.5, 0), Vector2.new(0, 0.5))
				button.Activated:Connect(item.press :: () -> ())
			end
		end
	end
end

local function refreshFooter()
	local armed = os.clock() - resetArmedAt < CONFIRM_TIME
	;(resetButton:FindFirstChild("Label") :: TextLabel).Text = if armed then "Sure? Press again" else "Reset to defaults"
	MenuStyle.SetButtonColor(resetButton, if armed then MenuStyle.Red else MenuStyle.Grey)
	statusLabel.Text = if player:GetAttribute("DataOffline") == true
		then "SAVING IS OFFLINE · KEPT UNTIL YOU LEAVE"
		else "SAVED WITH YOUR ACCOUNT · EVERY SERVER"
end

function SettingsMenu.Open()
	if state.settingsOpen then
		return
	end
	if state.modsOpen then
		ModsMenu.SetOpen(false)
	end
	state.settingsOpen = true
	screen.Visible = true
	resetArmedAt = -math.huge
	buildPage()
	refreshFooter()
end

function SettingsMenu.Close()
	state.settingsOpen = false
	screen.Visible = false
	dragging = nil
end

function SettingsMenu.Toggle()
	if state.settingsOpen then
		SettingsMenu.Close()
	else
		SettingsMenu.Open()
	end
end

local function buildMenu()
	gui = Instance.new("ScreenGui")
	gui.Name = "Settings"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 20 -- over every other menu (EDIT BUTTONS goes over this)
	gui.Parent = player:WaitForChild("PlayerGui")

	screen = Instance.new("Frame")
	screen.Size = UDim2.fromScale(1, 1)
	screen.BackgroundTransparency = 1
	screen.Visible = false
	screen.Parent = gui
	-- The game dimmed behind it; clicking there closes it
	local backdrop = Instance.new("TextButton")
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 0.45
	backdrop.AutoButtonColor = false
	backdrop.Text = ""
	backdrop.ZIndex = 0 -- (under the panel, which takes its own clicks so they don't close it)
	backdrop.Parent = screen
	backdrop.Activated:Connect(SettingsMenu.Close)

	panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(PANEL_SIZE.X, PANEL_SIZE.Y)
	panel.BackgroundColor3 = MenuStyle.Panel
	panel.BackgroundTransparency = 0.05
	panel.Active = true
	panel.Parent = screen
	MenuStyle.Corner(panel, UDim.new(0, 14))
	MenuStyle.Rim(panel, Color3.fromRGB(60, 64, 76), 2)
	MenuStyle.FitToScreen(panel, PANEL_SIZE)

	leftText(panel, "SETTINGS", UDim2.fromOffset(220, 36), UDim2.fromOffset(20, 14))
	local keyHint = leftText(panel, "O TO CLOSE", UDim2.fromOffset(160, 16), UDim2.fromOffset(250, 26))
	keyHint.TextColor3 = SOFT_TEXT
	thinOutline(keyHint, 1.5)
	keyHint.Visible = hasMouse()
	local close = MenuStyle.Button(panel, "Close", MenuStyle.Red, UDim2.fromOffset(120, 44), UDim2.new(1, -14, 0, 10), Vector2.new(1, 0))
	close.Activated:Connect(SettingsMenu.Close)

	for i, page in PAGES do
		local button = MenuStyle.Button(panel, page.name, MenuStyle.Grey, UDim2.fromOffset(170, 44), UDim2.fromOffset(20 + (i - 1) * 184, 68))
		button.Activated:Connect(function()
			currentPage = page.name
			buildPage()
		end)
		tabButtons[page.name] = button
	end

	list = Instance.new("ScrollingFrame")
	list.Position = UDim2.fromOffset(20, 124)
	list.Size = UDim2.new(1, -40, 1, -124 - 74)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 4)
	layout.Parent = list

	-- Footer: RESET TO DEFAULTS (press twice) and where it's saved
	resetButton = MenuStyle.Button(panel, "Reset to defaults", MenuStyle.Grey, UDim2.fromOffset(280, 50), UDim2.new(0, 20, 1, -14), Vector2.new(0, 1))
	resetButton.Activated:Connect(function()
		if os.clock() - resetArmedAt < CONFIRM_TIME then
			resetArmedAt = -math.huge
			ClientSettings.Reset()
		else
			resetArmedAt = os.clock()
		end
		refreshFooter()
		task.delay(CONFIRM_TIME, refreshFooter)
	end)
	statusLabel = MenuStyle.Text(panel, "", UDim2.fromOffset(420, 18), UDim2.new(1, -20, 1, -30), Vector2.new(1, 0.5))
	statusLabel.TextXAlignment = Enum.TextXAlignment.Right
	statusLabel.TextColor3 = SOFT_TEXT
	thinOutline(statusLabel, 1.5)
end

-- The gear (bottom left in a match, above the health), the lobby's SETTINGS button and the FPS /
-- ping readout
local function buildHud()
	hud = Instance.new("ScreenGui")
	hud.Name = "SettingsHud"
	hud.ResetOnSpawn = false
	hud.DisplayOrder = 3 -- under the lobby menus (their screens cover the lobby button)
	hud.Parent = player:WaitForChild("PlayerGui")

	gear = Instance.new("TextButton")
	gear.AnchorPoint = Vector2.new(0, 1)
	gear.Position = UDim2.new(0, 36, 1, -80)
	gear.Size = UDim2.fromOffset(40, 40)
	gear.BackgroundTransparency = 1
	gear.Text = ""
	gear.Parent = hud
	-- A gear drawn from bars (a text gear would come out as an emoji): teeth, body, hole
	local metal = Color3.fromRGB(215, 220, 230)
	for _, angle in { 0, 45, 90, 135 } do
		local tooth = Instance.new("Frame")
		tooth.AnchorPoint = Vector2.new(0.5, 0.5)
		tooth.Position = UDim2.fromScale(0.5, 0.5)
		tooth.Size = UDim2.fromOffset(34, 8)
		tooth.Rotation = angle
		tooth.BackgroundColor3 = metal
		MenuStyle.Corner(tooth, UDim.new(0, 2))
		tooth.Parent = gear
	end
	local body = Instance.new("Frame")
	body.AnchorPoint = Vector2.new(0.5, 0.5)
	body.Position = UDim2.fromScale(0.5, 0.5)
	body.Size = UDim2.fromOffset(26, 26)
	body.BackgroundColor3 = metal
	MenuStyle.Corner(body, UDim.new(1, 0))
	body.Parent = gear
	local hole = body:Clone()
	hole.Size = UDim2.fromOffset(11, 11)
	hole.BackgroundColor3 = MenuStyle.Panel
	hole.ZIndex = 2
	hole.Parent = gear
	local scale = Instance.new("UIScale")
	scale.Parent = gear
	gearTip = MenuStyle.Text(gear, "SETTINGS (O)", UDim2.fromOffset(130, 18), UDim2.new(1, 8, 0.5, 0), Vector2.new(0, 0.5))
	gearTip.TextXAlignment = Enum.TextXAlignment.Left
	thinOutline(gearTip, 1.5)
	gearTip.Visible = false
	gear.MouseEnter:Connect(function()
		scale.Scale = 1.1
		gearTip.Visible = true
	end)
	gear.MouseLeave:Connect(function()
		scale.Scale = 1
		gearTip.Visible = false
	end)
	gear.Activated:Connect(SettingsMenu.Open)

	-- Lobby: under the SHOP on the left
	lobbyHolder = Instance.new("Frame")
	lobbyHolder.Position = UDim2.new(0, 20, 0.5, 130)
	lobbyHolder.Size = UDim2.fromOffset(200, 60)
	lobbyHolder.BackgroundTransparency = 1
	lobbyHolder.Visible = false
	lobbyHolder.Parent = hud
	LobbyIntro.Animate(lobbyHolder)
	MenuStyle.FitToScreen(lobbyHolder, Vector2.new(900, 520))
	local lobbyButton = MenuStyle.Button(lobbyHolder, "Settings", Color3.fromRGB(100, 110, 130), UDim2.fromScale(1, 1), UDim2.new())
	lobbyButton.Activated:Connect(SettingsMenu.Open)

	statsLabel = Instance.new("TextLabel")
	statsLabel.Size = UDim2.fromOffset(180, 20)
	statsLabel.BackgroundTransparency = 1
	statsLabel.Font = Enum.Font.GothamMedium
	statsLabel.TextSize = 14
	statsLabel.TextColor3 = Color3.fromRGB(220, 225, 235)
	statsLabel.TextStrokeTransparency = 0.5
	statsLabel.TextXAlignment = Enum.TextXAlignment.Left
	statsLabel.Text = ""
	statsLabel.Visible = false
	statsLabel.Parent = hud
end

local inLobbyMenu = LobbyIntro.InLobby

function SettingsMenu.Start()
	ClientSettings.Start()
	buildMenu()
	buildHud()

	Actions.Bind("Settings", function(_, inputState)
		if inputState == Enum.UserInputState.Begin and not state.devPanelOpen then
			SettingsMenu.Toggle()
		end
		return Enum.ContextActionResult.Sink
	end, Enum.KeyCode.O, Enum.KeyCode.F1)

	ClientSettings.OnChanged(function()
		if state.settingsOpen then
			for _, refresh in refreshers do
				refresh()
			end
		end
	end)

	-- Dragging a slider (it keeps following the finger / mouse off the track)
	UserInputService.InputChanged:Connect(function(input)
		local drag = dragging
		if not drag then
			return
		end
		local mouse = drag.input.UserInputType == Enum.UserInputType.MouseButton1
		if input == drag.input or (mouse and input.UserInputType == Enum.UserInputType.MouseMovement) then
			drag.set(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		local drag = dragging
		local mouse = drag and drag.input.UserInputType == Enum.UserInputType.MouseButton1
		if drag and (input == drag.input or (mouse and input.UserInputType == Enum.UserInputType.MouseButton1)) then
			dragging = nil
			list.ScrollingEnabled = true
		end
	end)

	-- FPS: frames counted over half a second; ping: the round trip (twice Roblox's one-way figure)
	local frames, since = 0, os.clock()
	RunService.RenderStepped:Connect(function()
		local lobby = inLobbyMenu()
		lobbyHolder.Visible = LobbyIntro.Shown("Settings") and not (state.settingsOpen or state.shopOpen or state.modesOpen or state.partyOpen)
		gear.Visible = not lobby and not state.touchControls and not state.settingsOpen
		statsLabel.AnchorPoint = if state.touchControls then Vector2.zero else Vector2.new(0, 1)
		statsLabel.Position = if state.touchControls then UDim2.fromOffset(64, 44) else UDim2.new(0, 40, 1, -6)
		statsLabel.Visible = ClientSettings.Get("ShowStats") == true

		frames += 1
		local now = os.clock()
		if now - since >= 0.5 then
			local fps = math.floor(frames / (now - since) + 0.5)
			frames, since = 0, now
			if statsLabel.Visible then
				local ok, oneWay = pcall(player.GetNetworkPing, player)
				local ping = if ok and typeof(oneWay) == "number" then `{math.floor(oneWay * 2000 + 0.5)} MS` else "-"
				statsLabel.Text = `{fps} FPS  ·  {ping}`
			end
		end
	end)
end

return SettingsMenu
