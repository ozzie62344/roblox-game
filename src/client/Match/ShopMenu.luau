-- The SHOP (lobby): skins for your guns and knife, bought with credits earned in matches.
--   Left:   what you're dressing (each gun, the knife); the dot is the skin it wears now
--   Middle: a 3D preview (drag it to turn it) with BUY / EQUIP / EQUIP ON ALL
--   Right:  every skin as a paint chip, with its price, OWNED or EQUIPPED; or (MODS) the gun's
--           attachment slots: optic, muzzle, under barrel (shared/Attachments, free)
-- A bought skin works on every gun and the knife; buying one puts it on the selected item.
-- Dev-only skins (Skins.luau) only show up for devs, already unlocked.
-- Also: your credits next to the SHOP button in the lobby, and a toast whenever you earn some
-- ("+20 KILL"), anywhere. The server (ShopService) checks every purchase; the skins are in
-- shared/Skins and painted by Combat/SkinPainter.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Attachments = require(ReplicatedStorage.Shared.Attachments)
local Skins = require(ReplicatedStorage.Shared.Skins)
local Sounds = require(ReplicatedStorage.Shared.Sounds)
local Weapons = require(ReplicatedStorage.Shared.Weapons)
local Effects = require(script.Parent.Parent.Combat.Effects)
local GunModels = require(script.Parent.Parent.Combat.GunModels)
local Stickers = require(script.Parent.Parent.Combat.Stickers)
local state = require(script.Parent.Parent.PlayerState)
local MenuStyle = require(script.Parent.MenuStyle)

local MatchState = ReplicatedStorage:WaitForChild("MatchState")
local Shop = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Shop") :: RemoteEvent

local player = Players.LocalPlayer

local ShopMenu = {}

local FACTORY = Color3.fromRGB(45, 47, 52) -- chip color of the factory look
local CARD = Color3.fromRGB(36, 39, 48)
local GOLD = Color3.fromRGB(255, 196, 60)
local PREVIEW_FOV = 30
local MAX_TOASTS = 5

local gui: ScreenGui
local lobbyWidget: Frame
local lobbyCredits: TextLabel
local screen: Frame
local shopCredits: TextLabel
local offlineLabel: TextLabel
local tabs: { [string]: TextButton } = {}
local cards: { [string]: TextButton } = {} -- by skin id, "" = the factory look
local viewport: ViewportFrame
local previewCamera: Camera
local glow: Frame
local previewName: TextLabel
local rarityTag: Frame
local rarityLabel: TextLabel
local hintLabel: TextLabel
local actionButton: TextButton
local allButton: TextButton
local unlockedLabel: TextLabel
local toastList: Frame
local skinGrid: ScrollingFrame
local modsPanel: ScrollingFrame
local viewButtons: { [string]: TextButton } = {}

local selectedItem = "Rifle"
local selectedSkin = "" -- "" = the factory look
local view = "Skins" -- the right side: "Skins" or "Mods" (attachments)
local previewModel: Model? = nil
local previewKey = ""
local previewCenter = CFrame.identity -- moves the model's middle onto the origin
local dragYaw, swayTime = 0, 0
local dragging, lastDragX = false, 0
local shownCredits: number? = nil

local function formatCredits(amount: number): string
	local digits = tostring(math.floor(amount))
	local grouped = string.reverse((string.gsub(string.reverse(digits), "(%d%d%d)", "%1,")))
	return (string.gsub(grouped, "^,", ""))
end

local function itemName(item: string): string
	return if Weapons[item] then Weapons[item].Name else item
end

local function equippedId(item: string): string
	local skin = Skins.EquippedFor(player, item)
	return if skin then skin.Id else ""
end

local function owns(id: string): boolean
	return id == "" or Skins.Owns(player, id)
end

local function credits(): number?
	local value = player:GetAttribute("Credits")
	return if typeof(value) == "number" then value else nil
end

-- Smaller text needs a thinner outline than MenuStyle's chunky one
local function thinOutline(label: TextLabel, thickness: number)
	(label:FindFirstChildOfClass("UIStroke") :: UIStroke).Thickness = thickness
end

local function setButtonText(button: TextButton, text: string)
	(button:FindFirstChild("Label") :: TextLabel).Text = text
end

-- A gold coin: rim, face and a lighter middle
local function coin(parent: Instance, size: number, position: UDim2, anchor: Vector2?): Frame
	local outer = Instance.new("Frame")
	outer.Name = "Coin"
	outer.AnchorPoint = anchor or Vector2.new(0.5, 0.5)
	outer.Position = position
	outer.Size = UDim2.fromOffset(size, size)
	outer.BackgroundColor3 = GOLD
	MenuStyle.Corner(outer, UDim.new(1, 0))
	MenuStyle.Rim(outer, Color3.fromRGB(150, 95, 20), math.max(1.5, size * 0.09))
	local inner = Instance.new("Frame")
	inner.AnchorPoint = Vector2.new(0.5, 0.5)
	inner.Position = UDim2.fromScale(0.5, 0.5)
	inner.Size = UDim2.fromScale(0.5, 0.5)
	inner.BackgroundColor3 = Color3.fromRGB(255, 228, 130)
	MenuStyle.Corner(inner, UDim.new(1, 0))
	inner.Parent = outer
	outer.Parent = parent
	return outer
