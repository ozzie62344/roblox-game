-- Plays positional sounds with a clear audible range, muffled by what's between the sound and
-- your camera (like hearing someone through a wall in Siege): each wall makes it quieter and
-- duller, and a floor / ceiling in the way turns it into a deep thump from above or below.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Sounds = require(ReplicatedStorage.Shared.Sounds)
local SoundCache = require(script.Parent.SoundCache)
local state = require(script.Parent.Parent.PlayerState)

local Sound3D = {}

export type Options = {
	volume: number?,
	range: number?,
	pitch: number?,
	muffle: boolean?, -- check for walls (default true)
	duration: number?, -- cut the sound off after this many seconds
	treble: number?, -- tone in dB (footstep surfaces)
	bass: number?,
}

-- How many walls (up to Sounds.MaxWalls) are between your camera and `position`, and whether one
-- of them is a floor or ceiling
function Sound3D.Obstruction(position: Vector3): (number, boolean)
	local camera = Workspace.CurrentCamera
	local ignore: { Instance } = { camera }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	for _, name in { "ClientEffects", "Dummies" } do
		local folder = Workspace:FindFirstChild(name)
		if folder then
			table.insert(ignore, folder)
		end
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local from = camera.CFrame.Position
	local walls, throughFloor = 0, false
	-- Step through one surface at a time (a ray that starts inside a part doesn't hit it again)
	while walls < Sounds.MaxWalls do
		local toSound = position - from
		if toSound.Magnitude < 0.1 then
			break
		end
		local hit = Workspace:Raycast(from, toSound, params)
		if not hit then
			break
		end
		walls += 1
		throughFloor = throughFloor or math.abs(hit.Normal.Y) > 0.7
		from = hit.Position + toSound.Unit * 0.05
	end
	return walls, throughFloor
end

-- Make `sound` sound like it's behind `walls` walls (and a floor). Replaces any earlier muffle.
function Sound3D.Muffle(sound: Sound, walls: number, throughFloor: boolean)
	local eq = sound:FindFirstChild("Muffle") :: EqualizerSoundEffect?
	if walls == 0 then
		if eq then
			eq:Destroy()
		end
		return
	end
	if not eq then
		eq = Instance.new("EqualizerSoundEffect")
		eq.Name = "Muffle"
		eq.Parent = sound
	end
	local muffle = eq :: EqualizerSoundEffect
	if throughFloor then
		muffle.HighGain, muffle.MidGain, muffle.LowGain = -32, -12, 5 -- deep thump from upstairs / downstairs
	else
		muffle.HighGain, muffle.MidGain, muffle.LowGain = -8 - 10 * walls, -3 - 3 * walls, 2
	end
end

function Sound3D.Play(soundId: string, position: Vector3, options: Options?)
	if soundId == "" then
		return
	end
	local opts: Options = options or {}
	local range = opts.range or 100

	-- Out of earshot: don't bother creating anything
	local listener = Workspace.CurrentCamera.CFrame.Position
	if (listener - position).Magnitude > range then
		return
	end

	local attachment = Instance.new("Attachment")
	attachment.WorldPosition = position
	attachment.Parent = Workspace.Terrain

	local sound = SoundCache.New(soundId) -- preloaded copy, so it starts instantly
	sound.Volume = opts.volume or 0.6
	sound.PlaybackSpeed = opts.pitch or 1
	sound.RollOffMode = Enum.RollOffMode.Linear
	sound.RollOffMinDistance = 4
	sound.RollOffMaxDistance = range

	if opts.treble or opts.bass then
		local tone = Instance.new("EqualizerSoundEffect")
		tone.HighGain = opts.treble or 0
		tone.LowGain = opts.bass or 0
		tone.Parent = sound
	end
	if opts.muffle ~= false then
		local walls, throughFloor = Sound3D.Obstruction(position)
		sound.Volume *= Sounds.MuffleVolumeScale ^ walls
		Sound3D.Muffle(sound, walls, throughFloor)
	end
	-- Ears still ringing from a flashbang: everything comes through dull and quiet
	local deaf = state.deafStrength * math.clamp((state.deafUntil - os.clock()) / 2, 0, 1)
	if deaf > 0 then
		sound.Volume *= 1 - 0.75 * deaf
		local dull = Instance.new("EqualizerSoundEffect")
		dull.HighGain, dull.MidGain = -30 * deaf, -12 * deaf
		dull.Parent = sound
	end

	sound.Parent = attachment
	sound:Play()
	if opts.duration then
		task.delay(opts.duration, function()
			sound:Stop()
		end)
	end
	Debris:AddItem(attachment, 4)
end

-- One of the round's big tells (Sounds.Events) at `position`
function Sound3D.PlayEvent(name: string, position: Vector3)
	local event = Sounds.Events[name]
	if event then
		Sound3D.Play(Sounds.EventId(name), position, { volume = event.Volume, range = event.Range, pitch = event.Pitch })
	end
end

return Sound3D
