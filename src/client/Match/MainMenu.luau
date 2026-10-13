-- The lobby menu (lobby servers, while you're in the lobby):
--   PLAY NOW → the MODES screen: tick any of 1v1 / 2v2 / 3v3 / 4v4, START queues you for all of
--   them (server Matchmaker). The queue panel (bottom right) shows the fullest of your queues:
--   everyone's faces, Team 1 Vs Team 2, and LEAVE. When it fills: MATCH FOUND → loading screen
--   → teleported into the match (where MapVote takes over).
-- In a party (PartyMenu) only the leader picks modes and queues, for the whole party; modes whose
-- teams the party doesn't fit in are greyed out. The others see "Waiting for <leader>", what the
-- leader is searching for, and the leader's queue.
-- QUICK MATCH and RANKED sit side by side. RANKED (shared/Ranked) opens the same MODES screen for
-- the ranked queues; it shows your rank badge and rank (or PLACEMENTS 2/5). Under level 20 it's
-- locked: a padlock, "REACH LEVEL 20" and a bar of your XP towards it. In a party it's greyed out
-- with who's under the level (the server checks too).

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local LoadingScreen = require(ReplicatedFirst:WaitForChild("LoadingScreen"))
local MatchConfig = require(ReplicatedStorage.Shared.MatchConfig)
local Progression = require(ReplicatedStorage.Shared.Progression)
local Ranked = require(ReplicatedStorage.Shared.Ranked)
local state = require(script.Parent.Parent.PlayerState)
local MenuStyle = require(script.Parent.MenuStyle)
local PartyMenu = require(script.Parent.PartyMenu)
local RankBadge = require(script.Parent.RankBadge)

local MatchState = ReplicatedStorage:WaitForChild("MatchState")
local Queue = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Queue") :: RemoteEvent

local player = Players.LocalPlayer

local MainMenu = {}

local RANKED_COLOR = Color3.fromRGB(125, 70, 200)
local NOTE_YELLOW = Color3.fromRGB(255, 225, 120)

local selected: { [string]: boolean } = {}
local modesOpen = false
local rankedMode = false -- the MODES screen is for the ranked queues
local found: { mode: string, ids: { number }, at: number, ranked: boolean }? = nil -- the match we're being sent to
local notice = ""

local gui: ScreenGui
local playHolder: Frame
local playButton: TextButton
local partyLine: TextLabel
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
local rankedButton: TextButton
local rankedIcon: Frame -- the rank badge, or a padlock
local rankedSub: TextLabel
local rankedTrack: Frame -- (locked: XP towards the ranked level)
local rankedFill: Frame
local shownSlots = "" -- what the slot row was last built for
local shownParty = "" -- what the PLAY button and mode cards were last set up for
local shownRanked = "" -- ...and the RANKED button

local function teamSize(mode: string): number
	return tonumber(string.match(mode, "^(%d+)v")) :: number
end

-- In someone else's party: they pick the modes and queue for all of us
local function waitingFor(): Player?
	local leader = PartyMenu.Leader()
	return if leader and leader ~= player then leader else nil
end

-- The whole party fits in one of the mode's teams
local function fits(mode: string): boolean
	return teamSize(mode) >= PartyMenu.Size()
end

local function selectedModes(): { string }
	local list = {}
	for _, mode in MatchConfig.QueueModes do
		if selected[mode] and fits(mode) then
			table.insert(list, mode)
		end
	end
	return list
end

local function queuedIds(mode: string, ranked: boolean): { number }
	local ids = {}
	local key = "Queue" .. (if ranked then "Ranked" else "") .. mode
	for id in string.gmatch(MatchState:GetAttribute(key) or "", "%-?%d+") do
		table.insert(ids, tonumber(id) :: number)
	end
	return ids
end

local function numberAttribute(who: Player, name: string, default: number): number
	local value = who:GetAttribute(name)
	return if typeof(value) == "number" then value else default
end

-- Someone in my party (me included) who isn't level 20 yet, or nil: we can all play ranked
local function rankedBlocker(): Player?
	for _, member in PartyMenu.Members() do
		if numberAttribute(member, "Level", 1) < Ranked.MinLevel then
			return member
		end
	end
	return nil
end

-- How far my XP is towards the ranked level (0..1)
local function rankedProgress(): number
	local needed = 0
	for level = 1, Ranked.MinLevel - 1 do
		needed += Progression.XpToNext(level)
	end
	return math.clamp(numberAttribute(player, "Xp", 0) / needed, 0, 1)
end

-- A padlock (a ring for the shackle behind a block for the body)
local function padlock(parent: Frame)
	local shackle = Instance.new("Frame")
	shackle.AnchorPoint = Vector2.new(0.5, 0)
	shackle.Position = UDim2.fromScale(0.5, 0.08)
	shackle.Size = UDim2.fromScale(0.46, 0.6)
	shackle.BackgroundTransparency = 1
	shackle.Parent = parent
	MenuStyle.Corner(shackle, UDim.new(1, 0))
	MenuStyle.Rim(shackle, Color3.fromRGB(215, 220, 230), 6)
	local body = Instance.new("Frame")
	body.AnchorPoint = Vector2.new(0.5, 1)
	body.Position = UDim2.fromScale(0.5, 0.95)
	body.Size = UDim2.fromScale(0.72, 0.5)
	body.BackgroundColor3 = Color3.fromRGB(215, 220, 230)
	body.Parent = parent
	MenuStyle.Corner(body, UDim.new(0.18, 0))
	MenuStyle.Rim(body, MenuStyle.Outline, 2)
	local hole = Instance.new("Frame")
	hole.AnchorPoint = Vector2.new(0.5, 0.5)
	hole.Position = UDim2.fromScale(0.5, 0.48)
	hole.Size = UDim2.fromScale(0.14, 0.36)
	hole.BackgroundColor3 = MenuStyle.Outline
	hole.Parent = body
	MenuStyle.Corner(hole, UDim.new(1, 0))
end

-- The RANKED button: my badge and rank, or locked (level too low), or who in the party is
local function refreshRanked()
	for _, child in rankedIcon:GetChildren() do
		child:Destroy()
	end
	local level = numberAttribute(player, "Level", 1)
	local locked = level < Ranked.MinLevel
	local blocker = rankedBlocker()
	local mmr, matches = numberAttribute(player, "Mmr", Ranked.StartMmr), numberAttribute(player, "RankedMatches", 0)
	rankedTrack.Visible = locked
	if locked then
		padlock(rankedIcon)
		rankedFill.Size = UDim2.fromScale(rankedProgress(), 1)
		rankedSub.Text = `REACH LEVEL {Ranked.MinLevel} · LV {level}/{Ranked.MinLevel}`
		rankedSub.TextColor3 = NOTE_YELLOW
	else
		RankBadge.New(rankedIcon, 64, UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), mmr, matches)
		rankedSub.Text = if blocker then `{string.upper(blocker.DisplayName)} NEEDS LEVEL {Ranked.MinLevel}` else Ranked.Label(mmr, matches)
		rankedSub.TextColor3 = if blocker then NOTE_YELLOW else Ranked.ColorFor(mmr, matches):Lerp(Color3.new(1, 1, 1), 0.35)
	end
	MenuStyle.SetButtonColor(rankedButton, if blocker or waitingFor() then MenuStyle.Grey else RANKED_COLOR)
