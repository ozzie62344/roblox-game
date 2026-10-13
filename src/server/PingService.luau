-- On-foot pings (client TeamPing: middle mouse / T, or the phone's PING button) for your team:
--   "Spot" an enemy under your crosshair: spotted for the whole team exactly like from a drone
--          (DroneService.SpotFrom: they must really be in view of your eyes), short cooldown.
--   "Mark" a spot (wall, floor, gadget, objective...): the position goes to your team (and you),
--          who show a marker there for a few seconds. In free roam it goes to everyone.
-- Not in the lobby, and only while you're alive, or driving your drone (marks measured from its camera).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DroneService = require(script.Parent.DroneService)

local PingRemote = ReplicatedStorage.Remotes.Ping :: RemoteEvent

local PingService = {}

local RANGE = 300 -- studs from your eyes (the client casts this far from the camera)
local SLACK = 30 -- extra studs allowed for the camera being behind / above your head
local MARK_COOLDOWN = 0.5
local SPOT_COOLDOWN = 1.5

local lastMark: { [Player]: number } = {}
local lastSpot: { [Player]: number } = {}

-- Your head, if you're alive and not in the lobby
local function eyes(player: Player): BasePart?
	if player:GetAttribute("Location") == "Lobby" then
		return nil
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local head = character and character:FindFirstChild("Head") :: BasePart?
	return if humanoid and humanoid.Health > 0 then head else nil
end

local function finite(v: Vector3): boolean
	for _, n in { v.X, v.Y, v.Z } do
		if n ~= n or math.abs(n) > 1e6 then
			return false
		end
	end
	return true
end

local function mark(player: Player, position: any)
	local head = eyes(player)
	local origin = DroneService.EyeOf(player) or (head and head.Position)
	local now = os.clock()
	if not origin or typeof(position) ~= "Vector3" or not finite(position) or now - (lastMark[player] or 0) < MARK_COOLDOWN then
		return
	end
	if (position - origin).Magnitude > RANGE + SLACK then
		return
	end
	lastMark[player] = now
	-- Your team (and you); in free roam (no team) everyone
	local team = if player.Neutral or not player.Team then Players:GetPlayers() else player.Team:GetPlayers()
	if not table.find(team, player) then
		table.insert(team, player)
	end
	for _, teammate in team do
		PingRemote:FireClient(teammate, player, position)
	end
end

local function spot(player: Player, target: any)
	local head = eyes(player)
	local now = os.clock()
	if not head or now - (lastSpot[player] or 0) < SPOT_COOLDOWN then
		return
	end
	lastSpot[player] = now
	DroneService.SpotFrom(player, head.Position, RANGE, { player.Character :: Model }, target)
end

function PingService.Start()
	PingRemote.OnServerEvent:Connect(function(player, action, value)
		if action == "Mark" then
			mark(player, value)
		elseif action == "Spot" then
			spot(player, value)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastMark[player] = nil
		lastSpot[player] = nil
	end)
end

return PingService
