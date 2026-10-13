-- BANK — a downtown bank in the spirit of Rainbow Six Siege's Bank: a marble lobby open up to a
-- skylight, the teller counter, offices upstairs and the vault in the basement, with a parking
-- ramp down into the basement garage. Main street to the south, a side street west, the back
-- alley and staff lot north, the parking lot east.
-- Four site pairs; the defenders pick one each round (RoundService / SitePicker):
--   Vault:     Vault + Deposit boxes             Tellers:    Teller office + Archives
--   Security:  CCTV room + Staff lounge          Executive:  CEO office + Boardroom
--
--   Ground floor (north = +z; the main street is south):
--   ┌──────────┬──────┬───────────┬──────────┬─────┬────────────┐
--   │ STAFF    │ west │ ARCHIVES  │ TELLER   │ east│ back       │
--   │ LOUNGE   │ hall │           │ OFFICE   │ hall│ stairs ▓▓  │
--   ├──────────┤  ▒▒  │           │          │     ├────────────┤
--   │ CCTV     │      ├───────────┴──────────┤     │ loading    │
--   │ ROOM     │      │ tellers              │     │ dock    ═══│ shutter
--   ├──────────┴──────┼══ teller counter ════┼─────┴──┬─────────┤
--   │ open area       │ queue                │ side   │ manager │
--   │ (loans)         │ LOBBY (atrium)   ▓▓  │ entr.  │         │
--   └─────────────────┴──────────────────────┴────────┴─────────┘
--   x: -56     -36   -24          0         22  30   36        56
--   ▒▒ down to the basement, ▓▓ up (the grand stairs in the lobby, the back stairs north-east).
--   Upstairs: open-plan office, the gallery round the lobby's atrium, restrooms, server room,
--   executive lounge, CEO OFFICE + BOARDROOM over the archives and teller office, accounting,
--   loan and HR offices. Flat roof with a skylight over the atrium and a hatch into accounting.
--   Basement: VAULT (steel-lined concrete, a big round door left open) + DEPOSIT BOXES under the
--   tellers, the vault lobby, records store, guard room, electrical, lockers, boiler room, the
--   service hall at the foot of the back stairs and the garage at the bottom of the ramp.
--
-- Attackers spawn on the main street (south), in the staff lot (north) or the parking lot (east).
-- Drywall, stucco and the wooden floors are soft (shoot through, breach, reinforce); limestone,
-- brick, marble, concrete and the vault aren't. The vault's ceiling is solid concrete. Outside
-- doors and windows start barricaded; a hatch over every lower site lets attackers drop in.
-- Units: studs. The bank spans x -56..56, z -40..40; the ramp runs east from x 56 to 98.

local MapBuilder = require(script.Parent.MapBuilder)

local Bank = {}

-- Floor levels (the top of each floor)
local BF = -11.6 -- basement
local B = 0.4 -- ground floor
local F2 = 13.4 -- upstairs
local CEILING = 24.4 -- upstairs ceiling
local ROOF = CEILING + 1 -- top of the flat roof
local BASEMENT_WALL = 11 -- basement floor up to the ground floor slab
local GROUND_WALL = 12
local UPSTAIRS_WALL = 11
local PARAPET = 1.5 -- low wall round the roof (low enough to rappel over)
local STREET = 0.15 -- top of the asphalt outside
local CURB = 0.3 -- top of the sidewalks

-- Look
local LIMESTONE = Color3.fromRGB(214, 204, 182)
local BRICK = Color3.fromRGB(140, 82, 66)
local STUCCO = Color3.fromRGB(204, 196, 178)
local PLASTER = Color3.fromRGB(226, 218, 200)
local MARBLE_WHITE = Color3.fromRGB(232, 230, 224)
local CONCRETE = Color3.fromRGB(150, 150, 150)
local VAULT_STEEL = Color3.fromRGB(104, 108, 114)
local WOOD = Color3.fromRGB(150, 110, 75)
local DARK_WOOD = Color3.fromRGB(88, 58, 40)
local WHITE = Color3.fromRGB(240, 238, 232)
local DARK_METAL = Color3.fromRGB(62, 66, 72)
local BLACK = Color3.fromRGB(28, 29, 32)
local BRASS = Color3.fromRGB(176, 140, 70)
local GOLD = Color3.fromRGB(222, 182, 70)
local CASH = Color3.fromRGB(112, 150, 100)
local CARDBOARD = Color3.fromRGB(176, 136, 90)
local PALLET = Color3.fromRGB(150, 115, 70)
local LEATHER = Color3.fromRGB(70, 48, 40)
local FABRIC = Color3.fromRGB(90, 96, 104)
local SCREEN = Color3.fromRGB(70, 110, 150)
local HEDGE = Color3.fromRGB(70, 110, 60)
local ASPHALT = Color3.fromRGB(55, 55, 60)
local SIDEWALK = Color3.fromRGB(170, 168, 160)
local ROOF_GRAVEL = Color3.fromRGB(112, 110, 106)
local PAINT_WHITE = Color3.fromRGB(225, 225, 220)
local PAINT_YELLOW = Color3.fromRGB(214, 176, 52)
local BANK_GREEN = Color3.fromRGB(32, 64, 56)
local LIMESTONE_LIGHT = Color3.fromRGB(228, 220, 200) -- dressed stone: lintels, belt course, copings
local LIMESTONE_JOINT = Color3.fromRGB(170, 160, 138)
local LIMESTONE_SHADE = Color3.fromRGB(190, 180, 158) -- column flutes
local GRANITE_DARK = Color3.fromRGB(66, 68, 72)
local GRANITE_LIGHT = Color3.fromRGB(192, 188, 180)
local BRONZE = Color3.fromRGB(104, 78, 48)
local STEEL = Color3.fromRGB(150, 154, 160)
local CHROME = Color3.fromRGB(196, 200, 206)
local VELVET = Color3.fromRGB(128, 26, 36)
local LEAF = Color3.fromRGB(66, 106, 58)
local BARK = Color3.fromRGB(86, 66, 50)
local TINTED_GLASS = Color3.fromRGB(38, 46, 56)
local LAMP_GLOW = Color3.fromRGB(255, 228, 176)
local CHAIR = Color3.fromRGB(42, 44, 50)
local PAPER = Color3.fromRGB(236, 234, 226)
local SAFETY_YELLOW = Color3.fromRGB(226, 186, 40)
local BOOK_COLORS = {
	Color3.fromRGB(120, 36, 34), Color3.fromRGB(34, 60, 98), Color3.fromRGB(44, 84, 56), Color3.fromRGB(150, 120, 70),
	Color3.fromRGB(70, 40, 30), Color3.fromRGB(200, 190, 160), Color3.fromRGB(90, 30, 60), Color3.fromRGB(30, 30, 34),
}
local PIXELS = 20 -- SurfaceGui pixels per stud: the 2D dressing is measured in studs

-- Walls: soft ones can be shot through, breached and reinforced; the rest can't
local DRYWALL: MapBuilder.Style = { color = PLASTER, material = Enum.Material.Plaster, soft = true }
local MARBLE_WALL: MapBuilder.Style = { color = MARBLE_WHITE, material = Enum.Material.Marble }
local COUNTER: MapBuilder.Style = { color = DARK_WOOD, material = Enum.Material.Wood }
local CONCRETE_WALL: MapBuilder.Style = { color = CONCRETE, material = Enum.Material.Concrete }
local BRICK_WALL: MapBuilder.Style = { color = BRICK, material = Enum.Material.Brick }
local VAULT_WALL: MapBuilder.Style = { color = VAULT_STEEL, material = Enum.Material.DiamondPlate }
local OUTSIDE_STONE: MapBuilder.Style = { color = LIMESTONE, material = Enum.Material.Limestone, exterior = true }
local OUTSIDE_BRICK: MapBuilder.Style = { color = BRICK, material = Enum.Material.Brick, exterior = true }
local OUTSIDE_SOFT: MapBuilder.Style = { color = STUCCO, material = Enum.Material.Plaster, soft = true, exterior = true }
local OUTSIDE_CONCRETE: MapBuilder.Style = { color = CONCRETE, material = Enum.Material.Concrete, exterior = true }

-- Floor finishes over the wood / concrete
local CARPET = { Color3.fromRGB(150, 140, 125), Enum.Material.Carpet }
local GREY_CARPET = { Color3.fromRGB(96, 100, 108), Enum.Material.Carpet }
local BLUE_CARPET = { Color3.fromRGB(70, 90, 120), Enum.Material.Carpet }
local GREEN_CARPET = { Color3.fromRGB(60, 92, 78), Enum.Material.Carpet }
local RED_CARPET = { Color3.fromRGB(120, 50, 50), Enum.Material.Carpet }
local TILE = { Color3.fromRGB(222, 222, 216), Enum.Material.CeramicTiles }
local MARBLE = { Color3.fromRGB(232, 230, 224), Enum.Material.Marble }
local GRANITE = { Color3.fromRGB(74, 76, 80), Enum.Material.Granite }
local RAISED = { Color3.fromRGB(176, 180, 186), Enum.Material.DiamondPlate }

-- Holes in the floors: { x1, z1, x2, z2 }
local BASEMENT_STAIRS = { -35.5, 12, -29.5, 28 } -- west hall down to the basement corridor (climbs +z)
local MAIN_STAIRS = { 15.5, -34, 21.5, -18 } -- grand stairs, lobby up to the gallery (climbs +z)
local MAIN_STAIRWELL = { 15.5, -39.5, 21.5, -18 } -- the hole over them (to the front wall: no sliver)
local ATRIUM = { -14, -39.5, 15.5, -24 } -- the lobby is open up to the skylight
local DOWN_FLIGHT = { 34, 20, 40, 36 } -- back stairs, basement up to the ground floor (climbs +z)
local UP_FLIGHT = { 46, 20, 52, 36 } -- back stairs, ground floor up (climbs -z)
local VAULT_CEILING = { -24.5, 15.5, 6.5, 40.5 } -- poured concrete over the vault: no way in from above
local SKYLIGHT = { -8, -36, 10, -28 } -- glass in the roof over the atrium
-- Hatches (4 × 4 trapdoors) over every site below the top floor: x, z, the floor they're in
local HATCH = 4
local HATCHES = {
	{ -6, -2, B }, -- tellers → deposit boxes
	{ -42, -4, F2 }, -- restrooms → CCTV room
	{ -44, 30, F2 }, -- server room → staff lounge
	{ -8, 26, F2 }, -- CEO office → archives
	{ 6, 30, F2 }, -- boardroom → teller office
}
local ROOF_HATCH = { 40, -20 } -- roof → accounting
local GROUND_HOLES = { BASEMENT_STAIRS, DOWN_FLIGHT }
local UPSTAIRS_HOLES = { ATRIUM, MAIN_STAIRWELL, UP_FLIGHT }
local ROOF_HOLES = { SKYLIGHT, { ROOF_HATCH[1] - HATCH / 2, ROOF_HATCH[2] - HATCH / 2, ROOF_HATCH[1] + HATCH / 2, ROOF_HATCH[2] + HATCH / 2 } }
for _, hatch in HATCHES do
	local x, z, level = hatch[1], hatch[2], hatch[3]
	table.insert(if level == B then GROUND_HOLES else UPSTAIRS_HOLES, { x - HATCH / 2, z - HATCH / 2, x + HATCH / 2, z + HATCH / 2 })
end

-- name, x1, z1, x2, z2, floor, finish (nil = bare wood / concrete). Lights and floors come from here.
local ROOMS = {
	{ "Electrical", -56, -40, -36, -14, BF },
	{ "Lockers", -56, -14, -36, 14, BF, TILE },
	{ "BoilerRoom", -56, 14, -36, 40, BF },
	{ "WestCorridor", -36, -40, -24, 40, BF },
	{ "RecordsStore", -24, -40, 0, -14, BF },
	{ "GuardRoom", 0, -40, 22, -14, BF, GREY_CARPET },
	{ "DepositBoxes", -24, -14, 6, 16, BF, MARBLE },
	{ "Vault", -24, 16, 6, 40, BF, GRANITE },
	{ "VaultLobby", 6, -14, 22, 40, BF, MARBLE },
	{ "Garage", 22, -40, 56, 4, BF },
	{ "ServiceHall", 22, 4, 56, 40, BF },

	{ "Lobby", -24, -40, 22, -24, B, MARBLE },
	{ "Queue", -24, -24, 22, -12, B, MARBLE },
	{ "OpenArea", -56, -40, -24, -12, B, GREEN_CARPET },
	{ "CCTV", -56, -12, -36, 12, B, GREY_CARPET },
	{ "StaffLounge", -56, 12, -36, 40, B, TILE },
	{ "WestHall", -36, -12, -24, 40, B, TILE },
	{ "Tellers", -24, -12, 22, 6, B, CARPET },
	{ "Archives", -24, 6, 0, 40, B, GREY_CARPET },
	{ "TellerOffice", 0, 6, 22, 40, B, BLUE_CARPET },
	{ "SideEntrance", 22, -40, 36, -12, B, MARBLE },
	{ "Manager", 36, -40, 56, -12, B, GREEN_CARPET },
	{ "EastHall", 22, -12, 30, 40, B, TILE },
	{ "LoadingDock", 30, -12, 56, 16, B },
	{ "BackStairs", 30, 16, 56, 40, B, TILE },

	{ "OpenOffice", -56, -40, -24, -12, F2, GREY_CARPET },
	{ "GalleryWing", -24, -40, -14, -24, F2, CARPET },
	{ "Gallery", -24, -24, 22, -12, F2, CARPET },
	{ "Restrooms", -56, -12, -36, 6, F2, TILE },
	{ "ServerRoom", -56, 6, -36, 40, F2, RAISED },
	{ "UpperHall", -36, -12, -24, 40, F2, CARPET },
	{ "ExecLounge", -24, -12, 22, 6, F2, GREEN_CARPET },
	{ "CEO", -24, 6, 0, 40, F2, RED_CARPET },
	{ "Boardroom", 0, 6, 22, 40, F2, BLUE_CARPET },
	{ "UpperEastHall", 22, -12, 30, 40, F2, CARPET },
	{ "Accounting", 22, -40, 56, -12, F2, GREY_CARPET },
	{ "LoanOffice", 30, -12, 43, 16, F2, CARPET },
	{ "HROffice", 43, -12, 56, 16, F2, CARPET },
	{ "UpperStairs", 30, 16, 56, 40, F2, TILE },
}

-- Ceiling lights placed by hand where the usual spot would hang in a stairwell, a wall or the
-- skylight: x, z (the lobby's are the chandeliers, buildLobby)
local LIGHT_SPOTS = {
	Lobby = {},
	WestCorridor = { { -27, -26 }, { -27, 4 }, { -27, 34 } },
	ServiceHall = { { 28, 12 }, { 48, 12 }, { 49, 30 } },
	BackStairs = { { 37, 18 }, { 38, 38 } },
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

-- A teller's window in the counter: chest-high, so the tellers can be boarded in
local function teller(at: number): MapBuilder.Opening
	return { from = at, to = at + 5, bottom = 3.6, top = 8, kind = "Window" }
end

-- Every RoomWall built so far, so the dressing can follow the walls (window surrounds and
-- mullions, door leaves, the facade's bands). wallX / wallZ fill it; Bank.Build empties it first.
type WallRecord = {
	style: MapBuilder.Style,
	alongX: boolean,
	at: number, -- z of a wall along x, x of a wall along z
	from: number, -- its ends along the wall
	to: number,
	base: number,
	height: number,
	openings: { MapBuilder.Opening },
	inside: number?,
}
local walls: { WallRecord } = {}

-- Wall along x at `z`, or along z at `x`
local function wallX(map: MapBuilder.Builder, style: MapBuilder.Style, z: number, x1: number, x2: number, base: number, height: number, openings: { MapBuilder.Opening }?, inside: number?)
	map:RoomWall(style, x1, z, x2, z, base, height, openings, inside)
	table.insert(walls, { style = style, alongX = true, at = z, from = math.min(x1, x2), to = math.max(x1, x2), base = base, height = height, openings = openings or {}, inside = inside })
end

local function wallZ(map: MapBuilder.Builder, style: MapBuilder.Style, x: number, z1: number, z2: number, base: number, height: number, openings: { MapBuilder.Opening }?, inside: number?)
	map:RoomWall(style, x, z1, x, z2, base, height, openings, inside)
	table.insert(walls, { style = style, alongX = false, at = x, from = math.min(z1, z2), to = math.max(z1, z2), base = base, height = height, openings = openings or {}, inside = inside })
end

-- Looks only: no collisions, bullets go through
local function cosmetic(part: BasePart, parent: Instance)
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Parent = parent
end

-- Block between two corners given as numbers (any order)
local function block(map: MapBuilder.Builder, name: string, x1: number, y1: number, z1: number, x2: number, y2: number, z2: number, color: Color3, material: Enum.Material?): Part
	return map:Box(name, Vector3.new(math.min(x1, x2), math.min(y1, y2), math.min(z1, z2)), Vector3.new(math.max(x1, x2), math.max(y1, y2), math.max(z1, z2)), color, material)
end

-- Upright cylinder (columns, boilers, poles) standing on `y1`, up to `y2`
local function cylinder(map: MapBuilder.Builder, name: string, x: number, z: number, y1: number, y2: number, diameter: number, color: Color3, material: Enum.Material): Part
	local part = map:Part(name, Vector3.new(y2 - y1, diameter, diameter), CFrame.new(x, (y1 + y2) / 2, z) * CFrame.Angles(0, 0, math.pi / 2), color, material)
	part.Shape = Enum.PartType.Cylinder
	return part
end

-- Flat sign with text on its outward (front, -Z of `cframe`) face. `raised` gives the letters a
-- darker copy just below and to the side, so they read as cut into / standing off the board.
local function sign(map: MapBuilder.Builder, text: string, cframe: CFrame, size: Vector2, background: Color3, textColor: Color3, raised: boolean?, font: Enum.Font?): Part
	local board = map:Part("Sign", Vector3.new(size.X, size.Y, 0.2), cframe, background, Enum.Material.SmoothPlastic)
	cosmetic(board, map.geometry)
	board.CastShadow = false
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
	label.Font = font or Enum.Font.Garamond
	label.TextScaled = true
	label.TextColor3 = textColor
	label.Text = text
	label.ZIndex = 2
	label.Parent = gui
	if raised then
		local shadow = label:Clone()
		shadow.TextColor3 = textColor:Lerp(Color3.new(0, 0, 0), 0.6)
		shadow.Position = UDim2.new(0.03, 3, 0.1, 3)
		shadow.ZIndex = 1
		shadow.Parent = gui
	end
	return board
end

-- Deterministic 0..1 noise: the "random" variation comes out the same every round
local function noise(a: number, b: number?): number
	local n = math.sin(a * 12.9898 + (b or 0) * 78.233) * 43758.5453
	return n - math.floor(n)
end

-- `color` a little lighter or darker (by up to `amount`, 0..1), picked by noise(a, b)
local function vary(color: Color3, amount: number, a: number, b: number?): Color3
	local k = 1 + (noise(a, b) * 2 - 1) * amount
	return Color3.new(math.clamp(color.R * k, 0, 1), math.clamp(color.G * k, 0, 1), math.clamp(color.B * k, 0, 1))
end

-- Small looks-only block between two corners: no collisions, no shadow. In the geometry unless
-- `parent` says otherwise (Trim for anything stuck on a wall a breach can blow away).
local function dress(map: MapBuilder.Builder, name: string, x1: number, y1: number, z1: number, x2: number, y2: number, z2: number, color: Color3, material: Enum.Material?, parent: Instance?): Part
	local part = block(map, name, x1, y1, z1, x2, y2, z2, color, material)
	cosmetic(part, parent or map.geometry)
	part.CastShadow = false
	return part
end

-- Looks-only part placed by a CFrame (turned details), no shadow
local function dressAt(map: MapBuilder.Builder, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?, parent: Instance?): Part
	local part = map:Part(name, size, cframe, color, material)
	cosmetic(part, parent or map.geometry)
	part.CastShadow = false
	return part
end

-- Cylinder (pipes, rails, ropes, arms) from point `a` to point `b`; not for plumb-vertical runs
-- (see cylinder)
local function rod(map: MapBuilder.Builder, name: string, a: Vector3, b: Vector3, diameter: number, color: Color3, material: Enum.Material): Part
	local part = map:Part(name, Vector3.new((b - a).Magnitude, diameter, diameter), CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.pi / 2, 0), color, material)
	part.Shape = Enum.PartType.Cylinder
	return part
end

-- Round slab (clock face, manhole, dish, ring) centred on `center`, its flat faces facing along
-- `axis` ("X", "Y" or "Z")
local function disc(map: MapBuilder.Builder, name: string, center: Vector3, axis: string, diameter: number, thickness: number, color: Color3, material: Enum.Material): Part
	local turn = if axis == "Y" then CFrame.Angles(0, 0, math.pi / 2) elseif axis == "Z" then CFrame.Angles(0, math.pi / 2, 0) else CFrame.new()
	local part = map:Part(name, Vector3.new(thickness, diameter, diameter), CFrame.new(center) * turn, color, material)
	part.Shape = Enum.PartType.Cylinder
	return part
end

local function ball(map: MapBuilder.Builder, name: string, center: Vector3, diameter: number, color: Color3, material: Enum.Material): Part
	local part = map:Part(name, Vector3.one * diameter, CFrame.new(center), color, material)
	part.Shape = Enum.PartType.Ball
	return part
end

-- Light that doesn't cast shadows (small accent lights: cheap, and short enough not to leak far
-- through walls)
local function glow(part: BasePart, range: number, brightness: number, color: Color3?, spot: Enum.NormalId?): Light
	local light: Light
	if spot then
		local spotLight = Instance.new("SpotLight")
		spotLight.Face = spot
		spotLight.Angle = 100
		light = spotLight
	else
		light = Instance.new("PointLight")
	end
	light.Range = range
	light.Brightness = brightness
	light.Color = color or Color3.fromRGB(255, 236, 200)
	light.Shadows = false
	light.Parent = part
	return light
end

-- 2D dressing drawn on one face of a part (a SurfaceGui): window grids, box doors, book spines,
-- stone joints, for no extra parts. Only on parts nothing cuts up: DestructionService splits a
-- broken part into clones, drawing and all, and the drawing would stretch with them.
local function surface(part: BasePart, face: Enum.NormalId, light: number?): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = PIXELS
	gui.LightInfluence = light or 1
	gui.Parent = part
	return gui
end

-- A face's size in studs: across it (the drawing's x), then down it (its y)
local function faceSize(part: BasePart, face: Enum.NormalId): (number, number)
	local size = part.Size
	if face == Enum.NormalId.Front or face == Enum.NormalId.Back then
		return size.X, size.Y
	elseif face == Enum.NormalId.Left or face == Enum.NormalId.Right then
		return size.Z, size.Y
	end
	return size.X, size.Z
