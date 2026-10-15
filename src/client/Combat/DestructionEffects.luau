-- What you see and hear when something breaks (the server cuts the actual holes, see
-- DestructionService): chunks in the broken part's color and material, a puff of dust, a sound.
--   Hole  = a bullet punching through drywall, boards or sheet metal (a few chips, quiet crunch,
--           and a pinhole mark drawn right through the surface)
--   Chunk = a hole knocked out of a wall, floor or barricade (knife, shotgun blast, a cell of
--           wall shot through): debris by how big it is
--   Smash = a whole barricade / hatch cover broken down
--   Glass = a window pane shattering
--   Blast = a breach charge / impact grenade / thermite going off
--   Spark = electronics getting fried or shot (shock wire, jammer, EMP)
--   Ping  = a hit on steel (a reinforced wall or hatch): sparks and a clang
-- Debris, sounds and splinters depend on the material: drywall / plaster (chunks and white dust),
-- wood (splinters), metal (thin shards, sparks, a metal clang).
-- The server sends one "Batch" a frame holding all of these; the older single-effect form
-- (kind, point, size, color, material) still works. Debris, dust, sounds and marks are capped.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Sounds = require(ReplicatedStorage.Shared.Sounds)
local Effects = require(script.Parent.Effects)
local Sound3D = require(script.Parent.Parent.Audio.Sound3D)

local DestructionEvent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Destruction") :: RemoteEvent

local DestructionEffects = {}

