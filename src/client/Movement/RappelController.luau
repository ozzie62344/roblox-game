-- Rappel (V; attackers once the round is live, anyone while free roaming): climb the outside of
-- the house on a rope tied to the roof. Press V facing an exterior wall, or at the roof edge
-- looking out.
--   • W / S climb up / down, A / D move along the wall; look around and shoot freely
--   • climb past the top to get onto the roof; reach the ground to let go
--   • Space: go in through the opening in front of you (break the window first), or push off
--   • V again lets go
-- While rappelling the character is moved here every physics step (PlatformStand hands it over
-- from MovementController). The server only hears how high the rope is tied (SetRappel), so
-- everyone can draw the rope.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local state = require(script.Parent.Parent.PlayerState)
local Effects = require(script.Parent.Parent.Combat.Effects)

local MatchState = ReplicatedStorage:WaitForChild("MatchState")
local SetRappel = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("SetRappel") :: RemoteEvent

local player = Players.LocalPlayer

local RappelController = {}

local CLIMB_SPEED = 7
local DESCEND_SPEED = 11
local SIDE_SPEED = 6
local OFF_WALL = 1.2 -- your middle, out from the wall face
local REACH = 3 -- how close the wall has to be to start
local MAX_HEIGHT = 40 -- rope length
local LIVE_PHASES = { Action = true, Planted = true }

local normal = Vector3.zAxis -- out of the wall
local position = Vector3.zero -- where your middle hangs
local topY = 0 -- where the rope is tied
local ropes: { [Model]: Part } = {}

local function mapParams(): RaycastParams?
	local map = Workspace:FindFirstChild("Map")
	if not map then
		return nil
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { map }
	return params
end

