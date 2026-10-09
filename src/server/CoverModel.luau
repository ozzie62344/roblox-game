-- The look of the Deployable Cover: a steel ballistic shield built out of plain parts.
--
-- AbilityService makes one box part (6 wide x 4 tall x 0.8 thick) that does the real work: it
-- blocks players and bullets. Build() hides that box and welds the visible shield onto it, so
-- every piece rides along when the box is tweened up out of the ground. The visible pieces never
-- collide and never stop raycasts, so gameplay is exactly the box, no matter how detailed it looks.
--
-- Positions below are in the box's own space (studs from its center), laid out for that 6x4x0.8 size:
--   X = left/right (-3 to 3), Y = down/up (-2 to 2), Z = front/back (-0.4 to 0.4).
--   -Z is the armored front that faces the enemy; +Z is the back, facing the player who deployed it.
-- Nothing goes below Y = -2, so once it's in place nothing pokes through the floor.

local CoverModel = {}

-- The deploying player's hands grab the two carry handles (DeployArms on the client puts each
-- hand at X = ±1.1, on the top edge, 0.1 studs behind the back face), so the grips go exactly there.
local HANDLE_SPREAD = 1.1 -- keep in sync with DeployArms.HAND_SPREAD
local HANDLE_OUT = 0.1 -- keep in sync with DeployArms (size.Z / 2 + 0.1)

-- Colors
local STEEL = Color3.fromRGB(92, 98, 96) -- the armor plate
local DARK_STEEL = Color3.fromRGB(54, 57, 60) -- frame, trim, handle brackets
local GUARD = Color3.fromRGB(42, 44, 47) -- corner guards
local RIB = Color3.fromRGB(72, 77, 76) -- stiffeners on the back, legs
local BOLT = Color3.fromRGB(142, 146, 148) -- bolt heads, hinges
local RUBBER = Color3.fromRGB(28, 28, 30) -- window seal, grips, feet
local TINT = Color3.fromRGB(38, 56, 64) -- bulletproof glass
local HAZARD_YELLOW = Color3.fromRGB(226, 178, 36)
local HAZARD_BLACK = Color3.fromRGB(26, 26, 28)
local STENCIL = Color3.fromRGB(222, 224, 216)

local METAL = Enum.Material.Metal