end

-- Filled rectangle on a drawing: x, y from the top-left of `parent`, w × h, all in studs
local function rectangle(parent: Instance, x: number, y: number, w: number, h: number, color: Color3, transparency: number?): Frame
	local rect = Instance.new("Frame")
	rect.BorderSizePixel = 0
	rect.BackgroundColor3 = color
	rect.BackgroundTransparency = transparency or 0
	rect.Size = UDim2.fromOffset(w * PIXELS, h * PIXELS)
	rect.Position = UDim2.fromOffset(x * PIXELS, y * PIXELS)
	rect.Parent = parent
	return rect
end

-- cols × rows cells filling x, y, w, h (studs), `gap` between them and round the edge; `color`
-- picks each cell's colour. Returns the cells (to put more on them).
local function grid(parent: Instance, x: number, y: number, w: number, h: number, cols: number, rows: number, gap: number, color: (number, number) -> Color3): { Frame }
	local list = {}
	local cw, ch = (w - gap * (cols + 1)) / cols, (h - gap * (rows + 1)) / rows
	for row = 1, rows do
		for col = 1, cols do
			table.insert(list, rectangle(parent, x + gap + (col - 1) * (cw + gap), y + gap + (row - 1) * (ch + gap), cw, ch, color(col, row)))
		end
	end
	return list
end

-- A row of book spines: one strip, striped by a gradient (colours and widths picked by `seed`)
local function bookRow(parent: Instance, x: number, y: number, w: number, h: number, seed: number)
	local strip = rectangle(parent, x, y, w, h, WHITE)
	local keys = {}
	local count = 9 -- (a ColorSequence takes 20 keypoints at most: two per book)
	local t = 0
	for i = 1, count do
		local color = BOOK_COLORS[math.floor(noise(seed, i) * #BOOK_COLORS) + 1]
		local nextT = if i == count then 1 else math.min(t + (0.6 + noise(i, seed) * 0.8) / count, 1 - (count - i) * 0.02)
		table.insert(keys, ColorSequenceKeypoint.new(t, color))
		table.insert(keys, ColorSequenceKeypoint.new(if i == count then 1 else nextT - 0.004, color))
		t = nextT
	end
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(keys)
	gradient.Parent = strip
end

-- Office chair at (x, z) on `base`, whoever sits in it facing `facing` (a unit vector along x or z)
local function chair(map: MapBuilder.Builder, x: number, z: number, base: number, facing: Vector3, color: Color3?)
	local c = color or CHAIR
	local at = Vector3.new(x, base, z)
	local frame = CFrame.lookAt(at, at + facing)
	dressAt(map, "ChairSeat", Vector3.new(1.5, 0.35, 1.4), frame * CFrame.new(0, 1.55, 0), c, Enum.Material.Fabric)
	dressAt(map, "ChairBack", Vector3.new(1.4, 1.6, 0.22), frame * CFrame.new(0, 2.55, 0.68), c, Enum.Material.Fabric)
	dressAt(map, "ChairPost", Vector3.new(0.3, 1.4, 0.3), frame * CFrame.new(0, 0.7, 0), DARK_METAL, Enum.Material.Metal)
end

-- Rug: a thin layer on the floor finish (in the Shell, so a floor breach cuts it too)
local function rug(map: MapBuilder.Builder, x1: number, z1: number, x2: number, z2: number, level: number, color: Color3)
	local part = block(map, "Rug", x1, level + 0.04, z1, x2, level + 0.07, z2, color, Enum.Material.Fabric)
	cosmetic(part, map:Folder("Shell"))
	part.CastShadow = false
end

-- Picture on a wall, centred on `point` on the wall's face, `out` the way the wall faces (a unit
-- vector along x or z): a gilt frame and a painted canvas. In Trim: a breach takes it down.
local function picture(map: MapBuilder.Builder, point: Vector3, out: Vector3, w: number, h: number, seed: number)
	local frame = CFrame.lookAt(point, point + out) -- (-Z, the part's front, faces out of the wall)
	local trim = map:Folder("Trim")
	dressAt(map, "PictureFrame", Vector3.new(w, h, 0.12), frame * CFrame.new(0, 0, -0.06), GOLD, Enum.Material.Metal, trim)
	local canvas = dressAt(map, "Painting", Vector3.new(w - 0.4, h - 0.4, 0.04), frame * CFrame.new(0, 0, -0.14), WHITE, Enum.Material.SmoothPlastic, trim)
	-- A landscape: sky over hills over a field, the colours picked by `seed`
	local paint = rectangle(surface(canvas, Enum.NormalId.Front), 0, 0, w - 0.4, h - 0.4, WHITE)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	local sky = Color3.fromRGB(150, 176, 196):Lerp(Color3.fromRGB(214, 170, 120), noise(seed, 1))
	local hills = Color3.fromRGB(70, 96, 70):Lerp(Color3.fromRGB(110, 90, 60), noise(seed, 2))
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, sky),
		ColorSequenceKeypoint.new(0.5, sky:Lerp(WHITE, 0.3)),
		ColorSequenceKeypoint.new(0.56, hills),
		ColorSequenceKeypoint.new(0.75, hills:Lerp(Color3.new(0, 0, 0), 0.3)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 140, 90)),
	})
	gradient.Parent = paint
end

-- Glowing EXIT sign sticking out of a wall at `point`, `out` the way the wall faces
local function exitSign(map: MapBuilder.Builder, point: Vector3, out: Vector3)
	local frame = CFrame.lookAt(point, point + out)
	local box = dressAt(map, "ExitSign", Vector3.new(2, 0.7, 0.25), frame * CFrame.new(0, 0, -0.125), WHITE, Enum.Material.SmoothPlastic, map:Folder("Trim"))
	local gui = surface(box, Enum.NormalId.Front, 0)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(30, 150, 70)
	label.BorderSizePixel = 0
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = WHITE
	label.Text = "EXIT"
	label.Parent = gui
end

-- Wall lamp at `point` on a wall's face (`out` the way it faces): a metal hood, a glowing lens
-- under it, and its light
local function wallLamp(map: MapBuilder.Builder, point: Vector3, out: Vector3, range: number?)
	local frame = CFrame.lookAt(point, point + out)
	local trim = map:Folder("Trim")
	dressAt(map, "WallLamp", Vector3.new(1.1, 0.7, 0.8), frame * CFrame.new(0, 0, -0.4), DARK_METAL, Enum.Material.Metal, trim)
	local lens = dressAt(map, "LampGlow", Vector3.new(0.9, 0.12, 0.6), frame * CFrame.new(0, -0.4, -0.4), LAMP_GLOW, Enum.Material.Neon, trim)
	glow(lens, range or 14, 0.9, LAMP_GLOW)
end

local function ceilingOf(level: number): number
	return if level == BF then B - 1 elseif level == B then F2 - 1 else CEILING
end

local function buildFloors(map: MapBuilder.Builder)
	local shell = map:Folder("Shell")
	map:Floor("BasementFloor", -56.5, -40.5, 56.5, 40.5, BF, 1, CONCRETE, Enum.Material.Concrete)
	-- The wooden floors are soft (shoot down through them, breach them); the vault's ceiling is
	-- a slab of concrete instead
	local groundSlab = table.clone(GROUND_HOLES)
	table.insert(groundSlab, VAULT_CEILING)
	for _, piece in map:FloorWithHoles("Floor", -56.5, -40.5, 56.5, 40.5, groundSlab, B, 1, WOOD, Enum.Material.WoodPlanks) do
		piece:SetAttribute("Breakable", "Soft")
	end
	map:Floor("VaultCeiling", VAULT_CEILING[1], VAULT_CEILING[2], VAULT_CEILING[3], VAULT_CEILING[4], B, 1, CONCRETE, Enum.Material.Concrete)
	for _, piece in map:FloorWithHoles("Floor2", -56.5, -40.5, 56.5, 40.5, UPSTAIRS_HOLES, F2, 1, WOOD, Enum.Material.WoodPlanks) do
		piece:SetAttribute("Breakable", "Soft")
		-- Painted ceiling under the wood (DestructionService cuts it along with the floor)
		cosmetic(map:Part("Ceiling", Vector3.new(piece.Size.X, 0.1, piece.Size.Z), piece.CFrame * CFrame.new(0, -0.55, 0), WHITE, Enum.Material.Plaster), shell)
	end
	for _, hatch in HATCHES do
		map:Hatch(hatch[1], hatch[2], hatch[3], HATCH)
	end

	-- Flat roof: gravel on top, white ceiling under, the skylight (glass: shoot it out and drop
	-- into the lobby) and a hatch down into accounting
	map:FloorWithHoles("Roof", -56.5, -40.5, 56.5, 40.5, ROOF_HOLES, ROOF, 1, ROOF_GRAVEL, Enum.Material.Pebble)
	for _, piece in map:FloorWithHoles("UpstairsCeiling", -56.5, -40.5, 56.5, 40.5, ROOF_HOLES, ROOF - 0.95, 0.1, WHITE, Enum.Material.Plaster) do
		cosmetic(piece, shell)
	end
	map:Hatch(ROOF_HATCH[1], ROOF_HATCH[2], ROOF, HATCH)
	local x1, z1, x2, z2 = SKYLIGHT[1], SKYLIGHT[2], SKYLIGHT[3], SKYLIGHT[4]
	local glass = block(map, "Skylight", x1, ROOF - 0.6, z1, x2, ROOF - 0.4, z2, Color3.fromRGB(170, 200, 215), Enum.Material.Glass)
	glass.Transparency = 0.45
	glass:SetAttribute("Breakable", "Glass")
	glass.Parent = map:Folder("Glass")
	-- Glazing bars under the glass, and a curb round it on the roof
	for _, x in { -5, -2, 1, 4, 7 } do
		cosmetic(block(map, "GlazingBar", x - 0.12, ROOF - 0.8, z1, x + 0.12, ROOF - 0.6, z2, DARK_METAL, Enum.Material.Metal), map.geometry)
	end
	for _, z in { -34, -32, -30 } do
		cosmetic(block(map, "GlazingBar", x1, ROOF - 0.8, z - 0.12, x2, ROOF - 0.6, z + 0.12, DARK_METAL, Enum.Material.Metal), map.geometry)
	end
	block(map, "SkylightCurb", x1 - 0.6, ROOF, z1 - 0.6, x2 + 0.6, ROOF + 0.8, z1, DARK_METAL, Enum.Material.Metal)
	block(map, "SkylightCurb", x1 - 0.6, ROOF, z2, x2 + 0.6, ROOF + 0.8, z2 + 0.6, DARK_METAL, Enum.Material.Metal)
	block(map, "SkylightCurb", x1 - 0.6, ROOF, z1, x1, ROOF + 0.8, z2, DARK_METAL, Enum.Material.Metal)
	block(map, "SkylightCurb", x2, ROOF, z1, x2 + 0.6, ROOF + 0.8, z2, DARK_METAL, Enum.Material.Metal)

	for _, room in ROOMS do
		local name, rx1, rz1, rx2, rz2, level, finish = table.unpack(room)
		if finish then
			local holes = if level == B then GROUND_HOLES elseif level == F2 then UPSTAIRS_HOLES else {}
			for _, piece in map:FloorWithHoles(name .. "Floor", rx1, rz1, rx2, rz2, holes, level + 0.04, 0.04, finish[1], finish[2]) do
				cosmetic(piece, shell)
			end
		end
		-- Ceiling lights, spread along the room's long side (the lobby's hang from the roof, over
		-- the atrium), or where LIGHT_SPOTS puts them
		local top = if name == "Lobby" then CEILING else ceilingOf(level)
		local range = if name == "Lobby" then 40 else 24
		local spots = LIGHT_SPOTS[name]
		if not spots then
			spots = {}
			local count = math.max(1, math.round((rx2 - rx1) * (rz2 - rz1) / 500))
			for i = 1, count do
				local t = (i - 0.5) / count
				table.insert(spots, if rx2 - rx1 >= rz2 - rz1 then { rx1 + (rx2 - rx1) * t, (rz1 + rz2) / 2 } else { (rx1 + rx2) / 2, rz1 + (rz2 - rz1) * t })
			end
		end
		for _, spot in spots do
			map:Light(Vector3.new(spot[1], top - 0.2, spot[2]), range, 1)
		end
	end
end

local function buildBasement(map: MapBuilder.Builder)
	local base, h = BF, BASEMENT_WALL
	-- Outside walls: poured concrete, underground; the garage opening onto the ramp (east)
	wallX(map, OUTSIDE_CONCRETE, -40, -56.5, 56.5, base, h, nil, 1)
	wallX(map, OUTSIDE_CONCRETE, 40, -56.5, 56.5, base, h, nil, -1)
	wallZ(map, OUTSIDE_CONCRETE, -56, -40, 40, base, h, nil, 1)
	wallZ(map, OUTSIDE_CONCRETE, 56, -40, 40, base, h, { { from = -30, to = -18, top = 9.6 } }, -1)

	-- West: electrical room, lockers and boiler room off the corridor (the west hall stairs land in it)
	wallZ(map, CONCRETE_WALL, -36, -40, -14, base, h, { door(-30) })
	wallZ(map, DRYWALL, -36, -14, 14, base, h, { door(-2) })
	wallZ(map, CONCRETE_WALL, -36, 14, 40, base, h, { door(32) })
	wallX(map, DRYWALL, -14, -56, -36, base, h, { door(-48) })
	wallX(map, CONCRETE_WALL, 14, -56, -36, base, h, { door(-50) })

	-- Middle: records store, guard room, DEPOSIT BOXES + VAULT (site pair), the vault lobby
	wallZ(map, DRYWALL, -24, -40, 16, base, h, { door(-30), door(-4) })
	wallZ(map, VAULT_WALL, -24, 16, 40, base, h) -- the vault is steel-lined all round
	wallX(map, DRYWALL, -14, -24, 22, base, h, { door(-16), door(12) })
	wallZ(map, DRYWALL, 0, -40, -14, base, h, { door(-30) })
	wallX(map, VAULT_WALL, 16, -24, 6, base, h, { door(-18) }) -- barred gate from the deposit boxes
	wallZ(map, DRYWALL, 6, -14, 16, base, h, { door(-2) })
	wallZ(map, VAULT_WALL, 6, 16, 40, base, h, { { from = 24, to = 31, top = 7.5, kind = "Door" } }) -- the round door

	-- East: the garage (the ramp comes in from the parking lot), the service hall with the back stairs
	wallZ(map, CONCRETE_WALL, 22, -40, 4, base, h, { door(-30), doubleDoor(-10) })
	wallZ(map, DRYWALL, 22, 4, 40, base, h, { door(8), door(30) })
	wallX(map, CONCRETE_WALL, 4, 22, 56, base, h, { arch(26, 36), door(46) })
end

local function buildGround(map: MapBuilder.Builder)
	local base, h = B, GROUND_WALL
	-- Front: limestone, the main doors under the portico, the side entrance
	wallX(map, OUTSIDE_STONE, -40, -56.5, 56.5, base, h, {
		window(-52, -46),
		window(-42, -36),
		window(-32, -26), -- open area
		window(-19, -11, 2, 10),
		doubleDoor(-5),
		window(7, 15, 2, 10), -- lobby
		door(27), -- side entrance
		window(40, 46),
		window(49, 54), -- manager
	}, 1)
	-- Back: stucco (soft), staff doors onto the alley
	wallX(map, OUTSIDE_SOFT, 40, -56.5, 56.5, base, h, {
		door(-43), -- staff lounge
		door(-32), -- west hall
		window(-18, -12),
		window(-8, -3), -- archives
		window(5, 11),
		window(14, 19), -- teller office
		door(23.5), -- east hall
		door(44), -- back stairs
	}, -1)
	-- West: brick onto the side street
	wallZ(map, OUTSIDE_BRICK, -56, -40, 40, base, h, { door(-30), window(-20, -14), window(4, 9), window(18, 24), window(30, 36) }, 1)
	-- East: brick at the manager's office, stucco at the loading dock (its shutter is up: a plain hole)
	wallZ(map, OUTSIDE_BRICK, 56, -40, -12, base, h, { window(-34, -28), window(-22, -16) }, -1)
	wallZ(map, OUTSIDE_SOFT, 56, -12, 40, base, h, { { from = -6, to = 6, top = 10 }, door(9), window(26, 32) }, -1)

	-- West: the open area (loans) off the lobby; CCTV ROOM + STAFF LOUNGE (site pair) off the west hall
	wallZ(map, MARBLE_WALL, -24, -40, -12, base, h, { arch(-34, -16, 10) })
	wallX(map, DRYWALL, -12, -56, -36, base, h, { door(-48) })
	wallX(map, DRYWALL, -12, -36, -24, base, h, { arch(-34, -26) })
	wallZ(map, DRYWALL, -36, -12, 40, base, h, { door(-6), door(31) })
	wallX(map, DRYWALL, 12, -56, -36, base, h, { door(-44) })
	wallZ(map, DRYWALL, -24, -12, 40, base, h, { door(-5), door(30) })

	-- Middle: the teller counter across the lobby (open above, to the ceiling), the tellers behind
	-- it, ARCHIVES + TELLER OFFICE (site pair)
	wallX(map, COUNTER, -12, -24, 22, base, 9, { teller(-20), teller(-12), teller(-4), teller(4), door(13) })
	wallX(map, DRYWALL, 6, -24, 22, base, h, { door(-16), door(12) })
	wallZ(map, DRYWALL, 0, 6, 40, base, h, { door(20) })

	-- East: side entrance, manager's office, the east hall, loading dock, back stairs
	wallZ(map, MARBLE_WALL, 22, -40, -12, base, h, { door(-17.5) })
	wallZ(map, DRYWALL, 22, -12, 40, base, h, { door(-6), door(30) })
	wallZ(map, DRYWALL, 36, -40, -12, base, h, { door(-22) })
	wallX(map, DRYWALL, -12, 22, 56, base, h, { door(24), door(44) })
	wallZ(map, DRYWALL, 30, -12, 40, base, h, { door(0), door(24) })
	wallX(map, DRYWALL, 16, 30, 56, base, h, { door(44) })
end

local function buildUpstairs(map: MapBuilder.Builder)
	local base, h = F2, UPSTAIRS_WALL
	wallX(map, OUTSIDE_STONE, -40, -56.5, 56.5, base, h, {
		window(-52, -46),
		window(-42, -36),
		window(-32, -26), -- open-plan office
		window(-19, -11, 2, 9),
		window(-5, 3, 2, 9),
		window(7, 15, 2, 9), -- tall windows over the atrium
		window(26, 32),
		window(40, 46),
		window(49, 54), -- accounting
	}, 1)
	wallX(map, OUTSIDE_SOFT, 40, -56.5, 56.5, base, h, {
		window(-50, -44), -- server room
		window(-33, -27),
		window(-20, -14),
		window(-8, -3), -- CEO's office
		window(5, 11),
		window(14, 19), -- boardroom
		window(24, 28),
		window(34, 40),
	}, -1)
	wallZ(map, OUTSIDE_SOFT, -56, -40, 40, base, h, { window(-34, -28), window(-22, -16), window(26, 32) }, 1)
	wallZ(map, OUTSIDE_SOFT, 56, -40, 40, base, h, { window(-34, -28), window(-22, -16), window(-6, 0), window(24, 30) }, -1)

	-- The gallery round the atrium; open-plan office west of it, accounting east
	wallZ(map, DRYWALL, -24, -40, -12, base, h, { door(-34), door(-20) })
	wallZ(map, DRYWALL, 22, -40, -12, base, h, { door(-17.5) })
	wallX(map, DRYWALL, -12, -24, 22, base, h, { window(-20, -13), doubleDoor(-5), window(8, 15) })

	-- West: restrooms, server room, the upper hall
	wallX(map, DRYWALL, -12, -56, -36, base, h, { door(-43) })
	wallX(map, DRYWALL, -12, -36, -24, base, h, { arch(-34, -26) })
	wallZ(map, DRYWALL, -36, -12, 40, base, h, { door(-4), door(28) })
	wallX(map, DRYWALL, 6, -56, -36, base, h)
	wallZ(map, DRYWALL, -24, -12, 40, base, h, { door(-6), door(22) })

	-- Middle: executive lounge, CEO OFFICE + BOARDROOM (site pair)
	wallX(map, DRYWALL, 6, -24, 22, base, h, { door(-14), doubleDoor(6) })
	wallZ(map, DRYWALL, 0, 6, 40, base, h, { door(30) })

	-- East: the upper east hall, loan and HR offices, the top of the back stairs
	wallZ(map, DRYWALL, 22, -12, 40, base, h, { door(-4), door(14) })
	wallX(map, DRYWALL, -12, 22, 56, base, h, { door(24), door(36), door(48) })
	wallZ(map, DRYWALL, 30, -12, 40, base, h, { door(0), door(24) })
	wallZ(map, DRYWALL, 43, -12, 16, base, h, { door(4) })
	wallX(map, DRYWALL, 16, 30, 56, base, h, { door(36), door(48) })
end

