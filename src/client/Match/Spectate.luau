-- When you die: first a KILL CAM on whoever killed you (their name, weapon and health left),
-- then, during a round, watch a living teammate in third person.
-- Left click / → = next player, right click / ← = previous. Falls back to any living player
-- if you have no team. With nobody to watch and no body of your own (e.g. you joined mid-match:
-- you spawn next round), the camera circles above the map instead of sitting at the world's
-- origin, inside the floor.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local state = require(script.Parent.Parent.PlayerState)

local MatchState = ReplicatedStorage:WaitForChild("MatchState")

local player = Players.LocalPlayer

local Spectate = {}

local DEATH_CAM_TIME = 3.5 -- seconds of kill cam on your killer before switching to teammates
local ROUND_PHASES = { PreRound = true, Prep = true, Action = true, Planted = true, PostRound = true }

local deathTime = -math.huge
local killer: Player? = nil -- who killed us (for the kill cam)
local target: Player? = nil
local savedCamera = { mode = Enum.CameraMode.LockFirstPerson, minZoom = 0.5, maxZoom = 128 }
local label: TextLabel
local overviewOf: { map: Instance?, center: Vector3, radius: number } = { map = nil, center = Vector3.zero, radius = 80 }

local function humanoidOf(p: Player): Humanoid?
	local character = p.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		return humanoid
	end
	return nil
end

local function candidates(): { Player }
	local list = {}
	local sameTeamOnly = not player.Neutral and player.Team ~= nil
	for _, other in Players:GetPlayers() do
		if other ~= player and humanoidOf(other) and (not sameTeamOnly or other.Team == player.Team) then
			table.insert(list, other)
		end
	end
	return list
end

-- "Kill" = kill cam on our killer, "Death" = our own body (no killer), "Team" = spectating
-- teammates, nil = not spectating. All of them are third person.
local function spectateMode(): string?
	if humanoidOf(player) ~= nil then
		return nil
	end
	local inKillCam = os.clock() - deathTime <= DEATH_CAM_TIME
	if inKillCam and killer and killer ~= player and humanoidOf(killer) then
		return "Kill"
	end
	if inKillCam then
		return "Death" -- no killer to show: look at your own body, in third person
	end
	local phase = MatchState:GetAttribute("Phase")
	if ROUND_PHASES[phase] == true and not inKillCam then
		return "Team"
	end
	if not player.Character then
		return "Overview" -- no body at all (joined while a match was running)
	end
	return nil
end

-- A slow circle above the map, looking down at the building (the middle of its bomb sites; the
-- whole map's box takes in the street and yards, far too wide)
local function overview()
	local map = Workspace:FindFirstChild("Map") or Workspace:FindFirstChild("TestArena")
	if map ~= overviewOf.map and map then
		local objectives = map:FindFirstChild("Objectives")
		local sites = if objectives then objectives:GetChildren() else {}
		local sum, spread = Vector3.zero, 0
		for _, site in sites do
			sum += (site :: BasePart).Position
		end
		local center = if #sites > 0 then sum / #sites else Vector3.zero
		for _, site in sites do
			spread = math.max(spread, ((site :: BasePart).Position - center).Magnitude)
		end
		overviewOf = { map = map, center = center, radius = math.clamp(spread + 45, 60, 120) }
	end
	local camera = Workspace.CurrentCamera
	local angle = os.clock() * 0.08
	local radius = overviewOf.radius
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.lookAt(overviewOf.center + Vector3.new(math.cos(angle) * radius, radius * 0.55, math.sin(angle) * radius), overviewOf.center)
end

local function cycle(step: number)
	local list = candidates()
	if #list == 0 then
		target = nil
		return
	end
	local index = (target and table.find(list, target)) or 0
	target = list[(index - 1 + step) % #list + 1]
end

local function startSpectating()
	state.spectating = true
	savedCamera = {
		mode = player.CameraMode,
		minZoom = player.CameraMinZoomDistance,
		maxZoom = player.CameraMaxZoomDistance,
	}
	player.CameraMode = Enum.CameraMode.Classic
	player.CameraMinZoomDistance = 6
	player.CameraMaxZoomDistance = 14
end

local function stopSpectating()
	state.spectating = false
	target = nil
	label.Visible = false
	player.CameraMode = savedCamera.mode
	player.CameraMinZoomDistance = savedCamera.minZoom
	player.CameraMaxZoomDistance = savedCamera.maxZoom
	Workspace.CurrentCamera.CameraType = Enum.CameraType.Custom -- (after the map overview)
	local ownHumanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if ownHumanoid then
		Workspace.CurrentCamera.CameraSubject = ownHumanoid
	end
end

local function update()
	local mode = spectateMode()
	local should = mode ~= nil
	if should and not state.spectating then
		startSpectating()
	elseif not should and state.spectating then
		stopSpectating()
	end
	if not state.spectating then
		return
	end

	if mode == "Death" then
		local ownHumanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if ownHumanoid then
			Workspace.CurrentCamera.CameraSubject = ownHumanoid
		end
		label.Text = "YOU DIED"
		label.TextColor3 = Color3.fromRGB(255, 110, 100)
		label.Visible = true
		return
	end
	if mode == "Kill" then
		-- Kill cam: look at the player who killed us
		local theirHumanoid = humanoidOf(killer :: Player) :: Humanoid
		Workspace.CurrentCamera.CameraSubject = theirHumanoid
		local weapon = (killer :: Player):GetAttribute("Weapon") or ""
		label.Text = `KILLED BY  {string.upper((killer :: Player).DisplayName)}   ·   {string.upper(weapon)}   ·   {math.ceil(theirHumanoid.Health)} HP LEFT`
		label.TextColor3 = Color3.fromRGB(255, 110, 100)
		label.Visible = true
		return
	end
	label.TextColor3 = Color3.new(1, 1, 1)
	if mode == "Team" and (not target or not humanoidOf(target)) then
		cycle(1)
	end
	local humanoid = if mode == "Team" and target then humanoidOf(target) else nil
	if humanoid and target then
		Workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
		Workspace.CurrentCamera.CameraSubject = humanoid
		label.Text = `SPECTATING  {string.upper(target.DisplayName)}   ·   click to switch`
	else
		overview()
		label.Text = if player.Character then "NO ONE TO SPECTATE" else "YOU'LL JOIN AT THE START OF THE NEXT ROUND"
	end
	label.Visible = true
end

function Spectate.Start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Spectate"
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")

	label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.new(0.5, 0, 1, -40)
	label.Size = UDim2.fromOffset(640, 32)
	label.BackgroundColor3 = Color3.fromRGB(15, 16, 20)
	label.BackgroundTransparency = 0.4
	label.Font = Enum.Font.GothamBold
	label.TextSize = 16
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Visible = false
	label.Parent = gui

	local function watchCharacter(character: Model)
		local humanoid = character:WaitForChild("Humanoid") :: Humanoid
		humanoid.Died:Connect(function()
			deathTime = os.clock()
			local killerId = humanoid:GetAttribute("LastDamagedBy")
			killer = if killerId then Players:GetPlayerByUserId(killerId) else nil
		end)
	end
	if player.Character then
		task.spawn(watchCharacter, player.Character)
	end
	player.CharacterAdded:Connect(watchCharacter)

	UserInputService.InputBegan:Connect(function(input)
		if not state.spectating then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.Right then
			cycle(1)
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 or input.KeyCode == Enum.KeyCode.Left then
			cycle(-1)
		end
	end)

	RunService.RenderStepped:Connect(update)
end

return Spectate