-- Every visible piece goes through here: placed relative to the main part, welded to it (so it
-- follows the rise), and unable to collide, be touched or stop raycasts (so it can't snag players
-- or eat bullets; the main part does that).
local function attach(main: BasePart, part: BasePart, name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material): BasePart
	part.Name = name
	part.Size = size
	part.CFrame = main.CFrame * offset
	part.Color = color
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Anchored = false
	part.Massless = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	-- Tiny bits and flat paint layers skip shadows (cheaper, and you'd never notice them)
	part.CastShadow = size.Magnitude >= 1 and math.min(size.X, size.Y, size.Z) >= 0.05
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = main
	weld.Part1 = part
	weld.Parent = part
	part.Parent = main
	return part
end

-- A plain block filling the space between two opposite corners
local function block(main: BasePart, name: string, a: Vector3, b: Vector3, color: Color3, material: Enum.Material): BasePart
	local size = Vector3.new(math.abs(b.X - a.X), math.abs(b.Y - a.Y), math.abs(b.Z - a.Z))
	return attach(main, Instance.new("Part"), name, size, CFrame.new((a + b) / 2), color, material)
end

-- A block with any size and placement (for tilted pieces)
local function placed(main: BasePart, name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material): BasePart
	return attach(main, Instance.new("Part"), name, size, offset, color, material)
end

-- A wedge is a block sliced corner to corner (a ramp). Its full faces are its bottom and back;
-- the slope runs from the top-back edge down to the bottom-front edge.
local function wedge(main: BasePart, name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material): BasePart
	return attach(main, Instance.new("WedgePart"), name, size, offset, color, material)
end

-- Roblox cylinders run along their own X axis
local function cylinder(main: BasePart, name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material): BasePart
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Cylinder
	return attach(main, part, name, size, offset, color, material)
end

-- Turns `main` (the cover's hitbox) into a steel ballistic shield. Call it before parenting `main`.
function CoverModel.Build(main: BasePart, teamColor: Color3)
	-- The main part is only the hitbox now: invisible, but still solid and bulletproof
	main.Transparency = 1
	main.CastShadow = false
	main.Material = METAL -- footsteps on top of it sound like metal
	main.Color = STEEL

	-- FRAME: a thick steel rim around the edge. Its front edges are bevelled (angled back) so it
	-- doesn't read as a plain box, and the top corners are cut off at 45° and capped by corner guards.
	for _, side in { -1, 1 } do
		-- Side rails (the back 0.68 is square, the front 0.12 is the bevel wedge)
		block(main, "FrameSide", Vector3.new(side * 3, -2, -0.28), Vector3.new(side * 2.78, 1.4, 0.4), DARK_STEEL, METAL)
		-- Turned so the wedge runs up the rail and its slope faces forward and outward
		wedge(
			main,
			"FrameSideBevel",
			Vector3.new(3.4, 0.22, 0.12),
			CFrame.fromMatrix(Vector3.new(side * 2.89, -0.3, -0.34), Vector3.new(0, -side, 0), Vector3.new(side, 0, 0)),
			DARK_STEEL,
			METAL
		)
		-- Corner guard along the 45° cut: halfway along the cut, nudged inward by half its width
		placed(
			main,
			"CornerGuard",
			Vector3.new(0.6 * math.sqrt(2), 0.22, 0.78),
			CFrame.new(side * 2.622, 1.622, 0) * CFrame.Angles(0, 0, -side * math.pi / 4),
			GUARD,
			METAL
		)
	end
	-- Top rail with its bevel along the front edge (a plain wedge already slopes that way)
	block(main, "FrameTop", Vector3.new(-2.4, 1.78, -0.28), Vector3.new(2.4, 2, 0.4), DARK_STEEL, METAL)
	wedge(main, "FrameTopBevel", Vector3.new(4.8, 0.22, 0.12), CFrame.new(0, 1.89, -0.34), DARK_STEEL, METAL)
	-- Bottom rail sits on the ground, so it stays square
	block(main, "FrameBottom", Vector3.new(-2.78, -2, -0.4), Vector3.new(2.78, -1.78, 0.4), DARK_STEEL, METAL)

	-- ARMOR PLATE: sits just behind the frame's front face (so the rim stands proud of it), split
	-- into pieces around the viewing window. Its edges tuck into the frame, out of sight.
	local plate = block(main, "ArmorPlate", Vector3.new(-2.8, -1.8, -0.37), Vector3.new(2.8, 0.95, -0.13), STEEL, METAL)
	for _, side in { -1, 1 } do
		block(main, "ArmorPlate", Vector3.new(side * 0.75, 0.95, -0.37), Vector3.new(side * 2.8, 1.4, -0.13), STEEL, METAL)
		-- Triangle that follows the cut-off corner (wedge stood on its side, flat in the plate)
		wedge(
			main,
			"ArmorPlateCorner",
			Vector3.new(0.24, 0.4, 0.4),
			CFrame.fromMatrix(Vector3.new(side * 2.644, 1.6, -0.25), Vector3.new(0, 0, side), Vector3.new(0, 1, 0)),
			STEEL,
			METAL
		)
	end
	block(main, "ArmorPlate", Vector3.new(-2.444, 1.4, -0.37), Vector3.new(2.444, 1.8, -0.13), STEEL, METAL)

	-- Faded stencil lettering on the front
	local stencil = Instance.new("SurfaceGui")
	stencil.Name = "Stencil"
	stencil.Face = Enum.NormalId.Front
	stencil.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	stencil.PixelsPerStud = 40
	stencil.LightInfluence = 1 -- lit like the steel around it, not glowing
	stencil.MaxDistance = 80 -- not worth drawing from far away
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.45)
	label.Size = UDim2.fromScale(0.55, 0.12)
	label.Font = Enum.Font.Oswald
	label.TextScaled = true
	label.Text = "BALLISTIC SHIELD  -  LEVEL III"
	label.TextColor3 = STENCIL
	label.TextTransparency = 0.45
	label.Parent = stencil
	stencil.Parent = plate

	-- VIEWING WINDOW near the top: thick, dark tinted armored glass set into a rubber seal. It's fully
	-- opaque (shiny, but not see-through) so nobody can spot a player crouching behind the cover, just
	-- like the old solid box. It runs all the way through to the back skin, so it shows on both sides.
	local glass = block(main, "Window", Vector3.new(-0.75, 0.95, -0.31), Vector3.new(0.75, 1.4, 0.39), TINT, Enum.Material.Glass)
	glass.Transparency = 0
	glass.Reflectance = 0.3
	block(main, "WindowSeal", Vector3.new(-0.83, 1.4, -0.4), Vector3.new(0.83, 1.48, -0.3), RUBBER, Enum.Material.Rubber)
	block(main, "WindowSeal", Vector3.new(-0.83, 0.87, -0.4), Vector3.new(0.83, 0.95, -0.3), RUBBER, Enum.Material.Rubber)
	for _, side in { -1, 1 } do
		block(main, "WindowSeal", Vector3.new(side * 0.75, 0.95, -0.4), Vector3.new(side * 0.83, 1.4, -0.3), RUBBER, Enum.Material.Rubber)
	end

	-- TEAM STRIPE: painted band across the top, on the front and the back
	block(main, "TeamStripe", Vector3.new(-2.35, 1.58, -0.39), Vector3.new(2.35, 1.7, -0.35), teamColor, Enum.Material.SmoothPlastic)
	block(main, "TeamStripe", Vector3.new(-2.4, 1.83, 0.38), Vector3.new(2.4, 1.95, 0.42), teamColor, Enum.Material.SmoothPlastic)

	-- HAZARD STRIPES along the bottom of the front: yellow slashes painted on a black band. The ends
	-- of each slash hide inside the bottom rail and the trim strip above it, so the band has clean edges.
	block(main, "HazardBand", Vector3.new(-2.79, -1.8, -0.38), Vector3.new(2.79, -1.36, -0.35), HAZARD_BLACK, Enum.Material.Plastic)
	for i = -3, 3 do
		placed(
			main,
			"HazardStripe",
			Vector3.new(0.877, 0.28, 0.025),
			CFrame.new(i * 0.78, -1.58, -0.3775) * CFrame.Angles(0, 0, math.pi / 4),
			HAZARD_YELLOW,
			Enum.Material.Plastic
		)
	end
	block(main, "HazardTrim", Vector3.new(-2.78, -1.38, -0.4), Vector3.new(2.78, -1.16, -0.3), DARK_STEEL, METAL)

	-- BOLTS holding the plate to the frame (cylinders turned to face forward)
	for _, side in { -1, 1 } do
		for _, y in { -0.95, 0.1, 1.15 } do
			cylinder(
				main,
				"Bolt",
				Vector3.new(0.05, 0.13, 0.13),
				CFrame.new(side * 2.56, y, -0.39) * CFrame.Angles(0, math.pi / 2, 0),
				BOLT,
				METAL
			)
		end
	end

	-- BACK SKIN: a steel sheet that closes in the back of the frame, its face at Z = 0.39 (the hidden
	-- box's back face is 0.4). Without it the back would be hollow, and shots hitting the cover from
	-- behind would leave their bullet holes floating in mid-air. It's split into pieces around the
	-- window, and its top corners follow the corner guards' inner edge (the line X + Y = 4.09).
	block(main, "BackSkin", Vector3.new(-2.78, -1.78, 0.32), Vector3.new(2.78, 0.95, 0.39), STEEL, METAL)
	block(main, "BackSkin", Vector3.new(-0.75, 1.4, 0.32), Vector3.new(0.75, 1.78, 0.39), STEEL, METAL)
	for _, side in { -1, 1 } do
		block(main, "BackSkin", Vector3.new(side * 0.75, 0.95, 0.32), Vector3.new(side * 2.78, 1.31, 0.39), STEEL, METAL)
		block(main, "BackSkin", Vector3.new(side * 0.75, 1.31, 0.32), Vector3.new(side * 2.31, 1.78, 0.39), STEEL, METAL)
		-- Triangle that fills the cut-off corner (same trick as ArmorPlateCorner on the front)
		wedge(
			main,
			"BackSkinCorner",
			Vector3.new(0.07, 0.47, 0.47),
			CFrame.fromMatrix(Vector3.new(side * 2.545, 1.545, 0.355), Vector3.new(0, 0, side), Vector3.new(0, 1, 0)),
			STEEL,
			METAL
		)
	end

	-- BACK: stiffener ribs welded onto the skin (what the deploying player sees as it comes up). They
	-- stand a little proud of the back, which is fine because nothing visible collides. The cross rib
	-- and the upright ribs end at different depths so their back faces never overlap and flicker.
	block(main, "BackRib", Vector3.new(-2.78, -0.25, 0.38), Vector3.new(2.78, 0.05, 0.44), RIB, METAL)
	for _, side in { -1, 1 } do
		block(main, "BackRib", Vector3.new(side * 1.0, -1.78, 0.38), Vector3.new(side * 1.2, 1.78, 0.46), RIB, METAL)
	end

	for _, side in { -1, 1 } do
		-- CARRY HANDLE on top of each rib: a rubber grip between two steel brackets
		local handleX = side * HANDLE_SPREAD
		cylinder(main, "HandleGrip", Vector3.new(0.72, 0.13, 0.13), CFrame.new(handleX, 2, 0.4 + HANDLE_OUT), RUBBER, Enum.Material.Rubber)
		for _, along in { -1, 1 } do
			block(
				main,
				"HandleBracket",
				Vector3.new(handleX + along * 0.28, 1.8, 0.4),
				Vector3.new(handleX + along * 0.36, 2.07, 0.58),
				DARK_STEEL,
				METAL
			)
		end

		-- FOLD-OUT LEG: hinged on the back of the cross rib, angled down and back to a rubber foot on the ground
		local hinge = Vector3.new(side * 2.2, -0.1, 0.51)
		local foot = Vector3.new(side * 2.2, -1.92, 1.3)
		cylinder(main, "LegHinge", Vector3.new(0.26, 0.16, 0.16), CFrame.new(hinge), BOLT, METAL)
		placed(main, "Leg", Vector3.new(0.12, 0.12, (foot - hinge).Magnitude), CFrame.lookAt((hinge + foot) / 2, foot), RIB, METAL)
		block(main, "LegFoot", Vector3.new(side * 2.2 - 0.13, -2, 1.12), Vector3.new(side * 2.2 + 0.13, -1.94, 1.48), RUBBER, Enum.Material.Rubber)
	end
end

return CoverModel
