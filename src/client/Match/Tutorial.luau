-- The first-time tutorial: a checklist card at the top middle of the screen that moves on when you
-- actually do each thing (walk, look, sprint, crouch, then in the PRACTICE RANGE: vault, aim,
-- hit a bot, take two down, reload, lean, ping, scoreboard, and back out), then a few one-line
-- cards about the match (NEXT) and YOU'RE READY. Every line shows the key, or on a touch screen
-- the button's name (state.touchControls). Each step is checked here, on this client, from the
-- shared PlayerState (sprinting, vaulting, aiming, leaning, lastPing...) and a few remotes
-- (HitConfirmed for hits / kills on the bots, ReloadStarted for your own reloads).
--   New players (the "TutorialSeen" attribute is false: PlayerData) are asked once when they
--   first reach the lobby: NEW HERE? START / SKIP. The lobby's TUTORIAL button (right, under the
--   PARTY) runs it again any time.
--   Finishing it tells the server (TutorialService), which gives TutorialService.Reward credits
--   the first time only.
-- A step that needs the practice range is left out on a server without one (vaulting too: its
-- low walls and crates are there). Phones crouch in the range (the CROUCH button only shows when
-- you're playing, not in the lobby).
-- In the range the mouse is locked: Left Alt frees it to click SKIP (MouseUnlock).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local state = require(script.Parent.Parent.PlayerState)
local MenuStyle = require(script.Parent.MenuStyle)
local Scoreboard = require(script.Parent.Scoreboard)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local HitConfirmed = Remotes:WaitForChild("HitConfirmed") :: RemoteEvent
local ReloadStarted = Remotes:WaitForChild("ReloadStarted") :: RemoteEvent
local MatchState = ReplicatedStorage:WaitForChild("MatchState")

local player = Players.LocalPlayer

local Tutorial = {}

local REWARD = 250 -- (TutorialService.Reward on the server: shown here, paid there)
local GOLD_HEX = "#FFBE3C" -- MenuStyle.Gold
local ACCENT = Color3.fromRGB(255, 170, 60) -- the range's signs and HUD
local PROMPT_DELAY = 3 -- seconds in the lobby before NEW HERE? (after the loading screen)
local DONE_PAUSE = 0.8 -- seconds the green tick shows before the next step
local CARD_Y_LOBBY = 78 -- under the lobby's level bar (ProgressMenu)
local CARD_Y_RANGE = 104 -- under the range's stats and its "DOWNED" line (PracticeRange)

type Step = {
	title: string,
	text: () -> string, -- the one-line instruction (keys, or the phone's buttons)
	check: ((dt: number) -> boolean)?, -- true once it's done; nil = an info card (NEXT)
	begin: (() -> ())?,
	guide: string?, -- show the marker: "In" (to the range's door) or "Out" (back to the lobby)
	finish: boolean?, -- the last card (DONE: tells the server)
}

local gui: ScreenGui
local card: Frame
local tagLabel: TextLabel
local countLabel: TextLabel
local titleLabel: TextLabel
local textLabel: TextLabel
local check: Frame
local nextButton: TextButton
local skipButton: TextButton
local mouseHint: TextLabel
local prompt: Frame
local buttonHolder: Frame

local remote: RemoteEvent? = nil

local steps: { Step } = {}
local index = 0
local running = false
local completing = false
local prompted = false
local lobbyTime = 0
local shownText = ""

-- What the current step has counted so far (reset when a step begins)
local progress = 0
local stepStarted = 0
local lastFlat: Vector3? = nil
local lastYaw: number? = nil
local hits, kills, reloads = 0, 0, 0
local baseHits, baseKills, baseReloads = 0, 0, 0

-- The guide: a marker over the range's doorway (or its way out) and a beam to it from your feet
local marker: Part
local markerLabel: TextLabel
local beam: Beam
local beamFrom: Attachment
local doorway: Vector3? = nil -- the lobby side of the range's doorway
local inside: Vector3? = nil -- where the corridor opens into the range

local function gold(text: string): string
	return `<font color="{GOLD_HEX}"><b>{text}</b></font>`
end

local function touch(): boolean
	return state.touchControls
end

local function fire(kind: string)
	if remote then
		remote:FireServer(kind)
	end
end

local function rootPart(): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return if humanoid and humanoid.Health > 0 then root else nil
end

-- The lobby menu is on screen: a lobby server, in the lobby (not the range), between matches
local function inLobbyMenu(): boolean
	return MatchState:GetAttribute("ServerKind") == "Lobby"
		and player:GetAttribute("Location") == "Lobby"
		and not state.inPractice
		and MatchState:GetAttribute("Phase") == "Waiting"
end

local function menuOpen(): boolean
	return state.shopOpen or state.partyOpen or state.modesOpen or state.settingsOpen or state.modsOpen
		or state.resultsOpen or state.devPanelOpen
end

-- Finds the range's doorway from what the server built (PracticeRange): its PRACTICE RANGE sign
-- hangs over the lobby side, and the bots' invisible wall fills the far end of the corridor
local function findRange(): boolean
	if doorway and inside then
		return true
	end
	local range = Workspace:FindFirstChild("PracticeRange")
	if not range then
		return false
	end
	for _, item in range:GetDescendants() do
		if item:IsA("TextLabel") and item.Text == "PRACTICE RANGE" then
			local sign = item:FindFirstAncestorWhichIsA("BasePart")
			if sign then
				doorway = sign.Position - Vector3.new(0, 7, 0) -- (the sign is ~12 studs up: chest height in the doorway)
			end
			break
		end
	end
	local wall = range:FindFirstChild("BotWall", true)
	if wall and wall:IsA("BasePart") then
		inside = wall.Position
	end
	return doorway ~= nil and inside ~= nil
end

-- The camera's heading (radians)
local function cameraYaw(): number
	local look = Workspace.CurrentCamera.CFrame.LookVector
	return math.atan2(-look.X, -look.Z)
end

---------------------------------------------------------------------------------------------------
-- The steps

local moveStep: Step = {
	title = "MOVE",
	text = function()
		return if touch() then `Drag the {gold("THUMBSTICK")} on the left of the screen to walk` else `Walk around with {gold("W A S D")}`
	end,
	check = function()
		local root = rootPart()
		if root then
			local flat = Vector3.new(root.Position.X, 0, root.Position.Z)
			local moved = if lastFlat then (flat - lastFlat).Magnitude else 0
			if moved < 3 then -- (a bigger jump is a respawn or a teleport, not walking)
				progress += moved
			end
			lastFlat = flat
		end
		return progress >= 12
	end,
}

local lookStep: Step = {
	title = "LOOK AROUND",
	text = function()
		if touch() then
			return `Drag your finger on the {gold("RIGHT SIDE")} of the screen to look around`
		end
		return if state.inLobby then `Hold the {gold("RIGHT MOUSE BUTTON")} and drag to look around` else `Move the {gold("MOUSE")} to look around`
	end,
	check = function()
		local yaw = cameraYaw()
		if lastYaw then
			local turned = math.abs((yaw - lastYaw + math.pi) % (2 * math.pi) - math.pi)
			if turned < math.rad(60) then -- (a respawn snaps the camera)
				progress += turned
			end
		end
		lastYaw = yaw
		return progress >= math.rad(150)
	end,
}

local sprintStep: Step = {
	title = "SPRINT",
	text = function()
		return if touch() then `Push the {gold("THUMBSTICK")} all the way forward to sprint` else `Hold {gold("LEFT SHIFT")} while you walk forward to sprint`
	end,
	check = function(dt)
		if state.sprinting and state.speed > 1 then
			progress += dt
		end
		return progress >= 1
	end,
}

local crouchStep: Step = {
	title = "CROUCH",
	text = function()
		return if touch() then `Tap {gold("CROUCH")} to crouch` else `Press {gold("C")} to crouch`
	end,
	check = function()
		return state.crouching or state.prone
	end,
}

local vaultStep: Step = {
	title = "VAULT",
	text = function()
		local key = if touch() then "VAULT" else "SPACE"
		return `Walk up to a {gold("LOW WALL")} or crate and press {gold(key)} to vault over or climb up`
	end,
	check = function()
		return state.vaulting
	end,
}

local rangeStep: Step = {
	title = "THE PRACTICE RANGE",
	text = function()
		return `Follow the marker through the {gold("PRACTICE RANGE")} door`
	end,
	guide = "In",
	check = function()
		return state.inPractice
	end,
}

local aimStep: Step = {
	title = "AIM DOWN SIGHTS",
	text = function()
		return if touch() then `Tap {gold("AIM")} to aim down your sights` else `Hold the {gold("RIGHT MOUSE BUTTON")} to aim down your sights`
	end,
	check = function(dt)
		if state.inPractice and state.aiming and state.aimAlpha > 0.6 then
			progress += dt
		end
		return progress >= 0.3
	end,
}

local hitStep: Step = {
	title = "SHOOT A BOT",
	text = function()
		return if touch() then `Tap {gold("FIRE")} to shoot one of the bots (slide your finger on it to aim)` else `{gold("LEFT CLICK")} to shoot one of the bots`
	end,
	begin = function()
		baseHits = hits
	end,
	check = function()
		return hits > baseHits
	end,
}

local killStep: Step = {
	title = "TAKE DOWN 2 BOTS",
	text = function()
		return `Aim for the head: it's quicker  ({math.min(kills - baseKills, 2)}/2)`
	end,
	begin = function()
		baseKills = kills
	end,
	check = function()
		return kills - baseKills >= 2
	end,
}

local reloadStep: Step = {
	title = "RELOAD",
	text = function()
		return if touch() then `Fire a shot or two, then tap {gold("RELOAD")}` else `Fire a shot or two, then press {gold("R")} to reload`
	end,
	begin = function()
		baseReloads = reloads
	end,
	check = function()
		return reloads > baseReloads
	end,
}

local leanStep: Step = {
	title = "LEAN",
	text = function()
		return if touch() then `Tap {gold("LEAN LEFT")} or {gold("LEAN RIGHT")} to peek around cover` else `Press {gold("Q")} or {gold("E")} to lean and peek around cover`
	end,
	check = function()
		return state.leaning
	end,
}

local pingStep: Step = {
	title = "PING",
	text = function()
		return if touch() then `Tap {gold("PING")} to mark where you're looking for your team` else `Press {gold("T")} (or the middle mouse button) to mark a spot for your team`
	end,
	check = function()
		return state.lastPing > stepStarted
	end,
}

local scoreStep: Step = {
	title = "SCOREBOARD",
	text = function()
		return if touch() then `Tap {gold("SCORE")} to see the scoreboard` else `Hold {gold("TAB")} to see the scoreboard`
	end,
	check = function()
		return Scoreboard.IsOpen()
	end,
}

local outStep: Step = {
	title = "BACK TO THE LOBBY",
	text = function()
		return "Walk back out the way you came in"
	end,
	guide = "Out",
	check = function()
		return not state.inPractice and player:GetAttribute("Location") == "Lobby"
	end,
}

local function info(title: string, text: () -> string): Step
	return { title = title, text = text }
end

local infoSteps: { Step } = {
	info("THE DRONE", function()
		return `Attackers: press {gold(if touch() then "DRONE" else "Z")} to drive a scout drone and find the enemy first`
	end),
	info("REINFORCE & BARRICADE", function()
		return `Defenders: hold {gold(if touch() then "USE" else "G")} on walls to reinforce them and on doors to barricade`
	end),
	info("THE DEFUSER", function()
		return "Attackers plant the defuser on a site; defenders stop them or disable it in time"
	end),
	info("OPERATORS", function()
		return `Each round you pick an operator: their gadget ({gold(if touch() then "ABILITY" else "X")}) is what sets them apart`
	end),
}

local finishStep: Step = {
	title = "YOU'RE READY!",
	text = function()
		local reward = if player:GetAttribute("TutorialDone") == true then "" else `  {gold(`+{REWARD} CREDITS`)}`
		return `Queue a {gold("QUICK MATCH")} with the big green button.{reward}`
	end,
	finish = true,
}

-- The steps in order for this run (phones crouch in the range: no CROUCH button in the lobby, so
-- without a range they skip it)
local function buildSteps(): { Step }
	local hasRange = findRange()
	local list: { Step } = { moveStep, lookStep, sprintStep }
	if not touch() then
		table.insert(list, crouchStep)
	end
	if hasRange then
		for _, step in { rangeStep, aimStep, hitStep, killStep, reloadStep, leanStep, pingStep, scoreStep, outStep } do
			table.insert(list, step)
			if step == rangeStep then
				if touch() then
					table.insert(list, crouchStep)
				end
				table.insert(list, vaultStep)
			end
		end
	end
	for _, step in infoSteps do
		table.insert(list, step)
	end
	table.insert(list, finishStep)
	return list
end

---------------------------------------------------------------------------------------------------

local function refreshCard()
	local step = steps[index]
	if not step then
		return
	end
	local text = step.text()
	if text ~= shownText then
		shownText = text
		textLabel.Text = text
	end
	countLabel.Text = `{index}/{#steps}`
	titleLabel.Text = step.title
	local isInfo = step.check == nil
	nextButton.Visible = isInfo
	local nextLabel = nextButton:FindFirstChild("Label") :: TextLabel
	nextLabel.Text = if step.finish then "Done" else "Next"
	tagLabel.Text = if isInfo and not step.finish then "TUTORIAL · TIP" else "TUTORIAL"
	-- (the cursor is locked out of the lobby: Left Alt frees it to click)
	mouseHint.Visible = not touch() and not state.inLobby and not state.mouseUnlocked
end

local function beginStep(i: number)
	index = i
	completing = false
	progress = 0
	stepStarted = os.clock()
	lastFlat, lastYaw = nil, nil
	check.Visible = false
	local step = steps[index]
	if step and step.begin then
		step.begin()
	end
	shownText = ""
	refreshCard()
end

local function stop()
	running = false
	card.Visible = false
	marker.Parent = nil
	beam.Enabled = false
	beamFrom.Parent = nil
end

local function advance()
	if index >= #steps then
		stop()
	else
		beginStep(index + 1)
	end
end

-- The step's done: a green tick for a moment, then the next one
local function complete()
	completing = true
	check.Visible = true
	local scale = check:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Scale = 0.4
	scale.Parent = check
	TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	local at = index
	task.delay(DONE_PAUSE, function()
		if running and index == at then
			advance()
		end
	end)
end

function Tutorial.Begin()
	if player:GetAttribute("TutorialSeen") == false then
		fire("Seen")
	end
	prompted = true
	prompt.Visible = false
	steps = buildSteps()
	running = true
	beginStep(1)
end

function Tutorial.IsRunning(): boolean
	return running
end

---------------------------------------------------------------------------------------------------
-- UI

local function makeCard()
	card = Instance.new("Frame")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 0)
	card.Position = UDim2.new(0.5, 0, 0, CARD_Y_LOBBY)
	card.Size = UDim2.fromOffset(460, 150)
	card.BackgroundColor3 = MenuStyle.Panel
	card.BackgroundTransparency = 0.12
	card.Visible = false
	card.Parent = gui
	MenuStyle.Corner(card, UDim.new(0, 12))
	MenuStyle.Rim(card, MenuStyle.Gold, 3)
	MenuStyle.FitToScreen(card, Vector2.new(520, 420))

	local function small(text: string, position: UDim2, anchor: Vector2, align: Enum.TextXAlignment): TextLabel
		local label = Instance.new("TextLabel")
		label.AnchorPoint = anchor
		label.Position = position
		label.Size = UDim2.fromOffset(200, 16)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.TextSize = 13
		label.TextColor3 = MenuStyle.Gold
		label.TextXAlignment = align
		label.Text = text
		label.Parent = card
		return label
	end
	tagLabel = small("TUTORIAL", UDim2.fromOffset(16, 10), Vector2.zero, Enum.TextXAlignment.Left)
	countLabel = small("", UDim2.new(1, -16, 0, 10), Vector2.new(1, 0), Enum.TextXAlignment.Right)
	countLabel.TextColor3 = Color3.fromRGB(200, 204, 214)

	titleLabel = MenuStyle.Text(card, "", UDim2.new(1, -80, 0, 32), UDim2.fromOffset(16, 28))
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	check = MenuStyle.Check(card, UDim2.new(1, -36, 0, 44))
	check.Visible = false

	textLabel = Instance.new("TextLabel")
	textLabel.Position = UDim2.fromOffset(16, 64)
	textLabel.Size = UDim2.new(1, -32, 0, 40)
	textLabel.BackgroundTransparency = 1
	textLabel.Font = Enum.Font.GothamMedium
	textLabel.TextSize = 16
	textLabel.TextColor3 = Color3.new(1, 1, 1)
	textLabel.TextStrokeTransparency = 0.6
	textLabel.TextWrapped = true
	textLabel.RichText = true
	textLabel.TextXAlignment = Enum.TextXAlignment.Left
	textLabel.TextYAlignment = Enum.TextYAlignment.Top
	textLabel.Text = ""
	textLabel.Parent = card

	skipButton = Instance.new("TextButton")
	skipButton.AnchorPoint = Vector2.new(0, 1)
	skipButton.Position = UDim2.new(0, 10, 1, -8)
	skipButton.Size = UDim2.fromOffset(130, 28)
	skipButton.BackgroundTransparency = 1
	skipButton.Font = Enum.Font.GothamBold
	skipButton.TextSize = 13
	skipButton.TextColor3 = Color3.fromRGB(170, 176, 190)
	skipButton.Text = "SKIP TUTORIAL"
	skipButton.Parent = card
	skipButton.Activated:Connect(stop)

	mouseHint = Instance.new("TextLabel")
	mouseHint.AnchorPoint = Vector2.new(0, 1)
	mouseHint.Position = UDim2.new(0, 140, 1, -8)
	mouseHint.Size = UDim2.fromOffset(160, 28)
	mouseHint.BackgroundTransparency = 1
	mouseHint.Font = Enum.Font.GothamMedium
	mouseHint.TextSize = 12
	mouseHint.TextColor3 = Color3.fromRGB(130, 136, 150)
	mouseHint.TextXAlignment = Enum.TextXAlignment.Left
	mouseHint.Text = "(LEFT ALT frees the mouse)"
	mouseHint.Visible = false
	mouseHint.Parent = card

	nextButton = MenuStyle.Button(card, "Next", MenuStyle.Green, UDim2.fromOffset(120, 38), UDim2.new(1, -12, 1, -8), Vector2.new(1, 1))
	nextButton.Visible = false
	nextButton.Activated:Connect(function()
		local step = steps[index]
		if not running or not step or step.check then
			return
		end
		if step.finish then
			fire("Done")
		end
		advance()
	end)
end

local function makePrompt()
	prompt = Instance.new("Frame")
	prompt.Name = "Prompt"
	prompt.AnchorPoint = Vector2.new(0.5, 0.5)
	prompt.Position = UDim2.fromScale(0.5, 0.45)
	prompt.Size = UDim2.fromOffset(440, 236)
	prompt.BackgroundColor3 = MenuStyle.Panel
	prompt.BackgroundTransparency = 0.05
	prompt.Active = true
	prompt.Visible = false
	prompt.Parent = gui
	MenuStyle.Corner(prompt, UDim.new(0, 16))
	MenuStyle.Rim(prompt, MenuStyle.Gold, 4)
	MenuStyle.FitToScreen(prompt, Vector2.new(480, 280))

	MenuStyle.Text(prompt, "NEW HERE?", UDim2.new(1, -40, 0, 54), UDim2.new(0.5, 0, 0, 16), Vector2.new(0.5, 0))
	MenuStyle.Text(prompt, "Take the 2-minute tutorial", UDim2.new(1, -60, 0, 28), UDim2.new(0.5, 0, 0, 76), Vector2.new(0.5, 0))
	local reward = MenuStyle.Text(prompt, `+{REWARD} CREDITS WHEN YOU FINISH`, UDim2.new(1, -120, 0, 20), UDim2.new(0.5, 0, 0, 112), Vector2.new(0.5, 0))
	reward.TextColor3 = MenuStyle.Gold

	local start = MenuStyle.Button(prompt, "Start", MenuStyle.Green, UDim2.fromOffset(190, 64), UDim2.new(0.5, 8, 1, -18), Vector2.new(0, 1))
	start.Activated:Connect(Tutorial.Begin)
	local skip = MenuStyle.Button(prompt, "Skip", MenuStyle.Grey, UDim2.fromOffset(190, 64), UDim2.new(0.5, -8, 1, -18), Vector2.new(1, 1))
	skip.Activated:Connect(function()
		prompt.Visible = false
		fire("Seen")
	end)
end

-- The lobby's TUTORIAL button: on the right, under the PARTY (SettingsMenu's is under the SHOP)
local function makeButton()
	buttonHolder = Instance.new("Frame")
	buttonHolder.Name = "TutorialButton"
	buttonHolder.AnchorPoint = Vector2.new(1, 0)
	buttonHolder.Position = UDim2.new(1, -20, 0.5, 100)
	buttonHolder.Size = UDim2.fromOffset(170, 50)
	buttonHolder.BackgroundTransparency = 1
	buttonHolder.Visible = false
	buttonHolder.Parent = gui
	MenuStyle.FitToScreen(buttonHolder, Vector2.new(900, 520))
	local button = MenuStyle.Button(buttonHolder, "Tutorial", Color3.fromRGB(70, 140, 150), UDim2.fromScale(1, 1), UDim2.new())
	button.Activated:Connect(Tutorial.Begin)
end

local function makeGuide()
	marker = Instance.new("Part")
	marker.Name = "TutorialMarker"
	marker.Anchored = true
	marker.CanCollide = false
	marker.CanQuery = false
	marker.CanTouch = false
	marker.Transparency = 1
	marker.Size = Vector3.new(0.2, 0.2, 0.2)
	local target = Instance.new("Attachment")
	target.Parent = marker

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(200, 70)
	billboard.StudsOffset = Vector3.new(0, 2, 0)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.Parent = marker
	markerLabel = MenuStyle.Text(billboard, "PRACTICE RANGE", UDim2.new(1, 0, 0, 26), UDim2.new())
	markerLabel.TextColor3 = ACCENT
	MenuStyle.Text(billboard, "▼", UDim2.new(0, 30, 0, 30), UDim2.new(0.5, 0, 0, 30), Vector2.new(0.5, 0))

	beamFrom = Instance.new("Attachment")
	beamFrom.Name = "TutorialBeam"
	beamFrom.Position = Vector3.new(0, -2, 0) -- (about at your feet)
	beam = Instance.new("Beam")
	beam.Attachment0 = beamFrom
	beam.Attachment1 = target
	beam.Color = ColorSequence.new(ACCENT)
	beam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.85),
		NumberSequenceKeypoint.new(0.15, 0.35),
		NumberSequenceKeypoint.new(1, 0.2),
	})
	beam.Width0 = 0.35
	beam.Width1 = 0.35
	beam.FaceCamera = true
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Segments = 2
	beam.Enabled = false
	beam.Parent = marker
