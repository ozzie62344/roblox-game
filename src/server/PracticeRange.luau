-- PRACTICE RANGE — behind the doorway in the lobby's south wall (lobby servers only: on a match
-- server the doorway stays plugged, Maps/Lobby "RangeDoorPlug"). Walk in and you play like in a
-- match: first person, gun out (client PracticeRange / LobbyView), shooting practice bots
-- (PracticeBots). Players can't hurt each other here (WeaponService protects anyone whose
-- Location is "Lobby"), and bot kills never count for XP, career stats, challenges or
-- leaderboards (those only count player deaths in a match: RoundService).
--
--                          lobby south wall
--                                ║ corridor
--   ┌────────────────────────────╨──────────────────────────┐ z 47
--   │  entry                                 │ firing line  │ z 58
--   │ ┌────door──────────┬──────door───────┐ │  10 ──────── │ z 68
--   │ │  A               door      B       │ │  25 ──────── │ z 83
--   │ ├──door────────────┼────────door─────┤ │  cover       │
--   │ │  C               door      D       │ │  50 ──────── │ z 108
--   │ └──────────────────┴─────────────────┘ │  backstop    │
--   └────────────────────────────────────────┴──────────────┘ z 131
--   x -34             kill house           x 20   lane     x 46
--
-- The server decides who's in the range (the "Zone" box): their "InPracticeRange" attribute. Bots
-- only run while someone's in there, and only shoot at those players. You're healed on the way out.

local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Lobby = require(script.Parent.Maps.Lobby)
local MapBuilder = require(script.Parent.Maps.MapBuilder)
local MapCleanup = require(script.Parent.Maps.MapCleanup)
local PracticeBots = require(script.Parent.PracticeBots)
local RoundService = require(script.Parent.RoundService)

local PracticeRange = {}

PracticeRange.Attribute = "InPracticeRange" -- on players, set by the server

local ROOM = { x1 = -34, x2 = 46, z1 = 47, z2 = 131 } -- relative to Lobby.Origin; walls on these lines
local ROOM_HEIGHT = 16
local FIRING_LINE = 58 -- z: distances are measured from here
local LANE_X = 20 -- the wall between the kill house (west) and the lane (east)
local MARKERS = { 10, 25, 50 } -- studs from the firing line
local HOUSE_FRONT = 62 -- z of the kill house's front wall
local HOUSE_MID_X, HOUSE_MID_Z = -8, 96 -- its inside walls (four rooms)
local HOUSE_WALL = 10 -- open-topped, like a real shoot house
local HOUSE_DOOR = 8 -- doorway height
local CHECK_EVERY = 0.25 -- seconds between zone checks
local IDLE_TIME = 10 -- seconds the range has to be empty before the bots are cleared away

