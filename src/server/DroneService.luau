-- Siege-style scout drones for the attacking team. During the defenders' setup (Prep) every
-- attacker drives one out from spawn; during the round Z jumps back into it, or throws your
-- second one if it's gone (2 per round); after you die Z still gets you back into a drone you left
-- out. Drones drive and hop (client-owned physics, see
-- DroneController), spot enemies for the whole team (click), and find the site: once a drone (or,
-- during the round, an attacker's own eyes) gets a clear view of the defended site, it's revealed
-- to the attackers (MatchState "SiteFound"). Any bullet or knife destroys a drone (Breakable =
-- "Gadget"). Near an enemy Signal Jammer the feed breaks up (DroneController) and the drone can't
-- spot or find the site. While free roaming anyone can drive one, as many as they like.
-- A player's "Droning" attribute says they're driving (their body stays where it is meanwhile);
-- "DronesLeft" is how many they can still throw this round.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local GadgetService = require(script.Parent.GadgetService)
local ObjectiveService = require(script.Parent.ObjectiveService)

local Remotes = ReplicatedStorage.Remotes
local DroneRemote = Remotes.Drone :: RemoteEvent
local AbilityEffect = Remotes.AbilityEffect :: RemoteEvent
local MatchState = ReplicatedStorage.MatchState

local DroneService = {}

local DRONES_PER_ROUND = 2
local SPOT_RANGE = 70 -- studs from the drone's camera
local SPOT_TIME = 4 -- seconds a spotted enemy stays highlighted for the team
local SITE_SEE_RANGE = 45 -- how close a drone / attacker has to be to make out the site
local SITE_CHECK_EVERY = 0.3
local LIVE_PHASES = { Prep = true, Action = true, Planted = true }
local DARK = Color3.fromRGB(38, 40, 44)

local drones: { [Player]: Model } = {}
local lastSiteCheck = 0

local function deployables(): Folder
	local folder = Workspace:FindFirstChild("Deployables")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Deployables"
		folder.Parent = Workspace
	end
	return folder :: Folder
end

local function isAttacker(player: Player): boolean
	return player.Team ~= nil and player.Team.Name == MatchState:GetAttribute("AttackTeam")
end

local function aliveRoot(character: Model?): BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return if humanoid and humanoid.Health > 0 then root else nil
end

-- Where the drone's camera is (DroneController puts yours here too)
function DroneService.Eye(drone: Model): Vector3?
	local body = drone.PrimaryPart
	return body and (body.CFrame * CFrame.new(0, 0.3, -0.45)).Position
end

local function attach(body: BasePart, name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material, shape: Enum.PartType?)
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = shape or Enum.PartType.Block
	part.Size = size
	part.CFrame = body.CFrame * offset
	part.Color = color
	part.Material = material
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = body
	weld.Part1 = part
	weld.Parent = part
	part.Parent = body.Parent
end

-- A little two-wheeled bot: the body is the only part that collides or can be shot
local function buildDrone(player: Player, at: CFrame): Model
	local model = Instance.new("Model")
	model.Name = "Drone"
	model:SetAttribute("OwnerId", player.UserId)
	model:SetAttribute("OwnerTeam", if player.Neutral or not player.Team then "" else player.Team.Name)
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(1.1, 0.5, 1)
	body.CFrame = at
	body.Color = DARK
	body.Material = Enum.Material.Metal
	body.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.2, 0, 1, 1)
	body:SetAttribute("Breakable", "Gadget")
	body.Parent = model
	model.PrimaryPart = body
	for _, side in { -1, 1 } do
		attach(body, "Wheel", Vector3.new(0.18, 0.7, 0.7), CFrame.new(side * 0.66, 0.1, 0), Color3.fromRGB(25, 25, 27), Enum.Material.Rubber, Enum.PartType.Cylinder)
	end
	attach(body, "Lens", Vector3.new(0.22, 0.22, 0.06), CFrame.new(0, 0.12, -0.52), Color3.fromRGB(255, 60, 60), Enum.Material.Neon)
	attach(body, "Antenna", Vector3.new(0.05, 0.6, 0.05), CFrame.new(0.35, 0.5, 0.35), DARK, Enum.Material.Metal)
	model.Parent = deployables()
	body:SetNetworkOwner(player) -- the owner's client drives it (DroneController)
	return model
