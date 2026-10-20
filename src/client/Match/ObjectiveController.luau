-- Attack / Defend on the client:
--   • Hold G to plant the defuser (the attacker carrying it, inside a bomb site) or disable it
--     (defenders, next to it); a "D" marker shows attackers where a dead carrier dropped it
--   • "HOLD [G]" prompt + progress bar; you're locked in place while doing it
--   • A / B site markers (only the defended pair's, on maps with several), and a countdown
--     marker on the planted defuser
--   • The defuser blinks and beeps faster as it gets close to defusing the bomb
--   • Hold G next to a downed teammate to revive them (DBNOController finds them and draws the
--     revive ring instead of the progress bar); downed, G does nothing

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local DBNO = require(ReplicatedStorage.Shared.DBNO)
local MatchConfig = require(ReplicatedStorage.Shared.MatchConfig)
local Sounds = require(ReplicatedStorage.Shared.Sounds)
local state = require(script.Parent.Parent.PlayerState)
local Sound3D = require(script.Parent.Parent.Audio.Sound3D)
local Actions = require(script.Parent.Parent.Input.Actions)
local DBNOController = require(script.Parent.DBNOController)

local MatchState = ReplicatedStorage:WaitForChild("MatchState")
local Interact = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Interact") :: RemoteEvent

local player = Players.LocalPlayer

local ObjectiveController = {}

local SITE_COLOR = Color3.fromRGB(255, 200, 60)
local DEFUSER_COLOR = Color3.fromRGB(255, 60, 60)
local ACTIVE_PHASES = { Prep = true, Action = true, Planted = true, PostRound = true }
local BUILD_PHASES = { Prep = true, Action = true, Planted = true } -- when defenders can barricade
local BARRICADE_REACH = 7 -- studs from your eyes to the middle of the doorway / window
local INTERACTIONS = {
	Plant = { time = MatchConfig.PlantTime, label = "PLANTING DEFUSER...", prompt = "PLANT THE DEFUSER", color = Color3.fromRGB(255, 60, 60) },
	Disable = { time = MatchConfig.DisableTime, label = "DISABLING DEFUSER...", prompt = "DISABLE THE DEFUSER", color = Color3.fromRGB(90, 170, 255) },
	Barricade = { time = MatchConfig.BarricadeTime, label = "BARRICADING...", prompt = "BARRICADE", color = Color3.fromRGB(200, 150, 90) },
	Unbarricade = { time = MatchConfig.UnbarricadeTime, label = "TAKING IT DOWN...", prompt = "TAKE DOWN THE BARRICADE", color = Color3.fromRGB(200, 150, 90) },
	Reinforce = { time = MatchConfig.ReinforceTime, label = "REINFORCING...", prompt = "REINFORCE", color = Color3.fromRGB(150, 160, 175) },
	Revive = { time = DBNO.ReviveTime, label = "REVIVING...", prompt = "REVIVE YOUR TEAMMATE", color = Color3.fromRGB(90, 220, 120) },
}

local prompt: TextLabel
local progressBack: Frame
local progressFill: Frame
local siteMarkers: { [BasePart]: BillboardGui } = {}
local siteFloors: { [BasePart]: Model } = {}
local defuserMarker: BillboardGui
local defuserMarkerText: TextLabel
local defuserAnchor: Part
local droppedMarker: BillboardGui -- attackers: where the dead carrier dropped the defuser
local droppedAnchor: Part
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

-- Maps with several site pairs: only the pair the defenders picked ("SitePair") is in play, and
-- attackers don't see which until a drone (or one of them) finds it ("SiteFound", DroneService).
-- Between matches every site shows.
-- shortcut: the pick is a public MatchState attribute, so a cheater could read it early; send it
-- only to defenders if that ever matters
local function isActiveSite(site: BasePart): boolean
	local pair = site:GetAttribute("Pair")
	local picked = MatchState:GetAttribute("SitePair")
	if pair == nil or picked == nil then
		return true
	end
	if myRole() == "Attack" and not MatchState:GetAttribute("SiteFound") then
		return false
	end
	return pair == picked
end

local function inSite(position: Vector3): boolean
	for _, site in getSites() do
		if not isActiveSite(site) then
			continue
		end
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

-- The empty doorway / window you're looking at, close enough to board up (BarricadeService)
local function barricadeSlot(): BasePart?
	local map = Workspace:FindFirstChild("Map")
	local slots = map and map:FindFirstChild("BarricadeSlots")
	if not slots then
		return nil
	end
	local camera = Workspace.CurrentCamera.CFrame
	local best, bestDot = nil, 0.6
	for _, slot in slots:GetChildren() do
		if slot:IsA("BasePart") and slot.Name == "Slot" and not slot:GetAttribute("Built") then
			local offset = slot.Position - camera.Position
			local dot = offset.Unit:Dot(camera.LookVector)
			if offset.Magnitude <= BARRICADE_REACH and dot > bestDot then
				best, bestDot = slot, dot
			end
		end
	end
	return best
end

-- The barricade you're looking at (close enough to pull down): its doorway / window slot
local function builtBarricade(): BasePart?
	local map = Workspace:FindFirstChild("Map")
	local slots = map and map:FindFirstChild("BarricadeSlots")
	if not slots then
		return nil
	end
	local camera = Workspace.CurrentCamera.CFrame
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character :: Model, Workspace.CurrentCamera }
	local result = Workspace:Raycast(camera.Position, camera.LookVector * BARRICADE_REACH, params)
	if not result or result.Instance:GetAttribute("Breakable") ~= "Barricade" then
		return nil
	end
	for _, slot in slots:GetChildren() do
		if slot:IsA("BasePart") and slot.Name == "Slot" and slot:GetAttribute("Built") then
			local localHit = slot.CFrame:PointToObjectSpace(result.Position)
			local half = slot.Size / 2 + Vector3.one * 0.3
			if math.abs(localHit.X) <= half.X and math.abs(localHit.Y) <= half.Y and math.abs(localHit.Z) <= half.Z then
				return slot
			end
		end
	end
	return nil