local FLOOR = Color3.fromRGB(72, 74, 80)
local PLYWOOD = Color3.fromRGB(150, 115, 70) -- (the lobby's crates)
local BRICK = Color3.fromRGB(150, 88, 70) -- (the lobby's low wall)
local DIVIDER = Color3.fromRGB(96, 98, 104)
local BACKSTOP = Color3.fromRGB(34, 36, 40)

local zone: BasePart? = nil

-- A sign like the lobby's screens: a dark glass panel in a trim frame, two lines of text.
-- `face` is the side the text is on (the way the sign faces).
local function sign(map: MapBuilder.Builder, center: Vector3, size: Vector2, face: Enum.NormalId, title: string, subtitle: string?)
	local P = Lobby.Palette
	local normal = Vector3.FromNormalId(face)
	local across = Vector3.new(math.abs(normal.Z), 0, math.abs(normal.X)) -- along the wall
	local half = across * size.X / 2 + Vector3.yAxis * size.Y / 2
	-- (a Box can't be inside out: sort the corners so min < max on every axis)
	local function corners(a: Vector3, b: Vector3): (Vector3, Vector3)
		return Vector3.new(math.min(a.X, b.X), math.min(a.Y, b.Y), math.min(a.Z, b.Z)), Vector3.new(math.max(a.X, b.X), math.max(a.Y, b.Y), math.max(a.Z, b.Z))
	end
	local pad = (across + Vector3.yAxis) * 0.3
	local frameMin, frameMax = corners(center - normal * 0.5 - half - pad, center + half + pad)
	local framePart = map:Box("SignFrame", frameMin, frameMax, P.Trim, Enum.Material.Metal)
	framePart.CanCollide = false
	local glassMin, glassMax = corners(center - half, center + half + normal * 0.15)
	local panel = map:Box("Sign", glassMin, glassMax, P.Screen, Enum.Material.Glass)
	panel.CanCollide = false
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Parent = panel
	local function label(text: string, y: number, height: number, color: Color3)
		local l = Instance.new("TextLabel")
		l.AnchorPoint = Vector2.new(0.5, 0.5)
		l.Position = UDim2.fromScale(0.5, y)
		l.Size = UDim2.fromScale(0.94, height)
		l.BackgroundTransparency = 1
		l.Font = Enum.Font.Michroma
		l.TextScaled = true
		l.Text = text
		l.TextColor3 = color
		l.Parent = gui
	end
	if subtitle then
		label(title, 0.38, 0.5, Color3.new(1, 1, 1))
		label(subtitle, 0.78, 0.22, P.Accent)
	else
		label(title, 0.5, 0.7, Color3.new(1, 1, 1))
	end
end

-- Builds the corridor, the range and the sign over the lobby doorway. Returns the model and where
-- the bots walk (PracticeBots.Layout, minus the zone / entrance which the caller adds).
local function build(): (Model, { PracticeBots.Area }, CFrame)
	local map = MapBuilder.new("PracticeRange")
	local P = Lobby.Palette
	local door = Lobby.RangeDoor
	local o = Lobby.Origin
	local function at(x: number, y: number, z: number): Vector3
		return o + Vector3.new(x, y, z)
	end
	local function flat(x: number, z: number): Vector3
		return at(x, 0, z)
	end
	-- Wood wainscot and baseboard on the inside face of a wall (min / max: the band's box)
	local function band(min: Vector3, max: Vector3)
		local wood = map:Box("Wainscot", min, max, P.Panel, Enum.Material.WoodPlanks)
		wood.CanCollide = false
		local base = map:Box("Baseboard", min - Vector3.new(0.05, 0, 0.05), Vector3.new(max.X, min.Y + 0.6, max.Z) + Vector3.new(0.05, 0, 0.05), P.Trim, Enum.Material.Wood)
		base.CanCollide = false
	end
	local function box(name: string, x1: number, z1: number, x2: number, z2: number, height: number, color: Color3, material: Enum.Material): Part
		return map:Box(name, at(x1, 0, z1), at(x2, height, z2), color, material)
	end

	-- Corridor: from the lobby's doorway to the range
	local halfZ = Lobby.HalfZ
	map:Floor("Floor", o.X + door.x1 - 1, o.Z + halfZ, o.X + door.x2 + 1, o.Z + ROOM.z1, o.Y, 1, P.Carpet, Enum.Material.Carpet)
	map:Floor("Ceiling", o.X + door.x1 - 1, o.Z + halfZ + 0.5, o.X + door.x2 + 1, o.Z + ROOM.z1 - 0.5, o.Y + door.top + 1, 1, P.Plaster, Enum.Material.Plaster)
	for _, x in { door.x1 - 0.5, door.x2 + 0.5 } do
		map:Wall("Wall", o.X + x, o.Z + halfZ + 0.5, o.X + x, o.Z + ROOM.z1 - 0.5, o.Y, door.top, nil, P.Plaster, Enum.Material.Plaster)
	end
	band(at(door.x1, 0, halfZ + 0.5), at(door.x1 + 0.2, 4, ROOM.z1 - 0.5))
	band(at(door.x2 - 0.2, 0, halfZ + 0.5), at(door.x2, 4, ROOM.z1 - 0.5))
	map:Light(at((door.x1 + door.x2) / 2, door.top - 0.2, (halfZ + ROOM.z1) / 2), 18, Lobby.LightBrightness)

	-- The room: concrete floor, the lobby's plaster walls and wainscot, ceiling lights
	map:Floor("Floor", o.X + ROOM.x1, o.Z + ROOM.z1, o.X + ROOM.x2, o.Z + ROOM.z2, o.Y, 1, FLOOR, Enum.Material.Concrete)
	map:Floor("Ceiling", o.X + ROOM.x1 - 1, o.Z + ROOM.z1 - 1, o.X + ROOM.x2 + 1, o.Z + ROOM.z2 + 1, o.Y + ROOM_HEIGHT + 1, 1, P.Plaster, Enum.Material.Plaster)
	local doorway = { { from = door.x1 - ROOM.x1, to = door.x2 - ROOM.x1, top = door.top } }
	map:Wall("Wall", o.X + ROOM.x1, o.Z + ROOM.z1, o.X + ROOM.x2, o.Z + ROOM.z1, o.Y, ROOM_HEIGHT, doorway, P.Plaster, Enum.Material.Plaster)
	map:Wall("Wall", o.X + ROOM.x1, o.Z + ROOM.z2, o.X + ROOM.x2, o.Z + ROOM.z2, o.Y, ROOM_HEIGHT, nil, P.Plaster, Enum.Material.Plaster)
	map:Wall("Wall", o.X + ROOM.x1, o.Z + ROOM.z1, o.X + ROOM.x1, o.Z + ROOM.z2, o.Y, ROOM_HEIGHT, nil, P.Plaster, Enum.Material.Plaster)
	map:Wall("Wall", o.X + ROOM.x2, o.Z + ROOM.z1, o.X + ROOM.x2, o.Z + ROOM.z2, o.Y, ROOM_HEIGHT, nil, P.Plaster, Enum.Material.Plaster)
	local inset = 0.5 -- (the walls' inside faces)
	band(at(ROOM.x1 + inset, 0, ROOM.z1 + inset), at(door.x1, 4, ROOM.z1 + inset + 0.2))
	band(at(door.x2, 0, ROOM.z1 + inset), at(ROOM.x2 - inset, 4, ROOM.z1 + inset + 0.2))
	band(at(ROOM.x1 + inset, 0, ROOM.z2 - inset - 0.2), at(ROOM.x2 - inset, 4, ROOM.z2 - inset))
	band(at(ROOM.x1 + inset, 0, ROOM.z1 + inset), at(ROOM.x1 + inset + 0.2, 4, ROOM.z2 - inset))
	band(at(ROOM.x2 - inset - 0.2, 0, ROOM.z1 + inset), at(ROOM.x2 - inset, 4, ROOM.z2 - inset))
	local lights = {
		{ -12, 53 }, { 14, 53 }, { 33, 52 }, -- entry, firing line
		{ -21, 79 }, { 6, 79 }, { -21, 113 }, { 6, 113 }, -- kill house rooms
		{ 33, 70 }, { 33, 90 }, { 33, 110 }, { 33, 126 }, -- down the lane
	}
	for _, spot in lights do
		map:Light(at(spot[1], ROOM_HEIGHT - 0.2, spot[2]), 28, Lobby.LightBrightness)
	end

	-- Signs: PRACTICE RANGE over the doorway (lobby side), the way back over it (range side)
	local doorX = (door.x1 + door.x2) / 2
	sign(map, at(doorX, door.top + 2.4, halfZ - 0.6), Vector2.new(door.x2 - door.x1 + 6, 3), Enum.NormalId.Front, "PRACTICE RANGE", "SHOOT THE BOTS")
	sign(map, at(doorX, door.top + 1.6, ROOM.z1 + 0.6), Vector2.new(door.x2 - door.x1, 1.6), Enum.NormalId.Back, "LOBBY")

	-- THE LANE (east): firing line counter, distance lines and plates, cover, a backstop
	map:Wall("LaneWall", o.X + LANE_X, o.Z + FIRING_LINE, o.X + LANE_X, o.Z + ROOM.z2, o.Y, HOUSE_WALL, nil, DIVIDER, Enum.Material.Concrete)
	for _, span in { { LANE_X + 0.5, 30 }, { 34, ROOM.x2 - inset } } do
		box("Counter", span[1], FIRING_LINE - 1.5, span[2], FIRING_LINE, 3.4, P.Trim, Enum.Material.Wood)
		map:Box("CounterTop", at(span[1], 3.4, FIRING_LINE - 1.7), at(span[2], 3.6, FIRING_LINE + 0.2), P.Panel, Enum.Material.WoodPlanks)
	end
	local function paint(z: number)
		local stripe = map:Box("Stripe", at(LANE_X + 0.5, 0, z - 0.2), at(ROOM.x2 - inset, 0.04, z + 0.2), P.Accent, Enum.Material.SmoothPlastic)
		stripe.CanCollide = false
		stripe.CanQuery = false
	end
	paint(FIRING_LINE + 0.4)
	for _, distance in MARKERS do
		local z = FIRING_LINE + distance
		paint(z)
		sign(map, at(ROOM.x2 - inset - 0.5, 7, z), Vector2.new(3.2, 2.4), Enum.NormalId.Left, tostring(distance), "STUDS")
		sign(map, at(LANE_X + 0.5 + 0.5, 7, z), Vector2.new(3.2, 2.4), Enum.NormalId.Right, tostring(distance), "STUDS")
	end
	box("Backstop", LANE_X + 0.5, ROOM.z2 - 4.5, ROOM.x2 - inset, ROOM.z2 - inset, 9, BACKSTOP, Enum.Material.Rubber)
	box("Crate", 24, 72, 28, 76, 4.5, PLYWOOD, Enum.Material.WoodPlanks)
	box("LowWall", 34, 90, 42, 91, 3.6, BRICK, Enum.Material.Brick)
	box("Pillar", 22.5, 100, 27.5, 101, 8, DIVIDER, Enum.Material.Concrete)
	box("Crate", 36, 112, 40, 116, 4.5, PLYWOOD, Enum.Material.WoodPlanks)
	map:Box("Crate", at(36.5, 4.5, 112.5), at(39.5, 7.5, 115.5), PLYWOOD, Enum.Material.WoodPlanks)
	box("LowWall", 26, 121, 32, 122, 3.6, BRICK, Enum.Material.Brick)

	-- THE KILL HOUSE (west): four plywood rooms, doorways to come around
	local function houseWall(x1: number, z1: number, x2: number, z2: number, doors: { { number } })
		local openings = {}
		local start = if z1 == z2 then math.min(x1, x2) else math.min(z1, z2)
		for _, d in doors do
			table.insert(openings, { from = d[1] - start, to = d[2] - start, top = HOUSE_DOOR })
		end
		map:Wall("HouseWall", o.X + x1, o.Z + z1, o.X + x2, o.Z + z2, o.Y, HOUSE_WALL, openings, PLYWOOD, Enum.Material.WoodPlanks)
	end
	houseWall(ROOM.x1, HOUSE_FRONT, LANE_X, HOUSE_FRONT, { { -22, -17 }, { 3, 8 } })
	houseWall(HOUSE_MID_X, HOUSE_FRONT, HOUSE_MID_X, ROOM.z2, { { 76, 81 }, { 110, 115 } })
	houseWall(ROOM.x1, HOUSE_MID_Z, HOUSE_MID_X, HOUSE_MID_Z, { { -25, -20 } })
	houseWall(HOUSE_MID_X, HOUSE_MID_Z, LANE_X, HOUSE_MID_Z, { { 4, 9 } })
	box("Crate", -30, 68, -26, 72, 4, PLYWOOD, Enum.Material.WoodPlanks)
	box("LowWall", -22, 86, -13, 87, 3.4, BRICK, Enum.Material.Brick)
	box("Crate", 10, 70, 14, 74, 4, PLYWOOD, Enum.Material.WoodPlanks)
	box("LowWall", -2, 86, 7, 87, 3.4, BRICK, Enum.Material.Brick)
	box("Crate", -30, 120, -26, 124, 4, PLYWOOD, Enum.Material.WoodPlanks)
	box("Crate", -17, 104, -13, 108, 4.5, PLYWOOD, Enum.Material.WoodPlanks)
	box("LowWall", 0, 118, 10, 119, 3.4, BRICK, Enum.Material.Brick)
	box("Crate", 12, 102, 16, 106, 4.5, PLYWOOD, Enum.Material.WoodPlanks)

	-- Where the bots walk: plain spots to stop and look around, and cover spots (tucked in behind
	-- something) with the spots beside it to peek out from
	local function cover(x: number, z: number, peeks: { { number } }): PracticeBots.Point
		local list = {}
		for _, p in peeks do
			table.insert(list, flat(p[1], p[2]))
		end
		return { at = flat(x, z), peeks = list }
	end
	local function spot(x: number, z: number): PracticeBots.Point
		return { at = flat(x, z) }
	end
	local areas: { PracticeBots.Area } = {
		{ -- the lane
			count = 2,
			points = {
				spot(32, 68), spot(42, 80), spot(31, 86), spot(44, 100), spot(32, 108), spot(25, 114), spot(42, 125),
				cover(26, 79, { { 22.2, 79 }, { 30, 79 } }),
				cover(38, 93.5, { { 32, 93.5 }, { 44, 93.5 } }),
				cover(25, 103.5, { { 29.8, 103.5 } }),
				cover(38, 119, { { 34, 119 }, { 42, 119 } }),
				cover(29, 124.5, { { 24, 124.5 }, { 34, 124.5 } }),
			},
		},
		{ -- the kill house
			count = 3,
			points = {
				spot(-21, 76), spot(-30, 92), spot(2, 74), spot(16, 90), spot(-24, 112), spot(-30, 128), spot(2, 106), spot(16, 126),
				cover(-17.5, 89.5, { { -24.5, 89.5 }, { -10.5, 89.5 } }),
				cover(2.5, 89.5, { { -4.5, 89.5 }, { 9.5, 89.5 } }),
				cover(-15, 110.5, { { -19.5, 110.5 }, { -10.5, 110.5 } }),
				cover(5, 121.5, { { -2, 121.5 }, { 12, 121.5 } }),
			},
		},
	}

	-- Keeps the bots in: an invisible wall across the way out that only they bump into
	local botWall = map:Box("BotWall", at(door.x1, 0, ROOM.z1 + 0.5), at(door.x2, door.top, ROOM.z1 + 1.5), P.Trim)
	botWall.Transparency = 1
	botWall.CanQuery = false
	botWall.CanTouch = false
	botWall.CollisionGroup = PracticeBots.WallGroup

	-- The zone: inside this box you're in the range (the corridor isn't)
	local zonePart = map:Box("Zone", at(ROOM.x1 + inset, -2, ROOM.z1 + inset), at(ROOM.x2 - inset, ROOM_HEIGHT + 2, ROOM.z2 - inset), P.Trim)
	zonePart.Transparency = 1
	zonePart.CanCollide = false
	zonePart.CanQuery = false
	zonePart.CanTouch = false
	zonePart.Parent = map.model -- (the client looks for PracticeRange.Zone)

	-- Where you're put back on your feet if the bots get you: just inside, facing down the range
	local entrance = CFrame.lookAt(flat(doorX, ROOM.z1 + 4), flat(doorX, ROOM.z1 + 5))
	return map.model, areas, entrance
end

local function contains(position: Vector3): boolean
	if not zone then
		return false
	end
	local p = zone.CFrame:PointToObjectSpace(position)
	local half = zone.Size / 2
	return math.abs(p.X) <= half.X and math.abs(p.Y) <= half.Y and math.abs(p.Z) <= half.Z
end

-- In the lobby, alive and standing inside the zone
local function isInside(player: Player): boolean
	if player:GetAttribute("Location") ~= "Lobby" then
		return false
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return humanoid ~= nil and humanoid.Health > 0 and root ~= nil and contains(root.Position)
end

local function heal(player: Player)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		humanoid.Health = humanoid.MaxHealth
	end
end

-- Bots and walls that only bots bump into. Raycasts use the Default group, so bullets and
-- line-of-sight checks go straight through the bot wall (like MapService's railing guards).
local function setUpCollisionGroups()
	PhysicsService:RegisterCollisionGroup(PracticeBots.Group)
	PhysicsService:RegisterCollisionGroup(PracticeBots.WallGroup)
	for _, group in PhysicsService:GetRegisteredCollisionGroups() do
		if group.name ~= PracticeBots.Group then
			PhysicsService:CollisionGroupSetCollidable(PracticeBots.WallGroup, group.name, false)
		end
	end
end

function PracticeRange.Start()
	-- The bots' shots and "you got downed" (client PracticeRange). Made on every server so the
	-- client always finds it.
	local remote = Instance.new("RemoteEvent")
	remote.Name = "Practice"
	remote.Parent = ReplicatedStorage:WaitForChild("Remotes")

	if RoundService.IsMatchServer() then
		return -- match servers: the doorway stays plugged, no range, no bots
	end
	local lobby = Workspace:FindFirstChild("Lobby")
	local plug = lobby and lobby:FindFirstChild("RangeDoorPlug", true)
	if not lobby or not plug then
		return
	end

	setUpCollisionGroups()
	local model, areas, entrance = build()
	MapCleanup.Run(model)
	plug:Destroy()
	model.Parent = Workspace
	zone = model:FindFirstChild("Zone") :: BasePart

	PracticeBots.Start({ areas = areas, entrance = entrance, contains = contains, remote = remote, attribute = PracticeRange.Attribute })

	task.spawn(function()
		local lastOccupied = -math.huge
		while true do
			local anyone = false
			for _, player in Players:GetPlayers() do
				local inside = isInside(player)
				anyone = anyone or inside
				if (player:GetAttribute(PracticeRange.Attribute) == true) ~= inside then
					player:SetAttribute(PracticeRange.Attribute, if inside then true else nil)
					if not inside then
						heal(player) -- (whatever the bots did stays in the range)
					end
				end
			end
			if anyone then
				lastOccupied = os.clock()
				PracticeBots.SetActive(true)
			elseif os.clock() - lastOccupied > IDLE_TIME then
				PracticeBots.SetActive(false)
			end
			task.wait(CHECK_EVERY)
		end
	end)
end

return PracticeRange
