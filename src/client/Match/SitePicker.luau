-- Defenders pick which site pair to defend during the pre-round freeze (Attack / Defend, on maps
-- with site pairs). Clicking one moves the whole team there (RoundService); the last pick counts.
-- Attackers pick their spawn point instead ("Front Street / Back Alley / Side Drive", MatchState
-- "AttackSpawns"): each picks their own and is moved there right away.
-- The operator select screen (LoadoutPicker) shows these choices in its own panel, through
-- SitePicker.Current / SitePicker.Choose. While that screen is hidden (Left Alt / HIDE) the same
-- choices sit in a row of buttons under the top bar instead; Left Alt frees the mouse for them.
-- Attackers find out where the defenders are when the round goes live.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local state = require(script.Parent.Parent.PlayerState)

local MatchState = ReplicatedStorage:WaitForChild("MatchState")
local PickSite = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("PickSite") :: RemoteEvent

local player = Players.LocalPlayer

local SitePicker = {}

-- What you can pick right now: Kind "Site" (defenders, for the team) or "Spawn" (attackers, for
-- yourself); Options in button order (Detail: the pair's rooms); Picked: the current pick; Key
-- changes whenever the options do (the map streams in), so a UI knows to remake its buttons
export type Option = { Id: string, Detail: string? }
export type Choice = { Kind: string, Options: { Option }, Picked: string?, Key: string }

local BUTTON_COLOR = Color3.fromRGB(28, 30, 36)
local PICKED_COLOR = Color3.fromRGB(50, 110, 220)

local bar: Frame
local row: Frame
local title: TextLabel
local buttons: { [string]: TextButton } = {}
local current: Choice? = nil
local builtFrom = "" -- the Key the bar's buttons were made from

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

local function makeOptions(kind: string): { Option }
	local options = {}
	if kind == "Spawn" then
		for _, name in string.split(MatchState:GetAttribute("AttackSpawns") or "", ",") do
			if name ~= "" then
				table.insert(options, { Id = name })
			end
		end
	else
		for pair, rooms in getPairs() do
			table.insert(options, { Id = pair, Detail = rooms })
		end
	end
	table.sort(options, function(a, b)
		return a.Id < b.Id
	end)
	return options
end

-- What there is to pick right now (nil: nothing)
function SitePicker.Current(): Choice?
	return current
end

-- Pick `id` from the current choice
function SitePicker.Choose(id: string)
	local choice = current
	if not choice then
		return
	end
	if choice.Kind == "Spawn" then
		PickSite:FireServer(id, "Spawn")
	else
		PickSite:FireServer(id)
	end
end

local function clearButtons()
	for _, button in buttons do
		button:Destroy()
	end
	table.clear(buttons)
end

local function makeButtons(choice: Choice)
	for i, option in choice.Options do
		local button = Instance.new("TextButton")
		button.Size = UDim2.fromOffset(170, 50)
		button.LayoutOrder = i
		button.BackgroundColor3 = BUTTON_COLOR
		button.BackgroundTransparency = 0.15
		button.Font = Enum.Font.GothamBold
		button.TextSize = 15
		button.TextColor3 = Color3.new(1, 1, 1)
		button.RichText = true
		button.Text = if option.Detail then `{string.upper(option.Id)}\n<font size="12" color="#AAB0BC">{option.Detail}</font>` else string.upper(option.Id)
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = button
		button.Activated:Connect(function()
			SitePicker.Choose(option.Id)
		end)
		button.Parent = row
		buttons[option.Id] = button
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
		if current then
			current = nil
			bar.Visible = false
			clearButtons() -- the next round may be on a fresh map
			builtFrom = ""
		end
		return
	end
	-- The map streams in (StreamingEnabled): far-off sites arrive a few seconds after the phase
	-- changes, so remake the options whenever more of them show up
	local key: string
	if kind == "Spawn" then
		key = "Spawn:" .. MatchState:GetAttribute("AttackSpawns")
	else
		local map = Workspace:FindFirstChild("Map")
		local objectives = map and map:FindFirstChild("Objectives")
		key = "Site:" .. (if objectives then #objectives:GetChildren() else 0)
	end
	if not current or current.Key ~= key then
		current = { Kind = kind, Options = makeOptions(kind), Picked = nil, Key = key }
	end
	local choice = current :: Choice
	local picked = if kind == "Spawn" then player:GetAttribute("SpawnPick") else MatchState:GetAttribute("SitePair")
	choice.Picked = if typeof(picked) == "string" then picked else nil

	-- The operator select screen shows the same choices while it's open: no second copy
	if state.draftOpen or #choice.Options == 0 then
		bar.Visible = false
		return
	end
	if builtFrom ~= key then
		clearButtons()
		makeButtons(choice)
		builtFrom = key
		local how = if state.touchControls then "TAP ONE" else "CLICK  (LEFT ALT FREES THE MOUSE)"
		title.Text = if kind == "Spawn" then `PICK YOUR SPAWN  ·  {how}` else `PICK A SITE TO DEFEND  ·  {how}`
		title.TextColor3 = if kind == "Spawn" then Color3.fromRGB(255, 150, 110) else Color3.fromRGB(120, 175, 255)
	end
	bar.Visible = true
	for id, button in buttons do
		button.BackgroundColor3 = if id == choice.Picked then PICKED_COLOR else BUTTON_COLOR
	end
end

function SitePicker.Start()
	build()
	RunService.RenderStepped:Connect(update)
end

return SitePicker
