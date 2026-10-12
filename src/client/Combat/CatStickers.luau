-- Cat-head stickers for skins with Stickers = "Cat" (shared/Skins): little white cat faces with
-- two pointed demon horns (pink inside), dot eyes and an ω mouth, in staggered rows over every big
-- flat face of the gun (or knife), all the way around it.
-- Each cat is built from flat parts stacked a hair apart (horns behind the head, the face in
-- front), so it shows wherever the gun does: in your hands, in other players' hands, in the shop's
-- preview. A sticker takes the name of the piece it's on, so it rides along when that piece moves
-- (a magazine coming out, a slide racking: Viewmodel moves pieces by name).
-- Only whole cats: a cat sits up over little flush details (slots, pins), but a spot where any bit
-- of one would sink into something bigger is skipped.

local CatStickers = {}

local WHITE = Color3.fromRGB(252, 250, 252)
local PINK = Color3.fromRGB(255, 158, 196)
local INK = Color3.fromRGB(26, 22, 28)

local SIZE = 0.045 -- a cat's width, as a share of the gun's length...
local MIN_SIZE, MAX_SIZE = 0.07, 0.14 -- ...kept between these (studs)
local SHRINK = 0.5 -- a face too small for a full-size cat gets one down to this share of it, or none
local BEND = 0.5 -- how far onto a rounded edge's curve a cat may reach (share of the way round)
local MAX_CATS = 44 -- per gun (each cat is 15 parts)
local MAX_LIFT = 0.12 -- a cat may sit up to this far off its face to clear small details (widths)
local GAP_X, GAP_Y = 1.75, 1.55 -- spacing between cats, in cat widths
local MARGIN = 0.08 -- kept clear along a face's edges, in cat widths
local TOP, BOTTOM = 0.84, 0.5 -- how far a cat reaches above (horn tips) and below its center, in widths

-- The horns, in cat widths from the middle of the head: where the right one's base sits (mostly
-- behind the head), how wide and tall it is, and how far it leans out. The left one is its mirror.
local HORN_X, HORN_Y = 0.25, 0.33
local HORN_BASE, HORN_HEIGHT = 0.28, 0.52
local HORN_LEAN = math.rad(18)
-- The pink inside: starts this far up the horn, this wide and tall (a stripe, with white all round)
local INNER_START, INNER_BASE, INNER_HEIGHT = 0.1, 0.1, 0.3

local FACE_OUT = CFrame.Angles(0, math.rad(90), 0) -- turns a cylinder's round side out of the surface
-- Lays a wedge flat: its triangle (square corner at the bottom left, point on top) in the sticker's
-- plane, its thickness out of the surface
local WEDGE_FLAT = CFrame.fromMatrix(Vector3.zero, Vector3.zAxis, Vector3.yAxis, -Vector3.xAxis)
local AXES = { Vector3.xAxis, Vector3.yAxis, Vector3.zAxis }

-- Where to check for room under a cat (cat widths): a grid over the head, and up each horn
local SPOTS: { Vector2 } = {}
for i = -2, 2 do
	for j = -2, 2 do
		local spot = Vector2.new(i, j) * 0.2
		if spot.Magnitude <= 0.5 then
			table.insert(SPOTS, spot)
		end
	end
end
for _, side in { -1, 1 } do
	for _, up in { 0.25, 0.38 } do
		table.insert(SPOTS, Vector2.new(side * (HORN_X + math.sin(HORN_LEAN) * up), HORN_Y + math.cos(HORN_LEAN) * up))
	end
end

type Face = { part: BasePart, frame: CFrame, width: number, height: number }
type Placed = { position: Vector3, normal: Vector3, width: number }

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

