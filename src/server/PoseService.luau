-- Stores each player's lean (-1, 0, 1) and crouch (bool) on their character
-- so every client can pose their body.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = ReplicatedStorage.Remotes
local SetLean = Remotes.SetLean :: RemoteEvent
local SetCrouch = Remotes.SetCrouch :: RemoteEvent

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
end

return PoseService
