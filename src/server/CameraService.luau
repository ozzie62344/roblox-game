-- Siege defender cameras: fixed cameras on the outside walls and in key rooms (SPOTS, per map),
-- rebuilt with the map every round (MapService) and handed to the defending team (RoundService).
-- Defenders press Z to watch them (client CamsController): A / D switch camera, the mouse turns
-- it, click spots an attacker for the whole team. Any bullet or knife destroys one (Breakable =
-- "Gadget"), and so does an attacker's EMP ("Electronic", GadgetService). A player watching has
-- the "OnCams" attribute (their body holds the controller meanwhile).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local DroneService = require(script.Parent.DroneService)

local CamsRemote = ReplicatedStorage.Remotes.Cams :: RemoteEvent
local MatchState = ReplicatedStorage.MatchState

local CameraService = {}

local SPOT_RANGE = 90 -- studs from the lens
local LIVE_PHASES = { Prep = true, Action = true, Planted = true }
local DARK = Color3.fromRGB(38, 40, 44)

-- { name, point on the wall, out of the wall, what it looks at } (measured against the map)
local SPOTS: { [string]: { { any } } } = {
	House = {
		{ "FRONT YARD", Vector3.new(-22, 9.4, -40.5), Vector3.new(0, 0, -1), Vector3.new(-14, 0.4, -72) },
		{ "WEST SIDE", Vector3.new(-56.5, 9.4, -8), Vector3.new(-1, 0, 0), Vector3.new(-84, 0.4, -4) },
		{ "BACK YARD", Vector3.new(4, 9.4, 40.5), Vector3.new(0, 0, 1), Vector3.new(-4, 0.4, 72) },
		{ "EAST DRIVE", Vector3.new(56.5, 9.4, 20), Vector3.new(1, 0, 0), Vector3.new(84, 0.4, 8) },
		{ "GARAGE", Vector3.new(76, 8.4, -4.5), Vector3.new(0, 0, -1), Vector3.new(64, 0.4, -36) },
		{ "FOYER", Vector3.new(16, 10.4, -22.5), Vector3.new(0, 0, -1), Vector3.new(-2, 0.4, -38) },
		{ "HALL", Vector3.new(14, 9.4, 9.5), Vector3.new(0, 0, -1), Vector3.new(-4, 0.4, -14) },
		{ "LANDING", Vector3.new(-8, 21.9, 11.5), Vector3.new(0, 0, -1), Vector3.new(4, 13.4, -16) },
		{ "REC ROOM", Vector3.new(-12, -2.6, -2.5), Vector3.new(0, 0, -1), Vector3.new(0, -11.6, -30) },
	},
	Warehouse = {
		{ "TRUCK LOT", Vector3.new(-8, 10.4, -40.5), Vector3.new(0, 0, -1), Vector3.new(-20, 0.3, -90) },
		{ "CONTAINER YARD", Vector3.new(-64.5, 10.4, 0), Vector3.new(-1, 0, 0), Vector3.new(-110, 0.3, 0) },
		{ "RAIL YARD", Vector3.new(-30, 10.4, 40.5), Vector3.new(0, 0, 1), Vector3.new(-20, 0.3, 90) },
		{ "CAR PARK", Vector3.new(56.5, 10.4, -10), Vector3.new(1, 0, 0), Vector3.new(100, 0.3, 0) },
		{ "LOADING DOCKS", Vector3.new(-26, 10.4, -39.5), Vector3.new(0, 0, 1), Vector3.new(-46, 0.4, -8) },
		{ "HALL FLOOR", Vector3.new(-24.5, 10.4, 20), Vector3.new(-1, 0, 0), Vector3.new(-60, 0.4, -4) },
		{ "MEZZANINE", Vector3.new(7.5, 21.9, 20), Vector3.new(-1, 0, 0), Vector3.new(-22, 13.4, -4) },
		{ "LOBBY", Vector3.new(30, 10.4, -16.5), Vector3.new(0, 0, -1), Vector3.new(16, 0.4, -38) },
		{ "CORRIDOR", Vector3.new(55.5, 10, -12), Vector3.new(-1, 0, 0), Vector3.new(8, 0.4, -12) },
		{ "OPEN PLAN", Vector3.new(54, 21.9, -8.5), Vector3.new(0, 0, -1), Vector3.new(12, 13.4, -36) },
		{ "LOADING TUNNEL", Vector3.new(-36, -2.6, -39.5), Vector3.new(0, 0, 1), Vector3.new(-36, -11.6, 30) },
	},
	Flight9 = {
		{ "CHECKPOINT", Vector3.new(30, 9.4, -40.5), Vector3.new(0, 0, -1), Vector3.new(0, 0.3, -88) },
		{ "GENERATOR YARD", Vector3.new(-40.5, 9.4, -25), Vector3.new(-1, 0, 0), Vector3.new(-58, 0.2, -32) },
		{ "TAIL", Vector3.new(-40.5, 8.6, 8), Vector3.new(-1, 0, 0), Vector3.new(-62, 0.4, 2) },
		{ "EXCAVATION", Vector3.new(-38, 8.6, 12.5), Vector3.new(0, 0, 1), Vector3.new(-20, -11.6, 28) },
		{ "NORTH FIELD", Vector3.new(44, 9.4, 40.5), Vector3.new(0, 0, 1), Vector3.new(30, 0.2, 75) },
		{ "NOSE", Vector3.new(56.5, 9.4, -27), Vector3.new(1, 0, 0), Vector3.new(72, 0.2, -4) },
		{ "ALLEY", Vector3.new(-8, 9.4, -21.5), Vector3.new(0, 0, 1), Vector3.new(-38, 0.4, -16) },
		{ "ECONOMY", Vector3.new(-16.5, 8.6, 0), Vector3.new(-1, 0, 0), Vector3.new(-38, 0.4, -6) },
		{ "AFT HOLD", Vector3.new(-20.5, -1.6, 8), Vector3.new(-1, 0, 0), Vector3.new(-38, -11.6, -6) },
		{ "HANGAR TENT", Vector3.new(44, 7.4, -12.5), Vector3.new(0, 0, -1), Vector3.new(12, 0.4, -15) },
		{ "LAB HALL", Vector3.new(33.5, 9.4, 37), Vector3.new(-1, 0, 0), Vector3.new(27, 0.4, 24) },
	},
	Bank = {
		{ "MAIN STREET", Vector3.new(-44, 9.4, -40.5), Vector3.new(0, 0, -1), Vector3.new(-30, 0.15, -80) },
		{ "SIDE STREET", Vector3.new(-56.5, 9.4, -8), Vector3.new(-1, 0, 0), Vector3.new(-82, 0.15, -2) },
		{ "BACK ALLEY", Vector3.new(-22, 9.4, 40.5), Vector3.new(0, 0, 1), Vector3.new(-14, 0.15, 80) },
		{ "PARKING LOT", Vector3.new(56.5, 9.4, 20), Vector3.new(1, 0, 0), Vector3.new(96, 0.15, 4) },
		{ "GARAGE", Vector3.new(40, -3.2, 3.5), Vector3.new(0, 0, -1), Vector3.new(52, -11.6, -24) },
		{ "LOBBY", Vector3.new(-23.5, 10.4, -37.5), Vector3.new(1, 0, 0), Vector3.new(8, 0.4, -16) },
		{ "TELLERS", Vector3.new(-2, 9.4, 5.5), Vector3.new(0, 0, -1), Vector3.new(-4, 0.4, -10) },
		{ "WEST HALL", Vector3.new(-25.5, 9.4, 39.5), Vector3.new(0, 0, -1), Vector3.new(-30, 0.4, -8) },
		{ "GALLERY", Vector3.new(18, 21.9, -12.5), Vector3.new(0, 0, -1), Vector3.new(-10, 8, -34) },
		{ "VAULT LOBBY", Vector3.new(8.5, -2.6, -13.5), Vector3.new(0, 0, 1), Vector3.new(14, -11.6, 30) },
		{ "BASEMENT", Vector3.new(-30, -2.6, -39.5), Vector3.new(0, 0, 1), Vector3.new(-27, -11.6, 10) },
	},
}