end

-- Dark rounded pill with a coin and the amount
local function creditsPill(parent: Instance, size: Vector2, position: UDim2, anchor: Vector2): TextLabel
	local pill = Instance.new("Frame")
	pill.Name = "Credits"
	pill.AnchorPoint = anchor
	pill.Position = position
	pill.Size = UDim2.fromOffset(size.X, size.Y)
	pill.BackgroundColor3 = MenuStyle.Panel
	pill.BackgroundTransparency = 0.1
	MenuStyle.Corner(pill, UDim.new(1, 0))
	MenuStyle.Rim(pill, Color3.fromRGB(60, 64, 76), 3)
	pill.Parent = parent
	coin(pill, size.Y * 0.62, UDim2.new(0, size.Y * 0.5, 0.5, 0))
	local label = MenuStyle.Text(pill, "...", UDim2.new(1, -size.Y * 1.05, 0.6, 0), UDim2.new(1, -size.Y * 0.35, 0.5, 0), Vector2.new(1, 0.5))
	label.TextXAlignment = Enum.TextXAlignment.Right
	label.TextColor3 = Color3.fromRGB(255, 225, 120)
	local pop = Instance.new("UIScale")
	pop.Parent = pill
	return label
end

-- A paint chip of the skin's look for its card
local function chip(parent: GuiObject, skin: Skins.Skin?)
	local swatch = Instance.new("Frame")
	swatch.Name = "Swatch"
	swatch.Position = UDim2.fromOffset(8, 8)
	swatch.Size = UDim2.new(1, -16, 0, 78)
	swatch.BackgroundColor3 = if skin then skin.Colors[1] else FACTORY
	swatch.ClipsDescendants = true
	MenuStyle.Corner(swatch, UDim.new(0, 8))
	swatch.Parent = parent

	if skin and skin.Pattern == "Stripes" then
		-- Hard-edged diagonal bands
		swatch.BackgroundColor3 = Color3.new(1, 1, 1)
		local bands, keys = 8, {}
		for i = 0, bands - 1 do
			local color = skin.Colors[i % #skin.Colors + 1]
			table.insert(keys, ColorSequenceKeypoint.new(i / bands, color))
			table.insert(keys, ColorSequenceKeypoint.new((i + 1) / bands - 0.002, color))
		end
		table.insert(keys, ColorSequenceKeypoint.new(1, skin.Colors[(bands - 1) % #skin.Colors + 1]))
		local stripes = Instance.new("UIGradient")
		stripes.Color = ColorSequence.new(keys)
		stripes.Rotation = 25
		stripes.Parent = swatch
	elseif skin and skin.Pattern == "Camo" then
		for i = 1, 9 do
			local blot = Instance.new("Frame")
			blot.BorderSizePixel = 0
			blot.BackgroundColor3 = skin.Colors[i % #skin.Colors + 1]
			local width = 0.22 + (i * 37 % 20) / 100
			blot.Size = UDim2.fromScale(width, width * 1.4)
			blot.Position = UDim2.fromScale((i * 53 % 100) / 100 - 0.1, (i * 29 % 100) / 100 - 0.15)
			MenuStyle.Corner(blot, UDim.new(0.5, 0))
			blot.Parent = swatch
		end
	end
	if skin and skin.Stickers then
		-- A few of its stickers, in two interlocking rows
		for i, spot in { { 0.2, 22 }, { 0.5, 22 }, { 0.8, 22 }, { 0.35, 50 }, { 0.65, 50 } } do
			Stickers.Icon(swatch, skin.Stickers, 24, UDim2.new(spot[1], 0, 0, spot[2]), i)
		end
	end
	if skin and skin.Material == Enum.Material.ForceField then
		swatch.BackgroundTransparency = 0.35
	end

	-- Trim along the bottom (a bright line for glowing trim)
	local neon = skin ~= nil and skin.TrimMaterial == Enum.Material.Neon
	local trim = Instance.new("Frame")
	trim.AnchorPoint = Vector2.new(0, 1)
	trim.Position = UDim2.new(0, 0, 1, if neon then -8 else 0)
	trim.Size = UDim2.new(1, 0, 0, if neon then 4 else 12)
	trim.BorderSizePixel = 0
	trim.BackgroundColor3 = if skin then skin.Trim else Color3.fromRGB(24, 24, 26)
	trim.Parent = swatch
	if skin and skin.Rainbow then
		trim.BackgroundColor3 = Color3.new(1, 1, 1)
		local keys = {}
		for i = 0, 6 do
			table.insert(keys, ColorSequenceKeypoint.new(i / 6, Color3.fromHSV(i / 6, 0.9, 1)))
		end
		local rainbow = Instance.new("UIGradient")
		rainbow.Color = ColorSequence.new(keys)
		rainbow.Parent = trim
	end

	-- Gloss over the top (stronger on polished skins)
	local gloss = Instance.new("Frame")
	gloss.Size = UDim2.fromScale(1, 1)
	gloss.BackgroundColor3 = Color3.new(1, 1, 1)
	gloss.BorderSizePixel = 0
	local fade = Instance.new("UIGradient")
	fade.Rotation = 90
	local top = if skin and (skin.Reflectance or 0) > 0.1 then 0.45 else 0.75
	fade.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, top), NumberSequenceKeypoint.new(0.55, 1), NumberSequenceKeypoint.new(1, 1) })
	fade.Parent = gloss
	gloss.Parent = swatch
	if not skin then
		local label = MenuStyle.Text(swatch, "FACTORY", UDim2.new(0.8, 0, 0, 20), UDim2.fromScale(0.5, 0.45), Vector2.new(0.5, 0.5))
		label.TextColor3 = Color3.fromRGB(150, 155, 165)
		thinOutline(label, 1.5)
	end
end

-- ─── Preview ───────────────────────────────────────────────────────────────────

-- Builds the selected item in the selected skin and frames the camera on it
local function rebuildPreview()
	local mods = if Weapons[selectedItem] then Attachments.For(player, selectedItem) else {}
	local key = selectedItem .. ":" .. selectedSkin .. ":" .. Attachments.Key(mods)
	if key == previewKey then
		return
	end
	previewKey = key
	if previewModel then
		previewModel:Destroy()
	end
	local skin = Skins.ById[selectedSkin]
	local model = if selectedItem == "Knife"
		then GunModels.BuildKnife(skin)
		else GunModels.Build(selectedItem, Weapons[selectedItem].Look.Color, skin, mods)
	local box, size = model:GetBoundingBox()
	previewCenter = CFrame.new(-box.Position) * model:GetPivot()

	-- Back far enough that the whole length fits across and the height fits up and down. The
	-- camera is off to the gun's right side, a little above: the muzzle (-Z) points right.
	local viewSize = viewport.AbsoluteSize
	local aspect = if viewSize.Y > 0 then viewSize.X / viewSize.Y else 1.6
	local tanV = math.tan(math.rad(PREVIEW_FOV / 2))
	local distance = math.max(size.Z / 2 / (tanV * aspect), size.Y / 2 / tanV) * 1.25 + size.X / 2
	previewCamera.CFrame = CFrame.lookAt(Vector3.new(distance, distance * 0.16, 0), Vector3.zero)
	model.Parent = viewport
	previewModel = model
	dragYaw, swayTime = 0, 0
end

local function turnPreview(dt: number)
	if not previewModel then
		return
	end
	if not dragging then
		swayTime += dt
	end
	local yaw = dragYaw + math.sin(swayTime * 0.7) * 0.35
	previewModel:PivotTo(CFrame.Angles(0, yaw, 0) * previewCenter)
end

-- ─── Mods ──────────────────────────────────────────────────────────────────────

-- One choice in a slot: its name and what it does; gold-rimmed when it's on the gun
local function modButton(parent: Instance, order: number, name: string, description: string, on: boolean, pick: () -> ())
	local button = Instance.new("TextButton")
	button.LayoutOrder = order
	button.AutoButtonColor = true
	button.Text = ""
	button.BackgroundColor3 = if on then Color3.fromRGB(58, 52, 36) else CARD
	MenuStyle.Corner(button, UDim.new(0, 10))
	MenuStyle.Rim(button, if on then GOLD else Color3.fromRGB(60, 64, 76), if on then 3 else 2)
	local title = MenuStyle.Text(button, string.upper(name), UDim2.new(1, -16, 0, 24), UDim2.fromOffset(8, 6))
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = if on then GOLD else Color3.new(1, 1, 1)
	local info = Instance.new("TextLabel")
	info.Position = UDim2.fromOffset(8, 32)
	info.Size = UDim2.new(1, -16, 1, -36)
	info.BackgroundTransparency = 1
	info.FontFace = MenuStyle.Font
	info.TextScaled = true
	info.TextWrapped = true
	info.TextXAlignment = Enum.TextXAlignment.Left
	info.TextYAlignment = Enum.TextYAlignment.Top
	info.TextColor3 = Color3.fromRGB(170, 176, 190)
	info.Text = description
	info.Parent = button
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 15
	limit.Parent = info
	button.Activated:Connect(pick)
	button.Parent = parent
end

-- The selected gun's slots, each with FACTORY and every attachment that goes in it
local function fillMods()
	for _, child in modsPanel:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local slots = Attachments.SlotsFor[selectedItem]
	if not slots then
		local none = MenuStyle.Text(modsPanel, "NOTHING GOES ON THE KNIFE", UDim2.new(1, -10, 0, 30), UDim2.new())
		none.LayoutOrder = 1
		return
	end
	local chosen = Attachments.For(player, selectedItem)
	local order = 0
	for _, slot in Attachments.Slots do
		if not slots[slot] then
			continue
		end
		order += 1
		local heading = MenuStyle.Text(modsPanel, Attachments.SlotNames[slot], UDim2.new(1, -10, 0, 26), UDim2.new())
		heading.TextXAlignment = Enum.TextXAlignment.Left
		heading.LayoutOrder = order
		order += 1
		local row = Instance.new("Frame")
		row.LayoutOrder = order
		row.Size = UDim2.new(1, -10, 0, 0)
		row.AutomaticSize = Enum.AutomaticSize.Y
		row.BackgroundTransparency = 1
		row.Parent = modsPanel
		local rowGrid = Instance.new("UIGridLayout")
		rowGrid.CellSize = UDim2.fromOffset(200, 70)
		rowGrid.CellPadding = UDim2.fromOffset(8, 8)
		rowGrid.SortOrder = Enum.SortOrder.LayoutOrder
		rowGrid.Parent = row
		local function put(id: string?)
			Shop:FireServer("Attach", selectedItem, slot, id)
			Effects.Sound(Sounds.Pick("GunFoley"), nil, 0.6, 1.1)
		end
		modButton(row, 0, "Factory", "What the gun comes with.", chosen[slot] == nil, function()
			put(nil)
		end)
		for i, attachment in Attachments.List do
			if attachment.Slot == slot then
				modButton(row, i, attachment.Name, attachment.Description, chosen[slot] == attachment.Id, function()
					put(attachment.Id)
				end)
			end
		end
	end
end

-- ─── Refresh ───────────────────────────────────────────────────────────────────

local function refresh()
	local amount = credits()
	local creditsText = if amount then formatCredits(amount) else "..."
	lobbyCredits.Text = creditsText
	shopCredits.Text = creditsText
	-- Credits went up: the lobby pill pops
	if amount and shownCredits and amount > shownCredits then
		local pop = (lobbyCredits.Parent :: Frame):FindFirstChildOfClass("UIScale") :: UIScale
		pop.Scale = 1.15
		TweenService:Create(pop, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	end
	shownCredits = amount
	offlineLabel.Visible = player:GetAttribute("DataOffline") == true

	for item, tab in tabs do
		local on = item == selectedItem
		local rim = tab:FindFirstChild("Rim") :: UIStroke
		rim.Color = if on then GOLD else Color3.fromRGB(60, 64, 76)
		rim.Thickness = if on then 4 else 2
		tab.BackgroundColor3 = if on then Color3.fromRGB(58, 52, 36) else CARD
		local skin = Skins.EquippedFor(player, item)
		local dot = tab:FindFirstChild("Dot") :: Frame
		dot.Visible = skin ~= nil
		dot.BackgroundColor3 = if skin then skin.Colors[1] else FACTORY
	end

	local wearing = equippedId(selectedItem)
	for id, card in cards do
		local skin = Skins.ById[id]
		local status = card:FindFirstChild("Status") :: TextLabel
		local price = card:FindFirstChild("Coin") :: Frame
		card.Visible = not skin or Skins.Listed(player, skin)
		price.Visible = false
		status.Position = UDim2.new(0, 10, 1, -9)
		if id == wearing then
			status.Text = "EQUIPPED"
			status.TextColor3 = Color3.fromRGB(120, 255, 100)
		elseif skin and skin.DevOnly then
			status.Text = "DEV ONLY"
			status.TextColor3 = Skins.Rarities.Dev.Color
		elseif skin and skin.OnlyFor then
			status.Text = "EXCLUSIVE"
			status.TextColor3 = Skins.Rarities.Exclusive.Color
		elseif owns(id) then
			status.Text = "OWNED"
			status.TextColor3 = Color3.fromRGB(200, 205, 215)
		else
			price.Visible = true
			status.Position = UDim2.new(0, 32, 1, -9)
			status.Text = formatCredits(skin.Price)
			status.TextColor3 = if amount and amount >= skin.Price then Color3.fromRGB(255, 225, 120) else Color3.fromRGB(255, 120, 110)
		end
		local rim = card:FindFirstChild("Rim") :: UIStroke
		local selected = id == selectedSkin
		rim.Color = if selected then Color3.new(1, 1, 1) elseif skin then Skins.Rarities[skin.Rarity].Color else MenuStyle.Grey
		rim.Thickness = if selected then 4 else 2
	end

	-- Preview: name, rarity, and what the big button does
	local skin = Skins.ById[selectedSkin]
	local rarityColor = if skin then Skins.Rarities[skin.Rarity].Color else MenuStyle.Grey
	previewName.Text = `{if skin then skin.Name else "Factory"} {itemName(selectedItem)}`
	rarityLabel.Text = if skin and skin.DevOnly then "DEV ONLY" else string.upper(if skin then skin.Rarity else "Standard")
	rarityTag.BackgroundColor3 = rarityColor
	glow.BackgroundColor3 = rarityColor

	local owned = owns(selectedSkin)
	allButton.Visible = owned
	actionButton.AnchorPoint = if owned then Vector2.new(0, 1) else Vector2.new(0.5, 1)
	actionButton.Position = if owned then UDim2.new(0, 20, 1, -16) else UDim2.new(0.5, 0, 1, -16)
	hintLabel.Text = ""
	if not owned then
		local affordable = amount ~= nil and amount >= skin.Price
		setButtonText(actionButton, `Buy · {formatCredits(skin.Price)}`)
		MenuStyle.SetButtonColor(actionButton, if affordable then MenuStyle.Green else MenuStyle.Grey)
		hintLabel.Text = if affordable then "Once bought it works on every gun and the knife" else "Not enough credits · win matches to earn more"
	elseif skin and (skin.DevOnly or skin.OnlyFor) and selectedSkin ~= wearing then
		hintLabel.Text = skin.Note or "Only devs can see and wear this one"
		setButtonText(actionButton, "Equip")
		MenuStyle.SetButtonColor(actionButton, MenuStyle.Blue)
	elseif selectedSkin == wearing then
		setButtonText(actionButton, "Equipped")
		MenuStyle.SetButtonColor(actionButton, MenuStyle.Grey)
	else
		setButtonText(actionButton, "Equip")
		MenuStyle.SetButtonColor(actionButton, MenuStyle.Blue)
	end
	-- SKINS or MODS on the right; the buy / equip buttons are for skins
	skinGrid.Visible = view == "Skins"
	modsPanel.Visible = view == "Mods"
	for name, button in viewButtons do
		MenuStyle.SetButtonColor(button, if name == view then MenuStyle.Gold else MenuStyle.Grey)
	end
	actionButton.Visible = view == "Skins"
	if view == "Mods" then
		allButton.Visible = false
		hintLabel.Text = if Attachments.SlotsFor[selectedItem] then "Attachments are free · tap one to put it on" else ""
		fillMods()
	end
	if screen.Visible then
		rebuildPreview()
	end
end

local function selectItem(item: string)
	selectedItem = item
	selectedSkin = equippedId(item)
	refresh()
end

-- ─── Building ──────────────────────────────────────────────────────────────────

local function tab(item: string, order: number): TextButton
	local button = Instance.new("TextButton")
	button.Name = item
	button.LayoutOrder = order
	button.Size = UDim2.new(1, 0, 0, 44)
	button.AutoButtonColor = false
	button.Text = ""
	button.BackgroundColor3 = CARD
	MenuStyle.Corner(button, UDim.new(0, 10))
	MenuStyle.Rim(button, Color3.fromRGB(60, 64, 76), 2).Name = "Rim"
	local label = MenuStyle.Text(button, itemName(item), UDim2.new(1, -46, 0, 24), UDim2.new(0, 14, 0.5, 0), Vector2.new(0, 0.5))
	label.TextXAlignment = Enum.TextXAlignment.Left
	thinOutline(label, 2)
	local dot = Instance.new("Frame")
	dot.Name = "Dot"
	dot.AnchorPoint = Vector2.new(1, 0.5)
	dot.Position = UDim2.new(1, -12, 0.5, 0)
	dot.Size = UDim2.fromOffset(18, 18)
	MenuStyle.Corner(dot, UDim.new(1, 0))
	MenuStyle.Rim(dot, Color3.new(1, 1, 1), 2)
	dot.Parent = button
	button.Activated:Connect(function()
		selectItem(item)
	end)
	return button
end

local function card(skin: Skins.Skin?, order: number): TextButton
	local id = if skin then skin.Id else ""
	local button = Instance.new("TextButton")
	button.Name = if id == "" then "Factory" else id
	button.LayoutOrder = order
	button.AutoButtonColor = false
	button.Text = ""
	button.BackgroundColor3 = CARD
	MenuStyle.Corner(button, UDim.new(0, 10))
	MenuStyle.Rim(button, MenuStyle.Grey, 2).Name = "Rim"
	chip(button, skin)
	local name = MenuStyle.Text(button, if skin then skin.Name else "Factory", UDim2.new(1, -14, 0, 20), UDim2.new(0.5, 0, 0, 94), Vector2.new(0.5, 0))
	thinOutline(name, 1.5)
	coin(button, 18, UDim2.new(0, 10, 1, -9), Vector2.new(0, 1))
	local status = MenuStyle.Text(button, "", UDim2.new(1, -40, 0, 18), UDim2.new(0, 10, 1, -9), Vector2.new(0, 1))
	status.Name = "Status"
	status.TextXAlignment = Enum.TextXAlignment.Left
	thinOutline(status, 1.5)
	local scale = Instance.new("UIScale")
	scale.Parent = button
	button.MouseEnter:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.1), { Scale = 1.04 }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.1), { Scale = 1 }):Play()
	end)
	button.Activated:Connect(function()
		selectedSkin = id
		refresh()
	end)
	return button
