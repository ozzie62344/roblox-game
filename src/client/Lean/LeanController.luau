-- Hold Q / E to lean left / right. Shifts and tilts the camera (CameraEffects applies it)
-- and tells the server so other players see your body lean.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.MovementConfig)
local state = require(script.Parent.Parent.PlayerState)

local SetLean = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("SetLean") :: RemoteEvent

local player = Players.LocalPlayer

local LeanController = {}

local leftHeld = false
local rightHeld = false
local sentLean = 0

-- Keep the camera from poking through walls when leaning next to them
local function maxOffsetToward(direction: number): number
	local character = player.Character
	local head = character and character:FindFirstChild("Head") :: BasePart?
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not head or not root then
		return 0
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character :: Instance }

	local margin = 0.6
	local side = root.CFrame.RightVector * direction
	local result = Workspace:Raycast(head.Position, side * (Config.LeanOffset + margin), params)
	if result then
		return math.max(result.Distance - margin, 0)
	end
	return Config.LeanOffset
end

local function update(dt: number)
	local target = (if rightHeld then 1 else 0) - (if leftHeld then 1 else 0)
	-- Can't lean mid-slide or mid-dash
	if state.sliding or state.dashing then
		target = 0
	end

	state.leaning = target ~= 0
	state.lean += (target - state.lean) * (1 - math.exp(-Config.LeanSpeed * dt))

	local direction = if state.lean >= 0 then 1 else -1
	local allowed = maxOffsetToward(direction)
	state.leanOffset = direction * math.min(math.abs(state.lean) * Config.LeanOffset, allowed)

	if target ~= sentLean then
		sentLean = target
		SetLean:FireServer(target)
	end
end

function LeanController.Start()
	ContextActionService:BindAction("LeanLeft", function(_, inputState)
		leftHeld = inputState == Enum.UserInputState.Begin
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.Q, Enum.KeyCode.DPadLeft)

	ContextActionService:BindAction("LeanRight", function(_, inputState)
		rightHeld = inputState == Enum.UserInputState.Begin
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.E, Enum.KeyCode.DPadRight)

	player.CharacterAdded:Connect(function()
		leftHeld, rightHeld = false, false
		state.lean, state.leanOffset = 0, 0
	end)

	RunService.RenderStepped:Connect(update)
end

return LeanController
