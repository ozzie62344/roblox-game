-- First-person hands for everything that isn't shooting: sticking gadgets on walls and floors,
-- throwing the EMP, the detonator, the recon scanner, the ghost step wrist tap, pushing an armor
-- panel into a doorway, planting / disabling the defuser, barricading, reinforcing and pulling up
-- deployable cover. Two gloved arms come from your shoulders and reach (two-bone IK) for points
-- in the world or in front of your eyes, holding small props; the gun is put away meanwhile
-- (WeaponController hides it while state.gesturing / interacting / deploying).
--   • short moves ("gestures"): the server sets Gesture / GestureTarget / GestureAt on your
--     character when an ability goes off (GadgetService.Gesture)
--   • holds: your Interaction / InteractEndsAt attributes (plant, disable, barricade, reinforce)
--   • deployable cover: AbilityController calls PlayCover with the server's timing
-- Other players' bodies do the same moves in third person: BodyAnimator calls Current / Sample
-- with their head instead of your camera (and shows someone driving a drone holding a tablet).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local MatchConfig = require(ReplicatedStorage.Shared.MatchConfig)
local state = require(script.Parent.Parent.PlayerState)
local Viewmodel = require(script.Parent.Parent.Combat.Viewmodel)

local MatchState = ReplicatedStorage:WaitForChild("MatchState")

local player = Players.LocalPlayer

local HandsAnimator = {}

-- Short moves: how they go, what's in the hand, seconds
HandsAnimator.Gestures = {
	BreachCharge = { move = "place", prop = "charge", time = 0.55 },
	HardBreach = { move = "place", prop = "thermite", time = 0.6 },
	ShockWire = { move = "place", prop = "battery", time = 0.6 },
	SignalJammer = { move = "place", prop = "jammer", time = 0.55 },
	ArmorPanel = { move = "push", time = 0.6 },
	EmpGrenade = { move = "throw", prop = "grenade", time = 0.65 },
	Detonate = { move = "detonate", prop = "detonator", time = 0.6 },
	ReconPulse = { move = "scan", prop = "scanner", time = 0.8 },
	GhostStep = { move = "wrist", prop = "band", time = 0.6 },
} :: { [string]: { move: string, prop: string?, time: number } }
-- Holds last as long as the server's timers
local HOLD_TIME = {
	Plant = MatchConfig.PlantTime,
	Disable = MatchConfig.DisableTime,
	Barricade = MatchConfig.BarricadeTime,
	Unbarricade = MatchConfig.UnbarricadeTime,
	Reinforce = MatchConfig.ReinforceTime,
}

local UPPER_ARM, FOREARM = 1.15, 1.15
-- Camera-space anchors
local SHOULDERS = { Left = Vector3.new(-0.75, -0.95, -0.15), Right = Vector3.new(0.75, -0.95, -0.15) }
local REST = { Left = Vector3.new(-0.45, -0.9, -1.2), Right = Vector3.new(0.45, -0.9, -1.2) }
local LOOK_DOWN = math.rad(28) -- planting / disabling: eyes down on the defuser
local HELD = CFrame.new(0, 0.05, -0.3) -- a prop in the fist, just past the knuckles
local COVER_GRAB = 0.2 -- matches AbilityService: first 20% of the cover deploy is the grab

export type Context = {
	eye: CFrame, -- your camera, or another player's head looking where they look
	t: number, -- 0 → 1 through the move / hold
	elapsed: number, -- seconds since it started
	target: CFrame?, -- gestures: where the device went (look vector out of the surface); cover: its final spot
	size: Vector3?, -- cover: its size
	slot: BasePart?, -- barricade / reinforce: the doorway / wall section / hatch being worked on
	ground: Vector3?, -- plant: the spot on the floor
	defuser: Vector3?, -- disable: the planted defuser
}
-- A prop held in a hand, sitting somewhere, or on its way from one to the other (alpha 0 → 1)
type Prop = { hand: string?, offset: CFrame?, at: CFrame?, alpha: number? }

