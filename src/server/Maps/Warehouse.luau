-- WAREHOUSE — a big logistics warehouse: a tall open hall full of pallet racks, with catwalks and a
-- mezzanine overhead, a two-floor office block on its east side, and cold storage and plant rooms
-- in the basement under both. Truck lot to the south (the street side), rail yard north, staff car
-- park east, container yard west.
-- Four site pairs; the defenders pick one each round (RoundService / SitePicker):
--   Basement:  Cold storage + Boiler room         Hall:      Secure cage + Packing room
--   Offices:   Manager's office + Records         Upstairs:  Server room + Director's office
--
--   Ground floor (north = +z; the truck lot is south):
--   ┌───────────────────────────────┬──────────┬───────────┬───┬───────────┐
--   │ hall      rack rack           │ PACKING  │ break room│ stairwell ▓▒ │
--   │   rack                        ├──────────┼───────────┼───┼───────────┤
--   │         ▒▒ freight stairs     │ CAGE     │ MANAGER   │   │ RECORDS   │
--   │ ▓ container                   ├──────────┼───────────┴───┴───────────┤
--   │ ▓                             │ staging ▓│ corridor                  │
--   │  (dock)      (dock)           │          │ lobby        │ security   │
--   └───────────────────────────────┴──────────┴──────────────┴────────────┘
--   x: -64 ......................... -24 ..... 8 ..... 30 34 ........... 56
--   ▒▒ down to the basement, ▓ up to the catwalks / mezzanine / office upstairs.
--   Upstairs: catwalks along the hall's west and north walls and a bridge across it, the mezzanine
--   (over the cage and packing room) with the foreman's office, and in the office block an open-plan
--   office, the SERVER ROOM, DIRECTOR's office and a meeting room. Skylights in the hall roof and a
--   hatch in the office roof let attackers in from above.
--   Basement: loading tunnel (freight stairs, walkout ramp to the rail yard), COLD STORAGE, generator
--   room, BOILER ROOM, archives, maintenance.
-- The hall's lower walls (corrugated metal), the office's back and upstairs walls and most inside
-- walls are soft; brick and concrete aren't. The office floors and the mezzanine are wood (soft);
-- the hall slab is concrete. Units: studs. The building spans x -64..56, z -40..40.

local MapBuilder = require(script.Parent.MapBuilder)

local Warehouse = {}

-- Floor levels (the top of each floor)
local BF = -11.6 -- basement
local B = 0.4 -- ground floor
local F2 = 13.4 -- office upstairs, mezzanine, catwalks
local OFFICE_ROOF = 25.4 -- top of the office block's flat roof
local HALL_ROOF = 30.4 -- top of the hall's flat roof
local BASEMENT_WALL = 11
local GROUND_WALL = 12
local UPSTAIRS_WALL = 11

-- Look
local CONCRETE = Color3.fromRGB(150, 150, 150)
local SLAB = Color3.fromRGB(132, 132, 128)
local SIDING = Color3.fromRGB(150, 160, 168)
local DARK_METAL = Color3.fromRGB(62, 66, 72)
local BRICK = Color3.fromRGB(150, 88, 70)
local PANEL = Color3.fromRGB(206, 202, 192)
local PLASTER = Color3.fromRGB(226, 218, 200)
local INSULATION = Color3.fromRGB(232, 236, 240)
local WOOD = Color3.fromRGB(150, 110, 75)
local PLYWOOD = Color3.fromRGB(190, 160, 115)
local WHITE = Color3.fromRGB(240, 238, 232)
local SAFETY_YELLOW = Color3.fromRGB(196, 160, 52)
local RACK_BLUE = Color3.fromRGB(40, 80, 160)
local RACK_ORANGE = Color3.fromRGB(230, 120, 30)
local CARDBOARD = Color3.fromRGB(176, 136, 90)
local PALLET = Color3.fromRGB(150, 115, 70)
local MESH = Color3.fromRGB(95, 100, 106)
local GRASS = Color3.fromRGB(96, 128, 72)
local ASPHALT = Color3.fromRGB(55, 55, 60)
local GRAVEL = Color3.fromRGB(120, 112, 102)
local BLACK = Color3.fromRGB(28, 29, 32)

-- Walls: soft ones can be shot through, breached and reinforced; brick and concrete can't
local DRYWALL: MapBuilder.Style = { color = PLASTER, material = Enum.Material.Plaster, soft = true }
local INSULATED: MapBuilder.Style = { color = INSULATION, material = Enum.Material.SmoothPlastic, soft = true }
local HALL_LOWER: MapBuilder.Style = { color = SIDING, material = Enum.Material.Metal, soft = true, exterior = true }
local HALL_UPPER: MapBuilder.Style = { color = SIDING, material = Enum.Material.Metal, exterior = true }
local OFFICE_SOFT: MapBuilder.Style = { color = PANEL, material = Enum.Material.Plaster, soft = true, exterior = true }
local OUTSIDE_BRICK: MapBuilder.Style = { color = BRICK, material = Enum.Material.Brick, exterior = true }
local OUTSIDE_CONCRETE: MapBuilder.Style = { color = CONCRETE, material = Enum.Material.Concrete, exterior = true }
local CONCRETE_WALL: MapBuilder.Style = { color = CONCRETE, material = Enum.Material.Concrete }
local BRICK_WALL: MapBuilder.Style = { color = BRICK, material = Enum.Material.Brick }

-- Floor finishes over the wood / concrete
local CARPET = { Color3.fromRGB(120, 116, 110), Enum.Material.Carpet }
local GREY_CARPET = { Color3.fromRGB(90, 96, 104), Enum.Material.Carpet }
local TILE = { Color3.fromRGB(220, 220, 214), Enum.Material.CeramicTiles }
local MARBLE = { Color3.fromRGB(226, 224, 218), Enum.Material.Marble }
local FROST = { Color3.fromRGB(196, 210, 220), Enum.Material.Concrete }
local RAISED = { Color3.fromRGB(176, 180, 186), Enum.Material.DiamondPlate }

-- Holes in the floors: { x1, z1, x2, z2 }
local FREIGHT_STAIRS = { -40, -20, -34, -4 } -- hall down to the loading tunnel (climbs +z)
local DOWN_FLIGHT = { 34, 20, 40, 36 } -- office stairwell, basement up to the ground floor (climbs +z)
local UP_FLIGHT = { 46, 20, 52, 36 } -- office stairwell, ground floor up (climbs -z)
local HATCH = 4
-- Hatches (4 × 4 trapdoors) over the sites below: x, z, the floor they're in
local HATCHES = {
	{ -12, -24, "Hall" }, -- staging → cold storage
	{ 20, -24, "Office" }, -- lobby → boiler room
	{ -8, 2, "Mezzanine" }, -- mezzanine → cage
	{ -14, 28, "Mezzanine" }, -- mezzanine → packing room
	{ 18, 6, "Upstairs" }, -- server room → manager's office
	{ 46, 2, "Upstairs" }, -- director's office → records
	{ 40, -30, "Roof" }, -- office roof → open-plan office
}
local HOLES = { Hall = { FREIGHT_STAIRS }, Office = { DOWN_FLIGHT }, Upstairs = { UP_FLIGHT }, Mezzanine = {}, Roof = {} }
local HATCH_TOPS = { Hall = B, Office = B, Mezzanine = F2, Upstairs = F2, Roof = OFFICE_ROOF }
for _, hatch in HATCHES do
	local x, z = hatch[1], hatch[2]
	table.insert(HOLES[hatch[3]], { x - HATCH / 2, z - HATCH / 2, x + HATCH / 2, z + HATCH / 2 })
end
-- Skylights in the hall roof: two over the mezzanine (drop in), two over the racks
local SKYLIGHTS = { { -22, 4, -12, 10 }, { -22, 26, -12, 32 }, { -54, -6, -44, 0 }, { -54, 14, -44, 20 } }

