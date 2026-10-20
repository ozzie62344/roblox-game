-- HOUSE — a big three-floor suburban house in the spirit of Rainbow Six Siege's House: basement,
-- ground floor and upstairs, two staircases, an attached garage and a big yard all round.
-- Four site pairs; the defenders pick one each round (RoundService / SitePicker):
--   Basement:  Gym + Workshop            Kitchen:   Dining room + Kitchen
--   Office:    Office + Den              Bedrooms:  Kids room + Master bedroom
--
--   Ground floor (north = +z; the street is south):
--   ┌─────────┬───────────┬──────┬─────────────┐
--   │ KITCHEN │ back hall │pantry│ mudroom ▓▓  │   ▓▓ back stairs: cellar → mudroom → game room
--   ├─────────┤           ├──────┤             │
--   │ DINING  │           │powder├─────────────┤
--   ├─────────┼───────────┴──────┤ DEN         │
--   │ living  │ hall  ▒▒  ▓▓     ├─────────────┼─────────┐
--   │         │ foyer            │ OFFICE      │ garage  │
--   └─────────┴──────────────────┴─────────────┴─────────┘
--   ▒▒ down to the basement, ▓▓ up to the landing. Upstairs: KIDS ROOM + MASTER over the living
--   and dining rooms, guest room, foyer balcony, art room, study, nursery, game room.
--   Basement: GYM + WORKSHOP under them, rec room, bunker, boiler room, walkout stairs (north).
--
-- Attackers spawn on the street (south), in the back alley (north) or on the east side drive.
-- Soft walls (plaster drywall, painted siding) can be shot through, breached and reinforced;
-- brick and concrete can't. Outside doors and windows start barricaded. The wooden floors are
-- soft too, and a hatch over every lower site lets attackers drop in from above.
-- Units: studs. The house spans x -56..56, z -40..40; the garage x 56..84, z -40..-4.

local MapBuilder = require(script.Parent.MapBuilder)

local House = {}

-- Floor levels (the top of each floor)
local BF = -11.6 -- basement
local B = 0.4 -- ground floor
local F2 = 13.4 -- upstairs
local CEILING = 24.4 -- upstairs ceiling
local BASEMENT_WALL = 11 -- basement floor up to the ground floor slab
local GROUND_WALL = 12
local UPSTAIRS_WALL = 11
local ROOF_BASE = CEILING + 1
local PITCH = math.rad(22)

-- Look
local BRICK = Color3.fromRGB(150, 88, 70)
local PLASTER = Color3.fromRGB(226, 218, 200)
local SIDING = Color3.fromRGB(222, 216, 200)
local WOOD = Color3.fromRGB(150, 110, 75)
local DARK_WOOD = Color3.fromRGB(95, 66, 45)
local CONCRETE = Color3.fromRGB(150, 150, 150)
local WHITE = Color3.fromRGB(240, 238, 232)
local GRASS = Color3.fromRGB(90, 135, 70)
local ASPHALT = Color3.fromRGB(55, 55, 60)
local ROOF = Color3.fromRGB(70, 66, 66)
local FENCE = Color3.fromRGB(200, 190, 170)

-- Walls: soft ones can be shot through, breached and reinforced; brick and concrete can't
local DRYWALL: MapBuilder.Style = { color = PLASTER, material = Enum.Material.Plaster, soft = true }
local OUTSIDE_SOFT: MapBuilder.Style = { color = SIDING, material = Enum.Material.WoodPlanks, soft = true, exterior = true }
local OUTSIDE_BRICK: MapBuilder.Style = { color = BRICK, material = Enum.Material.Brick, exterior = true }
local OUTSIDE_CONCRETE: MapBuilder.Style = { color = CONCRETE, material = Enum.Material.Concrete, exterior = true }
local BRICK_WALL: MapBuilder.Style = { color = BRICK, material = Enum.Material.Brick }
local CONCRETE_WALL: MapBuilder.Style = { color = CONCRETE, material = Enum.Material.Concrete }

