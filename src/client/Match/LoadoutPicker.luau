-- Operator cards shown during the pre-round freeze (LoadoutService sends them).
--   Draft:  a card for every operator on your side: name, one-line bio, gadget and the guns they
--           can take in this mode. Click a card (or press 1-6) to play them with the highlighted
--           gun, or click a gun on a card to take that one. You can change until the timer ends.
--           A teammate's operator is greyed out with their name on it; once you've used your
--           gadget (defenders during setup) you're locked in, but can still change guns.
--   Random: one card showing who you got.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Abilities = require(ReplicatedStorage.Shared.Abilities)
local GameRules = require(ReplicatedStorage.Shared.GameRules)
local MatchConfig = require(ReplicatedStorage.Shared.MatchConfig)
local Operators = require(ReplicatedStorage.Shared.Operators)
local Weapons = require(ReplicatedStorage.Shared.Weapons)
local state = require(script.Parent.Parent.PlayerState)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local LoadoutOffer = Remotes:WaitForChild("LoadoutOffer") :: RemoteEvent
local DraftPick = Remotes:WaitForChild("DraftPick") :: RemoteEvent
local MatchState = ReplicatedStorage:WaitForChild("MatchState")

local player = Players.LocalPlayer

local LoadoutPicker = {}

local CARD_COLOR = Color3.fromRGB(28, 30, 36)
local SELECTED_COLOR = Color3.fromRGB(50, 110, 220)
local CHIP_COLOR = Color3.fromRGB(44, 47, 56)
local GREY = Color3.fromRGB(165, 170, 180)
local DIM = Color3.fromRGB(95, 98, 106)
local GADGET_COLOR = Color3.fromRGB(120, 190, 255)
local TAKEN_COLOR = Color3.fromRGB(255, 170, 70)
local CARD_WIDTH, CARD_HEIGHT, CARD_GAP = 178, 360, 12
local CARDS_TOP = 72 -- title, timer bar and your team's picks above the cards
local PICK_KEYS = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five, Enum.KeyCode.Six }

type OfferEntry = { Id: string, Weapons: { string }, TakenBy: string? }
type Offer = {
	Side: string,
	Random: boolean,
	Deadline: number,
	Operators: { OfferEntry },
	Pick: { Operator: string, Weapon: string }?,
	Locked: boolean,
}

local root: Frame
local scale: UIScale
local title: TextLabel
local timerBar: Frame
local cardRow: Frame
local teamLine: TextLabel
local hint: TextLabel
local lastPhase: string? = nil
local cards: { GuiObject } = {}
local offer: Offer? = nil
local deadline = 0
local offeredAt = 0
local isDraft = false
local selected: string? = nil -- operator you're playing (or just clicked, until the server answers)
local chosenGun: { [string]: string } = {} -- the highlighted gun on each card

local function textLabel(parent: Instance, text: string, size: number, color: Color3?, order: number): TextLabel
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(1, 0, 0, size + 6)
	l.LayoutOrder = order
	l.BackgroundTransparency = 1
	l.Font = if size >= 20 then Enum.Font.GothamBlack else Enum.Font.GothamMedium
	l.TextSize = size
	l.TextColor3 = color or Color3.new(1, 1, 1)
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Top
	l.TextWrapped = true
	l.Text = text
	l.Parent = parent
	return l
end

local function gunName(name: string): string
	local weapon = Weapons[name]
	return string.upper(if weapon then weapon.Name elseif name == GameRules.NoGun then "Knife" else name)
end

local function gunInfo(name: string): string
	local weapon = Weapons[name]
	if not weapon then
		return "No guns this match. One stab kills."
	end
	return weapon.Description
end

-- Used a charge of your gadget this round? Then you can't change operator (LoadoutService)
local function locked(): boolean
	if offer and offer.Locked then
		return true
	end
	local ability = Abilities[player:GetAttribute("Ability") or ""]
	local charges = player:GetAttribute("AbilityCharges")
	return ability ~= nil and ability.Charges ~= nil and typeof(charges) == "number" and charges < ability.Charges
end

-- The gun a card has highlighted: the one you clicked, the one you're playing them with, the one
-- in your hands if they can take it, or their first
local function gunFor(entry: OfferEntry): string
	local chosen = chosenGun[entry.Id]
	if chosen and table.find(entry.Weapons, chosen) then
		return chosen
	end
	local holding = player:GetAttribute("Weapon")
	if typeof(holding) == "string" and table.find(entry.Weapons, holding) then
		return holding
	end
	return entry.Weapons[1] or GameRules.NoGun
end

local render: () -> ()

