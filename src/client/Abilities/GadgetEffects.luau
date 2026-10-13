-- What the operator gadgets do on your side (GadgetService runs them on the server):
--   Heartbeat Sensor  while you scan, the server sends where the enemies in range are every 0.6 s:
--                     each one pulses as a red heartbeat through walls and floors (only you see
--                     them), with a soft thump whenever anyone's there
--   Barbed Wire       inside a coil, your speed across the ground is capped right after physics
--                     each frame (MovementController takes the slower speed as what really
--                     happened and carries on from there), and everyone hears it rattle when
--                     someone wades through (WireRattle)

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Sounds = require(ReplicatedStorage.Shared.Sounds)
local state = require(script.Parent.Parent.PlayerState)
local Hud = require(script.Parent.Parent.Combat.Hud)
local Effects = require(script.Parent.Parent.Combat.Effects)
local Sound3D = require(script.Parent.Parent.Audio.Sound3D)
local SoundCache = require(script.Parent.Parent.Audio.SoundCache)

local AbilityEffect = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("AbilityEffect") :: RemoteEvent

local player = Players.LocalPlayer

local GadgetEffects = {}

local HEART_COLOR = Color3.fromRGB(255, 60, 75)
local WIRE_COLOR = Color3.fromRGB(190, 195, 180)
local WIRE_SPEED = 4.5 -- studs/second you can move through wire (walking is 18)
local BEAT_TIME = 0.6 -- each pulse lasts until the next one comes in

local inWire = false

-- One heartbeat: a dot with a ring growing out of it, drawn over everything
local function beat(position: Vector3)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one * 0.1
	anchor.Position = position
	anchor.Parent = Effects.GetFolder()
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(46, 46)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Adornee = anchor
	local function circle(size: number): Frame
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.fromScale(0.5, 0.5)
		f.Size = UDim2.fromScale(size, size)
		f.BorderSizePixel = 0
		f.BackgroundColor3 = HEART_COLOR
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = f
		f.Parent = gui
		return f
	end
	local dot = circle(0.32)
	local ring = circle(0.32)
	ring.BackgroundTransparency = 1
	local stroke = Instance.new("UIStroke")
	stroke.Color = HEART_COLOR
	stroke.Thickness = 2
	stroke.Parent = ring
	gui.Parent = player.PlayerGui -- 3D GUIs don't draw inside a ScreenGui
	local info = TweenInfo.new(BEAT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(ring, info, { Size = UDim2.fromScale(1, 1) }):Play()
	TweenService:Create(stroke, info, { Transparency = 1 }):Play()
	TweenService:Create(dot, TweenInfo.new(BEAT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { BackgroundTransparency = 1 }):Play()
	Debris:AddItem(gui, BEAT_TIME + 0.05)
	Debris:AddItem(anchor, BEAT_TIME + 0.05)
end

local function thump()
	local config = Sounds.ChargeBeep
	local sound = SoundCache.New(config.Id)
	sound.Volume = config.Volume * 0.5
	sound.PlaybackSpeed = 0.45 -- low and soft: a pulse, not an alarm
	sound.Parent = SoundService
	sound:Play()
	Debris:AddItem(sound, 1)
end

local function onHeartbeat(beats: { Vector3 }, remaining: number)
	for _, position in beats do
		beat(position)
	end
	if #beats > 0 then
		thump()
	end
	local stop = if state.touchControls then "TAP AGAIN TO STOP" else "X TO STOP"
	local contacts = if #beats == 0 then "NO HEARTBEATS" elseif #beats == 1 then "1 HEARTBEAT" else `{#beats} HEARTBEATS`
	Hud.ShowStatus(`SENSOR  ·  {contacts}  ·  {stop}`, math.max(remaining, 0.6), HEART_COLOR)
end

-- Inside a wire's zone (the invisible box over the coil)?
local function wireAt(position: Vector3): boolean
	local folder = Workspace:FindFirstChild("Deployables")
	for _, wire in if folder then folder:GetChildren() else {} do
		local zone = wire.Name == "BarbedWire" and wire:FindFirstChild("Zone")
		if zone and zone:IsA("BasePart") then
			local p = zone.CFrame:PointToObjectSpace(position)
			local half = zone.Size / 2
			if math.abs(p.X) <= half.X and math.abs(p.Y) <= half.Y and math.abs(p.Z) <= half.Z then
				return true
			end
		end
	end
	return false
end

-- After physics: cap your speed while you're in wire
local function slowInWire()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local wired = humanoid ~= nil and humanoid.Health > 0 and root ~= nil and wireAt(root.Position)
	if wired ~= inWire then
		inWire = wired
		if wired then
			Hud.ShowStatus("BARBED WIRE", 1.2, WIRE_COLOR)
		end
	end
	if not wired or not root then
		return
	end
	local velocity = root.AssemblyLinearVelocity
	local flat = Vector3.new(velocity.X, 0, velocity.Z)
	if flat.Magnitude > WIRE_SPEED then
		flat = flat.Unit * WIRE_SPEED
		root.AssemblyLinearVelocity = Vector3.new(flat.X, math.min(velocity.Y, 12), flat.Z) -- (no hopping over it either)
	end
end

local function rattle(position: Vector3)
	Sound3D.Play(Sounds.Pick("MetalStep"), position, { volume = 0.8, range = 75, pitch = 1.45 })
	Sound3D.Play(Sounds.Rappel.Zip, position, { volume = 0.3, range = 75, pitch = 1.3, duration = 0.4 })
end

function GadgetEffects.Start()
	AbilityEffect.OnClientEvent:Connect(function(kind: string, ...)
		if kind == "Heartbeat" then
			onHeartbeat(...)
		elseif kind == "HeartbeatStart" then
			Hud.ShowStatus("SENSOR  ·  LISTENING", 1, HEART_COLOR)
		elseif kind == "HeartbeatEnd" then
			Hud.ShowStatus("SENSOR PUT AWAY", 1)
		elseif kind == "WireRattle" then
			rattle(...)
		end
	end)
	RunService.PostSimulation:Connect(slowInWire)
end

return GadgetEffects
