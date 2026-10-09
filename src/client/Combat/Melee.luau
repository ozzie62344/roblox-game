-- Knife (F): a quick stab that kills in one hit. The gun is lowered, a gloved hand with a knife
-- thrusts forward, and anything right in front of you gets hit. The server double-checks the hit.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Sounds = require(ReplicatedStorage.Shared.Sounds)
local state = require(script.Parent.Parent.PlayerState)
local Effects = require(script.Parent.Effects)
local Viewmodel = require(script.Parent.Viewmodel)

local MeleeRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Melee") :: RemoteEvent

local player = Players.LocalPlayer

local Melee = {}

local REACH = 6 -- studs in front of the camera
local HIT_RADIUS = 1.3 -- how forgiving the aim is
local SWING_TIME = 0.42 -- whole animation
local HIT_TIME = 0.13 -- when in the swing the blade connects
local COOLDOWN = 0.75

local lastSwing = -math.huge
local knife: Model? = nil

local function makePart(model: Model, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material): Part
	local part = Instance.new("Part")
	part.Size = size
	part.CFrame = offset
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = model
	return part
end

-- Gloved fist holding a knife, blade pointing forward (-Z), built around the hand at the origin
local function buildKnife(): Model
	local model = Instance.new("Model")
	model.Name = "Knife"
	local steel = Color3.fromRGB(170, 172, 178)
	local dark = Color3.fromRGB(30, 30, 32)
	-- Hand + sleeve
	makePart(model, Vector3.new(0.34, 0.36, 0.42), CFrame.new(), Viewmodel.GloveColor, Enum.Material.Leather)
	makePart(model, Vector3.new(0.3, 0.3, 1.4), CFrame.new(0.05, -0.12, 0.85) * CFrame.Angles(math.rad(12), 0, 0), Viewmodel.SleeveColor, Enum.Material.Fabric)
	-- Handle, guard, blade (slightly tapered with a wedge tip)
	makePart(model, Vector3.new(0.12, 0.14, 0.5), CFrame.new(0, 0, -0.05), dark, Enum.Material.Plastic)
	makePart(model, Vector3.new(0.3, 0.06, 0.05), CFrame.new(0, 0, -0.32), dark, Enum.Material.Metal)
	makePart(model, Vector3.new(0.04, 0.16, 0.62), CFrame.new(0, 0.01, -0.66), steel, Enum.Material.Metal)
	local tip = Instance.new("WedgePart")
	tip.Size = Vector3.new(0.04, 0.16, 0.2)
	tip.CFrame = CFrame.new(0, 0.01, -1.07) * CFrame.Angles(0, math.rad(180), 0)
	tip.Color = steel
	tip.Material = Enum.Material.Metal
	tip.Anchored = true
	tip.CanCollide = false
	tip.CanQuery = false
	tip.CanTouch = false
	tip.CastShadow = false
	tip.Parent = model
	model.PrimaryPart = model:FindFirstChildOfClass("Part")
	return model
end

-- What's right in front of us: someone to stab, or a wall / barricade / window to break?
-- A thin ray first, then a fatter sphere sweep so it's not too picky.
local function findTarget(character: Model): (BasePart?, Vector3?)
	local camera = Workspace.CurrentCamera
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, camera }
	local origin = camera.CFrame.Position
	local direction = camera.CFrame.LookVector * REACH
	local result = Workspace:Raycast(origin, direction, params) or Workspace:Spherecast(origin, HIT_RADIUS, direction, params)
	if not result then
		return nil, nil
	end
	if result.Instance:GetAttribute("Breakable") then
		return result.Instance, result.Position
	end
	local model = result.Instance:FindFirstAncestorOfClass("Model")
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		return result.Instance, result.Position
	end
	return nil, nil
end

-- Stab pose over the swing: pull back slightly, thrust forward and a bit left, return
local function knifeOffset(t: number): CFrame
	local rest = CFrame.new(0.55, -0.75, -0.9) * CFrame.Angles(math.rad(10), math.rad(20), math.rad(-70))
	local thrust = CFrame.new(0.1, -0.35, -1.9) * CFrame.Angles(math.rad(-5), math.rad(5), math.rad(-80))
	local windup = CFrame.new(0.75, -0.6, -0.55) * CFrame.Angles(math.rad(20), math.rad(30), math.rad(-60))
	local hidden = rest * CFrame.new(0, -1.5, 1)
	if t < 0.1 then
		return hidden:Lerp(windup, t / 0.1)
	elseif t < HIT_TIME + 0.05 then
		local a = (t - 0.1) / (HIT_TIME + 0.05 - 0.1)
		return windup:Lerp(thrust, 1 - (1 - a) ^ 3) -- fast out
	else
		local a = (t - HIT_TIME - 0.05) / (SWING_TIME - HIT_TIME - 0.05)
		return thrust:Lerp(hidden, a * a) -- ease back down out of view
	end
end

local function swing()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not character or not humanoid or humanoid.Health <= 0 or not root or root.Anchored then
		return
	end
	if state.devPanelOpen or state.mouseUnlocked or state.draftOpen or state.deploying or state.interacting or state.spectating or state.inLobby then
		return
	end
	local now = os.clock()
	if now - lastSwing < COOLDOWN then
		return
	end
	lastSwing = now
	state.meleeing = true
	Effects.Sound(Sounds.Knife.Swing, nil, Sounds.Knife.Volume, 0.95 + math.random() * 0.1)

	if not knife then
		knife = buildKnife()
	end
	local model = knife :: Model
	model.Parent = Workspace.CurrentCamera

	local hitDone = false
	local started = os.clock()
	RunService:BindToRenderStep("KnifeSwing", Enum.RenderPriority.Camera.Value + 4, function()
		local t = os.clock() - started
		if t >= SWING_TIME or not character.Parent then
			RunService:UnbindFromRenderStep("KnifeSwing")
			model.Parent = nil
			state.meleeing = false
			return
		end
		model:PivotTo(Workspace.CurrentCamera.CFrame * knifeOffset(t))
		if not hitDone and t >= HIT_TIME then
			hitDone = true
			local target, point = findTarget(character)
			if target and not target:GetAttribute("Breakable") then
				Effects.Sound(Sounds.Knife.Hit, nil, Sounds.Knife.Volume)
			end
			MeleeRemote:FireServer(target, point) -- breaking things makes its own sound (DestructionEffects)
		end
	end)
end

function Melee.Start()
	ContextActionService:BindAction("Melee", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			swing()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.F, Enum.KeyCode.ButtonR3)
end

return Melee
