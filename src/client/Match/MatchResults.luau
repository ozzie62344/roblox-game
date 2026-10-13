-- End-of-match results: a moment after the "X WINS THE MATCH" banner, a big screen for everyone:
-- VICTORY / DEFEAT, the MVP (best score, worked out by the server's MatchStats) standing with
-- their gun, and both teams' scoreboard (kills, deaths, assists, headshots, score).
-- CONTINUE (or ENTER) closes it. It also goes away by itself once the match is really over (the
-- phase moves on); on a match server everyone is being sent back to a lobby meanwhile, so it
-- simply stays up until the teleport.
-- While it's up the cursor is free (state.mouseUnlocked) and the phone's buttons hide
-- (state.resultsOpen, MobileControls).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Attachments = require(ReplicatedStorage.Shared.Attachments)
local MatchConfig = require(ReplicatedStorage.Shared.MatchConfig)
local Skins = require(ReplicatedStorage.Shared.Skins)
local Weapons = require(ReplicatedStorage.Shared.Weapons)
local GunModels = require(script.Parent.Parent.Combat.GunModels)
local state = require(script.Parent.Parent.PlayerState)
local MenuStyle = require(script.Parent.MenuStyle)

local MatchResultsRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("MatchResults") :: RemoteEvent
local MatchState = ReplicatedStorage:WaitForChild("MatchState")

local player = Players.LocalPlayer

local MatchResults = {}

local DESIGN = Vector2.new(1000, 540) -- the screen's size before FitToScreen shrinks it for phones
local GUN_SCALE = 1.35 -- (held guns are drawn this much bigger, like BodyAnimator's)
local ROW_HEIGHT = 30
local CARD = Color3.fromRGB(36, 39, 48)
local YOU = Color3.fromRGB(62, 67, 82)
local GREY = Color3.fromRGB(175, 180, 192)
-- Scoreboard columns: header, x, width
local COLUMNS = { { "K", 290 }, { "D", 345 }, { "A", 400 }, { "HS", 455 }, { "SCORE", 520 } }

type Row = {
	userId: number,
	name: string,
	team: string,
	kills: number,
	deaths: number,
	assists: number,
	headshots: number,
	objectives: number,
	score: number,
}
type Results = {
	winner: string,
	scores: { [string]: number },
	players: { Row },
	mvp: number?,
	mvpWeapon: string?,
	mvpBody: Model?,
	delay: number?,
}

local gui: ScreenGui
local showing: { root: Frame, step: RBXScriptConnection }? = nil

local function teamColor(name: string): Color3
	local team = MatchConfig.Teams[name]
	return if team then team.Color.Color else Color3.new(1, 1, 1)
end

local function close()
	local open = showing
	if not open then
		return
	end
	showing = nil
	open.step:Disconnect()
	open.root:Destroy()
	state.resultsOpen = false
	state.mouseUnlocked = false
end

-- Left-aligned or centered chunky text in a row
local function cell(parent: Instance, text: string, x: number, width: number, height: number, color: Color3?, left: boolean?): TextLabel
	local label = MenuStyle.Text(parent, text, UDim2.fromOffset(width, height), UDim2.new(0, x, 0.5, 0), Vector2.new(0, 0.5))
	label.TextXAlignment = if left then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center
	label.TextColor3 = color or Color3.new(1, 1, 1)
	return label
end

-- Puts the MVP's gun in the right hand of their body, arm a little forward, barrel ahead and
-- down (a relaxed "low ready")
local function holdGun(model: Model, base: CFrame, weaponName: string?, owner: Player?)
	local upper = model:FindFirstChild("RightUpperArm") :: BasePart?
	local lower = model:FindFirstChild("RightLowerArm") :: BasePart?
	local hand = model:FindFirstChild("RightHand") :: BasePart?
	local weapon = if weaponName then Weapons[weaponName] else nil
	if not (upper and lower and hand and weapon and weaponName) then
		return
	end
	-- (the body is anchored and outside the world: moving parts is all it takes, the joints don't pull back)
	local shoulderAttachment = upper:FindFirstChild("RightShoulderRigAttachment") :: Attachment?
	local shoulder = if shoulderAttachment then (upper.CFrame * shoulderAttachment.CFrame).Position else (upper.CFrame * CFrame.new(0, upper.Size.Y / 2, 0)).Position
	local swing = CFrame.new(shoulder) * CFrame.fromAxisAngle(base.RightVector, math.rad(35)) * CFrame.new(-shoulder)
	for _, part in { upper, lower, hand } do
		part.CFrame = swing * part.CFrame
	end

	local skin = if owner then Skins.EquippedFor(owner, weaponName) else nil
	local attachments = if owner then Attachments.For(owner, weaponName) else nil
	local gun = GunModels.Build(weaponName, weapon.Look.Color, skin, attachments)
	gun:ScaleTo(GUN_SCALE)
	local body = gun.PrimaryPart :: BasePart
	local grip = body:FindFirstChild("RightGrip") :: Attachment?
	-- The grip sits a little above the hand's middle (Roblox hands are big blocks)
	local gripPoint = (if grip then grip.CFrame.Position else Vector3.new(0, -0.3, 0.3)) - Vector3.new(0, 0.2, 0)
	gun:PivotTo(CFrame.new(hand.Position) * base.Rotation * CFrame.Angles(-math.rad(30), 0, 0) * CFrame.new(-gripPoint))
	gun.Parent = model
end

-- The MVP: their match body (MatchStats sends a standing copy) holding their gun, swaying
-- slowly; or their avatar picture when there's no body (they left / it couldn't be made).
-- Returns a function to call every frame.
local function mvpFigure(parent: Frame, results: Results, row: Row): (() -> ())?
	local body: Model? = results.mvpBody
	if not (typeof(body) == "Instance" and body:IsA("Model")) then
		-- (the copy may arrive a moment after the results)
		local found = ReplicatedStorage:FindFirstChild("MvpBody")
		body = if found and found:IsA("Model") then found :: Model else nil
	end
	local root = body and body:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not body or not root then
		if row.userId <= 0 then
			-- (Studio's test players have no avatar picture)
			MenuStyle.Figure(parent, teamColor(row.team), 0.5, 0.95, 190)
		end
		local image = Instance.new("ImageLabel")
		image.Size = UDim2.fromScale(1, 1)
		image.BackgroundTransparency = 1
		image.ScaleType = Enum.ScaleType.Fit
		image.Image = if row.userId > 0 then `rbxthumb://type=Avatar&id={row.userId}&w=420&h=420` else ""
		image.Parent = parent
		return nil
	end

	local viewport = Instance.new("ViewportFrame")
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.BackgroundTransparency = 1
	viewport.Ambient = Color3.fromRGB(150, 150, 160)
	viewport.LightColor = Color3.new(1, 1, 1)
	viewport.LightDirection = Vector3.new(-1, -1, -2)
	viewport.Parent = parent
	local model = (body :: Model):Clone()
	local base = (model:FindFirstChild("HumanoidRootPart") :: BasePart).CFrame
	holdGun(model, base, results.mvpWeapon, Players:GetPlayerByUserId(row.userId))
	model.Parent = viewport
	local camera = Instance.new("Camera")
	camera.FieldOfView = 34
	-- In front of them (bodies face -Z), a little to their right (the gun side) and above, looking
	-- at their middle
	camera.CFrame = CFrame.lookAt((base * CFrame.new(2.2, 0.8, -11)).Position, (base * CFrame.new(0, -0.3, 0)).Position)
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	return function()
		model:PivotTo(base * CFrame.Angles(0, math.sin(os.clock() * 0.8) * math.rad(25), 0))
	end
end

local function buildMvp(parent: Frame, results: Results, row: Row?): (() -> ())?
	local panel = Instance.new("Frame")
	panel.Size = UDim2.fromOffset(320, 370)
	panel.BackgroundColor3 = MenuStyle.Panel
	panel.Parent = parent
	MenuStyle.Corner(panel, UDim.new(0, 14))
	MenuStyle.Rim(panel, MenuStyle.Gold, 3)
	MenuStyle.Text(panel, "MVP", UDim2.fromOffset(200, 34), UDim2.new(0.5, 0, 0, 8), Vector2.new(0.5, 0)).TextColor3 = MenuStyle.Gold
	if not row then
		MenuStyle.Text(panel, "NOBODY", UDim2.fromOffset(240, 30), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5)).TextColor3 = GREY
		return nil
	end

	local stage = Instance.new("Frame")
	stage.Position = UDim2.fromOffset(10, 46)
	stage.Size = UDim2.fromOffset(300, 214)
	stage.BackgroundColor3 = CARD
	stage.ClipsDescendants = true
	stage.Parent = panel
	MenuStyle.Corner(stage, UDim.new(0, 10))
	local glow = Instance.new("UIGradient")
	glow.Rotation = 90
	glow.Color = ColorSequence.new(teamColor(row.team):Lerp(CARD, 0.55), CARD)
	glow.Parent = stage
	local frameStep = mvpFigure(stage, results, row)

	MenuStyle.Text(panel, string.upper(row.name), UDim2.fromOffset(296, 32), UDim2.new(0.5, 0, 0, 266), Vector2.new(0.5, 0)).TextColor3 = teamColor(row.team)
	local stats = `{row.kills} KILLS  ·  {row.assists} ASSISTS  ·  {row.headshots} HS`
	if row.objectives > 0 then
		stats ..= `  ·  {row.objectives} OBJ`
	end
	MenuStyle.Text(panel, stats, UDim2.fromOffset(296, 20), UDim2.new(0.5, 0, 0, 304), Vector2.new(0.5, 0)).TextColor3 = GREY
	MenuStyle.Text(panel, `{row.score} PTS`, UDim2.fromOffset(200, 28), UDim2.new(0.5, 0, 0, 330), Vector2.new(0.5, 0)).TextColor3 = MenuStyle.Gold
	return frameStep
end

-- One team: a colored bar (name, rounds won, WINNER), then its players by score
local function buildTeam(board: Frame, results: Results, teamName: string, order: number)
	local header = Instance.new("Frame")
	header.LayoutOrder = order
	header.Size = UDim2.new(1, 0, 0, 32)
	header.BackgroundColor3 = teamColor(teamName)
	header.Parent = board
	MenuStyle.Corner(header, UDim.new(0, 8))
	local rounds = results.scores[teamName] or 0
	cell(header, `{string.upper(teamName)}  ·  {rounds} ROUND{if rounds == 1 then "" else "S"}`, 14, 260, 22, nil, true)
	if results.winner == teamName then
		cell(header, "WINNER", 520, 100, 22)
	end

	for _, row in results.players do
		if row.team ~= teamName then
			continue
		end
		order += 1
		local line = Instance.new("Frame")
		line.LayoutOrder = order
		line.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
		line.BackgroundColor3 = if row.userId == player.UserId then YOU else CARD
		line.Parent = board
		MenuStyle.Corner(line, UDim.new(0, 6))
		local here = Players:GetPlayerByUserId(row.userId) ~= nil
		cell(line, row.name, 14, 200, 20, if here then nil else GREY, true)
		if row.userId == results.mvp then
			local tag = Instance.new("Frame")
			tag.AnchorPoint = Vector2.new(0, 0.5)
			tag.Position = UDim2.new(0, 222, 0.5, 0)
			tag.Size = UDim2.fromOffset(46, 20)
			tag.BackgroundColor3 = MenuStyle.Gold
			tag.Parent = line
			MenuStyle.Corner(tag, UDim.new(0, 5))
			MenuStyle.Text(tag, "MVP", UDim2.fromScale(0.8, 0.8), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
		end
		for i, value in { row.kills, row.deaths, row.assists, row.headshots, row.score } do
			local column = COLUMNS[i]
			cell(line, tostring(value), column[2], if i == 5 then 100 else 50, 18)
		end
	end
end

local function open(results: Results)
	close()
	state.resultsOpen = true
	local root = Instance.new("Frame")
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = Color3.fromRGB(8, 9, 12)
	root.BackgroundTransparency = 0.2
	root.Active = true -- (clicks don't reach the game under it)
	root.Parent = gui

	local content = Instance.new("Frame")
	content.AnchorPoint = Vector2.new(0.5, 0.5)
	content.Position = UDim2.fromScale(0.5, 0.5)
	content.Size = UDim2.fromOffset(DESIGN.X, DESIGN.Y)
	content.BackgroundTransparency = 1
	content.Parent = root
	MenuStyle.FitToScreen(content, DESIGN)

	-- VICTORY / DEFEAT (or who won, for anyone who sat it out), and the final score
	local mine: Row? = nil
	local mvpRow: Row? = nil
	for _, row in results.players do
		if row.userId == player.UserId then
			mine = row
		end
		if row.userId == results.mvp then
			mvpRow = row
		end
	end
	local won = mine ~= nil and mine.team == results.winner
	local title = if not mine then `{string.upper(results.winner)} WINS` elseif won then "VICTORY" else "DEFEAT"
	local heading = MenuStyle.Text(content, title, UDim2.fromOffset(600, 54), UDim2.new(0.5, 0, 0, 0), Vector2.new(0.5, 0))
	heading.TextColor3 = if not mine then teamColor(results.winner) elseif won then MenuStyle.Gold else MenuStyle.Red
	local order = MatchConfig.TeamOrder
	MenuStyle.Text(
		content,
		`{string.upper(order[1])}  {results.scores[order[1]] or 0} - {results.scores[order[2]] or 0}  {string.upper(order[2])}`,
		UDim2.fromOffset(400, 24), UDim2.new(0.5, 0, 0, 58), Vector2.new(0.5, 0)
	).TextColor3 = GREY

	local body = Instance.new("Frame")
	body.Position = UDim2.fromOffset(0, 92)
	body.Size = UDim2.fromOffset(DESIGN.X, 370)
	body.BackgroundTransparency = 1
	body.Parent = content
	local frameStep = buildMvp(body, results, mvpRow)

	local board = Instance.new("Frame")
	board.Position = UDim2.fromOffset(340, 0)
	board.Size = UDim2.fromOffset(660, 370)
	board.BackgroundTransparency = 1
	board.Parent = body
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 4)
	list.Parent = board
	local columns = Instance.new("Frame")
	columns.LayoutOrder = 0
	columns.Size = UDim2.new(1, 0, 0, 20)
	columns.BackgroundTransparency = 1
	columns.Parent = board
	cell(columns, "PLAYER", 14, 120, 16, GREY, true)
	for i, column in COLUMNS do
		cell(columns, column[1], column[2], if i == 5 then 100 else 50, 16, GREY)
	end
	-- The winners on top
	local first = if results.winner == order[2] then order[2] else order[1]
	buildTeam(board, results, first, 100)
	buildTeam(board, results, if first == order[1] then order[2] else order[1], 200)

	local continueButton = MenuStyle.Button(content, "CONTINUE", MenuStyle.Green, UDim2.fromOffset(300, 64), UDim2.new(0.5, 0, 1, 0), Vector2.new(0.5, 1))
	continueButton.Activated:Connect(close)
	local countdown = MenuStyle.Text(content, "", UDim2.fromOffset(300, 20), UDim2.new(1, 0, 1, -22), Vector2.new(1, 0.5))
	countdown.TextXAlignment = Enum.TextXAlignment.Right
	countdown.TextColor3 = GREY

	local step = RunService.RenderStepped:Connect(function()
		if frameStep then
			frameStep()
		end
		state.mouseUnlocked = not state.inLobby -- (the cursor for CONTINUE; the lobby frees it anyway)
		local left = math.ceil((MatchState:GetAttribute("PhaseEndsAt") or 0) - Workspace:GetServerTimeNow())
		countdown.Text = if left > 0 then `BACK TO THE LOBBY IN {left}` else "BACK TO THE LOBBY..."
	end)
	showing = { root = root, step = step }
end

function MatchResults.Start()
	gui = Instance.new("ScreenGui")
	gui.Name = "MatchResults"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 30 -- over the HUD and the menus (a flashbang's white still goes over it)
	gui.Parent = player:WaitForChild("PlayerGui")

	-- The banner first, then the screen (if the match is still over by then)
	MatchResultsRemote.OnClientEvent:Connect(function(results: Results)
		if typeof(results) ~= "table" or typeof(results.players) ~= "table" then
			return
		end
		task.delay(results.delay or 0, function()
			if MatchState:GetAttribute("Phase") == "MatchOver" then
				open(results)
			end
		end)
	end)
	MatchState:GetAttributeChangedSignal("Phase"):Connect(function()
		if MatchState:GetAttribute("Phase") ~= "MatchOver" then
			close()
		end
	end)
	UserInputService.InputBegan:Connect(function(input)
		if showing and (input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.ButtonA) then
			close()
		end
	end)
end

return MatchResults
