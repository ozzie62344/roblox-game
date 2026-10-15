-- The scoreboard: HOLD TAB (phones: the SCORE button, tap to show, tap it again or the board to
-- hide). In a match: both teams (yours on top, rounds won, ATTACK / DEFEND) with each player's
-- kills / deaths / assists this match and their ping, best first (kills, then fewer deaths); your
-- own row highlighted, the dead greyed, anyone sitting the match out underneath. In free roam
-- it's one list of everyone. Not in the lobby, under the menus or over the results screen.
-- It's only a picture: the cursor stays locked and the gun keeps working (on a keyboard it takes
-- no clicks; on a phone only the board takes taps, and MobileControls' buttons sit on top of it).
-- The numbers are player attributes the server's MatchStats keeps current: MatchKills /
-- MatchDeaths / MatchAssists (as they change) and Ping (ms, every couple of seconds). In a ranked
-- match each player's rank badge (RankBadge, from their Mmr / RankedMatches) sits by their name.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local MatchConfig = require(ReplicatedStorage.Shared.MatchConfig)
local Actions = require(script.Parent.Parent.Input.Actions)
local state = require(script.Parent.Parent.PlayerState)
local MenuStyle = require(script.Parent.MenuStyle)
local RankBadge = require(script.Parent.RankBadge)

local MatchState = ReplicatedStorage:WaitForChild("MatchState")

local player = Players.LocalPlayer

local Scoreboard = {}

local WIDTH = 600
local DESIGN = Vector2.new(WIDTH, 460) -- (FitToScreen shrinks it for phones)
local ROW_HEIGHT = 30
local REFRESH = 0.5 -- seconds between rebuilds while it's up
local CARD = Color3.fromRGB(36, 39, 48)
local YOU = Color3.fromRGB(62, 67, 82)
local GREY = Color3.fromRGB(175, 180, 192)
local DEAD = Color3.fromRGB(120, 124, 135)
local YELLOW = Color3.fromRGB(240, 210, 60)
-- Columns: header, x, width
local COLUMNS = { { "K", 310, 50 }, { "D", 370, 50 }, { "A", 430, 50 }, { "PING", 490, 76 } }

local gui: ScreenGui
local board: Frame
local content: Frame
local tapToClose: TextButton
local hint: TextLabel
local held = false -- Tab is down
local toggled = false -- opened with the SCORE button
local shown = false
local lastBuild = 0

-- Left-aligned or centered chunky text in a row
local function cell(parent: Instance, text: string, x: number, width: number, height: number, color: Color3?, left: boolean?): TextLabel
	local label = MenuStyle.Text(parent, text, UDim2.fromOffset(width, height), UDim2.new(0, x, 0.5, 0), Vector2.new(0, 0.5))
	label.TextXAlignment = if left then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center
	label.TextColor3 = color or Color3.new(1, 1, 1)
	return label
end

local function pingColor(ms: number): Color3
	return if ms <= 80 then MenuStyle.Green elseif ms <= 150 then YELLOW else MenuStyle.Red
end

local function stat(other: Player, attribute: string): number
	local value = other:GetAttribute(attribute)
	return if typeof(value) == "number" then value else 0
end

local function alive(other: Player): boolean
	local humanoid = other.Character and other.Character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

-- Most kills first, then fewest deaths, then by name
local function byScore(a: Player, b: Player): boolean
	local killsA, killsB = stat(a, "MatchKills"), stat(b, "MatchKills")
	if killsA ~= killsB then
		return killsA > killsB
	end
	local deathsA, deathsB = stat(a, "MatchDeaths"), stat(b, "MatchDeaths")
	if deathsA ~= deathsB then
		return deathsA < deathsB
	end
	return a.DisplayName < b.DisplayName
end