end

local function setDroning(player: Player, on: boolean)
	player:SetAttribute("Droning", if on then true else nil)
end

-- Throws a drone out in front of the player and puts them in it
local function deploy(player: Player): boolean
	local root = aliveRoot(player.Character)
	if not root then
		return false
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character :: Model, deployables() }
	local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z).Unit
	-- Out in front, unless there's a wall right there
	local distance = 2.5
	local blocked = Workspace:Raycast(root.Position, look * distance, params)
	if blocked then
		distance = math.max(blocked.Distance - 0.8, 0)
	end
	local spot = root.Position + look * distance
	local ground = Workspace:Raycast(spot, Vector3.new(0, -8, 0), params)
	local position = (if ground then ground.Position else spot - Vector3.new(0, 2.5, 0)) + Vector3.new(0, 0.4, 0)
	local drone = buildDrone(player, CFrame.lookAt(position, position + look))
	drones[player] = drone
	drone.Destroying:Connect(function()
		if drones[player] == drone then
			drones[player] = nil
			setDroning(player, false)
		end
	end)
	setDroning(player, true)
	return true
end

-- Z: hop into your drone, back to your body, or throw a new one
local function toggle(player: Player)
	if player:GetAttribute("Droning") then
		setDroning(player, false)
		return
	end
	local root = aliveRoot(player.Character)
	if not root then
		-- Dead attackers can still drive the drone they left out (like Siege), not throw a new one
		local drone = drones[player]
		if drone and drone.Parent and isAttacker(player) and LIVE_PHASES[MatchState:GetAttribute("Phase")] and player:GetAttribute("Location") == "Match" then
			setDroning(player, true)
		end
		return
	end
	local freeRoam = player.Neutral
	if not freeRoam and (not isAttacker(player) or not LIVE_PHASES[MatchState:GetAttribute("Phase")]) then
		return
	end
	local drone = drones[player]
	if drone and drone.Parent then
		setDroning(player, true)
		return
	end
	local left = player:GetAttribute("DronesLeft") or 0
	if not freeRoam and left <= 0 then
		AbilityEffect:FireClient(player, "Status", "NO DRONES LEFT")
		return
	end
	if not freeRoam and MatchState:GetAttribute("Phase") ~= "Prep" and root.Anchored then
		return -- frozen before the round
	end
	if deploy(player) and not freeRoam then
		player:SetAttribute("DronesLeft", left - 1)
	end
end

-- Spotting from a drone or a defender camera (CameraService) at `eye`: if that enemy really is in
-- view, everyone on your team sees them for a few seconds
function DroneService.SpotFrom(player: Player, eye: Vector3, range: number, ignore: { Instance }, target: any)
	if typeof(target) ~= "Instance" or not target:IsA("Model") then
		return
	end
	local targetRoot = aliveRoot(target)
	local targetPlayer = Players:GetPlayerFromCharacter(target)
	local dummies = Workspace:FindFirstChild("Dummies") -- practice targets (dev panel)
	local enemy = if targetPlayer
		then targetPlayer ~= player and (player.Neutral or targetPlayer.Team ~= player.Team)
		else dummies ~= nil and target:IsDescendantOf(dummies)
	if not targetRoot or not enemy or (targetRoot.Position - eye).Magnitude > range then
		return
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { target, table.unpack(ignore) }
	if Workspace:Raycast(eye, targetRoot.Position - eye, params) then
		return -- not actually in view
	end
	local team = if player.Neutral or not player.Team then { player } else player.Team:GetPlayers()
	for _, teammate in team do
		AbilityEffect:FireClient(teammate, "Reveal", { target }, SPOT_TIME)
	end
end

