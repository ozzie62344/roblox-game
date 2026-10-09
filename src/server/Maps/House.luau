-- HOUSE — a two-story suburban house with an attached garage.
--
--   Ground floor (z = north):            Upstairs:
--   ┌──────────┬────┬──────────┐          ┌──────────┬────┬──────────┐
--   │ Kitchen  │    │ Stairs   │          │ MASTER   │    │ Landing  │
--   │          │Hall│ / laundry│          │ BEDROOM  │Hall│ (stairs) │
--   ├──arch────┤    ├──door────┤          │ SITE A   │    ├──────────┤
--   │ Living   │    │ GARAGE   │          ├──door────┤    │ Bathroom │
--   │ room     │    │ SITE B   │          │ Kids room│    │          │
--   └──window──┴door┴garage door┘          └──────────┴────┴──────────┘
--               (south: front yard, street, attacker spawn)
--
-- Defenders spawn in the stairs / laundry room. Attackers spawn on the street (south) or the
-- east side yard. Windows are open: you can peek and shoot through them.
--
-- Units: studs. The house spans x -32..32, z -24..24. Doors are 5 wide x 8 tall.

local MapBuilder = require(script.Parent.MapBuilder)

local House = {}

-- Heights
local B = 0.4 -- ground floor surface
local F2 = B + 13 -- upstairs floor surface
local WALL = 12 -- ground floor wall height
local WALL2 = 11 -- upstairs wall height
local ROOF = F2 + WALL2 + 1

-- Look
local BRICK = Color3.fromRGB(150, 88, 70)
local PLASTER = Color3.fromRGB(226, 216, 196)
local WOOD = Color3.fromRGB(150, 110, 75)
local DARK_WOOD = Color3.fromRGB(95, 66, 45)
local CONCRETE = Color3.fromRGB(150, 150, 150)
local GRASS = Color3.fromRGB(90, 135, 70)
local ASPHALT = Color3.fromRGB(55, 55, 60)
local FABRIC = Color3.fromRGB(85, 95, 120)
local METAL = Color3.fromRGB(120, 125, 130)
local WHITE = Color3.fromRGB(235, 235, 235)

local function door(from: number): MapBuilder.Opening
	return { from = from, to = from + 5, bottom = 0, top = 8 }
end

local function window(from: number, to: number): MapBuilder.Opening
	return { from = from, to = to, bottom = 3, top = 7 }
end

local function prop(map: MapBuilder.Builder, name: string, min: Vector3, max: Vector3, color: Color3, material: Enum.Material?)
	return map:Box(name, min, max, color, material or Enum.Material.SmoothPlastic)
end

