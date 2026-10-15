-- Siege-style destruction. Any part with a "Breakable" attribute can be shot or knifed apart:
--   "Glass"      window panes: any hit shatters the whole pane
--   "Soft"       drywall walls and wooden floors. A single bullet only leaves a pinhole mark (no
--                see-through hole, like Siege since 2021); damage adds up per small grid cell, and
--                a cell shot enough opens into a murder hole (so a tight burst opens a peek hole,
--                and a spray opens a row of them). A shotgun blast up close tears one big hole
--                where its pellets land together; the knife knocks out a fist-to-head-sized hole
--                per hit, so 6-10 hits (or a few shells side by side) make a rotation hole.
--                Floors take smaller knife / shotgun holes: to shoot down through, not drop.
--   "Hatch"      trapdoor covers: 5 knife hits or close shotgun blasts, or one explosive, open
--                them; bullets pass through. A reinforced hatch only opens to a hard breach.
--   "Barricade"  wooden boards on doors/windows (FortifyService): holes like a soft wall, and
--                3 knife hits, ~20 bullets or 2-3 close shotgun shells smash the whole thing
--   "Panel"      armor panels (GadgetService): bulletproof; 10 knife hits or an explosive
--   "Gadget"     batteries, jammers, charges (GadgetService): any hit destroys the device
-- Reinforced wall sections and hatches (FortifyService tags their slots "Reinforced") are immune
-- to bullets, knives and ordinary explosives: hits on the soft wall over the steel only clang,
-- and any hole that would reach into a reinforced section stops at its edge. A hard breach
-- removes the steel first (FortifyService.RemoveReinforcement), then calls Breach.
-- Explosives (breach charges, impact grenades, thermite) call Breach: a door-sized hole through
-- the wall, or a hole to drop through in a floor.
-- A hole is cut by splitting the part into up to 4 pieces around a rectangle, so a wall only
-- grows by a few parts per hit; small-arms holes stop once a wall (or the whole map) has been cut
-- into too many pieces. Everything resets when the map reloads at the start of a round.
-- Clients get "Destruction" events for the debris, dust, pinhole marks and sound
-- (DestructionEffects), batched: one "Batch" event per frame carrying every effect.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local DestructionEvent = ReplicatedStorage.Remotes.Destruction :: RemoteEvent

local DestructionService = {}

