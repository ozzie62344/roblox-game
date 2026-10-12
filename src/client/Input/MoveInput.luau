-- How far and which way the movement controls are pushed (keys, the phone's thumbstick or a
-- gamepad stick), from Roblox's ControlModule: X is right, Z is back (-1 = all the way forward),
-- length 0..1. It's looked up once, in the background and safely: until it's found, or if it
-- can't be, Vector() returns nil and callers fall back to something else. Never look it up
-- inside a per-frame function: a yield or error there stops movement / the drone every frame.

local Players = game:GetService("Players")

local MoveInput = {}

local controlModule: any = nil

function MoveInput.Vector(): Vector3?
	if not controlModule then
		return nil
	end
	local ok, vector = pcall(controlModule.GetMoveVector, controlModule)
	return if ok and typeof(vector) == "Vector3" then vector else nil
end

function MoveInput.Start()
	task.spawn(function()
		local scripts = Players.LocalPlayer:WaitForChild("PlayerScripts", 15)
		local module = scripts and scripts:WaitForChild("PlayerModule", 15)
		if not module then
			warn("MoveInput: no PlayerModule; using fallbacks")
			return
		end
		local ok, playerModule = pcall(require, module)
		if ok and typeof(playerModule) == "table" and playerModule.GetControls then
			local found, controls = pcall(playerModule.GetControls, playerModule)
			if found and controls and controls.GetMoveVector then
				controlModule = controls
				return
			end
		end
		warn("MoveInput: couldn't read Roblox's ControlModule; using fallbacks")
	end)
end

return MoveInput