local function smoothstep(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

-- 0 before a, 1 after b, eased in between
local function ramp(t: number, a: number, b: number): number
	return smoothstep((t - a) / (b - a))
end

-- A quick 0 → 1 → 0 between a and b (a button press, a tap)
local function pulse(t: number, a: number, b: number): number
	return math.sin(math.clamp((t - a) / (b - a), 0, 1) * math.pi)
end

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 1e-3 then f.Unit else Vector3.zAxis
end

-- Barricade / reinforce: hands on the edge of the boards / plate as it goes up (the same easing
-- FortifyEffects draws it with): pulling the boards down by their bottom edge as they unroll from
-- the top (then nailing them at chest height), on the steel's top edge as it rises, at the
-- leading edge of a hatch plate sliding across
local function edgeHands(kind: string, ctx: Context): (Vector3?, Vector3?)
	local slot = ctx.slot
	local cframe = slot and slot:GetAttribute("BuildCFrame")
	local size = slot and slot:GetAttribute("BuildSize")
	if typeof(cframe) ~= "CFrame" or typeof(size) ~= "Vector3" then
		return nil, nil
	end
	local grow = 1 - (1 - math.clamp(ctx.t, 0, 1)) ^ 2
	local eye = ctx.eye.Position
	local a, b
	if size.Y < 1 then
		local edge = cframe * CFrame.new(-size.X / 2 + size.X * grow, 0.3, 0)
		a, b = (edge * CFrame.new(0, 0, -1)).Position, (edge * CFrame.new(0, 0, 1)).Position
	else
		local alongX = size.X > size.Z
		local across = if alongX then Vector3.zAxis else Vector3.xAxis
		local along = if alongX then Vector3.xAxis else Vector3.zAxis
		local thickness = if alongX then size.Z else size.X
		local length = if alongX then size.X else size.Z
		local side = if (eye - cframe.Position):Dot(across) >= 0 then 1 else -1
		local height = size.Y * grow
		local y = if kind == "Barricade"
			then math.max(size.Y / 2 - height, eye.Y - 1.1 - cframe.Position.Y) -- pull them down to chest height, then nail them
			else -size.Y / 2 + height
		-- Banging the boards up / shoving the steel: a little in-and-out on the beat
		local beat = math.sin(ctx.elapsed * (if kind == "Barricade" then 16 else 10)) * 0.07
		local point = cframe.Position + across * side * (thickness / 2 + 0.25 + beat) + Vector3.yAxis * y
		local spread = math.min(length / 2 - 0.4, 1.1)
		a, b = point - along * spread, point + along * spread
	end
	-- Left hand takes whichever point is on the left
	if (a - eye):Dot(ctx.eye.RightVector) > (b - eye):Dot(ctx.eye.RightVector) then
		a, b = b, a
	end
	return a, b
end

-- Where the hands go for move / hold `kind` (nil = resting in front of you) and where the props are
function HandsAnimator.Sample(kind: string, ctx: Context): (Vector3?, Vector3?, { [string]: Prop })
	local eye, t = ctx.eye, ctx.t
	local function cam(x: number, y: number, z: number): Vector3
		return (eye * CFrame.new(x, y, z)).Position
	end
	local restL, restR = cam(REST.Left.X, REST.Left.Y, REST.Left.Z), cam(REST.Right.X, REST.Right.Y, REST.Right.Z)
	local side = flat(eye.RightVector)
	local up = Vector3.yAxis
	local props: { [string]: Prop } = {}
	local gesture = HandsAnimator.Gestures[kind]
	local move = if gesture then gesture.move else kind

	if move == "place" then
		-- Reach out, press the device onto the wall / floor, pull back
		local target = ctx.target
		if not target or not gesture then
			return nil, nil, props
		end
		local contact = target.Position + target.LookVector * 0.3
		local reach = ramp(t, 0, 0.45) * (1 - ramp(t, 0.62, 1))
		if t < 0.55 then
			props[gesture.prop :: string] = { hand = "Right", offset = HELD, at = target * CFrame.new(0, 0, -0.12), alpha = ramp(t, 0.25, 0.45) }
		end
		return restL:Lerp(contact - side * 0.55, reach * 0.8), restR:Lerp(contact, reach), props
	elseif move == "push" then
		-- Both hands shove the armor panel into the doorway
		local center = if ctx.target then ctx.target.Position else cam(0, -1.2, -2)
		local chest = Vector3.new(center.X, eye.Position.Y - 1.3, center.Z)
		local reach = ramp(t, 0, 0.4) * (1 - ramp(t, 0.65, 1))
		return restL:Lerp(chest - side * 0.9, reach), restR:Lerp(chest + side * 0.9, reach), props
	elseif move == "throw" then
		-- Wind up over the shoulder, snap forward, let go, follow through
		local windup, release = cam(0.8, 0.15, 0.25), cam(0.25, 0.1, -2.1)
		local right = if t < 0.35
			then restR:Lerp(windup, ramp(t, 0, 0.35))
			elseif t < 0.5 then windup:Lerp(release, (t - 0.35) / 0.15)
			else release:Lerp(restR, ramp(t, 0.5, 1))
		if t < 0.47 then
			props[gesture.prop :: string] = { hand = "Right", offset = HELD }
		end
		return restL:Lerp(cam(-0.35, -0.2, -1.7), ramp(t, 0, 0.3) * (1 - ramp(t, 0.55, 1))), right, props
	elseif move == "detonate" then
		-- Clicker up in front of you, a quick squeeze
		local raise = ramp(t, 0, 0.3) * (1 - ramp(t, 0.7, 1))
		local squeeze = pulse(t, 0.35, 0.5)
		if t < 0.95 then
			props.detonator = { hand = "Right", offset = CFrame.new(0, 0.12, -0.2) * CFrame.Angles(-math.rad(60), 0, 0) }
		end
		return nil, restR:Lerp(cam(0.3, -0.35 - 0.06 * squeeze, -1.05 + 0.05 * squeeze), raise), props
	elseif move == "scan" then
		-- Scanner up in the left hand, the right taps the screen
		local raise = ramp(t, 0, 0.25) * (1 - ramp(t, 0.75, 1))
		local tablet = eye * CFrame.new(-0.12, -0.32 - 0.7 * (1 - raise), -1.05) * CFrame.Angles(math.rad(25), math.rad(8), 0)
		props.scanner = { at = tablet }
		local tap = pulse(t, 0.3, 0.5)
		local grip = (tablet * CFrame.new(0, -0.4, -0.08)).Position -- holding it from below
		local press = (tablet * CFrame.new(0.34, -0.05, 0.28 - 0.2 * tap)).Position -- a finger on the screen's edge
		return grip, restR:Lerp(press, raise * 0.9), props
	elseif move == "wrist" then
		-- Left wrist up, the right hand taps the band on it
		local raise = ramp(t, 0, 0.25) * (1 - ramp(t, 0.7, 1))
		local wrist = cam(0.02, -0.42, -1.0)
		local tap = pulse(t, 0.3, 0.5)
		props.band = { hand = "Left", offset = CFrame.new(0, 0, 0.18) }
		return restL:Lerp(wrist, raise), restR:Lerp(wrist + side * 0.32 + up * (0.16 - 0.1 * tap), raise), props
	elseif kind == "Plant" then
		-- Carry the defuser down, set it on the floor, type the code in
		local ground = ctx.ground or cam(0, -4, -1.5)
		local down = ramp(t, 0, 0.12)
		local typing = math.max(math.sin(ctx.elapsed * 13), 0) * ramp(t, 0.22, 0.28)
		local onFloor = CFrame.lookAt(ground + up * 0.25, ground + up * 0.25 + flat(eye.LookVector))
		props.defuser = { hand = "Right", offset = HELD, at = onFloor, alpha = ramp(t, 0.1, 0.22) }
		return restL:Lerp(ground - side * 0.5 + up * 0.45, down), restR:Lerp(ground + side * 0.3 + up * (0.5 + 0.1 * typing), down), props
	elseif kind == "Disable" then
		-- Steady the defuser with the left hand, work on it with the tool in the right
		local defuser = ctx.defuser or ctx.ground or cam(0, -4, -1.5)
		local down = ramp(t, 0, 0.1)
		local probe = math.sin(ctx.elapsed * 9)
		props.tool = { hand = "Right", offset = CFrame.new(0, 0, -0.35) }
		return restL:Lerp(defuser - side * 0.45 + up * 0.35, down), restR:Lerp(defuser + side * (0.25 + 0.1 * probe) + up * (0.45 + 0.08 * math.cos(ctx.elapsed * 11)), down), props
	elseif kind == "Barricade" or kind == "Reinforce" or kind == "Unbarricade" then
		-- Taking boards down: the barricading moves played backwards (hands from chest height,
		-- ripping them up and off the doorway)
		local edgeCtx = ctx
		if kind == "Unbarricade" then
			edgeCtx = table.clone(ctx)
			edgeCtx.t = 1 - ctx.t
		end
		local left, right = edgeHands(if kind == "Unbarricade" then "Barricade" else kind, edgeCtx)
		local reach = ramp(t, 0, 0.12)
		return if left then restL:Lerp(left, reach) else nil, if right then restR:Lerp(right, reach) else nil, props
	elseif kind == "Controller" then
		-- Driving a drone (DroneController): both hands on the tablet in front of you
		local tablet = eye * CFrame.new(0, -0.75, -0.95) * CFrame.Angles(math.rad(40), 0, 0)
		props.scanner = { at = tablet }
		return (tablet * CFrame.new(-0.4, -0.15, 0)).Position, (tablet * CFrame.new(0.4, -0.15, 0)).Position, props
	elseif kind == "Cover" then
		-- Grab the shield's top edge and ride it up out of the ground (AbilityService's timing)
		local target, size = ctx.target, ctx.size
		if not target or not size then
			return nil, nil, props
		end
		local rise = if t < COVER_GRAB then 0 else -(math.cos(math.pi * math.clamp((t - COVER_GRAB) / (1 - COVER_GRAB), 0, 1)) - 1) / 2
		local topY = size.Y / 2 - size.Y * (1 - rise)
		local reach = smoothstep(t / COVER_GRAB)
		local gripL = (target * CFrame.new(-1.1, topY, size.Z / 2 + 0.1)).Position
		local gripR = (target * CFrame.new(1.1, topY, size.Z / 2 + 0.1)).Position
		return restL:Lerp(gripL, reach), restR:Lerp(gripR, reach), props
	end
	return nil, nil, props
