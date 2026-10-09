-- Attack / Defend on the client:
--   • Hold G to plant (attackers, inside a site) or defuse (defenders, next to the charge)
--   • "HOLD [G]" prompt + progress bar; you're locked in place while doing it
--   • A / B site markers, and a countdown marker on the planted charge
--   • The charge blinks and beeps faster as it gets close to detonating

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local MatchConfig = require(ReplicatedStorage.Shared.MatchConfig)
local Sounds = require(ReplicatedStorage.Shared.Sounds)
local state = require(script.Parent.Parent.PlayerState)
local Sound3D = require(script.Parent.Parent.Audio.Sound3D)

local MatchState = ReplicatedStorage:WaitForChild("MatchState")
local Interact = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Interact") :: RemoteEvent

local player = Players.LocalPlayer

local ObjectiveController = {}

local SITE_COLOR = Color3.fromRGB(255, 200, 60)
local BOMB_COLOR = Color3.fromRGB(255, 60, 60)
local ACTIVE_PHASES = { Prep = true, Action = true, Planted = true, PostRound = true }

local prompt: TextLabel
local progressBack: Frame
local progressFill: Frame
local siteMarkers: { [BasePart]: BillboardGui } = {}
local siteFloors: { [BasePart]: Model } = {}
local bombMarker: BillboardGui
local bombMarkerText: TextLabel
local bombAnchor: Part
local nextBeep = 0

local function isAttackDefend(): boolean
	return MatchState:GetAttribute("GameMode") == "AttackDefend"
end

local function myRole(): string?
	local attackTeam = MatchState:GetAttribute("AttackTeam")
	if not attackTeam or not player.Team then
		return nil
	end
	return if player.Team.Name == attackTeam then "Attack" else "Defend"
end

local function getSites(): { BasePart }
	local mapRoot = Workspace:FindFirstChild("Map") or Workspace:FindFirstChild("TestArena")
	local folder = mapRoot and mapRoot:FindFirstChild("Objectives")
	local sites = {}
	if folder then
		for _, part in folder:GetChildren() do
			if part:IsA("BasePart") and part:GetAttribute("Site") then
				table.insert(sites, part)
			end
		end
	end
	return sites
end

local function inSite(position: Vector3): boolean
	for _, site in getSites() do
		local localPos = site.CFrame:PointToObjectSpace(position)
		local half = site.Size / 2
		if math.abs(localPos.X) <= half.X and math.abs(localPos.Z) <= half.Z and math.abs(localPos.Y) <= half.Y + 4 then
			return true
		end
	end
	return false
end

local function aliveRoot(): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if humanoid and humanoid.Health > 0 and root then
		return root
	end
	return nil
end

-- What G would do right now ("Plant" / "Defuse"), if anything
local function availableAction(): string?
	local phase = MatchState:GetAttribute("Phase")
	local root = aliveRoot()
	if not isAttackDefend() or not root or root.Anchored then
		return nil
	end
	local role = myRole()
	local bombPosition = MatchState:GetAttribute("BombPosition")
	if role == "Attack" and phase == "Action" and not bombPosition and inSite(root.Position) then
		return "Plant"
	elseif role == "Defend" and phase == "Planted" and bombPosition then
		if (root.Position - bombPosition).Magnitude <= MatchConfig.DefuseRange then
			return "Defuse"
		end
	end
	return nil
end

local function marker(text: string, color: Color3): (BillboardGui, TextLabel)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(44, 44)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(15, 16, 20)
	label.BackgroundTransparency = 0.3
	label.Font = Enum.Font.GothamBlack
	label.TextSize = 22
	label.TextColor3 = color
	label.Text = text
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = label
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = 2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = label
	label.Parent = gui
	return gui, label
