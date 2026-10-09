-- Siege-style destruction. Any part with a "Breakable" attribute can be shot or knifed apart:
--   "Glass"      window panes: any hit shatters the whole pane
--   "Soft"       drywall walls and wooden floors: a single bullet only marks it (no see-through
--                hole, like Siege since 2021); a tight burst knocks a chunk out; the knife knocks
--                out big chunks (small ones in floors: holes to shoot down through, not to drop)
--   "Hatch"      trapdoor covers: 3 knife hits or an explosive open them; bullets pass through
--   "Barricade"  wooden boards on doors/windows (FortifyService): chunks like a soft wall, and
--                3 knife hits or ~20 bullets smash the whole thing (Siege numbers)
--   "Panel"      armor panels (GadgetService): bulletproof; 10 knife hits or an explosive
--   "Gadget"     batteries, jammers, charges (GadgetService): any hit destroys the device
-- Explosives (breach charges, thermite) call Breach: a door-sized hole through the wall, or a
-- hole to drop through in a floor.
-- A hole is cut by splitting the part into up to 4 pieces around a rectangle, so a wall only
-- grows by a few parts per hit. Everything resets when the map reloads at the start of a round.
-- Clients get a "Destruction" event for the debris, dust and sound (DestructionEffects).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local DestructionEvent = ReplicatedStorage.Remotes.Destruction :: RemoteEvent

local DestructionService = {}

local MELEE_HOLE = Vector3.one * 2.2 -- studs
local FLOOR_MELEE_HOLE = Vector3.one * 1.6 -- a hole to shoot down through, too small to drop through
local BULLET_CHUNK = Vector3.one * 1.1 -- chunk a burst knocks out
local HATCH_MELEE_HITS = 3 -- knife hits that break a hatch cover open
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

-- The axis (1 = X, 2 = Y, 3 = Z) that goes through a wall / floor: its thinnest. It's worked out
-- once from the whole part and remembered, because the strips left over a hole can end up
-- thinner than the wall is thick. Map parts aren't rotated, so 2 means a floor.
local function throughAxis(part: BasePart): number
	local thin = part:GetAttribute("Through")
	if typeof(thin) ~= "number" then
		local size = part.Size
		thin = if size.X <= size.Y and size.X <= size.Z then 1 elseif size.Y <= size.Z then 2 else 3
		part:SetAttribute("Through", thin) -- set before cloning, so every piece keeps it
	end
	return thin :: number
end

-- Splits `part` around a box-shaped hole centred on `point` (`hole` = its size in world axes;
-- walls are axis-aligned). Returns false if the hole missed the part entirely.
local function cutHole(part: BasePart, point: Vector3, hole: Vector3): boolean
	local cf, partSize = part.CFrame, part.Size
	local localPoint = cf:PointToObjectSpace(point)
	-- The hole goes through the part along its thin axis and is cut in the other two (u, v)
	local dims = { partSize.X, partSize.Y, partSize.Z }
	local thin = throughAxis(part)
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

local function isFloor(part: BasePart): boolean
	return throughAxis(part) == 2
end

