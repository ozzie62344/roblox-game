-- Helpers for building maps out of parts in code: floors, walls with door/window openings,
-- stairs, railings, props, lights, plus the gameplay markers (spawn pads, plant sites).
-- Coordinates are in studs. Walls are axis-aligned.
-- RoomWall also does the Siege dressing: soft walls get Breakable = "Soft" (DestructionService),
-- doorways and windows get trim and a barricade slot (FortifyService), outside windows get glass.
-- Hatch makes trapdoors in floors.

local MapBuilder = {}
MapBuilder.__index = MapBuilder

export type Opening = {
	from: number, -- start along the wall
	to: number, -- end along the wall
	bottom: number?, -- height above the wall's base (0 = door)
	top: number, -- height above the wall's base
	kind: ("Door" | "Window" | "Arch")?, -- RoomWall: trim, plus a barricade slot for doors / windows
}

-- How a RoomWall looks and behaves
export type Style = {
	color: Color3,
	material: Enum.Material?,
	soft: boolean?, -- drywall / siding: can be shot through, breached and reinforced
	exterior: boolean?, -- outside wall: windows get glass, doorways / windows start barricaded
}

export type Builder = typeof(setmetatable(
	{} :: { model: Model, geometry: Folder, spawns: Folder, objectives: Folder },
	MapBuilder
))

local TRIM_COLOR = Color3.fromRGB(238, 234, 224)
local GLASS_COLOR = Color3.fromRGB(170, 200, 215)
local RAIL_COLOR = Color3.fromRGB(95, 66, 45)
local HATCH_COLOR = Color3.fromRGB(120, 86, 56)
local CASING = 0.45 -- width of the trim around doorways and windows
local RAIL_HEIGHT = 3.2
local DIRECTIONS = { ["+X"] = Vector3.xAxis, ["-X"] = -Vector3.xAxis, ["+Z"] = Vector3.zAxis, ["-Z"] = -Vector3.zAxis }

-- Looks only: nothing collides with it, and bullets / raycasts go straight through
local function cosmetic(part: BasePart): BasePart
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	return part
end

function MapBuilder.new(name: string): Builder
	local model = Instance.new("Model")
	model.Name = name
	local function folder(folderName: string): Folder
		local f = Instance.new("Folder")
		f.Name = folderName
		f.Parent = model
		return f
	end
	return setmetatable({
		model = model,
		geometry = folder("Geometry"),
		spawns = folder("TeamSpawns"), -- RoundService reads these
		objectives = folder("Objectives"), -- ObjectiveService reads these
	}, MapBuilder)
end

-- Folder in the map, made the first time it's asked for ("Trim", "Glass", "BarricadeSlots"...)
function MapBuilder.Folder(self: Builder, name: string): Folder
	local folder = self.model:FindFirstChild(name)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = self.model
	end
	return folder :: Folder
end

