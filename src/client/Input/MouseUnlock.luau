-- Owns the mouse and the camera's turning speed every frame (runs right after Roblox's camera,
-- so it gets the final say):
--   locked → cursor hidden and locked to the center (you only see the crosshair); how far the
--            camera turns is scaled by MouseSensitivity (and slower while aiming)
--   free   → cursor visible, camera stops turning, shooting is blocked
-- Left Alt toggles free mode. The dev panel also frees the mouse while it's open.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.MovementConfig)
local state = require(script.Parent.Parent.PlayerState)

local player = Players.LocalPlayer

local MouseUnlock = {}

-- Must run after the camera (Camera) and before CameraEffects (Camera + 2)
MouseUnlock.RenderPriority = Enum.RenderPriority.Camera.Value + 1

local MAX_PITCH = math.rad(80)
-- A bigger jump than this in one frame was a script moving the camera (respawn, teleport), not
-- the mouse — let it through unscaled
local SNAP_ANGLE = math.rad(60)

local hint: TextLabel
-- Where the camera was pointing at the very end of the last frame (after recoil etc.)
local lastYaw: number? = nil
local lastPitch = 0

local function isFree(): boolean
	return state.mouseUnlocked or state.devPanelOpen or state.draftOpen or state.voteOpen
end

local function yawPitch(look: Vector3): (number, number)
	return math.atan2(-look.X, -look.Z), math.asin(math.clamp(look.Y, -1, 1))
end

local function wrapAngle(a: number): number
	return (a + math.pi) % (2 * math.pi) - math.pi
end

local function update()
	local free = isFree()

	-- Lobby: a normal Roblox cursor for the menus; right-drag turns the camera (Roblox's camera
	-- owns the mouse while you drag, so only undo our lock)
	if state.inLobby and not state.spectating then
		if UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter then
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		end
		UserInputService.MouseIconEnabled = true
		hint.Visible = false
		return
	end

	-- Spectating (third person): moving the mouse turns the camera around them, like a
	-- third-person shooter. Roblox's own camera handles it; we just lock the cursor.
	if state.spectating and not free then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		UserInputService.MouseIconEnabled = false
		hint.Visible = false
		return
	end

	UserInputService.MouseBehavior = if free then Enum.MouseBehavior.Default else Enum.MouseBehavior.LockCenter
	UserInputService.MouseIconEnabled = free
	hint.Visible = state.mouseUnlocked and not state.devPanelOpen

	-- Roblox's camera starts each frame from where the last one ended and adds this frame's mouse
	-- movement. So we can measure that movement and scale it: 0 = frozen (free cursor),
	-- 1 = Roblox's normal speed, below 1 = slower.
	local camera = Workspace.CurrentCamera
	if state.spectating or not lastYaw then
		return -- third-person spectating keeps Roblox's own camera
	end
	local scale = if free then 0 else Config.MouseSensitivity * state.aimSensitivity
	local yaw, pitch = yawPitch(camera.CFrame.LookVector)
	local deltaYaw = wrapAngle(yaw - lastYaw)
	local deltaPitch = pitch - lastPitch
	if math.abs(deltaYaw) > SNAP_ANGLE or math.abs(deltaPitch) > SNAP_ANGLE then
		return
	end
	local newYaw = lastYaw + deltaYaw * scale
	local newPitch = math.clamp(lastPitch + deltaPitch * scale, -MAX_PITCH, MAX_PITCH)
	camera.CFrame = CFrame.new(camera.CFrame.Position) * CFrame.fromOrientation(newPitch, newYaw, 0)
end

-- Remember the final camera direction once everything else (recoil, lean, etc.) has applied
local function remember()
	lastYaw, lastPitch = yawPitch(Workspace.CurrentCamera.CFrame.LookVector)
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
			if state.loadoutWindow then
				-- Before the round starts, Alt shows / hides the loadout cards instead
				state.draftOpen = not state.draftOpen
			else
				state.mouseUnlocked = not state.mouseUnlocked
			end
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.LeftAlt)

	player.CharacterAdded:Connect(function()
		state.mouseUnlocked = false
		lastYaw = nil -- new body: don't scale the jump to the spawn direction
	end)

	RunService:BindToRenderStep("MouseControl", MouseUnlock.RenderPriority, update)
	RunService:BindToRenderStep("MouseControlRemember", Enum.RenderPriority.Last.Value, remember)
end

return MouseUnlock
