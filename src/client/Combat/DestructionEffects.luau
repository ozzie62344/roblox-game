-- What you see and hear when something breaks (the server cuts the actual holes, see
-- DestructionService): chunks in the broken part's color and material, a puff of dust, a sound.
--   Hole  = a bullet punching through drywall or boards (a few chips, quiet crunch)
--   Chunk = the knife knocking a piece out of a wall or barricade
--   Smash = a whole barricade broken down
--   Glass = a window pane shattering
--   Blast = a breach charge / thermite going off against a wall
--   Spark = electronics getting fried or shot (shock wire, jammer, EMP)

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Sounds = require(ReplicatedStorage.Shared.Sounds)
local Effects = require(script.Parent.Effects)
local Sound3D = require(script.Parent.Parent.Audio.Sound3D)

local DestructionEvent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Destruction") :: RemoteEvent

local DestructionEffects = {}

local random = Random.new()

local function chunk(position: Vector3, size: Vector3, color: Color3, material: Enum.Material, speed: number, transparency: number?)
	local part = Instance.new("Part")
	part.Size = size
	part.CFrame = CFrame.new(position) * CFrame.Angles(random:NextNumber(0, 6.3), random:NextNumber(0, 6.3), 0)
	part.Color = color
	part.Material = material
	part.Transparency = transparency or 0
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.AssemblyLinearVelocity = random:NextUnitVector() * speed + Vector3.new(0, speed * 0.4, 0)
	part.Parent = Effects.GetFolder()
	Debris:AddItem(part, random:NextNumber(2, 3.5))
end

local function dust(position: Vector3, color: Color3, amount: number)
	local attachment = Instance.new("Attachment")
	attachment.WorldPosition = position
	attachment.Parent = workspace.Terrain
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.3))
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 2.2) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
	emitter.Lifetime = NumberRange.new(0.6, 1.3)
	emitter.Speed = NumberRange.new(1, 4)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Drag = 3
	emitter.Enabled = false
	emitter.Parent = attachment
	emitter:Emit(amount)
	Debris:AddItem(attachment, 1.5)
end

local function play(setName: string, position: Vector3, volume: number)
	Sound3D.Play(Sounds.Pick(setName), position, {
		volume = volume,
		range = Sounds.Destruction.Range,
		pitch = random:NextNumber(0.92, 1.08),
	})
end

local function onDestruction(kind: string, point: Vector3, size: number, color: Color3, material: Enum.Material)
	local wood = material == Enum.Material.WoodPlanks or material == Enum.Material.Wood
	local breakSound = if wood then "WoodBreak" else "DrywallBreak"
	local config = Sounds.Destruction

	if kind == "Blast" then
		for _ = 1, 30 do
			local offset = Vector3.new(random:NextNumber(-1, 1) * size * 0.4, random:NextNumber(-3, 3), random:NextNumber(-1, 1) * size * 0.4)
			chunk(point + offset, Vector3.one * random:NextNumber(0.25, 0.8), color, material, 22)
		end
		dust(point, color, 45)
		Sound3D.Play(Sounds.Pick("Explosion"), point, { volume = config.BlastVolume, range = config.BlastRange, muffle = false })
	elseif kind == "Spark" then
		for _ = 1, 10 * size do
			chunk(point, Vector3.one * random:NextNumber(0.06, 0.14), color, Enum.Material.Neon, 14)
		end
		play("Zap", point, config.ZapVolume)
	elseif kind == "Glass" then
		for _ = 1, 16 do
			local offset = Vector3.new(random:NextNumber(-1, 1), random:NextNumber(-1, 1), random:NextNumber(-1, 1)) * size * 0.4
			local shard = Vector3.new(random:NextNumber(0.15, 0.5), random:NextNumber(0.15, 0.6), 0.04)
			chunk(point + offset, shard, color, Enum.Material.Glass, 6, 0.4)
		end
		play("GlassBreak", point, config.GlassVolume)
	elseif kind == "Hole" then
		for _ = 1, 3 do
			chunk(point, Vector3.one * random:NextNumber(0.08, 0.18), color, material, 8)
		end
		dust(point, color, 4)
		play(breakSound, point, config.HoleVolume)
	elseif kind == "Chunk" or kind == "Smash" then
		local count = if kind == "Smash" then 18 else 9
		for _ = 1, count do
			local offset = random:NextUnitVector() * size * 0.3
			local piece = if wood
				then Vector3.new(random:NextNumber(0.6, 1.6), 0.15, random:NextNumber(0.25, 0.4))
				else Vector3.one * random:NextNumber(0.2, 0.55)
			chunk(point + offset, piece, color, material, 10)
		end
		dust(point, color, if kind == "Smash" then 20 else 10)
		play(breakSound, point, if kind == "Smash" then config.SmashVolume else config.ChunkVolume)
	end
end

function DestructionEffects.Start()
	DestructionEvent.OnClientEvent:Connect(onDestruction)
end

return DestructionEffects