-- name, x1, z1, x2, z2, floor, finish (nil = bare). Lights and floor finishes come from here.
local ROOMS = {
	{ "Tunnel", -44, -40, -28, 40, BF },
	{ "ColdStorage", -28, -40, 8, -10, BF, FROST },
	{ "Generator", -28, -10, 8, 40, BF },
	{ "BoilerRoom", 8, -40, 32, -10, BF },
	{ "Archives", 32, -40, 56, -10, BF, GREY_CARPET },
	{ "BasementCorridor", 8, -10, 56, 2, BF },
	{ "Maintenance", 8, 2, 34, 40, BF },
	{ "LowerStairs", 34, 2, 56, 40, BF },

	{ "Cage", -24, -8, 8, 14, B },
	{ "Packing", -24, 14, 8, 40, B },
	{ "Lobby", 8, -40, 32, -16, B, MARBLE },
	{ "Security", 32, -40, 56, -16, B, GREY_CARPET },
	{ "Corridor", 8, -16, 56, -8, B, TILE },
	{ "Manager", 8, -8, 30, 16, B, CARPET },
	{ "Hallway", 30, -8, 34, 16, B, TILE },
	{ "Records", 34, -8, 56, 16, B, GREY_CARPET },
	{ "BreakRoom", 8, 16, 30, 40, B, TILE },
	{ "Stairwell", 30, 16, 56, 40, B, TILE },

	{ "OpenPlan", 8, -40, 56, -8, F2, GREY_CARPET },
	{ "ServerRoom", 8, -8, 30, 16, F2, RAISED },
	{ "UpperHallway", 30, -8, 34, 16, F2, TILE },
	{ "Director", 34, -8, 56, 16, F2, CARPET },
	{ "Meeting", 8, 16, 30, 40, F2, CARPET },
	{ "UpperStairs", 30, 16, 56, 40, F2, TILE },
	{ "Foreman", -8, 24, 8, 40, F2, CARPET },
}

-- Openings (positions are world x / z along the wall)
local door = MapBuilder.Door
local doubleDoor = MapBuilder.DoubleDoor
local window = MapBuilder.Window
local arch = MapBuilder.Arch

-- A roll-up loading door, left open (a plain hole: no trim, no barricade)
local function dock(from: number, to: number): MapBuilder.Opening
	return { from = from, to = to, top = 11 }
end

-- Wall along x at `z`, or along z at `x`
local wallX = MapBuilder.WallX
local wallZ = MapBuilder.WallZ

-- Looks only: no collisions, bullets go through
local cosmetic = MapBuilder.Cosmetic

-- Block between two corners given as numbers (any order)
local block = MapBuilder.Block

-- Steel mesh partition (the secure cage): see and shoot through it, can't walk through it.
-- `doors` are { from, to } in world x / z along the wall.
local function meshWall(map: MapBuilder.Builder, x1: number, z1: number, x2: number, z2: number, base: number, height: number, doors: { { number } })
	local alongX = z1 == z2
	local start = if alongX then math.min(x1, x2) else math.min(z1, z2)
	local openings = {}
	for _, d in doors do
		table.insert(openings, { from = d[1] - start, to = d[2] - start, top = 8 })
	end
	for _, piece in map:Wall("Mesh", x1, z1, x2, z2, base, height, openings, MESH, Enum.Material.DiamondPlate, 0.3) do
		piece.Transparency = 0.55
		piece:SetAttribute("Breakable", "Soft")
	end
	-- Steel posts at the ends and either side of each door
	local stops = { start, if alongX then math.max(x1, x2) else math.max(z1, z2) }
	for _, d in doors do
		table.insert(stops, d[1])
		table.insert(stops, d[2])
	end
	for _, at in stops do
		local x, z = if alongX then at else x1, if alongX then z1 else at
		block(map, "MeshPost", x - 0.25, base, z - 0.25, x + 0.25, base + height, z + 0.25, DARK_METAL, Enum.Material.Metal)
	end
end

-- Steel pallet rack over x1..x2 × z1..z2 (long side along the longer axis): blue uprights, orange
-- beams, wire decks and cartons on pallets. Cover, and lanes to shoot down between the boxes.
local function rack(map: MapBuilder.Builder, x1: number, z1: number, x2: number, z2: number, base: number, seed: number, levels: number?)
	local count = levels or 3
	local spacing = 4.5
	local alongX = x2 - x1 > z2 - z1
	local length = if alongX then x2 - x1 else z2 - z1
	local depth = if alongX then z2 - z1 else x2 - x1
	local bays = math.max(1, math.round(length / 6))
	local bay = length / bays
	local function at(along: number, across: number): (number, number)
		if alongX then
			return x1 + along, z1 + across
		end
		return x1 + across, z1 + along
	end
	for i = 0, bays do
		for _, across in { 0, depth } do
			local x, z = at(i * bay, across)
			block(map, "RackPost", x - 0.2, base, z - 0.2, x + 0.2, base + count * spacing, z + 0.2, RACK_BLUE, Enum.Material.Metal)
		end
	end
	for level = 1, count do
		local y = base + level * spacing
		for _, across in { 0, depth } do
			local ax, az = at(0, across)
			local bx, bz = at(length, across)
			block(map, "RackBeam", ax - 0.15, y - 0.5, az - 0.15, bx + 0.15, y, bz + 0.15, RACK_ORANGE, Enum.Material.Metal)
		end
		if level < count then
			block(map, "RackDeck", x1, y - 0.2, z1, x2, y - 0.05, z2, MESH, Enum.Material.DiamondPlate)
		end
	end
	-- Cartons: most bays on every level, some empty (a fixed pattern, so every round is the same)
	for i = 0, bays - 1 do
		for level = 0, count - 1 do
			if (i * 7 + level * 3 + seed) % 5 == 0 then
				continue
			end
			local floor = base + level * spacing
			local height = 2.4 + ((i + level + seed) % 3) * 0.5
			local ax, az = at(i * bay + 0.6, 0.3)
			local bx, bz = at((i + 1) * bay - 0.6, depth - 0.3)
			block(map, "Pallet", ax, floor, az, bx, floor + 0.4, bz, PALLET, Enum.Material.WoodPlanks)
			block(map, "Cartons", ax + 0.1, floor + 0.4, az + 0.1, bx - 0.1, floor + 0.4 + height, bz - 0.1, CARDBOARD, Enum.Material.Cardboard)
		end
	end
end

-- Pallet with a stack of cartons on the floor at (x, z)
local function pallet(map: MapBuilder.Builder, x: number, z: number, base: number, height: number)
	block(map, "Pallet", x - 2, base, z - 2, x + 2, base + 0.4, z + 2, PALLET, Enum.Material.WoodPlanks)
	block(map, "Cartons", x - 1.8, base + 0.4, z - 1.8, x + 1.8, base + 0.4 + height, z + 1.8, CARDBOARD, Enum.Material.Cardboard)
end

-- Shipping container, 8 wide × 8.6 tall × 20 long, from (x1, z1) along x or z. Solid, or (walk-in)
-- hollow with the far end open and its doors swung back.
local function container(map: MapBuilder.Builder, x1: number, z1: number, alongX: boolean, base: number, color: Color3, hollow: boolean, parent: Instance?): { BasePart }
	local x2, z2 = if alongX then x1 + 20 else x1 + 8, if alongX then z1 + 8 else z1 + 20
	local top = base + 8.6
	local parts = {}
	local function add(part: BasePart)
		if parent then
			part.Parent = parent
		end
		table.insert(parts, part)
	end
	if not hollow then
		add(block(map, "Container", x1, base, z1, x2, top, z2, color, Enum.Material.CorrodedMetal))
		return parts
	end
	local t = 0.3
	add(block(map, "Container", x1, top - t, z1, x2, top, z2, color, Enum.Material.CorrodedMetal)) -- roof
	if alongX then
		add(block(map, "Container", x1, base, z1, x2, top, z1 + t, color, Enum.Material.CorrodedMetal))
		add(block(map, "Container", x1, base, z2 - t, x2, top, z2, color, Enum.Material.CorrodedMetal))
		add(block(map, "Container", x1, base, z1, x1 + t, top, z2, color, Enum.Material.CorrodedMetal)) -- closed end
	else
		add(block(map, "Container", x1, base, z1, x1 + t, top, z2, color, Enum.Material.CorrodedMetal))
		add(block(map, "Container", x2 - t, base, z1, x2, top, z2, color, Enum.Material.CorrodedMetal))
		add(block(map, "Container", x1, base, z1, x2, top, z1 + t, color, Enum.Material.CorrodedMetal)) -- closed end
		-- Doors folded back against the sides at the open (+z) end
		add(block(map, "ContainerDoor", x1 - t, base, z2, x1, top - 0.2, z2 + 4, color, Enum.Material.CorrodedMetal))
		add(block(map, "ContainerDoor", x2, base, z2, x2 + t, top - 0.2, z2 + 4, color, Enum.Material.CorrodedMetal))
	end
	return parts
