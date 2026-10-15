-- Top-of-screen match info, Siege-style: round timer in the middle, each team's score, a chip per
-- player with their operator (alive / dead), the phase, and a line saying what your side should be
-- doing. Also round banners and the kill feed.
-- Reads the attributes RoundService sets on ReplicatedStorage.MatchState ("RANKED · " in front of
-- the round line in a ranked match), and players' "Operator" / "HasDefuser" attributes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Teams = game:GetService("Teams")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local GameRules = require(ReplicatedStorage.Shared.GameRules)
local MatchConfig = require(ReplicatedStorage.Shared.MatchConfig)
local Operators = require(ReplicatedStorage.Shared.Operators)
local MusicController = require(script.Parent.Parent.Audio.MusicController)
local state = require(script.Parent.Parent.PlayerState)

local MatchState = ReplicatedStorage:WaitForChild("MatchState")
local KillFeed = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("KillFeed") :: RemoteEvent

local player = Players.LocalPlayer

local MatchHud = {}

local PHASE_LABELS = {
	Waiting = "WAITING FOR PLAYERS",
	Vote = "MAP VOTE",
	PreRound = "OPERATOR SELECTION",
	Prep = "PREPARATION PHASE",
	Action = "ACTION PHASE",
	Planted = "DEFUSER PLANTED",
	PostRound = "ROUND OVER",
	MatchOver = "MATCH OVER",
}

-- Top bar sizes (build): timer in the middle, a score each side, then a chip per player slot
local CHIP_WIDTH, CHIP_HEIGHT, CHIP_GAP = 78, 40, 4
local TIMER_WIDTH, SCORE_WIDTH, GAP = 104, 46, 6
local TOP_WIDTH = TIMER_WIDTH + 2 * (GAP + SCORE_WIDTH + GAP + MatchConfig.MaxTeamSize * (CHIP_WIDTH + CHIP_GAP))
local DEAD_COLOR = Color3.fromRGB(48, 50, 56)

type Chip = { frame: Frame, operator: TextLabel, player: TextLabel, badge: TextLabel }

local gui: ScreenGui
local top: Frame
local topScale: UIScale
local sideLabels: { [string]: TextLabel } = {}
local timerLabel: TextLabel
local phaseLabel: TextLabel
local hintLabel: TextLabel
local bannerLabel: TextLabel
local scoreLabels: { [string]: TextLabel } = {}
local chips: { [string]: { Chip } } = {}
local feedList: Frame

local function text(parent: Instance, size: UDim2, position: UDim2, textSize: number): TextLabel
	local l = Instance.new("TextLabel")
	l.AnchorPoint = Vector2.new(0.5, 0)
	l.Size = size
	l.Position = position
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextSize = textSize
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextStrokeTransparency = 0.6
	l.Parent = parent
	return l
end

local function teamColor(name: string): Color3
	return MatchConfig.Teams[name].Color.Color
end

