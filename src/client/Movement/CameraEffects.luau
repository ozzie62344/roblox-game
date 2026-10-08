-- First-person camera feel: speed-based FOV, aim-down-sights zoom, recoil,
-- lean, dash / wall jump FOV kicks, slide tilt and drop, strafe tilt.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.MovementConfig)
local state = require(script.Parent.Parent.PlayerState)

local player = Players.LocalPlayer

local CameraEffects = {}

local fov = Config.BaseFov
local roll = 0
local appliedRecoilPitch = 0
local appliedRecoilYaw = 0

-- Frame-rate independent smoothing
local function smooth(current: number, target: number, sharpness: number, dt: number): number
	return current + (target - current) * (1 - math.exp(-sharpness * dt))
end

local function update(dt: number)
	local camera = Workspace.CurrentCamera

	-- FOV grows with speed (not while aiming), zooms in when aiming
	local speedAlpha =
		math.clamp((state.speed - Config.WalkSpeed) / (Config.FovMaxSpeed - Config.WalkSpeed), 0, 1)
	local targetFov = Config.BaseFov + speedAlpha * Config.FovSpeedBonus * (1 - state.aimAlpha)
	if state.dashing then
		targetFov += Config.DashFovKick
	end
	if os.clock() - state.lastWallJump < 0.15 then
		targetFov += Config.WallJumpFovKick
	end
	targetFov *= 1 + (state.adsFovScale - 1) * state.aimAlpha
	fov = smooth(fov, targetFov, 14, dt)
	camera.FieldOfView = fov

	-- Recoil kick (WeaponController adds to these, then they recover toward zero).
	-- Roblox's camera builds each frame from the last one, so rotation sticks: apply only the
	-- change since last frame, otherwise recoil stacks up every frame (→ staring at the sky).
	-- (deployPitch — looking down while pulling up cover — rides the same channel)
	local pitch = state.recoilPitch + state.deployPitch
	camera.CFrame *= CFrame.Angles(pitch - appliedRecoilPitch, state.recoilYaw - appliedRecoilYaw, 0)
	appliedRecoilPitch, appliedRecoilYaw = pitch, state.recoilYaw

	-- Roll: lean, slide tilt, and a slight lean into strafes
	local right = camera.CFrame.RightVector
	local strafe = math.clamp(state.velocity:Dot(right) / Config.SprintSpeed, -1, 1)
	local targetRoll = -strafe * math.rad(Config.StrafeTilt) - state.lean * math.rad(Config.LeanRoll)
	if state.sliding then
		targetRoll += math.rad(Config.SlideTilt)
	end
	roll = smooth(roll, targetRoll, 16, dt)
	camera.CFrame *= CFrame.Angles(0, 0, roll + state.recoilRoll)

	-- Shift sideways while leaning (crouch/slide height comes from the body itself lowering)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.CameraOffset = Vector3.new(state.leanOffset, 0, 0)
	end
end

function CameraEffects.Start()
	-- Camera + 1 is MouseUnlock, which may hold the camera still first
	RunService:BindToRenderStep("MovementCameraEffects", Enum.RenderPriority.Camera.Value + 2, update)
end

return CameraEffects