local function pick(index: number, gun: string?)
	local entry = offer and offer.Operators[index]
	if not isDraft or not entry or entry.TakenBy then
		return
	end
	if locked() and entry.Id ~= player:GetAttribute("Operator") then
		return -- (the card says why)
	end
	if gun then
		chosenGun[entry.Id] = gun
	end
	selected = entry.Id
	DraftPick:FireServer(entry.Id, gunFor(entry))
	render()
end

-- The pick window is over (the round started): close everything
local function close()
	root.Visible = false
	hint.Visible = false
	state.draftOpen = false
	state.loadoutWindow = false
	ContextActionService:UnbindAction("DraftPick")
end

local function makeCard(index: number, entry: OfferEntry): TextButton?
	local operator = Operators.ById[entry.Id]
	if not operator then
		return nil
	end
	local gadget = Abilities[operator.Gadget]
	local mine = entry.Id == selected
	local blockedBy = if entry.TakenBy then `TAKEN  ·  {string.upper(entry.TakenBy)}`
		elseif isDraft and not mine and locked() then "LOCKED IN: GADGET USED"
		else nil
	local active = isDraft and not blockedBy

	local card = Instance.new("TextButton")
	card.Size = UDim2.fromOffset(CARD_WIDTH, CARD_HEIGHT)
	card.LayoutOrder = index
	card.BackgroundColor3 = if mine then SELECTED_COLOR else CARD_COLOR
	card.BackgroundTransparency = if blockedBy then 0.45 else 0
	card.AutoButtonColor = active
	card.Text = ""
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = card
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = operator.Color
	stroke.Thickness = if mine then 2 else 1
	stroke.Transparency = if blockedBy then 0.8 else 0.35
	stroke.Parent = card
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 12)
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = card
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 2)
	layout.Parent = card

	local text = if blockedBy then DIM else GREY
	if isDraft then
		textLabel(card, `[{index}]`, 12, text, 0)
	end
	textLabel(card, string.upper(operator.Name), 24, if blockedBy then DIM else operator.Color, 1)
	-- Armor / speed pips over the bio, e.g. "ARMOR ●●○  SPEED ●○○"
	local armor, speed = operator.Armor or 2, operator.Speed or 2
	local ratings = `ARMOR {string.rep("●", armor)}{string.rep("○", 3 - armor)}  SPEED {string.rep("●", speed)}{string.rep("○", 3 - speed)}`
	textLabel(card, ratings .. "\n" .. operator.Bio, 12, text, 2).Size = UDim2.new(1, 0, 0, 58)
	if gadget then
		textLabel(card, `{string.upper(gadget.Name)}  [{gadget.Key}]`, 14, if blockedBy then DIM else GADGET_COLOR, 3)
		local description = textLabel(card, gadget.Description, 11, text, 4)
		description.Size = UDim2.new(1, 0, 0, 80)
		description.TextTruncate = Enum.TextTruncate.AtEnd
	end

	-- Guns: click one to play this operator with it
	local gun = gunFor(entry)
	for i, name in entry.Weapons do
		local chip = Instance.new("TextButton")
		chip.Size = UDim2.new(1, 0, 0, 22)
		chip.LayoutOrder = 10 + i
		chip.BackgroundColor3 = if name == gun and not blockedBy then operator.Color else CHIP_COLOR
		chip.BackgroundTransparency = if blockedBy then 0.6 else 0
		chip.AutoButtonColor = active
		chip.Font = Enum.Font.GothamBold
		chip.TextSize = 12
		chip.TextColor3 = if blockedBy then DIM elseif name == gun then Color3.fromRGB(15, 16, 20) else Color3.new(1, 1, 1)
		chip.Text = gunName(name)
		local chipCorner = Instance.new("UICorner")
		chipCorner.CornerRadius = UDim.new(0, 6)
		chipCorner.Parent = chip
		chip.Activated:Connect(function()
			pick(index, name)
		end)
		chip.Parent = card
	end
	textLabel(card, gunInfo(gun), 11, text, 20).Size = UDim2.new(1, 0, 0, 28)
	if blockedBy then
		textLabel(card, blockedBy, 12, TAKEN_COLOR, 21)
	end

	card.Activated:Connect(function()
		pick(index)
	end)
	card.Parent = cardRow
	return card
end

function render()
	for _, card in cards do
		card:Destroy()
	end
	table.clear(cards)
	local current = offer
	if not current then
		return
	end
	local count = 0
	for i, entry in current.Operators do
		-- Random: just the card you got
		if isDraft or entry.Id == selected then
			local card = makeCard(i, entry)
			if card then
				table.insert(cards, card)
				count += 1
			end
		end
	end
	root.Size = UDim2.fromOffset(math.max(count * (CARD_WIDTH + CARD_GAP) - CARD_GAP, 420), CARDS_TOP + CARD_HEIGHT)
end

