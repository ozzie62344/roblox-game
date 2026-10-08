-- Dev panel (press P). Only shows for players the server marks as devs
-- (anyone in Studio, plus the game owner / DEV_USER_IDS in DevService).

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Abilities = require(ReplicatedStorage.Shared.Abilities)
local Weapons = require(ReplicatedStorage.Shared.Weapons)
local state = require(script.Parent.Parent.PlayerState)
local WeaponController = require(script.Parent.Parent.Combat.WeaponController)

local DevAction = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("DevAction") :: RemoteEvent
local MatchState = ReplicatedStorage:WaitForChild("MatchState")

local player = Players.LocalPlayer

local DevPanel = {}

local BUTTON_COLOR = Color3.fromRGB(45, 48, 56)
local ACTIVE_COLOR = Color3.fromRGB(60, 130, 230)

local panel: ScrollingFrame
local refreshers: { () -> () } = {}

local function styleButton(b: TextButton, text: string)
	b.BackgroundColor3 = BUTTON_COLOR
	b.BorderSizePixel = 0
	b.Font = Enum.Font.GothamMedium
	b.TextSize = 14
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Text = text
	b.AutoButtonColor = true
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = b
end

local function button(parent: Instance, text: string, order: number): TextButton
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(1, 0, 0, 30)
	b.LayoutOrder = order
	styleButton(b, text)
	b.Parent = parent
	return b
end

local function heading(parent: Instance, text: string, order: number)
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(1, 0, 0, 20)
	l.LayoutOrder = order
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextSize = 12
	l.TextColor3 = Color3.fromRGB(160, 165, 175)
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = text
	l.Parent = parent
end

