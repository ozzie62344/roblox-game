-- Attack / Defend objective (Siege's Bomb mode): a bomb sits in site A and B and the defenders
-- guard them. Attackers plant a defuser inside either site (hold G); if it runs for DefuserTime
-- the bomb is defused and the attackers win, unless a defender disables it first (hold G next to it).
-- Sites are parts with a "Site" attribute ("A" / "B") in <Map or TestArena>/Objectives. Maps with
-- several site pairs also give each site a "Pair"; only the pair the defenders picked is in play.
-- RoundService places the bombs when the pick is locked in, starts/ends rounds and polls GetStatus().
-- Clients read MatchState attributes (DefuserSite, DefuserPosition, DefusedAt) and the player
-- attributes Interaction / InteractEndsAt (for the progress bar).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local MatchConfig = require(ReplicatedStorage.Shared.MatchConfig)
local MatchStats = require(script.Parent.MatchStats)
local ProgressService = require(script.Parent.ProgressService)
local ShopService = require(script.Parent.ShopService)

local Remotes = ReplicatedStorage.Remotes
local Interact = Remotes.Interact :: RemoteEvent
local ObjectiveEvent = Remotes.ObjectiveEvent :: RemoteEvent
local MatchState = ReplicatedStorage.MatchState

-- "Defused": the attackers' defuser finished (they win). "Disabled": a defender stopped it.
export type Status = "None" | "Planted" | "Disabled" | "Defused"

local ObjectiveService = {}

local active = false
local status: Status = "None"
local attackTeam: Team? = nil
local defendTeam: Team? = nil
local defusedAt = 0
local defuser: BasePart? = nil
local plantedSite: BasePart? = nil
local bombs: { [BasePart]: Model } = {}
local interactors: { [Player]: { kind: string, endsAt: number } } = {}

local function allSites(): { BasePart }
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

-- Sites in play: the pair the defenders picked (MatchState "SitePair", set by RoundService), plus
-- any site that isn't part of a pair
local function getSites(): { BasePart }
	local picked = MatchState:GetAttribute("SitePair")
	local sites = {}
	for _, site in allSites() do
		local pair = site:GetAttribute("Pair")
		if pair == nil or picked == nil or pair == picked then
			table.insert(sites, site)
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
	elseif kind == "Disable" then
		return status == "Planted"
			and player.Team == defendTeam
			and defuser ~= nil
			and (root.Position - defuser.Position).Magnitude <= MatchConfig.DisableRange
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

	-- Put the defuser on the ground at the planter's feet
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character :: Model }
	local ground = Workspace:Raycast(root.Position, Vector3.new(0, -8, 0), params)
	local position = if ground then ground.Position + Vector3.new(0, 0.25, 0) else root.Position - Vector3.new(0, 2.7, 0)

	local device = Instance.new("Part")
	device.Name = "Defuser"
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
	defuser = device
	plantedSite = site

	status = "Planted"
	defusedAt = Workspace:GetServerTimeNow() + MatchConfig.DefuserTime
	local siteName = site:GetAttribute("Site")
	MatchState:SetAttribute("DefuserSite", siteName)
	MatchState:SetAttribute("DefuserPosition", position)
	MatchState:SetAttribute("DefusedAt", defusedAt)
	clearInteractors()
	ObjectiveEvent:FireAllClients("Planted", siteName, position, player)
	ShopService.Award(player, MatchConfig.Credits.Plant, "DEFUSER PLANTED")
	ProgressService.Record(player, "Plant")
	MatchStats.Objective(player)
end

local function disable(player: Player)
	status = "Disabled"
	clearInteractors()
	ObjectiveEvent:FireAllClients("Disabled", player)
	ShopService.Award(player, MatchConfig.Credits.Disable, "DEFUSER DISABLED")
	ProgressService.Record(player, "Disable")
	MatchStats.Objective(player)
end

-- The defuser ran out its timer: the bomb at that site is safe, its light goes green
local function bombDefused()
	status = "Defused"
	clearInteractors()
	local bomb = plantedSite and bombs[plantedSite]
	local light = bomb and bomb:FindFirstChild("Light") :: BasePart?
	if light then
		light.Color = Color3.fromRGB(60, 255, 110)
	end
	ObjectiveEvent:FireAllClients("Defused")
end

local BOMB_SIZE = Vector3.new(1.8, 1, 1.2)
-- Where a bomb may go, as offsets from the middle of its site: the middle first, then rings 2 and 4 studs out
local BOMB_SPOTS = { Vector2.zero }
for _, r in { 2, 4 } do
	for _, d in { Vector2.new(1, 0), Vector2.new(-1, 0), Vector2.new(0, 1), Vector2.new(0, -1), Vector2.new(1, 1), Vector2.new(-1, 1), Vector2.new(1, -1), Vector2.new(-1, -1) } do
		table.insert(BOMB_SPOTS, d * r)
	end
