-- The vote before a match (server RoundService.voteMap): a card per map on top, a card per mode
-- (GameRules: Classic, Snipers Only, Knives Only...) below, each with its vote count. Click one of
-- each to vote (click another to change). When the timer runs out the winners light up gold.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local GameRules = require(ReplicatedStorage.Shared.GameRules)
local MenuStyle = require(script.Parent.MenuStyle)
local state = require(script.Parent.Parent.PlayerState)

local MatchState = ReplicatedStorage:WaitForChild("MatchState")
local VoteMap = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("VoteMap") :: RemoteEvent

local player = Players.LocalPlayer

local MapVote = {}

-- Card colors per map (dark → light); anything else gets the last one
local ART = {
	House = { Color3.fromRGB(120, 60, 30), Color3.fromRGB(235, 160, 70) },
	Warehouse = { Color3.fromRGB(45, 60, 80), Color3.fromRGB(230, 170, 40) },
	Chalet = { Color3.fromRGB(35, 65, 90), Color3.fromRGB(170, 205, 230) },
	Bank = { Color3.fromRGB(32, 64, 56), Color3.fromRGB(214, 180, 96) },
	TestArena = { Color3.fromRGB(40, 50, 70), Color3.fromRGB(120, 150, 190) },
	Other = { Color3.fromRGB(40, 70, 50), Color3.fromRGB(110, 190, 120) },
}

-- One row of cards (maps, or modes) and what it votes on
type Row = {
	frame: Frame,
	cards: { [string]: TextButton },
	shown: string, -- the option list the cards were built for
	listAttribute: string, -- MatchState: the options ("House,Warehouse")
	voteAttribute: string, -- player: what they voted for
	winnerAttribute: string, -- MatchState: the result
}

local gui: ScreenGui
local title: TextLabel
local timer: TextLabel
local maps: Row
local modes: Row

local function displayName(name: string): string
	local spaced = string.gsub(string.gsub(name, "(%l)(%u)", "%1 %2"), "(%a)(%d)", "%1 %2")
	return string.upper(spaced) -- "TestArena" → "TEST ARENA", "Flight9" → "FLIGHT 9"
end

-- A card with a two-color gradient, a big name, an optional line under it and a votes strip
local function card(name: string, order: number, size: Vector2, colors: { Color3 }, heading: string, subtitle: string?, onVote: () -> ()): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.LayoutOrder = order
	button.Size = UDim2.fromOffset(size.X, size.Y)
	button.AutoButtonColor = false
	button.Text = ""
	button.BackgroundColor3 = Color3.new(1, 1, 1)
	MenuStyle.Corner(button, UDim.new(0, 14))
	MenuStyle.Rim(button, Color3.new(1, 1, 1), 2).Name = "Rim"
	local art = Instance.new("UIGradient")
	art.Color = ColorSequence.new(colors[1], colors[2])
	art.Rotation = -60
	art.Parent = button
	local scale = Instance.new("UIScale")
	scale.Parent = button

	local strip = 44
	local headingLabel = MenuStyle.Text(button, heading, UDim2.new(0.9, 0, 0, if subtitle then 30 else 46), UDim2.new(0.5, 0, 0.5, -strip / 2 - (if subtitle then 10 else 0)), Vector2.new(0.5, 0.5))
	headingLabel.Name = "Heading"
	if subtitle then
		local line = MenuStyle.Text(button, subtitle, UDim2.new(0.9, 0, 0, 14), UDim2.new(0.5, 0, 0.5, -strip / 2 + 16), Vector2.new(0.5, 0.5))
		;(line:FindFirstChildOfClass("UIStroke") :: UIStroke).Thickness = 1.5
	end
	local bar = Instance.new("Frame")
	bar.AnchorPoint = Vector2.new(0, 1)
	bar.Position = UDim2.fromScale(0, 1)
	bar.Size = UDim2.new(1, 0, 0, strip)
	bar.BackgroundColor3 = Color3.new(0, 0, 0)
	bar.BackgroundTransparency = 0.3
	bar.Parent = button
	MenuStyle.Text(bar, "", UDim2.new(0.6, 0, 0, 26), UDim2.fromScale(0.42, 0.5), Vector2.new(0.5, 0.5)).Name = "Votes"
	local check = MenuStyle.Check(bar, UDim2.fromScale(0.85, 0.5))
	check.Size = UDim2.fromOffset(28, 28)

	button.Activated:Connect(onVote)
	return button
end

local function rebuild(row: Row, list: string)
	for _, existing in row.cards do
		existing:Destroy()
	end
	table.clear(row.cards)
	local order = 0
	for name in string.gmatch(list, "[^,]+") do
		order += 1
		local made
		if row == maps then
			made = card(name, order, Vector2.new(280, 160), ART[name] or ART.Other, displayName(name), nil, function()
				VoteMap:FireServer(name)
			end)
		else
			local rules = GameRules.ById[name]
			if not rules then
				continue
			end
			made = card(name, order, Vector2.new(150, 140), rules.Colors, string.upper(rules.Name), rules.Description, function()
				VoteMap:FireServer(name, "Rules")
			end)
		end
		row.cards[name] = made
		made.Parent = row.frame
	end
