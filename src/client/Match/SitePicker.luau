-- Defenders pick which site pair to defend during the pre-round freeze (Attack / Defend, on maps
-- with site pairs): a row of buttons under the top bar. Clicking one moves the whole team there
-- (RoundService); the last pick counts. The cursor is free while the loadout cards are open;
-- otherwise Left Alt frees it. Attackers find out where when the round goes live.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local MatchState = ReplicatedStorage:WaitForChild("MatchState")
local PickSite = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("PickSite") :: RemoteEvent

local player = Players.LocalPlayer

local SitePicker = {}

local BUTTON_COLOR = Color3.fromRGB(28, 30, 36)
local PICKED_COLOR = Color3.fromRGB(50, 110, 220)

local bar: Frame
local row: Frame
local buttons: { [string]: TextButton } = {}
local builtFrom = -1 -- how many sites the buttons were made from

local function shouldShow(): boolean
	local attackTeam = MatchState:GetAttribute("AttackTeam")
	return MatchState:GetAttribute("Phase") == "PreRound"
		and MatchState:GetAttribute("GameMode") == "AttackDefend"
		and attackTeam ~= nil
		and player.Team ~= nil
		and player.Team.Name ~= attackTeam
end

-- Pair → its rooms in site order ("Gym · Workshop"), read from the map's sites
local function getPairs(): { [string]: string }
	local map = Workspace:FindFirstChild("Map")
	local objectives = map and map:FindFirstChild("Objectives")
	local sites: { [string]: { BasePart } } = {}
	for _, site in if objectives then objectives:GetChildren() else {} do
		local pair = site:GetAttribute("Pair")
		if pair then
			sites[pair] = sites[pair] or {}
			table.insert(sites[pair], site)
		end
	end
	local rooms = {}
	for pair, list in sites do
		table.sort(list, function(a, b)
			return (a:GetAttribute("Site") or "") < (b:GetAttribute("Site") or "")
		end)
		local names = {}
		for _, site in list do
			table.insert(names, site:GetAttribute("Room") or site:GetAttribute("Site"))
		end
		rooms[pair] = table.concat(names, " · ")
	end
	return rooms
end

local function clearButtons()
	for _, button in buttons do
		button:Destroy()
	end
	table.clear(buttons)
end

local function makeButtons()
	local rooms = getPairs()
	local names = {}
	for pair in rooms do
		table.insert(names, pair)
	end
	table.sort(names)
	for i, pair in names do
		local button = Instance.new("TextButton")
		button.Size = UDim2.fromOffset(170, 50)
		button.LayoutOrder = i
		button.BackgroundColor3 = BUTTON_COLOR
		button.BackgroundTransparency = 0.15
		button.Font = Enum.Font.GothamBold
		button.TextSize = 15
		button.TextColor3 = Color3.new(1, 1, 1)
		button.RichText = true
		button.Text = `{string.upper(pair)}\n<font size="12" color="#AAB0BC">{rooms[pair]}</font>`
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = button
		button.Activated:Connect(function()
			PickSite:FireServer(pair)
		end)
		button.Parent = row
		buttons[pair] = button
	end
end

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "SitePicker"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 6
	gui.Parent = player:WaitForChild("PlayerGui")

	bar = Instance.new("Frame")
	bar.AnchorPoint = Vector2.new(0.5, 0)
	bar.Position = UDim2.new(0.5, 0, 0, 116)
	bar.Size = UDim2.fromOffset(760, 84)
	bar.BackgroundTransparency = 1
	bar.Visible = false
	bar.Parent = gui

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 24)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 16
	title.TextColor3 = Color3.fromRGB(120, 175, 255)
	title.TextStrokeTransparency = 0.5
	title.Text = "PICK A SITE TO DEFEND  ·  CLICK  (LEFT ALT FREES THE MOUSE)"
	title.Parent = bar

	row = Instance.new("Frame")
	row.Position = UDim2.fromOffset(0, 30)
	row.Size = UDim2.new(1, 0, 0, 50)
	row.BackgroundTransparency = 1
	row.Parent = bar
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 10)
	layout.Parent = row
end

local function update()
	if not shouldShow() then
		if bar.Visible then
			bar.Visible = false
			clearButtons() -- the next round may be on a fresh map
			builtFrom = -1
		end
		return
	end
	-- The map streams in (StreamingEnabled): far-off sites arrive a few seconds after the phase
	-- changes, so remake the buttons whenever more of them show up
	local map = Workspace:FindFirstChild("Map")
	local objectives = map and map:FindFirstChild("Objectives")
	local siteCount = if objectives then #objectives:GetChildren() else 0
	if siteCount ~= builtFrom then
		clearButtons()
		makeButtons()
		builtFrom = siteCount
	end
	bar.Visible = next(buttons) ~= nil
	local picked = MatchState:GetAttribute("SitePair")
	for pair, button in buttons do
		button.BackgroundColor3 = if pair == picked then PICKED_COLOR else BUTTON_COLOR
	end
end

function SitePicker.Start()
	build()
	RunService.RenderStepped:Connect(update)
end

return SitePicker
