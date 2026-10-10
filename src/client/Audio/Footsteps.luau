-- Footsteps, jumps and landings for every character, including your own (yours quieter).
-- Sprinting is loud and carries far, walking is medium, crouching is nearly silent,
-- sliding makes no steps. The floor changes the step (Sounds.Footstep.Surfaces): metal catwalks
-- clank and carry, floorboards thud, carpet and grass are soft. This is how you hear people coming.

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

-- (a plain table, cleaned up below: Roblox can drop an Instance key from a weak table while the
-- character still exists, which would restart its step count)
local trackers: { [Model]: Tracker } = {}

-- What's under the character's feet (nil = in the air)
local function groundUnder(character: Model, root: BasePart, humanoid: Humanoid): RaycastResult?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local reach = humanoid.HipHeight + root.Size.Y / 2 + 0.6
	return Workspace:Raycast(root.Position, Vector3.new(0, -reach, 0), params)
end

local SURFACES: { [Enum.Material]: string } = {
	[Enum.Material.Metal] = "Metal",
	[Enum.Material.DiamondPlate] = "Metal",
	[Enum.Material.CorrodedMetal] = "Metal",
	[Enum.Material.Foil] = "Metal",
	[Enum.Material.Wood] = "Wood",
	[Enum.Material.WoodPlanks] = "Wood",
	[Enum.Material.Carpet] = "Soft",
	[Enum.Material.Fabric] = "Soft",
	[Enum.Material.Rubber] = "Soft",
	[Enum.Material.Grass] = "Soft",
	[Enum.Material.LeafyGrass] = "Soft",
	[Enum.Material.Ground] = "Soft",
	[Enum.Material.Mud] = "Soft",
	[Enum.Material.Sand] = "Soft",
	[Enum.Material.Snow] = "Soft",
	[Enum.Material.Pebble] = "Gravel",
	[Enum.Material.Cobblestone] = "Gravel",
	[Enum.Material.Salt] = "Gravel",
}

-- Carpets, tiles and marble are thin looks-only layers over the floorboards (the map's "Shell"
-- folder), which rays can't see: keep a list of them per map and check the feet against it
type Finish = { x1: number, x2: number, z1: number, z2: number, top: number, material: Enum.Material }
local cachedShell: Instance? = nil -- the current map's (one map at a time)
local cachedFinishes: { Finish } = {}

local function finishAt(feet: Vector3): Enum.Material?
	local map = Workspace:FindFirstChild("Map")
	local shell = map and map:FindFirstChild("Shell")
	if not shell then
		return nil
	end
	if shell ~= cachedShell then
		cachedShell = shell
		cachedFinishes = {}
		for _, part in shell:GetChildren() do
			if part:IsA("BasePart") and part.Size.Y <= 0.1 and string.sub(part.Name, -5) == "Floor" then
				local half = part.Size / 2
				table.insert(cachedFinishes, { x1 = part.Position.X - half.X, x2 = part.Position.X + half.X, z1 = part.Position.Z - half.Z, z2 = part.Position.Z + half.Z, top = part.Position.Y + half.Y, material = part.Material })
			end
		end
	end
	for _, f in cachedFinishes do
		if feet.X >= f.x1 and feet.X <= f.x2 and feet.Z >= f.z1 and feet.Z <= f.z2 and math.abs(feet.Y - f.top) < 1.5 then
			return f.material
		end
	end
	return nil
end

local function surfaceOf(ground: RaycastResult, feet: Vector3): string
	local material = finishAt(feet) or ground.Material
	return SURFACES[material] or "Hard"
end

local function update(dt: number)
	local config = Sounds.Footstep
	for character in trackers do
		if not character.Parent then
			trackers[character] = nil
		end
	end
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
		local ground = groundUnder(character, root, humanoid)
		local grounded = ground ~= nil
		local feet = root.Position - Vector3.new(0, humanoid.HipHeight + root.Size.Y / 2, 0)

		-- Ghost Step: no sounds at all
		if character:GetAttribute("Silent") then
			tracker.grounded = grounded
			tracker.lastVerticalSpeed = velocity.Y
			tracker.distance = 0
			continue
		end

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
			local surface = config.Surfaces[surfaceOf(ground :: RaycastResult, feet)]
			local own = player == Players.LocalPlayer
			volume *= surface.Volume * (if own then config.OwnVolumeScale else 1)
			range *= surface.Range
			local pitch = surface.Pitch * random:NextNumber(0.92, 1.08)
			Sound3D.Play(config.Id, feet, {
				volume = volume,
				range = range,
				pitch = pitch,
				treble = surface.Treble,
				bass = surface.Bass,
				-- The built-in sound is a loop of several steps; play just one
				duration = config.Duration,
				-- Your own steps don't need the wall check
				muffle = not own,
			})
			if surface.Layer then
				Sound3D.Play(Sounds.Pick(surface.Layer), feet, {
					volume = volume * surface.LayerVolume,
					range = range,
					pitch = random:NextNumber(1.3, 1.6), -- (a light ring, not a bang)
					duration = 0.25,
					muffle = not own,
				})
			end
		end
	end
end

-- Roblox's default character sounds (in the HumanoidRootPart) double up with ours. Mute them on
-- every character, including ones that get added later.
local DEFAULT_SOUND_NAMES = {
	Running = true,
	Jumping = true,
	Landing = true,
	FreeFalling = true,
	Climbing = true,
	GettingUp = true,
	Swimming = true,
	Splash = true,
	Died = true,
}

local function muteDefaultSounds(character: Model)
	local function mute(instance: Instance)
		if instance:IsA("Sound") and DEFAULT_SOUND_NAMES[instance.Name] and instance.Parent
			and instance.Parent.Name == "HumanoidRootPart"
		then
			instance.Volume = 0
		end
	end
	for _, descendant in character:GetDescendants() do
		mute(descendant)
	end
	character.DescendantAdded:Connect(mute)
end

function Footsteps.Start()
	local function watchPlayer(player: Player)
		if player.Character then
			muteDefaultSounds(player.Character)
		end
		player.CharacterAdded:Connect(muteDefaultSounds)
	end
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	Players.PlayerAdded:Connect(watchPlayer)

	RunService.Heartbeat:Connect(update)
end

return Footsteps
