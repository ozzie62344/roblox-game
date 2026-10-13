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
-- skylight: x, z
local LIGHT_SPOTS = {
	Lobby = { { -12, -32 }, { 14, -32 } },
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

-- Wall along x at `z`, or along z at `x`
local function wallX(map: MapBuilder.Builder, style: MapBuilder.Style, z: number, x1: number, x2: number, base: number, height: number, openings: { MapBuilder.Opening }?, inside: number?)
	map:RoomWall(style, x1, z, x2, z, base, height, openings, inside)
end

local function wallZ(map: MapBuilder.Builder, style: MapBuilder.Style, x: number, z1: number, z2: number, base: number, height: number, openings: { MapBuilder.Opening }?, inside: number?)
	map:RoomWall(style, x, z1, x, z2, base, height, openings, inside)
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

-- Flat sign with text on its outward (front, -Z of `cframe`) face
local function sign(map: MapBuilder.Builder, text: string, cframe: CFrame, size: Vector2, background: Color3, textColor: Color3)
	local board = map:Part("Sign", Vector3.new(size.X, size.Y, 0.2), cframe, background, Enum.Material.SmoothPlastic)
	cosmetic(board, map.geometry)
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
	label.Font = Enum.Font.Garamond
	label.TextScaled = true
	label.TextColor3 = textColor
	label.Text = text
	label.Parent = gui
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
	for _, x in { -2, 4 } do
		cosmetic(block(map, "GlazingBar", x - 0.15, ROOF - 0.8, z1, x + 0.15, ROOF - 0.6, z2, DARK_METAL, Enum.Material.Metal), map.geometry)
	end
	cosmetic(block(map, "GlazingBar", x1, ROOF - 0.8, -32.15, x2, ROOF - 0.6, -31.85, DARK_METAL, Enum.Material.Metal), map.geometry)
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

-- Pallet at (x, z) with a stack on it (cash in the vault, cartons elsewhere)
local function pallet(map: MapBuilder.Builder, x: number, z: number, base: number, height: number, color: Color3, material: Enum.Material)
	block(map, "Pallet", x - 2, base, z - 2, x + 2, base + 0.4, z + 2, PALLET, Enum.Material.WoodPlanks)
	block(map, "Stack", x - 1.8, base + 0.4, z - 1.8, x + 1.8, base + 0.4 + height, z + 1.8, color, material)
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
end

-- Pair of desks facing each other across a fabric partition, 8 × 5 from (x, z)
local function deskPod(map: MapBuilder.Builder, x: number, z: number, base: number)
	block(map, "Desks", x, base, z, x + 8, base + 2.6, z + 5, WOOD, Enum.Material.Wood)
	block(map, "Partition", x, base, z + 2.35, x + 8, base + 4.6, z + 2.65, FABRIC, Enum.Material.Fabric)
	for _, side in { 1.2, 3.8 } do
		cosmetic(block(map, "Monitor", x + 3, base + 2.6, z + side - 0.15, x + 5, base + 3.9, z + side + 0.15, BLACK, Enum.Material.SmoothPlastic), map.geometry)
	end
end

local function buildVault(map: MapBuilder.Builder)
	-- Vault: safe-deposit boxes floor to ceiling on two walls, pallets of cash, a table of gold
	local boxes = Enum.Material.DiamondPlate
	block(map, "DepositBoxes", -23.5, BF, 37.6, 5.5, BF + 9, 39.5, VAULT_STEEL, boxes)
	block(map, "DepositBoxes", -23.5, BF, 16.5, -21.6, BF + 9, 37.6, VAULT_STEEL, boxes)
	pallet(map, -14, 30, BF, 3, CASH, Enum.Material.SmoothPlastic)
	pallet(map, -3, 28, BF, 3.6, CASH, Enum.Material.SmoothPlastic)
	block(map, "Table", -10, BF, 33, -4, BF + 3, 36, DARK_METAL, Enum.Material.Metal)
	block(map, "GoldBars", -9.4, BF + 3, 33.6, -4.6, BF + 3.6, 35.4, GOLD, Enum.Material.Foil)
	-- The barred gate from the deposit boxes, swung back against the vault wall
	local gate = block(map, "Gate", -18.8, BF, 16.6, -18.6, BF + 7.6, 21.4, DARK_METAL, Enum.Material.DiamondPlate)
	gate.Transparency = 0.35

	-- The round door, swung open into the vault lobby on a massive hinge (it stays open: cover)
	local spin = CFrame.Angles(0, math.pi / 2, 0) -- disc faces along z
	local disc = map:Part("VaultDoor", Vector3.new(1.6, 10, 10), CFrame.new(12.6, BF + 5.3, 32.6) * spin, VAULT_STEEL, Enum.Material.DiamondPlate)
	disc.Shape = Enum.PartType.Cylinder
	local wheel = map:Part("VaultWheel", Vector3.new(0.5, 3.6, 3.6), CFrame.new(12.6, BF + 5.3, 31.55) * spin, BRASS, Enum.Material.Metal)
	wheel.Shape = Enum.PartType.Cylinder
	cosmetic(wheel, map.geometry)
	block(map, "VaultHinge", 6.5, BF + 1.5, 31.6, 7.8, BF + 9, 33.6, DARK_METAL, Enum.Material.Metal)
	-- Steel collar round the doorway (lobby side)
	block(map, "VaultFrame", 6.5, BF, 22.4, 7.3, BF + 9, 24, DARK_METAL, Enum.Material.Metal)
	block(map, "VaultFrame", 6.5, BF, 31, 7.3, BF + 9, 31.6, DARK_METAL, Enum.Material.Metal)
	block(map, "VaultFrame", 6.5, BF + 7.5, 24, 7.3, BF + 9, 31, DARK_METAL, Enum.Material.Metal)
	sign(map, "VAULT", CFrame.lookAt(Vector3.new(6.72, BF + 9.9, 27.5), Vector3.new(7.72, BF + 9.9, 27.5)), Vector2.new(6, 1.4), DARK_METAL, GOLD)

	-- Deposit boxes: walls of boxes, two islands of them (cover), a viewing table
	block(map, "DepositBoxes", -12.3, BF, 13.6, 5.5, BF + 9, 15.5, VAULT_STEEL, boxes)
	block(map, "DepositBoxes", -23.5, BF, 13.6, -18.7, BF + 9, 15.5, VAULT_STEEL, boxes)
	block(map, "DepositBoxes", -10.3, BF, -13.5, 5.5, BF + 9, -11.6, VAULT_STEEL, boxes)
	block(map, "BoxIsland", -17, BF, 2, -13, BF + 6, 10, VAULT_STEEL, boxes)
	block(map, "BoxIsland", -1, BF, 4, 3, BF + 6, 12, VAULT_STEEL, boxes)
	block(map, "ViewingTable", -20, BF, -10, -14, BF + 3, -7, WOOD, Enum.Material.Wood)
end

local function buildProps(map: MapBuilder.Builder)
	buildVault(map)

	-- Basement: records shelving, the guard room, garage, service hall, plant rooms, lockers
	shelves(map, -20, -36, -5, -34.5, BF, 7)
	shelves(map, -20, -28, -5, -26.5, BF, 7)
	shelves(map, -16, -21, -3, -19.5, BF, 7)
	block(map, "GuardDesk", 4, BF, -38, 12, BF + 2.8, -35, DARK_METAL, Enum.Material.Metal)
	block(map, "Monitors", 5, BF + 2.8, -38, 11, BF + 5, -37.4, BLACK, Enum.Material.SmoothPlastic)
	block(map, "GunLockers", 20, BF, -22, 21.5, BF + 7, -15, Color3.fromRGB(70, 80, 70), Enum.Material.Metal)
	block(map, "Table", 8, BF, -26, 14, BF + 2.8, -22, WOOD, Enum.Material.Wood)
	for _, x in { 33, 45 } do
		block(map, "Pillar", x - 1, BF, -13, x + 1, B - 1, -11, CONCRETE, Enum.Material.Concrete)
	end
	block(map, "Crate", 25, BF, 18, 29, BF + 4, 22, PALLET, Enum.Material.WoodPlanks)
	block(map, "Crate", 50, BF, 35, 54, BF + 4.5, 39, PALLET, Enum.Material.WoodPlanks)
	pallet(map, 50, 9, BF, 3.2, CARDBOARD, Enum.Material.Cardboard)
	cosmetic(block(map, "ElevatorDoors", 24.5, BF, 39.3, 31.5, BF + 9, 39.5, DARK_METAL, Enum.Material.Metal), map.geometry)
	block(map, "ElectricalCabinets", -54, BF, -39.5, -40, BF + 7, -37.6, Color3.fromRGB(120, 124, 130), Enum.Material.Metal)
	block(map, "Transformer", -52, BF, -26, -46, BF + 5, -21, Color3.fromRGB(80, 96, 80), Enum.Material.Metal)
	block(map, "Lockers", -55.5, BF, -10, -54, BF + 7, 10, Color3.fromRGB(80, 90, 110), Enum.Material.Metal)
	block(map, "Lockers", -47, BF, -6, -45, BF + 7, 8, Color3.fromRGB(80, 90, 110), Enum.Material.Metal)
	block(map, "Bench", -52, BF, -6, -50, BF + 1.6, 6, WOOD, Enum.Material.Wood)
	for _, z in { 22, 33 } do
		cylinder(map, "Boiler", -50, z, BF, BF + 9, 5, Color3.fromRGB(150, 60, 50), Enum.Material.Metal)
	end
	block(map, "Pump", -42, BF, 18, -38, BF + 4, 22, DARK_METAL, Enum.Material.Metal)
	for _, z in { 38.4, 39.2 } do
		cosmetic(block(map, "Pipe", -55.5, B - 2.4, z - 0.3, -38, B - 1.8, z + 0.3, DARK_METAL, Enum.Material.Metal), map.geometry)
	end

	-- Lobby: columns under the gallery, writing desks, benches, planters, the runner to the counter
	for _, x in { -14, 8 } do
		block(map, "Column", x - 1, B, -25, x + 1, F2 - 1, -23, MARBLE_WHITE, Enum.Material.Marble)
	end
	for _, x in { -14, 6 } do
		block(map, "WritingDesk", x, B, -31, x + 6, B + 3.6, -28, MARBLE_WHITE, Enum.Material.Marble)
	end
	block(map, "Bench", -19.5, B, -38, -15, B + 1.6, -36.5, DARK_WOOD, Enum.Material.Wood)
	block(map, "Bench", 6, B, -38, 11, B + 1.6, -36.5, DARK_WOOD, Enum.Material.Wood)
	for _, p in { { -21.5, -38 }, { 13, -38 } } do
		block(map, "Planter", p[1] - 1.5, B, p[2] - 1.5, p[1] + 1.5, B + 2, p[2] + 1.5, BRASS, Enum.Material.Metal)
		block(map, "Plant", p[1] - 1.2, B + 2, p[2] - 1.2, p[1] + 1.2, B + 4.5, p[2] + 1.2, HEDGE, Enum.Material.Grass)
	end
	cosmetic(block(map, "Runner", -3, B + 0.04, -39.5, 1, B + 0.08, -12.6, Color3.fromRGB(130, 40, 45), Enum.Material.Carpet), map:Folder("Shell"))
	sign(map, "TELLERS", CFrame.lookAt(Vector3.new(-1, B + 10.6, -12.2), Vector3.new(-1, B + 10.6, -13.2)), Vector2.new(10, 1.6), BANK_GREEN, GOLD)

	-- Behind the counter: a desk and screen at every window, cabinets, a coin counter
	for _, x in { -20, -12, -4, 4 } do
		block(map, "TellerDesk", x - 1, B, -11.5, x + 6, B + 3.4, -9.5, DARK_WOOD, Enum.Material.Wood)
		cosmetic(block(map, "Monitor", x + 1.5, B + 3.4, -10.7, x + 3.5, B + 4.8, -10.4, BLACK, Enum.Material.SmoothPlastic), map.geometry)
	end
	block(map, "Cabinets", -9, B, 3.5, 9, B + 4, 5.5, DARK_WOOD, Enum.Material.Wood)
	block(map, "CoinCounter", -20, B, 0, -16, B + 3, 3, DARK_METAL, Enum.Material.Metal)

	-- Archives: rows of shelving (cover), filing cabinets
	shelves(map, -20.75, 12, -19.25, 28, B, 8)
	shelves(map, -14.75, 12, -13.25, 32, B, 8)
	shelves(map, -6.75, 12, -5.25, 22, B, 8)
	block(map, "FilingCabinets", -2, B, 30, -0.5, B + 4.5, 38, Color3.fromRGB(120, 124, 130), Enum.Material.Metal)

	-- Teller office: desks under the windows, the big safe, the counting table
	for _, x in { 3, 13 } do
		block(map, "Desk", x, B, 35, x + 6, B + 2.8, 38, WOOD, Enum.Material.Wood)
	end
	block(map, "Safe", 18.5, B, 9, 21.5, B + 7, 14, DARK_METAL, Enum.Material.Metal)
	block(map, "CountingTable", 12, B, 22, 18, B + 3, 25, WOOD, Enum.Material.Wood)
	block(map, "Cash", 13, B + 3, 22.6, 17, B + 3.5, 24.4, CASH, Enum.Material.SmoothPlastic)

	-- Open area: loan officers' desks
	for _, d in { { -50, -36 }, { -36, -36 }, { -50, -21 }, { -36, -21 } } do
		deskPod(map, d[1], d[2], B)
	end

	-- CCTV room: the wall of screens, the console, a recorder rack
	block(map, "MonitorWall", -55.5, B + 2.6, -10, -54.6, B + 8.6, 2, BLACK, Enum.Material.SmoothPlastic)
	cosmetic(block(map, "Screens", -54.6, B + 3, -9.6, -54.5, B + 8.2, 1.6, SCREEN, Enum.Material.Neon), map.geometry)
	block(map, "Console", -53, B, -9, -50, B + 2.8, 1, DARK_METAL, Enum.Material.Metal)
	block(map, "Recorder", -39, B, 6, -37, B + 7, 10, BLACK, Enum.Material.Metal)

	-- Staff lounge: kitchenette, table, sofa, lockers
	block(map, "Fridge", -55.5, B, 37, -52.5, B + 7, 39.5, WHITE, Enum.Material.Metal)
	block(map, "Counter", -52.5, B, 37.5, -46, B + 3.2, 39.5, WHITE, Enum.Material.Marble)
	block(map, "Table", -50, B, 22, -44, B + 2.8, 26, WOOD, Enum.Material.Wood)
	block(map, "Sofa", -55.5, B, 13, -53, B + 2.6, 20, LEATHER, Enum.Material.Fabric)
	block(map, "Lockers", -38, B, 14, -36.5, B + 7, 22, Color3.fromRGB(80, 90, 110), Enum.Material.Metal)

	-- Side entrance: cash machines; manager's office
	for _, z in { -38, -34, -30 } do
		block(map, "ATM", 34.4, B, z, 35.5, B + 6, z + 2.5, DARK_METAL, Enum.Material.Metal)
		cosmetic(block(map, "ATMScreen", 34.3, B + 3.6, z + 0.5, 34.4, B + 4.8, z + 2, SCREEN, Enum.Material.Neon), map.geometry)
	end
	block(map, "Bench", 23, B, -36, 24.5, B + 1.6, -30, DARK_WOOD, Enum.Material.Wood)
	block(map, "ManagerDesk", 44, B, -32, 52, B + 2.8, -29, DARK_WOOD, Enum.Material.Wood)
	block(map, "Bookshelf", 54, B, -27, 55.5, B + 7, -23, DARK_WOOD, Enum.Material.Wood)
	block(map, "Sofa", 37, B, -38, 39.5, B + 2.6, -32, LEATHER, Enum.Material.Fabric)
	block(map, "MeetingTable", 40, B, -20, 46, B + 2.8, -16, WOOD, Enum.Material.Wood)

	-- Loading dock: crates, a cash cart, cartons
	block(map, "Crate", 32, B, -8, 36, B + 4, -4, PALLET, Enum.Material.WoodPlanks)
	block(map, "CashCart", 39, B, -9, 43, B + 4.5, -5, DARK_METAL, Enum.Material.DiamondPlate)
	pallet(map, 36, 10, B, 3, CARDBOARD, Enum.Material.Cardboard)

	-- Upstairs: open-plan and accounting desks, the executive floor, servers, restrooms, offices
	for _, d in { { -50, -37 }, { -37, -37 }, { -50, -25 }, { -37, -25 } } do
		deskPod(map, d[1], d[2], F2)
	end
	for _, d in { { 25, -37 }, { 37, -37 }, { 47, -37 }, { 25, -28 }, { 47, -28 } } do
		deskPod(map, d[1], d[2], F2)
	end
	for _, p in { { -22, -14 }, { -22, -38 } } do
		block(map, "Planter", p[1] - 1, F2, p[2] - 1, p[1] + 1, F2 + 1.6, p[2] + 1, BRASS, Enum.Material.Metal)
		block(map, "Plant", p[1] - 0.8, F2 + 1.6, p[2] - 0.8, p[1] + 0.8, F2 + 3.8, p[2] + 0.8, HEDGE, Enum.Material.Grass)
	end
	for _, x in { -18, 2 } do
		block(map, "Sofa", x, F2, -3, x + 6, F2 + 2.6, -0.5, LEATHER, Enum.Material.Fabric)
		block(map, "CoffeeTable", x + 1, F2, 1, x + 5, F2 + 1.4, 3, DARK_WOOD, Enum.Material.Wood)
	end
	block(map, "Bar", 15, F2, -10, 21, F2 + 3.4, -7.5, DARK_WOOD, Enum.Material.Wood)
	block(map, "CEODesk", -16, F2, 30, -8, F2 + 2.8, 33.5, DARK_WOOD, Enum.Material.Wood)
	block(map, "Bookshelf", -23.5, F2, 9, -22, F2 + 8, 20, DARK_WOOD, Enum.Material.Wood)
	block(map, "Sofa", -6, F2, 9, -1, F2 + 2.6, 11.5, LEATHER, Enum.Material.Fabric)
	block(map, "BoardTable", 8, F2, 12, 14, F2 + 2.8, 26, DARK_WOOD, Enum.Material.Wood)
	block(map, "Cabinet", 20, F2, 30, 21.5, F2 + 4, 38, DARK_WOOD, Enum.Material.Wood)
	cosmetic(block(map, "Screen", 0.5, F2 + 3, 12, 0.7, F2 + 8, 22, BLACK, Enum.Material.SmoothPlastic), map.geometry)
	for _, z in { 10, 18 } do -- (clear of the door and the hatch)
		for x = -53, -41, 3 do
			block(map, "ServerRack", x, F2, z, x + 2.4, F2 + 7, z + 2.5, BLACK, Enum.Material.Metal)
			cosmetic(block(map, "ServerLights", x + 0.3, F2 + 1, z - 0.05, x + 2.1, F2 + 6, z, Color3.fromRGB(60, 200, 255), Enum.Material.Neon), map.geometry)
		end
	end
	for _, z in { -10, -6, -2, 2 } do
		block(map, "Stall", -55.5, F2, z - 0.1, -51, F2 + 6.5, z + 0.1, Color3.fromRGB(150, 160, 170), Enum.Material.SmoothPlastic)
	end
	block(map, "Sinks", -50, F2, 4, -42, F2 + 3.2, 5.5, WHITE, Enum.Material.Marble)
	cosmetic(block(map, "Mirror", -50, F2 + 4, 5.4, -42, F2 + 7, 5.5, Color3.fromRGB(190, 205, 215), Enum.Material.Glass), map.geometry)
	block(map, "Desk", 33, F2, 6, 39, F2 + 2.8, 9, WOOD, Enum.Material.Wood)
	block(map, "FilingCabinets", 41, F2, -8, 42.5, F2 + 4.5, -2, Color3.fromRGB(120, 124, 130), Enum.Material.Metal)
	block(map, "Desk", 47, F2, -4, 53, F2 + 2.8, -1, WOOD, Enum.Material.Wood)
	block(map, "FilingCabinets", 54, F2, 8, 55.5, F2 + 4.5, 14, Color3.fromRGB(120, 124, 130), Enum.Material.Metal)
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

-- Parked car at (x, z), long side along x or z, standing on `base`
local function car(map: MapBuilder.Builder, x: number, z: number, alongX: boolean, color: Color3, base: number, parent: Instance?)
	local hx, hz = if alongX then 6 else 2.6, if alongX then 2.6 else 6
	local cx, cz = if alongX then 3 else 2.3, if alongX then 2.3 else 3
	local parts = {
		block(map, "Car", x - hx, base + 0.8, z - hz, x + hx, base + 3, z + hz, color, Enum.Material.SmoothPlastic),
		block(map, "CarCabin", x - cx, base + 3, z - cz, x + cx, base + 4.8, z + cz, Color3.fromRGB(30, 34, 40), Enum.Material.Glass),
	}
	-- A black block under each axle for the tyres
	for _, s in { -1, 1 } do
		local ax, az = if alongX then x + s * (hx - 2) else x, if alongX then z else z + s * (hz - 2)
		local tx, tz = if alongX then 1.2 else hx - 0.2, if alongX then hz - 0.2 else 1.2
		table.insert(parts, block(map, "Tyres", ax - tx, base, az - tz, ax + tx, base + 1.2, az + tz, BLACK, Enum.Material.Rubber))
	end
	if parent then
		for _, part in parts do
			part.Parent = parent
		end
	end
end

-- Front portico (columns and the bank's name), the loading shutter, the roof's parapet and plant
local function buildFacade(map: MapBuilder.Builder)
	map:Floor("Porch", -27, -49, 25, -40.5, B, 0.4, LIMESTONE, Enum.Material.Limestone)
	for _, x in { -21.5, -8, 5, 18 } do
		cylinder(map, "Column", x, -43.5, B + 1, 22.4, 2.6, LIMESTONE, Enum.Material.Limestone)
		block(map, "ColumnBase", x - 1.7, B, -45.2, x + 1.7, B + 1, -41.8, LIMESTONE, Enum.Material.Limestone)
		block(map, "Capital", x - 1.7, 22.4, -45.2, x + 1.7, 23.4, -41.8, LIMESTONE, Enum.Material.Limestone)
	end
	block(map, "Entablature", -25, 23.4, -46.5, 23, ROOF + PARAPET, -40.5, LIMESTONE, Enum.Material.Limestone)
	local front = Vector3.new(-1, 25.15, -46.62)
	sign(map, "OAKHAVEN SAVINGS & TRUST", CFrame.lookAt(front, front - Vector3.zAxis), Vector2.new(40, 2.4), LIMESTONE, BANK_GREEN)
	local atm = Vector3.new(29.5, B + 9.6, -40.62)
	sign(map, "ATM", CFrame.lookAt(atm, atm - Vector3.zAxis), Vector2.new(3.6, 1.2), BANK_GREEN, WHITE)

	-- Loading dock: the shutter rolled up on its drum, guide rails
	local drum = map:Part("ShutterDrum", Vector3.new(13, 1.5, 1.5), CFrame.new(55.1, B + 11.2, 0) * CFrame.Angles(0, math.pi / 2, 0), DARK_METAL, Enum.Material.Metal)
	drum.Shape = Enum.PartType.Cylinder
	cosmetic(drum, map.geometry)
	for _, z in { -6.3, 6.3 } do
		cosmetic(block(map, "ShutterRail", 54.95, B, z - 0.15, 55.25, B + 10.8, z + 0.15, DARK_METAL, Enum.Material.Metal), map.geometry)
	end
	local loading = Vector3.new(56.62, B + 11, 0)
	sign(map, "LOADING", CFrame.lookAt(loading, loading + Vector3.xAxis), Vector2.new(8, 1.4), BANK_GREEN, WHITE)

	-- Roof: parapet on the outside walls, air-conditioning units, vents, an antenna
	map:Wall("Parapet", -56.5, -40, 56.5, -40, ROOF, PARAPET, nil, LIMESTONE, Enum.Material.Limestone)
	map:Wall("Parapet", -56.5, 40, 56.5, 40, ROOF, PARAPET, nil, LIMESTONE, Enum.Material.Limestone)
	map:Wall("Parapet", -56, -39.5, -56, 39.5, ROOF, PARAPET, nil, LIMESTONE, Enum.Material.Limestone)
	map:Wall("Parapet", 56, -39.5, 56, 39.5, ROOF, PARAPET, nil, LIMESTONE, Enum.Material.Limestone)
	for _, u in { { -40, 24 }, { 28, 26 }, { -30, -22 } } do
		block(map, "HVAC", u[1] - 3, ROOF, u[2] - 2.5, u[1] + 3, ROOF + 3.6, u[2] + 2.5, Color3.fromRGB(196, 198, 194), Enum.Material.Metal)
		local fan = map:Part("HVACFan", Vector3.new(0.3, 3.2, 3.2), CFrame.new(u[1] + 1, ROOF + 3.7, u[2]) * CFrame.Angles(0, 0, math.pi / 2), DARK_METAL, Enum.Material.DiamondPlate)
		fan.Shape = Enum.PartType.Cylinder
	end
	for _, v in { { 0, 18 }, { -48, -6 }, { 44, 4 } } do
		cylinder(map, "RoofVent", v[1], v[2], ROOF, ROOF + 2.4, 2.2, Color3.fromRGB(170, 174, 178), Enum.Material.Metal)
	end
	cosmetic(cylinder(map, "Antenna", 48, 32, ROOF, ROOF + 14, 0.4, DARK_METAL, Enum.Material.Metal), map.geometry)
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
	map:Floor("Sidewalk", -94, -62, 128, -40.5, CURB, 0.3, SIDEWALK, Enum.Material.Concrete)
	map:Floor("Sidewalk", -94, -104, 128, -92, CURB, 0.3, SIDEWALK, Enum.Material.Concrete)
	map:Floor("Sidewalk", -70, -40.5, -56.5, 40.5, CURB, 0.3, SIDEWALK, Enum.Material.Concrete)
	local paint = map:Folder("Paint")
	for _, z in { -77.3, -76.7 } do
		cosmetic(block(map, "CenterLine", -94, STREET - 0.02, z - 0.15, 128, STREET + 0.03, z + 0.15, PAINT_YELLOW, Enum.Material.SmoothPlastic), paint)
	end
	for x = -8, 8, 4 do
		cosmetic(block(map, "Crosswalk", x - 0.9, STREET - 0.02, -91.5, x + 0.9, STREET + 0.03, -62.5, PAINT_WHITE, Enum.Material.SmoothPlastic), paint)
	end
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
	for _, n in neighbours do
		block(map, "Building", n[1], 0, n[2], n[3], n[5], n[4], n[6], n[7])
	end
	-- Shop fronts across the main street
	for _, s in { { -96, -50 }, { -40, 4 }, { 14, 64 }, { 74, 124 } } do
		cosmetic(block(map, "Storefront", s[1], CURB, -103.95, s[2], 8, -103.85, Color3.fromRGB(40, 50, 60), Enum.Material.Glass), map.geometry)
		cosmetic(block(map, "Awning", s[1], 8.4, -103.85, s[2], 8.8, -101.5, BANK_GREEN, Enum.Material.Fabric), map.geometry)
	end

	-- Main street: parked cars both sides and a bus (cover on the way in)
	local colors = { Color3.fromRGB(180, 30, 30), Color3.fromRGB(40, 60, 120), Color3.fromRGB(210, 210, 205), BLACK, Color3.fromRGB(120, 120, 125), Color3.fromRGB(60, 110, 70) }
	for i, x in { -74, -46, 30, 62, 96 } do
		car(map, x, -67, true, colors[i % #colors + 1], STREET, yard)
	end
	for i, x in { -60, -12, 44, 86, 112 } do
		car(map, x, -87, true, colors[(i + 2) % #colors + 1], STREET, yard)
	end
	toYard({
		block(map, "Bus", -32, STREET + 0.8, -80, -6, STREET + 10, -74, Color3.fromRGB(220, 220, 214), Enum.Material.SmoothPlastic),
		block(map, "BusStripe", -32.05, STREET + 3, -80.05, -5.95, STREET + 4, -73.95, BANK_GREEN, Enum.Material.SmoothPlastic),
	})

	-- Plaza in front of the bank: planters (cover), benches, flagpoles either side of the portico
	for _, x in { -44, -34, 34, 46 } do
		block(map, "Planter", x - 3, CURB, -53.5, x + 3, CURB + 2.2, -50.5, CONCRETE, Enum.Material.Concrete)
		block(map, "Hedge", x - 2.7, CURB + 2.2, -53.2, x + 2.7, CURB + 3.4, -50.8, HEDGE, Enum.Material.Grass)
	end
	for _, x in { -62, 58 } do
		block(map, "Bench", x, CURB, -59, x + 5, CURB + 1.6, -57.5, DARK_WOOD, Enum.Material.Wood)
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
	toYard({
		block(map, "ArmouredTruck", 63, STREET + 0.9, -8, 70, STREET + 8, 6, Color3.fromRGB(70, 84, 76), Enum.Material.Metal),
		block(map, "TruckCab", 63.5, STREET + 0.9, 6, 69.5, STREET + 6.5, 11, Color3.fromRGB(70, 84, 76), Enum.Material.Metal),
		block(map, "TruckWindscreen", 63.8, STREET + 4.2, 10.9, 69.2, STREET + 6.2, 11.05, Color3.fromRGB(30, 34, 40), Enum.Material.Glass),
		block(map, "Tyres", 62.8, STREET, -6, 70.2, STREET + 1.6, -3, BLACK, Enum.Material.Rubber),
		block(map, "Tyres", 62.8, STREET, 6.5, 70.2, STREET + 1.6, 9.5, BLACK, Enum.Material.Rubber),
	})
	car(map, 112, -36, true, colors[1], STREET, yard)
	car(map, 90, 26, false, colors[3], STREET, yard)
	car(map, 112, 48, true, colors[4], STREET, yard)

	-- Garage (basement): staff cars
	car(map, 29.5, -36, true, colors[6], BF)
	car(map, 43, -36, true, colors[3], BF)
	car(map, 49, -2, true, colors[2], BF)

	-- Street lights
	for _, p in { { -50, -60 }, { 0, -60 }, { 50, -60 }, { -82, 10 }, { 0, 62 }, { 60, 80 }, { 110, -50 }, { 110, 30 } } do
		block(map, "LightPole", p[1] - 0.3, STREET, p[2] - 0.3, p[1] + 0.3, 18, p[2] + 0.3, DARK_METAL, Enum.Material.Metal)
		map:Light(Vector3.new(p[1], 18, p[2]), 40)
	end

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
	buildFloors(map)
	buildBasement(map)
	buildGround(map)
	buildUpstairs(map)
	buildStairs(map)
	buildProps(map)
	buildFacade(map)
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
