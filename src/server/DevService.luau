-- Handles dev panel actions. Only the game's owner can use it (and anyone in a Studio test).
-- The server sets "IsDev" and checks it on every action; clients can't set it themselves.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Abilities = require(ReplicatedStorage.Shared.Abilities)
local MatchConfig = require(ReplicatedStorage.Shared.MatchConfig)
local AbilityService = require(script.Parent.AbilityService)
local Dummies = require(script.Parent.Dummies)
local MapService = require(script.Parent.MapService)
local RoundService = require(script.Parent.RoundService)
local ShopService = require(script.Parent.ShopService)
local WeaponService = require(script.Parent.WeaponService)

local DevAction = ReplicatedStorage.Remotes.DevAction :: RemoteEvent

local DevService = {}

local actions: { [string]: (player: Player, arg: any) -> () } = {
	SetAbility = function(player, ability)
		if ability == "None" then
			player:SetAttribute("Ability", nil)
		elseif typeof(ability) == "string" and Abilities[ability] then
			player:SetAttribute("Ability", ability)
		end
	end,

	SpawnDummy = function(player)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then
			return
		end
		-- 15 studs in front of you, facing you
		local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
		local position = root.Position + look.Unit * 15
		Dummies.Spawn(CFrame.lookAt(position, root.Position * Vector3.new(1, 0, 1) + Vector3.new(0, position.Y, 0)))
	end,

	ClearDummies = function()
		Dummies.ClearSpawned()
	end,

	ClearCovers = function()
		AbilityService.ClearDeployables()
	end,

	Heal = function(player)
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			humanoid.Health = humanoid.MaxHealth
		end
	end,

	GiveCredits = function(player)
		ShopService.Award(player, 1000, "DEV")
	end,

	RefillAmmo = function(player)
		WeaponService.Refill(player)
		AbilityService.ResetCharges(player)
	end,

	SetWeapon = function(player, weaponName)
		if typeof(weaponName) == "string" then
			WeaponService.SetWeapon(player, weaponName)
		end
	end,

	SetLoadoutMode = function(_, mode)
		RoundService.SetLoadoutMode(mode)
	end,

	SetGameMode = function(_, mode)
		RoundService.SetGameMode(mode)
	end,

	-- Which team someone plays on from the next match (RoundService.assignTeams); "Auto" = random
	SetTeam = function(_, arg)
		local target, team = typeof(arg) == "table" and arg.Player, typeof(arg) == "table" and arg.Team
		if typeof(target) == "Instance" and target:IsA("Player") and (team == "Auto" or table.find(MatchConfig.TeamOrder, team)) then
			target:SetAttribute("TeamPick", if team == "Auto" then nil else team)
		end
	end,

	-- Switching maps ends any running match and respawns everyone on the new map
	LoadMap = function(_, mapName)
		if typeof(mapName) ~= "string" then
			return
		end
		local wasRunning = RoundService.IsMatchRunning()
		RoundService.StopMatch()
		if not MapService.Load(mapName) then
			return
		end
		if not wasRunning then
			for _, other in Players:GetPlayers() do
				RoundService.SpawnFreeRoam(other)
			end
		end
	end,

	-- Between matches: free-roam on the map in first person (to test guns) or go back to the lobby
	GoToMap = function(player)
		player:SetAttribute("FreeRoamArea", "Map")
		RoundService.SpawnFreeRoam(player)
	end,

	GoToLobby = function(player)
		player:SetAttribute("FreeRoamArea", "Lobby")
		RoundService.SpawnFreeRoam(player)
	end,

	StartMatch = function()
		RoundService.ForceStart()
	end,

	EndRound = function()
		RoundService.EndRound()
	end,

	StopMatch = function()
		RoundService.StopMatch()
	end,
}

function DevService.Start()
	local function onPlayerAdded(player: Player)
		local owner = player.UserId == game.CreatorId
		if game.CreatorType == Enum.CreatorType.Group then
			local ok, rank = pcall(player.GetRankInGroup, player, game.CreatorId)
			owner = ok and rank == 255
		end
		player:SetAttribute("IsDev", RunService:IsStudio() or owner)
	end
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)

	DevAction.OnServerEvent:Connect(function(player, action, arg)
		if not player:GetAttribute("IsDev") or typeof(action) ~= "string" then
			return
		end
		local handler = actions[action]
		if handler then
			handler(player, arg)
		end
	end)
end

return DevService
