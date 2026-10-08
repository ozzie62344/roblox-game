-- Visual and audio effects for shots: tracers, impacts, sounds.
-- Used for your own shots and for other players' shots (ShotFired from the server).

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Effects = {}

local folder: Folder? = nil

-- Client-only folder for effect parts (not replicated, ignored by raycasts)
function Effects.GetFolder(): Folder
	if not folder or not folder.Parent then
		local newFolder = Instance.new("Folder")
		newFolder.Name = "ClientEffects"
		newFolder.Parent = Workspace
		folder = newFolder
	end
	return folder :: Folder
end

local function effectPart(size: Vector3, cframe: CFrame, color: Color3): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Size = size
	part.CFrame = cframe
	part.Parent = Effects.GetFolder()
	return part
end

function Effects.Tracer(from: Vector3, to: Vector3)
	local length = (to - from).Magnitude
	if length < 0.5 then
		return
	end
	local tracer = effectPart(
		Vector3.new(0.06, 0.06, length),
		CFrame.lookAt(from, to) * CFrame.new(0, 0, -length / 2),
		Color3.fromRGB(255, 220, 140)
	)
	tracer.Transparency = 0.3
	TweenService:Create(tracer, TweenInfo.new(0.08), { Transparency = 1 }):Play()
	Debris:AddItem(tracer, 0.1)
end

function Effects.Impact(position: Vector3, normal: Vector3?)
	local facing = if normal then CFrame.lookAt(position, position + normal) else CFrame.new(position)
	local spark = effectPart(Vector3.new(0.25, 0.25, 0.25), facing, Color3.fromRGB(255, 200, 120))
	TweenService:Create(spark, TweenInfo.new(0.15), { Size = Vector3.new(0.05, 0.05, 0.05), Transparency = 1 })
		:Play()
	Debris:AddItem(spark, 0.2)

	local hole = effectPart(Vector3.new(0.18, 0.18, 0.02), facing, Color3.fromRGB(25, 25, 25))
	hole.Material = Enum.Material.SmoothPlastic
	Debris:AddItem(hole, 6)
end

-- Plays a sound in 3D at a position (other players' gunshots), or flat if no position (your own)
function Effects.Sound(soundId: string, position: Vector3?, volume: number?, pitch: number?)
	if soundId == "" then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume or 0.6
	sound.PlaybackSpeed = pitch or 1
	sound.RollOffMaxDistance = 400

	if position then
		local attachment = Instance.new("Attachment")
		attachment.WorldPosition = position
		attachment.Parent = Workspace.Terrain
		sound.Parent = attachment
		Debris:AddItem(attachment, 4)
	else
		sound.Parent = Workspace.CurrentCamera
		Debris:AddItem(sound, 4)
	end
	sound:Play()
end

return Effects