-- One cat, centered on `frame` (X right, Y up, Z out of the surface), `width` studs across.
-- Shapes are laid out in cat widths around the middle of the head.
local function drawCat(parent: Instance, name: string, frame: CFrame, width: number)
	local step = width * 0.009 -- each layer's front sits this far in front of the one below
	local thick = width * 0.025
	local function at(x: number, y: number, layer: number): CFrame
		return frame * CFrame.new(x * width, y * width, (layer + 1) * step - thick / 2)
	end
	local function disc(x: number, y: number, layer: number, diameter: number, color: Color3)
		local size = Vector3.new(thick, diameter * width, diameter * width)
		makePart(parent, name, size, at(x, y, layer) * FACE_OUT, color, Enum.PartType.Cylinder)
	end
	-- A pointed triangle standing on its base (middle at x, y), leaning `lean` radians
	-- (anticlockwise): two mirrored wedges back to back
	local function spike(x: number, y: number, layer: number, base: number, height: number, lean: number, color: Color3)
		local foot = at(x, y, layer) * CFrame.Angles(0, 0, lean)
		local size = Vector3.new(thick, height * width, base / 2 * width)
		for _, half in { 1, -1 } do
			local cf = foot * CFrame.new(half * base / 4 * width, height / 2 * width, 0)
			if half < 0 then
				cf *= CFrame.Angles(0, math.pi, 0)
			end
			makePart(parent, name, size, cf * WEDGE_FLAT, color, "Wedge")
		end
	end

	for _, side in { -1, 1 } do
		-- Horn: its base hidden behind the head, leaning out a little; pink inside
		local lean = -side * HORN_LEAN
		spike(side * HORN_X, HORN_Y, 0, HORN_BASE, HORN_HEIGHT, lean, WHITE)
		local inner = Vector2.new(side * HORN_X, HORN_Y) + Vector2.new(-math.sin(lean), math.cos(lean)) * INNER_START
		spike(inner.X, inner.Y, 1, INNER_BASE, INNER_HEIGHT, lean, PINK)
		disc(side * 0.19, 0.03, 3, 0.11, INK) -- eye
		-- Half the ω: a black dot with a white one over its top half leaves a little curve
		disc(side * 0.07, -0.13, 3, 0.14, INK)
		disc(side * 0.07, -0.09, 4, 0.14, WHITE)
	end
	disc(0, 0, 2, 1, WHITE) -- head
end

-- The same cat as a little picture for menus (the shop's paint chip): `size` pixels across,
-- centered on `position`
function CatStickers.Icon(parent: GuiObject, size: number, position: UDim2)
	local holder = Instance.new("Frame")
	holder.Name = "Cat"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = position
	holder.Size = UDim2.fromOffset(size, size)
	holder.Parent = parent
	-- (laid out like drawCat: cat widths from the middle of the head, but y runs down on screen)
	local function frame(at: Vector2, across: Vector2, layer: number, color: Color3, parentFrame: GuiObject?): Frame
		local shape = Instance.new("Frame")
		shape.BorderSizePixel = 0
		shape.BackgroundColor3 = color
		shape.AnchorPoint = Vector2.new(0.5, 0.5)
		shape.Position = UDim2.new(0.5, at.X * size, 0.5, -at.Y * size)
		shape.Size = UDim2.fromOffset(across.X * size, across.Y * size)
		shape.ZIndex = layer + 1
		shape.Parent = parentFrame or holder
		return shape
	end
	local function dot(x: number, y: number, diameter: number, layer: number, color: Color3)
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = frame(Vector2.new(x, y), Vector2.one * diameter, layer, color)
	end
	-- A pointed triangle: a box standing on the base's middle, turned to lean (GUI rotation turns an
	-- element around its middle, so the box is placed by its middle), filled by two halves each cut
	-- corner to corner by a hard-edged gradient
	local function spike(base: Vector2, across: number, height: number, lean: number, layer: number, color: Color3)
		local middle = base + Vector2.new(-math.sin(lean), math.cos(lean)) * height / 2
		local box = frame(middle, Vector2.new(across, height), layer, color)
		box.BackgroundTransparency = 1
		box.Rotation = -math.deg(lean)
		for _, half in { 0, 1 } do
			local piece = Instance.new("Frame")
			piece.BorderSizePixel = 0
			piece.BackgroundColor3 = color
			piece.Position = UDim2.fromScale(half * 0.5, 0)
			piece.Size = UDim2.fromScale(0.5, 1)
			piece.ZIndex = layer + 1
			local cut = Instance.new("UIGradient")
			cut.Rotation = if half == 0 then 45 else 135 -- (keeps the half below the diagonal from the point)
			cut.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.499, 1),
				NumberSequenceKeypoint.new(0.501, 0),
				NumberSequenceKeypoint.new(1, 0),
			})
			cut.Parent = piece
			piece.Parent = box
		end
	end
	for _, side in { -1, 1 } do
		local lean = -side * HORN_LEAN
		local foot = Vector2.new(side * HORN_X, HORN_Y)
		spike(foot, HORN_BASE, HORN_HEIGHT, lean, 0, WHITE)
		spike(foot + Vector2.new(-math.sin(lean), math.cos(lean)) * INNER_START, INNER_BASE, INNER_HEIGHT, lean, 1, PINK)
		dot(side * 0.19, 0.03, 0.11, 3, INK)
		dot(side * 0.07, -0.13, 0.14, 3, INK)
		dot(side * 0.07, -0.09, 0.14, 4, WHITE)
	end
	dot(0, 0, 1, 2, WHITE)