-- Hole sizes are in studs (a character is ~5.5 tall, so a stud is ~33 cm)
local MELEE_HOLE = 1.4 -- a knife hit in a wall / barricade
local FLOOR_MELEE_HOLE = 1 -- in a floor: a hole to shoot down through, too small to drop through
local CELL = 0.8 -- bullet damage adds up per 0.8-stud cell of a surface (the murder-hole grid)
local CELL_HOLE = CELL + 0.05 -- a shot-through cell opens this wide (a hair over: neighbours join)
local CHUNK_AFTER = 3 -- damage in one cell before it opens
local MARKS = { Bullet = 1, Pellet = 2 } -- a stray shotgun pellet chews through faster
-- Shotgun: the pellets of one blast that land close together on one surface tear one hole
local BLAST_CLUSTER = 1.3 -- studs from the first pellet of a cluster to the others
local BLAST_MIN_PELLETS = 3 -- fewer together than this (long range) count as stray pellets
local BLAST_HOLE_BASE = 0.8 -- hole size: this plus BLAST_HOLE_PER_PELLET per pellet in it...
local BLAST_HOLE_PER_PELLET = 0.17 -- (all 8 pellets: ~2.2, about 70 cm)
local BLAST_HOLE_EDGE = 0.5 -- ...but at least the pellets' spread plus this
local BLAST_HOLE_MAX = 2.2
local FLOOR_BLAST_HOLE_MAX = 1.6 -- floors: to look / shoot down through; dropping takes several
local HATCH_HITS = 5 -- knife hits or close shotgun blasts that break a hatch cover open
local PANEL_MELEE_HITS = 10 -- knife hits that break an armor panel (Siege's Castle panel)
local BARRICADE_MELEE_HITS = 3 -- knife hits that smash a whole barricade
local BARRICADE_BULLET_MARKS = 20 -- bullets that bring one down...
local BARRICADE_MARKS = { Bullet = 1, Pellet = 1 } -- ...or pellets (8 a shell: 2-3 close shells)
local MIN_PIECE = 0.15 -- slivers thinner than this just crumble away
local MIN_PIECE_AREA = 0.3 -- and so do tiny leftover bits
local REINFORCED_TAG = "Reinforced" -- FortifyService tags reinforce slots that have steel on them
local STEEL_MARGIN = 0.3 -- studs round a reinforced section where hits still just clang
-- Performance
local MAX_PIECES_PER_WALL = 160 -- a wall cut into this many pieces only takes marks from small arms
local MAX_PIECES = 4000 -- pieces small arms may add to the whole map in a round (explosives aren't capped)
local MAX_EVENTS = 48 -- effects per network batch; extra bullet chips are dropped

export type HitKind = "Bullet" | "Pellet" | "Melee"

local marks: { [string]: number } = {} -- damage per cell ("<wall>:<cell>")
local pieceCounts: { [number]: number } = {} -- pieces each wall (WallId) has been cut into
local piecesMade = 0 -- by small arms this round
local nextWallId = 0
type Pellet = { part: BasePart, point: Vector3, wall: number, breakable: string }
local pellets: { Pellet } = {} -- shotgun pellets this frame, cut together (flushPellets)
local pelletsQueued = false
local outbox: { { any } } = {} -- effects waiting for this frame's batch
local sendQueued = false

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
-- walls are axis-aligned). Returns false if the hole missed the part entirely, and how many
-- pieces are left in its place.
local function cutHole(part: BasePart, point: Vector3, hole: Vector3): (boolean, number)
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
		return false, 1
	end

	-- One remaining piece covering [a1, a2] along u and [b1, b2] along v
	local made = 0
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
		made += 1
	end
	piece(-halfU, u1, -halfV, halfV) -- left of the hole, full height
	piece(u2, halfU, -halfV, halfV) -- right of the hole
	piece(u1, u2, -halfV, v1) -- under the hole
	piece(u1, u2, v2, halfV) -- over the hole
	part:Destroy()
	return true, made
end

-- Effects go out once a frame, all together (DestructionEffects takes the "Batch" apart).
-- `depth` = through the surface from the face that was hit (pinhole marks); `holder` = the model
-- the marks belong to (they go when it does).
local function send()
	sendQueued = false
	local batch = outbox
	outbox = {}
	if #batch > 0 then
		DestructionEvent:FireAllClients("Batch", batch)
	end
end

local function queueEffect(kind: string, point: Vector3, size: number, color: Color3, material: Enum.Material, depth: Vector3?, holder: Instance?)
	if (kind == "Hole" or kind == "Ping") and #outbox >= MAX_EVENTS then
		return -- a hail of bullets: the chips are already flying
	end
	table.insert(outbox, { kind, point, size, color, material, depth or Vector3.zero, holder })
	if not sendQueued then
		sendQueued = true
		task.defer(send)
	end
end

local function broadcast(kind: string, part: BasePart, point: Vector3, size: number)
	queueEffect(kind, point, size, part.Color, part.Material)
end

local function isFloor(part: BasePart): boolean
	return throughAxis(part) == 2
end

-- Every piece cut from one wall / floor / barricade shares its number (set before cloning, so
-- the pieces inherit it): marks and part caps are kept per wall, not per piece
local function wallId(part: BasePart): number
	local id = part:GetAttribute("WallId")
	if typeof(id) ~= "number" then
		nextWallId += 1
		id = nextWallId
		part:SetAttribute("WallId", id)
	end
	return id :: number
end

-- The direction through the surface (its thin axis, in world space)
local function axisVector(part: BasePart): Vector3
	local thin = throughAxis(part)
	local cf = part.CFrame
	return if thin == 1 then cf.XVector elseif thin == 2 then cf.YVector else cf.ZVector
end

-- `point` moved onto the middle of the surface's thickness
local function midPlane(part: BasePart, point: Vector3): Vector3
	local normal = axisVector(part)
	return point + normal * normal:Dot(part.Position - point)
end

-- A box `size` across in the surface's plane and `depth` through it (world axes)
local function holeBox(normal: Vector3, size: number, depth: number): Vector3
	local through = Vector3.new(math.abs(normal.X), math.abs(normal.Y), math.abs(normal.Z))
	return through * depth + (Vector3.one - through) * size
end

-- Is there steel at `point`: a reinforced wall section or hatch (FortifyService)?
local function reinforcedAt(point: Vector3): boolean
	for _, slot in CollectionService:GetTagged(REINFORCED_TAG) do
		if slot:IsA("BasePart") and slot.Parent then
			local localPoint = slot.CFrame:PointToObjectSpace(point)
			local half = slot.Size / 2 + Vector3.one * STEEL_MARGIN
			if math.abs(localPoint.X) <= half.X and math.abs(localPoint.Y) <= half.Y and math.abs(localPoint.Z) <= half.Z then
				return true
			end
		end
	end
	return false
end

-- Steel stops a hole: trims a wall hole (a `hole`-sized box at `center`, through a wall facing
-- `normal`) along the wall so it ends where a reinforced section starts. nil = the centre is on
-- steel, nothing to cut. Slots are axis-aligned like the walls.
local function clipToSteel(center: Vector3, hole: Vector3, normal: Vector3): (Vector3?, Vector3?)
	local low, high = center - hole / 2, center + hole / 2
	local wallAlongX = math.abs(normal.Z) > math.abs(normal.X)
	for _, slot in CollectionService:GetTagged(REINFORCED_TAG) do
		if not slot:IsA("BasePart") or not slot.Parent or slot:GetAttribute("Hatch") then
			continue
		end
		local slotLow, slotHigh = slot.Position - slot.Size / 2, slot.Position + slot.Size / 2
		local overlaps = slotLow.X < high.X and slotHigh.X > low.X and slotLow.Y < high.Y and slotHigh.Y > low.Y and slotLow.Z < high.Z and slotHigh.Z > low.Z
		if not overlaps or (slot.Size.X > slot.Size.Z) ~= wallAlongX then
			continue -- elsewhere, or a wall at right angles (a corner)
		end
		if wallAlongX then
			if center.X >= slotLow.X and center.X <= slotHigh.X then
				return nil, nil
			elseif slot.Position.X < center.X then
				low = Vector3.new(slotHigh.X, low.Y, low.Z)
			else
				high = Vector3.new(slotLow.X, high.Y, high.Z)
			end
		else
			if center.Z >= slotLow.Z and center.Z <= slotHigh.Z then
				return nil, nil
			elseif slot.Position.Z < center.Z then
				low = Vector3.new(low.X, low.Y, slotHigh.Z)
			else
				high = Vector3.new(high.X, high.Y, slotLow.Z)
			end
		end
	end
	local size = high - low
	if size.X < 0.2 or size.Z < 0.2 then
		return nil, nil
	end
	return (low + high) / 2, size
end

-- A bullet mark: chips at `point`, and a pinhole drawn right through the surface (the marks on
-- a barricade / hatch go with it; on a wall they stay with the map)
local function broadcastHole(part: BasePart, point: Vector3)
	local normal = axisVector(part)
	local depth = normal * (2 * normal:Dot(part.Position - point)) -- to the opposite face
	queueEffect("Hole", point, 0, part.Color, part.Material, depth, part:FindFirstAncestorOfClass("Model"))
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

-- The barricade / hatch model a part belongs to (never the map itself)
local function ownModel(part: BasePart): Model?
	local model = part.Parent
	return if model and model:IsA("Model") and model.Name ~= "Map" then model else nil
end

-- Cuts a `size`-wide hole (in the surface's plane) at `point` through `part` and every piece of
-- the same surface next to it: the hole can straddle the seam between two pieces. Holes stop at
-- steel, and small arms stop cutting once the wall / map is in too many pieces. A soft `part`
-- may already be gone (cut by an earlier hole this frame): only its attributes and place are
-- used. Returns whether anything was cut.
local function punch(part: BasePart, point: Vector3, size: number): boolean
	local breakable = part:GetAttribute("Breakable")
	if (pieceCounts[wallId(part)] or 1) >= MAX_PIECES_PER_WALL or piecesMade >= MAX_PIECES then
		return false
	end
	local axis = throughAxis(part)
	local normal = axisVector(part)
	local thickness = if axis == 1 then part.Size.X elseif axis == 2 then part.Size.Y else part.Size.Z
	local center, hole = midPlane(part, point), holeBox(normal, size, thickness + 0.4)
	local floor = axis == 2
	if not floor then
		local clippedCenter, clippedHole = clipToSteel(center, hole, normal)
		if not clippedCenter or not clippedHole then
			return false
		end
		center, hole = clippedCenter, clippedHole
	end
	-- A barricade's holes stay in its own boards
	local barricade = if breakable == "Barricade" then ownModel(part) else nil
	if breakable == "Barricade" and not barricade then
		return false
	end
	local cutAny = false
	local color, material = part.Color, part.Material
	for _, other in Workspace:GetPartBoundsInBox(CFrame.new(center), hole) do
		if other:GetAttribute("Breakable") ~= breakable or throughAxis(other) ~= axis or (barricade and other.Parent ~= barricade) then
			continue
		end
		local id = wallId(other) -- (before the cut: the pieces inherit it)
		local otherColor, otherMaterial = other.Color, other.Material
		local cut, made = cutHole(other, center, hole)
		if cut then
			cutAny = true
			color, material = otherColor, otherMaterial
			pieceCounts[id] = (pieceCounts[id] or 1) + made - 1
			piecesMade += math.max(made - 1, 0)
		end
	end
	if not cutAny then
		return false
	end
	queueEffect("Chunk", center, size, color, material)
	if floor then
		cutSkins(center, hole)
	end
	-- A barricade shot down to nothing is gone (so the doorway can be boarded up again)
	if barricade and barricade.Parent and not barricade:FindFirstChildWhichIsA("BasePart") then
		barricade:Destroy()
	end
	return true
end

-- Bullet damage adds up per grid cell of a surface; a cell that's had enough opens up, on the
-- grid, so neighbouring cells join into bigger holes (a murder hole, then a peek slot...)
local function markCell(part: BasePart, point: Vector3, weight: number)
	local normal = axisVector(part)
	local center = midPlane(part, point)
	local ax, ay, az = math.abs(normal.X), math.abs(normal.Y), math.abs(normal.Z)
	local thin = if ax >= ay and ax >= az then 1 elseif ay >= az then 2 else 3
	-- The cell in the surface's plane (the through axis is left out)
	local cells = { math.floor(center.X / CELL), math.floor(center.Y / CELL), math.floor(center.Z / CELL) }
	cells[thin] = 0
	local key = string.format("%d:%d,%d,%d", wallId(part), cells[1], cells[2], cells[3])
	local damage = (marks[key] or 0) + weight
	if damage < CHUNK_AFTER then
		marks[key] = damage
		broadcastHole(part, point)
		return
	end
	marks[key] = nil
	local middle = { (cells[1] + 0.5) * CELL, (cells[2] + 0.5) * CELL, (cells[3] + 0.5) * CELL }
	middle[thin] = if thin == 1 then center.X elseif thin == 2 then center.Y else center.Z
	if not punch(part, Vector3.new(middle[1], middle[2], middle[3]), CELL_HOLE) then
		broadcastHole(part, point) -- (steel, or the wall's at its part cap: just a mark)
	end
end

-- A knife hit or a close shotgun blast on an unreinforced hatch cover
local function damageHatch(part: BasePart, point: Vector3)
	local hatch = ownModel(part)
	local hits = (if hatch then hatch:GetAttribute("Hits") or 0 else 0) + 1
	if hits >= HATCH_HITS or not hatch then
		broadcast("Smash", part, point, 4)
		;(hatch or part):Destroy()
		return
	end
	hatch:SetAttribute("Hits", hits)
	broadcast("Chunk", part, point, 1)
end

-- One shotgun blast's pellets that landed close together on one surface: one hole, sized by how
-- many there are and how far apart. Too few (long range) and they're just stray pellets.
local function shotgunHole(cluster: { Pellet })
	local first = cluster[1]
	local ref = first
	for _, pellet in cluster do
		if pellet.part.Parent then
			ref = pellet -- (a piece still standing, if any)
			break
		end
	end
	if #cluster < BLAST_MIN_PELLETS then
		for _, pellet in cluster do
			if pellet.breakable == "Hatch" then
				broadcastHole(pellet.part, pellet.point)
			elseif pellet.part.Parent or pellet.breakable == "Soft" then
				markCell(pellet.part, pellet.point, MARKS.Pellet)
			end
		end
		return
	end
	local center = Vector3.zero
	for _, pellet in cluster do
		center += pellet.point
	end
	center /= #cluster
	if first.breakable == "Hatch" then
		if ref.part.Parent then
			damageHatch(ref.part, center)
		end
		return
	end
	if first.breakable == "Barricade" and not ref.part.Parent then
		return -- these pellets smashed it
	end
	local spread = 0
	for _, pellet in cluster do
		spread = math.max(spread, (pellet.point - center).Magnitude)
	end
	local size = math.max(BLAST_HOLE_BASE + BLAST_HOLE_PER_PELLET * #cluster, spread * 2 + BLAST_HOLE_EDGE)
	size = math.min(size, if isFloor(ref.part) then FLOOR_BLAST_HOLE_MAX else BLAST_HOLE_MAX)
	if not punch(ref.part, center, size) then
		broadcastHole(ref.part, center)
	end
end

-- Every shotgun pellet that hit something soft this frame, sorted by surface and then into
-- clusters (pellets within BLAST_CLUSTER of the first of them)
local function flushPellets()
	pelletsQueued = false
	local batch = pellets
	pellets = {}
	local surfaces: { [number]: { Pellet } } = {}
	for _, pellet in batch do
		local group = surfaces[pellet.wall]
		if not group then
			group = {}
			surfaces[pellet.wall] = group
		end
		table.insert(group, pellet)
	end
	for _, group in surfaces do
		while #group > 0 do
			local seed = group[1].point
			local cluster, rest = {}, {}
			for _, pellet in group do
				if (pellet.point - seed).Magnitude <= BLAST_CLUSTER then
					table.insert(cluster, pellet)
				else
					table.insert(rest, pellet)
				end
			end
			group = rest
			shotgunHole(cluster)
		end
	end
end

-- Pellets are cut together once the whole blast has been traced (WeaponService traces a shot's
-- pellets one after another, all in the same frame)
local function queuePellet(part: BasePart, point: Vector3)
	table.insert(pellets, { part = part, point = point, wall = wallId(part), breakable = part:GetAttribute("Breakable") })
	if not pelletsQueued then
		pelletsQueued = true
		task.defer(flushPellets)
	end
end

-- A bullet, shotgun pellet or knife hit `part` (which must have a Breakable attribute) at `point`
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
		-- Bullets go through the boards but can't open it; the knife, close shotgun blasts or an
		-- explosive can. With steel on top, none of them can.
		if reinforcedAt(part.Position) then
			broadcast("Ping", part, point, 1)
		elseif melee then
			damageHatch(part, point)
		elseif hitKind == "Pellet" then
			queuePellet(part, point)
		else
			broadcastHole(part, point)
		end
		return
	end

	if breakable == "Soft" and reinforcedAt(point) then
		broadcast("Ping", part, point, 1) -- the steel behind it takes the hit
		return
	end

	if breakable == "Barricade" then
		-- Every piece of a barricade shares its model's knife / bullet counts
		local barricade = ownModel(part)
		if barricade then
			local attribute = if melee then "KnifeHits" else "BulletMarks"
			local limit = if melee then BARRICADE_MELEE_HITS else BARRICADE_BULLET_MARKS
			local count = (barricade:GetAttribute(attribute) or 0) + (if melee then 1 else BARRICADE_MARKS[hitKind] or 1)
			if count >= limit then
				broadcast("Smash", part, point, 4)
				barricade:Destroy()
				return
			end
			barricade:SetAttribute(attribute, count)
		end
	end

	if hitKind == "Pellet" then
		queuePellet(part, point)
	elseif not melee then
		markCell(part, point, MARKS[hitKind] or 1)
	elseif not punch(part, point, if isFloor(part) then FLOOR_MELEE_HOLE else MELEE_HOLE) then
		broadcast("Chunk", part, point, 0.6) -- (the wall's at its part cap: just the debris)
	end
end

function DestructionService.IsBreakable(instance: Instance): boolean
	return instance:GetAttribute("Breakable") ~= nil
end

-- A fresh map was loaded: forget the bullet marks and part counts of the old one
function DestructionService.Reset()
	table.clear(marks)
	table.clear(pieceCounts)
	table.clear(pellets)
	piecesMade = 0
end

-- An explosive went off against a wall or a floor at `center` (`normal` = the face it was stuck
-- to). On a wall: a `width` × `height` hole through every soft wall piece there; on a floor: a
-- `width` × `width` hole to drop through (carpet and ceiling too). Either way it takes out any
-- barricade, hatch cover, armor panel or gadget in the way, and shatters glass. Steel stops it:
-- a wall hole ends where a reinforced section starts, and a reinforced hatch stays shut (a hard
-- breach takes its steel off before it calls this).
function DestructionService.Breach(center: Vector3, normal: Vector3, width: number, height: number)
	local onFloor = math.abs(normal.Y) > 0.7
	local depth = 3 -- through the wall / floor, plus whatever is stuck to either face
	local blastAt = center
	local hole
	if onFloor then
		hole = Vector3.new(width, depth, width)
	else
		local across = Vector3.new(normal.X, 0, normal.Z).Unit
		local along = Vector3.yAxis:Cross(across)
		hole = Vector3.new(math.abs(along.X) * width + math.abs(across.X) * depth, height, math.abs(along.Z) * width + math.abs(across.Z) * depth)
		local clippedCenter, clippedHole = clipToSteel(center, hole, across)
		if not clippedCenter or not clippedHole then
			queueEffect("Blast", blastAt, width, Color3.fromRGB(92, 97, 104), Enum.Material.DiamondPlate)
			return -- right on the steel: it holds
		end
		center, hole = clippedCenter, clippedHole
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
		elseif breakable == "Hatch" and reinforcedAt(part.Position) then
			continue -- steel on top
		else
			local model = part:FindFirstAncestorOfClass("Model")
			if model and model.Name == "Map" then
				model = nil -- (never the whole map: a loose breakable part just goes on its own)
			end
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
	queueEffect("Blast", blastAt, width, color, material)
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