-- Floor finishes over the wood / concrete
local CARPET = { Color3.fromRGB(150, 140, 125), Enum.Material.Carpet }
local BLUE_CARPET = { Color3.fromRGB(95, 120, 150), Enum.Material.Carpet }
local GREY_CARPET = { Color3.fromRGB(105, 105, 110), Enum.Material.Carpet }
local ROSE_CARPET = { Color3.fromRGB(175, 135, 135), Enum.Material.Carpet }
local TILE = { Color3.fromRGB(225, 225, 220), Enum.Material.CeramicTiles }
local MARBLE = { Color3.fromRGB(232, 230, 224), Enum.Material.Marble }
local RUBBER = { Color3.fromRGB(45, 45, 48), Enum.Material.Rubber }
local BRICK_FLOOR = { Color3.fromRGB(140, 85, 65), Enum.Material.Brick }

-- Holes in the floors: { x1, z1, x2, z2 }
local BASEMENT_STAIRS = { -8, -20, -2, -4 } -- hall down to the rec room (climbs +z)
local MAIN_STAIRS = { 2, -20, 8, -4 } -- hall up to the landing (climbs +z)
local FOYER_VOID = { -9.5, -39.5, 9.5, -24 } -- the foyer is open up to the roof
local BACK_LOWER = { 44, 16, 49.5, 32 } -- back stairs, cellar up to the mudroom (climbs +z)
local BACK_UPPER = { 50.5, 18, 55.5, 34 } -- back stairs, mudroom up to the game room (climbs -z)
-- Hatches (4 × 4 trapdoors) over every site below the top floor: x, z, the floor they're in
local HATCH = 4
local HATCHES = {
	{ -48, -28, B }, -- living room → gym
	{ -44, 11, B }, -- dining room → workshop
	{ -50, -1.5, F2 }, -- master bedroom → dining room
	{ -36, 34, F2 }, -- master bath → kitchen
	{ 46, -17, F2 }, -- study → office
	{ 32, 4, F2 }, -- nursery → den
}
local GROUND_HOLES = { BASEMENT_STAIRS, BACK_LOWER }
local UPSTAIRS_HOLES = { FOYER_VOID, MAIN_STAIRS, BACK_UPPER }
for _, hatch in HATCHES do
	local x, z, level = hatch[1], hatch[2], hatch[3]
	table.insert(if level == B then GROUND_HOLES else UPSTAIRS_HOLES, { x - HATCH / 2, z - HATCH / 2, x + HATCH / 2, z + HATCH / 2 })
end

-- name, x1, z1, x2, z2, floor, finish (nil = bare wood / concrete). Lights and floors come from here.
local ROOMS = {
	{ "Gym", -56, -40, -20, -6, BF, RUBBER },
	{ "Workshop", -56, -6, -20, 22, BF },
	{ "WineCellar", -56, 22, -20, 40, BF, BRICK_FLOOR },
	{ "RecRoom", -20, -40, 20, -2, BF, GREY_CARPET },
	{ "Storage", -20, -2, -6, 40, BF },
	{ "BasementHall", -6, -2, 6, 40, BF },
	{ "Bunker", 6, -2, 20, 22, BF },
	{ "PumpRoom", 6, 22, 20, 40, BF },
	{ "BoilerRoom", 20, -40, 56, -14, BF },
	{ "Utility", 20, -14, 56, 14, BF },
	{ "CellarStairs", 20, 14, 56, 40, BF },

	{ "Living", -56, -40, -20, -10, B },
	{ "Dining", -56, -10, -20, 14, B },
	{ "Kitchen", -56, 14, -20, 40, B, TILE },
	{ "Foyer", -20, -40, 20, -22, B, MARBLE },
	{ "Hall", -20, -22, 20, 10, B },
	{ "BackHall", -20, 10, 6, 40, B },
	{ "Powder", 6, 10, 20, 24, B, TILE },
	{ "Pantry", 6, 24, 20, 40, B, TILE },
	{ "Office", 20, -40, 56, -14, B },
	{ "Den", 20, -14, 56, 14, B, CARPET },
	{ "Mudroom", 20, 14, 56, 40, B, TILE },
	{ "Garage", 56, -40, 84, -4, B },

	{ "KidsRoom", -56, -40, -22, -4, F2, BLUE_CARPET },
	{ "Master", -56, -4, -22, 28, F2, CARPET },
	{ "MasterBath", -56, 28, -22, 40, F2, TILE },
	{ "Guest", -22, -40, -10, -24, F2, CARPET },
	{ "Closet", 10, -40, 22, -24, F2, CARPET },
	{ "Landing", -22, -24, 22, 12, F2 },
	{ "Bathroom", -22, 12, 0, 24, F2, TILE },
	{ "Corridor", 0, 12, 8, 24, F2 },
	{ "Linen", 8, 12, 22, 24, F2 },
	{ "ArtRoom", -22, 24, 22, 40, F2 },
	{ "Study", 22, -40, 56, -10, F2 },
	{ "Nursery", 22, -10, 42, 14, F2, ROSE_CARPET },
	{ "Bath", 42, -10, 56, 4, F2, TILE },
	{ "WalkIn", 42, 4, 56, 14, F2, CARPET },
	{ "GameRoom", 22, 14, 56, 40, F2, GREY_CARPET },
}