end

-- Industrial high-bay lamp hung from the roof on a rod: a dark bell shade with a glowing lens
local function highBay(map: MapBuilder.Builder, x: number, z: number)
	local lampY = HALL_ROOF - 5.5
	cosmetic(block(map, "LampRod", x - 0.08, lampY + 0.6, z - 0.08, x + 0.08, HALL_ROOF - 1, z + 0.08, DARK_METAL, Enum.Material.Metal), map.geometry)
	local shade = map:Part("LampShade", Vector3.new(1.2, 2.6, 2.6), CFrame.new(x, lampY + 0.2, z) * CFrame.Angles(0, 0, math.pi / 2), DARK_METAL, Enum.Material.Metal)
	shade.Shape = Enum.PartType.Cylinder
	cosmetic(shade, map.geometry)
	local lens = map:Part("Light", Vector3.new(0.15, 2.2, 2.2), CFrame.new(x, lampY - 0.45, z) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(255, 244, 214), Enum.Material.Neon)
	lens.Shape = Enum.PartType.Cylinder
	lens.CastShadow = false
	cosmetic(lens, map.geometry)
	local light = Instance.new("PointLight")
	light.Range = 30 -- (twenty of them overlap: keep each one dim)
	light.Brightness = 0.55
	light.Color = Color3.fromRGB(255, 236, 200)
	light.Shadows = true
	light.Parent = lens
end

local function ceilingOf(name: string, level: number): number
	if name == "Foreman" then
		return F2 + 9
	end
	return if level == BF then B - 1 elseif level == B then F2 - 1 else OFFICE_ROOF - 1
end

local function buildFloors(map: MapBuilder.Builder)
	local shell = map:Folder("Shell")
	map:Floor("BasementFloor", -44.5, -40.5, 56.5, 40.5, BF, 1, CONCRETE, Enum.Material.Concrete)
	-- The hall slab is concrete; the office floors are wood (shoot down through them, breach them)
	map:FloorWithHoles("HallFloor", -64.5, -40.5, 8, 40.5, HOLES.Hall, B, 1, SLAB, Enum.Material.Concrete)
	for _, piece in map:FloorWithHoles("Floor", 8, -40.5, 56.5, 40.5, HOLES.Office, B, 1, WOOD, Enum.Material.WoodPlanks) do
		piece:SetAttribute("Breakable", "Soft")
	end
	for _, piece in map:FloorWithHoles("Floor2", 8, -40.5, 56.5, 40.5, HOLES.Upstairs, F2, 1, WOOD, Enum.Material.WoodPlanks) do
		piece:SetAttribute("Breakable", "Soft")
		-- Painted ceiling under the wood (DestructionService cuts it along with the floor)
		cosmetic(map:Part("Ceiling", Vector3.new(piece.Size.X, 0.1, piece.Size.Z), piece.CFrame * CFrame.new(0, -0.55, 0), WHITE, Enum.Material.Plaster), shell)
	end
	-- Mezzanine (over the cage and packing room) and the landing at the top of its stairs: plywood
	for _, piece in map:FloorWithHoles("Mezzanine", -24, -8, 8, 40, HOLES.Mezzanine, F2, 1, PLYWOOD, Enum.Material.WoodPlanks) do
		piece:SetAttribute("Breakable", "Soft")
	end
	map:Floor("Mezzanine", -24, -20, -16, -8, F2, 1, PLYWOOD, Enum.Material.WoodPlanks):SetAttribute("Breakable", "Soft")
	-- Steel catwalks: along the west wall, along the north wall, the bridge across, a stair landing
	for _, c in { { -63.5, -40, -60, 40 }, { -60, 36, -24, 40 }, { -60, -2, -24, 2 }, { -60, -22, -55, -18 } } do
		map:Floor("Catwalk", c[1], c[2], c[3], c[4], F2, 0.5, DARK_METAL, Enum.Material.DiamondPlate)
	end
	for z = -36, 36, 12 do
		block(map, "CatwalkPost", -60.3, B, z - 0.3, -59.7, F2 - 0.5, z + 0.3, SAFETY_YELLOW, Enum.Material.Metal)
	end
	for _, x in { -48, -36 } do
		block(map, "CatwalkPost", x - 0.3, B, -0.3, x + 0.3, F2 - 0.5, 0.3, SAFETY_YELLOW, Enum.Material.Metal)
		block(map, "CatwalkPost", x - 0.3, B, 37.7, x + 0.3, F2 - 0.5, 38.3, SAFETY_YELLOW, Enum.Material.Metal)
	end
	for _, hatch in HATCHES do
		map:Hatch(hatch[1], hatch[2], HATCH_TOPS[hatch[3]], HATCH)
	end

	-- Roofs: the office block's flat roof (gravel on top, white ceiling under), the hall's higher
	-- one with skylights (glass: shoot it out and drop in), and the foreman's office
	map:FloorWithHoles("Roof", 8, -40.5, 56.5, 40.5, HOLES.Roof, OFFICE_ROOF, 1, Color3.fromRGB(110, 108, 104), Enum.Material.Pebble)
	for _, piece in map:FloorWithHoles("UpstairsCeiling", 8, -40.5, 56.5, 40.5, HOLES.Roof, OFFICE_ROOF - 0.95, 0.1, WHITE, Enum.Material.Plaster) do
		cosmetic(piece, shell)
	end
	map:FloorWithHoles("Roof", -64.5, -40.5, 8.5, 40.5, SKYLIGHTS, HALL_ROOF, 1, SIDING, Enum.Material.Metal)
	for _, s in SKYLIGHTS do
		local glass = block(map, "Skylight", s[1], HALL_ROOF - 0.6, s[2], s[3], HALL_ROOF - 0.4, s[4], Color3.fromRGB(170, 200, 215), Enum.Material.Glass)
		glass.Transparency = 0.45
		glass:SetAttribute("Breakable", "Glass")
		glass.Parent = map:Folder("Glass")
	end
	map:Floor("ForemanRoof", -8.5, 24, 8, 40, F2 + 10, 1, DARK_METAL, Enum.Material.Metal)

	for _, room in ROOMS do
		local name, x1, z1, x2, z2, level, finish = table.unpack(room)
		if finish then
			local holes = if level == B then HOLES.Office elseif level == F2 then HOLES.Upstairs else {}
			for _, piece in map:FloorWithHoles(name .. "Floor", x1, z1, x2, z2, holes, level + 0.04, 0.04, finish[1], finish[2]) do
				cosmetic(piece, shell)
			end
		end
		local top = ceilingOf(name, level)
		local count = math.max(1, math.round((x2 - x1) * (z2 - z1) / 500))
		for i = 1, count do
			local t = (i - 0.5) / count
			local position = if x2 - x1 >= z2 - z1
				then Vector3.new(x1 + (x2 - x1) * t, top - 0.2, (z1 + z2) / 2)
				else Vector3.new((x1 + x2) / 2, top - 0.2, z1 + (z2 - z1) * t)
			map:Light(position, 24, 0.85)
		end
	end
	-- High-bay lamps hanging under the hall roof, over the floor and the mezzanine
	for _, x in { -56, -44, -32, -14 } do
		for _, z in { -30, -15, 0, 15, 30 } do
			highBay(map, x, z)
		end
	end
