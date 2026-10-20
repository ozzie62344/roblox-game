-- CUSTOM matches (lobby): a private match for you and your friends (server CustomMatchService,
-- settings: shared/CustomMatch).
--   The CUSTOM button sits on the right under the TUTORIAL (hidden while you're searching, like it).
--   The custom screen: CREATE a lobby, or JOIN WITH A CODE (6 letters / numbers; a lobby on another
--   server takes you there first).
--   In a lobby: its CODE at the top (click it to select and copy), the BLUE and ORANGE teams and the
--   SPECTATORS side by side, and the settings on the right. The host moves players with < / >,
--   KICKs, changes the settings, SHUFFLEs the teams and STARTs; anyone can INVITE players in this
--   server and LEAVE. BACK just closes the screen (you stay in the lobby).
--   An invite pops up at the top, "<name> invited you to a custom match", with JOIN / NO.
-- Custom matches give no XP, credits, ranked or stats: the screen says so before you create one.

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local LoadingScreen = require(ReplicatedFirst:WaitForChild("LoadingScreen"))
local CustomMatch = require(ReplicatedStorage.Shared.CustomMatch)
local state = require(script.Parent.Parent.PlayerState)
local LobbyIntro = require(script.Parent.LobbyIntro)
local MenuStyle = require(script.Parent.MenuStyle)
local Tutorial = require(script.Parent.Tutorial)

local MatchState = ReplicatedStorage:WaitForChild("MatchState")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local player = Players.LocalPlayer

local CustomMatchMenu = {}

local CARD = Color3.fromRGB(36, 39, 48)
local EDGE = Color3.fromRGB(60, 64, 76)
local SOFT_TEXT = Color3.fromRGB(150, 156, 170)
local NOTE_YELLOW = Color3.fromRGB(255, 225, 120)
local CUSTOM_COLOR = Color3.fromRGB(225, 110, 45)
local COLUMNS = { "Blue", "Orange", "Spectate" } -- (< / > move a player one column along)
local COLUMN_NAMES = { Blue = "BLUE", Orange = "ORANGE", Spectate = "SPECTATORS" }
local COLUMN_COLORS = { Blue = Color3.fromRGB(70, 140, 255), Orange = Color3.fromRGB(255, 145, 50), Spectate = SOFT_TEXT }
local ROW_HEIGHT = 64
local SETTING_ROW = 27
local NOTICE_TIME = 4
local INVITE_COOLDOWN = 30 -- (the server says no to asking again sooner anyway)

type Member = { Player: Player, Team: string }
type View = {
	Code: string,
	Host: Player?,
	Members: { Member },
	Settings: { [string]: any },
	Maps: { string },
	TeamSize: number,
	MaxPlayers: number,
	Starting: boolean,
}
type Invite = { from: Player, code: string, ends: number, total: number }

local Remote: RemoteEvent? = nil
local view: View? = nil -- my lobby (nil: not in one)
local screenOpen = false
local inviteOpen = false
local invites: { Invite } = {} -- invites to me, oldest first
local sent: { [Player]: number } = {} -- my invites → when I can ask again (os.clock)
local noticeText, noticeEnds = "", 0
local shownInvites = "" -- what the invite list was last built for

local buttonHolder: Frame
local lobbyButton: TextButton
local screen: Frame
local startPage: Frame
local lobbyPage: Frame
local codeInput: TextBox
local codeBox: TextBox
local columnLists: { [string]: ScrollingFrame } = {}
local columnTitles: { [string]: TextLabel } = {}
local settingsList: Frame
local settingsHint: TextLabel
local shuffleButton: TextButton
local startButton: TextButton
local statusLabel: TextLabel
local screenNotice: TextLabel
local inviteOverlay: Frame
local inviteList: ScrollingFrame
local popup: Frame
local popupFace: ImageLabel
local popupName: TextLabel
local popupMore: TextLabel
local popupTimer: Frame
local popupNotice: TextLabel

local function fire(...: any)
	if Remote then
		Remote:FireServer(...)
	end
end

local function showNotice(text: string)
	noticeText, noticeEnds = text, os.clock() + NOTICE_TIME
end

local function isHost(): boolean
	return view ~= nil and view.Host == player
end

local inLobbyMenu = LobbyIntro.InLobby

-- Another lobby menu has the screen
local function otherMenuOpen(): boolean
	return state.shopOpen or state.partyOpen or state.modesOpen or state.settingsOpen or state.modsOpen
		or state.resultsOpen or state.devPanelOpen
end

local thinOutline = MenuStyle.ThinOutline

local function leftText(parent: Instance, text: string, size: UDim2, position: UDim2, anchor: Vector2?): TextLabel
	local label = MenuStyle.Text(parent, text, size, position, anchor)
	label.TextXAlignment = Enum.TextXAlignment.Left
	return label
end

-- (blank for Studio's test players)
local function headshot(userId: number): string
	return if userId > 0 then `rbxthumb://type=AvatarHeadShot&id={userId}&w=150&h=150` else ""
end

-- A round head shot
local function face(parent: Instance, userId: number, size: number, position: UDim2, anchor: Vector2?): ImageLabel
	local image = Instance.new("ImageLabel")
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

local function listLayout(parent: Instance, padding: number)
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, padding)
	layout.Parent = parent
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
	local title = leftText(frame, heading, UDim2.new(1, -28, 0, 22), UDim2.fromOffset(14, 11))
	thinOutline(title, 2)
	return frame, title
end

local function scrollList(parent: Instance, position: UDim2, size: UDim2): ScrollingFrame
	local list = Instance.new("ScrollingFrame")
	list.Position = position
	list.Size = size
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.ScrollBarThickness = 5
	list.ScrollBarImageColor3 = Color3.fromRGB(120, 124, 135)
	list.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.Parent = parent
	listLayout(list, 6)
	return list
end

-- A player card: face, name, a short line under it (buttons go along the bottom right)
local function card(list: Instance, order: number, who: Player, line: string, lineColor: Color3): Frame
	local frame = Instance.new("Frame")
	frame.LayoutOrder = order
	frame.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
	frame.BackgroundColor3 = CARD
	MenuStyle.Corner(frame, UDim.new(0, 10))
	MenuStyle.Rim(frame, EDGE, 2).Name = "Rim"
	face(frame, who.UserId, 40, UDim2.fromOffset(6, 6))
	local name = leftText(frame, who.DisplayName, UDim2.new(1, -58, 0, 20), UDim2.fromOffset(52, 5))
	thinOutline(name, 2)
	local sub = leftText(frame, line, UDim2.new(0, 64, 0, 14), UDim2.fromOffset(52, 34))
	sub.TextColor3 = lineColor
	thinOutline(sub, 1.5)
	frame.Parent = list
	return frame
end

local function smallButton(parent: Instance, text: string, color: Color3, width: number, right: number, onPress: () -> ()): TextButton
	local button = MenuStyle.Button(parent, text, color, UDim2.fromOffset(width, 26), UDim2.new(1, -right, 1, -5), Vector2.new(1, 1))
	button.Activated:Connect(onPress)
	return button
end

-- ─── The lobby ─────────────────────────────────────────────────────────────────

local function memberCard(list: Instance, order: number, member: Member, column: number)
	local current = view :: View
	local who = member.Player
	local hosting = current.Host == who
	local line = if hosting and who == player then "HOST · YOU" elseif hosting then "HOST" elseif who == player then "YOU" else ""
	local frame = card(list, order, who, line, if hosting then MenuStyle.Gold else SOFT_TEXT)
	if hosting then
		(frame:FindFirstChild("Rim") :: UIStroke).Color = MenuStyle.Gold
	end
	if not isHost() or current.Starting then
		return
	end
	local function moveTo(target: string)
		if who == player then
			fire("MoveSelf", target)
		else
			fire("Move", who, target)
		end
	end
	local right = 4
	if who ~= player then
		smallButton(frame, "Kick", MenuStyle.Red, 50, right, function()
			fire("Kick", who)
		end)
		right += 54
	end
	if column < #COLUMNS then
		smallButton(frame, ">", MenuStyle.Blue, 28, right, function()
			moveTo(COLUMNS[column + 1])
		end)
		right += 32
	end
	if column > 1 then
		smallButton(frame, "<", MenuStyle.Blue, 28, right, function()
			moveTo(COLUMNS[column - 1])
		end)
	end
end

local function cycleSetting(key: string, step: number)
	local current = view
	if not current then
		return
	end
	local options = CustomMatch.Options(key, current.Maps)
	local at = table.find(options, current.Settings[key]) or 1
	fire("Set", key, options[(at - 1 + step) % #options + 1])
end

local function rebuildSettings(current: View)
	clear(settingsList)
	local hosting = isHost() and not current.Starting
	for i, setting in CustomMatch.Settings do
		local row = Instance.new("Frame")
		row.Position = UDim2.fromOffset(0, (i - 1) * (SETTING_ROW + 2))
		row.Size = UDim2.new(1, 0, 0, SETTING_ROW)
		row.BackgroundColor3 = CARD
		MenuStyle.Corner(row, UDim.new(0, 6))
		row.Parent = settingsList
		local label = leftText(row, setting.Label, UDim2.fromOffset(150, 15), UDim2.new(0, 10, 0.5, 0), Vector2.new(0, 0.5))
		label.TextColor3 = SOFT_TEXT
		thinOutline(label, 1.5)
		local value = current.Settings[setting.Key]
		local valueLabel = MenuStyle.Text(row, CustomMatch.Label(setting.Key, value), UDim2.fromOffset(100, 16), UDim2.new(1, -95, 0.5, 0), Vector2.new(0.5, 0.5))
		thinOutline(valueLabel, 1.5)
		if value == true then
			valueLabel.TextColor3 = Color3.fromRGB(120, 255, 100)
		end
		if hosting then
			for _, step in { -1, 1 } do
				local arrow = MenuStyle.Button(row, if step < 0 then "<" else ">", MenuStyle.Blue, UDim2.fromOffset(26, 22),
					UDim2.new(1, if step < 0 then -170 else -6, 0.5, 0), Vector2.new(if step < 0 then 0 else 1, 0.5))
				arrow.Activated:Connect(function()
					cycleSetting(setting.Key, step)
				end)
			end
		end
	end
	settingsHint.Text = if hosting then "" elseif current.Host then `{string.upper(current.Host.DisplayName)} PICKS` else ""
end

local function rebuildLobby()
	local current = view
	if not current then
		return
	end
	codeBox.Text = current.Code
	for column, name in COLUMNS do
		local list = columnLists[name]
		clear(list)
		local n = 0
		for i, member in current.Members do
			local team = if member.Team == "" then "Spectate" else member.Team
			if team == name then
				n += 1
				memberCard(list, i, member, column)
			end
		end
		columnTitles[name].Text = if name == "Spectate" then `{COLUMN_NAMES[name]} · {n}` else `{COLUMN_NAMES[name]} · {n}/{current.TeamSize}`
	end
	rebuildSettings(current)
	local hosting = isHost()
	shuffleButton.Visible = hosting
	startButton.Visible = hosting
	MenuStyle.SetButtonColor(startButton, if current.Starting then MenuStyle.Grey else MenuStyle.Green)
	statusLabel.Text = if current.Starting then "MATCH STARTING..."
		elseif hosting then `{#current.Members}/{current.MaxPlayers} IN THE LOBBY`
		elseif current.Host then `WAITING FOR {string.upper(current.Host.DisplayName)} TO START`
		else ""
end

-- ─── Invites ───────────────────────────────────────────────────────────────────

local function inviteKey(now: number): string
	local parts = { if view then view.Code else "" }
	for _, someone in Players:GetPlayers() do
		local pending = if (sent[someone] or 0) > now then 1 else 0
		table.insert(parts, `{someone.UserId}/{someone:GetAttribute("CustomLobby") or ""}/{pending}`)
	end
	return table.concat(parts, ",")
end

local function rebuildInvites(now: number)
	clear(inviteList)
	local mine = if view then view.Code else nil
	local others = {}
	for _, other in Players:GetPlayers() do
		if other ~= player and (mine == nil or other:GetAttribute("CustomLobby") ~= mine) then
			table.insert(others, other)
		end
	end
	table.sort(others, function(a, b)
		return a.DisplayName < b.DisplayName
	end)
	for i, other in others do
		local busy = other:GetAttribute("CustomLobby") ~= nil
		local frame = card(inviteList, i, other, if busy then "IN A LOBBY" else `@{other.Name}`, SOFT_TEXT)
		local pending = (sent[other] or 0) > now
		smallButton(frame, if pending then "Sent" else "Invite", if pending then MenuStyle.Grey else MenuStyle.Green, 90, 6, function()
			if not pending then
				sent[other] = os.clock() + INVITE_COOLDOWN
				fire("Invite", other)
			end
		end)
	end
	if #others == 0 then
		local empty = MenuStyle.Text(inviteList, "NOBODY ELSE IS IN THIS SERVER YET", UDim2.new(1, -20, 0, 20), UDim2.new())
		empty.TextColor3 = SOFT_TEXT
		thinOutline(empty, 1.5)
	end
end

-- ─── Building ──────────────────────────────────────────────────────────────────

local function buildStartPage(content: Frame)
	startPage = Instance.new("Frame")
	startPage.Position = UDim2.fromOffset(0, 68)
	startPage.Size = UDim2.new(1, 0, 0, 330)
	startPage.BackgroundTransparency = 1
	startPage.Parent = content

	local create = panel(startPage, UDim2.new(), UDim2.new(0.5, -8, 1, 0), "CREATE A LOBBY")
	local lines = {
		{ "PICK THE MAP, THE MODE AND THE RULES", Color3.new(1, 1, 1) },
		{ "PUT YOUR FRIENDS ON TEAMS AND START", Color3.new(1, 1, 1) },
		{ "INVITE THEM OR SHARE THE CODE", Color3.new(1, 1, 1) },
		{ "NO XP, CREDITS, RANKED OR STATS IN CUSTOM MATCHES", NOTE_YELLOW },
	}
	for i, line in lines do
		local label = MenuStyle.Text(create, line[1], UDim2.new(1, -40, 0, 18), UDim2.new(0.5, 0, 0, 40 + i * 32), Vector2.new(0.5, 0))
		label.TextColor3 = line[2]
		thinOutline(label, 1.5)
	end
	local createButton = MenuStyle.Button(create, "Create", MenuStyle.Green, UDim2.fromOffset(240, 70), UDim2.new(0.5, 0, 1, -18), Vector2.new(0.5, 1))
	createButton.Activated:Connect(function()
		fire("Create")
	end)

	local joinPanel = panel(startPage, UDim2.new(0.5, 8, 0, 0), UDim2.new(0.5, -8, 1, 0), "JOIN WITH A CODE")
	local hint = MenuStyle.Text(joinPanel, `ENTER THE {CustomMatch.CodeLength}-CHARACTER CODE YOUR FRIEND SHARED`, UDim2.new(1, -40, 0, 18), UDim2.new(0.5, 0, 0, 72), Vector2.new(0.5, 0))
	hint.TextColor3 = SOFT_TEXT
	thinOutline(hint, 1.5)
	codeInput = Instance.new("TextBox")
	codeInput.AnchorPoint = Vector2.new(0.5, 0)
	codeInput.Position = UDim2.new(0.5, 0, 0, 112)
	codeInput.Size = UDim2.fromOffset(300, 70)
	codeInput.BackgroundColor3 = CARD
	codeInput.FontFace = MenuStyle.Font
	codeInput.TextScaled = true
	codeInput.TextColor3 = Color3.new(1, 1, 1)
	codeInput.PlaceholderText = "CODE"
	codeInput.PlaceholderColor3 = Color3.fromRGB(90, 95, 110)
	codeInput.ClearTextOnFocus = false
	codeInput.Text = ""
	MenuStyle.Corner(codeInput, UDim.new(0, 12))
	MenuStyle.Rim(codeInput, EDGE, 3)
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.Parent = codeInput
	codeInput.Parent = joinPanel
	-- Only the letters and numbers a code can have, in capitals, at most a code's length
	codeInput:GetPropertyChangedSignal("Text"):Connect(function()
		local cleaned = string.sub(string.gsub(string.upper(codeInput.Text), "[^A-Z0-9]", ""), 1, CustomMatch.CodeLength)
		if cleaned ~= codeInput.Text then
			codeInput.Text = cleaned
		end
	end)
	local function join()
		if #codeInput.Text == CustomMatch.CodeLength then
			fire("Join", codeInput.Text)
		else
			showNotice(`A CODE IS {CustomMatch.CodeLength} LETTERS AND NUMBERS`)
		end
	end
	codeInput.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			join()
		end
	end)
	local joinButton = MenuStyle.Button(joinPanel, "Join", MenuStyle.Blue, UDim2.fromOffset(240, 70), UDim2.new(0.5, 0, 1, -18), Vector2.new(0.5, 1))
	joinButton.Activated:Connect(join)
end

local function buildLobbyPage(content: Frame)
	lobbyPage = Instance.new("Frame")
	lobbyPage.Position = UDim2.fromOffset(0, 68)
	lobbyPage.Size = UDim2.new(1, 0, 1, -68)
	lobbyPage.BackgroundTransparency = 1
	lobbyPage.Visible = false
	lobbyPage.Parent = content

	-- Teams and spectators
	local x = 0
	for _, name in COLUMNS do
		local width = if name == "Spectate" then 210 else 230
		local column, title = panel(lobbyPage, UDim2.fromOffset(x, 0), UDim2.fromOffset(width, 340), COLUMN_NAMES[name])
		title.TextColor3 = COLUMN_COLORS[name]
		columnTitles[name] = title
		local rim = column:FindFirstChildOfClass("UIStroke") :: UIStroke
		rim.Color = COLUMN_COLORS[name]:Lerp(EDGE, 0.55)
		columnLists[name] = scrollList(column, UDim2.fromOffset(8, 42), UDim2.new(1, -12, 1, -50))
		x += width + 10
	end

	-- Settings
	local settingsPanel = panel(lobbyPage, UDim2.fromOffset(x, 0), UDim2.new(1, -x, 0, 340), "SETTINGS")
	settingsHint = MenuStyle.Text(settingsPanel, "", UDim2.fromOffset(180, 15), UDim2.new(1, -14, 0, 15), Vector2.new(1, 0))
	settingsHint.TextXAlignment = Enum.TextXAlignment.Right
	settingsHint.TextColor3 = NOTE_YELLOW
	thinOutline(settingsHint, 1.5)
	settingsList = Instance.new("Frame")
	settingsList.Position = UDim2.fromOffset(10, 42)
	settingsList.Size = UDim2.new(1, -20, 1, -48)
	settingsList.BackgroundTransparency = 1
	settingsList.Parent = settingsPanel

	-- Along the bottom: SHUFFLE, INVITE ... what's happening ... START
	shuffleButton = MenuStyle.Button(lobbyPage, "Shuffle", MenuStyle.Blue, UDim2.fromOffset(170, 60), UDim2.new(0, 0, 1, 0), Vector2.new(0, 1))
	shuffleButton.Activated:Connect(function()
		fire("Shuffle")
	end)
	local inviteButton = MenuStyle.Button(lobbyPage, "Invite", MenuStyle.Green, UDim2.fromOffset(170, 60), UDim2.new(0, 180, 1, 0), Vector2.new(0, 1))
	inviteButton.Activated:Connect(function()
		inviteOpen = true
		shownInvites = ""
	end)
	statusLabel = MenuStyle.Text(lobbyPage, "", UDim2.fromOffset(380, 22), UDim2.new(0, 370, 1, -19), Vector2.new(0, 1))
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left
	statusLabel.TextColor3 = NOTE_YELLOW
	thinOutline(statusLabel, 1.5)
	startButton = MenuStyle.Button(lobbyPage, "Start!", MenuStyle.Green, UDim2.fromOffset(240, 60), UDim2.fromScale(1, 1), Vector2.new(1, 1))
	startButton.Activated:Connect(function()
		if view and not view.Starting then
			fire("Start")
		end
	end)
end

-- Everyone in this server you could invite, over the lobby
local function buildInviteOverlay(content: Frame)
	inviteOverlay = Instance.new("Frame")
	inviteOverlay.Size = UDim2.fromScale(1, 1)
	inviteOverlay.BackgroundColor3 = Color3.new(0, 0, 0)
	inviteOverlay.BackgroundTransparency = 0.35
	inviteOverlay.Active = true
	inviteOverlay.Visible = false
	inviteOverlay.Parent = content
	local box = panel(inviteOverlay, UDim2.new(0.5, -240, 0, 40), UDim2.fromOffset(480, 400), "INVITE PLAYERS HERE")
	local close = MenuStyle.Button(box, "Done", MenuStyle.Red, UDim2.fromOffset(110, 40), UDim2.new(1, -10, 0, 8), Vector2.new(1, 0))
	close.Activated:Connect(function()
		inviteOpen = false
	end)
	inviteList = scrollList(box, UDim2.fromOffset(10, 58), UDim2.new(1, -14, 1, -66))
end

local function buildScreen()
	local gui = Instance.new("ScreenGui")
	gui.Name = "CustomMatch"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling -- (the invite overlay draws over the lobby)
	gui.DisplayOrder = 9 -- over the lobby menus' buttons (the party's and clan's are 7-8)
	gui.Parent = player:WaitForChild("PlayerGui")

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
	content.Size = UDim2.fromOffset(1060, 500)
	content.BackgroundTransparency = 1
	content.Parent = screen
	MenuStyle.FitToScreen(content, Vector2.new(1060, 600)) -- (room for the notice under it)

	local title = leftText(content, "CUSTOM MATCH", UDim2.fromOffset(300, 56), UDim2.new())
	title.TextColor3 = Color3.new(1, 1, 1)
	local back = MenuStyle.Button(content, "Back", MenuStyle.Red, UDim2.fromOffset(150, 56), UDim2.fromScale(1, 0), Vector2.new(1, 0))
	back.Activated:Connect(CustomMatchMenu.Close)

	-- In a lobby: its code (a read-only box, so it can be selected and copied) and LEAVE
	local codeHolder = Instance.new("Frame")
	codeHolder.Name = "Code"
	codeHolder.Position = UDim2.fromOffset(320, 4)
	codeHolder.Size = UDim2.fromOffset(330, 48)
	codeHolder.BackgroundColor3 = MenuStyle.Panel
	MenuStyle.Corner(codeHolder, UDim.new(0, 12))
	MenuStyle.Rim(codeHolder, MenuStyle.Gold, 3)
	codeHolder.Parent = content
	local codeLabel = leftText(codeHolder, "CODE", UDim2.fromOffset(70, 20), UDim2.new(0, 14, 0.5, 0), Vector2.new(0, 0.5))
	codeLabel.TextColor3 = SOFT_TEXT
	thinOutline(codeLabel, 1.5)
	codeBox = Instance.new("TextBox")
	codeBox.AnchorPoint = Vector2.new(1, 0.5)
	codeBox.Position = UDim2.new(1, -14, 0.5, 0)
	codeBox.Size = UDim2.fromOffset(220, 34)
	codeBox.BackgroundTransparency = 1
	codeBox.FontFace = MenuStyle.Font
	codeBox.TextScaled = true
	codeBox.TextColor3 = MenuStyle.Gold
	codeBox.TextEditable = false
	codeBox.ClearTextOnFocus = false
	codeBox.Text = ""
	codeBox.Parent = codeHolder
	local leave = MenuStyle.Button(content, "Leave", MenuStyle.Red, UDim2.fromOffset(150, 56), UDim2.new(1, -160, 0, 0), Vector2.new(1, 0))
	leave.Activated:Connect(function()
		inviteOpen = false
		fire("Leave")
	end)

	buildStartPage(content)
	buildLobbyPage(content)
	buildInviteOverlay(content)

	screenNotice = MenuStyle.Text(content, "", UDim2.new(1, 0, 0, 22), UDim2.new(0.5, 0, 1, 26), Vector2.new(0.5, 0))
	screenNotice.TextColor3 = NOTE_YELLOW
	thinOutline(screenNotice, 1.5)

	-- (the lobby-only pieces show with the lobby page)
	lobbyPage:GetPropertyChangedSignal("Visible"):Connect(function()
		codeHolder.Visible = lobbyPage.Visible
		leave.Visible = lobbyPage.Visible
	end)
	codeHolder.Visible = false
	leave.Visible = false
end

-- The invite popup (top middle) with notices under it, over every lobby menu
local function buildPopup()
	local top = Instance.new("ScreenGui")
	top.Name = "CustomInvite"
	top.IgnoreGuiInset = true
	top.ResetOnSpawn = false
	top.DisplayOrder = 9
	top.Parent = player:WaitForChild("PlayerGui")

	local holder = Instance.new("Frame")
	holder.AnchorPoint = Vector2.new(0.5, 0)
	holder.Position = UDim2.new(0.5, 0, 0, 64)
	holder.Size = UDim2.fromOffset(460, 180)
	holder.BackgroundTransparency = 1
	holder.Parent = top
	MenuStyle.FitToScreen(holder, Vector2.new(500, 380))
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
	MenuStyle.Rim(popup, CUSTOM_COLOR, 3)
	popup.Parent = holder
	popupFace = face(popup, 0, 64, UDim2.fromOffset(16, 16))
	popupName = leftText(popup, "", UDim2.fromOffset(240, 30), UDim2.fromOffset(94, 16))
	local line = leftText(popup, "INVITED YOU TO A CUSTOM MATCH", UDim2.fromOffset(300, 18), UDim2.fromOffset(94, 50))
	line.TextColor3 = Color3.fromRGB(190, 195, 205)
	thinOutline(line, 1.5)
	popupMore = MenuStyle.Text(popup, "", UDim2.fromOffset(100, 16), UDim2.new(1, -14, 0, 14), Vector2.new(1, 0))
	popupMore.TextXAlignment = Enum.TextXAlignment.Right
	popupMore.TextColor3 = SOFT_TEXT
	thinOutline(popupMore, 1.5)

	local function answer(action: string)
		local invite = table.remove(invites, 1)
		if invite then
			fire(action, invite.code)
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

	-- Time left: a bar along the bottom that runs down
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
	popupTimer.BackgroundColor3 = CUSTOM_COLOR
	popupTimer.BorderSizePixel = 0
	MenuStyle.Corner(popupTimer, UDim.new(1, 0))
	popupTimer.Parent = track

	popupNotice = MenuStyle.Text(holder, "", UDim2.fromOffset(460, 24), UDim2.new())
	popupNotice.LayoutOrder = 2
	popupNotice.TextColor3 = NOTE_YELLOW
	popupNotice.Visible = false
end

local function build()
	-- Lobby: the CUSTOM button on the right, under the TUTORIAL's (same width, same screen fit)
	local gui = Instance.new("ScreenGui")
	gui.Name = "CustomMatchButton"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5 -- (with the lobby menu: the other menus' screens cover it)
	gui.Parent = player:WaitForChild("PlayerGui")
	buttonHolder = Instance.new("Frame")
	buttonHolder.Name = "CustomButton"
	buttonHolder.AnchorPoint = Vector2.new(1, 0)
	buttonHolder.Position = UDim2.new(1, -20, 0.5, 158)
	buttonHolder.Size = UDim2.fromOffset(170, 50)
	buttonHolder.BackgroundTransparency = 1
	buttonHolder.Visible = false
	buttonHolder.Parent = gui
	LobbyIntro.Animate(buttonHolder)
	MenuStyle.FitToScreen(buttonHolder, Vector2.new(900, 520))
	lobbyButton = MenuStyle.Button(buttonHolder, "Custom", CUSTOM_COLOR, UDim2.fromScale(1, 1), UDim2.new())
	lobbyButton.Activated:Connect(CustomMatchMenu.Open)

	buildScreen()
	buildPopup()
end

-- ─── Every frame ───────────────────────────────────────────────────────────────

local function update()
	local now = os.clock()
	local lobby = inLobbyMenu()
	if screenOpen and not lobby then
		CustomMatchMenu.Close() -- a match is starting
	end
	buttonHolder.Visible = LobbyIntro.Shown("Custom") and not screenOpen and not otherMenuOpen() and not player:GetAttribute("Queued")
	-- Under the TUTORIAL button while it's showing (a gap that shrinks with the screen fit), in its
	-- place once it's gone (finished the tutorial, or played a few matches)
	local scale = buttonHolder:FindFirstChildOfClass("UIScale")
	local below = if Tutorial.ButtonShown() then 50 * (if scale then scale.Scale else 1) + 12 else 0
	buttonHolder.Position = UDim2.new(1, -20, 0.5, 100 + below)
	;(lobbyButton:FindFirstChild("Label") :: TextLabel).Text = if view then `Lobby {view.Code}` else "Custom"

	if screenOpen then
		startPage.Visible = view == nil
		lobbyPage.Visible = view ~= nil
		if not view then
			inviteOpen = false
		end
		inviteOverlay.Visible = inviteOpen
		if inviteOpen then
			local key = inviteKey(now)
			if key ~= shownInvites then
				shownInvites = key
				rebuildInvites(now)
			end
		end
	end

	-- Invites: drop the ones that ran out or whose sender left; show the oldest
	for i = #invites, 1, -1 do
		if invites[i].ends <= now or not invites[i].from.Parent then
			table.remove(invites, i)
		end
	end
	local invite = invites[1]
	popup.Visible = lobby and invite ~= nil
	if invite then
		popupName.Text = invite.from.DisplayName
		popupFace.Image = headshot(invite.from.UserId)
		popupMore.Text = if #invites > 1 then `+{#invites - 1} MORE` else ""
		popupTimer.Size = UDim2.fromScale(math.clamp((invite.ends - now) / invite.total, 0, 1), 1)
	end
	local showing = now < noticeEnds
	screenNotice.Text = noticeText
	screenNotice.Visible = showing and screenOpen
	popupNotice.Text = noticeText
	popupNotice.Visible = showing and lobby and not screenOpen
end

function CustomMatchMenu.Open()
	if screenOpen or otherMenuOpen() then
		return
	end
	screenOpen = true
	screen.Visible = true
	rebuildLobby()
end

function CustomMatchMenu.Close()
	screenOpen = false
	inviteOpen = false
	if screen then
		screen.Visible = false
	end
end

local function onEvent(event: string, a: any, b: any, c: any)
	if event == "State" then
		local wasIn = view ~= nil
		view = if typeof(a) == "table" then a else nil
		if view then
			rebuildLobby()
			if not wasIn and inLobbyMenu() then
				CustomMatchMenu.Open() -- (just joined: show the lobby)
			end
		end
	elseif event == "Invite" and typeof(a) == "Instance" and a:IsA("Player") and typeof(b) == "string" and typeof(c) == "number" then
		-- (a new invite to the same lobby replaces the old one)
		for i, invite in invites do
			if invite.code == b then
				table.remove(invites, i)
				break
			end
		end
		table.insert(invites, { from = a, code = b, ends = os.clock() + c, total = c })
	elseif event == "Notice" and typeof(a) == "string" then
		showNotice(a)
	elseif event == "Starting" then
		if not RunService:IsStudio() then
			TeleportService:SetTeleportGui(LoadingScreen.Build(if a == true then "JOINING CUSTOM LOBBY..." else "LOADING CUSTOM MATCH..."))
		end
	end
end

function CustomMatchMenu.Start()
	build()
	RunService.RenderStepped:Connect(update)
	Players.PlayerRemoving:Connect(function(other)
		sent[other] = nil
	end)
	-- (the server makes the remote when it starts: don't hold up the other menus for it)
	task.spawn(function()
		local remote = Remotes:WaitForChild("CustomMatch") :: RemoteEvent
		Remote = remote
		remote.OnClientEvent:Connect(onEvent)
	end)
end

return CustomMatchMenu