-- Openings (positions are world x / z along the wall)
local door = MapBuilder.Door
local doubleDoor = MapBuilder.DoubleDoor
local window = MapBuilder.Window
local arch = MapBuilder.Arch

-- Wall along x at `z`, or along z at `x`
local wallX = MapBuilder.WallX
local wallZ = MapBuilder.WallZ

-- Looks only: no collisions, bullets go through
local cosmetic = MapBuilder.Cosmetic

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

local function ceilingOf(level: number): number
	return if level == BF then B - 1 elseif level == B then F2 - 1 else CEILING
end

local function buildFloors(map: MapBuilder.Builder)
	local shell = map:Folder("Shell")
	-- The wooden floors are soft (shoot down through them, breach them); concrete isn't
	map:Floor("BasementFloor", -56.5, -40.5, 56.5, 40.5, BF, 1, CONCRETE, Enum.Material.Concrete)
	for _, piece in map:FloorWithHoles("Floor", -56.5, -40.5, 56.5, 40.5, GROUND_HOLES, B, 1, WOOD, Enum.Material.WoodPlanks) do
		piece:SetAttribute("Breakable", "Soft")
	end
	map:Floor("GarageFloor", 56.5, -40.5, 84.5, -3.5, B, 1, CONCRETE, Enum.Material.Concrete)
	for _, piece in map:FloorWithHoles("Floor2", -56.5, -40.5, 56.5, 40.5, UPSTAIRS_HOLES, F2, 1, WOOD, Enum.Material.WoodPlanks) do
		piece:SetAttribute("Breakable", "Soft")
		-- Painted ceiling under the wood (DestructionService cuts it along with the floor)
		cosmetic(map:Part("Ceiling", Vector3.new(piece.Size.X, 0.1, piece.Size.Z), piece.CFrame * CFrame.new(0, -0.55, 0), WHITE, Enum.Material.Plaster), shell)
	end
	for _, hatch in HATCHES do
		map:Hatch(hatch[1], hatch[2], hatch[3], HATCH)
	end
	map:Floor("UpstairsCeiling", -56.5, -40.5, 56.5, 40.5, ROOF_BASE, 1, WHITE, Enum.Material.Plaster)
	map:Floor("GarageCeiling", 56.5, -40.5, 84.5, -3.5, F2, 1, WHITE, Enum.Material.Plaster)

	for _, room in ROOMS do
		local name, x1, z1, x2, z2, level, finish = table.unpack(room)
		if finish then
			local holes = if level == B then GROUND_HOLES elseif level == F2 then UPSTAIRS_HOLES else {}
			for _, piece in map:FloorWithHoles(name .. "Floor", x1, z1, x2, z2, holes, level + 0.04, 0.04, finish[1], finish[2]) do
				cosmetic(piece, shell)
			end
		end
		-- Ceiling lights, spread along the room's long side (the foyer's hang from the roof)
		local top = if name == "Foyer" then CEILING else ceilingOf(level)
		local count = math.max(1, math.round((x2 - x1) * (z2 - z1) / 500))
		for i = 1, count do
			local t = (i - 0.5) / count
			local position = if x2 - x1 >= z2 - z1
				then Vector3.new(x1 + (x2 - x1) * t, top - 0.2, (z1 + z2) / 2)
				else Vector3.new((x1 + x2) / 2, top - 0.2, z1 + (z2 - z1) * t)
			map:Light(position, if name == "Foyer" then 40 else 26)
		end
	end