end

local function buildBasement(map: MapBuilder.Builder)
	local base, h = BF, BASEMENT_WALL
	-- Outside walls: poured concrete, underground; double doors to the walkout ramp (north)
	wallX(map, OUTSIDE_CONCRETE, -40, -44.5, 56.5, base, h, nil, 1)
	wallX(map, OUTSIDE_CONCRETE, 40, -44.5, 56.5, base, h, { doubleDoor(-40) }, -1)
	wallZ(map, OUTSIDE_CONCRETE, -44, -40, 40, base, h, nil, 1)
	wallZ(map, OUTSIDE_CONCRETE, 56, -40, 40, base, h, nil, -1)

	-- West: the loading tunnel along the outside wall, COLD STORAGE (insulated panels) + generators
	wallZ(map, INSULATED, -28, -40, -10, base, h, { door(-30) })
	wallZ(map, CONCRETE_WALL, -28, -10, 40, base, h, { doubleDoor(12) })
	wallX(map, INSULATED, -10, -28, 8, base, h, { door(-14) })

	-- East (under the offices): BOILER ROOM + archives, a corridor, maintenance, the stairwell
	wallZ(map, CONCRETE_WALL, 8, -40, -10, base, h, { door(-24) }) -- cold storage ↔ boiler room
	wallZ(map, CONCRETE_WALL, 8, -10, 40, base, h, { door(-6), door(22) })
	wallX(map, CONCRETE_WALL, -10, 8, 32, base, h, { door(14) })
	wallX(map, DRYWALL, -10, 32, 56, base, h, { door(42) })
	wallZ(map, DRYWALL, 32, -40, -10, base, h, { door(-30) })
	wallX(map, DRYWALL, 2, 8, 56, base, h, { door(18), door(46) })
	wallZ(map, DRYWALL, 34, 2, 40, base, h, { door(4) }) -- (south of the flight)
end