local MAX_DEBRIS = 150 -- flying chunks alive at once; past this new ones are skipped
local MAX_DUST = 16 -- dust puffs alive at once
local MAX_SOUNDS = 6 -- breaking sounds per SOUND_WINDOW (a spray into a wall doesn't stack 30 crunches)
local SOUND_WINDOW = 0.1 -- seconds
local MAX_MARKS = 300 -- pinhole marks kept; the oldest go first
local MARK_PROUD = 0.03 -- studs a mark stands out of each face (so it draws over the wall)
local MARK_COLOR = Color3.fromRGB(26, 22, 20)
local PING_VOLUME = 0.55 -- a hit on steel (Sounds' MetalStep set: metal impacts)
local WOOD = { [Enum.Material.WoodPlanks] = true, [Enum.Material.Wood] = true }
local METAL = { [Enum.Material.Metal] = true, [Enum.Material.DiamondPlate] = true, [Enum.Material.CorrodedMetal] = true, [Enum.Material.Foil] = true }

local random = Random.new()
local liveDebris, liveDust = 0, 0
local soundWindowStart, soundsInWindow = 0, 0
local marks: { BasePart } = {}

local function chunk(position: Vector3, size: Vector3, color: Color3, material: Enum.Material, speed: number, transparency: number?)
	if liveDebris >= MAX_DEBRIS then
		return
	end
	local part = Instance.new("Part")
	part.Size = size
	part.CFrame = CFrame.new(position) * CFrame.Angles(random:NextNumber(0, 6.3), random:NextNumber(0, 6.3), 0)
	part.Color = color
	part.Material = material
	part.Transparency = transparency or 0
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.CollisionGroup = "Debris" -- (bounces off the floor and walls, never off people: MapService)
	part.AssemblyLinearVelocity = random:NextUnitVector() * speed + Vector3.new(0, speed * 0.4, 0)
	part.Parent = Effects.GetFolder()
	liveDebris += 1
	task.delay(random:NextNumber(2, 3.5), function()
		liveDebris -= 1
		part:Destroy()
	end)
end

local function dust(position: Vector3, color: Color3, amount: number)
	if liveDust >= MAX_DUST then
		return
	end
	liveDust += 1
	task.delay(1.5, function()
		liveDust -= 1
	end)
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
	task.delay(1.5, function()
		attachment:Destroy()
	end)
end

local function play(setName: string, position: Vector3, volume: number)
	local now = os.clock()
	if now - soundWindowStart > SOUND_WINDOW then
		soundWindowStart, soundsInWindow = now, 0
	end
	if soundsInWindow >= MAX_SOUNDS then
		return
	end
	soundsInWindow += 1
	Sound3D.Play(Sounds.Pick(setName), position, {
		volume = volume,
		range = Sounds.Destruction.Range,
		pitch = random:NextNumber(0.92, 1.08),
	})
end

-- A pinhole: a dark sliver right through the surface (`depth` = from the face hit to the other
-- face), kept with the barricade / hatch / map it's in, so it goes when that does
local function pinhole(point: Vector3, depth: Vector3, holder: Instance?)
	local length = depth.Magnitude
	if length < 0.05 then
		return
	end
	local axis = depth / length
	local center = point + depth / 2
	local up = if math.abs(axis.Y) > 0.9 then Vector3.xAxis else Vector3.yAxis
	local width = random:NextNumber(0.1, 0.17)
	local mark = Instance.new("Part")
	mark.Name = "Pinhole"
	mark.Size = Vector3.new(width, width, length + MARK_PROUD * 2)
	mark.CFrame = CFrame.lookAt(center, center + axis, up) * CFrame.Angles(0, 0, random:NextNumber(0, math.pi / 2))
	mark.Color = MARK_COLOR
	mark.Material = Enum.Material.SmoothPlastic
	mark.Anchored = true
	mark.CanCollide = false
	mark.CanQuery = false
	mark.CanTouch = false
	mark.CastShadow = false
	mark.Parent = if holder and holder.Parent then holder else Effects.GetFolder()
	table.insert(marks, mark)
	if #marks > MAX_MARKS then
		local oldest = table.remove(marks, 1)
		if oldest then
			oldest:Destroy()
		end
	end
end

-- A hole was cut: the marks that were in it would be left floating
local function clearMarks(point: Vector3, radius: number)
	for i = #marks, 1, -1 do
		local mark = marks[i]
		if not mark.Parent or (mark.Position - point).Magnitude < radius then
			mark:Destroy()
			table.remove(marks, i)
		end
	end
end

local function onDestruction(kind: string, point: Vector3, size: number, color: Color3, material: Enum.Material, depth: Vector3?, holder: Instance?)
	local wood = WOOD[material] == true
	local metal = METAL[material] == true
	local breakSound = if wood then "WoodBreak" elseif metal then "MetalStep" else "DrywallBreak"
	local config = Sounds.Destruction

	if kind == "Blast" then
		clearMarks(point, size * 0.95)
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
	elseif kind == "Ping" then
		-- Steel: a few sparks and a clang, nothing comes off
		for _ = 1, 5 do
			chunk(point, Vector3.one * random:NextNumber(0.05, 0.1), Color3.fromRGB(255, 200, 120), Enum.Material.Neon, 12)
		end
		play("MetalStep", point, PING_VOLUME)
	elseif kind == "Glass" then
		for _ = 1, 16 do
			local offset = Vector3.new(random:NextNumber(-1, 1), random:NextNumber(-1, 1), random:NextNumber(-1, 1)) * size * 0.4
			local shard = Vector3.new(random:NextNumber(0.15, 0.5), random:NextNumber(0.15, 0.6), 0.04)
			chunk(point + offset, shard, color, Enum.Material.Glass, 6, 0.4)
		end
		play("GlassBreak", point, config.GlassVolume)
	elseif kind == "Hole" then
		for _ = 1, 3 do
			local chip = if wood
				then Vector3.new(random:NextNumber(0.2, 0.45), 0.05, random:NextNumber(0.05, 0.1))
				elseif metal then Vector3.new(random:NextNumber(0.08, 0.16), 0.03, random:NextNumber(0.08, 0.16))
				else Vector3.one * random:NextNumber(0.08, 0.18)
			chunk(point, chip, color, material, 8)
		end
		if not metal then
			dust(point, color, 4)
		end
		if depth then
			pinhole(point, depth, holder)
		end
		play(breakSound, point, config.HoleVolume)
	elseif kind == "Chunk" or kind == "Smash" then
		if kind == "Chunk" then
			clearMarks(point, size * 0.75 + 0.1)
		end
		-- More debris out of a bigger hole
		local count = if kind == "Smash" then 18 else math.clamp(math.round(4 + size * 5), 5, 16)
		for _ = 1, count do
			local offset = random:NextUnitVector() * size * 0.3
			local piece = if wood
				then Vector3.new(random:NextNumber(0.6, 1.6), 0.15, random:NextNumber(0.25, 0.4)) -- splinters
				elseif metal then Vector3.new(random:NextNumber(0.25, 0.6), 0.04, random:NextNumber(0.2, 0.45)) -- torn sheet
				else Vector3.one * random:NextNumber(0.2, 0.55)
			chunk(point + offset, piece, color, material, 10)
		end
		if metal then
			for _ = 1, 4 do
				chunk(point, Vector3.one * random:NextNumber(0.05, 0.1), Color3.fromRGB(255, 200, 120), Enum.Material.Neon, 12)
			end
		end
		dust(point, color, if kind == "Smash" then 20 elseif metal then 4 else math.round(6 + size * 4))
		play(breakSound, point, if kind == "Smash" then config.SmashVolume else config.ChunkVolume)
	end
end

-- One "Batch" of effects a frame from DestructionService, or one effect on its own (the older
-- form, still sent by FortifyService / GadgetService)
local function onEvent(kind: string, ...: any)
	if kind ~= "Batch" then
		onDestruction(kind, ...)
		return
	end
	local batch = ...
	if typeof(batch) ~= "table" then
		return
	end
	for _, effect in batch do
		local depth = effect[6]
		onDestruction(effect[1], effect[2], effect[3], effect[4], effect[5], if typeof(depth) == "Vector3" then depth else nil, effect[7])
	end
end

function DestructionEffects.Start()
	DestructionEvent.OnClientEvent:Connect(onEvent)
	-- A new map: the old one's marks went with it (forget them)
	Workspace.ChildRemoved:Connect(function(child)
		if child.Name == "Map" then
			clearMarks(Vector3.zero, 0)
		end
	end)
end

return DestructionEffects