end

local function buildBasement(map: MapBuilder.Builder)
	local base, h = BF, BASEMENT_WALL
	-- Outside walls: poured concrete, underground
	wallX(map, OUTSIDE_CONCRETE, -40, -56.5, 56.5, base, h, nil, 1)
	wallX(map, OUTSIDE_CONCRETE, 40, -56.5, 56.5, base, h, { door(38) }, -1) -- walkout to the back yard
	wallZ(map, OUTSIDE_CONCRETE, -56, -40, 40, base, h, nil, 1)
	wallZ(map, OUTSIDE_CONCRETE, 56, -40, 40, base, h, nil, -1)

	-- West: GYM + WORKSHOP (site pair) and the wine cellar, off the rec room and storage
	wallZ(map, DRYWALL, -20, -40, 40, base, h, { door(-33), door(-17), door(8), door(31) })
	wallX(map, CONCRETE_WALL, -6, -56, -20, base, h, { arch(-45, -31) }) -- gym ↔ workshop
	wallX(map, DRYWALL, 22, -56, -20, base, h, { door(-40) }) -- workshop ↔ wine cellar

	-- Middle: rec room (the stairs from the hall land here), storage, hall, bunker, pump room
	wallX(map, DRYWALL, -2, -20, 6, base, h, { door(-16), arch(-4, 4) })
	wallX(map, CONCRETE_WALL, -2, 6, 20, base, h, { door(12) }) -- the bunker is concrete all round
	wallZ(map, DRYWALL, -6, -2, 40, base, h, { door(20) })
	wallZ(map, CONCRETE_WALL, 6, -2, 22, base, h, { door(6) })
	wallZ(map, DRYWALL, 6, 22, 40, base, h, { door(30) })
	wallX(map, CONCRETE_WALL, 22, 6, 20, base, h)
	for _, x in { -12, 12 } do
		map:Box("Column", Vector3.new(x - 1, base, -29), Vector3.new(x + 1, B - 1, -27), CONCRETE, Enum.Material.Concrete)
	end

	-- East: boiler room, utility, and the back stairs room with the walkout
	wallZ(map, DRYWALL, 20, -40, -2, base, h, { door(-30), door(-9) })
	wallZ(map, CONCRETE_WALL, 20, -2, 22, base, h)
	wallZ(map, DRYWALL, 20, 22, 40, base, h, { door(33) })
	wallX(map, CONCRETE_WALL, -14, 20, 56, base, h, { door(30) })
	wallX(map, DRYWALL, 14, 20, 56, base, h, { door(26), door(44.5) })
end