local function onOffer(newOffer: Offer)
	local newRound = newOffer.Deadline ~= deadline
	offer = newOffer
	deadline = newOffer.Deadline
	isDraft = not newOffer.Random
	if newRound then
		offeredAt = Workspace:GetServerTimeNow()
		table.clear(chosenGun)
	end
	-- The server's word on who you are (it may have refused a pick: taken a moment ago)
	selected = if newOffer.Pick then newOffer.Pick.Operator else nil
	if newOffer.Pick then
		chosenGun[newOffer.Pick.Operator] = newOffer.Pick.Weapon
	end

	local side = string.upper(newOffer.Side)
	title.Text = if not isDraft then `YOUR OPERATOR  ·  {side}`
		elseif state.touchControls then `PICK YOUR OPERATOR  ·  {side}  ·  TAP A CARD`
		else `PICK YOUR OPERATOR  ·  {side}  ·  CLICK OR 1-{#newOffer.Operators}  ·  ALT TO HIDE`
	render()
	if not newRound then
		return -- a teammate picked: just the cards change (hidden cards stay hidden)
	end
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
	root.Size = UDim2.fromOffset(720, CARDS_TOP + CARD_HEIGHT)
	root.BackgroundTransparency = 1
	root.Visible = false
	root.Parent = gui
	-- Six cards don't fit a phone: everything shrinks to fit the screen
	scale = Instance.new("UIScale")
	scale.Parent = root

	title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 36)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 22
	title.TextColor3 = Color3.new(1, 1, 1)
	title.TextStrokeTransparency = 0.5
	title.Parent = root

	local timerBack = Instance.new("Frame")
	timerBack.AnchorPoint = Vector2.new(0.5, 0)
	timerBack.Position = UDim2.new(0.5, 0, 0, 42)
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

	-- Your team's picks so far (Siege shows who's taken what)
	teamLine = Instance.new("TextLabel")
	teamLine.Position = UDim2.fromOffset(0, 50)
	teamLine.Size = UDim2.new(1, 0, 0, 16)
	teamLine.BackgroundTransparency = 1
	teamLine.Font = Enum.Font.GothamBold
	teamLine.TextSize = 13
	teamLine.TextColor3 = GREY
	teamLine.TextStrokeTransparency = 0.6
	teamLine.RichText = true
	teamLine.TextTruncate = Enum.TextTruncate.AtEnd
	teamLine.Parent = root

	cardRow = Instance.new("Frame")
	cardRow.Position = UDim2.fromOffset(0, CARDS_TOP)
	cardRow.Size = UDim2.new(1, 0, 0, CARD_HEIGHT)
	cardRow.BackgroundTransparency = 1
	cardRow.Parent = root
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, CARD_GAP)
	layout.Parent = cardRow
end

-- "YOUR TEAM:  Ozzie VOLTA  ·  Sam choosing..." (operators replicate as player attributes)
local function teamPicks(): string
	local team = player.Team
	if not team then
		return ""
	end
	local parts = {}
	for _, member in team:GetPlayers() do
		local operator = Operators.ById[member:GetAttribute("Operator") or ""]
		local name = if member == player then "You" else member.DisplayName
		table.insert(parts, if operator
			then `{name} <font color="#{operator.Color:ToHex()}">{string.upper(operator.Name)}</font>`
			else `{name} <font color="#{DIM:ToHex()}">choosing...</font>`)
	end
	return "YOUR TEAM:  " .. table.concat(parts, "   ·   ")
end

local function update()
	local now = Workspace:GetServerTimeNow()
	local remaining = deadline - now
	-- Operator selection is over and the setup has started: cards away so you can get to work
	-- (Left Alt / LOADOUT still brings them back until the round starts)
	local phase = MatchState:GetAttribute("Phase")
	if phase ~= lastPhase then
		lastPhase = phase
		if phase == "Prep" then
			state.draftOpen = false
		end
	end
	if root.Visible then
		teamLine.Text = teamPicks()
	end
	-- Fit the row on screen (a little margin; never bigger than designed)
	local viewport = Workspace.CurrentCamera.ViewportSize
	local size = root.Size
	scale.Scale = math.min(1, (viewport.X - 24) / size.X.Offset, viewport.Y * 0.88 / size.Y.Offset)
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
		hint.Text = `{if state.touchControls then "TAP LOADOUT" else "LEFT ALT"}  ·  CHANGE OPERATOR  ({math.ceil(remaining)}s)`
	else
		-- Random: just show who you got for a few seconds
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
	-- Using your gadget during setup locks your operator in: show it on the cards straight away
	player:GetAttributeChangedSignal("AbilityCharges"):Connect(function()
		if isDraft and state.loadoutWindow then
			render()
		end
	end)
end

return LoadoutPicker
