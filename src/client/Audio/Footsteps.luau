-- Footsteps, jumps and landings for every character, including your own.
-- Sprinting is loud and carries far, walking is medium, crouching is nearly silent,
-- sliding makes no steps. This is how you hear people coming.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Sounds = require(ReplicatedStorage.Shared.Sounds)
local Sound3D = require(script.Parent.Sound3D)

local Footsteps = {}

local SPRINT_THRESHOLD = 22 -- studs/s; faster than this counts as sprinting
local MIN_STEP_SPEED = 3

local random = Random.new()

type Tracker = {
	distance: number,
	grounded: boolean,
	lastVerticalSpeed: number,
}

local trackers: { [Model]: Tracker } = setmetatable({}, { __mode = "k" }) :: any

local function isGrounded(character: Model, root: BasePart, humanoid: Humanoid): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local reach = humanoid.HipHeight + root.Size.Y / 2 + 0.6
	return Workspace:Raycast(root.Position, Vector3.new(0, -reach, 0), params) ~= nil
end

local function update(dt: number)
	local config = Sounds.Footstep
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not character or not root or not humanoid or humanoid.Health <= 0 then
			continue
		end

		local tracker = trackers[character]
		if not tracker then
			tracker = { distance = 0, grounded = true, lastVerticalSpeed = 0 }
			trackers[character] = tracker
		end

		local velocity = root.AssemblyLinearVelocity
		local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
		local grounded = isGrounded(character, root, humanoid)
		local feet = root.Position - Vector3.new(0, humanoid.HipHeight + root.Size.Y / 2, 0)

		-- Jump / land
		if tracker.grounded and not grounded and velocity.Y > 20 then
			Sound3D.Play(Sounds.Jump.Id, feet, { volume = Sounds.Jump.Volume, range = Sounds.Jump.Range })
		elseif not tracker.grounded and grounded and tracker.lastVerticalSpeed < -Sounds.Land.MinFallSpeed then
			Sound3D.Play(Sounds.Land.Id, feet, { volume = Sounds.Land.Volume, range = Sounds.Land.Range })
			tracker.distance = 0
		end
		tracker.grounded = grounded
		tracker.lastVerticalSpeed = velocity.Y

		-- Steps
		local crouching = character:GetAttribute("Crouching") == true
		local sliding = crouching and speed > SPRINT_THRESHOLD * 0.7
		if not grounded or sliding or speed < MIN_STEP_SPEED then
			continue
		end

		local stride, range, volume
		if crouching then
			stride, range, volume = config.CrouchStride, config.CrouchRange, config.CrouchVolume
		elseif speed > SPRINT_THRESHOLD then
			stride, range, volume = config.SprintStride, config.SprintRange, config.SprintVolume
		else
			stride, range, volume = config.WalkStride, config.WalkRange, config.WalkVolume
		end

		tracker.distance += speed * dt
		if tracker.distance >= stride then
			tracker.distance = 0
			Sound3D.Play(config.Id, feet, {
				volume = volume,
				range = range,
				pitch = random:NextNumber(0.9, 1.1),
				-- The built-in sound is a loop of several steps; play just one
				duration = config.Duration,
				-- Your own steps don't need the wall check
				muffle = player ~= Players.LocalPlayer,
			})
		end
	end
end

function Footsteps.Start()
	RunService.Heartbeat:Connect(update)
end

return Footsteps