local function buildGround(map: MapBuilder.Builder)
	local base, h = B, GROUND_WALL
	-- Front: brick, with the front door
	wallX(map, OUTSIDE_BRICK, -40, -56.5, 56, base, h, {
		window(-50, -44),
		window(-36, -28), -- living room
		window(-16, -12),
		doubleDoor(-4),
		window(12, 16), -- foyer
		window(26, 32),
		window(42, 50), -- office
	}, 1)
	-- Garage: the big door is up (a plain hole)
	wallX(map, OUTSIDE_SOFT, -40, 56, 84.5, base, h, { { from = 60, to = 80, top = 10 } }, 1)
	wallZ(map, OUTSIDE_SOFT, 84, -40.5, -3.5, base, h, { door(-30), window(-18, -12) }, -1)
	wallX(map, OUTSIDE_SOFT, -4, 56, 84.5, base, h, { window(64, 70), door(76) }, -1)
	-- Back and sides: painted siding
	wallX(map, OUTSIDE_SOFT, 40, -56.5, 56.5, base, h, {
		window(-50, -44),
		door(-32), -- kitchen
		doubleDoor(-10), -- patio doors
		window(11, 15), -- pantry
		door(26),
		window(36, 42),
		window(47, 53), -- mudroom
	}, -1)
	wallZ(map, OUTSIDE_SOFT, -56, -40, 40, base, h, { window(-34, -28), window(-20, -14), window(-4, 2), window(6, 10), window(24, 30) }, 1)
	wallZ(map, OUTSIDE_SOFT, 56, -40, -4, base, h, { door(-11) }, -1) -- garage → den
	wallZ(map, OUTSIDE_SOFT, 56, -4, 40, base, h, { window(0, 6), door(34) }, -1)

	-- West: living room, DINING + KITCHEN (site pair)
	wallZ(map, BRICK_WALL, -20, -40, -22, base, h, { arch(-36, -26) }) -- living ↔ foyer
	wallZ(map, DRYWALL, -20, -22, 40, base, h, { door(0), door(22), door(31) })
	wallX(map, DRYWALL, -10, -56, -20, base, h, { arch(-46, -36) }) -- living ↔ dining
	wallX(map, DRYWALL, 14, -56, -20, base, h, { arch(-50, -38, 9.5), door(-31) }) -- dining ↔ kitchen

	-- Middle: foyer, hall (both staircases), back hall, powder room, pantry
	wallX(map, BRICK_WALL, -22, -20, 20, base, h, { arch(-14, 14, 10) }) -- foyer ↔ hall
	wallX(map, DRYWALL, 10, -20, 20, base, h, { arch(-16, -6) })
	wallZ(map, DRYWALL, 6, 10, 40, base, h, { door(15), door(28) })
	wallX(map, DRYWALL, 24, 6, 20, base, h)

	-- East: OFFICE + DEN (site pair), mudroom
	wallZ(map, DRYWALL, 20, -40, 40, base, h, { door(-32), doubleDoor(-4), door(30) })
	wallX(map, DRYWALL, -14, 20, 56, base, h, { door(34), door(46) }) -- office ↔ den
	wallX(map, DRYWALL, 14, 20, 56, base, h, { door(26), door(38) }) -- den ↔ mudroom
end

local function buildUpstairs(map: MapBuilder.Builder)
	local base, h = F2, UPSTAIRS_WALL
	wallX(map, OUTSIDE_SOFT, -40, -56.5, 56.5, base, h, {
		window(-50, -44),
		window(-36, -30), -- kids room
		window(-18, -14), -- guest room
		window(-6, 6, 2, 9), -- tall window over the foyer
		window(14, 17), -- closet
		window(28, 34),
		window(44, 50), -- study
	}, 1)
	wallX(map, OUTSIDE_SOFT, 40, -56.5, 56.5, base, h, {
		window(-44, -38), -- master bath
		window(-16, -8),
		window(4, 12), -- art room
		window(28, 36),
		window(40, 46), -- game room
	}, -1)
	wallZ(map, OUTSIDE_SOFT, -56, -40, 40, base, h, { window(-26, -20), window(4, 10), window(16, 22), window(32, 36) }, 1)
	-- (no windows over the garage roof)
	wallZ(map, OUTSIDE_SOFT, 56, -40, 40, base, h, { window(-4, 0), window(34, 38) }, -1)

	-- West: KIDS ROOM + MASTER (site pair), master bath
	wallZ(map, DRYWALL, -22, -40, 12, base, h, { door(-14), door(4) })
	wallZ(map, BRICK_WALL, -22, 12, 40, base, h) -- chimney and plumbing
	wallX(map, DRYWALL, -4, -56, -22, base, h, { door(-30) }) -- kids ↔ master
	wallX(map, DRYWALL, 28, -56, -22, base, h, { door(-30) }) -- master ↔ master bath

	-- Middle: guest room and closet either side of the foyer balcony, landing, bathroom, art room
	wallX(map, DRYWALL, -24, -22, -10, base, h, { door(-17) })
	wallX(map, DRYWALL, -24, 10, 22, base, h, { door(12) })
	wallZ(map, DRYWALL, -10, -40, -24, base, h, { window(-36, -28) }) -- guest room looks down into the foyer
	wallZ(map, DRYWALL, 10, -40, -24, base, h)
	wallX(map, DRYWALL, 12, -22, 22, base, h, { arch(0, 8) }) -- landing ↔ corridor to the art room
	wallZ(map, DRYWALL, 0, 12, 24, base, h, { door(15) })
	wallZ(map, DRYWALL, 8, 12, 24, base, h, { door(15) })
	wallX(map, DRYWALL, 24, -22, 22, base, h, { door(1.5) })

	-- East: study, nursery, bath, walk-in closet, game room (back stairs)
	wallZ(map, DRYWALL, 22, -40, 40, base, h, { door(-18), door(0), arch(29, 37) })
	wallX(map, DRYWALL, -10, 22, 56, base, h, { door(32) })
	wallZ(map, DRYWALL, 42, -10, 14, base, h, { door(-6), door(7) })
	wallX(map, DRYWALL, 4, 42, 56, base, h)
	wallX(map, DRYWALL, 14, 22, 56, base, h, { door(30) })
