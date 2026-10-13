-- LOBBY — where everyone waits between matches, in third person (so you can see your own
-- character). It floats high above the play area so it never overlaps a map.
-- You queue for a match from here with the PLAY menu (client MainMenu, server Matchmaker).
--
--   ┌──────────────────────────────── north (screens) ─────────────────────────────┐
--   │  couches                                                         couches     │
--   │                     movement course: crates, low wall, ramp                  │
--   │                                  spawn                                       │
--   └──────────────────────────────────────────────────────[range door]────────────┘
--   (east wall: the leaderboard, top 10 for kills / wins / level: LeaderboardService)
--   (south wall: the doorway to the PRACTICE RANGE. Built plugged ("RangeDoorPlug"); on lobby
--   servers PracticeRange removes the plug and builds the range behind it)

local MapBuilder = require(script.Parent.MapBuilder)

local Lobby = {}

Lobby.Origin = Vector3.new(0, 400, 0) -- center of the floor

local WALL = 18
local HALF_X, HALF_Z = 45, 35

local CARPET = Color3.fromRGB(58, 62, 74)
local PANEL = Color3.fromRGB(110, 78, 52)
local PLASTER = Color3.fromRGB(184, 178, 168) -- (a pale plaster bounced so much light the room glared)
local TRIM = Color3.fromRGB(40, 42, 48)
local FABRIC = Color3.fromRGB(70, 80, 105)
local SCREEN = Color3.fromRGB(14, 16, 20)
local ACCENT = Color3.fromRGB(255, 170, 60)
local LIGHT_BRIGHTNESS = 0.7 -- the ceiling lights overlap a lot; at full strength the room was too bright

-- For the practice range (PracticeRange), so it looks like it belongs to the lobby
Lobby.HalfZ = HALF_Z
Lobby.Palette = { Carpet = CARPET, Panel = PANEL, Plaster = PLASTER, Trim = TRIM, Screen = SCREEN, Accent = ACCENT }
Lobby.LightBrightness = LIGHT_BRIGHTNESS
-- The range doorway in the south wall: x1..x2 across (from the center), `top` studs high
Lobby.RangeDoor = { x1 = 10, x2 = 18, top = 10 }

local function screen(map: MapBuilder.Builder, center: Vector3, width: number, title: string, subtitle: string)
	map:Box("ScreenFrame", center - Vector3.new(width / 2 + 0.3, 3.3, 0.5), center + Vector3.new(width / 2 + 0.3, 3.3, 0), TRIM, Enum.Material.Metal)
	-- The glass sits just in front of (south of) the frame, facing into the room
	local panel = map:Box("Screen", center - Vector3.new(width / 2, 3, 0), center + Vector3.new(width / 2, 3, 0.15), SCREEN, Enum.Material.Glass)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back -- faces into the room (south, +Z)
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Parent = panel
	local function label(text: string, size: number, y: number, color: Color3)
		local l = Instance.new("TextLabel")
		l.AnchorPoint = Vector2.new(0.5, 0.5)
		l.Position = UDim2.fromScale(0.5, y)
		l.Size = UDim2.fromScale(0.95, 0.3)
		l.BackgroundTransparency = 1
		l.Font = Enum.Font.Michroma
		l.TextScaled = true
		l.Text = text
		l.TextColor3 = color
		l.Parent = gui
		local limit = Instance.new("UITextSizeConstraint")
		limit.MaxTextSize = size
		limit.Parent = l
	end
	label(title, 90, 0.4, Color3.new(1, 1, 1))
	label(subtitle, 40, 0.72, ACCENT)
end

-- The leaderboard on the east wall: top 10 for kills, wins, level and ranked MMR, side by side.
-- Built empty; LeaderboardService fills it in (it looks for "Leaderboard" → "Board" → Kills /
-- Wins / Level / Ranked → Row1..Row10 → Face / Who / Value, and "Status").
local BOARD_ROWS = 10
local BOARD_COLUMNS = { { "Kills", "MOST KILLS" }, { "Wins", "MOST WINS" }, { "Level", "HIGHEST LEVEL" }, { "Ranked", "TOP RANKED" } }

