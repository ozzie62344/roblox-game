-- Stores each player's lean (-1, 0, 1), crouch (bool) and look pitch (radians, up/down) on their
-- character so every client can pose their body and aim their gun.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = ReplicatedStorage.Remotes
local SetLean = Remotes.SetLean :: RemoteEvent
local SetCrouch = Remotes.SetCrouch :: RemoteEvent
local LookPitch = Remotes.LookPitch :: UnreliableRemoteEvent

local MAX_PITCH = math.rad(85)

local PoseService = {}

function PoseService.Start()
	SetLean.OnServerEvent:Connect(function(player, value)
		if value ~= -1 and value ~= 0 and value ~= 1 then
			return
		end
		if player.Character then
			player.Character:SetAttribute("Lean", value)
		end
	end)

	SetCrouch.OnServerEvent:Connect(function(player, crouching)
		if typeof(crouching) ~= "boolean" then
			return
		end
		if player.Character then
			player.Character:SetAttribute("Crouching", crouching)
		end
	end)

	LookPitch.OnServerEvent:Connect(function(player, pitch)
		if typeof(pitch) ~= "number" or pitch ~= pitch then -- (pitch ~= pitch catches NaN)
			return
		end
		if player.Character then
			-- Rounded so tiny changes don't spam attribute updates
			local clamped = math.clamp(pitch, -MAX_PITCH, MAX_PITCH)
			player.Character:SetAttribute("LookPitch", math.round(clamped * 100) / 100)
		end
	end)
end

return PoseService