local function addRow(other: Player, order: number, inMatch: boolean)
	local row = Instance.new("Frame")
	row.LayoutOrder = order
	row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
	row.BackgroundColor3 = if other == player then YOU else CARD
	row.BackgroundTransparency = 0.1
	row.Parent = content
	MenuStyle.Corner(row, UDim.new(0, 6))
	if other == player then
		MenuStyle.Rim(row, Color3.new(1, 1, 1), 1.5).Transparency = 0.4
	end
	-- (a little bar in their team's colour down the left)
	local team = if other.Team then MatchConfig.Teams[other.Team.Name] else nil
	if team then
		local bar = Instance.new("Frame")
		bar.AnchorPoint = Vector2.new(0, 0.5)
		bar.Position = UDim2.new(0, 4, 0.5, 0)
		bar.Size = UDim2.new(0, 4, 1, -10)
		bar.BackgroundColor3 = team.Color.Color
		bar.BorderSizePixel = 0
		bar.Parent = row
		MenuStyle.Corner(bar, UDim.new(1, 0))
	end
	local dead = inMatch and team ~= nil and not alive(other)
	-- Ranked match: their rank badge at the end of the name column
	local ranked = inMatch and team ~= nil and MatchState:GetAttribute("Ranked") == true
	if ranked then
		RankBadge.ForPlayer(row, other, 26, UDim2.new(0, 282, 0.5, 0), Vector2.new(0.5, 0.5))
	end
	local tag = other:GetAttribute("ClanTag") -- ("[TAG] Name" for clan members: ClanService)
	local name = if typeof(tag) == "string" and tag ~= "" then `[{tag}] {other.DisplayName}` else other.DisplayName
	cell(row, name, 16, if ranked then 250 else 280, 20, if dead then DEAD else nil, true)
	for i, attribute in { "MatchKills", "MatchDeaths", "MatchAssists" } do
		local column = COLUMNS[i]
		local value = other:GetAttribute(attribute)
		cell(row, if typeof(value) == "number" then tostring(value) else "-", column[2], column[3], 18, if inMatch then nil else GREY)
	end
	local ping = other:GetAttribute("Ping")
	local pingColumn = COLUMNS[4]
	if typeof(ping) == "number" then
		cell(row, tostring(ping), pingColumn[2], pingColumn[3], 18, pingColor(ping))
	else
		cell(row, "-", pingColumn[2], pingColumn[3], 18, GREY)
	end
end

-- A coloured bar with the team's name (and side, rounds won), then its players
local function addTeam(name: string, members: { Player }, order: number): number
	local header = Instance.new("Frame")
	header.LayoutOrder = order
	header.Size = UDim2.new(1, 0, 0, 32)
	header.BackgroundColor3 = MatchConfig.Teams[name].Color.Color
	header.Parent = content
	MenuStyle.Corner(header, UDim.new(0, 8))
	local attackTeam = MatchState:GetAttribute("AttackTeam")
	local side = if attackTeam and MatchState:GetAttribute("GameMode") == "AttackDefend"
		then (if attackTeam == name then "  ·  ATTACK" else "  ·  DEFEND")
		else ""
	local yours = if player.Team and player.Team.Name == name then "  ·  YOUR TEAM" else ""
	cell(header, string.upper(name) .. side .. yours, 14, 420, 22, nil, true)
	cell(header, tostring(MatchState:GetAttribute("Score" .. name) or 0), COLUMNS[4][2], COLUMNS[4][3], 24)

	table.sort(members, byScore)
	for _, member in members do
		order += 1
		addRow(member, order, true)
	end
	return order
end

local function build()
	lastBuild = os.clock()
	for _, child in content:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	-- Who's on which team (players on neither are sitting the match out / in free roam)
	local byTeam: { [string]: { Player } } = {}
	local others: { Player } = {}
	local inMatch = false
	for _, other in Players:GetPlayers() do
		local team = if not other.Neutral and other.Team and MatchConfig.Teams[other.Team.Name] then other.Team.Name else nil
		if team then
			byTeam[team] = byTeam[team] or {}
			table.insert(byTeam[team], other)
			inMatch = true
		else
			table.insert(others, other)
		end
	end

	-- Title line: the round, or free roam
	local round = MatchState:GetAttribute("Round") or 0
	local title = Instance.new("Frame")
	title.LayoutOrder = 0
	title.Size = UDim2.new(1, 0, 0, 30)
	title.BackgroundTransparency = 1
	title.Parent = content
	local rankedTag = if inMatch and MatchState:GetAttribute("Ranked") == true then "RANKED · " else ""
	cell(title, if not inMatch then "FREE ROAM" elseif round > 0 then `{rankedTag}ROUND {round}` else `{rankedTag}MATCH`, 4, 300, 26, nil, true)
	local columns = Instance.new("Frame")
	columns.LayoutOrder = 1
	columns.Size = UDim2.new(1, 0, 0, 18)
	columns.BackgroundTransparency = 1
	columns.Parent = content
	cell(columns, "PLAYER", 16, 120, 15, GREY, true)
	for _, column in COLUMNS do
		cell(columns, column[1], column[2], column[3], 15, GREY)
	end

	local order = 10
	if inMatch then
		-- Your team on top
		local teamOrder = table.clone(MatchConfig.TeamOrder)
		if player.Team and player.Team.Name == teamOrder[2] then
			teamOrder[1], teamOrder[2] = teamOrder[2], teamOrder[1]
		end
		for _, name in teamOrder do
			order = addTeam(name, byTeam[name] or {}, order + 10)
		end
		if #others == 0 then
			return
		end
		local away = Instance.new("Frame")
		away.LayoutOrder = order + 10
		away.Size = UDim2.new(1, 0, 0, 24)
		away.BackgroundTransparency = 1
		away.Parent = content
		cell(away, "SPECTATING", 16, 200, 18, GREY, true)
		order += 10
	end
	table.sort(others, byScore)
	for _, other in others do
		order += 1
		addRow(other, order, false)
	end
end

local function allowed(): boolean
	return not (state.inLobby or state.resultsOpen or state.modsOpen or state.draftOpen or state.voteOpen or state.devPanelOpen)
end

local function update()
	local show = (held or toggled) and allowed()
	if show and (not shown or os.clock() - lastBuild >= REFRESH) then
		build()
	end
	shown = show
	gui.Enabled = show
	-- Only a board opened by tapping takes taps (to close it); held open with Tab it takes no clicks
	local tappable = show and toggled and not held
	tapToClose.Visible = tappable
	hint.Visible = tappable
	if tappable then
		tapToClose.Position = UDim2.fromOffset(board.AbsolutePosition.X, board.AbsolutePosition.Y)
		tapToClose.Size = UDim2.fromOffset(board.AbsoluteSize.X, board.AbsoluteSize.Y)
	end
end

-- The SCORE button (MobileControls)
function Scoreboard.Toggle()
	toggled = not toggled
end

function Scoreboard.IsOpen(): boolean
	return shown
end

-- Roblox's own player list also opens with Tab. SetCoreGuiEnabled can fail if called too early, so retry.
local function hideRobloxPlayerList()
	for _ = 1, 20 do
		if pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.PlayerList, false) then
			return
		end
		task.wait(0.5)
	end
