-- Q / E lean left / right: tap to lean and tap again to stop, or hold (state.leanToggle, switched
-- in the dev panel). Shifts and tilts the camera (CameraEffects applies it) and tells the server
-- so other players see your body lean.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.MovementConfig)
local state = require(script.Parent.Parent.PlayerState)
local Actions = require(script.Parent.Parent.Input.Actions)

local SetLean = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("SetLean") :: RemoteEvent

local player = Players.LocalPlayer

local LeanController = {}

local leftOn = false
local rightOn = false
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
	local target = (if rightOn then 1 else 0) - (if leftOn then 1 else 0)
	-- Can't lean mid-vault, while spectating or downed (aiming down sights is fine)
	if state.vaulting or state.spectating or state.downed then
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

-- side: -1 = Q (left), 1 = E (right). Toggle mode: a tap flips that side on (and the other off).
local function leanInput(side: number, inputState: Enum.UserInputState)
	local down = inputState == Enum.UserInputState.Begin
	if not state.leanToggle then
		if side < 0 then
			leftOn = down
		else
			rightOn = down
		end
	elseif down then
		local wasOn = if side < 0 then leftOn else rightOn
		leftOn, rightOn = side < 0 and not wasOn, side > 0 and not wasOn
	end
end

function LeanController.Start()
	Actions.Bind("LeanLeft", function(_, inputState)
		leanInput(-1, inputState)
		return Enum.ContextActionResult.Sink
	end, Enum.KeyCode.Q, Enum.KeyCode.DPadLeft)

	Actions.Bind("LeanRight", function(_, inputState)
		leanInput(1, inputState)
		return Enum.ContextActionResult.Sink
	end, Enum.KeyCode.E, Enum.KeyCode.DPadRight)

	player.CharacterAdded:Connect(function()
		leftOn, rightOn = false, false
		state.lean, state.leanOffset = 0, 0
	end)

	RunService.RenderStepped:Connect(update)
end

return LeanController
