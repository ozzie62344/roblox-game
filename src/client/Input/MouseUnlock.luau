-- Owns the mouse every frame (runs right after Roblox's camera, so it gets the final say):
--   locked → cursor hidden and locked to the center (you only see the crosshair)
--   free   → cursor visible, camera stops turning, shooting is blocked
-- Left Alt toggles free mode. The dev panel also frees the mouse while it's open.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local state = require(script.Parent.Parent.PlayerState)

local player = Players.LocalPlayer

local MouseUnlock = {}

-- Must run after the camera (Camera) and before CameraEffects (Camera + 2)
MouseUnlock.RenderPriority = Enum.RenderPriority.Camera.Value + 1

local hint: TextLabel
local frozenLook: Vector3? = nil

local function isFree(): boolean
	return state.mouseUnlocked or state.devPanelOpen
end

local function update()
	local free = isFree()
	UserInputService.MouseBehavior = if free then Enum.MouseBehavior.Default else Enum.MouseBehavior.LockCenter
	UserInputService.MouseIconEnabled = free
	hint.Visible = state.mouseUnlocked and not state.devPanelOpen

	-- Hold the camera's aim while the cursor is free so moving the mouse to click doesn't spin you.
	-- (Roblox's camera starts each frame from the last one, so resetting it here keeps it still.)
	local camera = Workspace.CurrentCamera
	if free then
		local position = camera.CFrame.Position
		if not frozenLook then
			frozenLook = camera.CFrame.LookVector
		end
		camera.CFrame = CFrame.lookAt(position, position + (frozenLook :: Vector3))
	else
		frozenLook = nil
	end
end

function MouseUnlock.Start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "MouseUnlock"
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")

	hint = Instance.new("TextLabel")
	hint.AnchorPoint = Vector2.new(0.5, 1)
	hint.Position = UDim2.new(0.5, 0, 1, -90)
	hint.Size = UDim2.fromOffset(300, 24)
	hint.BackgroundTransparency = 1
	hint.Font = Enum.Font.GothamMedium
	hint.TextSize = 14
	hint.TextColor3 = Color3.fromRGB(200, 205, 215)
	hint.TextStrokeTransparency = 0.6
	hint.Text = "Mouse unlocked · Left Alt to lock"
	hint.Visible = false
	hint.Parent = gui

	ContextActionService:BindAction("ToggleMouseUnlock", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			state.mouseUnlocked = not state.mouseUnlocked
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.LeftAlt)

	player.CharacterAdded:Connect(function()
		state.mouseUnlocked = false
	end)

	RunService:BindToRenderStep("MouseControl", MouseUnlock.RenderPriority, update)
end

return MouseUnlock
