-- Dev panel (press P). Shows for players the server marks as devs (everyone, for now: DevService).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Abilities = require(ReplicatedStorage.Shared.Abilities)
local MatchConfig = require(ReplicatedStorage.Shared.MatchConfig)
local Weapons = require(ReplicatedStorage.Shared.Weapons)
local state = require(script.Parent.Parent.PlayerState)
local WeaponController = require(script.Parent.Parent.Combat.WeaponController)
local Actions = require(script.Parent.Parent.Input.Actions)

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

-- One row per player: name, then Blue / Random / Orange (their "TeamPick", used next match)
local TEAM_CHOICES = { { value = "Blue", label = "Blue" }, { value = "Auto", label = "Random" }, { value = "Orange", label = "Orange" } }

local function buildTeamRows(list: Frame, leaving: Player?)
	for _, child in list:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for i, other in Players:GetPlayers() do
		if other == leaving then
			continue
		end
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 28)
		row.LayoutOrder = i
		row.BackgroundTransparency = 1
		row.Parent = list
		local name = Instance.new("TextLabel")
		name.Size = UDim2.new(0.31, 0, 1, 0)
		name.BackgroundTransparency = 1
		name.Font = Enum.Font.GothamMedium
		name.TextSize = 13
		name.TextColor3 = Color3.new(1, 1, 1)
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.Text = other.DisplayName
		name.Parent = row
		local pick = other:GetAttribute("TeamPick") or "Auto"
		for j, choice in TEAM_CHOICES do
			local b = Instance.new("TextButton")
			b.Size = UDim2.new(0.23, -4, 1, 0)
			b.Position = UDim2.new(0.31 + (j - 1) * 0.23, 4, 0, 0)
			styleButton(b, choice.label)
			b.TextSize = 12
			if choice.value == pick then
				local team = MatchConfig.Teams[choice.value]
				b.BackgroundColor3 = if team then team.Color.Color else ACTIVE_COLOR
			end
			b.Activated:Connect(function()
				DevAction:FireServer("SetTeam", { Player = other, Team = choice.value })
			end)
			b.Parent = row
		end
	end
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

	-- Your own setting (not sent to the server)
	local leanButton = button(panel, "", 5)
	local function showLean()
		leanButton.Text = if state.leanToggle then "Lean (Q / E): tap to toggle" else "Lean (Q / E): hold"
	end
	showLean()
	leanButton.Activated:Connect(function()
		state.leanToggle = not state.leanToggle
		showLean()
	end)

	heading(panel, "BETWEEN MATCHES", 6)
	button(panel, "Go to map (first person, test guns)", 7).Activated:Connect(function()
		DevAction:FireServer("GoToMap")
	end)
	button(panel, "Back to lobby (third person)", 8).Activated:Connect(function()
		DevAction:FireServer("GoToLobby")
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
	-- Coins: pick anyone in the server (◀ ▶, starts on you), then give or take some
	local coins = Instance.new("Frame")
	coins.Size = UDim2.new(1, 0, 0, 0)
	coins.AutomaticSize = Enum.AutomaticSize.Y
	coins.LayoutOrder = 16
	coins.BackgroundTransparency = 1
	coins.Parent = panel
	local coinsLayout = Instance.new("UIListLayout")
	coinsLayout.Padding = UDim.new(0, 4)
	coinsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	coinsLayout.Parent = coins
	heading(coins, "COINS (shop credits)", 1)
	local target: Player = player
	local pickRow = Instance.new("Frame")
	pickRow.Size = UDim2.new(1, 0, 0, 30)
	pickRow.LayoutOrder = 2
	pickRow.BackgroundTransparency = 1
	pickRow.Parent = coins
	local previous = Instance.new("TextButton")
	previous.Size = UDim2.new(0, 30, 1, 0)
	styleButton(previous, "◀")
	previous.Parent = pickRow
	local nextButton = Instance.new("TextButton")
	nextButton.AnchorPoint = Vector2.new(1, 0)
	nextButton.Position = UDim2.fromScale(1, 0)
	nextButton.Size = UDim2.new(0, 30, 1, 0)
	styleButton(nextButton, "▶")
	nextButton.Parent = pickRow
	local targetLabel = Instance.new("TextLabel")
	targetLabel.Position = UDim2.fromOffset(34, 0)
	targetLabel.Size = UDim2.new(1, -68, 1, 0)
	targetLabel.BackgroundTransparency = 1
	targetLabel.Font = Enum.Font.GothamMedium
	targetLabel.TextSize = 13
	targetLabel.TextColor3 = Color3.new(1, 1, 1)
	targetLabel.TextTruncate = Enum.TextTruncate.AtEnd
	targetLabel.Parent = pickRow
	local function showTarget()
		if target.Parent ~= Players then
			target = player -- (they left)
		end
		local credits = target:GetAttribute("Credits")
		targetLabel.Text = `{target.DisplayName} · {if typeof(credits) == "number" then credits else "?"} coins`
	end
	local function step(by: number)
		local list = Players:GetPlayers()
		local index = table.find(list, target) or 1
		target = list[(index - 1 + by) % #list + 1]
		showTarget()
	end
	previous.Activated:Connect(function()
		step(-1)
	end)
	nextButton.Activated:Connect(function()
		step(1)
	end)
	table.insert(refreshers, showTarget)
	local amounts = Instance.new("Frame")
	amounts.Size = UDim2.new(1, 0, 0, 0)
	amounts.AutomaticSize = Enum.AutomaticSize.Y
	amounts.LayoutOrder = 3
	amounts.BackgroundTransparency = 1
	amounts.Parent = coins
	local amountGrid = Instance.new("UIGridLayout")
	amountGrid.CellSize = UDim2.new(0.25, -5, 0, 28)
	amountGrid.CellPadding = UDim2.fromOffset(6, 6)
	amountGrid.SortOrder = Enum.SortOrder.LayoutOrder
	amountGrid.Parent = amounts
	for i, amount in { 100, 1000, 10000, -1000 } do
		local b = Instance.new("TextButton")
		b.LayoutOrder = i
		styleButton(b, if amount > 0 then `+{amount}` else tostring(amount))
		b.Activated:Connect(function()
			DevAction:FireServer("GiveCoins", { Player = target, Amount = amount })
			task.delay(0.5, showTarget) -- (once the server has updated their total)
		end)
		b.Parent = amounts
	end
	showTarget()

	heading(panel, "MAP (ends any match)", 26)
	choiceGrid(panel, 27, {
		{ value = "House", label = "House" },
		{ value = "Warehouse", label = "Warehouse" },
		{ value = "Chalet", label = "Chalet" },
		{ value = "TestArena", label = "Test Arena" },
	}, function()
		return MatchState:GetAttribute("Map") or "House"
	end, function(mapName)
		DevAction:FireServer("LoadMap", mapName)
	end)

	heading(panel, "MATCH", 17)
	heading(panel, "Game mode (applies next match):", 18)
	choiceGrid(panel, 19, {
		{ value = "AttackDefend", label = "Attack / Defend" },
		{ value = "Elimination", label = "Elimination" },
	}, function()
		return MatchState:GetAttribute("GameMode") or "AttackDefend"
	end, function(mode)
		DevAction:FireServer("SetGameMode", mode)
	end)
	heading(panel, "Loadouts each round:", 21)
	choiceGrid(panel, 22, {
		{ value = "Draft", label = "Draft (pick 1 of 3)" },
		{ value = "Random", label = "Random" },
	}, function()
		return MatchState:GetAttribute("LoadoutMode") or "Draft"
	end, function(mode)
		DevAction:FireServer("SetLoadoutMode", mode)
	end)
	heading(panel, "TEAMS (applies next match)", 28)
	local teamList = Instance.new("Frame")
	teamList.Size = UDim2.new(1, 0, 0, 0)
	teamList.AutomaticSize = Enum.AutomaticSize.Y
	teamList.LayoutOrder = 29
	teamList.BackgroundTransparency = 1
	teamList.Parent = panel
	local teamLayout = Instance.new("UIListLayout")
	teamLayout.Padding = UDim.new(0, 4)
	teamLayout.SortOrder = Enum.SortOrder.LayoutOrder
	teamLayout.Parent = teamList
	local function rebuildTeams(leaving: Player?)
		buildTeamRows(teamList, leaving)
	end
	local function watch(other: Player)
		other:GetAttributeChangedSignal("TeamPick"):Connect(rebuildTeams)
	end
	for _, other in Players:GetPlayers() do
		watch(other)
	end
	Players.PlayerAdded:Connect(function(other)
		watch(other)
		rebuildTeams()
	end)
	Players.PlayerRemoving:Connect(rebuildTeams)
	rebuildTeams()

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
	MatchState:GetAttributeChangedSignal("GameMode"):Connect(refreshAll)
	MatchState:GetAttributeChangedSignal("Map"):Connect(refreshAll)
end

function DevPanel.Start()
	build()
	Actions.Bind("ToggleDevPanel", function(_, inputState)
		if inputState == Enum.UserInputState.Begin and player:GetAttribute("IsDev") then
			setOpen(not panel.Visible)
		end
		return Enum.ContextActionResult.Sink
	end, Enum.KeyCode.P)
end

return DevPanel
