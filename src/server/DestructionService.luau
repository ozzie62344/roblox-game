-- Siege-style destruction. Any part with a "Breakable" attribute can be shot or knifed apart:
--   "Glass"      window panes: any hit shatters the whole pane
--   "Soft"       drywall walls: a single bullet only marks it (no see-through hole, like Siege
--                since 2021); a tight burst knocks a chunk out; the knife knocks out big chunks
--   "Barricade"  wooden boards on doors/windows (FortifyService): chunks like a soft wall, and
--                3 knife hits or ~20 bullets smash the whole thing (Siege numbers)
--   "Panel"      armor panels (GadgetService): bulletproof; 10 knife hits or an explosive
--   "Gadget"     batteries, jammers, charges (GadgetService): any hit destroys the device
-- Explosives (breach charges, thermite) call Breach: a door-sized hole through the wall.
-- A hole is cut by splitting the part into up to 4 pieces around a rectangle, so a wall only
-- grows by a few parts per hit. Everything resets when the map reloads at the start of a round.
-- Clients get a "Destruction" event for the debris, dust and sound (DestructionEffects).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local DestructionEvent = ReplicatedStorage.Remotes.Destruction :: RemoteEvent

local DestructionService = {}

local MELEE_HOLE = Vector3.one * 2.2 -- studs
local BULLET_CHUNK = Vector3.one * 1.1 -- chunk a burst knocks out
local PANEL_MELEE_HITS = 10 -- knife hits that break an armor panel (Siege's Castle panel)
local CELL = 1 -- bullet marks are counted per 1-stud cell of wall
local CHUNK_AFTER = 3 -- marks in one cell before its chunk falls out
local MARKS = { Bullet = 1, Pellet = 2 } -- shotgun pellets chew through faster
local BARRICADE_MELEE_HITS = 3 -- knife hits that smash a whole barricade
local BARRICADE_BULLET_MARKS = 20 -- bullet marks that bring one down
local MIN_PIECE = 0.15 -- slivers thinner than this just crumble away
local MIN_PIECE_AREA = 0.3 -- and so do tiny leftover bits

export type HitKind = "Bullet" | "Pellet" | "Melee"

local marks: { [string]: number } = {}

-- Splits `part` around a box-shaped hole centred on `point` (`hole` = its size in world axes;
-- walls are axis-aligned). Returns false if the hole missed the part entirely.
local function cutHole(part: BasePart, point: Vector3, hole: Vector3): boolean
	local cf, partSize = part.CFrame, part.Size
	local localPoint = cf:PointToObjectSpace(point)
	-- The wall's thickness axis goes through it; the hole is cut in the other two (u, v). It's
	-- worked out once from the whole wall and remembered, because the strips left over a hole
	-- can end up thinner than the wall is thick.
	local dims = { partSize.X, partSize.Y, partSize.Z }
	local thin = part:GetAttribute("Through")
	if typeof(thin) ~= "number" then
		thin = if dims[1] <= dims[2] and dims[1] <= dims[3] then 1 elseif dims[2] <= dims[3] then 2 else 3
		part:SetAttribute("Through", thin) -- set before cloning, so every piece keeps it
	end
	local u = if thin == 1 then 2 else 1
	local v = if thin == 3 then 2 else 3
	local p = { localPoint.X, localPoint.Y, localPoint.Z }
	-- The hole's size along each of the part's own axes
	local axes = { cf.XVector, cf.YVector, cf.ZVector }
	local function holeAlong(axis: Vector3): number
		return math.abs(axis.X) * hole.X + math.abs(axis.Y) * hole.Y + math.abs(axis.Z) * hole.Z
	end
	local sizeU, sizeV = holeAlong(axes[u]), holeAlong(axes[v])
	local halfU, halfV = dims[u] / 2, dims[v] / 2
	local u1, u2 = math.max(p[u] - sizeU / 2, -halfU), math.min(p[u] + sizeU / 2, halfU)
	local v1, v2 = math.max(p[v] - sizeV / 2, -halfV), math.min(p[v] + sizeV / 2, halfV)
	if u1 >= u2 or v1 >= v2 then
		return false
	end

	-- One remaining piece covering [a1, a2] along u and [b1, b2] along v
	local function piece(a1: number, a2: number, b1: number, b2: number)
		local lengthU, lengthV = a2 - a1, b2 - b1
		if lengthU < MIN_PIECE or lengthV < MIN_PIECE or lengthU * lengthV < MIN_PIECE_AREA then
			return
		end
		local sizes, center = { 0, 0, 0 }, { 0, 0, 0 }
		sizes[thin], sizes[u], sizes[v] = dims[thin], lengthU, lengthV
		center[u], center[v] = (a1 + a2) / 2, (b1 + b2) / 2
		local copy = part:Clone()
		copy.Size = Vector3.new(sizes[1], sizes[2], sizes[3])
		copy.CFrame = cf * CFrame.new(center[1], center[2], center[3])
		copy.Parent = part.Parent
	end
	piece(-halfU, u1, -halfV, halfV) -- left of the hole, full height
	piece(u2, halfU, -halfV, halfV) -- right of the hole
	piece(u1, u2, -halfV, v1) -- under the hole
	piece(u1, u2, v2, halfV) -- over the hole
	part:Destroy()
	return true
end

local function broadcast(kind: string, part: BasePart, point: Vector3, size: number)
	DestructionEvent:FireAllClients(kind, point, size, part.Color, part.Material)
end

-- A bullet or knife hit `part` (which must have a Breakable attribute) at `point`
function DestructionService.Hit(part: BasePart, point: Vector3, hitKind: HitKind)
	local breakable = part:GetAttribute("Breakable")
	if not part.Parent or not breakable then
		return
	end

	if breakable == "Glass" then
		broadcast("Glass", part, part.Position, math.max(part.Size.X, part.Size.Z))
		part:Destroy()
		return
	end

	local melee = hitKind == "Melee"
	if breakable == "Gadget" then
		broadcast("Spark", part, part.Position, 1)
		local device = part:FindFirstAncestorOfClass("Model")
		;(device or part):Destroy()
		return
	end
	if breakable == "Panel" then
		-- Bulletproof (WeaponService stops bullets at it); the knife slowly hacks it apart
		local panel = part:FindFirstAncestorOfClass("Model")
		if melee and panel then
			local hits = (panel:GetAttribute("KnifeHits") or 0) + 1
			if hits >= PANEL_MELEE_HITS then
				broadcast("Smash", part, point, 4)
				panel:Destroy()
				return
			end
			panel:SetAttribute("KnifeHits", hits)
			broadcast("Hole", part, point, 0)
		end
		return
	end

	local weight = MARKS[hitKind] or 1
	if breakable == "Barricade" then
		-- Every piece of a barricade shares its model's knife / bullet counts
		local barricade = part:FindFirstAncestorOfClass("Model")
		if barricade then
			local attribute = if melee then "KnifeHits" else "BulletMarks"
			local limit = if melee then BARRICADE_MELEE_HITS else BARRICADE_BULLET_MARKS
			local count = (barricade:GetAttribute(attribute) or 0) + (if melee then 1 else weight)
			if count >= limit then
				broadcast("Smash", part, point, 4)
				barricade:Destroy()
				return
			end
			barricade:SetAttribute(attribute, count)
		end
	end

	-- Bullets only chip the surface until enough of them land in the same spot
	if not melee then
		local key = string.format("%d,%d,%d", math.floor(point.X / CELL), math.floor(point.Y / CELL), math.floor(point.Z / CELL))
		local count = (marks[key] or 0) + weight
		if count < CHUNK_AFTER then
			marks[key] = count
			broadcast("Hole", part, point, 0)
			return
		end
		marks[key] = nil
	end

	local hole = if melee then MELEE_HOLE else BULLET_CHUNK
	local parent = part.Parent
	if cutHole(part, point, hole) then
		broadcast("Chunk", part, point, hole.X)
	end
	-- A barricade shot down to nothing is gone (so the doorway can be boarded up again)
	if breakable == "Barricade" and parent and parent:IsA("Model") and not parent:FindFirstChildWhichIsA("BasePart") then
		parent:Destroy()
	end
end

function DestructionService.IsBreakable(instance: Instance): boolean
	return instance:GetAttribute("Breakable") ~= nil
end

-- A fresh map was loaded: forget the bullet marks on the old one
function DestructionService.Reset()
	table.clear(marks)
end

-- An explosive went off against a wall at `center` (`normal` = the face it was stuck to).
-- Cuts a `width` × `height` hole through every soft wall piece there, takes out any barricade,
-- armor panel or gadget in the way, and shatters glass.
function DestructionService.Breach(center: Vector3, normal: Vector3, width: number, height: number)
	local across = Vector3.new(normal.X, 0, normal.Z)
	across = if across.Magnitude > 1e-3 then across.Unit else Vector3.zAxis
	local along = Vector3.yAxis:Cross(across)
	local depth = 3 -- through the wall, plus whatever is stuck to either face
	local hole = Vector3.new(
		math.abs(along.X) * width + math.abs(across.X) * depth,
		height,
		math.abs(along.Z) * width + math.abs(across.Z) * depth
	)
	local color, material = Color3.fromRGB(230, 225, 212), Enum.Material.Plaster
	for _, part in Workspace:GetPartBoundsInBox(CFrame.new(center), hole) do
		local breakable = part:GetAttribute("Breakable")
		if not breakable or not part.Parent then
			continue -- not breakable, or already gone with its barricade / device
		end
		if breakable == "Soft" then
			color, material = part.Color, part.Material
			cutHole(part, center, hole)
		elseif breakable == "Glass" then
			broadcast("Glass", part, part.Position, math.max(part.Size.X, part.Size.Z))
			part:Destroy()
		else
			local model = part:FindFirstAncestorOfClass("Model")
			;(model or part):Destroy()
		end
	end
	-- Trim (casings, baseboards, sills) lets bullets through (CanQuery off), so the box query above
	-- can't see it: drop any piece the hole goes through rather than leave it floating
	local map = Workspace:FindFirstChild("Map")
	local trim = map and map:FindFirstChild("Trim")
	if trim then
		local boxMin, boxMax = center - hole / 2, center + hole / 2
		for _, piece in trim:GetChildren() do
			if piece:IsA("BasePart") then
				local pieceMin, pieceMax = piece.Position - piece.Size / 2, piece.Position + piece.Size / 2 -- trim is axis-aligned
				if pieceMin.X < boxMax.X and pieceMax.X > boxMin.X and pieceMin.Y < boxMax.Y and pieceMax.Y > boxMin.Y and pieceMin.Z < boxMax.Z and pieceMax.Z > boxMin.Z then
					piece:Destroy()
				end
			end
		end
	end
	DestructionEvent:FireAllClients("Blast", center, width, color, material)
end

-- shortcut: self-check runs once per server start; move it to a test runner if one is added
do
	local wall = Instance.new("Part")
	wall.Size = Vector3.new(10, 8, 1)
	wall.CFrame = CFrame.new(0, -1000, 0)
	local holder = Instance.new("Folder")
	wall.Parent = holder
	-- Hole near the bottom: leaves a strip under it that's only 0.6 tall (thinner than the wall)
	assert(cutHole(wall, Vector3.new(0, -1002.4, 0), Vector3.one * 2), "hole should hit the wall")
	local area = 0
	for _, piece in holder:GetChildren() do
		area += (piece :: BasePart).Size.X * (piece :: BasePart).Size.Y
	end
	assert(#holder:GetChildren() == 4 and math.abs(area - (80 - 4)) < 1e-3, "hole should leave 4 pieces = wall minus hole")
	-- A second hit on that strip must still go through the wall, not slice it along its thickness
	local strip: BasePart
	for _, piece in holder:GetChildren() do
		if (piece :: BasePart).Size.Y < 1 then
			strip = piece :: BasePart
		end
	end
	assert(cutHole(strip, strip.Position, Vector3.one * 0.5), "hole should hit the strip")
	for _, piece in holder:GetChildren() do
		assert((piece :: BasePart).Size.Z == 1, "pieces must keep the wall's full thickness")
	end
	holder:ClearAllChildren()
	-- A breach: 4.5 wide, 7 tall, from the floor up (the depth across the wall doesn't matter)
	local door = Instance.new("Part")
	door.Size = Vector3.new(10, 8, 1)
	door.CFrame = CFrame.new(0, -1000, 0)
	door.Parent = holder
	assert(cutHole(door, Vector3.new(0, -1004 + 3.5, 0), Vector3.new(4.5, 7, 3)), "breach should hit the wall")
	area = 0
	for _, piece in holder:GetChildren() do
		area += (piece :: BasePart).Size.X * (piece :: BasePart).Size.Y
	end
	assert(#holder:GetChildren() == 3 and math.abs(area - (80 - 4.5 * 7)) < 1e-3, "breach should leave a doorway")
	holder:Destroy()
end

return DestructionService
