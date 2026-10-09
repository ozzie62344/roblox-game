-- When you die: first a KILL CAM on whoever killed you (their name, weapon and health left),
-- then, during a round, watch a living teammate in third person.
-- Left click / → = next player, right click / ← = previous. Falls back to any living player
-- if you have no team (e.g. you joined mid-match).

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
	return nil
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
	if not target or not humanoidOf(target) then
		cycle(1)
	end
	local humanoid = target and humanoidOf(target)
	if humanoid and target then
		Workspace.CurrentCamera.CameraSubject = humanoid
		label.Text = `SPECTATING  {string.upper(target.DisplayName)}   ·   click to switch`
	else
		label.Text = "NO ONE TO SPECTATE"
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
