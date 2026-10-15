-- DOWN BUT NOT OUT on the client (the rules: Shared/DBNO; the server side: DBNOService).
--   You, downed (your character's "Downed" attribute → state.downed): MovementController keeps you
--   flat and crawling, the gun's put away (WeaponController), no gadgets, knife, lean, drone or
--   cameras. A pulsing red vignette and a heartbeat that quickens as you bleed out, "DOWNED" with
--   a bleed-out bar (your down pool) and "HOLD [F] TO HOLD WOUND": F (gamepad R3, the phone's
--   HOLD WOUND button) halves the bleed while held but you can't crawl.
--   Being picked up: a ring filling up in the middle of the screen, for you and for the reviver.
--   Teammates downed: a red marker over them that shows through walls (like Siege), with their
--   bleed-out bar and distance; enemies don't get one. ObjectiveController offers HOLD [G] TO
--   REVIVE when you're next to one (ReviveTarget), through the same Interact remote as a plant.
--   Downs also go in the kill feed (MatchHud, a smaller line than a kill).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local DBNO = require(ReplicatedStorage.Shared.DBNO)
local Sounds = require(ReplicatedStorage.Shared.Sounds)
local state = require(script.Parent.Parent.PlayerState)
local Actions = require(script.Parent.Parent.Input.Actions)
local Effects = require(script.Parent.Parent.Combat.Effects)
local Hud = require(script.Parent.Parent.Combat.Hud)
local MatchHud = require(script.Parent.MatchHud)

local MatchState = ReplicatedStorage:WaitForChild("MatchState")

local player = Players.LocalPlayer

local DBNOController = {}

local RED = Color3.fromRGB(230, 40, 40)
local REVIVE_COLOR = Color3.fromRGB(90, 220, 120)
local RING_SEGMENTS = 36
local RING_RADIUS = 38 -- pixels from the middle of the screen
-- Heartbeat: a beat every SLOW seconds with a full pool, every FAST nearly bled out ("lub-dub":
-- the landing thump pitched way down, twice)
local BEAT_SLOW, BEAT_FAST = 1.0, 0.45
local BEAT_GAP = 0.2 -- seconds between the two thumps of a beat
local BEAT_VOLUME = 0.55
local VIGNETTE_LOW, VIGNETTE_HIGH = 0.45, 0.1 -- the vignette's transparency between / on a beat

local remote: RemoteEvent? = nil
local gui: ScreenGui
local vignette: CanvasGroup
local panel: Frame
local titleLabel: TextLabel
local bleedFill: Frame
local hintLabel: TextLabel
local ring: Frame
local ringDots: { Frame } = {}
local ringLabel: TextLabel
local markers: { [Model]: { gui: BillboardGui, info: TextLabel, fill: Frame } } = {}
local nextBeat = 0
local beatPulse = 0 -- 1 right on a beat, fading to 0

local function myCharacter(): (Model?, Humanoid?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if character and humanoid and humanoid.Health > 0 then
		return character, humanoid
	end
	return nil, nil
end

local function nameOf(userId: any): string?
	local other = if typeof(userId) == "number" then Players:GetPlayerByUserId(userId) else nil
	return if other then string.upper(other.DisplayName) else nil
end

local function setHolding(holding: boolean)
	if state.holdingWound == holding then
		return
	end
	state.holdingWound = holding
	if remote then
		remote:FireServer("HoldWound", holding)
	end
end

local function text(parent: Instance, size: UDim2, position: UDim2, textSize: number, font: Enum.Font): TextLabel
	local l = Instance.new("TextLabel")
	l.AnchorPoint = Vector2.new(0.5, 0.5)
	l.Size = size
	l.Position = position
	l.BackgroundTransparency = 1
	l.Font = font
	l.TextSize = textSize
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextStrokeTransparency = 0.5
	l.Parent = parent
	return l
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "DBNO"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Red creeping in from every edge (a gradient strip per side), pulsing with the heartbeat
	vignette = Instance.new("CanvasGroup")
	vignette.Size = UDim2.fromScale(1, 1)
	vignette.BackgroundTransparency = 1
	vignette.Visible = false
	vignette.Parent = gui
	local sides = {
		{ size = UDim2.fromScale(1, 0.35), position = UDim2.fromScale(0, 0), rotation = 90 },
		{ size = UDim2.fromScale(1, 0.35), position = UDim2.fromScale(0, 0.65), rotation = -90 },
		{ size = UDim2.fromScale(0.3, 1), position = UDim2.fromScale(0, 0), rotation = 0 },
		{ size = UDim2.fromScale(0.3, 1), position = UDim2.fromScale(0.7, 0), rotation = 180 },
	}
	for _, side in sides do
		local strip = Instance.new("Frame")
		strip.Size = side.size
		strip.Position = side.position
		strip.BackgroundColor3 = Color3.fromRGB(150, 0, 0)
		strip.BorderSizePixel = 0
		strip.Parent = vignette
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = side.rotation
		gradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.1),
			NumberSequenceKeypoint.new(0.6, 0.85),
			NumberSequenceKeypoint.new(1, 1),
		})
		gradient.Parent = strip
	end

	-- DOWNED, the bleed-out bar and what you can do about it (under the crosshair)
	panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.Position = UDim2.fromScale(0.5, 0.66)
	panel.Size = UDim2.fromOffset(320, 80)
	panel.BackgroundTransparency = 1
	panel.Visible = false
	panel.Parent = gui
	titleLabel = text(panel, UDim2.fromOffset(320, 30), UDim2.fromOffset(160, 14), 26, Enum.Font.GothamBlack)
	titleLabel.Text = "DOWNED"
	titleLabel.TextColor3 = RED
	local bleedBack = Instance.new("Frame")
	bleedBack.AnchorPoint = Vector2.new(0.5, 0.5)
	bleedBack.Position = UDim2.fromOffset(160, 38)
	bleedBack.Size = UDim2.fromOffset(260, 8)
	bleedBack.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
	bleedBack.BackgroundTransparency = 0.2
	bleedBack.BorderSizePixel = 0
	bleedBack.Parent = panel
	bleedFill = Instance.new("Frame")
	bleedFill.Size = UDim2.fromScale(1, 1)
	bleedFill.BackgroundColor3 = RED
	bleedFill.BorderSizePixel = 0
	bleedFill.Parent = bleedBack
	hintLabel = text(panel, UDim2.fromOffset(320, 22), UDim2.fromOffset(160, 62), 16, Enum.Font.GothamBold)

	-- Revive progress: a ring of dots around the crosshair that light up as it goes
	ring = Instance.new("Frame")
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromOffset(RING_RADIUS * 2, RING_RADIUS * 2)
	ring.BackgroundTransparency = 1
	ring.Visible = false
	ring.Parent = gui
	for i = 1, RING_SEGMENTS do
		local angle = (i - 1) / RING_SEGMENTS * math.pi * 2
		local dot = Instance.new("Frame")
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.Size = UDim2.fromOffset(3, 8)
		dot.Position = UDim2.new(0.5, math.sin(angle) * RING_RADIUS, 0.5, -math.cos(angle) * RING_RADIUS)
		dot.Rotation = math.deg(angle)
		dot.BorderSizePixel = 0
		dot.Parent = ring
		ringDots[i] = dot
	end
	ringLabel = text(ring, UDim2.fromOffset(300, 20), UDim2.new(0.5, 0, 1, 16), 15, Enum.Font.GothamBold)