end

local function buildPreviewPanel(content: Frame)
	local panel = Instance.new("Frame")
	panel.Name = "Preview"
	panel.Position = UDim2.fromOffset(186, 84)
	panel.Size = UDim2.fromOffset(470, 470)
	panel.BackgroundColor3 = MenuStyle.Panel
	panel.ClipsDescendants = true
	MenuStyle.Corner(panel, UDim.new(0, 14))
	MenuStyle.Rim(panel, Color3.fromRGB(60, 64, 76), 3)
	panel.Parent = content

	-- A soft glow in the rarity's color behind the gun
	glow = Instance.new("Frame")
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.new(0.5, 0, 0, 140)
	glow.Size = UDim2.fromOffset(420, 240)
	glow.BackgroundTransparency = 0.55
	MenuStyle.Corner(glow, UDim.new(0.5, 0))
	local fade = Instance.new("UIGradient")
	fade.Rotation = 90
	fade.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.35), NumberSequenceKeypoint.new(1, 1) })
	fade.Parent = glow
	glow.Parent = panel

	viewport = Instance.new("ViewportFrame")
	viewport.Size = UDim2.new(1, 0, 0, 280)
	viewport.BackgroundTransparency = 1
	viewport.Ambient = Color3.fromRGB(150, 150, 160)
	viewport.LightColor = Color3.fromRGB(255, 250, 240)
	viewport.LightDirection = Vector3.new(-1, -1.4, 0.4)
	viewport.Parent = panel
	previewCamera = Instance.new("Camera")
	previewCamera.FieldOfView = PREVIEW_FOV
	previewCamera.Parent = viewport
	viewport.CurrentCamera = previewCamera
	viewport.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			lastDragX = input.Position.X
		end
	end)
	local drag = MenuStyle.Text(panel, "DRAG TO TURN", UDim2.fromOffset(140, 16), UDim2.fromOffset(16, 14))
	drag.TextXAlignment = Enum.TextXAlignment.Left
	drag.TextColor3 = Color3.fromRGB(130, 136, 150)
	thinOutline(drag, 1)

	previewName = MenuStyle.Text(panel, "", UDim2.new(1, -40, 0, 38), UDim2.new(0.5, 0, 0, 282), Vector2.new(0.5, 0))
	rarityTag = Instance.new("Frame")
	rarityTag.AnchorPoint = Vector2.new(0.5, 0)
	rarityTag.Position = UDim2.new(0.5, 0, 0, 326)
	rarityTag.Size = UDim2.fromOffset(140, 24)
	MenuStyle.Corner(rarityTag, UDim.new(1, 0))
	rarityTag.Parent = panel
	rarityLabel = MenuStyle.Text(rarityTag, "", UDim2.new(1, -16, 0, 18), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
	thinOutline(rarityLabel, 1.5)
	hintLabel = MenuStyle.Text(panel, "", UDim2.new(1, -40, 0, 18), UDim2.new(0.5, 0, 0, 358), Vector2.new(0.5, 0))
	hintLabel.TextColor3 = Color3.fromRGB(190, 195, 205)
	thinOutline(hintLabel, 1.5)

	actionButton = MenuStyle.Button(panel, "Buy", MenuStyle.Green, UDim2.fromOffset(240, 64), UDim2.new(0.5, 0, 1, -16), Vector2.new(0.5, 1))
	actionButton.Activated:Connect(function()
		local skin = Skins.ById[selectedSkin]
		if skin and not owns(skin.Id) then
			local amount = credits()
			if amount and amount >= skin.Price then
				Shop:FireServer("Buy", skin.Id, selectedItem)
			end
		elseif selectedSkin ~= equippedId(selectedItem) then
			Shop:FireServer("Equip", selectedItem, if skin then skin.Id else nil)
		end
	end)
	allButton = MenuStyle.Button(panel, "Equip on all", MenuStyle.Blue, UDim2.fromOffset(176, 64), UDim2.new(1, -20, 1, -16), Vector2.new(1, 1))
	allButton.Activated:Connect(function()
		Shop:FireServer("EquipAll", if selectedSkin ~= "" then selectedSkin else nil)
	end)

	-- "UNLOCKED!" stamped over the preview after a purchase
	unlockedLabel = MenuStyle.Text(panel, "UNLOCKED!", UDim2.fromOffset(320, 64), UDim2.new(0.5, 0, 0, 140), Vector2.new(0.5, 0.5))
	unlockedLabel.TextColor3 = Color3.fromRGB(120, 255, 100)
	unlockedLabel.Visible = false
	Instance.new("UIScale").Parent = unlockedLabel
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "Shop"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 6 -- over the lobby menu
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Lobby: credits + SHOP button on the left
	lobbyWidget = Instance.new("Frame")
	lobbyWidget.Name = "LobbyButtons"
	lobbyWidget.AnchorPoint = Vector2.new(0, 0.5)
	lobbyWidget.Position = UDim2.new(0, 20, 0.5, 0)
	lobbyWidget.Size = UDim2.fromOffset(200, 150)
	lobbyWidget.BackgroundTransparency = 1
	lobbyWidget.Visible = false
	lobbyWidget.Parent = gui
	MenuStyle.FitToScreen(lobbyWidget, Vector2.new(900, 520))
	lobbyCredits = creditsPill(lobbyWidget, Vector2.new(200, 50), UDim2.new(), Vector2.zero)
	local shopButton = MenuStyle.Button(lobbyWidget, "Shop", MenuStyle.Gold, UDim2.fromOffset(200, 80), UDim2.new(0, 0, 1, 0), Vector2.new(0, 1))
	shopButton.Activated:Connect(ShopMenu.Open)

	-- The shop screen
	screen = Instance.new("Frame")
	screen.Name = "Screen"
	screen.Size = UDim2.fromScale(1, 1)
	screen.BackgroundColor3 = Color3.new(0, 0, 0)
	screen.BackgroundTransparency = 0.25
	screen.Active = true
	screen.Visible = false
	screen.Parent = gui
	local content = Instance.new("Frame")
	content.AnchorPoint = Vector2.new(0.5, 0.5)
	content.Position = UDim2.fromScale(0.5, 0.5)
	content.Size = UDim2.fromOffset(1100, 640)
	content.BackgroundTransparency = 1
	content.Parent = screen
	MenuStyle.FitToScreen(content, Vector2.new(1100, 640))

	local title = MenuStyle.Text(content, "SHOP", UDim2.fromOffset(170, 64), UDim2.new())
	title.TextXAlignment = Enum.TextXAlignment.Left
	local subtitle = MenuStyle.Text(content, "SKINS FOR YOUR GUNS AND KNIFE", UDim2.fromOffset(420, 24), UDim2.fromOffset(186, 24))
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.TextColor3 = Color3.fromRGB(170, 176, 190)
	thinOutline(subtitle, 1.5)
	shopCredits = creditsPill(content, Vector2.new(230, 56), UDim2.new(1, 0, 0, 4), Vector2.new(1, 0))

	-- Left: items
	local tabList = Instance.new("Frame")
	tabList.Position = UDim2.fromOffset(0, 84)
	tabList.Size = UDim2.fromOffset(170, 470)
	tabList.BackgroundTransparency = 1
	tabList.Parent = content
	local tabLayout = Instance.new("UIListLayout")
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabLayout.Padding = UDim.new(0, 6)
	tabLayout.Parent = tabList
	for i, item in Skins.Items do
		tabs[item] = tab(item, i)
		tabs[item].Parent = tabList
	end

	buildPreviewPanel(content)

	-- Right: SKINS / MODS, then the skins or the attachment slots
	for i, name in { "Skins", "Mods" } do
		local button = MenuStyle.Button(content, name, MenuStyle.Grey, UDim2.fromOffset(206, 38), UDim2.fromOffset(672 + (i - 1) * 216, 84))
		button.Activated:Connect(function()
			view = name
			refresh()
		end)
		viewButtons[name] = button
	end
	modsPanel = Instance.new("ScrollingFrame")
	modsPanel.Position = UDim2.fromOffset(672, 130)
	modsPanel.Size = UDim2.fromOffset(428, 424)
	modsPanel.BackgroundTransparency = 1
	modsPanel.BorderSizePixel = 0
	modsPanel.ScrollBarThickness = 6
	modsPanel.ScrollBarImageColor3 = Color3.fromRGB(120, 124, 135)
	modsPanel.CanvasSize = UDim2.new()
	modsPanel.AutomaticCanvasSize = Enum.AutomaticSize.Y
	modsPanel.Visible = false
	modsPanel.Parent = content
	local modsLayout = Instance.new("UIListLayout")
	modsLayout.Padding = UDim.new(0, 6)
	modsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	modsLayout.Parent = modsPanel
	local modsPadding = Instance.new("UIPadding")
	modsPadding.PaddingTop = UDim.new(0, 4)
	modsPadding.PaddingLeft = UDim.new(0, 5)
	modsPadding.Parent = modsPanel

	local grid = Instance.new("ScrollingFrame")
	skinGrid = grid
	grid.Position = UDim2.fromOffset(672, 130)
	grid.Size = UDim2.fromOffset(428, 424)
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.ScrollBarThickness = 6
	grid.ScrollBarImageColor3 = Color3.fromRGB(120, 124, 135)
	grid.CanvasSize = UDim2.new()
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.Parent = content
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 5)
	padding.PaddingLeft = UDim.new(0, 5)
	padding.PaddingBottom = UDim.new(0, 5)
	padding.Parent = grid
	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.fromOffset(130, 150)
	gridLayout.CellPadding = UDim2.fromOffset(8, 10)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = grid
	cards[""] = card(nil, 0)
	cards[""].Parent = grid
	for i, skin in Skins.List do
		cards[skin.Id] = card(skin, i)
		cards[skin.Id].Parent = grid
	end

	local back = MenuStyle.Button(content, "Back", MenuStyle.Red, UDim2.fromOffset(240, 70), UDim2.new(0.5, 0, 1, 0), Vector2.new(0.5, 1))
	back.Activated:Connect(ShopMenu.Close)
	offlineLabel = MenuStyle.Text(content, "SAVING IS OFF ON THIS SERVER · SKINS WON'T BE KEPT", UDim2.fromOffset(400, 20), UDim2.new(0, 0, 1, -25), Vector2.new(0, 0.5))
	offlineLabel.TextXAlignment = Enum.TextXAlignment.Left
	offlineLabel.TextColor3 = Color3.fromRGB(255, 120, 110)
	thinOutline(offlineLabel, 1.5)

	-- Credit toasts, stacking up on the right
	toastList = Instance.new("Frame")
	toastList.AnchorPoint = Vector2.new(1, 1)
	toastList.Position = UDim2.new(1, -24, 0.7, 0)
	toastList.Size = UDim2.fromOffset(300, 220)
	toastList.BackgroundTransparency = 1
	toastList.Parent = gui
	local toastLayout = Instance.new("UIListLayout")
	toastLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	toastLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	toastLayout.SortOrder = Enum.SortOrder.LayoutOrder
	toastLayout.Padding = UDim.new(0, 4)
	toastLayout.Parent = toastList
