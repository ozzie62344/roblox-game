-- Loadout cards shown during the pre-round freeze.
--   Draft:  3 cards — click one or press 1 / 2 / 3. You can change your pick until the timer ends.
--   Random: one card showing what you rolled.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Abilities = require(ReplicatedStorage.Shared.Abilities)
local MatchConfig = require(ReplicatedStorage.Shared.MatchConfig)
local Weapons = require(ReplicatedStorage.Shared.Weapons)
local state = require(script.Parent.Parent.PlayerState)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local LoadoutOffer = Remotes:WaitForChild("LoadoutOffer") :: RemoteEvent
local DraftPick = Remotes:WaitForChild("DraftPick") :: RemoteEvent

local player = Players.LocalPlayer

local LoadoutPicker = {}

local CARD_COLOR = Color3.fromRGB(28, 30, 36)
local SELECTED_COLOR = Color3.fromRGB(50, 110, 220)
local PICK_KEYS = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three }

local root: Frame
local title: TextLabel
local timerBar: Frame
local cardRow: Frame
local hint: TextLabel
local cards: { TextButton } = {}
local deadline = 0
local offeredAt = 0
local isDraft = false
local selected: number? = nil

type Loadout = { Weapon: string, Ability: string }

local function textLabel(parent: Instance, text: string, size: number, color: Color3?, order: number): TextLabel
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(1, 0, 0, size + 6)
	l.LayoutOrder = order
	l.BackgroundTransparency = 1
	l.Font = if size >= 20 then Enum.Font.GothamBlack else Enum.Font.GothamMedium
	l.TextSize = size
	l.TextColor3 = color or Color3.new(1, 1, 1)
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextWrapped = true
	l.Text = text
	l.Parent = parent
	return l
end

local function fireRateText(weapon: Weapons.Weapon): string
	return if weapon.Automatic then `{weapon.RPM} RPM auto` else `{weapon.RPM} RPM semi`
end

local function damageText(weapon: Weapons.Weapon): string
	return if weapon.Pellets > 1 then `{weapon.Damage} × {weapon.Pellets} pellets` else `{weapon.Damage} dmg`
end

local function refreshSelection()
	for i, card in cards do
		card.BackgroundColor3 = if i == selected then SELECTED_COLOR else CARD_COLOR
	end
end

local function pick(index: number)
	if not isDraft or not cards[index] then
		return
	end
	selected = index
	DraftPick:FireServer(index)
	refreshSelection()
end

-- The pick window is over (the round started): close everything
local function close()
	root.Visible = false
	hint.Visible = false
	state.draftOpen = false
	state.loadoutWindow = false
	ContextActionService:UnbindAction("DraftPick")
end

local function makeCard(index: number, loadout: Loadout): TextButton
	local weapon = Weapons[loadout.Weapon]
	local ability = Abilities[loadout.Ability]

	local card = Instance.new("TextButton")
	card.Size = UDim2.fromOffset(220, 250)
	card.LayoutOrder = index
	card.BackgroundColor3 = CARD_COLOR
	card.AutoButtonColor = isDraft
	card.Text = ""
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = card
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 14)
	padding.PaddingLeft = UDim.new(0, 14)
	padding.PaddingRight = UDim.new(0, 14)
	padding.Parent = card
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 2)
	layout.Parent = card

	local grey = Color3.fromRGB(165, 170, 180)
	if isDraft then
		textLabel(card, `[{index}]`, 13, grey, 0)
	end
	if weapon then
		textLabel(card, string.upper(weapon.Name), 26, nil, 1)
		textLabel(card, weapon.Description, 13, grey, 2)
		textLabel(card, `{damageText(weapon)}  ·  {fireRateText(weapon)}`, 13, nil, 3)
		textLabel(card, `{weapon.MagazineSize} round magazine`, 13, nil, 4)
	else
		-- Knives Only
		textLabel(card, "KNIFE", 26, nil, 1)
		textLabel(card, "No guns this match.", 13, grey, 2)
		textLabel(card, "One stab kills  ·  quick recharge", 13, nil, 3)
	end
	textLabel(card, " ", 8, nil, 5)
	if ability then
		textLabel(card, `{string.upper(ability.Name)}  [{ability.Key}]`, 18, Color3.fromRGB(120, 190, 255), 6)
		textLabel(card, ability.Description, 13, grey, 7).Size = UDim2.new(1, 0, 0, 40)
	end

	card.Activated:Connect(function()
		pick(index)
	end)
	card.Parent = cardRow
	return card
