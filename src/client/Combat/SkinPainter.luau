-- Repaints a freshly built gun or knife in a skin (shared/Skins says what each pattern does).
-- Runs on the model at its built size, before anything else is added to it. Parts with the
-- "NoSkin" attribute (bores, lenses, brass, glowing sights) and glass / neon parts keep their look.
-- Rainbow skins: their glowing pieces are tagged and Start() cycles their color every frame, the
-- hue running along the gun so the colors flow from the stock to the muzzle.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Skins = require(ReplicatedStorage.Shared.Skins)
local GunMaterials = require(script.Parent.GunMaterials)

local SkinPainter = {}

local RAINBOW_TAG = "SkinRainbow"
local RAINBOW_SPEED = 0.12 -- trips around the color wheel per second
local RAINBOW_VALUE = 0.62 -- kept dim like the other neon trims

local KEEP = {
	[Enum.Material.Glass] = true,
	[Enum.Material.Neon] = true,
	[Enum.Material.ForceField] = true,
}

-- Same "random" number for the same piece every time the gun is built
local function hash(i: number, salt: number): number
	return ((i * 1103515245 + salt * 12345) // 65536) % 1000
end

local function paint(part: BasePart, color: Color3, material: Enum.Material, reflectance: number?)
	part.Color = color
	part.Material = material
	part.MaterialVariant = GunMaterials.VariantFor(material)
	part.Reflectance = reflectance or 0
	if material == Enum.Material.ForceField then
		part.CastShadow = false
	end
end

-- Glowing trim; on a rainbow skin it joins the color cycle (`along` 0..1: where it sits on the gun)
local function glow(part: BasePart, skin: Skins.Skin, along: number)
	paint(part, skin.Trim, skin.TrimMaterial)
	if skin.Rainbow then
		part:SetAttribute("RainbowOffset", along * 0.6)
		CollectionService:AddTag(part, RAINBOW_TAG)
	end
end

-- A touch lighter or darker per piece so neighbouring pieces don't melt into one blob
local function shade(color: Color3, i: number): Color3
	local amount = (hash(i, 7) / 1000 - 0.5) * 0.12
	return if amount > 0 then color:Lerp(Color3.new(1, 1, 1), amount) else color:Lerp(Color3.new(), -amount)
end

local function skinnable(part: Instance): boolean
	return part:IsA("BasePart") and not part:GetAttribute("NoSkin") and not KEEP[part.Material] and part.Transparency == 0
end

-- A gun from GunModels: -Z out of the muzzle
function SkinPainter.PaintGun(model: Model, skin: Skins.Skin)
	local extents = model:GetExtentsSize()
	local length = math.max(extents.X, extents.Y, extents.Z)
	local big = length * 0.07 -- pieces at least this long count as the gun's main surfaces
	local front = model:GetBoundingBox().Position.Z - extents.Z / 2
	local band = extents.Z / 9
	local colors = skin.Colors

	-- Rounded pieces (GunModels) are painted as one: their edge pieces follow the main box
	local mains: { [number]: BasePart } = {}
	for _, part in model:GetDescendants() do
		local piece = part:GetAttribute("Piece")
		if piece and not part:GetAttribute("Edge") then
			mains[piece] = part :: BasePart
		end
	end

	for i, part in model:GetDescendants() do
		if not skinnable(part) then
			continue
		end
		local p = part :: BasePart
		local piece = p:GetAttribute("Piece")
		local ref = if piece then mains[piece] or p else p
		local key = if piece then 5000 + piece else i
		local size = p:GetAttribute("PieceSize") or p.Size -- (a rounded piece counts as its whole box)
		local longest = math.max(size.X, size.Y, size.Z)
		local shortest = math.min(size.X, size.Y, size.Z)
		if skin.TrimMaterial == Enum.Material.Neon then
			-- Glowing trim only lights up long thin strips (rails, spines, edges): a few lines, not
			-- every screw and rail tooth (too much glow right in front of your face); everything
			-- else matches the body
			if longest >= big * 0.6 and shortest < big * 0.3 and longest / shortest > 4 then
				glow(p, skin, (ref.Position.Z - front) / extents.Z)
				continue
			end
		elseif longest < big then
			paint(p, skin.Trim, skin.TrimMaterial) -- small piece: trim
			continue
		end
		local color = colors[1]
		if skin.Pattern == "Camo" then
			color = colors[hash(key, 3) % #colors + 1]
		elseif skin.Pattern == "Stripes" then
			color = colors[math.floor((ref.Position.Z - front) / band) % #colors + 1]
		end
		paint(p, shade(color, key), skin.Material, skin.Reflectance)
	end
end

-- A knife from GunModels.BuildKnife: Blade + Tip + Edge, Guard + Pommel, Handle
function SkinPainter.PaintKnife(model: Model, skin: Skins.Skin)
	local colors = skin.Colors
	local glowing = skin.TrimMaterial == Enum.Material.Neon
	local handle = colors[2] or (if glowing then colors[1]:Lerp(Color3.new(), 0.3) else skin.Trim)
	for _, part in model:GetChildren() do
		if not part:IsA("BasePart") then
			continue
		end
		if part.Name == "Blade" or part.Name == "Tip" then
			paint(part, colors[1], skin.Material, skin.Reflectance)
		elseif part.Name == "Edge" then
			-- Glowing skins light up the edge; the rest get a brighter bevel of the blade color
			if glowing then
				glow(part, skin, 0)
			else
				paint(part, colors[1]:Lerp(Color3.new(1, 1, 1), 0.25), skin.Material, skin.Reflectance)
			end
		elseif part.Name == "Guard" or part.Name == "Pommel" then
			paint(part, skin.Trim, if glowing then Enum.Material.Metal else skin.TrimMaterial)
		elseif part.Name == "Handle" then
			paint(part, handle, if skin.Material == Enum.Material.ForceField then skin.Material else Enum.Material.Plastic)
		end
	end
end

-- Keeps rainbow trims cycling (on every gun on screen: yours, other players', the shop's)
function SkinPainter.Start()
	RunService.RenderStepped:Connect(function()
		local hue = os.clock() * RAINBOW_SPEED
		for _, part in CollectionService:GetTagged(RAINBOW_TAG) do
			local offset = part:GetAttribute("RainbowOffset") or 0
			(part :: BasePart).Color = Color3.fromHSV((hue + offset) % 1, 0.9, RAINBOW_VALUE)
		end
	end)
end

return SkinPainter
