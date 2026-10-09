-- Helpers for building maps out of parts in code: floors, walls with door/window openings,
-- stairs, props, lights, plus the gameplay markers (spawn pads, plant sites).
-- Coordinates are in studs. Walls are axis-aligned.

local MapBuilder = {}
MapBuilder.__index = MapBuilder

export type Opening = {
	from: number, -- start along the wall
	to: number, -- end along the wall
	bottom: number?, -- height above the wall's base (0 = door)
	top: number, -- height above the wall's base
}

export type Builder = typeof(setmetatable(
	{} :: { model: Model, geometry: Folder, spawns: Folder, objectives: Folder },
	MapBuilder
))

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
function MapBuilder.Floor(self: Builder, name: string, x1: number, z1: number, x2: number, z2: number, y: number, thickness: number, color: Color3, material: Enum.Material?)
	return self:Box(name, Vector3.new(x1, y - thickness, z1), Vector3.new(x2, y, z2), color, material)
end

-- Like Floor, but leaves a rectangular hole (e.g. a stairwell)
function MapBuilder.FloorWithHole(self: Builder, name: string, x1: number, z1: number, x2: number, z2: number, hole: { number }, y: number, thickness: number, color: Color3, material: Enum.Material?)
	local hx1, hz1, hx2, hz2 = hole[1], hole[2], hole[3], hole[4]
	self:Floor(name, x1, z1, hx1, z2, y, thickness, color, material) -- left of hole
	self:Floor(name, hx2, z1, x2, z2, y, thickness, color, material) -- right of hole
	self:Floor(name, hx1, z1, hx2, hz1, y, thickness, color, material) -- in front of hole
	self:Floor(name, hx1, hz2, hx2, z2, y, thickness, color, material) -- behind hole
end

-- Axis-aligned wall from (x1, z1) to (x2, z2) (one of x or z must match), rising from `base` by
-- `height`, with openings cut out (doors: bottom = 0, windows: bottom > 0).
-- Opening positions are measured along the wall from its lower x / z end.
function MapBuilder.Wall(self: Builder, name: string, x1: number, z1: number, x2: number, z2: number, base: number, height: number, openings: { Opening }?, color: Color3, material: Enum.Material?, thickness: number?)
	local t = thickness or 1
	local alongX = z1 == z2
	local startPos = if alongX then math.min(x1, x2) else math.min(z1, z2)
	local length = if alongX then math.abs(x2 - x1) else math.abs(z2 - z1)
	local fixed = if alongX then z1 else x1

	-- One wall piece covering [a, b] along the wall and [bottom, top] in height
	local function piece(a: number, b: number, bottom: number, top: number)
		if b - a < 0.01 or top - bottom < 0.01 then
			return
		end
		if alongX then
			self:Box(name, Vector3.new(startPos + a, base + bottom, fixed - t / 2), Vector3.new(startPos + b, base + top, fixed + t / 2), color, material)
		else
			self:Box(name, Vector3.new(fixed - t / 2, base + bottom, startPos + a), Vector3.new(fixed + t / 2, base + top, startPos + b), color, material)
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
end

-- Straight stairs: visual steps you walk on top of, plus an invisible ramp for smooth movement.
-- Runs along +Z from z1 to z2 (between x1..x2), rising from y1 to y2.
function MapBuilder.StairsZ(self: Builder, x1: number, x2: number, z1: number, z2: number, y1: number, y2: number, color: Color3)
	local steps = math.max(math.floor((y2 - y1) / 0.8), 1)
	local run = (z2 - z1) / steps
	local rise = (y2 - y1) / steps
	for i = 1, steps do
		local step = self:Box(
			"Step",
			Vector3.new(x1, y1, z1 + (i - 1) * run),
			Vector3.new(x2, y1 + i * rise, z1 + i * run),
			color,
			Enum.Material.WoodPlanks
		)
		step.CanCollide = false
	end
	-- The ramp the player actually walks on (steps are just for looks)
	local length = math.sqrt((z2 - z1) ^ 2 + (y2 - y1) ^ 2)
	local angle = math.atan2(y2 - y1, z2 - z1)
	local center = Vector3.new((x1 + x2) / 2, (y1 + y2) / 2, (z1 + z2) / 2)
	local ramp = self:Part("StairRamp", Vector3.new(x2 - x1, 0.4, length), CFrame.new(center) * CFrame.Angles(-angle, 0, 0), color)
	ramp.Transparency = 1
end

-- Ceiling light: a small glowing panel with a light under it
function MapBuilder.Light(self: Builder, position: Vector3, range: number?)
	local panel = self:Part("Light", Vector3.new(2, 0.2, 2), CFrame.new(position), Color3.fromRGB(255, 244, 214), Enum.Material.Neon)
	panel.CanCollide = false
	panel.CastShadow = false
	local light = Instance.new("PointLight")
	light.Range = range or 26
	light.Brightness = 1.2
	light.Color = Color3.fromRGB(255, 236, 200)
	light.Shadows = true
	light.Parent = panel
end

-- Spawn pad for one side ("Attack" / "Defend"). Players spawn on it facing `facing`.
function MapBuilder.SpawnPad(self: Builder, side: string, position: Vector3, facing: Vector3)
	local pad = Instance.new("Part")
	pad.Name = side .. "Spawn"
	pad.Size = Vector3.new(12, 0.2, 6)
	pad.CFrame = CFrame.lookAt(position, position + Vector3.new(facing.X, 0, facing.Z))
	pad.Anchored = true
	pad.CanCollide = false
	pad.CanQuery = false
	pad.Transparency = 0.6
	pad.Material = Enum.Material.Neon
	pad.Color = if side == "Attack" then Color3.fromRGB(220, 70, 70) else Color3.fromRGB(60, 130, 230)
	pad:SetAttribute("Side", side)
	pad.Parent = self.spawns
end

-- Plant site zone (invisible box): attackers plant anywhere inside it
function MapBuilder.Site(self: Builder, name: string, min: Vector3, max: Vector3)
	local site = Instance.new("Part")
	site.Name = "Site" .. name
	site.Size = max - min
	site.CFrame = CFrame.new((min + max) / 2)
	site.Anchored = true
	site.CanCollide = false
	site.CanQuery = false
	site.CanTouch = false
	site.Transparency = 1
	site:SetAttribute("Site", name)
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

return MapBuilder
