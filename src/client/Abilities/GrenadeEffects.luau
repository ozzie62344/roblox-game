-- What grenades look and sound like (GadgetService throws them):
--   Smoke      once a canister's "SmokeEndsAt" is set it pours out a thick grey cloud with a hiss;
--              with your camera inside the cloud your screen fogs over, so it hides you both ways.
--   Flashbang  a bang and a burst of light for everyone. If you could see it go off (near enough,
--              nothing in the way of your eyes) you're whited out and your ears ring: longer the
--              closer you were and the more you were looking at it.

local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Sounds = require(ReplicatedStorage.Shared.Sounds)
local state = require(script.Parent.Parent.PlayerState)
local Effects = require(script.Parent.Parent.Combat.Effects)
local Sound3D = require(script.Parent.Parent.Audio.Sound3D)
local SoundCache = require(script.Parent.Parent.Audio.SoundCache)

local AbilityEffect = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("AbilityEffect") :: RemoteEvent

local player = Players.LocalPlayer

local GrenadeEffects = {}

local FILL_TIME = 1.2 -- seconds for a new cloud to get thick
local FADE_TIME = 3 -- seconds for it to thin out once the canister runs dry
local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"

type Cloud = { grenade: Model, emitter: ParticleEmitter, hiss: Sound, radius: number, endsAt: number, startedAt: number, stopped: boolean }
local clouds: { Cloud } = {}
local fog: Frame
local whiteout: Frame
local blur: BlurEffect

local function startCloud(grenade: Model)
	local body = grenade.PrimaryPart
	if not body then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Parent = body
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = SMOKE_TEXTURE
	emitter.Color = ColorSequence.new(Color3.fromRGB(208, 210, 208), Color3.fromRGB(172, 175, 172))
	emitter.LightInfluence = 0.8
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.08, 0.05),
		NumberSequenceKeypoint.new(0.75, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 3),
		NumberSequenceKeypoint.new(0.25, 9),
		NumberSequenceKeypoint.new(1, 12),
	})
	emitter.Lifetime = NumberRange.new(7, 10)
	emitter.Rate = 22
	emitter.Speed = NumberRange.new(6, 11)
	emitter.Drag = 1.2 -- (slows them down so the cloud stays put instead of spraying away)
	emitter.SpreadAngle = Vector2.new(85, 85)
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Acceleration = Vector3.new(0, 0.4, 0)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-15, 15)
	emitter.Parent = attachment
	emitter:Emit(40) -- an instant wall of smoke, then it keeps pouring

	local config = Sounds.SmokeHiss
	local hiss = SoundCache.New(config.Id)
	hiss.Looped = true
	hiss.Volume = config.Volume
	hiss.PlaybackSpeed = config.Pitch
	hiss.RollOffMode = Enum.RollOffMode.Linear
	hiss.RollOffMinDistance = 4
	hiss.RollOffMaxDistance = config.Range
	hiss.Parent = body
	hiss:Play()

	table.insert(clouds, {
		grenade = grenade,
		emitter = emitter,
		hiss = hiss,
		radius = grenade:GetAttribute("SmokeRadius") or 11,
		endsAt = grenade:GetAttribute("SmokeEndsAt"),
		startedAt = os.clock(),
		stopped = false,
	})
end

local function update()
	-- New clouds (the server sets SmokeEndsAt when the fuse runs out)
	local folder = Workspace:FindFirstChild("Deployables")
	for _, grenade in if folder then folder:GetChildren() else {} do
		if grenade.Name == "SmokeGrenade" and grenade:IsA("Model") and typeof(grenade:GetAttribute("SmokeEndsAt")) == "number" and not grenade:GetAttribute("CloudStarted") then
			grenade:SetAttribute("CloudStarted", true) -- (only on this client)
			startCloud(grenade)
		end
	end

	-- How deep inside a cloud your camera is → how thick the fog on your screen
	local now = Workspace:GetServerTimeNow()
	local camera = Workspace.CurrentCamera.CFrame.Position
	local thickest = 0
	for i = #clouds, 1, -1 do
		local cloud = clouds[i]
		local body = cloud.grenade.PrimaryPart
		if not cloud.grenade.Parent or not body then
			table.remove(clouds, i)
			continue
		end
		if not cloud.stopped and now >= cloud.endsAt then
			cloud.stopped = true
			cloud.emitter.Rate = 0
			TweenService:Create(cloud.hiss, TweenInfo.new(1), { Volume = 0 }):Play()
		end
		local strength = math.min(math.clamp((os.clock() - cloud.startedAt) / FILL_TIME, 0, 1), math.clamp(1 - (now - cloud.endsAt) / FADE_TIME, 0, 1))
		if strength > 0 then
			-- A dome sitting on the floor (flattened: vertical distance counts for more)
			local offset = camera - (body.Position + Vector3.new(0, cloud.radius * 0.3, 0))
			local depth = 1 - Vector3.new(offset.X, offset.Y * 1.6, offset.Z).Magnitude / cloud.radius
			thickest = math.max(thickest, math.clamp(depth * 1.8, 0, 1) * strength)
		end
	end
	fog.Visible = thickest > 0.01
	fog.BackgroundTransparency = 1 - 0.93 * thickest