local function buildStairs(map: MapBuilder.Builder)
	-- Grand marble stairs up the east side of the lobby; plain concrete ones down in the west hall
	map:Stairs(MAIN_STAIRS[1], MAIN_STAIRS[2], MAIN_STAIRS[3], MAIN_STAIRS[4], B, F2, "+Z", MARBLE_WHITE, Enum.Material.Marble)
	map:Stairs(BASEMENT_STAIRS[1], BASEMENT_STAIRS[2], BASEMENT_STAIRS[3], BASEMENT_STAIRS[4], BF, B, "+Z", CONCRETE, Enum.Material.Concrete)
	-- Back stairs in the north-east corner, a brick wall between the two flights (walk round its
	-- north end from one to the other)
	map:Stairs(DOWN_FLIGHT[1], DOWN_FLIGHT[2], DOWN_FLIGHT[3], DOWN_FLIGHT[4], BF, B, "+Z", CONCRETE, Enum.Material.Concrete)
	map:Stairs(UP_FLIGHT[1], UP_FLIGHT[2], UP_FLIGHT[3], UP_FLIGHT[4], B, F2, "-Z", CONCRETE, Enum.Material.Concrete)
	wallZ(map, BRICK_WALL, 43, 20, 36, BF, F2 - BF)

	local function rail(x1: number, z1: number, x2: number, z2: number, y: number, color: Color3?)
		map:Railing(Vector3.new(x1, y, z1), Vector3.new(x2, y, z2), color)
	end
	local function handrail(x1: number, y1: number, z1: number, x2: number, y2: number, z2: number, color: Color3?)
		map:Railing(Vector3.new(x1, y1, z1), Vector3.new(x2, y2, z2), color)
	end
	-- Lobby: brass balustrade round the atrium and up the open side of the grand stairs
	rail(-14, -24, 15.5, -24, F2, BRASS)
	rail(-14, -39.5, -14, -24, F2, BRASS)
	rail(15.5, -24, 15.5, -18, F2, BRASS)
	handrail(15.5, B, -34, 15.5, F2, -18, BRASS)
	-- West hall: round the opening down to the basement (entered from its north end)
	rail(-29.5, 12, -29.5, 28, B)
	rail(-35.5, 12, -29.5, 12, B)
	handrail(-29.5, BF, 12, -29.5, B, 28)
	-- Back stairs: round both openings, and up the flights
	rail(34, 20, 34, 36, B)
	rail(40, 20, 40, 36, B)
	rail(34, 20, 40, 20, B)
	rail(46, 20, 46, 36, F2)
	rail(52, 20, 52, 36, F2)
	rail(46, 36, 52, 36, F2)
	handrail(34, BF, 20, 34, B, 36)
	handrail(40, BF, 20, 40, B, 36)
	handrail(46, B, 36, 46, F2, 20)
	handrail(52, B, 36, 52, F2, 20)
end

-- Pallet at (x, z) with a stack on it (cash in the vault, cartons elsewhere); returns the stack
local function pallet(map: MapBuilder.Builder, x: number, z: number, base: number, height: number, color: Color3, material: Enum.Material): Part
	block(map, "Pallet", x - 2, base, z - 2, x + 2, base + 0.4, z + 2, PALLET, Enum.Material.WoodPlanks)
	return block(map, "Stack", x - 1.8, base + 0.4, z - 1.8, x + 1.8, base + 0.4 + height, z + 1.8, color, material)
end

-- A wall of safe-deposit boxes drawn on one face of `part`: rows of little steel doors, each
-- with its keyhole, `rows` high
local function boxDoors(part: BasePart, face: Enum.NormalId, rows: number)
	local w, h = faceSize(part, face)
	local gui = surface(part, face)
	rectangle(gui, 0, 0, w, h, Color3.fromRGB(58, 60, 64))
	local cols = math.max(1, math.round(w / 1.6))
	for _, door in grid(gui, 0, 0, w, h, cols, rows, 0.08, function(col, row)
		return vary(Color3.fromRGB(150, 154, 160), 0.07, col, row + w)
	end) do
		local dw, dh = door.Size.X.Offset / PIXELS, door.Size.Y.Offset / PIXELS
		rectangle(door, dw * 0.78, dh * 0.38, 0.12, 0.24, Color3.fromRGB(40, 40, 44))
	end
end

-- A bank of screens drawn on a face: cols × rows camera pictures in dark bezels, glowing (unlit)
local function screens(part: BasePart, face: Enum.NormalId, cols: number, rows: number)
	local w, h = faceSize(part, face)
	local gui = surface(part, face, 0)
	rectangle(gui, 0, 0, w, h, BLACK)
	for _, screen in grid(gui, 0, 0, w, h, cols, rows, 0.12, function(col, row)
		return Color3.fromRGB(70, 110, 150):Lerp(Color3.fromRGB(120, 146, 128), noise(col, row + w))
	end) do
		-- A darker floor across the bottom of each picture, and a red REC dot
		local sw, sh = screen.Size.X.Offset / PIXELS, screen.Size.Y.Offset / PIXELS
		rectangle(screen, 0, sh * 0.62, sw, sh * 0.38, Color3.fromRGB(36, 52, 66), 0.25)
		rectangle(screen, sw * 0.06, sh * 0.08, 0.1, 0.1, Color3.fromRGB(255, 60, 60))
	end
end

-- Front of a server rack: a stack of units, each with its status lights (green, blue, the odd amber)
local function rackFront(part: BasePart, face: Enum.NormalId, seed: number)
	local w, h = faceSize(part, face)
	local gui = surface(part, face, 0.3)
	rectangle(gui, 0, 0, w, h, Color3.fromRGB(20, 21, 24))
	local units = 12
	local pitch = (h - 0.6) / units
	for u = 1, units do
		local unit = rectangle(gui, 0.15, 0.3 + (u - 1) * pitch, w - 0.3, pitch - 0.08, vary(Color3.fromRGB(50, 52, 58), 0.25, u, seed))
		for i = 1, 2 do
			local pick = noise(u * 3 + i, seed)
			local color = if pick > 0.8 then Color3.fromRGB(255, 170, 40) elseif pick > 0.35 then Color3.fromRGB(60, 230, 120) else Color3.fromRGB(60, 170, 255)
			rectangle(unit, 0.2 + (i - 1) * 0.24, 0.1, 0.1, 0.1, color)
		end
	end
end

-- Locker doors drawn on a face: vent slots near the top, a handle
local function lockerDoors(part: BasePart, face: Enum.NormalId)
	local w, h = faceSize(part, face)
	local gui = surface(part, face)
	local dark = part.Color:Lerp(Color3.new(0, 0, 0), 0.55)
	rectangle(gui, 0, 0, w, h, dark)
	for _, door in grid(gui, 0, 0, w, h, math.max(1, math.round(w / 1.3)), 1, 0.06, function(col, _row)
		return vary(part.Color, 0.06, col, w)
	end) do
		local dw = door.Size.X.Offset / PIXELS
		for v = 0, 2 do
			rectangle(door, dw * 0.2, 0.5 + v * 0.22, dw * 0.6, 0.08, dark)
		end
		rectangle(door, dw * 0.76, h * 0.45, 0.1, 0.5, CHROME)
	end
end

-- Drawer (or cupboard door) fronts drawn on a face, each with its pull
local function drawerFronts(part: BasePart, face: Enum.NormalId, cols: number, rows: number, pull: Color3?)
	local w, h = faceSize(part, face)
	local gui = surface(part, face)
	rectangle(gui, 0, 0, w, h, part.Color:Lerp(Color3.new(0, 0, 0), 0.45))
	for _, drawer in grid(gui, 0, 0, w, h, cols, rows, 0.06, function(col, row)
		return vary(part.Color, 0.05, col, row)
	end) do
		local dw, dh = drawer.Size.X.Offset / PIXELS, drawer.Size.Y.Offset / PIXELS
		rectangle(drawer, dw * 0.35, math.min(dh * 0.2, 0.4), dw * 0.3, 0.1, pull or CHROME)
	end
end

-- Shelves of books drawn on a bookcase's face, `rows` shelves high
local function bookshelfFront(part: BasePart, face: Enum.NormalId, rows: number, seed: number)
	local w, h = faceSize(part, face)
	local gui = surface(part, face)
	rectangle(gui, 0, 0, w, h, DARK_WOOD:Lerp(Color3.new(0, 0, 0), 0.4)) -- the back of the case
	local shelf = h / rows
	for r = 1, rows do
		local y = (r - 1) * shelf
		local fill = 0.65 + noise(r, seed) * 0.3
		local tall = shelf * fill * 0.85
		bookRow(gui, 0.15, y + shelf - tall, (w - 0.3) * (0.7 + noise(seed, r) * 0.3), tall, seed + r)
		rectangle(gui, 0, y, w, 0.14, DARK_WOOD) -- the shelf over them
	end
	rectangle(gui, 0, h - 0.14, w, 0.14, DARK_WOOD)
	rectangle(gui, 0, 0, 0.14, h, DARK_WOOD)
	rectangle(gui, w - 0.14, 0, 0.14, h, DARK_WOOD)
end

-- Banded bundles of notes drawn on the four sides of a pallet's stack
local function cashBundles(stack: BasePart)
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right } do
		local w, h = faceSize(stack, face)
		local gui = surface(stack, face)
		rectangle(gui, 0, 0, w, h, Color3.fromRGB(70, 96, 64))
		local rows = math.max(1, math.round(h / 0.5))
		grid(gui, 0, 0, w, h, 4, rows, 0.05, function(col, row)
			return vary(CASH, 0.08, col + w, row)
		end)
		for col = 1, 4 do
			rectangle(gui, (col - 0.5) * w / 4 - 0.12, 0, 0.24, h, PAPER) -- the paper bands
		end
	end
end

-- Steel shelving full of archive boxes (the boxes stick out a hair either side of the frame)
local function shelves(map: MapBuilder.Builder, x1: number, z1: number, x2: number, z2: number, base: number, height: number)
	block(map, "Shelving", x1, base, z1, x2, base + height, z2, DARK_METAL, Enum.Material.Metal)
	local alongX = x2 - x1 > z2 - z1
	if alongX then
		block(map, "ArchiveBoxes", x1 + 0.3, base + 0.2, z1 - 0.1, x2 - 0.3, base + height - 0.8, z2 + 0.1, CARDBOARD, Enum.Material.Cardboard)
	else
		block(map, "ArchiveBoxes", x1 - 0.1, base + 0.2, z1 + 0.3, x2 + 0.1, base + height - 0.8, z2 - 0.3, CARDBOARD, Enum.Material.Cardboard)
	end
	-- Shelf boards across the boxes, so it reads as rows of boxes on shelves
	local reach = if alongX then Vector3.new(0, 0, 0.18) else Vector3.new(0.18, 0, 0)
	for k = 1, 3 do
		local y = base + 0.2 + (height - 1) * k / 4
		dress(map, "ShelfBoard", x1 - reach.X, y - 0.06, z1 - reach.Z, x2 + reach.X, y + 0.06, z2 + reach.Z, DARK_METAL, Enum.Material.Metal)
	end
end

-- Pair of desks facing each other across a fabric partition, 8 × 5 from (x, z)
local function deskPod(map: MapBuilder.Builder, x: number, z: number, base: number)
	block(map, "Desks", x, base, z, x + 8, base + 2.6, z + 5, WOOD, Enum.Material.Wood)
	block(map, "Partition", x, base, z + 2.35, x + 8, base + 4.6, z + 2.65, FABRIC, Enum.Material.Fabric)
	for _, side in { 1.2, 3.8 } do
		cosmetic(block(map, "Monitor", x + 3, base + 2.6, z + side - 0.15, x + 5, base + 3.9, z + side + 0.15, BLACK, Enum.Material.SmoothPlastic), map.geometry)
	end
	-- A chair on each side, and some paperwork
	chair(map, x + 4, z - 0.9, base, Vector3.zAxis)
	chair(map, x + 4, z + 5.9, base, -Vector3.zAxis)
	dress(map, "Papers", x + 0.6, base + 2.6, z + 0.5, x + 1.8, base + 2.8, z + 1.4, PAPER, Enum.Material.SmoothPlastic)
end

local function buildVault(map: MapBuilder.Builder)
	-- Vault: safe-deposit boxes floor to ceiling on two walls, pallets of cash, a table of gold
	local boxes = Enum.Material.DiamondPlate
	boxDoors(block(map, "DepositBoxes", -23.5, BF, 37.6, 5.5, BF + 9, 39.5, VAULT_STEEL, boxes), Enum.NormalId.Front, 9)
	boxDoors(block(map, "DepositBoxes", -23.5, BF, 16.5, -21.6, BF + 9, 37.6, VAULT_STEEL, boxes), Enum.NormalId.Right, 9)
	for _, p in { { -14, 30, 3 }, { -3, 28, 3.6 } } do
		local stack = pallet(map, p[1], p[2], BF, p[3], CASH, Enum.Material.SmoothPlastic)
		cashBundles(stack)
		-- Plastic strapping over the top
		for _, dz in { -0.9, 0.9 } do
			dress(map, "Strap", p[1] - 1.85, BF + 0.5, p[2] + dz - 0.1, p[1] + 1.85, BF + 0.45 + p[3], p[2] + dz + 0.1, Color3.fromRGB(40, 40, 44), Enum.Material.Plastic)
		end
	end
	block(map, "Table", -10, BF, 33, -4, BF + 3, 36, DARK_METAL, Enum.Material.Metal)
	-- Two pyramids of gold bars on it (3, 2, 1)
	for _, cx in { -8.4, -5.6 } do
		for layer = 0, 2 do
			for i = 0, 2 - layer do
				local x = cx + (i - (2 - layer) / 2) * 0.62
				local y = BF + 3 + layer * 0.3
				dress(map, "GoldBar", x - 0.28, y, 33.7, x + 0.28, y + 0.3, 35.3, vary(GOLD, 0.05, x, layer), Enum.Material.Foil)
			end
		end
	end
	-- The barred gate from the deposit boxes, swung back against the vault wall (drawn bars on an
	-- invisible panel that still stops people)
	local gate = block(map, "Gate", -18.8, BF, 16.6, -18.6, BF + 7.6, 21.4, DARK_METAL, Enum.Material.DiamondPlate)
	gate.Transparency = 1
	for _, face in { Enum.NormalId.Left, Enum.NormalId.Right } do
		local gui = surface(gate, face)
		for i = 0, 11 do
			rectangle(gui, 0.15 + i * 0.4, 0, 0.12, 7.6, DARK_METAL)
		end
		for _, y in { 0.2, 3.6, 7.2 } do
			rectangle(gui, 0, y, 4.8, 0.2, DARK_METAL)
		end
	end

	-- The round door, swung open into the vault lobby on a massive hinge (it stays open: cover):
	-- a stepped face, the three-spoke wheel, the locking bolts round its edge, the boltwork
	-- behind glass on the inside
	local spin = CFrame.Angles(0, math.pi / 2, 0) -- disc faces along z
	local door = map:Part("VaultDoor", Vector3.new(1.6, 10, 10), CFrame.new(12.6, BF + 5.3, 32.6) * spin, VAULT_STEEL, Enum.Material.DiamondPlate)
	door.Shape = Enum.PartType.Cylinder
	local hub = Vector3.new(12.6, BF + 5.3, 31.1)
	cosmetic(disc(map, "VaultDoorStep", Vector3.new(12.6, BF + 5.3, 31.65), "Z", 8.4, 0.3, Color3.fromRGB(122, 126, 132), Enum.Material.Metal), map.geometry)
	cosmetic(disc(map, "VaultWheel", hub, "Z", 1.3, 0.8, BRASS, Enum.Material.Metal), map.geometry)
	for i = 0, 2 do
		local angle = i * math.pi / 3
		local arm = Vector3.new(math.cos(angle), math.sin(angle), 0) * 2.2
		cosmetic(rod(map, "WheelSpoke", hub - arm, hub + arm, 0.24, BRASS, Enum.Material.Metal), map.geometry)
		for _, tip in { hub - arm, hub + arm } do
			dressAt(map, "WheelKnob", Vector3.one * 0.5, CFrame.new(tip), BRASS, Enum.Material.Metal).Shape = Enum.PartType.Ball
		end
	end
	for _, degrees in { -40, -10, 20, 50, 80, 110, 140 } do
		local out = Vector3.new(math.cos(math.rad(degrees)), math.sin(math.rad(degrees)), 0)
		local center = Vector3.new(12.6, BF + 5.3, 32.6)
		cosmetic(rod(map, "LockingBolt", center + out * 4.6, center + out * 5.5, 0.6, CHROME, Enum.Material.Metal), map.geometry)
	end
	local boltwork = disc(map, "Boltwork", Vector3.new(12.6, BF + 5.3, 33.45), "Z", 7, 0.1, CHROME, Enum.Material.Glass)
	cosmetic(boltwork, map.geometry)
	block(map, "VaultHinge", 6.5, BF + 1.5, 31.6, 7.8, BF + 9, 33.6, DARK_METAL, Enum.Material.Metal)
	for _, y in { BF + 2, BF + 6.5 } do
		cosmetic(cylinder(map, "HingeKnuckle", 7.9, 32.6, y, y + 2, 1.3, CHROME, Enum.Material.Metal), map.geometry)
	end
	-- Alarm beacon over the doorway
	dressAt(map, "AlarmBeacon", Vector3.one * 0.7, CFrame.new(6.85, BF + 9.8, 22.4), Color3.fromRGB(230, 40, 40), Enum.Material.Neon).Shape = Enum.PartType.Ball
	-- Steel collar round the doorway (lobby side)
	block(map, "VaultFrame", 6.5, BF, 22.4, 7.3, BF + 9, 24, DARK_METAL, Enum.Material.Metal)
	block(map, "VaultFrame", 6.5, BF, 31, 7.3, BF + 9, 31.6, DARK_METAL, Enum.Material.Metal)
	block(map, "VaultFrame", 6.5, BF + 7.5, 24, 7.3, BF + 9, 31, DARK_METAL, Enum.Material.Metal)
	sign(map, "VAULT", CFrame.lookAt(Vector3.new(6.72, BF + 9.9, 27.5), Vector3.new(7.72, BF + 9.9, 27.5)), Vector2.new(6, 1.4), DARK_METAL, GOLD)

	-- Deposit boxes: walls of boxes, two islands of them (cover), a viewing table
	boxDoors(block(map, "DepositBoxes", -12.3, BF, 13.6, 5.5, BF + 9, 15.5, VAULT_STEEL, boxes), Enum.NormalId.Front, 9)
	boxDoors(block(map, "DepositBoxes", -23.5, BF, 13.6, -18.7, BF + 9, 15.5, VAULT_STEEL, boxes), Enum.NormalId.Front, 9)
	boxDoors(block(map, "DepositBoxes", -10.3, BF, -13.5, 5.5, BF + 9, -11.6, VAULT_STEEL, boxes), Enum.NormalId.Back, 9)
	for _, island in { block(map, "BoxIsland", -17, BF, 2, -13, BF + 6, 10, VAULT_STEEL, boxes), block(map, "BoxIsland", -1, BF, 4, 3, BF + 6, 12, VAULT_STEEL, boxes) } do
		for _, face in { Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right } do
			boxDoors(island, face, 6)
		end
		-- A brushed-steel top
		local top = island.Position + Vector3.new(0, island.Size.Y / 2, 0)
		dress(map, "IslandTop", top.X - island.Size.X / 2 - 0.1, top.Y, top.Z - island.Size.Z / 2 - 0.1, top.X + island.Size.X / 2 + 0.1, top.Y + 0.15, top.Z + island.Size.Z / 2 + 0.1, CHROME, Enum.Material.Metal)
	end
	block(map, "ViewingTable", -20, BF, -10, -14, BF + 3, -7, WOOD, Enum.Material.Wood)
	-- Somebody's box out on the viewing table, a lamp over it, chairs
	dress(map, "DepositBox", -17.8, BF + 3, -9.2, -16.2, BF + 3.5, -8.2, STEEL, Enum.Material.Metal)
	cosmetic(cylinder(map, "LampStem", -15, -7.6, BF + 3, BF + 4.4, 0.15, BRASS, Enum.Material.Metal), map.geometry)
	local shade = dress(map, "LampShade", -15.5, BF + 4.4, -8.1, -14.5, BF + 4.8, -7.1, BANK_GREEN, Enum.Material.Glass)
	glow(shade, 8, 0.6, LAMP_GLOW)
	for _, x in { -18.5, -15.5 } do
		chair(map, x, -11, BF, Vector3.zAxis, LEATHER)
	end
end

-- Back and arms on a bench or sofa block (x1..x2 × z1..z2, its seat at `top`), the back along the
-- side `back` points to (a unit vector along x or z)
local function seatDress(map: MapBuilder.Builder, x1: number, z1: number, x2: number, z2: number, top: number, back: Vector3, color: Color3, material: Enum.Material, backHeight: number, armHeight: number)
	local t = 0.4
	if back.Z ~= 0 then
		local zb = if back.Z < 0 then z1 else z2 - t
		dress(map, "SeatBack", x1, top, zb, x2, top + backHeight, zb + t, color, material)
		dress(map, "SeatArm", x1, top, z1, x1 + t, top + armHeight, z2, color, material)
		dress(map, "SeatArm", x2 - t, top, z1, x2, top + armHeight, z2, color, material)
	else
		local xb = if back.X < 0 then x1 else x2 - t
		dress(map, "SeatBack", xb, top, z1, xb + t, top + backHeight, z2, color, material)
		dress(map, "SeatArm", x1, top, z1, x2, top + armHeight, z1 + t, color, material)
		dress(map, "SeatArm", x1, top, z2 - t, x2, top + armHeight, z2, color, material)
	end
end

-- Pot plant at (x, z) on `base`: a brass pot and its foliage. `solid` keeps the pot and the main
-- bush colliding (the lobby's and gallery's planters always have)
local function pottedPlant(map: MapBuilder.Builder, x: number, z: number, base: number, size: number, solid: boolean)
	local pot = cylinder(map, "Planter", x, z, base, base + size * 0.65, size, BRASS, Enum.Material.Metal)
	local bush = ball(map, "Plant", Vector3.new(x, base + size * 1.1, z), size, vary(LEAF, 0.12, x, z), Enum.Material.Grass) -- (no wider than the pot)
	if not solid then
		cosmetic(pot, map.geometry)
		cosmetic(bush, map.geometry)
	end
	dressAt(map, "Plant", Vector3.one * size * 0.7, CFrame.new(x + size * 0.15, base + size * 1.55, z - size * 0.1), vary(LEAF, 0.15, z, x), Enum.Material.Grass).Shape = Enum.PartType.Ball
end

