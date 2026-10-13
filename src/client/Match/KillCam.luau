-- KILL CAM: when you die, a few seconds on whoever killed you before spectating (Spectate takes
-- over after). The camera sits just behind the killer's head looking at where you died (zoomed in
-- when that's far), and follows them as they move; they and your body are outlined. A card says
-- who it was, their gun (and its skin), how far away they were, headshot or not, and the health
-- they had left.
-- Click / tap anywhere, SPACE or SKIP ends it early. Killed by an explosion, by yourself or by
-- nobody (a fall): just the card, while Spectate shows your body.
-- RoundService sends the details with the kill feed (its 4th argument, MatchStats.KillDetails); if
-- they never come, the card says what your humanoid knows (LastDamagedBy / LastHitWith).
-- state.killCam: "View" while this drives the camera, "Card" while only the card is up. The
-- camera always goes back to Roblox's (Custom) when it ends: time up, skipped, respawned, in your
-- drone / on the cameras, or the match results came up.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local state = require(script.Parent.Parent.PlayerState)
local MenuStyle = require(script.Parent.MenuStyle)

local KillFeed = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("KillFeed") :: RemoteEvent

local player = Players.LocalPlayer

local KillCam = {}

local VIEW_TIME = 3.5 -- seconds on the killer
local CARD_TIME = 2.5 -- seconds of the card alone (nobody to show)
local DETAILS_WAIT = 1 -- seconds to wait for the server's details before the card makes do
local SKIP_GRACE = 0.6 -- clicks this soon after dying don't skip (you were probably still shooting)
local SHOULDER = Vector3.new(1.4, 1.1, 3.5) -- camera from the killer's head: right, up, back
local ZOOM_HEIGHT = 16 -- studs of the scene around your body the zoom fits on screen
local MIN_FOV, MAX_FOV = 12, 70
local ZOOM_TIME = 0.8 -- seconds to zoom in on where you died
local RED = Color3.fromRGB(255, 90, 80)
local GREY = Color3.fromRGB(190, 195, 205)

type Details = { [string]: any }
type Cam = {
	character: Model,
	startedAt: number,
	killer: Player?,
	headshot: boolean,
	details: Details?,
	view: boolean,
	from: Vector3?, -- the killer's head (last seen)
	skipped: boolean,
	highlights: { Highlight },
}

local current: Cam? = nil
local card: Frame
local accent: Frame
local titleLabel: TextLabel
local nameLabel: TextLabel
local weaponLabel: TextLabel
local infoLabel: TextLabel
local headshotTag: Frame
local hintLabel: TextLabel
local timeFill: Frame

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function teamColor(p: Player?): Color3
	return if p and p.Team then p.Team.TeamColor.Color else RED
end

-- "RIFLE · CRIMSON TIDE", "KNIFE", "EXPLOSION"
local function withText(with: string?, skin: string?): string
	if with == "Blast" then
		return "EXPLOSION"
	elseif not with then
		return ""
	end
	return if skin then `{string.upper(with)}  ·  {string.upper(skin)}` else string.upper(with)
end

local function fillCard(cam: Cam)
	local details = cam.details or {}
	local killer = cam.killer
	accent.BackgroundColor3 = teamColor(killer)
	headshotTag.Visible = false
	if killer and killer ~= player then
		titleLabel.Text = "KILLED BY"
		nameLabel.Text = string.upper(killer.DisplayName)
		nameLabel.TextColor3 = teamColor(killer)
		weaponLabel.Text = withText(details.with, details.skin)
		local bits = {}
		if typeof(details.distance) == "number" then
			table.insert(bits, `{details.distance} STUDS AWAY`)
		end
		if typeof(details.health) == "number" then
			table.insert(bits, if details.health > 0 then `{details.health} HP LEFT` else "THEY'RE DOWN TOO")
		end
		infoLabel.Text = table.concat(bits, "   ·   ")
		headshotTag.Visible = cam.headshot
	else
		titleLabel.Text = "ELIMINATED"
		nameLabel.Text = if killer == player then (if details.with == "Blast" then "YOUR OWN EXPLOSION" else "SELF-INFLICTED") else "YOU DIED"
		nameLabel.TextColor3 = RED
		weaponLabel.Text = ""
		infoLabel.Text = ""
	end
end

local function outline(cam: Cam, model: Model?, color: Color3)
	if not model then
		return
	end
	local highlight = Instance.new("Highlight")
	highlight.Name = "KillCamHighlight"
	highlight.FillColor = color
	highlight.FillTransparency = 0.8
	highlight.OutlineColor = color
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop -- (seen through the wall they shot through)
	highlight.Adornee = model
	highlight.Parent = model
	table.insert(cam.highlights, highlight)
end