local function buildGround(map: MapBuilder.Builder)
	local base, h = B, GROUND_WALL
	-- Hall, lower walls: corrugated siding (soft). Two loading docks and a door on the truck lot,
	-- the rail door on the north side, doors west.
	wallX(map, HALL_LOWER, -40, -64.5, 8, base, h, { dock(-58, -48), dock(-42, -32), door(-20) }, 1)
	wallX(map, HALL_LOWER, 40, -64.5, 8, base, h, { dock(-62, -50), door(-48), door(-6) }, -1)
	wallZ(map, HALL_LOWER, -64, -40.5, 40.5, base, h, { door(-12), door(15) }, 1)
	-- Hall, upper walls (hard): windows at the catwalks, so you can rappel up and shoot in
	local upper, upperH = base + h, HALL_ROOF - 1 - (base + h)
	wallX(map, HALL_UPPER, -40, -64.5, 8, upper, upperH, nil, 1)
	wallX(map, HALL_UPPER, 40, -64.5, 8, upper, upperH, { window(-58, -52), window(-46, -40), window(-34, -28) }, -1)
	wallZ(map, HALL_UPPER, -64, -40.5, 40.5, upper, upperH, { window(-34, -28), window(-12, -6), window(8, 14), window(26, 32) }, 1)
	-- (the bit of the hall's east wall that sticks up over the office roof)
	wallZ(map, HALL_UPPER, 8, -40.5, 40.5, OFFICE_ROOF, HALL_ROOF - 1 - OFFICE_ROOF, nil, -1)

	-- Inside the hall, east side: the secure CAGE (steel mesh) and the PACKING room under the mezzanine
	meshWall(map, -24, -8, -24, 14, base, h, { { 0, 5 } })
	meshWall(map, -24, -8, 8, -8, base, h, { { -14, -9 } })
	wallZ(map, DRYWALL, -24, 14, 40, base, h, { window(17, 23), doubleDoor(28) })
	wallX(map, DRYWALL, 14, -24, 8, base, h, { door(-6) })

	-- Office block, outside: brick front with the main entrance, panels elsewhere (soft)
	wallX(map, OUTSIDE_BRICK, -40, 8, 56.5, base, h, { doubleDoor(16), window(26, 31, 2, 9), window(36, 42), window(48, 53) }, 1)
	wallZ(map, OFFICE_SOFT, 56, -40, 40, base, h, { door(-32), window(-4, 2), window(6, 12), door(30) }, -1)
	wallX(map, OFFICE_SOFT, 40, 8, 56.5, base, h, { window(14, 22), door(36), window(48, 53) }, -1)
	-- Office block, inside
	wallZ(map, DRYWALL, 8, -40, 40, base, h, { door(-30), door(26) }) -- hall ↔ lobby / break room
	wallX(map, DRYWALL, -16, 8, 56, base, h, { arch(12, 28), door(42) })
	wallZ(map, DRYWALL, 32, -40, -16, base, h, { window(-38, -32), door(-24) }) -- lobby ↔ security
	wallX(map, DRYWALL, -8, 8, 56, base, h, { door(14), arch(30, 34), door(46) })
	wallZ(map, DRYWALL, 30, -8, 16, base, h, { door(2) }) -- MANAGER ↔ hallway
	wallZ(map, DRYWALL, 34, -8, 16, base, h, { door(6) }) -- RECORDS ↔ hallway
	wallX(map, DRYWALL, 16, 8, 56, base, h, { door(20), arch(30, 34), door(48) })
	wallZ(map, DRYWALL, 30, 16, 40, base, h, { door(30) }) -- break room ↔ stairwell
end

local function buildUpstairs(map: MapBuilder.Builder)
	local base, h = F2, UPSTAIRS_WALL
	wallX(map, OFFICE_SOFT, -40, 8, 56.5, base, h, { window(10, 16), window(20, 26), window(34, 40), window(46, 52) }, 1)
	wallZ(map, OFFICE_SOFT, 56, -40, 40, base, h, { window(-30, -24), window(-2, 4), window(8, 12), window(26, 32) }, -1)
	wallX(map, OFFICE_SOFT, 40, 8, 56.5, base, h, { window(12, 20), window(38, 44) }, -1)
	-- Toward the hall: windows over the staging area, doors onto the mezzanine
	wallZ(map, DRYWALL, 8, -40, 40, base, h, { window(-36, -30), window(-24, -18), door(-4), door(28) })
	wallX(map, DRYWALL, -8, 8, 56, base, h, { door(14), arch(30, 34), door(46) })
	wallZ(map, DRYWALL, 30, -8, 16, base, h, { door(2) }) -- SERVER ROOM ↔ hallway
	wallZ(map, DRYWALL, 34, -8, 16, base, h, { door(6) }) -- DIRECTOR ↔ hallway
	wallX(map, DRYWALL, 16, 8, 56, base, h, { window(12, 24), arch(30, 34), door(48) }) -- meeting room looks into the server room
	wallZ(map, DRYWALL, 30, 16, 40, base, h, { door(30) })
	-- Foreman's office on the mezzanine, windows over the hall
	wallX(map, DRYWALL, 24, -8, 8, base, 9, { window(-6, 0), door(2) })
	wallZ(map, DRYWALL, -8, 24, 40, base, 9, { window(28, 36) })
end

local function buildStairs(map: MapBuilder.Builder)
	-- Freight stairs: hall floor down to the loading tunnel
	map:Stairs(-40, -20, -34, -4, BF, B, "+Z", DARK_METAL, Enum.Material.DiamondPlate)
	-- Steel stairs: hall floor up to the west catwalk, and staging up to the mezzanine
	map:Stairs(-60, -38, -55, -22, B, F2, "+Z", DARK_METAL, Enum.Material.DiamondPlate)
	map:Stairs(-22, -36, -17, -20, B, F2, "+Z", DARK_METAL, Enum.Material.DiamondPlate)
	-- Office stairwell: down to the basement and up to the offices, a brick wall between the flights
	map:Stairs(34, 20, 40, 36, BF, B, "+Z", WOOD)
	map:Stairs(46, 20, 52, 36, B, F2, "-Z", WOOD)
	wallZ(map, BRICK_WALL, 43, 18, 36, BF, F2 - BF)

	local function rail(x1: number, z1: number, x2: number, z2: number, y: number)
		map:Railing(Vector3.new(x1, y, z1), Vector3.new(x2, y, z2), SAFETY_YELLOW)
	end
	local function handrail(x1: number, y1: number, z1: number, x2: number, y2: number, z2: number)
		map:Railing(Vector3.new(x1, y1, z1), Vector3.new(x2, y2, z2), SAFETY_YELLOW)
	end
	-- Freight stairs: round the opening in the hall floor (entered from the north end)
	rail(-40, -20, -40, -4, B)
	rail(-34, -20, -34, -4, B)
	rail(-40, -20, -34, -20, B)
	handrail(-40, BF, -20, -40, B, -4)
	handrail(-34, BF, -20, -34, B, -4)
	-- West catwalk stairs and their landing
	handrail(-55, B, -38, -55, F2, -22)
	handrail(-60, B, -38, -60, F2, -22)
	rail(-60, -18, -55, -18, F2)
	rail(-55, -22, -55, -18, F2)
	-- West catwalk's inner edge (gaps for the landing, the bridge and the north catwalk)
	rail(-60, -40, -60, -22, F2)
	rail(-60, -18, -60, -2, F2)
	rail(-60, 2, -60, 36, F2)
	-- North catwalk and the bridge
	rail(-60, 36, -24, 36, F2)
	rail(-60, -2, -24, -2, F2)
	rail(-60, 2, -24, 2, F2)
	-- Mezzanine stairs, landing and the mezzanine's open edges
	handrail(-22, B, -36, -22, F2, -20)
	handrail(-17, B, -36, -17, F2, -20)
	rail(-24, -20, -22, -20, F2)
	rail(-17, -20, -16, -20, F2)
	rail(-16, -20, -16, -8, F2)
	rail(-16, -8, 8, -8, F2)
	rail(-24, -20, -24, -2, F2)
	rail(-24, 2, -24, 36, F2)
	-- Office stairwell openings
	rail(34, 20, 34, 36, B)
	rail(40, 20, 40, 36, B)
	rail(34, 20, 40, 20, B)
	rail(46, 20, 46, 36, F2)
	rail(52, 20, 52, 36, F2)
	rail(46, 36, 52, 36, F2)
	handrail(34, BF, 20, 34, B, 36)
	handrail(46, B, 36, 46, F2, 20)
	handrail(52, B, 36, 52, F2, 20)
end

local function buildProps(map: MapBuilder.Builder)
	-- Hall: racks, a walk-in container, a forklift, pallets in the staging area
	rack(map, -57, -12, -54, 18, B, 1)
	rack(map, -47, -8, -44, 20, B, 2)
	rack(map, -31, -16, -28, 10, B, 3)
	rack(map, -52, 26, -30, 29, B, 4)
	container(map, -52, -34, false, B, Color3.fromRGB(40, 80, 140), true)
	block(map, "Forklift", -38, B, -32, -34, B + 3.2, -27, SAFETY_YELLOW, Enum.Material.Metal)
	block(map, "ForkliftMast", -37.6, B, -33.4, -34.4, B + 7, -32, DARK_METAL, Enum.Material.Metal)
	block(map, "ForkliftCage", -37.8, B + 3.2, -30, -34.2, B + 6.4, -27.4, DARK_METAL, Enum.Material.Metal).Transparency = 0.6
	for _, p in { { -4, -34, 3.2 }, { 3, -34, 2.6 }, { 3, -14, 3.6 }, { -6, -14, 2.4 }, { -28, -36, 3 } } do
		pallet(map, p[1], p[2], B, p[3])
	end

	-- Cage: low shelving and crates; packing room: conveyor, packing tables, cartons
	rack(map, -22, 9, -8, 12, B, 5, 2)
	block(map, "Crate", -2, B, -4, 2, B + 3, 0, PALLET, Enum.Material.WoodPlanks)
	block(map, "Crate", 2, B, 4, 6, B + 3.5, 8, PALLET, Enum.Material.WoodPlanks)
	block(map, "Conveyor", -20, B, 21, 4, B + 2.6, 23.5, DARK_METAL, Enum.Material.Metal)
	block(map, "ConveyorBelt", -20, B + 2.6, 21.3, 4, B + 2.8, 23.2, BLACK, Enum.Material.Rubber)
	for _, x in { -14, -2 } do
		block(map, "PackingTable", x - 4, B, 30, x + 4, B + 3, 34, PLYWOOD, Enum.Material.WoodPlanks)
	end
	pallet(map, -12, 37.5, B, 3.2)
	pallet(map, 4, 18, B, 2.6)

	-- Mezzanine: stored stock; foreman's office: desk and a cabinet
	for _, p in { { -19, -4, 3 }, { -2, 8, 2.6 }, { -20, 16, 3.4 }, { 2, 18, 2.4 }, { -14, 37, 3 } } do
		pallet(map, p[1], p[2], F2, p[3])
	end
	block(map, "Desk", -4, F2, 34, 4, F2 + 2.6, 37, WOOD, Enum.Material.Wood)
	block(map, "Cabinet", -7.5, F2, 37.5, -5.5, F2 + 4.5, 39.5, DARK_METAL, Enum.Material.Metal)

	-- Basement: cold storage racks, generators, boilers, archive shelves, workbenches
	rack(map, -24, -36, -6, -33, BF, 6, 2) -- (2 levels: the basement is lower)
	rack(map, -24, -18, -6, -15, BF, 7, 2)
	for _, z in { 6, 24 } do
		block(map, "Generator", -22, BF, z - 3, -12, BF + 5, z + 3, Color3.fromRGB(60, 100, 70), Enum.Material.Metal)
		block(map, "Exhaust", -21, BF + 5, z - 0.5, -20, B - 1, z + 0.5, DARK_METAL, Enum.Material.Metal)
	end
	for _, x in { 13, 27 } do
		local boiler = map:Part("Boiler", Vector3.new(9, 5, 5), CFrame.new(x, BF + 4.5, -35) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(150, 60, 50), Enum.Material.Metal)
		boiler.Shape = Enum.PartType.Cylinder
	end
	for _, z in { -36, -28, -20 } do
		rack(map, 36, z, 52, z + 2, BF, z, 2)
	end
	block(map, "Workbench", 12, BF, 34, 24, BF + 3, 37, WOOD, Enum.Material.Wood)
	block(map, "ToolShelf", 10, BF, 6, 12, BF + 7, 16, DARK_METAL, Enum.Material.Metal)
	for _, x in { -43.4, -29.4 } do -- (along the walls, clear of the freight stairs)
		block(map, "Pipe", x, B - 2.2, -40, x + 0.8, B - 1.4, 40, DARK_METAL, Enum.Material.Metal)
	end

	-- Office ground floor
	block(map, "ReceptionDesk", 10, B, -22, 18, B + 3.4, -19.5, WOOD, Enum.Material.Wood)
	block(map, "Bench", 24, B, -38, 30, B + 1.6, -36.5, DARK_METAL, Enum.Material.Metal)
	block(map, "SecurityDesk", 40, B, -38, 50, B + 3, -35, DARK_METAL, Enum.Material.Metal)
	block(map, "Monitors", 41, B + 3, -38, 49, B + 5.4, -37.4, BLACK, Enum.Material.SmoothPlastic)
	block(map, "Lockers", 54, B, -24, 55.5, B + 7, -17.5, Color3.fromRGB(80, 90, 110), Enum.Material.Metal)
	block(map, "ManagerDesk", 13, B, -2, 23, B + 2.8, 1, WOOD, Enum.Material.Wood)
	block(map, "Bookshelf", 9, B, 8, 10.5, B + 7, 15, WOOD, Enum.Material.Wood)
	block(map, "Sofa", 24, B, -6, 29, B + 2.6, 0, Color3.fromRGB(70, 60, 55), Enum.Material.Fabric)
	-- (clear of the doors and of the drop from the director's hatch)
	for _, c in { { 36, 42, -2 }, { 36, 42, 12 }, { 49, 55, 4 } } do
		block(map, "FilingCabinets", c[1], B, c[3], c[2], B + 4.5, c[3] + 1.6, Color3.fromRGB(120, 124, 130), Enum.Material.Metal)
	end
	block(map, "BreakTable", 14, B, 26, 24, B + 2.8, 30, WOOD, Enum.Material.Wood)
	block(map, "Counter", 9, B, 32, 11, B + 3.2, 39.5, WHITE, Enum.Material.Marble)
	block(map, "Fridge", 26, B, 37, 29.5, B + 7, 39.5, WHITE, Enum.Material.Metal)

	-- Office upstairs: desk pods, server racks, the director's desk, the meeting table
	for _, d in { { 12, -36 }, { 12, -22 }, { 26, -36 }, { 26, -22 }, { 46, -22 } } do
		block(map, "Desks", d[1], F2, d[2], d[1] + 8, F2 + 2.6, d[2] + 5, PLYWOOD, Enum.Material.Wood)
		block(map, "Partition", d[1], F2, d[2] + 2.35, d[1] + 8, F2 + 4.6, d[2] + 2.65, Color3.fromRGB(90, 96, 104), Enum.Material.Fabric)
	end
	for _, z in { -2, 11.5 } do -- (clear of both doors and of the hatch between the rows)
		for x = 12.5, 24.5, 3 do
			block(map, "ServerRack", x, F2, z, x + 2.4, F2 + 7, z + 2.5, BLACK, Enum.Material.Metal)
			block(map, "ServerLights", x + 0.3, F2 + 1, z - 0.05, x + 2.1, F2 + 6, z, Color3.fromRGB(60, 200, 255), Enum.Material.Neon)
		end
	end
	block(map, "DirectorDesk", 38, F2, 8, 46, F2 + 2.8, 11, Color3.fromRGB(90, 60, 40), Enum.Material.Wood)
	block(map, "Bookshelf", 54, F2, -6, 55.5, F2 + 7, 4, Color3.fromRGB(90, 60, 40), Enum.Material.Wood)
	block(map, "MeetingTable", 12, F2, 26, 26, F2 + 2.8, 31, WOOD, Enum.Material.Wood)
end

local function buildOutside(map: MapBuilder.Builder)
	local yard = map:Folder("Yard") -- (PerimeterService: stacked containers aren't a roof)
	local function toYard(parts: { BasePart })
		for _, part in parts do
			part.Parent = yard
		end
	end

	-- Ground: grass round everything, the truck lot and its entrance off the road, the concrete
	-- apron behind the building, the car park, the gravel rail yard
	local footprint = { -64.5, -40.5, 56.5, 40.5 }
	local walkout = { -42, 40.5, -30, 57 }
	map:FloorWithHoles("Ground", -150, -130, 150, 130, { footprint, walkout }, 0.2, 0.4, GRASS, Enum.Material.Grass)
	map:Floor("Road", -150, -130, 150, -110, 0.3, 0.2, ASPHALT, Enum.Material.Asphalt)
	map:Floor("Entrance", -44, -110, -6, -100, 0.3, 0.2, ASPHALT, Enum.Material.Asphalt)
	map:FloorWithHoles("TruckLot", -110, -100, 70, -40.5, {}, 0.3, 0.2, ASPHALT, Enum.Material.Asphalt)
	map:FloorWithHoles("Apron", -70, 40.5, 56.5, 60, { walkout }, 0.3, 0.2, CONCRETE, Enum.Material.Concrete)
	map:Floor("CarPark", 56.5, -70, 120, 70, 0.3, 0.2, ASPHALT, Enum.Material.Asphalt)
	map:Floor("RailYard", -150, 60, 150, 100, 0.28, 0.2, GRAVEL, Enum.Material.Pebble)
	for x = 64, 112, 8 do
		for _, z in { -50, -20, 20, 50 } do
			cosmetic(block(map, "BayLine", x - 0.15, 0.3, z - 6, x + 0.15, 0.34, z + 6, WHITE, Enum.Material.SmoothPlastic), map.geometry)
		end
	end

	-- Walkout ramp from the rail yard side down to the loading tunnel
	map:Floor("WalkoutLanding", -42, 40.5, -30, 42, BF, 1, CONCRETE, Enum.Material.Concrete)
	map:Stairs(-41, 42, -31, 57, BF, 0.3, "+Z", CONCRETE, Enum.Material.Concrete)
	for _, x in { -42, -30 } do
		map:Wall("RetainingWall", x, 40.5, x, 57, BF, 3.4 - BF, nil, CONCRETE, Enum.Material.Concrete)
	end

	-- Rail yard: track and a boxcar (cover all along the north side)
	for _, z in { 77.6, 83.4 } do
		block(map, "Rail", -150, 0.28, z - 0.2, 150, 0.9, z + 0.2, DARK_METAL, Enum.Material.Metal)
	end
	for x = -146, 146, 6 do
		block(map, "Sleeper", x - 0.6, 0.28, 75.5, x + 0.6, 0.6, 85.5, Color3.fromRGB(80, 62, 45), Enum.Material.Wood)
	end
	toYard({ block(map, "Boxcar", -56, 1.6, 76.5, -16, 13, 84.5, Color3.fromRGB(140, 50, 40), Enum.Material.CorrodedMetal) })
	toYard({ block(map, "Boxcar", 30, 1.6, 76.5, 70, 13, 84.5, Color3.fromRGB(60, 80, 110), Enum.Material.CorrodedMetal) })

	-- Truck lot: a trailer backed up to the west dock (the other dock is clear), another parked,
	-- containers and concrete barriers for cover on the way in
	local function truck(x: number, z: number, length: number)
		toYard({
			block(map, "Trailer", x - 4, 1.6, z, x + 4, 12, z - length, Color3.fromRGB(225, 225, 220), Enum.Material.Metal),
			block(map, "Cab", x - 3.5, 1, z - length - 1, x + 3.5, 9, z - length - 8, Color3.fromRGB(170, 40, 40), Enum.Material.Metal),
		})
		for _, along in { 3, length - 3, length + 5 } do
			for _, side in { -1, 1 } do
				local wheel = map:Part("Wheel", Vector3.new(1, 3, 3), CFrame.new(x + side * 3.6, 1.8, z - along), BLACK, Enum.Material.Rubber)
				wheel.Shape = Enum.PartType.Cylinder
				wheel.Parent = yard
			end
		end
	end
	truck(-53, -44, 22)
	truck(30, -60, 22)
	toYard(container(map, -100, -82, true, 0.3, Color3.fromRGB(150, 45, 40), false))
	toYard(container(map, 38, -96, true, 0.3, Color3.fromRGB(50, 110, 70), false))
	for _, w in { { -24, -66, -16, -66 }, { 0, -78, 8, -78 }, { -84, -58, -84, -50 }, { 46, -50, 54, -50 }, { -6, -56, 2, -56 } } do
		map:Wall("Barrier", w[1], w[2], w[3], w[4], 0.3, 3, nil, CONCRETE, Enum.Material.Concrete, 1.2)
	end

	-- Container yard (west): stacks, one and two high
	for _, c in { { -112, -52, true, 2 }, { -126, -22, true, 1 }, { -100, 6, true, 2 }, { -124, 34, true, 1 }, { -92, 36, false, 1 }, { -134, -60, false, 2 } } do
		local x, z, alongX, high = c[1], c[2], c[3], c[4]
		for level = 0, high - 1 do
			local colors = { Color3.fromRGB(40, 80, 140), Color3.fromRGB(200, 110, 40), Color3.fromRGB(50, 110, 70), Color3.fromRGB(150, 45, 40) }
			toYard(container(map, x, z, alongX, 0.2 + level * 8.6, colors[(math.abs(x + z) + level) % 4 + 1], false))
		end
	end

	-- Staff car park (east)
	for _, car in { { 70, -44, Color3.fromRGB(180, 30, 30) }, { 78, -14, Color3.fromRGB(40, 60, 120) }, { 102, 22, Color3.fromRGB(210, 210, 205) }, { 94, -52, BLACK }, { 70, 46, Color3.fromRGB(120, 120, 125) } } do
		local x, z = car[1], car[2]
		toYard({
			block(map, "Car", x - 2.6, 0.9, z - 6, x + 2.6, 3.2, z + 6, car[3], Enum.Material.SmoothPlastic),
			block(map, "CarCabin", x - 2.3, 3.2, z - 3, x + 2.3, 5, z + 2.5, Color3.fromRGB(30, 34, 40), Enum.Material.Glass),
		})
	end

	-- Light poles
	for _, p in { { -80, -90 }, { 0, -92 }, { 50, -70 }, { -100, 30 }, { 88, 0 }, { 0, 66 } } do
		block(map, "LightPole", p[1] - 0.3, 0.3, p[2] - 0.3, p[1] + 0.3, 20, p[2] + 0.3, DARK_METAL, Enum.Material.Metal)
		map:Light(Vector3.new(p[1], 20, p[2]), 40)
	end

	-- Chain-link fence along the west and north edges
	for _, f in { { -140, -100, -140, 110 }, { -140, 110, 140, 110 } } do
		for _, piece in map:Wall("Fence", f[1], f[2], f[3], f[4], 0.2, 7, nil, MESH, Enum.Material.DiamondPlate, 0.3) do
			piece.Transparency = 0.6
		end
	end

	-- Invisible walls at the edge of the world
	for _, edge in { { -150, -130, 150, -130 }, { -150, 130, 150, 130 }, { -150, -130, -150, 130 }, { 150, -130, 150, 130 } } do
		for _, piece in map:Wall("Boundary", edge[1], edge[2], edge[3], edge[4], -20, 120, nil, Color3.new(), nil, 2) do
			piece.Transparency = 1
			piece.CanQuery = false
		end
	end
end

-- Bar between two points (truss members, braces)
local function strut(map: MapBuilder.Builder, name: string, a: Vector3, b: Vector3, thickness: number, color: Color3)
	local part = map:Part(name, Vector3.new(thickness, thickness, (b - a).Magnitude), CFrame.lookAt((a + b) / 2, b), color, Enum.Material.Metal)
	cosmetic(part, map.geometry)
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
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = textColor
	label.Text = text
	label.Parent = gui
end

-- The hall's steel: roof trusses across it, purlins along it, and two columns out on the floor
local function buildStructure(map: MapBuilder.Builder)
	local steel = Color3.fromRGB(88, 94, 102)
	local bottom, top = HALL_ROOF - 4, HALL_ROOF - 1.2
	for _, x in { -56, -44, -32, -20, -8, 4 } do
		strut(map, "TrussChord", Vector3.new(x, bottom, -39.5), Vector3.new(x, bottom, 39.5), 0.35, steel)
		strut(map, "TrussChord", Vector3.new(x, top, -39.5), Vector3.new(x, top, 39.5), 0.35, steel)
		for i = 0, 19 do
			local z1, z2 = -39.5 + i * 3.95, -39.5 + (i + 1) * 3.95
			local up = i % 2 == 0
			strut(map, "TrussWeb", Vector3.new(x, if up then bottom else top, z1), Vector3.new(x, if up then top else bottom, z2), 0.2, steel)
		end
	end
	for z = -36, 36, 8 do
		strut(map, "Purlin", Vector3.new(-63.5, HALL_ROOF - 1.15, z), Vector3.new(7.5, HALL_ROOF - 1.15, z), 0.3, steel)
	end
	-- I-beam columns (cover out on the open floor)
	for _, z in { -30, 20 } do
		local x = -32
		block(map, "Column", x - 0.12, B, z - 0.5, x + 0.12, bottom, z + 0.5, SAFETY_YELLOW, Enum.Material.Metal)
		for _, side in { -1, 1 } do
			block(map, "Column", x - 0.5, B, z + side * 0.5 - 0.08, x + 0.5, bottom, z + side * 0.5 + 0.08, SAFETY_YELLOW, Enum.Material.Metal)
		end
	end
end

-- Paint, docks, signs, rooftop plant and the small things on the outside walls
local function buildDetails(map: MapBuilder.Builder)
	local paint = map:Folder("Paint")
	local function line(x1: number, z1: number, x2: number, z2: number, color: Color3?)
		cosmetic(block(map, "FloorLine", x1, B + 0.01, z1, x2, B + 0.04, z2, color or SAFETY_YELLOW, Enum.Material.SmoothPlastic), paint)
	end
	local function outline(x1: number, z1: number, x2: number, z2: number)
		line(x1, z1, x2, z1 + 0.3)
		line(x1, z2 - 0.3, x2, z2)
		line(x1, z1, x1 + 0.3, z2)
		line(x2 - 0.3, z1, x2, z2)
	end
	-- Lines along the rack faces, keep-clear boxes inside the dock doors, the stairwell opening
	for _, r in { { -57, -12, -54, 18 }, { -47, -8, -44, 20 }, { -31, -16, -28, 10 } } do
		line(r[1] - 0.9, r[2] - 0.5, r[1] - 0.6, r[4] + 0.5)
		line(r[3] + 0.6, r[2] - 0.5, r[3] + 0.9, r[4] + 0.5)
	end
	line(-52.5, 25.1, -29.5, 25.4)
	for _, d in { { -58, -39.5, -48, -31 }, { -42, -39.5, -32, -31 }, { -62, 31, -50, 39.5 } } do
		outline(d[1], d[2], d[3], d[4])
	end
	outline(-41, -21, -33, -3)
	-- Walkway from the side door to the staging area
	line(-24, -38, -23.7, -21)

	-- Loading docks: rolled-up shutters, guide rails, rubber bumpers outside, bollards
	local shutter = Color3.fromRGB(176, 182, 188)
	for _, d in { { -58, -48, -40, -1 }, { -42, -32, -40, -1 }, { -62, -50, 40, 1 } } do
		local x1, x2, z, out = d[1], d[2], d[3], d[4]
		local inside = z - out * 0.9
		local drum = map:Part("ShutterDrum", Vector3.new(x2 - x1 + 1, 1.5, 1.5), CFrame.new((x1 + x2) / 2, B + 11.8, inside), DARK_METAL, Enum.Material.Metal)
		drum.Shape = Enum.PartType.Cylinder
		cosmetic(drum, map.geometry)
		block(map, "Shutter", x1, B + 9.6, inside - 0.1, x2, B + 11, inside + 0.1, shutter, Enum.Material.Metal)
		for _, x in { x1 - 0.3, x2 + 0.3 } do
			cosmetic(block(map, "ShutterRail", x - 0.15, B, inside - 0.15, x + 0.15, B + 11.5, inside + 0.15, DARK_METAL, Enum.Material.Metal), map.geometry)
			local face = z + out * 0.5
			block(map, "Bumper", x - 0.5, 0.3, face, x + 0.5, 2.2, face + out * 0.8, BLACK, Enum.Material.Rubber)
			local bollard = map:Part("Bollard", Vector3.new(3.4, 0.8, 0.8), CFrame.new(x + (if x < (x1 + x2) / 2 then -1.2 else 1.2), 2, z + out * 2.4) * CFrame.Angles(0, 0, math.pi / 2), SAFETY_YELLOW, Enum.Material.Metal)
			bollard.Shape = Enum.PartType.Cylinder
		end
		sign(map, if out < 0 then (if x1 == -58 then "DOCK 1" else "DOCK 2") else "RAIL DOCK", CFrame.new((x1 + x2) / 2, B + 13.4, z + out * 0.62) * CFrame.Angles(0, if out < 0 then 0 else math.pi, 0), Vector2.new(6, 1.6), Color3.fromRGB(30, 40, 60), WHITE)
	end
	-- Canopy over the south docks, on braces
	block(map, "DockCanopy", -61, B + 13.6, -48, -29, B + 14.1, -40.5, DARK_METAL, Enum.Material.Metal)
	for _, x in { -60, -45, -30 } do
		strut(map, "CanopyBrace", Vector3.new(x, B + 9, -40.6), Vector3.new(x, B + 13.6, -47.5), 0.3, DARK_METAL)
	end

	-- Office entrance: canopy on two posts, company sign over it, the big sign on the hall
	block(map, "EntranceCanopy", 13, B + 10.4, -47, 27, B + 11, -40.5, DARK_METAL, Enum.Material.Metal)
	for _, x in { 14, 26 } do
		block(map, "CanopyPost", x - 0.3, 0.3, -46.4, x + 0.3, B + 10.4, -45.8, DARK_METAL, Enum.Material.Metal)
	end
	sign(map, "RECEPTION", CFrame.new(20, B + 11.8, -47.15), Vector2.new(10, 1.4), DARK_METAL, WHITE)
	sign(map, "NORTHGATE LOGISTICS", CFrame.new(-36, HALL_ROOF - 6, -40.62), Vector2.new(44, 5), Color3.fromRGB(28, 46, 84), WHITE)
	sign(map, "NORTHGATE LOGISTICS", CFrame.new(-28, HALL_ROOF - 6, 40.62) * CFrame.Angles(0, math.pi, 0), Vector2.new(40, 5), Color3.fromRGB(28, 46, 84), WHITE)

	-- Rooftop: air-conditioning units on the offices, vents on the hall
	for _, u in { { 22, 8 }, { 46, 24 }, { 30, 30 } } do
		block(map, "HVAC", u[1] - 3, OFFICE_ROOF, u[2] - 2.5, u[1] + 3, OFFICE_ROOF + 3.6, u[2] + 2.5, Color3.fromRGB(196, 198, 194), Enum.Material.Metal)
		local fan = map:Part("HVACFan", Vector3.new(0.3, 3.2, 3.2), CFrame.new(u[1] + 1, OFFICE_ROOF + 3.7, u[2]) * CFrame.Angles(0, 0, math.pi / 2), DARK_METAL, Enum.Material.DiamondPlate)
		fan.Shape = Enum.PartType.Cylinder
	end
	for _, v in { { -54, -30 }, { -30, 24 }, { -6, -28 } } do
		local vent = map:Part("RoofVent", Vector3.new(2.4, 2.6, 2.6), CFrame.new(v[1], HALL_ROOF + 1.2, v[2]) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(170, 174, 178), Enum.Material.Metal)
		vent.Shape = Enum.PartType.Cylinder
	end

	-- Downspouts at the corners, lamps over the outside doors, a dumpster by the offices
	for _, c in { { -64.9, -40.9, HALL_ROOF }, { -64.9, 40.9, HALL_ROOF }, { 56.9, -40.9, OFFICE_ROOF }, { 56.9, 40.9, OFFICE_ROOF } } do
		cosmetic(block(map, "Downspout", c[1] - 0.3, 0.3, c[2] - 0.3, c[1] + 0.3, c[3], c[2] + 0.3, Color3.fromRGB(120, 126, 132), Enum.Material.Metal), map.geometry)
	end
	for _, l in { { -17.5, -41, 0 }, { -45.5, 41, math.pi }, { -3.5, 41, math.pi }, { -65, -9.5, math.pi / 2 }, { -65, 17.5, math.pi / 2 }, { 57, -29.5, -math.pi / 2 }, { 57, 32.5, -math.pi / 2 }, { 38.5, 41, math.pi } } do
		local lamp = map:Part("WallLamp", Vector3.new(1.2, 0.6, 0.8), CFrame.new(l[1], B + 9.6, l[2]) * CFrame.Angles(0, l[3], 0), DARK_METAL, Enum.Material.Metal)
		cosmetic(lamp, map.geometry)
		local glow = map:Part("Light", Vector3.new(1, 0.1, 0.6), lamp.CFrame * CFrame.new(0, -0.32, 0), Color3.fromRGB(255, 236, 190), Enum.Material.Neon)
		cosmetic(glow, map.geometry)
		local light = Instance.new("PointLight")
		light.Range = 16
		light.Brightness = 1
		light.Color = Color3.fromRGB(255, 226, 180)
		light.Parent = glow
	end
	block(map, "Dumpster", 21, 0.3, 46, 27, 4.4, 49.5, Color3.fromRGB(40, 90, 60), Enum.Material.Metal)
	block(map, "DumpsterLid", 20.8, 4.4, 45.8, 27.2, 4.7, 49.7, Color3.fromRGB(30, 30, 32), Enum.Material.Plastic)
end

-- Surfaces from the place's MaterialService (corrugated cladding, warehouse concrete, grating).
-- Without those variants (code-only builds) Roblox just shows the base material.
local function applyFinishes(map: MapBuilder.Builder)
	for _, part in map.model:GetDescendants() do
		if part:IsA("BasePart") then
			if part.Material == Enum.Material.Metal and part.Color:ToHex() == SIDING:ToHex() then
				part.MaterialVariant = "CorrugatedSteel"
			elseif part.Name == "HallFloor" then
				part.MaterialVariant = "WarehouseConcrete"
			elseif part.Name == "Catwalk" then
				part.MaterialVariant = "SteelGrating"
			end
		end
	end
end

function Warehouse.Build(): Model
	local map = MapBuilder.new("Warehouse")
	buildFloors(map)
	buildBasement(map)
	buildGround(map)
	buildUpstairs(map)
	buildStairs(map)
	buildStructure(map)
	buildProps(map)
	buildDetails(map)
	buildOutside(map)
	applyFinishes(map)

	-- Sites: four pairs, A and B each; the defenders pick one pair per round
	local function site(name: string, x1: number, z1: number, x2: number, z2: number, level: number, pair: string, room: string)
		map:Site(name, Vector3.new(x1 + 0.5, level, z1 + 0.5), Vector3.new(x2 - 0.5, level + 6, z2 - 0.5), pair, room)
	end
	site("A", -28, -40, 8, -10, BF, "Basement", "Cold storage")
	site("B", 8, -40, 32, -10, BF, "Basement", "Boiler room")
	site("A", -24, -8, 8, 14, B, "Hall", "Secure cage")
	site("B", -24, 14, 8, 40, B, "Hall", "Packing")
	site("A", 8, -8, 30, 16, B, "Offices", "Manager")
	site("B", 34, -8, 56, 16, B, "Offices", "Records")
	site("A", 8, -8, 30, 16, F2, "Upstairs", "Server room")
	site("B", 34, -8, 56, 16, F2, "Upstairs", "Director")

	-- Defenders spawn by the pair they picked; attackers in the truck lot, the rail yard or the car park
	map:SpawnPad("Defend", Vector3.new(-6, BF + 0.1, 16), Vector3.new(0, 0, -1), "Basement")
	map:SpawnPad("Defend", Vector3.new(-6, B + 0.1, 26.75), Vector3.new(0, 0, -1), "Hall")
	map:SpawnPad("Defend", Vector3.new(19, B + 0.1, 22), Vector3.new(0, 0, -1), "Offices")
	map:SpawnPad("Defend", Vector3.new(19, F2 + 0.1, 22), Vector3.new(0, 0, -1), "Upstairs")
	map:SpawnPad("Attack", Vector3.new(-25, 0.4, -105), Vector3.new(0, 0, 1))
	map:SpawnPad("Attack", Vector3.new(-10, 0.4, 106), Vector3.new(0, 0, -1))
	map:SpawnPad("Attack", Vector3.new(112, 0.4, 0), Vector3.new(-1, 0, 0))
	map:FreeRoamSpawn(Vector3.new(-10, 0.6, -64))

	return map.model
end

return Warehouse