-- The lobby: marble columns with bases and capitals, the inlaid floor, the brass-and-velvet queue,
-- benches, planters, writing desks, the clock over the doors, two chandeliers under the skylight,
-- the teller counter's marble top, ledges and window numbers
local function buildLobby(map: MapBuilder.Builder)
	local shell = map:Folder("Shell")
	for _, x in { -14, 8 } do
		block(map, "Column", x - 1, B, -25, x + 1, F2 - 1, -23, MARBLE_WHITE, Enum.Material.Marble)
		dress(map, "ColumnBase", x - 1.3, B, -25.3, x + 1.3, B + 0.7, -22.7, GRANITE_DARK, Enum.Material.Granite)
		dress(map, "ColumnCapital", x - 1.3, F2 - 1.7, -25.3, x + 1.3, F2 - 1, -22.7, MARBLE_WHITE, Enum.Material.Marble)
	end

	-- Inlaid floor: a granite border round the hall, a diamond medallion with a brass star in front
	-- of the doors (thin layers in the Shell, like the marble under them), the runner over it
	local function inlay(x1: number, z1: number, x2: number, z2: number, y: number, color: Color3, material: Enum.Material, turn: number?)
		local part = map:Part("Inlay", Vector3.new(x2 - x1, 0.03, z2 - z1), CFrame.new((x1 + x2) / 2, y, (z1 + z2) / 2) * CFrame.Angles(0, turn or 0, 0), color, material)
		cosmetic(part, shell)
		part.CastShadow = false
	end
	local inlayY = B + 0.055
	inlay(-21, -35.5, 13, -34.9, inlayY, GRANITE_DARK, Enum.Material.Granite)
	inlay(-21, -26.6, 13, -26, inlayY, GRANITE_DARK, Enum.Material.Granite)
	inlay(-21, -34.9, -20.4, -26.6, inlayY, GRANITE_DARK, Enum.Material.Granite)
	inlay(12.4, -34.9, 13, -26.6, inlayY, GRANITE_DARK, Enum.Material.Granite)
	inlay(-3.7, -33.45, 1.7, -28.05, inlayY, GRANITE_DARK, Enum.Material.Granite, math.pi / 4)
	inlay(-3, -32.75, 1, -28.75, inlayY + 0.01, MARBLE_WHITE, Enum.Material.Marble, math.pi / 4)
	inlay(-1.7, -31.45, -0.3, -30.05, inlayY + 0.02, BRASS, Enum.Material.Metal, math.pi / 4)
	inlay(-1.7, -31.45, -0.3, -30.05, inlayY + 0.02, BRASS, Enum.Material.Metal)
	local runner = Color3.fromRGB(130, 40, 45)
	cosmetic(block(map, "Runner", -3, B + 0.04, -39.5, 1, B + 0.08, -35, runner, Enum.Material.Carpet), shell)
	cosmetic(block(map, "Runner", -3, B + 0.04, -26.5, 1, B + 0.08, -12.6, runner, Enum.Material.Carpet), shell)

	-- The queue: brass posts and velvet ropes in front of the teller windows, open at the runner
	for _, line in { { -21, -4.5, 6 }, { 2.5, 11, 4 } } do
		local x1, x2, count, z = line[1], line[2], line[3], -18
		local tops = {}
		for i = 0, count - 1 do
			local x = x1 + (x2 - x1) * i / (count - 1)
			dressAt(map, "Stanchion", Vector3.new(2.9, 0.2, 0.2), CFrame.new(x, B + 1.55, z) * CFrame.Angles(0, 0, math.pi / 2), BRASS, Enum.Material.Metal).Shape = Enum.PartType.Cylinder
			dressAt(map, "StanchionBase", Vector3.new(0.12, 0.9, 0.9), CFrame.new(x, B + 0.06, z) * CFrame.Angles(0, 0, math.pi / 2), BRASS, Enum.Material.Metal).Shape = Enum.PartType.Cylinder
			table.insert(tops, Vector3.new(x, B + 2.75, z))
		end
		for i = 1, #tops - 1 do
			local rope = rod(map, "Rope", tops[i], tops[i + 1], 0.18, VELVET, Enum.Material.Fabric)
			cosmetic(rope, map.geometry)
			rope.CastShadow = false
		end
	end

	-- Benches against the front wall, planters in the corners, the writing desks
	for _, b in { { -19.5, -15 }, { 6, 11 } } do
		block(map, "Bench", b[1], B, -38, b[2], B + 1.6, -36.5, DARK_WOOD, Enum.Material.Wood)
		seatDress(map, b[1], -38, b[2], -36.5, B + 1.6, -Vector3.zAxis, DARK_WOOD, Enum.Material.Wood, 1.6, 0.7)
	end
	for _, p in { { -21.5, -38 }, { 13, -38 } } do
		pottedPlant(map, p[1], p[2], B, 3, true)
	end
	for _, x in { -14, 6 } do
		block(map, "WritingDesk", x, B, -31, x + 6, B + 3.6, -28, MARBLE_WHITE, Enum.Material.Marble)
		dress(map, "DeskTop", x - 0.15, B + 3.6, -31.15, x + 6.15, B + 3.75, -27.85, GRANITE_DARK, Enum.Material.Granite)
		dress(map, "SlipTray", x + 2.2, B + 3.75, -29.9, x + 3.8, B + 3.9, -29.1, BRASS, Enum.Material.Metal)
	end

	-- The clock over the front doors (ten past ten)
	local trim = map:Folder("Trim")
	local clock = Vector3.new(-1, B + 10.5, -39.5)
	cosmetic(disc(map, "ClockRim", clock + Vector3.new(0, 0, 0.12), "Z", 3, 0.24, BRASS, Enum.Material.Metal), trim)
	dressAt(map, "ClockFace", Vector3.new(0.06, 2.6, 2.6), CFrame.new(clock + Vector3.new(0, 0, 0.26)) * CFrame.Angles(0, math.pi / 2, 0), WHITE, Enum.Material.SmoothPlastic, trim).Shape = Enum.PartType.Cylinder
	local face = CFrame.new(clock + Vector3.new(0, 0, 0.31))
	for i = 0, 3 do
		local a = i * math.pi / 2
		dressAt(map, "ClockMark", Vector3.new(0.14, 0.36, 0.04), face * CFrame.Angles(0, 0, -a) * CFrame.new(0, 1.05, 0), BLACK, Enum.Material.SmoothPlastic, trim)
	end
	dressAt(map, "ClockHand", Vector3.new(0.1, 1.1, 0.03), face * CFrame.Angles(0, 0, -math.rad(60)) * CFrame.new(0, 0.5, 0.02), BLACK, Enum.Material.SmoothPlastic, trim)
	dressAt(map, "ClockHand", Vector3.new(0.14, 0.72, 0.03), face * CFrame.Angles(0, 0, -math.rad(305)) * CFrame.new(0, 0.32, 0.04), BLACK, Enum.Material.SmoothPlastic, trim)

	-- Two chandeliers hanging from the roof either side of the skylight
	for _, x in { -10, 11.5 } do
		local z = -31.75
		cosmetic(cylinder(map, "ChandelierChain", x, z, B + 20.2, CEILING, 0.12, DARK_METAL, Enum.Material.Metal), map.geometry)
		cosmetic(disc(map, "ChandelierCrown", Vector3.new(x, B + 20, z), "Y", 2.6, 0.25, BRASS, Enum.Material.Metal), map.geometry)
		cosmetic(cylinder(map, "ChandelierStem", x, z, B + 17.8, B + 20.2, 0.45, BRASS, Enum.Material.Metal), map.geometry)
		cosmetic(disc(map, "ChandelierRing", Vector3.new(x, B + 18.5, z), "Y", 4.2, 0.25, BRASS, Enum.Material.Metal), map.geometry)
		local candles = disc(map, "ChandelierCandles", Vector3.new(x, B + 18.75, z), "Y", 3.8, 0.25, LAMP_GLOW, Enum.Material.Neon)
		cosmetic(candles, map.geometry)
		candles.CastShadow = false
		local bowl = ball(map, "ChandelierBowl", Vector3.new(x, B + 17.7, z), 1.3, LAMP_GLOW, Enum.Material.Neon)
		cosmetic(bowl, map.geometry)
		bowl.CastShadow = false
		local light = glow(bowl, 40, 1.2, Color3.fromRGB(255, 236, 200))
		light.Shadows = true -- (a big light: it would shine through the lobby's walls without)
	end

	-- Paintings on the marble walls, the loans sign over the arch to the open area
	picture(map, Vector3.new(21.5, B + 6, -36.75), -Vector3.xAxis, 2.6, 3.4, 1)
	picture(map, Vector3.new(-23.5, B + 6, -14.1), Vector3.xAxis, 2.2, 3, 2)
	sign(map, "LOANS & MORTGAGES", CFrame.lookAt(Vector3.new(-23.38, B + 11.2, -25), Vector3.new(-22.38, B + 11.2, -25)), Vector2.new(8, 1.1), BANK_GREEN, GOLD, true)

	-- The teller counter: a marble top, a brass foot rail, a marble ledge and a number at each
	-- window, and the TELLERS sign hung from the ceiling over it
	dress(map, "CounterTop", -24, B + 9, -12.75, 22, B + 9.2, -11.25, MARBLE_WHITE, Enum.Material.Marble)
	cosmetic(rod(map, "FootRail", Vector3.new(-23.4, B + 0.9, -12.85), Vector3.new(12.3, B + 0.9, -12.85), 0.18, BRASS, Enum.Material.Metal), map.geometry)
	for i, x in { -20, -12, -4, 4 } do
		dress(map, "TellerLedge", x - 0.4, B + 3.6, -13.2, x + 5.4, B + 3.75, -10.8, MARBLE_WHITE, Enum.Material.Marble)
		local at = Vector3.new(x + 2.5, B + 8.72, -12.62)
		sign(map, tostring(i), CFrame.lookAt(at, at - Vector3.zAxis), Vector2.new(0.9, 0.42), BANK_GREEN, GOLD)
	end
	sign(map, "TELLERS", CFrame.lookAt(Vector3.new(-1, B + 10.6, -12.2), Vector3.new(-1, B + 10.6, -13.2)), Vector2.new(10, 1.6), BANK_GREEN, GOLD, true)
	for _, x in { -5, 3 } do
		dress(map, "SignHanger", x - 0.05, B + 11.4, -12.25, x + 0.05, F2 - 1, -12.15, BRASS, Enum.Material.Metal)
	end
end

local function buildProps(map: MapBuilder.Builder)
	buildVault(map)

	-- Basement: records shelving, the guard room, garage, service hall, plant rooms, lockers
	shelves(map, -20, -36, -5, -34.5, BF, 7)
	shelves(map, -20, -28, -5, -26.5, BF, 7)
	shelves(map, -16, -21, -3, -19.5, BF, 7)
	block(map, "GuardDesk", 4, BF, -38, 12, BF + 2.8, -35, DARK_METAL, Enum.Material.Metal)
	screens(block(map, "Monitors", 5, BF + 2.8, -38, 11, BF + 5, -37.4, BLACK, Enum.Material.SmoothPlastic), Enum.NormalId.Back, 3, 2)
	drawerFronts(block(map, "GunLockers", 20, BF, -22, 21.5, BF + 7, -15, Color3.fromRGB(70, 80, 70), Enum.Material.Metal), Enum.NormalId.Left, 3, 1)
	block(map, "Table", 8, BF, -26, 14, BF + 2.8, -22, WOOD, Enum.Material.Wood)
	chair(map, 8, -33.8, BF, -Vector3.zAxis)
	chair(map, 11, -27.2, BF, Vector3.zAxis)
	chair(map, 11, -20.8, BF, -Vector3.zAxis)
	dress(map, "Keyboard", 7, BF + 2.8, -36.4, 9, BF + 2.9, -35.8, BLACK, Enum.Material.SmoothPlastic)
	for _, x in { 33, 45 } do
		block(map, "Pillar", x - 1, BF, -13, x + 1, B - 1, -11, CONCRETE, Enum.Material.Concrete)
		-- Hazard bands round the foot of the pillar
		for i, color in { SAFETY_YELLOW, BLACK, SAFETY_YELLOW } do
			dress(map, "PillarBand", x - 1.05, BF + (i - 1) * 0.9, -13.05, x + 1.05, BF + i * 0.9, -10.95, color, Enum.Material.SmoothPlastic)
		end
	end
	block(map, "Crate", 25, BF, 18, 29, BF + 4, 22, PALLET, Enum.Material.WoodPlanks)
	block(map, "Crate", 50, BF, 35, 54, BF + 4.5, 39, PALLET, Enum.Material.WoodPlanks)
	pallet(map, 50, 9, BF, 3.2, CARDBOARD, Enum.Material.Cardboard)
	local lift = block(map, "ElevatorDoors", 24.5, BF, 39.3, 31.5, BF + 9, 39.5, DARK_METAL, Enum.Material.Metal)
	cosmetic(lift, map.geometry)
	local liftFace = surface(lift, Enum.NormalId.Front)
	rectangle(liftFace, 0, 0, 7, 9, STEEL)
	rectangle(liftFace, 3.46, 0, 0.08, 9, DARK_METAL) -- where the doors meet
	dress(map, "LiftButtons", 32, BF + 3.6, 39.3, 32.6, BF + 4.8, 39.5, CHROME, Enum.Material.Metal)
	dress(map, "LiftIndicator", 26.8, BF + 9.3, 39.38, 29.2, BF + 9.9, 39.5, Color3.fromRGB(255, 150, 40), Enum.Material.Neon)
	-- Garage: bay lines, sprinkler and drain pipes, signs at the ramp
	local paint = map:Folder("Paint")
	for _, line in { { 22.5, -32.7, 50, -32.4 }, { 36.1, -39.5, 36.4, -32.4 }, { 49.7, -39.5, 50, -32.4 }, { 42, -5.6, 55.5, -5.3 }, { 42, -5.6, 42.3, 3.5 } } do
		cosmetic(block(map, "BayLine", line[1], BF, line[2], line[3], BF + 0.03, line[4], PAINT_WHITE, Enum.Material.SmoothPlastic), paint)
	end
	cosmetic(rod(map, "SprinklerPipe", Vector3.new(22.6, B - 2.1, -38.6), Vector3.new(55.4, B - 2.1, -38.6), 0.4, Color3.fromRGB(170, 40, 40), Enum.Material.Metal), map.geometry)
	cosmetic(rod(map, "DrainPipe", Vector3.new(22.6, B - 2.5, -37.8), Vector3.new(55.4, B - 2.5, -37.8), 0.7, Color3.fromRGB(120, 124, 130), Enum.Material.Metal), map.geometry)
	-- (over the opening onto the ramp: the wall above it runs BF + 9.6 .. BF + 11)
	sign(map, "EXIT TO STREET", CFrame.lookAt(Vector3.new(55.38, BF + 10.3, -24), Vector3.new(54.38, BF + 10.3, -24)), Vector2.new(7, 1), BANK_GREEN, WHITE, false, Enum.Font.GothamBold)
	sign(map, "OAKHAVEN PARKING", CFrame.lookAt(Vector3.new(56.62, BF + 10.3, -24), Vector3.new(57.62, BF + 10.3, -24)), Vector2.new(10, 1), BANK_GREEN, WHITE, false, Enum.Font.GothamBold)

	-- Plant rooms: electrical cabinets with conduits up the wall, the transformer's cooling fins,
	-- lockers, the boilers' pipework
	local cabinets = block(map, "ElectricalCabinets", -54, BF, -39.5, -40, BF + 7, -37.6, Color3.fromRGB(120, 124, 130), Enum.Material.Metal)
	drawerFronts(cabinets, Enum.NormalId.Back, 7, 1, DARK_METAL)
	for _, x in { -52, -47, -42 } do
		cosmetic(cylinder(map, "Conduit", x, -38.6, BF + 7, B - 1, 0.45, DARK_METAL, Enum.Material.Metal), map.geometry)
	end
	sign(map, "DANGER  HIGH VOLTAGE", CFrame.lookAt(Vector3.new(-47, BF + 5.6, -37.48), Vector3.new(-47, BF + 5.6, -36.48)), Vector2.new(4, 0.8), WHITE, Color3.fromRGB(190, 30, 30), false, Enum.Font.GothamBold)
	local transformer = block(map, "Transformer", -52, BF, -26, -46, BF + 5, -21, Color3.fromRGB(80, 96, 80), Enum.Material.Metal)
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right } do
		local w, h = faceSize(transformer, face)
		local gui = surface(transformer, face)
		for i = 1, math.floor(w / 0.5) - 1 do
			rectangle(gui, i * 0.5 - 0.06, 0.5, 0.12, h - 1, Color3.fromRGB(56, 68, 56))
		end
	end
	lockerDoors(block(map, "Lockers", -55.5, BF, -10, -54, BF + 7, 10, Color3.fromRGB(80, 90, 110), Enum.Material.Metal), Enum.NormalId.Right)
	local island = block(map, "Lockers", -47, BF, -6, -45, BF + 7, 8, Color3.fromRGB(80, 90, 110), Enum.Material.Metal)
	lockerDoors(island, Enum.NormalId.Left)
	lockerDoors(island, Enum.NormalId.Right)
	block(map, "Bench", -52, BF, -6, -50, BF + 1.6, 6, WOOD, Enum.Material.Wood)
	for _, z in { 22, 33 } do
		cylinder(map, "Boiler", -50, z, BF, BF + 9, 5, Color3.fromRGB(150, 60, 50), Enum.Material.Metal)
		cosmetic(cylinder(map, "Riser", -50, z, BF + 9, B - 1.5, 0.7, DARK_METAL, Enum.Material.Metal), map.geometry)
		cosmetic(disc(map, "Gauge", Vector3.new(-47.45, BF + 5.5, z), "X", 0.8, 0.1, WHITE, Enum.Material.SmoothPlastic), map.geometry)
	end
	cosmetic(rod(map, "Header", Vector3.new(-50, B - 1.6, 18), Vector3.new(-50, B - 1.6, 38), 0.9, DARK_METAL, Enum.Material.Metal), map.geometry)
	block(map, "Pump", -42, BF, 18, -38, BF + 4, 22, DARK_METAL, Enum.Material.Metal)
	cosmetic(cylinder(map, "Riser", -40, 20, BF + 4, B - 1.6, 0.5, DARK_METAL, Enum.Material.Metal), map.geometry)
	cosmetic(rod(map, "Pipe", Vector3.new(-40, B - 1.6, 20), Vector3.new(-50, B - 1.6, 20), 0.5, DARK_METAL, Enum.Material.Metal), map.geometry)
	cosmetic(disc(map, "Valve", Vector3.new(-40, BF + 6, 20), "Y", 1.1, 0.12, Color3.fromRGB(180, 40, 40), Enum.Material.Metal), map.geometry)
	for _, z in { 38.4, 39.2 } do
		cosmetic(block(map, "Pipe", -55.5, B - 2.4, z - 0.3, -38, B - 1.8, z + 0.3, DARK_METAL, Enum.Material.Metal), map.geometry)
	end
	-- Pipes along the top of the west corridor (on the east side: clear of the stairs down)
	for _, p in { { -25.1, 0.5 }, { -25.8, 0.35 } } do
		cosmetic(rod(map, "Pipe", Vector3.new(p[1], B - 1.5, -39.5), Vector3.new(p[1], B - 1.5, 39.5), p[2], Color3.fromRGB(120, 124, 130), Enum.Material.Metal), map.geometry)
	end

	buildLobby(map)

	-- Behind the counter: a desk and screen at every window (keyboard, receipt printer, a chair),
	-- cabinets, a coin counter
	for _, x in { -20, -12, -4, 4 } do
		block(map, "TellerDesk", x - 1, B, -11.5, x + 6, B + 3.4, -9.5, DARK_WOOD, Enum.Material.Wood)
		cosmetic(block(map, "Monitor", x + 1.5, B + 3.4, -10.7, x + 3.5, B + 4.8, -10.4, BLACK, Enum.Material.SmoothPlastic), map.geometry)
		dress(map, "Keyboard", x + 1.6, B + 3.4, -10.2, x + 3.4, B + 3.5, -9.7, BLACK, Enum.Material.SmoothPlastic)
		dress(map, "ReceiptPrinter", x + 4.2, B + 3.4, -11.1, x + 5, B + 3.9, -10.3, Color3.fromRGB(200, 200, 196), Enum.Material.SmoothPlastic)
		chair(map, x + 2.5, -8.2, B, -Vector3.zAxis)
	end
	drawerFronts(block(map, "Cabinets", -9, B, 3.5, 9, B + 4, 5.5, DARK_WOOD, Enum.Material.Wood), Enum.NormalId.Front, 9, 2, BRASS)
	block(map, "CoinCounter", -20, B, 0, -16, B + 3, 3, DARK_METAL, Enum.Material.Metal)
	dress(map, "CoinDisplay", -19.2, B + 2.2, -0.08, -16.8, B + 2.7, 0, Color3.fromRGB(90, 220, 120), Enum.Material.Neon)

	-- Archives: rows of shelving (cover), filing cabinets
	shelves(map, -20.75, 12, -19.25, 28, B, 8)
	shelves(map, -14.75, 12, -13.25, 32, B, 8)
	shelves(map, -6.75, 12, -5.25, 22, B, 8)
	drawerFronts(block(map, "FilingCabinets", -2, B, 30, -0.5, B + 4.5, 38, Color3.fromRGB(120, 124, 130), Enum.Material.Metal), Enum.NormalId.Left, 5, 4)

	-- Teller office: desks under the windows (screens, chairs), the big safe (dial, handle,
	-- hinges), the counting table with the cash and a note counter
	for _, x in { 3, 13 } do
		block(map, "Desk", x, B, 35, x + 6, B + 2.8, 38, WOOD, Enum.Material.Wood)
		dress(map, "Monitor", x + 2, B + 2.8, 36.6, x + 4, B + 4.1, 36.9, BLACK, Enum.Material.SmoothPlastic)
		dress(map, "Keyboard", x + 2.1, B + 2.8, 35.5, x + 3.9, B + 2.9, 36.1, BLACK, Enum.Material.SmoothPlastic)
		chair(map, x + 3, 33.6, B, Vector3.zAxis)
	end
	local safe = block(map, "Safe", 18.5, B, 9, 21.5, B + 7, 14, DARK_METAL, Enum.Material.Metal)
	local safeFace = surface(safe, Enum.NormalId.Left)
	rectangle(safeFace, 0.3, 0.3, 4.4, 6.4, Color3.fromRGB(74, 78, 84)) -- the door
	cosmetic(disc(map, "SafeDial", Vector3.new(18.42, B + 4.6, 11.2), "X", 0.9, 0.12, CHROME, Enum.Material.Metal), map.geometry)
	cosmetic(rod(map, "SafeHandle", Vector3.new(18.3, B + 3.4, 10.6), Vector3.new(18.3, B + 3.4, 11.8), 0.16, CHROME, Enum.Material.Metal), map.geometry)
	for _, y in { B + 1.2, B + 5.6 } do
		dress(map, "SafeHinge", 18.3, y, 13.3, 18.5, y + 0.8, 13.6, CHROME, Enum.Material.Metal)
	end
	block(map, "CountingTable", 12, B, 22, 18, B + 3, 25, WOOD, Enum.Material.Wood)
	cashBundles(block(map, "Cash", 13, B + 3, 22.6, 17, B + 3.5, 24.4, CASH, Enum.Material.SmoothPlastic))
	dress(map, "NoteCounter", 17.2, B + 3, 22.8, 17.9, B + 3.8, 24.2, Color3.fromRGB(200, 200, 196), Enum.Material.SmoothPlastic)
	dress(map, "NoteCounterDisplay", 17.15, B + 3.45, 23.2, 17.2, B + 3.7, 23.8, Color3.fromRGB(90, 220, 120), Enum.Material.Neon)

	-- Open area: loan officers' desks, plants in the corners
	for _, d in { { -50, -36 }, { -36, -36 }, { -50, -21 }, { -36, -21 } } do
		deskPod(map, d[1], d[2], B)
	end
	pottedPlant(map, -54.4, -13.6, B, 1.4, false)
	pottedPlant(map, -25.6, -38.4, B, 1.4, false)

	-- CCTV room: the wall of screens, the console (keyboards, screens, two chairs), the recorder
	block(map, "MonitorWall", -55.5, B + 2.6, -10, -54.6, B + 8.6, 2, BLACK, Enum.Material.SmoothPlastic)
	local screenWall = block(map, "Screens", -54.6, B + 3, -9.6, -54.5, B + 8.2, 1.6, SCREEN, Enum.Material.Neon)
	cosmetic(screenWall, map.geometry)
	screens(screenWall, Enum.NormalId.Right, 4, 3)
	glow(screenWall, 12, 0.5, Color3.fromRGB(150, 190, 255))
	block(map, "Console", -53, B, -9, -50, B + 2.8, 1, DARK_METAL, Enum.Material.Metal)
	for _, z in { -5.5, -1 } do
		dress(map, "Keyboard", -51.2, B + 2.8, z - 0.9, -50.6, B + 2.9, z + 0.9, BLACK, Enum.Material.SmoothPlastic)
		dress(map, "Monitor", -52.8, B + 2.8, z - 1, -52.5, B + 4, z + 1, BLACK, Enum.Material.SmoothPlastic)
		chair(map, -48.6, z, B, -Vector3.xAxis)
	end
	rackFront(block(map, "Recorder", -39, B, 6, -37, B + 7, 10, BLACK, Enum.Material.Metal), Enum.NormalId.Left, 7)

	-- Staff lounge: kitchenette (sink, cupboards, microwave, coffee machine), the table and its
	-- chairs, sofa, lockers
	local fridge = block(map, "Fridge", -55.5, B, 37, -52.5, B + 7, 39.5, WHITE, Enum.Material.Metal)
	local fridgeFace = surface(fridge, Enum.NormalId.Front)
	rectangle(fridgeFace, 0, 2.4, 3, 0.06, Color3.fromRGB(150, 150, 150))
	rectangle(fridgeFace, 0.3, 0.6, 0.1, 1.2, CHROME)
	rectangle(fridgeFace, 0.3, 3, 0.1, 2, CHROME)
	block(map, "Counter", -52.5, B, 37.5, -46, B + 3.2, 39.5, WHITE, Enum.Material.Marble)
	dress(map, "Sink", -50.6, B + 3.2, 38, -48.6, B + 3.24, 39.2, CHROME, Enum.Material.Metal)
	cosmetic(cylinder(map, "Tap", -49.6, 39.3, B + 3.2, B + 4, 0.15, CHROME, Enum.Material.Metal), map.geometry)
	drawerFronts(dress(map, "WallCupboards", -52.4, B + 6, 38.4, -46.1, B + 8.5, 39.5, WHITE, Enum.Material.Wood, map:Folder("Trim")), Enum.NormalId.Front, 4, 1)
	dress(map, "Microwave", -47.8, B + 3.2, 38.4, -46.3, B + 4.1, 39.4, DARK_METAL, Enum.Material.Metal)
	dress(map, "CoffeeMachine", -52.2, B + 3.2, 38.6, -51.3, B + 4.4, 39.4, BLACK, Enum.Material.SmoothPlastic)
	block(map, "Table", -50, B, 22, -44, B + 2.8, 26, WOOD, Enum.Material.Wood)
	for _, x in { -48.5, -45.5 } do
		chair(map, x, 21, B, Vector3.zAxis, WOOD)
		chair(map, x, 27, B, -Vector3.zAxis, WOOD)
	end
	block(map, "Sofa", -55.5, B, 13, -53, B + 2.6, 20, LEATHER, Enum.Material.Fabric)
	seatDress(map, -55.5, 13, -53, 20, B + 2.6, -Vector3.xAxis, LEATHER, Enum.Material.Fabric, 1, 0.5)
	lockerDoors(block(map, "Lockers", -38, B, 14, -36.5, B + 7, 22, Color3.fromRGB(80, 90, 110), Enum.Material.Metal), Enum.NormalId.Left)

	-- Side entrance: cash machines (keypads, card slots), a bench; the manager's office (desk with
	-- his chair and two for visitors, a rug, the bookcase, a meeting table)
	for _, z in { -38, -34, -30 } do
		block(map, "ATM", 34.4, B, z, 35.5, B + 6, z + 2.5, DARK_METAL, Enum.Material.Metal)
		cosmetic(block(map, "ATMScreen", 34.3, B + 3.6, z + 0.5, 34.4, B + 4.8, z + 2, SCREEN, Enum.Material.Neon), map.geometry)
		dress(map, "ATMKeypad", 34.0, B + 2.9, z + 0.7, 34.4, B + 3.3, z + 1.8, STEEL, Enum.Material.Metal)
		dress(map, "CardSlot", 34.32, B + 3.5, z + 2.05, 34.4, B + 3.6, z + 2.35, Color3.fromRGB(80, 230, 120), Enum.Material.Neon)
	end
	block(map, "Bench", 23, B, -36, 24.5, B + 1.6, -30, DARK_WOOD, Enum.Material.Wood)
	seatDress(map, 23, -36, 24.5, -30, B + 1.6, -Vector3.xAxis, DARK_WOOD, Enum.Material.Wood, 1.6, 0.7)
	block(map, "ManagerDesk", 44, B, -32, 52, B + 2.8, -29, DARK_WOOD, Enum.Material.Wood)
	dress(map, "Monitor", 47, B + 2.8, -29.9, 49, B + 4.1, -29.6, BLACK, Enum.Material.SmoothPlastic)
	cosmetic(cylinder(map, "LampStem", 51, -30, B + 2.8, B + 4.2, 0.12, BRASS, Enum.Material.Metal), map.geometry)
	glow(dress(map, "LampShade", 50.5, B + 4.2, -30.5, 51.5, B + 4.6, -29.5, BANK_GREEN, Enum.Material.Glass), 8, 0.6, LAMP_GLOW)
	chair(map, 48, -34, B, Vector3.zAxis, LEATHER)
	chair(map, 46.5, -27.2, B, -Vector3.zAxis, LEATHER)
	chair(map, 49.5, -27.2, B, -Vector3.zAxis, LEATHER)
	rug(map, 41, -37, 54, -24, B, Color3.fromRGB(110, 44, 40))
	bookshelfFront(block(map, "Bookshelf", 54, B, -27, 55.5, B + 7, -23, DARK_WOOD, Enum.Material.Wood), Enum.NormalId.Left, 5, 11)
	block(map, "Sofa", 37, B, -38, 39.5, B + 2.6, -32, LEATHER, Enum.Material.Fabric)
	seatDress(map, 37, -38, 39.5, -32, B + 2.6, -Vector3.xAxis, LEATHER, Enum.Material.Fabric, 1, 0.5)
	block(map, "MeetingTable", 40, B, -20, 46, B + 2.8, -16, WOOD, Enum.Material.Wood)
	chair(map, 43, -21.2, B, Vector3.zAxis)
	chair(map, 43, -14.8, B, -Vector3.zAxis)
	picture(map, Vector3.new(36.5, B + 6, -30), Vector3.xAxis, 3, 2.2, 3)
	pottedPlant(map, 54.6, -13.6, B, 1.4, false)

	-- Loading dock: crates, a cash cart (wheels, push bar), cartons, safety lines on the floor
	block(map, "Crate", 32, B, -8, 36, B + 4, -4, PALLET, Enum.Material.WoodPlanks)
	block(map, "CashCart", 39, B, -9, 43, B + 4.5, -5, DARK_METAL, Enum.Material.DiamondPlate)
	for _, w in { { 39.5, -9.1 }, { 42.5, -9.1 }, { 39.5, -4.9 }, { 42.5, -4.9 } } do
		cosmetic(disc(map, "CartWheel", Vector3.new(w[1], B + 0.35, w[2]), "Z", 0.7, 0.2, BLACK, Enum.Material.Rubber), map.geometry)
	end
	cosmetic(rod(map, "CartHandle", Vector3.new(43.6, B + 4, -8.6), Vector3.new(43.6, B + 4, -5.4), 0.15, CHROME, Enum.Material.Metal), map.geometry)
	pallet(map, 36, 10, B, 3, CARDBOARD, Enum.Material.Cardboard)
	cosmetic(block(map, "SafetyLine", 53.6, B + 0.04, -6.5, 54, B + 0.07, 6.5, SAFETY_YELLOW, Enum.Material.SmoothPlastic), map:Folder("Shell"))
	cosmetic(block(map, "SafetyLine", 30.6, B + 0.04, -11.2, 53.6, B + 0.07, -10.8, SAFETY_YELLOW, Enum.Material.SmoothPlastic), map:Folder("Shell"))

	-- Upstairs: open-plan and accounting desks, the executive floor, servers, restrooms, offices
	for _, d in { { -50, -37 }, { -37, -37 }, { -50, -25 }, { -37, -25 } } do
		deskPod(map, d[1], d[2], F2)
	end
	for _, d in { { 25, -37 }, { 37, -37 }, { 47, -37 }, { 25, -28 }, { 47, -28 } } do
		deskPod(map, d[1], d[2], F2)
	end
	for _, p in { { -22, -14 }, { -22, -38 } } do
		pottedPlant(map, p[1], p[2], F2, 2, true)
	end
	-- Executive lounge: sofas on rugs round coffee tables, the bar with its stools and bottles
	for _, x in { -18, 2 } do
		rug(map, x - 1, -4, x + 7, 4, F2, Color3.fromRGB(150, 130, 100))
		block(map, "Sofa", x, F2, -3, x + 6, F2 + 2.6, -0.5, LEATHER, Enum.Material.Fabric)
		seatDress(map, x, -3, x + 6, -0.5, F2 + 2.6, -Vector3.zAxis, LEATHER, Enum.Material.Fabric, 1, 0.5)
		block(map, "CoffeeTable", x + 1, F2, 1, x + 5, F2 + 1.4, 3, DARK_WOOD, Enum.Material.Wood)
		dress(map, "Magazines", x + 1.6, F2 + 1.4, 1.5, x + 2.8, F2 + 1.5, 2.4, Color3.fromRGB(180, 60, 50), Enum.Material.SmoothPlastic)
	end
	block(map, "Bar", 15, F2, -10, 21, F2 + 3.4, -7.5, DARK_WOOD, Enum.Material.Wood)
	dress(map, "BarTop", 14.85, F2 + 3.4, -10.15, 21.15, F2 + 3.55, -7.35, GRANITE_DARK, Enum.Material.Granite)
	for i, x in { 15.8, 17, 18.2, 19.4 } do
		cosmetic(cylinder(map, "Bottle", x, -9.4, F2 + 3.55, F2 + 4.5 + noise(i) * 0.3, 0.3, BOOK_COLORS[i + 2], Enum.Material.Glass), map.geometry)
	end
	for _, x in { 16, 18, 20 } do
		cosmetic(cylinder(map, "StoolPost", x, -6.6, F2, F2 + 2.4, 0.2, CHROME, Enum.Material.Metal), map.geometry)
		cosmetic(disc(map, "StoolSeat", Vector3.new(x, F2 + 2.5, -6.6), "Y", 1.2, 0.25, LEATHER, Enum.Material.Fabric), map.geometry)
	end

	-- CEO's office: the desk (screen, lamp, his chair, two for visitors), a rug, the bookcase, a
	-- globe, paintings, the sofa
	block(map, "CEODesk", -16, F2, 30, -8, F2 + 2.8, 33.5, DARK_WOOD, Enum.Material.Wood)
	rug(map, -20, 29, -4, 38.5, F2, Color3.fromRGB(150, 120, 80))
	dress(map, "Monitor", -13, F2 + 2.8, 30.6, -11, F2 + 4.1, 30.9, BLACK, Enum.Material.SmoothPlastic)
	dress(map, "Keyboard", -12.9, F2 + 2.8, 32.4, -11.1, F2 + 2.9, 33, BLACK, Enum.Material.SmoothPlastic)
	cosmetic(cylinder(map, "LampStem", -9, 32.6, F2 + 2.8, F2 + 4.2, 0.12, BRASS, Enum.Material.Metal), map.geometry)
	glow(dress(map, "LampShade", -9.5, F2 + 4.2, 32.1, -8.5, F2 + 4.6, 33.1, BANK_GREEN, Enum.Material.Glass), 8, 0.6, LAMP_GLOW)
	chair(map, -12, 35, F2, -Vector3.zAxis, LEATHER)
	chair(map, -14.5, 28.6, F2, Vector3.zAxis, LEATHER)
	chair(map, -11, 28.6, F2, Vector3.zAxis, LEATHER)
	bookshelfFront(block(map, "Bookshelf", -23.5, F2, 9, -22, F2 + 8, 20, DARK_WOOD, Enum.Material.Wood), Enum.NormalId.Right, 6, 23)
	cosmetic(cylinder(map, "GlobeStand", -20.5, 36.5, F2, F2 + 2.4, 0.3, DARK_WOOD, Enum.Material.Wood), map.geometry)
	cosmetic(ball(map, "Globe", Vector3.new(-20.5, F2 + 3.1, 36.5), 1.5, Color3.fromRGB(70, 110, 140), Enum.Material.SmoothPlastic), map.geometry)
	picture(map, Vector3.new(-0.5, F2 + 6, 18), -Vector3.xAxis, 3.4, 2.4, 4)
	picture(map, Vector3.new(-19, F2 + 6, 6.5), Vector3.zAxis, 2.6, 3.2, 5)
	block(map, "Sofa", -6, F2, 9, -1, F2 + 2.6, 11.5, LEATHER, Enum.Material.Fabric)
	seatDress(map, -6, 9, -1, 11.5, F2 + 2.6, -Vector3.zAxis, LEATHER, Enum.Material.Fabric, 1, 0.5)

	-- Boardroom: the long table (a polished top, eight chairs, a speakerphone), pendant lamps over
	-- it, the screen with this quarter's chart, the cabinet
	block(map, "BoardTable", 8, F2, 12, 14, F2 + 2.8, 26, DARK_WOOD, Enum.Material.Wood)
	dress(map, "TableTop", 7.8, F2 + 2.8, 11.8, 14.2, F2 + 2.95, 26.2, Color3.fromRGB(60, 38, 26), Enum.Material.Wood)
	dress(map, "Speakerphone", 10.6, F2 + 2.95, 18.6, 11.4, F2 + 3.1, 19.4, BLACK, Enum.Material.SmoothPlastic)
	for _, z in { 14, 17.5, 21, 24.5 } do
		chair(map, 6.9, z, F2, Vector3.xAxis, LEATHER)
		chair(map, 15.1, z, F2, -Vector3.xAxis, LEATHER)
	end
	for i, z in { 15, 19, 23 } do
		cosmetic(cylinder(map, "PendantCord", 11, z, F2 + 8.2, CEILING, 0.08, BLACK, Enum.Material.SmoothPlastic), map.geometry)
		local shade = dress(map, "PendantShade", 10.3, F2 + 7.8, z - 0.7, 11.7, F2 + 8.2, z + 0.7, BRASS, Enum.Material.Metal)
		local bulb = dress(map, "PendantGlow", 10.45, F2 + 7.74, z - 0.55, 11.55, F2 + 7.8, z + 0.55, LAMP_GLOW, Enum.Material.Neon)
		if i == 2 then
			glow(bulb, 12, 0.7, LAMP_GLOW)
		end
		shade.CastShadow = false
	end
	drawerFronts(block(map, "Cabinet", 20, F2, 30, 21.5, F2 + 4, 38, DARK_WOOD, Enum.Material.Wood), Enum.NormalId.Left, 4, 1, BRASS)
	local screen = block(map, "Screen", 0.5, F2 + 3, 12, 0.7, F2 + 8, 22, BLACK, Enum.Material.SmoothPlastic)
	cosmetic(screen, map.geometry)
	local chart = surface(screen, Enum.NormalId.Right, 0)
	rectangle(chart, 0.3, 0.3, 9.4, 4.4, Color3.fromRGB(236, 238, 240))
	rectangle(chart, 0.8, 0.7, 4, 0.3, BANK_GREEN)
	for i = 1, 6 do
		local h = 0.8 + noise(i, 9) * 2.4
		rectangle(chart, 1 + i * 1.1, 4.2 - h, 0.7, h, if i == 6 then GOLD else Color3.fromRGB(60, 110, 160))
	end

	-- Server room: racks (status lights on their fronts), cable trays over the rows, a wall cooler
	for _, z in { 10, 18 } do -- (clear of the door and the hatch)
		for x = -53, -41, 3 do
			rackFront(block(map, "ServerRack", x, F2, z, x + 2.4, F2 + 7, z + 2.5, BLACK, Enum.Material.Metal), Enum.NormalId.Front, x + z)
		end
		local tray = dress(map, "CableTray", -53.5, F2 + 9.4, z + 0.5, -40, F2 + 9.7, z + 2, DARK_METAL, Enum.Material.DiamondPlate)
		glow(tray, 12, 0.5, Color3.fromRGB(120, 200, 255))
	end
	local cooler = dress(map, "WallCooler", -55.5, F2 + 8, 27, -54.7, F2 + 9.4, 31, WHITE, Enum.Material.SmoothPlastic, map:Folder("Trim"))
	drawerFronts(cooler, Enum.NormalId.Right, 1, 4, Color3.fromRGB(200, 200, 200))

	-- Restrooms: stalls with a toilet in each, the sinks (taps), a hand dryer
	for _, z in { -10, -6, -2, 2 } do
		block(map, "Stall", -55.5, F2, z - 0.1, -51, F2 + 6.5, z + 0.1, Color3.fromRGB(150, 160, 170), Enum.Material.SmoothPlastic)
	end
	for _, z in { -8, -4, 0 } do
		dress(map, "Toilet", -55.3, F2, z - 0.6, -53.9, F2 + 1.4, z + 0.6, WHITE, Enum.Material.Marble)
		dress(map, "Cistern", -55.5, F2 + 1.4, z - 0.8, -55, F2 + 3, z + 0.8, WHITE, Enum.Material.Marble)
	end
	local sinks = block(map, "Sinks", -50, F2, 4, -42, F2 + 3.2, 5.5, WHITE, Enum.Material.Marble)
	cosmetic(block(map, "Mirror", -50, F2 + 4, 5.4, -42, F2 + 7, 5.5, Color3.fromRGB(190, 205, 215), Enum.Material.Glass), map.geometry)
	local basins = surface(sinks, Enum.NormalId.Top)
	for i = 0, 2 do
		rectangle(basins, 1 + i * 2.5, 0.25, 1.5, 0.9, Color3.fromRGB(200, 204, 208))
		dress(map, "Tap", -48.6 + i * 2.5, F2 + 3.2, 5.1, -48.4 + i * 2.5, F2 + 3.8, 5.4, CHROME, Enum.Material.Metal)
	end
	dress(map, "HandDryer", -41.4, F2 + 4, 5.2, -40, F2 + 5, 5.5, CHROME, Enum.Material.Metal, map:Folder("Trim"))

	-- Loan and HR offices: a desk each (screen, chairs), filing cabinets
	block(map, "Desk", 33, F2, 6, 39, F2 + 2.8, 9, WOOD, Enum.Material.Wood)
	dress(map, "Monitor", 35, F2 + 2.8, 6.4, 37, F2 + 4.1, 6.7, BLACK, Enum.Material.SmoothPlastic)
	chair(map, 36, 10.2, F2, -Vector3.zAxis)
	chair(map, 34.5, 4.8, F2, Vector3.zAxis)
	chair(map, 37.5, 4.8, F2, Vector3.zAxis)
	drawerFronts(block(map, "FilingCabinets", 41, F2, -8, 42.5, F2 + 4.5, -2, Color3.fromRGB(120, 124, 130), Enum.Material.Metal), Enum.NormalId.Left, 4, 4)
	block(map, "Desk", 47, F2, -4, 53, F2 + 2.8, -1, WOOD, Enum.Material.Wood)
	dress(map, "Monitor", 49, F2 + 2.8, -1.9, 51, F2 + 4.1, -1.6, BLACK, Enum.Material.SmoothPlastic)
	chair(map, 50, -5.2, F2, Vector3.zAxis)
	chair(map, 48.5, 0.2, F2, -Vector3.zAxis)
	chair(map, 51.5, 0.2, F2, -Vector3.zAxis)
	drawerFronts(block(map, "FilingCabinets", 54, F2, 8, 55.5, F2 + 4.5, 14, Color3.fromRGB(120, 124, 130), Enum.Material.Metal), Enum.NormalId.Left, 4, 4)

	-- EXIT signs over the doors out and at the stairs
	exitSign(map, Vector3.new(29.5, B + 9.6, -39.5), Vector3.zAxis) -- side entrance
	exitSign(map, Vector3.new(46.5, B + 9.6, 39.5), -Vector3.zAxis) -- back stairs door
	exitSign(map, Vector3.new(-29.5, B + 9.6, 39.5), -Vector3.zAxis) -- west hall door
	exitSign(map, Vector3.new(38.5, F2 + 9.6, 16.5), Vector3.zAxis) -- top of the back stairs
	exitSign(map, Vector3.new(42.5, BF + 8.5, 22), -Vector3.xAxis) -- foot of the back stairs
	exitSign(map, Vector3.new(-35.5, BF + 8.5, 9), Vector3.xAxis) -- foot of the west hall stairs
