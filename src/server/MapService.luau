-- Loads maps into Workspace as "Map" (the test arena builds itself as "TestArena").
-- Every map (and the lobby) goes through MapCleanup first: no flickering where surfaces overlap.
-- A map built in Studio (ServerStorage/Maps/<name>, saved in the place file, not in Rojo) wins
-- over the code-built version. RoundService / ObjectiveService read spawns and sites from it.

local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local MatchConfig = require(ReplicatedStorage.Shared.MatchConfig)
local CameraService = require(script.Parent.CameraService)
local Dummies = require(script.Parent.Dummies)
local DestructionService = require(script.Parent.DestructionService)
local FortifyService = require(script.Parent.FortifyService)
local TestArena = require(script.Parent.TestArena)
local Chalet = require(script.Parent.Maps.Chalet)
local House = require(script.Parent.Maps.House)
local Lobby = require(script.Parent.Maps.Lobby)
local MapCleanup = require(script.Parent.Maps.MapCleanup)
local Warehouse = require(script.Parent.Maps.Warehouse)

local MatchState = ReplicatedStorage.MatchState

local MapService = {}

local builders: { [string]: () -> Model } = {
	House = House.Build,
	Warehouse = Warehouse.Build,
	Chalet = Chalet.Build,
}

-- The maps players vote between before a match (the dev panel can also load the TestArena)
MapService.MapNames = { "House", "Warehouse", "Chalet" }

function MapService.Load(name: string): boolean
	if name ~= "TestArena" and not builders[name] then
		return false
	end

	-- Clear whatever was there
	for _, existingName in { "Map", "TestArena", "Deployables" } do
		local existing = Workspace:FindFirstChild(existingName)
		if existing then
			existing:Destroy()
		end
	end
	Dummies.ClearAll()

	if name == "TestArena" then
		TestArena.Build()
		local arena = Workspace:FindFirstChild("TestArena")
		if arena then
			MapCleanup.Run(arena)
		end
	else
		local studioMaps = ServerStorage:FindFirstChild("Maps")
		local studioMap = studioMaps and studioMaps:FindFirstChild(name)
		local map = if studioMap then studioMap:Clone() else builders[name]()
		map.Name = "Map"
		for _, part in map:GetDescendants() do
			if part:IsA("BasePart") and part.Name == "RailGuard" then
				part.CollisionGroup = "Guards"
			end
		end
		MapCleanup.Run(map)
		FortifyService.Prepare(map)
		CameraService.Build(name, map)
		map.Parent = Workspace
	end
	DestructionService.Reset()
	MatchState:SetAttribute("Map", name)
	return true
end

-- Where players stand in the lobby (between matches)
function MapService.GetLobbySpawn(): CFrame?
	local lobby = Workspace:FindFirstChild("Lobby")
	local pad = lobby and lobby:FindFirstChild("LobbySpawn", true) :: BasePart?
	return pad and pad.CFrame
end

-- Where players stand when free-roaming on the current map (dev testing between matches)
function MapService.GetMapSpawn(): CFrame?
	local mapRoot = Workspace:FindFirstChild("Map") or Workspace:FindFirstChild("TestArena")
	local spawn = mapRoot and mapRoot:FindFirstChildWhichIsA("SpawnLocation", true)
	return spawn and spawn.CFrame
end

function MapService.Start()
	-- Railing guards (invisible walls that stop people falling off balconies and stairs) block
	-- characters and nothing else. Roblox ignores CanQuery = false on anything that collides, so
	-- they'd stop bullets and line-of-sight checks too; raycasts use the Default group, which
	-- guards don't collide with. (RoundService puts characters in "Characters".)
	PhysicsService:RegisterCollisionGroup("Characters")
	PhysicsService:RegisterCollisionGroup("Guards")
	PhysicsService:CollisionGroupSetCollidable("Guards", "Default", false)

	-- The lobby always exists, floating above whatever map is loaded
	local lobby = Lobby.Build()
	MapCleanup.Run(lobby)
	lobby.Parent = Workspace
	MapService.Load(MatchConfig.DefaultMap)
end

return MapService
