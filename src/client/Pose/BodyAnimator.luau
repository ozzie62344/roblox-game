-- Animates other players' bodies (and your own while you're in the third-person lobby) (Roblox's default walk/idle animations are turned off, see
-- src/Animate.client.luau). Everything is worked out every frame from what we know about them:
--   • legs: feet stay planted on the ground — real steps when moving, knees bend when crouching
--     (their body is lowered, so this is what stops them sinking into the floor), one leg out
--     in front going over cover (vaulting), tucked up in the air
--   • a gun in their hands (the same detailed model you hold), both arms holding it, aimed where
--     they're looking (up/down comes from the "LookPitch" attribute), kicking when they shoot
--   • lean, sprint (gun lowered), reload (left hand to the mag and to a pouch), deploying cover
--     (reaching down), vaulting (leaning back over the cover, gun lowered)
--   • lying down (prone): the body tips forward flat onto the floor, chest up on the elbows, head
--     up, gun out in front, legs stretched behind; crawling draws one knee up at a time
--   • rappelling: feet braced against the wall (stepping up / down it as they move), leaning back
--     off it, left hand up on the rope, gun in the right
--   • gadget / ability moves and plant / disable / barricade / reinforce holds: the same hand
--     moves as first person (HandsAnimator), with the gun slung at the hip
--   • downed (DBNO, the "Downed" attribute): lying down like prone, gun slung, both hands pressed
--     to their middle; reviving someone kneels and reaches down like deploying cover
--
-- How the joints are moved: each R15 joint (a Motor6D, or an AnimationConstraint on avatars with
-- Roblox's upgraded joints — both work the same way) places its part like this
--     part.CFrame = parent.CFrame * C0 * Transform * C1:Inverse()
-- We decide where every part should be in the world (from the root down), then solve for the
-- Transform that puts it there. Arms and legs use "two-bone IK": given where the shoulder/hip is
-- and where the hand/foot must go, work out where the elbow/knee has to be.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Attachments = require(ReplicatedStorage.Shared.Attachments)
local Config = require(ReplicatedStorage.Shared.MovementConfig)
local Skins = require(ReplicatedStorage.Shared.Skins)
local Weapons = require(ReplicatedStorage.Shared.Weapons)
local GunModels = require(script.Parent.Parent.Combat.GunModels)
local HandsAnimator = require(script.Parent.Parent.Abilities.HandsAnimator)
local state = require(script.Parent.Parent.PlayerState)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local ReloadStarted = Remotes:WaitForChild("ReloadStarted") :: RemoteEvent
local ShotFired = Remotes:WaitForChild("ShotFired") :: RemoteEvent
local LookPitch = Remotes:WaitForChild("LookPitch") :: UnreliableRemoteEvent

local player = Players.LocalPlayer

local BodyAnimator = {}

-- Tuning
local SPRINT_SPEED = Config.SprintThreshold -- faster than this looks like sprinting
local MOVE_SPEED = 2 -- slower than this counts as standing still
local STEP_HEIGHT = 0.55 -- how high feet lift while walking
local SMOOTH = 12 -- how quickly poses blend
local GUN_SCALE = 1.35 -- held guns are drawn bigger than real so they read on chunky Roblox hands
local PITCH_SEND_RATE = 1 / 12 -- seconds between sending our own look pitch
local PITCH_SEND_STEP = math.rad(1.5) -- only send when it changed at least this much
local PRONE_DROP = 0.55 -- lying down: how far the tipped-over body drops to rest on the floor

local UP = Vector3.yAxis

type Joint = { motor: Motor6D | AnimationConstraint, c0: CFrame, c1: CFrame }
type Side = {
	shoulder: Joint, elbow: Joint, wrist: Joint,
	hip: Joint, knee: Joint, ankle: Joint,
	upperArm: number, lowerArm: number, upperLeg: number, lowerLeg: number,
	ankleHeight: number,
}
type Gun = { name: string, skin: Skins.Skin?, mods: string, model: Model, parts: { BasePart }, offsets: { CFrame }, rightGrip: Vector3, leftGrip: Vector3, handgun: boolean }
type Rig = {
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	rootJoint: Joint, waist: Joint, neck: Joint,
	left: Side, right: Side,
	gun: Gun?,
	-- smoothed pose values
	phase: number,
	stride: number,
	crouch: number,
	prone: number,
	rappel: number,
	lastRootPos: Vector3?, -- (a rappeller's velocity reads zero: speed comes from how far they moved)
	vault: number, -- going over cover (the "Vaulting" attribute)
	sprint: number,
	air: number,
	lean: number,
	pitch: number,
	busy: number, -- deploying cover / planting / disabling / fortifying
	kneel: number, -- deploying cover / planting / disabling (fortifying is done standing)
	work: number, -- hands on a gadget / ability move or a hold (HandsAnimator)
	workLeft: Vector3,
	workRight: Vector3,
	kick: number,
	reloadStart: number,
	reloadEnd: number,
}

local rigs: { [Model]: Rig } = {}
local warned: { [Model]: boolean } = setmetatable({}, { __mode = "k" }) :: any

-- ─── Math helpers ──────────────────────────────────────────────────────────────

local function joint(part: Instance?, name: string): Joint?
	local motor = part and part:FindFirstChild(name)
	if motor and (motor:IsA("Motor6D") or motor:IsA("AnimationConstraint")) then
		return { motor = motor, c0 = motor.C0, c1 = motor.C1 }
	end
	return nil
end

local function smooth(current: number, target: number, dt: number, sharpness: number?): number
	return current + (target - current) * (1 - math.exp(-(sharpness or SMOOTH) * dt))
end

-- A rotation whose Y axis points along `dir`, twisted so its Z axis leans toward `hint`
local function basis(dir: Vector3, hint: Vector3): CFrame
	local y = dir.Unit
	local z = hint - y * hint:Dot(y)
	if z.Magnitude < 1e-3 then
		z = Vector3.zAxis - y * y.Z
		if z.Magnitude < 1e-3 then
			z = Vector3.xAxis - y * y.X
		end
	end
	z = z.Unit
	return CFrame.fromMatrix(Vector3.zero, y:Cross(z), y, z)
end

-- Where a limb part must be so that its two joint points (in the part's own space) land on two
-- world points, twisted so `localHint` faces `worldHint`
local function limbCFrame(localStart: Vector3, localEnd: Vector3, localHint: Vector3, worldStart: Vector3, worldEnd: Vector3, worldHint: Vector3): CFrame
	local rotation = basis(worldEnd - worldStart, worldHint) * basis(localEnd - localStart, localHint):Inverse()
	return CFrame.new(worldStart) * rotation * CFrame.new(-localStart)
end

-- Two-bone IK: from joint `a`, with bone lengths l1 and l2, reach toward `target`; the middle
-- joint bends toward `pole`. Returns the middle joint and the (reachable) end point.
local function solveTwoBone(a: Vector3, target: Vector3, l1: number, l2: number, pole: Vector3): (Vector3, Vector3)
	local offset = target - a
	local distance = math.clamp(offset.Magnitude, math.abs(l1 - l2) + 0.01, (l1 + l2) * 0.999)
	local dir = if offset.Magnitude > 1e-4 then offset.Unit else -UP
	local along = (l1 * l1 - l2 * l2 + distance * distance) / (2 * distance)
	local bowOut = math.sqrt(math.max(l1 * l1 - along * along, 0))
	local bend = pole - dir * pole:Dot(dir)
	bend = if bend.Magnitude > 1e-4 then bend.Unit else Vector3.zAxis
	return a + dir * along + bend * bowOut, a + dir * distance
end

-- The Transform that puts `part1World` where it should be, given the joint's parent part
local function transformFor(j: Joint, part0World: CFrame, part1World: CFrame): CFrame
	return (part0World * j.c0):Inverse() * part1World * j.c1
end

-- Where the joint's child part sits for a given Transform
local function childCFrame(j: Joint, part0World: CFrame, transform: CFrame): CFrame
	return part0World * j.c0 * transform * j.c1:Inverse()
end

-- The way something faces, flattened to just its left/right turn (no tilt)
local function yawOnly(cframe: CFrame): CFrame
	local look = cframe.LookVector
	return CFrame.Angles(0, math.atan2(-look.X, -look.Z), 0)
end

-- ─── Rig setup ─────────────────────────────────────────────────────────────────

local function buildSide(character: Model, prefix: string): Side?
	local shoulder = joint(character:FindFirstChild(prefix .. "UpperArm"), prefix .. "Shoulder")
	local elbow = joint(character:FindFirstChild(prefix .. "LowerArm"), prefix .. "Elbow")
	local wrist = joint(character:FindFirstChild(prefix .. "Hand"), prefix .. "Wrist")
	local hip = joint(character:FindFirstChild(prefix .. "UpperLeg"), prefix .. "Hip")
	local knee = joint(character:FindFirstChild(prefix .. "LowerLeg"), prefix .. "Knee")
	local foot = character:FindFirstChild(prefix .. "Foot") :: BasePart?
	local ankle = joint(foot, prefix .. "Ankle")
	if not (shoulder and elbow and wrist and hip and knee and ankle and foot) then
		return nil
	end
	return {
		shoulder = shoulder, elbow = elbow, wrist = wrist, hip = hip, knee = knee, ankle = ankle,
		-- Bone lengths: distance between the two joint points inside each limb part
		upperArm = (elbow.c0.Position - shoulder.c1.Position).Magnitude,
		lowerArm = (wrist.c0.Position - elbow.c1.Position).Magnitude,
		upperLeg = (knee.c0.Position - hip.c1.Position).Magnitude,
		lowerLeg = (ankle.c0.Position - knee.c1.Position).Magnitude,
		ankleHeight = ankle.c1.Position.Y + foot.Size.Y / 2, -- ankle point above the sole
	}
end

local function destroyGun(rig: Rig)
	if rig.gun then
		rig.gun.model:Destroy()
		rig.gun = nil
	end
end

-- A world-sized copy of the gun this player holds, in their skin. Its parts are moved every frame
-- (anchored), so they never collide; they cast shadows like real objects.
local function ensureGun(rig: Rig, weaponName: string, skin: Skins.Skin?, attachments: Attachments.Chosen)
	local mods = Attachments.Key(attachments)
	if rig.gun and rig.gun.name == weaponName and rig.gun.skin == skin and rig.gun.mods == mods then
		return
	end
	destroyGun(rig)
	local weapon = Weapons[weaponName]
	local model = GunModels.Build(weaponName, weapon and weapon.Look.Color or nil, skin, attachments)
	model:ScaleTo(GUN_SCALE)
	local body = model.PrimaryPart :: BasePart
	local parts, offsets = {}, {}
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.CastShadow = part.Material ~= Enum.Material.ForceField -- (see-through skins)
			table.insert(parts, part)
			table.insert(offsets, body.CFrame:ToObjectSpace(part.CFrame))
		elseif part:IsA("Light") then
			part.Enabled = false
		end
	end
	local rightGrip = body:FindFirstChild("RightGrip") :: Attachment?
	local leftGrip = body:FindFirstChild("LeftGrip") :: Attachment?
	model.Name = "HeldGun"
	model.Parent = Workspace.CurrentCamera -- client-only, like other effects
	local rightPos = if rightGrip then rightGrip.CFrame.Position else Vector3.new(0, -0.3, 0.3)
	local leftPos = if leftGrip then leftGrip.CFrame.Position else Vector3.new(0, -0.1, -0.9)
	rig.gun = {
		name = weaponName,
		skin = skin,
		mods = mods,
		model = model,
		parts = parts,
		offsets = offsets,
		rightGrip = rightPos,
		leftGrip = leftPos,
		-- Both hands on the same handle = a handgun
		handgun = (leftPos - rightPos).Magnitude < 0.6 * GUN_SCALE,
	}
end

local function makeRig(character: Model): Rig?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local lowerTorso = character:FindFirstChild("LowerTorso")
	local rootJoint = joint(lowerTorso, "Root")
	local waist = joint(character:FindFirstChild("UpperTorso"), "Waist")
	local neck = joint(character:FindFirstChild("Head"), "Neck")
	local left = buildSide(character, "Left")
	local right = buildSide(character, "Right")
	if not (humanoid and root and rootJoint and waist and neck and left and right) then
		return nil -- not an R15 character (yet)
	end
	return {
		character = character, humanoid = humanoid, root = root,
		rootJoint = rootJoint, waist = waist, neck = neck, left = left, right = right,
		phase = 0, stride = 0, crouch = 0, prone = 0, rappel = 0, vault = 0, sprint = 0, air = 0, lean = 0, pitch = 0,
		busy = 0, kneel = 0, work = 0, workLeft = Vector3.zero, workRight = Vector3.zero,
		kick = 0, reloadStart = 0, reloadEnd = 0,
	}
end

-- ─── Posing ────────────────────────────────────────────────────────────────────

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function groundHeight(rig: Rig, from: Vector3): number?
	rayParams.FilterDescendantsInstances = { rig.character, Workspace.CurrentCamera }
	local result = Workspace:Raycast(from, Vector3.new(0, -9, 0), rayParams)
	return result and result.Position.Y
end

local function poseLeg(side: Side, sign: number, lowerTorsoCF: CFrame, rig: Rig, facing: CFrame, moveDir: Vector3, ground: number?)
	local hipPos = (lowerTorsoCF * side.hip.c0).Position
	local legLength = side.upperLeg + side.lowerLeg
	local forward, right = facing.LookVector, facing.RightVector

	-- Walking: feet swing forward/back out of phase, lifting on the way forward
	local phase = rig.phase + (if sign > 0 then math.pi else 0)
	local swing = math.sin(phase) * rig.stride
	local lift = math.max(0, math.cos(phase)) * STEP_HEIGHT * math.min(rig.stride / 1.2, 1)
	-- Crouch: one foot a little forward, the other back, slightly wider
	local crouchOffset = forward * (if sign < 0 then 0.55 else -0.45) * rig.crouch + right * sign * 0.2 * rig.crouch
	-- Vaulting: left leg straight out in front, right leg folded under (a speed vault)
	local vaultOffset = if sign < 0 then forward * 2.4 else forward * -0.6 + right * 0.25

	local groundY = (ground or (hipPos.Y - legLength)) + side.ankleHeight
	local target = Vector3.new(hipPos.X, groundY, hipPos.Z)
		+ right * sign * 0.15
		+ moveDir * swing * (1 - rig.vault)
		+ UP * lift * (1 - rig.vault)
		+ crouchOffset * (1 - rig.vault)
		+ vaultOffset * rig.vault
	-- In the air: feet tucked up under the body
	local tucked = hipPos - UP * legLength * 0.7 + forward * (if sign < 0 then 0.5 else -0.3)
	target = target:Lerp(tucked, rig.air)
	-- Lying down: legs stretched out behind along the floor; crawling draws one knee up at a time
	if rig.prone > 0.01 then
		local crawl = math.max(0, math.sin(phase)) * math.min(rig.stride, 1)
		local floorY = (ground or (hipPos.Y - 1)) + 0.25
		local proneTarget = Vector3.new(hipPos.X, floorY, hipPos.Z)
			- forward * legLength * (0.92 - 0.4 * crawl)
			+ right * sign * (0.3 + 0.45 * crawl)
		target = target:Lerp(proneTarget, rig.prone)
	end
	-- Rappelling: feet braced flat against the wall in front, walking up / down it in turn
	if rig.rappel > 0.01 then
		local step = math.sin(phase) * math.min(rig.stride, 1) * 0.45
		local braced = hipPos + forward * 1.15 - UP * (1.0 - step) + right * sign * 0.45
		target = target:Lerp(braced, rig.rappel)
	end

	-- Knees point forward (and a touch outward); lying down they point at the floor; braced on a
	-- wall they point up and out
	local pole = (forward + right * sign * 0.15):Lerp(right * sign * 0.4 - UP, rig.prone):Lerp(UP + right * sign * 0.4, rig.rappel)
	local kneePos, anklePos = solveTwoBone(hipPos, target, side.upperLeg, side.lowerLeg, pole)
	local upperCF = limbCFrame(side.hip.c1.Position, side.knee.c0.Position, Vector3.new(0, 0, -1), hipPos, kneePos, pole)
	local lowerCF = limbCFrame(side.knee.c1.Position, side.ankle.c0.Position, Vector3.new(0, 0, -1), kneePos, anklePos, pole)
	-- Feet stay flat, facing the way the body faces (lying down: toes dug into the floor; on a
	-- rope: soles flat on the wall)
	local footCF = CFrame.new(anklePos) * facing * CFrame.Angles(math.rad(80) * rig.rappel - math.rad(70) * rig.prone, 0, 0) * CFrame.new(-side.ankle.c1.Position)

	side.hip.motor.Transform = transformFor(side.hip, lowerTorsoCF, upperCF)
	side.knee.motor.Transform = transformFor(side.knee, upperCF, lowerCF)
	side.ankle.motor.Transform = transformFor(side.ankle, lowerCF, footCF)
end

local function poseArm(side: Side, sign: number, upperTorsoCF: CFrame, handTarget: Vector3, prone: number)
	local shoulderPos = (upperTorsoCF * side.shoulder.c0).Position
	-- Aim the wrist a little short of the grip so the hand (not the wrist) ends up on it
	local toTarget = handTarget - shoulderPos
	local wristTarget = handTarget - (if toTarget.Magnitude > 1e-3 then toTarget.Unit else -UP) * 0.3
	-- Elbows hang down and out (lying down: propped on the floor)
	local pole = (upperTorsoCF.RightVector * sign * 0.8 - upperTorsoCF.UpVector):Lerp(upperTorsoCF.RightVector * sign * 0.6 - UP, prone)
	local elbowPos, wristPos = solveTwoBone(shoulderPos, wristTarget, side.upperArm, side.lowerArm, pole)
	local bend = elbowPos - (shoulderPos + wristPos) / 2
	local hint = if bend.Magnitude > 1e-3 then bend else pole
	local upperCF = limbCFrame(side.shoulder.c1.Position, side.elbow.c0.Position, Vector3.new(0, 0, 1), shoulderPos, elbowPos, hint)
	local lowerCF = limbCFrame(side.elbow.c1.Position, side.wrist.c0.Position, Vector3.new(0, 0, 1), elbowPos, wristPos, hint)
	side.shoulder.motor.Transform = transformFor(side.shoulder, upperTorsoCF, upperCF)
	side.elbow.motor.Transform = transformFor(side.elbow, upperCF, lowerCF)
	side.wrist.motor.Transform = CFrame.new()
end

local function moveGun(gun: Gun, gunCF: CFrame)
	local cframes = table.create(#gun.parts)
	for i, offset in gun.offsets do
		cframes[i] = gunCF * offset
	end
	Workspace:BulkMoveTo(gun.parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
end

local function easeInOut(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function animate(rig: Rig, other: Player, dt: number)
	local character, root = rig.character, rig.root
	local velocity = root.AssemblyLinearVelocity
	local flatVelocity = Vector3.new(velocity.X, 0, velocity.Z)
	local speed = flatVelocity.Magnitude
	local facing = yawOnly(root.CFrame)
	local moveDir = if speed > 0.5 then flatVelocity.Unit else facing.LookVector

	-- What are they doing? (attributes set by the server from their own client)
	local lowered = character:GetAttribute("Crouching") == true -- crouching OR lying down
	local downed = character:GetAttribute("Downed") == true -- (DBNO: always lying down)
	local prone = character:GetAttribute("Prone") == true or downed
	local vaulting = character:GetAttribute("Vaulting") == true
	local crouching = lowered and not prone and not vaulting
	local deployingCover = character:GetAttribute("Deploying") == true
	local interaction = other:GetAttribute("Interaction")
	local busy = deployingCover or interaction ~= nil or downed
	local kneeling = not prone and (deployingCover or interaction == "Plant" or interaction == "Disable" or interaction == "Revive")
	local rootPos = root.CFrame.Position
	local ground = groundHeight(rig, rootPos)
	local rappelling = typeof(character:GetAttribute("RappelTop")) == "number"
	local airborne = not rappelling and (ground == nil or rootPos.Y - ground > rig.humanoid.HipHeight + root.Size.Y / 2 + 1.2)
	-- On a rope they're moved by hand (their velocity reads zero): how fast are they climbing?
	local moved = if rig.lastRootPos then (rootPos - rig.lastRootPos).Magnitude / math.max(dt, 1e-3) else 0
	rig.lastRootPos = rootPos
	local gait = if rappelling then moved else speed

	rig.crouch = smooth(rig.crouch, if crouching or kneeling then 1 else 0, dt)
	rig.prone = smooth(rig.prone, if prone then 1 else 0, dt, 8)
	rig.rappel = smooth(rig.rappel, if rappelling then 1 else 0, dt, 10)
	rig.vault = smooth(rig.vault, if vaulting then 1 else 0, dt, 16)
	rig.sprint = smooth(rig.sprint, if speed > SPRINT_SPEED and not lowered then 1 else 0, dt, 8)
	rig.air = smooth(rig.air, if airborne then 1 else 0, dt, 10)
	rig.lean = smooth(rig.lean, character:GetAttribute("Lean") or 0, dt, Config.LeanSpeed)
	rig.pitch = smooth(rig.pitch, character:GetAttribute("LookPitch") or 0, dt, 15)
	rig.busy = smooth(rig.busy, if busy then 1 else 0, dt, 10)
	rig.kneel = smooth(rig.kneel, if kneeling then 1 else 0, dt, 10)
	rig.kick = smooth(rig.kick, 0, dt, 18)

	-- Hands on a gadget / ability move or a plant / disable / fortify hold: the same moves you do in
	-- first person (HandsAnimator), from their head, looking where they look
	local head = character:FindFirstChild("Head") :: BasePart?
	local eye = CFrame.new(if head then head.Position else rootPos + Vector3.new(0, 1.5, 0)) * yawOnly(root.CFrame).Rotation * CFrame.Angles(rig.pitch, 0, 0)
	local moveKind, moveContext = HandsAnimator.Current(other, character, root, eye)
	if moveKind and moveContext then
		local left, right = HandsAnimator.Sample(moveKind, moveContext)
		rig.workLeft = left or (eye * CFrame.new(-0.45, -0.9, -1.2)).Position
		rig.workRight = right or (eye * CFrame.new(0.45, -0.9, -1.2)).Position
	end
	rig.work = smooth(rig.work, if moveKind then 1 else 0, dt, 14)

	-- Step cycle: steps get longer the faster you go (on a rope: steps up / down the wall)
	local stepLength = math.clamp(gait * 0.11, 0.9, 2.4) * (1 - rig.crouch * 0.4)
	rig.stride = smooth(rig.stride, if gait > MOVE_SPEED then stepLength else 0, dt, 10)
	if gait > MOVE_SPEED then
		rig.phase = (rig.phase + gait * dt * math.pi / math.max(stepLength * 2, 0.5)) % (math.pi * 2)
	end

	-- ── Torso ── a slight bounce while walking, leaning back over cover, tipped flat lying down
	local bob = -math.abs(math.sin(rig.phase)) * 0.12 * math.min(rig.stride, 1) * (1 - rig.vault) * (1 - rig.prone)
	local rootTransform = CFrame.new(0, bob, 0) * CFrame.Angles(math.rad(22) * rig.vault + math.rad(14) * rig.rappel, 0, 0)
	rootTransform = rootTransform:Lerp(CFrame.new(0, -PRONE_DROP, 0) * CFrame.Angles(-math.rad(88), 0, 0), rig.prone)
	local lowerTorsoCF = childCFrame(rig.rootJoint, root.CFrame, rootTransform)
	rig.rootJoint.motor.Transform = rootTransform

	-- Lean sideways, bend toward where they look, hunch a bit when crouched or busy; lying down,
	-- the chest comes up onto the elbows
	local waistPitch = rig.pitch * 0.45 - math.rad(12) * rig.crouch - math.rad(25) * rig.kneel + math.rad(28) * rig.prone
	-- Bladed stance: the upper body turns toward the gun side so the left shoulder comes forward
	-- (Roblox arms are short; square on, the left hand can't reach the front of the gun).
	-- Handguns are held square on, both arms pushed out in front. Lying down: square on too.
	local handgun = rig.gun ~= nil and rig.gun.handgun
	local twist = math.rad(if handgun then -10 else -38) * (1 - rig.busy) * (1 - rig.prone)
	local waistTransform = CFrame.Angles(waistPitch, twist, -rig.lean * math.rad(Config.LeanBodyAngle))
	local upperTorsoCF = childCFrame(rig.waist, lowerTorsoCF, waistTransform)
	rig.waist.motor.Transform = waistTransform
	-- The head turns back the other way so it still looks straight ahead; down when busy; lying
	-- down it tips back up to look forward
	rig.neck.motor.Transform = CFrame.Angles(rig.pitch * 0.55 - math.rad(15) * rig.kneel + math.rad(58) * rig.prone, -twist, 0)

	-- ── Legs ──
	poseLeg(rig.left, -1, lowerTorsoCF, rig, facing, moveDir, ground)
	poseLeg(rig.right, 1, lowerTorsoCF, rig, facing, moveDir, ground)

	-- ── Gun ── shouldered and aimed where they look; lowered while sprinting; tilted while reloading
	local weaponName = other:GetAttribute("Weapon")
	if typeof(weaponName) ~= "string" or not Weapons[weaponName] then -- (no gun: Knives Only)
		destroyGun(rig)
		return
	end
	ensureGun(rig, weaponName, Skins.EquippedFor(other, weaponName), Attachments.For(other, weaponName))
	local gun = rig.gun :: Gun

	local now = os.clock()
	local reloadT = if now < rig.reloadEnd then (now - rig.reloadStart) / (rig.reloadEnd - rig.reloadStart) else -1
	local reloading = reloadT >= 0
	-- 0 → 1 → 0 bell over the reload, for the gun tilt
	local reloadTilt = if reloading then math.sin(reloadT * math.pi) else 0

	local shoulderPos = (upperTorsoCF * rig.right.shoulder.c0).Position
	local aim = facing * CFrame.Angles(rig.pitch, 0, 0)
	local lowReady = math.max(rig.sprint, rig.busy, rig.vault)
	local gunRotation = aim
		* CFrame.Angles(-math.rad(40) * lowReady, math.rad(35) * lowReady, 0)
		* CFrame.Angles(-math.rad(15) * reloadTilt, 0, math.rad(35) * reloadTilt)
	-- Long guns: right hand in front of the right shoulder, a bit low and toward the middle.
	-- Handguns: pushed out in front of the middle of the chest.
	local gripTarget = if gun.handgun
		then (upperTorsoCF * CFrame.new(0, 0.6, 0)).Position
			+ aim.LookVector * (1.5 - 0.5 * lowReady - rig.kick)
			- aim.UpVector * (0.15 + 0.6 * lowReady)
		else shoulderPos
			+ aim.LookVector * (1.05 - 0.3 * lowReady - rig.kick)
			- aim.UpVector * (0.3 + 0.35 * lowReady)
			- aim.RightVector * 0.4
	local gunCF = CFrame.new(gripTarget) * gunRotation * CFrame.new(-gun.rightGrip)
	-- Hands busy: the gun hangs at the right hip on its sling instead of floating
	local sling = math.max(rig.work, rig.busy)
	if sling > 0.01 then
		local hip = (lowerTorsoCF * CFrame.new(0.95, 0.1, -0.2)).Position
		local slung = CFrame.new(hip) * facing.Rotation * CFrame.Angles(-math.rad(70), 0, 0) * CFrame.new(-gun.rightGrip)
		gunCF = gunCF:Lerp(slung, easeInOut(sling))
	end
	moveGun(gun, gunCF)

	-- Roblox hands are big blocks: aim them a little under the grips so the gun sits on top of
	-- them instead of disappearing inside
	local rightHand = (gunCF * CFrame.new(gun.rightGrip - Vector3.new(0, 0.2, 0))).Position
	local leftHand = (gunCF * CFrame.new(gun.leftGrip - Vector3.new(0, 0.4, 0))).Position
	-- Roblox arms are short: if the handguard is out of reach, slide the left hand back along the
	-- gun toward the right hand until it fits
	local leftShoulder = (upperTorsoCF * rig.left.shoulder.c0).Position
	local reach = (rig.left.upperArm + rig.left.lowerArm + 0.3) * 0.97
	for _ = 1, 20 do
		if (leftHand - leftShoulder).Magnitude <= reach then
			break
		end
		leftHand -= gunCF.LookVector * 0.1
	end
	if reloading then
		-- Left hand: to the mag well, down to a pouch on the belt, back to the mag well, back to the grip
		local magWell = (gunCF * CFrame.new(Vector3.new(0, -0.45, -0.15) * GUN_SCALE)).Position
		local pouch = (lowerTorsoCF * CFrame.new(-0.6, -0.2, -0.6)).Position
		local t = reloadT
		if t < 0.2 then
			leftHand = leftHand:Lerp(magWell, easeInOut(t / 0.2))
		elseif t < 0.45 then
			leftHand = magWell:Lerp(pouch, easeInOut((t - 0.2) / 0.25))
		elseif t < 0.7 then
			leftHand = pouch:Lerp(magWell, easeInOut((t - 0.45) / 0.25))
		else
			leftHand = magWell:Lerp(leftHand, easeInOut((t - 0.7) / 0.3))
		end
	end
	if rig.rappel > 0.01 then
		-- Left hand up on the rope (RappelController draws it to this point), gun in the right
		local rope = rootPos + facing.LookVector * 0.5 - facing.RightVector * 0.45 + UP * 2.2
		leftHand = leftHand:Lerp(rope, rig.rappel)
	end
	if rig.work > 0.01 then
		leftHand = leftHand:Lerp(rig.workLeft, rig.work)
		rightHand = rightHand:Lerp(rig.workRight, rig.work)
	elseif rig.busy > 0.01 then
		-- Deploying cover (or reviving): both hands reach down in front. Downed: both hands
		-- pressed to their middle (holding the wound)
		local reachLeft = (if downed then lowerTorsoCF * CFrame.new(-0.25, 0.3, -0.75) else root.CFrame * CFrame.new(-0.5, -2.3, -1.8)).Position
		local reachRight = (if downed then lowerTorsoCF * CFrame.new(0.25, 0.45, -0.75) else root.CFrame * CFrame.new(0.5, -2.3, -1.8)).Position
		leftHand = leftHand:Lerp(reachLeft, rig.busy)
		rightHand = rightHand:Lerp(reachRight, rig.busy * 0.8)
	end
	poseArm(rig.right, 1, upperTorsoCF, rightHand, rig.prone)
	poseArm(rig.left, -1, upperTorsoCF, leftHand, rig.prone)
end

local function release(character: Model)
	local rig = rigs[character]
	if rig then
		destroyGun(rig)
		rigs[character] = nil
	end
end

local function update(dt: number)
	for _, other in Players:GetPlayers() do
		local character = other.Character
		if not character then
			continue
		end
		-- Your own body is only animated in the lobby (in first person you can't see it, and its
		-- held gun would block your view)
		if other == player and not state.inLobby then
			release(character)
			continue
		end
		local rig = rigs[character]
		if not rig then
			rig = makeRig(character)
			if not rig then
				-- Usually an R6 avatar (no elbows / knees). Say so once, clearly.
				if not warned[character] and character:FindFirstChild("Torso") then
					warned[character] = true
					warn(`[BodyAnimator] {other.Name}'s avatar is R6, so it can't be animated. In Studio: Game Settings > Avatar > Avatar type = R15.`)
				end
				continue
			end
			rigs[character] = rig
		end
		if rig.humanoid.Health <= 0 or not rig.root.Parent then
			destroyGun(rig) -- ragdoll falls on its own
			continue
		end
		animate(rig, other, dt)
	end
	-- Forget characters that are gone
	for character in rigs do
		if not character.Parent then
			release(character)
		end
	end
end

-- Tell the server where we're looking up/down so others can aim our body and gun
local lastSentPitch = math.huge
local lastSendTime = 0
local function sendPitch()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	local now = os.clock()
	-- In the third-person lobby the camera looks down at you, so just aim straight ahead
	local pitch = if state.inLobby then 0 else math.asin(math.clamp(Workspace.CurrentCamera.CFrame.LookVector.Y, -1, 1))
	if now - lastSendTime >= PITCH_SEND_RATE and math.abs(pitch - lastSentPitch) >= PITCH_SEND_STEP then
		lastSendTime = now
		lastSentPitch = pitch
		LookPitch:FireServer(pitch)
	end
end

-- The gun model in `character`'s hands as everyone else sees it (LaserSights), if it has one
function BodyAnimator.HeldGun(character: Model): Model?
	local rig = rigs[character]
	return if rig and rig.gun then rig.gun.model else nil
end

function BodyAnimator.Start()
	-- A new body has no LookPitch yet: send ours again even if we're still looking the same way
	player.CharacterAdded:Connect(function()
		lastSentPitch = math.huge
	end)
	ReloadStarted.OnClientEvent:Connect(function(reloader: Player, weaponName: string, duration: number?)
		local rig = reloader.Character and rigs[reloader.Character]
		local weapon = Weapons[weaponName]
		if rig and weapon then
			rig.reloadStart = os.clock()
			rig.reloadEnd = rig.reloadStart + (duration or weapon.ReloadTime) -- (empty reloads take longer)
		end
	end)
	ShotFired.OnClientEvent:Connect(function(shooter: Player)
		local rig = shooter.Character and rigs[shooter.Character]
		if rig then
			rig.kick = math.min(rig.kick + 0.12, 0.25)
		end
	end)
	Players.PlayerRemoving:Connect(function(other)
		if other.Character then
			release(other.Character)
		end
	end)
	-- PreSimulation is where hand-made joint Transforms are meant to be set (each frame)
	RunService.PreSimulation:Connect(update)
	RunService.Heartbeat:Connect(sendPitch)
end

return BodyAnimator