end

-- The marker over where the current step wants you to go (nothing if the step doesn't guide)
local function updateGuide(step: Step?, visible: boolean)
	local root = rootPart()
	local goal: Vector3? = nil
	local name = "PRACTICE RANGE"
	if visible and step and step.guide and root and findRange() then
		local door, far = doorway :: Vector3, inside :: Vector3
		if step.guide == "In" then
			-- In the corridor already (nearer the range than its doorway is): on to the range itself
			goal = if (root.Position - far).Magnitude < (door - far).Magnitude then far else door
		elseif state.inPractice then
			goal, name = far, "LOBBY"
		end
	end
	if not goal or not root then
		marker.Parent = nil
		beam.Enabled = false
		return
	end
	marker.Position = goal + Vector3.new(0, math.sin(os.clock() * 3) * 0.3, 0)
	marker.Parent = Workspace
	markerLabel.Text = `{name} · {math.floor((goal - root.Position).Magnitude + 0.5)}m`
	if beamFrom.Parent ~= root then
		beamFrom.Parent = root
	end
	beam.Enabled = true
end

local function update(dt: number)
	local lobbyMenu = inLobbyMenu()
	lobbyTime = if lobbyMenu then lobbyTime + dt else 0

	-- NEW HERE? once, for a new player, a moment after they reach the lobby
	local seen = player:GetAttribute("TutorialSeen")
	if not prompted and not running and seen == false and lobbyMenu and lobbyTime >= PROMPT_DELAY and not menuOpen() then
		prompted = true
		prompt.Visible = true
	end
	if prompt.Visible and (not lobbyMenu or seen ~= false) then
		prompt.Visible = false -- (a match is starting, or another server said they've seen it)
	end

	buttonHolder.Visible = lobbyMenu and not running and not prompt.Visible and not menuOpen() and not player:GetAttribute("Queued")

	if not running then
		return
	end
	-- (paused away from the lobby: a match in Studio, spectating)
	local here = MatchState:GetAttribute("ServerKind") == "Lobby" and player:GetAttribute("Location") == "Lobby" and not state.spectating
	card.Visible = here and not menuOpen()
	card.Position = UDim2.new(0.5, 0, 0, if state.inPractice then CARD_Y_RANGE else CARD_Y_LOBBY)
	local step = steps[index]
	if here and step and step.check and not completing and step.check(dt) then
		complete()
	end
	refreshCard()
	updateGuide(step, card.Visible and not completing)
end

function Tutorial.Start()
	gui = Instance.new("ScreenGui")
	gui.Name = "Tutorial"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 9 -- over the lobby menus (the level bar's popups are 8)
	gui.Parent = player:WaitForChild("PlayerGui")
	makeCard()
	makePrompt()
	makeButton()
	makeGuide()

	-- Hits and kills on the practice bots (nobody else can be hit in the lobby), your own reloads
	HitConfirmed.OnClientEvent:Connect(function(_damage: number, _headshot: boolean, killed: boolean)
		if state.inPractice then
			hits += 1
			kills += if killed then 1 else 0
		end
	end)
	ReloadStarted.OnClientEvent:Connect(function(reloader: Player)
		if reloader == player then
			reloads += 1
		end
	end)

	RunService.RenderStepped:Connect(update)

	-- (made by the server at start; waited for off the main thread so nothing else is held up)
	task.spawn(function()
		remote = Remotes:WaitForChild("Tutorial") :: RemoteEvent
	end)
end

return Tutorial
