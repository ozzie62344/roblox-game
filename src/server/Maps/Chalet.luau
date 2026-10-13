-- CHALET — a snowed-in ski chalet in the spirit of Rainbow Six Siege's Chalet: a log lodge on a
-- stone foundation, a wine cellar and a snowmobile garage dug in under it, a great room open two
-- floors up to the roof round a stone fireplace, and bedrooms off a gallery that looks down into
-- it. Snowy yard all round, inside a log fence.
-- Four site pairs; the defenders pick one each round (RoundService / SitePicker):
--   Cellar:    Wine cellar + Snowmobile garage      Kitchen:   Dining room + Kitchen
--   Bar:       Gaming room + Bar                    Upstairs:  Office + Master bedroom
--
--   Ground floor (north = +z; the road is south, the frozen lake north):
--   ┌──────────┬────────────────────┬──────────┐
--   │ KITCHEN  │ great room  ▀▀▀▀   │ BAR      │   ▀▀▀▀ the fireplace (the deck is outside it)
--   │          │░░           ▓▓     │          │   ░░ gallery overhead (west and south sides)
--   ├──────────┤░░ (open to   ▓▓    ├──────────┤
--   │ DINING   │░░  the roof)       │ GAMING   │
--   │          ├────────────────────┤ ROOM     │
--   ├──────────┤ hall  ▒▒▒▒▒        ├──────────┤
--   │▒▓ library├────────────────────┤ trophy   │
--   │▒▓        │ foyer              │ room     │
--   └──────────┴────────────────────┴──────────┘
--   x: -56    -20                   20         56
--   ▒▒ down to the cellar hall, ▓▓ up to the gallery, ▒▓ back stairs (boiler room → library →
--   gear room). Upstairs: OFFICE + MASTER BEDROOM over the dining room and kitchen, the gallery
--   round the great room, bunk room (its door opens onto the balcony over the front door), reading
--   room, sauna, bathroom, gear room, twin room, TV room, guest room (it looks down into the great
--   room). Basement: WINE CELLAR under the foyer, the SNOWMOBILE GARAGE beside it (a ramp up to
--   the east yard), cellar hall, wine stock, workshop, boiler room, laundry, ski storage.
--
-- Attackers spawn on the road (south), out on the frozen lake (north) or in the woods (west).
-- Log walls and the pine panelling inside are soft (shoot through, breach, reinforce); fieldstone
-- (the front, the fireplace wall, round the cellar) and concrete aren't. Outside doors and windows
-- start barricaded. The wooden floors are soft too, with a hatch over every lower site.
-- Units: studs. The chalet spans x -56..56, z -40..40; the deck z 40..56, the garage ramp x 56..84.

local MapBuilder = require(script.Parent.MapBuilder)

local Chalet = {}

-- Floor levels (the top of each floor)
local BF = -11.6 -- basement
local B = 0.4 -- ground floor
local F2 = 13.4 -- upstairs
local CEILING = 24.4 -- upstairs ceiling (the great room goes all the way up to it)
local BASEMENT_WALL = 11 -- basement floor up to the ground floor slab
local GROUND_WALL = 12
local UPSTAIRS_WALL = 11
local ROOF_BASE = CEILING + 1
local PITCH = math.rad(30) -- steeper than the House's: it's built for snow
local GROUND = 0.2 -- top of the snow outside

-- Look
local LOG = Color3.fromRGB(122, 80, 50)
local DARK_LOG = Color3.fromRGB(80, 54, 36)
local PINE_PANEL = Color3.fromRGB(184, 136, 90)
local PLASTER = Color3.fromRGB(226, 218, 200)
local FIELDSTONE = Color3.fromRGB(140, 134, 124)
local SLATE = Color3.fromRGB(104, 104, 106)
local SOOT = Color3.fromRGB(40, 36, 34)
local CONCRETE = Color3.fromRGB(150, 150, 150)
local WOOD = Color3.fromRGB(150, 110, 75)
local CEDAR = Color3.fromRGB(196, 146, 98)
local DECK = Color3.fromRGB(138, 112, 86)
local WHITE = Color3.fromRGB(240, 238, 232)
local SNOW = Color3.fromRGB(228, 232, 236) -- off-white: pure white glares in the sun
local ICE = Color3.fromRGB(168, 196, 214)
local ASPHALT = Color3.fromRGB(58, 60, 66)
local GRAVEL = Color3.fromRGB(124, 118, 110)
local PINE = Color3.fromRGB(44, 78, 56)
local BARK = Color3.fromRGB(86, 62, 44)
local LEATHER = Color3.fromRGB(110, 62, 40)
local GRANITE = Color3.fromRGB(150, 142, 134)
local DARK_METAL = Color3.fromRGB(62, 66, 72)
local BLACK = Color3.fromRGB(28, 29, 32)
local FIRE = Color3.fromRGB(255, 136, 48)

-- Walls: soft ones can be shot through, breached and reinforced; stone and concrete can't
local PANELLING: MapBuilder.Style = { color = PINE_PANEL, material = Enum.Material.WoodPlanks, soft = true }
local DRYWALL: MapBuilder.Style = { color = PLASTER, material = Enum.Material.Plaster, soft = true }
local OUTSIDE_LOG: MapBuilder.Style = { color = LOG, material = Enum.Material.Wood, soft = true, exterior = true }
local OUTSIDE_STONE: MapBuilder.Style = { color = FIELDSTONE, material = Enum.Material.Cobblestone, exterior = true }
local OUTSIDE_CONCRETE: MapBuilder.Style = { color = CONCRETE, material = Enum.Material.Concrete, exterior = true }
local STONE_WALL: MapBuilder.Style = { color = FIELDSTONE, material = Enum.Material.Cobblestone }
local CONCRETE_WALL: MapBuilder.Style = { color = CONCRETE, material = Enum.Material.Concrete }

-- Floor finishes over the wood / concrete
local TILE = { Color3.fromRGB(214, 208, 196), Enum.Material.CeramicTiles }
local SLATE_FLOOR = { Color3.fromRGB(118, 116, 112), Enum.Material.Slate }
local RED_CARPET = { Color3.fromRGB(128, 48, 42), Enum.Material.Carpet }
local GREEN_CARPET = { Color3.fromRGB(62, 92, 72), Enum.Material.Carpet }
local BEIGE_CARPET = { Color3.fromRGB(170, 152, 126), Enum.Material.Carpet }
local GREY_CARPET = { Color3.fromRGB(100, 102, 108), Enum.Material.Carpet }
local CEDAR_FLOOR = { CEDAR, Enum.Material.WoodPlanks }
local BRICK_FLOOR = { Color3.fromRGB(140, 85, 65), Enum.Material.Brick }
local RUBBER = { Color3.fromRGB(45, 45, 48), Enum.Material.Rubber }

-- Holes in the floors: { x1, z1, x2, z2 }
local CELLAR_STAIRS = { -4, -19.5, 12, -13.5 } -- hall down to the cellar hall (climbs -x)
local BACK_LOWER = { -55.5, -34, -50.5, -18 } -- back stairs, boiler room up to the library (climbs -z)
local BACK_UPPER = { -49.5, -36, -44.5, -20 } -- back stairs, library up to the gear room (climbs +z)
local GREAT_VOID = { -14, 8, 19.5, 40.5 } -- the great room is open up to the roof (the main stairs rise in it)
-- Hatches (4 × 4 trapdoors) over every site below the top floor: x, z, the floor they're in
local HATCH = 4
local HATCHES = {
	{ -12, -28, B }, -- foyer → wine cellar
	{ 32, -28, B }, -- trophy room → garage
	{ 46, -6, B }, -- gaming room → garage
	{ -44, 30, F2 }, -- master bedroom → kitchen
	{ -28, -4, F2 }, -- office → dining room
	{ 44, 22, F2 }, -- guest room → bar (lands in front of the counter)
	{ 30, -2, F2 }, -- TV room → gaming room
}
local GROUND_HOLES = { CELLAR_STAIRS, BACK_LOWER }
local UPSTAIRS_HOLES = { GREAT_VOID, BACK_UPPER }
for _, hatch in HATCHES do
	local x, z, level = hatch[1], hatch[2], hatch[3]
	table.insert(if level == B then GROUND_HOLES else UPSTAIRS_HOLES, { x - HATCH / 2, z - HATCH / 2, x + HATCH / 2, z + HATCH / 2 })
end

