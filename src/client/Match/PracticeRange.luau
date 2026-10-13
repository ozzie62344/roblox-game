-- The lobby's practice range on your side (server PracticeRange / PracticeBots). Standing inside
-- its "Zone" box (lobby servers only) sets state.inPractice, which LobbyView turns into "not in
-- the lobby": first person, gun out, combat HUD, shooting. Walk back out and you're in the lobby
-- again. Here: the "PRACTICE RANGE · shoot the bots" hint with your kills / headshots / accuracy
-- (counted on this client, just for you), and the bots' shots: tracer, muzzle flash, gunshot.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Sounds = require(ReplicatedStorage.Shared.Sounds)
local Weapons = require(ReplicatedStorage.Shared.Weapons)
local Sound3D = require(script.Parent.Parent.Audio.Sound3D)
local Effects = require(script.Parent.Parent.Combat.Effects)
local state = require(script.Parent.Parent.PlayerState)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local HitConfirmed = Remotes:WaitForChild("HitConfirmed") :: RemoteEvent

local player = Players.LocalPlayer

local PracticeRange = {}

local ACCENT = Color3.fromRGB(255, 170, 60)
local BOT_SHOT_RANGE = 160 -- how far the bots' gunshots carry (quieter than a player's)
local DOWNED_TIME = 2.5 -- seconds the "downed" line stays up

local stats = { shots = 0, hits = 0, kills = 0, headshots = 0 }
local lastShotSeen = state.lastShot
local gui: ScreenGui
local statsLabel: TextLabel
local downedLabel: TextLabel
local downedToken = 0

-- In the lobby, alive and inside the range's zone
local function isInside(): boolean
	if player:GetAttribute("Location") ~= "Lobby" or state.spectating then
		return false
	end
	local range = Workspace:FindFirstChild("PracticeRange")
	local zone = range and range:FindFirstChild("Zone") :: BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not zone or not humanoid or humanoid.Health <= 0 or not root then
		return false
	end
	local p = zone.CFrame:PointToObjectSpace(root.Position)
	local half = zone.Size / 2
	return math.abs(p.X) <= half.X and math.abs(p.Y) <= half.Y and math.abs(p.Z) <= half.Z
end

local function updateStats()
	-- (a shotgun blast that hits two bots confirms twice: never over 100%)
	local accuracy = if stats.shots > 0 then `{math.floor(math.min(stats.hits, stats.shots) / stats.shots * 100 + 0.5)}%` else "—"
	statsLabel.Text = `KILLS {stats.kills}    HEADSHOTS {stats.headshots}    ACCURACY {accuracy}`
end

local function update()
	state.inPractice = isInside()
	gui.Enabled = state.inPractice
	-- Your gun sets state.lastShot each time it fires (at most once a frame)
	if state.lastShot ~= lastShotSeen then
		lastShotSeen = state.lastShot
		if state.inPractice then
			stats.shots += 1
			updateStats()
		end
	end
end

-- A bot's shot: flash at its gun, a tracer, a spark where it landed (not on you), the gunshot
local function onBotShot(origin: Vector3, endPosition: Vector3, hitPlayer: boolean)
	Effects.Tracer(origin, endPosition)
	if not hitPlayer then
		Effects.Impact(endPosition)
	end
	local flash = Instance.new("Part")
	flash.Anchored = true
	flash.CanCollide = false
	flash.CanQuery = false
	flash.CanTouch = false
	flash.CastShadow = false
	flash.Material = Enum.Material.Neon
	flash.Color = Color3.fromRGB(255, 210, 120)
	flash.Shape = Enum.PartType.Ball
	flash.Size = Vector3.new(0.5, 0.5, 0.5)
	flash.CFrame = CFrame.new(origin)
	local light = Instance.new("PointLight")
	light.Color = flash.Color
	light.Range = 8
	light.Brightness = 3
	light.Parent = flash
	flash.Parent = Effects.GetFolder()
	Debris:AddItem(flash, 0.05)
	Sound3D.Play(Sounds.Pick(Weapons.Rifle.FireSound), origin, {
		volume = Sounds.Guns.OtherVolume * 0.7,
		range = BOT_SHOT_RANGE,
		pitch = 1.08,
	})
end

local function onDowned()
	downedToken += 1
	local token = downedToken
	downedLabel.Visible = true
	task.delay(DOWNED_TIME, function()
		if token == downedToken then
			downedLabel.Visible = false
		end
	end)
end

local function makeGui()
	gui = Instance.new("ScreenGui")
	gui.Name = "PracticeHud"
	gui.ResetOnSpawn = false
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.Position = UDim2.new(0.5, 0, 0, 10)
	panel.Size = UDim2.fromOffset(380, 56)
	panel.BackgroundColor3 = Color3.fromRGB(14, 16, 20)
	panel.BackgroundTransparency = 0.35
	panel.BorderSizePixel = 0
	panel.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = panel
	local rim = Instance.new("UIStroke")
	rim.Color = ACCENT
	rim.Transparency = 0.5
	rim.Parent = panel

	local function label(y: number, height: number, font: Enum.Font, size: number): TextLabel
		local l = Instance.new("TextLabel")
		l.Position = UDim2.new(0, 0, 0, y)
		l.Size = UDim2.new(1, 0, 0, height)
		l.BackgroundTransparency = 1
		l.Font = font
		l.TextSize = size
		l.TextColor3 = Color3.new(1, 1, 1)
		l.TextStrokeTransparency = 0.6
		l.Parent = panel
		return l
	end
	local title = label(6, 22, Enum.Font.GothamBold, 16)
	title.RichText = true
	title.Text = `<font color="#FFAA3C">PRACTICE RANGE</font> · shoot the bots`
	statsLabel = label(30, 18, Enum.Font.GothamMedium, 13)
	statsLabel.TextColor3 = Color3.fromRGB(200, 204, 214)
	updateStats()

	downedLabel = Instance.new("TextLabel")
	downedLabel.AnchorPoint = Vector2.new(0.5, 0)
	downedLabel.Position = UDim2.new(0.5, 0, 0, 74)
	downedLabel.Size = UDim2.fromOffset(380, 24)
	downedLabel.BackgroundTransparency = 1
	downedLabel.Font = Enum.Font.GothamBold
	downedLabel.TextSize = 18
	downedLabel.TextColor3 = Color3.fromRGB(255, 90, 80)
	downedLabel.TextStrokeTransparency = 0.5
	downedLabel.Text = "DOWNED · back to the entrance"
	downedLabel.Visible = false
	downedLabel.Parent = gui
end

function PracticeRange.Start()
	makeGui()
	RunService.RenderStepped:Connect(update)

	-- Hits, headshots and kills on the bots (in the lobby nobody else can be hit). Knife hits
	-- aren't shots, so they only count as kills.
	HitConfirmed.OnClientEvent:Connect(function(_damage: number, headshot: boolean, killed: boolean)
		if not state.inPractice then
			return
		end
		if not state.meleeing then
			stats.hits += 1
			stats.headshots += if headshot then 1 else 0
		end
		stats.kills += if killed then 1 else 0
		updateStats()
	end)

	-- (made by the server at start; waited for off the main thread so nothing else is held up)
	task.spawn(function()
		local remote = Remotes:WaitForChild("Practice") :: RemoteEvent
		remote.OnClientEvent:Connect(function(kind: string, ...)
			if kind == "Shot" then
				onBotShot(...)
			elseif kind == "Downed" then
				onDowned()
			end
		end)
	end)
end

return PracticeRange
