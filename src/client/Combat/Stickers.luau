-- Stickers for skins with a Stickers design (shared/Skins), in staggered rows over every big flat
-- face of the gun (or knife), all the way around it:
--   Cat     little white cat faces with two demon horns (pink inside), dot eyes and an ω mouth
--   Cheeto  cheese puffs, scattered every which way
--   Holds   colourful rock climbing holds, each with its bolt, every size and angle
-- Each sticker is built from flat parts stacked a hair apart (back to front), so it shows wherever
-- the gun does: in your hands, in other players' hands, in the shop's preview. A sticker takes the
-- name of the piece it's on, so it rides along when that piece moves (a magazine coming out, a
-- slide racking: Viewmodel moves pieces by name).
-- Only whole stickers: one sits up over little flush details (slots, pins), but a spot where any
-- bit of it would sink into something bigger is skipped.
-- A design is drawn once, with a "kit" of shapes (discs and triangles): the same drawing makes
-- the 3D sticker and the little picture on the shop's paint chip (Icon).

local Stickers = {}

local MIN_SIZE, MAX_SIZE = 0.07, 0.14 -- a sticker's width (studs) on a gun goes by its length, kept between these
local KNIFE_SIZE = 0.1 -- (studs) on the knife
local SHRINK = 0.5 -- a face too small for a full-size sticker gets one down to this share of it, or none
local BEND = 0.5 -- how far onto a rounded edge's curve a sticker may reach (share of the way round)
local MAX_PARTS = 540 -- per gun, all stickers together (phones move every one of them each frame)
local MAX_LIFT = 0.12 -- a sticker may sit up to this far off its face to clear small details (widths)
local MARGIN = 0.08 -- kept clear along a face's edges, in sticker widths

local FACE_OUT = CFrame.Angles(0, math.rad(90), 0) -- turns a cylinder's round side out of the surface
-- Lays a wedge flat: its triangle (square corner at the bottom left, point on top) in the sticker's
-- plane, its thickness out of the surface
local WEDGE_FLAT = CFrame.fromMatrix(Vector3.zero, Vector3.zAxis, Vector3.yAxis, -Vector3.xAxis)
local AXES = { Vector3.xAxis, Vector3.yAxis, Vector3.zAxis }

-- Shapes a design draws with, in sticker widths from its middle (y up). `layer`: higher is in front.
export type Kit = {
	disc: (x: number, y: number, layer: number, diameter: number, color: Color3) -> (),
	triangle: (tip: Vector2, a: Vector2, b: Vector2, layer: number, color: Color3) -> (),
}

type Design = {
	parts: number, -- per sticker (for MAX_PARTS)
	top: number, -- how far it reaches above its middle, in widths
	bottom: number, -- below
	gap: Vector2, -- spacing between stickers, in widths
	size: number, -- its width as a share of the gun's length
	turn: boolean, -- each one turned to its own angle
	spots: { Vector2 }, -- where to check for room under it (widths)
	draw: (kit: Kit, index: number) -> (),
}

type Face = { part: BasePart, frame: CFrame, width: number, height: number }
type Placed = { position: Vector3, normal: Vector3, width: number }

