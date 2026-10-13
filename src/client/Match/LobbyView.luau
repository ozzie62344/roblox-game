-- In the lobby you play in THIRD PERSON so you can see your own character: the camera pulls back
-- behind you, the mouse works like a normal Roblox game (right-drag to look around), and your
-- gun is put away (no shooting). On the map / in a match it's first person as usual, and so it is
-- in the lobby's practice range (state.inPractice, PracticeRange).
-- The server says where you are with the "Location" player attribute.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local state = require(script.Parent.Parent.PlayerState)

local player = Players.LocalPlayer

local LobbyView = {}

local function set(property: string, value: any)
	if (player :: any)[property] ~= value then
		(player :: any)[property] = value
	end
end

-- Checked every frame (cheap) so it also corrects itself after spectating changed the camera
local function update()
	-- (the practice range is part of the lobby, but there you play like in a match: PracticeRange)
	state.inLobby = player:GetAttribute("Location") == "Lobby" and not state.inPractice
	if state.spectating then
		return -- Spectate manages the camera while you're dead
	end
	if state.inLobby then
		set("CameraMode", Enum.CameraMode.Classic)
		set("CameraMinZoomDistance", 8)
		set("CameraMaxZoomDistance", 20)
	else
		set("CameraMode", Enum.CameraMode.LockFirstPerson)
		set("CameraMinZoomDistance", 0.5)
		set("CameraMaxZoomDistance", 0.5)
	end
end

function LobbyView.Start()
	RunService.RenderStepped:Connect(update)
end

return LobbyView