-- Click on the drone camera (all static near an enemy jammer: no spotting)
local function spot(player: Player, target: any)
	local drone = drones[player]
	local eye = drone and player:GetAttribute("Droning") and DroneService.Eye(drone)
	if eye and not GadgetService.Jammed(eye, player) then
		DroneService.SpotFrom(player, eye, SPOT_RANGE, { drone :: Model }, target)
	end
end

-- Can `eye` make out the site? Close enough and nothing in the way of its middle, at waist height
local function seesSite(eye: Vector3, site: BasePart, ignore: { Instance }): boolean
	local center = site.Position - Vector3.new(0, site.Size.Y / 2 - 2, 0)
	local offset = center - eye
	if offset.Magnitude > SITE_SEE_RANGE then
		return false
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	return Workspace:Raycast(eye, offset, params) == nil
end

local function checkSite()
	local phase = MatchState:GetAttribute("Phase")
	if MatchState:GetAttribute("SiteFound") or not LIVE_PHASES[phase] or MatchState:GetAttribute("GameMode") ~= "AttackDefend" then
		return
	end
	local eyes = {}
	for player, drone in drones do
		local eye = isAttacker(player) and DroneService.Eye(drone)
		if eye and not GadgetService.Jammed(eye, player) then -- (a jammed feed is all static)
			table.insert(eyes, eye)
		end
	end
	if phase ~= "Prep" then
		for _, player in Players:GetPlayers() do
			local head = isAttacker(player) and aliveRoot(player.Character) and (player.Character :: Model):FindFirstChild("Head") :: BasePart?
			if head then
				table.insert(eyes, head.Position)
			end
		end
	end
	-- (windows don't hide the site)
	local map = Workspace:FindFirstChild("Map")
	local ignore: { Instance } = { deployables(), map and map:FindFirstChild("Glass") or deployables() }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	for _, site in ObjectiveService.GetActiveSites() do
		for _, eye in eyes do
			if seesSite(eye, site, ignore) then
				MatchState:SetAttribute("SiteFound", true)
				local pair = MatchState:GetAttribute("SitePair")
				for _, player in Players:GetPlayers() do
					if isAttacker(player) then
						AbilityEffect:FireClient(player, "Status", `OBJECTIVE LOCATED{if pair then ": " .. string.upper(pair) else ""}`)
					end
				end
				return
			end
		end
	end
end

-- Defenders' setup: every attacker gets their drones and drives the first one out of spawn
function DroneService.StartPrep(attackers: Team)
	for _, player in attackers:GetPlayers() do
		player:SetAttribute("DronesLeft", DRONES_PER_ROUND - 1)
		deploy(player)
	end
end

-- The round goes live: everyone's back in their body (the drones stay where they are)
function DroneService.StartAction()
	for _, player in Players:GetPlayers() do
		setDroning(player, false)
	end
end

-- New round / match over: drones gone, site unknown again
function DroneService.Reset()
	for _, drone in drones do
		drone:Destroy()
	end
	table.clear(drones)
	for _, player in Players:GetPlayers() do
		setDroning(player, false)
		player:SetAttribute("DronesLeft", nil)
	end
	MatchState:SetAttribute("SiteFound", nil)
end

function DroneService.Start()
	DroneRemote.OnServerEvent:Connect(function(player, action, target)
		if action == "Toggle" then
			toggle(player)
		elseif action == "Spot" then
			spot(player, target)
		end
	end)
	local function onPlayerAdded(player: Player)
		player.CharacterAdded:Connect(function(character)
			setDroning(player, false)
			local humanoid = character:WaitForChild("Humanoid") :: Humanoid
			humanoid.Died:Connect(function()
				setDroning(player, false)
			end)
		end)
	end
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		local drone = drones[player]
		if drone then
			drone:Destroy()
		end
		drones[player] = nil
	end)
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now - lastSiteCheck >= SITE_CHECK_EVERY then
			lastSiteCheck = now
			checkSite()
		end
	end)
end

return DroneService
