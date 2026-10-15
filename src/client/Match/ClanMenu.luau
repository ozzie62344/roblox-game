-- The CLAN screen (lobby; rules: shared/Clans, the server: ClanService).
--   Right side of the lobby, left of the PARTY: your clan's badge and [TAG] over the CLAN button.
--   Tabs along the top:
--     MY CLAN   your clan: badge, tag, name, description, wins / kills, who can join, the activity
--               log, LEAVE (DISBAND for the owner) and SETTINGS (owner and officers). On the right
--               its members (a green dot: in this server) with KICK / PROMOTE / DEMOTE / OWNER for
--               whoever may; the owner and officers also get INVITE (players here) and the join
--               REQUESTS list (ACCEPT / DECLINE).
--     CREATE    (not in a clan) the new-clan form: name, tag, description, badge, type and
--               requirements; locked below Clans.CreateLevel with your progress towards it
--     BROWSE    (not in a clan) recommended clans and a search (by name, or the exact tag), each
--               with its requirements ticked or crossed for you and JOIN / REQUEST / INVITE ONLY
--     TOP       the clans with the most match wins and kills (ReplicatedStorage.ClanBoard)
--   A clan invite pops up at the top of the screen with JOIN / NO, under the party's.
-- Also adds the "[TAG]" to chat (ChatTags), after the [VIP] one.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Clans = require(ReplicatedStorage.Shared.Clans)
local Progression = require(ReplicatedStorage.Shared.Progression)
local Ranked = require(ReplicatedStorage.Shared.Ranked)
local state = require(script.Parent.Parent.PlayerState)
local ChatTags = require(script.Parent.ChatTags)
local MenuStyle = require(script.Parent.MenuStyle)

local MatchState = ReplicatedStorage:WaitForChild("MatchState")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local player = Players.LocalPlayer

local ClanMenu = {}

local CARD = Color3.fromRGB(36, 39, 48)
local EDGE = Color3.fromRGB(60, 64, 76)
local SOFT_TEXT = Color3.fromRGB(150, 156, 170)
local OFFICER = Color3.fromRGB(120, 180, 255)
local PURPLE = Color3.fromRGB(130, 80, 200)
local ONLINE = Color3.fromRGB(110, 255, 90)
local TAG_COLOR = "#8FD0FF" -- (chat)
local ROW_HEIGHT = 52
local NOTICE_TIME = 4
local CONFIRM_TIME = 3 -- seconds to press a dangerous button again (DISBAND, LEAVE, OWNER)
local BODY = Vector2.new(880, 362)

local TYPE_HINTS = {
	Open = "ANYONE WHO MEETS THE REQUIREMENTS JOINS",
	Request = "PLAYERS ASK TO JOIN · THE OWNER OR AN OFFICER SAYS YES",
	Invite = "ONLY PLAYERS YOU INVITE CAN JOIN",
}

type Invite = { from: Player, tag: string, name: string, badge: number, ends: number, total: number }
type Form = {
	frame: Frame,
	name: TextBox?,
	tag: TextBox?,
	description: TextBox,
	values: { Type: string, MinLevel: number, MinRank: number, Badge: number },
	refresh: () -> (),
	hint: TextLabel,
	lock: Frame?,
}

local Clan: RemoteEvent
local boardFolder: Instance

local gui: ScreenGui
local widget: Frame
local widgetBadge: Frame
local widgetTag: TextLabel
local screen: Frame
local tabButtons: { [string]: TextButton } = {}
local pages: { [string]: Frame } = {}
local homeLeft: Frame
local homeRight: Frame
local memberList: ScrollingFrame
local logList: ScrollingFrame
local createForm: Form
local settingsForm: Form
local settingsOverlay: Frame
local pickerOverlay: Frame
local pickerList: ScrollingFrame
local requestOverlay: Frame
local requestTitle: TextLabel
local requestBox: TextBox
local searchBox: TextBox
local browseHeading: TextLabel
local browseList: ScrollingFrame
local topLists: { [string]: Frame } = {}
local topStatus: TextLabel
local popup: Frame
local popupBadge: Frame
local popupName: TextLabel
local popupLine: TextLabel
local popupMore: TextLabel
local popupTimer: Frame
local noticeLabel: TextLabel

local screenOpen = false
local tab: string = "Home" -- "Home" (MY CLAN / CREATE), "Browse", "Top"
local rightView = "Members" -- or "Requests"
local overlay: string? = nil -- "Settings", "Picker", "Request"
local info: { [string]: any }? = nil -- my clan, as the server last sent it
local infoVersion = 0
local browseEntries: { any } = {}
local searchEntries: { any }? = nil -- nil: showing the recommended ones
local listVersion = 0
local boardVersion = 0
local requested: { [string]: boolean } = {} -- clan id → asked to join (this session)
local requestingId: string? = nil
local lastBrowse = -math.huge
local invites: { Invite } = {}
local sent: { [Player]: number } = {}
local confirming: { what: string, ends: number }? = nil
local noticeText, noticeEnds = "", 0
local shownKey = ""

-- ─── Small parts ───────────────────────────────────────────────────────────────

local function thinOutline(label: TextLabel, thickness: number)
	(label:FindFirstChildOfClass("UIStroke") :: UIStroke).Thickness = thickness
end

local function leftText(parent: Instance, text: string, size: UDim2, position: UDim2, color: Color3?, outline: number?): TextLabel
	local label = MenuStyle.Text(parent, text, size, position)
	label.TextXAlignment = Enum.TextXAlignment.Left
	if color then
		label.TextColor3 = color
	end
	thinOutline(label, outline or 1.5)
	return label
end

local function formatNumber(n: number): string
	local text = tostring(math.floor(n))
	local formatted = string.reverse((string.gsub(string.reverse(text), "(%d%d%d)", "%1,")))
	return (string.gsub(formatted, "^,", ""))
end

local function ago(time: number): string
	local seconds = math.max(0, os.time() - time)
	if seconds < 3600 then
		return `{math.max(1, math.floor(seconds / 60))}M AGO`
	elseif seconds < 86400 then
		return `{math.floor(seconds / 3600)}H AGO`
	end
	return `{math.floor(seconds / 86400)}D AGO`
end

local function headshot(userId: number): string
	return if userId > 0 then `rbxthumb://type=AvatarHeadShot&id={userId}&w=150&h=150` else ""
end

local function face(parent: Instance, userId: number, size: number, position: UDim2, anchor: Vector2?): ImageLabel
	local image = Instance.new("ImageLabel")
	image.Name = "Face"
	image.AnchorPoint = anchor or Vector2.zero
	image.Position = position
	image.Size = UDim2.fromOffset(size, size)
	image.BackgroundColor3 = Color3.fromRGB(46, 50, 60)
	image.Image = headshot(userId)
	MenuStyle.Corner(image, UDim.new(1, 0))
	image.Parent = parent
	return image
end

local function clear(list: Instance)
	for _, child in list:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function listLayout(parent: Instance, padding: number?)
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, padding or 6)
	layout.Parent = parent
end

local function scroller(parent: Instance, position: UDim2, size: UDim2): ScrollingFrame
	local list = Instance.new("ScrollingFrame")
	list.Position = position
	list.Size = size
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.ScrollBarThickness = 6
	list.ScrollBarImageColor3 = Color3.fromRGB(120, 124, 135)
	list.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.Parent = parent
	listLayout(list)
	return list
end

-- A dark rounded panel with a heading in the top left
local function panel(parent: Instance, position: UDim2, size: UDim2, heading: string): (Frame, TextLabel)
	local frame = Instance.new("Frame")
	frame.Position = position
	frame.Size = size
	frame.BackgroundColor3 = MenuStyle.Panel
	frame.BackgroundTransparency = 0.08
	MenuStyle.Corner(frame, UDim.new(0, 14))
	MenuStyle.Rim(frame, EDGE, 3)
	frame.Parent = parent
	local title = leftText(frame, heading, UDim2.fromOffset(300, 24), UDim2.fromOffset(14, 11), nil, 2)
	return frame, title
end