end

local function wedge(map: MapBuilder.Builder, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material)
	local part = Instance.new("WedgePart")
	part.Name = name
	part.Size = size
	part.CFrame = cframe -- a WedgePart climbs toward its +Z
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.Parent = map.geometry
end

-- Parked car at (x, z), long side along x or z, standing on `base`, its nose toward +x / +z (-x /
-- -z with `reverse`). The body, the glass cabin and the wheels are solid (cover); the roof
-- panel, lights and bumper only look.
local function car(map: MapBuilder.Builder, x: number, z: number, alongX: boolean, color: Color3, base: number, parent: Instance?, reverse: boolean?)
	local at = Vector3.new(x, base, z)
	local nose = (if alongX then Vector3.xAxis else Vector3.zAxis) * (if reverse then -1 else 1)
	local frame = CFrame.lookAt(at, at + nose) -- (-Z forward, X across)
	local home = parent or map.geometry
	local function piece(name: string, size: Vector3, offset: Vector3, c: Color3, material: Enum.Material, solid: boolean): Part
		local part = map:Part(name, size, frame * CFrame.new(offset), c, material)
		if solid then
			part.Parent = home
		else
			cosmetic(part, home)
			part.CastShadow = false
		end
		return part
	end
	piece("Car", Vector3.new(5.2, 2, 12), Vector3.new(0, 1.9, 0), color, Enum.Material.SmoothPlastic, true)
	piece("CarCabin", Vector3.new(4.6, 1.7, 6.2), Vector3.new(0, 3.75, 0.5), TINTED_GLASS, Enum.Material.Glass, true)
	piece("CarRoof", Vector3.new(4.4, 0.2, 5), Vector3.new(0, 4.7, 0.8), color, Enum.Material.SmoothPlastic, false)
	for _, w in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		piece("Wheel", Vector3.new(0.9, 2, 2), Vector3.new(w[1] * 2.25, 1, w[2] * 3.9), BLACK, Enum.Material.Rubber, true).Shape = Enum.PartType.Cylinder
	end
	for _, s in { -1, 1 } do
		piece("Headlight", Vector3.new(1, 0.45, 0.1), Vector3.new(s * 1.75, 2.35, -6.02), Color3.fromRGB(255, 250, 225), Enum.Material.Neon, false)
	end
	piece("Taillights", Vector3.new(4.6, 0.35, 0.1), Vector3.new(0, 2.45, 6.02), Color3.fromRGB(200, 30, 30), Enum.Material.Neon, false)
	piece("Bumper", Vector3.new(5.3, 0.5, 0.3), Vector3.new(0, 1.15, -6.1), Color3.fromRGB(40, 40, 44), Enum.Material.SmoothPlastic, false)
