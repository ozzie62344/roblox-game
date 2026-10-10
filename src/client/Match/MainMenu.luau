-- The lobby menu (lobby servers, while you're in the lobby):
--   PLAY NOW → the MODES screen: tick any of 1v1 / 2v2 / 3v3 / 4v4, START queues you for all of
--   them (server Matchmaker). The queue panel (bottom right) shows the fullest of your queues:
--   everyone's faces, Team 1 Vs Team 2, and LEAVE. When it fills: MATCH FOUND → loading screen
--   → teleported into the match (where MapVote takes over).

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local LoadingScreen = require(ReplicatedFirst:WaitForChild("LoadingScreen"))
local MatchConfig = require(ReplicatedStorage.Shared.MatchConfig)
local MenuStyle = require(script.Parent.MenuStyle)

local MatchState = ReplicatedStorage:WaitForChild("MatchState")
local Queue = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Queue") :: RemoteEvent

local player = Players.LocalPlayer

local MainMenu = {}

local selected: { [string]: boolean } = {}
local modesOpen = false
local found: { mode: string, ids: { number }, at: number }? = nil -- the match we're being sent to
local notice = ""

local gui: ScreenGui
local playHolder: Frame
local modesScreen: Frame
local modesTitle: TextLabel
local startButton: TextButton
local cards: { [string]: TextButton } = {}
local queuePanel: Frame
local queueTitle: TextLabel
local slotRow: Frame
local countLabel: TextLabel
local statusLabel: TextLabel
local leaveButton: TextButton
local noticeLabel: TextLabel
local shownSlots = "" -- what the slot row was last built for

local function teamSize(mode: string): number
	return tonumber(string.match(mode, "^(%d+)v")) :: number
end

local function selectedModes(): { string }
	local list = {}
	for _, mode in MatchConfig.QueueModes do
		if selected[mode] then
			table.insert(list, mode)
		end
	end
	return list
end

local function queuedIds(mode: string): { number }
	local ids = {}
	for id in string.gmatch(MatchState:GetAttribute("Queue" .. mode) or "", "%-?%d+") do
		table.insert(ids, tonumber(id) :: number)
	end
	return ids
end

local function refreshCards()
	for mode, card in cards do
		local on = selected[mode] == true
		local rim = card:FindFirstChild("Rim") :: UIStroke
		rim.Color = if on then MenuStyle.Green else Color3.new(1, 1, 1)
		rim.Thickness = if on then 5 else 2
		rim.Transparency = if on then 0 else 0.5
		;(card:FindFirstChild("Tint") :: Frame).Visible = on
		;(card:FindFirstChild("Check", true) :: Frame).Visible = on
	end
	local list = selectedModes()
	modesTitle.Text = if #list > 0 then "Modes: " .. table.concat(list, ", ") else "Pick a mode"
	MenuStyle.SetButtonColor(startButton, if #list > 0 then MenuStyle.Green else MenuStyle.Grey)
end

-- Red team on the left, blue on the right, on a red → blue card, mode name along the bottom
local function modeCard(mode: string, order: number): TextButton
	local size = teamSize(mode)
	local card = Instance.new("TextButton")
	card.Name = mode
	card.LayoutOrder = order
	card.Size = UDim2.fromOffset(220, 320)
	card.AutoButtonColor = false
	card.Text = ""
	card.BackgroundColor3 = Color3.new(1, 1, 1)
	card.ClipsDescendants = true
	MenuStyle.Corner(card, UDim.new(0, 14))
	MenuStyle.Rim(card, Color3.new(1, 1, 1), 2).Name = "Rim"
	local art = Instance.new("UIGradient")
	art.Color = ColorSequence.new(MenuStyle.Red, MenuStyle.Blue)
	art.Rotation = 20
	art.Parent = card

	-- Picked: a green glow from the bottom (behind the art)
	local tint = Instance.new("Frame")
	tint.Name = "Tint"
	tint.Size = UDim2.fromScale(1, 1)
	tint.BackgroundColor3 = MenuStyle.Green
	tint.Parent = card
	local fade = Instance.new("UIGradient")
	fade.Rotation = 90
	fade.Transparency = NumberSequence.new(1, 0.35)
	fade.Parent = tint

	-- Back row (every second person) first so the front row is drawn over it
	for row = 1, 0, -1 do
		for i = 1, size do
			if (i + 1) % 2 == row then
				local spread = (i - (size + 1) / 2) * 0.1
				local height = 92 - size * 6 - row * 10
				local bottom = 0.8 - row * 0.06
				MenuStyle.Figure(card, Color3.fromRGB(190, 30, 35), 0.27 + spread, bottom, height)
				MenuStyle.Figure(card, Color3.fromRGB(30, 75, 200), 0.73 - spread, bottom, height)
			end
		end
	end
	MenuStyle.Text(card, "VS", UDim2.fromOffset(60, 36), UDim2.fromScale(0.5, 0.45), Vector2.new(0.5, 0.5))

	local strip = Instance.new("Frame")
	strip.AnchorPoint = Vector2.new(0, 1)
	strip.Position = UDim2.fromScale(0, 1)
	strip.Size = UDim2.new(1, 0, 0, 62)
	strip.BackgroundColor3 = Color3.new(0, 0, 0)
	strip.BackgroundTransparency = 0.3
	strip.Parent = card
	MenuStyle.Text(strip, mode, UDim2.new(0.5, 0, 0, 42), UDim2.new(0.42, 0, 0.5, 0), Vector2.new(0.5, 0.5))
	MenuStyle.Check(strip, UDim2.fromScale(0.82, 0.5))

	card.Activated:Connect(function()
		selected[mode] = not selected[mode]
		refreshCards()
	end)
	return card
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "MainMenu"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5
	gui.Parent = player:WaitForChild("PlayerGui")

	-- PLAY NOW
	playHolder = Instance.new("Frame")
	playHolder.AnchorPoint = Vector2.new(0.5, 1)
	playHolder.Position = UDim2.new(0.5, 0, 1, -36)
	playHolder.Size = UDim2.fromOffset(330, 92)
	playHolder.BackgroundTransparency = 1
	playHolder.Parent = gui
	MenuStyle.FitToScreen(playHolder, Vector2.new(700, 500))
	local playButton = MenuStyle.Button(playHolder, "Play Now", MenuStyle.Green, UDim2.fromScale(1, 1), UDim2.new())
	playButton.Activated:Connect(function()
		modesOpen = true
		refreshCards()
	end)
	noticeLabel = MenuStyle.Text(gui, "", UDim2.fromOffset(620, 24), UDim2.new(0.5, 0, 1, -140), Vector2.new(0.5, 1))
	noticeLabel.TextColor3 = Color3.fromRGB(255, 120, 110)

	-- MODES screen
	modesScreen = Instance.new("Frame")
	modesScreen.Size = UDim2.fromScale(1, 1)
	modesScreen.BackgroundColor3 = Color3.new(0, 0, 0)
	modesScreen.BackgroundTransparency = 0.35
	modesScreen.Active = true
	modesScreen.Visible = false
	modesScreen.Parent = gui
	local content = Instance.new("Frame")
	content.AnchorPoint = Vector2.new(0.5, 0.5)
	content.Position = UDim2.fromScale(0.5, 0.5)
	content.Size = UDim2.fromOffset(980, 540)
	content.BackgroundTransparency = 1
	content.Parent = modesScreen
	MenuStyle.FitToScreen(content, Vector2.new(980, 540))
	modesTitle = MenuStyle.Text(content, "", UDim2.new(1, 0, 0, 70), UDim2.fromScale(0.5, 0), Vector2.new(0.5, 0))

	local row = Instance.new("Frame")
	row.Position = UDim2.fromOffset(0, 92)
	row.Size = UDim2.new(1, 0, 0, 330)
	row.BackgroundTransparency = 1
	row.Parent = content
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 24)
	layout.Parent = row
	for i, mode in MatchConfig.QueueModes do
		selected[mode] = true
		cards[mode] = modeCard(mode, i)
		cards[mode].Parent = row
	end

	local back = MenuStyle.Button(content, "Back", MenuStyle.Red, UDim2.fromOffset(240, 76), UDim2.new(0.5, -136, 1, 0), Vector2.new(0.5, 1))
	back.Activated:Connect(function()
		modesOpen = false
	end)
	startButton = MenuStyle.Button(content, "Start!", MenuStyle.Green, UDim2.fromOffset(240, 76), UDim2.new(0.5, 136, 1, 0), Vector2.new(0.5, 1))
	startButton.Activated:Connect(function()
		local modes = selectedModes()
		if #modes > 0 then
			notice = ""
			Queue:FireServer("Join", modes)
			modesOpen = false
		end
	end)

	-- Queue panel (bottom right)
	queuePanel = Instance.new("Frame")
	queuePanel.AnchorPoint = Vector2.new(1, 1)
	queuePanel.Position = UDim2.new(1, -20, 1, -20)
	queuePanel.Size = UDim2.fromOffset(400, 186)
	queuePanel.BackgroundColor3 = MenuStyle.Panel
	queuePanel.BackgroundTransparency = 0.08
	queuePanel.Visible = false
	queuePanel.Parent = gui
	MenuStyle.Corner(queuePanel, UDim.new(0, 14))
	MenuStyle.Rim(queuePanel, Color3.fromRGB(60, 64, 76), 3)
	MenuStyle.FitToScreen(queuePanel, Vector2.new(1100, 600))
	queueTitle = MenuStyle.Text(queuePanel, "", UDim2.new(1, -20, 0, 36), UDim2.new(0.5, 0, 0, 8), Vector2.new(0.5, 0))
	slotRow = Instance.new("Frame")
	slotRow.AnchorPoint = Vector2.new(0.5, 0)
	slotRow.Position = UDim2.new(0.5, 0, 0, 50)
	slotRow.Size = UDim2.new(1, -20, 0, 44)
	slotRow.BackgroundTransparency = 1
	slotRow.Parent = queuePanel
	local slotLayout = layout:Clone()
	slotLayout.Padding = UDim.new(0, 5)
	slotLayout.Parent = slotRow
	statusLabel = MenuStyle.Text(queuePanel, "", UDim2.fromOffset(200, 20), UDim2.new(0.5, 0, 0, 102), Vector2.new(0.5, 0))
	statusLabel.TextScaled = false -- (fixed size while the dots come and go)
	statusLabel.TextSize = 18
	leaveButton = MenuStyle.Button(queuePanel, "Leave", MenuStyle.Red, UDim2.fromOffset(150, 46), UDim2.new(0.5, 0, 1, -10), Vector2.new(0.5, 1))
	leaveButton.Activated:Connect(function()
		Queue:FireServer("Leave")
	end)
	countLabel = MenuStyle.Text(queuePanel, "", UDim2.fromOffset(70, 30), UDim2.new(1, -14, 1, -32), Vector2.new(1, 0.5))
	countLabel.TextXAlignment = Enum.TextXAlignment.Right
end

-- One square per player in the match: faces of who's in, a slow pulse for empty spots
local function buildSlots(mode: string, ids: { number })
	for _, child in slotRow:GetChildren() do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
	local size = teamSize(mode)
	local slotSize = if size >= 4 then 36 else 42
	for i = 1, size * 2 do
		if i == size + 1 then
			local vs = MenuStyle.Text(slotRow, "Vs", UDim2.fromOffset(40, 34), UDim2.new())
			vs.LayoutOrder = i * 2 - 1
		end
		local slot = Instance.new("Frame")
		slot.Name = "Slot"
		slot.LayoutOrder = i * 2
		slot.Size = UDim2.fromOffset(slotSize, slotSize)
		slot.BackgroundColor3 = Color3.fromRGB(46, 50, 60)
		MenuStyle.Corner(slot, UDim.new(0, 8))
		MenuStyle.Rim(slot, if i <= size then MenuStyle.Red else MenuStyle.Blue, 2)
		local id = ids[i]
		if id then
			local face = Instance.new("ImageLabel")
			face.Size = UDim2.fromScale(1, 1)
			face.BackgroundTransparency = 1
			face.Image = if id > 0 then `rbxthumb://type=AvatarHeadShot&id={id}&w=48&h=48` else ""
			face.Parent = slot
			MenuStyle.Corner(face, UDim.new(0, 8))
		else
			slot:SetAttribute("Empty", true)
		end
		slot.Parent = slotRow
	end
end

local function update()
	local phase = MatchState:GetAttribute("Phase")
	local inLobby = MatchState:GetAttribute("ServerKind") == "Lobby" and player:GetAttribute("Location") == "Lobby" and phase == "Waiting"
	if found and (phase ~= "Waiting" or os.clock() - found.at > 30) then
		found = nil -- (Studio plays the match here instead of teleporting; or the teleport never came)
	end
	gui.Enabled = inLobby or found ~= nil
	if not inLobby then
		modesOpen = false
	end
	playHolder.Visible = not modesOpen and not found
	modesScreen.Visible = modesOpen

	-- The fullest of my queues (or the match that was found)
	local mode, ids = nil, {}
	if found then
		mode, ids = found.mode, found.ids
	else
		local best = -1
		for queued in string.gmatch(player:GetAttribute("Queued") or "", "[^,]+") do
			local list = queuedIds(queued)
			local fill = #list / (teamSize(queued) * 2)
			if fill > best then
				mode, ids, best = queued, list, fill
			end
		end
	end
	queuePanel.Visible = mode ~= nil and not modesOpen
	noticeLabel.Text = notice
	noticeLabel.Visible = notice ~= "" and not modesOpen
	if not mode then
		return
	end
	local needed = teamSize(mode) * 2
	queueTitle.Text = mode
	countLabel.Text = `{#ids}/{needed}`
	leaveButton.Visible = not found
	statusLabel.Text = if found then "MATCH FOUND!" else "SEARCHING" .. string.rep(".", math.floor(os.clock() * 2) % 4)
	statusLabel.TextColor3 = if found then Color3.fromRGB(120, 255, 100) else Color3.new(1, 1, 1)
	local key = mode .. ":" .. table.concat(ids, ",")
	if key ~= shownSlots then
		shownSlots = key
		buildSlots(mode, ids)
	end
	local pulse = 0.35 + 0.3 * math.sin(os.clock() * 4)
	for _, slot in slotRow:GetChildren() do
		if slot:GetAttribute("Empty") then
			(slot :: Frame).BackgroundTransparency = pulse
		end
	end
end

function MainMenu.Start()
	build()
	Queue.OnClientEvent:Connect(function(event, mode, ids)
		if event == "Found" then
			found = { mode = mode, ids = ids or {}, at = os.clock() }
			notice = ""
			if not RunService:IsStudio() then
				TeleportService:SetTeleportGui(LoadingScreen.Build(`LOADING {mode} MATCH...`))
			end
		elseif event == "Failed" then
			found = nil
			notice = "COULDN'T START THE MATCH · PRESS PLAY TO TRY AGAIN"
		end
	end)
	RunService.RenderStepped:Connect(update)
end

return MainMenu