end

-- "+20  KILL" with a coin; pops in, then fades away
local toastCount = 0
local function toast(amount: number, reason: string)
	toastCount += 1
	local row = Instance.new("CanvasGroup")
	row.LayoutOrder = toastCount
	row.Size = UDim2.fromOffset(300, 34)
	row.BackgroundTransparency = 1
	coin(row, 24, UDim2.new(1, -4, 0.5, 0), Vector2.new(1, 0.5))
	local label = MenuStyle.Text(row, `+{amount}  {reason}`, UDim2.new(1, -40, 0, 26), UDim2.new(1, -36, 0.5, 0), Vector2.new(1, 0.5))
	label.TextXAlignment = Enum.TextXAlignment.Right
	label.TextColor3 = Color3.fromRGB(255, 225, 120)
	thinOutline(label, 2)
	local scale = Instance.new("UIScale")
	scale.Scale = 0.5
	scale.Parent = row
	row.Parent = toastList
	TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	Effects.Sound(Sounds.Shop.Credits, nil, Sounds.Shop.Volume * 0.6, 1.6)

	-- Only the newest few stay up
	local rows = {}
	for _, child in toastList:GetChildren() do
		if child:IsA("CanvasGroup") then
			table.insert(rows, child)
		end
	end
	table.sort(rows, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	for i = 1, #rows - MAX_TOASTS do
		rows[i]:Destroy()
	end

	task.delay(2.6, function()
		if row.Parent then
			local fade = TweenService:Create(row, TweenInfo.new(0.5), { GroupTransparency = 1 })
			fade.Completed:Connect(function()
				row:Destroy()
			end)
			fade:Play()
		end
	end)
end

local function bought(id: string)
	Effects.Sound(Sounds.Shop.Buy, nil, Sounds.Shop.Volume, 1.25)
	if not screen.Visible or id ~= selectedSkin then
		return
	end
	local scale = unlockedLabel:FindFirstChildOfClass("UIScale") :: UIScale
	unlockedLabel.Visible = true
	unlockedLabel.Rotation = -8
	scale.Scale = 2
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	task.delay(1.4, function()
		unlockedLabel.Visible = false
	end)
end

local function inLobbyMenu(): boolean
	return MatchState:GetAttribute("ServerKind") == "Lobby"
		and player:GetAttribute("Location") == "Lobby"
		and MatchState:GetAttribute("Phase") == "Waiting"
end

function ShopMenu.Open()
	if state.shopOpen then
		return
	end
	state.shopOpen = true
	screen.Visible = true
	-- Start on the gun you're holding
	local weapon = player:GetAttribute("Weapon")
	selectItem(if typeof(weapon) == "string" and table.find(Skins.Items, weapon) then weapon else selectedItem)
end

function ShopMenu.Close()
	state.shopOpen = false
	screen.Visible = false
	dragging = false
	-- (the preview model is kept for next time)
end

function ShopMenu.Start()
	build()
	refresh()
	for _, attribute in { "Credits", "OwnedSkins", "EquippedSkins", "DataOffline", "IsDev", "Attachments" } do
		player:GetAttributeChangedSignal(attribute):Connect(refresh)
	end
	Shop.OnClientEvent:Connect(function(event, a, b)
		if event == "Reward" and typeof(a) == "number" and typeof(b) == "string" then
			toast(a, b)
		elseif event == "Bought" and typeof(a) == "string" then
			bought(a)
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			dragYaw += (input.Position.X - lastDragX) * 0.012
			lastDragX = input.Position.X
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)

	RunService.RenderStepped:Connect(function(dt)
		local lobby = inLobbyMenu()
		if state.shopOpen and not lobby then
			ShopMenu.Close() -- a match is starting
		end
		lobbyWidget.Visible = lobby and not state.shopOpen and not state.modesOpen
		if state.shopOpen then
			turnPreview(dt)
		end
	end)
end

return ShopMenu