local function buildGroundFloor(map: MapBuilder.Builder)
	-- Floors: wood in the house, concrete in the garage
	map:Floor("Floor", -32, -24, 4, 24, B, 0.4, WOOD, Enum.Material.WoodPlanks)
	map:Floor("Floor", 4, 0, 32, 24, B, 0.4, WOOD, Enum.Material.WoodPlanks)
	map:Floor("GarageFloor", 4, -24, 32, 0, B, 0.4, CONCRETE, Enum.Material.Concrete)

	-- Exterior walls (openings are measured from the west / south end of each wall)
	map:Wall("ExteriorWall", -32, -24, 32, -24, B, WALL, {
		window(8, 16), -- living room window
		{ from = 29.5, to = 34.5, bottom = 0, top = 8 }, -- front door
		{ from = 40, to = 60, bottom = 0, top = 10 }, -- garage door (wide open)
	}, BRICK, Enum.Material.Brick)
	map:Wall("ExteriorWall", -32, 24, 32, 24, B, WALL, {
		window(8, 18), -- kitchen window
		{ from = 29.5, to = 34.5, bottom = 0, top = 8 }, -- back door
		window(40, 48), -- laundry window
	}, BRICK, Enum.Material.Brick)
	map:Wall("ExteriorWall", -32, -24, -32, 24, B, WALL, {
		window(10, 18), -- living room
		window(34, 42), -- kitchen
	}, BRICK, Enum.Material.Brick)
	map:Wall("ExteriorWall", 32, -24, 32, 24, B, WALL, {
		door(6), -- garage side door
	}, BRICK, Enum.Material.Brick)

	-- Hallway walls
	map:Wall("Wall", -4, -24, -4, 24, B, WALL, { door(12), door(34) }, PLASTER) -- living / kitchen doors
	map:Wall("Wall", 4, -24, 4, 24, B, WALL, { door(10), door(30) }, PLASTER) -- garage / stairs doors

	-- Room dividers
	map:Wall("Wall", -32, 2, -4, 2, B, WALL, { { from = 8, to = 18, bottom = 0, top = 9 } }, PLASTER) -- living ↔ kitchen arch
	map:Wall("Wall", 4, 0, 32, 0, B, WALL, { door(4) }, PLASTER) -- garage ↔ stairs room

	-- Living room: couch, coffee table, TV stand
	prop(map, "Couch", Vector3.new(-27, B, -21), Vector3.new(-15, B + 2, -17), FABRIC, Enum.Material.Fabric)
	prop(map, "CouchBack", Vector3.new(-27, B, -22), Vector3.new(-15, B + 3.5, -21), FABRIC, Enum.Material.Fabric)
	prop(map, "CoffeeTable", Vector3.new(-24, B, -13), Vector3.new(-18, B + 1.5, -10), DARK_WOOD, Enum.Material.Wood)
	prop(map, "TVStand", Vector3.new(-31.5, B, -22), Vector3.new(-29.5, B + 3, -15), DARK_WOOD, Enum.Material.Wood)
	map:Light(Vector3.new(-18, B + WALL - 0.2, -11))

	-- Kitchen: island (waist-high cover), counters, fridge
	prop(map, "Island", Vector3.new(-24, B, 9), Vector3.new(-14, B + 3.5, 14), WHITE, Enum.Material.Marble)
	prop(map, "Counter", Vector3.new(-31.5, B, 4), Vector3.new(-28.5, B + 3.5, 18), WHITE, Enum.Material.Marble)
	prop(map, "Fridge", Vector3.new(-31.5, B, 19), Vector3.new(-27.5, B + 7, 23.5), METAL, Enum.Material.Metal)
	map:Light(Vector3.new(-18, B + WALL - 0.2, 13))

	-- Garage (Site B): car in the middle, shelves, workbench, boxes
	prop(map, "CarBody", Vector3.new(15, B + 0.8, -21), Vector3.new(21, B + 4, -8), Color3.fromRGB(160, 40, 40), Enum.Material.Metal)
	prop(map, "CarCabin", Vector3.new(15.5, B + 4, -17), Vector3.new(20.5, B + 6.5, -11), Color3.fromRGB(60, 70, 80), Enum.Material.Glass)
	prop(map, "Shelves", Vector3.new(29, B, -11), Vector3.new(31.5, B + 7, -4), METAL, Enum.Material.Metal)
	prop(map, "Workbench", Vector3.new(20, B, -3), Vector3.new(31, B + 3.5, -0.5), DARK_WOOD, Enum.Material.Wood)
	prop(map, "Boxes", Vector3.new(6, B, -23), Vector3.new(10, B + 4, -19), Color3.fromRGB(170, 140, 100), Enum.Material.Cardboard)
	prop(map, "Boxes", Vector3.new(6, B + 4, -22), Vector3.new(9, B + 6.5, -19.5), Color3.fromRGB(170, 140, 100), Enum.Material.Cardboard)
	map:Light(Vector3.new(18, B + WALL - 0.2, -12), 30)

	-- Stairs room: stairs up along the east wall (south → north), laundry
	map:StairsZ(25, 31.5, 4, 20, B, F2, WOOD)
	prop(map, "Washer", Vector3.new(6, B, 20.5), Vector3.new(12, B + 3.5, 23.5), WHITE, Enum.Material.Metal)
	prop(map, "Boxes", Vector3.new(14, B, 20), Vector3.new(18, B + 3, 23.5), Color3.fromRGB(170, 140, 100), Enum.Material.Cardboard)
	map:Light(Vector3.new(14, B + WALL - 0.2, 12))

	-- Hallway lights
	map:Light(Vector3.new(0, B + WALL - 0.2, -12))
	map:Light(Vector3.new(0, B + WALL - 0.2, 12))
end