-- Same "random" 0..1 for the same sticker every time the gun is built
local function hash(i: number, salt: number): number
	return ((i * 1103515245 + salt * 12345) // 65536) % 1000 / 1000
end

-- Points within `radius` of the middle on a grid, for a design's spots
local function grid(radius: number, step: number): { Vector2 }
	local spots = {}
	local n = math.floor(radius / step)
	for i = -n, n do
		for j = -n, n do
			local spot = Vector2.new(i, j) * step
			if spot.Magnitude <= radius then
				table.insert(spots, spot)
			end
		end
	end
	return spots
end

---------------------------------------------------------------------------------------------
-- Cat: a round white head, demon horns from its top corners (short and wide, pink inside with a
-- white rim), dot eyes, an ω mouth
---------------------------------------------------------------------------------------------
local WHITE = Color3.fromRGB(252, 250, 252)
local PINK = Color3.fromRGB(255, 178, 210)
local INK = Color3.fromRGB(26, 22, 28)

-- The right horn: its point, up at the head's top corner, and the two ends of its base, hidden
-- behind the head (the outer edge runs nearly straight up from the side of the head, the inner one
-- slopes down toward the middle). The left horn is its mirror. The pink inside is the same shape
-- shrunk toward the middle of the base, leaving a white rim.
local HORN_TIP = Vector2.new(0.41, 0.68)
local HORN_OUTER = Vector2.new(0.46, 0.2)
local HORN_INNER = Vector2.new(0.06, 0.46)
local HORN_PINK = 0.72

local function hornCorners(side: number, pink: boolean): (Vector2, Vector2, Vector2)
	local mirror = Vector2.new(side, 1)
	local tip, outer, inner = HORN_TIP * mirror, HORN_OUTER * mirror, HORN_INNER * mirror
	if pink then
		local middle = (outer + inner) / 2
		tip = middle + (tip - middle) * HORN_PINK
		outer = middle + (outer - middle) * HORN_PINK
		inner = middle + (inner - middle) * HORN_PINK
	end
	return tip, outer, inner
end

local catSpots = grid(0.5, 0.2)
for _, side in { -1, 1 } do
	local tip, outer, inner = hornCorners(side, false)
	local middle = (outer + inner) / 2
	for _, share in { 0.15, 0.45 } do
		table.insert(catSpots, tip + (middle - tip) * share)
	end
end

local CAT: Design = {
	parts = 15,
	top = 0.72,
	bottom = 0.5,
	gap = Vector2.new(1.75, 1.55),
	size = 0.045,
	turn = false,
	spots = catSpots,
	draw = function(kit)
		for _, side in { -1, 1 } do
			local tip, outer, inner = hornCorners(side, false)
			kit.triangle(tip, outer, inner, 0, WHITE)
			tip, outer, inner = hornCorners(side, true)
			kit.triangle(tip, outer, inner, 1, PINK)
			kit.disc(side * 0.19, 0.03, 3, 0.11, INK) -- eye
			-- Half the ω: a black dot with a white one over its top half leaves a little curve
			kit.disc(side * 0.07, -0.13, 3, 0.14, INK)
			kit.disc(side * 0.07, -0.09, 4, 0.14, WHITE)
		end
		kit.disc(0, 0, 2, 1, WHITE) -- head
	end,
}

---------------------------------------------------------------------------------------------
-- Cheeto: a lumpy, slightly bent cheese puff, with a shine and a little dust
---------------------------------------------------------------------------------------------
local CHEESE = Color3.fromRGB(255, 150, 35)
local CHEESE_DEEP = Color3.fromRGB(248, 136, 28)
local CHEESE_SHINE = Color3.fromRGB(255, 202, 112)
local CHEESE_DUST = Color3.fromRGB(214, 100, 18)
local LUMPS = { { -0.31, -0.03, 0.3 }, { -0.11, 0.04, 0.35 }, { 0.1, 0.04, 0.33 }, { 0.29, -0.03, 0.27 } }

local cheetoSpots = {}
for _, lump in LUMPS do
	table.insert(cheetoSpots, Vector2.new(lump[1], lump[2]))
end
for _, spot in { { -0.44, -0.03 }, { 0.41, -0.03 }, { -0.11, 0.2 }, { 0.1, -0.12 } } do
	table.insert(cheetoSpots, Vector2.new(spot[1], spot[2]))
end

local CHEETO: Design = {
	parts = 7,
	top = 0.5,
	bottom = 0.5,
	gap = Vector2.new(1.1, 1),
	size = 0.05,
	turn = true,
	spots = cheetoSpots,
	draw = function(kit)
		for i, lump in LUMPS do
			kit.disc(lump[1], lump[2], i % 2, lump[3], if i % 2 == 0 then CHEESE else CHEESE_DEEP)
		end
		kit.disc(-0.13, 0.12, 2, 0.09, CHEESE_SHINE)
		kit.disc(0.13, -0.03, 2, 0.05, CHEESE_DUST)
		kit.disc(-0.3, 0, 2, 0.045, CHEESE_DUST)
	end,
}

---------------------------------------------------------------------------------------------
-- Holds: a climbing-wall jug (three blobs in one bright colour) with its bolt in the middle,
-- every one its own colour and size
---------------------------------------------------------------------------------------------
local HOLD_COLORS = {
	Color3.fromRGB(225, 50, 50),
	Color3.fromRGB(40, 110, 225),
	Color3.fromRGB(60, 180, 80),
	Color3.fromRGB(245, 205, 40),
	Color3.fromRGB(150, 70, 210),
	Color3.fromRGB(245, 130, 30),
	Color3.fromRGB(240, 90, 170),
	Color3.fromRGB(30, 180, 180),
}
local BOLT = Color3.fromRGB(45, 45, 50)
local BOLT_HEAD = Color3.fromRGB(175, 178, 185)

local HOLDS: Design = {
	parts = 5,
	top = 0.5,
	bottom = 0.5,
	gap = Vector2.new(1.55, 1.4),
	size = 0.045,
	turn = true,
	spots = grid(0.42, 0.14),
	draw = function(kit, index)
		local color = HOLD_COLORS[math.floor(hash(index, 11) * #HOLD_COLORS) + 1]
		local s = 0.75 + hash(index, 5) * 0.3 -- (big jugs and little crimps)
		kit.disc(0, -0.04 * s, 0, 0.66 * s, color)
		kit.disc(0.19 * s, 0.14 * s, 1, 0.44 * s, color)
		kit.disc(-0.17 * s, 0.15 * s, 1, 0.4 * s, color)
		kit.disc(0, 0.03 * s, 2, 0.15 * s, BOLT)
		kit.disc(0, 0.03 * s, 3, 0.07 * s, BOLT_HEAD)
	end,
}

local DESIGNS: { [string]: Design } = { Cat = CAT, Cheeto = CHEETO, Holds = HOLDS }

---------------------------------------------------------------------------------------------
-- Drawing kits: flat parts on a gun, or frames in a menu
---------------------------------------------------------------------------------------------

-- A triangle as the two right-angled triangles either side of the line from its point square
-- onto its base: `along` the base (from the end on the left as you look at the point), `up`
-- toward the point, where that line meets the base, and each part's width
type Split = { along: Vector2, up: Vector2, foot: Vector2, height: number, left: number, right: number, start: Vector2 }
local function split(a: Vector2, b: Vector2, point: Vector2): Split
	local along = (b - a).Unit
	local up = Vector2.new(-along.Y, along.X)
	if (point - a):Dot(up) < 0 then
		a, b = b, a
		along, up = -along, -up
	end
	local foot = a + along * (point - a):Dot(along)
	return {
		along = along,
		up = up,
		foot = foot,
		height = (point - foot).Magnitude,
		left = (foot - a).Magnitude,
		right = (b - foot).Magnitude,
		start = a,
	}
end

local function makePart(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, shape: Enum.PartType | "Wedge" | nil)
	local part: BasePart
	if shape == "Wedge" then
		part = Instance.new("WedgePart")
	else
		local block = Instance.new("Part")
		block.Shape = (shape or Enum.PartType.Block) :: Enum.PartType
		part = block
	end
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part:SetAttribute("NoSkin", true)
	part.Parent = parent
end

-- Flat parts on a gun, centered on `frame` (X right, Y up, Z out of the surface), `width` studs across
local function partKit(parent: Instance, name: string, frame: CFrame, width: number): Kit
	local step = width * 0.009 -- each layer's front sits this far in front of the one below
	local thick = width * 0.025
	local function at(x: number, y: number, layer: number): CFrame
		return frame * CFrame.new(x * width, y * width, (layer + 1) * step - thick / 2)
	end
	return {
		disc = function(x, y, layer, diameter, color)
			local size = Vector3.new(thick, diameter * width, diameter * width)
			makePart(parent, name, size, at(x, y, layer) * FACE_OUT, color, Enum.PartType.Cylinder)
		end,
		-- A wedge either side of the line from the point down onto the base
		triangle = function(tip, a, b, layer, color)
			local s = split(a, b, tip)
			local base = at(s.foot.X, s.foot.Y, layer) * CFrame.Angles(0, 0, math.atan2(s.along.Y, s.along.X))
			for _, piece in { { s.right, 1 }, { s.left, -1 } } do
				local across, sign = piece[1], piece[2]
				if across > 0.001 then
					local cf = base * CFrame.new(sign * across / 2 * width, s.height / 2 * width, 0)
					if sign < 0 then
						cf *= CFrame.Angles(0, math.pi, 0) -- (mirrored: square corner on its right)
					end
					makePart(parent, name, Vector3.new(thick, s.height * width, across * width), cf * WEDGE_FLAT, color, "Wedge")
				end
			end
		end,
	}
end

-- Frames in a menu: `holder` is `size` pixels across (y runs down on screen)
local function guiKit(holder: Frame, size: number): Kit
	local function frame(at: Vector2, across: Vector2, layer: number, color: Color3): Frame
		local shape = Instance.new("Frame")
		shape.BorderSizePixel = 0
		shape.BackgroundColor3 = color
		shape.AnchorPoint = Vector2.new(0.5, 0.5)
		shape.Position = UDim2.new(0.5, at.X * size, 0.5, -at.Y * size)
		shape.Size = UDim2.fromOffset(across.X * size, across.Y * size)
		shape.ZIndex = layer + 1
		shape.Parent = holder
		return shape
	end
	return {
		disc = function(x, y, layer, diameter, color)
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0.5, 0)
			corner.Parent = frame(Vector2.new(x, y), Vector2.one * diameter, layer, color)
		end,
		-- A box on its base, turned to lie along it (GUI rotation turns an element around its middle,
		-- so the box is placed by its middle), filled by the two parts either side of the line from
		-- the point, each cut corner to corner by a hard-edged gradient
		triangle = function(tip, a, b, layer, color)
			local s = split(a, b, tip)
			local across = s.left + s.right
			local box = frame(s.start + s.along * across / 2 + s.up * s.height / 2, Vector2.new(across, s.height), layer, color)
			box.BackgroundTransparency = 1
			box.Rotation = -math.deg(math.atan2(s.along.Y, s.along.X))
			for _, piece in { { 0, s.left, 45 }, { s.left, s.right, 135 } } do
				if piece[2] <= 0.001 then
					continue
				end
				local half = Instance.new("Frame")
				half.BorderSizePixel = 0
				half.BackgroundColor3 = color
				half.Position = UDim2.fromScale(piece[1] / across, 0)
				half.Size = UDim2.fromScale(piece[2] / across, 1)
				half.ZIndex = layer + 1
				local cut = Instance.new("UIGradient")
				cut.Rotation = piece[3] -- (keeps the half below the diagonal from the point)
				cut.Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1),
					NumberSequenceKeypoint.new(0.499, 1),
					NumberSequenceKeypoint.new(0.501, 0),
					NumberSequenceKeypoint.new(1, 0),
				})
				cut.Parent = half
				half.Parent = box
			end
		end,
	}