-- Carpet / tile on top of a floor and the painted ceiling under it are thin see-through layers
-- (<Map>/Shell): cut the same hole in them, all the way through the floor
local function cutSkins(point: Vector3, hole: Vector3)
	local map = Workspace:FindFirstChild("Map")
	local shell = map and map:FindFirstChild("Shell")
	if not shell then
		return
	end
	local deep = Vector3.new(hole.X, 3, hole.Z)
	local boxMin, boxMax = point - deep / 2, point + deep / 2
	for _, skin in shell:GetChildren() do
		if skin:IsA("BasePart") then
			local skinMin, skinMax = skin.Position - skin.Size / 2, skin.Position + skin.Size / 2
			if skinMin.X < boxMax.X and skinMax.X > boxMin.X and skinMin.Y < boxMax.Y and skinMax.Y > boxMin.Y and skinMin.Z < boxMax.Z and skinMax.Z > boxMin.Z then
				cutHole(skin, point, deep)
			end
		end
	end
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

	if breakable == "Hatch" then
		-- Bullets go through the boards but can't open it; the knife or an explosive can
		local hatch = part:FindFirstAncestorOfClass("Model")
		if melee and hatch then
			local hits = (hatch:GetAttribute("KnifeHits") or 0) + 1
			if hits >= HATCH_MELEE_HITS then
				broadcast("Smash", part, point, 4)
				hatch:Destroy()
				return
			end
			hatch:SetAttribute("KnifeHits", hits)
			broadcast("Chunk", part, point, 1)
		else
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

	local floor = isFloor(part)
	local hole = if not melee then BULLET_CHUNK elseif floor then FLOOR_MELEE_HOLE else MELEE_HOLE
	local parent = part.Parent
	-- The hole can straddle the seam between two pieces of the same wall / floor: cut them all
	local cut = false
	if breakable == "Soft" then
		local axis = throughAxis(part)
		for _, other in Workspace:GetPartBoundsInBox(CFrame.new(point), hole) do
			if other ~= part and other:GetAttribute("Breakable") == "Soft" and throughAxis(other) == axis then
				cut = cutHole(other, point, hole) or cut
			end
		end
	end
	if cutHole(part, point, hole) or cut then
		broadcast("Chunk", part, point, hole.X)
		if floor then
			cutSkins(point, hole)
		end
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

-- An explosive went off against a wall or a floor at `center` (`normal` = the face it was stuck
-- to). On a wall: a `width` × `height` hole through every soft wall piece there; on a floor: a
-- `width` × `width` hole to drop through (carpet and ceiling too). Either way it takes out any
-- barricade, hatch cover, armor panel or gadget in the way, and shatters glass.
function DestructionService.Breach(center: Vector3, normal: Vector3, width: number, height: number)
	local onFloor = math.abs(normal.Y) > 0.7
	local depth = 3 -- through the wall / floor, plus whatever is stuck to either face
	local hole
	if onFloor then
		hole = Vector3.new(width, depth, width)
	else
		local across = Vector3.new(normal.X, 0, normal.Z).Unit
		local along = Vector3.yAxis:Cross(across)
		hole = Vector3.new(math.abs(along.X) * width + math.abs(across.X) * depth, height, math.abs(along.Z) * width + math.abs(across.Z) * depth)
	end
	local color, material = Color3.fromRGB(230, 225, 212), Enum.Material.Plaster
	for _, part in Workspace:GetPartBoundsInBox(CFrame.new(center), hole) do
		local breakable = part:GetAttribute("Breakable")
		if not breakable or not part.Parent then
			continue -- not breakable, or already gone with its barricade / device
		end
		if breakable == "Soft" then
			-- A wall breach leaves the floor under it alone, and a floor breach the walls
			if isFloor(part) == onFloor then
				color, material = part.Color, part.Material
				cutHole(part, center, hole)
			end
		elseif breakable == "Glass" then
			broadcast("Glass", part, part.Position, math.max(part.Size.X, part.Size.Z))
			part:Destroy()
		else
			local model = part:FindFirstAncestorOfClass("Model")
			;(model or part):Destroy()
		end
	end
	if onFloor then
		cutSkins(center, hole)
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
	holder:ClearAllChildren()
	-- A floor: the hole goes down through it (its thin axis is Y), leaving a frame of 4 pieces
	local floor = Instance.new("Part")
	floor.Size = Vector3.new(10, 1, 10)
	floor.CFrame = CFrame.new(0, -1000, 0)
	floor.Parent = holder
	assert(isFloor(floor), "a slab is a floor")
	assert(cutHole(floor, Vector3.new(0, -999.5, 0), Vector3.new(4.5, 3, 4.5)), "floor breach should hit the floor")
	area = 0
	for _, piece in holder:GetChildren() do
		assert((piece :: BasePart).Size.Y == 1, "floor pieces keep the floor's thickness")
		area += (piece :: BasePart).Size.X * (piece :: BasePart).Size.Z
	end
	assert(#holder:GetChildren() == 4 and math.abs(area - (100 - 4.5 * 4.5)) < 1e-3, "floor breach should leave a hole to drop through")
	holder:Destroy()
end

return DestructionService
