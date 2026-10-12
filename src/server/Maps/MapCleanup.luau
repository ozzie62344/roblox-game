-- Removes z-fighting from code-built maps. Wherever two visible blocks have faces in the same
-- plane, facing the same way and overlapping (a floor's edge flush with the outside wall, a sill
-- flush with its wall, road paint flush with the road, a baseboard flush with the wall), the GPU
-- can't decide which one to draw and the surface flickers in stripes as you move.
-- The fix moves the smaller of the two faces by a hair (OFFSET):
--   thin layers (paint, tiles, trim: THIN or less deep) come forward, so they show
--   anything else (an edge buried in a wall) goes back, so the bigger face covers it
-- Only faces with open air in front of them count: overlaps hidden inside other geometry don't
-- flicker. Rotated parts (roofs, ramps) are left alone. Moving one face can line it up with a
-- third part, so it runs a few passes. Runs on a built map before it's parented (it only reads
-- the model, no Workspace queries).

local MapCleanup = {}

local OFFSET = 0.03 -- studs the smaller face ends up in front of / behind the other one
local SAME_PLANE = 0.02 -- faces closer than this count as the same plane
local THIN = 0.35 -- layers this thin or thinner (along the face's normal) are meant to be seen
local CELL = 8 -- spatial hash cell size
local LARGE = 64 -- parts bigger than this in any direction skip the hash (checked against all)

type Box = { part: Part, min: Vector3, max: Vector3, index: number }

local AXES = { Vector3.xAxis, Vector3.yAxis, Vector3.zAxis }

local function component(v: Vector3, i: number): number
	return if i == 1 then v.X elseif i == 2 then v.Y else v.Z
end

-- Axis-aligned (in any of the 24 right-angle orientations)?
local function aligned(part: BasePart): boolean
	local r = part.CFrame
	for _, v in { r.XVector, r.YVector, r.ZVector } do
		if math.max(math.abs(v.X), math.abs(v.Y), math.abs(v.Z)) < 0.9999 then
			return false
		end
	end
	return true
end

local function worldSize(part: BasePart): Vector3
	local cf, s = part.CFrame, part.Size
	return Vector3.new(
		math.abs(cf.XVector.X) * s.X + math.abs(cf.YVector.X) * s.Y + math.abs(cf.ZVector.X) * s.Z,
		math.abs(cf.XVector.Y) * s.X + math.abs(cf.YVector.Y) * s.Y + math.abs(cf.ZVector.Y) * s.Z,
		math.abs(cf.XVector.Z) * s.X + math.abs(cf.YVector.Z) * s.Y + math.abs(cf.ZVector.Z) * s.Z
	)
end

-- Puts an axis-aligned part back from world-space min / max (keeping its orientation)
local function setBounds(part: BasePart, min: Vector3, max: Vector3)
	local size = max - min
	local cf = part.CFrame
	local function along(v: Vector3): number
		local ax, ay, az = math.abs(v.X), math.abs(v.Y), math.abs(v.Z)
		return if ax >= ay and ax >= az then size.X elseif ay >= az then size.Y else size.Z
	end
	part.Size = Vector3.new(along(cf.XVector), along(cf.YVector), along(cf.ZVector))
	part.CFrame = CFrame.new((min + max) / 2) * cf.Rotation
end

local MAX_PASSES = 4

local function pass(map: Instance): number
	-- Visible, solid-looking, axis-aligned blocks
	local boxes: { Box } = {}
	local large: { Box } = {}
	local cells: { [Vector3]: { Box } } = {}
	for _, part in map:GetDescendants() do
		if part:IsA("Part") and part.Shape == Enum.PartType.Block and part.Transparency < 0.5 and aligned(part) then
			local half = worldSize(part) / 2
			local box = { part = part, min = part.Position - half, max = part.Position + half, index = #boxes + 1 }
			table.insert(boxes, box)
			local size = half * 2
			if math.max(size.X, size.Y, size.Z) > LARGE then
				table.insert(large, box)
			else
				for x = math.floor(box.min.X / CELL), math.floor(box.max.X / CELL) do
					for y = math.floor(box.min.Y / CELL), math.floor(box.max.Y / CELL) do
						for z = math.floor(box.min.Z / CELL), math.floor(box.max.Z / CELL) do
							local key = Vector3.new(x, y, z)
							local list = cells[key]
							if not list then
								list = {}
								cells[key] = list
							end
							table.insert(list, box)
						end
					end
				end
			end
		end
	end

	-- Is this point inside any of the blocks (open air otherwise)?
	local function solidAt(point: Vector3): boolean
		local function inside(box: Box): boolean
			return point.X > box.min.X and point.X < box.max.X and point.Y > box.min.Y and point.Y < box.max.Y and point.Z > box.min.Z and point.Z < box.max.Z
		end
		for _, box in cells[Vector3.new(math.floor(point.X / CELL), math.floor(point.Y / CELL), math.floor(point.Z / CELL))] or {} do
			if inside(box) then
				return true
			end
		end
		for _, box in large do
			if inside(box) then
				return true
			end
		end
		return false
	end

	-- Moves to make: per box, per face (axis 1..3, side ±1), the plane that face should end up on
	local moves: { [Box]: { [number]: number } } = {}
	local function move(box: Box, faceKey: number, plane: number, forward: boolean)
		local faces = moves[box] or {}
		moves[box] = faces
		local current = faces[faceKey]
		-- Several partners: the furthest forward / furthest back wins
		if current == nil or (forward and plane * math.sign(faceKey) > current * math.sign(faceKey)) or (not forward and plane * math.sign(faceKey) < current * math.sign(faceKey)) then
			faces[faceKey] = plane
		end
	end

	local function check(a: Box, b: Box)
		for i = 1, 3 do
			for _, side in { 1, -1 } do
				local pa = if side > 0 then component(a.max, i) else component(a.min, i)
				local pb = if side > 0 then component(b.max, i) else component(b.min, i)
				if math.abs(pa - pb) >= SAME_PLANE then
					continue
				end
				-- Overlap on the other two axes
				local lo, hi, areaA, areaB = {}, {}, 1, 1
				local overlaps = true
				for j = 1, 3 do
					if j ~= i then
						local l = math.max(component(a.min, j), component(b.min, j))
						local h = math.min(component(a.max, j), component(b.max, j))
						if h - l <= 0.05 then
							overlaps = false
							break
						end
						lo[j], hi[j] = l, h
						areaA *= component(a.max, j) - component(a.min, j)
						areaB *= component(b.max, j) - component(b.min, j)
					end
				end
				if not overlaps then
					continue
				end
				-- Open air just in front of it somewhere (3 × 3 samples)?
				local plane = if side > 0 then math.max(pa, pb) else math.min(pa, pb)
				local visible = false
				for _, u in { 0.2, 0.5, 0.8 } do
					for _, v in { 0.2, 0.5, 0.8 } do
						local coords = { 0, 0, 0 }
						coords[i] = plane + side * 0.05
						local k = 0
						for j = 1, 3 do
							if j ~= i then
								k += 1
								coords[j] = lo[j] + (hi[j] - lo[j]) * (if k == 1 then u else v)
							end
						end
						if not solidAt(Vector3.new(coords[1], coords[2], coords[3])) then
							visible = true
							break
						end
					end
					if visible then
						break
					end
				end
				if not visible then
					continue
				end
				-- Move the smaller face: thin layers forward, anything else back
				local small, big = a, b
				if areaA > areaB or (areaA == areaB and a.index > b.index) then
					small, big = b, a
				end
				local depth = component(small.max, i) - component(small.min, i)
				local faceKey = side * i
				if depth <= THIN then
					move(small, faceKey, plane + side * OFFSET, true)
				else
					local other = if side > 0 then math.min(component(big.max, i), plane) else math.max(component(big.min, i), plane)
					move(small, faceKey, other - side * OFFSET, false)
				end
			end
		end
	end

	-- Every nearby pair once
	local done: { [number]: boolean } = {}
	local count = #boxes
	local function pairKey(a: Box, b: Box): number
		return if a.index < b.index then a.index * (count + 1) + b.index else b.index * (count + 1) + a.index
	end
	local function consider(a: Box, b: Box)
		if a == b then
			return
		end
		local key = pairKey(a, b)
		if done[key] then
			return
		end
		done[key] = true
		-- (touching or overlapping bounds only)
		if a.max.X < b.min.X - SAME_PLANE or b.max.X < a.min.X - SAME_PLANE
			or a.max.Y < b.min.Y - SAME_PLANE or b.max.Y < a.min.Y - SAME_PLANE
			or a.max.Z < b.min.Z - SAME_PLANE or b.max.Z < a.min.Z - SAME_PLANE then
			return
		end
		check(a, b)
	end
	for _, list in cells do
		for x = 1, #list do
			for y = x + 1, #list do
				consider(list[x], list[y])
			end
		end
	end
	for _, a in large do
		for _, b in boxes do
			consider(a, b)
		end
	end

	-- Apply
	local moved = 0
	for box, faces in moves do
		local min, max = box.min, box.max
		for faceKey, plane in faces do
			local i, side = math.abs(faceKey), math.sign(faceKey)
			local axis = AXES[i]
			if side > 0 then
				max += axis * (plane - component(max, i))
			else
				min += axis * (plane - component(min, i))
			end
		end
		-- (never turn a part inside out)
		if (max - min).X > 0.01 and (max - min).Y > 0.01 and (max - min).Z > 0.01 then
			setBounds(box.part, min, max)
			moved += 1
		end
	end
	return moved
end

-- Returns how many parts it adjusted (a part adjusted in several passes counts each time)
function MapCleanup.Run(map: Instance): number
	local total = 0
	for _ = 1, MAX_PASSES do
		local moved = pass(map)
		total += moved
		if moved == 0 then
			break
		end
	end
	return total
end

return MapCleanup
