-- Defenders pick which site pair to defend during the pre-round freeze (Attack / Defend, on maps
-- with site pairs): a row of buttons under the top bar. Clicking one moves the whole team there
-- (RoundService); the last pick counts. The cursor is free while the loadout cards are open;
-- otherwise Left Alt frees it. Attackers find out where when the round goes live.
-- Attackers get the same row for their spawn point instead ("SPAWN: Front Street / Back Alley /
-- Side Drive", MatchState "AttackSpawns"): each picks their own and is moved there right away.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local state = require(script.Parent.Parent.PlayerState)

local MatchState = ReplicatedStorage:WaitForChild("MatchState")
local PickSite = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("PickSite") :: RemoteEvent

local player = Players.LocalPlayer

local SitePicker = {}

local BUTTON_COLOR = Color3.fromRGB(28, 30, 36)
local PICKED_COLOR = Color3.fromRGB(50, 110, 220)

local bar: Frame
local row: Frame
local title: TextLabel
local buttons: { [string]: TextButton } = {}
local builtFrom: any = -1 -- what the buttons were made from (site count, or the spawn list)

-- "Site" (defenders), "Spawn" (attackers) or nil (nothing to pick right now)
local function shouldShow(): string?
	local attackTeam = MatchState:GetAttribute("AttackTeam")
	if MatchState:GetAttribute("Phase") ~= "PreRound" or attackTeam == nil or player.Team == nil then
		return nil
	end
	if player.Team.Name == attackTeam then
		return if MatchState:GetAttribute("AttackSpawns") then "Spawn" else nil
	end
	return if MatchState:GetAttribute("GameMode") == "AttackDefend" then "Site" else nil
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

local function makeButtons(kind: string)
	local rooms = if kind == "Site" then getPairs() else {}
	local names = {}
	if kind == "Spawn" then
		names = string.split(MatchState:GetAttribute("AttackSpawns") or "", ",")
	else
		for pair in rooms do
			table.insert(names, pair)
		end
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
		button.Text = if kind == "Spawn" then string.upper(pair)
			else `{string.upper(pair)}\n<font size="12" color="#AAB0BC">{rooms[pair]}</font>`
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = button
		button.Activated:Connect(function()
			if kind == "Spawn" then
				PickSite:FireServer(pair, "Spawn")
			else
				PickSite:FireServer(pair)
			end
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

	title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 24)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 16
	title.TextColor3 = Color3.fromRGB(120, 175, 255)
	title.TextStrokeTransparency = 0.5
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
	local kind = shouldShow()
	if not kind then
		if bar.Visible or builtFrom ~= -1 then
			bar.Visible = false
			clearButtons() -- the next round may be on a fresh map
			builtFrom = -1
		end
		return
	end
	-- The map streams in (StreamingEnabled): far-off sites arrive a few seconds after the phase
	-- changes, so remake the buttons whenever more of them show up
	local source: any
	if kind == "Spawn" then
		source = "Spawn:" .. MatchState:GetAttribute("AttackSpawns")
	else
		local map = Workspace:FindFirstChild("Map")
		local objectives = map and map:FindFirstChild("Objectives")
		source = if objectives then #objectives:GetChildren() else 0
	end
	if source ~= builtFrom then
		clearButtons()
		makeButtons(kind)
		builtFrom = source
		local how = if state.touchControls then "TAP ONE" else "CLICK  (LEFT ALT FREES THE MOUSE)"
		title.Text = if kind == "Spawn" then `PICK YOUR SPAWN  ·  {how}` else `PICK A SITE TO DEFEND  ·  {how}`
		title.TextColor3 = if kind == "Spawn" then Color3.fromRGB(255, 150, 110) else Color3.fromRGB(120, 175, 255)
	end
	bar.Visible = next(buttons) ~= nil
	local picked = if kind == "Spawn" then player:GetAttribute("SpawnPick") else MatchState:GetAttribute("SitePair")
	for pair, button in buttons do
		button.BackgroundColor3 = if pair == picked then PICKED_COLOR else BUTTON_COLOR
	end
end

function SitePicker.Start()
	build()
	RunService.RenderStepped:Connect(update)
end

return SitePicker