end

-- 0..1 through a revive that finishes at `endsAt` (server time)
local function reviveProgress(endsAt: any): number?
	if typeof(endsAt) ~= "number" then
		return nil
	end
	return math.clamp(1 - (endsAt - Workspace:GetServerTimeNow()) / DBNO.ReviveTime, 0, 1)
end

local function showRing(progress: number?, label: string)
	ring.Visible = progress ~= nil
	if not progress then
		return
	end
	local lit = math.floor(progress * RING_SEGMENTS + 0.5)
	for i, dot in ringDots do
		dot.BackgroundColor3 = if i <= lit then REVIVE_COLOR else Color3.fromRGB(40, 42, 48)
		dot.BackgroundTransparency = if i <= lit then 0 else 0.35
	end
	ringLabel.Text = label
end

-- Your own downed screen: vignette, heartbeat, bleed bar and hint
local function updateSelf(dt: number, character: Model?, humanoid: Humanoid?)
	local downed = character ~= nil and character:GetAttribute("Downed") == true
	if downed ~= state.downed then
		state.downed = downed
		if not downed then
			setHolding(false)
		end
	end
	vignette.Visible = downed
	panel.Visible = downed
	if not downed or not character or not humanoid then
		return
	end
	local pool = math.clamp(humanoid.Health / DBNO.DownHealth, 0, 1)
	bleedFill.Size = UDim2.fromScale(pool, 1)
	local reviver = nameOf(character:GetAttribute("RevivedBy"))
	local key = if state.touchControls then "HOLD WOUND" else "F"
	hintLabel.TextColor3 = if reviver then REVIVE_COLOR else Color3.new(1, 1, 1)
	hintLabel.Text = if reviver then `{reviver} IS REVIVING YOU`
		elseif state.holdingWound then "HOLDING WOUND · BLEEDING SLOWER"
		else `HOLD [{key}] TO HOLD WOUND`

	-- Heartbeat, quicker the less is left; the vignette throbs with it
	local now = os.clock()
	if now >= nextBeat then
		nextBeat = now + BEAT_FAST + (BEAT_SLOW - BEAT_FAST) * pool
		beatPulse = 1
		Effects.Sound(Sounds.Land.Id, nil, BEAT_VOLUME, 0.42)
		task.delay(BEAT_GAP, function()
			if state.downed then
				Effects.Sound(Sounds.Land.Id, nil, BEAT_VOLUME * 0.7, 0.36)
			end
		end)
	end
	beatPulse = math.max(beatPulse - dt * 3, 0)
	vignette.GroupTransparency = VIGNETTE_LOW + (VIGNETTE_HIGH - VIGNETTE_LOW) * beatPulse * (1.2 - pool * 0.4)
