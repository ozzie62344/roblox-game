-- Driving your scout drone (DroneService): while your "Droning" attribute is set the camera rides
-- the drone: WASD drives, Space hops, the mouse looks around, click spots an enemy for your team,
-- Z goes back to your body (and back into the drone, or throws your second one, during the round).
-- Sprint (the same input as on foot: Shift / L3, or the phone's stick pushed all the way out) is
-- a short burst of speed on a stamina bar that refills when you let go.
-- On a phone: the thumbstick drives, dragging looks, and MobileControls has the buttons.
-- Near an enemy Signal Jammer the feed breaks up into static, the picture shakes and the drone
-- crawls, worse the closer you get (and no spotting: the server agrees, GadgetService.Jammed).
-- The drone's physics belong to this client, so its movement is set here every frame. Your body
-- stays put meanwhile (state.droning roots it and puts the gun away).
-- Every drone's wheels roll as it drives (each client turns them for itself, just for looks).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Abilities = require(ReplicatedStorage.Shared.Abilities)
local Config = require(ReplicatedStorage.Shared.MovementConfig)
local state = require(script.Parent.Parent.PlayerState)
local TouchLook = require(script.Parent.Parent.Input.TouchLook)
local Static = require(script.Parent.Static)
local Actions = require(script.Parent.Parent.Input.Actions)
local MoveInput = require(script.Parent.Parent.Input.MoveInput)

local DroneRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Drone") :: RemoteEvent
local PingRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Ping") :: RemoteEvent

local player = Players.LocalPlayer

local DroneController = {}

local SPEED = 13
local SPRINT_SPEED = 1.6 -- times SPEED while sprinting
local STAMINA = 2 -- seconds of sprint on a full bar
local RECHARGE_DELAY = 0.6 -- seconds after you stop sprinting before the bar starts filling
local RECHARGE = 3.5 -- seconds from empty to full
local RESPRINT = 0.35 -- run the bar dry and you can't sprint again until it's back to this much
local STICK_SPRINT = 0.92 -- how far out the phone's stick has to be to sprint (as on foot: MovementController)
local HOP = 25.5 -- upward speed of a hop (about a third higher than it was at 22)
local WHEEL_RADIUS = 0.385 -- to the outside of the tread (DroneService's wheels)
local LOOK_SPEED = 0.0045 -- radians per pixel of mouse movement (times your mouse sensitivity)
local MAX_PITCH = math.rad(70)
local FOV = 85 -- wide-angle lens
local EYE = CFrame.new(0, 0.3, -0.45) -- matches DroneService.Eye
local SPOT_RANGE = 70
local MARK_RANGE = 300 -- (team pings reach further than spotting: PingService)
local JAM_RADIUS = Abilities.SignalJammer.Radius or 10

local yaw, pitch = 0, 0
local driving: Model? = nil -- the drone the camera is on
local overlay: ScreenGui
local countLabel: TextLabel
local hintLabel: TextLabel
local static: Static.Static
local jam = 0 -- 0 = clear signal .. 1 = right on top of a jammer (smoothed)
local stamina = 1 -- sprint left: 0 .. 1 (full)
local winded = false -- ran it dry: no sprinting until it's back to RESPRINT
local lastSprint = 0
local staminaBar: Frame
local staminaFill: Frame
local wheelAngles: { [Weld]: number } = {} -- every drone's wheels (spinWheels)
local headings: { [Model]: number } = {}

-- How badly enemy jammers interfere at `position` (the same jammers GadgetService.Jammed counts)
local function jamAt(position: Vector3): number
	local folder = Workspace:FindFirstChild("Deployables")
	local myTeam = if player.Neutral or not player.Team then "" else player.Team.Name
	local strongest = 0
	for _, device in if folder then folder:GetChildren() else {} do
		local owner = device:GetAttribute("OwnerTeam")
		local body = device:IsA("Model") and device.PrimaryPart
		if body and device:GetAttribute("Jammer") and (owner == "" or owner ~= myTeam) then
			strongest = math.max(strongest, 1 - (body.Position - position).Magnitude / JAM_RADIUS)
		end
	end
	return strongest
end

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
	hintLabel = label(overlay, "", 14, UDim2.new(0.5, 0, 1, -48), Vector2.new(0.5, 1))
	-- Sprint stamina: a thin bar just above the hints, only there while it isn't full
	staminaBar = Instance.new("Frame")
	staminaBar.AnchorPoint = Vector2.new(0.5, 1)
	staminaBar.Position = UDim2.new(0.5, 0, 1, -84)
	staminaBar.Size = UDim2.fromOffset(160, 6)
	staminaBar.BackgroundColor3 = Color3.new(0, 0, 0)
	staminaBar.BackgroundTransparency = 0.5
	staminaBar.BorderSizePixel = 0
	staminaBar.Visible = false
	staminaBar.Parent = overlay
	Instance.new("UICorner", staminaBar).CornerRadius = UDim.new(1, 0)
	staminaFill = Instance.new("Frame")
	staminaFill.BackgroundColor3 = Color3.new(1, 1, 1)
	staminaFill.BorderSizePixel = 0
	staminaFill.Size = UDim2.fromScale(1, 1)
	staminaFill.Parent = staminaBar
	Instance.new("UICorner", staminaFill).CornerRadius = UDim.new(1, 0)
	static = Static.new(overlay)
end

local function exit()
	driving = nil
	state.droning = false
	jam = 0
	static:Set(0)
	Workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
	overlay.Enabled = false
end

-- Holding sprint: the keys sprint uses on foot (MovementController's "Sprint": Shift / L3), or
-- on a phone the stick all the way out
local function sprintHeld(): boolean
	if UserInputService:GetFocusedTextBox() then
		return false -- (typing a capital in chat)
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonL3) then
		return true
	end
	local push = if state.touchControls then MoveInput.Push() else nil
	return push ~= nil and push >= STICK_SPRINT
end

-- Drains while you sprint, refills a moment after you stop (in or out of the drone)
local function tickStamina(dt: number, sprinting: boolean)
	local now = os.clock()
	if sprinting then
		lastSprint = now
		stamina = math.max(stamina - dt / STAMINA, 0)
		if stamina == 0 then
			winded = true
		end
	elseif now - lastSprint >= RECHARGE_DELAY then
		stamina = math.min(stamina + dt / RECHARGE, 1)
		if stamina >= RESPRINT then
			winded = false
		end
	end
	staminaBar.Visible = stamina < 1
	staminaFill.Size = UDim2.fromScale(stamina, 1)
	staminaFill.BackgroundColor3 = if winded then Color3.fromRGB(255, 95, 70) else Color3.new(1, 1, 1)
end

local function update(dt: number)
	local drone = if player:GetAttribute("Droning") then myDrone() else nil
	if not drone then
		if driving then
			exit()
		end
		tickStamina(dt, false)
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
		local delta = UserInputService:GetMouseDelta() + TouchLook.Consume()
		local speed = LOOK_SPEED * Config.MouseSensitivity
		yaw -= delta.X * speed
		pitch = math.clamp(pitch - delta.Y * speed * (if state.invertY then -1 else 1), -MAX_PITCH, MAX_PITCH)
	end
	local facing = CFrame.Angles(0, yaw, 0)

	-- Drive where you look; gravity and hops keep their own vertical speed. WASD, the phone's
	-- thumbstick and a gamepad stick all work the same way: your (rooted) body still gets told
	-- which way to walk, relative to the camera, which is this drone's camera.
	local move = Vector3.zero
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not uiOpen and humanoid then
		move = humanoid.MoveDirection * Vector3.new(1, 0, 1)
	end
	jam += (math.clamp(jamAt(body.Position), 0, 1) - jam) * 0.2
	local strength = math.min(move.Magnitude, 1)
	local sprinting = strength > 0.05 and not uiOpen and not winded and sprintHeld()
	tickStamina(dt, sprinting)
	local speed = SPEED * (if sprinting then SPRINT_SPEED else 1) * (1 - 0.85 * jam)
	local horizontal = if strength > 0.05 then move.Unit * strength * speed else Vector3.zero
	body.AssemblyLinearVelocity = Vector3.new(horizontal.X, body.AssemblyLinearVelocity.Y, horizontal.Z)
	body.AssemblyAngularVelocity = Vector3.zero
	body.CFrame = CFrame.new(body.Position) * facing -- upright, facing where you look

	camera.CameraType = Enum.CameraType.Scriptable -- every frame, in case anything else reset it
	local shake = CFrame.Angles((math.random() - 0.5) * 0.08 * jam, (math.random() - 0.5) * 0.08 * jam, (math.random() - 0.5) * 0.12 * jam)
	camera.CFrame = CFrame.new((body.CFrame * EYE).Position) * CFrame.fromOrientation(pitch, yaw, 0) * shake
	camera.FieldOfView = FOV + (math.random() - 0.5) * 12 * jam
	static:Set(jam * 1.2, if jam > 0.05 then "SIGNAL JAMMED" else nil)
	local left = player:GetAttribute("DronesLeft")
	countLabel.Text = if typeof(left) == "number" then `{left} MORE DRONE{if left == 1 then "" else "S"} THIS ROUND` else ""
	local alive = humanoid ~= nil and humanoid.Health > 0
	hintLabel.Text = if state.touchControls
		then "STICK DRIVES (ALL THE WAY: SPRINT)  ·  DRAG TO LOOK  ·  JUMP HOPS  ·  SPOT / PING"
		else `WASD DRIVE  ·  SHIFT SPRINT  ·  SPACE HOP  ·  CLICK SPOT / PING  ·  Z {if alive then "BACK TO YOUR BODY" else "BACK TO SPECTATING"}`
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

-- Click (or the ping key): an enemy under the crosshair gets spotted (the server checks the drone
-- can see them); anywhere else gets a team ping marker, like pinging on foot (TeamPing)
local function spot()
	local drone = driving
	if not drone or jam > 0.05 then
		return
	end
	local camera = Workspace.CurrentCamera.CFrame
	local hit = Workspace:Raycast(camera.Position, camera.LookVector * MARK_RANGE, ignoring(drone))
	if not hit then
		return
	end
	local model = hit.Instance:FindFirstAncestorOfClass("Model")
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 and (hit.Position - camera.Position).Magnitude <= SPOT_RANGE then
		DroneRemote:FireServer("Spot", model)
	elseif not humanoid or humanoid.Health <= 0 then
		PingRemote:FireServer("Mark", hit.Position + hit.Normal * 0.3)
	end
end

-- Every drone's wheels roll with it, here on this client only (looks, nothing else). Each wheel
-- hangs off the body by a Weld named "Spin" (DroneService) that turns about the axle; on a bend
-- the outside wheel rolls faster and the inside one slower (or backwards), like a real two-wheeler.
local function spinWheels(dt: number)
	local folder = Workspace:FindFirstChild("Deployables")
	for _, drone in if folder then folder:GetChildren() else {} do
		local body = drone.Name == "Drone" and drone:IsA("Model") and drone.PrimaryPart
		if not body then
			continue
		end
		local look = body.CFrame.LookVector
		local heading = math.atan2(-look.X, -look.Z)
		local turned = (heading - (headings[drone] or heading) + math.pi) % (2 * math.pi) - math.pi -- (+ = left)
		headings[drone] = heading
		local forward = body.AssemblyLinearVelocity:Dot(look) * dt
		for _, wheel in drone:GetChildren() do
			local spin = wheel.Name == "Wheel" and wheel:FindFirstChild("Spin")
			if spin and spin:IsA("Weld") then
				local axle = spin.C0.Position
				local rolled = forward + turned * axle.X -- how far this wheel's tread went
				-- (rolling forward, the top of the wheel goes forward: a negative turn about X)
				local angle = ((wheelAngles[spin] or 0) - rolled / WHEEL_RADIUS) % (2 * math.pi)
				wheelAngles[spin] = angle
				spin.C0 = CFrame.new(axle) * CFrame.Angles(angle, 0, 0)
			end
		end
	end
	-- Forget drones that are gone
	for drone in headings do
		if not drone.Parent then
			headings[drone] = nil
		end
	end
	for spin in wheelAngles do
		if not spin.Parent then
			wheelAngles[spin] = nil
		end
	end
end

-- For MobileControls
function DroneController.IsDriving(): boolean
	return driving ~= nil
end
function DroneController.Hop()
	hop()
end
function DroneController.Spot()
	spot()
end

function DroneController.Start()
	buildOverlay()
	Actions.Bind("Drone", function(_, inputState)
		if inputState == Enum.UserInputState.Begin and not (state.devPanelOpen or state.mouseUnlocked) then
			DroneRemote:FireServer("Toggle") -- (getting in puts the loadout cards away)
		end
		return Enum.ContextActionResult.Sink
	end, Enum.KeyCode.Z, Enum.KeyCode.DPadUp)
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
	RunService.Heartbeat:Connect(spinWheels)
end

return DroneController