end

local function buildStairs(map: MapBuilder.Builder)
	-- Main stairs up and the stairs down to the basement, side by side in the hall
	map:Stairs(2, -20, 8, -4, B, F2, "+Z", WOOD)
	map:Stairs(-8, -20, -2, -4, BF, B, "+Z", WOOD)
	-- Back stairs in the north-east corner, a brick wall between the two flights
	map:Stairs(44, 16, 49.5, 32, BF, B, "+Z", WOOD)
	map:Stairs(50.5, 18, 55.5, 34, B, F2, "-Z", WOOD)
	wallZ(map, BRICK_WALL, 50, 16, 34, BF, F2 - BF)

	local function rail(x1: number, z1: number, x2: number, z2: number, y: number)
		map:Railing(Vector3.new(x1, y, z1), Vector3.new(x2, y, z2))
	end
	-- Around the floor openings (each staircase is entered from its open end)
	rail(-8, -20, -8, -4, B)
	rail(-2, -20, -2, -4, B)
	rail(-8, -20, -2, -20, B)
	rail(2, -20, 2, -4, F2)
	rail(8, -20, 8, -4, F2)
	rail(2, -20, 8, -20, F2)
	rail(-9.5, -24, 9.5, -24, F2) -- foyer balcony
	rail(44, 16, 44, 32, B)
	rail(44, 16, 49.5, 16, B)
	rail(50, 18, 50, 34, F2)
	rail(50.5, 34, 55.5, 34, F2)
	-- Handrails up the open sides of the flights
	map:Railing(Vector3.new(2, B, -20), Vector3.new(2, F2, -4))
	map:Railing(Vector3.new(8, B, -20), Vector3.new(8, F2, -4))
	map:Railing(Vector3.new(-8, BF, -20), Vector3.new(-8, B, -4))
	map:Railing(Vector3.new(-2, BF, -20), Vector3.new(-2, B, -4))
	map:Railing(Vector3.new(44, BF, 16), Vector3.new(44, B, 32))
end

-- Gable roof over x1..x2 × z1..z2 (wall lines), ridge along x; the slopes meet the walls at
-- `base` and overhang 2 studs. `gables` are the x positions of the triangular end walls.
local function gableRoof(map: MapBuilder.Builder, x1: number, x2: number, z1: number, z2: number, base: number, gables: { number })
	local overhang = 2
	local halfDepth = (z2 - z1) / 2
	local midZ = (z1 + z2) / 2
	local rise = halfDepth * math.tan(PITCH)
	local ridge = base + rise
	local drop = overhang * math.tan(PITCH)
	for _, side in { -1, 1 } do
		local low = Vector3.new((x1 + x2) / 2, base - drop, midZ + side * (halfDepth + overhang))
		local high = Vector3.new((x1 + x2) / 2, ridge, midZ)
		local frame = CFrame.lookAt((low + high) / 2, high)
		map:Part("Roof", Vector3.new(x2 - x1, 1, (high - low).Magnitude), frame * CFrame.new(0, 0.5, 0), ROOF, Enum.Material.RoofShingles)
	end
	map:Part("RidgeCap", Vector3.new(x2 - x1, 0.6, 1.4), CFrame.new((x1 + x2) / 2, ridge + 0.9, midZ), ROOF, Enum.Material.RoofShingles)
	for _, x in gables do
		local size = Vector3.new(1, rise, halfDepth)
		wedge(map, "Gable", size, CFrame.new(x, base + rise / 2, z1 + halfDepth / 2), SIDING, Enum.Material.WoodPlanks)
		wedge(map, "Gable", size, CFrame.new(x, base + rise / 2, z2 - halfDepth / 2) * CFrame.Angles(0, math.pi, 0), SIDING, Enum.Material.WoodPlanks)
	end
end