end

-- A marker over a downed teammate: a red "+", DOWNED / REVIVING, their bleed bar and distance
local function makeMarker(root: BasePart)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "DownedMarker"
	billboard.Size = UDim2.fromOffset(90, 58)
	billboard.StudsOffset = Vector3.new(0, 2.2, 0)
	billboard.AlwaysOnTop = true -- (through walls, like Siege's downed teammate icon)
	billboard.LightInfluence = 0
	billboard.Adornee = root
	local icon = Instance.new("TextLabel")
	icon.AnchorPoint = Vector2.new(0.5, 0)
	icon.Position = UDim2.fromScale(0.5, 0)
	icon.Size = UDim2.fromOffset(26, 26)
	icon.BackgroundColor3 = RED
	icon.Font = Enum.Font.GothamBlack
	icon.TextSize = 24
	icon.TextColor3 = Color3.new(1, 1, 1)
	icon.Text = "+"
	icon.Parent = billboard
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = icon
	local info = Instance.new("TextLabel")
	info.AnchorPoint = Vector2.new(0.5, 0)
	info.Position = UDim2.new(0.5, 0, 0, 27)
	info.Size = UDim2.fromOffset(90, 16)
	info.BackgroundTransparency = 1
	info.Font = Enum.Font.GothamBold
	info.TextSize = 12
	info.TextColor3 = RED
	info.TextStrokeTransparency = 0.4
	info.Parent = billboard
	local back = Instance.new("Frame")
	back.AnchorPoint = Vector2.new(0.5, 0)
	back.Position = UDim2.new(0.5, 0, 0, 45)
	back.Size = UDim2.fromOffset(50, 4)
	back.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
	back.BorderSizePixel = 0
	back.Parent = billboard
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = RED
	fill.BorderSizePixel = 0
	fill.Parent = back
	billboard.Parent = player.PlayerGui -- (3D markers go straight into PlayerGui)
	return { gui = billboard, info = info, fill = fill }
end

local function updateMarkers()
	local myRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local seen: { [Model]: boolean } = {}
	for _, other in Players:GetPlayers() do
		local character = other.Character
		if other == player or player.Neutral or not player.Team or other.Team ~= player.Team or not character then
			continue
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if character:GetAttribute("Downed") ~= true or not humanoid or humanoid.Health <= 0 or not root then
			continue
		end
		seen[character] = true
		local marker = markers[character] or makeMarker(root)
		markers[character] = marker
		local reviving = character:GetAttribute("RevivedBy") ~= nil
		local distance = if myRoot then `  {math.floor((root.Position - myRoot.Position).Magnitude * 0.28 + 0.5)}m` else ""
		marker.info.Text = (if reviving then "REVIVING" else "DOWNED") .. distance
		marker.info.TextColor3 = if reviving then REVIVE_COLOR else RED
		marker.fill.Size = UDim2.fromScale(math.clamp(humanoid.Health / DBNO.DownHealth, 0, 1), 1)
	end
	for character, marker in markers do
		if not seen[character] then
			marker.gui:Destroy()
			markers[character] = nil
		end
	end
end

local function update(dt: number)
	local character, humanoid = myCharacter()
	updateSelf(dt, character, humanoid)
	updateMarkers()

	-- The revive ring: being picked up, or picking someone up
	if state.downed and character then
		local reviver = nameOf(character:GetAttribute("RevivedBy"))
		showRing(if reviver then reviveProgress(character:GetAttribute("ReviveEndsAt")) else nil, "BEING REVIVED")
	elseif player:GetAttribute("Interaction") == "Revive" then
		showRing(reviveProgress(player:GetAttribute("InteractEndsAt")), "REVIVING...")
	else
		showRing(nil, "")
	end
end

-- The downed teammate you could pick up right now (their root part, for Interact), if any: the
-- closest one within DBNO.ReviveRange that nobody's already reviving
function DBNOController.ReviveTarget(): BasePart?
	local character = myCharacter()
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root or state.downed or player.Neutral or not player.Team or not DBNO.LivePhases[MatchState:GetAttribute("Phase")] then
		return nil
	end
	local best, bestDistance = nil, DBNO.ReviveRange
	for _, other in Players:GetPlayers() do
		local otherCharacter = other.Character
		if other == player or other.Team ~= player.Team or not otherCharacter then
			continue
		end
		local humanoid = otherCharacter:FindFirstChildOfClass("Humanoid")
		local otherRoot = otherCharacter:FindFirstChild("HumanoidRootPart") :: BasePart?
		if otherCharacter:GetAttribute("Downed") ~= true or otherCharacter:GetAttribute("RevivedBy") or not humanoid or humanoid.Health <= 0 or not otherRoot then
			continue
		end
		local distance = (otherRoot.Position - root.Position).Magnitude
		if distance <= bestDistance then
			best, bestDistance = otherRoot, distance
		end
	end
	return best
end

function DBNOController.Start()
	build()

	-- F (R3 on a gamepad, HOLD WOUND on a phone: MobileControls): hold your wound while downed.
	-- Above the knife's binding on the same key, and only while downed (otherwise it passes).
	Actions.BindAtPriority("HoldWound", function(_, inputState)
		if not state.downed then
			setHolding(false)
			return Enum.ContextActionResult.Pass
		end
		setHolding(inputState == Enum.UserInputState.Begin)
		return Enum.ContextActionResult.Sink
	end, Enum.ContextActionPriority.High.Value, Enum.KeyCode.F, Enum.KeyCode.ButtonR3)

	player.CharacterAdded:Connect(function()
		state.downed = false
		state.holdingWound = false
	end)

	-- (DBNOService makes the remote when the server starts)
	task.spawn(function()
		local found = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("DBNO") :: RemoteEvent
		remote = found
		found.OnClientEvent:Connect(function(kind: string, who: Player?, by: Player?)
			if kind == "Downed" and who then
				MatchHud.AddDownedEntry(by, who)
			elseif kind == "Revived" and who and by then
				if who == player then
					Hud.ShowStatus(`REVIVED BY {string.upper(by.DisplayName)}`, 2, REVIVE_COLOR)
				elseif by == player then
					Hud.ShowStatus(`YOU REVIVED {string.upper(who.DisplayName)}`, 2, REVIVE_COLOR)
				end
			end
		end)
	end)

	RunService.RenderStepped:Connect(update)
end

return DBNOController