end

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Objective"
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")

	prompt = Instance.new("TextLabel")
	prompt.AnchorPoint = Vector2.new(0.5, 0)
	prompt.Position = UDim2.new(0.5, 0, 0.62, 0)
	prompt.Size = UDim2.fromOffset(300, 28)
	prompt.BackgroundTransparency = 1
	prompt.Font = Enum.Font.GothamBold
	prompt.TextSize = 18
	prompt.TextColor3 = Color3.new(1, 1, 1)
	prompt.TextStrokeTransparency = 0.5
	prompt.Visible = false
	prompt.Parent = gui

	progressBack = Instance.new("Frame")
	progressBack.AnchorPoint = Vector2.new(0.5, 0)
	progressBack.Position = UDim2.new(0.5, 0, 0.62, 32)
	progressBack.Size = UDim2.fromOffset(260, 8)
	progressBack.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
	progressBack.BorderSizePixel = 0
	progressBack.Visible = false
	progressBack.Parent = gui
	progressFill = Instance.new("Frame")
	progressFill.Size = UDim2.fromScale(0, 1)
	progressFill.BackgroundColor3 = Color3.new(1, 1, 1)
	progressFill.BorderSizePixel = 0
	progressFill.Parent = progressBack

	-- The bomb marker follows an invisible anchor part placed at the charge
	bombAnchor = Instance.new("Part")
	bombAnchor.Anchored = true
	bombAnchor.CanCollide = false
	bombAnchor.CanQuery = false
	bombAnchor.CanTouch = false
	bombAnchor.Transparency = 1
	bombAnchor.Size = Vector3.one
	bombMarker, bombMarkerText = marker("", BOMB_COLOR)
	bombMarker.Size = UDim2.fromOffset(56, 44)
	bombMarker.StudsOffset = Vector3.new(0, 3, 0)
	bombMarker.Adornee = bombAnchor
	bombMarker.Enabled = false
	-- 3D markers go straight into PlayerGui (they don't draw inside a ScreenGui)
	bombMarker.Parent = player.PlayerGui
end

-- Painted area on the floor showing exactly where you can plant: a faint yellow fill and a
-- glowing border. Local to this client (nobody can collide with or shoot it).
local function buildSiteFloor(site: BasePart): Model
	local model = Instance.new("Model")
	model.Name = "SiteFloor" .. tostring(site:GetAttribute("Site"))
	local floor = site.CFrame * CFrame.new(0, -site.Size.Y / 2 + 0.06, 0)
	local function strip(size: Vector3, offset: CFrame, transparency: number, material: Enum.Material)
		local part = Instance.new("Part")
		part.Size = size
		part.CFrame = floor * offset
		part.Color = SITE_COLOR
		part.Material = material
		part.Transparency = transparency
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Parent = model
	end
	local x, z, w = site.Size.X, site.Size.Z, 0.25
	strip(Vector3.new(x, 0.02, z), CFrame.new(), 0.82, Enum.Material.SmoothPlastic) -- fill
	strip(Vector3.new(x, 0.05, w), CFrame.new(0, 0, -z / 2 + w / 2), 0.15, Enum.Material.Neon) -- border
	strip(Vector3.new(x, 0.05, w), CFrame.new(0, 0, z / 2 - w / 2), 0.15, Enum.Material.Neon)
	strip(Vector3.new(w, 0.05, z), CFrame.new(-x / 2 + w / 2, 0, 0), 0.15, Enum.Material.Neon)
	strip(Vector3.new(w, 0.05, z), CFrame.new(x / 2 - w / 2, 0, 0), 0.15, Enum.Material.Neon)
	return model
end

local function updateSiteMarkers(show: boolean)
	for _, site in getSites() do
		local gui = siteMarkers[site]
		if not gui then
			gui = marker(site:GetAttribute("Site"), SITE_COLOR)
			gui.Adornee = site
			gui.Parent = player.PlayerGui
			siteMarkers[site] = gui
			siteFloors[site] = buildSiteFloor(site)
		end
		gui.Enabled = show
		siteFloors[site].Parent = if show then Workspace.CurrentCamera else nil
	end
	for site, gui in siteMarkers do
		if not site.Parent then
			gui:Destroy()
			siteFloors[site]:Destroy()
			siteMarkers[site] = nil
			siteFloors[site] = nil
		end
	end
end

local function update()
	local phase = MatchState:GetAttribute("Phase")
	local attackDefend = isAttackDefend() and ACTIVE_PHASES[phase] == true
	local bombPosition = MatchState:GetAttribute("BombPosition")
	local now = Workspace:GetServerTimeNow()

	-- Sites are shown the whole time you're in Attack / Defend mode (also between rounds, so
	-- everyone can learn where they are), until the charge is planted
	updateSiteMarkers(isAttackDefend() and not bombPosition)

	-- Planted charge: marker with countdown, blinking light, beeps that speed up
	if attackDefend and bombPosition then
		local remaining = (MatchState:GetAttribute("DetonateAt") or now) - now
		bombAnchor.Position = bombPosition
		bombAnchor.Parent = Workspace.CurrentCamera
		bombMarker.Enabled = true
		bombMarkerText.Text = tostring(math.max(0, math.ceil(remaining)))

		local interval = math.clamp(remaining / MatchConfig.FuseTime, 0.12, 1)
		local charge = Workspace:FindFirstChild("Charge")
		local light = charge and charge:FindFirstChild("Light") :: BasePart?
		if light then
			light.Transparency = if (now % interval) < interval / 2 then 0 else 0.8
		end
		if now >= nextBeep and remaining > 0 then
			nextBeep = now + interval
			Sound3D.Play(Sounds.ChargeBeep.Id, bombPosition, { volume = Sounds.ChargeBeep.Volume, range = Sounds.ChargeBeep.Range })
		end
	else
		bombMarker.Enabled = false
		bombAnchor.Parent = nil
	end

	-- Plant / defuse in progress: progress bar, and locked in place
	local interaction = player:GetAttribute("Interaction")
	local endsAt = player:GetAttribute("InteractEndsAt")
	state.interacting = interaction ~= nil
	if interaction and endsAt then
		local duration = if interaction == "Plant" then MatchConfig.PlantTime else MatchConfig.DefuseTime
		progressBack.Visible = true
		progressFill.Size = UDim2.fromScale(math.clamp(1 - (endsAt - now) / duration, 0, 1), 1)
		progressFill.BackgroundColor3 = if interaction == "Plant" then BOMB_COLOR else Color3.fromRGB(90, 170, 255)
		prompt.Visible = true
		prompt.Text = if interaction == "Plant" then "PLANTING..." else "DEFUSING..."
		return
	end
	progressBack.Visible = false

	local action = availableAction()
	prompt.Visible = action ~= nil
	if action then
		prompt.Text = `HOLD [G] TO {string.upper(action)}`
	end
end

function ObjectiveController.Start()
	build()

	ContextActionService:BindAction("Interact", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			if availableAction() and not (state.devPanelOpen or state.mouseUnlocked or state.deploying) then
				Interact:FireServer("Begin")
			end
		else
			Interact:FireServer("End")
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.G, Enum.KeyCode.ButtonY)

	RunService.RenderStepped:Connect(update)
end

return ObjectiveController
