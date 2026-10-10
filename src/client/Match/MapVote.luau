-- The map vote before a match (server RoundService.voteMap): one card per map with its vote count.
-- Click one to vote (click another to change). When the timer runs out the winner lights up gold.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local MenuStyle = require(script.Parent.MenuStyle)
local state = require(script.Parent.Parent.PlayerState)

local MatchState = ReplicatedStorage:WaitForChild("MatchState")
local VoteMap = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("VoteMap") :: RemoteEvent

local player = Players.LocalPlayer

local MapVote = {}

-- Card colors per map (dark → light); anything else gets the last one
local ART = {
	House = { Color3.fromRGB(120, 60, 30), Color3.fromRGB(235, 160, 70) },
	TestArena = { Color3.fromRGB(40, 50, 70), Color3.fromRGB(120, 150, 190) },
	Other = { Color3.fromRGB(40, 70, 50), Color3.fromRGB(110, 190, 120) },
}

local gui: ScreenGui
local title: TextLabel
local timer: TextLabel
local row: Frame
local cards: { [string]: TextButton } = {}
local shownMaps = ""

local function displayName(name: string): string
	return string.upper((string.gsub(name, "(%l)(%u)", "%1 %2"))) -- "TestArena" → "TEST ARENA"
end

local function mapCard(name: string, order: number): TextButton
	local card = Instance.new("TextButton")
	card.Name = name
	card.LayoutOrder = order
	card.Size = UDim2.fromOffset(300, 240)
	card.AutoButtonColor = false
	card.Text = ""
	card.BackgroundColor3 = Color3.new(1, 1, 1)
	MenuStyle.Corner(card, UDim.new(0, 14))
	MenuStyle.Rim(card, Color3.new(1, 1, 1), 2).Name = "Rim"
	local colors = ART[name] or ART.Other
	local art = Instance.new("UIGradient")
	art.Color = ColorSequence.new(colors[1], colors[2])
	art.Rotation = -60
	art.Parent = card
	local scale = Instance.new("UIScale")
	scale.Parent = card

	MenuStyle.Text(card, displayName(name), UDim2.new(0.9, 0, 0, 52), UDim2.fromScale(0.5, 0.36), Vector2.new(0.5, 0.5))
	local strip = Instance.new("Frame")
	strip.AnchorPoint = Vector2.new(0, 1)
	strip.Position = UDim2.fromScale(0, 1)
	strip.Size = UDim2.new(1, 0, 0, 56)
	strip.BackgroundColor3 = Color3.new(0, 0, 0)
	strip.BackgroundTransparency = 0.3
	strip.Parent = card
	MenuStyle.Text(strip, "", UDim2.new(0.6, 0, 0, 34), UDim2.fromScale(0.42, 0.5), Vector2.new(0.5, 0.5)).Name = "Votes"
	MenuStyle.Check(strip, UDim2.fromScale(0.85, 0.5))

	card.Activated:Connect(function()
		VoteMap:FireServer(name)
	end)
	return card
end

local function rebuild(maps: string)
	for _, card in cards do
		card:Destroy()
	end
	table.clear(cards)
	local order = 0
	for name in string.gmatch(maps, "[^,]+") do
		order += 1
		cards[name] = mapCard(name, order)
		cards[name].Parent = row
	end
end

local function update()
	local open = MatchState:GetAttribute("Phase") == "Vote"
	state.voteOpen = open
	gui.Enabled = open
	if not open then
		return
	end
	local maps = MatchState:GetAttribute("VoteMaps") or ""
	if maps ~= shownMaps then
		shownMaps = maps
		rebuild(maps)
	end

	local counts = {}
	for _, other in Players:GetPlayers() do
		local vote = other:GetAttribute("MapVote")
		if vote then
			counts[vote] = (counts[vote] or 0) + 1
		end
	end
	local winner = MatchState:GetAttribute("VoteWinner")
	local mine = player:GetAttribute("MapVote")
	for name, card in cards do
		local count = counts[name] or 0
		local rim = card:FindFirstChild("Rim") :: UIStroke
		local isWinner = name == winner
		rim.Color = if isWinner then MenuStyle.Gold elseif name == mine then MenuStyle.Green else Color3.new(1, 1, 1)
		rim.Thickness = if isWinner or name == mine then 5 else 2
		rim.Transparency = if isWinner or name == mine then 0 else 0.5
		;(card:FindFirstChild("Votes", true) :: TextLabel).Text = if count == 1 then "1 VOTE" else `{count} VOTES`
		;(card:FindFirstChild("Check", true) :: Frame).Visible = name == mine
		local scale = card:FindFirstChildOfClass("UIScale") :: UIScale
		scale.Scale += ((if isWinner then 1.1 elseif winner then 0.92 else 1) - scale.Scale) * 0.2
	end
	title.Text = if winner then `{displayName(winner)} WINS!` else "Vote for the map"
	local left = math.max(0, math.ceil((MatchState:GetAttribute("PhaseEndsAt") or 0) - Workspace:GetServerTimeNow()))
	timer.Text = if winner then "STARTING..." else `{left}`
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
	content.Size = UDim2.fromOffset(980, 440)
	content.BackgroundTransparency = 1
	content.Parent = shade
	MenuStyle.FitToScreen(content, Vector2.new(980, 440))
	title = MenuStyle.Text(content, "", UDim2.new(1, 0, 0, 70), UDim2.fromScale(0.5, 0), Vector2.new(0.5, 0))
	timer = MenuStyle.Text(content, "", UDim2.new(0, 300, 0, 40), UDim2.new(0.5, 0, 0, 76), Vector2.new(0.5, 0))
	timer.TextColor3 = MenuStyle.Gold

	row = Instance.new("Frame")
	row.Position = UDim2.fromOffset(0, 150)
	row.Size = UDim2.new(1, 0, 0, 260)
	row.BackgroundTransparency = 1
	row.Parent = content
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 30)
	layout.Parent = row

	RunService.RenderStepped:Connect(update)
end

return MapVote
