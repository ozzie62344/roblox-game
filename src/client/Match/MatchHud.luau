-- Top-of-screen match info (scores, timer, players alive), round banners and the kill feed.
-- Reads the attributes RoundService sets on ReplicatedStorage.MatchState.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Teams = game:GetService("Teams")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local MatchConfig = require(ReplicatedStorage.Shared.MatchConfig)

local MatchState = ReplicatedStorage:WaitForChild("MatchState")
local KillFeed = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("KillFeed") :: RemoteEvent

local player = Players.LocalPlayer

local MatchHud = {}

local PHASE_LABELS = {
	Waiting = "WAITING FOR PLAYERS",
	Starting = "MATCH STARTING",
	PreRound = "PREPARE",
	Action = "",
	PostRound = "ROUND OVER",
	MatchOver = "MATCH OVER",
}

local gui: ScreenGui
local timerLabel: TextLabel
local phaseLabel: TextLabel
local bannerLabel: TextLabel
local scoreLabels: { [string]: TextLabel } = {}
local pipFrames: { [string]: { Frame } } = {}
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

	local top = Instance.new("Frame")
	top.AnchorPoint = Vector2.new(0.5, 0)
	top.Position = UDim2.new(0.5, 0, 0, 12)
	top.Size = UDim2.fromOffset(320, 64)
	top.BackgroundTransparency = 1
	top.Parent = gui

	timerLabel = text(top, UDim2.fromOffset(120, 34), UDim2.new(0.5, 0, 0, 0), 30)
	phaseLabel = text(top, UDim2.fromOffset(240, 18), UDim2.new(0.5, 0, 0, 36), 13)
	phaseLabel.TextColor3 = Color3.fromRGB(200, 205, 215)

	for i, name in MatchConfig.TeamOrder do
		local side = if i == 1 then -1 else 1
		local box = Instance.new("Frame")
		box.AnchorPoint = Vector2.new(0.5, 0)
		box.Position = UDim2.new(0.5, side * 105, 0, 0)
		box.Size = UDim2.fromOffset(56, 34)
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
		scoreLabels[name] = text(box, UDim2.fromScale(1, 1), UDim2.fromScale(0.5, 0), 24)

		-- One pip per player slot: filled = alive
		pipFrames[name] = {}
		for p = 1, MatchConfig.MaxTeamSize do
			local pip = Instance.new("Frame")
			pip.AnchorPoint = Vector2.new(0.5, 0)
			pip.Size = UDim2.fromOffset(10, 10)
			pip.Position = UDim2.new(0.5, side * 105 + (p - (MatchConfig.MaxTeamSize + 1) / 2) * 14, 0, 40)
			pip.BackgroundColor3 = teamColor(name)
			pip.BorderSizePixel = 0
			pip.Parent = top
			local pipStroke = Instance.new("UIStroke")
			pipStroke.Color = teamColor(name)
			pipStroke.Parent = pip
			pipFrames[name][p] = pip
		end
	end

	bannerLabel = text(gui, UDim2.fromOffset(800, 60), UDim2.new(0.5, 0, 0.22, 0), 42)
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

local function update()
	local phase = MatchState:GetAttribute("Phase") or "Waiting"
	local endsAt = MatchState:GetAttribute("PhaseEndsAt") or 0
	local remaining = endsAt - Workspace:GetServerTimeNow()

	local inMatch = phase ~= "Waiting" and phase ~= "Starting"
	timerLabel.Text = if endsAt > 0 then formatTime(remaining) else ""

	local phaseText = PHASE_LABELS[phase] or ""
	local round = MatchState:GetAttribute("Round") or 0
	if inMatch and round > 0 then
		phaseText = if phaseText == "" then `ROUND {round}` else `ROUND {round} · {phaseText}`
	elseif phase == "Waiting" then
		phaseText ..= ` ({#Players:GetPlayers()}/{MatchConfig.MinPlayers})`
		if player:GetAttribute("IsDev") then
			phaseText ..= "  ·  P → Start match"
		end
	end
	phaseLabel.Text = phaseText

	for _, name in MatchConfig.TeamOrder do
		local box = scoreLabels[name].Parent :: Frame
		box.Visible = inMatch
		scoreLabels[name].Text = tostring(MatchState:GetAttribute("Score" .. name) or 0)
		local stroke = box:FindFirstChild("YourTeam") :: UIStroke
		stroke.Enabled = player.Team ~= nil and player.Team.Name == name

		local team = Teams:FindFirstChild(name) :: Team?
		local members = if team then team:GetPlayers() else {}
		local alive = 0
		for _, member in members do
			local humanoid = member.Character and member.Character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				alive += 1
			end
		end
		for p, pip in pipFrames[name] do
			pip.Visible = inMatch and p <= #members
			pip.BackgroundTransparency = if p <= alive then 0 else 1
		end
	end
end

function MatchHud.Start()
	build()
	MatchState:GetAttributeChangedSignal("Banner"):Connect(function()
		showBanner(MatchState:GetAttribute("Banner") or "")
	end)
	KillFeed.OnClientEvent:Connect(addKillFeedEntry)
	RunService.RenderStepped:Connect(update)
end

return MatchHud