local function formatTime(seconds: number): string
	seconds = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "MatchHud"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Siege-style top bar (top center; shrinks to fit a phone):
	--   [op][op][op][op] [3]  1:42  [2] [op][op][op][op]   ← operator (and player) per slot, greyed when dead
	--                    ATTACK      DEFEND
	--          ROUND 4 · MATCH POINT · ACTION PHASE         ← below everything, never overlapped
	--          YOU HAVE THE DEFUSER · PLANT IT IN KITCHEN   ← what your side should be doing
	top = Instance.new("Frame")
	top.AnchorPoint = Vector2.new(0.5, 0)
	top.Position = UDim2.new(0.5, 0, 0, 6)
	top.Size = UDim2.fromOffset(TOP_WIDTH, 98)
	top.BackgroundTransparency = 1
	top.Parent = gui
	topScale = Instance.new("UIScale")
	topScale.Parent = top

	local timerBox = Instance.new("Frame")
	timerBox.AnchorPoint = Vector2.new(0.5, 0)
	timerBox.Position = UDim2.new(0.5, 0, 0, 0)
	timerBox.Size = UDim2.fromOffset(TIMER_WIDTH, CHIP_HEIGHT)
	timerBox.BackgroundColor3 = Color3.fromRGB(15, 16, 20)
	timerBox.BackgroundTransparency = 0.3
	timerBox.BorderSizePixel = 0
	timerBox.Parent = top
	local timerCorner = Instance.new("UICorner")
	timerCorner.CornerRadius = UDim.new(0, 6)
	timerCorner.Parent = timerBox
	timerLabel = text(timerBox, UDim2.fromScale(1, 1), UDim2.fromScale(0.5, 0), 26)
	timerLabel.Font = Enum.Font.Michroma
	phaseLabel = text(top, UDim2.fromOffset(TOP_WIDTH, 16), UDim2.new(0.5, 0, 0, 62), 13)
	phaseLabel.Font = Enum.Font.Michroma
	phaseLabel.TextColor3 = Color3.fromRGB(215, 220, 230)
	hintLabel = text(top, UDim2.fromOffset(TOP_WIDTH, 16), UDim2.new(0.5, 0, 0, 80), 12)
	hintLabel.Font = Enum.Font.GothamBold
	hintLabel.TextColor3 = Color3.fromRGB(255, 205, 100)

	local scoreX = TIMER_WIDTH / 2 + GAP + SCORE_WIDTH / 2
	for i, name in MatchConfig.TeamOrder do
		local side = if i == 1 then -1 else 1
		local box = Instance.new("Frame")
		box.AnchorPoint = Vector2.new(0.5, 0)
		box.Position = UDim2.new(0.5, side * scoreX, 0, 0)
		box.Size = UDim2.fromOffset(SCORE_WIDTH, CHIP_HEIGHT)
		box.BackgroundColor3 = teamColor(name)
		box.BorderSizePixel = 0
		box.Parent = top
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = box
		local stroke = Instance.new("UIStroke")
		stroke.Name = "YourTeam"
		stroke.Color = Color3.new(1, 1, 1)
		stroke.Thickness = 2
		stroke.Enabled = false
		stroke.Parent = box
		scoreLabels[name] = text(box, UDim2.fromScale(1, 1), UDim2.fromScale(0.5, 0), 22)
		scoreLabels[name].Font = Enum.Font.Michroma

		-- "ATTACK" / "DEFEND" under each team's score (Attack / Defend mode)
		local sideLabel = text(top, UDim2.fromOffset(80, 12), UDim2.new(0.5, side * scoreX, 0, CHIP_HEIGHT + 3), 10)
		sideLabel.Font = Enum.Font.Michroma
		sideLabel.TextColor3 = Color3.fromRGB(215, 220, 230)
		sideLabels[name] = sideLabel

		-- One chip per player slot, filling outwards from the score: operator name over the
		-- player's name; greyed out when they're dead
		chips[name] = {}
		local innerEdge = TIMER_WIDTH / 2 + GAP + SCORE_WIDTH + GAP
		for p = 1, MatchConfig.MaxTeamSize do
			local chip = Instance.new("Frame")
			chip.AnchorPoint = Vector2.new(0.5, 0)
			chip.Size = UDim2.fromOffset(CHIP_WIDTH, CHIP_HEIGHT)
			chip.Position = UDim2.new(0.5, side * (innerEdge + (p - 1) * (CHIP_WIDTH + CHIP_GAP) + CHIP_WIDTH / 2), 0, 0)
			chip.BackgroundColor3 = teamColor(name)
			chip.BorderSizePixel = 0
			chip.Parent = top
			local chipCorner = Instance.new("UICorner")
			chipCorner.CornerRadius = UDim.new(0, 5)
			chipCorner.Parent = chip
			local operator = text(chip, UDim2.new(1, -6, 0, 18), UDim2.new(0.5, 0, 0, 3), 13)
			operator.Font = Enum.Font.GothamBlack
			operator.TextTruncate = Enum.TextTruncate.AtEnd
			local playerName = text(chip, UDim2.new(1, -6, 0, 14), UDim2.new(0.5, 0, 0, 22), 10)
			playerName.Font = Enum.Font.GothamMedium
			playerName.RichText = true
			playerName.TextTruncate = Enum.TextTruncate.AtEnd
			-- The defuser carrier (attackers see it on their own team)
			local badge = text(chip, UDim2.fromOffset(14, 14), UDim2.new(1, -8, 0, -5), 10)
			badge.Font = Enum.Font.GothamBlack
			badge.BackgroundTransparency = 0
			badge.BackgroundColor3 = Color3.fromRGB(255, 150, 60)
			badge.TextColor3 = Color3.fromRGB(20, 20, 24)
			badge.TextStrokeTransparency = 1
			badge.Text = "D"
			local badgeCorner = Instance.new("UICorner")
			badgeCorner.CornerRadius = UDim.new(0.5, 0)
			badgeCorner.Parent = badge
			chips[name][p] = { frame = chip, operator = operator, player = playerName, badge = badge }
		end
	end

	bannerLabel = text(gui, UDim2.fromOffset(900, 60), UDim2.new(0.5, 0, 0.22, 0), 34)
	bannerLabel.Font = Enum.Font.Michroma
	bannerLabel.TextTransparency = 1
	bannerLabel.TextStrokeTransparency = 1

	feedList = Instance.new("Frame")
	feedList.AnchorPoint = Vector2.new(1, 0)
	feedList.Position = UDim2.new(1, -20, 0, 20)
	feedList.Size = UDim2.fromOffset(360, 200)
	feedList.BackgroundTransparency = 1
	feedList.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 4)
	layout.Parent = feedList