local function buildUpstairs(map: MapBuilder.Builder)
	-- Floor with a hole over the stairs
	map:FloorWithHole("Floor2", -32, -24, 32, 24, { 24.5, 4, 31.5, 20 }, F2, 1, WOOD, Enum.Material.WoodPlanks)
	-- Railing around the stairwell
	map:Wall("Railing", 24.5, 4, 24.5, 20, F2, 3.5, nil, DARK_WOOD, Enum.Material.Wood, 0.5)
	map:Wall("Railing", 24.5, 4, 31.5, 4, F2, 3.5, nil, DARK_WOOD, Enum.Material.Wood, 0.5)

	-- Exterior walls
	map:Wall("ExteriorWall", -32, -24, 32, -24, F2, WALL2, {
		window(8, 16), -- kids room
		window(30, 34), -- end of the hallway
		window(46, 52), -- bathroom
	}, BRICK, Enum.Material.Brick)
	map:Wall("ExteriorWall", -32, 24, 32, 24, F2, WALL2, {
		window(6, 16), -- master bedroom
		window(44, 52), -- landing
	}, BRICK, Enum.Material.Brick)
	map:Wall("ExteriorWall", -32, -24, -32, 24, F2, WALL2, {
		window(10, 18), -- kids room
		window(32, 40), -- master bedroom
	}, BRICK, Enum.Material.Brick)
	map:Wall("ExteriorWall", 32, -24, 32, 24, F2, WALL2, {
		window(22, 28), -- landing
	}, BRICK, Enum.Material.Brick)

	-- Hallway walls
	map:Wall("Wall", -4, -24, -4, 24, F2, WALL2, { door(12), door(32) }, PLASTER) -- kids / master doors
	map:Wall("Wall", 4, -24, 4, 24, F2, WALL2, {
		door(8), -- bathroom
		{ from = 26, to = 36, bottom = 0, top = 9 }, -- wide opening to the landing
	}, PLASTER)

	-- Room dividers
	map:Wall("Wall", -32, 0, -4, 0, F2, WALL2, { door(18) }, PLASTER) -- kids ↔ master (connecting door)
	map:Wall("Wall", 4, -4, 32, -4, F2, WALL2, nil, PLASTER) -- bathroom ↔ landing

	-- Master bedroom (Site A): big bed, dresser, wardrobe
	prop(map, "Bed", Vector3.new(-26, F2, 13), Vector3.new(-16, F2 + 2.5, 23.5), Color3.fromRGB(200, 200, 210), Enum.Material.Fabric)
	prop(map, "Headboard", Vector3.new(-26, F2, 23), Vector3.new(-16, F2 + 4.5, 23.5), DARK_WOOD, Enum.Material.Wood)
	prop(map, "Dresser", Vector3.new(-31.5, F2, 2), Vector3.new(-28.5, F2 + 4, 9), DARK_WOOD, Enum.Material.Wood)
	prop(map, "Wardrobe", Vector3.new(-12, F2, 21), Vector3.new(-6, F2 + 7, 23.5), DARK_WOOD, Enum.Material.Wood)
	map:Light(Vector3.new(-18, F2 + WALL2 - 0.2, 12))

	-- Kids room: bed, desk, toy chest
	prop(map, "Bed", Vector3.new(-31.5, F2, -22), Vector3.new(-25.5, F2 + 2.5, -12), Color3.fromRGB(110, 160, 220), Enum.Material.Fabric)
	prop(map, "Desk", Vector3.new(-12, F2, -23.5), Vector3.new(-6, F2 + 3, -20), WOOD, Enum.Material.Wood)
	prop(map, "ToyChest", Vector3.new(-20, F2, -5), Vector3.new(-15, F2 + 2.5, -1.5), Color3.fromRGB(220, 170, 60), Enum.Material.Wood)
	map:Light(Vector3.new(-18, F2 + WALL2 - 0.2, -12))

	-- Bathroom: tub, sink
	prop(map, "Tub", Vector3.new(24, F2, -23.5), Vector3.new(31.5, F2 + 2.5, -19), WHITE, Enum.Material.Marble)
	prop(map, "Sink", Vector3.new(6, F2, -23.5), Vector3.new(10, F2 + 3.5, -21), WHITE, Enum.Material.Marble)
	map:Light(Vector3.new(18, F2 + WALL2 - 0.2, -14))

	-- Landing: bookshelf
	prop(map, "Bookshelf", Vector3.new(4.5, F2, 14), Vector3.new(6.5, F2 + 7, 22), DARK_WOOD, Enum.Material.Wood)
	map:Light(Vector3.new(14, F2 + WALL2 - 0.2, 10))

	-- Hallway lights
	map:Light(Vector3.new(0, F2 + WALL2 - 0.2, -12))
	map:Light(Vector3.new(0, F2 + WALL2 - 0.2, 12))

	-- Roof
	map:Floor("Roof", -33, -25, 33, 25, ROOF, 1, Color3.fromRGB(70, 60, 60), Enum.Material.Slate)
end

local function tree(map: MapBuilder.Builder, x: number, z: number)
	local trunk = map:Part("TreeTrunk", Vector3.new(10, 2, 2), CFrame.new(x, 5.2, z) * CFrame.Angles(0, 0, math.rad(90)), DARK_WOOD, Enum.Material.Wood)
	trunk.Shape = Enum.PartType.Cylinder
	local leaves = map:Part("TreeLeaves", Vector3.new(11, 11, 11), CFrame.new(x, 12, z), Color3.fromRGB(70, 120, 55), Enum.Material.Grass)
	leaves.Shape = Enum.PartType.Ball
end

local function car(map: MapBuilder.Builder, center: Vector3, alongX: boolean, color: Color3)
	local half = if alongX then Vector3.new(6, 0, 3) else Vector3.new(3, 0, 6)
	local cabinHalf = if alongX then Vector3.new(3, 0, 2.5) else Vector3.new(2.5, 0, 3)
	prop(map, "CarBody", center - half + Vector3.new(0, 0.8, 0), center + half + Vector3.new(0, 4, 0), color, Enum.Material.Metal)
	prop(map, "CarCabin", center - cabinHalf + Vector3.new(0, 4, 0), center + cabinHalf + Vector3.new(0, 6.5, 0), Color3.fromRGB(60, 70, 80), Enum.Material.Glass)
