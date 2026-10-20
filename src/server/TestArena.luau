-- Builds a throwaway playground for testing movement.
-- Only runs if there's no "Map" in Workspace, so once you build a real map it stops spawning.

local Workspace = game:GetService("Workspace")

local Dummies = require(script.Parent.Dummies)

local TestArena = {}

local function block(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

function TestArena.Build()
	if Workspace:FindFirstChild("Map") or Workspace:FindFirstChild("TestArena") then
		return
	end

	local arena = Instance.new("Folder")
	arena.Name = "TestArena"
	arena.Parent = Workspace

	local grey = Color3.fromRGB(90, 95, 105)
	local orange = Color3.fromRGB(235, 130, 50)
	local blue = Color3.fromRGB(60, 130, 230)

	if not Workspace:FindFirstChild("Baseplate") then
		block(arena, "Floor", Vector3.new(400, 2, 400), CFrame.new(0, -1, 0), Color3.fromRGB(60, 62, 68))
	end

	-- Long range lane (orange marks every 20 studs)
	for i = 0, 8 do
		block(arena, "LaneMarker", Vector3.new(12, 0.2, 1), CFrame.new(-40, 0.1, -20 - i * 20), orange)
	end

	-- A ramp up onto a platform
	block(arena, "RampPlatform", Vector3.new(20, 12, 20), CFrame.new(30, 6, -60), grey)
	block(
		arena,
		"Ramp",
		Vector3.new(20, 1, 40),
		CFrame.new(30, 6, -31) * CFrame.Angles(math.rad(17), 0, 0),
		blue
	)

	-- Boxes of increasing height (vault / climb: only the lowest ones can be)
	for i = 1, 5 do
		local height = i * 3
		block(arena, "JumpBox", Vector3.new(8, height, 8), CFrame.new(-10 + i * 12, height / 2, 30), grey)
	end

	-- Two platforms with a gap between them (drops, landings)
	block(arena, "GapStart", Vector3.new(16, 10, 16), CFrame.new(70, 5, 20), grey)
	block(arena, "GapEnd", Vector3.new(16, 10, 16), CFrame.new(70, 5, -22), orange)

	-- Tall walls (rappel and lean practice)
	block(arena, "Wall", Vector3.new(2, 30, 40), CFrame.new(-80, 15, 20), blue)
	block(arena, "Wall", Vector3.new(2, 30, 40), CFrame.new(-100, 15, 20), blue)

	-- Peek practice: a wall with a doorway. Stand behind either side and lean (Q / E) to see the dummies.
	block(arena, "PeekWall", Vector3.new(20, 10, 2), CFrame.new(-14, 5, 80), grey)
	block(arena, "PeekWall", Vector3.new(20, 10, 2), CFrame.new(14, 5, 80), grey)
	block(arena, "PeekWallTop", Vector3.new(8, 3, 2), CFrame.new(0, 8.5, 80), grey)
	Dummies.Spawn(CFrame.new(6, 3, 96), true)
	Dummies.Spawn(CFrame.new(-8, 3, 104), true)
	Dummies.Spawn(CFrame.new(16, 3, 114), true)

	-- Range dummies down the lane (falloff testing)
	for _, distance in { 40, 90, 160 } do
		Dummies.Spawn(CFrame.new(-40, 3, -distance) * CFrame.Angles(0, math.pi, 0), true)
	end

	-- Spawn pads (RoundService looks for a "TeamSpawns" folder with Side = "Attack" / "Defend";
	-- players face the pad's front). Attackers come from the north, through the peek wall.
	local teamSpawns = Instance.new("Folder")
	teamSpawns.Name = "TeamSpawns"
	teamSpawns.Parent = arena
	local pads = {
		{ side = "Attack", cframe = CFrame.new(0, 0.1, 150), color = Color3.fromRGB(220, 70, 70) },
		{ side = "Defend", cframe = CFrame.new(0, 0.1, -30) * CFrame.Angles(0, math.pi, 0), color = blue },
	}
	for _, info in pads do
		local pad = block(teamSpawns, info.side .. "Spawn", Vector3.new(16, 0.2, 8), info.cframe, info.color)
		pad.CanCollide = false
		pad.Transparency = 0.4
		pad:SetAttribute("Side", info.side)
	end

	-- Plant sites (ObjectiveService looks for an "Objectives" folder with Site = "A" / "B")
	local objectives = Instance.new("Folder")
	objectives.Name = "Objectives"
	objectives.Parent = arena
	local sites = {
		{ name = "A", position = Vector3.new(20, 3, 50) },
		{ name = "B", position = Vector3.new(-60, 3, 15) },
	}
	for _, info in sites do
		local site = block(objectives, "Site" .. info.name, Vector3.new(16, 6, 16), CFrame.new(info.position), Color3.fromRGB(255, 200, 60))
		site.Transparency = 0.85
		site.CanCollide = false
		site.CanQuery = false
		site.CanTouch = false
		site:SetAttribute("Site", info.name)
	end

	local spawn = Instance.new("SpawnLocation")
	spawn.Anchored = true
	spawn.Size = Vector3.new(8, 1, 8)
	spawn.CFrame = CFrame.new(0, 0.5, 0)
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = arena
end

return TestArena