end

-- Vote counts, my pick, the winner
local function refresh(row: Row)
	local list = MatchState:GetAttribute(row.listAttribute) or ""
	if list ~= row.shown then
		row.shown = list
		rebuild(row, list)
	end
	local counts = {}
	for _, other in Players:GetPlayers() do
		local vote = other:GetAttribute(row.voteAttribute)
		if vote then
			counts[vote] = (counts[vote] or 0) + 1
		end
	end
	local winner = MatchState:GetAttribute(row.winnerAttribute)
	local mine = player:GetAttribute(row.voteAttribute)
	for name, button in row.cards do
		local count = counts[name] or 0
		local rim = button:FindFirstChild("Rim") :: UIStroke
		local isWinner = name == winner
		rim.Color = if isWinner then MenuStyle.Gold elseif name == mine then MenuStyle.Green else Color3.new(1, 1, 1)
		rim.Thickness = if isWinner or name == mine then 5 else 2
		rim.Transparency = if isWinner or name == mine then 0 else 0.5
		;(button:FindFirstChild("Votes", true) :: TextLabel).Text = if count == 1 then "1 VOTE" else `{count} VOTES`
		;(button:FindFirstChild("Check", true) :: Frame).Visible = name == mine
		local scale = button:FindFirstChildOfClass("UIScale") :: UIScale
		scale.Scale += ((if isWinner then 1.08 elseif winner then 0.92 else 1) - scale.Scale) * 0.2
	end
end

local function update()
	local open = MatchState:GetAttribute("Phase") == "Vote"
	state.voteOpen = open
	gui.Enabled = open
	if not open then
		return
	end
	refresh(maps)
	refresh(modes)

	local winner = MatchState:GetAttribute("VoteWinner")
	local rules = GameRules.ById[MatchState:GetAttribute("RulesWinner") or ""]
	title.Text = if winner and rules then `{displayName(winner)} · {string.upper(rules.Name)}!` else "Vote for the map and mode"
	local left = math.max(0, math.ceil((MatchState:GetAttribute("PhaseEndsAt") or 0) - Workspace:GetServerTimeNow()))
	timer.Text = if winner then "STARTING..." else `{left}`
end

local function row(parent: Frame, y: number, height: number, padding: number, heading: string, listAttribute: string, voteAttribute: string, winnerAttribute: string): Row
	local label = MenuStyle.Text(parent, heading, UDim2.fromOffset(200, 24), UDim2.new(0.5, 0, 0, y - 30), Vector2.new(0.5, 0))
	label.TextColor3 = Color3.fromRGB(200, 205, 215)
	local frame = Instance.new("Frame")
	frame.Position = UDim2.fromOffset(0, y)
	frame.Size = UDim2.new(1, 0, 0, height)
	frame.BackgroundTransparency = 1
	frame.Parent = parent
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, padding)
	layout.Parent = frame
	return {
		frame = frame,
		cards = {},
		shown = "",
		listAttribute = listAttribute,
		voteAttribute = voteAttribute,
		winnerAttribute = winnerAttribute,
	}
end

function MapVote.Start()
	gui = Instance.new("ScreenGui")
	gui.Name = "MapVote"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 6
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local shade = Instance.new("Frame")
	shade.Size = UDim2.fromScale(1, 1)
	shade.BackgroundColor3 = Color3.new(0, 0, 0)
	shade.BackgroundTransparency = 0.35
	shade.Active = true
	shade.Parent = gui
	local content = Instance.new("Frame")
	content.AnchorPoint = Vector2.new(0.5, 0.5)
	content.Position = UDim2.fromScale(0.5, 0.5)
	content.Size = UDim2.fromOffset(980, 560)
	content.BackgroundTransparency = 1
	content.Parent = shade
	MenuStyle.FitToScreen(content, Vector2.new(980, 560))
	title = MenuStyle.Text(content, "", UDim2.new(1, 0, 0, 60), UDim2.fromScale(0.5, 0), Vector2.new(0.5, 0))
	timer = MenuStyle.Text(content, "", UDim2.new(0, 300, 0, 36), UDim2.new(0.5, 0, 0, 64), Vector2.new(0.5, 0))
	timer.TextColor3 = MenuStyle.Gold

	maps = row(content, 150, 170, 30, "MAP", "VoteMaps", "MapVote", "VoteWinner")
	modes = row(content, 384, 150, 12, "MODE", "VoteRules", "RulesVote", "RulesWinner")

	RunService.RenderStepped:Connect(update)
end

return MapVote
