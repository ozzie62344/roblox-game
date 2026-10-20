-- The PARTY (lobby): up to 5 friends who queue and play together, always on the same team.
--   Right side of the lobby: your party's faces (the leader's ringed in gold) and the PARTY button
--   (the SHOP is on the left).
--   The party screen: your party on the left (the leader marked; the leader can KICK, and LEAVE
--   on your own row hands the lead to the next one in), everyone else in this server on the
--   right with INVITE (only the leader, or someone on their own, invites).
--   An invite pops up at the top of the screen, "<name> invited you to their party", with JOIN /
--   NO, and goes away by itself when its time runs out. What happens ("BOB JOINED THE PARTY")
--   shows under it for a few seconds.
-- The server (PartyService) checks everything. Parties come from the "PartyLeader" player
-- attributes; MainMenu asks Leader() / Size() / Members(): only the leader queues, for modes the
-- party fits (and ranked only if everyone's level is high enough).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local state = require(script.Parent.Parent.PlayerState)
local LobbyIntro = require(script.Parent.LobbyIntro)
local MenuStyle = require(script.Parent.MenuStyle)

local MatchState = ReplicatedStorage:WaitForChild("MatchState")
local Party = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Party") :: RemoteEvent

local player = Players.LocalPlayer

local PartyMenu = {}

local CARD = Color3.fromRGB(36, 39, 48)
local EDGE = Color3.fromRGB(60, 64, 76)
local SOFT_TEXT = Color3.fromRGB(150, 156, 170)
local ROW_HEIGHT = 52
local NOTICE_TIME = 4

type Invite = { from: Player, ends: number, total: number }

local gui: ScreenGui
local lobbyWidget: Frame
local faceRow: Frame
local screen: Frame
local partyTitle: TextLabel
local memberList: Frame
local playerList: ScrollingFrame
local inviteHint: TextLabel
local popup: Frame
local popupFace: ImageLabel
local popupName: TextLabel
local popupMore: TextLabel
local popupTimer: Frame
local noticeLabel: TextLabel

local invites: { Invite } = {} -- invites to me, oldest first
local sent: { [Player]: number } = {} -- my invites → when they run out (os.clock)
local noticeText, noticeEnds = "", 0
local shownFaces = "" -- what the lobby faces were last built for
local shownScreen = "" -- ...and the party screen

local function maxSize(): number
	local size = MatchState:GetAttribute("PartyMaxSize")
	return if typeof(size) == "number" then size else 5
end

local function leaderId(other: Player): number?
	local id = other:GetAttribute("PartyLeader")
	return if typeof(id) == "number" then id else nil
end

-- Everyone in `other`'s party, leader first, then by name ({ other } if they're on their own)
local function partyOf(other: Player): { Player }
	local id = leaderId(other)
	if not id then
		return { other }
	end
	local list = {}
	for _, someone in Players:GetPlayers() do
		if leaderId(someone) == id then
			table.insert(list, someone)
		end
	end
	table.sort(list, function(a, b)
		if (a.UserId == id) ~= (b.UserId == id) then
			return a.UserId == id
		end
		return a.DisplayName < b.DisplayName
	end)
	return list
end

-- My party's leader (nil when I'm on my own)
function PartyMenu.Leader(): Player?
	local id = leaderId(player)
	if not id then
		return nil
	end
	for _, someone in Players:GetPlayers() do
		if someone.UserId == id then
			return someone
		end
	end
	return nil
end

-- How many of us there are (1 on my own)
function PartyMenu.Size(): number
	return #partyOf(player)
end

-- Everyone in my party, leader first ({ me } on my own): MainMenu checks they can all play ranked
function PartyMenu.Members(): { Player }
	return partyOf(player)
end

local inLobbyMenu = LobbyIntro.InLobby

local thinOutline = MenuStyle.ThinOutline

