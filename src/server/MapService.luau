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
local LightingService = require(script.Parent.LightingService)
local TestArena = require(script.Parent.TestArena)
local Bank = require(script.Parent.Maps.Bank)
local Flight9 = require(script.Parent.Maps.Flight9)
local House = require(script.Parent.Maps.House)
local Lobby = require(script.Parent.Maps.Lobby)
local MapCleanup = require(script.Parent.Maps.MapCleanup)
local Warehouse = require(script.Parent.Maps.Warehouse)

local MatchState = ReplicatedStorage.MatchState

local MapService = {}

local builders: { [string]: () -> Model } = {
	House = House.Build,
	Warehouse = Warehouse.Build,
	Flight9 = Flight9.Build,
	Bank = Bank.Build,
}

-- The maps players vote between before a match (the dev panel can also load the TestArena)
MapService.MapNames = { "House", "Warehouse", "Flight9", "Bank" }

-- Attackers pick one of their side's spawn pads during operator selection (Siege's spawn
-- select). Each map's pads are named by which side of the building they're on (+Z is north);
-- a pad that already has a "SpawnName" attribute (a Studio-built map) keeps it, and anything not
-- listed here gets a compass name.
local SPAWN_NAMES: { [string]: { [string]: string } } = {
	House = { South = "Front Street", North = "Back Alley", East = "Side Drive" },
	Warehouse = { South = "Truck Lot", North = "Rail Yard", East = "Car Park" },
	Flight9 = { South = "Checkpoint Road", North = "North Field", West = "Crash Scar" },
	Bank = { South = "Main Street", North = "Staff Lot", East = "Parking Lot" },
}

local function compass(position: Vector3): string
	if math.abs(position.Z) >= math.abs(position.X) then
		return if position.Z >= 0 then "North" else "South"
	end
	return if position.X >= 0 then "East" else "West"
end

-- Gives every attacker pad its name and publishes the list (MatchState "AttackSpawns",
-- "Front Street,Back Alley,Side Drive") for the client's spawn picker
local function nameAttackSpawns(name: string, mapRoot: Instance)
	local folder = mapRoot:FindFirstChild("TeamSpawns")
	local names = {}
	for _, pad in if folder then folder:GetChildren() else {} do
		if pad:IsA("BasePart") and pad:GetAttribute("Side") == "Attack" then
			local spawnName = pad:GetAttribute("SpawnName")
			if typeof(spawnName) ~= "string" then
				local direction = compass(pad.Position)
				spawnName = SPAWN_NAMES[name] and SPAWN_NAMES[name][direction] or `{direction} Side`
			end
			-- (two pads on the same side of an unlisted map: number them)
			local unique, n = spawnName, 1
			while table.find(names, unique) do
				n += 1
				unique = `{spawnName} {n}`
			end
			pad:SetAttribute("SpawnName", unique)
			table.insert(names, unique)
		end
	end
	table.sort(names)
	MatchState:SetAttribute("AttackSpawns", if #names > 0 then table.concat(names, ",") else nil)
end

-- The attackers' spawn pads on the loaded map (each with its "SpawnName")
function MapService.GetAttackSpawns(): { BasePart }
	local mapRoot = Workspace:FindFirstChild("Map") or Workspace:FindFirstChild("TestArena")
	local folder = mapRoot and mapRoot:FindFirstChild("TeamSpawns")
	local pads = {}
	for _, pad in if folder then folder:GetChildren() else {} do
		if pad:IsA("BasePart") and pad:GetAttribute("Side") == "Attack" then
			table.insert(pads, pad)
		end
	end
	return pads
end

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
	local loaded = Workspace:FindFirstChild("Map") or Workspace:FindFirstChild("TestArena")
	if loaded then
		nameAttackSpawns(name, loaded)
	end
	DestructionService.Reset()
	LightingService.Apply(name) -- (each map's own weather: overcast on Flight 9...)
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