local function textBox(parent: Instance, placeholder: string, size: UDim2, position: UDim2): TextBox
	local box = Instance.new("TextBox")
	box.Position = position
	box.Size = size
	box.BackgroundColor3 = CARD
	box.ClearTextOnFocus = false
	box.FontFace = MenuStyle.Font
	box.TextSize = 20
	box.TextColor3 = Color3.new(1, 1, 1)
	box.PlaceholderText = placeholder
	box.PlaceholderColor3 = Color3.fromRGB(110, 116, 130)
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.Text = ""
	MenuStyle.Corner(box, UDim.new(0, 8))
	MenuStyle.Rim(box, EDGE, 2)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = box
	box.Parent = parent
	return box
end

-- Keeps a text box to `max` characters (and `clean`ed, if given)
local function limit(box: TextBox, max: number, clean: ((string) -> string)?)
	box:GetPropertyChangedSignal("Text"):Connect(function()
		local text = if clean then clean(box.Text) else box.Text
		local length = utf8.len(text)
		if length and length > max then
			text = string.sub(text, 1, (utf8.offset(text, max + 1) or (#text + 1)) - 1)
		end
		if text ~= box.Text then
			box.Text = text
		end
	end)
end

-- A clan badge (shared/Clans Badges) drawn into `holder` (anything already in it is replaced)
local function drawBadge(holder: Frame, id: any)
	clear(holder)
	local badge = Clans.BadgeById(id)
	local dark = badge.Color:Lerp(Color3.new(), 0.55)
	local function piece(size: UDim2, position: UDim2, rotation: number, radius: UDim, rim: boolean): Frame
		local frame = Instance.new("Frame")
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Position = position
		frame.Size = size
		frame.Rotation = rotation
		frame.BackgroundColor3 = badge.Color
		MenuStyle.Corner(frame, radius)
		if rim then
			MenuStyle.Rim(frame, dark, 2)
		end
		frame.Parent = holder
		return frame
	end
	if badge.Shape == "Circle" then
		piece(UDim2.fromScale(0.94, 0.94), UDim2.fromScale(0.5, 0.5), 0, UDim.new(1, 0), true)
	elseif badge.Shape == "Square" then
		piece(UDim2.fromScale(0.88, 0.88), UDim2.fromScale(0.5, 0.5), 0, UDim.new(0.22, 0), true)
	elseif badge.Shape == "Diamond" then
		piece(UDim2.fromScale(0.68, 0.68), UDim2.fromScale(0.5, 0.5), 45, UDim.new(0.18, 0), true)
	else -- Shield: a rounded top and a point
		piece(UDim2.fromScale(0.62, 0.62), UDim2.fromScale(0.5, 0.58), 45, UDim.new(0.12, 0), false)
		piece(UDim2.fromScale(0.86, 0.5), UDim2.fromScale(0.5, 0.3), 0, UDim.new(0.2, 0), false)
	end
	-- (a little light in the middle)
	local dot = piece(UDim2.fromScale(0.3, 0.3), UDim2.fromScale(0.5, 0.5), 0, UDim.new(1, 0), false)
	dot.BackgroundColor3 = Color3.new(1, 1, 1)
	dot.BackgroundTransparency = 0.35
end

local function badgeHolder(parent: Instance, size: number, position: UDim2, anchor: Vector2?): Frame
	local holder = Instance.new("Frame")
	holder.AnchorPoint = anchor or Vector2.zero
	holder.Position = position
	holder.Size = UDim2.fromOffset(size, size)
	holder.BackgroundTransparency = 1
	holder.Parent = parent
	return holder
end

-- A green tick or a red cross, 16 pixels
local function mark(parent: Instance, ok: boolean, order: number)
	local holder = Instance.new("Frame")
	holder.LayoutOrder = order
	holder.Size = UDim2.fromOffset(16, 16)
	holder.BackgroundTransparency = 1
	holder.Parent = parent
	if ok then
		local scale = Instance.new("UIScale")
		scale.Scale = 0.45
		scale.Parent = MenuStyle.Check(holder, UDim2.fromScale(0.5, 0.5))
		return
	end
	for _, angle in { 45, -45 } do
		local bar = Instance.new("Frame")
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Position = UDim2.fromScale(0.5, 0.5)
		bar.Size = UDim2.fromOffset(15, 4)
		bar.Rotation = angle
		bar.BackgroundColor3 = Color3.fromRGB(255, 90, 80)
		MenuStyle.Corner(bar, UDim.new(1, 0))
		MenuStyle.Rim(bar, MenuStyle.Outline, 1)
		bar.Parent = holder
	end
end

-- A line of small labels and marks side by side (row info lines)
local function strip(parent: Instance, position: UDim2, width: number): Frame
	local frame = Instance.new("Frame")
	frame.Position = position
	frame.Size = UDim2.fromOffset(width, 16)
	frame.BackgroundTransparency = 1
	frame.Parent = parent
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 5)
	layout.Parent = frame
	return frame
end

local function stripText(parent: Instance, text: string, order: number, color: Color3?)
	local label = MenuStyle.Text(parent, text, UDim2.fromOffset(#text * 8 + 4, 15), UDim2.new())
	label.LayoutOrder = order
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = color or SOFT_TEXT
	thinOutline(label, 1.2)
end

-- A row of small buttons, right-aligned in `frame`
local function buttonStrip(frame: Instance, width: number): Frame
	local holder = Instance.new("Frame")
	holder.AnchorPoint = Vector2.new(1, 0.5)
	holder.Position = UDim2.new(1, -6, 0.5, 0)
	holder.Size = UDim2.fromOffset(width, 40)
	holder.BackgroundTransparency = 1
	holder.Parent = frame
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = holder
	return holder
end

local function smallButton(parent: Instance, text: string, color: Color3, width: number, order: number, onPress: (() -> ())?)
	local button = MenuStyle.Button(parent, text, color, UDim2.fromOffset(width, 38), UDim2.new())
	button.LayoutOrder = order
	if onPress then
		button.Activated:Connect(onPress)
	end
end

-- A card in a list: room for a picture on the left and buttons on the right
local function card(list: Instance, order: number, height: number, highlight: Color3?): Frame
	local frame = Instance.new("Frame")
	frame.LayoutOrder = order
	frame.Size = UDim2.new(1, 0, 0, height)
	frame.BackgroundColor3 = CARD
	MenuStyle.Corner(frame, UDim.new(0, 10))
	MenuStyle.Rim(frame, highlight or EDGE, 2)
	frame.Parent = list
	return frame
end

local function emptyLine(list: Instance, text: string)
	local label = MenuStyle.Text(list, text, UDim2.new(1, -20, 0, 20), UDim2.new())
	label.TextColor3 = SOFT_TEXT
	thinOutline(label, 1.5)
end

local function notify(text: string)
	noticeText, noticeEnds = string.upper(text), os.clock() + NOTICE_TIME
end

-- Pressed twice within a few seconds? (the first press turns the button into SURE?)
local function confirmed(what: string): boolean
	local now = os.clock()
	if confirming and confirming.what == what and confirming.ends > now then
		confirming = nil
		return true
	end
	confirming = { what = what, ends = now + CONFIRM_TIME }
	return false
end

local function confirmingNow(what: string): boolean
	return confirming ~= nil and confirming.what == what and confirming.ends > os.clock()
end

-- Asks for the recommended clans (again, if it's been a while)
local function browse(force: boolean?)
	if force or os.clock() - lastBrowse > 20 then
		lastBrowse = os.clock()
		Clan:FireServer("Browse")
	end
end

-- ─── About me ──────────────────────────────────────────────────────────────────

local function number(attribute: string, default: number): number
	local value = player:GetAttribute(attribute)
	return if typeof(value) == "number" then value else default
end

local function myLevel(): number
	return number("Level", 1)
end

local function myTier(): number
	return Clans.TierIndex(number("Mmr", Ranked.StartMmr), number("RankedMatches", 0))
end

local function myRole(): string?
	return if info then info.Role else nil
end

local function isStaff(): boolean
	local role = myRole()
	return role == "Owner" or role == "Officer"
end

local function inLobbyMenu(): boolean
	return MatchState:GetAttribute("ServerKind") == "Lobby"
		and player:GetAttribute("Location") == "Lobby"
		and not state.inPractice
		and MatchState:GetAttribute("Phase") == "Waiting"
end

-- "LV 10+", "GOLD+" (nil: no rank needed)
local function requirementTexts(minLevel: number, minRank: number): (string, string?)
	return `LV {minLevel}+`, if minRank > 0 then `{Clans.RankLabel(minRank)}+` else nil
end

-- ─── The form (CREATE, and SETTINGS for the owner and officers) ────────────────

local function buildForm(parent: Instance, creating: boolean): Form
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromOffset(BODY.X, BODY.Y)
	frame.BackgroundTransparency = 1
	frame.Parent = parent
	local values = { Type = "Open", MinLevel = 1, MinRank = 0, Badge = 1 }
	local form: Form = { frame = frame, description = nil :: any, values = values, refresh = nil :: any, hint = nil :: any }

	-- Left: who the clan is
	local left = panel(frame, UDim2.new(), UDim2.fromOffset(430, BODY.Y), if creating then "NEW CLAN" else "CLAN SETTINGS")
	if creating then
		leftText(left, "NAME", UDim2.fromOffset(120, 16), UDim2.fromOffset(14, 44), SOFT_TEXT)
		local name = textBox(left, "3-20 letters", UDim2.fromOffset(300, 40), UDim2.fromOffset(14, 62))
		limit(name, 20, function(text)
			return (string.gsub(text, "[^%w ]", ""))
		end)
		leftText(left, "TAG", UDim2.fromOffset(80, 16), UDim2.fromOffset(326, 44), SOFT_TEXT)
		local tag = textBox(left, "ABC", UDim2.fromOffset(90, 40), UDim2.fromOffset(326, 62))
		limit(tag, 4, function(text)
			return string.upper((string.gsub(text, "[^%w]", "")))
		end)
		form.name, form.tag = name, tag
	else
		leftText(left, "THE NAME AND TAG STAY AS THEY ARE", UDim2.fromOffset(400, 16), UDim2.fromOffset(14, 62), SOFT_TEXT)
	end
	leftText(left, "DESCRIPTION", UDim2.fromOffset(160, 16), UDim2.fromOffset(14, 112), SOFT_TEXT)
	local counter = MenuStyle.Text(left, "", UDim2.fromOffset(80, 14), UDim2.fromOffset(416, 113), Vector2.new(1, 0))
	counter.TextXAlignment = Enum.TextXAlignment.Right
	counter.TextColor3 = SOFT_TEXT
	thinOutline(counter, 1)
	local description = textBox(left, "What's your clan about? (optional)", UDim2.fromOffset(402, 64), UDim2.fromOffset(14, 130))
	description.TextSize = 17
	description.TextWrapped = true
	description.MultiLine = false
	description.TextYAlignment = Enum.TextYAlignment.Top
	limit(description, Clans.MaxDescription)
	form.description = description

	leftText(left, "BADGE", UDim2.fromOffset(120, 16), UDim2.fromOffset(14, 206), SOFT_TEXT)
	local badgeButtons: { TextButton } = {}
	for i, badge in Clans.Badges do
		local button = Instance.new("TextButton")
		button.Text = ""
		button.AutoButtonColor = false
		button.Position = UDim2.fromOffset(14 + (i - 1) * 50, 226)
		button.Size = UDim2.fromOffset(44, 44)
		button.BackgroundColor3 = CARD
		MenuStyle.Corner(button, UDim.new(0, 8))
		MenuStyle.Rim(button, EDGE, 2).Name = "Rim"
		drawBadge(badgeHolder(button, 34, UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5)), badge.Id)
		button.Parent = left
		button.Activated:Connect(function()
			values.Badge = badge.Id
			form.refresh()
		end)
		badgeButtons[i] = button
	end
	local hint = leftText(left, "", UDim2.fromOffset(402, 16), UDim2.fromOffset(14, 290), SOFT_TEXT)
	form.hint = hint

	-- Right: who can join
	local right = panel(frame, UDim2.fromOffset(446, 0), UDim2.fromOffset(434, BODY.Y), "WHO CAN JOIN")
	local typeButtons: { [string]: TextButton } = {}
	for i, clanType in Clans.Types do
		local button = MenuStyle.Button(right, Clans.TypeLabels[clanType], MenuStyle.Grey, UDim2.fromOffset(130, 40), UDim2.fromOffset(14 + (i - 1) * 138, 44))
		button.Activated:Connect(function()
			values.Type = clanType
			form.refresh()
		end)
		typeButtons[clanType] = button
	end
	local typeHint = leftText(right, "", UDim2.fromOffset(406, 15), UDim2.fromOffset(14, 92), Color3.fromRGB(255, 225, 120))

	leftText(right, "MINIMUM LEVEL", UDim2.fromOffset(200, 16), UDim2.fromOffset(14, 120), SOFT_TEXT)
	local levelBox = Instance.new("Frame")
	levelBox.Position = UDim2.fromOffset(140, 140)
	levelBox.Size = UDim2.fromOffset(140, 40)
	levelBox.BackgroundColor3 = CARD
	MenuStyle.Corner(levelBox, UDim.new(0, 8))
	levelBox.Parent = right
	local levelValue = MenuStyle.Text(levelBox, "", UDim2.fromScale(0.8, 0.7), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
	for _, step in { { -10, 14 }, { -1, 77 }, { 1, 286 }, { 10, 349 } } do
		local text = if step[1] < 0 then tostring(step[1]) else `+{step[1]}`
		local button = MenuStyle.Button(right, text, MenuStyle.Blue, UDim2.fromOffset(57, 40), UDim2.fromOffset(step[2], 140))
		button.Activated:Connect(function()
			values.MinLevel = math.clamp(values.MinLevel + step[1], 1, Clans.MaxLevelRequirement)
			form.refresh()
		end)
	end

	leftText(right, "MINIMUM RANK", UDim2.fromOffset(200, 16), UDim2.fromOffset(14, 192), SOFT_TEXT)
	local rankBox = Instance.new("Frame")
	rankBox.Position = UDim2.fromOffset(77, 212)
	rankBox.Size = UDim2.fromOffset(266, 40)
	rankBox.BackgroundColor3 = CARD
	MenuStyle.Corner(rankBox, UDim.new(0, 8))
	rankBox.Parent = right
	local rankValue = MenuStyle.Text(rankBox, "", UDim2.fromScale(0.8, 0.7), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
	for _, step in { { -1, 14, "<" }, { 1, 349, ">" } } do
		local button = MenuStyle.Button(right, step[3] :: string, MenuStyle.Blue, UDim2.fromOffset(57, 40), UDim2.fromOffset(step[2] :: number, 212))
		button.Activated:Connect(function()
			values.MinRank = (values.MinRank + (step[1] :: number)) % (#Ranked.Tiers + 1)
			form.refresh()
		end)
	end
	local unused = leftText(right, "", UDim2.fromOffset(406, 15), UDim2.fromOffset(14, 260), SOFT_TEXT)

	if creating then
		local submit = MenuStyle.Button(right, `Create · {formatNumber(Clans.CreateCost)}`, MenuStyle.Green, UDim2.fromOffset(260, 56), UDim2.new(1, -14, 1, -14), Vector2.new(1, 1))
		submit.Activated:Connect(function()
			local name = Clans.CleanName((form.name :: TextBox).Text)
			local tag = Clans.CleanTag((form.tag :: TextBox).Text)
			if not name then
				notify("Names are 3-20 letters, numbers and spaces")
			elseif not tag then
				notify("Tags are 2-4 letters or numbers")
			elseif number("Credits", 0) < Clans.CreateCost then
				notify(`You need {formatNumber(Clans.CreateCost)} credits`)
			else
				notify("Founding your clan...")
				Clan:FireServer("Create", name, tag, {
					Type = values.Type, MinLevel = values.MinLevel, MinRank = values.MinRank, Badge = values.Badge, Description = description.Text,
				})
			end
		end)
		-- Below the level it takes: the form's covered, with how far there is to go
		local lock = Instance.new("Frame")
		lock.Size = UDim2.fromScale(1, 1)
		lock.BackgroundColor3 = MenuStyle.Panel
		lock.BackgroundTransparency = 0.12
		lock.Active = true
		lock.ZIndex = 5
		MenuStyle.Corner(lock, UDim.new(0, 14))
		lock.Parent = frame
		form.lock = lock
	else
		local save = MenuStyle.Button(right, "Save", MenuStyle.Green, UDim2.fromOffset(180, 56), UDim2.new(1, -14, 1, -14), Vector2.new(1, 1))
		save.Activated:Connect(function()
			Clan:FireServer("Settings", { Type = values.Type, MinLevel = values.MinLevel, MinRank = values.MinRank, Badge = values.Badge, Description = description.Text })
			overlay = nil
		end)
		local cancel = MenuStyle.Button(right, "Cancel", MenuStyle.Red, UDim2.fromOffset(140, 56), UDim2.new(1, -206, 1, -14), Vector2.new(1, 1))
		cancel.Activated:Connect(function()
			overlay = nil
		end)
	end

	form.refresh = function()
		for clanType, button in typeButtons do
			MenuStyle.SetButtonColor(button, if values.Type == clanType then MenuStyle.Blue else MenuStyle.Grey)
		end
		for i, button in badgeButtons do
			(button:FindFirstChild("Rim") :: UIStroke).Color = if values.Badge == i then MenuStyle.Gold else EDGE
		end
		typeHint.Text = TYPE_HINTS[values.Type] or ""
		levelValue.Text = `LEVEL {values.MinLevel}`
		rankValue.Text = Clans.RankLabel(values.MinRank)
		rankValue.TextColor3 = if values.MinRank > 0 then Ranked.Tiers[values.MinRank].Color else Color3.new(1, 1, 1)
		unused.Text = if values.Type == "Invite" then "(REQUIREMENTS DON'T APPLY TO INVITES)" else ""
		counter.Text = `{utf8.len(description.Text) or 0}/{Clans.MaxDescription}`
	end
	description:GetPropertyChangedSignal("Text"):Connect(form.refresh)
	form.refresh()
	return form
end

-- The create form's lock: "REACH LEVEL 5" with a bar of the XP there
local function refreshLock()
	local lock = createForm.lock :: Frame
	local level = myLevel()
	lock.Visible = level < Clans.CreateLevel
	if not lock.Visible then
		return
	end
	clear(lock)
	local needed = 0
	for l = 1, Clans.CreateLevel - 1 do
		needed += Progression.XpToNext(l)
	end
	local xp = number("Xp", 0)
	local title = MenuStyle.Text(lock, `REACH LEVEL {Clans.CreateLevel} TO FOUND A CLAN`, UDim2.fromOffset(600, 40), UDim2.new(0.5, 0, 0, 90), Vector2.new(0.5, 0))
	title.ZIndex = 6
	local track = Instance.new("Frame")
	track.AnchorPoint = Vector2.new(0.5, 0)
	track.Position = UDim2.new(0.5, 0, 0, 150)
	track.Size = UDim2.fromOffset(460, 18)
	track.BackgroundColor3 = Color3.fromRGB(46, 50, 60)
	track.ZIndex = 6
	MenuStyle.Corner(track, UDim.new(1, 0))
	track.Parent = lock
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(math.clamp(xp / math.max(needed, 1), 0, 1), 1)
	fill.BackgroundColor3 = MenuStyle.Gold
	fill.ZIndex = 7
	MenuStyle.Corner(fill, UDim.new(1, 0))
	fill.Parent = track
	local line = MenuStyle.Text(lock, `LEVEL {level} / {Clans.CreateLevel} · {formatNumber(math.max(0, needed - xp))} XP TO GO`, UDim2.fromOffset(460, 20), UDim2.new(0.5, 0, 0, 178), Vector2.new(0.5, 0))
	line.TextColor3 = SOFT_TEXT
	line.ZIndex = 6
	thinOutline(line, 1.5)
	local browseButton = MenuStyle.Button(lock, "Browse Clans", MenuStyle.Blue, UDim2.fromOffset(240, 56), UDim2.new(0.5, 0, 0, 226), Vector2.new(0.5, 0))
	browseButton.ZIndex = 6
	browseButton.Activated:Connect(function()
		tab = "Browse"
		browse()
	end)
end

-- ─── Pages ─────────────────────────────────────────────────────────────────────

local function logText(entry: any): string
	local who = string.upper(tostring(entry.Who))
	local by = if typeof(entry.By) == "string" then string.upper(entry.By) else nil
	local kind = entry.Kind
	if kind == "Created" then
		return `{who} FOUNDED THE CLAN`
	elseif kind == "Joined" then
		return if by then `{who} JOINED · LET IN BY {by}` else `{who} JOINED`
	elseif kind == "Left" then
		return `{who} LEFT`
	elseif kind == "Kicked" then
		return if by then `{who} WAS KICKED BY {by}` else `{who} WAS KICKED`
	elseif kind == "Promoted" then
		return `{who} IS NOW AN OFFICER`
	elseif kind == "Demoted" then
		return `{who} IS NOW A MEMBER`
	elseif kind == "Owner" then
		return `{who} IS THE NEW OWNER`
	end
	return who
end

local ROLE_ORDER = { Owner = 1, Officer = 2, Member = 3 }

local function renderMembers(clan: { [string]: any })
	clear(memberList)
	local role = myRole()
	local list = table.clone(clan.MemberList or {})
	table.sort(list, function(a, b)
		if a.Role ~= b.Role then
			return (ROLE_ORDER[a.Role] or 4) < (ROLE_ORDER[b.Role] or 4)
		end
		return tostring(a.Name) < tostring(b.Name)
	end)
	for i, member in list do
		local id = tonumber(member.Id) or 0
		local me = id == player.UserId
		local here = Players:GetPlayerByUserId(id)
		local roleColor = if member.Role == "Owner" then MenuStyle.Gold elseif member.Role == "Officer" then OFFICER else SOFT_TEXT
		local frame = card(memberList, i, ROW_HEIGHT, if me then Color3.new(1, 1, 1) else nil)
		local picture = face(frame, id, 40, UDim2.new(0, 7, 0.5, 0), Vector2.new(0, 0.5))
		if here then
			local dot = Instance.new("Frame")
			dot.AnchorPoint = Vector2.new(1, 1)
			dot.Position = UDim2.fromScale(1.05, 1.05)
			dot.Size = UDim2.fromOffset(13, 13)
			dot.BackgroundColor3 = ONLINE
			MenuStyle.Corner(dot, UDim.new(1, 0))
			MenuStyle.Rim(dot, MenuStyle.Outline, 2)
			dot.Parent = picture
		end
		leftText(frame, if here then here.DisplayName else tostring(member.Name), UDim2.new(1, -300, 0, 22), UDim2.fromOffset(56, 6), nil, 2)
		local line = string.upper(tostring(member.Role)) .. (if me then " · YOU" elseif here then " · IN THIS SERVER" else "")
		leftText(frame, line, UDim2.new(1, -300, 0, 15), UDim2.fromOffset(56, 31), roleColor)
		if me then
			continue
		end
		local buttons = buttonStrip(frame, 250)
		if role == "Owner" then
			local owner = `Owner:{id}`
			smallButton(buttons, if confirmingNow(owner) then "Sure?" else "Owner", MenuStyle.Gold, 74, 3, function()
				if confirmed(owner) then
					Clan:FireServer("Transfer", id)
				end
			end)
			if member.Role == "Member" then
				smallButton(buttons, "Promote", MenuStyle.Blue, 84, 2, function()
					Clan:FireServer("Promote", id)
				end)
			elseif member.Role == "Officer" then
				smallButton(buttons, "Demote", MenuStyle.Grey, 84, 2, function()
					Clan:FireServer("Demote", id)
				end)
			end
		end
		if role == "Owner" or (role == "Officer" and member.Role == "Member") then
			smallButton(buttons, "Kick", MenuStyle.Red, 70, 1, function()
				Clan:FireServer("Kick", id)
			end)
		end
	end
end

local function renderRequests(clan: { [string]: any })
	clear(memberList)
	local requests = clan.Requests or {}
	for i = #requests, 1, -1 do -- (newest first)
		local entry = requests[i]
		local id = tonumber(entry.Id) or 0
		local frame = card(memberList, #requests - i + 1, ROW_HEIGHT)
		face(frame, id, 40, UDim2.new(0, 7, 0.5, 0), Vector2.new(0, 0.5))
		leftText(frame, tostring(entry.Name), UDim2.new(1, -250, 0, 22), UDim2.fromOffset(56, 6), nil, 2)
		local message = if typeof(entry.Message) == "string" and entry.Message ~= "" then `"{entry.Message}"` else "NO MESSAGE"
		local line = leftText(frame, `{message} · {ago(tonumber(entry.At) or 0)}`, UDim2.new(1, -250, 0, 15), UDim2.fromOffset(56, 31), SOFT_TEXT)
		line.TextScaled = false
		line.TextSize = 14
		line.TextTruncate = Enum.TextTruncate.AtEnd
		local buttons = buttonStrip(frame, 200)
		smallButton(buttons, "Accept", MenuStyle.Green, 94, 1, function()
			Clan:FireServer("AcceptRequest", id)
		end)
		smallButton(buttons, "No", MenuStyle.Red, 60, 2, function()
			Clan:FireServer("DeclineRequest", id)
		end)
	end
	if #requests == 0 then
		emptyLine(memberList, "NO REQUESTS RIGHT NOW")
	end
end

-- Players here who could be invited (not in a clan)
local function renderPicker()
	clear(pickerList)
	local others = {}
	for _, other in Players:GetPlayers() do
		if other ~= player and not other:GetAttribute("ClanId") then
			table.insert(others, other)
		end
	end
	table.sort(others, function(a, b)
		return a.DisplayName < b.DisplayName
	end)
	local now = os.clock()
	for i, other in others do
		local frame = card(pickerList, i, ROW_HEIGHT)
		face(frame, other.UserId, 40, UDim2.new(0, 7, 0.5, 0), Vector2.new(0, 0.5))
		leftText(frame, other.DisplayName, UDim2.new(1, -200, 0, 22), UDim2.fromOffset(56, 6), nil, 2)
		leftText(frame, `@{other.Name} · LEVEL {other:GetAttribute("Level") or 1}`, UDim2.new(1, -200, 0, 15), UDim2.fromOffset(56, 31), SOFT_TEXT)
		local pending = (sent[other] or 0) > now
		local buttons = buttonStrip(frame, 130)
		smallButton(buttons, if pending then "Sent" else "Invite", if pending then MenuStyle.Grey else MenuStyle.Green, 110, 1, function()
			if not pending then
				Clan:FireServer("Invite", other)
			end
		end)
	end
	if #others == 0 then
		emptyLine(pickerList, "NOBODY HERE WITHOUT A CLAN")
	end
end

local function renderHome(clan: { [string]: any })
	clear(homeLeft)
	local badge = badgeHolder(homeLeft, 64, UDim2.fromOffset(14, 14))
	drawBadge(badge, clan.Badge)
	leftText(homeLeft, `[{clan.Tag}]`, UDim2.fromOffset(220, 30), UDim2.fromOffset(90, 14), MenuStyle.Gold, 2)
	leftText(homeLeft, string.upper(tostring(clan.Name)), UDim2.fromOffset(226, 24), UDim2.fromOffset(90, 48), nil, 2)
	local description = leftText(homeLeft, if clan.Description ~= "" then clan.Description else "NO DESCRIPTION", UDim2.fromOffset(302, 36), UDim2.fromOffset(14, 88), SOFT_TEXT, 1)
	description.TextScaled = false
	description.TextSize = 15
	description.TextWrapped = true
	description.TextYAlignment = Enum.TextYAlignment.Top
	leftText(homeLeft, `MEMBERS {clan.Members}/{clan.Max} · WINS {formatNumber(clan.Wins)} · KILLS {formatNumber(clan.Kills)}`, UDim2.fromOffset(302, 16), UDim2.fromOffset(14, 130))
	local who = strip(homeLeft, UDim2.fromOffset(14, 152), 302)
	stripText(who, Clans.TypeLabels[clan.Type] or "", 1, Color3.fromRGB(255, 225, 120))
	if clan.Type ~= "Invite" then
		local levelText, rankText = requirementTexts(clan.MinLevel, clan.MinRank)
		stripText(who, "· " .. levelText, 2)
		if rankText then
			stripText(who, "· " .. rankText, 3)
		end
	end

	leftText(homeLeft, "ACTIVITY", UDim2.fromOffset(200, 18), UDim2.fromOffset(14, 178), nil, 2)
	logList = scroller(homeLeft, UDim2.fromOffset(14, 200), UDim2.fromOffset(306, 100))
	local log = clan.Log or {}
	for i = #log, 1, -1 do
		local entry = log[i]
		local line = leftText(logList, `{logText(entry)} · {ago(tonumber(entry.At) or 0)}`, UDim2.new(1, -8, 0, 15), UDim2.new(), SOFT_TEXT, 1)
		line.LayoutOrder = #log - i
	end

	local role = myRole()
	if role == "Owner" then
		-- (the owner can't just leave: OWNER on someone else first, or disband)
		local disband = MenuStyle.Button(homeLeft, if confirmingNow("Disband") then "Sure?" else "Disband", MenuStyle.Red, UDim2.fromOffset(140, 44), UDim2.new(0, 14, 1, -12), Vector2.new(0, 1))
		disband.Activated:Connect(function()
			if confirmed("Disband") then
				Clan:FireServer("Disband")
			end
		end)
	else
		local leave = MenuStyle.Button(homeLeft, if confirmingNow("Leave") then "Sure?" else "Leave", MenuStyle.Red, UDim2.fromOffset(140, 44), UDim2.new(0, 14, 1, -12), Vector2.new(0, 1))
		leave.Activated:Connect(function()
			if confirmed("Leave") then
				Clan:FireServer("Leave")
			end
		end)
	end
	if isStaff() then
		local settingsButton = MenuStyle.Button(homeLeft, "Settings", Color3.fromRGB(100, 110, 130), UDim2.fromOffset(150, 44), UDim2.new(1, -14, 1, -12), Vector2.new(1, 1))
		settingsButton.Activated:Connect(function()
			local values = settingsForm.values
			values.Type, values.MinLevel, values.MinRank, values.Badge = clan.Type, clan.MinLevel, clan.MinRank, clan.Badge
			settingsForm.description.Text = clan.Description or ""
			settingsForm.refresh()
			overlay = "Settings"
		end)
	end

	-- Right: members (or join requests), INVITE
	clear(homeRight)
	local staff = isStaff()
	if not staff then
		rightView = "Members"
	end
	leftText(homeRight, if rightView == "Requests" then "JOIN REQUESTS" else `MEMBERS {clan.Members}/{clan.Max}`, UDim2.fromOffset(220, 24), UDim2.fromOffset(14, 11), nil, 2)
	if staff then
		local requests = #(clan.Requests or {})
		local toggle = MenuStyle.Button(homeRight, if rightView == "Requests" then "Members" else `Requests ({requests})`, if requests > 0 and rightView ~= "Requests" then MenuStyle.Gold else MenuStyle.Grey, UDim2.fromOffset(150, 38), UDim2.new(1, -138, 0, 6), Vector2.new(1, 0))
		toggle.Activated:Connect(function()
			rightView = if rightView == "Requests" then "Members" else "Requests"
		end)
		local inviteButton = MenuStyle.Button(homeRight, "Invite", MenuStyle.Green, UDim2.fromOffset(116, 38), UDim2.new(1, -12, 0, 6), Vector2.new(1, 0))
		inviteButton.Activated:Connect(function()
			overlay = "Picker"
		end)
	end
	memberList = scroller(homeRight, UDim2.fromOffset(10, 52), UDim2.new(1, -14, 1, -60))
	if rightView == "Requests" then
		renderRequests(clan)
	else
		renderMembers(clan)
	end
end

local function renderBrowse()
	clear(browseList)
	local entries = searchEntries or browseEntries
	browseHeading.Text = if searchEntries then "SEARCH RESULTS" else "RECOMMENDED FOR YOU"
	local level, tier = myLevel(), myTier()
	for i, entry in entries do
		if typeof(entry) ~= "table" or typeof(entry.Id) ~= "string" then
			continue
		end
		local frame = card(browseList, i, 70)
		drawBadge(badgeHolder(frame, 46, UDim2.new(0, 10, 0.5, 0), Vector2.new(0, 0.5)), entry.Badge)
		leftText(frame, `[{entry.Tag}] {string.upper(tostring(entry.Name))}`, UDim2.new(1, -250, 0, 22), UDim2.fromOffset(66, 5), nil, 2)
		local description = leftText(frame, tostring(entry.Description or ""), UDim2.new(1, -250, 0, 15), UDim2.fromOffset(66, 28), SOFT_TEXT, 1)
		description.TextScaled = false
		description.TextSize = 14
		description.TextTruncate = Enum.TextTruncate.AtEnd
		local line = strip(frame, UDim2.fromOffset(66, 47), 560)
		local members = tonumber(entry.Members) or 0
		stripText(line, `{members}/{Clans.MaxMembers}`, 1, Color3.new(1, 1, 1))
		stripText(line, "· " .. (Clans.TypeLabels[entry.Type] or ""), 2, Color3.fromRGB(255, 225, 120))
		local levelOk, rankOk = Clans.Meets(level, tier, tonumber(entry.MinLevel) or 1, tonumber(entry.MinRank) or 0)
		if entry.Type ~= "Invite" then
			local levelText, rankText = requirementTexts(tonumber(entry.MinLevel) or 1, tonumber(entry.MinRank) or 0)
			stripText(line, "· " .. levelText, 3)
			mark(line, levelOk, 4)
			if rankText then
				stripText(line, rankText, 5)
				mark(line, rankOk, 6)
			end
		end

		local text, color, action = "Join", MenuStyle.Grey, nil :: (() -> ())?
		if entry.Type == "Invite" then
			text = "Invite Only"
		elseif members >= Clans.MaxMembers then
			text = "Full"
		elseif requested[entry.Id] or entry.Requested == true then
			text = "Requested"
		elseif entry.Type == "Request" then
			text = "Request"
			if levelOk and rankOk then
				color = MenuStyle.Blue
				action = function()
					requestingId = entry.Id
					requestTitle.Text = `ASK TO JOIN [{entry.Tag}]`
					requestBox.Text = ""
					overlay = "Request"
				end
			end
		elseif levelOk and rankOk then
			color = MenuStyle.Green
			action = function()
				Clan:FireServer("Join", entry.Id)
			end
		end
		local buttons = buttonStrip(frame, 160)
		smallButton(buttons, text, color, 150, 1, action)
	end
	if #entries == 0 then
		emptyLine(browseList, if searchEntries then "NO CLANS FOUND · TRY THE EXACT TAG" else "NO CLANS TO SHOW YET · FOUND ONE IN CREATE")
	end
end

local function renderTop()
	local myId = if info then info.Id else nil
	for _, board in { "Wins", "Kills" } do
		local list = topLists[board]
		clear(list)
		local raw = boardFolder:GetAttribute(board)
		local ok, entries = pcall(HttpService.JSONDecode, HttpService, if typeof(raw) == "string" then raw else "[]")
		entries = if ok and typeof(entries) == "table" then entries else {}
		for i, entry in entries do
			if typeof(entry) ~= "table" then
				continue
			end
			local frame = card(list, i, 26, if entry.Id == myId then MenuStyle.Gold else nil)
			leftText(frame, `{i}`, UDim2.fromOffset(26, 18), UDim2.fromOffset(8, 4), SOFT_TEXT)
			drawBadge(badgeHolder(frame, 22, UDim2.new(0, 34, 0.5, 0), Vector2.new(0, 0.5)), entry.Badge)
			leftText(frame, `[{entry.Tag}] {string.upper(tostring(entry.Name))}`, UDim2.new(1, -170, 0, 18), UDim2.fromOffset(62, 4), if entry.Id == myId then MenuStyle.Gold else nil)
			local value = MenuStyle.Text(frame, formatNumber(tonumber(entry[board]) or 0), UDim2.fromOffset(90, 18), UDim2.new(1, -10, 0, 4), Vector2.new(1, 0))
			value.TextXAlignment = Enum.TextXAlignment.Right
			thinOutline(value, 1.5)
		end
		if #entries == 0 then
			emptyLine(list, "NO CLANS YET")
		end
	end
	topStatus.Text = if boardFolder:GetAttribute("Live") then "CLANS FROM EVERY SERVER · UPDATED EVERY FEW MINUTES" else "SHOWING THIS SERVER'S CLANS"
end

local function render()
	local clan = info
	if clan and tab == "Browse" then
		tab = "Home"
	end
	(tabButtons.Home:FindFirstChild("Label") :: TextLabel).Text = if clan then "My Clan" else "Create"
	tabButtons.Browse.Visible = clan == nil
	for name, button in tabButtons do
		MenuStyle.SetButtonColor(button, if tab == name then MenuStyle.Blue else MenuStyle.Grey)
	end
	if overlay == "Settings" and not (clan and isStaff() and tab == "Home") then
		overlay = nil
	elseif overlay == "Picker" and not (clan and isStaff() and tab == "Home") then
		overlay = nil
	elseif overlay == "Request" and tab ~= "Browse" then
		overlay = nil
	end
	pages.Home.Visible = tab == "Home" and clan ~= nil and overlay ~= "Settings"
	pages.Create.Visible = tab == "Home" and clan == nil
	pages.Browse.Visible = tab == "Browse"
	pages.Top.Visible = tab == "Top"
	settingsOverlay.Visible = overlay == "Settings"
	pickerOverlay.Visible = overlay == "Picker"
	requestOverlay.Visible = overlay == "Request"

	if pages.Home.Visible and clan then
		renderHome(clan)
		if overlay == "Picker" then
			renderPicker()
		end
	elseif pages.Create.Visible then
		createForm.hint.Text = `COSTS {formatNumber(Clans.CreateCost)} CREDITS · YOU HAVE {formatNumber(number("Credits", 0))}`
		refreshLock()
	elseif pages.Browse.Visible then
		renderBrowse()
	elseif pages.Top.Visible then
		renderTop()
	end
end

-- What the screen shows; it's rebuilt when this changes
local function renderKey(): string
	local now = os.clock()
	local parts = {
		tab, overlay or "", rightView, tostring(infoVersion), tostring(listVersion), tostring(boardVersion),
		if confirming and confirming.ends > now then confirming.what else "",
		tostring(player:GetAttribute("Level")), tostring(player:GetAttribute("Credits")),
	}
	for _, someone in Players:GetPlayers() do
		local pending = if (sent[someone] or 0) > now then 1 else 0
		table.insert(parts, `{someone.UserId}/{someone:GetAttribute("ClanId") or ""}/{pending}`)
	end
	return table.concat(parts, ",")
end

-- ─── Building ──────────────────────────────────────────────────────────────────

local function overlayFrame(parent: Instance, size: UDim2, position: UDim2): Frame
	local frame = Instance.new("Frame")
	frame.Position = position
	frame.Size = size
	frame.BackgroundColor3 = MenuStyle.Panel
	frame.Active = true
	frame.Visible = false
	frame.ZIndex = 10
	MenuStyle.Corner(frame, UDim.new(0, 14))
	MenuStyle.Rim(frame, MenuStyle.Blue, 3)
	frame.Parent = parent
	return frame
end

local function buildScreen()
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
	content.Size = UDim2.fromOffset(BODY.X, BODY.Y + 68)
	content.BackgroundTransparency = 1
	content.Parent = screen
	MenuStyle.FitToScreen(content, Vector2.new(BODY.X, BODY.Y + 68))

	leftText(content, "CLAN", UDim2.fromOffset(130, 56), UDim2.new(), Color3.new(1, 1, 1), 2.5)
	for i, entry in { { "Home", "My Clan" }, { "Browse", "Browse" }, { "Top", "Top Clans" } } do
		local button = MenuStyle.Button(content, entry[2], MenuStyle.Grey, UDim2.fromOffset(150, 48), UDim2.fromOffset(140 + (i - 1) * 160, 4))
		button.Activated:Connect(function()
			tab = entry[1]
			if tab == "Browse" then
				browse()
			end
		end)
		tabButtons[entry[1]] = button
	end
	local back = MenuStyle.Button(content, "Back", MenuStyle.Red, UDim2.fromOffset(150, 56), UDim2.new(1, 0, 0, 0), Vector2.new(1, 0))
	back.Activated:Connect(ClanMenu.Close)

	local body = Instance.new("Frame")
	body.Position = UDim2.fromOffset(0, 68)
	body.Size = UDim2.fromOffset(BODY.X, BODY.Y)
	body.BackgroundTransparency = 1
	body.Parent = content
	local function page(name: string): Frame
		local frame = Instance.new("Frame")
		frame.Name = name
		frame.Size = UDim2.fromScale(1, 1)
		frame.BackgroundTransparency = 1
		frame.Visible = false
		frame.Parent = body
		pages[name] = frame
		return frame
	end

	-- MY CLAN
	local home = page("Home")
	homeLeft = panel(home, UDim2.new(), UDim2.fromOffset(330, BODY.Y), "")
	homeRight = panel(home, UDim2.fromOffset(342, 0), UDim2.fromOffset(538, BODY.Y), "")
	pickerOverlay = overlayFrame(home, UDim2.fromOffset(538, BODY.Y), UDim2.fromOffset(342, 0))
	leftText(pickerOverlay, "INVITE SOMEONE HERE", UDim2.fromOffset(300, 24), UDim2.fromOffset(14, 11), nil, 2).ZIndex = 11
	local closePicker = MenuStyle.Button(pickerOverlay, "Done", MenuStyle.Grey, UDim2.fromOffset(110, 38), UDim2.new(1, -12, 0, 6), Vector2.new(1, 0))
	closePicker.Activated:Connect(function()
		overlay = nil
	end)
	pickerList = scroller(pickerOverlay, UDim2.fromOffset(10, 52), UDim2.new(1, -14, 1, -60))

	-- CREATE
	createForm = buildForm(page("Create"), true)

	-- BROWSE
	local browsePage = page("Browse")
	searchBox = textBox(browsePage, "Clan name or exact tag", UDim2.fromOffset(520, 46), UDim2.new())
	limit(searchBox, 20)
	local searchButton = MenuStyle.Button(browsePage, "Search", MenuStyle.Blue, UDim2.fromOffset(160, 46), UDim2.fromOffset(530, 0))
	local function runSearch()
		local text = searchBox.Text
		if #text >= 2 then
			Clan:FireServer("Search", text)
		end
	end
	searchButton.Activated:Connect(runSearch)
	searchBox.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			runSearch()
		end
	end)
	local recommendedButton = MenuStyle.Button(browsePage, "Recommended", MenuStyle.Grey, UDim2.fromOffset(180, 46), UDim2.new(1, 0, 0, 0), Vector2.new(1, 0))
	recommendedButton.Activated:Connect(function()
		searchEntries = nil
		searchBox.Text = ""
		listVersion += 1
		browse(true)
	end)
	local listPanel, heading = panel(browsePage, UDim2.fromOffset(0, 56), UDim2.fromOffset(BODY.X, BODY.Y - 56), "")
	browseHeading = heading
	browseList = scroller(listPanel, UDim2.fromOffset(10, 42), UDim2.new(1, -14, 1, -50))

	requestOverlay = overlayFrame(browsePage, UDim2.fromOffset(500, 200), UDim2.fromOffset(190, 80))
	requestTitle = MenuStyle.Text(requestOverlay, "", UDim2.fromOffset(460, 30), UDim2.new(0.5, 0, 0, 14), Vector2.new(0.5, 0))
	requestTitle.ZIndex = 11
	requestBox = textBox(requestOverlay, `A short message (optional, {Clans.MaxMessage} letters)`, UDim2.fromOffset(460, 44), UDim2.fromOffset(20, 56))
	requestBox.ZIndex = 11
	limit(requestBox, Clans.MaxMessage)
	local send = MenuStyle.Button(requestOverlay, "Send", MenuStyle.Green, UDim2.fromOffset(180, 52), UDim2.new(1, -20, 1, -16), Vector2.new(1, 1))
	send.Activated:Connect(function()
		if requestingId then
			Clan:FireServer("Request", requestingId, requestBox.Text)
		end
		overlay = nil
	end)
	local cancel = MenuStyle.Button(requestOverlay, "Cancel", MenuStyle.Red, UDim2.fromOffset(140, 52), UDim2.new(1, -212, 1, -16), Vector2.new(1, 1))
	cancel.Activated:Connect(function()
		overlay = nil
	end)

	-- TOP CLANS
	local top = page("Top")
	for i, entry in { { "Wins", "MOST MATCHES WON" }, { "Kills", "MOST KILLS" } } do
		local frame = panel(top, UDim2.fromOffset((i - 1) * 446, 0), UDim2.fromOffset(434, BODY.Y - 26), entry[2])
		local list = Instance.new("Frame")
		list.Position = UDim2.fromOffset(10, 42)
		list.Size = UDim2.new(1, -20, 1, -50)
		list.BackgroundTransparency = 1
		list.Parent = frame
		listLayout(list, 2)
		topLists[entry[1]] = list
	end
	topStatus = MenuStyle.Text(top, "", UDim2.fromOffset(600, 16), UDim2.new(0.5, 0, 1, -2), Vector2.new(0.5, 1))
	topStatus.TextColor3 = SOFT_TEXT
	thinOutline(topStatus, 1)

	-- SETTINGS (over the whole body)
	settingsOverlay = Instance.new("Frame")
	settingsOverlay.Size = UDim2.fromScale(1, 1)
	settingsOverlay.BackgroundTransparency = 1
	settingsOverlay.Visible = false
	settingsOverlay.ZIndex = 20
	settingsOverlay.Parent = body
	settingsForm = buildForm(settingsOverlay, false)
end

-- The invite popup (top middle, under the party's) with the notices under it, over every menu
local function buildPopup()
	local top = Instance.new("ScreenGui")
	top.Name = "ClanInvite"
	top.IgnoreGuiInset = true
	top.ResetOnSpawn = false
	top.DisplayOrder = 8 -- over the clan screen and the shop
	top.Parent = player:WaitForChild("PlayerGui")

	local holder = Instance.new("Frame")
	holder.AnchorPoint = Vector2.new(0.5, 0)
	holder.Position = UDim2.new(0.5, 0, 0, 230)
	holder.Size = UDim2.fromOffset(460, 180)
	holder.BackgroundTransparency = 1
	holder.Parent = top
	MenuStyle.FitToScreen(holder, Vector2.new(500, 560))
	local stack = Instance.new("UIListLayout")
	stack.HorizontalAlignment = Enum.HorizontalAlignment.Center
	stack.SortOrder = Enum.SortOrder.LayoutOrder
	stack.Padding = UDim.new(0, 8)
	stack.Parent = holder

	popup = Instance.new("Frame")
	popup.LayoutOrder = 1
	popup.Size = UDim2.fromOffset(460, 140)
	popup.BackgroundColor3 = MenuStyle.Panel
	popup.BackgroundTransparency = 0.05
	popup.Visible = false
	MenuStyle.Corner(popup, UDim.new(0, 14))
	MenuStyle.Rim(popup, PURPLE, 3)
	popup.Parent = holder
	popupBadge = badgeHolder(popup, 64, UDim2.fromOffset(16, 16))
	popupName = leftText(popup, "", UDim2.fromOffset(250, 30), UDim2.fromOffset(94, 16), nil, 2.5)
	popupLine = leftText(popup, "", UDim2.fromOffset(340, 18), UDim2.fromOffset(94, 50), Color3.fromRGB(190, 195, 205))
	popupMore = MenuStyle.Text(popup, "", UDim2.fromOffset(100, 16), UDim2.new(1, -14, 0, 14), Vector2.new(1, 0))
	popupMore.TextXAlignment = Enum.TextXAlignment.Right
	popupMore.TextColor3 = SOFT_TEXT
	thinOutline(popupMore, 1.5)

	local function answer(action: string)
		local invite = table.remove(invites, 1)
		if invite then
			Clan:FireServer(action, invite.from)
		end
	end
	local join = MenuStyle.Button(popup, "Join", MenuStyle.Green, UDim2.fromOffset(170, 52), UDim2.new(1, -134, 1, -16), Vector2.new(1, 1))
	join.Activated:Connect(function()
		answer("Accept")
	end)
	local no = MenuStyle.Button(popup, "No", MenuStyle.Red, UDim2.fromOffset(110, 52), UDim2.new(1, -14, 1, -16), Vector2.new(1, 1))
	no.Activated:Connect(function()
		answer("Decline")
	end)

	local track = Instance.new("Frame")
	track.AnchorPoint = Vector2.new(0, 1)
	track.Position = UDim2.new(0, 16, 1, -5)
	track.Size = UDim2.new(1, -32, 0, 4)
	track.BackgroundColor3 = Color3.fromRGB(46, 50, 60)
	track.BorderSizePixel = 0
	MenuStyle.Corner(track, UDim.new(1, 0))
	track.Parent = popup
	popupTimer = Instance.new("Frame")
	popupTimer.Size = UDim2.fromScale(1, 1)
	popupTimer.BackgroundColor3 = PURPLE
	popupTimer.BorderSizePixel = 0
	MenuStyle.Corner(popupTimer, UDim.new(1, 0))
	popupTimer.Parent = track

	noticeLabel = MenuStyle.Text(holder, "", UDim2.fromOffset(460, 24), UDim2.new())
	noticeLabel.LayoutOrder = 2
	noticeLabel.TextColor3 = Color3.fromRGB(255, 225, 120)
	noticeLabel.Visible = false
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "Clan"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 8 -- (the screen: over the lobby menu, the shop's and the party's buttons)
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Lobby: [badge TAG] over the CLAN button, just left of the PARTY's. Laid out like PartyMenu's
	-- widget (same anchor, size and screen fit), so the two shrink together on small screens.
	widget = Instance.new("Frame")
	widget.Name = "LobbyClan"
	widget.AnchorPoint = Vector2.new(1, 0.5)
	widget.Position = UDim2.new(1, -20, 0.5, 0)
	widget.Size = UDim2.fromOffset(342, 150)
	widget.BackgroundTransparency = 1
	widget.Visible = false
	widget.Parent = gui
	MenuStyle.FitToScreen(widget, Vector2.new(900, 520))
	local pill = Instance.new("Frame")
	pill.Size = UDim2.fromOffset(130, 50)
	pill.BackgroundColor3 = MenuStyle.Panel
	pill.BackgroundTransparency = 0.1
	MenuStyle.Corner(pill, UDim.new(1, 0))
	MenuStyle.Rim(pill, EDGE, 3)
	pill.Parent = widget
	widgetBadge = badgeHolder(pill, 30, UDim2.new(0, 12, 0.5, 0), Vector2.new(0, 0.5))
	widgetTag = MenuStyle.Text(pill, "", UDim2.fromOffset(76, 22), UDim2.new(0, 46, 0.5, 0), Vector2.new(0, 0.5))
	widgetTag.TextXAlignment = Enum.TextXAlignment.Left
	thinOutline(widgetTag, 2)
	local clanButton = MenuStyle.Button(widget, "Clan", PURPLE, UDim2.fromOffset(130, 80), UDim2.new(0, 0, 1, 0), Vector2.new(0, 1))
	clanButton.Activated:Connect(ClanMenu.Open)

	buildScreen()
	buildPopup()
end

local function refreshWidget()
	local tag = player:GetAttribute("ClanTag")
	if typeof(tag) == "string" and tag ~= "" then
		widgetBadge.Visible = true
		drawBadge(widgetBadge, player:GetAttribute("ClanBadge"))
		widgetTag.Text = `[{tag}]`
		widgetTag.Position = UDim2.new(0, 46, 0.5, 0)
		widgetTag.TextColor3 = MenuStyle.Gold
	else
		widgetBadge.Visible = false
		widgetTag.Text = "NO CLAN"
		widgetTag.Position = UDim2.new(0, 27, 0.5, 0)
		widgetTag.TextColor3 = SOFT_TEXT
	end
end

local function update()
	local now = os.clock()
	local lobby = inLobbyMenu()
	if screenOpen and not lobby then
		ClanMenu.Close() -- a match is starting
	end
	widget.Visible = lobby and not screenOpen and not state.shopOpen and not state.modesOpen and not state.partyOpen
	if screenOpen then
		local key = renderKey()
		if key ~= shownKey then
			shownKey = key
			render()
		end
	end

	for i = #invites, 1, -1 do
		if invites[i].ends <= now or not invites[i].from.Parent then
			table.remove(invites, i)
		end
	end
	local invite = invites[1]
	popup.Visible = lobby and invite ~= nil
	if invite then
		if popupName.Text ~= `[{invite.tag}] {string.upper(invite.name)}` then
			popupName.Text = `[{invite.tag}] {string.upper(invite.name)}`
			drawBadge(popupBadge, invite.badge)
		end
		popupLine.Text = `{string.upper(invite.from.DisplayName)} INVITED YOU TO THEIR CLAN`
		popupMore.Text = if #invites > 1 then `+{#invites - 1} MORE` else ""
		popupTimer.Size = UDim2.fromScale(math.clamp((invite.ends - now) / invite.total, 0, 1), 1)
	end
	noticeLabel.Text = noticeText
	noticeLabel.Visible = lobby and now < noticeEnds
end

function ClanMenu.Open()
	if screenOpen then
		return
	end
	screenOpen = true
	screen.Visible = true
	shownKey = ""
	Clan:FireServer("Refresh") -- (BROWSE asks for its list when it's opened)
end

function ClanMenu.Close()
	screenOpen = false
	overlay = nil
	if screen then
		screen.Visible = false
	end
end

function ClanMenu.Start()
	Clan = Remotes:WaitForChild("Clan") :: RemoteEvent
	boardFolder = ReplicatedStorage:WaitForChild("ClanBoard")
	build()
	refreshWidget()
	for _, attribute in { "ClanTag", "ClanBadge" } do
		player:GetAttributeChangedSignal(attribute):Connect(refreshWidget)
	end
	boardFolder.AttributeChanged:Connect(function()
		boardVersion += 1
	end)

	-- [TAG] in chat, after the [VIP] (ShopMenu)
	ChatTags.Add(2, function(sender)
		local tag = sender:GetAttribute("ClanTag")
		return if typeof(tag) == "string" and tag ~= "" then `<font color="{TAG_COLOR}">[{tag}]</font>` else nil
	end)

	Clan.OnClientEvent:Connect(function(event, a, b, c, d, e)
		if event == "Info" then
			info = if typeof(a) == "table" then a else nil
			infoVersion += 1
		elseif event == "Invite" and typeof(a) == "Instance" and a:IsA("Player") and typeof(e) == "number" then
			for i, invite in invites do
				if invite.from == a then
					table.remove(invites, i)
					break
				end
			end
			table.insert(invites, { from = a, tag = tostring(b), name = tostring(c), badge = tonumber(d) or 1, ends = os.clock() + e, total = e })
		elseif event == "Sent" and typeof(a) == "Instance" and a:IsA("Player") and typeof(b) == "number" then
			sent[a] = os.clock() + b
		elseif event == "Answered" and typeof(a) == "Instance" and a:IsA("Player") then
			sent[a] = nil
		elseif event == "Notice" and typeof(a) == "string" then
			notify(a)
		elseif event == "Browse" and typeof(a) == "table" then
			browseEntries = a
			listVersion += 1
		elseif event == "Search" and typeof(a) == "table" then
			searchEntries = a
			listVersion += 1
		elseif event == "Requested" and typeof(a) == "string" then
			requested[a] = true
			listVersion += 1
		elseif event == "Created" then
			if createForm.name and createForm.tag then
				createForm.name.Text = ""
				createForm.tag.Text = ""
			end
			createForm.description.Text = ""
			tab = "Home"
		end
	end)
	Players.PlayerRemoving:Connect(function(other)
		sent[other] = nil
	end)
	RunService.RenderStepped:Connect(update)
end

return ClanMenu