end

local function buildOutside(map: MapBuilder.Builder)
	-- Ground: lawn, driveway, sidewalk, street
	map:Floor("Lawn", -120, -120, 120, 120, 0.2, 0.4, GRASS, Enum.Material.Grass)
	map:Floor("Driveway", 8, -74, 28, -24, 0.3, 0.2, CONCRETE, Enum.Material.Concrete)
	map:Floor("Path", -3, -74, 3, -24, 0.3, 0.2, CONCRETE, Enum.Material.Concrete)
	map:Floor("Sidewalk", -120, -80, 120, -74, 0.3, 0.2, CONCRETE, Enum.Material.Concrete)
	map:Floor("Street", -120, -100, 120, -80, 0.25, 0.2, ASPHALT, Enum.Material.Asphalt)

	-- Cover on the approach
	car(map, Vector3.new(15, 0.3, -42), false, Color3.fromRGB(40, 70, 150)) -- on the driveway
	car(map, Vector3.new(-34, 0.25, -88), true, Color3.fromRGB(200, 200, 200)) -- parked on the street
	car(map, Vector3.new(50, 0.25, -92), true, Color3.fromRGB(30, 30, 30))
	map:Wall("GardenWall", -30, -36, -8, -36, 0.2, 3, nil, BRICK, Enum.Material.Brick) -- low wall, crouch behind it
	map:Wall("GardenWall", 34, -36, 60, -36, 0.2, 3, nil, BRICK, Enum.Material.Brick)
	for _, position in { Vector3.new(-48, 0, -20), Vector3.new(44, 0, -54), Vector3.new(54, 0, 6), Vector3.new(-12, 0, 40) } do
		prop(map, "Crate", position + Vector3.new(-2, 0.2, -2), position + Vector3.new(2, 4.2, 2), Color3.fromRGB(150, 115, 70), Enum.Material.WoodPlanks)
	end

	-- Fence around the back yard (gaps to get through)
	local FENCE = Color3.fromRGB(200, 190, 170)
	map:Wall("Fence", -70, 60, 70, 60, 0.2, 5, { { from = 60, to = 68, bottom = 0, top = 5 } }, FENCE, Enum.Material.WoodPlanks, 0.5)
	map:Wall("Fence", -70, -60, -70, 60, 0.2, 5, { { from = 50, to = 58, bottom = 0, top = 5 } }, FENCE, Enum.Material.WoodPlanks, 0.5)

	-- Shed in the back yard (door faces east)
	map:Floor("ShedFloor", -66, 30, -52, 44, 0.4, 0.2, WOOD, Enum.Material.WoodPlanks)
	map:Wall("Shed", -66, 30, -52, 30, 0.2, 9, nil, DARK_WOOD, Enum.Material.WoodPlanks)
	map:Wall("Shed", -66, 44, -52, 44, 0.2, 9, nil, DARK_WOOD, Enum.Material.WoodPlanks)
	map:Wall("Shed", -66, 30, -66, 44, 0.2, 9, nil, DARK_WOOD, Enum.Material.WoodPlanks)
	map:Wall("Shed", -52, 30, -52, 44, 0.2, 9, { door(4.5) }, DARK_WOOD, Enum.Material.WoodPlanks)
	map:Floor("ShedRoof", -67, 29, -51, 45, 9.4, 0.5, Color3.fromRGB(70, 60, 60), Enum.Material.Slate)

	tree(map, -45, -40)
	tree(map, 45, 30)
	tree(map, -25, 45)
	tree(map, 75, -40)
end

function House.Build(): Model
	local map = MapBuilder.new("House")
	buildGroundFloor(map)
	buildUpstairs(map)
	buildOutside(map)

	-- Sites: A = master bedroom (upstairs), B = garage (ground floor)
	map:Site("A", Vector3.new(-31.5, F2, 0.5), Vector3.new(-4.5, F2 + 6, 23.5))
	map:Site("B", Vector3.new(4.5, B, -23.5), Vector3.new(31.5, B + 6, -0.5))

	-- Spawns: defenders in the stairs / laundry room, attackers on the street or the east side
	map:SpawnPad("Defend", Vector3.new(14, B + 0.1, 12), Vector3.new(-1, 0, 0))
	map:SpawnPad("Attack", Vector3.new(0, 0.35, -108), Vector3.new(0, 0, 1))
	map:SpawnPad("Attack", Vector3.new(95, 0.35, 0), Vector3.new(-1, 0, 0))
	map:FreeRoamSpawn(Vector3.new(-12, 0.5, -60))

	return map.model
end

return House