end

-- Front portico (columns and the bank's name), the loading shutter, the roof's parapet and plant
local function buildFacade(map: MapBuilder.Builder)
	local porch = map:Floor("Porch", -27, -49, 25, -40.5, B, 0.4, LIMESTONE, Enum.Material.Limestone)
	-- Paving joints across the porch: slabs 4 studs wide, two deep
	local paving = surface(porch, Enum.NormalId.Top)
	for i = 1, 12 do
		rectangle(paving, i * 4 - 0.05, 0, 0.1, 8.5, LIMESTONE_JOINT)
	end
	rectangle(paving, 0, 4.2, 52, 0.1, LIMESTONE_JOINT)
	-- Columns: a torus over the square base, fluting up the shaft, a necking and an echinus under
	-- the square capital
	for _, x in { -21.5, -8, 5, 18 } do
		cylinder(map, "Column", x, -43.5, B + 1, 22.4, 2.6, LIMESTONE, Enum.Material.Limestone)
		block(map, "ColumnBase", x - 1.7, B, -45.2, x + 1.7, B + 1, -41.8, LIMESTONE, Enum.Material.Limestone)
		block(map, "Capital", x - 1.7, 22.4, -45.2, x + 1.7, 23.4, -41.8, LIMESTONE, Enum.Material.Limestone)
		cosmetic(disc(map, "ColumnTorus", Vector3.new(x, B + 1.3, -43.5), "Y", 3.2, 0.6, LIMESTONE, Enum.Material.Limestone), map.geometry)
		cosmetic(disc(map, "ColumnNeck", Vector3.new(x, 21.65, -43.5), "Y", 2.9, 0.3, LIMESTONE, Enum.Material.Limestone), map.geometry)
		cosmetic(disc(map, "ColumnEchinus", Vector3.new(x, 22.15, -43.5), "Y", 3.3, 0.5, LIMESTONE, Enum.Material.Limestone), map.geometry)
		for i = 0, 7 do
			local angle = i * math.pi / 4 + math.pi / 8
			local at = Vector3.new(x + math.cos(angle) * 1.27, (B + 1.6 + 21.5) / 2, -43.5 + math.sin(angle) * 1.27)
			dressAt(map, "Flute", Vector3.new(0.1, 21.5 - (B + 1.6), 0.16), CFrame.new(at) * CFrame.Angles(0, -angle, 0), LIMESTONE_SHADE, Enum.Material.Limestone)
		end
	end
	-- Entablature: an architrave step under the name, a row of dentils over it, the cornice on top
	block(map, "Entablature", -25, 23.4, -46.5, 23, ROOF + PARAPET, -40.5, LIMESTONE, Enum.Material.Limestone)
	cosmetic(block(map, "Architrave", -25.2, 23.4, -46.8, 23.2, 23.9, -46.5, LIMESTONE_LIGHT, Enum.Material.Limestone), map.geometry)
	local dentils = block(map, "Dentils", -25.3, 26.4, -46.85, 23.3, 26.75, -46.5, LIMESTONE_LIGHT, Enum.Material.Limestone)
	cosmetic(dentils, map.geometry)
	local teeth = surface(dentils, Enum.NormalId.Front)
	for i = 0, 68 do
		rectangle(teeth, 0.35 + i * 0.7, 0, 0.22, 0.35, LIMESTONE_JOINT)
	end
	cosmetic(block(map, "EntablatureCornice", -25.8, 26.75, -47.3, 23.8, 27.3, -40.5, LIMESTONE_LIGHT, Enum.Material.Limestone), map.geometry)
	local front = Vector3.new(-1, 25.15, -46.62)
	sign(map, "OAKHAVEN SAVINGS & TRUST", CFrame.lookAt(front, front - Vector3.zAxis), Vector2.new(40, 2.4), LIMESTONE, BANK_GREEN, true)
	local atm = Vector3.new(29.5, B + 9.6, -40.62)
	sign(map, "ATM", CFrame.lookAt(atm, atm - Vector3.zAxis), Vector2.new(3.6, 1.2), BANK_GREEN, WHITE)
	local stone = Vector3.new(-54.4, B + 2, -40.62)
	sign(map, "EST. 1924", CFrame.lookAt(stone, stone - Vector3.zAxis), Vector2.new(2.6, 1.2), LIMESTONE_LIGHT, Color3.fromRGB(90, 80, 64), true)

	-- Lanterns hanging under the portico between the columns
	for _, x in { -14.75, -1.5, 11.5 } do
		cosmetic(cylinder(map, "LanternChain", x, -43.5, 20.3, 23.4, 0.1, DARK_METAL, Enum.Material.Metal), map.geometry)
		dress(map, "LanternCap", x - 0.65, 20, -44.15, x + 0.65, 20.3, -42.85, DARK_METAL, Enum.Material.Metal)
		local lens = dress(map, "LanternGlow", x - 0.45, 18.5, -43.95, x + 0.45, 20, -43.05, LAMP_GLOW, Enum.Material.Neon)
		dress(map, "LanternBase", x - 0.55, 18.25, -44.05, x + 0.55, 18.5, -42.95, DARK_METAL, Enum.Material.Metal)
		glow(lens, 14, 1, LAMP_GLOW)
	end

	-- A cash machine in the wall east of the side entrance: granite surround, screen, keypad, hood
	dress(map, "ATMSurround", 33.2, 1.6, -40.85, 36.8, 7.8, -40.5, GRANITE_DARK, Enum.Material.Granite)
	dress(map, "ATMFascia", 33.6, 2.2, -40.92, 36.4, 7.2, -40.85, DARK_METAL, Enum.Material.Metal)
	dress(map, "ATMScreen", 34.3, 4.6, -40.95, 35.7, 5.6, -40.92, SCREEN, Enum.Material.Neon)
	dress(map, "ATMKeypad", 34.4, 3.4, -41.25, 35.6, 3.85, -40.92, STEEL, Enum.Material.Metal)
	dress(map, "ATMHood", 33, 7.8, -41.4, 37, 8.1, -40.5, DARK_METAL, Enum.Material.Metal)

	-- Night deposit slot in the side street wall
	dress(map, "NightDeposit", -56.75, B + 3.2, -11.8, -56.5, B + 4.6, -10.2, BRASS, Enum.Material.Metal)
	dress(map, "DepositSlot", -56.8, B + 3.9, -11.4, -56.75, B + 4.1, -10.6, BLACK, Enum.Material.SmoothPlastic)
	local deposit = Vector3.new(-56.62, B + 5, -11)
	sign(map, "NIGHT DEPOSIT", CFrame.lookAt(deposit, deposit - Vector3.xAxis), Vector2.new(1.8, 0.4), BANK_GREEN, WHITE, false, Enum.Font.GothamBold)

	-- Staff doors: a canopy and a lamp over each (just a lamp by the camera on the east wall)
	for _, d in { { -40.5, 40.5, 1, 0 }, { -29.5, 40.5, 1, 0 }, { 26, 40.5, 1, 0 }, { 46.5, 40.5, 1, 0 }, { -27.5, -56.5, 0, -1 }, { 11.5, 56.5, 0, 1 } } do
		local along, at, alongX, out = d[1], d[2], d[3] == 1, d[4]
		if alongX then
			dress(map, "DoorCanopy", along - 3, B + 9.9, at, along + 3, B + 10.15, at + 1.8, DARK_METAL, Enum.Material.Metal, map:Folder("Trim"))
			wallLamp(map, Vector3.new(along, B + 9.4, at), Vector3.zAxis)
		else
			if out < 0 then
				dress(map, "DoorCanopy", at - 1.8, B + 9.9, along - 3, at, B + 10.15, along + 3, DARK_METAL, Enum.Material.Metal, map:Folder("Trim"))
			end
			wallLamp(map, Vector3.new(at, B + 9.4, along), Vector3.xAxis * out)
		end
	end

	-- Downpipes from the roof (around the belt course, a hopper under the cornice)
	for _, p in { { -53, 40.5, 0, 1 }, { 53, 40.5, 0, 1 }, { -56.5, 37.5, -1, 0 }, { 56.5, 37.5, 1, 0 } } do
		local x, z = p[1] + p[3] * 0.3, p[2] + p[4] * 0.3 -- (standing just off the wall's face)
		local pipe = Color3.fromRGB(110, 114, 118)
		for _, run in { { 1.6, B + GROUND_WALL - 0.3 }, { F2 + 0.15, CEILING - 1.5 } } do
			dress(map, "Downpipe", x - 0.25, run[1], z - 0.25, x + 0.25, run[2], z + 0.25, pipe, Enum.Material.Metal, map:Folder("Trim"))
		end
		dress(map, "Hopper", x - 0.45, CEILING - 1.5, z - 0.45, x + 0.45, CEILING - 0.8, z + 0.45, pipe, Enum.Material.Metal, map:Folder("Trim"))
	end

	-- Loading dock: the shutter rolled up on its drum, guide rails
	local drum = map:Part("ShutterDrum", Vector3.new(13, 1.5, 1.5), CFrame.new(55.1, B + 11.2, 0) * CFrame.Angles(0, math.pi / 2, 0), DARK_METAL, Enum.Material.Metal)
	drum.Shape = Enum.PartType.Cylinder
	cosmetic(drum, map.geometry)
	for _, z in { -6.3, 6.3 } do
		cosmetic(block(map, "ShutterRail", 54.95, B, z - 0.15, 55.25, B + 10.8, z + 0.15, DARK_METAL, Enum.Material.Metal), map.geometry)
	end
	local loading = Vector3.new(56.62, B + 11, 0)
	sign(map, "LOADING", CFrame.lookAt(loading, loading + Vector3.xAxis), Vector2.new(8, 1.4), BANK_GREEN, WHITE)
	-- A canopy over the dock on two stays, rubber bumpers either side of the opening
	dress(map, "DockCanopy", 56.5, B + 11.8, -7.5, 60.5, B + 12.1, 7.5, DARK_METAL, Enum.Material.Metal)
	for _, z in { -6, 6 } do
		cosmetic(rod(map, "CanopyStay", Vector3.new(56.6, B + 14.6, z), Vector3.new(60.3, B + 12.1, z), 0.15, DARK_METAL, Enum.Material.Metal), map.geometry)
		dress(map, "DockBumper", 56.5, B, z + (if z < 0 then -1.1 else 0.5), 57.1, B + 1.8, z + (if z < 0 then -0.5 else 1.1), BLACK, Enum.Material.Rubber)
	end

	-- Roof: parapet on the outside walls (a stone coping on top, lightning rods at the corners),
	-- air-conditioning units with their ducts, vents, the antenna and a satellite dish
	map:Wall("Parapet", -56.5, -40, 56.5, -40, ROOF, PARAPET, nil, LIMESTONE, Enum.Material.Limestone)
	map:Wall("Parapet", -56.5, 40, 56.5, 40, ROOF, PARAPET, nil, LIMESTONE, Enum.Material.Limestone)
	map:Wall("Parapet", -56, -39.5, -56, 39.5, ROOF, PARAPET, nil, LIMESTONE, Enum.Material.Limestone)
	map:Wall("Parapet", 56, -39.5, 56, 39.5, ROOF, PARAPET, nil, LIMESTONE, Enum.Material.Limestone)
	local top = ROOF + PARAPET
	for _, c in { { -57.2, -40.7, 57.2, -39.3 }, { -57.2, 39.3, 57.2, 40.7 }, { -56.7, -39.3, -55.3, 39.3 }, { 55.3, -39.3, 56.7, 39.3 } } do
		cosmetic(block(map, "Coping", c[1], top, c[2], c[3], top + 0.25, c[4], LIMESTONE_LIGHT, Enum.Material.Limestone), map.geometry)
	end
	for _, c in { { -56, -40 }, { 56, -40 }, { -56, 40 }, { 56, 40 } } do
		cosmetic(cylinder(map, "LightningRod", c[1], c[2], top + 0.25, top + 3.2, 0.12, DARK_METAL, Enum.Material.Metal), map.geometry)
	end
	for _, u in { { -40, 24 }, { 28, 26 }, { -30, -22 } } do
		local unit = block(map, "HVAC", u[1] - 3, ROOF, u[2] - 2.5, u[1] + 3, ROOF + 3.6, u[2] + 2.5, Color3.fromRGB(196, 198, 194), Enum.Material.Metal)
		local fan = map:Part("HVACFan", Vector3.new(0.3, 3.2, 3.2), CFrame.new(u[1] + 1, ROOF + 3.7, u[2]) * CFrame.Angles(0, 0, math.pi / 2), DARK_METAL, Enum.Material.DiamondPlate)
		fan.Shape = Enum.PartType.Cylinder
		-- Louvres down the long sides, a duct from the end into the roof
		for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
			local gui = surface(unit, face)
			for i = 0, 7 do
				rectangle(gui, 0.4, 0.4 + i * 0.36, 5.2, 0.14, Color3.fromRGB(120, 122, 120))
			end
		end
		dress(map, "Duct", u[1] - 6, ROOF, u[2] - 0.8, u[1] - 3, ROOF + 1.4, u[2] + 0.8, Color3.fromRGB(170, 172, 170), Enum.Material.Metal)
	end
	for _, v in { { 0, 18 }, { -48, -6 }, { 44, 4 } } do
		cylinder(map, "RoofVent", v[1], v[2], ROOF, ROOF + 2.4, 2.2, Color3.fromRGB(170, 174, 178), Enum.Material.Metal)
	end
	for _, v in { { -20, 10 }, { 12, 30 }, { -50, 36 }, { 30, -6 } } do
		cosmetic(cylinder(map, "VentPipe", v[1], v[2], ROOF, ROOF + 1.6, 0.45, DARK_METAL, Enum.Material.Metal), map.geometry)
	end
	cosmetic(cylinder(map, "Antenna", 48, 32, ROOF, ROOF + 14, 0.4, DARK_METAL, Enum.Material.Metal), map.geometry)
	cosmetic(cylinder(map, "DishMount", 43, 34, ROOF, ROOF + 2.2, 0.3, DARK_METAL, Enum.Material.Metal), map.geometry)
	local dishAt = Vector3.new(43, ROOF + 3, 34)
	local dish = map:Part("Dish", Vector3.new(0.25, 3, 3), CFrame.lookAt(dishAt, dishAt + Vector3.new(0, 0.7, -1)) * CFrame.Angles(0, math.pi / 2, 0), WHITE, Enum.Material.SmoothPlastic)
	dish.Shape = Enum.PartType.Cylinder
	cosmetic(dish, map.geometry)
end

-- The dressing that follows the walls (see `walls`). Outside: a granite plinth, a stone belt
-- course at the upper floor, the cornice under the parapet, a lintel over every window (and a
-- keystone on the limestone front), mullions and transoms in the glass, joints cut into the
-- limestone. Door leaves stand open against the hard walls. All looks only (bullets go through),
-- and in Trim, so a breach takes whatever it hits down with the wall.
local CASING = 0.45 -- (MapBuilder's trim round openings)
local function dressWalls(map: MapBuilder.Builder)
	local trim = map:Folder("Trim")
	-- Box along wall `w`: a1..a2 along it, y1..y2 up, c1..c2 across it from its centre line
	local function onWall(w: WallRecord, name: string, a1: number, a2: number, y1: number, y2: number, c1: number, c2: number, color: Color3, material: Enum.Material, shadow: boolean?): Part
		local cMin, cMax = w.at + math.min(c1, c2), w.at + math.max(c1, c2)
		local part = if w.alongX
			then block(map, name, a1, y1, cMin, a2, y2, cMax, color, material)
			else block(map, name, cMin, y1, a1, cMax, y2, a2, color, material)
		cosmetic(part, trim)
		part.CastShadow = shadow == true
		return part
	end

	-- Door leaves first (the plinth runs round them)
	local stairs = { { BASEMENT_STAIRS, BF }, { MAIN_STAIRS, B }, { DOWN_FLIGHT, BF }, { UP_FLIGHT, B } }
	local leaves: { [WallRecord]: { { number } } } = {}
	-- Does a leaf fit on wall `w` from a1 to a2 along it, against the face on `side` (±1)?
	local function fits(w: WallRecord, a1: number, a2: number, side: number): boolean
		if a1 < w.from + 0.6 or a2 > w.to - 0.6 then
			return false
		end
		for _, o in w.openings do
			if o.from - 0.5 < a2 and o.to + 0.5 > a1 then
				return false
			end
		end
		local c = w.at + side * 0.7
		for _, other in walls do
			if other.base == w.base and other.alongX ~= w.alongX and other.at > a1 - 0.6 and other.at < a2 + 0.6 and c > other.from and c < other.to then
				return false -- a wall meets this face there
			end
		end
		local c1, c2 = math.min(w.at + side * 0.5, c), math.max(w.at + side * 0.5, c)
		for _, s in stairs do
			local r = s[1]
			if s[2] == w.base then
				local x1, z1, x2, z2 = a1, c1, a2, c2
				if not w.alongX then
					x1, z1, x2, z2 = c1, a1, c2, a2
				end
				if x1 < r[3] and x2 > r[1] and z1 < r[4] and z2 > r[2] then
					return false
				end
			end
		end
		return true
	end
	local function leaf(w: WallRecord, o: MapBuilder.Opening, a1: number, a2: number, side: number, hingeHigh: boolean, color: Color3, glazed: boolean)
		local part = onWall(w, "DoorLeaf", a1, a2, w.base + 0.05, w.base + o.top - 0.1, side * 0.6, side * 0.72, color, Enum.Material.Metal, true)
		local free = if hingeHigh then a1 + 0.35 else a2 - 0.35
		if glazed then
			onWall(w, "DoorPull", free - 0.07, free + 0.07, w.base + 2.8, w.base + 5.4, side * 0.72, side * 0.9, BRASS, Enum.Material.Metal)
		else
			onWall(w, "DoorHandle", free - 0.3, free + 0.3, w.base + 3.3, w.base + 3.45, side * 0.72, side * 0.88, CHROME, Enum.Material.Metal)
		end
		local face = if w.alongX then (if side > 0 then Enum.NormalId.Back else Enum.NormalId.Front) else (if side > 0 then Enum.NormalId.Right else Enum.NormalId.Left)
		local fw, fh = faceSize(part, face)
		local gui = surface(part, face)
		if glazed then
			rectangle(gui, 0.35, 0.45, fw - 0.7, fh - 2, Color3.fromRGB(70, 92, 108)) -- the glass
		else
			rectangle(gui, fw * 0.3, 1.2, fw * 0.4, 1.4, Color3.fromRGB(70, 92, 108)) -- vision panel
		end
		rectangle(gui, 0.2, fh - 1, fw - 0.4, 0.8, color:Lerp(Color3.new(0, 0, 0), 0.3)) -- kick plate
		leaves[w] = leaves[w] or {}
		table.insert(leaves[w], { a1, a2, w.base + o.top })
	end
	for _, w in walls do
		if w.style.soft or w.style == VAULT_WALL or w.style == COUNTER then
			continue -- (only hard walls: a leaf on a soft one would hide the holes shot in it)
		end
		local sides = if w.style.exterior then { -(w.inside or 1) } else { 1, -1 }
		local glazed = w.style == OUTSIDE_STONE
		local color = if glazed then BRONZE elseif w.style == OUTSIDE_BRICK then BANK_GREEN else Color3.fromRGB(120, 126, 132)
		for _, o in w.openings do
			if o.kind ~= "Door" then
				continue
			end
			local double = o.to - o.from > 6
			local placed = false
			for _, width in if double then { (o.to - o.from) / 2 - 0.2, 3, 2.6 } else { o.to - o.from - 0.4, 3.5 } do
				for _, side in sides do
					local low, high = { o.from - 0.5 - width, o.from - 0.5 }, { o.to + 0.5, o.to + 0.5 + width }
					if double then
						if fits(w, low[1], low[2], side) and fits(w, high[1], high[2], side) then
							leaf(w, o, low[1], low[2], side, true, color, glazed)
							leaf(w, o, high[1], high[2], side, false, color, glazed)
							placed = true
						end
					elseif fits(w, low[1], low[2], side) then
						leaf(w, o, low[1], low[2], side, true, color, glazed)
						placed = true
					elseif fits(w, high[1], high[2], side) then
						leaf(w, o, high[1], high[2], side, false, color, glazed)
						placed = true
					end
					if placed then
						break
					end
				end
				if placed then
					break
				end
			end
		end
	end

	-- Stretches of wall `w` clear of its openings (and their casings, and any door leaf) between
	-- heights y1 and y2, running `stretch` past either end to wrap the corners
	local function spans(w: WallRecord, y1: number, y2: number, stretch: number): { { number } }
		local blocked = {}
		for _, o in w.openings do
			if w.base + (o.bottom or 0) < y2 and w.base + o.top > y1 then
				table.insert(blocked, { o.from - CASING, o.to + CASING })
			end
		end
		for _, l in leaves[w] or {} do
			if l[3] > y1 then
				table.insert(blocked, { l[1], l[2] })
			end
		end
		table.sort(blocked, function(a, b)
			return a[1] < b[1]
		end)
		local result = {}
		local cursor = w.from - stretch
		for _, b in blocked do
			if b[1] > cursor then
				table.insert(result, { cursor, b[1] })
			end
			cursor = math.max(cursor, b[2])
		end
		if w.to + stretch > cursor then
			table.insert(result, { cursor, w.to + stretch })
		end
		return result
	end

	for _, w in walls do
		if not w.style.exterior or w.base == BF then
			continue
		end
		local out = -(w.inside or 1)
		local stone = not w.style.soft
		local front = w.style == OUTSIDE_STONE
		local function band(name: string, y1: number, y2: number, depth: number, color: Color3, material: Enum.Material, shadow: boolean)
			for _, s in spans(w, y1, y2, if w.alongX then depth else 0.5) do
				onWall(w, name, s[1], s[2], y1, y2, out * 0.5, out * (0.5 + depth), color, material, shadow)
			end
		end
		if w.base == B then
			-- (the belt course stops short of a soft wall upstairs, so breaching that leaves it be)
			local upstairsSoft = true
			for _, other in walls do
				if other.base == F2 and other.style.exterior and other.alongX == w.alongX and other.at == w.at then
					upstairsSoft = other.style.soft == true
				end
			end
			band("Plinth", 0.15, 1.6, 0.3, GRANITE_DARK, Enum.Material.Granite, false)
			band("BeltCourse", B + GROUND_WALL - 0.3, if upstairsSoft then F2 - 0.05 else F2 + 0.15, 0.4, LIMESTONE_LIGHT, Enum.Material.Limestone, true)
		else
			band("Cornice", CEILING - 0.8, ROOF + 0.1, 0.45, LIMESTONE_LIGHT, Enum.Material.Limestone, true)
			band("CorniceCap", ROOF - 0.15, ROOF + 0.3, 0.85, LIMESTONE_LIGHT, Enum.Material.Limestone, true)
		end
		for _, o in w.openings do
			if o.kind ~= "Window" then
				continue
			end
			local bottom, top = w.base + (o.bottom or 0), w.base + o.top
			local mid = (o.from + o.to) / 2
			onWall(w, "Lintel", o.from - 0.75, o.to + 0.75, top + CASING, top + CASING + 0.7, out * 0.5, out * 0.75, if stone then LIMESTONE_LIGHT else STUCCO:Lerp(Color3.new(0, 0, 0), 0.08), if stone then Enum.Material.Limestone else Enum.Material.Plaster, true)
			if front then
				onWall(w, "Keystone", mid - 0.45, mid + 0.45, top + 0.25, top + 1.45, out * 0.5, out * 0.85, LIMESTONE_LIGHT, Enum.Material.Limestone, true)
			end
			local bar = if front then BRONZE else DARK_METAL
			if o.to - o.from >= 5 then
				onWall(w, "Mullion", mid - 0.1, mid + 0.1, bottom, top, -0.14, 0.14, bar, Enum.Material.Metal)
			end
			if top - bottom >= 6 then
				local y = bottom + (top - bottom) * 0.7
				onWall(w, "Transom", o.from, o.to, y - 0.1, y + 0.1, -0.14, 0.14, bar, Enum.Material.Metal)
			end
		end
	end

	-- Joints cut into the limestone front: deep rustication on the ground floor (courses 2 studs
	-- high, joints staggered every 4), fine ashlar upstairs (every 5). The stone isn't breakable,
	-- so a drawing on it is safe.
	for _, piece in map.geometry:GetChildren() do
		if not (piece:IsA("BasePart") and piece.Name == "ExteriorWall" and piece.Material == Enum.Material.Limestone) then
			continue
		end
		local w, h = piece.Size.X, piece.Size.Y
		local top = piece.Position.Y + h / 2
		local bottom = top - h
		local left = piece.Position.X + w / 2 -- (seen from the street, the drawing's left is the +x end)
		local ground = bottom < F2 - 0.5
		local joint = if ground then 0.14 else 0.06
		local module = if ground then 4 else 5
		local color = if ground then LIMESTONE_JOINT else LIMESTONE_SHADE
		local floor = if ground then B else F2
		local gui = surface(piece, Enum.NormalId.Front)
		for k = 0, 6 do
			local y = floor + k * 2
			if y > bottom + 0.01 and y < top - 0.01 then
				rectangle(gui, 0, top - y - joint / 2, w, joint, color)
			end
			local y1, y2 = math.max(y, bottom), math.min(y + 2, top)
			if y2 - y1 > 0.05 then
				local x = -56.5 + (k % 2) * module / 2
				while x < 56.5 do
					if x > left - w + 0.05 and x < left - 0.05 then
						rectangle(gui, left - x - joint / 2, top - y2, joint, y2 - y1, color)
					end
					x += module
				end
			end
		end
	end
end

-- A neighbouring block (one of the buildings round the edge): a cornice along its top, and on
-- the face that looks into the map a grid of windows floor by floor (the odd one lit), a band
-- over the ground floor and, where there are no shop fronts, doors and shop windows below it.
-- `seed` varies the window sizes and rhythm from building to building.
local function dressNeighbour(map: MapBuilder.Builder, building: BasePart, seed: number)
	local size, center = building.Size, building.Position
	local x1, x2 = center.X - size.X / 2, center.X + size.X / 2
	local z1, z2 = center.Z - size.Z / 2, center.Z + size.Z / 2
	local height = size.Y
	local trimColor = building.Color:Lerp(Color3.new(0, 0, 0), 0.25)
	dress(map, "Cornice", x1 - 0.5, height, z1 - 0.5, x2 + 0.5, height + 0.8, z2 + 0.5, trimColor, building.Material)
	-- Which face looks into the map (the row it's in)
	local face, out
	if z2 <= -104 then
		face, out = Enum.NormalId.Back, Vector3.zAxis
	elseif z1 >= 104 then
		face, out = Enum.NormalId.Front, -Vector3.zAxis
	elseif x2 <= -94 then
		face, out = Enum.NormalId.Right, Vector3.xAxis
	else
		face, out = Enum.NormalId.Left, -Vector3.xAxis
	end
	local w, h = faceSize(building, face)
	local gui = surface(building, face, 0.8)
	local brick = building.Material == Enum.Material.Brick
	local frameColor = if brick then Color3.fromRGB(214, 206, 190) else Color3.fromRGB(70, 74, 80)
	local module = 4.5 + noise(seed, 1) * 1.5
	local pitch = 5.5 + noise(seed, 2) * 1
	local winW, winH = module * (0.5 + noise(seed, 3) * 0.15), pitch * 0.55
	local bays = math.floor((w - 3) / module)
	local start = (w - bays * module) / 2
	local floor = 10.5
	local row = 0
	while floor + winH < height - 2.5 do
		row += 1
		for bay = 0, bays - 1 do
			local lit = noise(seed * 7 + bay, row) > 0.86
			local pane = rectangle(gui, start + bay * module + (module - winW) / 2, height - floor - winH - 0.6, winW, winH, if lit then Color3.fromRGB(240, 214, 150) else vary(TINTED_GLASS, 0.25, bay, row + seed))
			pane.BorderSizePixel = 4
			pane.BorderColor3 = frameColor
			rectangle(pane, winW / 2 - 0.06, 0, 0.12, winH, frameColor) -- the sash bar
		end
		floor += pitch
	end
	-- A band over the ground floor, and its doors and windows (the main street side has real shop
	-- fronts instead)
	local along = if out.X ~= 0 then Vector3.zAxis else Vector3.xAxis
	local faceAt = if out.X ~= 0 then (if out.X > 0 then x2 else x1) else (if out.Z > 0 then z2 else z1)
	if out.Z <= 0 then
		local a1, a2 = if along.X ~= 0 then x1 else z1, if along.X ~= 0 then x2 else z2
		if along.X ~= 0 then
			dress(map, "GroundBand", a1, 9.4, math.min(faceAt, faceAt + out.Z * 0.35), a2, 10, math.max(faceAt, faceAt + out.Z * 0.35), trimColor, building.Material)
		else
			dress(map, "GroundBand", math.min(faceAt, faceAt + out.X * 0.35), 9.4, a1, math.max(faceAt, faceAt + out.X * 0.35), 10, a2, trimColor, building.Material)
		end
		local count = math.max(1, math.floor(w / 12))
		for k = 0, count - 1 do
			local at = (k + 0.5) * w / count
			if (k + seed) % 3 == 0 then
				rectangle(gui, at - 1.6, height - 7.6, 3.2, 7.4, Color3.fromRGB(34, 32, 30)) -- door
			else
				local shop = rectangle(gui, at - 3.5, height - 8, 7, 5.4, vary(TINTED_GLASS, 0.2, k, seed))
				shop.BorderSizePixel = 4
				shop.BorderColor3 = frameColor
			end
		end
	end
end

-- Street furniture, all in the Yard (PerimeterService: none of it is a roof). Only tree trunks
-- and the light and signal poles are solid; the rest only looks (bullets and people go through).
local function buildStreetFurniture(map: MapBuilder.Builder)
	local yard = map:Folder("Yard")
	local function bit(name: string, x1: number, y1: number, z1: number, x2: number, y2: number, z2: number, color: Color3, material: Enum.Material?): Part
		return dress(map, name, x1, y1, z1, x2, y2, z2, color, material, yard)
	end
	local function post(name: string, x: number, z: number, y1: number, y2: number, diameter: number, color: Color3, material: Enum.Material, solid: boolean?): Part
		local part = cylinder(map, name, x, z, y1, y2, diameter, color, material)
		part.Parent = yard
		if not solid then
			cosmetic(part, yard)
			part.CastShadow = false
		end
		return part
	end

	-- Traffic lights at the crossing: a pole, an arm over the lane, the signal head (red lit), a
	-- crossing signal on the pole
	for _, t in { { 11.5, -61.2, -1, -1 }, { -11.5, -92.8, 1, 1 } } do
		local x, z, over, facing = t[1], t[2], t[3], t[4]
		post("SignalPole", x, z, CURB, 15.4, 0.45, DARK_METAL, Enum.Material.Metal, true)
		local tip = Vector3.new(x, 15, z + over * 8)
		cosmetic(rod(map, "SignalArm", Vector3.new(x, 15, z), tip, 0.25, DARK_METAL, Enum.Material.Metal), yard)
		bit("SignalHead", tip.X - 0.45, 12, tip.Z - 0.45, tip.X + 0.45, 14.8, tip.Z + 0.45, Color3.fromRGB(30, 32, 30), Enum.Material.Metal)
		for i, c in { Color3.fromRGB(240, 40, 30), Color3.fromRGB(90, 70, 20), Color3.fromRGB(20, 70, 40) } do
			local y = 14.35 - (i - 1) * 0.85
			local lensX = tip.X + facing * 0.47
			bit("SignalLens", math.min(lensX, lensX + facing * 0.06), y - 0.3, tip.Z - 0.3, math.max(lensX, lensX + facing * 0.06), y + 0.3, tip.Z + 0.3, c, if i == 1 then Enum.Material.Neon else Enum.Material.SmoothPlastic)
		end
		local box = Vector3.new(x + facing * 0.55, CURB + 7.6, z) -- (on the crossing's side of the pole)
		bit("CrossingSignal", box.X - 0.3, box.Y - 0.5, z - 0.45, box.X + 0.3, box.Y + 0.5, z + 0.45, Color3.fromRGB(30, 32, 30), Enum.Material.Metal)
		bit("CrossingHand", box.X + facing * 0.31 - 0.02, box.Y - 0.3, z - 0.3, box.X + facing * 0.31 + 0.02, box.Y + 0.3, z + 0.3, Color3.fromRGB(255, 120, 30), Enum.Material.Neon)
	end

	-- Bus shelter on the far side: roof, glass back, posts, a bench, an advert panel, the stop sign
	bit("ShelterRoof", -46.3, 8, -103.8, -37.7, 8.3, -100, DARK_METAL, Enum.Material.Metal)
	bit("ShelterGlass", -46, CURB + 0.6, -103.6, -38, 7.9, -103.45, Color3.fromRGB(170, 200, 215), Enum.Material.Glass).Transparency = 0.6
	for _, x in { -46, -38 } do
		bit("ShelterPost", x - 0.12, CURB, -100.4, x + 0.12, 8, -100.16, DARK_METAL, Enum.Material.Metal)
	end
	bit("ShelterBench", -44, CURB + 1.1, -103.3, -40, CURB + 1.4, -102.3, CHROME, Enum.Material.Metal)
	local advert = bit("Advert", -46.25, CURB + 0.6, -103.4, -46.05, 7.6, -100.6, WHITE, Enum.Material.SmoothPlastic)
	local ad = surface(advert, Enum.NormalId.Right, 0.4)
	rectangle(ad, 0.2, 0.2, 2.4, 6.6, BANK_GREEN)
	for i, line in { { "OAKHAVEN", 0.6, GOLD }, { "SAVINGS & TRUST", 1.3, WHITE }, { "HOME LOANS", 3.6, WHITE }, { "FROM 3.9%", 4.4, GOLD } } do
		local text = Instance.new("TextLabel")
		text.Size = UDim2.fromOffset(2.2 * PIXELS, 0.6 * PIXELS)
		text.Position = UDim2.fromOffset(0.3 * PIXELS, line[2] * PIXELS)
		text.BackgroundTransparency = 1
		text.Font = if i <= 2 then Enum.Font.Garamond else Enum.Font.GothamBold
		text.TextScaled = true
		text.TextColor3 = line[3]
		text.Text = line[1]
		text.Parent = ad
	end
	post("StopPole", -36.8, -100.4, CURB, 9, 0.18, DARK_METAL, Enum.Material.Metal)
	local stop = Vector3.new(-36.8, 8.3, -100.28)
	sign(map, "BUS  12", CFrame.lookAt(stop, stop + Vector3.zAxis), Vector2.new(1.6, 0.9), Color3.fromRGB(30, 80, 160), WHITE, false, Enum.Font.GothamBold).Parent = yard

	-- Bins, fire hydrants, newspaper boxes, parking meters, manholes, bollards
	for _, b in { { -55.6, -58.3 }, { 64.4, -58.3 }, { 17.8, -93.4 }, { -50, -93.4 } } do
		post("Bin", b[1], b[2], CURB, CURB + 2.8, 1.4, Color3.fromRGB(40, 70, 52), Enum.Material.Metal)
		cosmetic(disc(map, "BinLid", Vector3.new(b[1], CURB + 2.85, b[2]), "Y", 1.5, 0.12, DARK_METAL, Enum.Material.Metal), yard)
	end
	for _, h in { { -38.5, -61.2 }, { 44, -61.2 }, { -68.8, -30 }, { 70, -93.2 } } do
		post("Hydrant", h[1], h[2], CURB, CURB + 1.9, 0.8, Color3.fromRGB(190, 40, 34), Enum.Material.Metal)
		dressAt(map, "HydrantCap", Vector3.one * 0.75, CFrame.new(h[1], CURB + 1.95, h[2]), Color3.fromRGB(190, 40, 34), Enum.Material.Metal, yard).Shape = Enum.PartType.Ball
		cosmetic(rod(map, "HydrantNozzle", Vector3.new(h[1] - 0.6, CURB + 1.3, h[2]), Vector3.new(h[1] + 0.6, CURB + 1.3, h[2]), 0.32, CHROME, Enum.Material.Metal), yard)
	end
	for i, c in { Color3.fromRGB(40, 70, 150), Color3.fromRGB(170, 40, 40), Color3.fromRGB(220, 180, 40) } do
		local x = 12.2 + (i - 1) * 1.5
		bit("NewsBox", x, CURB, -94.2, x + 1.2, CURB + 2.6, -93.2, c, Enum.Material.Metal)
		bit("NewsWindow", x + 0.15, CURB + 1.4, -93.22, x + 1.05, CURB + 2.3, -93.18, PAPER, Enum.Material.Glass)
	end
	for _, m in { { -79, -61.2 }, { -51, -61.2 }, { 25, -61.2 }, { 57, -61.2 }, { 91, -61.2 }, { -55, -92.8 }, { -17, -92.8 }, { 49, -92.8 }, { 91, -92.8 }, { 117, -92.8 } } do
		post("MeterPost", m[1], m[2], CURB, CURB + 3.3, 0.18, DARK_METAL, Enum.Material.Metal)
		bit("Meter", m[1] - 0.3, CURB + 3.3, m[2] - 0.22, m[1] + 0.3, CURB + 4.2, m[2] + 0.22, STEEL, Enum.Material.Metal)
	end
	for _, m in { { -60, -72 }, { 20, -82 }, { -82, -30 }, { 40, 56 }, { 100, 0 } } do
		cosmetic(disc(map, "Manhole", Vector3.new(m[1], STREET + 0.015, m[2]), "Y", 2.4, 0.03, Color3.fromRGB(46, 44, 42), Enum.Material.DiamondPlate), yard)
	end
	for _, x in { -26, -22, -18, -14, 14, 18, 22, 26 } do
		post("Bollard", x, -60.6, CURB, CURB + 2.8, 0.7, DARK_METAL, Enum.Material.Metal)
	end

	-- Street trees in iron grates: the trunks are solid, the crowns only look
	local trees = { { -84, -59.5 }, { -66, -59.5 }, { 74, -59.5 }, { 104, -59.5 }, { -80, -96.5 }, { -60, -96.5 }, { 30, -96.5 }, { 56, -96.5 }, { 96, -96.5 }, { -66.5, -20 }, { -66.5, 22 } }
	for i, t in trees do
		local x, z = t[1], t[2]
		bit("TreeGrate", x - 1.4, CURB, z - 1.4, x + 1.4, CURB + 0.03, z + 1.4, Color3.fromRGB(46, 44, 42), Enum.Material.DiamondPlate)
		post("TreeTrunk", x, z, CURB, CURB + 8, 0.7, BARK, Enum.Material.Wood, true)
		local crown = vary(LEAF, 0.12, i)
		cosmetic(ball(map, "TreeCrown", Vector3.new(x, CURB + 9.8, z), 7, crown, Enum.Material.Grass), yard)
		cosmetic(ball(map, "TreeCrown", Vector3.new(x + 0.9, CURB + 12.2, z - 0.6), 5, crown:Lerp(Color3.new(1, 1, 1), 0.06), Enum.Material.Grass), yard)
	end
end

local function buildOutside(map: MapBuilder.Builder)
	local yard = map:Folder("Yard") -- (PerimeterService: cars and the bus aren't a roof)
	local function toYard(parts: { BasePart })
		for _, part in parts do
			part.Parent = yard
		end
	end

	-- Ground: asphalt everywhere (not under the bank or down the ramp), sidewalks on top along the
	-- front, the far side of the main street and the bank's west side
	local footprint = { -56.5, -40.5, 56.5, 40.5 }
	local trench = { 56.5, -31, 98, -17 }
	map:FloorWithHoles("Street", -104, -116, 136, 112, { footprint, trench }, STREET, 0.4, ASPHALT, Enum.Material.Asphalt)
	local sidewalks = {
		map:Floor("Sidewalk", -94, -62, 128, -40.5, CURB, 0.3, SIDEWALK, Enum.Material.Concrete),
		map:Floor("Sidewalk", -94, -104, 128, -92, CURB, 0.3, SIDEWALK, Enum.Material.Concrete),
		map:Floor("Sidewalk", -70, -40.5, -56.5, 40.5, CURB, 0.3, SIDEWALK, Enum.Material.Concrete),
	}
	-- Joints between the paving slabs (5-stud squares)
	for _, walk in sidewalks do
		local w, h = faceSize(walk, Enum.NormalId.Top)
		local gui = surface(walk, Enum.NormalId.Top)
		for i = 1, math.floor(w / 5) do
			rectangle(gui, i * 5 - 0.06, 0, 0.12, h, Color3.fromRGB(140, 138, 132))
		end
		for i = 1, math.floor(h / 5) do
			rectangle(gui, 0, i * 5 - 0.06, w, 0.12, Color3.fromRGB(140, 138, 132))
		end
	end
	-- Granite kerbs along the road edges, a darker gutter in front of them
	local paint = map:Folder("Paint")
	for _, k in { { -94, -62, 128, -61.5, -63 }, { -94, -92.5, 128, -92, -91 }, { -94, -41, -70, -40.5, -39.5 } } do
		dress(map, "Kerb", k[1], 0, k[2], k[3], CURB + 0.04, k[4], GRANITE_LIGHT, Enum.Material.Granite)
		local edge = if k[5] < k[2] then k[2] else k[4]
		cosmetic(block(map, "Gutter", k[1], STREET - 0.02, math.min(edge, k[5]), k[3], STREET + 0.02, math.max(edge, k[5]), Color3.fromRGB(44, 44, 48), Enum.Material.Concrete), paint)
	end
	dress(map, "Kerb", -70, 0, -40.5, -69.5, CURB + 0.04, 40.5, GRANITE_LIGHT, Enum.Material.Granite)
	cosmetic(block(map, "Gutter", -71, STREET - 0.02, -40.5, -70, STREET + 0.02, 40.5, Color3.fromRGB(44, 44, 48), Enum.Material.Concrete), paint)
	-- Granite paving across the plaza in front of the portico, in big slabs with a border
	local plaza = dress(map, "Plaza", -27, CURB, -61.5, 25, CURB + 0.03, -49, GRANITE_LIGHT, Enum.Material.Granite)
	local slabs = surface(plaza, Enum.NormalId.Top)
	rectangle(slabs, 0, 0, 52, 12.5, GRANITE_LIGHT)
	grid(slabs, 0.8, 0.8, 50.4, 10.9, 12, 3, 0.1, function(col, row)
		return vary(GRANITE_LIGHT, 0.05, col, row)
	end)
	for _, z in { -77.3, -76.7 } do
		cosmetic(block(map, "CenterLine", -94, STREET - 0.02, z - 0.15, 128, STREET + 0.03, z + 0.15, PAINT_YELLOW, Enum.Material.SmoothPlastic), paint)
	end
	for x = -8, 8, 4 do
		cosmetic(block(map, "Crosswalk", x - 0.9, STREET - 0.02, -91.5, x + 0.9, STREET + 0.03, -62.5, PAINT_WHITE, Enum.Material.SmoothPlastic), paint)
	end
	-- Parking lane lines either side, stop lines before the crossing
	for _, z in { -70.5, -83.5 } do
		for _, run in { { -94, -9.5 }, { 9.5, 128 } } do
			cosmetic(block(map, "LaneLine", run[1], STREET - 0.02, z - 0.15, run[2], STREET + 0.03, z + 0.15, PAINT_WHITE, Enum.Material.SmoothPlastic), paint)
		end
	end
	cosmetic(block(map, "StopLine", -11.6, STREET - 0.02, -91.5, -11, STREET + 0.03, -77.4, PAINT_WHITE, Enum.Material.SmoothPlastic), paint)
	cosmetic(block(map, "StopLine", 11, STREET - 0.02, -76.6, 11.6, STREET + 0.03, -62.5, PAINT_WHITE, Enum.Material.SmoothPlastic), paint)
	for z = -28, 52, 10 do -- parking bays along the east lot's far side
		cosmetic(block(map, "BayLine", 108, STREET - 0.02, z - 0.15, 124, STREET + 0.03, z + 0.15, PAINT_WHITE, Enum.Material.SmoothPlastic), paint)
	end

	-- Parking ramp from the east lot down to the basement garage, between retaining walls
	map:Floor("RampLanding", 56.5, -30, 62, -18, BF, 1, CONCRETE, Enum.Material.Concrete)
	local rise = STREET - BF
	wedge(map, "Ramp", Vector3.new(12, rise, 36), CFrame.lookAt(Vector3.new(80, BF + rise / 2, -24), Vector3.new(79, BF + rise / 2, -24)), CONCRETE, Enum.Material.Concrete)
	for _, z in { -30.5, -17.5 } do
		map:Wall("RetainingWall", 56.5, z, 98, z, BF, 3.4 - BF, nil, CONCRETE, Enum.Material.Concrete)
	end

	-- Neighbouring buildings all round: the edge of the block (and of the world)
	local neighbours = {
		{ -104, -116, -44, -104, 36, Color3.fromRGB(120, 96, 84), Enum.Material.Brick },
		{ -44, -116, 10, -104, 30, Color3.fromRGB(180, 170, 150), Enum.Material.Concrete },
		{ 10, -116, 70, -104, 42, Color3.fromRGB(110, 120, 130), Enum.Material.Concrete },
		{ 70, -116, 136, -104, 34, Color3.fromRGB(150, 90, 70), Enum.Material.Brick },
		{ -104, -104, -94, -20, 32, Color3.fromRGB(160, 150, 130), Enum.Material.Concrete },
		{ -104, -20, -94, 50, 38, Color3.fromRGB(130, 80, 66), Enum.Material.Brick },
		{ -104, 50, -94, 112, 30, Color3.fromRGB(120, 124, 128), Enum.Material.Concrete },
		{ -94, 104, -20, 112, 34, Color3.fromRGB(150, 100, 80), Enum.Material.Brick },
		{ -20, 104, 50, 112, 30, Color3.fromRGB(170, 162, 146), Enum.Material.Concrete },
		{ 50, 104, 136, 112, 36, Color3.fromRGB(120, 86, 72), Enum.Material.Brick },
		{ 128, -104, 136, -30, 32, Color3.fromRGB(140, 140, 136), Enum.Material.Concrete },
		{ 128, -30, 136, 40, 38, Color3.fromRGB(130, 84, 70), Enum.Material.Brick },
		{ 128, 40, 136, 104, 30, Color3.fromRGB(165, 155, 140), Enum.Material.Concrete },
	}
	for i, n in neighbours do
		dressNeighbour(map, block(map, "Building", n[1], 0, n[2], n[3], n[5], n[4], n[6], n[7]), i)
	end
	-- Shop fronts across the main street: mullions and doors in the glass, a striped awning with
	-- a valance, the shop's sign over it
	local shops = {
		{ -96, -50, "CORNER CAFÉ", Color3.fromRGB(120, 40, 40) },
		{ -40, 4, "PHARMACY", Color3.fromRGB(40, 110, 80) },
		{ 14, 64, "DELI & GROCER", BANK_GREEN },
		{ 74, 124, "BOOKSELLERS", Color3.fromRGB(40, 50, 100) },
	}
	for i, s in shops do
		local glass = block(map, "Storefront", s[1], CURB, -103.95, s[2], 8, -103.85, Color3.fromRGB(40, 50, 60), Enum.Material.Glass)
		cosmetic(glass, map.geometry)
		local width = s[2] - s[1]
		local front = surface(glass, Enum.NormalId.Back)
		rectangle(front, 0, 5.6, width, 0.18, Color3.fromRGB(70, 72, 76)) -- transom bar
		for k = 0, math.floor(width / 4) do
			rectangle(front, k * 4 - 0.08, 0, 0.16, 7.7, Color3.fromRGB(70, 72, 76))
		end
		for _, at in { width * 0.25, width * 0.75 } do
			rectangle(front, at - 1.4, 2.4, 2.8, 5.3, Color3.fromRGB(28, 30, 34)) -- a door
			rectangle(front, at + 0.9, 4.6, 0.12, 1, CHROME)
		end
		local awning = block(map, "Awning", s[1], 8.4, -103.85, s[2], 8.8, -101.5, s[4], Enum.Material.Fabric)
		cosmetic(awning, map.geometry)
		local valance = dress(map, "Valance", s[1], 7.8, -101.6, s[2], 8.4, -101.4, s[4], Enum.Material.Fabric)
		for _, part in { awning, valance } do
			local face = if part == awning then Enum.NormalId.Bottom else Enum.NormalId.Back
			local w, h = faceSize(part, face)
			local stripes = surface(part, face)
			for k = 0, math.floor(w / 2) do
				rectangle(stripes, k * 2, 0, 1, h, Color3.fromRGB(236, 232, 220))
			end
		end
		local at = Vector3.new((s[1] + s[2]) / 2, 10, -103.75)
		sign(map, s[3], CFrame.lookAt(at, at + Vector3.zAxis), Vector2.new(math.min(width * 0.5, 16), 1.4), Color3.fromRGB(30, 32, 36), if i % 2 == 0 then GOLD else WHITE, false, if i % 2 == 0 then Enum.Font.Garamond else Enum.Font.GothamBold)
	end

	-- Main street: parked cars both sides and a bus (cover on the way in)
	local colors = { Color3.fromRGB(180, 30, 30), Color3.fromRGB(40, 60, 120), Color3.fromRGB(210, 210, 205), BLACK, Color3.fromRGB(120, 120, 125), Color3.fromRGB(60, 110, 70) }
	for i, x in { -74, -46, 30, 62, 96 } do
		car(map, x, -67, true, colors[i % #colors + 1], STREET, yard, true)
	end
	for i, x in { -60, -12, 44, 86, 112 } do
		car(map, x, -87, true, colors[(i + 2) % #colors + 1], STREET, yard)
	end
	-- The bus: windows down both sides, windscreen and destination board at the front (east),
	-- a door, lights, wheels
	local busWhite = Color3.fromRGB(220, 220, 214)
	toYard({
		block(map, "Bus", -32, STREET + 0.8, -80, -6, STREET + 10, -74, busWhite, Enum.Material.SmoothPlastic),
		block(map, "BusStripe", -32.05, STREET + 3, -80.05, -5.95, STREET + 4, -73.95, BANK_GREEN, Enum.Material.SmoothPlastic),
	})
	dress(map, "BusWindows", -30, STREET + 5.4, -80.06, -8, STREET + 8.6, -73.94, TINTED_GLASS, Enum.Material.Glass, yard)
	dress(map, "BusWindscreen", -6, STREET + 4.2, -79.6, -5.9, STREET + 9.2, -74.4, TINTED_GLASS, Enum.Material.Glass, yard)
	local board = dress(map, "BusBoard", -5.9, STREET + 9.3, -79, -5.85, STREET + 9.9, -75, BLACK, Enum.Material.SmoothPlastic, yard)
	local boardText = Instance.new("TextLabel")
	boardText.Size = UDim2.fromScale(1, 1)
	boardText.BackgroundTransparency = 1
	boardText.Font = Enum.Font.Arcade
	boardText.TextScaled = true
	boardText.TextColor3 = Color3.fromRGB(255, 170, 40)
	boardText.Text = "12  DOWNTOWN"
	boardText.Parent = surface(board, Enum.NormalId.Right, 0)
	dress(map, "BusDoor", -9.6, STREET + 1.2, -73.96, -7.2, STREET + 8.6, -73.9, TINTED_GLASS, Enum.Material.Glass, yard)
	dress(map, "BusLights", -5.95, STREET + 2.2, -79.4, -5.88, STREET + 2.6, -74.6, Color3.fromRGB(255, 250, 225), Enum.Material.Neon, yard)
	dress(map, "BusTaillights", -32.12, STREET + 2.2, -79.4, -32.05, STREET + 2.6, -74.6, Color3.fromRGB(200, 30, 30), Enum.Material.Neon, yard)
	for _, x in { -27.5, -10.5 } do
		for _, z in { -80.05, -73.95 } do
			local wheel = map:Part("Wheel", Vector3.new(0.8, 2.4, 2.4), CFrame.new(x, STREET + 1.2, z) * CFrame.Angles(0, math.pi / 2, 0), BLACK, Enum.Material.Rubber)
			wheel.Shape = Enum.PartType.Cylinder
			wheel.Parent = yard
		end
	end

	-- Plaza in front of the bank: planters (cover), benches, flagpoles either side of the portico
	for _, x in { -44, -34, 34, 46 } do
		block(map, "Planter", x - 3, CURB, -53.5, x + 3, CURB + 2.2, -50.5, CONCRETE, Enum.Material.Concrete)
		block(map, "Hedge", x - 2.7, CURB + 2.2, -53.2, x + 2.7, CURB + 3.4, -50.8, HEDGE, Enum.Material.Grass)
		dress(map, "PlanterCap", x - 3.15, CURB + 2.2, -53.65, x + 3.15, CURB + 2.4, -50.35, GRANITE_LIGHT, Enum.Material.Granite)
	end
	for _, x in { -62, 58 } do
		block(map, "Bench", x, CURB, -59, x + 5, CURB + 1.6, -57.5, DARK_WOOD, Enum.Material.Wood)
		seatDress(map, x, -59, x + 5, -57.5, CURB + 1.6, Vector3.zAxis, DARK_WOOD, Enum.Material.Wood, 1.6, 0.7)
	end
	for _, x in { -31, 29 } do
		cylinder(map, "Flagpole", x, -46, CURB, 30, 0.4, WHITE, Enum.Material.Metal)
		cosmetic(block(map, "Flag", x + 0.2, 26, -46.05, x + 5, 29, -45.95, BANK_GREEN, Enum.Material.Fabric), map.geometry)
	end

	-- Side street (west): parked cars, a dumpster
	car(map, -78, -20, false, colors[2], STREET, yard)
	car(map, -78, 16, false, colors[5], STREET, yard)
	block(map, "Dumpster", -66, CURB, 28, -60, CURB + 4.1, 31.5, Color3.fromRGB(40, 90, 60), Enum.Material.Metal)

	-- Back alley and staff lot (north): dumpsters, staff cars, concrete barriers
	for _, x in { -12, 36 } do
		block(map, "Dumpster", x - 3, STREET, 42, x + 3, STREET + 4.2, 45.5, Color3.fromRGB(40, 90, 60), Enum.Material.Metal)
		block(map, "DumpsterLid", x - 3.2, STREET + 4.2, 41.8, x + 3.2, STREET + 4.5, 45.7, Color3.fromRGB(30, 30, 32), Enum.Material.Plastic)
	end
	for i, c in { { -60, 74 }, { -44, 74 }, { 24, 78 }, { 62, 72 }, { 76, 58 } } do
		car(map, c[1], c[2], false, colors[i], STREET, yard)
	end
	for _, w in { { -30, 60, -22, 60 }, { 6, 66, 14, 66 }, { 46, 58, 54, 58 }, { -70, 52, -70, 60 }, { 84, -46, 92, -46 } } do
		map:Wall("Barrier", w[1], w[2], w[3], w[4], STREET, 3, nil, CONCRETE, Enum.Material.Concrete, 1.2)
	end

	-- Parking lot (east): the armoured truck at the loading dock, cars
	local truckBox = block(map, "ArmouredTruck", 63, STREET + 0.9, -8, 70, STREET + 8, 6, Color3.fromRGB(70, 84, 76), Enum.Material.Metal)
	toYard({
		truckBox,
		block(map, "TruckCab", 63.5, STREET + 0.9, 6, 69.5, STREET + 6.5, 11, Color3.fromRGB(70, 84, 76), Enum.Material.Metal),
		block(map, "TruckWindscreen", 63.8, STREET + 4.2, 10.9, 69.2, STREET + 6.2, 11.05, Color3.fromRGB(30, 34, 40), Enum.Material.Glass),
		block(map, "Tyres", 62.8, STREET, -6, 70.2, STREET + 1.6, -3, BLACK, Enum.Material.Rubber),
		block(map, "Tyres", 62.8, STREET, 6.5, 70.2, STREET + 1.6, 9.5, BLACK, Enum.Material.Rubber),
	})
	-- Its side windows, headlights, a beacon on the cab, hubs on the tyres, the company's name
	-- and the rear doors drawn on the box
	dress(map, "TruckWindows", 63.45, STREET + 4.4, 7, 69.55, STREET + 6, 10, TINTED_GLASS, Enum.Material.Glass, yard)
	for _, x in { 64.2, 68.8 } do
		dress(map, "TruckHeadlight", x - 0.5, STREET + 2.4, 11, x + 0.5, STREET + 2.9, 11.08, Color3.fromRGB(255, 250, 225), Enum.Material.Neon, yard)
	end
	dress(map, "TruckBeacon", 66, STREET + 6.5, 8, 67, STREET + 6.9, 9, Color3.fromRGB(255, 160, 40), Enum.Material.Neon, yard)
	for _, x in { 62.75, 70.25 } do
		for _, z in { -4.5, 8 } do
			cosmetic(disc(map, "Hub", Vector3.new(x, STREET + 0.8, z), "X", 0.9, 0.1, CHROME, Enum.Material.Metal), yard)
		end
	end
	for _, face in { Enum.NormalId.Left, Enum.NormalId.Right } do
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(0.8, 0.22)
		label.Position = UDim2.fromScale(0.1, 0.3)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(222, 182, 70)
		label.Text = "OAKHAVEN SECURE"
		label.Parent = surface(truckBox, face)
	end
	local rear = surface(truckBox, Enum.NormalId.Front)
	rectangle(rear, 3.47, 0.4, 0.06, 6.4, Color3.fromRGB(40, 48, 44))
	rectangle(rear, 0.3, 0.4, 6.4, 0.06, Color3.fromRGB(40, 48, 44))
	rectangle(rear, 3.1, 3.4, 0.25, 0.7, CHROME)
	car(map, 112, -36, true, colors[1], STREET, yard)
	car(map, 90, 26, false, colors[3], STREET, yard)
	car(map, 112, 48, true, colors[4], STREET, yard)

	-- Garage (basement): staff cars
	car(map, 29.5, -36, true, colors[6], BF)
	car(map, 43, -36, true, colors[3], BF)
	car(map, 49, -2, true, colors[2], BF)

	-- Street lights: a pole on a base (solid), an arm out over the road with the lamp head
	for _, p in { { -50, -60, 0, -1 }, { 0, -60, 0, -1 }, { 50, -60, 0, -1 }, { -82, 10, -1, 0 }, { 0, 62, 0, 1 }, { 60, 80, 0, -1 }, { 110, -50, 1, 0 }, { 110, 30, -1, 0 } } do
		local x, z, arm = p[1], p[2], Vector3.new(p[3], 0, p[4])
		cylinder(map, "LampBase", x, z, STREET, STREET + 1.2, 1, DARK_METAL, Enum.Material.Metal).Parent = yard
		cylinder(map, "LightPole", x, z, STREET + 1.2, 17.8, 0.45, DARK_METAL, Enum.Material.Metal).Parent = yard
		local tip = Vector3.new(x, 17.6, z) + arm * 3
		cosmetic(rod(map, "LampArm", Vector3.new(x, 17.6, z), tip, 0.22, DARK_METAL, Enum.Material.Metal), yard)
		local frame = CFrame.lookAt(tip, tip + arm)
		dressAt(map, "LampHead", Vector3.new(0.9, 0.45, 1.9), frame * CFrame.new(0, -0.1, -0.6), DARK_METAL, Enum.Material.Metal, yard)
		local lens = dressAt(map, "LampGlow", Vector3.new(0.7, 0.08, 1.6), frame * CFrame.new(0, -0.36, -0.6), Color3.fromRGB(255, 240, 210), Enum.Material.Neon, yard)
		local light = glow(lens, 40, 1.6, Color3.fromRGB(255, 236, 200), Enum.NormalId.Bottom)
		light.Shadows = true
	end
	buildStreetFurniture(map)

	-- Invisible walls at the edge of the world
	for _, edge in { { -104, -116, 136, -116 }, { -104, 112, 136, 112 }, { -104, -116, -104, 112 }, { 136, -116, 136, 112 } } do
		for _, piece in map:Wall("Boundary", edge[1], edge[2], edge[3], edge[4], -20, 120, nil, Color3.new(), nil, 2) do
			piece.Transparency = 1
			piece.CanQuery = false
		end
	end
end

function Bank.Build(): Model
	local map = MapBuilder.new("Bank")
	table.clear(walls)
	buildFloors(map)
	buildBasement(map)
	buildGround(map)
	buildUpstairs(map)
	buildStairs(map)
	buildProps(map)
	buildFacade(map)
	dressWalls(map)
	buildOutside(map)

	-- Sites: four pairs, A and B each; the defenders pick one pair per round
	local function site(name: string, x1: number, z1: number, x2: number, z2: number, level: number, pair: string, room: string)
		map:Site(name, Vector3.new(x1 + 0.5, level, z1 + 0.5), Vector3.new(x2 - 0.5, level + 6, z2 - 0.5), pair, room)
	end
	site("A", -24, 16, 6, 40, BF, "Vault", "Vault")
	site("B", -24, -14, 6, 16, BF, "Vault", "Deposit boxes")
	site("A", 0, 6, 22, 40, B, "Tellers", "Teller office")
	site("B", -24, 6, 0, 40, B, "Tellers", "Archives")
	site("A", -56, -12, -36, 12, B, "Security", "CCTV room")
	site("B", -56, 12, -36, 40, B, "Security", "Staff lounge")
	site("A", -24, 6, 0, 40, F2, "Executive", "CEO office")
	site("B", 0, 6, 22, 40, F2, "Executive", "Boardroom")

	-- Defenders spawn in the pair they picked; attackers on the main street, in the staff lot or
	-- in the parking lot
	map:SpawnPad("Defend", Vector3.new(-9, BF + 0.1, 21), Vector3.new(0, 0, 1), "Vault")
	map:SpawnPad("Defend", Vector3.new(8, B + 0.1, 22), Vector3.new(1, 0, 0), "Tellers")
	map:SpawnPad("Defend", Vector3.new(-46, B + 0.1, 32), Vector3.new(0, 0, -1), "Security")
	map:SpawnPad("Defend", Vector3.new(10, F2 + 0.1, 35), Vector3.new(0, 0, -1), "Executive")
	map:SpawnPad("Attack", Vector3.new(-24, CURB + 0.1, -98), Vector3.new(0, 0, 1))
	map:SpawnPad("Attack", Vector3.new(-10, STREET + 0.1, 90), Vector3.new(0, 0, -1))
	map:SpawnPad("Attack", Vector3.new(114, STREET + 0.1, 10), Vector3.new(-1, 0, 0))
	map:FreeRoamSpawn(Vector3.new(0, 0.5, -54))

	return map.model
end

return Bank