end

-- The doorway / wall section someone is working on: the slot whose BuildEndsAt matches their
-- InteractEndsAt (FortifyService sets both from the same number)
local function workSlot(endsAt: number): BasePart?
	local map = Workspace:FindFirstChild("Map")
	for _, folderName in { "BarricadeSlots", "ReinforceSlots" } do
		local folder = map and map:FindFirstChild(folderName)
		for _, slot in if folder then folder:GetChildren() else {} do
			if slot:IsA("BasePart") and slot:GetAttribute("BuildEndsAt") == endsAt then
				return slot
			end
		end
	end
	return nil
end

-- Floor under a spot just in front of someone (where the charge goes down)
local function groundAhead(root: BasePart, character: Model): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local from = root.Position + flat(root.CFrame.LookVector) * 1.4
	local hit = Workspace:Raycast(from, Vector3.new(0, -8, 0), params)
	return if hit then hit.Position else from - Vector3.new(0, 3, 0)
end

-- What `who` is doing with their hands right now, if anything: the move and its context
-- (gestures and holds; cover is handled separately). `eye` = where they look from.
function HandsAnimator.Current(who: Player, character: Model, root: BasePart, eye: CFrame): (string?, Context?)
	local now = Workspace:GetServerTimeNow()
	local interaction = who:GetAttribute("Interaction")
	local endsAt = who:GetAttribute("InteractEndsAt")
	local holdTime = interaction and HOLD_TIME[interaction]
	if holdTime and typeof(endsAt) == "number" then
		local elapsed = now - (endsAt - holdTime)
		local ctx: Context = { eye = eye, t = elapsed / holdTime, elapsed = elapsed }
		if interaction == "Barricade" or interaction == "Reinforce" or interaction == "Unbarricade" then
			ctx.slot = workSlot(endsAt)
		elseif interaction == "Plant" then
			ctx.ground = groundAhead(root, character)
		else
			local defuser = MatchState:GetAttribute("DefuserPosition")
			ctx.defuser = if typeof(defuser) == "Vector3" then defuser else nil
			ctx.ground = groundAhead(root, character)
		end
		return interaction, ctx
	end
	if who:GetAttribute("Droning") then
		return "Controller", { eye = eye, t = 1, elapsed = 0 }
	end
	local gestureAt = character:GetAttribute("GestureAt")
	local name = character:GetAttribute("Gesture")
	local gesture = typeof(name) == "string" and HandsAnimator.Gestures[name]
	if gesture and typeof(gestureAt) == "number" and now - gestureAt < gesture.time then
		local target = character:GetAttribute("GestureTarget")
		local elapsed = math.max(now - gestureAt, 0)
		return name, { eye = eye, t = elapsed / gesture.time, elapsed = elapsed, target = if typeof(target) == "CFrame" then target else nil }
	end
	return nil, nil
