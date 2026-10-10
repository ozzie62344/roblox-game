-- Driving your scout drone (DroneService): while your "Droning" attribute is set the camera rides
-- the drone: WASD drives, Space hops, the mouse looks around, click spots an enemy for your team,
-- Z goes back to your body (and back into the drone, or throws your second one, during the round).
-- The drone's physics belong to this client, so its movement is set here every frame. Your body
-- stays put meanwhile (state.droning roots it and puts the gun away).

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.MovementConfig)
local state = require(script.Parent.Parent.PlayerState)

local DroneRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Drone") :: RemoteEvent

local player = Players.LocalPlayer

local DroneController = {}

local SPEED = 13
local HOP = 22
local LOOK_SPEED = 0.0045 -- radians per pixel of mouse movement (times your mouse sensitivity)
local MAX_PITCH = math.rad(70)
local FOV = 85 -- wide-angle lens
local EYE = CFrame.new(0, 0.3, -0.45) -- matches DroneService.Eye
local SPOT_RANGE = 70

local yaw, pitch = 0, 0
local driving: Model? = nil -- the drone the camera is on
local overlay: ScreenGui
local countLabel: TextLabel

local function myDrone(): Model?
	local folder = Workspace:FindFirstChild("Deployables")
	for _, drone in if folder then folder:GetChildren() else {} do
		if drone.Name == "Drone" and drone:GetAttribute("OwnerId") == player.UserId and (drone :: Model).PrimaryPart then
			return drone :: Model
		end
	end
	return nil
end

local function ignoring(drone: Model): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { drone, player.Character :: Model }
	return params
end

local function label(parent: Instance, text: string, size: number, position: UDim2, anchor: Vector2): TextLabel
	local l = Instance.new("TextLabel")
	l.AnchorPoint = anchor
	l.Position = position
	l.Size = UDim2.fromOffset(600, size + 8)
	l.BackgroundTransparency = 1
	l.Font = if size >= 20 then Enum.Font.GothamBlack else Enum.Font.GothamMedium
	l.TextSize = size
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextStrokeTransparency = 0.5
	l.TextXAlignment = if anchor.X == 0 then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center
	l.Text = text
	l.Parent = parent
	return l
end

local function buildOverlay()
	overlay = Instance.new("ScreenGui")
	overlay.Name = "DroneView"
	overlay.IgnoreGuiInset = true
	overlay.ResetOnSpawn = false
	overlay.Enabled = false
	overlay.Parent = player:WaitForChild("PlayerGui")
	-- A thin camera frame inset from the screen edges
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
	local title = label(overlay, "●  DRONE", 22, UDim2.fromOffset(52, 44), Vector2.new(0, 0))
	title.TextColor3 = Color3.fromRGB(255, 80, 80)
	countLabel = label(overlay, "", 14, UDim2.fromOffset(52, 72), Vector2.new(0, 0))
	label(overlay, "WASD DRIVE  ·  SPACE HOP  ·  CLICK SPOT AN ENEMY  ·  Z BACK TO YOUR BODY", 14, UDim2.new(0.5, 0, 1, -48), Vector2.new(0.5, 1))
end

local function exit()
	driving = nil
	state.droning = false
	Workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
	overlay.Enabled = false
end

local function update()
	local drone = if player:GetAttribute("Droning") then myDrone() else nil
	if not drone then
		if driving then
			exit()
		end
		return
	end
	local camera = Workspace.CurrentCamera
	local body = drone.PrimaryPart :: BasePart
	if driving ~= drone then
		-- Just got in: look the way the drone faces. The loadout cards would cover the view and
		-- free the mouse: put them away (Left Alt still brings them back until the round starts).
		driving = drone
		state.droning = true
		state.draftOpen = false
		local look = body.CFrame.LookVector
		yaw, pitch = math.atan2(-look.X, -look.Z), 0
		camera.CameraType = Enum.CameraType.Scriptable
		overlay.Enabled = true
	end

	local uiOpen = state.devPanelOpen or state.mouseUnlocked
	if not uiOpen then
		local delta = UserInputService:GetMouseDelta()
		local speed = LOOK_SPEED * Config.MouseSensitivity
		yaw -= delta.X * speed
		pitch = math.clamp(pitch - delta.Y * speed, -MAX_PITCH, MAX_PITCH)
	end
	local facing = CFrame.Angles(0, yaw, 0)

	-- Drive where you look; gravity and hops keep their own vertical speed
	local move = Vector3.zero
	if not uiOpen then
		local keys = { W = facing.LookVector, S = -facing.LookVector, A = -facing.RightVector, D = facing.RightVector }
		for key, direction in keys do
			if UserInputService:IsKeyDown(Enum.KeyCode[key]) then
				move += direction
			end
		end
	end
	local horizontal = if move.Magnitude > 0 then move.Unit * SPEED else Vector3.zero
	body.AssemblyLinearVelocity = Vector3.new(horizontal.X, body.AssemblyLinearVelocity.Y, horizontal.Z)
	body.AssemblyAngularVelocity = Vector3.zero
	body.CFrame = CFrame.new(body.Position) * facing -- upright, facing where you look

	camera.CameraType = Enum.CameraType.Scriptable -- every frame, in case anything else reset it
	camera.CFrame = CFrame.new((body.CFrame * EYE).Position) * CFrame.fromOrientation(pitch, yaw, 0)
	camera.FieldOfView = FOV
	local left = player:GetAttribute("DronesLeft")
	countLabel.Text = if typeof(left) == "number" then `{left} MORE DRONE{if left == 1 then "" else "S"} THIS ROUND` else ""
end

local function hop()
	local drone = driving
	local body = drone and drone.PrimaryPart
	if not drone or not body then
		return
	end
	local ground = Workspace:Raycast(body.Position, Vector3.new(0, -(body.Size.Y / 2 + 0.3), 0), ignoring(drone))
	if ground then
		local velocity = body.AssemblyLinearVelocity
		body.AssemblyLinearVelocity = Vector3.new(velocity.X, HOP, velocity.Z)
	end
end

-- Click: if there's an enemy under the crosshair, the server checks the drone can see them
local function spot()
	local drone = driving
	if not drone then
		return
	end
	local camera = Workspace.CurrentCamera.CFrame
	local hit = Workspace:Raycast(camera.Position, camera.LookVector * SPOT_RANGE, ignoring(drone))
	local model = hit and hit.Instance:FindFirstAncestorOfClass("Model")
	if model and model:FindFirstChildOfClass("Humanoid") then
		DroneRemote:FireServer("Spot", model)
	end
end

function DroneController.Start()
	buildOverlay()
	ContextActionService:BindAction("Drone", function(_, inputState)
		if inputState == Enum.UserInputState.Begin and not (state.devPanelOpen or state.mouseUnlocked or state.draftOpen) then
			DroneRemote:FireServer("Toggle")
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.Z, Enum.KeyCode.DPadUp)
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or not driving then
			return
		end
		if input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.ButtonA then
			hop()
		elseif input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.ButtonR2 then
			spot()
		end
	end)
	-- After the camera and its effects (Camera + 2) and the hands (Camera + 4): the drone's lens wins
	RunService:BindToRenderStep("DroneController", Enum.RenderPriority.Camera.Value + 5, update)
end

return DroneController