end

-- Your ears ring and everything else goes dull (Sound3D reads state.deafUntil)
local function deafen(strength: number)
	if strength <= 0.05 then
		return
	end
	local duration = 1 + 3 * strength
	if os.clock() + duration > state.deafUntil then
		state.deafUntil = os.clock() + duration
		state.deafStrength = strength
	end
	local ring = SoundCache.New(Sounds.EarRing.Id)
	ring.Volume = Sounds.EarRing.Volume * strength
	ring.Parent = SoundService
	ring:Play()
	TweenService:Create(ring, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Volume = 0 }):Play()
	Debris:AddItem(ring, duration + 0.2)
end

-- White screen, held for a moment, then fading; a blur that clears with it
local function blind(strength: number, duration: number)
	whiteout.BackgroundTransparency = 1 - math.min(1, 0.35 + strength)
	local hold = duration * 0.35
	TweenService:Create(whiteout, TweenInfo.new(duration - hold, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, hold), { BackgroundTransparency = 1 }):Play()
	blur.Size = 28 * strength
	TweenService:Create(blur, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Size = 0 }):Play()
end

local function onFlashbang(position: Vector3, radius: number, maxDuration: number)
	local config = Sounds.Flashbang
	Sound3D.Play(Sounds.Pick("Explosion"), position, { volume = config.Volume, range = config.Range, pitch = config.Pitch })
	-- A split-second burst of light where it went off (everyone sees this, through windows too)
	local glow = Instance.new("Part")
	glow.Anchored = true
	glow.CanCollide = false
	glow.CanQuery = false
	glow.CanTouch = false
	glow.Transparency = 1
	glow.Size = Vector3.one
	glow.Position = position
	glow.Parent = Effects.GetFolder()
	local light = Instance.new("PointLight")
	light.Brightness = 14
	light.Range = 36
	light.Color = Color3.fromRGB(255, 252, 240)
	light.Parent = glow
	TweenService:Create(light, TweenInfo.new(0.4), { Brightness = 0 }):Play()
	Debris:AddItem(glow, 0.5)

	-- Did it get me? Measured from my eyes (my body's, while I'm driving a drone or on cameras)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local head = character and character:FindFirstChild("Head") :: BasePart?
	if not humanoid or humanoid.Health <= 0 or not head or state.inLobby or state.spectating then
		return
	end
	local camera = Workspace.CurrentCamera.CFrame
	local eye = if state.droning then head.Position else camera.Position
	local offset = position - eye
	local distance = offset.Magnitude
	if distance > radius then
		return
	end
	local ignore: { Instance } = { Effects.GetFolder() }
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(ignore, other.Character)
		end
	end
	local deployables = Workspace:FindFirstChild("Deployables")
	if deployables then
		table.insert(ignore, deployables)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local closeness = 1 - distance / radius
	if Workspace:Raycast(eye, offset, params) then
		deafen(closeness * 0.4) -- went off behind a wall: loud, but you didn't see it
		return
	end
	local facing = if state.droning then 0 else math.max(camera.LookVector:Dot(offset.Unit), 0)
	local strength = closeness ^ 0.6 * (0.4 + 0.6 * facing)
	if distance < 5 then
		strength = math.max(strength, 0.8) -- right next to you: looking away won't save you
	end
	blind(strength, math.max(0.6, maxDuration * strength))
	deafen(strength)
end

function GrenadeEffects.Start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "GrenadeEffects"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 40 -- over the HUD
	gui.Parent = player:WaitForChild("PlayerGui")
	fog = Instance.new("Frame")
	fog.Size = UDim2.fromScale(1, 1)
	fog.BackgroundColor3 = Color3.fromRGB(172, 175, 172)
	fog.BorderSizePixel = 0
	fog.Visible = false
	fog.Parent = gui
	whiteout = Instance.new("Frame")
	whiteout.Size = UDim2.fromScale(1, 1)
	whiteout.BackgroundColor3 = Color3.new(1, 1, 1)
	whiteout.BackgroundTransparency = 1
	whiteout.BorderSizePixel = 0
	whiteout.Parent = gui
	blur = Instance.new("BlurEffect")
	blur.Name = "FlashBlur"
	blur.Size = 0
	blur.Parent = Lighting

	AbilityEffect.OnClientEvent:Connect(function(kind: string, ...)
		if kind == "Flashbang" then
			onFlashbang(...)
		end
	end)
	RunService.RenderStepped:Connect(update)
end

return GrenadeEffects