local function buildOutside(map: MapBuilder.Builder)
	-- Roofs: the house, and the garage's lower one against the house's east wall
	gableRoof(map, -58, 58, -40, 40, ROOF_BASE, { -56, 56 })
	gableRoof(map, 56.5, 86.5, -40, -4, F2, { 84 })
	-- Porch roof over the front door
	map:Box("PorchRoof", Vector3.new(-9, 10.4, -47), Vector3.new(9, 10.9, -40.5), ROOF, Enum.Material.RoofShingles)
	for _, x in { -8, 8 } do
		map:Box("PorchColumn", Vector3.new(x - 0.4, 0.4, -46.5), Vector3.new(x + 0.4, 10.4, -45.7), WHITE, Enum.Material.Wood)
	end

	-- Ground: lawn (not under the house, so it can't plug the stairwells), sidewalk, street,
	-- back alley, drives
	local footprints = { { -56.5, -40.5, 56.5, 40.5 }, { 56.5, -40.5, 84.5, -3.5 }, { 35.5, 40.5, 45.5, 57 } }
	map:FloorWithHoles("Lawn", -140, -86, 140, 96, footprints, 0.2, 0.4, GRASS, Enum.Material.Grass)
	map:Floor("Sidewalk", -140, -92, 140, -86, 0.3, 0.5, CONCRETE, Enum.Material.Concrete)
	map:Floor("Street", -140, -124, 140, -92, 0.15, 0.4, ASPHALT, Enum.Material.Asphalt)
	map:Floor("Alley", -140, 96, 140, 114, 0.15, 0.4, ASPHALT, Enum.Material.Asphalt)
	map:Floor("Driveway", 58, -86, 82, -40.5, 0.3, 0.2, CONCRETE, Enum.Material.Concrete)
	map:Floor("FrontWalk", -3, -86, 3, -47, 0.3, 0.2, CONCRETE, Enum.Material.Concrete)
	map:Floor("Porch", -12, -47, 12, -40.5, B, 0.3, CONCRETE, Enum.Material.Concrete)
	map:Floor("SideDrive", 102, -86, 114, 96, 0.28, 0.2, Color3.fromRGB(140, 132, 120), Enum.Material.Pebble)
	map:Floor("Patio", -16, 40.5, 6, 52, 0.3, 0.2, Color3.fromRGB(170, 160, 150), Enum.Material.Slate)

	-- Walkout stairs from the back yard down to the basement door
	map:Floor("WalkoutLanding", 36, 40.5, 45, 42, BF, 1, CONCRETE, Enum.Material.Concrete)
	map:Stairs(37, 42, 44, 57, BF, 0.2, "+Z", CONCRETE, Enum.Material.Concrete)
	for _, x in { 36, 45 } do
		map:Wall("RetainingWall", x, 40.5, x, 57, BF, 3.2 - BF, nil, CONCRETE, Enum.Material.Concrete)
	end

	-- Fences around the back yard, with gaps to get through (wood: shoot / knife through it)
	local function fence(x1: number, z1: number, x2: number, z2: number, gaps: { { number } })
		local start = if z1 == z2 then x1 else z1
		local openings = {}
		for _, gap in gaps do
			table.insert(openings, { from = gap[1] - start, to = gap[2] - start, top = 5 })
		end
		for _, piece in map:Wall("Fence", x1, z1, x2, z2, 0.2, 5, openings, FENCE, Enum.Material.WoodPlanks, 0.5) do
			piece:SetAttribute("Breakable", "Soft")
		end
	end
	fence(-110, 90, 96, 90, { { -64, -56 }, { -4, 4 }, { 60, 68 } })
	fence(-110, -60, -110, 90, { { -20, -12 }, { 40, 48 } })
	fence(96, -30, 96, 90, { { 0, 8 }, { 50, 58 } })

	-- Low brick garden walls: cover on the way in
	for _, w in { { -50, -62, -24, -62 }, { 18, -62, 44, -62 }, { -86, 10, -86, 34 }, { 66, 62, 66, 78 }, { -40, 66, -20, 66 } } do
		map:Wall("GardenWall", w[1], w[2], w[3], w[4], 0.2, 3, nil, BRICK, Enum.Material.Brick)
	end
	for _, position in { Vector3.new(-72, 0, -40), Vector3.new(36, 0, -74), Vector3.new(84, 0, 30), Vector3.new(-20, 0, 80), Vector3.new(124, 0, -50), Vector3.new(88, 0, 70) } do
		map:Box("Crate", position + Vector3.new(-2, 0.2, -2), position + Vector3.new(2, 4.2, 2), Color3.fromRGB(150, 115, 70), Enum.Material.WoodPlanks)
	end

	-- Shed in the back yard (door faces east)
	map:Floor("ShedFloor", -84, 56, -70, 70, 0.4, 0.2, WOOD, Enum.Material.WoodPlanks)
	map:Wall("Shed", -84, 56, -70, 56, 0.2, 9, nil, DARK_WOOD, Enum.Material.WoodPlanks)
	map:Wall("Shed", -84, 70, -70, 70, 0.2, 9, nil, DARK_WOOD, Enum.Material.WoodPlanks)
	map:Wall("Shed", -84, 56, -84, 70, 0.2, 9, nil, DARK_WOOD, Enum.Material.WoodPlanks)
	map:Wall("Shed", -70, 56, -70, 70, 0.2, 9, { { from = 4.5, to = 9.5, top = 8 } }, DARK_WOOD, Enum.Material.WoodPlanks)
	map:Floor("ShedRoof", -85, 55, -69, 71, 9.7, 0.5, ROOF, Enum.Material.Slate)

	-- Invisible walls at the edge of the world
	for _, edge in { { -140, -124, 140, -124 }, { -140, 114, 140, 114 }, { -140, -124, -140, 114 }, { 140, -124, 140, 114 } } do
		for _, piece in map:Wall("Boundary", edge[1], edge[2], edge[3], edge[4], -20, 120, nil, Color3.new(), nil, 2) do
			piece.Transparency = 1
			piece.CanQuery = false
		end
	end
end

function House.Build(): Model
	local map = MapBuilder.new("House")
	buildFloors(map)
	buildBasement(map)
	buildGround(map)
	buildUpstairs(map)
	buildStairs(map)
	buildOutside(map)

	-- Sites: four pairs, A and B each; the defenders pick one pair per round
	local function site(name: string, x1: number, z1: number, x2: number, z2: number, level: number, pair: string, room: string)
		map:Site(name, Vector3.new(x1 + 0.5, level, z1 + 0.5), Vector3.new(x2 - 0.5, level + 6, z2 - 0.5), pair, room)
	end
	site("A", -56, -40, -20, -6, BF, "Basement", "Gym")
	site("B", -56, -6, -20, 22, BF, "Basement", "Workshop")
	site("A", -56, -10, -20, 14, B, "Kitchen", "Dining")
	site("B", -56, 14, -20, 40, B, "Kitchen", "Kitchen")
	site("A", 20, -40, 56, -14, B, "Office", "Office")
	site("B", 20, -14, 56, 14, B, "Office", "Den")
	site("A", -56, -40, -22, -4, F2, "Bedrooms", "Kids room")
	site("B", -56, -4, -22, 28, F2, "Bedrooms", "Master")

	-- Defenders spawn in the pair they picked; attackers on the street, in the alley or on the side drive
	map:SpawnPad("Defend", Vector3.new(-38, BF + 0.1, 10), Vector3.new(1, 0, 0), "Basement")
	map:SpawnPad("Defend", Vector3.new(-30, B + 0.1, 27), Vector3.new(-1, 0, 0), "Kitchen")
	map:SpawnPad("Defend", Vector3.new(36, B + 0.1, 2), Vector3.new(-1, 0, 0), "Office")
	map:SpawnPad("Defend", Vector3.new(-40, F2 + 0.1, 14), Vector3.new(1, 0, 0), "Bedrooms")
	map:SpawnPad("Attack", Vector3.new(-30, 0.25, -104), Vector3.new(0, 0, 1))
	map:SpawnPad("Attack", Vector3.new(10, 0.25, 105), Vector3.new(0, 0, -1))
	map:SpawnPad("Attack", Vector3.new(108, 0.4, 10), Vector3.new(-1, 0, 0))
	map:FreeRoamSpawn(Vector3.new(0, 0.5, -64))

	return map.model
end

return House
