-- First-person arms for pulling up deployable cover: the hands reach down, grab the shield's
-- top edge, and ride it up out of the ground. The rise is recomputed here with the same
-- timing/easing the server uses, so the hands stay glued to the edge every frame.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Viewmodel = require(script.Parent.Parent.Combat.Viewmodel)

local DeployArms = {}

local GRAB_PORTION = 0.2 -- matches AbilityService: first 20% is the grab, the rest is the rise
local HAND_SPREAD = 1.1 -- studs from the cover's center to each hand
-- Arms have a fixed length. If the cover's edge is out of reach, the hands stretch toward it
-- as far as they can; once it rises into reach, they lock onto it.
local UPPER_ARM_LENGTH = 1.15
local FOREARM_LENGTH = 1.15

-- Camera-space anchor points
local SHOULDERS = { Left = Vector3.new(-0.75, -0.95, -0.15), Right = Vector3.new(0.75, -0.95, -0.15) }
local REST_HANDS = { Left = Vector3.new(-0.45, -0.9, -1.2), Right = Vector3.new(0.45, -0.9, -1.2) }

local model: Model? = nil
local parts: { [string]: { upper: Part, fore: Part, hand: Part } } = {}

local function newPart(parent: Instance, size: Vector3, color: Color3): Part
	local part = Instance.new("Part")
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.Fabric
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = parent
	return part
end

local function build()
	local newModel = Instance.new("Model")
	newModel.Name = "DeployArms"
	for _, side in { "Left", "Right" } do
		parts[side] = {
			upper = newPart(newModel, Vector3.new(0.34, 0.34, 1), Viewmodel.SleeveColor),
			fore = newPart(newModel, Vector3.new(0.3, 0.3, 1), Viewmodel.SleeveColor),
			hand = newPart(newModel, Vector3.new(0.3, 0.32, 0.38), Viewmodel.GloveColor),
		}
	end
	model = newModel
end

-- Stretch a part between two world points
local function span(part: Part, a: Vector3, b: Vector3)
	local length = (b - a).Magnitude
	part.Size = Vector3.new(part.Size.X, part.Size.Y, math.max(length, 0.05))
	part.CFrame = CFrame.lookAt((a + b) / 2, b)
end

-- Two-bone arm: given a shoulder and where the hand wants to be, returns the elbow and the hand
-- (clamped to arm's length). The elbow bends toward `pole` (outward and down).
local function solveArm(shoulder: Vector3, target: Vector3, pole: Vector3): (Vector3, Vector3)
	local toTarget = target - shoulder
	local maxReach = (UPPER_ARM_LENGTH + FOREARM_LENGTH) * 0.999
	local distance = math.clamp(toTarget.Magnitude, 0.1, maxReach)
	local direction = if toTarget.Magnitude > 1e-3 then toTarget.Unit else Vector3.new(0, -1, 0)
	local hand = shoulder + direction * distance

	-- Law of cosines: how far along the arm the elbow sits, and how far it bows out
	local along = (UPPER_ARM_LENGTH ^ 2 - FOREARM_LENGTH ^ 2 + distance ^ 2) / (2 * distance)
	local bow = math.sqrt(math.max(UPPER_ARM_LENGTH ^ 2 - along ^ 2, 0))
	local bend = pole - direction * pole:Dot(direction)
	bend = if bend.Magnitude > 1e-3 then bend.Unit else Vector3.new(0, -1, 0)
	local elbow = shoulder + direction * along + bend * bow
	return elbow, hand
end

local function sineInOut(x: number): number
	return -(math.cos(math.pi * x) - 1) / 2
end

local function smoothstep(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

-- duration / finalCFrame / size come from the server's DeployStart message
function DeployArms.Play(duration: number, finalCFrame: CFrame, size: Vector3)
	DeployArms.Stop()
	if not model then
		build()
	end
	local arms = model :: Model
	arms.Parent = Workspace.CurrentCamera
	local startedAt = os.clock()
	local grabTime = duration * GRAB_PORTION

	RunService:BindToRenderStep("DeployArms", Enum.RenderPriority.Camera.Value + 4, function()
		local camera = Workspace.CurrentCamera.CFrame
		local elapsed = os.clock() - startedAt

		-- How far the cover has risen (0 = buried, top edge at the ground; 1 = in place)
		local rise = if elapsed < grabTime
			then 0
			else sineInOut(math.clamp((elapsed - grabTime) / (duration - grabTime), 0, 1))
		local topY = size.Y / 2 - size.Y * (1 - rise)
		-- The edge facing you (cover's +Z side faces back toward the player)
		local reach = smoothstep(elapsed / grabTime)

		for side, sign in { Left = -1, Right = 1 } do
			local limb = parts[side]
			local grip = (finalCFrame * CFrame.new(sign * HAND_SPREAD, topY, size.Z / 2 + 0.1)).Position
			local rest = (camera * CFrame.new(REST_HANDS[side])).Position
			local shoulder = (camera * CFrame.new(SHOULDERS[side])).Position
			-- Elbows bow outward and down
			local pole = camera.RightVector * sign - camera.UpVector
			local elbow, hand = solveArm(shoulder, rest:Lerp(grip, reach), pole)

			span(limb.upper, shoulder, elbow)
			span(limb.fore, elbow, hand)
			limb.hand.CFrame = CFrame.lookAt(hand, hand + (hand - elbow))
		end
	end)
end

function DeployArms.Stop()
	RunService:UnbindFromRenderStep("DeployArms")
	if model then
		model.Parent = nil
	end
end

return DeployArms