-- Plain anchored block
function MapBuilder.Part(self: Builder, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = self.geometry
	return part
end

-- Block given by two corners (min / max)
function MapBuilder.Box(self: Builder, name: string, min: Vector3, max: Vector3, color: Color3, material: Enum.Material?): Part
	return self:Part(name, max - min, CFrame.new((min + max) / 2), color, material)
end

-- Horizontal slab covering x1..x2, z1..z2, with its top at `y`
function MapBuilder.Floor(self: Builder, name: string, x1: number, z1: number, x2: number, z2: number, y: number, thickness: number, color: Color3, material: Enum.Material?): Part
	return self:Box(name, Vector3.new(x1, y - thickness, z1), Vector3.new(x2, y, z2), color, material)
end

-- Like Floor, but leaves rectangular holes (stairwells, voids). Each hole is { x1, z1, x2, z2 };
-- holes may overlap each other or stick out past the floor. Returns the pieces.
function MapBuilder.FloorWithHoles(self: Builder, name: string, x1: number, z1: number, x2: number, z2: number, holes: { { number } }, y: number, thickness: number, color: Color3, material: Enum.Material?): { Part }
	local clipped = {}
	local zs = { z1, z2 }
	for _, hole in holes do
		local hx1, hz1, hx2, hz2 = math.max(hole[1], x1), math.max(hole[2], z1), math.min(hole[3], x2), math.min(hole[4], z2)
		if hx1 < hx2 and hz1 < hz2 then
			table.insert(clipped, { hx1, hz1, hx2, hz2 })
			table.insert(zs, hz1)
			table.insert(zs, hz2)
		end
	end
	table.sort(zs)
	-- Strips between every hole edge along z; each strip is filled in between the holes crossing it
	local pieces = {}
	for i = 1, #zs - 1 do
		local za, zb = zs[i], zs[i + 1]
		if zb - za > 1e-3 then
			local crossing = {}
			for _, hole in clipped do
				if hole[2] < zb - 1e-3 and hole[4] > za + 1e-3 then
					table.insert(crossing, hole)
				end
			end
			table.sort(crossing, function(a, b)
				return a[1] < b[1]
			end)
			local x = x1
			for _, hole in crossing do
				if hole[1] > x then
					table.insert(pieces, self:Floor(name, x, za, hole[1], zb, y, thickness, color, material))
				end
				x = math.max(x, hole[3])
			end
			if x2 > x then
				table.insert(pieces, self:Floor(name, x, za, x2, zb, y, thickness, color, material))
			end
		end
	end
	return pieces
end

-- Axis-aligned wall from (x1, z1) to (x2, z2) (one of x or z must match), rising from `base` by
-- `height`, with openings cut out (doors: bottom = 0, windows: bottom > 0).
-- Opening positions are measured along the wall from its lower x / z end. Returns the pieces.
function MapBuilder.Wall(self: Builder, name: string, x1: number, z1: number, x2: number, z2: number, base: number, height: number, openings: { Opening }?, color: Color3, material: Enum.Material?, thickness: number?): { Part }
	local t = thickness or 1
	local alongX = z1 == z2
	local startPos = if alongX then math.min(x1, x2) else math.min(z1, z2)
	local length = if alongX then math.abs(x2 - x1) else math.abs(z2 - z1)
	local fixed = if alongX then z1 else x1
	local pieces = {}

	-- One wall piece covering [a, b] along the wall and [bottom, top] in height
	local function piece(a: number, b: number, bottom: number, top: number)
		if b - a < 0.01 or top - bottom < 0.01 then
			return
		end
		if alongX then
			table.insert(pieces, self:Box(name, Vector3.new(startPos + a, base + bottom, fixed - t / 2), Vector3.new(startPos + b, base + top, fixed + t / 2), color, material))
		else
			table.insert(pieces, self:Box(name, Vector3.new(fixed - t / 2, base + bottom, startPos + a), Vector3.new(fixed + t / 2, base + top, startPos + b), color, material))
		end
	end

	local sorted = table.clone(openings or {})
	table.sort(sorted, function(a, b)
		return a.from < b.from
	end)
	local cursor = 0
	for _, opening in sorted do
		piece(cursor, opening.from, 0, height) -- solid wall before the opening
		piece(opening.from, opening.to, 0, opening.bottom or 0) -- below (windows)
		piece(opening.from, opening.to, opening.top, height) -- above
		cursor = opening.to
	end
	piece(cursor, length, 0, height)
	return pieces
end

-- A 1-stud wall with the Siege dressing (see the top). Here openings are in world coordinates
-- along the wall (x for a wall along x, z for one along z). `inside` (+1 / -1) says which side is
-- indoors, across the wall: outside walls only get baseboards there, and the barricade goes on
-- that side of the glass.
function MapBuilder.RoomWall(self: Builder, style: Style, x1: number, z1: number, x2: number, z2: number, base: number, height: number, openings: { Opening }?, inside: number?)
	local alongX = z1 == z2
	local fixed = if alongX then z1 else x1
	local start = if alongX then math.min(x1, x2) else math.min(z1, z2)
	local half = 0.5 -- of the wall's thickness
	local trim = self:Folder("Trim")

	-- Box from a1..a2 along the wall (world), y1..y2 up, c1..c2 across it (from its centre line)
	local function box(name: string, a1: number, a2: number, y1: number, y2: number, c1: number, c2: number, color: Color3, material: Enum.Material, parent: Instance): Part
		local cMin, cMax = fixed + math.min(c1, c2), fixed + math.max(c1, c2)
		local part = if alongX
			then self:Box(name, Vector3.new(a1, y1, cMin), Vector3.new(a2, y2, cMax), color, material)
			else self:Box(name, Vector3.new(cMin, y1, a1), Vector3.new(cMax, y2, a2), color, material)
		part.Parent = parent
		return part
	end
	local function trimBox(name: string, a1: number, a2: number, y1: number, y2: number, c1: number, c2: number)
		cosmetic(box(name, a1, a2, y1, y2, c1, c2, TRIM_COLOR, Enum.Material.SmoothPlastic, trim))
	end

	local relative = {}
	for _, opening in openings or {} do
		table.insert(relative, { from = opening.from - start, to = opening.to - start, bottom = opening.bottom, top = opening.top })
	end
	local pieces = self:Wall(if style.exterior then "ExteriorWall" else "Wall", x1, z1, x2, z2, base, height, relative, style.color, style.material)

	local indoors = if style.exterior then { inside or 1 } else { 1, -1 }
	for _, piece in pieces do
		if style.soft then
			piece:SetAttribute("Breakable", "Soft")
		end
		-- Baseboards along every piece that stands on the floor
		if piece.Position.Y - piece.Size.Y / 2 < base + 0.01 then
			local mid = if alongX then piece.Position.X else piece.Position.Z
			local length = if alongX then piece.Size.X else piece.Size.Z
			for _, side in indoors do
				trimBox("Baseboard", mid - length / 2, mid + length / 2, base, base + 0.5, side * half, side * (half + 0.08))
			end
		end
	end

	for _, opening in openings or {} do
		local kind = opening.kind
		if not kind then
			continue -- a plain hole (garage door, void)
		end
		local a1, a2 = opening.from, opening.to
		local y1, y2 = base + (opening.bottom or 0), base + opening.top
		local low = if kind == "Window" then y1 - 0.2 else y1
		for _, side in { 1, -1 } do
			local c1, c2 = side * half, side * (half + 0.12)
			trimBox("Casing", a1 - CASING, a1, low, y2 + CASING, c1, c2)
			trimBox("Casing", a2, a2 + CASING, low, y2 + CASING, c1, c2)
			trimBox("Casing", a1 - CASING, a2 + CASING, y2, y2 + CASING, c1, c2)
		end
		if kind == "Window" then
			trimBox("Sill", a1 - CASING - 0.2, a2 + CASING + 0.2, y1 - 0.2, y1, -(half + 0.35), half + 0.35)
			if style.exterior then
				local glass = box("Glass", a1, a2, y1, y2, -0.06, 0.06, GLASS_COLOR, Enum.Material.Glass, self:Folder("Glass"))
				glass.Transparency = 0.55
				glass:SetAttribute("Breakable", "Glass")
			end
		end
		if kind ~= "Arch" then
			-- Where FortifyService puts the boards: indoors of the glass on outside walls
			local offset = if style.exterior then (inside or 1) * 0.3 else 0
			local slot = box("Slot", a1, a2, y1, y2, offset - 0.15, offset + 0.15, TRIM_COLOR, Enum.Material.SmoothPlastic, self:Folder("BarricadeSlots"))
			slot.Transparency = 1
			cosmetic(slot)
			slot:SetAttribute("Kind", kind)
			if style.exterior then
				slot:SetAttribute("Exterior", true)
			end
		end
	end
end

-- Straight flight filling x1..x2, z1..z2, climbing from y1 to y2 toward `toward` ("+X", "-X",
-- "+Z" or "-Z"). The steps are mostly for looks: you walk on an invisible wedge running just over
-- the treads, which also fills the space under the flight (nobody walks or shoots under it).
function MapBuilder.Stairs(self: Builder, x1: number, z1: number, x2: number, z2: number, y1: number, y2: number, toward: string, color: Color3, material: Enum.Material?)
	local dir = DIRECTIONS[toward]
	local alongZ = dir.X == 0
	local run = if alongZ then z2 - z1 else x2 - x1
	local width = if alongZ then x2 - x1 else z2 - z1
	local rise = y2 - y1
	local count = math.max(math.round(rise / 0.8), 1)
	local tread = run / count
	local bottom = Vector3.new((x1 + x2) / 2, y1, (z1 + z2) / 2) - dir * run / 2
	local frame = CFrame.lookAt(bottom, bottom + dir) -- forward (-Z) is up the flight
	for i = 1, count do
		local top = rise * i / count
		local step = self:Part("Step", Vector3.new(width, top, tread), frame * CFrame.new(0, top / 2, -(i - 0.5) * tread), color, material or Enum.Material.WoodPlanks)
		step.CanCollide = i == count -- the top step is flush with the floor above: walk straight on
	end
	local wedge = Instance.new("WedgePart")
	wedge.Name = "StairRamp"
	-- From half a tread before the first step up to the front edge of the (solid) top step, so the
	-- slope meets it flush: no lip at the top for a drone to catch on. Turned to climb forward.
	local length = run - tread / 2
	wedge.Size = Vector3.new(width, rise, length)
	wedge.CFrame = frame * CFrame.new(0, rise / 2, -(run - 1.5 * tread) / 2) * CFrame.Angles(0, math.pi, 0)
	wedge.Anchored = true
	wedge.Transparency = 1
	wedge.Parent = self.geometry
end

-- Balustrade from floor point `a` to floor point `b` (level, or up a flight of stairs): handrail,
-- posts and balusters you can see and shoot through, plus an invisible wall so nobody falls off.
function MapBuilder.Railing(self: Builder, a: Vector3, b: Vector3, color: Color3?)
	local railColor = color or RAIL_COLOR
	local up = Vector3.yAxis
	local length = (b - a).Magnitude
	local rail = self:Part("Handrail", Vector3.new(0.35, 0.25, length), CFrame.lookAt((a + b) / 2 + up * RAIL_HEIGHT, b + up * RAIL_HEIGHT), railColor, Enum.Material.Wood)
	cosmetic(rail)
	local count = math.max(math.floor(length / 1.2), 1)
	for i = 0, count do
		local post = i == 0 or i == count
		local height = if post then RAIL_HEIGHT + 0.5 else RAIL_HEIGHT
		local width = if post then 0.55 else 0.18
		local p = a:Lerp(b, i / count)
		cosmetic(self:Part(if post then "Post" else "Baluster", Vector3.new(width, height, width), CFrame.new(p + up * height / 2), railColor, Enum.Material.Wood))
	end
	-- (MapService puts guards in a collision group that only characters bump into: CanQuery =
	-- false does nothing on a part that collides, so that's what keeps bullets going through)
	local guard = self:Part("RailGuard", Vector3.new(0.3, RAIL_HEIGHT, length), CFrame.lookAt((a + b) / 2, b) * CFrame.new(0, RAIL_HEIGHT / 2, 0), railColor)
	guard.Transparency = 1
	guard.CanTouch = false
end

-- Trapdoor in a floor whose top is at `top`: a wooden cover over a size × size hole (the floor
-- itself must leave the hole, see FloorWithHoles). The knife or close shotgun blasts (5 hits) or
-- an explosive break the cover (DestructionService); defenders can reinforce it like a wall
-- section (FortifyService), and then only a hard breach opens it.
function MapBuilder.Hatch(self: Builder, x: number, z: number, top: number, size: number)
	local half = size / 2
	local cover = Instance.new("Model")
	cover.Name = "HatchCover"
	local boards = self:Box("Cover", Vector3.new(x - half, top - 0.4, z - half), Vector3.new(x + half, top, z + half), HATCH_COLOR, Enum.Material.WoodPlanks)
	boards:SetAttribute("Breakable", "Hatch")
	boards.Parent = cover
	cover.Parent = self:Folder("Hatches")
	-- Frame round the opening, flush on the floor
	local trim = self:Folder("Trim")
	for _, side in { -1, 1 } do
		cosmetic(self:Box("HatchFrame", Vector3.new(x - half - 0.3, top, z + side * half - 0.15), Vector3.new(x + half + 0.3, top + 0.06, z + side * half + 0.15), RAIL_COLOR, Enum.Material.Wood)).Parent = trim
		cosmetic(self:Box("HatchFrame", Vector3.new(x + side * half - 0.15, top, z - half), Vector3.new(x + side * half + 0.15, top + 0.06, z + half), RAIL_COLOR, Enum.Material.Wood)).Parent = trim
	end
	-- Where a reinforcement goes: the opening, from under the floor to just above it
	local slot = self:Box("Slot", Vector3.new(x - half, top - 1, z - half), Vector3.new(x + half, top + 0.5, z + half), HATCH_COLOR)
	slot.Transparency = 1
	cosmetic(slot)
	slot:SetAttribute("Hatch", true)
	slot.Parent = self:Folder("ReinforceSlots")
end

-- Ceiling light: a small glowing panel with a light under it
function MapBuilder.Light(self: Builder, position: Vector3, range: number?, brightness: number?)
	local panel = self:Part("Light", Vector3.new(2, 0.2, 2), CFrame.new(position), Color3.fromRGB(255, 244, 214), Enum.Material.Neon)
	panel.CanCollide = false
	panel.CastShadow = false
	local light = Instance.new("PointLight")
	light.Range = range or 26
	light.Brightness = brightness or 1.2
	light.Color = Color3.fromRGB(255, 236, 200)
	light.Shadows = true
	light.Parent = panel
end

-- Spawn pad for one side ("Attack" / "Defend"). Players spawn on it facing `facing`.
-- Defender pads can belong to a site pair: you spawn there when your team defends that pair.
function MapBuilder.SpawnPad(self: Builder, side: string, position: Vector3, facing: Vector3, pair: string?)
	local pad = Instance.new("Part")
	pad.Name = side .. "Spawn" .. (pair or "")
	pad.Size = Vector3.new(12, 0.2, 6)
	pad.CFrame = CFrame.lookAt(position, position + Vector3.new(facing.X, 0, facing.Z))
	pad.Anchored = true
	pad.CanCollide = false
	pad.CanQuery = false
	pad.Transparency = 0.6
	pad.Material = Enum.Material.Neon
	pad.Color = if side == "Attack" then Color3.fromRGB(220, 70, 70) else Color3.fromRGB(60, 130, 230)
	pad:SetAttribute("Side", side)
	pad:SetAttribute("Pair", pair)
	pad.Parent = self.spawns
end

-- Plant site zone (invisible box): attackers plant anywhere inside it. Maps with several site
-- pairs give each site its pair ("Basement") and room ("Gym"); defenders pick a pair each round.
function MapBuilder.Site(self: Builder, name: string, min: Vector3, max: Vector3, pair: string?, room: string?)
	local site = Instance.new("Part")
	site.Name = "Site" .. (pair or "") .. name
	site.Size = max - min
	site.CFrame = CFrame.new((min + max) / 2)
	site.Anchored = true
	site.CanCollide = false
	site.CanQuery = false
	site.CanTouch = false
	site.Transparency = 1
	site:SetAttribute("Site", name)
	site:SetAttribute("Pair", pair)
	site:SetAttribute("Room", room)
	site.Parent = self.objectives
end

-- Neutral spawn used between matches (free roam)
function MapBuilder.FreeRoamSpawn(self: Builder, position: Vector3)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "FreeRoamSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(8, 0.4, 8)
	spawn.CFrame = CFrame.new(position)
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Transparency = 0.5
	spawn.Parent = self.model
end

-- shortcut: self-check runs on require; move it to a test runner if one is added
do
	local test = MapBuilder.new("SelfCheck")
	-- Second hole sticks out past the floor: only its 2 × 3 inside part counts
	local pieces = test:FloorWithHoles("F", 0, 0, 10, 10, { { 2, 2, 4, 8 }, { 6, -5, 8, 3 } }, 0, 1, Color3.new(), nil)
	local area = 0
	for _, piece in pieces do
		area += piece.Size.X * piece.Size.Z
	end
	assert(math.abs(area - (100 - 12 - 6)) < 1e-6, "FloorWithHoles should leave the floor minus the holes")
	test.model:Destroy()
end

return MapBuilder
