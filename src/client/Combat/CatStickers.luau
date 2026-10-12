-- Cat-head stickers for skins with Stickers = "Cat" (shared/Skins): little white cat faces with
-- pink inside the ears, dot eyes and an ω mouth, in staggered rows over every big flat face of the
-- gun (or knife), all the way around it.
-- Each cat is built from flat parts stacked a hair apart (ears behind the head, the face in
-- front), so it shows wherever the gun does: in your hands, in other players' hands, in the shop's
-- preview. A sticker takes the name of the piece it's on, so it rides along when that piece moves
-- (a magazine coming out, a slide racking: Viewmodel moves pieces by name).
-- Only whole cats: a spot where any bit of one would sink into another piece is skipped.

local CatStickers = {}

local WHITE = Color3.fromRGB(252, 250, 252)
local PINK = Color3.fromRGB(255, 158, 196)
local INK = Color3.fromRGB(26, 22, 28)

local SIZE = 0.045 -- a cat's width, as a share of the gun's length...
local MIN_SIZE, MAX_SIZE = 0.07, 0.14 -- ...kept between these (studs)
local SHRINK = 0.6 -- a face too small for a full-size cat gets one down to this share of it, or none
local MAX_CATS = 40 -- per gun (each cat is 11 parts)
local GAP_X, GAP_Y = 1.75, 1.55 -- spacing between cats, in cat widths
local MARGIN = 0.08 -- kept clear along a face's edges, in cat widths
local TOP, BOTTOM = 0.6, 0.5 -- how far a cat reaches above (ear tips) and below its center, in widths

local FACE_OUT = CFrame.Angles(0, math.rad(90), 0) -- turns a cylinder's round side out of the surface
local AXES = { Vector3.xAxis, Vector3.yAxis, Vector3.zAxis }

type Face = { part: BasePart, frame: CFrame, width: number, height: number }
type Placed = { position: Vector3, normal: Vector3, width: number }

local function makePart(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, shape: Enum.PartType?)
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = shape or Enum.PartType.Block
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
	-- A square turned so one corner points at `angle` (radians from +X), `reach` from its middle
	local function corner(x: number, y: number, layer: number, reach: number, angle: number, color: Color3)
		local side = reach * math.sqrt(2) * width
		makePart(parent, name, Vector3.new(side, side, thick), at(x, y, layer) * CFrame.Angles(0, 0, angle - math.pi / 4), color)
	end

	for _, side in { -1, 1 } do
		-- Ear: mostly hidden behind the head, its tip leaning out a little; pink inside
		local angle = math.rad(90 - side * 30)
		local x, y = side * 0.15, 0.28
		corner(x, y, 0, 0.36, angle, WHITE)
		corner(x + math.cos(angle) * 0.12, y + math.sin(angle) * 0.12, 1, 0.18, angle, PINK)
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
	local function shape(x: number, y: number, across: number, layer: number, color: Color3, round: boolean, turn: number?)
		local frame = Instance.new("Frame")
		frame.BorderSizePixel = 0
		frame.BackgroundColor3 = color
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Position = UDim2.new(0.5, x * size, 0.5, -y * size)
		frame.Size = UDim2.fromOffset(across * size, across * size)
		frame.Rotation = turn or 0
		frame.ZIndex = layer + 1
		if round then
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0.5, 0)
			corner.Parent = frame
		end
		frame.Parent = holder
	end
	for _, side in { -1, 1 } do
		local angle = 90 - side * 30
		local x, y = side * 0.15, 0.28
		local turn = 45 - angle -- (GUI rotation runs clockwise)
		shape(x, y, 0.36 * math.sqrt(2), 0, WHITE, false, turn)
		local tip = math.rad(angle)
		shape(x + math.cos(tip) * 0.12, y + math.sin(tip) * 0.12, 0.18 * math.sqrt(2), 1, PINK, false, turn)
		shape(side * 0.19, 0.03, 0.11, 3, INK, true)
		shape(side * 0.07, -0.13, 0.14, 3, INK, true)
		shape(side * 0.07, -0.09, 0.14, 4, WHITE, true)
	end
	shape(0, 0, 1, 2, WHITE, true)
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
			local upWorld = cf:VectorToWorldSpace(up)
			table.insert(faces, {
				part = part,
				frame = CFrame.fromMatrix(cf:PointToWorldSpace(axis * sign * size:Dot(axis) / 2), upWorld:Cross(normal), upWorld, normal),
				width = math.abs(size:Dot(axis:Cross(up))),
				height = math.abs(size:Dot(up)),
			})
		end
	end
	return faces
end

-- Room for a whole cat here: nothing else's box over any of its edges or its middle, and no other
-- cat already on (nearly) the same spot
local function clear(frame: CFrame, width: number, solids: { BasePart }, placed: { Placed }): boolean
	for _, other in placed do
		local offset = frame.Position - other.position
		if other.normal:Dot(frame.ZVector) > 0.9 and math.abs(offset:Dot(other.normal)) < 0.2 * width
			and offset.Magnitude < 0.6 * (width + other.width) then
			return false
		end
	end
	local lift = 0.05 -- just above the stack
	for _, spot in { { 0, 0 }, { -0.45, 0 }, { 0.45, 0 }, { 0, -0.45 }, { -0.33, 0.59 }, { 0.33, 0.59 } } do
		local point = frame:PointToWorldSpace(Vector3.new(spot[1], spot[2], lift) * width)
		for _, part in solids do
			local half = part.Size / 2
			if (point - part.Position).Magnitude > half.Magnitude then
				continue
			end
			local p = part.CFrame:PointToObjectSpace(point)
			if math.abs(p.X) < half.X and math.abs(p.Y) < half.Y and math.abs(p.Z) < half.Z then
				return false
			end
		end
	end
	return true
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
	-- Biggest faces first (if the cats run out, it's on the little ones)
	table.sort(faces, function(a, b)
		return a.width * a.height > b.width * b.height
	end)

	local placed: { Placed } = {}
	for _, face in faces do
		local width = math.min(full, face.width / (1 + 2 * MARGIN), face.height / (TOP + BOTTOM + 2 * MARGIN))
		if width < full * SHRINK then
			continue
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
				if clear(frame, width, solids, placed) then
					drawCat(face.part.Parent :: Instance, face.part.Name, frame, width)
					table.insert(placed, { position = frame.Position, normal = frame.ZVector, width = width })
				end
			end
		end
	end
end

return CatStickers
