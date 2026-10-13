-- FLIGHT 9 (Flight9) — Boreal Air flight 9, a big wide-body, came down on a snowy mountain
-- plateau and ploughed a scorched gouge through the snow before it broke in three. A military
-- research team has fenced the wreck off and built a recovery site round it: a hangar tent over
-- the nose half, prefab lab modules and stacked container labs, a command trailer, a generator
-- yard, floodlights, and an excavation pit where they dug the cargo hold out of the ice.
-- Four site pairs; the defenders pick one each round (RoundService / SitePicker):
--   Hold:      Cargo hold + Ice vault            Nose:      First class + Cockpit
--   Labs:      Bio lab + Recorder lab (upstairs) Command:   Control room + Server room
--
--   Ground level (north = +z; the checkpoint gate and the road are south, the scar runs west):
--                ┌──────── EXCAVATION PIT (dug down to the hold) ───┐   ┌─ LAB BLOCK ──────────────┐
--      tail  ▓▓  │ ramp ═══▶          drill rig           stairs ▲  │ ▒ │ decon│hall│ sample store ▓ │
--    ◀═scar═╱    ╞══════════════════════════════════════════════════╡   └──────────────────────────┘
--   ▕fin▏ ╱  gap │ ECONOMY (seats)      │ GALLEY ▒▒ (stairs down)   │gap┃ TENT ┃ BUSINESS │ FIRST  │ COCKPIT ▶ nose
--         ╲      ╞══ the mid section ══════════════════════════════╡   ┃      ┃ the forward section   │
--   gen yard     │ gantry stairs ▓▓▓▓▓ ═ gantry over the hull ═     │   ┃ (hangar tent round it)┃     │
--                ├────────────────┬────────────────┐                   ┌──────────┬──────────┬─────┐
--                │ DRILL LAB ▒    │ MEDBAY         │      yard         │ comms    │ CONTROL  │SERV.│
--                └────────────────┴────────────────┘                   └──────────┴──────────┴─────┘
--   x: -56     -40       -22     -16      -6     2    8 14    26      44    56
--   The fuselage lies along x: tail (west, turned off line, walk-in, its fin standing up), the mid
--   section (x -40..2: economy and galley on the main deck, the cargo hold under them), a gap where
--   it broke, and the forward section (x 14..56: business, first class, the cockpit and the nose
--   cone). The torn-off wing and an engine pod lie out in the north field.
--   Lower level (BF): AFT HOLD + CARGO HOLD in the mid section, open on the north side to the
--   excavation pit (ramp down from the west, stairs up at the east end); ICE STORE + ICE VAULT
--   under the drill lab / medbay module, through the hull from the cargo hold.
--   Upper level (F2): the fuselage roofs (gantry stairs from the alley onto the mid section, a
--   bridge across the gap into the tent, roof hatches into first class and the cockpit), the lab
--   block upstairs (BIO LAB, upper hall, RECORDER LAB; outside stairs and inside stairs), the
--   trailer roofs (steel stairs, hatches into the control and server rooms).
--
-- Attackers spawn at the checkpoint road (south), in the north field or at the end of the scar (west).
-- Soft (shoot through, breach, reinforce): the fuselage's aluminium skin, the plywood bulkheads
-- sealing the breaks, cabin dividers, the tent fabric, the prefab module panels, the lab block's
-- upper panels, the cabin floor over the hold and the lab block's upper floor. Hard: the container
-- steel downstairs, concrete and ice down in the dig, the armoured cockpit bulkhead and the nose.
-- Outside doors and windows start barricaded; a hatch over every site below a roof or a floor.
-- Units: studs. The core spans x -56..56, z -40..40; the fence x ±112, z -92..88.

local MapBuilder = require(script.Parent.MapBuilder)

local Flight9 = {}

-- Floor levels (the top of each floor)
local BF = -11.6 -- the dig: cargo hold, ice store and vault, the pit floor
local B = 0.4 -- ground: the cabins, the modules, the tent
local F2 = 13.4 -- the fuselage roof, the lab block upstairs, the trailer roofs, the gantry
local CEILING = 24.4 -- lab block upstairs ceiling
local LAB_ROOF = CEILING + 1
local LOWER_WALL = 11 -- the dig's floor up to the slab over it
local GROUND_WALL = 12
local UPPER_WALL = 11
local GROUND = 0.2 -- top of the snow outside
local PIT_RIM = GROUND + 1 -- the pit's retaining walls stand this high (hop over them)

-- The fuselage: a box with a chamfered top (sides up to the shoulders, then slopes in to a flat
-- roof), sunk into the ice up to the main deck. Its walls stand on z = ±HULL.
local HULL = 12
local HULL_WALL = 9 -- main deck walls, B up to the shoulders
local SHOULDER = B + HULL_WALL
local CROWN = 8.5 -- half-width of the flat roof (its top is F2)
local MID_W, MID_E = -40, 2 -- the mid section's broken ends
local FWD_W, FWD_E = 14, 56 -- the forward section: its broken end, and the nose wall
local COCKPIT = 44 -- the cockpit bulkhead
-- The hangar tent over the forward section: an arch springing from fabric walls
local TENT_W, TENT_E = 8, 46
local TENT_R = 17
local TENT_SPRING = 8.4 -- where the arch starts (it peaks at TENT_SPRING + TENT_R)
-- The tail section lies turned off line beyond the mid section's west end
local TAIL = CFrame.new(-46, 0, 0) * CFrame.Angles(0, math.rad(8), 0)
-- The torn-off wing and an engine pod out in the north field
local WING = CFrame.new(-24, GROUND + 0.8, 62) * CFrame.Angles(0, math.rad(-16), math.rad(7))
local POD = CFrame.new(-64, 2.4, 50) * CFrame.Angles(0, math.rad(30), math.rad(6))

-- Look
local SNOW = Color3.fromRGB(228, 232, 236) -- off-white: pure white glares
local PACKED = Color3.fromRGB(206, 214, 222) -- trodden snow and ice down in the pit
local ICE = Color3.fromRGB(164, 190, 206)
local HULL_GREY = Color3.fromRGB(212, 216, 221) -- a touch darker than the snow, so it stands out
local NAVY = Color3.fromRGB(28, 50, 96) -- Boreal Air's livery
local LIVERY_RED = Color3.fromRGB(176, 38, 40)
local SOOT = Color3.fromRGB(34, 31, 30)
local SCORCH = Color3.fromRGB(78, 66, 56)
local SCAR = Color3.fromRGB(58, 50, 44) -- ploughed earth and burnt fuel
local WINDOW_DARK = Color3.fromRGB(38, 46, 58)
local WINDOW_FRAME = Color3.fromRGB(196, 201, 207)
local SEAM = Color3.fromRGB(172, 178, 186) -- panel joints in the skin
local DIRTY_SNOW = Color3.fromRGB(176, 170, 162)
local SHADOW_SNOW = Color3.fromRGB(214, 222, 232) -- a bluer drift
local INSULATION = Color3.fromRGB(214, 190, 120)
local CABLE = Color3.fromRGB(36, 36, 38)
local MASK_YELLOW = Color3.fromRGB(230, 196, 60)
local REFLECTOR = Color3.fromRGB(236, 120, 40)
local LINING = Color3.fromRGB(226, 222, 212) -- cabin panels
local DECK = Color3.fromRGB(118, 122, 128)
local HOLD_DECK = Color3.fromRGB(84, 88, 94)
local PLYWOOD = Color3.fromRGB(196, 164, 116)
local TENT = Color3.fromRGB(102, 110, 96) -- olive drab: it reads against the snow
local TENT_RIB = Color3.fromRGB(58, 62, 56)
local PANEL = Color3.fromRGB(186, 194, 198) -- prefab module cladding
local PANEL_IN = Color3.fromRGB(222, 224, 220)
local SAFETY_ORANGE = Color3.fromRGB(228, 108, 36)
local SAFETY_YELLOW = Color3.fromRGB(214, 170, 40)
local RUST = Color3.fromRGB(150, 64, 44)
local CONTAINER_BLUE = Color3.fromRGB(44, 84, 140)
local CONTAINER_GREEN = Color3.fromRGB(58, 104, 74)
local CONCRETE = Color3.fromRGB(150, 150, 150)
local DARK_METAL = Color3.fromRGB(62, 66, 72)
local STEEL = Color3.fromRGB(120, 126, 132)
local OLIVE = Color3.fromRGB(88, 96, 64)
local WHITE = Color3.fromRGB(240, 238, 232)
local BLACK = Color3.fromRGB(28, 29, 32)
local GLASS = Color3.fromRGB(170, 200, 215)
local SCREEN = Color3.fromRGB(80, 200, 255)
local GRAVEL = Color3.fromRGB(124, 118, 110)
local ASPHALT = Color3.fromRGB(58, 60, 66)
local SLATE = Color3.fromRGB(104, 104, 106)
local PINE = Color3.fromRGB(44, 78, 56)
local BARK = Color3.fromRGB(86, 62, 44)
local CRATE = Color3.fromRGB(150, 115, 70)
local MESH = Color3.fromRGB(110, 116, 122)
local SEAT = Color3.fromRGB(46, 62, 102)

-- Walls: soft ones can be shot through, breached and reinforced; steel, concrete and ice can't
local HULL_OUT: MapBuilder.Style = { color = HULL_GREY, material = Enum.Material.Metal, soft = true, exterior = true } -- thin aluminium skin
local HULL_IN: MapBuilder.Style = { color = HULL_GREY, material = Enum.Material.Metal, soft = true } -- the skin inside the tent / down by the vault
local NOSE: MapBuilder.Style = { color = HULL_GREY, material = Enum.Material.Metal, exterior = true } -- the nose's frames: hard
local COCKPIT_WALL: MapBuilder.Style = { color = DARK_METAL, material = Enum.Material.DiamondPlate } -- armoured flight-deck bulkhead
local CABIN: MapBuilder.Style = { color = LINING, material = Enum.Material.SmoothPlastic, soft = true } -- class dividers
local PLY_OUT: MapBuilder.Style = { color = PLYWOOD, material = Enum.Material.WoodPlanks, soft = true, exterior = true } -- sealing the breaks
local PLY: MapBuilder.Style = { color = PLYWOOD, material = Enum.Material.WoodPlanks, soft = true }
local TENT_OUT: MapBuilder.Style = { color = TENT, material = Enum.Material.Fabric, soft = true, exterior = true }
local PANEL_OUT: MapBuilder.Style = { color = PANEL, material = Enum.Material.SmoothPlastic, soft = true, exterior = true }
local PANEL_WALL: MapBuilder.Style = { color = PANEL_IN, material = Enum.Material.Plaster, soft = true }
local STEEL_RUST: MapBuilder.Style = { color = RUST, material = Enum.Material.Metal, exterior = true } -- container steel
local STEEL_BLUE: MapBuilder.Style = { color = CONTAINER_BLUE, material = Enum.Material.Metal, exterior = true }
local STEEL_GREEN: MapBuilder.Style = { color = CONTAINER_GREEN, material = Enum.Material.Metal, exterior = true }
local CONCRETE_WALL: MapBuilder.Style = { color = CONCRETE, material = Enum.Material.Concrete }
local ICE_WALL: MapBuilder.Style = { color = ICE, material = Enum.Material.Glacier }

-- Floor finishes
local BLUE_CARPET = { Color3.fromRGB(52, 70, 110), Enum.Material.Carpet }
local WINE_CARPET = { Color3.fromRGB(104, 40, 52), Enum.Material.Carpet }
local DARK_CARPET = { Color3.fromRGB(58, 60, 66), Enum.Material.Carpet }
local GREY_CARPET = { Color3.fromRGB(100, 102, 108), Enum.Material.Carpet }
local TILE = { Color3.fromRGB(214, 214, 210), Enum.Material.CeramicTiles }
local LAB_TILE = { Color3.fromRGB(226, 230, 228), Enum.Material.CeramicTiles }
local RUBBER = { Color3.fromRGB(45, 45, 48), Enum.Material.Rubber }
local RAISED = { Color3.fromRGB(176, 180, 186), Enum.Material.DiamondPlate }
local FROST = { Color3.fromRGB(196, 210, 220), Enum.Material.Concrete }

-- Holes in the floors: { x1, z1, x2, z2 }
local GALLEY_STAIRS = { -8, -7, -3, 9 } -- galley down into the cargo hold (climbs -z)
local ICE_STAIRS = { -35, -36, -30, -22.5 } -- drill lab down into the ice store (climbs -z)
local LAB_STAIRS = { 36, 35.5, 51, 39.5 } -- sample store up to the lab block's upper hall (climbs -x)
-- Hatches (4 × 4 trapdoors) over every site below a floor or a roof: x, z, the floor they're in
local HATCH = 4
local HATCHES = {
	{ -12, 6, B }, -- galley → cargo hold
	{ -12, -30, B }, -- medbay → ice vault
	{ -8, -17, B }, -- service hatch out in the alley → ice vault
	{ 34, 0, F2 }, -- fuselage roof (under the tent) → first class
	{ 49, 0, F2 }, -- cockpit roof (outside) → cockpit
	{ 38, -32, F2 }, -- trailer roof → control room
	{ 51, -32, F2 }, -- trailer roof → server room
}
local GROUND_HOLES = { GALLEY_STAIRS, ICE_STAIRS }
local UPPER_HOLES = { LAB_STAIRS }
for _, hatch in HATCHES do
	local x, z, level = hatch[1], hatch[2], hatch[3]
	table.insert(if level == B then GROUND_HOLES else UPPER_HOLES, { x - HATCH / 2, z - HATCH / 2, x + HATCH / 2, z + HATCH / 2 })
end

-- name, x1, z1, x2, z2, floor, finish (nil = the bare deck / concrete). Lights and finishes come from here.
local ROOMS = {
	{ "AftHold", -40, -12, -20, 12, BF },
	{ "CargoHold", -20, -12, 2, 12, BF },
	{ "IceStore", -38, -38, -24, -12, BF },
	{ "IceVault", -24, -38, -4, -12, BF, FROST },

	{ "Economy", -40, -12, -16, 12, B, BLUE_CARPET },
	{ "Galley", -16, -12, 2, 12, B, TILE },
	{ "Business", 14, -12, 26, 12, B, BLUE_CARPET },
	{ "FirstClass", 26, -12, 44, 12, B, WINE_CARPET },
	{ "Cockpit", 44, -12, 56, 12, B, DARK_CARPET },
	{ "DrillLab", -40, -40, -22, -22, B, RUBBER },
	{ "Medbay", -22, -40, -6, -22, B, TILE },
	{ "Comms", 14, -40, 30, -24, B, GREY_CARPET },
	{ "Control", 30, -40, 46, -24, B, GREY_CARPET },
	{ "ServerRoom", 46, -40, 56, -24, B, RAISED },
	{ "Decon", 14, 22, 26, 40, B, TILE },
	{ "LabHall", 26, 22, 34, 40, B },
	{ "SampleStore", 34, 22, 52, 40, B },

	{ "BioLab", 14, 22, 30, 40, F2, LAB_TILE },
	{ "UpperHall", 30, 22, 36, 40, F2 },
	{ "RecorderLab", 36, 22, 52, 35, F2, GREY_CARPET },
}

-- Openings (positions are world x / z along the wall)
local function door(at: number): MapBuilder.Opening
	return { from = at, to = at + 5, top = 8, kind = "Door" }
end

local function doubleDoor(at: number): MapBuilder.Opening
	return { from = at, to = at + 8, top = 8.5, kind = "Door" }
end

local function window(from: number, to: number, bottom: number?, top: number?): MapBuilder.Opening
	return { from = from, to = to, bottom = bottom or 3, top = top or 7, kind = "Window" }
end

local function arch(from: number, to: number, top: number?): MapBuilder.Opening
	return { from = from, to = to, top = top or 9, kind = "Arch" }
end

-- Wall along x at `z`, or along z at `x`
local function wallX(map: MapBuilder.Builder, style: MapBuilder.Style, z: number, x1: number, x2: number, base: number, height: number, openings: { MapBuilder.Opening }?, inside: number?)
	map:RoomWall(style, x1, z, x2, z, base, height, openings, inside)
end

local function wallZ(map: MapBuilder.Builder, style: MapBuilder.Style, x: number, z1: number, z2: number, base: number, height: number, openings: { MapBuilder.Opening }?, inside: number?)
	map:RoomWall(style, x, z1, x, z2, base, height, openings, inside)
end

-- Looks only: no collisions, bullets go through
local function cosmetic(part: BasePart, parent: Instance): BasePart
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Parent = parent
	return part
end

local function wedge(map: MapBuilder.Builder, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material): WedgePart
	local part = Instance.new("WedgePart")
	part.Name = name
	part.Size = size
	part.CFrame = cframe -- a WedgePart climbs toward its +Z
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.Parent = map.geometry
	return part
end

-- Block between two corners given as numbers (any order)
local function block(map: MapBuilder.Builder, name: string, x1: number, y1: number, z1: number, x2: number, y2: number, z2: number, color: Color3, material: Enum.Material?): Part
	return map:Box(name, Vector3.new(math.min(x1, x2), math.min(y1, y2), math.min(z1, z2)), Vector3.new(math.max(x1, x2), math.max(y1, y2), math.max(z1, z2)), color, material)
end

