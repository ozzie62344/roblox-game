-- Knife (F): a quick stab that kills in one hit. The gun is lowered, a gloved hand with a knife
-- thrusts forward, and anything right in front of you gets hit. The server double-checks the hit.
-- Then it recharges (GameRules.MeleeCooldown: quicker in Knives Only; a bar under the crosshair
-- fills back up).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local GameRules = require(ReplicatedStorage.Shared.GameRules)
local Skins = require(ReplicatedStorage.Shared.Skins)
local Sounds = require(ReplicatedStorage.Shared.Sounds)
local state = require(script.Parent.Parent.PlayerState)
local Effects = require(script.Parent.Effects)
local GunModels = require(script.Parent.GunModels)
local Hud = require(script.Parent.Hud)
local Viewmodel = require(script.Parent.Viewmodel)
local Actions = require(script.Parent.Parent.Input.Actions)

local MeleeRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Melee") :: RemoteEvent

local player = Players.LocalPlayer

local Melee = {}

local REACH = 6 -- studs in front of the camera
local HIT_RADIUS = 1.3 -- how forgiving the aim is
local SPHERE_LEAD = 0.3 -- studs the sweep must reach something before the ray does to win
local SWING_TIME = 0.42 -- whole animation
local HIT_TIME = 0.13 -- when in the swing the blade connects

local lastSwing = -math.huge
local knife: Model? = nil
local knifeSkin: Skins.Skin? = nil -- what `knife` was built with

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

-- Gloved fist holding the knife (GunModels, in your equipped skin), blade pointing forward (-Z),
-- built around the hand at the origin
local function buildKnife(skin: Skins.Skin?): Model
	local model = GunModels.BuildKnife(skin)
	local hand = makePart(model, Vector3.new(0.34, 0.36, 0.42), CFrame.new(), Viewmodel.GloveColor, Enum.Material.Leather)
	makePart(model, Vector3.new(0.3, 0.3, 1.4), CFrame.new(0.05, -0.12, 0.85) * CFrame.Angles(math.rad(12), 0, 0), Viewmodel.SleeveColor, Enum.Material.Fabric)
	model.PrimaryPart = hand
	return model
end

-- What's right in front of us: someone to stab, or a wall / barricade / window to break?
-- A thin ray first, then a fatter sphere sweep so it's not too picky. Someone the ray hits comes
-- first; otherwise whichever is nearer, so a stab at the edge of a hole you've already knocked
-- in a wall chips the edge (making the hole bigger: a rotation hole) instead of reaching through
-- it to whatever is in the next room.
local function findTarget(character: Model): (BasePart?, Vector3?)
	local camera = Workspace.CurrentCamera
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, camera }
	local origin = camera.CFrame.Position
	local direction = camera.CFrame.LookVector * REACH
	local ray = Workspace:Raycast(origin, direction, params)
	local rayModel = ray and ray.Instance:FindFirstAncestorOfClass("Model")
	local rayHumanoid = rayModel and rayModel:FindFirstChildOfClass("Humanoid")
	local result = ray
	if not (rayHumanoid and rayHumanoid.Health > 0) then
		local sphere = Workspace:Spherecast(origin, HIT_RADIUS, direction, params)
		if sphere and (not ray or sphere.Distance < ray.Distance - HIT_RADIUS - SPHERE_LEAD) then
			result = sphere
		end
	end
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
	if state.devPanelOpen or state.mouseUnlocked or state.draftOpen or state.settingsOpen or state.deploying or state.interacting or state.gesturing or state.droning or state.spectating or state.inLobby or state.downed then
		return
	end
	local now = os.clock()
	if now - lastSwing < GameRules.MeleeCooldown() then -- (the server checks it too)
		return
	end
	lastSwing = now
	state.meleeing = true
	Effects.Sound(Sounds.Knife.Swing, nil, Sounds.Knife.Volume, 0.95 + math.random() * 0.1)

	local skin = Skins.EquippedFor(player, "Knife")
	if not knife or skin ~= knifeSkin then
		if knife then
			knife:Destroy()
		end
		knife = buildKnife(skin)
		knifeSkin = skin
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
	Actions.Bind("Melee", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			swing()
		end
		return Enum.ContextActionResult.Sink
	end, Enum.KeyCode.F, Enum.KeyCode.ButtonR3)
	-- Recharge bar under the crosshair
	RunService.RenderStepped:Connect(function()
		Hud.SetKnifeCooldown(math.clamp(1 - (os.clock() - lastSwing) / GameRules.MeleeCooldown(), 0, 1))
	end)
end

return Melee
