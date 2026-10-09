-- Loads maps. Every map is built in code and placed in Workspace as "Map" (the test arena
-- builds itself as "TestArena"). RoundService / ObjectiveService read spawns and sites from it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local MatchConfig = require(ReplicatedStorage.Shared.MatchConfig)
local Dummies = require(script.Parent.Dummies)
local TestArena = require(script.Parent.TestArena)
local House = require(script.Parent.Maps.House)

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

function MapService.Start()
	MapService.Load(MatchConfig.DefaultMap)
end

return MapService
