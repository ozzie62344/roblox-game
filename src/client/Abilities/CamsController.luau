-- Watching the defenders' cameras (server CameraService). On the defending team, during setup and
-- the round (dead or alive), Z opens the feeds (attackers' Z stays the drone): A / D (or ← / →) switches camera,
-- the mouse turns it (within its mount's reach), click spots an attacker for your team, Z goes
-- back to your body. A camera that gets shot or EMP'd cuts to static and the next one comes up.
-- Your body stays put meanwhile (state.droning: rooted, gun away).

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.MovementConfig)
local state = require(script.Parent.Parent.PlayerState)
local Static = require(script.Parent.Static)

local MatchState = ReplicatedStorage:WaitForChild("MatchState")
local CamsRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Cams") :: RemoteEvent

local player = Players.LocalPlayer

local CamsController = {}

local LOOK_SPEED = 0.0035 -- radians per pixel (times your mouse sensitivity)
local MAX_TURN = math.rad(70) -- either side of where the camera points
local MIN_PITCH, MAX_PITCH = math.rad(-70), math.rad(15)
local FOV = 80
local SPOT_RANGE = 90
local SWITCH_STATIC = 0.25 -- seconds of static when the feed changes
local LOST_TIME = 0.8 -- "CAMERA DESTROYED" before moving on
local LIVE_PHASES = { Prep = true, Action = true, Planted = true }

local watching = false
local current: Model? = nil
local currentIndex = 1
local baseYaw, basePitch, turn, pitch = 0, 0, 0, 0
local switchedAt = 0
local lostAt: number? = nil
local overlay: ScreenGui
local nameLabel: TextLabel
local clockLabel: TextLabel
local hintLabel: TextLabel
local static: Static.Static

local function cameras(): { Model }
	local map = Workspace:FindFirstChild("Map")
	local folder = map and map:FindFirstChild("Cameras")
	local list = {}
	for _, camera in if folder then folder:GetChildren() else {} do
		if camera:IsA("Model") and camera.PrimaryPart then
			table.insert(list, camera)
		end
	end
	table.sort(list, function(a, b)
		return (a:GetAttribute("CamIndex") or 0) < (b:GetAttribute("CamIndex") or 0)
	end)
	return list
end

-- Defending in a live round, alive or dead: dead defenders keep watching and spotting, like in
-- Siege (the server checks the same: CameraService.canWatch)
local function allowed(): boolean
	local attackTeam = MatchState:GetAttribute("AttackTeam")
	return player:GetAttribute("Location") == "Match"
		and not player.Neutral and player.Team ~= nil and attackTeam ~= nil and player.Team.Name ~= attackTeam
		and LIVE_PHASES[MatchState:GetAttribute("Phase")] == true
end

local function eye(camera: Model): CFrame
	return (camera.PrimaryPart :: BasePart).CFrame * CFrame.new(0, 0, -0.5)
end

local function show(camera: Model, index: number)
	current, currentIndex = camera, index
	local look = eye(camera).LookVector
	baseYaw, basePitch = math.atan2(-look.X, -look.Z), math.asin(math.clamp(look.Y, -1, 1))
	turn, pitch = 0, basePitch
	switchedAt = os.clock()
	lostAt = nil
	nameLabel.Text = `●  CAM {camera:GetAttribute("CamIndex") or index}  ·  {camera:GetAttribute("CamName") or ""}`
end

local function cycle(step: number)
	local list = cameras()
	if #list == 0 then
		return
	end
	local at = (current and table.find(list, current)) or currentIndex
	local index = (at - 1 + step) % #list + 1
	show(list[index], index)
end

local function stop()
	if not watching then
		return
	end
	watching = false
	current = nil
	state.droning = false
	static:Set(0)
	overlay.Enabled = false
	Workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
	CamsRemote:FireServer("Watch", false)
end

local function start()
	local list = cameras()
	if #list == 0 then
		return
	end
	watching = true
	state.droning = true
	state.draftOpen = false -- (the loadout cards would cover the feed)
	overlay.Enabled = true
	show(list[math.clamp(currentIndex, 1, #list)], math.clamp(currentIndex, 1, #list))
	CamsRemote:FireServer("Watch", true)
end

local function update()
	if not watching then
		return
	end
	if not allowed() then
		stop()
		return
	end
	local now = os.clock()

	-- Our camera got shot / EMP'd: static, then on to the next one (or out if none are left)
	if not current or not current.Parent or not current.PrimaryPart then
		lostAt = lostAt or now
		static:Set(1, "CAMERA DESTROYED")
		if now - (lostAt :: number) >= LOST_TIME then
			local list = cameras()
			if #list == 0 then
				stop()
				return
			end
			local index = math.clamp(currentIndex, 1, #list)
			show(list[index], index)
		end
		return
	end

	if not (state.devPanelOpen or state.mouseUnlocked) then
		local delta = UserInputService:GetMouseDelta()
		local speed = LOOK_SPEED * Config.MouseSensitivity
		turn = math.clamp(turn - delta.X * speed, -MAX_TURN, MAX_TURN)
		pitch = math.clamp(pitch - delta.Y * speed, MIN_PITCH, MAX_PITCH)
	end
	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable -- every frame, in case anything else reset it
	camera.CFrame = CFrame.new(eye(current).Position) * CFrame.fromOrientation(pitch, baseYaw + turn, 0)
	camera.FieldOfView = FOV
	static:Set(1 - (now - switchedAt) / SWITCH_STATIC)
	clockLabel.Text = os.date("!%H:%M:%S", math.floor(Workspace:GetServerTimeNow())) :: string
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	local alive = humanoid ~= nil and humanoid.Health > 0
	hintLabel.Text = `A / D SWITCH CAMERA  ·  MOUSE LOOK  ·  CLICK SPOT AN ENEMY  ·  Z {if alive then "BACK TO YOUR BODY" else "BACK TO SPECTATING"}`
end

-- Click: if there's an enemy under the crosshair, the server checks the camera can see them
local function spot()
	local camera = current
	if not camera or not camera.Parent then
		return
	end
	local view = Workspace.CurrentCamera.CFrame
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { camera, player.Character :: Model }
	local hit = Workspace:Raycast(view.Position, view.LookVector * SPOT_RANGE, params)
	local model = hit and hit.Instance:FindFirstAncestorOfClass("Model")
	if model and model:FindFirstChildOfClass("Humanoid") then
		CamsRemote:FireServer("Spot", camera, model)
	end
end

local function label(text: string, size: number, position: UDim2, anchor: Vector2): TextLabel
	local l = Instance.new("TextLabel")
	l.AnchorPoint = anchor
	l.Position = position
	l.Size = UDim2.fromOffset(600, size + 8)
	l.BackgroundTransparency = 1
	l.Font = if size >= 20 then Enum.Font.GothamBlack else Enum.Font.GothamMedium
	l.TextSize = size
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextStrokeTransparency = 0.5
	l.TextXAlignment = if anchor.X == 0 then Enum.TextXAlignment.Left elseif anchor.X == 1 then Enum.TextXAlignment.Right else Enum.TextXAlignment.Center
	l.Text = text
	l.Parent = overlay
	return l
end

local function buildOverlay()
	overlay = Instance.new("ScreenGui")
	overlay.Name = "CamsView"
	overlay.IgnoreGuiInset = true
	overlay.ResetOnSpawn = false
	overlay.Enabled = false
	overlay.Parent = player:WaitForChild("PlayerGui")
	-- Darker corners, like a cheap security camera
	local vignette = Instance.new("Frame")
	vignette.Size = UDim2.fromScale(1, 1)
	vignette.BackgroundColor3 = Color3.new(0, 0, 0)
	vignette.Parent = overlay
	local fade = Instance.new("UIGradient")
	fade.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(0.2, 1),
		NumberSequenceKeypoint.new(0.8, 1),
		NumberSequenceKeypoint.new(1, 0.35),
	})
	fade.Parent = vignette
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.new(1, -60, 1, -60)
	frame.BackgroundTransparency = 1
	frame.Parent = overlay
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Transparency = 0.7
	stroke.Thickness = 2
	stroke.Parent = frame
	nameLabel = label("", 22, UDim2.fromOffset(52, 44), Vector2.new(0, 0))
	nameLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
	clockLabel = label("", 16, UDim2.new(1, -52, 0, 48), Vector2.new(1, 0))
	hintLabel = label("", 14, UDim2.new(0.5, 0, 1, -48), Vector2.new(0.5, 1))
	static = Static.new(overlay)
end

function CamsController.Start()
	buildOverlay()
	-- Z: before the drone's binding (DroneController), which gets it whenever this passes
	ContextActionService:BindActionAtPriority("Cams", function(_, inputState)
		if watching then
			if inputState == Enum.UserInputState.Begin then
				stop()
			end
			return Enum.ContextActionResult.Sink
		end
		if not allowed() then
			return Enum.ContextActionResult.Pass
		end
		if inputState == Enum.UserInputState.Begin and not (state.devPanelOpen or state.mouseUnlocked) then
			start() -- (puts the loadout cards away)
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.Z, Enum.KeyCode.DPadUp)

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or not watching then
			return
		end
		if input.KeyCode == Enum.KeyCode.D or input.KeyCode == Enum.KeyCode.Right or input.KeyCode == Enum.KeyCode.ButtonR1 then
			cycle(1)
		elseif input.KeyCode == Enum.KeyCode.A or input.KeyCode == Enum.KeyCode.Left or input.KeyCode == Enum.KeyCode.ButtonL1 then
			cycle(-1)
		elseif input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.ButtonR2 then
			spot()
		end
	end)
	player.CharacterAdded:Connect(stop)
	-- After the camera and its effects, like the drone: the feed wins
	RunService:BindToRenderStep("CamsController", Enum.RenderPriority.Camera.Value + 5, update)
end

return CamsController
