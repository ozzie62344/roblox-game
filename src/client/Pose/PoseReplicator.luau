-- Poses other players' bodies from attributes the server sets on their character:
--   "Lean" (-1 / 0 / 1)  → upper body tilts sideways
--   "Crouching" (bool)   → knees bend (their hitbox is already lowered by their own client)
-- Placeholder until we have real animations.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.MovementConfig)

local PoseReplicator = {}

-- R15 crouch: thighs forward, shins back, feet flat
local CROUCH_JOINTS = {
	{ part = "LeftUpperLeg", joint = "LeftHip", angle = 85 },
	{ part = "RightUpperLeg", joint = "RightHip", angle = 85 },
	{ part = "LeftLowerLeg", joint = "LeftKnee", angle = -145 },
	{ part = "RightLowerLeg", joint = "RightKnee", angle = -145 },
	{ part = "LeftFoot", joint = "LeftAnkle", angle = 60 },
	{ part = "RightFoot", joint = "RightAnkle", angle = 60 },
}

local originalC0: { [Motor6D]: CFrame } = setmetatable({}, { __mode = "k" }) :: any
local smoothed: { [Instance]: { lean: number, crouch: number } } = setmetatable({}, { __mode = "k" }) :: any

local function getJoint(character: Model, partName: string, jointName: string): Motor6D?
	local part = character:FindFirstChild(partName)
	return part and part:FindFirstChild(jointName) :: Motor6D?
end

local function pose(joint: Motor6D?, offset: CFrame)
	if not joint then
		return
	end
	if not originalC0[joint] then
		originalC0[joint] = joint.C0
	end
	joint.C0 = originalC0[joint] * offset
end

local function update(dt: number)
	local alpha = 1 - math.exp(-Config.LeanSpeed * dt)
	for _, other in Players:GetPlayers() do
		local character = other.Character
		if other == Players.LocalPlayer or not character then
			continue
		end

		local values = smoothed[character]
		if not values then
			values = { lean = 0, crouch = 0 }
			smoothed[character] = values
		end
		values.lean += ((character:GetAttribute("Lean") or 0) - values.lean) * alpha
		values.crouch += ((if character:GetAttribute("Crouching") then 1 else 0) - values.crouch) * alpha

		pose(getJoint(character, "UpperTorso", "Waist"), CFrame.Angles(0, 0, -values.lean * math.rad(Config.LeanBodyAngle)))
		for _, info in CROUCH_JOINTS do
			pose(getJoint(character, info.part, info.joint), CFrame.Angles(math.rad(info.angle) * values.crouch, 0, 0))
		end
	end
end

function PoseReplicator.Start()
	RunService.RenderStepped:Connect(update)
end

return PoseReplicator