end

local function onOffer(options: { Loadout }, newDeadline: number, isRandom: boolean)
	for _, card in cards do
		card:Destroy()
	end
	table.clear(cards)
	deadline = newDeadline
	offeredAt = Workspace:GetServerTimeNow()
	isDraft = not isRandom
	selected = nil

	-- Pick with a click or 1 / 2 / 3. Left Alt hides the cards so you can look around, and brings
	-- them back — any time until the round starts.
	title.Text = if not isDraft then "YOUR LOADOUT"
		elseif state.touchControls then "PICK YOUR LOADOUT  ·  TAP A CARD"
		else "PICK YOUR LOADOUT  ·  CLICK OR 1 / 2 / 3  ·  ALT TO HIDE"
	for i, loadout in options do
		cards[i] = makeCard(i, loadout)
	end
	refreshSelection()
	root.Visible = true

	if isDraft then
		-- Draft needs the mouse (MouseUnlock frees it while the cards are open); Random is just information
		state.loadoutWindow = true
		state.draftOpen = true
		ContextActionService:BindAction("DraftPick", function(_, inputState, input)
			if inputState == Enum.UserInputState.Begin then
				local index = table.find(PICK_KEYS, input.KeyCode)
				if index then
					pick(index)
				end
			end
			return Enum.ContextActionResult.Sink
		end, false, table.unpack(PICK_KEYS))
	end
end

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "LoadoutPicker"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5
	gui.Parent = player:WaitForChild("PlayerGui")

	root = Instance.new("Frame")
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.55)
	root.Size = UDim2.fromOffset(720, 330)
	root.BackgroundTransparency = 1
	root.Visible = false
	root.Parent = gui

	title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 36)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 24
	title.TextColor3 = Color3.new(1, 1, 1)
	title.TextStrokeTransparency = 0.5
	title.Parent = root

	local timerBack = Instance.new("Frame")
	timerBack.Position = UDim2.new(0.5, -150, 0, 42)
	timerBack.Size = UDim2.fromOffset(300, 4)
	timerBack.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
	timerBack.BorderSizePixel = 0
	timerBack.Parent = root
	timerBar = Instance.new("Frame")
	timerBar.Size = UDim2.fromScale(1, 1)
	timerBar.BackgroundColor3 = Color3.new(1, 1, 1)
	timerBar.BorderSizePixel = 0
	timerBar.Parent = timerBack

	-- Shown while the cards are hidden but you can still change your mind
	hint = Instance.new("TextLabel")
	hint.AnchorPoint = Vector2.new(0.5, 0)
	hint.Position = UDim2.new(0.5, 0, 0, 112)
	hint.Size = UDim2.fromOffset(420, 24)
	hint.BackgroundColor3 = Color3.fromRGB(15, 16, 20)
	hint.BackgroundTransparency = 0.35
	hint.Font = Enum.Font.Michroma
	hint.TextSize = 13
	hint.TextColor3 = Color3.fromRGB(255, 200, 90)
	hint.Visible = false
	hint.Parent = gui

	cardRow = Instance.new("Frame")
	cardRow.Position = UDim2.fromOffset(0, 60)
	cardRow.Size = UDim2.new(1, 0, 0, 260)
	cardRow.BackgroundTransparency = 1
	cardRow.Parent = root
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 16)
	layout.Parent = cardRow
end

local function update()
	local now = Workspace:GetServerTimeNow()
	local remaining = deadline - now
	if isDraft then
		if not state.loadoutWindow then
			return
		end
		if remaining <= 0 then
			close()
			return
		end
		-- Cards open or hidden (Left Alt toggles state.draftOpen in MouseUnlock)
		root.Visible = state.draftOpen
		hint.Visible = not state.draftOpen
		hint.Text = `{if state.touchControls then "TAP LOADOUT" else "LEFT ALT"}  ·  CHANGE LOADOUT  ({math.ceil(remaining)}s)`
	else
		-- Random: just show what you got for a few seconds
		if not root.Visible then
			return
		end
		if remaining <= 0 or now - offeredAt > MatchConfig.PreRoundTime then
			root.Visible = false
			return
		end
	end
	local total = math.max(deadline - offeredAt, 0.1)
	timerBar.Size = UDim2.fromScale(math.clamp(remaining / total, 0, 1), 1)
end

function LoadoutPicker.Start()
	build()
	LoadoutOffer.OnClientEvent:Connect(onOffer)
	RunService.RenderStepped:Connect(update)
end

return LoadoutPicker