-- name, x1, z1, x2, z2, floor, finish (nil = bare wood / concrete). Lights and floors come from here.
local ROOMS = {
	{ "BoilerRoom", -56, -40, -20, -14, BF },
	{ "Laundry", -56, -14, -20, 12, BF, TILE },
	{ "SkiStorage", -56, 12, -20, 40, BF, RUBBER },
	{ "WineCellar", -20, -40, 20, -20, BF, BRICK_FLOOR },
	{ "CellarHall", -20, -20, 20, 0, BF },
	{ "WineStock", -20, 0, 20, 40, BF },
	{ "Garage", 20, -40, 56, 0, BF },
	{ "Workshop", 20, 0, 56, 40, BF },

	{ "Library", -56, -40, -20, -14, B, GREEN_CARPET },
	{ "Dining", -56, -14, -20, 12, B },
	{ "Kitchen", -56, 12, -20, 40, B, TILE },
	{ "Foyer", -20, -40, 20, -20, B, SLATE_FLOOR },
	{ "Hall", -20, -20, 20, 0, B },
	{ "GreatRoom", -20, 0, 20, 40, B },
	{ "TrophyRoom", 20, -40, 56, -14, B, RED_CARPET },
	{ "GamingRoom", 20, -14, 56, 12, B, GREY_CARPET },
	{ "Bar", 20, 12, 56, 40, B, SLATE_FLOOR },

	{ "GearRoom", -56, -40, -36, -14, F2 },
	{ "Sauna", -36, -40, -20, -26, F2, CEDAR_FLOOR },
	{ "Bathroom", -36, -26, -20, -14, F2, TILE },
	{ "Office", -56, -14, -20, 10, F2, GREEN_CARPET },
	{ "Master", -56, 10, -20, 40, F2, BEIGE_CARPET },
	{ "BunkRoom", -20, -40, 6, -14, F2, RED_CARPET },
	{ "ReadingRoom", 6, -40, 20, -14, F2, GREEN_CARPET },
	{ "Landing", -20, -14, 20, 8, F2 },
	{ "Gallery", -20, 8, -14, 40, F2 },
	{ "TwinRoom", 20, -40, 56, -14, F2, BEIGE_CARPET },
	{ "TVRoom", 20, -14, 56, 10, F2, GREY_CARPET },
	{ "GuestRoom", 20, 10, 56, 40, F2, BEIGE_CARPET },
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
local function cosmetic(part: BasePart, parent: Instance)
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Parent = parent
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

-- Upright cylinder standing on `base` (barrels, stools, round tables, tree trunks)
local function drum(map: MapBuilder.Builder, name: string, x: number, z: number, base: number, height: number, diameter: number, color: Color3, material: Enum.Material): Part
	local part = map:Part(name, Vector3.new(height, diameter, diameter), CFrame.new(x, base + height / 2, z) * CFrame.Angles(0, 0, math.pi / 2), color, material)
	part.Shape = Enum.PartType.Cylinder -- (a cylinder's axis is its X: turned upright)
	return part
end

local function ceilingOf(name: string, level: number): number
	if name == "GreatRoom" then
		return CEILING -- two floors up
	end
	return if level == BF then B - 1 elseif level == B then F2 - 1 else CEILING
end

local function buildFloors(map: MapBuilder.Builder)
	local shell = map:Folder("Shell")
	-- The wooden floors are soft (shoot down through them, breach them); the cellar's concrete isn't
	map:Floor("BasementFloor", -56.5, -40.5, 56.5, 40.5, BF, 1, CONCRETE, Enum.Material.Concrete)
	for _, piece in map:FloorWithHoles("Floor", -56.5, -40.5, 56.5, 40.5, GROUND_HOLES, B, 1, WOOD, Enum.Material.WoodPlanks) do
		piece:SetAttribute("Breakable", "Soft")
	end
	for _, piece in map:FloorWithHoles("Floor2", -56.5, -40.5, 56.5, 40.5, UPSTAIRS_HOLES, F2, 1, WOOD, Enum.Material.WoodPlanks) do
		piece:SetAttribute("Breakable", "Soft")
		-- Painted ceiling under the wood (DestructionService cuts it along with the floor)
		cosmetic(map:Part("Ceiling", Vector3.new(piece.Size.X, 0.1, piece.Size.Z), piece.CFrame * CFrame.new(0, -0.55, 0), WHITE, Enum.Material.Plaster), shell)
	end
	for _, hatch in HATCHES do
		map:Hatch(hatch[1], hatch[2], hatch[3], HATCH)
	end
	-- Pine boards under the roof (the great room looks straight up at them)
	map:Floor("UpstairsCeiling", -56.5, -40.5, 56.5, 40.5, ROOF_BASE, 1, CEDAR, Enum.Material.WoodPlanks)

	for _, room in ROOMS do
		local name, x1, z1, x2, z2, level, finish = table.unpack(room)
		if finish then
			local holes = if level == B then GROUND_HOLES elseif level == F2 then UPSTAIRS_HOLES else {}
			for _, piece in map:FloorWithHoles(name .. "Floor", x1, z1, x2, z2, holes, level + 0.04, 0.04, finish[1], finish[2]) do
				cosmetic(piece, shell)
			end
		end
		-- Ceiling lights, spread along the room's long side (the great room's hang from the roof)
		local top = ceilingOf(name, level)
		local count = math.max(1, math.round((x2 - x1) * (z2 - z1) / 500))
		for i = 1, count do
			local t = (i - 0.5) / count
			local position = if x2 - x1 >= z2 - z1
				then Vector3.new(x1 + (x2 - x1) * t, top - 0.2, (z1 + z2) / 2)
				else Vector3.new((x1 + x2) / 2, top - 0.2, z1 + (z2 - z1) * t)
			map:Light(position, if name == "GreatRoom" then 40 else 26)
		end
	end
end

local function buildBasement(map: MapBuilder.Builder)
	local base, h = BF, BASEMENT_WALL
	-- Outside walls: poured concrete, dug into the hill. The garage opens onto its ramp (east): a
	-- big wooden door (shut) and a side door.
	wallX(map, OUTSIDE_CONCRETE, -40, -56.5, 56.5, base, h, nil, 1)
	wallX(map, OUTSIDE_CONCRETE, 40, -56.5, 56.5, base, h, nil, -1)
	wallZ(map, OUTSIDE_CONCRETE, -56, -40, 40, base, h, nil, 1)
	wallZ(map, OUTSIDE_CONCRETE, 56, -40, 40, base, h, { { from = -20, to = -10, top = 10 }, door(-8.5) }, -1)
	-- The garage door fills its hole: planks, so it can be shot through, breached and reinforced
	block(map, "GarageDoor", 55.7, base, -20, 56.3, base + 10, -10, DARK_LOG, Enum.Material.WoodPlanks):SetAttribute("Breakable", "Soft")

	-- West: boiler room (the back stairs start here), laundry, ski storage
	wallX(map, CONCRETE_WALL, -14, -56, -20, base, h, { door(-42) }) -- boiler room ↔ laundry
	wallX(map, DRYWALL, 12, -56, -20, base, h, { door(-42) }) -- laundry ↔ ski storage
	wallZ(map, STONE_WALL, -20, -40, -14, base, h, { door(-32) }) -- boiler room ↔ wine cellar
	wallZ(map, DRYWALL, -20, -14, 40, base, h, { door(-10), door(26) }) -- laundry ↔ cellar hall, ski storage ↔ wine stock

	-- Middle: WINE CELLAR (under the foyer), the cellar hall (stairs down from the hall), wine stock
	wallX(map, DRYWALL, -20, -20, 20, base, h, { door(-17), door(14) }) -- wine cellar ↔ cellar hall
	wallX(map, DRYWALL, 0, -20, 56, base, h, { door(-12), door(6), doubleDoor(34) }) -- cellar hall ↔ wine stock, garage ↔ workshop

	-- East: SNOWMOBILE GARAGE (site pair with the wine cellar: an arch between them), workshop
	wallZ(map, DRYWALL, 20, -40, 0, base, h, { arch(-34, -26), door(-12) })
	wallZ(map, CONCRETE_WALL, 20, 0, 40, base, h, { door(26) }) -- wine stock ↔ workshop
	-- Concrete columns holding up the ground floor over the garage (cover)
	for _, c in { { 32, -14 }, { 44, -23 } } do
		map:Box("Column", Vector3.new(c[1] - 1, base, c[2] - 1), Vector3.new(c[1] + 1, B - 1, c[2] + 1), CONCRETE, Enum.Material.Concrete)
	end
end

local function buildGround(map: MapBuilder.Builder)
	local base, h = B, GROUND_WALL
	-- Front: fieldstone round the front door, logs either side
	wallX(map, OUTSIDE_LOG, -40, -56.5, -20, base, h, { door(-54.5), window(-40, -34), window(-30, -24) }, 1) -- back stairs door, library
	wallX(map, OUTSIDE_STONE, -40, -20, 20, base, h, { window(-16, -10), doubleDoor(-4), window(10, 16) }, 1) -- foyer
	wallX(map, OUTSIDE_LOG, -40, 20, 56.5, base, h, { window(26, 32), window(42, 48) }, 1) -- trophy room
	-- Back: the great room's wall is fieldstone and goes up both floors, glass doors onto the deck
	-- and high windows level with the gallery
	wallX(map, OUTSIDE_LOG, 40, -56.5, -20, base, h, { window(-50, -44), window(-34, -28) }, -1) -- kitchen
	wallX(map, OUTSIDE_STONE, 40, -20, 20, base, CEILING - B, {
		doubleDoor(-16),
		doubleDoor(8),
		window(-17, -9, 15, 21),
		window(9, 17, 15, 21),
	}, -1)
	wallX(map, OUTSIDE_LOG, 40, 20, 56.5, base, h, { window(24, 30), door(36), window(46, 52) }, -1) -- bar
	-- Sides: logs. Kitchen door to the woods (west), gaming room door to the east yard
	wallZ(map, OUTSIDE_LOG, -56, -40, 40, base, h, { window(-10, -4), window(2, 8), window(18, 24), door(30) }, 1)
	wallZ(map, OUTSIDE_LOG, 56, -40, 40, base, h, { window(-34, -28), window(-24, -18), window(-10, -4), door(4), window(18, 24), window(30, 36) }, -1)

	-- West: library (the back stairs in its west end), DINING + KITCHEN (site pair)
	wallZ(map, PANELLING, -20, -40, 40, base, h, { door(-31), door(-10), doubleDoor(28) }) -- library ↔ foyer, dining ↔ hall, kitchen ↔ great room
	wallX(map, PANELLING, -14, -56, -20, base, h, { door(-49), door(-30) }) -- library ↔ dining
	wallX(map, PANELLING, 12, -56, -20, base, h, { arch(-46, -34) }) -- dining ↔ kitchen

	-- Middle: foyer, hall (cellar stairs along its south wall), the great room
	wallX(map, STONE_WALL, -20, -20, 20, base, h, { arch(-16, -6), door(14) }) -- foyer ↔ hall
	wallX(map, PANELLING, 0, -20, 20, base, h, { arch(-10, 10, 10) }) -- hall ↔ great room

	-- East: trophy room, GAMING ROOM + BAR (site pair)
	wallZ(map, PANELLING, 20, -40, 40, base, h, { door(-31), door(-10), door(1), doubleDoor(28) }) -- trophy ↔ foyer, gaming ↔ hall / great room, bar ↔ great room
	wallX(map, PANELLING, -14, 20, 56, base, h, { door(36) }) -- trophy ↔ gaming
	wallX(map, PANELLING, 12, 20, 56, base, h, { arch(32, 44) }) -- gaming ↔ bar
end

local function buildUpstairs(map: MapBuilder.Builder)
	local base, h = F2, UPSTAIRS_WALL
	wallX(map, OUTSIDE_LOG, -40, -56.5, 56.5, base, h, {
		window(-42, -38), -- gear room
		window(-30, -27), -- sauna
		window(-16, -11),
		door(-2.5), -- bunk room, out onto the balcony
		window(11, 16), -- reading room
		window(28, 34),
		window(44, 50), -- twin room
	}, 1)
	-- (the great room's tall wall fills the middle of the back)
	wallX(map, OUTSIDE_LOG, 40, -56.5, -20, base, h, { window(-50, -44), window(-34, -28) }, -1) -- master bedroom
	wallX(map, OUTSIDE_LOG, 40, 20, 56.5, base, h, { window(26, 32), window(42, 48) }, -1) -- guest room
	wallZ(map, OUTSIDE_LOG, -56, -40, 40, base, h, { window(-30, -25), window(-8, -2), window(18, 24), window(30, 36) }, 1)
	wallZ(map, OUTSIDE_LOG, 56, -40, 40, base, h, { window(-34, -28), window(-24, -18), window(-6, 0), window(18, 24), window(30, 36) }, -1)

	-- Across the front rooms: gear room ↔ office (right at the top of the back stairs), bunk room
	-- and reading room ↔ landing, twin room ↔ TV room
	wallX(map, PANELLING, -14, -56, 56, base, h, { door(-49), door(-10), door(12), door(40) })

	-- West: gear room, sauna, bathroom, OFFICE + MASTER BEDROOM (site pair)
	wallZ(map, PANELLING, -36, -40, -14, base, h, { door(-22) }) -- gear room ↔ bathroom
	wallX(map, PANELLING, -26, -36, -20, base, h, { door(-31) }) -- bathroom ↔ sauna
	wallX(map, PANELLING, 10, -56, -20, base, h, { door(-40) }) -- office ↔ master
	-- bunk room ↔ bathroom, office ↔ landing, master ↔ gallery (and a window down into the great room)
	wallZ(map, PANELLING, -20, -40, 40, base, h, { door(-24), door(-8), door(20), window(30, 36) })

	-- Middle: bunk room and reading room at the front, the landing and the gallery round the void
	wallZ(map, PANELLING, 6, -40, -14, base, h, { door(-30) })

	-- East: twin room, TV room, guest room (its window looks down into the great room)
	wallZ(map, PANELLING, 20, -40, 40, base, h, { door(-30), door(-8), window(28, 36) })
	wallX(map, PANELLING, 10, 20, 56, base, h, { door(40) }) -- TV room ↔ guest room
end

local function buildStairs(map: MapBuilder.Builder)
	-- Main stairs: up the great room's east wall to the gallery
	map:Stairs(13.5, 8, 19.5, 24, B, F2, "-Z", WOOD)
	-- Cellar stairs: along the hall's south wall, down to the cellar hall
	map:Stairs(-4, -19.5, 12, -13.5, BF, B, "-X", WOOD)
	-- Back stairs in the library's west end (boiler room → library → gear room), a stone wall
	-- between the two flights
	map:Stairs(-55.5, -34, -50.5, -18, BF, B, "-Z", WOOD)
	map:Stairs(-49.5, -36, -44.5, -20, B, F2, "+Z", WOOD)
	wallZ(map, STONE_WALL, -50, -36, -18, BF, F2 - BF)

	local function rail(x1: number, z1: number, x2: number, z2: number, y: number)
		map:Railing(Vector3.new(x1, y, z1), Vector3.new(x2, y, z2))
	end
	-- The gallery's edge round the void (the main stairs come up at its east end)
	rail(-14, 8, 13.5, 8, F2)
	rail(-14, 8, -14, 39.5, F2)
	-- Round the floor openings (each flight is entered from its open end)
	rail(-4, -13.5, 12, -13.5, B) -- cellar stairs
	rail(12, -19.5, 12, -13.5, B)
	rail(-55.5, -18, -50.5, -18, B) -- back stairs, lower flight
	rail(-49.5, -36, -49.5, -20, F2) -- back stairs, upper flight
	rail(-44.5, -36, -44.5, -20, F2)
	rail(-49.5, -36, -44.5, -36, F2)
	-- Handrails up the open sides of the flights
	map:Railing(Vector3.new(13.5, B, 24), Vector3.new(13.5, F2, 8))
	map:Railing(Vector3.new(12, BF, -13.5), Vector3.new(-4, B, -13.5))
	map:Railing(Vector3.new(-44.5, B, -36), Vector3.new(-44.5, F2, -20))
end

-- Snowmobile standing on `base` at (x, z), nose toward +x
local function snowmobile(map: MapBuilder.Builder, x: number, z: number, base: number, color: Color3)
	block(map, "Snowmobile", x - 3, base + 0.7, z - 1.3, x + 2.2, base + 2.2, z + 1.3, color, Enum.Material.SmoothPlastic)
	block(map, "SnowmobileNose", x + 2.2, base + 0.3, z - 1.1, x + 3.6, base + 1.6, z + 1.1, color, Enum.Material.SmoothPlastic)
	block(map, "Seat", x - 2.8, base + 2.2, z - 0.8, x + 0.2, base + 2.8, z + 0.8, BLACK, Enum.Material.Fabric)
	block(map, "Track", x - 3.2, base, z - 0.9, x - 0.4, base + 0.7, z + 0.9, BLACK, Enum.Material.Rubber)
	for _, side in { -1, 1 } do
		block(map, "Ski", x + 0.6, base, z + side * 1.2 - 0.2, x + 4.4, base + 0.3, z + side * 1.2 + 0.2, DARK_METAL, Enum.Material.Metal)
	end
	block(map, "Windshield", x + 1.6, base + 2.2, z - 1, x + 1.8, base + 3.4, z + 1, Color3.fromRGB(170, 200, 215), Enum.Material.Glass).Transparency = 0.5
end

local function buildProps(map: MapBuilder.Builder)
	local shell = map:Folder("Shell")
	-- Rugs lie with the floor finishes (DestructionService cuts them along with the floor)
	local function rug(x1: number, z1: number, x2: number, z2: number, level: number, color: Color3)
		cosmetic(map:Floor("RugFloor", x1, z1, x2, z2, level + 0.08, 0.04, color, Enum.Material.Carpet), shell)
	end
	local function bed(x1: number, z1: number, x2: number, z2: number, level: number, color: Color3)
		block(map, "Bed", x1, level, z1, x2, level + 2.2, z2, color, Enum.Material.Fabric)
	end
	-- Bunk bed, long along z: two bunks between end boards
	local function bunk(x1: number, z1: number, x2: number, z2: number)
		block(map, "Bunk", x1, F2, z1 + 0.4, x2, F2 + 2, z2 - 0.4, WOOD, Enum.Material.WoodPlanks)
		block(map, "Bunk", x1, F2 + 4.6, z1 + 0.4, x2, F2 + 5.4, z2 - 0.4, WOOD, Enum.Material.WoodPlanks)
		for _, z in { z1, z2 - 0.4 } do
			block(map, "BunkEnd", x1, F2, z, x2, F2 + 6.4, z + 0.4, DARK_LOG, Enum.Material.Wood)
		end
	end
	local crate = Color3.fromRGB(150, 115, 70)

	-- Great room: the stone fireplace (a real hearth, solid cover), sofas round a rug in front of it,
	-- log posts holding up the gallery, beams under the roof
	block(map, "ChimneyBreast", -6, B, 36, -3, CEILING, 39.5, FIELDSTONE, Enum.Material.Cobblestone)
	block(map, "ChimneyBreast", 3, B, 36, 6, CEILING, 39.5, FIELDSTONE, Enum.Material.Cobblestone)
	block(map, "ChimneyBreast", -3, B + 5, 36, 3, CEILING, 39.5, FIELDSTONE, Enum.Material.Cobblestone)
	block(map, "Firebox", -3, B, 38, 3, B + 5, 39.5, SOOT, Enum.Material.Slate)
	block(map, "Hearth", -8, B, 33, 8, B + 1, 36, SLATE, Enum.Material.Slate)
	block(map, "Mantel", -6.5, B + 6, 35.2, 6.5, B + 6.6, 36, DARK_LOG, Enum.Material.Wood)
	for i, z in { 36.8, 37.4 } do
		local log = map:Part("FireLog", Vector3.new(4, 0.6, 0.6), CFrame.new(0, B + 0.3 + (i - 1) * 0.5, z) * CFrame.Angles(0, (i - 1.5) * 0.6, 0), BARK, Enum.Material.Wood)
		log.Shape = Enum.PartType.Cylinder
	end
	local fire = block(map, "Fire", -1.2, B + 0.6, 36.6, 1.2, B + 2.6, 37.6, FIRE, Enum.Material.Neon)
	fire.Transparency = 0.25
	fire.CastShadow = false
	cosmetic(fire, map.geometry)
	local glow = Instance.new("PointLight")
	glow.Range = 22
	glow.Brightness = 1.6
	glow.Color = Color3.fromRGB(255, 160, 90)
	glow.Shadows = true
	glow.Parent = fire
	rug(-10, 14, 10, 31, B, Color3.fromRGB(140, 50, 42))
	block(map, "Sofa", -8, B, 14, 8, B + 2.2, 16.5, LEATHER, Enum.Material.Fabric)
	block(map, "SofaBack", -8, B + 2.2, 14, 8, B + 3.6, 14.8, LEATHER, Enum.Material.Fabric)
	block(map, "Sofa", -12.5, B, 19, -10, B + 2.2, 29, LEATHER, Enum.Material.Fabric)
	block(map, "SofaBack", -12.5, B + 2.2, 19, -11.7, B + 3.6, 29, LEATHER, Enum.Material.Fabric)
	block(map, "CoffeeTable", -4, B, 22, 4, B + 1.6, 26, DARK_LOG, Enum.Material.Wood)
	block(map, "Armchair", 7.5, B, 21, 11, B + 3, 24.5, LEATHER, Enum.Material.Fabric)
	block(map, "Piano", -19.5, B, 11, -15.5, B + 3.4, 16.5, BLACK, Enum.Material.SmoothPlastic)
	for _, p in { { -14, 8 }, { -14, 20 }, { -14, 32 }, { 2, 8 } } do
		block(map, "Post", p[1] - 0.6, B, p[2] - 0.6, p[1] + 0.6, F2 - 1, p[2] + 0.6, DARK_LOG, Enum.Material.Wood)
	end
	for _, z in { 16, 26, 34 } do
		cosmetic(block(map, "Beam", -19.5, CEILING - 1.2, z - 0.6, 19.5, CEILING, z + 0.6, DARK_LOG, Enum.Material.Wood), map.geometry)
	end

	-- Foyer
	rug(-6, -36, 6, -24, B, Color3.fromRGB(120, 44, 40))
	block(map, "Bench", -19.5, B, -39, -17.5, B + 1.8, -33, DARK_LOG, Enum.Material.Wood)
	block(map, "BootBench", 12, B, -39.5, 18, B + 1.6, -38, DARK_LOG, Enum.Material.Wood)
	block(map, "CoatRack", 18, B, -36, 19, B + 6.5, -35, DARK_LOG, Enum.Material.Wood)
	block(map, "ConsoleTable", 0, B, -22, 7, B + 3, -20.5, DARK_LOG, Enum.Material.Wood)

	-- Library: shelves on the walls, a map table and a reading desk (low: the camera sees over them)
	block(map, "Bookshelf", -42, B, -16, -32, B + 7.5, -14.5, DARK_LOG, Enum.Material.Wood)
	block(map, "Bookshelf", -22, B, -39.5, -20.5, B + 7.5, -33, DARK_LOG, Enum.Material.Wood)
	block(map, "MapTable", -38, B, -30, -32, B + 3, -26, DARK_LOG, Enum.Material.Wood)
	block(map, "ReadingDesk", -30, B, -24, -24, B + 2.8, -21, DARK_LOG, Enum.Material.Wood)
	block(map, "Armchair", -28, B, -38, -24.5, B + 3, -34.5, LEATHER, Enum.Material.Fabric)

	-- Dining room: a long table with benches, a sideboard
	block(map, "DiningTable", -48, B, -3, -34, B + 2.8, 3, DARK_LOG, Enum.Material.Wood)
	for _, z in { -5.2, 3.6 } do
		block(map, "DiningBench", -47, B, z, -35, B + 1.6, z + 1.6, DARK_LOG, Enum.Material.Wood)
	end
	block(map, "Sideboard", -42, B, -13.5, -32, B + 3, -12, DARK_LOG, Enum.Material.Wood)

	-- Kitchen: counters under the windows, the range and its hood, the fridge, an island
	block(map, "Counter", -55.5, B, 37, -38, B + 3, 39.5, GRANITE, Enum.Material.Granite)
	block(map, "Counter", -55.5, B, 16, -53, B + 3, 27, GRANITE, Enum.Material.Granite)
	block(map, "Range", -42, B + 3, 37.2, -38, B + 3.2, 39.5, BLACK, Enum.Material.Metal)
	block(map, "Hood", -42, B + 7, 37.5, -38, B + 9, 39.5, DARK_METAL, Enum.Material.Metal)
	block(map, "Fridge", -55.5, B, 12.5, -52, B + 7, 16, Color3.fromRGB(200, 202, 204), Enum.Material.Metal)
	block(map, "Island", -40, B, 22, -30, B + 3, 26, DARK_LOG, Enum.Material.Wood)
	block(map, "IslandTop", -40.3, B + 3, 21.7, -29.7, B + 3.2, 26.3, GRANITE, Enum.Material.Granite)

	-- Trophy room: a stuffed bear, a display case, a trophy cabinet, antlers on the wall
	local fur = Color3.fromRGB(70, 48, 32)
	block(map, "TrophyCabinet", 34, B, -39.5, 40, B + 7, -38, DARK_LOG, Enum.Material.Wood)
	block(map, "DisplayCase", 38, B, -24, 44, B + 3.4, -21, DARK_LOG, Enum.Material.Wood)
	block(map, "Bear", 46, B, -31, 50, B + 4.4, -28, fur, Enum.Material.Fabric)
	block(map, "BearHead", 46.6, B + 4.4, -30.4, 49.4, B + 6.6, -28.6, fur, Enum.Material.Fabric)
	for _, x in { 26, 31, 46, 51 } do
		cosmetic(block(map, "Mount", x - 0.8, B + 7.6, -14.9, x + 0.8, B + 9, -14.5, DARK_LOG, Enum.Material.Wood), map.geometry)
		cosmetic(block(map, "Antlers", x - 1.8, B + 9, -14.8, x + 1.8, B + 9.3, -14.6, Color3.fromRGB(220, 206, 180), Enum.Material.SmoothPlastic), map.geometry)
	end

	-- Gaming room: a pool table, arcade machines, foosball
	block(map, "PoolTable", 35, B, -7, 43, B + 2.6, -2, DARK_LOG, Enum.Material.Wood) -- (clear of the hatch down to the garage)
	block(map, "Felt", 35.5, B + 2.6, -6.5, 42.5, B + 2.8, -2.5, Color3.fromRGB(40, 110, 70), Enum.Material.Fabric)
	for i, x in { 46, 49, 52 } do
		block(map, "Arcade", x, B, -13.5, x + 2.2, B + 6, -11.5, BLACK, Enum.Material.SmoothPlastic)
		local screenColor = ({ Color3.fromRGB(60, 200, 255), Color3.fromRGB(255, 80, 160), Color3.fromRGB(120, 255, 120) })[i]
		cosmetic(block(map, "Screen", x + 0.3, B + 3.6, -11.5, x + 1.9, B + 5.2, -11.4, screenColor, Enum.Material.Neon), map.geometry)
	end
	block(map, "Foosball", 25, B, 4, 30, B + 3, 7, DARK_LOG, Enum.Material.Wood)

	-- Bar: the counter (its east end against the wall: get behind it from the west), back bar,
	-- stools, round tables
	block(map, "BarCounter", 42, B, 28, 55.5, B + 3.6, 30.5, DARK_LOG, Enum.Material.Wood)
	block(map, "BarTop", 41.7, B + 3.6, 27.7, 55.5, B + 3.8, 30.8, GRANITE, Enum.Material.Granite)
	block(map, "BackBar", 43, B, 38, 55.5, B + 3, 39.5, DARK_LOG, Enum.Material.Wood)
	cosmetic(block(map, "Bottles", 44, B + 3, 38.5, 54, B + 4.2, 39.2, Color3.fromRGB(70, 110, 60), Enum.Material.Glass), map.geometry)
	for _, x in { 47, 50, 53 } do -- (clear of the drop from the guest room's hatch)
		drum(map, "Stool", x, 26.4, B, 2.6, 1.4, LEATHER, Enum.Material.Fabric)
	end
	for _, t in { { 28, 18 }, { 36, 20 }, { 28, 25 } } do
		drum(map, "BarTable", t[1], t[2], B, 3, 3.2, DARK_LOG, Enum.Material.Wood)
	end

	-- Wine cellar: two racks down the middle (lanes between them), one along the back wall, barrels,
	-- a tasting table
	for _, x in { -6, 6 } do
		block(map, "WineRack", x - 0.7, BF, -34, x + 0.7, BF + 7, -24, DARK_LOG, Enum.Material.WoodPlanks)
	end
	block(map, "WineRack", -16, BF, -39.5, 16, BF + 7, -38.3, DARK_LOG, Enum.Material.WoodPlanks)
	for _, x in { -17.5, 17.5 } do
		drum(map, "Barrel", x, -36.5, BF, 3.4, 3, Color3.fromRGB(120, 80, 50), Enum.Material.Wood)
	end
	drum(map, "TastingTable", 12, -24, BF, 3, 3, DARK_LOG, Enum.Material.Wood)

	-- Garage: snowmobiles, a workbench, tool shelves, fuel drums
	snowmobile(map, 44, -15, BF, Color3.fromRGB(180, 40, 36))
	snowmobile(map, 44, -30, BF, Color3.fromRGB(40, 80, 150))
	block(map, "Workbench", 24, BF, -39.5, 34, BF + 3, -37, WOOD, Enum.Material.Wood)
	block(map, "ToolShelf", 54, BF, -38, 55.5, BF + 7, -28, DARK_METAL, Enum.Material.Metal)
	for _, x in { 24, 27 } do
		drum(map, "FuelDrum", x, -3, BF, 3.4, 2.4, Color3.fromRGB(170, 40, 30), Enum.Material.Metal)
	end

	-- Workshop: a bench, tool shelves, a snowmobile in for repairs, crates
	block(map, "Workbench", 24, BF, 37, 40, BF + 3, 39.5, WOOD, Enum.Material.Wood)
	block(map, "ToolShelf", 54, BF, 6, 55.5, BF + 7, 20, DARK_METAL, Enum.Material.Metal)
	snowmobile(map, 36, 18, BF, Color3.fromRGB(230, 170, 40))
	for _, c in { { 46, 30 }, { 50.5, 30 }, { 48, 34.5 } } do
		block(map, "Crate", c[1] - 2, BF, c[2] - 2, c[1] + 2, BF + 4, c[2] + 2, crate, Enum.Material.WoodPlanks)
	end

	-- Wine stock: shelving along the walls, crates and barrels (the defenders' spawn is in front)
	for _, x in { -17, 17 } do
		block(map, "Shelving", x - 0.8, BF, 4, x + 0.8, BF + 7, 22, DARK_LOG, Enum.Material.WoodPlanks)
	end
	for _, c in { { -6, 30 }, { 6, 33 } } do
		block(map, "Crate", c[1] - 2, BF, c[2] - 2, c[1] + 2, BF + 4, c[2] + 2, crate, Enum.Material.WoodPlanks)
	end
	for _, b in { { 12, 26 }, { -12, 36 } } do
		drum(map, "Barrel", b[1], b[2], BF, 3.4, 3, Color3.fromRGB(120, 80, 50), Enum.Material.Wood)
	end

	-- Boiler room: two boilers and a water tank, clear of the way to the back stairs
	for _, x in { -34, -27.5 } do
		drum(map, "Boiler", x, -36, BF, 9, 5, Color3.fromRGB(150, 60, 50), Enum.Material.Metal)
	end
	drum(map, "WaterTank", -40, -26, BF, 7, 4, Color3.fromRGB(170, 170, 175), Enum.Material.Metal)

	-- Laundry and ski storage
	for _, z in { -6, -2.5 } do
		block(map, "Washer", -55.5, BF, z, -52.5, BF + 3.6, z + 3, WHITE, Enum.Material.Metal)
	end
	block(map, "FoldingTable", -32, BF, -2, -24, BF + 3, 2, WOOD, Enum.Material.Wood)
	block(map, "SkiRack", -54, BF, 38, -30, BF + 6, 39.5, DARK_LOG, Enum.Material.Wood)
	block(map, "Lockers", -55.5, BF, 16, -54, BF + 7, 30, Color3.fromRGB(90, 110, 130), Enum.Material.Metal)
	for _, c in { { -40, 26 }, { -28, 34 } } do
		block(map, "Crate", c[1] - 2, BF, c[2] - 2, c[1] + 2, BF + 4, c[2] + 2, crate, Enum.Material.WoodPlanks)
	end

	-- Upstairs, west: gear room, sauna, bathroom
	block(map, "Lockers", -55.5, F2, -24, -54, F2 + 7, -15, Color3.fromRGB(90, 110, 130), Enum.Material.Metal)
	block(map, "SkiRack", -55, F2, -39.5, -50, F2 + 6, -38.5, DARK_LOG, Enum.Material.Wood)
	block(map, "Bench", -42, F2, -30, -38, F2 + 1.6, -28.5, DARK_LOG, Enum.Material.Wood)
	block(map, "SaunaBench", -35.5, F2, -39.5, -20.5, F2 + 2.6, -37.5, CEDAR, Enum.Material.WoodPlanks)
	block(map, "SaunaStep", -35.5, F2, -37.5, -20.5, F2 + 1.3, -36, CEDAR, Enum.Material.WoodPlanks)
	block(map, "SaunaStove", -24, F2, -30, -22, F2 + 2.6, -28, BLACK, Enum.Material.Metal)
	block(map, "SaunaStones", -23.8, F2 + 2.6, -29.8, -22.2, F2 + 3, -28.2, SLATE, Enum.Material.Slate)
	block(map, "Tub", -26, F2, -18, -20.5, F2 + 2, -14.5, WHITE, Enum.Material.Marble)
	block(map, "Sink", -35.5, F2, -25.5, -33.5, F2 + 3, -23, WHITE, Enum.Material.Marble)

	-- Office: a desk, bookshelves, a filing cabinet
	block(map, "Desk", -50, F2, -2, -42, F2 + 2.8, 1, DARK_LOG, Enum.Material.Wood)
	block(map, "Bookshelf", -55.5, F2, -13.5, -54, F2 + 7, -9, DARK_LOG, Enum.Material.Wood)
	block(map, "Bookshelf", -55.5, F2, 8, -44, F2 + 7, 9.5, DARK_LOG, Enum.Material.Wood)
	block(map, "FilingCabinet", -22, F2, 2, -20.5, F2 + 4.5, 6, DARK_METAL, Enum.Material.Metal)

	-- Master bedroom: the bed against the west wall, a wardrobe, a dresser
	rug(-42, 16, -32, 30, F2, Color3.fromRGB(110, 60, 50))
	block(map, "Headboard", -55.5, F2, 21, -54.9, F2 + 3, 29, DARK_LOG, Enum.Material.Wood)
	bed(-54.9, 21, -47, 29, F2, Color3.fromRGB(150, 60, 50))
	block(map, "Nightstand", -55.5, F2, 29.5, -53.5, F2 + 2.2, 31.5, DARK_LOG, Enum.Material.Wood)
	block(map, "Wardrobe", -30, F2, 10.5, -22, F2 + 7.5, 12, DARK_LOG, Enum.Material.Wood)
	block(map, "Dresser", -42, F2, 38, -36, F2 + 3, 39.5, DARK_LOG, Enum.Material.Wood)

	-- Bunk room, reading room, the landing
	bunk(-19.5, -39.5, -15.5, -31.5)
	bunk(1.5, -23, 5.5, -15)
	block(map, "Bookshelf", 18, F2, -39.5, 19.5, F2 + 7, -32, DARK_LOG, Enum.Material.Wood)
	block(map, "Bookshelf", 18, F2, -23, 19.5, F2 + 7, -15, DARK_LOG, Enum.Material.Wood)
	block(map, "Armchair", 8, F2, -38, 11.5, F2 + 3, -34.5, LEATHER, Enum.Material.Fabric)
	block(map, "Armchair", 8, F2, -22, 11.5, F2 + 3, -18.5, LEATHER, Enum.Material.Fabric)
	block(map, "Bench", -2, F2, -13.5, 8, F2 + 1.8, -12, DARK_LOG, Enum.Material.Wood)

	-- Twin room, TV room, guest room
	for _, x in { 28, 44 } do
		bed(x, -39.5, x + 5, -31, F2, Color3.fromRGB(70, 90, 130))
	end
	block(map, "Nightstand", 37, F2, -39.5, 40, F2 + 2.2, -37.5, DARK_LOG, Enum.Material.Wood)
	block(map, "Dresser", 24, F2, -16, 30, F2 + 3.2, -14.5, DARK_LOG, Enum.Material.Wood)
	block(map, "TVStand", 24, F2, 8, 36, F2 + 2.2, 9.5, DARK_LOG, Enum.Material.Wood)
	block(map, "TV", 26, F2 + 2.2, 8.6, 34, F2 + 6.4, 9, BLACK, Enum.Material.SmoothPlastic)
	block(map, "Sofa", 25, F2, 2, 35, F2 + 2.2, 4.5, Color3.fromRGB(90, 96, 104), Enum.Material.Fabric)
	block(map, "SofaBack", 25, F2 + 2.2, 2, 35, F2 + 3.6, 2.8, Color3.fromRGB(90, 96, 104), Enum.Material.Fabric)
	block(map, "Headboard", 54.9, F2, 24, 55.5, F2 + 3, 32, DARK_LOG, Enum.Material.Wood)
	bed(47, 24, 54.9, 32, F2, Color3.fromRGB(70, 110, 90))
	block(map, "Wardrobe", 34, F2, 38, 40, F2 + 7.5, 39.5, DARK_LOG, Enum.Material.Wood)
end

-- Gable roof over x1..x2 × z1..z2 (wall lines), ridge along x, under a blanket of snow; the
-- slopes meet the walls at `base` and overhang 2 studs. `gables` are the x positions of the
-- triangular end walls.
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
		local length = (high - low).Magnitude
		map:Part("Roof", Vector3.new(x2 - x1, 1, length), frame * CFrame.new(0, 0.5, 0), DARK_LOG, Enum.Material.WoodPlanks)
		-- (the snow stops short of the eaves, so the dark boards show along the edge)
		map:Part("RoofSnow", Vector3.new(x2 - x1 - 0.6, 0.8, length - 0.6), frame * CFrame.new(0, 1.4, -0.3), SNOW, Enum.Material.Snow)
	end
	map:Part("RidgeSnow", Vector3.new(x2 - x1 - 0.6, 0.8, 2.4), CFrame.new((x1 + x2) / 2, ridge + 2, midZ), SNOW, Enum.Material.Snow)
	for _, x in gables do
		local size = Vector3.new(1, rise, halfDepth)
		wedge(map, "Gable", size, CFrame.new(x, base + rise / 2, z1 + halfDepth / 2), LOG, Enum.Material.Wood)
		wedge(map, "Gable", size, CFrame.new(x, base + rise / 2, z2 - halfDepth / 2) * CFrame.Angles(0, math.pi, 0), LOG, Enum.Material.Wood)
	end
end

-- Pine: a trunk and four tiers of boughs, snow lying on each. Trees go in the Yard folder:
-- standing under one still counts as outdoors (PerimeterService).
local function pine(map: MapBuilder.Builder, x: number, z: number, height: number)
	local yard = map:Folder("Yard")
	drum(map, "Trunk", x, z, GROUND, height * 0.45, 1.6, BARK, Enum.Material.Wood).Parent = yard
	for i = 0, 3 do
		local bottom = GROUND + height * (0.15 + 0.2 * i)
		local thick = height * 0.13
		local width = height * (0.44 - 0.09 * i)
		drum(map, "Boughs", x, z, bottom, thick, width, PINE, Enum.Material.Grass).Parent = yard
		drum(map, "BoughSnow", x, z, bottom + thick, 0.5, width * 0.75, SNOW, Enum.Material.Snow).Parent = yard
	end
	drum(map, "TreeTop", x, z, GROUND + height * 0.88, height * 0.1, 1.4, PINE, Enum.Material.Grass).Parent = yard
end

-- Snowbank: a long ridge of snow (two wedges back to back), along x or along z. Low cover you
-- can crouch behind or walk over.
local function snowbank(map: MapBuilder.Builder, x: number, z: number, length: number, alongX: boolean, height: number)
	local half = height * 1.1 -- how far each slope runs (just under 45°: you can walk up it)
	for _, side in { -1, 1 } do
		-- Each half climbs toward the ridge line
		local cframe = if alongX
			then CFrame.new(x, GROUND + height / 2, z - side * half / 2) * CFrame.Angles(0, if side > 0 then 0 else math.pi, 0)
			else CFrame.new(x - side * half / 2, GROUND + height / 2, z) * CFrame.Angles(0, side * math.pi / 2, 0)
		wedge(map, "Snowbank", Vector3.new(length, height, half), cframe, SNOW, Enum.Material.Snow)
	end
end

local function buildOutside(map: MapBuilder.Builder)
	local yard = map:Folder("Yard") -- (PerimeterService: trees, the woodshed and parked cars aren't a roof)
	local function toYard(part: BasePart)
		part.Parent = yard
	end

	-- Roof, snowed over, and the chimney up the outside of the fireplace wall
	gableRoof(map, -58, 58, -40, 40, ROOF_BASE, { -56, 56 })
	block(map, "Chimney", -4, GROUND, 40.5, 4, ROOF_BASE + 9, 44.5, FIELDSTONE, Enum.Material.Cobblestone)
	block(map, "ChimneyCap", -4.6, ROOF_BASE + 9, 39.9, 4.6, ROOF_BASE + 9.6, 45.1, SLATE, Enum.Material.Slate)

	-- Ground: snow (not under the chalet or the ramp, so it can't plug them), the ploughed road,
	-- the gravel drive and parking, the frozen lake
	local footprints = { { -56.5, -40.5, 56.5, 40.5 }, { 56.5, -22.5, 84.5, -1.5 } }
	map:FloorWithHoles("Snow", -150, -130, 150, 130, footprints, GROUND, 0.4, SNOW, Enum.Material.Snow)
	map:Floor("Road", -150, -122, 150, -100, 0.3, 0.2, ASPHALT, Enum.Material.Asphalt)
	for x = -144, 144, 16 do
		cosmetic(block(map, "RoadLine", x - 3, 0.3, -111.15, x + 3, 0.34, -110.85, Color3.fromRGB(214, 176, 60), Enum.Material.SmoothPlastic), map.geometry)
	end
	map:Floor("Driveway", -7, -100, 7, -50, 0.3, 0.2, GRAVEL, Enum.Material.Pebble)
	map:Floor("Parking", 7, -74, 31, -56, 0.3, 0.2, GRAVEL, Enum.Material.Pebble)
	local lake = map:Floor("Lake", -150, 92, 150, 130, 0.25, 0.2, ICE, Enum.Material.Ice)
	lake.CustomPhysicalProperties = PhysicalProperties.new(Enum.Material.Snow) -- (looks like ice, doesn't skate like it)

	-- Front porch, and the bunk room's balcony over it on two log posts
	map:Floor("Porch", -12, -50, 12, -40.5, B, 0.4, SLATE, Enum.Material.Slate)
	map:Floor("Balcony", -10, -48, 10, -40.5, F2, 1, WOOD, Enum.Material.WoodPlanks)
	for _, x in { -9.4, 9.4 } do
		block(map, "PorchPost", x - 0.6, B, -47.6, x + 0.6, F2 - 1, -46.4, DARK_LOG, Enum.Material.Wood)
	end
	map:Railing(Vector3.new(-10, F2, -40.5), Vector3.new(-10, F2, -48))
	map:Railing(Vector3.new(-10, F2, -48), Vector3.new(10, F2, -48))
	map:Railing(Vector3.new(10, F2, -48), Vector3.new(10, F2, -40.5))

	-- Deck off the great room (the lake view): railings with gaps north and west, a hot tub, chairs
	map:Floor("Deck", -24, 40.5, 24, 56, B, 0.4, DECK, Enum.Material.WoodPlanks)
	for _, r in { { -24, 40.5, -24, 46 }, { -24, 52, -24, 56 }, { -24, 56, -4, 56 }, { 4, 56, 24, 56 }, { 24, 56, 24, 40.5 } } do
		map:Railing(Vector3.new(r[1], B, r[2]), Vector3.new(r[3], B, r[4]))
	end
	block(map, "HotTub", 10, B, 45, 20, B + 2.8, 53, DARK_LOG, Enum.Material.WoodPlanks)
	local water = block(map, "HotTubWater", 10.6, B + 2.8, 45.6, 19.4, B + 2.9, 52.4, Color3.fromRGB(110, 190, 210), Enum.Material.Glass)
	water.Transparency = 0.3
	cosmetic(water, map.geometry)
	for _, x in { -18, -12 } do
		block(map, "DeckChair", x - 1.2, B, 47, x + 1.2, B + 2.4, 49.5, CEDAR, Enum.Material.WoodPlanks)
	end

	-- Garage ramp: from the east yard down to the garage doors, between fieldstone retaining walls
	map:Floor("RampLanding", 56.5, -21.5, 60, -2.5, BF, 1, CONCRETE, Enum.Material.Concrete)
	wedge(map, "GarageRamp", Vector3.new(19, GROUND - BF, 24.5), CFrame.new(72.25, (BF + GROUND) / 2, -12) * CFrame.Angles(0, math.pi / 2, 0), CONCRETE, Enum.Material.Concrete)
	for _, z in { -22, -2 } do
		map:Wall("RetainingWall", 56.5, z, 84.5, z, BF, 3.2 - BF, nil, FIELDSTONE, Enum.Material.Cobblestone)
	end
	snowmobile(map, 90, 6, GROUND, Color3.fromRGB(40, 140, 90))

	-- Log fence round the yard, with gaps to get through (wood: shoot / knife through it, or hop it)
	local function fence(x1: number, z1: number, x2: number, z2: number, gaps: { { number } })
		local start = if z1 == z2 then x1 else z1
		local openings = {}
		for _, gap in gaps do
			table.insert(openings, { from = gap[1] - start, to = gap[2] - start, top = 4 })
		end
		for _, piece in map:Wall("Fence", x1, z1, x2, z2, GROUND, 4, openings, LOG, Enum.Material.WoodPlanks, 0.5) do
			piece:SetAttribute("Breakable", "Soft")
		end
	end
	fence(-110, -92, 110, -92, { { -60, -52 }, { -8, 8 }, { 50, 58 } })
	fence(-110, -92, -110, 84, { { -46, -38 }, { -4, 8 }, { 44, 52 } })
	fence(-110, 84, 110, 84, { { -46, -38 }, { -6, 6 }, { 36, 44 } })
	fence(110, -92, 110, 84, { { -30, -22 }, { 30, 38 } })

	-- Snowbanks: ploughed up along the road and the drive, drifts round the yard (cover on the way in)
	for _, x in { -118, -76, -34, 32, 76, 118 } do
		snowbank(map, x, -96.5, if math.abs(x) > 100 then 36 else 30, true, 3)
	end
	snowbank(map, -11.5, -75, 30, false, 3)
	snowbank(map, 11.5, -84, 12, false, 3)
	for _, s in {
		{ -40, -66, 18, true },
		{ 54, -64, 16, false },
		{ -80, -20, 20, false },
		{ -78, 30, 18, false },
		{ 80, 30, 18, false },
		{ 96, -12, 16, false },
		{ 96, -48, 16, true },
		{ -44, 70, 20, true },
		{ 50, 70, 20, true },
		{ 12, 76, 16, true },
	} do
		snowbank(map, s[1], s[2], s[3], s[4], 3.5)
	end

	-- Low fieldstone walls: hard cover
	for _, w in { { -66, -58, -54, -58 }, { 64, -40, 64, -28 }, { 24, 66, 36, 66 }, { -96, -60, -96, -48 } } do
		map:Wall("StoneWall", w[1], w[2], w[3], w[4], GROUND, 3, nil, FIELDSTONE, Enum.Material.Cobblestone, 1.2)
	end
	-- Boulders in the yard and along the lake shore
	for _, r in { { -96, -30, 5, 0.5 }, { 70, 50, 4, 1.1 }, { -116, 88, 6, 0.9 }, { -80, 89, 6, 0.3 }, { -30, 90, 5, 1.2 }, { 52, 89, 6, 0.7 }, { 90, 90, 5, 2 }, { 120, 88, 5, 0.4 } } do
		map:Part("Rock", Vector3.new(r[3], r[3] * 0.6, r[3] * 0.8), CFrame.new(r[1], GROUND + r[3] * 0.18, r[2]) * CFrame.Angles(0.08, r[4], 0.12), SLATE, Enum.Material.Slate)
	end

	-- Pines: the woods to the west, a few round the yard, more beyond the east fence
	for _, t in {
		{ -138, -86, 30 },
		{ -124, -76, 26 },
		{ -140, -48, 32 },
		{ -142, -24, 28 },
		{ -136, 24, 28 },
		{ -144, 44, 26 },
		{ -122, 46, 26 },
		{ -142, 68, 30 },
		{ -128, 78, 28 },
		{ -82, -78, 24 },
		{ -64, -82, 22 },
		{ -94, 72, 24 },
		{ -22, 74, 22 },
		{ 78, -76, 26 },
		{ 98, 14, 26 },
		{ 88, 56, 24 },
		{ 126, -60, 30 },
		{ 130, -84, 28 },
		{ 132, 0, 28 },
		{ 124, 50, 30 },
		{ 136, 76, 26 },
	} do
		pine(map, t[1], t[2], t[3])
	end

	-- Campfire in the woods: a ring of stones, the fire, two logs to sit on
	local fx, fz = -124, -24
	for i = 0, 5 do
		local a = i * math.pi / 3
		map:Part("FireRing", Vector3.new(1.4, 0.9, 1.2), CFrame.new(fx + math.cos(a) * 2.4, GROUND + 0.35, fz + math.sin(a) * 2.4) * CFrame.Angles(0, -a, 0), SLATE, Enum.Material.Slate)
	end
	local campfire = block(map, "Fire", fx - 1, GROUND, fz - 1, fx + 1, GROUND + 2.2, fz + 1, FIRE, Enum.Material.Neon)
	campfire.Transparency = 0.25
	campfire.CastShadow = false
	cosmetic(campfire, map.geometry)
	local flicker = Instance.new("PointLight")
	flicker.Range = 24
	flicker.Brightness = 1.5
	flicker.Color = Color3.fromRGB(255, 160, 90)
	flicker.Parent = campfire
	for _, dz in { -6, 6 } do
		local bench = map:Part("LogBench", Vector3.new(8, 1.6, 1.6), CFrame.new(fx, GROUND + 0.8, fz + dz), BARK, Enum.Material.Wood)
		bench.Shape = Enum.PartType.Cylinder
	end

	-- Woodshed in the west yard (open to the east), stacked with firewood
	for _, w in { { -84, 48, -84, 62 }, { -84, 48, -76, 48 }, { -84, 62, -76, 62 } } do
		for _, piece in map:Wall("Woodshed", w[1], w[2], w[3], w[4], GROUND, 8, nil, DARK_LOG, Enum.Material.WoodPlanks) do
			toYard(piece)
		end
	end
	toYard(map:Floor("WoodshedRoof", -85, 47, -75, 63, GROUND + 8.5, 0.5, SNOW, Enum.Material.Snow))
	for _, z in { 51, 55, 59 } do
		toYard(block(map, "Firewood", -83.5, GROUND, z - 1.5, -79, GROUND + 4, z + 1.5, BARK, Enum.Material.Wood))
	end

	-- Cars: two in the parking by the drive, one stopped on the road
	local function car(x: number, z: number, alongX: boolean, color: Color3)
		local hx, hz = if alongX then 6 else 2.6, if alongX then 2.6 else 6
		local cx, cz = if alongX then 3.2 else 2.3, if alongX then 2.3 else 3.2
		toYard(block(map, "Tyres", x - hx * 0.8, GROUND, z - hz * 0.9, x + hx * 0.8, 1.1, z + hz * 0.9, BLACK, Enum.Material.Rubber))
		toYard(block(map, "Car", x - hx, 1.1, z - hz, x + hx, 3.4, z + hz, color, Enum.Material.SmoothPlastic))
		toYard(block(map, "CarCabin", x - cx, 3.4, z - cz, x + cx, 5.2, z + cz, Color3.fromRGB(30, 34, 40), Enum.Material.Glass))
		toYard(block(map, "CarSnow", x - cx + 0.2, 5.2, z - cz + 0.2, x + cx - 0.2, 5.5, z + cz - 0.2, SNOW, Enum.Material.Snow))
	end
	car(14, -65, false, Color3.fromRGB(150, 36, 36))
	car(24, -65, false, Color3.fromRGB(40, 70, 110))
	car(44, -114, true, Color3.fromRGB(210, 210, 205))

	-- Lamp posts along the drive, by the deck and the ramp
	for _, p in { { -10, -54 }, { 34, -52 }, { -30, 60 }, { 30, 62 }, { 90, -28 } } do
		block(map, "LampPost", p[1] - 0.25, GROUND, p[2] - 0.25, p[1] + 0.25, 12, p[2] + 0.25, DARK_METAL, Enum.Material.Metal)
		map:Light(Vector3.new(p[1], 12.2, p[2]), 36, 1)
	end
	-- Lamps over the outside doors: x, y, z, which way the wall faces
	for _, l in {
		{ -6.5, B + 9, -41, 0 },
		{ 6.5, B + 9, -41, 0 }, -- front door, under the balcony
		{ -12, B + 10.2, 41, math.pi },
		{ 12, B + 10.2, 41, math.pi }, -- deck doors
		{ 43, B + 9.4, 41, math.pi }, -- bar
		{ -57, B + 9.4, 36.5, math.pi / 2 }, -- kitchen
		{ 57, B + 9.4, 10.5, -math.pi / 2 }, -- gaming room
		{ 57, BF + 10.5, -15, -math.pi / 2 }, -- over the garage door
	} do
		local lamp = map:Part("WallLamp", Vector3.new(1.2, 0.6, 0.8), CFrame.new(l[1], l[2], l[3]) * CFrame.Angles(0, l[4], 0), DARK_METAL, Enum.Material.Metal)
		cosmetic(lamp, map.geometry)
		local bulb = map:Part("Light", Vector3.new(1, 0.1, 0.6), lamp.CFrame * CFrame.new(0, -0.32, 0), Color3.fromRGB(255, 236, 190), Enum.Material.Neon)
		cosmetic(bulb, map.geometry)
		local light = Instance.new("PointLight")
		light.Range = 16
		light.Brightness = 1
		light.Color = Color3.fromRGB(255, 226, 180)
		light.Parent = bulb
	end

	-- Invisible walls at the edge of the world
	for _, edge in { { -150, -130, 150, -130 }, { -150, 130, 150, 130 }, { -150, -130, -150, 130 }, { 150, -130, 150, 130 } } do
		for _, piece in map:Wall("Boundary", edge[1], edge[2], edge[3], edge[4], -20, 120, nil, Color3.new(), nil, 2) do
			piece.Transparency = 1
			piece.CanQuery = false
		end
	end
end

function Chalet.Build(): Model
	local map = MapBuilder.new("Chalet")
	buildFloors(map)
	buildBasement(map)
	buildGround(map)
	buildUpstairs(map)
	buildStairs(map)
	buildProps(map)
	buildOutside(map)

	-- Sites: four pairs, A and B each; the defenders pick one pair per round
	local function site(name: string, x1: number, z1: number, x2: number, z2: number, level: number, pair: string, room: string)
		map:Site(name, Vector3.new(x1 + 0.5, level, z1 + 0.5), Vector3.new(x2 - 0.5, level + 6, z2 - 0.5), pair, room)
	end
	site("A", -20, -40, 20, -20, BF, "Cellar", "Wine cellar")
	site("B", 20, -40, 56, 0, BF, "Cellar", "Snowmobile garage")
	site("A", -56, -14, -20, 12, B, "Kitchen", "Dining")
	site("B", -56, 12, -20, 40, B, "Kitchen", "Kitchen")
	site("A", 20, -14, 56, 12, B, "Bar", "Gaming room")
	site("B", 20, 12, 56, 40, B, "Bar", "Bar")
	site("A", -56, -14, -20, 10, F2, "Upstairs", "Office")
	site("B", -56, 10, -20, 40, F2, "Upstairs", "Master bedroom")

	-- Defenders spawn by the pair they picked; attackers on the road, out on the lake or in the woods
	map:SpawnPad("Defend", Vector3.new(0, BF + 0.1, 12), Vector3.new(0, 0, -1), "Cellar")
	map:SpawnPad("Defend", Vector3.new(-32, B + 0.1, 32), Vector3.new(0, 0, -1), "Kitchen")
	map:SpawnPad("Defend", Vector3.new(40, B + 0.1, 6), Vector3.new(0, 0, -1), "Bar")
	map:SpawnPad("Defend", Vector3.new(-30, F2 + 0.1, 24), Vector3.new(-1, 0, 0), "Upstairs")
	map:SpawnPad("Attack", Vector3.new(-2, 0.4, -107), Vector3.new(0, 0, 1))
	map:SpawnPad("Attack", Vector3.new(12, 0.35, 106), Vector3.new(0, 0, -1))
	map:SpawnPad("Attack", Vector3.new(-130, 0.3, 4), Vector3.new(1, 0, 0))
	map:FreeRoamSpawn(Vector3.new(0, 0.5, -66))

	return map.model
end

return Chalet