end

local function refreshCards()
	local partySize = PartyMenu.Size()
	local anyFits = false
	for mode, card in cards do
		local on = selected[mode] == true and fits(mode)
		local rim = card:FindFirstChild("Rim") :: UIStroke
		rim.Color = if on then MenuStyle.Green else Color3.new(1, 1, 1)
		rim.Thickness = if on then 5 else 2
		rim.Transparency = if on then 0 else 0.5
		;(card:FindFirstChild("Tint") :: Frame).Visible = on
		;(card:FindFirstChild("Check", true) :: Frame).Visible = on
		-- Too small for the party: greyed out, with why
		local blocked = card:FindFirstChild("Blocked") :: Frame
		blocked.Visible = not fits(mode)
		;(blocked:FindFirstChild("Reason") :: TextLabel).Text = `YOUR PARTY OF {partySize} WON'T FIT`
		anyFits = anyFits or fits(mode)
	end
	local list = selectedModes()
	modesTitle.Text = (if rankedMode then "Ranked · " else "")
		.. (if #list > 0 then "Modes: " .. table.concat(list, ", ")
			elseif anyFits then "Pick a mode"
			else `No mode fits a party of {partySize}`)
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

	-- Teams too small for your party: a dark cover with why (made last so it's drawn on top)
	local blocked = Instance.new("Frame")
	blocked.Name = "Blocked"
	blocked.Size = UDim2.fromScale(1, 1)
	blocked.BackgroundColor3 = Color3.new(0, 0, 0)
	blocked.BackgroundTransparency = 0.3
	blocked.Visible = false
	blocked.Parent = card
	MenuStyle.Text(blocked, "TOO SMALL", UDim2.new(0.8, 0, 0, 34), UDim2.fromScale(0.5, 0.42), Vector2.new(0.5, 0.5))
	local reason = MenuStyle.Text(blocked, "", UDim2.new(0.86, 0, 0, 18), UDim2.new(0.5, 0, 0.42, 30), Vector2.new(0.5, 0.5))
	reason.Name = "Reason"
	reason.TextColor3 = Color3.fromRGB(255, 225, 120)
	;(reason:FindFirstChildOfClass("UIStroke") :: UIStroke).Thickness = 1.5

	card.Activated:Connect(function()
		if not fits(mode) then
			return
		end
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

	-- QUICK MATCH and RANKED
	playHolder = Instance.new("Frame")
	playHolder.AnchorPoint = Vector2.new(0.5, 1)
	playHolder.Position = UDim2.new(0.5, 0, 1, -36)
	playHolder.Size = UDim2.fromOffset(690, 92)
	playHolder.BackgroundTransparency = 1
	playHolder.Parent = gui
	MenuStyle.FitToScreen(playHolder, Vector2.new(740, 500))
	playButton = MenuStyle.Button(playHolder, "Quick Match", MenuStyle.Green, UDim2.new(0, 330, 1, 0), UDim2.new())
	playButton.Activated:Connect(function()
		if waitingFor() then
			return -- (the leader queues for the party)
		end
		rankedMode = false
		modesOpen = true
		refreshCards()
	end)
	rankedButton = MenuStyle.Button(playHolder, "Ranked", RANKED_COLOR, UDim2.new(0, 330, 1, 0), UDim2.fromScale(1, 0), Vector2.new(1, 0))
	local rankedLabel = rankedButton:FindFirstChild("Label") :: TextLabel
	rankedLabel.Size = UDim2.fromScale(0.62, 0.42)
	rankedLabel.Position = UDim2.fromScale(0.6, 0.32)
	rankedSub = MenuStyle.Text(rankedButton, "", UDim2.fromScale(0.64, 0.19), UDim2.fromScale(0.6, 0.66), Vector2.new(0.5, 0.5))
	;(rankedSub:FindFirstChildOfClass("UIStroke") :: UIStroke).Thickness = 1.5
	rankedIcon = Instance.new("Frame")
	rankedIcon.AnchorPoint = Vector2.new(0, 0.5)
	rankedIcon.Position = UDim2.new(0, 14, 0.5, 0)
	rankedIcon.Size = UDim2.fromOffset(64, 64)
	rankedIcon.BackgroundTransparency = 1
	rankedIcon.Parent = rankedButton
	rankedTrack = Instance.new("Frame")
	rankedTrack.AnchorPoint = Vector2.new(0.5, 1)
	rankedTrack.Position = UDim2.new(0.6, 0, 1, -10)
	rankedTrack.Size = UDim2.new(0.56, 0, 0, 7)
	rankedTrack.BackgroundColor3 = MenuStyle.Outline
	rankedTrack.Parent = rankedButton
	MenuStyle.Corner(rankedTrack, UDim.new(1, 0))
	rankedFill = Instance.new("Frame")
	rankedFill.Size = UDim2.fromScale(0, 1)
	rankedFill.BackgroundColor3 = NOTE_YELLOW
	rankedFill.Parent = rankedTrack
	MenuStyle.Corner(rankedFill, UDim.new(1, 0))
	rankedButton.Activated:Connect(function()
		if waitingFor() then
			return
		end
		local blocker = rankedBlocker()
		if blocker then
			notice = if blocker == player then `REACH LEVEL {Ranked.MinLevel} TO PLAY RANKED`
				else `{string.upper(blocker.DisplayName)} IS LEVEL {numberAttribute(blocker, "Level", 1)} · EVERYONE NEEDS LEVEL {Ranked.MinLevel} FOR RANKED`
			return
		end
		notice = ""
		rankedMode = true
		modesOpen = true
		refreshCards()
	end)
	-- In someone's party: what the leader is searching for, under the (grey) button
	partyLine = MenuStyle.Text(playHolder, "", UDim2.new(1.4, 0, 0, 22), UDim2.new(0.5, 0, 1, 6), Vector2.new(0.5, 0))
	partyLine.TextColor3 = Color3.fromRGB(255, 225, 120)
	;(partyLine:FindFirstChildOfClass("UIStroke") :: UIStroke).Thickness = 1.5
	partyLine.Visible = false
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
			Queue:FireServer("Join", modes, rankedMode)
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
		and not state.inPractice -- (the practice range plays like a match: lobby menus hide)
	if found and (phase ~= "Waiting" or os.clock() - found.at > 30) then
		found = nil -- (Studio plays the match here instead of teleporting; or the teleport never came)
	end
	gui.Enabled = inLobby or found ~= nil
	local leader = waitingFor()
	if not inLobby or leader then
		modesOpen = false
	end
	state.modesOpen = modesOpen
	playHolder.Visible = not modesOpen and not found
	modesScreen.Visible = modesOpen

	-- Party: the others wait for the leader; modes too small for the party grey out
	local searching = player:GetAttribute("Queued")
	if searching then
		notice = "" -- (searching again)
	end
	local partyKey = `{if leader then leader.DisplayName else ""}:{PartyMenu.Size()}`
	if partyKey ~= shownParty then
		shownParty = partyKey
		;(playButton:FindFirstChild("Label") :: TextLabel).Text = if leader then `Waiting for {leader.DisplayName}` else "Quick Match"
		MenuStyle.SetButtonColor(playButton, if leader then MenuStyle.Grey else MenuStyle.Green)
		refreshCards()
	end
	-- RANKED: rebuilt when my rank, level or the party's levels change
	local blocker = rankedBlocker()
	local rankedKey = `{partyKey}:{if blocker then blocker.UserId else 0}:{player:GetAttribute("Level")}:{player:GetAttribute("Mmr")}`
		.. `:{player:GetAttribute("RankedMatches")}:{math.floor(rankedProgress() * 100)}`
	if rankedKey ~= shownRanked then
		shownRanked = rankedKey
		refreshRanked()
	end
	local queuedRanked = player:GetAttribute("QueuedRanked") == true
	partyLine.Visible = leader ~= nil
	if leader then
		partyLine.Text = if searching then `{string.upper(leader.DisplayName)} IS SEARCHING: {if queuedRanked then "RANKED " else ""}{(string.gsub(searching, ",", ", "))}`
			else `{string.upper(leader.DisplayName)} PICKS THE MODES`
	end

	-- The fullest of my queues (or the match that was found)
	local mode, ids = nil, {}
	if found then
		mode, ids, queuedRanked = found.mode, found.ids, found.ranked
	else
		local best = -1
		for queued in string.gmatch(player:GetAttribute("Queued") or "", "[^,]+") do
			local list = queuedIds(queued, queuedRanked)
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
	queueTitle.Text = if queuedRanked then `RANKED {mode}` else mode
	countLabel.Text = `{#ids}/{needed}`
	leaveButton.Visible = not found and not leader -- (only the leader stops a party's search)
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
	-- "Found" (mode, ids, ranked), "Failed", "Stopped" (why: the party changed while searching)
	Queue.OnClientEvent:Connect(function(event, a, b, c)
		if event == "Found" then
			found = { mode = a, ids = b or {}, at = os.clock(), ranked = c == true }
			notice = ""
			PartyMenu.Close() -- (MATCH FOUND takes the screen)
			if not RunService:IsStudio() then
				TeleportService:SetTeleportGui(LoadingScreen.Build(if c == true then `LOADING RANKED {a} MATCH...` else `LOADING {a} MATCH...`))
			end
		elseif event == "Failed" then
			found = nil
			notice = if waitingFor() then "COULDN'T START THE MATCH · YOUR LEADER CAN TRY AGAIN" else "COULDN'T START THE MATCH · PRESS PLAY TO TRY AGAIN"
		elseif event == "Stopped" and typeof(a) == "string" then
			notice = a
		end
	end)
	RunService.RenderStepped:Connect(update)
end

return MainMenu