local function leaderboard(map: MapBuilder.Builder, center: Vector3, width: number, height: number)
	-- Frame against the wall, glass just in front of it (west), facing into the room
	map:Box("BoardFrame", center + Vector3.new(0, -height / 2 - 0.3, -width / 2 - 0.3), center + Vector3.new(0.5, height / 2 + 0.3, width / 2 + 0.3), TRIM, Enum.Material.Metal)
	local panel = map:Box("Leaderboard", center + Vector3.new(-0.15, -height / 2, -width / 2), center + Vector3.new(0, height / 2, width / 2), SCREEN, Enum.Material.Glass)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Board"
	gui.Face = Enum.NormalId.Left -- faces into the room (west, -X)
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Parent = panel
	local function label(parent: Instance, name: string, text: string, position: UDim2, size: UDim2, color: Color3, font: Enum.Font): TextLabel
		local l = Instance.new("TextLabel")
		l.Name = name
		l.Position = position
		l.Size = size
		l.BackgroundTransparency = 1
		l.Font = font
		l.TextScaled = true
		l.Text = text
		l.TextColor3 = color
		l.Parent = parent
		return l
	end
	label(gui, "Title", "TOP OPERATORS", UDim2.fromScale(0.05, 0.02), UDim2.fromScale(0.9, 0.11), Color3.new(1, 1, 1), Enum.Font.Michroma)
	label(gui, "Status", "LOADING...", UDim2.fromScale(0.05, 0.93), UDim2.fromScale(0.9, 0.05), Color3.fromRGB(150, 156, 170), Enum.Font.Michroma)
	for i, info in BOARD_COLUMNS do
		local column = Instance.new("Frame")
		column.Name = info[1]
		column.Position = UDim2.fromScale(0.02 + (i - 1) * 0.245, 0.15)
		column.Size = UDim2.fromScale(0.235, 0.77)
		column.BackgroundTransparency = 1
		column.Parent = gui
		label(column, "Heading", info[2], UDim2.new(), UDim2.fromScale(1, 0.09), ACCENT, Enum.Font.Michroma)
		for r = 1, BOARD_ROWS do
			local row = Instance.new("Frame")
			row.Name = "Row" .. r
			row.Position = UDim2.fromScale(0, 0.1 + (r - 1) * 0.09)
			row.Size = UDim2.fromScale(1, 0.085)
			row.BackgroundColor3 = Color3.new(1, 1, 1)
			row.BackgroundTransparency = if r % 2 == 1 then 0.94 else 1
			row.BorderSizePixel = 0
			row.Visible = false
			row.Parent = column
			local rankColor = if r == 1 then ACCENT elseif r <= 3 then Color3.fromRGB(215, 220, 230) else Color3.fromRGB(150, 156, 170)
			label(row, "Rank", tostring(r), UDim2.fromScale(0, 0.1), UDim2.fromScale(0.09, 0.8), rankColor, Enum.Font.GothamBold)
			local face = Instance.new("ImageLabel")
			face.Name = "Face"
			face.Position = UDim2.fromScale(0.1, 0.05)
			face.Size = UDim2.fromScale(0.1, 0.9)
			face.BackgroundTransparency = 1
			face.Parent = row
			local aspect = Instance.new("UIAspectRatioConstraint")
			aspect.Parent = face
			local who = label(row, "Who", "", UDim2.fromScale(0.22, 0.12), UDim2.fromScale(0.56, 0.76), Color3.new(1, 1, 1), Enum.Font.GothamBold)
			who.TextXAlignment = Enum.TextXAlignment.Left
			local value = label(row, "Value", "", UDim2.fromScale(0.78, 0.12), UDim2.fromScale(0.21, 0.76), ACCENT, Enum.Font.GothamBold)
			value.TextXAlignment = Enum.TextXAlignment.Right
		end
	end
end

