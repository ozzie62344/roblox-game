-- First-person camera feel: speed-based FOV, aim-down-sights zoom, recoil,
-- lean, the dip and roll of a vault, strafe tilt.

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
local proneDrop = 0
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
	-- Eased so the zoom starts and ends gently instead of snapping
	local aimEase = state.aimAlpha * state.aimAlpha * (3 - 2 * state.aimAlpha)
	targetFov *= 1 + (state.adsFovScale - 1) * aimEase
	fov = smooth(fov, targetFov, 10, dt)
	camera.FieldOfView = fov

	-- Recoil kick (WeaponController adds to these, then they recover toward zero).
	-- Roblox's camera builds each frame from the last one, so rotation sticks: apply only the
	-- change since last frame, otherwise recoil stacks up every frame (→ staring at the sky).
	-- (deployPitch — looking down while pulling up cover — rides the same channel)
	local pitch = state.recoilPitch + state.deployPitch
	camera.CFrame *= CFrame.Angles(pitch - appliedRecoilPitch, state.recoilYaw - appliedRecoilYaw, 0)
	appliedRecoilPitch, appliedRecoilYaw = pitch, state.recoilYaw

	-- Roll: lean, a vault's tilt, and a slight lean into strafes
	local right = camera.CFrame.RightVector
	local strafe = math.clamp(state.velocity:Dot(right) / Config.SprintSpeed, -1, 1)
	local targetRoll = -strafe * math.rad(Config.StrafeTilt) - state.lean * math.rad(Config.LeanRoll)
	-- Mid-vault: rolled a little and dipped (both peak halfway over)
	local vaultArc = if state.vaulting then math.sin(state.vaultAlpha * math.pi) else 0
	targetRoll += vaultArc * math.rad(Config.VaultCameraRoll)
	roll = smooth(roll, targetRoll, 16, dt)
	camera.CFrame *= CFrame.Angles(0, 0, roll + state.recoilRoll)

	-- Shift sideways while leaning (crouch height comes from the body itself lowering).
	-- Lying down: your body lies flat, so your eyes go further down than the body's drop.
	proneDrop = smooth(proneDrop, if state.prone then Config.ProneCameraDrop else 0, 8, dt)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.CameraOffset = Vector3.new(state.leanOffset, -proneDrop - vaultArc * Config.VaultCameraDip, 0)
	end
end

function CameraEffects.Start()
	-- Camera + 1 is MouseUnlock, which may hold the camera still first
	RunService:BindToRenderStep("MovementCameraEffects", Enum.RenderPriority.Camera.Value + 2, update)
end

return CameraEffects