end

-- One of a design's stickers as a little picture for menus (the shop's paint chip): `size` pixels
-- across, centered on `position`; `index` picks its angle / colour, like on the gun
function Stickers.Icon(parent: GuiObject, designName: string, size: number, position: UDim2, index: number)
	local design = DESIGNS[designName]
	if not design then
		return
	end
	local holder = Instance.new("Frame")
	holder.Name = "Sticker"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = position
	holder.Size = UDim2.fromOffset(size, size)
	if design.turn then
		holder.Rotation = hash(index, 3) * 360
	end
	holder.Parent = parent
	design.draw(guiKit(holder, size), index)
end

---------------------------------------------------------------------------------------------
-- Placing stickers on a gun
---------------------------------------------------------------------------------------------

-- The flat faces of a block that are on the outside (a rounded piece's inner boxes only count
-- where they reach the whole piece's surface), each with its up direction: straight up on the
-- sides, toward the muzzle (-Z) on top and underneath
local function facesOf(part: BasePart): { Face }
	local faces: { Face } = {}
	local cf, size = part.CFrame, part.Size
	local whole = part:GetAttribute("PieceSize")
	for _, axis in AXES do
		if typeof(whole) == "Vector3" and size:Dot(axis) < whole:Dot(axis) - 0.001 then
			continue
		end
		for _, sign in { 1, -1 } do
			local normal = cf:VectorToWorldSpace(axis * sign)
			local want = if math.abs(normal.Y) > 0.7 then -Vector3.zAxis else Vector3.yAxis
			local best, up = -math.huge, Vector3.zero
			for _, other in AXES do
				if other ~= axis then
					for _, s in { 1, -1 } do
						local lean = cf:VectorToWorldSpace(other * s):Dot(want)
						if lean > best then
							best, up = lean, other * s
						end
					end
				end
			end
			-- A rounded piece's flat faces stop where its edges start curving away; a sticker may reach
			-- a little way onto the curve (BEND of the way round), like a wrap
			local function span(along: Vector3): number
				local flat = math.abs(size:Dot(along))
				return if typeof(whole) == "Vector3" then flat + (math.abs(whole:Dot(along)) - flat) * BEND else flat
			end
			local upWorld = cf:VectorToWorldSpace(up)
			table.insert(faces, {
				part = part,
				frame = CFrame.fromMatrix(cf:PointToWorldSpace(axis * sign * size:Dot(axis) / 2), upWorld:Cross(normal), upWorld, normal),
				width = span(axis:Cross(up)),
				height = span(up),
			})
		end
	end
	return faces
end

-- How far off its face a sticker here has to sit to clear whatever's on the face under it (0 for
-- nothing); nil if something there sticks out too far, or another sticker is already on that spot
local function seat(frame: CFrame, width: number, spots: { Vector2 }, nearby: { BasePart }, placed: { Placed }): number?
	for _, other in placed do
		local offset = frame.Position - other.position
		if other.normal:Dot(frame.ZVector) > 0.9 and math.abs(offset:Dot(other.normal)) < 0.2 * width
			and offset.Magnitude < 0.45 * (width + other.width) then
			return nil
		end
	end
	local normal = frame.ZVector
	local base = 0.0005 -- (just off the face, clear of anything flush with it)
	local lift = 0
	for _, spot in spots do
		local point = frame:PointToWorldSpace(Vector3.new(spot.X * width, spot.Y * width, base))
		for _, part in nearby do
			local half = part.Size / 2
			if (point - part.Position).Magnitude > half.Magnitude then
				continue
			end
			local p = part.CFrame:PointToObjectSpace(point)
			if math.abs(p.X) < half.X and math.abs(p.Y) < half.Y and math.abs(p.Z) < half.Z then
				-- Inside it: how much further out does it reach?
				local n = part.CFrame:VectorToObjectSpace(normal)
				local reach = math.huge
				for _, axis in AXES do
					local d = n:Dot(axis)
					if math.abs(d) > 1e-6 then
						local h = half:Dot(axis)
						reach = math.min(reach, ((if d > 0 then h else -h) - p:Dot(axis)) / d)
					end
				end
				if base + reach > MAX_LIFT * width then
					return nil
				end
				lift = math.max(lift, base + reach)
			end
		end
	end
	return lift
