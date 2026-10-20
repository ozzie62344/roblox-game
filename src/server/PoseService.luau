-- Stores each player's lean (-1, 0, 1), crouch / prone (bools), look pitch (radians, up/down) and rappel
-- rope height on their character so every client can pose their body, aim their gun and draw ropes,
-- and whether they're mid-vault ("Vaulting").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Remotes = ReplicatedStorage.Remotes
local SetLean = Remotes.SetLean :: RemoteEvent
local SetCrouch = Remotes.SetCrouch :: RemoteEvent
local LookPitch = Remotes.LookPitch :: UnreliableRemoteEvent
local SetRappel = Remotes.SetRappel :: RemoteEvent
local VaultRemote = Remotes.Vault :: RemoteEvent

local MAX_PITCH = math.rad(85)
local VAULT_MAX_TIME = 1 -- seconds a vault can say it lasts (they're 0.4-0.75)
local VAULT_SPAM = 0.35 -- seconds between vaults
-- (anti-cheat) The server's own checks, so a made-up rope or vault can't switch off AntiCheat's
-- fly / noclip checks (it trusts "RappelTop" and "Vaulting")
local ROPE_PHASES = { Action = true, Planted = true } -- like RappelController: attackers, live round
local ROPE_WALL_REACH = 5 -- studs: you're hanging against an outside wall (or a window) this close
local VAULT_REACH = 6 -- studs ahead there has to be something to vault over or climb onto

local MatchState = ReplicatedStorage:WaitForChild("MatchState")

local PoseService = {}

local lastVault: { [Player]: number } = {}

local function mapParams(character: Model): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { character }
	local deployables = Workspace:FindFirstChild("Deployables")
	if deployables then
		table.insert(ignore, deployables)
	end
	params.FilterDescendantsInstances = ignore
	return params
end

-- May `player` be on a rope right now, here? (attackers in a live round, or anyone free roaming,
-- hanging against an outside wall or window: RappelController's rules)
local function canRappel(player: Player, root: BasePart): boolean
	if not player.Neutral and not (player.Team and player.Team.Name == MatchState:GetAttribute("AttackTeam") and ROPE_PHASES[MatchState:GetAttribute("Phase")]) then
		return false
	end
	local params = mapParams(root.Parent :: Model)
	for _, direction in { Vector3.xAxis, -Vector3.xAxis, Vector3.zAxis, -Vector3.zAxis, Vector3.new(1, 0, 1).Unit, Vector3.new(-1, 0, 1).Unit, Vector3.new(1, 0, -1).Unit, Vector3.new(-1, 0, -1).Unit } do
		local hit = Workspace:Raycast(root.Position, direction * ROPE_WALL_REACH, params)
		local parent = hit and hit.Instance.Parent
		if hit and (hit.Instance.Name == "ExteriorWall" or (parent ~= nil and parent.Name == "Glass")) then
			return true
		end
	end
	return false
end

-- Is there anything next to them to vault over or climb onto? (knee to chest height, any way
-- round: a vault can go sideways, and the server's copy of them may face a little off)
local function coverAhead(root: BasePart): boolean
	local params = mapParams(root.Parent :: Model)
	for i = 0, 7 do
		local angle = i * math.pi / 4
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle)) * VAULT_REACH
		for _, dy in { -2, -1.2, -0.4, 0.4 } do
			if Workspace:Raycast(root.Position + Vector3.new(0, dy, 0), direction, params) then
				return true
			end
		end
	end
	return false
end

function PoseService.Start()
	SetLean.OnServerEvent:Connect(function(player, value)
		if value ~= -1 and value ~= 0 and value ~= 1 then
			return
		end
		if player.Character then
			player.Character:SetAttribute("Lean", value)
		end
	end)

	-- Lowered (crouching / lying down) and whether it's lying down (prone)
	SetCrouch.OnServerEvent:Connect(function(player, crouching, prone)
		if typeof(crouching) ~= "boolean" then
			return
		end
		if player.Character then
			player.Character:SetAttribute("Crouching", crouching)
			player.Character:SetAttribute("Prone", prone == true)
		end
	end)

	LookPitch.OnServerEvent:Connect(function(player, pitch)
		if typeof(pitch) ~= "number" or pitch ~= pitch then -- (pitch ~= pitch catches NaN)
			return
		end
		if player.Character then
			-- Rounded so tiny changes don't spam attribute updates
			local clamped = math.clamp(pitch, -MAX_PITCH, MAX_PITCH)
			player.Character:SetAttribute("LookPitch", math.round(clamped * 100) / 100)
		end
	end)

	-- Where a rappelling player's rope is tied (a height; nil = let go). RappelController draws it.
	SetRappel.OnServerEvent:Connect(function(player, top)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root or (top ~= nil and (typeof(top) ~= "number" or top ~= top or math.abs(top - root.Position.Y) > 60)) then
			return
		end
		if top ~= nil and not canRappel(player, root) then
			return -- (not theirs to use here: no rope)
		end
		(player.Character :: Model):SetAttribute("RappelTop", top)
	end)

	-- Vaulting over cover / climbing onto a ledge (MovementController moves them itself): the
	-- character's "Vaulting" attribute is true for as long as it lasts, so others hear it and see
	-- the pose (Footsteps, BodyAnimator) and the anti-cheat lets the hop over the cover through
	VaultRemote.OnServerEvent:Connect(function(player, duration)
		local character = player.Character
		local now = os.clock()
		if typeof(duration) ~= "number" or duration ~= duration or not character or now - (lastVault[player] or 0) < VAULT_SPAM then
			return
		end
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root or not coverAhead(root) then
			return -- nothing there to vault
		end
		lastVault[player] = now
		character:SetAttribute("Vaulting", true)
		task.delay(math.clamp(duration, 0.1, VAULT_MAX_TIME), function()
			if lastVault[player] == now and character.Parent then
				character:SetAttribute("Vaulting", false)
			end
		end)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastVault[player] = nil
	end)
end

return PoseService