end

-- The wall section or hatch you're looking at, if it can still be reinforced (FortifyService)
local function reinforceSlot(): BasePart?
	local map = Workspace:FindFirstChild("Map")
	local slots = map and map:FindFirstChild("ReinforceSlots")
	if not slots or (not player.Neutral and (MatchState:GetAttribute("Reinforcements") or 0) <= 0) then
		return nil
	end
	local camera = Workspace.CurrentCamera.CFrame
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character :: Model, Workspace.CurrentCamera }
	local result = Workspace:Raycast(camera.Position, camera.LookVector * BARRICADE_REACH, params)
	local kind = result and result.Instance:GetAttribute("Breakable")
	if kind ~= "Soft" and kind ~= "Hatch" then
		return nil
	end
	for _, slot in slots:GetChildren() do
		if slot:IsA("BasePart") and not slot:GetAttribute("Built") and not slot:GetAttribute("Breached") then
			local localHit = slot.CFrame:PointToObjectSpace(result.Position)
			local half = slot.Size / 2
			if math.abs(localHit.X) <= half.X and math.abs(localHit.Y) <= half.Y and math.abs(localHit.Z) <= half.Z then
				return slot
			end
		end
	end
	return nil
end

-- What G would do right now ("Plant" / "Disable" / "Reinforce" / "Barricade" / "Unbarricade"), if anything, and
-- the wall section / doorway it's for
local function teammatePlanting(): boolean
	for _, other in Players:GetPlayers() do
		if other ~= player and other:GetAttribute("Interaction") == "Plant" then
			return true
		end
	end
	return false
end

