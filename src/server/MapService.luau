-- Loads maps. Every map is built in code and placed in Workspace as "Map" (the test arena
-- builds itself as "TestArena"). RoundService / ObjectiveService read spawns and sites from it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local MatchConfig = require(ReplicatedStorage.Shared.MatchConfig)
local Dummies = require(script.Parent.Dummies)
local TestArena = require(script.Parent.TestArena)
local House = require(script.Parent.Maps.House)
local Lobby = require(script.Parent.Maps.Lobby)

local MatchState = ReplicatedStorage.MatchState

local MapService = {}

local builders: { [string]: () -> Model } = {
	House = House.Build,
}

MapService.MapNames = { "House", "TestArena" }

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
	else
		local map = builders[name]()
		map.Name = "Map"
		map.Parent = Workspace
	end
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
	-- The lobby always exists, floating above whatever map is loaded
	local lobby = Lobby.Build()
	lobby.Parent = Workspace
	MapService.Load(MatchConfig.DefaultMap)
end

return MapService
