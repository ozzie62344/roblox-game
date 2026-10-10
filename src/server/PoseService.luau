-- Stores each player's lean (-1, 0, 1), crouch / prone (bools), look pitch (radians, up/down) and rappel
-- rope height on their character so every client can pose their body, aim their gun and draw ropes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = ReplicatedStorage.Remotes
local SetLean = Remotes.SetLean :: RemoteEvent
local SetCrouch = Remotes.SetCrouch :: RemoteEvent
local LookPitch = Remotes.LookPitch :: UnreliableRemoteEvent
local SetRappel = Remotes.SetRappel :: RemoteEvent

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

	-- Lowered (crouching / sliding / lying down) and whether it's lying down (prone)
	SetCrouch.OnServerEvent:Connect(function(player, crouching, prone)
		if typeof(crouching) ~= "boolean" then
			return
		end
		if player.Character then
			player.Character:SetAttribute("Crouching", crouching)
			player.Character:SetAttribute("Prone", prone == true)
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

	-- Where a rappelling player's rope is tied (a height; nil = let go). RappelController draws it.
	SetRappel.OnServerEvent:Connect(function(player, top)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root or (top ~= nil and (typeof(top) ~= "number" or math.abs(top - root.Position.Y) > 60)) then
			return
		end
		(player.Character :: Model):SetAttribute("RappelTop", top)
	end)
end

return PoseService