end

-- The first spot with something solid to sit on (floor, table, bench: no higher than a table) and
-- no furniture in the way
local function bombSpot(site: BasePart, mapRoot: Instance): CFrame
	local ray = RaycastParams.new()
	ray.FilterType = Enum.RaycastFilterType.Include
	ray.FilterDescendantsInstances = { mapRoot }
	ray.RespectCanCollide = true
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Include
	overlap.FilterDescendantsInstances = { mapRoot }
	overlap.RespectCanCollide = true
	local floorY = site.Position.Y - site.Size.Y / 2
	for _, offset in BOMB_SPOTS do
		local top = Vector3.new(site.Position.X + offset.X, floorY + site.Size.Y, site.Position.Z + offset.Y)
		local hit = Workspace:Raycast(top, Vector3.new(0, -site.Size.Y - 2, 0), ray)
		if hit and hit.Instance.Transparency < 1 and hit.Position.Y - floorY <= 3.5 then
			local cf = CFrame.new(hit.Position + Vector3.new(0, BOMB_SIZE.Y / 2 + 0.05, 0))
			if #Workspace:GetPartBoundsInBox(cf, BOMB_SIZE, overlap) == 0 then
				return cf
			end
		end
	end
	return CFrame.new(site.Position.X, floorY + BOMB_SIZE.Y / 2, site.Position.Z)
end

-- A bomb: a dark case with a screen and a red light
local function buildBomb(site: BasePart, parent: Instance): Model
	local cf = bombSpot(site, parent)
	local bomb = Instance.new("Model")
	bomb.Name = "Bomb" .. tostring(site:GetAttribute("Site"))
	local function part(name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = cf * offset
		p.Color = color
		p.Material = material
		p.Anchored = true
		p.Parent = bomb
		return p
	end
	bomb.PrimaryPart = part("Case", BOMB_SIZE, CFrame.new(), Color3.fromRGB(45, 47, 52), Enum.Material.Metal)
	part("Screen", Vector3.new(0.8, 0.05, 0.5), CFrame.new(-0.3, 0.52, 0), Color3.fromRGB(20, 40, 30), Enum.Material.Glass)
	part("Light", Vector3.new(0.18, 0.1, 0.18), CFrame.new(0.55, 0.53, -0.3), Color3.fromRGB(255, 40, 40), Enum.Material.Neon).CanCollide = false
	for _, x in { -0.75, 0.75 } do
		part("Strap", Vector3.new(0.12, 1.04, 1.24), CFrame.new(x, 0, 0), Color3.fromRGB(190, 160, 60), Enum.Material.Fabric)
	end
	bomb.Parent = parent
	return bomb
end

-- Puts a bomb in each site in play (call once the defenders' pick is final). The map is rebuilt
-- every round, so last round's bombs are already gone.
function ObjectiveService.PlaceBombs()
	table.clear(bombs)
	local mapRoot = Workspace:FindFirstChild("Map") or Workspace:FindFirstChild("TestArena")
	if not mapRoot then
		return
	end
	for _, site in getSites() do
		bombs[site] = buildBomb(site, mapRoot)
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
				disable(player)
			end
			return -- the state changed; everyone else's interaction was cleared
		end
	end
	if status == "Planted" and now >= defusedAt then
		bombDefused()
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
	if defuser then
		defuser:Destroy()
		defuser = nil
	end
	plantedSite = nil
	MatchState:SetAttribute("DefuserSite", nil)
	MatchState:SetAttribute("DefuserPosition", nil)
	MatchState:SetAttribute("DefusedAt", nil)
end

function ObjectiveService.GetStatus(): Status
	return status
end

-- The sites in play this round (the defended pair, or every site on maps without pairs)
ObjectiveService.GetActiveSites = getSites

-- The map's site pairs, e.g. { "Basement", "Bedrooms", "Kitchen", "Office" } (empty if it has none)
function ObjectiveService.GetPairs(): { string }
	local found = {}
	for _, site in allSites() do
		local pair = site:GetAttribute("Pair")
		if pair and not table.find(found, pair) then
			table.insert(found, pair)
		end
	end
	table.sort(found)
	return found
end

function ObjectiveService.Start()
	Interact.OnServerEvent:Connect(function(player, action, kind)
		if action == "End" then
			stopInteracting(player)
			return
		end
		-- Barricades / reinforcements share the G key but are FortifyService's job
		if action ~= "Begin" or kind == "Barricade" or kind == "Reinforce" or kind == "Unbarricade" or interactors[player] then
			return
		end
		local kind = if player.Team == attackTeam then "Plant" else "Disable"
		if not canInteract(player, kind) then
			return
		end
		for _, info in interactors do
			if kind == "Plant" and info.kind == "Plant" then
				return -- one planter at a time
			end
		end
		local duration = if kind == "Plant" then MatchConfig.PlantTime else MatchConfig.DisableTime
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
