-- Plays positional sounds with a clear audible range, muffled when a wall is between
-- the sound and your camera (like hearing someone through a wall in Siege).

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Sounds = require(ReplicatedStorage.Shared.Sounds)

local Sound3D = {}

export type Options = {
	volume: number?,
	range: number?,
	pitch: number?,
	muffle: boolean?, -- check for walls (default true)
	duration: number?, -- cut the sound off after this many seconds
}

local function isOccluded(position: Vector3): boolean
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
	return Workspace:Raycast(from, position - from, params) ~= nil
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

	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = opts.volume or 0.6
	sound.PlaybackSpeed = opts.pitch or 1
	sound.RollOffMode = Enum.RollOffMode.Linear
	sound.RollOffMinDistance = 4
	sound.RollOffMaxDistance = range

	if opts.muffle ~= false and isOccluded(position) then
		sound.Volume *= Sounds.MuffleVolumeScale
		local eq = Instance.new("EqualizerSoundEffect")
		eq.HighGain = -25
		eq.MidGain = -8
		eq.LowGain = 2
		eq.Parent = sound
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

return Sound3D