-- Where the lens is (CamsController looks out of the same point)
function CameraService.Eye(camera: Model): Vector3?
	local body = camera.PrimaryPart
	return body and (body.CFrame * CFrame.new(0, 0, -0.5)).Position
end

local function part(name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Parent = parent
	return p
end

local function cameraFolder(): Instance?
	local map = Workspace:FindFirstChild("Map")
	return map and map:FindFirstChild("Cameras")
end

-- A newly loaded map gets its cameras (MapService.Load); nobody owns them until a round starts
function CameraService.Build(mapName: string, map: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "Cameras"
	for i, spot in SPOTS[mapName] or {} do
		local name, point, out, target = spot[1], spot[2], spot[3], spot[4]
		local model = Instance.new("Model")
		model.Name = "Camera"
		model:SetAttribute("CamName", name)
		model:SetAttribute("CamIndex", i)
		model:SetAttribute("Electronic", true)
		model:SetAttribute("OwnerTeam", "")
		-- A housing on a short arm out of the wall, tipped toward what it watches
		local head = point + out * 0.8 - Vector3.new(0, 0.3, 0)
		local body = part("Body", Vector3.new(0.7, 0.55, 0.9), CFrame.lookAt(head, target), DARK, Enum.Material.Metal, model)
		body.CanQuery = true -- (bullets)
		body:SetAttribute("Breakable", "Gadget")
		model.PrimaryPart = body
		part("Arm", Vector3.new(0.2, 0.2, 0.8), CFrame.lookAt(point + out * 0.4, point + out), DARK, Enum.Material.Metal, model)
		part("Lens", Vector3.new(0.42, 0.42, 0.06), body.CFrame * CFrame.new(0, 0, -0.46), Color3.fromRGB(12, 12, 16), Enum.Material.Glass, model)
		part("Light", Vector3.new(0.1, 0.1, 0.1), body.CFrame * CFrame.new(0.24, 0.2, -0.43), Color3.fromRGB(255, 50, 50), Enum.Material.Neon, model)
		model.Parent = folder
	end
	folder.Parent = map
end

-- The defending team owns the cameras this round (RoundService)
function CameraService.SetOwner(teamName: string)
	local folder = cameraFolder()
	for _, camera in if folder then folder:GetChildren() else {} do
		camera:SetAttribute("OwnerTeam", teamName)
	end
end

-- Defenders in a live round, dead ones included (like Siege, you keep spotting for your team
-- after you're killed)
local function canWatch(player: Player): boolean
	if player:GetAttribute("Location") == "Lobby" then
		return false
	end
	if player.Neutral then
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		return humanoid ~= nil and humanoid.Health > 0 -- free roam, to try them
	end
	local attackTeam = MatchState:GetAttribute("AttackTeam")
	return player.Team ~= nil and attackTeam ~= nil and player.Team.Name ~= attackTeam and LIVE_PHASES[MatchState:GetAttribute("Phase")] == true
end

-- Click on a camera feed: the server checks that camera really sees them
local function spot(player: Player, camera: any, target: any)
	local folder = cameraFolder()
	if not player:GetAttribute("OnCams") or not folder or typeof(camera) ~= "Instance" or camera.Parent ~= folder then
		return
	end
	local owner = camera:GetAttribute("OwnerTeam")
	if not player.Neutral and (not player.Team or owner ~= player.Team.Name) then
		return
	end
	local eye = CameraService.Eye(camera :: Model)
	if eye then
		DroneService.SpotFrom(player, eye, SPOT_RANGE, { camera :: Model }, target)
	end
end

function CameraService.Start()
	CamsRemote.OnServerEvent:Connect(function(player, action, a, b)
		if action == "Watch" then
			player:SetAttribute("OnCams", if a == true and canWatch(player) then true else nil)
		elseif action == "Spot" then
			spot(player, a, b)
		end
	end)
	-- Off the cameras when you die, respawn or the round stops being live
	RunService.Heartbeat:Connect(function()
		for _, player in Players:GetPlayers() do
			if player:GetAttribute("OnCams") and not canWatch(player) then
				player:SetAttribute("OnCams", nil)
			end
		end
	end)
end

return CameraService