-- Where you died: your body while it's there, otherwise where the server said
local function deathSpot(cam: Cam): Vector3?
	local root = cam.character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root and root.Parent then
		return root.Position
	end
	local details = cam.details
	return if details and typeof(details.at) == "Vector3" then details.at else nil
end

local function finish()
	local cam = current
	if not cam then
		return
	end
	current = nil
	state.killCam = nil
	card.Visible = false
	for _, highlight in cam.highlights do
		highlight:Destroy()
	end
	if cam.view then
		-- Back to Roblox's camera (Spectate picks who it follows next; CameraEffects resets the FOV)
		local camera = Workspace.CurrentCamera
		camera.CameraType = Enum.CameraType.Custom
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			camera.CameraSubject = humanoid
		end
	end
end

-- The kill cam for this body (one per death: the kill feed and Died can come in either order)
local function begin(character: Model): Cam
	if current and current.character == character then
		return current
	end
	finish()
	local cam: Cam = {
		character = character,
		startedAt = os.clock(),
		killer = nil,
		headshot = false,
		details = nil,
		view = false,
		from = nil,
		skipped = false,
		highlights = {},
	}
	current = cam
	state.killCam = "Card"
	hintLabel.Text = if state.touchControls then "TAP TO SKIP" else "CLICK / SPACE"
	fillCard(cam)
	card.Visible = true
	return cam
end

-- Who killed us is known: fill in the card, and show them if there's someone to show (not for
-- explosions: the one who set it off may be anywhere, looking anywhere)
local function setKiller(cam: Cam, killer: Player?, headshot: boolean, details: Details?)
	cam.killer = killer
	cam.headshot = headshot
	cam.details = details
	fillCard(cam)
	local from = details and details.from
	local canView = killer ~= nil and killer ~= player and typeof(from) == "Vector3"
		and details ~= nil and details.with ~= "Blast" and deathSpot(cam) ~= nil
	if canView and not cam.view and not state.droning and not state.resultsOpen then
		cam.view = true
		cam.from = from
		state.killCam = "View"
		outline(cam, (killer :: Player).Character, RED)
		outline(cam, cam.character, Color3.new(1, 1, 1))
	end
end

-- Behind the killer's head, a little to the right and up, looking at where you died; pulled in
-- if a wall is in the way, zoomed in so your body isn't a speck
local function drive(cam: Cam)
	local killerCharacter = cam.killer and cam.killer.Character
	local head = killerCharacter and killerCharacter:FindFirstChild("Head") :: BasePart?
	if head and head.Parent then
		cam.from = head.Position
	end
	local from, at = cam.from, deathSpot(cam)
	if not from or not at then
		return
	end
	local look = at - from
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.zAxis
	local right = flat:Cross(Vector3.yAxis)
	local wanted = from + right * SHOULDER.X + Vector3.yAxis * SHOULDER.Y - flat * SHOULDER.Z
	local ignore: { Instance } = { cam.character, Workspace.CurrentCamera }
	if killerCharacter then
		table.insert(ignore, killerCharacter)
	end
	rayParams.FilterDescendantsInstances = ignore
	local offset = wanted - from
	local hit = Workspace:Raycast(from, offset, rayParams)
	local position = if hit then from + offset.Unit * math.max(hit.Distance - 0.4, 0.2) else wanted

	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable -- every frame, in case anything else reset it
	camera.CFrame = CFrame.lookAt(position, at)
	local distance = math.max((at - position).Magnitude, 1)
	local zoomed = math.clamp(math.deg(2 * math.atan(ZOOM_HEIGHT / 2 / distance)), MIN_FOV, MAX_FOV)
	local t = math.clamp((os.clock() - cam.startedAt) / ZOOM_TIME, 0, 1)
	camera.FieldOfView = MAX_FOV + (zoomed - MAX_FOV) * t * t * (3 - 2 * t)
end