local function couch(map: MapBuilder.Builder, center: Vector3, facingSouth: boolean)
	local dz = if facingSouth then 1 else -1
	map:Box("Couch", center - Vector3.new(4, 0, 1.5), center + Vector3.new(4, 1.6, 1.5), FABRIC, Enum.Material.Fabric)
	map:Box("CouchBack", center + Vector3.new(-4, 0, -1.5 * dz) - Vector3.new(0, 0, 0.5), center + Vector3.new(4, 3.2, -1.5 * dz + 0.5), FABRIC, Enum.Material.Fabric)
	map:Box("CouchArm", center + Vector3.new(-4.6, 0, -1.5), center + Vector3.new(-3.8, 2.3, 1.5), FABRIC, Enum.Material.Fabric)
	map:Box("CouchArm", center + Vector3.new(3.8, 0, -1.5), center + Vector3.new(4.6, 2.3, 1.5), FABRIC, Enum.Material.Fabric)
end

function Lobby.Build(): Model
	local map = MapBuilder.new("Lobby")
	local o = Lobby.Origin
	local function at(x: number, y: number, z: number): Vector3
		return o + Vector3.new(x, y, z)
	end

	-- Shell: carpet floor, plaster walls with a wood panel band, dark trim, ceiling
	map:Floor("Floor", o.X - HALF_X, o.Z - HALF_Z, o.X + HALF_X, o.Z + HALF_Z, o.Y, 1, CARPET, Enum.Material.Carpet)
	map:Floor("Ceiling", o.X - HALF_X - 1, o.Z - HALF_Z - 1, o.X + HALF_X + 1, o.Z + HALF_Z + 1, o.Y + WALL + 1, 1, PLASTER, Enum.Material.Plaster)
	map:Wall("Wall", o.X - HALF_X, o.Z - HALF_Z, o.X + HALF_X, o.Z - HALF_Z, o.Y, WALL, nil, PLASTER, Enum.Material.Plaster)
	local door = Lobby.RangeDoor
	map:Wall("Wall", o.X - HALF_X, o.Z + HALF_Z, o.X + HALF_X, o.Z + HALF_Z, o.Y, WALL, { { from = HALF_X + door.x1, to = HALF_X + door.x2, top = door.top } }, PLASTER, Enum.Material.Plaster)
	map:Wall("Wall", o.X - HALF_X, o.Z - HALF_Z, o.X - HALF_X, o.Z + HALF_Z, o.Y, WALL, nil, PLASTER, Enum.Material.Plaster)
	map:Wall("Wall", o.X + HALF_X, o.Z - HALF_Z, o.X + HALF_X, o.Z + HALF_Z, o.Y, WALL, nil, PLASTER, Enum.Material.Plaster)
	for _, side in { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } } do
		-- Wood wainscoting band and a dark baseboard just inside each wall
		local sx, sz = side[1], side[2]
		local inset = 0.6
		local min, max
		if sx ~= 0 then
			local x = o.X + sx * (HALF_X - inset)
			min, max = Vector3.new(x - 0.1, o.Y, o.Z - HALF_Z), Vector3.new(x + 0.1, o.Y + 4, o.Z + HALF_Z)
		else
			local z = o.Z + sz * (HALF_Z - inset)
			min, max = Vector3.new(o.X - HALF_X, o.Y, z - 0.1), Vector3.new(o.X + HALF_X, o.Y + 4, z + 0.1)
		end
		-- (the south one stops either side of the range doorway; the plug below fills the gap)
		local spans = { { min, max } }
		if sz == 1 then
			spans = { { min, Vector3.new(o.X + door.x1, max.Y, max.Z) }, { Vector3.new(o.X + door.x2, min.Y, min.Z), max } }
		end
		for _, span in spans do
			local band = map:Box("Wainscot", span[1], span[2], PANEL, Enum.Material.WoodPlanks)
			band.CanCollide = false
			local base = map:Box("Baseboard", span[1], Vector3.new(span[2].X, o.Y + 0.6, span[2].Z) + Vector3.new(0.05, 0, 0.05), TRIM, Enum.Material.Wood)
			base.CanCollide = false
		end
	end

	-- The range doorway starts walled up (wall, wainscot and baseboard, like the rest of the wall).
	-- PracticeRange removes this on lobby servers; match servers have no range behind it.
	local plug = Instance.new("Model")
	plug.Name = "RangeDoorPlug"
	plug.Parent = map.model
	local plugWall = map:Box("Wall", at(door.x1, 0, HALF_Z - 0.5), at(door.x2, door.top, HALF_Z + 0.5), PLASTER, Enum.Material.Plaster)
	local plugBand = map:Box("Wainscot", at(door.x1, 0, HALF_Z - 0.7), at(door.x2, 4, HALF_Z - 0.5), PANEL, Enum.Material.WoodPlanks)
	local plugBase = map:Box("Baseboard", at(door.x1, 0, HALF_Z - 0.7), at(door.x2, 0.6, HALF_Z - 0.45), TRIM, Enum.Material.Wood)
	plugBand.CanCollide = false
	plugBase.CanCollide = false
	for _, part in { plugWall, plugBand, plugBase } do
		part.Parent = plug
	end

	-- Ceiling lights in a grid
	for x = -30, 30, 20 do
		for z = -20, 20, 20 do
			map:Light(at(x, WALL - 0.2, z), 28, LIGHT_BRIGHTNESS)
		end
	end

	-- Screens on the north wall (voting will go here later)
	screen(map, at(0, 10, -HALF_Z + 0.6), 26, "BREACHPOINT", "PRESS PLAY TO FIND A MATCH")
	screen(map, at(-28, 9, -HALF_Z + 0.6), 12, "MODES", "1v1 · 2v2 · 3v3 · 4v4")
	screen(map, at(28, 9, -HALF_Z + 0.6), 12, "MAPS", "VOTED IN EVERY MATCH")
	-- Leaderboard on the east wall (LeaderboardService fills it in)
	leaderboard(map, at(HALF_X - 0.6, 10.5, 0), 34, 13)

	-- Lounge corners
	couch(map, at(-32, 0, -22), true)
	couch(map, at(32, 0, -22), true)
	map:Box("Rug", at(-38, 0, -28), at(-26, 0.05, -14), Color3.fromRGB(120, 60, 50), Enum.Material.Fabric).CanCollide = false
	map:Box("Rug", at(26, 0, -28), at(38, 0.05, -14), Color3.fromRGB(120, 60, 50), Enum.Material.Fabric).CanCollide = false

	-- Movement course to try every animation on yourself: crates to climb and jump, a low wall
	-- to crouch behind, a ramp, a long open lane to slide down, two tall walls to wall-jump between
	local CRATE = Color3.fromRGB(150, 115, 70)
	map:Box("Crate", at(-14, 0, -6), at(-10, 4, -2), CRATE, Enum.Material.WoodPlanks)
	map:Box("Crate", at(-10, 0, -6), at(-6, 2.5, -2), CRATE, Enum.Material.WoodPlanks)
	map:Box("Crate", at(-14, 4, -6), at(-11, 7, -3), CRATE, Enum.Material.WoodPlanks)
	map:Box("LowWall", at(4, 0, -4), at(16, 3.2, -3), Color3.fromRGB(150, 88, 70), Enum.Material.Brick)
	local rampLength = 16
	map:Part("Ramp", Vector3.new(8, 0.6, rampLength), CFrame.new(at(30, 2.4, 10)) * CFrame.Angles(math.rad(17), 0, 0), Color3.fromRGB(120, 125, 130), Enum.Material.DiamondPlate)
	map:Box("RampTop", at(26, 0, -6), at(34, 4.8, 2.6), Color3.fromRGB(120, 125, 130), Enum.Material.DiamondPlate)
	-- (painted, not neon: a long glowing strip bloomed across half the room)
	map:Box("SlideLane", at(-40, 0.02, 4), at(-4, 0.06, 10), Color3.fromRGB(205, 130, 50), Enum.Material.SmoothPlastic).CanCollide = false
	map:Box("WallJumpWall", at(-42, 0, 14), at(-41, WALL, 30), PLASTER, Enum.Material.Concrete)
	map:Box("WallJumpWall", at(-27, 0, 14), at(-26, WALL, 30), PLASTER, Enum.Material.Concrete)

	-- Where players appear (RoundService moves them here)
	local spawn = map:Box("LobbySpawn", at(-4, 0, 20), at(4, 0.08, 28), ACCENT, Enum.Material.Neon)
	spawn.CanCollide = false
	spawn.Transparency = 0.7

	return map.model
end

return Lobby