-- Upright cylinder standing on `base` (tanks, drums, posts)
local function drum(map: MapBuilder.Builder, name: string, x: number, z: number, base: number, height: number, diameter: number, color: Color3, material: Enum.Material): Part
	local part = map:Part(name, Vector3.new(height, diameter, diameter), CFrame.new(x, base + height / 2, z) * CFrame.Angles(0, 0, math.pi / 2), color, material)
	part.Shape = Enum.PartType.Cylinder -- (a cylinder's axis is its X: turned upright)
	return part
end

-- Cylinder lying along x from x1 to x2, its axis at (y, z) — or placed by `frame` (axis = its X)
local function tube(map: MapBuilder.Builder, name: string, length: number, diameter: number, frame: CFrame, color: Color3, material: Enum.Material): Part
	local part = map:Part(name, Vector3.new(length, diameter, diameter), frame, color, material)
	part.Shape = Enum.PartType.Cylinder
	return part
end

-- Flat sign with text on its front (-Z of `cframe`); `see` = false makes the board itself
-- invisible (letters painted straight onto a surface)
local function sign(map: MapBuilder.Builder, text: string, cframe: CFrame, size: Vector2, background: Color3, textColor: Color3, see: boolean?)
	local board = map:Part("Sign", Vector3.new(size.X, size.Y, 0.2), cframe, background, Enum.Material.SmoothPlastic)
	cosmetic(board, map.geometry)
	if see == false then
		board.Transparency = 1
	end
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.LightInfluence = 0.6
	gui.Parent = board
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(0.94, 0.8)
	label.Position = UDim2.fromScale(0.03, 0.1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = textColor
	label.Text = text
	label.Parent = gui
end

-- Sign on a wall face at `point`, facing `out`
local function wallSign(map: MapBuilder.Builder, text: string, point: Vector3, out: Vector3, size: Vector2, background: Color3, textColor: Color3, see: boolean?)
	local at = point + out * 0.12
	sign(map, text, CFrame.lookAt(at, at + out), size, background, textColor, see)
end

-- Pieces of [x1, x2] left between the gaps (each gap padded by `pad`)
local function segments(x1: number, x2: number, gaps: { { number } }, pad: number): { { number } }
	local sorted = table.clone(gaps)
	table.sort(sorted, function(a, b)
		return a[1] < b[1]
	end)
	local out = {}
	local cursor = x1
	for _, gap in sorted do
		local a, b = gap[1] - pad, gap[2] + pad
		if a > cursor then
			table.insert(out, { cursor, math.min(a, x2) })
		end
		cursor = math.max(cursor, b)
	end
	if x2 > cursor then
		table.insert(out, { cursor, x2 })
	end
	return out
end

-- Repeatable scatter: 0..1 from a couple of numbers (no math.random: the map is the same every round)
local function noise(a: number, b: number?): number
	local v = math.sin(a * 12.9898 + (b or 0) * 78.233) * 43758.5453
	return v - math.floor(v)
end

-- Looks-only part placed by `frame`; small detail casts no shadow. Dressing fixed to a soft wall
-- goes in Trim, so a breach through the wall takes it away too (DestructionService).
local function decoPart(map: MapBuilder.Builder, name: string, size: Vector3, frame: CFrame, color: Color3, material: Enum.Material, parent: Instance?): Part
	local part = map:Part(name, size, frame, color, material)
	cosmetic(part, parent or map.geometry)
	if size.X * size.Y * size.Z < 8 or math.min(size.X, size.Y, size.Z) < 0.3 then
		part.CastShadow = false
	end
	return part
end

-- Looks-only block between two corners
local function deco(map: MapBuilder.Builder, name: string, x1: number, y1: number, z1: number, x2: number, y2: number, z2: number, color: Color3, material: Enum.Material, parent: Instance?): Part
	local min = Vector3.new(math.min(x1, x2), math.min(y1, y2), math.min(z1, z2))
	local max = Vector3.new(math.max(x1, x2), math.max(y1, y2), math.max(z1, z2))
	return decoPart(map, name, max - min, CFrame.new((min + max) / 2), color, material, parent)
end

-- Looks-only cylinder (its axis along the frame's X)
local function decoTube(map: MapBuilder.Builder, name: string, length: number, diameter: number, frame: CFrame, color: Color3, material: Enum.Material, parent: Instance?): Part
	local part = decoPart(map, name, Vector3.new(length, diameter, diameter), frame, color, material, parent)
	part.Shape = Enum.PartType.Cylinder
	return part
end

-- Round cable / rope / hose / strut from `a` to `b`
local function cable(map: MapBuilder.Builder, name: string, a: Vector3, b: Vector3, diameter: number, color: Color3, material: Enum.Material?, parent: Instance?): Part
	local dir = (b - a).Unit
	local frame = if math.abs(dir.Y) > 0.999
		then CFrame.new((a + b) / 2) * CFrame.Angles(0, 0, math.pi / 2) -- (straight up: lookAt has no "up" to go by)
		else CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.pi / 2, 0) -- (turns the cylinder's X onto the line)
	return decoTube(map, name, (b - a).Magnitude, diameter, frame, color, material or Enum.Material.Rubber, parent)
end

-- Looks-only wedge (climbs toward its +Z)
local function decoWedge(map: MapBuilder.Builder, name: string, size: Vector3, frame: CFrame, color: Color3, material: Enum.Material, parent: Instance?): WedgePart
	local part = wedge(map, name, size, frame, color, material)
	cosmetic(part, parent or map.geometry)
	part.CastShadow = false
	return part
end

-- Snow blown up against a wall: `height` high where it meets the face at `point` (on the
-- ground), tailing off `run` studs out along `out`, `length` long along the wall. You wade
-- through it (looks only).
local function drift(map: MapBuilder.Builder, point: Vector3, out: Vector3, length: number, height: number, run: number)
	local centre = point + out * (run / 2) + Vector3.new(0, height / 2, 0)
	decoWedge(map, "Drift", Vector3.new(length, height, run), CFrame.lookAt(centre, centre + out), SNOW, Enum.Material.Snow)
end

-- Drifts along a wall face from a to b (world x or z along it), leaving the doorways in `gaps`
-- clear. `alongX`: the wall runs along x at `fixed` (else along z at `fixed`).
local function driftAlong(map: MapBuilder.Builder, alongX: boolean, fixed: number, a: number, b: number, out: number, gaps: { { number } }, height: number?)
	for i, s in segments(a, b, gaps, 0.6) do
		local length = s[2] - s[1]
		if length > 1.5 then
			local mid = (s[1] + s[2]) / 2
			local point = if alongX then Vector3.new(mid, GROUND, fixed) else Vector3.new(fixed, GROUND, mid)
			local dir = if alongX then Vector3.new(0, 0, out) else Vector3.new(out, 0, 0)
			local h = (height or 1.3) * (0.75 + 0.5 * noise(mid, fixed + i))
			drift(map, point, dir, length, h, h * 2.4)
		end
	end
end

-- Layer of snow lying on top of something (roofs, crates, barriers): looks only
local function snowCap(map: MapBuilder.Builder, x1: number, z1: number, x2: number, z2: number, top: number, thick: number?, parent: Instance?): Part
	return deco(map, "SnowCap", x1, top, z1, x2, top + (thick or 0.3), z2, SNOW, Enum.Material.Snow, parent)
end

-- Icicles hanging under an edge from `a` to `b`
local function icicles(map: MapBuilder.Builder, a: Vector3, b: Vector3, count: number)
	for i = 1, count do
		local t = (i - 0.5 + (noise(a.X + i, a.Z) - 0.5) * 0.6) / count
		local length = 0.5 + 1.6 * noise(b.X - i, b.Z + i)
		local p = a:Lerp(b, t)
		local spike = Instance.new("CornerWedgePart")
		spike.Name = "Icicle"
		spike.Size = Vector3.new(0.28, length, 0.28)
		spike.CFrame = CFrame.new(p - Vector3.new(0, length / 2, 0)) * CFrame.Angles(math.pi, noise(i, a.X) * 6, 0) -- (upside down: the point hangs)
		spike.Color = ICE
		spike.Material = Enum.Material.Ice
		spike.Transparency = 0.25
		spike.Anchored = true
		spike.CastShadow = false
		cosmetic(spike, map.geometry)
	end
end

local function ceilingOf(level: number): number
	return if level == BF then B - 1 elseif level == B then F2 - 1 else CEILING
end

local function buildFloors(map: MapBuilder.Builder)
	local shell = map:Folder("Shell")
	-- The dig: the hold's cargo deck, the vault's concrete, the pit's trodden ice (it looks like ice
	-- but doesn't skate like it)
	map:Floor("HoldFloor", -40.5, -12.5, 2.5, 12.5, BF, 1, HOLD_DECK, Enum.Material.DiamondPlate)
	map:Floor("VaultFloor", -38.5, -38.5, -3.5, -12.5, BF, 1, CONCRETE, Enum.Material.Concrete)
	local pit = map:Floor("PitFloor", -44, 12.5, 2, 38, BF, 1, PACKED, Enum.Material.Glacier)
	pit.CustomPhysicalProperties = PhysicalProperties.new(Enum.Material.Snow)

	-- The cabin floor over the hold is panels on beams: soft (shoot down through it, breach it)
	for _, piece in map:FloorWithHoles("CabinFloor", -40.5, -12.5, 2.5, 12.5, GROUND_HOLES, B, 1, DECK, Enum.Material.SmoothPlastic) do
		piece:SetAttribute("Breakable", "Soft")
		-- The hold's lining under it (DestructionService cuts it along with the floor)
		cosmetic(map:Part("Ceiling", Vector3.new(piece.Size.X, 0.1, piece.Size.Z), piece.CFrame * CFrame.new(0, -0.55, 0), LINING, Enum.Material.SmoothPlastic), shell)
	end
	-- The drill lab / medbay module stands over the ice store and vault: plywood, soft. The vault
	-- carries on out under the alley, where its roof is concrete.
	for _, piece in map:FloorWithHoles("ModuleFloor", -40.5, -40.5, -5.5, -21.5, GROUND_HOLES, B, 1, PLYWOOD, Enum.Material.WoodPlanks) do
		piece:SetAttribute("Breakable", "Soft")
		cosmetic(map:Part("Ceiling", Vector3.new(piece.Size.X, 0.1, piece.Size.Z), piece.CFrame * CFrame.new(0, -0.55, 0), WHITE, Enum.Material.Plaster), shell)
	end
	map:FloorWithHoles("VaultRoof", -40.5, -21.5, -3.5, -12.5, GROUND_HOLES, B, 1, CONCRETE, Enum.Material.Concrete)
	map:Floor("VaultRoof", -5.5, -40.5, -3.5, -21.5, B, 1, CONCRETE, Enum.Material.Concrete)

	-- Ground floors with nothing under them: the forward section (its lower half is still in the
	-- ice), the tent's duckboards round it, the trailers, the lab block
	map:Floor("ForwardDeck", 13.5, -12.5, 56.5, 12.5, B, 1, DECK, Enum.Material.SmoothPlastic)
	map:FloorWithHoles("TentFloor", TENT_W, -TENT_R, TENT_E, TENT_R, { { 13.5, -12.5, TENT_E, 12.5 } }, B, 0.3, PLYWOOD, Enum.Material.WoodPlanks)
	map:Floor("TrailerFloor", 13.5, -40.5, 56.5, -23.5, B, 1, PLYWOOD, Enum.Material.WoodPlanks)
	map:Floor("LabFloor", 13.5, 21.5, 52.5, 40.5, B, 1, CONCRETE, Enum.Material.Concrete)
	-- The lab block's upper floor: plywood over the containers, soft
	for _, piece in map:FloorWithHoles("LabFloor2", 13.5, 21.5, 52.5, 40.5, UPPER_HOLES, F2, 1, PLYWOOD, Enum.Material.WoodPlanks) do
		piece:SetAttribute("Breakable", "Soft")
		cosmetic(map:Part("Ceiling", Vector3.new(piece.Size.X, 0.1, piece.Size.Z), piece.CFrame * CFrame.new(0, -0.55, 0), WHITE, Enum.Material.Plaster), shell)
	end

	-- Roofs (the fuselage's come with it)
	local roof = Color3.fromRGB(150, 156, 160)
	map:Floor("ModuleRoof", -40.5, -40.5, -5.5, -21.5, F2, 1, roof, Enum.Material.Metal)
	map:FloorWithHoles("TrailerRoof", 13.5, -40.5, 56.5, -23.5, UPPER_HOLES, F2, 1, roof, Enum.Material.Metal)
	map:Floor("LabRoof", 13.5, 21.5, 52.5, 40.5, LAB_ROOF, 1, roof, Enum.Material.Metal)

	for _, hatch in HATCHES do
		map:Hatch(hatch[1], hatch[2], hatch[3], HATCH)
	end

	for _, room in ROOMS do
		local name, x1, z1, x2, z2, level, finish = table.unpack(room)
		if finish then
			local holes = if level == B then GROUND_HOLES elseif level == F2 then UPPER_HOLES else {}
			for _, piece in map:FloorWithHoles(name .. "Floor", x1, z1, x2, z2, holes, level + 0.04, 0.04, finish[1], finish[2]) do
				cosmetic(piece, shell)
			end
		end
		-- Ceiling lights, spread along the room's long side
		local top = ceilingOf(level)
		local count = math.max(1, math.round((x2 - x1) * (z2 - z1) / 500))
		for i = 1, count do
			local t = (i - 0.5) / count
			local position = if x2 - x1 >= z2 - z1
				then Vector3.new(x1 + (x2 - x1) * t, top - 0.2, (z1 + z2) / 2)
				else Vector3.new((x1 + x2) / 2, top - 0.2, z1 + (z2 - z1) * t)
			map:Light(position, 26)
		end
	end
end

-- Boreal Air's livery down one side of a hull section (side = -1 / 1: the wall on z = side * HULL):
-- the navy cheat line and red pinstripe, a row of cabin windows, the same windows inside (sky
-- through them), skipping the doors and windows in `gaps` and the bulkheads at `bulkheads`
local function livery(map: MapBuilder.Builder, x1: number, x2: number, side: number, gaps: { { number } }, bulkheads: { number })
	local outer, inner = side * (HULL + 0.5), side * (HULL - 0.5)
	local function strip(name: string, a: number, b: number, y1: number, y2: number, face: number, out: number, color: Color3, material: Enum.Material)
		cosmetic(block(map, name, a, y1, face, b, y2, face + out * 0.08, color, material), map.geometry)
	end
	local trim = map:Folder("Trim")
	for _, s in segments(x1, x2, gaps, 0.7) do
		strip("Stripe", s[1], s[2], B + 2.2, B + 3, outer, side, NAVY, Enum.Material.SmoothPlastic)
		strip("Pinstripe", s[1], s[2], B + 3.2, B + 3.45, outer, side, LIVERY_RED, Enum.Material.SmoothPlastic)
		-- Lap joints between the skin's panel rows
		for _, y in { B + 1.2, B + 6.7, SHOULDER - 0.7 } do
			strip("Seam", s[1], s[2], y, y + 0.1, outer, side * 0.6, SEAM, Enum.Material.Metal)
		end
	end
	-- The frames behind the skin show as joints every other window
	local x = x1 + 2.9
	while x < x2 - 0.5 do
		local clear = true
		for _, gap in gaps do
			if x > gap[1] - 0.8 and x < gap[2] + 0.8 then
				clear = false
			end
		end
		if clear then
			cosmetic(block(map, "Seam", x - 0.06, B + 0.3, outer, x + 0.06, SHOULDER - 0.05, outer + side * 0.05, SEAM, Enum.Material.Metal), trim).CastShadow = false
		end
		x += 5.2
	end
	x = x1 + 1.6
	while x < x2 - 1 do
		local clear = true
		for _, gap in gaps do
			if x > gap[1] - 1.4 and x < gap[2] + 1.4 then
				clear = false
			end
		end
		if clear then
			-- Rounded like a real cabin window: a pane between two discs
			cosmetic(block(map, "CabinWindow", x - 0.5, B + 4.8, outer, x + 0.5, B + 5.4, outer + side * 0.08, WINDOW_DARK, Enum.Material.Glass), trim)
			for _, y in { B + 4.8, B + 5.4 } do
				local disc = tube(map, "CabinWindow", 0.08, 1, CFrame.new(x, y, outer + side * 0.04) * CFrame.Angles(0, math.pi / 2, 0), WINDOW_DARK, Enum.Material.Glass)
				cosmetic(disc, trim).CastShadow = false
			end
			-- and its frame, a shade lighter than the skin
			cosmetic(block(map, "WindowFrame", x - 0.64, B + 4.15, outer, x + 0.64, B + 6.05, outer + side * 0.05, WINDOW_FRAME, Enum.Material.Metal), trim).CastShadow = false
			local hidden = false
			for _, at in bulkheads do
				if math.abs(x - at) < 1.4 then
					hidden = true
				end
			end
			if not hidden then
				strip("CabinWindow", x - 0.5, x + 0.5, B + 4.3, B + 5.9, inner, -side, Color3.fromRGB(196, 210, 222), Enum.Material.SmoothPlastic)
			end
		end
		x += 2.6
	end
end

-- The chamfered top of a fuselage section: a plate each side sloping in from the shoulders to the
-- flat roof. `frame` is the middle of the section (its X along the fuselage).
local function shoulders(map: MapBuilder.Builder, frame: CFrame, length: number): { BasePart }
	local parts = {}
	local inset = 0.5 / math.sqrt(2) -- (the outer face runs corner to corner; the centre is half a stud in)
	for _, side in { -1, 1 } do
		local centre = Vector3.new(0, (SHOULDER + F2) / 2 - inset, side * ((HULL + 0.5 + CROWN) / 2 - inset))
		local size = Vector3.new(length, 1, (F2 - SHOULDER) * math.sqrt(2) + 0.3)
		table.insert(parts, map:Part("HullShoulder", size, frame * CFrame.new(centre) * CFrame.Angles(side * math.pi / 4, 0, 0), HULL_GREY, Enum.Material.Metal))
	end
	return parts
end

-- The skin's round cross-section over the shoulders: the chamfer under it is what you walk on and
-- what shuts the cabin in; this is the curve you see from outside (three facets each side,
-- bowing out from the wall's top to the roof's edge). `frame` as for `shoulders`.
local CURVE = { Vector2.new(HULL + 0.5, SHOULDER), Vector2.new(11.96, SHOULDER + 2), Vector2.new(10.5, SHOULDER + 3.46), Vector2.new(CROWN, F2) } -- (z, y)
local function facet(map: MapBuilder.Builder, frame: CFrame, length: number, side: number, i: number, thick: number, lift: number, color: Color3, material: Enum.Material, parent: Instance?): Part
	local a, b = CURVE[i], CURVE[i + 1]
	local along = (b - a).Unit
	local n = Vector2.new(along.Y, -along.X) -- (outward, on the +z side)
	local centre = (a + b) / 2 + n * (lift - thick / 2)
	local normal = Vector3.new(0, n.Y, side * n.X)
	local placed = frame * CFrame.fromMatrix(Vector3.new(0, centre.Y, side * centre.X), Vector3.xAxis, normal, Vector3.xAxis:Cross(normal))
	return decoPart(map, "HullCurve", Vector3.new(length, thick, (b - a).Magnitude + 0.06), placed, color, material, parent)
end
local function roundShoulders(map: MapBuilder.Builder, frame: CFrame, length: number, parent: Instance?)
	for _, side in { -1, 1 } do
		for i = 1, 3 do
			facet(map, frame, length, side, i, 0.4, 0, HULL_GREY, Enum.Material.Metal, parent).CastShadow = true
		end
	end
end
-- Snow lying along the top of the curve (the flatter facets)
local function shoulderSnow(map: MapBuilder.Builder, frame: CFrame, length: number, parent: Instance?)
	for _, side in { -1, 1 } do
		facet(map, frame, length, side, 3, 0.3, 0.25, SNOW, Enum.Material.Snow, parent)
		facet(map, frame * CFrame.new(0, 0, 0), length * 0.7, side, 2, 0.2, 0.15, SNOW, Enum.Material.Snow, parent)
	end
end

-- A wall straight across a fuselage section at `x` on the main deck, with its top stepped in
-- under the shoulders so it fills the hull's cross-section
local function bulkhead(map: MapBuilder.Builder, style: MapBuilder.Style, x: number, openings: { MapBuilder.Opening }?, inside: number?)
	wallZ(map, style, x, -HULL, HULL, B, HULL_WALL, openings, inside)
	for _, step in { { SHOULDER, SHOULDER + 1.5, 10.5 }, { SHOULDER + 1.5, F2 - 1, 9 } } do
		local part = block(map, if style.exterior then "ExteriorWall" else "Wall", x - 0.5, step[1], -step[3], x + 0.5, step[2], step[3], style.color, style.material)
		if style.soft then
			part:SetAttribute("Breakable", "Soft")
		end
	end
end

-- Where the fuselage tore apart: shreds of skin curling out of the break and soot blown back over
-- the hull. `frame` sits on the break, its +X pointing out of the section.
local function brokenEnd(map: MapBuilder.Builder, frame: CFrame, parent: Instance)
	local function add(name: string, size: Vector3, cframe: CFrame, color: Color3)
		cosmetic(map:Part(name, size, frame * cframe, color, Enum.Material.Metal), parent)
	end
	-- side, height, size up, length out, how far it curls
	for _, s in { { 1, 2.4, 4.2, 2.8, 0.38 }, { 1, 7.2, 3.2, 1.6, 0.18 }, { -1, 3.6, 5, 2.2, 0.3 }, { -1, 8.2, 2.2, 3, 0.45 } } do
		local side, y, h, len, curl = s[1], s[2], s[3], s[4], s[5]
		add("TornSkin", Vector3.new(len, h, 0.3), CFrame.new(0, y, side * (HULL + 0.35)) * CFrame.Angles(0, -side * curl, 0) * CFrame.new(len / 2, 0, 0), SCORCH)
	end
	for _, s in { { -4, 5, 2.4, 0.25 }, { 3.5, 4, 1.6, 0.15 } } do
		add("TornSkin", Vector3.new(s[3], 0.3, s[2]), CFrame.new(0, F2 - 0.15, s[1]) * CFrame.Angles(0, 0, s[4]) * CFrame.new(s[3] / 2, 0, 0), SCORCH)
	end
	-- Soot along the top of the walls, over the shoulders and across the roof
	for _, side in { -1, 1 } do
		add("Soot", Vector3.new(7, 1, 0.1), CFrame.new(-3.5, SHOULDER - 0.6, side * (HULL + 0.56)), SOOT)
		local centre = Vector3.new(-3, (SHOULDER + F2) / 2 + 0.06, side * ((HULL + 0.5 + CROWN) / 2 + 0.06))
		add("Soot", Vector3.new(6, 0.1, 5.4), CFrame.new(centre) * CFrame.Angles(side * math.pi / 4, 0, 0), SOOT)
	end
	add("Soot", Vector3.new(5, 0.1, 2 * CROWN - 1), CFrame.new(-2.5, F2 + 0.05, 0), SOOT)
	-- The last frame ring standing proud of the tear, bent: up both sides, over the shoulders
	local rib = DARK_METAL
	for _, side in { -1, 1 } do
		decoPart(map, "Frame", Vector3.new(0.4, SHOULDER - B + 0.6, 0.5), frame * CFrame.new(0.7, (B + SHOULDER) / 2 - 0.3, side * (HULL + 0.1)) * CFrame.Angles(side * 0.04, 0, 0), rib, Enum.Material.Metal, parent)
		decoPart(map, "Frame", Vector3.new(0.4, 0.5, (F2 - SHOULDER) * math.sqrt(2)), frame * CFrame.new(0.7, (SHOULDER + F2) / 2 - 0.2, side * ((HULL + CROWN) / 2 + 0.1)) * CFrame.Angles(side * math.pi / 4, 0, 0), rib, Enum.Material.Metal, parent)
		-- Jagged skin round the bottom corners, and stringers snapped off along the tear
		decoWedge(map, "TornSkin", Vector3.new(0.25, 2.6, 2.2), frame * CFrame.new(1, B + 1.4, side * (HULL + 0.3)) * CFrame.Angles(0, side * 0.4 + math.pi / 2, 0.3), SCORCH, Enum.Material.Metal, parent)
		for _, y in { B + 4.5, SHOULDER - 1 } do
			decoPart(map, "Stringer", Vector3.new(1.8, 0.2, 0.3), frame * CFrame.new(0.9, y, side * (HULL - 0.2)) * CFrame.Angles(0, side * 0.25, -0.15), STEEL, Enum.Material.Metal, parent)
		end
		-- Insulation blankets torn out with it
		decoPart(map, "Insulation", Vector3.new(1.2, 2.2, 0.6), frame * CFrame.new(0.5, B + 6.2, side * (HULL - 1.2)) * CFrame.Angles(0.3, 0.2, side * 0.25), INSULATION, Enum.Material.Fabric, parent)
	end
	decoPart(map, "Frame", Vector3.new(0.4, 0.5, 2 * CROWN), frame * CFrame.new(0.7, F2 - 0.3, 0) * CFrame.Angles(0.05, 0, 0), rib, Enum.Material.Metal, parent)
	-- Floor beams sticking out of the deck
	for _, z in { -9, -5, 5, 9 } do
		decoPart(map, "FloorBeam", Vector3.new(1.4 + noise(z, frame.X) * 1.6, 0.6, 0.35), frame * CFrame.new(0.9, B - 0.7, z) * CFrame.Angles(0, 0, -0.08), STEEL, Enum.Material.Metal, parent)
	end
	-- Wiring looms and hydraulic lines hanging out of the ceiling (clear of the doorway)
	for i, c in { { 4, 3.2, CABLE }, { 5.5, 4.6, LIVERY_RED }, { -4.5, 3.8, CABLE }, { -6, 5.4, SAFETY_YELLOW }, { 7.5, 2.6, MESH }, { -8, 3, CABLE } } do
		local z, drop = c[1], c[2]
		local top = frame * Vector3.new(0.2, F2 - 1.2, z)
		local bottom = frame * Vector3.new(0.9 + noise(i, z) * 1.2, F2 - 1.2 - drop, z + (noise(z, i) - 0.5) * 1.5)
		cable(map, "Wiring", top, bottom, if c[3] == CABLE then 0.22 else 0.14, c[3], Enum.Material.Rubber, parent)
	end
end

local function buildFuselage(map: MapBuilder.Builder)
	-- MID SECTION. The hold, dug out of the ice: its north side stands open to the pit (the cargo
	-- door cut wide), its south side opens through the skin into the ice store and the vault
	wallX(map, HULL_OUT, HULL, MID_W - 0.5, MID_E + 0.5, BF, LOWER_WALL, { door(-36), doubleDoor(-14) }, -1)
	wallX(map, HULL_IN, -HULL, MID_W - 0.5, MID_E + 0.5, BF, LOWER_WALL, { door(-33), door(-15) })
	wallZ(map, ICE_WALL, MID_W, -HULL, HULL, BF, LOWER_WALL) -- (still frozen in at both ends)
	wallZ(map, ICE_WALL, MID_E, -HULL, HULL, BF, LOWER_WALL)
	wallZ(map, PLY, -20, -HULL, HULL, BF, LOWER_WALL, { arch(-4, 4) }) -- aft hold ↔ cargo hold
	-- The main deck: emergency exits onto the south alley, windows looking down into the pit,
	-- plywood sealing both breaks, the divider between economy and the galley (two aisles)
	wallX(map, HULL_OUT, HULL, MID_W - 0.5, MID_E + 0.5, B, HULL_WALL, { window(-34, -30), window(-8, -4) }, -1)
	wallX(map, HULL_OUT, -HULL, MID_W - 0.5, MID_E + 0.5, B, HULL_WALL, { door(-37), door(-6) }, 1)
	bulkhead(map, PLY_OUT, MID_W, { door(-2.5) }, 1)
	bulkhead(map, CABIN, -16, { door(-7.5), door(2.5) })
	bulkhead(map, PLY_OUT, MID_E, { door(-2.5) }, -1)
	shoulders(map, CFrame.new((MID_W + MID_E) / 2, 0, 0), MID_E - MID_W + 1)
	map:FloorWithHoles("HullRoof", MID_W - 0.5, -CROWN, MID_E + 0.5, CROWN, UPPER_HOLES, F2, 1, HULL_GREY, Enum.Material.Metal)

	-- FORWARD SECTION, inside the tent up to x = TENT_E (its skin there is an inside wall), then the
	-- cockpit out in the open. Business ↔ first class (two aisles), the armoured flight-deck door,
	-- the nose wall with the windscreen.
	wallX(map, HULL_IN, -HULL, FWD_W - 0.5, TENT_E, B, HULL_WALL, { door(17), door(37) })
	wallX(map, HULL_OUT, -HULL, TENT_E, FWD_E + 0.5, B, HULL_WALL, { window(49, 52) }, 1)
	wallX(map, HULL_IN, HULL, FWD_W - 0.5, TENT_E, B, HULL_WALL, { door(19), window(30, 34) })
	wallX(map, HULL_OUT, HULL, TENT_E, FWD_E + 0.5, B, HULL_WALL, { window(49, 52) }, -1)
	bulkhead(map, PLY, FWD_W, { door(-2.5) })
	bulkhead(map, CABIN, 26, { door(-7.5), door(2.5) })
	bulkhead(map, COCKPIT_WALL, COCKPIT, { door(-2.5) })
	bulkhead(map, NOSE, FWD_E, { window(-8, -2, 6, 8.6), window(2, 8, 6, 8.6) }, -1)
	shoulders(map, CFrame.new((FWD_W + FWD_E) / 2, 0, 0), FWD_E - FWD_W + 1)
	map:FloorWithHoles("HullRoof", FWD_W - 0.5, -CROWN, FWD_E + 0.5, CROWN, UPPER_HOLES, F2, 1, HULL_GREY, Enum.Material.Metal)
	-- The nose cone, chin down in the snow under the windscreen
	local noseY = -1.8
	for _, n in { { 0.5, 3, 16 }, { 3, 5.5, 12.5 }, { 5.5, 7.5, 8.5 } } do
		tube(map, "NoseCone", n[2] - n[1], n[3], CFrame.new(FWD_E + (n[1] + n[2]) / 2, noseY, 0), HULL_GREY, Enum.Material.Metal)
	end
	map:Part("Radome", Vector3.new(6, 6, 6), CFrame.new(FWD_E + 7.5, noseY, 0), Color3.fromRGB(70, 74, 80), Enum.Material.SmoothPlastic).Shape = Enum.PartType.Ball

	-- Livery, lettering, and the recovery team's spray-painted section markings
	livery(map, MID_W - 0.5, MID_E + 0.5, -1, { { -37, -32 }, { -6, -1 } }, { MID_W, -16, MID_E })
	livery(map, MID_W - 0.5, MID_E + 0.5, 1, { { -34, -30 }, { -8, -4 } }, { MID_W, -16, MID_E })
	livery(map, FWD_W - 0.5, FWD_E + 0.5, -1, { { 17, 22 }, { 37, 42 }, { 49, 52 } }, { FWD_W, 26, COCKPIT, FWD_E })
	livery(map, FWD_W - 0.5, FWD_E + 0.5, 1, { { 19, 24 }, { 30, 34 }, { 49, 52 } }, { FWD_W, 26, COCKPIT, FWD_E })
	for _, side in { -1, 1 } do
		wallSign(map, "BOREAL", Vector3.new(-19, B + 7.4, side * (HULL + 0.5)), Vector3.new(0, 0, side), Vector2.new(14, 2.4), NAVY, NAVY, false)
	end
	wallSign(map, "FLT 9 · SECTION A", Vector3.new(30, B + 7.6, -(HULL + 0.5)), -Vector3.zAxis, Vector2.new(10, 1.2), SAFETY_ORANGE, SAFETY_ORANGE, false)
	wallSign(map, "FLT 9 · SECTION B", Vector3.new(-23, BF + 7.4, HULL + 0.5), Vector3.zAxis, Vector2.new(10, 1.2), SAFETY_ORANGE, SAFETY_ORANGE, false)

	-- The breaks
	brokenEnd(map, CFrame.new(MID_W - 0.5, 0, 0) * CFrame.Angles(0, math.pi, 0), map.geometry)
	brokenEnd(map, CFrame.new(MID_E + 0.5, 0, 0), map.geometry)
	brokenEnd(map, CFrame.new(FWD_W - 0.5, 0, 0) * CFrame.Angles(0, math.pi, 0), map.geometry)
	-- What's left of the torn-off wing's root on the north side, over the pit, burnt black
	block(map, "WingRoot", -26, -3.4, HULL + 0.5, -8, -1.4, HULL + 3.5, SCORCH, Enum.Material.Metal)
	cosmetic(map:Part("TornSkin", Vector3.new(16, 0.3, 2.4), CFrame.new(-17, -1.3, HULL + 4.2) * CFrame.Angles(0.3, 0, 0.05), SOOT, Enum.Material.Metal), map.geometry)

	-- Overhead bins down both sides of every cabin (looks only: they're over everyone's heads)
	for _, cabin in { { MID_W + 0.5, -16.5 }, { -15.5, MID_E - 0.5 }, { FWD_W + 0.5, 25.5 }, { 26.5, COCKPIT - 0.5 } } do
		for _, side in { -1, 1 } do
			cosmetic(block(map, "Bins", cabin[1], SHOULDER - 2.2, side * (HULL - 2.4), cabin[2], SHOULDER, side * (HULL - 0.5), LINING, Enum.Material.SmoothPlastic), map.geometry)
			local face = side * (HULL - 2.42)
			-- Bin doors, the service strip under them, a cove light along the top
			local x = cabin[1] + 3.6
			while x < cabin[2] - 1 do
				deco(map, "BinSeam", x - 0.05, SHOULDER - 2.15, face, x + 0.05, SHOULDER - 0.05, face - side * 0.04, SEAM, Enum.Material.SmoothPlastic)
				deco(map, "BinLatch", x - 1.9, SHOULDER - 0.55, face, x - 1.3, SHOULDER - 0.35, face - side * 0.05, DARK_METAL, Enum.Material.Metal)
				x += 3.6
			end
			deco(map, "ServiceStrip", cabin[1], SHOULDER - 2.45, side * (HULL - 2.3), cabin[2], SHOULDER - 2.2, side * (HULL - 0.5), Color3.fromRGB(200, 198, 190), Enum.Material.SmoothPlastic)
			deco(map, "CoveLight", cabin[1], SHOULDER + 0.02, side * (HULL - 2.45), cabin[2], SHOULDER + 0.12, side * (HULL - 2.2), Color3.fromRGB(255, 236, 200), Enum.Material.Neon)
		end
	end

	-- Inside: the ceiling's cream lining, flat between the bins and sloping over them (the bare
	-- skin otherwise), with the roof hatches left open through it
	for _, s in { { MID_W + 0.5, MID_E - 0.5 }, { FWD_W + 0.5, FWD_E - 0.5 } } do
		for _, piece in map:FloorWithHoles("CabinCeiling", s[1], -8.1, s[2], 8.1, UPPER_HOLES, F2 - 1.04, 0.06, LINING, Enum.Material.SmoothPlastic) do
			cosmetic(piece, map.geometry).CastShadow = false
		end
		local length = s[2] - s[1]
		local inner = Vector2.new(HULL - 0.5, SHOULDER - 0.42) -- the chamfer's inner face, from the wall...
		local top = Vector2.new(CROWN - 0.42, F2 - 1) -- ...to the ceiling
		for _, side in { -1, 1 } do
			local mid = (inner + top) / 2 - Vector2.new(0.05, 0.05)
			decoPart(map, "CabinCeiling", Vector3.new(length, 0.06, (top - inner).Magnitude), CFrame.new((s[1] + s[2]) / 2, mid.Y, side * mid.X) * CFrame.Angles(side * math.pi / 4, 0, 0), LINING, Enum.Material.SmoothPlastic)
		end
	end

	-- Outside: the round of the skin over the shoulders, the joints and antennas on the roof, snow
	-- where it's out in the open (the forward section is under the tent up to its cockpit)
	roundShoulders(map, CFrame.new((MID_W + MID_E) / 2, 0, 0), MID_E - MID_W + 1)
	roundShoulders(map, CFrame.new((FWD_W + FWD_E) / 2, 0, 0), FWD_E - FWD_W + 1)
	shoulderSnow(map, CFrame.new(-27, 0, 0), 22) -- (not under the gantry)
	shoulderSnow(map, CFrame.new((TENT_E + FWD_E) / 2 + 0.5, 0, 0), FWD_E - TENT_E - 1)
	for _, s in { { MID_W - 0.5, MID_E + 0.5 }, { FWD_W - 0.5, FWD_E + 0.5 } } do
		for _, z in { -4.5, 4.5 } do
			deco(map, "RoofSeam", s[1], F2, z - 0.06, s[2], F2 + 0.04, z + 0.06, SEAM, Enum.Material.Metal)
		end
	end
	for _, a in { { -30, 0 }, { -10, 2.5 }, { 22, -1 }, { 52.5, 3 } } do -- VHF blades
		decoWedge(map, "Antenna", Vector3.new(0.15, 1.2, 1.6), CFrame.new(a[1], F2 + 0.6, a[2]) * CFrame.Angles(0, math.pi / 2, 0), DARK_METAL, Enum.Material.Metal)
	end
	deco(map, "Beacon", 41.7, F2, -0.3, 42.3, F2 + 0.35, 0.3, LIVERY_RED, Enum.Material.Neon)
	-- Snow drifted on the mid section's roof, patchy, and on the cockpit roof round its hatch
	for _, p in { { -39, -7.5, -25, 6.5 }, { -22, 1, -12, 8 }, { -21, -8, -16, -3 }, { -6, -7, 0, 2 } } do
		snowCap(map, p[1], p[2], p[3], p[4], F2, 0.22 + noise(p[1]) * 0.15)
	end
	for _, p in { { 46.6, -8, 56, -2.4 }, { 46.6, 2.4, 56, 8 }, { 51.4, -2.4, 56, 2.4 } } do
		snowCap(map, p[1], p[2], p[3], p[4], F2, 0.25)
	end
	-- Soot streaked back along the roof and the curve from the breaks
	for _, s in { { MID_W + 3, 1 }, { MID_E - 3, -1 }, { FWD_W + 3, 1 } } do
		for _, side in { -1, 1 } do
			facet(map, CFrame.new(s[1] + s[2] * 1.5, 0, 0), 7, side, 2, 0.1, 0.05, SOOT, Enum.Material.Metal)
			facet(map, CFrame.new(s[1] + s[2] * 3, 0, 0), 4, side, 3, 0.1, 0.05, SCORCH, Enum.Material.Metal)
		end
	end
	-- The nose: the cone's steps smoothed over, the windscreen's black mask, its frames and wipers
	for _, n in { { 2.2, 3.4, 14.4 }, { 5, 6, 10.6 }, { 7.2, 8, 6.4 } } do
		decoTube(map, "NoseCone", n[2] - n[1] + 0.8, n[3], CFrame.new(FWD_E + (n[1] + n[2]) / 2, -1.8, 0), HULL_GREY, Enum.Material.Metal).CastShadow = true
	end
	-- (the mask is painted round the panes, over their frames: the glass stays clear)
	local front = FWD_E + 0.63
	local mask = Color3.fromRGB(30, 31, 34)
	for _, m in { { -9.2, 9.2, B + 5.4, B + 6 }, { -9.2, 9.2, B + 8.6, B + 9.5 }, { -9.2, -8, B + 6, B + 8.6 }, { -2, 2, B + 6, B + 8.6 }, { 8, 9.2, B + 6, B + 8.6 } } do
		deco(map, "WindscreenMask", front, m[3], m[1], front + 0.05, m[4], m[2], mask, Enum.Material.SmoothPlastic)
	end
	for _, z in { -5, 5 } do
		decoPart(map, "Wiper", Vector3.new(0.12, 2.4, 0.18), CFrame.new(front + 0.15, B + 7, z + (if z < 0 then 1.2 else -1.2)) * CFrame.Angles(math.rad(if z < 0 then 50 else -50), 0, 0), BLACK, Enum.Material.Metal)
	end
	-- Pitot probes by the nose, the cockpit's side windows masked black too
	for _, side in { -1, 1 } do
		decoPart(map, "Pitot", Vector3.new(0.9, 0.12, 0.12), CFrame.new(FWD_E - 2, B + 5.2, side * (HULL + 0.8)) * CFrame.Angles(0, side * 0.3, 0), STEEL, Enum.Material.Metal)
		local face = side * (HULL + 0.63)
		for _, m in { { 48.5, 52.5, B + 2.6, B + 3 }, { 48.5, 52.5, B + 7, B + 7.9 }, { 48.5, 49, B + 3, B + 7 }, { 52, 52.5, B + 3, B + 7 } } do
			deco(map, "WindscreenMask", m[1], m[3], face, m[2], m[4], face + side * 0.05, mask, Enum.Material.SmoothPlastic, map:Folder("Trim"))
		end
	end
end

-- The tail section: broken off behind the wing and slewed round, lying at an angle beyond the mid
-- section's west end with its fin standing up. Walk into the rear cabin through the break. All of
-- it is in the Yard folder: standing inside the wreck still counts as outside (PerimeterService).
local function buildTail(map: MapBuilder.Builder)
	local yard = map:Folder("Yard")
	local function at(name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material): Part
		local part = map:Part(name, size, TAIL * offset, color, material)
		part.Parent = yard
		return part
	end
	at("TailFloor", Vector3.new(18, 1, 2 * HULL), CFrame.new(-9, B - 0.5, 0), DECK, Enum.Material.SmoothPlastic)
	for _, side in { -1, 1 } do
		at("TailSkin", Vector3.new(18, SHOULDER + 3, 1), CFrame.new(-9, (SHOULDER - 3) / 2, side * HULL), HULL_GREY, Enum.Material.Metal)
		local face = side * (HULL + 0.54)
		cosmetic(at("Stripe", Vector3.new(17, 0.8, 0.08), CFrame.new(-9, B + 2.6, face), NAVY, Enum.Material.SmoothPlastic), yard)
		cosmetic(at("Pinstripe", Vector3.new(17, 0.25, 0.08), CFrame.new(-9, B + 3.33, face), LIVERY_RED, Enum.Material.SmoothPlastic), yard)
		for i = 0, 5 do
			local x = -2.5 - i * 2.6
			decoPart(map, "CabinWindow", Vector3.new(1, 0.6, 0.08), TAIL * CFrame.new(x, B + 5.1, face), WINDOW_DARK, Enum.Material.Glass, yard)
			for _, y in { B + 4.8, B + 5.4 } do
				decoTube(map, "CabinWindow", 0.08, 1, TAIL * CFrame.new(x, y, face) * CFrame.Angles(0, math.pi / 2, 0), WINDOW_DARK, Enum.Material.Glass, yard)
			end
			if i % 2 == 0 then
				decoPart(map, "Seam", Vector3.new(0.12, SHOULDER - B, 0.05), TAIL * CFrame.new(x - 1.3, (B + SHOULDER) / 2, face), SEAM, Enum.Material.Metal, yard)
			end
		end
		for _, y in { B + 1.2, B + 6.7 } do
			decoPart(map, "Seam", Vector3.new(17, 0.1, 0.05), TAIL * CFrame.new(-9, y, face), SEAM, Enum.Material.Metal, yard)
		end
		-- Snow drifted up the side it's lying on, and icicles off the shoulder
		decoWedge(map, "Drift", Vector3.new(17, 1.6, 4), TAIL * CFrame.new(-9, GROUND + 0.8, side * (HULL + 0.5 + 2)) * CFrame.Angles(0, if side > 0 then math.pi else 0, 0), SNOW, Enum.Material.Snow, yard)
		icicles(map, TAIL * Vector3.new(-17, SHOULDER - 0.1, side * (HULL + 0.6)), TAIL * Vector3.new(-1, SHOULDER - 0.1, side * (HULL + 0.6)), 7)
	end
	for _, part in shoulders(map, TAIL * CFrame.new(-9, 0, 0), 18) do
		part.Parent = yard
	end
	roundShoulders(map, TAIL * CFrame.new(-9, 0, 0), 18, yard)
	shoulderSnow(map, TAIL * CFrame.new(-10, 0, 0), 14, yard)
	decoPart(map, "SnowCap", Vector3.new(14, 0.3, 2 * CROWN - 2), TAIL * CFrame.new(-10, F2 + 0.15, 0), SNOW, Enum.Material.Snow, yard)
	at("TailRoof", Vector3.new(18, 1, 2 * CROWN), CFrame.new(-9, F2 - 0.5, 0), HULL_GREY, Enum.Material.Metal)
	-- The aft pressure bulkhead closes the cabin off
	at("AftBulkhead", Vector3.new(1, HULL_WALL, 2 * HULL), CFrame.new(-17.5, B + HULL_WALL / 2, 0), LINING, Enum.Material.SmoothPlastic)
	at("AftBulkhead", Vector3.new(1, 1.5, 21), CFrame.new(-17.5, SHOULDER + 0.75, 0), LINING, Enum.Material.SmoothPlastic)
	at("AftBulkhead", Vector3.new(1, 1.5, 18), CFrame.new(-17.5, SHOULDER + 2.25, 0), LINING, Enum.Material.SmoothPlastic)
	-- The tail cone sweeping up to the APU exhaust
	for _, c in { { -21, 6, 19, 3.9 }, { -27, 6, 15, 5.6 }, { -32.5, 5, 10, 7.2 } } do
		tube(map, "TailCone", c[2], c[3], TAIL * CFrame.new(c[1], c[4], 0), HULL_GREY, Enum.Material.Metal).Parent = yard
	end
	at("APU", Vector3.new(4, 4, 4), CFrame.new(-35.5, 7.8, 0), DARK_METAL, Enum.Material.Metal).Shape = Enum.PartType.Ball
	-- The fin: Boreal's navy, a red cap, a big white 9 for the flight number
	at("Fin", Vector3.new(6, 26, 1.6), CFrame.new(-32, 24.5, 0), NAVY, Enum.Material.SmoothPlastic)
	wedge(map, "Fin", Vector3.new(1.6, 26, 14), TAIL * CFrame.new(-22, 24.5, 0) * CFrame.Angles(0, -math.pi / 2, 0), NAVY, Enum.Material.SmoothPlastic).Parent = yard
	at("FinCap", Vector3.new(6.4, 1.4, 1.8), CFrame.new(-32, 37.2, 0), LIVERY_RED, Enum.Material.SmoothPlastic)
	for _, side in { -1, 1 } do
		local turn = CFrame.Angles(0, if side > 0 then math.pi else 0, 0)
		sign(map, "9", TAIL * CFrame.new(-32, 27, side * 0.92) * turn, Vector2.new(5.6, 9), WHITE, WHITE, false)
		sign(map, "BOREAL", TAIL * CFrame.new(-25, 16, side * 0.92) * turn, Vector2.new(9, 1.6), WHITE, WHITE, false)
	end
	-- Tailplanes: one still on, one snapped and drooping into the snow
	at("Tailplane", Vector3.new(8, 0.8, 15), CFrame.new(-31, 9.6, 15) * CFrame.Angles(0.06, 0, 0), HULL_GREY, Enum.Material.Metal)
	at("Tailplane", Vector3.new(7, 0.8, 9), CFrame.new(-30, 5.2, -12.5) * CFrame.Angles(-0.42, 0.25, 0), HULL_GREY, Enum.Material.Metal)
	-- The elevator's hinge line and snow on the one still on; the rudder's hinge line; the cone's
	-- steps smoothed over
	decoPart(map, "Seam", Vector3.new(0.12, 0.05, 14.5), TAIL * CFrame.new(-33.3, 10.02, 15) * CFrame.Angles(0.06, 0, 0), SEAM, Enum.Material.Metal, yard)
	decoPart(map, "SnowCap", Vector3.new(6, 0.3, 12), TAIL * CFrame.new(-30.5, 10.15, 15.5) * CFrame.Angles(0.06, 0, 0), SNOW, Enum.Material.Snow, yard)
	for _, side in { -1, 1 } do
		decoPart(map, "Seam", Vector3.new(0.14, 24, 0.05), TAIL * CFrame.new(-33.2, 24, side * 0.82), Color3.fromRGB(20, 36, 70), Enum.Material.SmoothPlastic, yard)
	end
	for _, c in { { -23.9, 2.6, 17.2, 4.7 }, { -29.8, 2.4, 12.6, 6.4 } } do
		decoTube(map, "TailCone", c[2], c[3], TAIL * CFrame.new(c[1], c[4], 0), HULL_GREY, Enum.Material.Metal, yard).CastShadow = true
	end
	-- Seats still bolted in (facing the break), one row torn loose
	for i, x in { -5, -10, -14.5 } do
		for _, z in { -8.5, 0, 8.5 } do
			if i == 2 and z == 0 then
				continue
			end
			at("Seats", Vector3.new(2, 1.5, 5), CFrame.new(x, B + 0.75, z), SEAT, Enum.Material.Fabric)
			at("SeatBack", Vector3.new(0.5, 2.6, 5), CFrame.new(x - 0.75, B + 2.8, z), SEAT, Enum.Material.Fabric)
		end
	end
	at("Seats", Vector3.new(2, 1.5, 5), CFrame.new(-8, B + 1, 1) * CFrame.Angles(0.5, 0.9, 1.2), SEAT, Enum.Material.Fabric)
	brokenEnd(map, TAIL, yard)
	sign(map, "SECTION C", TAIL * CFrame.new(-9, B + 7.6, -(HULL + 0.64)), Vector2.new(7, 1.2), SAFETY_ORANGE, SAFETY_ORANGE, false)
end

-- One end of the hangar tent at `x`: fabric strips stepping up under the arch. `hole(y1, y2)` gives
-- the half-width to leave open in the middle of each strip (0: none).
local TENT_STRIPS = { TENT_SPRING, SHOULDER, SHOULDER + 1.5, SHOULDER + 2.75, F2, F2 + 2, F2 + 4, F2 + 6, F2 + 8, F2 + 9.6, F2 + 11, F2 + 11.8 }
local function tentEnd(map: MapBuilder.Builder, x: number, hole: (number, number) -> number)
	for i = 1, #TENT_STRIPS - 1 do
		local y1, y2 = TENT_STRIPS[i], TENT_STRIPS[i + 1]
		local mid = (y1 + y2) / 2 - TENT_SPRING
		local half = math.sqrt(TENT_R ^ 2 - mid ^ 2)
		local gap = hole(y1, y2)
		local spans = if gap <= 0 then { { -half, half } } elseif gap < half then { { -half, -gap }, { gap, half } } else {}
		for _, span in spans do
			block(map, "ExteriorWall", x - 0.5, y1, span[1], x + 0.5, y2, span[2], TENT, Enum.Material.Fabric):SetAttribute("Breakable", "Soft")
		end
	end
end

-- Arch of 8 flat panels round (z = 0, y = TENT_SPRING), radius `r`, from x1 to x2
local function archPanels(map: MapBuilder.Builder, name: string, x1: number, x2: number, r: number, thickness: number, color: Color3, material: Enum.Material): { BasePart }
	local parts = {}
	for i = 1, 8 do
		local angle = (i - 0.5) * math.pi / 8
		local chord = 2 * r * math.sin(math.pi / 16) + 0.5
		local frame = CFrame.new((x1 + x2) / 2, TENT_SPRING + r * math.sin(angle), r * math.cos(angle)) * CFrame.Angles(math.pi / 2 - angle, 0, 0)
		table.insert(parts, map:Part(name, Vector3.new(x2 - x1, thickness, chord), frame, color, material))
	end
	return parts
end

-- THE HANGAR TENT over the forward section: olive fabric on steel arches. Flap doors at ground
-- level all round, a door high in the west end onto the bridge from the mid section's roof, and
-- one in the east end out onto the cockpit roof, where the nose runs on out of the tent.
local function buildTent(map: MapBuilder.Builder)
	local x1, x2 = TENT_W, TENT_E
	local wall = TENT_SPRING - GROUND
	local function flap(from: number, to: number): MapBuilder.Opening
		return { from = from, to = to, top = 7.6, kind = "Door" }
	end
	wallX(map, TENT_OUT, -TENT_R, x1, x2, GROUND, wall, { door(20), door(36) }, 1)
	wallX(map, TENT_OUT, TENT_R, x1, x2, GROUND, wall, { door(18), door(32) }, -1)
	-- West end
	wallZ(map, TENT_OUT, x1, -TENT_R, TENT_R, GROUND, wall, { flap(-4, 4) }, 1)
	wallZ(map, TENT_OUT, x1, -4, 4, F2, 8, { door(-2.5) }, 1)
	tentEnd(map, x1, function(y1: number, y2: number): number
		return if y1 >= F2 - 0.01 and y2 <= F2 + 8.01 then 4 else 0
	end)
	-- East end, fitted round the fuselage
	wallZ(map, TENT_OUT, x2, -TENT_R, -(HULL + 0.5), GROUND, wall, { flap(-16.4, -13.1) }, -1)
	wallZ(map, TENT_OUT, x2, HULL + 0.5, TENT_R, GROUND, wall, { flap(13.1, 16.4) }, -1)
	wallZ(map, TENT_OUT, x2, -4, 4, F2, 8, { door(-2.5) }, -1)
	tentEnd(map, x2, function(y1: number, y2: number): number
		if y2 <= SHOULDER + 0.01 then
			return HULL + 0.5
		elseif y2 <= F2 + 0.01 then
			return HULL + 0.5 - (y1 - SHOULDER) -- (the shoulders slope in)
		elseif y2 <= F2 + 8.01 then
			return 4
		end
		return 0
	end)
	-- The arch, and its steel ribs outside
	archPanels(map, "TentRoof", x1 - 0.5, x2 + 0.5, TENT_R + 0.5, 1, TENT, Enum.Material.Fabric)
	for _, x in { x1, (2 * x1 + x2) / 3, (x1 + 2 * x2) / 3, x2 } do
		for _, part in archPanels(map, "TentRib", x - 0.3, x + 0.3, TENT_R + 1.25, 0.5, TENT_RIB, Enum.Material.Metal) do
			cosmetic(part, map.geometry)
		end
	end
	-- Work lights strung along the corridors round the hull, and in the vestibule
	for _, p in { { 20, -14.8 }, { 38, -14.8 }, { 20, 14.8 }, { 38, 14.8 }, { 11, -9 }, { 11, 9 } } do
		map:Light(Vector3.new(p[1], 11, p[2]), 22, 1.1)
	end
	-- Scaffold platform just inside the high west door, onto the forward section's roof
	map:Floor("Platform", x1 + 0.5, -4, FWD_W - 0.5, 4, F2, 0.5, MESH, Enum.Material.DiamondPlate)
	for _, z in { -4, 4 } do
		map:Railing(Vector3.new(x1 + 0.5, F2, z), Vector3.new(FWD_W - 0.5, F2, z), SAFETY_YELLOW)
	end
	for _, z in { -3.6, 3.6 } do
		block(map, "ScaffoldPole", x1 + 0.6, B, z - 0.2, x1 + 1, F2 - 0.5, z + 0.2, SAFETY_YELLOW, Enum.Material.Metal)
	end
	-- Signs over the west flap doors and by a side door
	wallSign(map, "FLIGHT 9 · RECOVERY HANGAR", Vector3.new(x1 - 0.5, TENT_SPRING + 2.2, 0), -Vector3.xAxis, Vector2.new(20, 2.4), DARK_METAL, WHITE)
	wallSign(map, "AUTHORISED PERSONNEL ONLY", Vector3.new(TENT_E - 8, 5.4, -(TENT_R + 0.5)), -Vector3.zAxis, Vector2.new(7, 1.4), SAFETY_YELLOW, BLACK)
end

-- The gantry along the mid section's south side (stairs up from the alley, a deck over the
-- hull's shoulder onto its roof) and the bridge across the gap into the tent's high door. In the
-- Yard folder: standing under them is still outside.
local function buildGantry(map: MapBuilder.Builder)
	local yard = map:Folder("Yard")
	map:Stairs(-30, -17, -14, -13, B, F2, "+X", SAFETY_YELLOW, Enum.Material.DiamondPlate)
	map:Floor("Gantry", -14, -17, MID_E + 0.5, -CROWN, F2, 0.5, MESH, Enum.Material.DiamondPlate).Parent = yard
	map:Floor("Bridge", MID_E + 0.5, -3, TENT_W - 0.5, 3, F2, 0.5, MESH, Enum.Material.DiamondPlate).Parent = yard
	for _, x in { -13.6, -6, 2 } do
		block(map, "GantryLeg", x - 0.25, B, -16.85, x + 0.25, F2 - 0.5, -16.35, SAFETY_YELLOW, Enum.Material.Metal).Parent = yard
	end
	block(map, "BridgeLeg", 5, GROUND, -0.25, 5.5, F2 - 0.5, 0.25, SAFETY_YELLOW, Enum.Material.Metal).Parent = yard
	map:Railing(Vector3.new(-30, B, -17), Vector3.new(-14, F2, -17), SAFETY_YELLOW)
	map:Railing(Vector3.new(-14, F2, -17), Vector3.new(MID_E + 0.5, F2, -17), SAFETY_YELLOW)
	map:Railing(Vector3.new(MID_E + 0.5, F2, -17), Vector3.new(MID_E + 0.5, F2, -CROWN), SAFETY_YELLOW)
	for _, z in { -3, 3 } do
		map:Railing(Vector3.new(MID_E + 0.5, F2, z), Vector3.new(TENT_W - 0.5, F2, z), SAFETY_YELLOW)
	end
end

-- The research site's buildings
local function buildModules(map: MapBuilder.Builder)
	local base, h = B, GROUND_WALL

	-- DRILL LAB + MEDBAY: a prefab module over the ice store and the vault, on the alley south of
	-- the mid section (stairs down in the drill lab, a hatch down from the medbay)
	wallX(map, PANEL_OUT, -40, -40.5, -5.5, base, h, { window(-38, -34), door(-26), window(-14, -9) }, 1)
	wallX(map, PANEL_OUT, -22, -40.5, -5.5, base, h, { window(-34, -29), door(-20) }, -1)
	wallZ(map, PANEL_OUT, -40, -40, -22, base, h, { door(-33) }, 1) -- from the generator yard
	wallZ(map, PANEL_OUT, -6, -40, -22, base, h, { window(-36, -31), door(-29) }, -1)
	wallZ(map, PANEL_WALL, -22, -40, -22, base, h, { door(-37), window(-29, -25) }) -- drill lab ↔ medbay

	-- ICE STORE + ICE VAULT, cut into the ice under it: concrete all round, and through the hull's
	-- skin (north) into the holds
	wallX(map, CONCRETE_WALL, -38, -38.5, -3.5, BF, LOWER_WALL)
	wallZ(map, CONCRETE_WALL, -38, -38, -12, BF, LOWER_WALL)
	wallZ(map, CONCRETE_WALL, -4, -38, -12, BF, LOWER_WALL)
	wallZ(map, CONCRETE_WALL, -24, -38, -12, BF, LOWER_WALL, { door(-30), door(-19) }) -- ice store ↔ vault

	-- COMMAND: three trailers end to end south of the tent: comms, the CONTROL ROOM, the SERVER
	-- ROOM. Steel stairs up the back to the roof (hatches into both sites).
	wallX(map, PANEL_OUT, -40, 13.5, 56.5, base, h, { window(17, 21), door(24), window(32, 37), window(39, 43) }, 1)
	wallX(map, PANEL_OUT, -24, 13.5, 56.5, base, h, { door(16), window(34, 40), door(50) }, -1)
	wallZ(map, PANEL_OUT, 14, -40, -24, base, h, { window(-35, -29) }, 1)
	wallZ(map, PANEL_OUT, 56, -40, -24, base, h, { window(-34, -30) }, -1)
	wallZ(map, PANEL_WALL, 30, -40, -24, base, h, { door(-36), window(-30, -26) }) -- comms ↔ control (a window to watch through)
	wallZ(map, PANEL_WALL, 46, -40, -24, base, h, { door(-30) }) -- control ↔ server room

	-- LAB BLOCK north of the tent: shipping containers (hard steel: rust, blue, green) with the
	-- labs' prefab panels stacked on top (soft). Downstairs decon, the hall, the sample store
	-- (stairs up inside); upstairs the BIO LAB and the RECORDER LAB either side of the upper hall.
	wallX(map, STEEL_RUST, 22, 13.5, 26, base, h, { window(17, 21) }, 1)
	wallX(map, STEEL_BLUE, 22, 26, 38, base, h, { door(28) }, 1)
	wallX(map, STEEL_GREEN, 22, 38, 52.5, base, h, { window(41, 46) }, 1)
	wallX(map, STEEL_GREEN, 40, 13.5, 26, base, h, { window(17, 21) }, -1)
	wallX(map, STEEL_RUST, 40, 26, 38, base, h, { door(28.5) }, -1)
	wallX(map, STEEL_BLUE, 40, 38, 52.5, base, h, nil, -1)
	wallZ(map, STEEL_RUST, 14, 21.5, 40.5, base, h, nil, 1) -- (the outside stairs run up this side)
	wallZ(map, STEEL_GREEN, 52, 21.5, 40.5, base, h, { door(25), window(31, 34) }, -1)
	wallZ(map, PANEL_WALL, 26, 22, 40, base, h, { door(32) }) -- decon ↔ hall
	wallZ(map, PANEL_WALL, 34, 22, 40, base, h, { door(25) }) -- hall ↔ sample store
	local up, uh = F2, UPPER_WALL
	wallX(map, PANEL_OUT, 22, 13.5, 52.5, up, uh, { door(14.5), window(23, 28), window(31, 34), window(40, 46) }, 1) -- (the door's off the outside stairs' landing)
	wallX(map, PANEL_OUT, 40, 13.5, 52.5, up, uh, { window(18, 24) }, -1)
	wallZ(map, PANEL_OUT, 14, 21.5, 40.5, up, uh, { window(28, 34) }, 1)
	wallZ(map, PANEL_OUT, 52, 21.5, 40.5, up, uh, { window(25, 31) }, -1)
	wallZ(map, PANEL_WALL, 30, 22, 40, up, uh, { door(26) }) -- bio lab ↔ upper hall
	wallZ(map, PANEL_WALL, 36, 22, 35, up, uh, { door(25) }) -- upper hall ↔ recorder lab
	wallX(map, PANEL_WALL, 35, 36, 52, up, uh, { window(40, 46) }) -- recorder lab ↔ over the stairs
	-- Container corner posts and the seam between the steel and the labs on top
	for _, x in { 13.5, 26, 38, 52.5 } do
		for _, z in { 21.5, 40.5 } do
			cosmetic(block(map, "CornerPost", x - 0.35, B, z - 0.35, x + 0.35, F2, z + 0.35, DARK_METAL, Enum.Material.Metal), map.geometry)
		end
	end
	for _, e in { { 13.3, 21.3, 52.7, 21.6 }, { 13.3, 40.4, 52.7, 40.7 }, { 13.3, 21.6, 13.6, 40.4 }, { 52.4, 21.6, 52.7, 40.4 } } do
		cosmetic(block(map, "Seam", e[1], F2 - 1.2, e[2], e[3], F2 - 0.6, e[4], DARK_METAL, Enum.Material.Metal), map.geometry)
	end
end

local function buildStairs(map: MapBuilder.Builder)
	local function rail(x1: number, z1: number, x2: number, z2: number, y: number)
		map:Railing(Vector3.new(x1, y, z1), Vector3.new(x2, y, z2), STEEL)
	end
	-- Galley down into the cargo hold, through a hole cut in the cabin floor
	map:Stairs(-8, -7, -3, 9, BF, B, "-Z", DARK_METAL, Enum.Material.DiamondPlate)
	rail(-8, -7, -8, 9, B)
	rail(-3, -7, -3, 9, B)
	rail(-8, 9, -3, 9, B)
	map:Railing(Vector3.new(-3, BF, 9), Vector3.new(-3, B, -7), STEEL)
	-- Drill lab down into the ice store
	map:Stairs(-35, -36, -30, -22.5, BF, B, "-Z", CONCRETE, Enum.Material.Concrete)
	rail(-35, -36, -35, -22.5, B)
	rail(-30, -36, -30, -22.5, B)
	map:Railing(Vector3.new(-30, BF, -22.5), Vector3.new(-30, B, -36), STEEL)
	map:Railing(Vector3.new(-35, BF, -22.5), Vector3.new(-35, B, -36), STEEL)
	-- Lab block: up along the sample store's north wall to the upper hall, and the outside stairs
	-- up its west end to a landing by the bio lab's door
	map:Stairs(36, 35.5, 51, 39.5, B, F2, "-X", DARK_METAL, Enum.Material.DiamondPlate)
	map:Railing(Vector3.new(51, B, 35.5), Vector3.new(36, F2, 35.5), STEEL)
	local yard = map:Folder("Yard")
	map:Stairs(9, 22, 13, 38, GROUND, F2, "-Z", DARK_METAL, Enum.Material.DiamondPlate)
	map:Floor("Landing", 9, 18, 20, 22, F2, 0.5, MESH, Enum.Material.DiamondPlate).Parent = yard
	for _, p in { { 9.3, 18.3 }, { 19.7, 18.3 } } do
		block(map, "LandingLeg", p[1] - 0.25, GROUND, p[2] - 0.25, p[1] + 0.25, F2 - 0.5, p[2] + 0.25, DARK_METAL, Enum.Material.Metal).Parent = yard
	end
	map:Railing(Vector3.new(9, GROUND, 38), Vector3.new(9, F2, 22), STEEL)
	rail(9, 22, 9, 18, F2)
	rail(9, 18, 20, 18, F2)
	rail(20, 18, 20, 22, F2)
	-- Steel stairs up the back of the command trailers to their roof
	map:Stairs(49, -56, 53, -40.5, GROUND, F2, "+Z", DARK_METAL, Enum.Material.DiamondPlate)
	map:Railing(Vector3.new(49, GROUND, -56), Vector3.new(49, F2, -40.5), STEEL)
	map:Railing(Vector3.new(53, GROUND, -56), Vector3.new(53, F2, -40.5), STEEL)
end

-- Unit load device (an airline cargo can), x / z its middle
local function uld(map: MapBuilder.Builder, x: number, z: number, base: number)
	block(map, "ULD", x - 2.6, base, z - 2.4, x + 2.6, base + 5.2, z + 2.4, Color3.fromRGB(176, 182, 188), Enum.Material.Metal)
	cosmetic(block(map, "ULDNet", x - 2.3, base + 0.3, z - 2.5, x + 2.3, base + 4.6, z - 2.4, Color3.fromRGB(60, 62, 56), Enum.Material.Fabric), map.geometry)
	-- Its aluminium base and top rails, the net's straps
	deco(map, "ULDRail", x - 2.68, base, z - 2.48, x + 2.68, base + 0.35, z + 2.48, STEEL, Enum.Material.Metal)
	deco(map, "ULDRail", x - 2.66, base + 4.95, z - 2.46, x + 2.66, base + 5.2, z + 2.46, STEEL, Enum.Material.Metal)
	for _, sx in { -1.15, 1.15 } do
		deco(map, "ULDStrap", x + sx - 0.12, base + 0.3, z - 2.56, x + sx + 0.12, base + 4.6, z - 2.5, SAFETY_ORANGE, Enum.Material.Fabric)
	end
end

local function crate(map: MapBuilder.Builder, x: number, z: number, base: number, size: number, color: Color3?, snowy: boolean?)
	local h = size / 2
	block(map, "Crate", x - h, base, z - h, x + h, base + size, z + h, color or CRATE, Enum.Material.WoodPlanks)
	-- Battens round it near the top and the bottom (looks only)
	for _, y in { base + 0.15, base + size - 0.45 } do
		deco(map, "Batten", x - h - 0.06, y, z - h - 0.06, x + h + 0.06, y + 0.3, z + h + 0.06, Color3.fromRGB(96, 74, 48), Enum.Material.Wood)
	end
	if snowy then
		snowCap(map, x - h + 0.1, z - h + 0.1, x + h - 0.1, z + h - 0.1, base + size, 0.35)
	end
end

-- THE EXCAVATION PIT north of the mid section: dug down to the hold through the ice, a vehicle
-- ramp in from the west, timber stairs up at the east end, a core drill rig in the middle
local function buildPit(map: MapBuilder.Builder)
	local h = PIT_RIM - BF
	map:Wall("PitWall", -44, 12, -44, 38, BF, h, { { from = 31 - 12, to = 37.5 - 12, top = 40 } }, ICE, Enum.Material.Glacier) -- (the ramp comes in)
	map:Wall("PitWall", -44.5, 38, 2.5, 38, BF, h, { { from = -4 + 44.5, to = 1.5 + 44.5, top = 40 } }, ICE, Enum.Material.Glacier) -- (the stairs go out)
	map:Wall("PitWall", 2, 12.5, 2, 38, BF, h, nil, ICE, Enum.Material.Glacier)
	map:Wall("PitWall", -44.5, 12, -40.5, 12, BF, h, nil, ICE, Enum.Material.Glacier)
	local ramp = wedge(map, "Ramp", Vector3.new(6.5, GROUND - BF, 24), CFrame.new(-32, (BF + GROUND) / 2, 34.25) * CFrame.Angles(0, -math.pi / 2, 0), PACKED, Enum.Material.Snow)
	ramp.CustomPhysicalProperties = PhysicalProperties.new(Enum.Material.Snow)
	map:Railing(Vector3.new(-44, GROUND, 31), Vector3.new(-20, BF, 31), STEEL)
	map:Stairs(-4, 22, 1.5, 38, BF, GROUND, "+Z", Color3.fromRGB(150, 110, 75), Enum.Material.WoodPlanks)
	map:Railing(Vector3.new(-4, BF, 22), Vector3.new(-4, GROUND, 38), STEEL)

	-- Core drill rig: a platform, the mast (it stands up out of the pit), the drill string, a winch
	block(map, "RigDeck", -31, BF, 19, -25, BF + 1, 25, DARK_METAL, Enum.Material.DiamondPlate)
	block(map, "RigMast", -28.6, BF + 1, 21.4, -27.4, BF + 21, 22.6, SAFETY_ORANGE, Enum.Material.Metal)
	block(map, "RigCrown", -29.4, BF + 21, 20.6, -26.6, BF + 22.2, 23.4, DARK_METAL, Enum.Material.Metal)
	drum(map, "DrillString", -26.4, 22, BF + 1, 14, 0.7, STEEL, Enum.Material.Metal)
	block(map, "Winch", -30.8, BF + 1, 19.2, -28.8, BF + 3.6, 21.2, OLIVE, Enum.Material.Metal)
	-- Ice cut out in blocks, cargo dug out of the hold, crates of samples
	for _, b in { { -40, 15, -35, 19, 4 }, { -40, 20, -36, 24, 2.6 }, { -12, 30, -7, 34, 3 } } do
		block(map, "IceBlock", b[1], BF, b[2], b[3], BF + b[5], b[4], ICE, Enum.Material.Glacier)
	end
	uld(map, -18, 23, BF)
	uld(map, -11, 25, BF)
	for _, c in { { -38, 28 }, { -34, 28 } } do
		crate(map, c[1], c[2], BF, 3.6, nil, true)
	end
	-- Timber shoring against the ice walls, snow lipping over the rim (looks only)
	local timber = Color3.fromRGB(122, 92, 62)
	for _, p in { { 1.2, 14 }, { 1.2, 19 } } do
		deco(map, "Shoring", p[1], BF, p[2] - 0.35, p[1] + 0.3, PIT_RIM - 0.2, p[2] + 0.35, timber, Enum.Material.Wood)
	end
	for _, x in { -18, -12, -7 } do
		deco(map, "Shoring", x - 0.35, BF, 37.2, x + 0.35, PIT_RIM - 0.2, 37.5, timber, Enum.Material.Wood)
	end
	deco(map, "Waler", -19, BF + 4, 36.9, -6, BF + 4.7, 37.2, timber, Enum.Material.Wood)
	deco(map, "Waler", 0.9, BF + 4, 13, 1.2, BF + 4.7, 20, timber, Enum.Material.Wood)
	for _, r in { { -44.6, 12, -43.4, 31 }, { -20, 37.4, -4, 38.6 }, { 1.4, 12.5, 2.6, 22 } } do
		snowCap(map, r[1], r[2], r[3], r[4], PIT_RIM, 0.4)
	end
	-- Meltwater frozen in the low spots, slush trodden dark round the rig and the hold doors
	deco(map, "Ice", -24, BF, 27, -15, BF + 0.06, 31, ICE, Enum.Material.Ice).Transparency = 0.2
	for _, d in { { -33, 17.5, -22, 27 }, { -16, 12.6, -5, 17 }, { -38, 12.6, -30, 15 } } do
		deco(map, "Slush", d[1], BF, d[2], d[3], BF + 0.05, d[4], DIRTY_SNOW, Enum.Material.Snow)
	end
	-- The rig: lattice braces up the mast, the hydraulic line, a lamp at the top, ice cores laid out
	for _, b in { { 0, 6 }, { 6, 12 }, { 12, 18 } } do
		cable(map, "Brace", Vector3.new(-29.2, BF + 1 + b[1], 21.2), Vector3.new(-29.2, BF + 1 + b[2], 22.8), 0.2, SAFETY_ORANGE, Enum.Material.Metal)
		cable(map, "Brace", Vector3.new(-26.8, BF + 1 + b[1], 22.8), Vector3.new(-26.8, BF + 1 + b[2], 21.2), 0.2, SAFETY_ORANGE, Enum.Material.Metal)
	end
	cable(map, "Hose", Vector3.new(-29.8, BF + 3.6, 20.2), Vector3.new(-28.7, BF + 19, 21.3), 0.25, CABLE)
	local lamp = deco(map, "Light", -28.4, BF + 20.4, 20.4, -27.6, BF + 21, 21.2, Color3.fromRGB(255, 240, 210), Enum.Material.Neon)
	local rigLight = Instance.new("SpotLight")
	rigLight.Face = Enum.NormalId.Bottom
	rigLight.Range = 30
	rigLight.Angle = 80
	rigLight.Brightness = 1.6
	rigLight.Color = Color3.fromRGB(255, 236, 205)
	rigLight.Parent = lamp
	deco(map, "CoreTray", -24.5, BF, 18.5, -20.5, BF + 0.5, 20.5, OLIVE, Enum.Material.Wood)
	for i = 0, 2 do
		decoTube(map, "IceCore", 3.6, 0.5, CFrame.new(-22.5, BF + 0.65, 18.9 + i * 0.6), ICE, Enum.Material.Glacier)
	end
	-- Work light on a stand, the dewatering pump and its hose up over the rim
	deco(map, "LightStand", -42.8, BF, 25.8, -42.5, BF + 7, 26.1, SAFETY_YELLOW, Enum.Material.Metal)
	local work = decoPart(map, "Light", Vector3.new(1.6, 1, 0.3), CFrame.lookAt(Vector3.new(-42.2, BF + 7.2, 26), Vector3.new(-30, BF, 22)), Color3.fromRGB(240, 246, 255), Enum.Material.Neon)
	local workLight = Instance.new("SpotLight")
	workLight.Face = Enum.NormalId.Front
	workLight.Range = 36
	workLight.Angle = 75
	workLight.Brightness = 1.4
	workLight.Color = Color3.fromRGB(230, 240, 255)
	workLight.Parent = work
	deco(map, "Pump", -6.2, BF, 29, -4.4, BF + 1.6, 31.6, SAFETY_ORANGE, Enum.Material.Metal)
	cable(map, "Hose", Vector3.new(-5.3, BF + 1.2, 31.6), Vector3.new(-5.6, BF + 0.2, 36.6), 0.4, CABLE)
	cable(map, "Hose", Vector3.new(-5.6, BF + 0.2, 36.6), Vector3.new(-5.8, PIT_RIM + 0.3, 37.3), 0.4, CABLE)
	cable(map, "Hose", Vector3.new(-5.8, PIT_RIM + 0.3, 37.3), Vector3.new(-7, GROUND + 0.2, 46), 0.4, CABLE)

	-- Warning signs on posts at the rim
	for _, s in { { -20, 38.6, Vector3.zAxis }, { -44.6, 20, -Vector3.xAxis } } do
		local point = Vector3.new(s[1], PIT_RIM + 1.6, s[2])
		local out = s[3]
		local across = Vector3.new(out.Z, 0, out.X) * 3
		for _, d in { -1, 1 } do
			local p = point + across * d + out * 0.3
			block(map, "SignPost", p.X - 0.15, GROUND, p.Z - 0.15, p.X + 0.15, point.Y + 0.8, p.Z + 0.15, DARK_METAL, Enum.Material.Metal)
		end
		wallSign(map, "DANGER · EXCAVATION", point + out * 0.3, out, Vector2.new(8, 1.6), SAFETY_YELLOW, BLACK)
	end
end

-- Row of airline seats facing the nose (+x) at `x`, across z1..z2: low cover
local function seats(map: MapBuilder.Builder, x: number, z1: number, z2: number)
	block(map, "Seats", x - 1, B, z1, x + 1, B + 1.5, z2, SEAT, Enum.Material.Fabric)
	block(map, "SeatBack", x - 1.5, B, z1, x - 1, B + 3.9, z2, SEAT, Enum.Material.Fabric)
	-- Looks only: an armrest between every seat, a headrest cover on each
	local count = math.max(1, math.round((z2 - z1) / 1.7))
	local width = (z2 - z1) / count
	for i = 0, count do
		local z = math.clamp(z1 + i * width, z1 + 0.12, z2 - 0.12)
		deco(map, "Armrest", x - 1, B + 1.5, z - 0.12, x + 0.75, B + 2.2, z + 0.12, DARK_CARPET[1], Enum.Material.SmoothPlastic)
	end
	for i = 0, count - 1 do
		local z = z1 + i * width
		local tone = if noise(x, z) > 0.8 then Color3.fromRGB(196, 206, 222) else Color3.fromRGB(224, 222, 214)
		deco(map, "Headrest", x - 1.56, B + 3.05, z + 0.18, x - 0.94, B + 3.96, z + width - 0.18, tone, Enum.Material.Fabric)
	end
end

-- Something glowing (a screen, a laptop, LEDs): looks only
local function glow(map: MapBuilder.Builder, x1: number, y1: number, z1: number, x2: number, y2: number, z2: number, color: Color3?)
	local part = block(map, "Screen", x1, y1, z1, x2, y2, z2, color or SCREEN, Enum.Material.Neon)
	part.CastShadow = false
	cosmetic(part, map.geometry)
end

-- Bench / desk / table top on legs-in-one (a block), at `base`
local function bench(map: MapBuilder.Builder, x1: number, z1: number, x2: number, z2: number, base: number, height: number?, color: Color3?)
	block(map, "Bench", x1, base, z1, x2, base + (height or 3), z2, color or Color3.fromRGB(176, 180, 184), Enum.Material.Metal)
end

local function buildProps(map: MapBuilder.Builder)
	local freezer = Color3.fromRGB(226, 232, 236)
	local orange = Color3.fromRGB(240, 120, 30)

	-- ECONOMY: rows of seats (two aisles), one row torn loose and flung over
	for _, row in { { -34, { 0, 1 } }, { -29, { -1, 0, 1 } }, { -24, { -1, 1 } }, { -19, { -1, 0, 1 } } } do
		for _, group in row[2] do
			local z1 = if group == -1 then -HULL + 0.5 elseif group == 0 then -3.5 else 6.5
			seats(map, row[1], z1, z1 + (if group == 0 then 7 else 5))
		end
	end
	map:Part("Seats", Vector3.new(2.4, 3.6, 6), CFrame.new(-24.5, B + 1.6, 0.5) * CFrame.Angles(0.2, 0.7, 1.3), SEAT, Enum.Material.Fabric)
	-- GALLEY: the team's workbench and laptops, a trolley left where it stopped
	bench(map, -0.5, -HULL + 0.5, MID_E - 0.5, -8, B)
	bench(map, -2, 8, MID_E - 0.5, HULL - 0.5, B)
	glow(map, -1.2, B + 3, 9.5, 0.6, B + 4.2, 9.6)
	block(map, "Trolley", -15.4, B, 9, -14, B + 3.4, 11.4, Color3.fromRGB(190, 192, 194), Enum.Material.Metal)

	-- BUSINESS (the Nose defenders' spawn): evidence crates, a folding table
	crate(map, 24, -9, B, 2.4, OLIVE)
	crate(map, 24, 9.5, B, 2.4, OLIVE)
	bench(map, 15, 7, 18, 11, B, 2.8, Color3.fromRGB(120, 124, 128))
	-- FIRST CLASS: suites (cover, chest high) and the bar
	for _, s in { { 28, -HULL + 0.5 }, { 28, 7 }, { 37, 7 } } do
		block(map, "Suite", s[1], B, s[2], s[1] + 5, B + 3.8, s[2] + 4.5, Color3.fromRGB(130, 96, 80), Enum.Material.Wood)
	end
	block(map, "Bar", 39, B, -6.5, 42.5, B + 3.6, -3.5, Color3.fromRGB(80, 58, 44), Enum.Material.Wood)
	-- COCKPIT: the instrument panel under the windscreen, two seats, the pedestal between them
	block(map, "InstrumentPanel", 54, B, -9, 55.5, B + 3.6, 9, BLACK, Enum.Material.SmoothPlastic)
	for _, z in { -6, -1.5, 3 } do
		glow(map, 53.9, B + 1.6, z, 54, B + 3.2, z + 3)
	end
	block(map, "Glareshield", 53, B + 3.6, -9, 55.5, B + 4.4, 9, BLACK, Enum.Material.SmoothPlastic)
	for _, z in { -6, 3 } do
		block(map, "PilotSeat", 50, B, z, 52, B + 2, z + 3, Color3.fromRGB(60, 60, 64), Enum.Material.Fabric)
		block(map, "PilotSeatBack", 49.5, B, z, 50, B + 4.6, z + 3, Color3.fromRGB(60, 60, 64), Enum.Material.Fabric)
	end
	block(map, "Pedestal", 52, B, -1, 54, B + 2.6, 1, BLACK, Enum.Material.SmoothPlastic)
	cosmetic(block(map, "OverheadPanel", 51, F2 - 2.2, -3, 54, F2 - 1, 3, Color3.fromRGB(70, 72, 78), Enum.Material.SmoothPlastic), map.geometry)

	-- HOLDS: cargo cans, crates of recovered parts
	uld(map, -37.2, -8, BF)
	uld(map, -24, -8, BF)
	uld(map, -25, 8, BF)
	crate(map, -37.5, 5.5, BF, 3.4)
	uld(map, -1, -8.5, BF)
	uld(map, -17, 7, BF)
	crate(map, -17, -4, BF, 3, OLIVE)
	crate(map, -17, -4, BF + 3, 2, OLIVE)

	-- ICE STORE (the Hold defenders' spawn): a rack of ice cores, a chest freezer
	block(map, "CoreRack", -37.5, BF, -37, -36, BF + 7, -24, DARK_METAL, Enum.Material.Metal)
	block(map, "Freezer", -28, BF, -37.5, -25, BF + 3.4, -34.5, freezer, Enum.Material.Metal)
	-- ICE VAULT: freezers along the back wall, a sample table, a rack of ice cores
	for _, x in { -22, -15, -8.5 } do
		block(map, "Freezer", x, BF, -37.5, x + 4.5, BF + 7, -35.5, freezer, Enum.Material.Metal)
		glow(map, x + 0.4, BF + 6, -35.5, x + 4.1, BF + 6.3, -35.4, Color3.fromRGB(120, 200, 255))
	end
	bench(map, -22, -30, -18, -26, BF)
	local case = block(map, "SampleCase", -21.2, BF + 3, -29.2, -18.8, BF + 4.6, -26.8, GLASS, Enum.Material.Glass)
	case.Transparency = 0.5
	block(map, "CoreRack", -8, BF, -27, -6, BF + 7, -21, DARK_METAL, Enum.Material.Metal)

	-- DRILL LAB: core-logging table, a centrifuge, shelves
	bench(map, -29, -32, -25, -28, B)
	drum(map, "Centrifuge", -38, -38, B, 3.2, 3, Color3.fromRGB(200, 204, 208), Enum.Material.Metal)
	block(map, "Shelves", -28, B, -23.5, -23, B + 7, -22.5, DARK_METAL, Enum.Material.Metal)
	-- MEDBAY: two cots, a cabinet
	for _, x in { -21.5, -10 } do
		block(map, "Cot", x, B, -39.5, x + 3.5, B + 2.2, -35, WHITE, Enum.Material.Fabric)
	end
	block(map, "Cabinet", -14, B, -24, -8, B + 6, -22.5, WHITE, Enum.Material.Metal)

	-- COMMS (the Command defenders' spawn): radio desk, lockers
	bench(map, 14.5, -38, 17, -30, B, 3, DARK_METAL)
	glow(map, 16.9, B + 3.2, -36, 17, B + 5, -32)
	block(map, "Lockers", 26, B, -25, 29.5, B + 7, -24.5, Color3.fromRGB(90, 110, 130), Enum.Material.Metal)
	-- CONTROL ROOM: console desks, a wall of screens
	for _, d in { { 32, 35 }, { 41, 44 } } do
		bench(map, d[1], -38, d[2], -34, B, 3, DARK_METAL)
		glow(map, d[1] + 0.3, B + 3, -36.5, d[2] - 0.3, B + 4.6, -36.4)
	end
	bench(map, 33, -26, 43, -24.5, B, 3, DARK_METAL)
	glow(map, 45.4, B + 4, -39, 45.5, B + 9, -31)
	-- SERVER ROOM: racks with their lights
	for _, r in { { 47.5, -39.5, 51.5, -37.5 }, { 52.5, -39.5, 55.5, -37.5 }, { 53, -29, 55.5, -26 } } do
		block(map, "ServerRack", r[1], B, r[2], r[3], B + 7.4, r[4], BLACK, Enum.Material.SmoothPlastic)
		local front = if r[2] < -35 then r[4] else r[2]
		glow(map, r[1] + 0.3, B + 1, front - 0.05, r[3] - 0.3, B + 1.2, front + 0.05, Color3.fromRGB(90, 255, 140))
		glow(map, r[1] + 0.3, B + 4, front - 0.05, r[3] - 0.3, B + 4.2, front + 0.05, Color3.fromRGB(90, 255, 140))
	end

	-- DECON: showers, hazmat suits on their rack, a bench
	for _, z in { 34, 37 } do
		local stall = block(map, "Shower", 14.5, B, z, 17.5, B + 7, z + 2.5, GLASS, Enum.Material.Glass)
		stall.Transparency = 0.5
	end
	block(map, "SuitRack", 22.5, B, 38.5, 25.5, B + 6, 39.5, SAFETY_YELLOW, Enum.Material.Fabric)
	block(map, "Bench", 18, B, 22.5, 23, B + 1.6, 23.6, DARK_METAL, Enum.Material.Metal)
	-- LAB HALL and SAMPLE STORE
	block(map, "Lockers", 26.5, B, 23, 27.5, B + 7, 30, Color3.fromRGB(90, 110, 130), Enum.Material.Metal)
	block(map, "Shelves", 46, B, 22.5, 51.5, B + 7, 24, DARK_METAL, Enum.Material.Metal)
	crate(map, 40, 28, B, 3.4)
	crate(map, 37.5, 31.5, B, 2.6, OLIVE)
	-- BIO LAB: benches, the fume hood, a glovebox, a specimen tank
	bench(map, 14.5, 26, 17, 38, F2)
	block(map, "FumeHood", 20, F2, 38, 26, F2 + 7, 39.5, WHITE, Enum.Material.Metal)
	local sash = block(map, "Sash", 20.4, F2 + 3, 37.8, 25.6, F2 + 6, 38, GLASS, Enum.Material.Glass)
	sash.Transparency = 0.5
	block(map, "Glovebox", 14.8, F2 + 3, 30, 16.8, F2 + 5, 34, GLASS, Enum.Material.Glass).Transparency = 0.4
	drum(map, "SpecimenTank", 27, 24.5, F2, 4.5, 2.6, Color3.fromRGB(150, 196, 210), Enum.Material.Glass)
	-- RECORDER LAB: Flight 9's two orange recorders on the bench, a panel of the wreck on trestles,
	-- the evidence board
	bench(map, 38, 22.5, 42, 25, F2)
	bench(map, 47, 22.5, 51.5, 25, F2)
	for _, x in { 38.6, 40.6 } do
		block(map, "FlightRecorder", x, F2 + 3, 23, x + 1.4, F2 + 4.2, 24.6, orange, Enum.Material.SmoothPlastic)
	end
	glow(map, 48, F2 + 3, 23.2, 50, F2 + 4.2, 23.3)
	block(map, "Trestle", 46, F2, 29, 50, F2 + 2.6, 32, DARK_METAL, Enum.Material.Metal)
	block(map, "WreckPanel", 45.6, F2 + 2.6, 28.6, 50.4, F2 + 2.9, 32.4, HULL_GREY, Enum.Material.Metal)
	cosmetic(block(map, "WreckStripe", 45.6, F2 + 2.9, 30, 50.4, F2 + 2.95, 30.8, NAVY, Enum.Material.SmoothPlastic), map.geometry)
	cosmetic(block(map, "EvidenceBoard", 47, F2 + 3.5, 34.35, 51.5, F2 + 7.5, 34.45, Color3.fromRGB(200, 190, 160), Enum.Material.Cardboard), map.geometry)

	-- The tent: tool chests and crates along the corridors round the hull
	crate(map, 30, -15.2, B, 2.2, OLIVE)
	block(map, "ToolChest", 42, B, 13.6, 44.5, B + 3.6, 15.4, LIVERY_RED, Enum.Material.Metal)
	crate(map, 10.5, 12, B, 3)
end

-- Monitor on a desk: a screen on a little stand, facing `out` (±x or ±z)
local function monitor(map: MapBuilder.Builder, x: number, z: number, base: number, out: Vector3, width: number?)
	local w = (width or 1.6) / 2
	local across = Vector3.new(math.abs(out.Z), 0, math.abs(out.X))
	local centre = Vector3.new(x, base + 1.2, z)
	local half = across * w + Vector3.new(0, 0.55, 0) + Vector3.new(math.abs(out.X), 0, math.abs(out.Z)) * 0.08
	local min, max = centre - half, centre + half
	deco(map, "Monitor", min.X, min.Y, min.Z, max.X, max.Y, max.Z, BLACK, Enum.Material.SmoothPlastic)
	local face = centre + out * 0.1
	local inner = across * (w - 0.1) + Vector3.new(0, 0.45, 0) + Vector3.new(math.abs(out.X), 0, math.abs(out.Z)) * 0.02
	glow(map, face.X - inner.X, face.Y - inner.Y, face.Z - inner.Z, face.X + inner.X, face.Y + inner.Y, face.Z + inner.Z, if noise(x, z) > 0.5 then SCREEN else Color3.fromRGB(120, 230, 160))
	deco(map, "MonitorStand", x - 0.1, base, z - 0.1, x + 0.1, base + 0.7, z + 0.1, DARK_METAL, Enum.Material.Metal)
end

-- Office chair (looks only): seat, back, the post
local function chair(map: MapBuilder.Builder, x: number, z: number, base: number, facing: Vector3)
	deco(map, "Chair", x - 0.8, base + 1.4, z - 0.8, x + 0.8, base + 1.75, z + 0.8, BLACK, Enum.Material.Fabric)
	local back = Vector3.new(x, base, z) - facing * 0.75
	local across = Vector3.new(math.abs(facing.Z), 0, math.abs(facing.X)) * 0.75 + Vector3.new(math.abs(facing.X), 0, math.abs(facing.Z)) * 0.1
	deco(map, "Chair", back.X - across.X, base + 1.75, back.Z - across.Z, back.X + across.X, base + 3.9, back.Z + across.Z, BLACK, Enum.Material.Fabric)
	deco(map, "ChairPost", x - 0.12, base, z - 0.12, x + 0.12, base + 1.4, z + 0.12, DARK_METAL, Enum.Material.Metal)
end

-- The small things that make the rooms lived in (looks only unless it says so)
local function buildInteriors(map: MapBuilder.Builder)
	local trim = map:Folder("Trim")
	local paper = Color3.fromRGB(232, 230, 222)
	local bags = { Color3.fromRGB(150, 40, 44), Color3.fromRGB(40, 44, 50), Color3.fromRGB(60, 90, 130), Color3.fromRGB(190, 150, 60), Color3.fromRGB(86, 96, 70) }

	-- ECONOMY: the oxygen masks dropped and still dangling, a couple of bins burst open, bags and
	-- papers everywhere
	for i, x in { -33, -28, -23, -18 } do
		for _, side in { -1, 1 } do
			local z = side * (HULL - 2.9 - noise(x, side) * 0.8)
			local length = 1 + noise(side, x) * 0.8
			cable(map, "MaskTube", Vector3.new(x, SHOULDER - 2.45, z), Vector3.new(x + 0.2, SHOULDER - 2.45 - length, z), 0.06, Color3.fromRGB(220, 220, 214), Enum.Material.SmoothPlastic)
			deco(map, "OxygenMask", x - 0.05, SHOULDER - 2.85 - length, z - 0.2, x + 0.45, SHOULDER - 2.45 - length, z + 0.2, MASK_YELLOW, Enum.Material.SmoothPlastic)
		end
		if i % 2 == 0 then
			local side = if i == 2 then 1 else -1
			decoPart(map, "BinDoor", Vector3.new(3.4, 0.12, 1.8), CFrame.new(x, SHOULDER - 2.7, side * (HULL - 3)) * CFrame.Angles(side * 1.1, 0, 0), LINING, Enum.Material.SmoothPlastic)
		end
	end
	for i, l in { { -36, -5, 0.4 }, { -31, 4.6, 1.3 }, { -26.5, -1, 2.2 }, { -21, 5.4, 0.9 }, { -12, 3, 0.2 }, { 20, -10, 1.6 }, { 33, -2, 0.5 } } do
		deco(map, "Bag", l[1] - 0.9, B, l[2] - 0.6, l[1] + 0.9, B + 0.9, l[2] + 0.6, bags[i % #bags + 1], Enum.Material.Fabric).CFrame *= CFrame.Angles(0, l[3], 0)
	end
	for i, p in { { -37, 0 }, { -27, 5 }, { -22, -5 }, { -10, -4 }, { 18, 2 }, { 30, -3 } } do
		decoPart(map, "Paper", Vector3.new(0.9, 0.03, 1.2), CFrame.new(p[1], B + 0.06, p[2]) * CFrame.Angles(0, i * 1.3, 0), paper, Enum.Material.SmoothPlastic)
	end

	-- GALLEY: the galley units against the south wall (solid: knee-high cover), a cart pulled out,
	-- the trolley's handle and its spilled drawer
	block(map, "GalleyUnit", -15.5, B, -HULL + 0.5, -10, B + 3.4, -10.1, Color3.fromRGB(196, 198, 200), Enum.Material.Metal)
	deco(map, "Worktop", -15.5, B + 3.4, -HULL + 0.5, -10, B + 3.5, -10, STEEL, Enum.Material.DiamondPlate)
	for _, x in { -14.1, -12.6, -11.1 } do
		deco(map, "CartDoor", x - 0.05, B + 0.3, -10.12, x + 0.05, B + 3.2, -10.06, DARK_METAL, Enum.Material.Metal)
	end
	deco(map, "GalleyCabinet", -15.5, B + 5, -HULL + 0.5, -10, B + 6.7, -10.6, Color3.fromRGB(206, 208, 210), Enum.Material.Metal)
	glow(map, -13.6, B + 5.3, -10.66, -12.4, B + 5.6, -10.6, Color3.fromRGB(255, 170, 70))
	deco(map, "TrolleyHandle", -15.5, B + 3.1, 8.8, -13.9, B + 3.3, 9, DARK_METAL, Enum.Material.Metal)
	decoPart(map, "Drawer", Vector3.new(1.2, 0.5, 1.4), CFrame.new(-12.5, B + 0.25, 10.2) * CFrame.Angles(0, 0.5, 0.1), Color3.fromRGB(190, 192, 194), Enum.Material.Metal)

	-- BUSINESS: seats unbolted and stacked out of the way, a laptop on the folding table
	for i = 0, 1 do
		decoPart(map, "Seats", Vector3.new(2, 1.4, 2.4), CFrame.new(15.6, B + 0.7 + i * 1.4, -10.2) * CFrame.Angles(0, i * 0.3, 0), SEAT, Enum.Material.Fabric)
	end
	deco(map, "Laptop", 15.6, B + 2.8, 8.4, 16.8, B + 2.86, 9.4, BLACK, Enum.Material.SmoothPlastic)
	glow(map, 15.6, B + 2.86, 9.36, 16.8, B + 3.6, 9.42)

	-- FIRST CLASS: wood caps on the suites, their screens, bottles on the bar
	for _, s in { { 28, -HULL + 0.5 }, { 28, 7 }, { 37, 7 } } do
		deco(map, "SuiteCap", s[1] - 0.05, B + 3.8, s[2] - 0.05, s[1] + 5.05, B + 3.95, s[2] + 4.55, Color3.fromRGB(176, 140, 104), Enum.Material.Wood)
		local face = if s[2] < 0 then s[2] + 4.55 else s[2] - 0.05
		glow(map, s[1] + 1.5, B + 2.2, face - 0.03, s[1] + 3.5, B + 3.3, face + 0.03, Color3.fromRGB(90, 140, 200))
	end
	deco(map, "BarTop", 38.9, B + 3.6, -6.6, 42.6, B + 3.7, -3.4, Color3.fromRGB(220, 218, 210), Enum.Material.Marble)
	for i, c in { Color3.fromRGB(60, 110, 60), Color3.fromRGB(120, 60, 30), Color3.fromRGB(200, 200, 190) } do
		cosmetic(drum(map, "Bottle", 39.6 + i * 0.7, -4.2 - (i % 2) * 0.6, B + 3.7, 0.9, 0.3, c, Enum.Material.Glass), map.geometry)
	end

	-- COCKPIT: six displays, the yokes, throttles on the pedestal, side consoles, the seats' rests,
	-- the overhead panel's lights, breaker panels on the bulkhead behind
	for _, z in { -8.7, 6.3 } do
		glow(map, 53.9, B + 1.6, z, 54, B + 3.2, z + 2.4, Color3.fromRGB(110, 220, 140))
	end
	for _, z in { -4.5, 4.5 } do
		cable(map, "YokeColumn", Vector3.new(53.9, B, z), Vector3.new(53.1, B + 2.5, z), 0.3, BLACK, Enum.Material.SmoothPlastic)
		deco(map, "Yoke", 52.9, B + 2.45, z - 0.8, 53.15, B + 2.65, z + 0.8, BLACK, Enum.Material.SmoothPlastic)
		for _, d in { -0.8, 0.8 } do
			deco(map, "YokeGrip", 52.9, B + 2.45, z + d - 0.12, 53.15, B + 3.2, z + d + 0.12, BLACK, Enum.Material.SmoothPlastic)
		end
		deco(map, "Headrest", 49.42, B + 3.7, z - 1.3, 50.06, B + 4.7, z + 1.3, Color3.fromRGB(80, 80, 86), Enum.Material.Fabric)
		local console = if z < 0 then -HULL + 0.5 else HULL - 1.8
		deco(map, "SideConsole", 48, B, console, 53.6, B + 2.4, console + 1.3, Color3.fromRGB(54, 56, 62), Enum.Material.SmoothPlastic)
		glow(map, 51, B + 2.4, console + 0.3, 52.4, B + 2.46, console + 1, Color3.fromRGB(255, 190, 90))
	end
	for _, z in { -0.5, 0.3 } do
		cable(map, "Throttle", Vector3.new(53, B + 2.6, z + 0.1), Vector3.new(52.7, B + 3.3, z + 0.1), 0.18, Color3.fromRGB(200, 200, 200), Enum.Material.SmoothPlastic)
	end
	glow(map, 52.3, B + 2.6, -0.8, 53.6, B + 2.66, 0.8, Color3.fromRGB(110, 220, 140))
	glow(map, 51.3, F2 - 2.26, -2.6, 53.7, F2 - 2.2, 2.6, Color3.fromRGB(255, 210, 120))
	for _, z in { -11, 8.4 } do
		deco(map, "BreakerPanel", COCKPIT + 0.5, B + 2, z, COCKPIT + 0.62, B + 8, z + 2.6, Color3.fromRGB(40, 42, 46), Enum.Material.SmoothPlastic)
	end

	-- HOLDS: roller tracks in the cargo deck, the hull's frames down the walls, a cargo net
	for _, z in { -6, -2, 2, 6 } do
		deco(map, "RollerTrack", MID_W, BF, z - 0.2, MID_E, BF + 0.06, z + 0.2, STEEL, Enum.Material.Metal)
	end
	for _, side in { -1, 1 } do
		local doors = if side < 0 then { { -33, -28 }, { -15, -10 } } else { { -36, -31 }, { -14, -6 } }
		for x = MID_W + 2, MID_E - 2, 4 do
			local clear = true
			for _, d in doors do
				if x > d[1] - 0.8 and x < d[2] + 0.8 then
					clear = false
				end
			end
			if clear and x ~= -20 then
				deco(map, "Frame", x - 0.2, BF, side * (HULL - 0.5), x + 0.2, B - 1, side * (HULL - 0.85), DARK_METAL, Enum.Material.Metal, trim)
			end
		end
	end
	deco(map, "CargoNet", -27, BF + 0.5, -HULL + 0.42, -21, BF + 7, -HULL + 0.5, Color3.fromRGB(60, 62, 56), Enum.Material.Fabric, trim)

	-- ICE STORE / VAULT: cores racked in tubes, frost creeping up the concrete
	for _, r in { { -35.75, -36.5, -24.5 }, { -8.25, -26.5, -21.5 } } do
		for i = 0, 2 do
			decoTube(map, "CoreTube", r[3] - r[2], 0.6, CFrame.new(r[1], BF + 1.5 + i * 2, (r[2] + r[3]) / 2) * CFrame.Angles(0, math.pi / 2, 0), ICE, Enum.Material.Glass).Transparency = 0.3
		end
	end
	for _, f in { { -23.5, -37.5, -4.5, -37.4, 2.2 }, { -37.5, -37.5, -37.4, -12.5, 1.6 } } do
		deco(map, "Frost", f[1], BF, f[2], f[3], BF + f[5], f[4], Color3.fromRGB(210, 226, 236), Enum.Material.Ice)
	end

	-- DRILL LAB: cores laid out on the logging table, a monitor; MEDBAY: pillows and blankets, an
	-- IV stand, the curtain between the cots
	deco(map, "CoreBox", -28.6, B + 3, -31.6, -25.4, B + 3.4, -28.4, OLIVE, Enum.Material.Wood)
	for i = 0, 2 do
		decoTube(map, "IceCore", 2.9, 0.55, CFrame.new(-27, B + 3.6, -31 + i * 0.9), ICE, Enum.Material.Glacier)
	end
	for _, x in { -21.5, -10 } do
		deco(map, "Pillow", x + 0.4, B + 2.2, -39.2, x + 3.1, B + 2.6, -38.2, WHITE, Enum.Material.Fabric)
		deco(map, "Blanket", x - 0.05, B + 2.2, -37.6, x + 3.55, B + 2.3, -35, Color3.fromRGB(70, 96, 120), Enum.Material.Fabric)
	end
	deco(map, "IVStand", -17, B, -38.6, -16.85, B + 6.4, -38.45, STEEL, Enum.Material.Metal)
	deco(map, "IVBag", -17.3, B + 5.2, -38.8, -16.6, B + 6.2, -38.6, Color3.fromRGB(200, 220, 230), Enum.Material.Glass)
	deco(map, "CurtainRail", -14.2, B + 9, -40, -14, B + 9.1, -34, STEEL, Enum.Material.Metal)
	deco(map, "Curtain", -14.15, B + 1.6, -40, -14.05, B + 9, -36.5, Color3.fromRGB(150, 190, 180), Enum.Material.Fabric)

	-- COMMS: radios on the desk, a chair, the map on the wall; CONTROL: monitors and chairs at the
	-- consoles, the screen wall's bezel; SERVER ROOM: cable trays over the racks
	for i = 0, 1 do
		deco(map, "Radio", 14.6, B + 3 + i * 1.1, -37.6 + i * 0.4, 16, B + 4 + i * 1.1, -35.4 + i * 0.4, Color3.fromRGB(70, 76, 66), Enum.Material.Metal)
		glow(map, 16, B + 3.3 + i * 1.1, -37 + i * 0.4, 16.06, B + 3.6 + i * 1.1, -36 + i * 0.4, Color3.fromRGB(255, 170, 60))
	end
	chair(map, 18.6, -34, B, -Vector3.xAxis)
	deco(map, "WallMap", 21.6, B + 4, -24.62, 25.8, B + 8.5, -24.5, Color3.fromRGB(196, 206, 186), Enum.Material.Cardboard, trim)
	for _, d in { { 32, 35 }, { 41, 44 } } do
		deco(map, "ScreenBezel", d[1] + 0.1, B + 2.9, -36.6, d[2] - 0.1, B + 4.8, -36.5, BLACK, Enum.Material.SmoothPlastic)
		chair(map, (d[1] + d[2]) / 2, -32.4, B, -Vector3.zAxis)
	end
	monitor(map, 36, -25.2, B + 3, -Vector3.zAxis, 1.3)
	monitor(map, 40, -25.2, B + 3, -Vector3.zAxis, 1.3)
	deco(map, "ScreenBezel", 45.45, B + 3.7, -39.3, 45.55, B + 9.3, -30.7, BLACK, Enum.Material.SmoothPlastic)
	deco(map, "CableTray", 47, F2 - 2, -39, 55.5, F2 - 1.8, -38, MESH, Enum.Material.DiamondPlate)
	deco(map, "CableTray", 54, F2 - 2, -37, 55, F2 - 1.8, -26, MESH, Enum.Material.DiamondPlate)
	for _, r in { { 47.5, -37.5 }, { 52.5, -37.5 } } do
		glow(map, r[1] + 0.3, B + 2.5, r[2] - 0.05, r[1] + 2.5, B + 2.65, r[2] + 0.05, Color3.fromRGB(255, 90, 70))
	end

	-- DECON: shower heads, hazmat suits hanging on the rack, boots under it; LAB HALL: an
	-- extinguisher, the notice board
	for _, z in { 35.25, 38.25 } do
		deco(map, "ShowerHead", 15.6, B + 7, z - 0.3, 16.4, B + 7.2, z + 0.3, STEEL, Enum.Material.Metal)
		deco(map, "Drain", 15.5, B, z - 0.5, 16.5, B + 0.06, z + 0.5, DARK_METAL, Enum.Material.DiamondPlate)
	end
	for i = 0, 2 do
		local x = 22.9 + i * 1.05
		deco(map, "HazmatSuit", x - 0.4, B + 1.6, 37.6, x + 0.4, B + 5.4, 38.4, SAFETY_YELLOW, Enum.Material.Fabric)
		deco(map, "Visor", x - 0.25, B + 4.6, 37.55, x + 0.25, B + 5.1, 37.6, Color3.fromRGB(40, 60, 70), Enum.Material.Glass)
	end
	deco(map, "Boots", 22.5, B, 36.6, 25.5, B + 0.8, 37.6, BLACK, Enum.Material.Rubber)
	cosmetic(drum(map, "Extinguisher", 33.1, 23, B + 2, 1.6, 0.5, LIVERY_RED, Enum.Material.Metal), map.geometry)
	deco(map, "NoticeBoard", 33.38, B + 4, 32, 33.5, B + 7, 36, Color3.fromRGB(176, 140, 100), Enum.Material.Cardboard, trim)

	-- SAMPLE STORE: sample boxes on the shelves, a biohazard drum
	for i = 0, 2 do
		deco(map, "SampleBox", 46.4 + i * 1.8, B + 2 + (i % 2) * 2.4, 24, 47.8 + i * 1.8, B + 3 + (i % 2) * 2.4, 24.8, if i == 1 then SAFETY_ORANGE else WHITE, Enum.Material.SmoothPlastic)
	end
	cosmetic(drum(map, "BioDrum", 45, 30, B, 2.6, 2, SAFETY_YELLOW, Enum.Material.Metal), map.geometry)

	-- BIO LAB: monitors and a microscope on the bench, racks of tubes, the whiteboard, an upright
	-- sample freezer in the corner (solid)
	monitor(map, 15.6, 27.5, F2 + 3, Vector3.xAxis)
	monitor(map, 15.6, 36.5, F2 + 3, Vector3.xAxis)
	deco(map, "Microscope", 15.2, F2 + 3, 28.8, 16.4, F2 + 3.4, 29.8, WHITE, Enum.Material.SmoothPlastic)
	deco(map, "Microscope", 15.4, F2 + 3.4, 29.1, 15.8, F2 + 4.6, 29.5, BLACK, Enum.Material.SmoothPlastic)
	deco(map, "TubeRack", 15.2, F2 + 3, 34.6, 16.6, F2 + 3.6, 35.6, Color3.fromRGB(120, 180, 220), Enum.Material.Glass)
	deco(map, "Whiteboard", 29.38, F2 + 3, 32, 29.5, F2 + 6.5, 37.6, Color3.fromRGB(236, 236, 230), Enum.Material.SmoothPlastic, trim)
	deco(map, "Writing", 29.36, F2 + 4.5, 33, 29.38, F2 + 5.6, 36.2, Color3.fromRGB(40, 70, 140), Enum.Material.SmoothPlastic, trim)
	block(map, "Freezer", 27.4, F2, 37.9, 29.4, F2 + 7, 39.5, Color3.fromRGB(226, 232, 236), Enum.Material.Metal)
	glow(map, 27.7, F2 + 6, 37.84, 29.1, F2 + 6.3, 37.9, Color3.fromRGB(120, 200, 255))

	-- RECORDER LAB: a monitor and a laptop on the benches, photos and red string on the evidence
	-- board, evidence bags
	monitor(map, 40.3, 22.85, F2 + 3, Vector3.zAxis, 1.4)
	deco(map, "Laptop", 47.6, F2 + 3, 23.4, 49, F2 + 3.06, 24.4, BLACK, Enum.Material.SmoothPlastic)
	for i, p in { { 47.6, 6.4 }, { 49.2, 5.5 }, { 50.4, 6.6 } } do
		deco(map, "Photo", p[1], F2 + p[2] - 0.5, 34.3, p[1] + 0.8, F2 + p[2] + 0.1, 34.33, if i == 2 then Color3.fromRGB(140, 150, 160) else paper, Enum.Material.SmoothPlastic)
	end
	cable(map, "String", Vector3.new(48, F2 + 6.2, 34.29), Vector3.new(49.6, F2 + 5.2, 34.29), 0.04, LIVERY_RED, Enum.Material.SmoothPlastic)
	cable(map, "String", Vector3.new(49.6, F2 + 5.2, 34.29), Vector3.new(50.8, F2 + 6.4, 34.29), 0.04, LIVERY_RED, Enum.Material.SmoothPlastic)
	for i = 0, 1 do
		decoPart(map, "EvidenceBag", Vector3.new(1, 0.15, 1.3), CFrame.new(39 + i * 1.4, F2 + 3.08, 24) * CFrame.Angles(0, 0.4 * i, 0), Color3.fromRGB(200, 210, 214), Enum.Material.Glass)
	end
end

-- Pine: a trunk and tiers of boughs with snow on them. In the Yard folder (trees aren't a roof).
local function pine(map: MapBuilder.Builder, x: number, z: number, height: number)
	local yard = map:Folder("Yard")
	drum(map, "Trunk", x, z, GROUND, height * 0.45, 1.6, BARK, Enum.Material.Wood).Parent = yard
	for i = 0, 2 do
		local bottom = GROUND + height * (0.18 + 0.24 * i)
		local thick = height * 0.15
		local width = height * (0.44 - 0.11 * i)
		drum(map, "Boughs", x, z, bottom, thick, width, PINE, Enum.Material.Grass).Parent = yard
		drum(map, "BoughSnow", x, z, bottom + thick, 0.5, width * 0.75, SNOW, Enum.Material.Snow).Parent = yard
	end
end

-- Snowbank: a long ridge of snow (two wedges back to back), along x or along z. Low cover you
-- can crouch behind or walk over.
local function snowbank(map: MapBuilder.Builder, x: number, z: number, length: number, alongX: boolean, height: number)
	local half = height * 1.1 -- how far each slope runs (just under 45°: you can walk up it)
	for _, side in { -1, 1 } do
		local cframe = if alongX
			then CFrame.new(x, GROUND + height / 2, z - side * half / 2) * CFrame.Angles(0, if side > 0 then 0 else math.pi, 0)
			else CFrame.new(x - side * half / 2, GROUND + height / 2, z) * CFrame.Angles(0, side * math.pi / 2, 0)
		wedge(map, "Snowbank", Vector3.new(length, height, half), cframe, SNOW, Enum.Material.Snow)
	end
end

-- Concrete jersey barrier, 6 long
local function barrier(map: MapBuilder.Builder, x: number, z: number, alongX: boolean)
	local hx, hz = if alongX then 3 else 0.9, if alongX then 0.9 else 3
	local tx, tz = if alongX then 3 else 0.4, if alongX then 0.4 else 3
	block(map, "Barrier", x - hx, GROUND, z - hz, x + hx, GROUND + 1.2, z + hz, CONCRETE, Enum.Material.Concrete)
	block(map, "Barrier", x - tx, GROUND + 1.2, z - tz, x + tx, GROUND + 3.2, z + tz, CONCRETE, Enum.Material.Concrete)
	-- A reflective band round the top, snow along it (looks only)
	local rx, rz = if alongX then 2.6 else 0.44, if alongX then 0.44 else 2.6
	deco(map, "Reflector", x - rx, GROUND + 2.4, z - rz, x + rx, GROUND + 2.75, z + rz, REFLECTOR, Enum.Material.SmoothPlastic)
	snowCap(map, x - tx + 0.05, z - tz + 0.05, x + tx - 0.05, z + tz - 0.05, GROUND + 3.2, 0.25)
end

-- Floodlight tower at (x, z), its lamps tipped down at `target`
local function floodlight(map: MapBuilder.Builder, x: number, z: number, target: Vector3)
	local yard = map:Folder("Yard")
	block(map, "MastFoot", x - 1.2, GROUND, z - 1.2, x + 1.2, GROUND + 0.8, z + 1.2, CONCRETE, Enum.Material.Concrete).Parent = yard
	block(map, "Mast", x - 0.35, GROUND, z - 0.35, x + 0.35, GROUND + 22, z + 0.35, DARK_METAL, Enum.Material.Metal).Parent = yard
	local head = Vector3.new(x, GROUND + 22.6, z)
	local frame = CFrame.lookAt(head, Vector3.new(target.X, head.Y, target.Z)) * CFrame.Angles(-0.4, 0, 0)
	map:Part("LampBar", Vector3.new(6.4, 0.5, 0.5), frame * CFrame.new(0, 0, 0.6), DARK_METAL, Enum.Material.Metal).Parent = yard
	-- Four lamp heads on the bar, lenses glowing; one light for the lot (no shadows: cheap)
	for i, d in { { -1.6, 0.85 }, { 1.6, 0.85 }, { -1.6, -0.85 }, { 1.6, -0.85 } } do
		decoPart(map, "LampHead", Vector3.new(2.8, 1.5, 0.9), frame * CFrame.new(d[1], d[2], 0), Color3.fromRGB(52, 56, 62), Enum.Material.Metal, yard).CastShadow = true
		local lens = decoPart(map, "Light", Vector3.new(2.4, 1.15, 0.1), frame * CFrame.new(d[1], d[2], -0.48), Color3.fromRGB(240, 246, 255), Enum.Material.Neon, yard)
		if i == 1 then
			local light = Instance.new("SpotLight")
			light.Face = Enum.NormalId.Front
			light.Range = 60
			light.Angle = 70
			light.Brightness = 2.2
			light.Color = Color3.fromRGB(230, 240, 255)
			light.Shadows = false
			light.Parent = lens
		end
	end
	-- The ballast box at its foot and the cable up the mast
	deco(map, "Ballast", x + 0.35, GROUND + 3, z - 0.6, x + 1.1, GROUND + 4.6, z + 0.6, SAFETY_YELLOW, Enum.Material.Metal, yard)
	cable(map, "Cable", Vector3.new(x + 0.45, GROUND + 4.6, z), Vector3.new(x + 0.45, GROUND + 22, z), 0.15, CABLE, Enum.Material.Rubber, yard)
end

-- A piece of debris on the snow: `size` placed by `frame` (put in the Yard folder)
local function debris(map: MapBuilder.Builder, name: string, size: Vector3, frame: CFrame, color: Color3, material: Enum.Material): Part
	local part = map:Part(name, size, frame, color, material)
	part.Parent = map:Folder("Yard")
	return part
end

local function buildOutside(map: MapBuilder.Builder)
	-- Ground: snow (not under the buildings, the dig or the fuselage), the ploughed road in from the
	-- checkpoint, a gravel track up to the site
	local footprints = {
		{ -44, 12, 2, 38 }, -- the pit
		{ MID_W - 0.5, -12.5, MID_E + 0.5, 12.5 }, -- the mid section's hold
		{ -40.5, -40.5, -3.5, -12.5 }, -- the module, the vault under the alley
		{ TENT_W, -TENT_R, TENT_E, TENT_R },
		{ TENT_E, -12.5, FWD_E + 0.5, 12.5 },
		{ 13.5, -40.5, 56.5, -23.5 }, -- the trailers
		{ 13.5, 21.5, 52.5, 40.5 }, -- the lab block
	}
	map:FloorWithHoles("Snow", -150, -130, 150, 130, footprints, GROUND, 0.4, SNOW, Enum.Material.Snow)
	map:Floor("Road", -8, -130, 8, -92, 0.3, 0.2, ASPHALT, Enum.Material.Asphalt)
	map:Floor("Track", -4, -92, 10, -41, 0.28, 0.2, GRAVEL, Enum.Material.Pebble)

	-- THE SCAR: the gouge the plane ploughed coming in from the west, dark earth and burnt fuel
	-- between berms of snow it shoved aside, and scorch where the pieces came to rest
	for _, s in { { -150, -110, 6, 24, 0.03 }, { -114, -82, 4, 26, -0.03 }, { -86, -60, 5, 22, 0.06 } } do
		map:Part("Scar", Vector3.new(s[2] - s[1], 0.1, s[4]), CFrame.new((s[1] + s[2]) / 2, GROUND + 0.04, s[3]) * CFrame.Angles(0, s[5], 0), SCAR, Enum.Material.Ground)
	end
	for _, b in { { -132, -9, 34 }, { -100, -10, 26 }, { -132, 21, 34 }, { -100, 19.5, 26 }, { -75, -14, 12 }, { -74, 24, 12 } } do
		snowbank(map, b[1], b[2], b[3], true, 3.4)
	end
	for _, s in { { 5, 0, 5, 18, 0.15 }, { -43, -4, 5, 16, 0.4 }, { 66, 2, 9, 20, 0.1 }, { -62, 50, 9, 9, 0.9 }, { -24, 52, 10, 14, 0.3 } } do
		map:Part("Scorch", Vector3.new(s[3], 0.1, s[4]), CFrame.new(s[1], GROUND + 0.05, s[2]) * CFrame.Angles(0, s[5], 0), SOOT, Enum.Material.Ground)
	end
	-- The snow the nose bulldozed up in front of it
	snowbank(map, 72, 0, 30, false, 4.5)
	snowbank(map, 69, 18, 12, false, 2.6)

	-- THE TORN WING out in the north field: tip up, its root dug in and burnt black
	local wing = WING
	for i, seg in { { -28, -10, 14 }, { -10, 8, 10.5 }, { 8, 26, 7 } } do
		local mid = (seg[1] + seg[2]) / 2
		local leading = 7 - 0.22 * (mid + 28)
		debris(map, "Wing", Vector3.new(seg[2] - seg[1] + 0.4, 1.8 - 0.3 * i, seg[3]), wing * CFrame.new(mid, 0, leading - seg[3] / 2), Color3.fromRGB(196, 200, 206), Enum.Material.Metal)
	end
	debris(map, "Winglet", Vector3.new(1, 5, 4.5), wing * CFrame.new(26.4, 2.4, -6.8), NAVY, Enum.Material.SmoothPlastic)
	debris(map, "Pylon", Vector3.new(4, 2.4, 6), wing * CFrame.new(-16, -1.4, 1), Color3.fromRGB(150, 154, 160), Enum.Material.Metal)
	cosmetic(map:Part("Soot", Vector3.new(5, 0.1, 13), wing * CFrame.new(-25.5, 0.95, 0.5), SOOT, Enum.Material.Metal), map:Folder("Yard"))
	-- An engine pod that came off, half buried
	local pod = POD
	tube(map, "EngineNacelle", 12, 7, pod, Color3.fromRGB(186, 190, 196), Enum.Material.Metal).Parent = map:Folder("Yard")
	cosmetic(tube(map, "Intake", 0.3, 6, pod * CFrame.new(6.05, 0, 0), BLACK, Enum.Material.Metal), map:Folder("Yard"))
	tube(map, "Exhaust", 3, 4.4, pod * CFrame.new(-7, 0, 0), DARK_METAL, Enum.Material.Metal).Parent = map:Folder("Yard")
	-- A main landing gear leg, wheels and all, by the nose
	debris(map, "GearLeg", Vector3.new(9, 1.2, 1.2), CFrame.new(71, GROUND + 3.2, -16) * CFrame.Angles(0, 0.5, 0.4), STEEL, Enum.Material.Metal).Shape = Enum.PartType.Cylinder
	for _, w in { { 66, -21.6 }, { 66, -18.4 }, { 69.4, -21.6 }, { 69.4, -18.4 } } do
		tube(map, "Wheel", 1.4, 3.6, CFrame.new(w[1], GROUND + 1.8, w[2]) * CFrame.Angles(0, math.pi / 2, 0), BLACK, Enum.Material.Rubber).Parent = map:Folder("Yard")
	end
	-- Seats, luggage and skin torn off the hull, strewn along the way it came
	for _, s in { { -96, -12, 0.4, 0 }, { -118, 16, 1.2, 0.3 }, { -70, 30, 2, 1.4 }, { 26, 58, 0.7, 0 }, { -14, -58, 2.6, 0 }, { 84, -6, 1.1, 0.2 } } do
		local frame = CFrame.new(s[1], GROUND + 0.75, s[2]) * CFrame.Angles(s[4], s[3], 0)
		debris(map, "Seats", Vector3.new(2, 1.5, 5), frame, SEAT, Enum.Material.Fabric)
		debris(map, "SeatBack", Vector3.new(0.5, 3.9, 5), frame * CFrame.new(-1.25, 1.2, 0), SEAT, Enum.Material.Fabric)
	end
	local bags = { Color3.fromRGB(150, 40, 44), Color3.fromRGB(40, 44, 50), Color3.fromRGB(60, 90, 130), Color3.fromRGB(190, 150, 60) }
	for i, l in { { 5, 9 }, { 6, -6 }, { -92, 4 }, { -104, -2 }, { -60, 6 }, { 30, 52 }, { 76, 10 }, { -20, 50 } } do
		debris(map, "Suitcase", Vector3.new(2.4, 1, 1.6), CFrame.new(l[1], GROUND + 0.5, l[2]) * CFrame.Angles(0, i * 0.7, 0), bags[i % 4 + 1], Enum.Material.Fabric)
	end
	for _, p in { { -58, 30, 0.6, 0.25 }, { -124, -16, 2.1, 0.15 }, { 80, -28, 1.2, 0.3 }, { -30, -56, 0.3, 0.2 }, { 40, 70, 2.6, 0.35 } } do
		local frame = CFrame.new(p[1], GROUND + 1, p[2]) * CFrame.Angles(0, p[3], p[4])
		debris(map, "HullPanel", Vector3.new(8, 0.4, 5), frame, HULL_GREY, Enum.Material.Metal)
		cosmetic(map:Part("Stripe", Vector3.new(8, 0.05, 0.8), frame * CFrame.new(0, 0.22, 1), NAVY, Enum.Material.SmoothPlastic), map:Folder("Yard"))
	end

	-- GENERATOR YARD (south-west): generators, fuel tanks on saddles, drums, a cable drum
	for _, z in { -38.5, -31.5 } do
		block(map, "Generator", -55, GROUND, z, -47, GROUND + 5, z + 4.5, OLIVE, Enum.Material.Metal)
		drum(map, "Exhaust", -48.2, z + 1, GROUND + 5, 3, 0.7, DARK_METAL, Enum.Material.Metal)
	end
	for _, z in { -36, -28 } do
		tube(map, "FuelTank", 12, 4.6, CFrame.new(-64, GROUND + 3, z), WHITE, Enum.Material.Metal)
		for _, x in { -68, -60 } do
			block(map, "Saddle", x - 0.6, GROUND, z - 2, x + 0.6, GROUND + 1.6, z + 2, DARK_METAL, Enum.Material.Metal)
		end
	end
	for _, d in { { -45, -38 }, { -45, -35.5 }, { -42.5, -38 } } do
		drum(map, "FuelDrum", d[1], d[2], GROUND, 3.2, 2.2, Color3.fromRGB(170, 40, 30), Enum.Material.Metal)
	end
	tube(map, "CableDrum", 2, 4, CFrame.new(-52, GROUND + 2, -22) * CFrame.Angles(0, math.pi / 2, 0), Color3.fromRGB(120, 90, 60), Enum.Material.Wood)
	-- A snowcat parked by the pit ramp
	block(map, "Snowcat", -58, GROUND + 1.6, 20, -50, GROUND + 4.4, 26, SAFETY_ORANGE, Enum.Material.Metal)
	block(map, "SnowcatCab", -55, GROUND + 4.4, 20.5, -50.5, GROUND + 7.6, 25.5, Color3.fromRGB(40, 46, 56), Enum.Material.Glass)
	for _, z in { 19.4, 25 } do
		block(map, "Track", -58.5, GROUND, z, -49.5, GROUND + 2, z + 1.6, BLACK, Enum.Material.Rubber)
	end

	-- Cover: jersey barriers and crates round the site
	for _, b in { { -2, -48, true }, { 10, -58, true }, { -50, -48, true }, { 62, -6, false }, { 62, 8, false }, { -60, 8, false }, { 30, 48, true }, { -8, 46, true }, { 4, -26, false }, { -20, -48, true } } do
		barrier(map, b[1], b[2], b[3])
	end
	for _, c in { { 8, -20, 3.4 }, { 10.5, -22.4, 2.4 }, { -46, -16, 3 }, { 58, 30, 3.4 }, { 46, 46, 3 }, { -2, 42, 3 } } do
		crate(map, c[1], c[2], GROUND, c[3], OLIVE, true)
	end

	-- Floodlights over the site
	floodlight(map, -52, -18, Vector3.new(-20, 0, -10))
	floodlight(map, 4, -34, Vector3.new(10, 0, 0))
	floodlight(map, 60, 22, Vector3.new(30, 0, 0))
	floodlight(map, -50, 44, Vector3.new(-20, 0, 25))
	floodlight(map, -70, 24, Vector3.new(-48, 0, 2)) -- (on the tail)
	floodlight(map, 82, 18, Vector3.new(56, 0, 0)) -- (on the nose)

	-- Helipad (north-east): the pad, its H, edge lights, a windsock
	local pad = drum(map, "Helipad", 66, 64, GROUND - 0.1, 0.35, 28, CONCRETE, Enum.Material.Concrete)
	pad.Parent = map:Folder("Yard")
	local top = GROUND + 0.27
	for _, h in { { 61, 58, 62.4, 70 }, { 69.6, 58, 71, 70 }, { 62.4, 63.3, 69.6, 64.7 } } do
		cosmetic(block(map, "HelipadH", h[1], top, h[2], h[3], top + 0.04, h[4], SAFETY_YELLOW, Enum.Material.SmoothPlastic), map.geometry)
	end
	for i = 0, 7 do
		local a = i * math.pi / 4
		glow(map, 66 + math.cos(a) * 13 - 0.3, top, 64 + math.sin(a) * 13 - 0.3, 66 + math.cos(a) * 13 + 0.3, top + 0.3, 64 + math.sin(a) * 13 + 0.3, Color3.fromRGB(80, 255, 120))
	end
	block(map, "WindsockPole", 83.8, GROUND, 48.8, 84.2, GROUND + 10, 49.2, DARK_METAL, Enum.Material.Metal)
	cosmetic(tube(map, "Windsock", 4, 1.2, CFrame.new(86, GROUND + 9.4, 49) * CFrame.Angles(0, 0, -0.3), SAFETY_ORANGE, Enum.Material.Fabric), map.geometry)

	-- On the command trailers' roof: a satellite dish, a radio mast, the air conditioner
	drum(map, "DishPost", 20, -36, F2, 3, 0.6, DARK_METAL, Enum.Material.Metal)
	tube(map, "Dish", 0.4, 6, CFrame.new(20, F2 + 4.6, -36) * CFrame.Angles(0, math.rad(40), math.rad(55)), WHITE, Enum.Material.SmoothPlastic)
	block(map, "RadioMast", 54.6, F2, -25.4, 55.2, F2 + 14, -24.8, DARK_METAL, Enum.Material.Metal)
	block(map, "AirCon", 24, F2, -30, 29, F2 + 3, -26, Color3.fromRGB(196, 198, 194), Enum.Material.Metal)

	-- THE PERIMETER: chain-link (see and shoot through it) on posts, gaps to get through, the
	-- checkpoint gate on the road (south)
	local function fence(x1: number, z1: number, x2: number, z2: number, gaps: { { number } })
		local alongX = z1 == z2
		local start = if alongX then x1 else z1
		local openings = {}
		for _, gap in gaps do
			table.insert(openings, { from = gap[1] - start, to = gap[2] - start, top = 9 })
		end
		for _, piece in map:Wall("Fence", x1, z1, x2, z2, GROUND, 7.6, openings, MESH, Enum.Material.DiamondPlate, 0.3) do
			piece.Transparency = 0.6
			piece:SetAttribute("Breakable", "Soft")
		end
		local length = if alongX then x2 - x1 else z2 - z1
		for d = 0, length, 16 do
			local at = start + d
			local inGap = false
			for _, gap in gaps do
				if at > gap[1] - 0.5 and at < gap[2] + 0.5 then
					inGap = true
				end
			end
			if not inGap then
				local x, z = if alongX then at else x1, if alongX then z1 else at
				block(map, "FencePost", x - 0.2, GROUND, z - 0.2, x + 0.2, GROUND + 8.2, z + 0.2, DARK_METAL, Enum.Material.Metal)
			end
		end
	end
	fence(-112, -92, 112, -92, { { -8, 8 }, { -70, -62 }, { 56, 64 } })
	fence(-112, 88, 112, 88, { { -60, -52 }, { 4, 12 }, { 70, 78 } })
	fence(-112, -92, -112, 88, { { -60, -52 }, { -10, 6 }, { 40, 48 } }) -- (the scar comes through)
	fence(112, -92, 112, 88, { { -30, -22 }, { 20, 28 } })
	-- Checkpoint: the guard booth, the boom (up), a sign, barriers zig-zagging the road
	block(map, "GuardBooth", 11, GROUND, -102, 17, GROUND + 7.6, -96, PANEL, Enum.Material.SmoothPlastic)
	local band = block(map, "BoothWindows", 10.9, GROUND + 3.6, -102.1, 17.1, GROUND + 5.8, -95.9, Color3.fromRGB(40, 46, 56), Enum.Material.Glass)
	cosmetic(band, map.geometry)
	block(map, "BoothRoof", 10.4, GROUND + 7.6, -102.6, 17.6, GROUND + 8.2, -95.4, DARK_METAL, Enum.Material.Metal)
	block(map, "BoomPost", 8.6, GROUND, -93.6, 9.6, GROUND + 3.6, -92.6, DARK_METAL, Enum.Material.Metal)
	local boom = math.rad(110)
	local pivot = Vector3.new(9.1, GROUND + 3.4, -93.1)
	local reach = Vector3.new(math.cos(boom), math.sin(boom), 0)
	map:Part("Boom", Vector3.new(16, 0.5, 0.5), CFrame.new(pivot + reach * 8) * CFrame.Angles(0, 0, boom), WHITE, Enum.Material.SmoothPlastic)
	cosmetic(map:Part("BoomBand", Vector3.new(3, 0.55, 0.55), CFrame.new(pivot + reach * 8) * CFrame.Angles(0, 0, boom), LIVERY_RED, Enum.Material.SmoothPlastic), map.geometry)
	for _, x in { -21.5, -10.5 } do
		block(map, "SignPost", x - 0.2, GROUND, -92.9, x + 0.2, GROUND + 8.6, -92.5, DARK_METAL, Enum.Material.Metal)
	end
	wallSign(map, "FLIGHT 9 RECOVERY SITE", Vector3.new(-16, GROUND + 7, -92.9), -Vector3.zAxis, Vector2.new(12, 1.8), NAVY, WHITE)
	wallSign(map, "RESTRICTED AREA · NO ENTRY WITHOUT A PASS", Vector3.new(-16, GROUND + 5, -92.9), -Vector3.zAxis, Vector2.new(12, 1.4), SAFETY_YELLOW, BLACK)
	barrier(map, -3.5, -100, true)
	barrier(map, 3.5, -106, true)
	-- Signs on the buildings
	wallSign(map, "COMMAND", Vector3.new(22, GROUND + 10.4, -40.5), -Vector3.zAxis, Vector2.new(8, 1.6), DARK_METAL, WHITE)
	wallSign(map, "LAB 2 · BIOHAZARD", Vector3.new(44, F2 + 9, 21.5), -Vector3.zAxis, Vector2.new(10, 1.6), SAFETY_YELLOW, BLACK)
	wallSign(map, "CORE LAB", Vector3.new(-23, GROUND + 10.4, -40.5), -Vector3.zAxis, Vector2.new(8, 1.6), DARK_METAL, WHITE)

	-- Rocks and a few stunted pines round the plateau's edge
	for _, r in { { -140, -100, 14, 0.4 }, { -130, 110, 18, 1.1 }, { 136, -112, 16, 2.2 }, { 140, 96, 20, 0.7 }, { 30, 118, 12, 1.8 }, { -60, -118, 12, 0.2 }, { 96, -60, 7, 1.4 }, { -86, -64, 6, 0.9 }, { 100, 40, 6, 2.6 } } do
		map:Part("Rock", Vector3.new(r[3], r[3] * 0.6, r[3] * 0.8), CFrame.new(r[1], GROUND + r[3] * 0.18, r[2]) * CFrame.Angles(0.08, r[4], 0.12), SLATE, Enum.Material.Slate)
	end
	for _, t in { { 126, -40, 26 }, { 134, 20, 22 }, { 122, 70, 28 }, { -128, -60, 24 }, { -136, 60, 26 }, { 60, -120, 24 }, { -90, 120, 22 }, { 90, 116, 26 } } do
		pine(map, t[1], t[2], t[3])
	end

	-- Invisible walls at the edge of the world
	for _, edge in { { -150, -130, 150, -130 }, { -150, 130, 150, 130 }, { -150, -130, -150, 130 }, { 150, -130, 150, 130 } } do
		for _, piece in map:Wall("Boundary", edge[1], edge[2], edge[3], edge[4], -20, 120, nil, Color3.new(), nil, 2) do
			piece.Transparency = 1
			piece.CanQuery = false
		end
	end
end

-- Signboard on two posts, facing `out`
local function postSign(map: MapBuilder.Builder, text: string, point: Vector3, out: Vector3, size: Vector2, background: Color3, textColor: Color3)
	local across = Vector3.new(out.Z, 0, out.X) * (size.X / 2 - 0.4)
	for _, d in { -1, 1 } do
		local p = point + across * d - out * 0.15
		block(map, "SignPost", p.X - 0.12, GROUND, p.Z - 0.12, p.X + 0.12, point.Y + size.Y / 2, p.Z + 0.12, DARK_METAL, Enum.Material.Metal)
	end
	wallSign(map, text, point, out, size, background, textColor)
end

-- The wreckage out in the field and the yard's kit, finished off: the wing's control surfaces and
-- fuel stain, the engine's fan, the gear's bogie, the snowcat, the generators, the checkpoint
local function buildYardDetail(map: MapBuilder.Builder)
	local yard = map:Folder("Yard")
	local silver = Color3.fromRGB(214, 218, 222)

	-- WING: flaps hanging off the trailing edge (one torn half off), the aileron, rounded leading
	-- edges, spoilers standing up, snow on top, the ribs and lines torn out of its root
	for _, f in { { -19, 16, 3, 0.25, -9, -0.42 }, { -1, 16, 2.6, 0.2, -9.44, -0.22 }, { 17, 10, 2, 0.16, -9.9, 0.1 } } do
		decoPart(map, "Flap", Vector3.new(f[2], f[4], f[3]), WING * CFrame.new(f[1], -0.2, f[5]) * CFrame.Angles(f[6], 0, 0) * CFrame.new(0, 0, -f[3] / 2), Color3.fromRGB(188, 192, 198), Enum.Material.Metal, yard)
	end
	for _, l in { { -19, 5.02, 1.5 }, { -1, 1.06, 1.2 }, { 17, -2.9, 0.9 } } do
		decoTube(map, "LeadingEdge", 18.2, l[3], WING * CFrame.new(l[1], 0, l[2]), Color3.fromRGB(200, 204, 210), Enum.Material.Metal, yard)
	end
	for _, x in { -23, -16 } do
		decoPart(map, "Spoiler", Vector3.new(5, 0.15, 1.8), WING * CFrame.new(x, 0.75, -6.6) * CFrame.Angles(0.55, 0, 0) * CFrame.new(0, 0, 0.9), Color3.fromRGB(180, 184, 190), Enum.Material.Metal, yard)
	end
	decoPart(map, "SnowCap", Vector3.new(14, 0.28, 8), WING * CFrame.new(-19, 0.88, 0), SNOW, Enum.Material.Snow, yard)
	decoPart(map, "SnowCap", Vector3.new(15, 0.22, 5), WING * CFrame.new(0, 0.71, -3.6), SNOW, Enum.Material.Snow, yard)
	decoPart(map, "NavLight", Vector3.new(0.5, 0.3, 0.5), WING * CFrame.new(26.3, 0.3, -2.8), Color3.fromRGB(80, 255, 120), Enum.Material.Neon, yard)
	for i, z in { -6, -1.5, 3 } do
		decoPart(map, "Rib", Vector3.new(1.4, 1.2, 0.15), WING * CFrame.new(-28.6, 0, z) * CFrame.Angles(0, 0.2 * i, 0.3), DARK_METAL, Enum.Material.Metal, yard)
	end
	cable(map, "Hydraulics", WING * Vector3.new(-28, 0.2, -3), WING * Vector3.new(-30.5, -0.6, -2), 0.2, CABLE, Enum.Material.Rubber, yard)
	-- The fuel it bled into the snow round its root
	for i, s in { { -47, 55, 9, 6, 0.3 }, { -41, 51, 7, 5, 1.1 }, { -51, 50, 5, 4, 2 } } do
		local stain = deco(map, "FuelStain", s[1] - s[3] / 2, GROUND, s[2] - s[4] / 2, s[1] + s[3] / 2, GROUND + 0.03 + i * 0.005, s[2] + s[4] / 2, Color3.fromRGB(70, 62, 54), Enum.Material.SmoothPlastic)
		stain.CFrame *= CFrame.Angles(0, s[5], 0)
		stain.Reflectance = 0.12
	end

	-- ENGINE: the intake lip, fan blades and spinner, the exhaust plug, the cowl's seams, snow
	-- drifted round it
	decoTube(map, "IntakeLip", 0.8, 7.4, POD * CFrame.new(5.75, 0, 0), silver, Enum.Material.Metal, yard)
	for k = 0, 7 do
		decoPart(map, "FanBlade", Vector3.new(0.08, 2.5, 0.55), POD * CFrame.new(6.25, 0, 0) * CFrame.Angles(k * math.pi / 4, 0, 0) * CFrame.new(0, 1.55, 0) * CFrame.Angles(0, 0.6, 0), Color3.fromRGB(96, 100, 108), Enum.Material.Metal, yard)
	end
	decoPart(map, "Spinner", Vector3.new(1.6, 1.6, 1.6), POD * CFrame.new(6.3, 0, 0), silver, Enum.Material.Metal, yard).Shape = Enum.PartType.Ball
	decoPart(map, "ExhaustPlug", Vector3.new(2.4, 2.4, 2.4), POD * CFrame.new(-8.5, 0, 0), Color3.fromRGB(70, 66, 62), Enum.Material.Metal, yard).Shape = Enum.PartType.Ball
	for _, x in { 1.5, -3 } do
		decoTube(map, "CowlSeam", 0.15, 7.08, POD * CFrame.new(x, 0, 0), SEAM, Enum.Material.Metal, yard)
	end
	decoPart(map, "SnowCap", Vector3.new(8, 0.3, 2.4), POD * CFrame.new(-0.5, 3.52, 0), SNOW, Enum.Material.Snow, yard)
	local across = POD:VectorToWorldSpace(Vector3.zAxis)
	across = Vector3.new(across.X, 0, across.Z).Unit
	for _, side in { -1, 1 } do
		local foot = POD * Vector3.new(-1, 0, side * 3.2)
		drift(map, Vector3.new(foot.X, GROUND, foot.Z), across * side, 9, 2.2, 4)
	end

	-- GEAR: hubs, the bogie beam, the chrome oleo
	for _, w in { { 66, -22.35 }, { 66, -17.65 }, { 69.4, -22.35 }, { 69.4, -17.65 } } do
		decoTube(map, "Hub", 0.1, 1.7, CFrame.new(w[1], GROUND + 1.8, w[2]) * CFrame.Angles(0, math.pi / 2, 0), silver, Enum.Material.Metal, yard)
	end
	deco(map, "Bogie", 65.2, GROUND + 1.45, -20.35, 70.2, GROUND + 2.15, -19.65, STEEL, Enum.Material.Metal, yard).CastShadow = true
	cable(map, "Oleo", Vector3.new(67.7, GROUND + 2.1, -20), Vector3.new(68.8, GROUND + 6.2, -18.4), 0.7, Color3.fromRGB(226, 228, 232), Enum.Material.Metal, yard)

	-- SNOWCAT: road wheels in the tracks, cab pillars, the plough blade, a light bar, the exhaust
	for _, z in { 19.32, 26.68 } do
		for _, x in { -56.6, -54, -51.4 } do
			decoTube(map, "RoadWheel", 0.12, 1.6, CFrame.new(x, GROUND + 1, z) * CFrame.Angles(0, math.pi / 2, 0), DARK_METAL, Enum.Material.Metal)
		end
	end
	for _, c in { { -55, 20.5 }, { -55, 25.2 }, { -50.8, 20.5 }, { -50.8, 25.2 } } do
		deco(map, "CabPillar", c[1], GROUND + 4.4, c[2], c[1] + 0.3, GROUND + 7.6, c[2] + 0.3, SAFETY_ORANGE, Enum.Material.Metal)
	end
	deco(map, "CabRoof", -55.2, GROUND + 7.6, 20.3, -50.3, GROUND + 7.9, 25.7, SAFETY_ORANGE, Enum.Material.Metal)
	snowCap(map, -55, 20.5, -50.5, 25.5, GROUND + 7.9, 0.3)
	deco(map, "LightBar", -53.5, GROUND + 7.9, 22.4, -52, GROUND + 8.2, 23.6, Color3.fromRGB(255, 170, 40), Enum.Material.Neon)
	deco(map, "Blade", -49.3, GROUND + 0.2, 18.6, -48.8, GROUND + 2.6, 27.4, Color3.fromRGB(60, 62, 66), Enum.Material.Metal)
	for _, z in { 21, 25 } do
		deco(map, "Headlight", -50.42, GROUND + 6.6, z - 0.3, -50.36, GROUND + 7.1, z + 0.3, Color3.fromRGB(255, 246, 220), Enum.Material.Neon)
	end
	cable(map, "Exhaust", Vector3.new(-56.6, GROUND + 4.4, 21), Vector3.new(-56.6, GROUND + 8.4, 21), 0.35, DARK_METAL, Enum.Material.Metal)

	-- GENERATOR YARD: radiators, louvres, skids, control panels, rain caps, snow on the lids; fuel
	-- lines from the tanks; placards; snow on the tanks and the drums
	for _, z in { -38.5, -31.5 } do
		deco(map, "Radiator", -47.05, GROUND + 0.8, z + 0.5, -46.9, GROUND + 4.4, z + 4, DARK_METAL, Enum.Material.DiamondPlate)
		deco(map, "Louvres", -54, GROUND + 1.6, z - 0.05, -49, GROUND + 3.8, z + 4.55, Color3.fromRGB(64, 72, 50), Enum.Material.DiamondPlate)
		deco(map, "Skid", -55.3, GROUND, z - 0.25, -46.7, GROUND + 0.5, z + 4.75, DARK_METAL, Enum.Material.Metal)
		deco(map, "ControlPanel", -55.5, GROUND + 2.4, z + 1.4, -55, GROUND + 4, z + 3.1, Color3.fromRGB(70, 76, 60), Enum.Material.Metal)
		glow(map, -55.56, GROUND + 3.2, z + 1.7, -55.5, GROUND + 3.7, z + 2.4, Color3.fromRGB(110, 255, 120))
		deco(map, "RainCap", -48.7, GROUND + 8.3, z + 0.5, -47.7, GROUND + 8.45, z + 1.5, DARK_METAL, Enum.Material.Metal)
		snowCap(map, -54.8, z + 0.2, -48.9, z + 4.3, GROUND + 5, 0.3)
		cable(map, "FuelLine", Vector3.new(-58.2, GROUND + 1.2, z + 2.5), Vector3.new(-55.3, GROUND + 0.6, z + 2.2), 0.25, CABLE)
	end
	for _, z in { -36, -28 } do
		deco(map, "SnowCap", -69.5, GROUND + 5.25, z - 0.9, -58.5, GROUND + 5.55, z + 0.9, SNOW, Enum.Material.Snow)
		decoPart(map, "Placard", Vector3.new(0.06, 1.2, 1.2), CFrame.new(-57.97, GROUND + 3, z) * CFrame.Angles(math.pi / 4, 0, 0), LIVERY_RED, Enum.Material.SmoothPlastic)
	end
	for _, d in { { -45, -38 }, { -45, -35.5 }, { -42.5, -38 } } do
		cosmetic(drum(map, "SnowCap", d[1], d[2], GROUND + 3.2, 0.2, 2, SNOW, Enum.Material.Snow), map.geometry)
	end
	postSign(map, "DANGER · AVIATION FUEL · NO NAKED FLAMES", Vector3.new(-64, GROUND + 3.6, -41.5), -Vector3.zAxis, Vector2.new(9, 1.4), LIVERY_RED, WHITE)
	postSign(map, "HARD HATS · HIGH-VIS BEYOND THIS POINT", Vector3.new(-47, GROUND + 3.2, 16), -Vector3.xAxis, Vector2.new(7, 1.4), SAFETY_YELLOW, BLACK)
	wallSign(map, "DANGER · 415 V", Vector3.new(-55, GROUND + 4.4, -29.2), -Vector3.xAxis, Vector2.new(2.4, 0.8), SAFETY_YELLOW, BLACK)

	-- Power out to the buildings: cables lying on the snow, a ramp where they cross the track
	local function run(points: { Vector3 })
		for i = 1, #points - 1 do
			cable(map, "PowerCable", points[i], points[i + 1], 0.32, CABLE)
		end
	end
	local y = GROUND + 0.16
	run({ Vector3.new(-47, y, -36), Vector3.new(-40.7, y, -37.5), Vector3.new(-40.7, 10, -37.5) })
	run({ Vector3.new(-47, y, -33), Vector3.new(-41, y, -44), Vector3.new(-5, y, -44) })
	run({ Vector3.new(11, y, -44), Vector3.new(13.3, y, -38), Vector3.new(13.3, 8, -38) })
	run({ Vector3.new(13.3, y, -24.4), Vector3.new(9, y, -18) })
	run({ Vector3.new(11, y, 17.6), Vector3.new(13.3, y, 21.3) })
	deco(map, "CableRamp", -5, GROUND, -44.7, 11, GROUND + 0.35, -43.3, SAFETY_YELLOW, Enum.Material.Rubber)

	-- CHECKPOINT: the road's markings, the boom's red bands, the booth's door and beacon, snow
	-- ploughed up both sides of the road, sandbags by the booth (solid: low cover)
	for z = -128, -100, 8 do
		deco(map, "RoadLine", -0.15, 0.3, z, 0.15, 0.32, z + 4, WHITE, Enum.Material.SmoothPlastic)
	end
	deco(map, "StopLine", 0.3, 0.3, -95, 7.7, 0.32, -94.4, WHITE, Enum.Material.SmoothPlastic)
	local boom = math.rad(110)
	local pivot = Vector3.new(9.1, GROUND + 3.4, -93.1)
	local reach = Vector3.new(math.cos(boom), math.sin(boom), 0)
	for _, along in { 3.5, 12.5 } do
		decoPart(map, "BoomBand", Vector3.new(1.8, 0.56, 0.56), CFrame.new(pivot + reach * along) * CFrame.Angles(0, 0, boom), LIVERY_RED, Enum.Material.SmoothPlastic)
	end
	deco(map, "BoothDoor", 10.85, GROUND, -100.2, 10.95, GROUND + 6.4, -98.2, DARK_METAL, Enum.Material.Metal)
	deco(map, "Beacon", 13.6, GROUND + 8.2, -99.4, 14.4, GROUND + 8.7, -98.6, Color3.fromRGB(255, 160, 40), Enum.Material.Neon)
	snowCap(map, 10.6, -102.4, 17.4, -95.6, GROUND + 8.2, 0.3)
	for _, side in { -1, 1 } do
		drift(map, Vector3.new(side * 8.1, GROUND, -111), Vector3.new(side, 0, 0), 38, 1.5, 3.6)
	end
	drift(map, Vector3.new(-4.1, GROUND, -66.5), -Vector3.xAxis, 49, 1.1, 3)
	drift(map, Vector3.new(10.1, GROUND, -66.5), Vector3.xAxis, 49, 1.1, 3)
	for i, b in { { 18.2, -98.6, 0 }, { 20, -98.6, 0 }, { 21.8, -98.6, 0 }, { 19.1, -98.6, 0.85 }, { 20.9, -98.6, 0.85 } } do
		map:Part("Sandbag", Vector3.new(1.75, 0.85, 1.15), CFrame.new(b[1], GROUND + 0.42 + b[3], b[2]) * CFrame.Angles(0, (noise(i) - 0.5) * 0.2, 0), Color3.fromRGB(150, 136, 104), Enum.Material.Fabric)
	end

	-- HELIPAD: its white perimeter ring
	for k = 0, 7 do
		local a = (k + 0.5) * math.pi / 4
		decoPart(map, "PadRing", Vector3.new(0.4, 0.04, 9.6), CFrame.new(66 + math.cos(a) * 12.2, GROUND + 0.27, 64 + math.sin(a) * 12.2) * CFrame.Angles(0, -a, 0), Color3.fromRGB(232, 232, 226), Enum.Material.SmoothPlastic)
	end
end

-- Panel joints down an outside wall's face every `step` studs, clear of its openings (`gaps`).
-- The wall runs along x at `fixed` (alongX) or along z; `out` is the outside (±1).
local function joints(map: MapBuilder.Builder, alongX: boolean, fixed: number, out: number, a: number, b: number, base: number, top: number, step: number, gaps: { { number } })
	local face = fixed + out * 0.5
	local at = a + step / 2
	while at < b - 0.5 do
		local clear = true
		for _, gap in gaps do
			if at > gap[1] - 0.8 and at < gap[2] + 0.8 then
				clear = false
			end
		end
		if clear then
			if alongX then
				deco(map, "Joint", at - 0.08, base + 0.2, face, at + 0.08, top - 0.2, face + out * 0.06, SEAM, Enum.Material.Metal, map:Folder("Trim"))
			else
				deco(map, "Joint", face, base + 0.2, at - 0.08, face + out * 0.06, top - 0.2, at + 0.08, SEAM, Enum.Material.Metal, map:Folder("Trim"))
			end
		end
		at += step
	end
end

-- The research site finished off: the tent's frame, guy ropes and snow; the buildings' panel
-- joints, AC units, door canopies and container hardware; snow on every roof, drifted against
-- every wall and hanging off the eaves; trodden paths; the snowfield's own variety
local function buildSiteDetail(map: MapBuilder.Builder)
	local trim = map:Folder("Trim")

	-- TENT: an arch between each pair, snow along the crown, guy ropes out to the snow
	local third = (TENT_E - TENT_W) / 3
	for _, x in { TENT_W + third / 2, TENT_W + third * 1.5, TENT_W + third * 2.5 } do
		for _, part in archPanels(map, "TentRib", x - 0.3, x + 0.3, TENT_R + 1.25, 0.5, TENT_RIB, Enum.Material.Metal) do
			cosmetic(part, map.geometry)
		end
	end
	for i, span in { [3] = { 10, 44, 0.18 }, [4] = { TENT_W - 0.3, TENT_E + 0.3, 0.32 }, [5] = { TENT_W - 0.3, TENT_E + 0.3, 0.32 }, [6] = { 12, 40, 0.18 } } do
		local angle = (i - 0.5) * math.pi / 8
		local r = TENT_R + 1 + span[3] / 2
		local chord = 2 * r * math.sin(math.pi / 16) + 0.2
		decoPart(map, "SnowCap", Vector3.new(span[2] - span[1], span[3], chord), CFrame.new((span[1] + span[2]) / 2, TENT_SPRING + r * math.sin(angle), r * math.cos(angle)) * CFrame.Angles(math.pi / 2 - angle, 0, 0), SNOW, Enum.Material.Snow)
	end
	-- (not where a rope would cross a doorway: the ribs at the doors are left out)
	local function ribAt(k: number): number
		return TENT_W + k * third / 2
	end
	for _, g in { { ribAt(0), -1, -22 }, { ribAt(1), -1, -22 }, { ribAt(3), -1, -22 }, { ribAt(4), -1, -22 }, { ribAt(0), 1, 21.2 }, { ribAt(1), 1, 21.2 }, { ribAt(3), 1, 21.2 }, { ribAt(5), 1, 21.2 } } do
		local x, side = g[1], g[2]
		local spring = Vector3.new(x, TENT_SPRING + 3, side * math.sqrt((TENT_R + 0.6) ^ 2 - 9))
		cable(map, "GuyRope", spring, Vector3.new(x, GROUND, g[3]), 0.1, Color3.fromRGB(70, 74, 60), Enum.Material.Fabric)
		deco(map, "Stake", x - 0.15, GROUND, g[3] - 0.15, x + 0.15, GROUND + 0.5, g[3] + 0.15, SAFETY_YELLOW, Enum.Material.Metal)
	end

	-- BUILDINGS: panel joints on the prefab walls (trailers, module, the labs upstairs)
	joints(map, true, -40, -1, 13.5, 56.5, B, B + GROUND_WALL, 5.4, { { 17, 21 }, { 24, 29 }, { 32, 37 }, { 39, 43 } })
	joints(map, true, -24, 1, 13.5, 56.5, B, B + GROUND_WALL, 5.4, { { 16, 21 }, { 34, 40 }, { 50, 55 } })
	joints(map, false, 56, 1, -40, -24, B, B + GROUND_WALL, 5.4, { { -34, -30 } })
	joints(map, false, 14, -1, -40, -24, B, B + GROUND_WALL, 5.4, { { -35, -29 } })
	joints(map, true, -40, -1, -40.5, -5.5, B, B + GROUND_WALL, 5.4, { { -38, -34 }, { -26, -21 }, { -14, -9 } })
	joints(map, false, -40, -1, -40, -22, B, B + GROUND_WALL, 5.4, { { -33, -28 } })
	joints(map, true, 22, -1, 13.5, 52.5, F2, F2 + UPPER_WALL, 4.8, { { 14.5, 19.5 }, { 23, 28 }, { 31, 34 }, { 40, 46 } })
	joints(map, true, 40, 1, 13.5, 52.5, F2, F2 + UPPER_WALL, 4.8, { { 18, 24 } })
	-- Air conditioners on the walls, canopies and steel landings at the outside doors
	for _, a in { { 45, -41.3, -40.5 }, { -17.5, -41.3, -40.5 } } do
		deco(map, "AirCon", a[1] - 1.5, B + 5, a[2], a[1] + 1.5, B + 7.4, a[3], Color3.fromRGB(200, 202, 198), Enum.Material.Metal, trim)
		decoTube(map, "AirConFan", 0.06, 1.8, CFrame.new(a[1], B + 6.2, a[2] - 0.03) * CFrame.Angles(0, math.pi / 2, 0), DARK_METAL, Enum.Material.DiamondPlate, trim)
	end
	deco(map, "AirCon", 30, F2 + 5, 40.5, 33, F2 + 7.4, 41.3, Color3.fromRGB(200, 202, 198), Enum.Material.Metal, trim)
	for _, d in { { 24, 29, -40.5, -1 }, { -26, -21, -40.5, -1 }, { 16, 21, -23.5, 1 }, { 28, 33, 21.5, -1 }, { 28.5, 33.5, 40.5, 1 } } do
		local z1, z2 = d[3], d[3] + d[4] * 1.8
		deco(map, "Canopy", d[1] - 0.6, B + 9.1, z1, d[2] + 0.6, B + 9.4, z2, DARK_METAL, Enum.Material.Metal, trim)
		snowCap(map, d[1] - 0.5, math.min(z1, z2), d[2] + 0.5, math.max(z1, z2), B + 9.4, 0.2, trim)
		deco(map, "DoorStep", d[1] - 0.4, GROUND, z1, d[2] + 0.4, B - 0.02, z1 + d[4] * 2, DARK_METAL, Enum.Material.DiamondPlate)
	end
	-- CONTAINERS: bottom rails, the end's locking bars, ID markings, hazard stripes by the door
	for _, r in { { 13.5, 27.6, 21.5, -1 }, { 33.8, 52.5, 21.5, -1 }, { 13.5, 28.1, 40.5, 1 }, { 34.3, 52.5, 40.5, 1 } } do
		deco(map, "BottomRail", r[1], B, r[3], r[2], B + 0.6, r[3] + r[4] * 0.12, DARK_METAL, Enum.Material.Metal)
	end
	for _, z in { 22.6, 23.6, 36.4, 38.6 } do
		cable(map, "LockBar", Vector3.new(52.62, B + 0.4, z), Vector3.new(52.62, F2 - 1.4, z), 0.18, DARK_METAL, Enum.Material.Metal)
		deco(map, "CamHandle", 52.55, B + 4, z - 0.1, 52.75, B + 4.3, z + 1, DARK_METAL, Enum.Material.Metal)
	end
	for _, c in { { "BRLU 402117 2", 19.75, 21.5, -1 }, { "TGHU 880315 7", 32, 40.5, 1 }, { "MSKU 559012 4", 45, 40.5, 1 } } do
		wallSign(map, c[1], Vector3.new(c[2], B + 9.6, c[3]), Vector3.new(0, 0, c[4]), Vector2.new(6, 1), WHITE, WHITE, false)
	end
	for _, x in { 27.1, 33.5 } do
		deco(map, "HazardStripe", x, B, 21.38, x + 0.4, B + 9, 21.5, SAFETY_YELLOW, Enum.Material.SmoothPlastic)
	end
	wallSign(map, "BIOHAZARD · PPE REQUIRED", Vector3.new(30.5, B + 10.3, 21.5), -Vector3.zAxis, Vector2.new(6, 0.9), SAFETY_YELLOW, BLACK)

	-- SNOW on the roofs (round the trailer roof's hatches), drifted against the walls, icicles
	-- off the eaves
	snowCap(map, -40.2, -40.2, -5.8, -21.8, F2, 0.4)
	snowCap(map, 13.8, 21.8, 52.2, 40.2, LAB_ROOF, 0.45)
	local roofHoles = {}
	for _, h in UPPER_HOLES do
		table.insert(roofHoles, { h[1] - 0.6, h[2] - 0.6, h[3] + 0.6, h[4] + 0.6 })
	end
	for _, piece in map:FloorWithHoles("SnowCap", 13.8, -40.2, 56.2, -23.8, roofHoles, F2 + 0.35, 0.35, SNOW, Enum.Material.Snow) do
		cosmetic(piece, map.geometry).CastShadow = false
	end
	driftAlong(map, true, -40.5, -40.5, -5.5, -1, { { -26, -21 } })
	driftAlong(map, false, -40.5, -40.5, -21.5, -1, { { -33, -28 } })
	driftAlong(map, true, -40.5, 13.5, 56.5, -1, { { 24, 29 }, { 49, 53 } })
	driftAlong(map, true, -23.5, 13.5, 56.5, 1, { { 16, 21 }, { 50, 55 } }, 0.8)
	driftAlong(map, false, 56.5, -40.5, -23.5, 1, {})
	driftAlong(map, false, 13.5, -40.5, -23.5, -1, {}, 0.9)
	driftAlong(map, true, 21.5, 20, 52.5, -1, { { 28, 33 } }, 0.8)
	driftAlong(map, true, 40.5, 13.5, 52.5, 1, { { 28.5, 33.5 } })
	driftAlong(map, false, 52.5, 21.5, 40.5, 1, { { 25, 30 } })
	driftAlong(map, true, -TENT_R - 0.5, TENT_W, TENT_E, -1, { { 20, 25 }, { 36, 41 } }, 0.8)
	driftAlong(map, true, TENT_R + 0.5, TENT_W, TENT_E, 1, { { 18, 23 }, { 32, 37 } }, 0.8)
	driftAlong(map, false, TENT_W - 0.5, -TENT_R, TENT_R, -1, { { -4, 4 } })
	for _, side in { -1, 1 } do
		driftAlong(map, true, side * (HULL + 0.5), TENT_E + 0.6, FWD_E + 0.5, side, {}, 1.2)
	end
	drift(map, Vector3.new(FWD_E + 9, GROUND, 0), Vector3.xAxis, 14, 1.8, 4)
	icicles(map, Vector3.new(-40, F2 - 1.05, -40.6), Vector3.new(-6, F2 - 1.05, -40.6), 9)
	icicles(map, Vector3.new(14, F2 - 1.05, -40.6), Vector3.new(48, F2 - 1.05, -40.6), 9) -- (not over the stairs)
	icicles(map, Vector3.new(14, LAB_ROOF - 1.05, 40.6), Vector3.new(52, LAB_ROOF - 1.05, 40.6), 10)

	-- PATHS: snow trodden down between the doors, tyre ruts from the track to the generators, the
	-- snowcat's tracks to the pit ramp
	local trodden = PACKED
	for _, p in { { 16.5, -23.4, 24.5, -17.6 }, { 46.6, -23.4, 55, -17.6 }, { 18, 17.6, 37, 21.4 }, { 52.6, 25.5, 64, 29.5 }, { 28.5, 40.6, 33.5, 60 }, { -26, -48, -21, -40.6 }, { -47, -33.5, -40.6, -28 } } do
		deco(map, "Path", p[1], GROUND, p[2], p[3], GROUND + 0.03, p[4], trodden, Enum.Material.Snow)
	end
	for _, z in { -47.4, -44.6 } do
		deco(map, "Rut", -46, GROUND, z, -4, GROUND + 0.04, z + 0.9, DIRTY_SNOW, Enum.Material.Snow)
	end
	for _, d in { -1, 1 } do
		local a, b = Vector3.new(-49, GROUND + 0.02, 23 + d * 2.4), Vector3.new(-43.6, GROUND + 0.02, 33.5 + d * 2.4)
		decoPart(map, "Rut", Vector3.new(1.6, 0.04, (b - a).Magnitude), CFrame.lookAt((a + b) / 2, b), DIRTY_SNOW, Enum.Material.Snow)
	end
	-- Slush and soot round the generators and the end of the scar, bluer drifts out in the field,
	-- rock showing through
	for i, d in { { -58, -33, 24, 18, 0.2 }, { -56, 2, 12, 9, 0.7 }, { -47, -18, 10, 6, 0.3 }, { 64, 2, 10, 14, 0.1 } } do
		deco(map, "Slush", d[1] - d[3] / 2, GROUND, d[2] - d[4] / 2, d[1] + d[3] / 2, GROUND + 0.02 + i * 0.004, d[2] + d[4] / 2, DIRTY_SNOW, Enum.Material.Snow).CFrame *= CFrame.Angles(0, d[5], 0)
	end
	for i, d in { { -100, 60, 50, 34, 0.4 }, { 92, -64, 44, 30, 1.2 }, { 98, 74, 40, 36, 0.8 }, { -94, -74, 46, 28, 2.1 }, { 30, 92, 36, 22, 0.3 } } do
		deco(map, "Snowdrift", d[1] - d[3] / 2, GROUND, d[2] - d[4] / 2, d[1] + d[3] / 2, GROUND + 0.02 + i * 0.003, d[2] + d[4] / 2, SHADOW_SNOW, Enum.Material.Snow).CFrame *= CFrame.Angles(0, d[5], 0)
	end
	for i, r in { { -118, 34, 6 }, { -80, 96, 5 }, { 44, 104, 7 }, { 122, -12, 5 }, { -34, -104, 6 }, { 76, -98, 4 } } do
		decoPart(map, "Rock", Vector3.new(r[3], 0.5, r[3] * 0.6), CFrame.new(r[1], GROUND + 0.05, r[2]) * CFrame.Angles(0.05, i * 1.1, 0.04), SLATE, Enum.Material.Rock)
	end

	-- Frost creeping up the outside windows (a child of the pane: it goes when the glass does)
	for _, glass in map:Folder("Glass"):GetChildren() do
		if glass:IsA("BasePart") then
			local size = glass.Size
			local thin = if size.X < size.Z then Vector3.new(size.X + 0.04, size.Y * 0.3, size.Z) else Vector3.new(size.X, size.Y * 0.3, size.Z + 0.04)
			local frost = map:Part("Frost", thin, glass.CFrame * CFrame.new(0, -size.Y * 0.35, 0), Color3.fromRGB(226, 238, 246), Enum.Material.Ice)
			frost.Transparency = 0.55
			frost.CastShadow = false
			cosmetic(frost, glass)
		end
	end
end

-- Weathering: neighbouring panels, slabs and walls never quite the same shade (hashed from where
-- each piece is, so the map looks the same every round)
local WEATHERED = {
	ExteriorWall = 0.045, Wall = 0.025, HullShoulder = 0.04, HullCurve = 0.04, HullRoof = 0.035, TentRoof = 0.06,
	Snow = 0.02, Snowbank = 0.025, Drift = 0.03, SnowCap = 0.025, Crate = 0.08, Barrier = 0.06, Rock = 0.08, Wing = 0.04,
	HullPanel = 0.05, Generator = 0.05, ULD = 0.05, ModuleRoof = 0.04, TrailerRoof = 0.04, LabRoof = 0.04, Seats = 0.05,
}
local function weather(map: MapBuilder.Builder)
	for _, part in map.model:GetDescendants() do
		local amount = part:IsA("BasePart") and WEATHERED[part.Name]
		if amount then
			local p = part.CFrame.Position
			local k = 1 + (noise(p.X * 0.37 + p.Y * 0.11, p.Z * 0.53) - 0.5) * 2 * amount
			local c = part.Color
			part.Color = Color3.new(math.min(c.R * k, 0.96), math.min(c.G * k, 0.96), math.min(c.B * (k + amount * 0.3 * (noise(p.Z, p.X) - 0.5)), 0.97))
		end
	end
end

-- Container walls get the place's corrugated steel (MaterialService); without the variant (a
-- code-only build) Roblox just shows plain metal
local function applyFinishes(map: MapBuilder.Builder)
	local steel = { [RUST:ToHex()] = true, [CONTAINER_BLUE:ToHex()] = true, [CONTAINER_GREEN:ToHex()] = true }
	for _, part in map.model:GetDescendants() do
		if part:IsA("BasePart") and part.Material == Enum.Material.Metal and steel[part.Color:ToHex()] then
			part.MaterialVariant = "CorrugatedSteel"
		end
	end
end

function Flight9.Build(): Model
	local map = MapBuilder.new("Flight9")
	buildFloors(map)
	buildFuselage(map)
	buildTail(map)
	buildTent(map)
	buildGantry(map)
	buildModules(map)
	buildStairs(map)
	buildPit(map)
	buildProps(map)
	buildInteriors(map)
	buildOutside(map)
	buildYardDetail(map)
	buildSiteDetail(map)
	applyFinishes(map)
	weather(map)

	-- Sites: four pairs, A and B each; the defenders pick one pair per round
	local function site(name: string, x1: number, z1: number, x2: number, z2: number, level: number, pair: string, room: string)
		map:Site(name, Vector3.new(x1 + 0.5, level, z1 + 0.5), Vector3.new(x2 - 0.5, level + 6, z2 - 0.5), pair, room)
	end
	site("A", -20, -12, 2, 12, BF, "Hold", "Cargo hold")
	site("B", -24, -38, -4, -12, BF, "Hold", "Ice vault")
	site("A", 26, -12, 44, 12, B, "Nose", "First class")
	site("B", 44, -12, 56, 12, B, "Nose", "Cockpit")
	site("A", 14, 22, 30, 40, F2, "Labs", "Bio lab")
	site("B", 36, 22, 52, 35, F2, "Labs", "Recorder lab")
	site("A", 30, -40, 46, -24, B, "Command", "Control room")
	site("B", 46, -40, 56, -24, B, "Command", "Server room")

	-- Defenders spawn by the pair they picked; attackers on the checkpoint road, in the north
	-- field or at the end of the scar
	map:SpawnPad("Defend", Vector3.new(-31, BF + 0.1, -15.5), Vector3.new(0, 0, 1), "Hold")
	map:SpawnPad("Defend", Vector3.new(20, B + 0.1, 0), Vector3.new(1, 0, 0), "Nose")
	map:SpawnPad("Defend", Vector3.new(33, F2 + 0.1, 30), Vector3.new(-1, 0, 0), "Labs")
	map:SpawnPad("Defend", Vector3.new(22, B + 0.1, -33), Vector3.new(1, 0, 0), "Command")
	map:SpawnPad("Attack", Vector3.new(0, 0.35, -118), Vector3.new(0, 0, 1))
	map:SpawnPad("Attack", Vector3.new(10, 0.25, 108), Vector3.new(0, 0, -1))
	map:SpawnPad("Attack", Vector3.new(-134, 0.25, 4), Vector3.new(1, 0, 0))
	map:FreeRoamSpawn(Vector3.new(0, 0.6, -66))

	return map.model
end

return Flight9