end

-- ── Your own first-person arms ────────────────────────────────────────────────

local arms: Model? = nil
local limbs: { [string]: { upper: Part, fore: Part, hand: Part } } = {}
local props: { [string]: Model } = {}
local cover: { startedAt: number, duration: number, target: CFrame, size: Vector3 }? = nil
local lookDown = 0

local function newPart(parent: Instance, size: Vector3, color: Color3, material: Enum.Material): Part
	local part = Instance.new("Part")
	part.Size = size
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = parent
	return part
end

local function buildArms(): Model
	local model = Instance.new("Model")
	model.Name = "HandsAnimator"
	for _, sideName in { "Left", "Right" } do
		limbs[sideName] = {
			upper = newPart(model, Vector3.new(0.34, 0.34, 1), Viewmodel.SleeveColor, Enum.Material.Fabric),
			fore = newPart(model, Vector3.new(0.3, 0.3, 1), Viewmodel.SleeveColor, Enum.Material.Fabric),
			hand = newPart(model, Vector3.new(0.3, 0.32, 0.38), Viewmodel.GloveColor, Enum.Material.Leather),
		}
	end
	return model
end

-- Small props, built the first time they're needed, centred on their pivot
local DARK = Color3.fromRGB(40, 42, 46)
local PROP_BUILDERS: { [string]: (Model) -> () } = {
	charge = function(m)
		newPart(m, Vector3.new(1.1, 0.75, 0.2), Color3.fromRGB(78, 82, 62), Enum.Material.Fabric)
		newPart(m, Vector3.new(0.35, 0.3, 0.12), DARK, Enum.Material.Metal).CFrame = CFrame.new(0, 0.1, -0.15)
		newPart(m, Vector3.new(0.08, 0.08, 0.05), Color3.fromRGB(255, 40, 40), Enum.Material.Neon).CFrame = CFrame.new(0.1, 0.18, -0.22)
	end,
	thermite = function(m)
		newPart(m, Vector3.new(0.8, 1, 0.25), Color3.fromRGB(170, 72, 40), Enum.Material.Metal)
		for _, y in { 0.3, -0.3 } do
			newPart(m, Vector3.new(0.84, 0.1, 0.28), DARK, Enum.Material.Fabric).CFrame = CFrame.new(0, y, 0)
		end
	end,
	battery = function(m)
		newPart(m, Vector3.new(0.6, 0.45, 0.4), DARK, Enum.Material.Metal)
		newPart(m, Vector3.new(0.62, 0.1, 0.42), Color3.fromRGB(230, 190, 40), Enum.Material.SmoothPlastic).CFrame = CFrame.new(0, 0.1, 0)
	end,
	jammer = function(m)
		newPart(m, Vector3.new(0.7, 0.28, 0.5), Color3.fromRGB(50, 66, 52), Enum.Material.Metal)
		newPart(m, Vector3.new(0.05, 0.7, 0.05), DARK, Enum.Material.Metal).CFrame = CFrame.new(0.25, 0.45, 0.1)
		newPart(m, Vector3.new(0.1, 0.05, 0.1), Color3.fromRGB(60, 255, 120), Enum.Material.Neon).CFrame = CFrame.new(-0.2, 0.16, -0.1)
	end,
	grenade = function(m)
		newPart(m, Vector3.new(0.3, 0.46, 0.3), Color3.fromRGB(60, 110, 180), Enum.Material.Metal)
		newPart(m, Vector3.new(0.33, 0.08, 0.33), Color3.fromRGB(90, 170, 255), Enum.Material.Neon)
	end,
	detonator = function(m)
		newPart(m, Vector3.new(0.22, 0.5, 0.18), DARK, Enum.Material.Plastic)
		newPart(m, Vector3.new(0.12, 0.06, 0.1), Color3.fromRGB(220, 40, 40), Enum.Material.SmoothPlastic).CFrame = CFrame.new(0, 0.27, 0)
		newPart(m, Vector3.new(0.03, 0.35, 0.03), DARK, Enum.Material.Metal).CFrame = CFrame.new(0.07, 0.42, 0.05)
	end,
	scanner = function(m)
		newPart(m, Vector3.new(0.75, 0.5, 0.06), DARK, Enum.Material.Plastic)
		newPart(m, Vector3.new(0.65, 0.4, 0.01), Color3.fromRGB(255, 90, 90), Enum.Material.Neon).CFrame = CFrame.new(0, 0, 0.035)
	end,
	band = function(m)
		newPart(m, Vector3.new(0.36, 0.36, 0.1), Color3.fromRGB(150, 200, 255), Enum.Material.Neon)
	end,
	defuser = function(m) -- the attackers' device (looks like the planted one, ObjectiveService)
		newPart(m, Vector3.new(1.0, 0.4, 0.7), DARK, Enum.Material.Metal)
		newPart(m, Vector3.new(0.35, 0.05, 0.25), Color3.fromRGB(190, 195, 200), Enum.Material.SmoothPlastic).CFrame = CFrame.new(0.2, 0.22, 0)
		newPart(m, Vector3.new(0.1, 0.06, 0.1), Color3.fromRGB(255, 40, 40), Enum.Material.Neon).CFrame = CFrame.new(-0.3, 0.22, 0.15)
	end,
	tool = function(m) -- what defenders pry the defuser apart with
		newPart(m, Vector3.new(0.14, 0.14, 0.4), Color3.fromRGB(230, 190, 40), Enum.Material.Plastic)
		newPart(m, Vector3.new(0.05, 0.05, 0.3), DARK, Enum.Material.Metal).CFrame = CFrame.new(0, 0, -0.33)
	end,
}

