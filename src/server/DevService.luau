-- Handles dev panel actions. Only devs can use it: everyone in Studio, the game's owner,
-- and anyone whose UserId is in DEV_USER_IDS.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Dummies = require(script.Parent.Dummies)
local RoundService = require(script.Parent.RoundService)
local WeaponService = require(script.Parent.WeaponService)

local DevAction = ReplicatedStorage.Remotes.DevAction :: RemoteEvent

-- Add teammates' UserIds here to give them dev access in live servers
local DEV_USER_IDS: { number } = {}

local VALID_ABILITIES = { None = true, Dash = true, WallJump = true }

local DevService = {}

local function isDev(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	if game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId then
		return true
	end
	return table.find(DEV_USER_IDS, player.UserId) ~= nil
end

local actions: { [string]: (player: Player, arg: any) -> () } = {
	SetAbility = function(player, ability)
		if VALID_ABILITIES[ability] then
			player:SetAttribute("Ability", if ability == "None" then nil else ability)
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

	Heal = function(player)
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			humanoid.Health = humanoid.MaxHealth
		end
	end,

	RefillAmmo = function(player)
		WeaponService.Refill(player)
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
		player:SetAttribute("IsDev", isDev(player))
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