end

-- Puts a design's stickers on `pieces` (the gun's big painted pieces) of a model at its built
-- size and spot. `knife`: sized for the knife (a gun's go by its length).
function Stickers.Cover(model: Model, pieces: { BasePart }, designName: string, knife: boolean?)
	local design = DESIGNS[designName]
	if not design then
		return
	end
	local extents = model:GetExtentsSize()
	local full = if knife then KNIFE_SIZE else math.clamp(math.max(extents.X, extents.Y, extents.Z) * design.size, MIN_SIZE, MAX_SIZE)
	local most = math.floor(MAX_PARTS / design.parts)
	local solids: { BasePart } = {}
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part.Transparency < 0.5 then
			table.insert(solids, part)
		end
	end
	local faces: { Face } = {}
	for _, part in pieces do
		if part:IsA("Part") and part.Shape == Enum.PartType.Block then
			for _, face in facesOf(part) do
				table.insert(faces, face)
			end
		end
	end
	-- The sides first (what everyone sees), then the top, the ends, underneath; biggest first within
	-- each (if the stickers run out, it's on the little ones)
	local function rank(face: Face): number
		local normal = face.frame.ZVector
		return if math.abs(normal.X) > 0.7 then 1 elseif normal.Y > 0.7 then 2 elseif normal.Y > -0.7 then 3 else 4
	end
	table.sort(faces, function(a, b)
		local ra, rb = rank(a), rank(b)
		if ra ~= rb then
			return ra < rb
		end
		return a.width * a.height > b.width * b.height
	end)

	local placed: { Placed } = {}
	local tall = design.top + design.bottom
	for _, face in faces do
		local width = math.min(full, face.width / (1 + 2 * MARGIN), face.height / (tall + 2 * MARGIN))
		if width < full * SHRINK then
			continue
		end
		-- Only what's near this face can be in the way
		local reach = Vector2.new(face.width, face.height).Magnitude / 2 + width
		local nearby: { BasePart } = {}
		for _, part in solids do
			if (part.Position - face.frame.Position).Magnitude < reach + (part.Size / 2).Magnitude then
				table.insert(nearby, part)
			end
		end
		local stepX, stepY = design.gap.X * width, design.gap.Y * width
		local columns = math.floor((face.width - (1 + 2 * MARGIN) * width) / stepX) + 1
		local rows = math.floor((face.height - (tall + 2 * MARGIN) * width) / stepY) + 1
		for row = 1, rows do
			-- Every other row one shorter, so the rows interlock
			local inRow = if row % 2 == 0 and columns > 1 then columns - 1 else columns
			local y = (row - (rows + 1) / 2) * stepY - (design.top - design.bottom) / 2 * width
			for column = 1, inRow do
				if #placed >= most then
					return
				end
				local index = #placed + 1
				local frame = face.frame * CFrame.new((column - (inRow + 1) / 2) * stepX, y, 0)
				if design.turn then
					frame *= CFrame.Angles(0, 0, hash(index, 3) * math.pi * 2)
				end
				local lift = seat(frame, width, design.spots, nearby, placed)
				if lift then
					design.draw(partKit(face.part.Parent :: Instance, face.part.Name, frame * CFrame.new(0, 0, lift), width), index)
					table.insert(placed, { position = frame.Position, normal = frame.ZVector, width = width })
				end
			end
		end
	end
end

return Stickers