-- (blank for Studio's test players)
local function headshot(userId: number): string
	return if userId > 0 then `rbxthumb://type=AvatarHeadShot&id={userId}&w=150&h=150` else ""
end

-- A round head shot
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

local function listLayout(parent: Instance)
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
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
	local title = MenuStyle.Text(frame, heading, UDim2.fromOffset(220, 24), UDim2.fromOffset(14, 11))
	title.TextXAlignment = Enum.TextXAlignment.Left
	thinOutline(title, 2)
	return frame, title
end

-- One player in a list: face, name with a line under it, room for a button on the right
local function row(list: Instance, order: number, who: Player, line: string, lineColor: Color3): Frame
	local frame = Instance.new("Frame")
	frame.LayoutOrder = order
	frame.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
	frame.BackgroundColor3 = CARD
	MenuStyle.Corner(frame, UDim.new(0, 10))
	MenuStyle.Rim(frame, EDGE, 2).Name = "Rim"
	face(frame, who.UserId, 40, UDim2.new(0, 7, 0.5, 0), Vector2.new(0, 0.5))
	local name = MenuStyle.Text(frame, who.DisplayName, UDim2.new(1, -190, 0, 22), UDim2.fromOffset(56, 6))
	name.TextXAlignment = Enum.TextXAlignment.Left
	thinOutline(name, 2)
	local sub = MenuStyle.Text(frame, line, UDim2.new(1, -190, 0, 15), UDim2.fromOffset(56, 31))
	sub.TextXAlignment = Enum.TextXAlignment.Left
	sub.TextColor3 = lineColor
	thinOutline(sub, 1.5)
	frame.Parent = list
	return frame
end

-- Big enough for a thumb (the whole screen shrinks a little on phones)
local function rowButton(frame: Frame, text: string, color: Color3, onPress: () -> ())
	local button = MenuStyle.Button(frame, text, color, UDim2.fromOffset(120, 42), UDim2.new(1, -5, 0.5, 0), Vector2.new(1, 0.5))
	button.Activated:Connect(onPress)
end

local function openSlot(list: Instance, order: number)
	local frame = Instance.new("Frame")
	frame.LayoutOrder = order
	frame.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
	frame.BackgroundColor3 = CARD
	frame.BackgroundTransparency = 0.6
	MenuStyle.Corner(frame, UDim.new(0, 10))
	MenuStyle.Rim(frame, EDGE, 2).Transparency = 0.5
	local label = MenuStyle.Text(frame, "OPEN SLOT", UDim2.new(1, -20, 0, 18), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
	label.TextColor3 = Color3.fromRGB(110, 116, 130)
	thinOutline(label, 1.5)
	frame.Parent = list
end

-- ─── Refresh ───────────────────────────────────────────────────────────────────

-- The lobby's row of faces: one per member, a dim circle per open slot
local function rebuildFaces(members: { Player }, leader: Player?)
	clear(faceRow)
	for i = 1, maxSize() do
		local member = members[i]
		local slot = Instance.new("Frame")
		slot.LayoutOrder = i
		slot.Size = UDim2.fromOffset(30, 30)
		slot.BackgroundColor3 = Color3.fromRGB(46, 50, 60)
		slot.BackgroundTransparency = if member then 0 else 0.5
		MenuStyle.Corner(slot, UDim.new(1, 0))
		MenuStyle.Rim(slot, if member and member == leader then MenuStyle.Gold else EDGE, 2)
		if member then
			face(slot, member.UserId, 30, UDim2.new())
		end
		slot.Parent = faceRow
	end
end

local function rebuildScreen(members: { Player }, leader: Player?)
	local leading = leader == nil or leader == player -- (on my own, or the leader)
	local max = maxSize()
	local full = #members >= max
	partyTitle.Text = if leader then `YOUR PARTY · {#members}/{max}` else "YOUR PARTY"

	-- Left: us
	clear(memberList)
	for i = 1, max do
		local member = members[i]
		if not member then
			openSlot(memberList, i)
			continue
		end
		local isLeader = member == leader
		local line = if isLeader and member == player then "LEADER · YOU"
			elseif isLeader then "LEADER"
			elseif member == player then "YOU"
			else "MEMBER"
		local frame = row(memberList, i, member, line, if isLeader then MenuStyle.Gold else SOFT_TEXT)
		if isLeader then
			(frame:FindFirstChild("Rim") :: UIStroke).Color = MenuStyle.Gold
		end
		if leader and member == player then
			rowButton(frame, "Leave", MenuStyle.Red, function()
				Party:FireServer("Leave")
			end)
		elseif leader == player then
			rowButton(frame, "Kick", MenuStyle.Red, function()
				Party:FireServer("Kick", member)
			end)
		end
	end

	-- Right: everyone else here
	clear(playerList)
	local others = {}
	for _, other in Players:GetPlayers() do
		if not table.find(members, other) then
			table.insert(others, other)
		end
	end
	table.sort(others, function(a, b)
		return a.DisplayName < b.DisplayName
	end)
	local now = os.clock()
	for i, other in others do
		local theirs = #partyOf(other)
		local frame = row(playerList, i, other, if theirs > 1 then `IN A PARTY OF {theirs}` else `@{other.Name}`, SOFT_TEXT)
		if leading then
			local pending = (sent[other] or 0) > now
			local usable = not pending and not full
			rowButton(frame, if pending then "Sent" else "Invite", if usable then MenuStyle.Green else MenuStyle.Grey, function()
				if usable then
					Party:FireServer("Invite", other)
				end
			end)
		end
	end
	if #others == 0 then
		local empty = MenuStyle.Text(playerList, "NOBODY ELSE IS IN THIS SERVER YET", UDim2.new(1, -20, 0, 20), UDim2.new())
		empty.TextColor3 = SOFT_TEXT
		thinOutline(empty, 1.5)
	end
	inviteHint.Text = if not leading and leader then `ONLY {string.upper(leader.DisplayName)} CAN INVITE`
		elseif full then "YOUR PARTY IS FULL"
		else ""
end

-- What the party screen shows; it's rebuilt when this changes
local function screenKey(now: number): string
	local parts = { tostring(maxSize()) }
	for _, someone in Players:GetPlayers() do
		local pending = if (sent[someone] or 0) > now then 1 else 0
		table.insert(parts, `{someone.UserId}/{someone.DisplayName}/{leaderId(someone) or 0}/{pending}`)
	end
	return table.concat(parts, ",")
end

-- ─── Building ──────────────────────────────────────────────────────────────────

local function buildScreen()
	screen = Instance.new("Frame")
	screen.Name = "Screen"
	screen.Size = UDim2.fromScale(1, 1)
	screen.BackgroundColor3 = Color3.new(0, 0, 0)
	screen.BackgroundTransparency = 0.25
	screen.Active = true
	screen.Visible = false
	screen.Parent = gui
	-- Kept short so it shrinks less on a phone held sideways
	local content = Instance.new("Frame")
	content.AnchorPoint = Vector2.new(0.5, 0.5)
	content.Position = UDim2.fromScale(0.5, 0.5)
	content.Size = UDim2.fromOffset(840, 410)
	content.BackgroundTransparency = 1
	content.Parent = screen
	MenuStyle.FitToScreen(content, Vector2.new(840, 410))

	local title = MenuStyle.Text(content, "PARTY", UDim2.fromOffset(170, 56), UDim2.new())
	title.TextXAlignment = Enum.TextXAlignment.Left
	local subtitle = MenuStyle.Text(content, "PLAY TOGETHER · ALWAYS ON THE SAME TEAM", UDim2.fromOffset(440, 22), UDim2.fromOffset(186, 20))
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.TextColor3 = Color3.fromRGB(170, 176, 190)
	thinOutline(subtitle, 1.5)
	local back = MenuStyle.Button(content, "Back", MenuStyle.Red, UDim2.fromOffset(170, 56), UDim2.new(1, 0, 0, 0), Vector2.new(1, 0))
	back.Activated:Connect(PartyMenu.Close)

	-- Left: my party (room for every slot without scrolling)
	local left, heading = panel(content, UDim2.fromOffset(0, 68), UDim2.fromOffset(380, 342), "YOUR PARTY")
	partyTitle = heading
	memberList = Instance.new("Frame")
	memberList.Position = UDim2.fromOffset(10, 44)
	memberList.Size = UDim2.new(1, -20, 1, -52)
	memberList.BackgroundTransparency = 1
	memberList.Parent = left
	listLayout(memberList)

	-- Right: everyone else in this server
	local right = panel(content, UDim2.fromOffset(396, 68), UDim2.fromOffset(444, 342), "PLAYERS HERE")
	inviteHint = MenuStyle.Text(right, "", UDim2.fromOffset(240, 16), UDim2.new(1, -14, 0, 15), Vector2.new(1, 0))
	inviteHint.TextXAlignment = Enum.TextXAlignment.Right
	inviteHint.TextColor3 = Color3.fromRGB(255, 225, 120)
	thinOutline(inviteHint, 1.5)
	playerList = Instance.new("ScrollingFrame")
	playerList.Position = UDim2.fromOffset(10, 44)
	playerList.Size = UDim2.new(1, -14, 1, -52)
	playerList.BackgroundTransparency = 1
	playerList.BorderSizePixel = 0
	playerList.ScrollingDirection = Enum.ScrollingDirection.Y
	playerList.ScrollBarThickness = 6
	playerList.ScrollBarImageColor3 = Color3.fromRGB(120, 124, 135)
	playerList.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar
	playerList.CanvasSize = UDim2.new()
	playerList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	playerList.Parent = right
	listLayout(playerList)
end

-- The invite popup (top middle) with the notices under it, over every menu
local function buildPopup()
	local top = Instance.new("ScreenGui")
	top.Name = "PartyInvite"
	top.IgnoreGuiInset = true
	top.ResetOnSpawn = false
	top.DisplayOrder = 8 -- over the party screen and the shop
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
	MenuStyle.Rim(popup, MenuStyle.Blue, 3)
	popup.Parent = holder
	popupFace = face(popup, 0, 64, UDim2.fromOffset(16, 16))
	popupName = MenuStyle.Text(popup, "", UDim2.fromOffset(240, 30), UDim2.fromOffset(94, 16))
	popupName.TextXAlignment = Enum.TextXAlignment.Left
	local line = MenuStyle.Text(popup, "INVITED YOU TO THEIR PARTY", UDim2.fromOffset(300, 18), UDim2.fromOffset(94, 50))
	line.TextXAlignment = Enum.TextXAlignment.Left
	line.TextColor3 = Color3.fromRGB(190, 195, 205)
	thinOutline(line, 1.5)
	popupMore = MenuStyle.Text(popup, "", UDim2.fromOffset(100, 16), UDim2.new(1, -14, 0, 14), Vector2.new(1, 0))
	popupMore.TextXAlignment = Enum.TextXAlignment.Right
	popupMore.TextColor3 = SOFT_TEXT
	thinOutline(popupMore, 1.5)

	local function answer(action: string)
		local invite = table.remove(invites, 1)
		if invite then
			Party:FireServer(action, invite.from)
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
	popupTimer.BackgroundColor3 = MenuStyle.Blue
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
	gui.Name = "Party"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 7 -- over the lobby menu and the shop's button
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Lobby: my party's faces + PARTY button on the right (the SHOP is on the left)
	lobbyWidget = Instance.new("Frame")
	lobbyWidget.Name = "LobbyButtons"
	lobbyWidget.AnchorPoint = Vector2.new(1, 0.5)
	lobbyWidget.Position = UDim2.new(1, -20, 0.5, 0)
	lobbyWidget.Size = UDim2.fromOffset(200, 150)
	lobbyWidget.BackgroundTransparency = 1
	lobbyWidget.Visible = false
	lobbyWidget.Parent = gui
	LobbyIntro.Animate(lobbyWidget)
	MenuStyle.FitToScreen(lobbyWidget, Vector2.new(900, 520))
	local pill = Instance.new("Frame")
	pill.Size = UDim2.fromOffset(200, 50)
	pill.BackgroundColor3 = MenuStyle.Panel
	pill.BackgroundTransparency = 0.1
	MenuStyle.Corner(pill, UDim.new(1, 0))
	MenuStyle.Rim(pill, EDGE, 3)
	pill.Parent = lobbyWidget
	faceRow = Instance.new("Frame")
	faceRow.Size = UDim2.fromScale(1, 1)
	faceRow.BackgroundTransparency = 1
	faceRow.Parent = pill
	local faceLayout = Instance.new("UIListLayout")
	faceLayout.FillDirection = Enum.FillDirection.Horizontal
	faceLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	faceLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	faceLayout.SortOrder = Enum.SortOrder.LayoutOrder
	faceLayout.Padding = UDim.new(0, 5)
	faceLayout.Parent = faceRow
	local partyButton = MenuStyle.Button(lobbyWidget, "Party", MenuStyle.Blue, UDim2.fromOffset(200, 80), UDim2.new(0, 0, 1, 0), Vector2.new(0, 1))
	partyButton.Activated:Connect(PartyMenu.Open)

	buildScreen()
	buildPopup()
end

local function refresh(force: boolean?)
	local now = os.clock()
	local members = partyOf(player)
	local leader = PartyMenu.Leader()
	local ids = {}
	for _, member in members do
		table.insert(ids, member.UserId)
	end
	local facesKey = `{maxSize()}:{table.concat(ids, ",")}:{if leader then leader.UserId else 0}`
	if facesKey ~= shownFaces then
		shownFaces = facesKey
		rebuildFaces(members, leader)
	end
	if state.partyOpen then
		local key = screenKey(now)
		if force or key ~= shownScreen then
			shownScreen = key
			rebuildScreen(members, leader)
		end
	end
end

local function update()
	local now = os.clock()
	local lobby = inLobbyMenu()
	if state.partyOpen and not lobby then
		PartyMenu.Close() -- a match is starting
	end
	lobbyWidget.Visible = LobbyIntro.Shown("Party") and not state.partyOpen and not state.shopOpen and not state.modesOpen
	refresh()

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
	noticeLabel.Text = noticeText
	noticeLabel.Visible = lobby and now < noticeEnds
end

function PartyMenu.Open()
	if state.partyOpen then
		return
	end
	state.partyOpen = true
	screen.Visible = true
	refresh(true)
end

function PartyMenu.Close()
	state.partyOpen = false
	if screen then
		screen.Visible = false
	end
end

function PartyMenu.Start()
	build()
	Party.OnClientEvent:Connect(function(event, a, b)
		if event == "Invite" and typeof(a) == "Instance" and a:IsA("Player") and typeof(b) == "number" then
			-- (a new invite from the same person replaces the old one)
			for i, invite in invites do
				if invite.from == a then
					table.remove(invites, i)
					break
				end
			end
			table.insert(invites, { from = a, ends = os.clock() + b, total = b })
		elseif event == "Sent" and typeof(a) == "Instance" and a:IsA("Player") and typeof(b) == "number" then
			sent[a] = os.clock() + b
		elseif event == "Answered" and typeof(a) == "Instance" and a:IsA("Player") then
			sent[a] = nil
		elseif event == "Notice" and typeof(a) == "string" then
			noticeText, noticeEnds = a, os.clock() + NOTICE_TIME
		end
	end)
	Players.PlayerRemoving:Connect(function(other)
		sent[other] = nil
	end)
	RunService.RenderStepped:Connect(update)
end

return PartyMenu