end

local function showBanner(message: string)
	if message == "" then
		return
	end
	bannerLabel.Text = message
	bannerLabel.TextTransparency = 0
	bannerLabel.TextStrokeTransparency = 0.5
	local fade = TweenService:Create(
		bannerLabel,
		TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 2.2),
		{ TextTransparency = 1, TextStrokeTransparency = 1 }
	)
	fade:Play()
end

-- Music: a sting with the round's banners (MusicController), for players on a team. The live
-- round's banner (RoundService sets Phase before Banner) → RoundStart; "BLUE WINS · ..." →
-- RoundWin / RoundLoss (draws and halftime get none; the match's last round is MatchResults')
local function roundSting(message: string)
	local phase = MatchState:GetAttribute("Phase")
	local team = player.Team
	if not team or not table.find(MatchConfig.TeamOrder, team.Name) then
		return
	end
	if phase == "Action" then
		MusicController.Sting("RoundStart")
	elseif phase == "PostRound" and string.find(message, " WINS · ", 1, true) then
		local won = string.sub(message, 1, #team.Name + 5) == string.upper(team.Name) .. " WINS"
		MusicController.Sting(if won then "RoundWin" else "RoundLoss")
	end
end

local function colorHex(color: Color3): string
	return "#" .. color:ToHex()
end

local function addKillFeedEntry(killer: Player?, victim: Player, headshot: boolean)
	local function name(p: Player): string
		local color = if p.Team then p.Team.TeamColor.Color else Color3.new(1, 1, 1)
		return `<font color="{colorHex(color)}">{p.DisplayName}</font>`
	end

	local entry = Instance.new("TextLabel")
	entry.Size = UDim2.fromOffset(360, 24)
	entry.BackgroundColor3 = Color3.fromRGB(15, 16, 20)
	entry.BackgroundTransparency = 0.35
	entry.BorderSizePixel = 0
	entry.RichText = true
	entry.Font = Enum.Font.GothamMedium
	entry.TextSize = 15
	entry.TextColor3 = Color3.new(1, 1, 1)
	entry.TextXAlignment = Enum.TextXAlignment.Right
	entry.AutomaticSize = Enum.AutomaticSize.X
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.Parent = entry

	if killer and killer ~= victim then
		local marker = if headshot then '  <font color="#ff5050">[HEADSHOT]</font>  ' else "  ▸  "
		entry.Text = name(killer) .. marker .. name(victim)
	else
		entry.Text = name(victim) .. "  died"
	end
	-- Highlight lines that involve you
	if killer == player or victim == player then
		entry.BackgroundColor3 = Color3.fromRGB(70, 70, 80)
	end

	entry.LayoutOrder = -math.floor(os.clock() * 1000)
	entry.Parent = feedList

	task.delay(5, function()
		local fade = TweenService:Create(entry, TweenInfo.new(0.5), { TextTransparency = 1, BackgroundTransparency = 1 })
		fade:Play()
		fade.Completed:Wait()
		entry:Destroy()
	end)
end

-- The line under the phase: what your side should be doing right now
local function objectiveHint(phase: string): string
	local attackTeam = MatchState:GetAttribute("AttackTeam")
	if not attackTeam or not player.Team or not table.find(MatchConfig.TeamOrder, player.Team.Name) then
		return ""
	end
	local attacking = player.Team.Name == attackTeam
	local bomb = MatchState:GetAttribute("GameMode") == "AttackDefend"
	if phase == "PreRound" then
		return if attacking then "PICK AN OPERATOR AND YOUR SPAWN POINT"
			elseif bomb then "PICK AN OPERATOR AND A SITE TO DEFEND"
			else "PICK AN OPERATOR"
	elseif not bomb then
		return if phase == "Action" then "ELIMINATE THE ENEMY TEAM" else ""
	end
	local pair = MatchState:GetAttribute("SitePair")
	local site = if pair then string.upper(pair) else "A OR B"
	local known = not attacking or MatchState:GetAttribute("SiteFound") == true
	local key = if state.touchControls then "USE" else "G"
	if phase == "Prep" then
		if attacking then
			return if known then `OBJECTIVE FOUND: {site}  ·  KEEP SCOUTING` else "DRONE OUT AND FIND THE OBJECTIVE"
		end
		return `REINFORCE AND BARRICADE {site}  ·  STAY INSIDE`
	elseif phase == "Action" then
		if not attacking then
			return `DEFEND {site}  ·  STOP THE DEFUSER PLANT`
		end
		local where = if known then site else "THE OBJECTIVE (FIND IT)"
		if player:GetAttribute("HasDefuser") then
			return `YOU HAVE THE DEFUSER  ·  HOLD [{key}] IN {where} TO PLANT`
		elseif MatchState:GetAttribute("DefuserDropped") then
			return "THE DEFUSER WAS DROPPED  ·  PICK IT UP (D MARKER)"
		end
		local carrierId = MatchState:GetAttribute("DefuserCarrier")
		local carrier = if carrierId then Players:GetPlayerByUserId(carrierId) else nil
		return if carrier then `COVER {string.upper(carrier.DisplayName)} (DEFUSER)  ·  PLANT IN {where}` else `PLANT THE DEFUSER IN {where}`
	elseif phase == "Planted" then
		return if attacking then "DEFUSER PLANTED  ·  PROTECT IT UNTIL IT FINISHES" else `DISABLE THE DEFUSER  ·  HOLD [{key}] NEXT TO IT`
	end
	return ""
end

local function update()
	local phase = MatchState:GetAttribute("Phase") or "Waiting"
	local endsAt = MatchState:GetAttribute("PhaseEndsAt") or 0
	local remaining = endsAt - Workspace:GetServerTimeNow()

	local inMatch = phase ~= "Waiting" and phase ~= "Vote"
	timerLabel.Text = if endsAt > 0 then formatTime(remaining) else ""
	-- The fuse countdown shows in red
	timerLabel.TextColor3 = if phase == "Planted" then Color3.fromRGB(255, 70, 70) else Color3.new(1, 1, 1)

	local phaseText = PHASE_LABELS[phase] or ""
	local round = MatchState:GetAttribute("Round") or 0
	if inMatch and round > 0 then
		-- (the mode too, unless it's Classic: "ROUND 2 · KNIVES ONLY · PREPARATION PHASE"; and
		-- overtime / match point, like Siege)
		local rules = GameRules.Current()
		local prefix = `ROUND {round}`
		local need = MatchConfig.RoundsToWin - 1
		if round > MatchConfig.SwapSidesAfterRounds * 2 then
			prefix ..= " · OVERTIME"
		elseif (MatchState:GetAttribute("ScoreBlue") or 0) == need or (MatchState:GetAttribute("ScoreOrange") or 0) == need then
			prefix ..= " · MATCH POINT"
		end
		if rules.Id ~= "Classic" then
			prefix ..= ` · {string.upper(rules.Name)}`
		end
		if MatchState:GetAttribute("Ranked") == true then
			prefix = "RANKED · " .. prefix
		end
		phaseText = if phaseText == "" then prefix else `{prefix} · {phaseText}`
	elseif phase == "Waiting" then
		-- Match server: waiting for everyone teleported in. Lobby: the menu says it all.
		if MatchState:GetAttribute("ServerKind") == "Match" then
			phaseText ..= ` ({#Players:GetPlayers()}/{MatchState:GetAttribute("Expected") or "?"})`
			if MatchState:GetAttribute("Ranked") == true then
				phaseText = "RANKED · " .. phaseText
			end
		else
			phaseText = if player:GetAttribute("IsDev") then "P → dev panel (start a match)" else ""
		end
	end
	phaseLabel.Text = phaseText
	hintLabel.Text = if inMatch then objectiveHint(phase) else ""
	local timerBox = timerLabel.Parent :: Frame
	timerBox.Visible = timerLabel.Text ~= ""

	-- Fit the bar on a phone; the kill feed moves below it when they'd overlap
	local viewport = Workspace.CurrentCamera.ViewportSize
	topScale.Scale = math.min(1, (viewport.X - 16) / TOP_WIDTH)
	local crowded = viewport.X < TOP_WIDTH * topScale.Scale + 2 * (feedList.Size.X.Offset + 24)
	feedList.Position = UDim2.new(1, -20, 0, if crowded then 6 + 100 * topScale.Scale else 20)

	local attackTeam = MatchState:GetAttribute("AttackTeam")
	local myTeam = player.Team and player.Team.Name
	-- Enemy operators show once the round is live (operator selection and the setup are secret)
	local revealEnemies = phase == "Action" or phase == "Planted" or phase == "PostRound" or phase == "MatchOver"
	for _, name in MatchConfig.TeamOrder do
		local box = scoreLabels[name].Parent :: Frame
		box.Visible = inMatch
		scoreLabels[name].Text = tostring(MatchState:GetAttribute("Score" .. name) or 0)
		local stroke = box:FindFirstChild("YourTeam") :: UIStroke
		stroke.Enabled = myTeam == name

		local showSides = inMatch and attackTeam ~= nil and MatchState:GetAttribute("GameMode") == "AttackDefend"
		sideLabels[name].Visible = showSides
		sideLabels[name].Text = if attackTeam == name then "ATTACK" else "DEFEND"

		local team = Teams:FindFirstChild(name) :: Team?
		local members = if team then team:GetPlayers() else {}
		table.sort(members, function(a, b)
			return a.UserId < b.UserId
		end)
		local friendly = myTeam == name or player.Neutral
		for p, chip in chips[name] do
			local member = members[p]
			chip.frame.Visible = inMatch and member ~= nil
			if not chip.frame.Visible then
				continue
			end
			local humanoid = member.Character and member.Character:FindFirstChildOfClass("Humanoid")
			local alive = humanoid ~= nil and humanoid.Health > 0
			local operator = Operators.ById[member:GetAttribute("Operator") or ""]
			chip.operator.Text = if not friendly and not revealEnemies then "?"
				elseif operator then string.upper(operator.Name)
				else "..."
			chip.player.Text = if alive then member.DisplayName else `<s>{member.DisplayName}</s>`
			chip.frame.BackgroundColor3 = if alive then teamColor(name):Lerp(Color3.new(0, 0, 0), 0.35) else DEAD_COLOR
			chip.frame.BackgroundTransparency = if alive then 0.1 else 0.35
			local textColor = if alive then Color3.new(1, 1, 1) else Color3.fromRGB(130, 134, 142)
			chip.operator.TextColor3 = if alive and operator and (friendly or revealEnemies) then operator.Color:Lerp(Color3.new(1, 1, 1), 0.45) else textColor
			chip.player.TextColor3 = textColor
			chip.badge.Visible = friendly and alive and member:GetAttribute("HasDefuser") == true
		end
	end
end

function MatchHud.Start()
	build()
	MatchState:GetAttributeChangedSignal("Banner"):Connect(function()
		showBanner(MatchState:GetAttribute("Banner") or "")
		roundSting(MatchState:GetAttribute("Banner") or "") -- Music: RoundStart / RoundWin / RoundLoss sting
	end)
	KillFeed.OnClientEvent:Connect(addKillFeedEntry)
	RunService.RenderStepped:Connect(update)
end

return MatchHud