end

function Scoreboard.Start()
	task.spawn(hideRobloxPlayerList)

	gui = Instance.new("ScreenGui")
	gui.Name = "Scoreboard"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 3 -- over the HUD, under the phone's buttons and the menus
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")

	board = Instance.new("Frame")
	board.AnchorPoint = Vector2.new(0.5, 0.5)
	board.Position = UDim2.fromScale(0.5, 0.48)
	board.Size = UDim2.fromOffset(WIDTH, 0)
	board.AutomaticSize = Enum.AutomaticSize.Y
	board.BackgroundColor3 = MenuStyle.Panel
	board.BackgroundTransparency = 0.15
	board.Parent = gui
	MenuStyle.Corner(board, UDim.new(0, 14))
	MenuStyle.Rim(board, Color3.fromRGB(60, 64, 76), 2)
	MenuStyle.FitToScreen(board, DESIGN)
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 12)
	padding.PaddingBottom = UDim.new(0, 12)
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = board
	local stack = Instance.new("UIListLayout")
	stack.SortOrder = Enum.SortOrder.LayoutOrder
	stack.Padding = UDim.new(0, 6)
	stack.Parent = board

	content = Instance.new("Frame")
	content.LayoutOrder = 1
	content.Size = UDim2.fromScale(1, 0)
	content.AutomaticSize = Enum.AutomaticSize.Y
	content.BackgroundTransparency = 1
	content.Parent = board
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 4)
	list.Parent = content

	hint = MenuStyle.Text(board, "TAP TO CLOSE", UDim2.new(1, 0, 0, 16), UDim2.new())
	hint.LayoutOrder = 2
	hint.TextColor3 = GREY
	hint.Visible = false

	-- Kept over the board (outside its list, see update): a tap anywhere on it closes it
	tapToClose = Instance.new("TextButton")
	tapToClose.BackgroundTransparency = 1
	tapToClose.Text = ""
	tapToClose.ZIndex = 5
	tapToClose.Visible = false
	tapToClose.Parent = gui
	tapToClose.Activated:Connect(function()
		toggled = false
	end)

	Actions.Bind("Scoreboard", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			held = true
		elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
			held = false
		end
		return Enum.ContextActionResult.Pass
	end, Enum.KeyCode.Tab)
	-- (alt-tabbing away while holding Tab: its release never comes)
	UserInputService.WindowFocusReleased:Connect(function()
		held = false
	end)

	RunService.Heartbeat:Connect(update)
end

return Scoreboard
