-- Detailed first-person gun models, built from ordinary parts (no meshes or textures needed).
-- The realism comes from real-world proportions, lots of small pieces (rails, pins, sights,
-- slots), Roblox's built-in materials (Metal, Plastic, Wood, Rubber, Glass...) and colors.
--
-- Model space (studs at viewmodel scale, a rifle is about 3 long): -Z points out of the
-- muzzle, +Y is up, +X is the gun's right side. The PrimaryPart "Body" sits at the origin.
--
-- Attachments on Body that Viewmodel relies on:
--   Muzzle     barrel tip: tracers start here and the muzzle flash appears here
--   AimPoint   the spot on the sight your eye looks through (red-dot window, rear-sight notch,
--              scope eyepiece). Its -Z axis is the line of sight. Attribute EyeRelief = how
--              many studs in front of the camera it sits when you aim in, tuned for a camera
--              that draws things down to 0.1 studs away (Viewmodel moves the gun further out
--              on platforms that clip closer things). Optional HipShift (Vector3) replaces
--              Viewmodel's usual hip-fire offset for this gun.
--   RightGrip / LeftGrip   where each hand holds the gun. Y runs along the handle toward the
--              thumb, -Z is the way the fingers wrap around it, +X points from the handle to
--              the back of the right hand (the left hand is a mirror image, so its palm is on
--              the -X side). Attributes describe the handle so the hand fits it:
--                RadiusX / RadiusZ   half the handle's thickness along X / Z
--                ThumbAngle          degrees the thumb wraps around the back of the handle
--                                    (negative: it stays on the palm side, pointing forward)
--                ThumbLift           how far the thumb reaches along the handle
--                PalmAngle           degrees the palm is turned toward the thumb (real hands
--                                    hold handles at a slight diagonal)
--                TriggerFinger       the index finger goes to the Trigger attachment
--                ForearmFollow       0..1, how much the forearm lines up with the hand instead
--                                    of dropping toward the body (keeps sleeves out of view)
--                ForearmDirection    optional Vector3: which way the forearm drops toward the
--                                    body for this gun (replaces Viewmodel's usual direction)
--   Trigger    where the right index finger rests

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Skins = require(ReplicatedStorage.Shared.Skins)
local GunMaterials = require(script.Parent.GunMaterials)
local SkinPainter = require(script.Parent.SkinPainter)

local GunModels = {}

export type Finish = {
	Color: Color3,
	Material: Enum.Material,
	Transparency: number?,
	Reflectance: number?,
	NoSkin: boolean?, -- skins leave it alone (bores, lenses, brass, sight dots)
}
type GripSettings = { [string]: number | boolean | Vector3 }
type MagSegments = { { number } }

function GunModels.Finish(color: Color3, material: Enum.Material, transparency: number?, reflectance: number?): Finish
	return { Color = color, Material = material, Transparency = transparency, Reflectance = reflectance }
end

-- A finish skins don't paint over
local function fixed(finish: Finish): Finish
	finish.NoSkin = true
	return finish
end

-- Shared finishes
local STEEL = GunModels.Finish(Color3.fromRGB(36, 37, 40), Enum.Material.Metal) -- blued / parkerized steel
local DARK_STEEL = GunModels.Finish(Color3.fromRGB(22, 22, 24), Enum.Material.Metal)
local POLYMER = GunModels.Finish(Color3.fromRGB(31, 32, 34), Enum.Material.Plastic)
local POLYMER_DARK = GunModels.Finish(Color3.fromRGB(22, 22, 24), Enum.Material.Plastic)
local RUBBER = GunModels.Finish(Color3.fromRGB(19, 19, 20), Enum.Material.Rubber)
local HOLE = fixed(GunModels.Finish(Color3.fromRGB(8, 8, 9), Enum.Material.SmoothPlastic)) -- bores, ports, slots
local BRASS = fixed(GunModels.Finish(Color3.fromRGB(196, 156, 74), Enum.Material.Metal, nil, 0.1))
local LENS = fixed(GunModels.Finish(Color3.fromRGB(150, 190, 205), Enum.Material.Glass, 0.8, 0.05))
local SCOPE_GLASS = fixed(GunModels.Finish(Color3.fromRGB(22, 38, 54), Enum.Material.Glass, 0.15, 0.3))
local RED_DOT = fixed(GunModels.Finish(Color3.fromRGB(255, 40, 40), Enum.Material.Neon))

-- One viewmodel part. It only exists on your screen, so it never collides, blocks shots,
-- touches anything or casts a shadow.
function GunModels.MakePart(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	look: Finish,
	shape: Enum.PartType?
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = shape or Enum.PartType.Block
	part.Size = size
	part.CFrame = cframe
	part.Color = look.Color
	part.Material = look.Material
	part.MaterialVariant = GunMaterials.VariantFor(look.Material)
	part.Transparency = look.Transparency or 0
	part.Reflectance = look.Reflectance or 0
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	if look.NoSkin then
		part:SetAttribute("NoSkin", true)
	end
	part.Parent = parent
	return part
end

-- Roblox cylinders are round around their X axis; these turn that axis to run along Z / Y
local ALONG_Z = CFrame.Angles(0, math.rad(90), 0)
local ALONG_Y = CFrame.Angles(0, 0, math.rad(90))

local function box(parent: Instance, name: string, size: Vector3, cframe: CFrame, look: Finish): Part
	return GunModels.MakePart(parent, name, size, cframe, look)
end

-- A box whose four edges running along `axis` (in the box's own space) are rounded off: two
-- crossed boxes plus a cylinder down each edge. Real receivers, grips and stocks never have
-- knife-sharp edges, and the rounded ones catch the light like machined / molded parts.
-- Every piece is named `name` (the Viewmodel finds moving groups by name) and shares a "Piece"
-- number and the whole box's "PieceSize" so skins paint them alike; the extra pieces are marked
-- "Edge". Returns the main box.
local pieceCount = 0
local function rounded(parent: Instance, name: string, size: Vector3, cframe: CFrame, look: Finish, radius: number, axis: string): Part
	pieceCount += 1
	-- The two directions across the rounded edges
	local a = if axis == "X" then Vector3.yAxis else Vector3.xAxis
	local b = if axis == "Z" then Vector3.yAxis else Vector3.zAxis
	local r = math.min(radius, size:Dot(a) / 2, size:Dot(b) / 2)
	local main = box(parent, name, size - a * 2 * r, cframe, look)
	local pieces = { main, box(parent, name, size - b * 2 * r, cframe, look) }
	local length = if axis == "X" then size.X elseif axis == "Y" then size.Y else size.Z
	local turn = if axis == "X" then CFrame.identity elseif axis == "Y" then ALONG_Y else ALONG_Z
	for _, sa in { -1, 1 } do
		for _, sb in { -1, 1 } do
			local offset = a * sa * (size:Dot(a) / 2 - r) + b * sb * (size:Dot(b) / 2 - r)
			local edge = Vector3.new(length, 2 * r, 2 * r)
			table.insert(pieces, GunModels.MakePart(parent, name, edge, cframe * CFrame.new(offset) * turn, look, Enum.PartType.Cylinder))
		end
	end
	for i, piece in pieces do
		piece:SetAttribute("Piece", pieceCount)
		piece:SetAttribute("PieceSize", size)
		if i > 1 then
			piece:SetAttribute("Edge", true)
		end
	end
	return main
end

-- Rounds off the long edges of every sizeable box in a finished model (see `rounded`): the
-- edges along its longest side, with a radius of a fifth of its thinner cross section. Thin
-- plates, rails, pins, holes and glass stay sharp; pieces a builder already rounded are left.
local function smoothEdges(model: Model)
	local extents = model:GetExtentsSize()
	local big = math.max(extents.X, extents.Y, extents.Z) * 0.07
	for _, part in model:GetChildren() do
		if not part:IsA("Part") or part.Shape ~= Enum.PartType.Block or part:GetAttribute("Piece") or part:GetAttribute("NoSkin") or part.Transparency > 0 then
			continue
		end
		local size = part.Size
		local longest = math.max(size.X, size.Y, size.Z)
		local axis = if longest == size.Z then "Z" elseif longest == size.Y then "Y" else "X"
		local across = if axis == "Z" then { size.X, size.Y } elseif axis == "Y" then { size.X, size.Z } else { size.Y, size.Z }
		local thinnest = math.min(across[1], across[2])
		if longest < big or thinnest < 0.05 then
			continue
		end
		local look = GunModels.Finish(part.Color, part.Material, nil, part.Reflectance)
		local main = rounded(model, part.Name, size, part.CFrame, look, math.min(thinnest * 0.2, 0.04), axis)
		if model.PrimaryPart == part then
			-- Keep the gun's attachments (grips, sight, muzzle) on the part the model is built around
			for _, child in part:GetChildren() do
				child.Parent = main
			end
			model.PrimaryPart = main
		end
		part:Destroy()
	end
end

-- Round bar running front-to-back (barrels, tubes, scope bodies), centered at `center`
local function tube(
	parent: Instance,
	name: string,
	length: number,
	diameter: number,
	center: Vector3,
	look: Finish
): Part
	local size = Vector3.new(length, diameter, diameter)
	return GunModels.MakePart(parent, name, size, CFrame.new(center) * ALONG_Z, look, Enum.PartType.Cylinder)
end

-- Round bar standing up (turrets, foregrips, shells)
local function post(
	parent: Instance,
	name: string,
	length: number,
	diameter: number,
	center: Vector3,
	look: Finish
): Part
	local size = Vector3.new(length, diameter, diameter)
	return GunModels.MakePart(parent, name, size, CFrame.new(center) * ALONG_Y, look, Enum.PartType.Cylinder)
end

-- Round bar running left-right (pins, knobs)
local function pin(
	parent: Instance,
	name: string,
	length: number,
	diameter: number,
	center: Vector3,
	look: Finish
): Part
	local size = Vector3.new(length, diameter, diameter)
	return GunModels.MakePart(parent, name, size, CFrame.new(center), look, Enum.PartType.Cylinder)
end

-- Round bar from point a to point b (also used for fingers and arms)
function GunModels.Rod(parent: Instance, name: string, a: Vector3, b: Vector3, diameter: number, look: Finish): Part
	local direction = b - a
	local up = if math.abs(direction.Unit.Y) > 0.99 then Vector3.xAxis else Vector3.yAxis
	local cframe = CFrame.lookAt((a + b) / 2, b, up) * ALONG_Z
	local size = Vector3.new(direction.Magnitude, diameter, diameter)
	return GunModels.MakePart(parent, name, size, cframe, look, Enum.PartType.Cylinder)
end

function GunModels.Ball(parent: Instance, name: string, diameter: number, position: Vector3, look: Finish): Part
	return GunModels.MakePart(parent, name, Vector3.one * diameter, CFrame.new(position), look, Enum.PartType.Ball)
end

-- Box stretched from point a to point b, kept upright (stock pieces that slope)
local function beam(
	parent: Instance,
	name: string,
	a: Vector3,
	b: Vector3,
	width: number,
	height: number,
	look: Finish
): Part
	return box(parent, name, Vector3.new(width, height, (b - a).Magnitude), CFrame.lookAt((a + b) / 2, b), look)
end

-- Picatinny rail along the top of the gun: a flat base with raised cross ridges.
-- `front` / `back` are Z positions, `y` is where the bottom of the rail sits.
local RAIL_PITCH = 0.075
local function rail(parent: Instance, name: string, front: number, back: number, y: number, look: Finish)
	local length = back - front
	box(parent, name, Vector3.new(0.07, 0.018, length), CFrame.new(0, y + 0.009, (front + back) / 2), look)
	local count = math.floor(length / RAIL_PITCH)
	local first = (front + back) / 2 - (count - 1) * RAIL_PITCH / 2
	for i = 0, count - 1 do
		local ridge = CFrame.new(0, y + 0.018, first + i * RAIL_PITCH)
		box(parent, `{name}Ridge`, Vector3.new(0.082, 0.016, 0.034), ridge, look)
	end
end

-- Box magazine hanging down from `top`. Each segment is { length, degrees }: the angle grows
-- segment by segment, so the magazine curves forward like a real one.
local function magazine(
	parent: Instance,
	top: Vector3,
	width: number,
	depth: number,
	segments: MagSegments,
	look: Finish,
	baseLook: Finish
)
	local point = top
	local angle = 0
	for index, segment in segments do
		local length = segment[1]
		angle = math.rad(segment[2])
		local down = Vector3.new(0, -math.cos(angle), -math.sin(angle))
		local cframe = CFrame.new(point + down * (length / 2)) * CFrame.Angles(angle, 0, 0)
		rounded(parent, `Mag{index}`, Vector3.new(width, length + 0.012, depth), cframe, look, math.min(width, depth) * 0.2, "Y")
		point += down * length
	end
	local down = Vector3.new(0, -math.cos(angle), -math.sin(angle))
	local baseCFrame = CFrame.new(point + down * 0.012) * CFrame.Angles(angle, 0, 0)
	box(parent, "MagBase", Vector3.new(width + 0.014, 0.03, depth + 0.02), baseCFrame, baseLook)
end

-- Red-dot reticle facing the shooter: a center dot inside a thin glowing ring
local function reticle(parent: Instance, center: Vector3, ringRadius: number)
	GunModels.Ball(parent, "ReticleDot", 0.007, center, RED_DOT)
	local segment = 2 * math.pi * ringRadius / 8
	for i = 0, 7 do
		local cframe = CFrame.new(center) * CFrame.Angles(0, 0, i * math.pi / 4) * CFrame.new(ringRadius, 0, 0)
		box(parent, "ReticleRing", Vector3.new(0.0028, segment, 0.002), cframe, RED_DOT)
	end
end

local function attach(body: Part, name: string, cframe: CFrame): Attachment
	local attachment = Instance.new("Attachment")
	attachment.Name = name
	attachment.CFrame = cframe
	attachment.Parent = body
	return attachment
end

local function addGrip(body: Part, name: string, cframe: CFrame, settings: GripSettings)
	local grip = attach(body, name, cframe)
	for key, value in settings do
		grip:SetAttribute(key, value)
	end
end

local function addSight(body: Part, position: Vector3, eyeRelief: number, hipShift: Vector3?)
	local aimPoint = attach(body, "AimPoint", CFrame.new(position))
	aimPoint:SetAttribute("EyeRelief", eyeRelief)
	if hipShift then
		aimPoint:SetAttribute("HipShift", hipShift)
	end
end

-- Grip frame for a handle that runs along `thumb`, with the fingers wrapping toward `fingers`
local function handleFrame(position: Vector3, thumb: Vector3, fingers: Vector3): CFrame
	local up = thumb.Unit
	local back = -(fingers - up * fingers:Dot(up)).Unit
	return CFrame.fromMatrix(position, up:Cross(back), up, back)
end

-- Support hand under a handguard / pump / forend: thumb along the left side pointing forward,
-- fingers curling up the right side, palm turned a bit like a real diagonal grip
local function underhandFrame(position: Vector3): CFrame
	return handleFrame(position, Vector3.new(-0.15, 0, -1), Vector3.new(1, 0, -0.15))
end

---------------------------------------------------------------------------------------------
-- Rifle: AR-15 style carbine with a holographic sight
---------------------------------------------------------------------------------------------
local function buildRifle(gun: Model, color: Color3): Part
	local anodized = GunModels.Finish(color, Enum.Material.Metal)
	local railLook = GunModels.Finish(color:Lerp(Color3.new(0, 0, 0), 0.2), Enum.Material.Metal)
	local optic = fixed(GunModels.Finish(Color3.fromRGB(40, 41, 44), Enum.Material.SmoothPlastic)) -- (skins leave sights alone)
	-- Flat dark earth polymer furniture (magazine, grip, stock), common on real rifles
	local furniture = GunModels.Finish(Color3.fromRGB(138, 116, 86), Enum.Material.Plastic)
	local furnitureDark = GunModels.Finish(Color3.fromRGB(112, 94, 70), Enum.Material.Plastic)

	-- Upper receiver (the Body) with its top rail, ejection port, forward assist, charging handle
	local body = box(gun, "Body", Vector3.new(0.095, 0.13, 0.72), CFrame.new(), anodized)
	rail(gun, "UpperRail", -0.36, -0.08, 0.065, railLook)
	rail(gun, "UpperRailRear", 0.24, 0.36, 0.065, railLook)
	box(gun, "EjectionPort", Vector3.new(0.006, 0.048, 0.2), CFrame.new(0.0475, 0.002, -0.03), HOLE)
	-- Dust cover hinged open under the port, and the brass deflector bump behind it
	box(gun, "DustCover", Vector3.new(0.008, 0.012, 0.19), CFrame.new(0.054, -0.03, -0.03) * CFrame.Angles(0, 0, math.rad(-35)), anodized)
	box(gun, "BrassDeflector", Vector3.new(0.024, 0.05, 0.035), CFrame.new(0.053, 0.02, 0.1), anodized)
	GunModels.Rod(gun, "ForwardAssist", Vector3.new(0.04, 0.02, 0.2), Vector3.new(0.085, 0.035, 0.3), 0.04, anodized)
	box(gun, "ChargingHandle", Vector3.new(0.16, 0.022, 0.035), CFrame.new(0, 0.045, 0.378), anodized)
	box(gun, "ChargingLatch", Vector3.new(0.035, 0.024, 0.05), CFrame.new(-0.085, 0.045, 0.372), anodized)

	-- Lower receiver, magazine well and a curved polymer magazine
	box(gun, "Lower", Vector3.new(0.105, 0.11, 0.62), CFrame.new(0, -0.12, 0.03), anodized)
	box(gun, "Magwell", Vector3.new(0.115, 0.075, 0.27), CFrame.new(0, -0.2, -0.135), anodized)
	local magSegments = { { 0.22, 0 }, { 0.17, 10 }, { 0.15, 20 } }
	magazine(gun, Vector3.new(0, -0.19, -0.135), 0.08, 0.22, magSegments, furniture, furnitureDark)
	box(gun, "BoltCatch", Vector3.new(0.012, 0.045, 0.05), CFrame.new(-0.057, -0.105, -0.02), anodized)
	box(gun, "Selector", Vector3.new(0.012, 0.022, 0.065), CFrame.new(-0.058, -0.1, 0.22), STEEL)
	pin(gun, "FrontPin", 0.112, 0.024, Vector3.new(0, -0.09, -0.25), STEEL)
	pin(gun, "RearPin", 0.112, 0.024, Vector3.new(0, -0.09, 0.3), STEEL)

	-- Angled pistol grip, trigger guard and trigger. gripTop's Y axis runs up the grip.
	local gripTop = CFrame.new(0, -0.175, 0.22) * CFrame.Angles(math.rad(-20), 0, 0)
	box(gun, "Grip", Vector3.new(0.1, 0.36, 0.165), gripTop * CFrame.new(0, -0.18, 0), furniture)
	box(gun, "GripBase", Vector3.new(0.104, 0.02, 0.17), gripTop * CFrame.new(0, -0.355, 0), furnitureDark)
	box(gun, "TriggerGuard", Vector3.new(0.03, 0.02, 0.16), CFrame.new(0, -0.255, 0.08), anodized)
	box(gun, "TriggerGuardFront", Vector3.new(0.03, 0.08, 0.025), CFrame.new(0, -0.215, 0.01), anodized)
	local triggerCFrame = CFrame.new(0, -0.205, 0.085) * CFrame.Angles(math.rad(12), 0, 0)
	box(gun, "Trigger", Vector3.new(0.02, 0.065, 0.022), triggerCFrame, STEEL)
	attach(body, "Trigger", CFrame.new(0, -0.222, 0.072))

	-- Buffer tube and collapsible stock
	tube(gun, "BufferTube", 0.66, 0.105, Vector3.new(0, -0.01, 0.69), anodized)
	tube(gun, "CastleNut", 0.03, 0.115, Vector3.new(0, -0.01, 0.38), STEEL)
	box(gun, "Stock", Vector3.new(0.13, 0.17, 0.48), CFrame.new(0, -0.01, 0.87), furniture)
	-- Underside slopes from the front of the stock down to the toe
	beam(gun, "StockToe", Vector3.new(0, -0.023, 0.715), Vector3.new(0, -0.218, 1.115), 0.12, 0.16, furniture)
	box(gun, "ButtPad", Vector3.new(0.135, 0.39, 0.035), CFrame.new(0, -0.11, 1.128), RUBBER)

	-- Free-float M-LOK handguard: a squared-off tube with rounded corners, a top rail, rows of
	-- slots down the sides and bottom, and a cut-down front end
	tube(gun, "BarrelNut", 0.03, 0.115, Vector3.new(0, -0.005, -0.37), STEEL)
	rounded(gun, "Handguard", Vector3.new(0.14, 0.145, 0.92), CFrame.new(0, -0.01, -0.84), anodized, 0.04, "Z")
	rounded(gun, "HandguardCap", Vector3.new(0.146, 0.151, 0.03), CFrame.new(0, -0.01, -1.29), railLook, 0.042, "Z")
	rail(gun, "HandguardRail", -1.3, -0.38, 0.0625, railLook)
	for i = 0, 3 do
		local z = -0.52 - i * 0.2
		for _, side in { -1, 1 } do
			box(gun, "MLokSlot", Vector3.new(0.006, 0.026, 0.12), CFrame.new(side * 0.0705, -0.005, z), HOLE)
		end
		box(gun, "MLokSlot", Vector3.new(0.05, 0.006, 0.12), CFrame.new(0, -0.0825, z), HOLE)
	end
	-- Low-profile gas block peeking out past the handguard
	rounded(gun, "GasBlock", Vector3.new(0.08, 0.075, 0.06), CFrame.new(0, -0.005, -1.335), STEEL, 0.015, "Z")
	-- Folded-down backup iron sights
	box(gun, "FrontSight", Vector3.new(0.05, 0.028, 0.075), CFrame.new(0, 0.105, -1.24), railLook)
	box(gun, "RearSight", Vector3.new(0.06, 0.025, 0.07), CFrame.new(0, 0.1035, 0.3), railLook)

	-- Barrel and birdcage flash hider
	tube(gun, "Barrel", 0.34, 0.062, Vector3.new(0, 0, -1.47), STEEL)
	tube(gun, "FlashHider", 0.17, 0.08, Vector3.new(0, 0, -1.725), STEEL)
	for i = -1, 1 do
		local slot = CFrame.new(0, 0, -1.75) * CFrame.Angles(0, 0, math.rad(i * 60)) * CFrame.new(0, 0.038, 0)
		box(gun, "FlashHiderSlot", Vector3.new(0.014, 0.006, 0.09), slot, HOLE)
	end
	tube(gun, "Bore", 0.006, 0.032, Vector3.new(0, 0, -1.811), HOLE)
	attach(body, "Muzzle", CFrame.new(0, 0, -1.815))

	-- Holographic sight: mount, electronics housing, hood, two glass windows, ring-and-dot reticle
	box(gun, "OpticMount", Vector3.new(0.12, 0.04, 0.3), CFrame.new(0, 0.085, 0.075), optic)
	box(gun, "OpticBody", Vector3.new(0.13, 0.035, 0.3), CFrame.new(0, 0.1225, 0.075), optic)
	for _, side in { -1, 1 } do
		box(gun, "OpticWall", Vector3.new(0.022, 0.12, 0.15), CFrame.new(side * 0.066, 0.2, 0), optic)
		box(gun, "OpticButton", Vector3.new(0.03, 0.01, 0.025), CFrame.new(side * 0.025, 0.145, 0.19), RUBBER)
	end
	box(gun, "OpticHood", Vector3.new(0.154, 0.022, 0.15), CFrame.new(0, 0.249, 0), optic)
	box(gun, "OpticFrontGlass", Vector3.new(0.11, 0.098, 0.005), CFrame.new(0, 0.189, -0.065), LENS)
	box(gun, "OpticRearGlass", Vector3.new(0.11, 0.098, 0.005), CFrame.new(0, 0.189, 0.065), LENS)
	pin(gun, "OpticKnob", 0.025, 0.035, Vector3.new(-0.075, 0.085, 0.16), STEEL)
	reticle(gun, Vector3.new(0, 0.19, 0.07), 0.018)
	addSight(body, Vector3.new(0, 0.19, 0.075), 0.62)

	-- Hands: right on the pistol grip, left under the handguard
	addGrip(body, "RightGrip", gripTop * CFrame.new(0, -0.17, 0), {
		RadiusX = 0.05,
		RadiusZ = 0.085,
		ThumbAngle = 190,
		ThumbLift = 0.04,
		PalmAngle = 25,
		TriggerFinger = true,
	})
	addGrip(body, "LeftGrip", underhandFrame(Vector3.new(0, -0.01, -0.98)), {
		RadiusX = 0.075,
		RadiusZ = 0.075,
		ThumbAngle = 95,
		ThumbLift = 0.18,
		PalmAngle = 30,
	})
	return body
end

---------------------------------------------------------------------------------------------
-- SMG: MP5 style with a collapsed stock, vertical foregrip and hooded iron sights
---------------------------------------------------------------------------------------------
local function buildSmg(gun: Model, color: Color3): Part
	local steel = GunModels.Finish(color, Enum.Material.Metal)

	-- Stamped receiver (the Body) with a rounded top and pressed ribs
	local body = box(gun, "Body", Vector3.new(0.11, 0.13, 0.78), CFrame.new(), steel)
	tube(gun, "ReceiverTop", 0.78, 0.11, Vector3.new(0, 0.035, 0), steel)
	for _, side in { -1, 1 } do
		box(gun, "ReceiverRib", Vector3.new(0.006, 0.018, 0.62), CFrame.new(side * 0.056, 0.015, -0.02), steel)
		-- Collapsed stock struts slide along the receiver sides
		tube(gun, "StockStrut", 0.5, 0.028, Vector3.new(side * 0.068, -0.03, 0.2), STEEL)
	end

	-- Cocking tube over the barrel, cocking handle on the left
	tube(gun, "CockingTube", 0.52, 0.072, Vector3.new(0, 0.055, -0.65), steel)
	tube(gun, "CockingTubeCap", 0.02, 0.064, Vector3.new(0, 0.055, -0.92), STEEL)
	box(gun, "CockingSlot", Vector3.new(0.004, 0.012, 0.2), CFrame.new(-0.0365, 0.055, -0.75), HOLE)
	GunModels.Rod(gun, "CockingHandle", Vector3.new(-0.03, 0.055, -0.82), Vector3.new(-0.1, 0.06, -0.8), 0.022, STEEL)
	GunModels.Ball(gun, "CockingKnob", 0.04, Vector3.new(-0.105, 0.06, -0.8), POLYMER)

	-- Short barrel with its locking lugs
	tube(gun, "Barrel", 0.17, 0.05, Vector3.new(0, 0, -1.0), STEEL)
	tube(gun, "BarrelLugs", 0.04, 0.068, Vector3.new(0, 0, -0.96), STEEL)
	tube(gun, "Bore", 0.006, 0.026, Vector3.new(0, 0, -1.086), HOLE)
	attach(body, "Muzzle", CFrame.new(0, 0, -1.09))

	-- Hooded front sight post
	box(gun, "FrontSightBase", Vector3.new(0.07, 0.11, 0.06), CFrame.new(0, 0.035, -0.9), steel)
	for _, side in { -1, 1 } do
		box(gun, "FrontSightEar", Vector3.new(0.012, 0.075, 0.055), CFrame.new(side * 0.033, 0.1275, -0.9), steel)
	end
	box(gun, "FrontSightHood", Vector3.new(0.078, 0.012, 0.055), CFrame.new(0, 0.171, -0.9), steel)
	box(gun, "FrontSightPost", Vector3.new(0.01, 0.0525, 0.014), CFrame.new(0, 0.11625, -0.9), STEEL)

	-- Rear aperture: you look through the small square hole, the front post's tip sits in it
	box(gun, "RearSightBase", Vector3.new(0.07, 0.035, 0.07), CFrame.new(0, 0.105, 0.3), steel)
	box(gun, "RearSightBottom", Vector3.new(0.07, 0.005, 0.03), CFrame.new(0, 0.125, 0.3), steel)
	box(gun, "RearSightTop", Vector3.new(0.07, 0.012, 0.03), CFrame.new(0, 0.1635, 0.3), steel)
	for _, side in { -1, 1 } do
		box(gun, "RearSightPost", Vector3.new(0.02, 0.047, 0.03), CFrame.new(side * 0.025, 0.146, 0.3), steel)
		box(gun, "RearSightEar", Vector3.new(0.012, 0.075, 0.09), CFrame.new(side * 0.052, 0.13, 0.3), steel)
	end
	addSight(body, Vector3.new(0, 0.1425, 0.3), 0.45)

	-- Polymer handguard with a short rail and a vertical foregrip
	box(gun, "Handguard", Vector3.new(0.13, 0.12, 0.42), CFrame.new(0, -0.045, -0.63), POLYMER)
	tube(gun, "HandguardBelly", 0.42, 0.13, Vector3.new(0, -0.065, -0.63), POLYMER)
	for _, side in { -1, 1 } do
		for i = 0, 1 do
			local groove = CFrame.new(side * 0.066, -0.025 - i * 0.04, -0.63)
			box(gun, "HandguardGroove", Vector3.new(0.004, 0.012, 0.3), groove, HOLE)
		end
	end
	box(gun, "ForegripRail", Vector3.new(0.06, 0.02, 0.24), CFrame.new(0, -0.14, -0.66), STEEL)
	box(gun, "ForegripClamp", Vector3.new(0.075, 0.045, 0.11), CFrame.new(0, -0.165, -0.66), POLYMER)
	post(gun, "Foregrip", 0.3, 0.1, Vector3.new(0, -0.335, -0.66), POLYMER)
	post(gun, "ForegripCap", 0.025, 0.108, Vector3.new(0, -0.49, -0.66), RUBBER)

	-- Curved steel magazine
	box(gun, "Magwell", Vector3.new(0.09, 0.08, 0.16), CFrame.new(0, -0.1, -0.2), steel)
	magazine(gun, Vector3.new(0, -0.12, -0.2), 0.066, 0.125, { { 0.2, 6 }, { 0.17, 15 }, { 0.15, 24 } }, STEEL, STEEL)
	box(gun, "MagRelease", Vector3.new(0.03, 0.012, 0.05), CFrame.new(0, -0.145, -0.1), STEEL)

	-- Trigger housing, pistol grip, trigger
	box(gun, "TriggerHousing", Vector3.new(0.1, 0.075, 0.42), CFrame.new(0, -0.1, 0.17), POLYMER)
	local gripTop = CFrame.new(0, -0.1375, 0.25) * CFrame.Angles(math.rad(-15), 0, 0)
	box(gun, "Grip", Vector3.new(0.1, 0.34, 0.16), gripTop * CFrame.new(0, -0.17, 0), POLYMER)
	box(gun, "GripBase", Vector3.new(0.104, 0.02, 0.165), gripTop * CFrame.new(0, -0.34, 0), POLYMER_DARK)
	box(gun, "TriggerGuardFront", Vector3.new(0.03, 0.085, 0.022), CFrame.new(0, -0.18, 0.02), POLYMER)
	box(gun, "TriggerGuard", Vector3.new(0.03, 0.02, 0.17), CFrame.new(0, -0.2225, 0.1), POLYMER)
	local triggerCFrame = CFrame.new(0, -0.165, 0.1) * CFrame.Angles(math.rad(12), 0, 0)
	box(gun, "Trigger", Vector3.new(0.02, 0.06, 0.022), triggerCFrame, STEEL)
	attach(body, "Trigger", CFrame.new(0, -0.182, 0.088))
	box(gun, "Selector", Vector3.new(0.012, 0.025, 0.06), CFrame.new(-0.056, -0.09, 0.27), STEEL)
	pin(gun, "PushPin", 0.104, 0.022, Vector3.new(0, -0.09, 0.05), STEEL)
	pin(gun, "PushPinRear", 0.104, 0.022, Vector3.new(0, -0.09, 0.34), STEEL)

	-- Butt plate of the collapsed stock, right behind the receiver
	box(gun, "ButtPlate", Vector3.new(0.16, 0.26, 0.04), CFrame.new(0, -0.13, 0.47), steel)
	box(gun, "ButtPad", Vector3.new(0.165, 0.27, 0.035), CFrame.new(0, -0.13, 0.505), RUBBER)

	-- Hands: right on the pistol grip, left wrapped around the foregrip
	addGrip(body, "RightGrip", gripTop * CFrame.new(0, -0.165, 0), {
		RadiusX = 0.05,
		RadiusZ = 0.08,
		ThumbAngle = 190,
		ThumbLift = 0.04,
		PalmAngle = 25,
		TriggerFinger = true,
	})
	addGrip(body, "LeftGrip", CFrame.new(0, -0.33, -0.66), {
		RadiusX = 0.05,
		RadiusZ = 0.05,
		ThumbAngle = 120,
		ThumbLift = 0.05,
		PalmAngle = 15,
	})
	return body
end

---------------------------------------------------------------------------------------------
-- Shotgun: pump action with a vent rib, bead sight, wood furniture and a shell carrier
---------------------------------------------------------------------------------------------
local function buildShotgun(gun: Model, color: Color3): Part
	local wood = GunModels.Finish(color:Lerp(Color3.fromRGB(150, 98, 58), 0.4), Enum.Material.Wood)
	local woodGroove = GunModels.Finish(color:Lerp(Color3.new(0, 0, 0), 0.3), Enum.Material.Wood)
	local blued = GunModels.Finish(Color3.fromRGB(32, 33, 37), Enum.Material.Metal)
	local bead = fixed(GunModels.Finish(Color3.fromRGB(235, 228, 205), Enum.Material.SmoothPlastic))
	local shell = fixed(GunModels.Finish(Color3.fromRGB(150, 28, 26), Enum.Material.Plastic))

	-- Receiver (the Body)
	local body = box(gun, "Body", Vector3.new(0.12, 0.19, 0.62), CFrame.new(), blued)
	box(gun, "ReceiverTop", Vector3.new(0.05, 0.004, 0.6), CFrame.new(0, 0.096, 0), DARK_STEEL)
	box(gun, "EjectionPort", Vector3.new(0.004, 0.065, 0.19), CFrame.new(0.0605, 0.025, -0.1), HOLE)
	box(gun, "LoadingPort", Vector3.new(0.075, 0.004, 0.26), CFrame.new(0, -0.0965, -0.12), HOLE)

	-- Barrel with a vented rib and a bead sight, magazine tube underneath
	tube(gun, "Barrel", 1.44, 0.082, Vector3.new(0, 0.025, -1.03), blued)
	box(gun, "Rib", Vector3.new(0.034, 0.01, 1.42), CFrame.new(0, 0.095, -1.04), blued)
	for i = 0, 4 do
		box(gun, "RibPost", Vector3.new(0.02, 0.025, 0.025), CFrame.new(0, 0.0775, -0.45 - i * 0.3), blued)
	end
	GunModels.Ball(gun, "Bead", 0.026, Vector3.new(0, 0.113, -1.725), bead)
	tube(gun, "Bore", 0.006, 0.042, Vector3.new(0, 0.025, -1.753), HOLE)
	attach(body, "Muzzle", CFrame.new(0, 0.025, -1.757))
	tube(gun, "MagTube", 1.1, 0.082, Vector3.new(0, -0.067, -0.86), blued)
	tube(gun, "MagCap", 0.075, 0.092, Vector3.new(0, -0.067, -1.4475), STEEL)
	tube(gun, "BarrelRing", 0.035, 0.096, Vector3.new(0, -0.067, -1.37), blued)
	box(gun, "BarrelLug", Vector3.new(0.035, 0.06, 0.035), CFrame.new(0, -0.02, -1.37), blued)
	-- Look along the receiver's top so the bead sits right on it
	addSight(body, Vector3.new(0, 0.113, 0.28), 0.8)

	-- Ribbed wooden pump (the left hand racks this)
	tube(gun, "Pump", 0.5, 0.155, Vector3.new(0, -0.06, -0.83), wood)
	for i = 0, 4 do
		tube(gun, "PumpGroove", 0.016, 0.159, Vector3.new(0, -0.06, -0.67 - i * 0.08), woodGroove)
	end

	-- Trigger group
	box(gun, "TriggerPlate", Vector3.new(0.1, 0.05, 0.3), CFrame.new(0, -0.115, 0.13), blued)
	box(gun, "TriggerGuardFront", Vector3.new(0.025, 0.075, 0.02), CFrame.new(0, -0.1775, 0.02), blued)
	box(gun, "TriggerGuard", Vector3.new(0.025, 0.02, 0.2), CFrame.new(0, -0.215, 0.11), blued)
	box(gun, "TriggerGuardRear", Vector3.new(0.025, 0.075, 0.02), CFrame.new(0, -0.1775, 0.2), blued)
	local triggerCFrame = CFrame.new(0, -0.165, 0.1) * CFrame.Angles(math.rad(12), 0, 0)
	box(gun, "Trigger", Vector3.new(0.018, 0.06, 0.02), triggerCFrame, STEEL)
	attach(body, "Trigger", CFrame.new(0, -0.182, 0.088))
	pin(gun, "Safety", 0.112, 0.024, Vector3.new(0, -0.115, 0.25), STEEL)

	-- Wood stock: wrist with a pistol grip, comb sloping down to the heel, toe, recoil pad
	local gripTop = CFrame.new(0, -0.03, 0.33) * CFrame.Angles(math.rad(-40), 0, 0)
	beam(gun, "StockWrist", Vector3.new(0, 0, 0.3), Vector3.new(0, -0.11, 0.66), 0.105, 0.16, wood)
	box(gun, "Grip", Vector3.new(0.1, 0.36, 0.15), gripTop * CFrame.new(0, -0.15, 0), wood)
	box(gun, "GripCap", Vector3.new(0.104, 0.025, 0.155), gripTop * CFrame.new(0, -0.33, 0), POLYMER_DARK)
	beam(gun, "StockComb", Vector3.new(0, -0.14, 0.62), Vector3.new(0, -0.22, 1.24), 0.11, 0.2, wood)
	beam(gun, "StockToe", Vector3.new(0, -0.31, 0.56), Vector3.new(0, -0.41, 1.24), 0.105, 0.24, wood)
	box(gun, "RecoilPad", Vector3.new(0.115, 0.46, 0.05), CFrame.new(0, -0.3, 1.265), RUBBER)

	-- Side saddle on the left with four spare shells (brass up)
	box(gun, "SideSaddle", Vector3.new(0.012, 0.13, 0.3), CFrame.new(-0.066, -0.01, -0.02), POLYMER)
	for i = 0, 3 do
		local z = -0.125 + i * 0.07
		post(gun, "Shell", 0.18, 0.064, Vector3.new(-0.106, -0.04, z), shell)
		post(gun, "ShellBase", 0.04, 0.067, Vector3.new(-0.106, 0.07, z), BRASS)
	end

	-- Hands: right on the stock's grip, left on the pump
	addGrip(body, "RightGrip", gripTop * CFrame.new(0, -0.14, 0), {
		RadiusX = 0.05,
		RadiusZ = 0.075,
		ThumbAngle = 170,
		ThumbLift = 0.05,
		PalmAngle = 20,
		TriggerFinger = true,
		ForearmFollow = 0.05, -- the sloped grip would point the arm up into view when aiming
		ForearmDirection = Vector3.new(0.3, -1.05, 1), -- drop the arm steeply so it leaves the screen sooner
	})
	addGrip(body, "LeftGrip", underhandFrame(Vector3.new(0, -0.06, -0.85)), {
		RadiusX = 0.078,
		RadiusZ = 0.078,
		ThumbAngle = 95,
		ThumbLift = 0.18,
		PalmAngle = 30,
	})
	return body
end

---------------------------------------------------------------------------------------------
-- Sniper: bolt action with a heavy barrel, muzzle brake, scope and folded bipod
---------------------------------------------------------------------------------------------
local SCOPE_Y = 0.175 -- height of the scope's center line above the bore

local function buildSniper(gun: Model, color: Color3): Part
	local stock = GunModels.Finish(color:Lerp(Color3.fromRGB(110, 118, 92), 0.25), Enum.Material.Plastic)
	local scope = fixed(GunModels.Finish(Color3.fromRGB(27, 28, 30), Enum.Material.SmoothPlastic)) -- (skins leave sights alone)
	local turretCap = fixed(GunModels.Finish(Color3.fromRGB(58, 60, 64), Enum.Material.Metal))

	-- Round action (the Body is the core inside it) with a one-piece scope rail
	local body = box(gun, "Body", Vector3.new(0.08, 0.07, 0.72), CFrame.new(), STEEL)
	tube(gun, "Action", 0.72, 0.11, Vector3.zero, STEEL)
	tube(gun, "ActionRing", 0.04, 0.12, Vector3.new(0, 0, -0.36), STEEL)
	box(gun, "EjectionPort", Vector3.new(0.005, 0.045, 0.2), CFrame.new(0.054, 0.012, -0.08), HOLE)
	box(gun, "ScopeRail", Vector3.new(0.07, 0.03, 0.74), CFrame.new(0, 0.065, -0.01), STEEL)

	-- Bolt: shroud at the back, handle with a big knob on the right
	tube(gun, "BoltShroud", 0.1, 0.085, Vector3.new(0, 0, 0.41), STEEL)
	tube(gun, "CockingPiece", 0.045, 0.05, Vector3.new(0, -0.005, 0.4825), DARK_STEEL)
	GunModels.Rod(gun, "BoltHandle", Vector3.new(0.045, 0, 0.3), Vector3.new(0.165, -0.065, 0.33), 0.03, STEEL)
	GunModels.Ball(gun, "BoltKnob", 0.065, Vector3.new(0.18, -0.073, 0.335), POLYMER)

	-- Heavy fluted barrel and muzzle brake
	tube(gun, "Barrel", 0.9, 0.088, Vector3.new(0, 0, -0.81), STEEL)
	tube(gun, "BarrelTaper", 0.65, 0.072, Vector3.new(0, 0, -1.585), STEEL)
	for i = -1, 1 do
		local flute = CFrame.new(0, 0, -0.85) * CFrame.Angles(0, 0, math.rad(i * 45)) * CFrame.new(0, 0.043, 0)
		box(gun, "BarrelFlute", Vector3.new(0.012, 0.006, 0.7), flute, DARK_STEEL)
	end
	tube(gun, "MuzzleBrake", 0.19, 0.1, Vector3.new(0, 0, -2.0), STEEL)
	for _, side in { -1, 1 } do
		for i = 0, 1 do
			box(gun, "BrakePort", Vector3.new(0.006, 0.05, 0.035), CFrame.new(side * 0.0505, 0, -1.96 - i * 0.08), HOLE)
		end
	end
	tube(gun, "Bore", 0.006, 0.035, Vector3.new(0, 0, -2.098), HOLE)
	attach(body, "Muzzle", CFrame.new(0, 0, -2.1))

	-- Composite stock: forend, action bedding, pistol grip, skeleton butt with a cheek riser
	box(gun, "Forend", Vector3.new(0.13, 0.1, 0.86), CFrame.new(0, -0.1, -0.8), stock)
	tube(gun, "ForendBelly", 0.86, 0.13, Vector3.new(0, -0.11, -0.8), stock)
	box(gun, "StockAction", Vector3.new(0.135, 0.15, 0.78), CFrame.new(0, -0.11, 0), stock)
	local gripTop = CFrame.new(0, -0.185, 0.29) * CFrame.Angles(math.rad(-12), 0, 0)
	box(gun, "Grip", Vector3.new(0.105, 0.36, 0.17), gripTop * CFrame.new(0, -0.17, 0), stock)
	box(gun, "GripCap", Vector3.new(0.11, 0.02, 0.175), gripTop * CFrame.new(0, -0.35, 0), RUBBER)
	box(gun, "StockTop", Vector3.new(0.12, 0.1, 0.86), CFrame.new(0, -0.085, 0.82), stock)
	box(gun, "CheekRiser", Vector3.new(0.11, 0.055, 0.4), CFrame.new(0, 0.0225, 0.93), stock)
	for i = 0, 1 do
		post(gun, "RiserPost", 0.03, 0.022, Vector3.new(0, -0.02, 0.8 + i * 0.26), STEEL)
	end
	beam(gun, "StockToe", Vector3.new(0, -0.4, 0.43), Vector3.new(0, -0.35, 1.22), 0.11, 0.12, stock)
	box(gun, "StockButt", Vector3.new(0.12, 0.43, 0.06), CFrame.new(0, -0.205, 1.22), stock)
	box(gun, "RecoilPad", Vector3.new(0.125, 0.45, 0.04), CFrame.new(0, -0.205, 1.27), RUBBER)

	-- Detachable box magazine, trigger guard and trigger
	box(gun, "Magazine", Vector3.new(0.075, 0.12, 0.2), CFrame.new(0, -0.23, -0.12), STEEL)
	box(gun, "MagBase", Vector3.new(0.08, 0.015, 0.21), CFrame.new(0, -0.2925, -0.12), POLYMER_DARK)
	box(gun, "MagRelease", Vector3.new(0.03, 0.02, 0.03), CFrame.new(0, -0.195, 0), STEEL)
	box(gun, "TriggerGuardFront", Vector3.new(0.03, 0.07, 0.025), CFrame.new(0, -0.22, 0.04), STEEL)
	box(gun, "TriggerGuard", Vector3.new(0.03, 0.02, 0.18), CFrame.new(0, -0.255, 0.13), STEEL)
	local triggerCFrame = CFrame.new(0, -0.21, 0.12) * CFrame.Angles(math.rad(12), 0, 0)
	box(gun, "Trigger", Vector3.new(0.02, 0.055, 0.022), triggerCFrame, STEEL)
	attach(body, "Trigger", CFrame.new(0, -0.226, 0.108))

	-- Folded bipod under the front of the forend
	box(gun, "BipodMount", Vector3.new(0.07, 0.035, 0.08), CFrame.new(0, -0.19, -1.12), STEEL)
	for _, side in { -1, 1 } do
		tube(gun, "BipodLeg", 0.48, 0.032, Vector3.new(side * 0.032, -0.215, -1.38), STEEL)
		box(gun, "BipodFoot", Vector3.new(0.045, 0.03, 0.035), CFrame.new(side * 0.032, -0.215, -1.635), RUBBER)
	end

	-- Scope: rings, main tube, turrets, objective bell and eyepiece with glass lenses
	for _, z in { 0.2, -0.28 } do
		box(gun, "ScopeRingBase", Vector3.new(0.07, 0.045, 0.05), CFrame.new(0, 0.1, z), STEEL)
		tube(gun, "ScopeRing", 0.05, 0.122, Vector3.new(0, SCOPE_Y, z), STEEL)
	end
	tube(gun, "ScopeTube", 0.8, 0.1, Vector3.new(0, SCOPE_Y, -0.02), scope)
	box(gun, "TurretSaddle", Vector3.new(0.115, 0.115, 0.13), CFrame.new(0, SCOPE_Y, -0.04), scope)
	post(gun, "ElevationTurret", 0.065, 0.085, Vector3.new(0, SCOPE_Y + 0.09, -0.04), scope)
	post(gun, "ElevationCap", 0.012, 0.07, Vector3.new(0, SCOPE_Y + 0.1285, -0.04), turretCap)
	pin(gun, "WindageTurret", 0.065, 0.085, Vector3.new(0.09, SCOPE_Y, -0.04), scope)
	pin(gun, "WindageCap", 0.012, 0.07, Vector3.new(0.1285, SCOPE_Y, -0.04), turretCap)
	pin(gun, "ParallaxKnob", 0.05, 0.078, Vector3.new(-0.0825, SCOPE_Y, -0.04), scope)
	tube(gun, "ObjectiveTaper", 0.07, 0.125, Vector3.new(0, SCOPE_Y, -0.455), scope)
	tube(gun, "ObjectiveBell", 0.15, 0.162, Vector3.new(0, SCOPE_Y, -0.565), scope)
	tube(gun, "ObjectiveLip", 0.02, 0.168, Vector3.new(0, SCOPE_Y, -0.65), scope)
	tube(gun, "ObjectiveLens", 0.004, 0.148, Vector3.new(0, SCOPE_Y, -0.662), SCOPE_GLASS)
	tube(gun, "PowerRing", 0.075, 0.115, Vector3.new(0, SCOPE_Y, 0.4175), scope)
	box(gun, "PowerLever", Vector3.new(0.014, 0.04, 0.02), CFrame.new(0.06, SCOPE_Y + 0.03, 0.42), scope)
	tube(gun, "Eyepiece", 0.12, 0.134, Vector3.new(0, SCOPE_Y, 0.515), scope)
	tube(gun, "EyeCup", 0.03, 0.138, Vector3.new(0, SCOPE_Y, 0.59), RUBBER)
	tube(gun, "OcularLens", 0.004, 0.105, Vector3.new(0, SCOPE_Y, 0.607), SCOPE_GLASS)
	addSight(body, Vector3.new(0, SCOPE_Y, 0.61), 0.42)

	-- Hands: right on the pistol grip, left under the forend
	addGrip(body, "RightGrip", gripTop * CFrame.new(0, -0.16, 0), {
		RadiusX = 0.052,
		RadiusZ = 0.085,
		ThumbAngle = 190,
		ThumbLift = 0.04,
		PalmAngle = 25,
		TriggerFinger = true,
	})
	addGrip(body, "LeftGrip", underhandFrame(Vector3.new(0, -0.11, -0.86)), {
		RadiusX = 0.065,
		RadiusZ = 0.068,
		ThumbAngle = 95,
		ThumbLift = 0.18,
		PalmAngle = 30,
	})
	return body
end

---------------------------------------------------------------------------------------------
-- Revolver: stainless double action with a full underlug, fluted cylinder and wood grip
---------------------------------------------------------------------------------------------
local function buildRevolver(gun: Model, color: Color3): Part
	local stainless = GunModels.Finish(color, Enum.Material.Metal, nil, 0.05)
	local cylinderLook = GunModels.Finish(color:Lerp(Color3.new(1, 1, 1), 0.06), Enum.Material.Metal, nil, 0.05)
	local flute = GunModels.Finish(color:Lerp(Color3.new(0, 0, 0), 0.35), Enum.Material.Metal)
	local hardened = GunModels.Finish(Color3.fromRGB(70, 70, 74), Enum.Material.Metal) -- hammer, trigger, sight
	local wood = GunModels.Finish(Color3.fromRGB(112, 68, 38), Enum.Material.Wood)
	local insert = fixed(GunModels.Finish(Color3.fromRGB(230, 60, 40), Enum.Material.SmoothPlastic))
	local bore = 0.0325 -- height of the barrel's center line
	local axis = bore - 0.06 -- the cylinder turns around this line, its top chamber lines up with the barrel

	-- Frame: recoil shield (the Body), top strap over the cylinder, front, bottom and rear
	local body = box(gun, "Body", Vector3.new(0.11, 0.245, 0.07), CFrame.new(), stainless)
	box(gun, "TopStrap", Vector3.new(0.075, 0.045, 0.27), CFrame.new(0, 0.1, -0.135), stainless)
	box(gun, "FrameFront", Vector3.new(0.1, 0.22, 0.04), CFrame.new(0, -0.0175, -0.255), stainless)
	box(gun, "FrameBottom", Vector3.new(0.1, 0.045, 0.31), CFrame.new(0, -0.145, -0.12), stainless)
	box(gun, "FrameRear", Vector3.new(0.1, 0.16, 0.075), CFrame.new(0, -0.065, 0.0725), stainless)
	box(gun, "CylinderLatch", Vector3.new(0.012, 0.03, 0.045), CFrame.new(-0.056, -0.02, 0.06), stainless)

	-- Cylinder with flutes between the chambers
	tube(gun, "Cylinder", 0.2, 0.2, Vector3.new(0, axis, -0.135), cylinderLook)
	for i = 0, 5 do
		local spin = CFrame.Angles(0, 0, math.rad(30 + i * 60))
		local cframe = CFrame.new(0, axis, -0.165) * spin * CFrame.new(0, 0.097, 0)
		box(gun, "CylinderFlute", Vector3.new(0.03, 0.012, 0.12), cframe, flute)
	end

	-- Barrel with a full-length underlug and a top rib carrying the front sight
	tube(gun, "Barrel", 0.445, 0.082, Vector3.new(0, bore, -0.4975), stainless)
	box(gun, "Rib", Vector3.new(0.045, 0.035, 0.445), CFrame.new(0, 0.0875, -0.4975), stainless)
	box(gun, "Underlug", Vector3.new(0.06, 0.085, 0.385), CFrame.new(0, -0.045, -0.4675), stainless)
	pin(gun, "UnderlugNose", 0.06, 0.085, Vector3.new(0, -0.045, -0.66), stainless)
	box(gun, "FrontSight", Vector3.new(0.018, 0.06, 0.07), CFrame.new(0, 0.135, -0.67), stainless)
	box(gun, "FrontSightInsert", Vector3.new(0.02, 0.022, 0.012), CFrame.new(0, 0.148, -0.638), insert)
	tube(gun, "Bore", 0.006, 0.04, Vector3.new(0, bore, -0.723), HOLE)
	attach(body, "Muzzle", CFrame.new(0, bore, -0.726))

	-- Rear sight: two blades with the notch you aim through between them. The front sight's
	-- top lines up level with them.
	box(gun, "RearSightBase", Vector3.new(0.06, 0.0175, 0.08), CFrame.new(0, 0.13125, -0.02), hardened)
	for _, side in { -1, 1 } do
		box(gun, "RearSightBlade", Vector3.new(0.024, 0.027, 0.025), CFrame.new(side * 0.021, 0.1535, -0.01), hardened)
	end
	-- Held out at arm's length when aimed, closer in at the hip
	addSight(body, Vector3.new(0, 0.165, -0.01), 1.15, Vector3.new(0.45, -0.16, 0.25))

	-- Hammer (cocked spur), trigger guard and trigger
	box(gun, "Hammer", Vector3.new(0.032, 0.09, 0.04), CFrame.new(0, 0.065, 0.075), hardened)
	local spur = CFrame.new(0, 0.115, 0.1) * CFrame.Angles(math.rad(-20), 0, 0)
	box(gun, "HammerSpur", Vector3.new(0.045, 0.018, 0.065), spur, hardened)
	box(gun, "TriggerGuardFront", Vector3.new(0.025, 0.1, 0.02), CFrame.new(0, -0.2175, -0.11), stainless)
	box(gun, "TriggerGuard", Vector3.new(0.025, 0.02, 0.19), CFrame.new(0, -0.2575, -0.025), stainless)
	local triggerCFrame = CFrame.new(0, -0.205, -0.02) * CFrame.Angles(math.rad(10), 0, 0)
	box(gun, "Trigger", Vector3.new(0.02, 0.07, 0.025), triggerCFrame, hardened)
	attach(body, "Trigger", CFrame.new(0, -0.222, -0.035))

	-- Wood grip (rounded front) with a steel backstrap and a brass medallion
	local gripTop = CFrame.new(0, -0.145, 0.085) * CFrame.Angles(math.rad(-22), 0, 0)
	box(gun, "Grip", Vector3.new(0.12, 0.38, 0.14), gripTop * CFrame.new(0, -0.19, 0), wood)
	local gripFront = gripTop * CFrame.new(0, -0.19, -0.07) * ALONG_Y
	GunModels.MakePart(gun, "GripFront", Vector3.new(0.38, 0.12, 0.12), gripFront, wood, Enum.PartType.Cylinder)
	local backstrap = gripTop * CFrame.new(0, -0.18, 0.07) * ALONG_Y
	GunModels.MakePart(gun, "Backstrap", Vector3.new(0.36, 0.07, 0.07), backstrap, stainless, Enum.PartType.Cylinder)
	local medallion = gripTop * CFrame.new(-0.061, -0.07, 0)
	GunModels.MakePart(gun, "Medallion", Vector3.new(0.004, 0.035, 0.035), medallion, BRASS, Enum.PartType.Cylinder)

	-- Two-handed grip: the left hand wraps over the right hand's fingers, thumbs forward
	addGrip(body, "RightGrip", gripTop * CFrame.new(0, -0.165, 0), {
		RadiusX = 0.06,
		RadiusZ = 0.1,
		ThumbAngle = 200,
		ThumbLift = 0.05,
		PalmAngle = 20,
		TriggerFinger = true,
	})
	addGrip(body, "LeftGrip", gripTop * CFrame.new(0, -0.24, 0), {
		RadiusX = 0.125,
		RadiusZ = 0.17,
		ThumbAngle = -50, -- negative: the thumb stays on the palm side and points forward
		ThumbLift = 0.12,
		PalmAngle = 20,
	})
	return body
end

---------------------------------------------------------------------------------------------
-- LMG: M249 style with a box of belted ammo, a hinged feed cover (the reflex sight rides on
-- it), heat shield, side-folded carry handle and a folded bipod
---------------------------------------------------------------------------------------------
local function buildLmg(gun: Model, color: Color3): Part
	local furniture = GunModels.Finish(color, Enum.Material.Plastic)
	local furnitureDark = GunModels.Finish(color:Lerp(Color3.new(0, 0, 0), 0.25), Enum.Material.Plastic)
	local optic = fixed(GunModels.Finish(Color3.fromRGB(40, 41, 44), Enum.Material.SmoothPlastic)) -- (skins leave sights alone)

	-- Receiver (the Body): a tall stamped box, belt port on the left, ejection port underneath
	local body = box(gun, "Body", Vector3.new(0.13, 0.17, 0.8), CFrame.new(), STEEL)
	box(gun, "FeedPort", Vector3.new(0.004, 0.05, 0.14), CFrame.new(-0.0655, 0.035, -0.12), HOLE)
	box(gun, "EjectionPort", Vector3.new(0.09, 0.004, 0.16), CFrame.new(0.01, -0.0855, -0.02), HOLE)
	for i = 0, 3 do
		pin(gun, "Rivet", 0.134, 0.016, Vector3.new(0, -0.05, -0.3 + i * 0.2), DARK_STEEL)
	end
	-- Charging handle in its slot on the right
	box(gun, "ChargingSlot", Vector3.new(0.004, 0.015, 0.3), CFrame.new(0.0655, 0.02, -0.2), HOLE)
	box(gun, "ChargingHandle", Vector3.new(0.05, 0.025, 0.04), CFrame.new(0.09, 0.02, -0.28), STEEL)
	box(gun, "ChargingLatch", Vector3.new(0.025, 0.05, 0.05), CFrame.new(0.125, 0.02, -0.28), POLYMER)

	-- Feed cover, hinged at its front: everything named FeedCover... swings up with it on reloads
	box(gun, "FeedCover", Vector3.new(0.136, 0.045, 0.44), CFrame.new(0, 0.1075, -0.06), STEEL)
	box(gun, "FeedCoverLatch", Vector3.new(0.07, 0.035, 0.04), CFrame.new(0, 0.105, 0.18), DARK_STEEL)
	rail(gun, "FeedCoverRail", -0.26, 0.1, 0.13, DARK_STEEL)
	-- Reflex sight: base, two posts and a hood framing a glass window with a red dot
	local dotY = 0.225
	box(gun, "FeedCoverSightBase", Vector3.new(0.09, 0.03, 0.16), CFrame.new(0, 0.17, -0.06), optic)
	for _, side in { -1, 1 } do
		box(gun, "FeedCoverSightPost", Vector3.new(0.016, 0.09, 0.04), CFrame.new(side * 0.05, dotY, -0.09), optic)
	end
	box(gun, "FeedCoverSightHood", Vector3.new(0.116, 0.016, 0.05), CFrame.new(0, dotY + 0.053, -0.09), optic)
	box(gun, "FeedCoverSightGlass", Vector3.new(0.084, 0.09, 0.004), CFrame.new(0, dotY, -0.1), LENS)
	GunModels.Ball(gun, "FeedCoverSightDot", 0.008, Vector3.new(0, dotY, -0.095), RED_DOT)
	addSight(body, Vector3.new(0, dotY, -0.09), 0.78)

	-- Polymer handguard under the barrel (the left hand holds it)
	box(gun, "Handguard", Vector3.new(0.15, 0.12, 0.46), CFrame.new(0, -0.05, -0.66), furniture)
	tube(gun, "HandguardBelly", 0.46, 0.15, Vector3.new(0, -0.07, -0.66), furniture)
	for _, side in { -1, 1 } do
		for i = 0, 1 do
			box(gun, "HandguardGroove", Vector3.new(0.004, 0.012, 0.34), CFrame.new(side * 0.076, -0.03 - i * 0.04, -0.66), HOLE)
		end
	end

	-- Barrel under a vented heat shield, gas tube and block, front sight, flash hider
	tube(gun, "BarrelExtension", 0.1, 0.1, Vector3.new(0, 0.02, -0.45), STEEL)
	tube(gun, "Barrel", 1.1, 0.07, Vector3.new(0, 0.02, -1.05), STEEL)
	box(gun, "HeatShield", Vector3.new(0.09, 0.025, 0.5), CFrame.new(0, 0.07, -0.72), DARK_STEEL)
	for i = 0, 3 do
		box(gun, "HeatShieldVent", Vector3.new(0.06, 0.004, 0.04), CFrame.new(0, 0.0835, -0.55 - i * 0.11), HOLE)
	end
	tube(gun, "GasTube", 0.75, 0.04, Vector3.new(0, -0.055, -0.95), STEEL)
	box(gun, "GasBlock", Vector3.new(0.06, 0.12, 0.09), CFrame.new(0, -0.02, -1.33), STEEL)
	box(gun, "FrontSight", Vector3.new(0.025, 0.08, 0.03), CFrame.new(0, 0.085, -1.52), STEEL)
	tube(gun, "FlashHider", 0.16, 0.085, Vector3.new(0, 0.02, -1.68), STEEL)
	for i = -1, 1 do
		local slot = CFrame.new(0, 0.02, -1.7) * CFrame.Angles(0, 0, math.rad(i * 60)) * CFrame.new(0, 0.04, 0)
		box(gun, "FlashHiderSlot", Vector3.new(0.014, 0.006, 0.09), slot, HOLE)
	end
	tube(gun, "Bore", 0.006, 0.034, Vector3.new(0, 0.02, -1.763), HOLE)
	attach(body, "Muzzle", CFrame.new(0, 0.02, -1.767))

	-- Carry handle clamped to the barrel, folded down to the left (out of the sight picture)
	box(gun, "HandleClamp", Vector3.new(0.09, 0.05, 0.06), CFrame.new(0, 0.06, -1.0), STEEL)
	GunModels.Rod(gun, "CarryHandleArm", Vector3.new(-0.03, 0.06, -1.0), Vector3.new(-0.13, 0.02, -1.0), 0.03, STEEL)
	tube(gun, "CarryHandle", 0.26, 0.05, Vector3.new(-0.14, 0.02, -1.0), furniture)

	-- Bipod folded back under the barrel
	box(gun, "BipodMount", Vector3.new(0.07, 0.04, 0.07), CFrame.new(0, -0.1, -1.33), STEEL)
	for _, side in { -1, 1 } do
		tube(gun, "BipodLeg", 0.42, 0.03, Vector3.new(side * 0.03, -0.12, -1.1), STEEL)
		box(gun, "BipodFoot", Vector3.new(0.04, 0.03, 0.035), CFrame.new(side * 0.03, -0.12, -0.88), RUBBER)
	end

	-- Ammo box (the Magazine) clipped under the receiver; the belt (Mag1..4) climbs into the
	-- left side, so it leaves with the box on reloads
	box(gun, "Magwell", Vector3.new(0.14, 0.03, 0.22), CFrame.new(0, -0.1, -0.12), STEEL)
	box(gun, "Magazine", Vector3.new(0.22, 0.3, 0.3), CFrame.new(-0.03, -0.265, -0.12), furniture)
	box(gun, "MagBase", Vector3.new(0.228, 0.025, 0.308), CFrame.new(-0.03, -0.425, -0.12), furnitureDark)
	for i = 1, 4 do
		local at = Vector3.new(-0.13, -0.12, -0.12):Lerp(Vector3.new(-0.075, 0.03, -0.12), (i - 1) / 3)
		box(gun, `Mag{i}`, Vector3.new(0.035, 0.03, 0.15), CFrame.new(at) * CFrame.Angles(0, 0, math.rad(-50)), BRASS)
	end

	-- Trigger housing, trigger guard, trigger and pistol grip
	box(gun, "TriggerHousing", Vector3.new(0.11, 0.07, 0.36), CFrame.new(0, -0.115, 0.2), furniture)
	box(gun, "TriggerGuardFront", Vector3.new(0.03, 0.08, 0.025), CFrame.new(0, -0.19, 0.07), STEEL)
	box(gun, "TriggerGuard", Vector3.new(0.03, 0.02, 0.17), CFrame.new(0, -0.235, 0.15), STEEL)
	local triggerCFrame = CFrame.new(0, -0.185, 0.155) * CFrame.Angles(math.rad(12), 0, 0)
	box(gun, "Trigger", Vector3.new(0.02, 0.065, 0.022), triggerCFrame, STEEL)
	attach(body, "Trigger", CFrame.new(0, -0.202, 0.142))
	local gripTop = CFrame.new(0, -0.15, 0.29) * CFrame.Angles(math.rad(-18), 0, 0)
	box(gun, "Grip", Vector3.new(0.1, 0.35, 0.16), gripTop * CFrame.new(0, -0.175, 0), furniture)
	box(gun, "GripBase", Vector3.new(0.104, 0.02, 0.165), gripTop * CFrame.new(0, -0.35, 0), furnitureDark)

	-- Fixed polymer stock with a sloped toe and a thick butt pad
	box(gun, "StockAdapter", Vector3.new(0.11, 0.12, 0.1), CFrame.new(0, -0.01, 0.45), STEEL)
	box(gun, "Stock", Vector3.new(0.12, 0.15, 0.5), CFrame.new(0, -0.01, 0.75), furniture)
	beam(gun, "StockToe", Vector3.new(0, -0.08, 0.52), Vector3.new(0, -0.26, 1.0), 0.11, 0.13, furniture)
	box(gun, "ButtPad", Vector3.new(0.125, 0.36, 0.04), CFrame.new(0, -0.11, 1.02), RUBBER)

	-- Hands: right on the pistol grip, left under the handguard
	addGrip(body, "RightGrip", gripTop * CFrame.new(0, -0.165, 0), {
		RadiusX = 0.05,
		RadiusZ = 0.08,
		ThumbAngle = 190,
		ThumbLift = 0.04,
		PalmAngle = 25,
		TriggerFinger = true,
	})
	addGrip(body, "LeftGrip", underhandFrame(Vector3.new(0, -0.07, -0.68)), {
		RadiusX = 0.078,
		RadiusZ = 0.078,
		ThumbAngle = 95,
		ThumbLift = 0.18,
		PalmAngle = 30,
	})
	return body
end

---------------------------------------------------------------------------------------------
-- Marksman: SR-25 style semi-auto with a long free-float handguard, straight 15-round mag,
-- precision stock and a 4x prism scope (a hollow housing you look straight through)
---------------------------------------------------------------------------------------------
local PRISM_Y = 0.26 -- height of the prism scope's sight line above the bore (high enough that the rail stays out of view)

local function buildMarksman(gun: Model, color: Color3): Part
	local anodized = GunModels.Finish(Color3.fromRGB(42, 43, 46), Enum.Material.Metal)
	local furniture = GunModels.Finish(color, Enum.Material.Plastic)
	local furnitureDark = GunModels.Finish(color:Lerp(Color3.new(0, 0, 0), 0.2), Enum.Material.Plastic)
	local housing = fixed(GunModels.Finish(Color3.fromRGB(34, 35, 38), Enum.Material.SmoothPlastic)) -- (skins leave sights alone)
	local fiber = GunModels.Finish(Color3.fromRGB(255, 70, 40), Enum.Material.Neon)

	-- Upper receiver (the Body): full-length top rail, ejection port, forward assist, charging handle
	local body = box(gun, "Body", Vector3.new(0.1, 0.135, 0.76), CFrame.new(), anodized)
	rail(gun, "UpperRail", -0.38, 0.38, 0.0675, anodized)
	box(gun, "EjectionPort", Vector3.new(0.006, 0.05, 0.22), CFrame.new(0.0505, 0.002, -0.03), HOLE)
	GunModels.Rod(gun, "ForwardAssist", Vector3.new(0.04, 0.02, 0.21), Vector3.new(0.09, 0.035, 0.31), 0.042, anodized)
	box(gun, "ChargingHandle", Vector3.new(0.16, 0.022, 0.035), CFrame.new(0, 0.045, 0.398), anodized)
	box(gun, "ChargingLatch", Vector3.new(0.035, 0.024, 0.05), CFrame.new(-0.085, 0.045, 0.392), anodized)

	-- Lower receiver, mag well, straight steel magazine, bolt catch (the empty reload slaps it)
	box(gun, "Lower", Vector3.new(0.11, 0.115, 0.64), CFrame.new(0, -0.123, 0.03), anodized)
	box(gun, "Magwell", Vector3.new(0.12, 0.08, 0.28), CFrame.new(0, -0.205, -0.14), anodized)
	magazine(gun, Vector3.new(0, -0.2, -0.14), 0.085, 0.24, { { 0.28, 3 } }, STEEL, POLYMER_DARK)
	box(gun, "BoltCatch", Vector3.new(0.012, 0.045, 0.05), CFrame.new(-0.06, -0.108, -0.02), anodized)
	box(gun, "Selector", Vector3.new(0.012, 0.022, 0.065), CFrame.new(-0.061, -0.1, 0.22), STEEL)
	pin(gun, "FrontPin", 0.116, 0.024, Vector3.new(0, -0.09, -0.26), STEEL)
	pin(gun, "RearPin", 0.116, 0.024, Vector3.new(0, -0.09, 0.31), STEEL)

	-- Pistol grip, trigger guard and trigger
	local gripTop = CFrame.new(0, -0.18, 0.225) * CFrame.Angles(math.rad(-18), 0, 0)
	box(gun, "Grip", Vector3.new(0.1, 0.36, 0.165), gripTop * CFrame.new(0, -0.18, 0), furniture)
	box(gun, "GripBase", Vector3.new(0.104, 0.02, 0.17), gripTop * CFrame.new(0, -0.355, 0), furnitureDark)
	box(gun, "TriggerGuard", Vector3.new(0.03, 0.02, 0.16), CFrame.new(0, -0.26, 0.085), anodized)
	box(gun, "TriggerGuardFront", Vector3.new(0.03, 0.08, 0.025), CFrame.new(0, -0.22, 0.015), anodized)
	local triggerCFrame = CFrame.new(0, -0.21, 0.09) * CFrame.Angles(math.rad(12), 0, 0)
	box(gun, "Trigger", Vector3.new(0.02, 0.065, 0.022), triggerCFrame, STEEL)
	attach(body, "Trigger", CFrame.new(0, -0.227, 0.077))

	-- Precision stock: buffer tube, adjustable cheek riser, sloped toe, thick recoil pad
	tube(gun, "BufferTube", 0.56, 0.105, Vector3.new(0, -0.01, 0.65), anodized)
	tube(gun, "CastleNut", 0.03, 0.115, Vector3.new(0, -0.01, 0.395), STEEL)
	box(gun, "Stock", Vector3.new(0.13, 0.19, 0.5), CFrame.new(0, -0.03, 0.86), furniture)
	box(gun, "CheekRiser", Vector3.new(0.11, 0.05, 0.3), CFrame.new(0, 0.09, 0.86), furniture)
	for i = 0, 1 do
		post(gun, "RiserPost", 0.04, 0.02, Vector3.new(0, 0.05, 0.76 + i * 0.2), STEEL)
	end
	beam(gun, "StockToe", Vector3.new(0, -0.1, 0.66), Vector3.new(0, -0.27, 1.11), 0.12, 0.15, furniture)
	box(gun, "ButtPad", Vector3.new(0.135, 0.42, 0.045), CFrame.new(0, -0.11, 1.135), RUBBER)

	-- Long free-float handguard with a top rail and M-LOK slots
	tube(gun, "BarrelNut", 0.03, 0.115, Vector3.new(0, -0.005, -0.39), STEEL)
	tube(gun, "Handguard", 1.0, 0.155, Vector3.new(0, -0.01, -0.9), anodized)
	tube(gun, "HandguardCap", 0.03, 0.16, Vector3.new(0, -0.01, -1.41), anodized)
	box(gun, "HandguardSpine", Vector3.new(0.06, 0.02, 1.0), CFrame.new(0, 0.06, -0.9), anodized)
	rail(gun, "HandguardRail", -1.4, -0.4, 0.0675, anodized)
	for _, side in { -1, 1 } do
		for i = 0, 3 do
			box(gun, "MLokSlot", Vector3.new(0.006, 0.028, 0.11), CFrame.new(side * 0.076, -0.01, -0.6 - i * 0.22), HOLE)
		end
	end

	-- Barrel and a three-port muzzle brake
	tube(gun, "Barrel", 0.42, 0.066, Vector3.new(0, 0, -1.62), STEEL)
	tube(gun, "MuzzleBrake", 0.17, 0.09, Vector3.new(0, 0, -1.91), STEEL)
	for _, side in { -1, 1 } do
		for i = 0, 2 do
			box(gun, "BrakePort", Vector3.new(0.006, 0.04, 0.03), CFrame.new(side * 0.0455, 0, -1.86 - i * 0.05), HOLE)
		end
	end
	tube(gun, "Bore", 0.006, 0.032, Vector3.new(0, 0, -1.998), HOLE)
	attach(body, "Muzzle", CFrame.new(0, 0, -2.0))

	-- Prism scope: a mount, then walls, top and bottom around an open window you look through,
	-- a bigger frame at the front, a rubber eyepiece, two clear lenses and a red chevron
	local length, back = 0.26, 0.13
	local front = back - length
	box(gun, "ScopeMount", Vector3.new(0.08, 0.1, 0.18), CFrame.new(0, 0.145, 0.02), housing)
	for _, side in { -1, 1 } do
		box(gun, "ScopeWall", Vector3.new(0.022, 0.13, length), CFrame.new(side * 0.046, PRISM_Y, back - length / 2), housing)
		box(gun, "ObjectiveSide", Vector3.new(0.025, 0.15, 0.05), CFrame.new(side * 0.0525, PRISM_Y, front - 0.02), housing)
		box(gun, "EyepieceSide", Vector3.new(0.02, 0.09, 0.03), CFrame.new(side * 0.04, PRISM_Y, back + 0.015), RUBBER)
	end
	box(gun, "ScopeTop", Vector3.new(0.114, 0.025, length), CFrame.new(0, PRISM_Y + 0.0525, back - length / 2), housing)
	box(gun, "ScopeBottom", Vector3.new(0.114, 0.03, length), CFrame.new(0, PRISM_Y - 0.05, back - length / 2), housing)
	box(gun, "ObjectiveTop", Vector3.new(0.13, 0.03, 0.05), CFrame.new(0, PRISM_Y + 0.06, front - 0.02), housing)
	box(gun, "ObjectiveBottom", Vector3.new(0.13, 0.03, 0.05), CFrame.new(0, PRISM_Y - 0.06, front - 0.02), housing)
	box(gun, "EyepieceTop", Vector3.new(0.1, 0.02, 0.03), CFrame.new(0, PRISM_Y + 0.045, back + 0.015), RUBBER)
	box(gun, "EyepieceBottom", Vector3.new(0.1, 0.02, 0.03), CFrame.new(0, PRISM_Y - 0.045, back + 0.015), RUBBER)
	box(gun, "ObjectiveLens", Vector3.new(0.08, 0.09, 0.004), CFrame.new(0, PRISM_Y, front - 0.03), LENS)
	box(gun, "OcularLens", Vector3.new(0.06, 0.07, 0.004), CFrame.new(0, PRISM_Y, back), LENS)
	-- Red chevron (its tip is the aim point) over a thin black drop line
	local chevron = CFrame.new(0, PRISM_Y, front + 0.03)
	for _, side in { -1, 1 } do
		box(gun, "ReticleChevron", Vector3.new(0.0022, 0.01, 0.002), chevron * CFrame.Angles(0, 0, math.rad(side * 40)) * CFrame.new(0, -0.005, 0), RED_DOT)
	end
	box(gun, "ReticleStadia", Vector3.new(0.0012, 0.02, 0.0012), chevron * CFrame.new(0, -0.022, 0), HOLE)
	-- Fiber-optic strip on top (lights the reticle) and the adjustment turrets
	box(gun, "FiberOptic", Vector3.new(0.014, 0.01, 0.16), CFrame.new(0, PRISM_Y + 0.07, -0.04), fiber)
	post(gun, "ElevationTurret", 0.03, 0.05, Vector3.new(0, PRISM_Y + 0.075, 0.08), housing)
	pin(gun, "WindageTurret", 0.03, 0.05, Vector3.new(0.072, PRISM_Y, 0.02), housing)
	addSight(body, Vector3.new(0, PRISM_Y, back + 0.005), 0.42)

	-- Hands: right on the pistol grip, left under the handguard
	addGrip(body, "RightGrip", gripTop * CFrame.new(0, -0.17, 0), {
		RadiusX = 0.05,
		RadiusZ = 0.085,
		ThumbAngle = 190,
		ThumbLift = 0.04,
		PalmAngle = 25,
		TriggerFinger = true,
	})
	addGrip(body, "LeftGrip", underhandFrame(Vector3.new(0, -0.01, -1.02)), {
		RadiusX = 0.078,
		RadiusZ = 0.078,
		ThumbAngle = 95,
		ThumbLift = 0.18,
		PalmAngle = 30,
	})
	return body
end

---------------------------------------------------------------------------------------------
-- Autopistol: Glock 18C style: polymer frame, ported slide with a fire selector, white-dot
-- sights and an extended magazine sticking out of the grip
---------------------------------------------------------------------------------------------
local function buildAutopistol(gun: Model, color: Color3): Part
	local frame = GunModels.Finish(color, Enum.Material.Plastic)
	local frameDark = GunModels.Finish(color:Lerp(Color3.new(0, 0, 0), 0.3), Enum.Material.Plastic)
	local slide = GunModels.Finish(Color3.fromRGB(48, 49, 52), Enum.Material.Metal)
	local dot = fixed(GunModels.Finish(Color3.fromRGB(235, 238, 225), Enum.Material.SmoothPlastic))
	local bore = 0.075 -- height of the barrel's center line

	-- Frame (the Body): the polymer dust cover under the slide, with an accessory rail slot
	local body = box(gun, "Body", Vector3.new(0.085, 0.06, 0.42), CFrame.new(), frame)
	box(gun, "FrameNose", Vector3.new(0.083, 0.05, 0.12), CFrame.new(0, -0.005, -0.27), frame)
	box(gun, "RailSlot", Vector3.new(0.087, 0.01, 0.015), CFrame.new(0, -0.022, -0.26), HOLE)

	-- Slide: everything named Slide... moves with it when it's racked
	box(gun, "Slide", Vector3.new(0.09, 0.1, 0.6), CFrame.new(0, 0.08, -0.06), slide)
	for _, side in { -1, 1 } do
		for i = 0, 4 do
			box(gun, "SlideSerration", Vector3.new(0.004, 0.07, 0.014), CFrame.new(side * 0.0455, 0.085, 0.13 + i * 0.024), HOLE)
		end
	end
	box(gun, "SlideEjectionPort", Vector3.new(0.004, 0.045, 0.13), CFrame.new(0.0455, 0.09, -0.04), HOLE)
	for i = 0, 1 do -- compensator cuts on top
		box(gun, "SlidePort", Vector3.new(0.045, 0.004, 0.022), CFrame.new(0, 0.1305, -0.28 - i * 0.045), HOLE)
	end
	box(gun, "SlideMuzzle", Vector3.new(0.06, 0.06, 0.004), CFrame.new(0, bore, -0.3605), DARK_STEEL)
	tube(gun, "SlideBore", 0.006, 0.032, Vector3.new(0, bore, -0.3625), HOLE)
	attach(body, "Muzzle", CFrame.new(0, bore, -0.365))
	box(gun, "SlideSelector", Vector3.new(0.012, 0.025, 0.03), CFrame.new(-0.0505, 0.07, 0.19), STEEL)

	-- White-dot sights: a post up front, a notch at the back. Aim across the notch onto the post.
	box(gun, "SlideFrontSight", Vector3.new(0.02, 0.03, 0.03), CFrame.new(0, 0.145, -0.33), DARK_STEEL)
	GunModels.Ball(gun, "SlideFrontDot", 0.012, Vector3.new(0, 0.152, -0.3135), dot)
	box(gun, "SlideRearSightBase", Vector3.new(0.07, 0.015, 0.04), CFrame.new(0, 0.1375, 0.21), DARK_STEEL)
	for _, side in { -1, 1 } do
		box(gun, "SlideRearSight", Vector3.new(0.024, 0.02, 0.035), CFrame.new(side * 0.022, 0.155, 0.21), DARK_STEEL)
		GunModels.Ball(gun, "SlideRearDot", 0.01, Vector3.new(side * 0.022, 0.155, 0.192), dot)
	end
	-- Held out at arm's length when aimed, closer in at the hip (like the revolver)
	addSight(body, Vector3.new(0, 0.158, 0.23), 1.1, Vector3.new(0.45, -0.17, 0.25))

	-- Square trigger guard and trigger
	box(gun, "TriggerGuardFront", Vector3.new(0.024, 0.085, 0.022), CFrame.new(0, -0.0725, -0.13), frame)
	box(gun, "TriggerGuard", Vector3.new(0.024, 0.02, 0.2), CFrame.new(0, -0.115, -0.03), frame)
	local triggerCFrame = CFrame.new(0, -0.065, -0.03) * CFrame.Angles(math.rad(10), 0, 0)
	box(gun, "Trigger", Vector3.new(0.018, 0.06, 0.02), triggerCFrame, frameDark)
	attach(body, "Trigger", CFrame.new(0, -0.082, -0.045))

	-- Grip with stippled panels and a beavertail
	local gripTop = CFrame.new(0, -0.03, 0.12) * CFrame.Angles(math.rad(-20), 0, 0)
	box(gun, "Grip", Vector3.new(0.085, 0.34, 0.15), gripTop * CFrame.new(0, -0.17, 0), frame)
	box(gun, "GripTexture", Vector3.new(0.088, 0.22, 0.11), gripTop * CFrame.new(0, -0.17, 0.005), frameDark)
	box(gun, "Beavertail", Vector3.new(0.08, 0.03, 0.06), CFrame.new(0, -0.02, 0.21), frame)

	-- Extended magazine: inside the grip and sticking out below it (drops out down the grip)
	box(gun, "Magazine", Vector3.new(0.066, 0.5, 0.12), gripTop * CFrame.new(0, -0.27, 0.005), DARK_STEEL)
	box(gun, "Mag1", Vector3.new(0.072, 0.17, 0.128), gripTop * CFrame.new(0, -0.43, 0.005), frameDark)
	box(gun, "MagBase", Vector3.new(0.078, 0.03, 0.135), gripTop * CFrame.new(0, -0.525, 0.005), POLYMER_DARK)

	-- Two-handed grip: the left hand wraps over the right hand's fingers, thumbs forward
	addGrip(body, "RightGrip", gripTop * CFrame.new(0, -0.15, 0), {
		RadiusX = 0.045,
		RadiusZ = 0.08,
		ThumbAngle = 200,
		ThumbLift = 0.05,
		PalmAngle = 20,
		TriggerFinger = true,
	})
	addGrip(body, "LeftGrip", gripTop * CFrame.new(0, -0.21, 0), {
		RadiusX = 0.11,
		RadiusZ = 0.15,
		ThumbAngle = -50, -- negative: the thumb stays on the palm side and points forward
		ThumbLift = 0.12,
		PalmAngle = 20,
	})
	return body
end

local BUILDERS: { [string]: (Model, Color3) -> Part } = {
	Rifle = buildRifle,
	SMG = buildSmg,
	Shotgun = buildShotgun,
	Sniper = buildSniper,
	Revolver = buildRevolver,
	LMG = buildLmg,
	Marksman = buildMarksman,
	Autopistol = buildAutopistol,
}

-- Builds the named gun (unknown names get the rifle). `finishColor` is the main finish
-- (Weapons Look.Color): receiver, wood, stock or stainless depending on the gun. A `skin`
-- (shared/Skins) repaints it.
function GunModels.Build(weaponName: string, finishColor: Color3?, skin: Skins.Skin?): Model
	local model = Instance.new("Model")
	model.Name = weaponName
	pieceCount = 0 -- (same numbers every build, so a camo skin looks the same everywhere)
	local builder = BUILDERS[weaponName] or buildRifle
	model.PrimaryPart = builder(model, finishColor or Color3.fromRGB(45, 47, 52))
	smoothEdges(model)
	if skin then
		SkinPainter.PaintGun(model, skin)
	end
	return model
end

-- The knife on its own (no hand): the handle is held at the origin, blade pointing forward
-- (-Z), cutting edge down. PrimaryPart "Handle".
function GunModels.BuildKnife(skin: Skins.Skin?): Model
	local model = Instance.new("Model")
	model.Name = "Knife"
	pieceCount = 0
	local handle = GunModels.MakePart(model, "Handle", Vector3.new(0.12, 0.14, 0.5), CFrame.new(0, 0, -0.05), POLYMER_DARK)
	box(model, "Pommel", Vector3.new(0.14, 0.16, 0.05), CFrame.new(0, 0, 0.22), DARK_STEEL)
	box(model, "Guard", Vector3.new(0.3, 0.06, 0.05), CFrame.new(0, 0, -0.32), DARK_STEEL)
	local blade = GunModels.Finish(Color3.fromRGB(170, 172, 178), Enum.Material.Metal)
	box(model, "Blade", Vector3.new(0.04, 0.16, 0.62), CFrame.new(0, 0.01, -0.66), blade)
	-- The sharpened bevel along the bottom, a little brighter
	box(model, "Edge", Vector3.new(0.044, 0.035, 0.62), CFrame.new(0, -0.0525, -0.66), GunModels.Finish(Color3.fromRGB(205, 208, 214), Enum.Material.Metal, nil, 0.1))
	-- Wedge tip: a wedge is tall at its back (+Z) and slopes down to its front, so the spine
	-- drops to the point at the edge
	local tip = Instance.new("WedgePart")
	tip.Name = "Tip"
	tip.Size = Vector3.new(0.04, 0.16, 0.2)
	tip.CFrame = CFrame.new(0, 0.01, -1.07)
	tip.Color = blade.Color
	tip.Material = blade.Material
	tip.Anchored = true
	tip.CanCollide = false
	tip.CanQuery = false
	tip.CanTouch = false
	tip.CastShadow = false
	tip.Parent = model
	model.PrimaryPart = handle
	smoothEdges(model)
	if skin then
		SkinPainter.PaintKnife(model, skin)
	end
	return model
end

return GunModels