local function isExterior(part: BasePart): boolean
	local parent = part.Parent
	return part.Name == "ExteriorWall" or (parent ~= nil and parent.Name == "Glass")
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function parts(): (Humanoid?, BasePart?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if humanoid and humanoid.Health > 0 and root then
		return humanoid, root
	end
	return nil, nil
end

-- Standing root height above the floor (matches RoundService's spawns)
local function standHeight(humanoid: Humanoid, root: BasePart): number
	return if humanoid.RigType == Enum.HumanoidRigType.R15 then humanoid.HipHeight + root.Size.Y / 2 else 3
end

local function allowed(): boolean
	if player.Neutral then
		return true -- free roam, to try it out
	end
	return player.Team ~= nil
		and player.Team.Name == MatchState:GetAttribute("AttackTeam")
		and LIVE_PHASES[MatchState:GetAttribute("Phase")] == true
end

local function stop(humanoid: Humanoid?)
	if not state.rappelling then
		return
	end
	state.rappelling = false
	state.rappelSpeed = 0
	SetRappel:FireServer(nil)
	if humanoid then
		humanoid.PlatformStand = false
		humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	end
end

-- Is there wall behind you anywhere from your feet to your head? (false past a corner)
local function onWall(at: Vector3, params: RaycastParams): boolean
	for _, dy in { -2, -1, 0, 1, 2 } do
		if Workspace:Raycast(at + Vector3.new(0, dy, 0), -normal * (OFF_WALL + 0.6), params) then
			return true
		end
	end
	return false
end

-- Land standing on whatever is below `spot`, facing into the wall
local function landOn(spot: Vector3, humanoid: Humanoid, root: BasePart, params: RaycastParams): boolean
	local ground = Workspace:Raycast(spot, Vector3.new(0, -6, 0), params)
	if not ground then
		return false
	end
	local stand = ground.Position + Vector3.new(0, standHeight(humanoid, root), 0)
	stop(humanoid)
	root.CFrame = CFrame.lookAt(stand, stand - normal)
	return true
end

local function start()
	local humanoid, root = parts()
	local params = mapParams()
	if not humanoid or not root or not params or root.Anchored or not allowed() then
		return
	end
	if state.droning or state.interacting or state.deploying then
		return
	end
	local look = flat(Workspace.CurrentCamera.CFrame.LookVector)
	if look.Magnitude < 1e-3 then
		return
	end
	look = look.Unit

	-- A wall right in front of you, or (at the roof edge) below and in front of you
	local fromRoof = false
	local wall = Workspace:Raycast(root.Position, look * REACH, params)
	if not wall then
		local ahead = root.Position + look * 2.5
		if Workspace:Raycast(ahead, Vector3.new(0, -5, 0), params) then
			return -- solid ground ahead: not an edge
		end
		wall = Workspace:Raycast(ahead - Vector3.new(0, 6, 0), -look * 5, params) -- under the eaves
		fromRoof = true
	end
	if not wall or math.abs(wall.Normal.Y) > 0.3 or not isExterior(wall.Instance :: BasePart) then
		return
	end
	normal = flat(wall.Normal).Unit

	-- The rope is tied where the wall meets the roof
	local inWall = wall.Position - normal * 0.5
	local knot = Workspace:Raycast(Vector3.new(inWall.X, root.Position.Y + MAX_HEIGHT, inWall.Z), Vector3.new(0, -MAX_HEIGHT * 2, 0), params)
	if not knot then
		return
	end
	topY = knot.Position.Y
	local y = if fromRoof then topY - 3.5 else root.Position.Y -- (head clear of the eaves)
	if topY - y < 2 or topY - y > MAX_HEIGHT then
		return
	end
	position = Vector3.new(wall.Position.X, y, wall.Position.Z) + normal * OFF_WALL

	state.rappelling = true
	state.crouching = false
	state.prone = false
	humanoid.PlatformStand = true
	SetRappel:FireServer(topY)
end

-- Space: in through the opening in front of you if there is one, otherwise push off the wall
local function jump()
	local humanoid, root = parts()
	local params = mapParams()
	if not state.rappelling or not humanoid or not root or not params then
		return
	end
	local reach = -normal * (OFF_WALL + 1.2)
	local open = not Workspace:Raycast(position, reach, params) and not Workspace:Raycast(position + Vector3.new(0, 1.2, 0), reach, params)
	if open and landOn(position - normal * (OFF_WALL + 2.3) + Vector3.new(0, 1, 0), humanoid, root, params) then -- clear of the wall inside
		return
	end
	stop(humanoid)
	root.AssemblyLinearVelocity = normal * 16 + Vector3.new(0, 8, 0)
end

local function step(dt: number)
	if not state.rappelling then
		return
	end
	local humanoid, root = parts()
	local params = mapParams()
	if not humanoid or not root or not params or root.Anchored or not allowed() then
		stop(humanoid)
		return
	end

	-- Camera-relative: forward climbs, right / left slide along the wall (not while driving a drone)
	local move = if state.droning then Vector3.zero else humanoid.MoveDirection
	local cameraLook = flat(Workspace.CurrentCamera.CFrame.LookVector)
	local forward = move:Dot(if cameraLook.Magnitude > 1e-3 then cameraLook.Unit else -normal)
	local along = Vector3.yAxis:Cross(normal) -- to your right when you face the wall
	local vertical = forward * (if forward > 0 then CLIMB_SPEED else DESCEND_SPEED)
	local lateral = move:Dot(along) * SIDE_SPEED
	local nextPosition = position + Vector3.new(0, vertical * dt, 0) + along * lateral * dt

	-- Over the top: onto the roof (or stay at the knot if there's nowhere to stand)
	if nextPosition.Y + 1.5 > topY then
		if vertical > 0 and landOn(Vector3.new(nextPosition.X, topY + 4, nextPosition.Z) - normal * (OFF_WALL + 1.6), humanoid, root, params) then
			return
		end
		nextPosition = Vector3.new(nextPosition.X, topY - 1.5, nextPosition.Z)
	end
	-- Past the corner of the wall: don't slide off
	if lateral ~= 0 and not onWall(nextPosition, params) then
		nextPosition = Vector3.new(position.X, nextPosition.Y, position.Z)
	end
	-- Feet on the ground: let go
	if vertical < 0 and Workspace:Raycast(nextPosition, Vector3.new(0, -(standHeight(humanoid, root) + 0.1), 0), params) then
		stop(humanoid)
		return
	end

	state.rappelSpeed = (nextPosition - position).Magnitude / math.max(dt, 1e-3) -- (the viewmodel climbs with it)
	position = nextPosition
	root.CFrame = CFrame.lookAt(position, position - normal)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
end

-- Everyone's ropes (anyone with a "RappelTop" attribute): from where it's tied down to their left
-- hand (BodyAnimator puts it on the rope). Yours hangs off to your left so it doesn't run through
-- the middle of your view.
local function drawRopes()
	local seen = {}
	for _, other in Players:GetPlayers() do
		local character = other.Character
		local top = character and character:GetAttribute("RappelTop")
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if typeof(top) ~= "number" or not root then
			continue
		end
		seen[character] = true
		local rope = ropes[character]
		if not rope then
			rope = Instance.new("Part")
			rope.Name = "RappelRope"
			rope.Shape = Enum.PartType.Cylinder
			rope.Color = Color3.fromRGB(70, 60, 45)
			rope.Material = Enum.Material.Fabric
			rope.Anchored = true
			rope.CanCollide = false
			rope.CanQuery = false
			rope.CanTouch = false
			rope.CastShadow = false
			rope.Parent = Effects.GetFolder()
			ropes[character] = rope
		end
		local hands = if other == player
			then root.Position + root.CFrame.LookVector * 0.9 - root.CFrame.RightVector * 0.9 + Vector3.new(0, 1.2, 0)
			else root.Position + root.CFrame.LookVector * 0.5 - root.CFrame.RightVector * 0.45 + Vector3.new(0, 2.2, 0)
		local length = math.max(top - hands.Y, 0.1)
		rope.Size = Vector3.new(length, 0.12, 0.12)
		rope.CFrame = CFrame.new(hands + Vector3.new(0, length / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	end
	for character, rope in ropes do
		if not seen[character] then
			rope:Destroy()
			ropes[character] = nil
		end
	end
end

function RappelController.Start()
	ContextActionService:BindAction("Rappel", function(_, inputState)
		if inputState == Enum.UserInputState.Begin and not (state.devPanelOpen or state.mouseUnlocked) then
			if state.rappelling then
				stop((parts()))
			else
				start()
			end
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.V, Enum.KeyCode.DPadDown)
	ContextActionService:BindActionAtPriority("RappelJump", function(_, inputState)
		if not state.rappelling then
			return Enum.ContextActionResult.Pass
		end
		if inputState == Enum.UserInputState.Begin then
			jump()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.Space, Enum.KeyCode.ButtonA)

	player.CharacterAdded:Connect(function()
		state.rappelling = false
	end)
	RunService.PreSimulation:Connect(step)
	RunService.Heartbeat:Connect(drawRopes)
end

return RappelController