-- A grid of buttons where the current value is highlighted
local function choiceGrid(
	parent: Instance,
	order: number,
	choices: { { value: string, label: string } },
	getCurrent: () -> string,
	onPick: (value: string) -> ()
)
	local grid = Instance.new("Frame")
	grid.Size = UDim2.new(1, 0, 0, 0)
	grid.AutomaticSize = Enum.AutomaticSize.Y
	grid.LayoutOrder = order
	grid.BackgroundTransparency = 1
	grid.Parent = parent
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.new(0.5, -3, 0, 28)
	layout.CellPadding = UDim2.fromOffset(6, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid

	local buttons: { [string]: TextButton } = {}
	for i, choice in choices do
		local b = Instance.new("TextButton")
		b.LayoutOrder = i
		styleButton(b, choice.label)
		b.Activated:Connect(function()
			onPick(choice.value)
		end)
		b.Parent = grid
		buttons[choice.value] = b
	end

	local function refresh()
		local current = getCurrent()
		for value, b in buttons do
			b.BackgroundColor3 = if value == current then ACTIVE_COLOR else BUTTON_COLOR
		end
	end
	table.insert(refreshers, refresh)
	refresh()
end

local function refreshAll()
	for _, refresh in refreshers do
		refresh()
	end
end

local function setOpen(open: boolean)
	state.devPanelOpen = open
	panel.Visible = open
	if open then
		refreshAll()
	end
end

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "DevPanel"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 10
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Scrolls when the panel is taller than the screen (mouse wheel or drag the bar)
	panel = Instance.new("ScrollingFrame")
	panel.Size = UDim2.fromOffset(280, 400)
	panel.Position = UDim2.fromOffset(20, 80)
	panel.BackgroundColor3 = Color3.fromRGB(24, 26, 31)
	panel.BackgroundTransparency = 0.05
	panel.BorderSizePixel = 0
	panel.ScrollingDirection = Enum.ScrollingDirection.Y
	panel.ScrollBarThickness = 6
	panel.ScrollBarImageColor3 = Color3.fromRGB(120, 125, 135)
	panel.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar
	panel.CanvasSize = UDim2.new()
	panel.AutomaticCanvasSize = Enum.AutomaticSize.Y
	panel.Visible = false
	panel.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = panel
	local padding = Instance.new("UIPadding")
	for _, side in { "PaddingTop", "PaddingBottom", "PaddingLeft", "PaddingRight" } do
		(padding :: any)[side] = UDim.new(0, 12)
	end
	padding.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = panel

	-- As tall as the content, but never taller than the screen (then it scrolls)
	local function fitToScreen()
		local screenHeight = gui.AbsoluteSize.Y
		local contentHeight = layout.AbsoluteContentSize.Y + 24 -- + top/bottom padding
		panel.Size = UDim2.fromOffset(280, math.min(contentHeight, screenHeight - 100))
	end
	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(fitToScreen)
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitToScreen)
	task.defer(fitToScreen)

	heading(panel, "DEV PANEL  (P to close)", 0)

	heading(panel, "WEAPON", 1)
	local weaponChoices = {}
	local weaponNames = {}
	for name in Weapons do
		table.insert(weaponNames, name)
	end
	table.sort(weaponNames)
	for _, name in weaponNames do
		table.insert(weaponChoices, { value = name, label = name })
	end
	choiceGrid(panel, 2, weaponChoices, function()
		return player:GetAttribute("Weapon") or "Rifle"
	end, function(name)
		DevAction:FireServer("SetWeapon", name)
	end)

	heading(panel, "ABILITY", 3)
	local abilityChoices = { { value = "None", label = "None" } }
	local abilityNames = {}
	for name in Abilities do
		table.insert(abilityNames, name)
	end
	table.sort(abilityNames)
	for _, name in abilityNames do
		table.insert(abilityChoices, { value = name, label = Abilities[name].Name })
	end
	choiceGrid(panel, 4, abilityChoices, function()
		return player:GetAttribute("Ability") or "None"
	end, function(ability)
		DevAction:FireServer("SetAbility", ability)
	end)

	heading(panel, "TESTING", 10)
	button(panel, "Spawn target dummy", 11).Activated:Connect(function()
		DevAction:FireServer("SpawnDummy")
	end)
	button(panel, "Clear dummies", 12).Activated:Connect(function()
		DevAction:FireServer("ClearDummies")
	end)
	button(panel, "Heal", 13).Activated:Connect(function()
		DevAction:FireServer("Heal")
	end)
	button(panel, "Clear covers", 15).Activated:Connect(function()
		DevAction:FireServer("ClearCovers")
	end)
	button(panel, "Refill ammo + ability charges", 14).Activated:Connect(function()
		DevAction:FireServer("RefillAmmo")
		WeaponController.Refill()
	end)

	heading(panel, "MATCH", 20)
	heading(panel, "Loadouts each round:", 21)
	choiceGrid(panel, 22, {
		{ value = "Draft", label = "Draft (pick 1 of 3)" },
		{ value = "Random", label = "Random" },
	}, function()
		return MatchState:GetAttribute("LoadoutMode") or "Draft"
	end, function(mode)
		DevAction:FireServer("SetLoadoutMode", mode)
	end)
	button(panel, "Start match now (works solo)", 23).Activated:Connect(function()
		DevAction:FireServer("StartMatch")
	end)
	button(panel, "End round", 24).Activated:Connect(function()
		DevAction:FireServer("EndRound")
	end)
	button(panel, "Stop match", 25).Activated:Connect(function()
		DevAction:FireServer("StopMatch")
	end)

	-- MouseUnlock frees the cursor while the panel is open (state.devPanelOpen)
	local close = button(panel, "Close", 30)
	close.BackgroundColor3 = Color3.fromRGB(120, 50, 50)
	close.Activated:Connect(function()
		setOpen(false)
	end)

	player:GetAttributeChangedSignal("Ability"):Connect(refreshAll)
	player:GetAttributeChangedSignal("Weapon"):Connect(refreshAll)
	MatchState:GetAttributeChangedSignal("LoadoutMode"):Connect(refreshAll)
end

function DevPanel.Start()
	build()
	ContextActionService:BindAction("ToggleDevPanel", function(_, inputState)
		if inputState == Enum.UserInputState.Begin and player:GetAttribute("IsDev") then
			setOpen(not panel.Visible)
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.P)
end

return DevPanel
