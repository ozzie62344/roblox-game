-- Drones whine while they drive: a looped servo sound on every drone, louder and higher the faster
-- it goes, silent when it's parked, and muffled through walls like other sounds (Sound3D). So you
-- can hear an enemy drone rolling around near you, the way you can in Siege.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Sounds = require(ReplicatedStorage.Shared.Sounds)
local SoundCache = require(script.Parent.SoundCache)
local Sound3D = require(script.Parent.Sound3D)

local DroneHum = {}

local TOP_SPEED = 13 -- DroneController's driving speed
local MUFFLE_EVERY = 0.25 -- seconds between wall checks

local lastMuffle = 0

local function update()
	local folder = Workspace:FindFirstChild("Deployables")
	local config = Sounds.DroneMotor
	local now = os.clock()
	local recheck = now - lastMuffle >= MUFFLE_EVERY
	if recheck then
		lastMuffle = now
	end
	for _, drone in if folder then folder:GetChildren() else {} do
		local body = drone.Name == "Drone" and drone:IsA("Model") and drone.PrimaryPart
		if not body then
			continue
		end
		-- (found by name: a weak table keyed by the part can lose it while the drone still exists)
		local hum = body:FindFirstChild("DroneHum") :: Sound?
		if not hum then
			hum = SoundCache.New(config.Id)
			hum.Name = "DroneHum"
			hum.Looped = true
			hum.Volume = 0
			hum.RollOffMode = Enum.RollOffMode.Linear
			hum.RollOffMinDistance = 3
			hum.RollOffMaxDistance = config.Range
			hum.Parent = body
			hum:Play()
		end
		local velocity = body.AssemblyLinearVelocity
		local speed = math.clamp(Vector3.new(velocity.X, 0, velocity.Z).Magnitude / TOP_SPEED, 0, 1)
		local walls, throughFloor = 0, false
		if recheck then
			-- (just above the drone: from your own drone's camera the body itself would count as a wall)
			walls, throughFloor = Sound3D.Obstruction(body.Position + Vector3.new(0, 0.8, 0))
			hum:SetAttribute("Walls", walls)
			Sound3D.Muffle(hum, walls, throughFloor)
		else
			walls = hum:GetAttribute("Walls") or 0
		end
		hum.Volume = config.Volume * speed * Sounds.MuffleVolumeScale ^ walls
		hum.PlaybackSpeed = config.Pitch * (0.8 + 0.3 * speed)
	end
end

function DroneHum.Start()
	RunService.Heartbeat:Connect(update)
end

return DroneHum