local function prop(name: string): Model?
	if props[name] then
		return props[name]
	end
	local builder = PROP_BUILDERS[name]
	if not builder then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = name
	builder(model)
	model.WorldPivot = CFrame.new()
	props[name] = model
	return model
end

-- Stretch a part between two points
local function span(part: Part, a: Vector3, b: Vector3)
	part.Size = Vector3.new(part.Size.X, part.Size.Y, math.max((b - a).Magnitude, 0.05))
	part.CFrame = CFrame.lookAt((a + b) / 2, b)
end

-- Two-bone arm: the hand goes as near the target as the arm reaches; the elbow bows toward `pole`
local function solveArm(shoulder: Vector3, target: Vector3, pole: Vector3): (Vector3, Vector3)
	local toTarget = target - shoulder
	local distance = math.clamp(toTarget.Magnitude, 0.1, (UPPER_ARM + FOREARM) * 0.999)
	local direction = if toTarget.Magnitude > 1e-3 then toTarget.Unit else -Vector3.yAxis
	local hand = shoulder + direction * distance
	local along = (UPPER_ARM ^ 2 - FOREARM ^ 2 + distance ^ 2) / (2 * distance)
	local bow = math.sqrt(math.max(UPPER_ARM ^ 2 - along ^ 2, 0))
	local bend = pole - direction * pole:Dot(direction)
	bend = if bend.Magnitude > 1e-3 then bend.Unit else -Vector3.yAxis
	return shoulder + direction * along + bend * bow, hand
