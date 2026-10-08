-- Attack / Defend objective: attackers plant a charge at site A or B (hold G inside the site),
-- defenders defuse it (hold G next to it) before it detonates.
-- Sites are parts with a "Site" attribute ("A" / "B") in <Map or TestArena>/Objectives.
-- RoundService starts/ends it each round and polls GetStatus().
-- Clients read MatchState attributes (BombSite, BombPosition, DetonateAt) and the player
-- attributes Interaction / InteractEndsAt (for the progress bar).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local MatchConfig = require(ReplicatedStorage.Shared.MatchConfig)

local Remotes = ReplicatedStorage.Remotes
local Interact = Remotes.Interact :: RemoteEvent
local ObjectiveEvent = Remotes.ObjectiveEvent :: RemoteEvent
local MatchState = ReplicatedStorage.MatchState

export type Status = "None" | "Planted" | "Defused" | "Detonated"

local ObjectiveService = {}

local active = false
local status: Status = "None"
local attackTeam: Team? = nil
local defendTeam: Team? = nil
local detonateAt = 0
local charge: BasePart? = nil
local interactors: { [Player]: { kind: string, endsAt: number } } = {}

local function getSites(): { BasePart }
	local mapRoot = Workspace:FindFirstChild("Map") or Workspace:FindFirstChild("TestArena")
	local folder = mapRoot and mapRoot:FindFirstChild("Objectives")
	local sites = {}
	if folder then
		for _, part in folder:GetChildren() do
			if part:IsA("BasePart") and part:GetAttribute("Site") then
				table.insert(sites, part)
			end
		end
	end
	return sites
end

-- Which site (if any) is this position standing in? Sites are boxes; height is generous.
local function siteAt(position: Vector3): BasePart?
	for _, site in getSites() do
		local localPos = site.CFrame:PointToObjectSpace(position)
		local half = site.Size / 2
		if math.abs(localPos.X) <= half.X and math.abs(localPos.Z) <= half.Z and math.abs(localPos.Y) <= half.Y + 4 then
			return site
		end
	end
	return nil
end

local function aliveRoot(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if humanoid and humanoid.Health > 0 and root and not root.Anchored then
		return root
	end
	return nil
end

local function canInteract(player: Player, kind: string): boolean
	local root = aliveRoot(player)
	if not active or not root then
		return false
	end
	if kind == "Plant" then
		return status == "None" and player.Team == attackTeam and siteAt(root.Position) ~= nil
	elseif kind == "Defuse" then
		return status == "Planted"
			and player.Team == defendTeam
			and charge ~= nil
			and (root.Position - charge.Position).Magnitude <= MatchConfig.DefuseRange
	end
	return false
end

local function stopInteracting(player: Player)
	interactors[player] = nil
	player:SetAttribute("Interaction", nil)
	player:SetAttribute("InteractEndsAt", nil)
end

local function clearInteractors()
	for player in interactors do
		stopInteracting(player)
	end
end

local function plant(player: Player)
	local root = aliveRoot(player) :: BasePart
	local site = siteAt(root.Position) :: BasePart

	-- Put the charge on the ground at the planter's feet
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character :: Model }
	local ground = Workspace:Raycast(root.Position, Vector3.new(0, -8, 0), params)
	local position = if ground then ground.Position + Vector3.new(0, 0.25, 0) else root.Position - Vector3.new(0, 2.7, 0)

	local device = Instance.new("Part")
	device.Name = "Charge"
	device.Size = Vector3.new(1.2, 0.5, 0.8)
	device.CFrame = CFrame.new(position) * CFrame.Angles(0, root.Orientation.Y * math.pi / 180, 0)
	device.Anchored = true
	device.CanCollide = false
	device.Color = Color3.fromRGB(40, 42, 46)
	device.Material = Enum.Material.Metal
	local light = Instance.new("Part")
	light.Name = "Light"
	light.Size = Vector3.new(0.2, 0.1, 0.2)
	light.CFrame = device.CFrame * CFrame.new(0, 0.3, 0)
	light.Anchored = true
	light.CanCollide = false
	light.CanQuery = false
	light.Material = Enum.Material.Neon
	light.Color = Color3.fromRGB(255, 40, 40)
	light.Parent = device
	device.Parent = Workspace
	charge = device

	status = "Planted"
	detonateAt = Workspace:GetServerTimeNow() + MatchConfig.FuseTime
	local siteName = site:GetAttribute("Site")
	MatchState:SetAttribute("BombSite", siteName)
	MatchState:SetAttribute("BombPosition", position)
	MatchState:SetAttribute("DetonateAt", detonateAt)
	clearInteractors()
	ObjectiveEvent:FireAllClients("Planted", siteName, position, player)
end

local function defuse(player: Player)
	status = "Defused"
	clearInteractors()
	ObjectiveEvent:FireAllClients("Defused", player)
end

local function detonate()
	status = "Detonated"
	clearInteractors()
	if charge then
		-- Visual only: the round ends on detonation anyway
		local explosion = Instance.new("Explosion")
		explosion.Position = charge.Position
		explosion.BlastRadius = 12
		explosion.BlastPressure = 0
		explosion.DestroyJointRadiusPercent = 0
		explosion.Parent = Workspace
		ObjectiveEvent:FireAllClients("Detonated", charge.Position)
		charge:Destroy()
		charge = nil
	end
end

local function update()
	if not active then
		return
	end
	local now = Workspace:GetServerTimeNow()
	for player, info in interactors do
		if not canInteract(player, info.kind) then
			stopInteracting(player)
		elseif now >= info.endsAt then
			if info.kind == "Plant" then
				plant(player)
			else
				defuse(player)
			end
			return -- the state changed; everyone else's interaction was cleared
		end
	end
	if status == "Planted" and now >= detonateAt then
		detonate()
	end
end

function ObjectiveService.BeginRound(attackers: Team, defenders: Team)
	ObjectiveService.EndRound()
	attackTeam, defendTeam = attackers, defenders
	active = true
	status = "None"
end

function ObjectiveService.EndRound()
	active = false
	status = "None"
	clearInteractors()
	if charge then
		charge:Destroy()
		charge = nil
	end
	MatchState:SetAttribute("BombSite", nil)
	MatchState:SetAttribute("BombPosition", nil)
	MatchState:SetAttribute("DetonateAt", nil)
end

function ObjectiveService.GetStatus(): Status
	return status
end

function ObjectiveService.Start()
	Interact.OnServerEvent:Connect(function(player, action)
		if action == "End" then
			stopInteracting(player)
			return
		end
		if action ~= "Begin" or interactors[player] then
			return
		end
		local kind = if player.Team == attackTeam then "Plant" else "Defuse"
		if not canInteract(player, kind) then
			return
		end
		local duration = if kind == "Plant" then MatchConfig.PlantTime else MatchConfig.DefuseTime
		local endsAt = Workspace:GetServerTimeNow() + duration
		interactors[player] = { kind = kind, endsAt = endsAt }
		player:SetAttribute("Interaction", kind)
		player:SetAttribute("InteractEndsAt", endsAt)
	end)
	Players.PlayerRemoving:Connect(function(player)
		interactors[player] = nil
	end)
	RunService.Heartbeat:Connect(update)
end

return ObjectiveService