end

-- The flat faces of a block that are on the outside (a rounded piece's inner boxes only count
-- where they reach the whole piece's surface), each with its cat-up direction: straight up on the
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

-- How far off its face a cat here has to sit to clear whatever's on the face under it (0 for
-- nothing); nil if something there sticks out too far, or another cat is already on that spot
local function seat(frame: CFrame, width: number, nearby: { BasePart }, placed: { Placed }): number?
	for _, other in placed do
		local offset = frame.Position - other.position
		if other.normal:Dot(frame.ZVector) > 0.9 and math.abs(offset:Dot(other.normal)) < 0.2 * width
			and offset.Magnitude < 0.6 * (width + other.width) then
			return nil
		end
	end
	local normal = frame.ZVector
	local base = 0.0005 -- (just off the face, clear of anything flush with it)
	local lift = 0
	for _, spot in SPOTS do
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

-- Puts cats on `pieces` (the gun's big painted pieces) of a model at its built size and spot.
-- `catWidth`: studs (default: by the gun's length).
function CatStickers.Cover(model: Model, pieces: { BasePart }, catWidth: number?)
	local extents = model:GetExtentsSize()
	local full = catWidth or math.clamp(math.max(extents.X, extents.Y, extents.Z) * SIZE, MIN_SIZE, MAX_SIZE)
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
	-- each (if the cats run out, it's on the little ones)
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
	for _, face in faces do
		local width = math.min(full, face.width / (1 + 2 * MARGIN), face.height / (TOP + BOTTOM + 2 * MARGIN))
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
		local stepX, stepY = GAP_X * width, GAP_Y * width
		local columns = math.floor((face.width - (1 + 2 * MARGIN) * width) / stepX) + 1
		local rows = math.floor((face.height - (TOP + BOTTOM + 2 * MARGIN) * width) / stepY) + 1
		for row = 1, rows do
			-- Every other row one shorter, so the rows interlock
			local inRow = if row % 2 == 0 and columns > 1 then columns - 1 else columns
			local y = (row - (rows + 1) / 2) * stepY - (TOP - BOTTOM) / 2 * width
			for column = 1, inRow do
				if #placed >= MAX_CATS then
					return
				end
				local frame = face.frame * CFrame.new((column - (inRow + 1) / 2) * stepX, y, 0)
				local lift = seat(frame, width, nearby, placed)
				if lift then
					drawCat(face.part.Parent :: Instance, face.part.Name, frame * CFrame.new(0, 0, lift), width)
					table.insert(placed, { position = frame.Position, normal = frame.ZVector, width = width })
				end
			end
		end
	end
end

return CatStickers