local function availableAction(): (string?, BasePart?)
	local phase = MatchState:GetAttribute("Phase")
	local root = aliveRoot()
	if not root or root.Anchored or state.droning or state.downed then
		return nil, nil
	end
	-- A downed teammate next to you: pick them up first
	local downedRoot = DBNOController.ReviveTarget()
	if downedRoot then
		return "Revive", downedRoot
	end
	local role = myRole()
	local defuserPosition = MatchState:GetAttribute("DefuserPosition")
	if isAttackDefend() then
		-- (only the attacker carrying the defuser can plant it, ObjectiveService)
		if role == "Attack" and phase == "Action" and player:GetAttribute("HasDefuser") and not defuserPosition and inSite(root.Position) and not teammatePlanting() then
			return "Plant", nil
		elseif role == "Defend" and phase == "Planted" and defuserPosition then
			if (root.Position - defuserPosition).Magnitude <= MatchConfig.DisableRange then
				return "Disable", nil
			end
		end
	end
	-- Defenders reinforce walls and barricade doorways (anyone can while free roaming, to try it).
	-- Looking at a wall means reinforce; looking through an empty doorway means barricade.
	if player.Neutral or (role == "Defend" and BUILD_PHASES[phase]) then
		local wall = reinforceSlot()
		if wall then
			return "Reinforce", wall
		end
		local slot = barricadeSlot()
		if slot then
			return "Barricade", slot
		end
		local boarded = builtBarricade()
		if boarded then
			return "Unbarricade", boarded
		end
	end
	return nil, nil
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

	-- The countdown marker follows an invisible anchor part placed at the defuser
	defuserAnchor = Instance.new("Part")
	defuserAnchor.Anchored = true
	defuserAnchor.CanCollide = false
	defuserAnchor.CanQuery = false
	defuserAnchor.CanTouch = false
	defuserAnchor.Transparency = 1
	defuserAnchor.Size = Vector3.one
	defuserMarker, defuserMarkerText = marker("", DEFUSER_COLOR)
	defuserMarker.Size = UDim2.fromOffset(56, 44)
	defuserMarker.StudsOffset = Vector3.new(0, 3, 0)
	defuserMarker.Adornee = defuserAnchor
	defuserMarker.Enabled = false
	-- 3D markers go straight into PlayerGui (they don't draw inside a ScreenGui)
	defuserMarker.Parent = player.PlayerGui

	droppedAnchor = defuserAnchor:Clone()
	local droppedText
	droppedMarker, droppedText = marker("D", Color3.fromRGB(255, 150, 60))
	droppedText.TextSize = 18
	droppedMarker.Size = UDim2.fromOffset(36, 36)
	droppedMarker.StudsOffset = Vector3.new(0, 2, 0)
	droppedMarker.Adornee = droppedAnchor
	droppedMarker.Enabled = false
	droppedMarker.Parent = player.PlayerGui
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
		local visible = show and isActiveSite(site)
		gui.Enabled = visible
		siteFloors[site].Parent = if visible then Workspace.CurrentCamera else nil
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
	local defuserPosition = MatchState:GetAttribute("DefuserPosition")
	local now = Workspace:GetServerTimeNow()

	-- Sites are shown the whole time you're in Attack / Defend mode (also between rounds, so
	-- everyone can learn where they are), until the defuser is planted
	updateSiteMarkers(isAttackDefend() and not defuserPosition)

	-- Planted defuser: marker with countdown, blinking light, beeps that speed up
	if attackDefend and defuserPosition then
		local remaining = (MatchState:GetAttribute("DefusedAt") or now) - now
		defuserAnchor.Position = defuserPosition
		defuserAnchor.Parent = Workspace.CurrentCamera
		defuserMarker.Enabled = true
		defuserMarkerText.Text = tostring(math.max(0, math.ceil(remaining)))

		local interval = math.clamp(remaining / MatchConfig.DefuserTime, 0.12, 1)
		local defuser = Workspace:FindFirstChild("Defuser")
		local light = defuser and defuser:FindFirstChild("Light") :: BasePart?
		if light then
			light.Transparency = if (now % interval) < interval / 2 then 0 else 0.8
		end
		if now >= nextBeep and remaining > 0 then
			nextBeep = now + interval
			Sound3D.Play(Sounds.ChargeBeep.Id, defuserPosition, { volume = Sounds.ChargeBeep.Volume, range = Sounds.ChargeBeep.Range })
		end
	else
		defuserMarker.Enabled = false
		defuserAnchor.Parent = nil
	end

	-- Dropped defuser (its carrier died): attackers see where to pick it up
	local droppedAt = MatchState:GetAttribute("DefuserDropped")
	if attackDefend and droppedAt and myRole() == "Attack" then
		droppedAnchor.Position = droppedAt
		droppedAnchor.Parent = Workspace.CurrentCamera
		droppedMarker.Enabled = true
	else
		droppedMarker.Enabled = false
		droppedAnchor.Parent = nil
	end

	-- Plant / disable / barricade in progress: progress bar, and locked in place
	local interaction = player:GetAttribute("Interaction")
	local endsAt = player:GetAttribute("InteractEndsAt")
	state.interacting = interaction ~= nil
	local info = interaction and INTERACTIONS[interaction]
	if info and endsAt then
		-- (reviving: DBNOController's ring shows the progress instead)
		progressBack.Visible = interaction ~= "Revive"
		progressFill.Size = UDim2.fromScale(math.clamp(1 - (endsAt - now) / info.time, 0, 1), 1)
		progressFill.BackgroundColor3 = info.color
		prompt.Visible = interaction ~= "Revive"
		prompt.Text = info.label
		state.interactAction = interaction
		return
	end
	progressBack.Visible = false

	local action = availableAction()
	state.interactAction = action -- (MobileControls shows its HOLD button)
	prompt.Visible = action ~= nil
	if action then
		prompt.Text = `HOLD [{if state.touchControls then "USE" else "G"}] TO {INTERACTIONS[action].prompt}`
		if action == "Reinforce" and not player.Neutral then
			prompt.Text ..= ` ({MatchState:GetAttribute("Reinforcements") or 0} LEFT)`
		end
	end
end

function ObjectiveController.Start()
	build()

	Actions.Bind("Interact", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			local action, slot = availableAction()
			if action and not (state.devPanelOpen or state.mouseUnlocked or state.deploying) then
				Interact:FireServer("Begin", action, slot)
			end
		else
			Interact:FireServer("End")
		end
		return Enum.ContextActionResult.Sink
	end, Enum.KeyCode.G, Enum.KeyCode.ButtonY)

	RunService.RenderStepped:Connect(update)

	-- The plant, heard by everyone: a beep as someone starts setting the defuser, and a heavy thunk
	-- with a long low tone once it's down
	local function watchPlanter(other: Player)
		other:GetAttributeChangedSignal("Interaction"):Connect(function()
			local head = other.Character and other.Character:FindFirstChild("Head") :: BasePart?
			if other:GetAttribute("Interaction") == "Plant" and head then
				Sound3D.PlayEvent("PlantStart", head.Position)
			end
		end)
	end
	for _, other in Players:GetPlayers() do
		watchPlanter(other)
	end
	Players.PlayerAdded:Connect(watchPlanter)
	MatchState:GetAttributeChangedSignal("DefuserPosition"):Connect(function()
		local position = MatchState:GetAttribute("DefuserPosition")
		if typeof(position) == "Vector3" then
			Sound3D.PlayEvent("Planted", position)
			Sound3D.PlayEvent("PlantedTone", position)
		end
	end)
end

return ObjectiveController