end

local function hide()
	if arms then
		arms.Parent = nil
	end
	for _, model in props do
		model.Parent = nil
	end
	state.gesturing = false
end

local function update(dt: number)
	local camera = Workspace.CurrentCamera
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local eye = camera.CFrame

	local kind, ctx = nil, nil
	-- (on the drone's camera your own arms aren't in view)
	if character and root and humanoid and humanoid.Health > 0 and not state.inLobby and not state.spectating and not state.droning then
		if cover and state.deploying then
			local elapsed = os.clock() - cover.startedAt
			kind, ctx = "Cover", { eye = eye, t = elapsed / cover.duration, elapsed = elapsed, target = cover.target, size = cover.size }
		else
			kind, ctx = HandsAnimator.Current(player, character, root, eye)
		end
	end

	-- Eyes down on the defuser while planting / disabling (the deploying cover owns this otherwise)
	local wantLook = if kind == "Plant" or kind == "Disable" then 1 else 0
	lookDown += (wantLook - lookDown) * (1 - math.exp(-8 * dt))
	if not state.deploying then
		state.deployPitch = -LOOK_DOWN * lookDown
	end

	if not kind or not ctx then
		hide()
		return
	end
	state.gesturing = HandsAnimator.Gestures[kind] ~= nil

	local left, right, wanted = HandsAnimator.Sample(kind, ctx)
	if not arms then
		arms = buildArms()
	end
	local model = arms :: Model
	model.Parent = camera
	local handCF: { [string]: CFrame } = {}
	for sideName, sign in { Left = -1, Right = 1 } do
		local limb = limbs[sideName]
		local want = (if sideName == "Left" then left else right) or (eye * CFrame.new(REST[sideName])).Position
		local shoulder = (eye * CFrame.new(SHOULDERS[sideName])).Position
		local elbow, hand = solveArm(shoulder, want, eye.RightVector * sign - eye.UpVector)
		span(limb.upper, shoulder, elbow)
		span(limb.fore, elbow, hand)
		handCF[sideName] = CFrame.lookAt(hand, hand + (hand - elbow))
		limb.hand.CFrame = handCF[sideName]
	end
	for name in PROP_BUILDERS do
		local spec = wanted[name]
		local propModel = if spec then prop(name) else props[name]
		if propModel and spec then
			local at = if spec.hand then handCF[spec.hand] * (spec.offset or CFrame.new()) else spec.at
			if spec.hand and spec.at then
				at = (at :: CFrame):Lerp(spec.at, spec.alpha or 0)
			end
			propModel:PivotTo(at :: CFrame)
			propModel.Parent = camera
		elseif propModel then
			propModel.Parent = nil
		end
	end
end

-- Pulling up deployable cover: duration / finalCFrame / size come from the server's DeployStart
function HandsAnimator.PlayCover(duration: number, finalCFrame: CFrame, size: Vector3)
	cover = { startedAt = os.clock(), duration = math.max(duration, 0.05), target = finalCFrame, size = size }
end

function HandsAnimator.StopCover()
	cover = nil
end

function HandsAnimator.Start()
	RunService:BindToRenderStep("HandsAnimator", Enum.RenderPriority.Camera.Value + 4, update)
end

return HandsAnimator