local function update()
	local cam = current
	if not cam then
		return
	end
	-- (checked before anything else each frame, so the camera can't get stuck here)
	local length = if cam.view then VIEW_TIME else CARD_TIME
	local elapsed = os.clock() - cam.startedAt
	if elapsed >= length or cam.skipped or player.Character ~= cam.character or state.droning or state.resultsOpen then
		finish()
		return
	end
	timeFill.Size = UDim2.fromScale(1 - elapsed / length, 1)
	if cam.view then
		drive(cam)
	end
end

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "KillCam"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 3 -- over the HUD, under the menus
	gui.Parent = player:WaitForChild("PlayerGui")

	card = Instance.new("Frame")
	card.AnchorPoint = Vector2.new(0.5, 1)
	card.Position = UDim2.new(0.5, 0, 1, -24)
	card.Size = UDim2.fromOffset(540, 150)
	card.BackgroundColor3 = MenuStyle.Panel
	card.BackgroundTransparency = 0.1
	card.Visible = false
	card.Parent = gui
	MenuStyle.Corner(card, UDim.new(0, 14))
	MenuStyle.Rim(card, Color3.fromRGB(60, 64, 76), 2)
	MenuStyle.FitToScreen(card, Vector2.new(540, 150))

	accent = Instance.new("Frame")
	accent.Position = UDim2.fromOffset(10, 14)
	accent.Size = UDim2.new(0, 6, 1, -28)
	accent.BorderSizePixel = 0
	accent.Parent = card
	MenuStyle.Corner(accent, UDim.new(1, 0))

	local function line(y: number, height: number, color: Color3): TextLabel
		local label = MenuStyle.Text(card, "", UDim2.fromOffset(360, height), UDim2.fromOffset(28, y))
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextColor3 = color
		return label
	end
	titleLabel = line(12, 20, GREY)
	nameLabel = line(34, 40, Color3.new(1, 1, 1))
	weaponLabel = line(80, 24, Color3.new(1, 1, 1))
	infoLabel = line(108, 20, GREY)

	headshotTag = Instance.new("Frame")
	headshotTag.AnchorPoint = Vector2.new(1, 0)
	headshotTag.Position = UDim2.new(1, -16, 0, 14)
	headshotTag.Size = UDim2.fromOffset(130, 30)
	headshotTag.BackgroundColor3 = MenuStyle.Red
	headshotTag.Visible = false
	headshotTag.Parent = card
	MenuStyle.Corner(headshotTag, UDim.new(0, 8))
	MenuStyle.Text(headshotTag, "HEADSHOT", UDim2.fromScale(0.86, 0.7), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))

	hintLabel = MenuStyle.Text(card, "", UDim2.fromOffset(130, 16), UDim2.new(1, -16, 1, -80), Vector2.new(1, 1))
	hintLabel.TextColor3 = GREY
	local skip = MenuStyle.Button(card, "SKIP", MenuStyle.Grey, UDim2.fromOffset(130, 56), UDim2.new(1, -16, 1, -16), Vector2.new(1, 1))
	skip.Activated:Connect(function()
		if current then
			current.skipped = true
		end
	end)

	-- How long until it moves on
	local timeBar = Instance.new("Frame")
	timeBar.AnchorPoint = Vector2.new(0.5, 1)
	timeBar.Position = UDim2.new(0.5, 0, 1, -4)
	timeBar.Size = UDim2.new(1, -28, 0, 3)
	timeBar.BackgroundTransparency = 1
	timeBar.Parent = card
	timeFill = Instance.new("Frame")
	timeFill.Size = UDim2.fromScale(1, 1)
	timeFill.BackgroundColor3 = Color3.new(1, 1, 1)
	timeFill.BackgroundTransparency = 0.3
	timeFill.BorderSizePixel = 0
	timeFill.Parent = timeBar
end

function KillCam.Start()
	build()

	local function watchCharacter(character: Model)
		local humanoid = character:WaitForChild("Humanoid") :: Humanoid
		humanoid.Died:Connect(function()
			local cam = begin(character)
			-- No details from the server yet: make do with what this humanoid knows
			task.delay(DETAILS_WAIT, function()
				if current == cam and not cam.details then
					local killerId = humanoid:GetAttribute("LastDamagedBy")
					local with = humanoid:GetAttribute("LastHitWith")
					cam.killer = if typeof(killerId) == "number" then Players:GetPlayerByUserId(killerId) else nil
					cam.headshot = humanoid:GetAttribute("LastHitHeadshot") == true
					cam.details = { with = if typeof(with) == "string" then with else nil }
					fillCard(cam)
				end
			end)
		end)
	end
	if player.Character then
		task.spawn(watchCharacter, player.Character)
	end
	player.CharacterAdded:Connect(watchCharacter)

	KillFeed.OnClientEvent:Connect(function(killer: Player?, victim: Player, headshot: boolean, details: Details?)
		local character = player.Character
		if victim ~= player or not character or typeof(details) ~= "table" then
			return
		end
		local cam = begin(character)
		if not cam.details or not cam.view then
			setKiller(cam, killer, headshot == true, details)
		end
	end)

	UserInputService.InputBegan:Connect(function(input)
		local cam = current
		if not cam or os.clock() - cam.startedAt < SKIP_GRACE then
			return
		end
		local kind, key = input.UserInputType, input.KeyCode
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch
			or key == Enum.KeyCode.Space or key == Enum.KeyCode.Return or key == Enum.KeyCode.ButtonA then
			cam.skipped = true
		end
	end)

	-- After the camera, its effects (Camera + 2), the hands (Camera + 4) and the drone / cameras
	-- (Camera + 5, which end the kill cam anyway)
	RunService:BindToRenderStep("KillCam", Enum.RenderPriority.Camera.Value + 6, update)
end

return KillCam
