-- LOBBY — where everyone waits between matches, in third person (so you can see your own
-- character). It floats high above the play area so it never overlaps a map.
-- You queue for a match from here with the PLAY menu (client MainMenu, server Matchmaker).
--
--   ┌──────────────────────────────── north (screens) ─────────────────────────────┐
--   │  couches                                                         couches     │
--   │                     movement course: crates, low wall, ramp                  │
--   │                                  spawn                                       │
--   └──────────────────────────────────────────────────────────────────────────────┘

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
	map:Wall("Wall", o.X - HALF_X, o.Z + HALF_Z, o.X + HALF_X, o.Z + HALF_Z, o.Y, WALL, nil, PLASTER, Enum.Material.Plaster)
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
		local band = map:Box("Wainscot", min, max, PANEL, Enum.Material.WoodPlanks)
		band.CanCollide = false
		local base = map:Box("Baseboard", min, Vector3.new(max.X, o.Y + 0.6, max.Z) + Vector3.new(0.05, 0, 0.05), TRIM, Enum.Material.Wood)
		base.CanCollide = false
	end

	-- Ceiling lights in a grid
	for x = -30, 30, 20 do
		for z = -20, 20, 20 do
			map:Light(at(x, WALL - 0.2, z), 28, LIGHT_BRIGHTNESS)
		end
	end

	-- Screens on the north wall (voting will go here later)
	screen(map, at(0, 10, -HALF_Z + 0.6), 26, "BREACH ROULETTE", "PRESS PLAY TO FIND A MATCH")
	screen(map, at(-28, 9, -HALF_Z + 0.6), 12, "MODES", "1v1 · 2v2 · 3v3 · 4v4")
	screen(map, at(28, 9, -HALF_Z + 0.6), 12, "MAPS", "VOTED IN EVERY MATCH")

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
