-- Siege's rule for defenders leaving the building (Attack / Defend). During setup (Prep) they
-- can't: step outside and you're put back where you last were indoors. Once the round is live they
-- can, but while they're outside the attackers see them highlighted and pinged through walls.
-- "Outside" = open sky above your head (porches and doorways under the roof count as inside).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Teams = game:GetService("Teams")
local Workspace = game:GetService("Workspace")

local AbilityEffect = ReplicatedStorage.Remotes.AbilityEffect :: RemoteEvent
local MatchState = ReplicatedStorage.MatchState

local PerimeterService = {}

local CHECK_EVERY = 0.2
local REVEAL_EVERY = 2 -- seconds between reveals while a defender stays outside
local SKY_CHECK = 80 -- studs up (the lobby floats far higher)
local LIVE_PHASES = { Prep = true, Action = true, Planted = true }

local lastInside: { [Player]: CFrame } = {}
local nextReveal: { [Player]: number } = {}

local function isOutside(head: BasePart, map: Instance): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { map }
	local yard = map:FindFirstChild("Yard") -- trees aren't a roof
	local hit = Workspace:Raycast(head.Position, Vector3.new(0, SKY_CHECK, 0), params)
	while hit and yard and hit.Instance:IsDescendantOf(yard) do
		hit = Workspace:Raycast(hit.Position + Vector3.new(0, 0.05, 0), Vector3.new(0, SKY_CHECK, 0), params)
	end
	return hit == nil
end

local function check()
	local phase = MatchState:GetAttribute("Phase")
	local attackTeam = Teams:FindFirstChild(MatchState:GetAttribute("AttackTeam") or "")
	local map = Workspace:FindFirstChild("Map")
	if MatchState:GetAttribute("GameMode") ~= "AttackDefend" or not LIVE_PHASES[phase] or not attackTeam or not map then
		table.clear(lastInside)
		table.clear(nextReveal)
		return
	end
	local now = os.clock()
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local head = character and character:FindFirstChild("Head") :: BasePart?
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not head or not root or not humanoid or humanoid.Health <= 0 or not player.Team or player.Team == attackTeam then
			continue
		end
		if not isOutside(head, map) then
			lastInside[player] = root.CFrame
		elseif phase == "Prep" then
			local back = lastInside[player]
			if back then
				(character :: Model):PivotTo(back)
				root.AssemblyLinearVelocity = Vector3.zero
				AbilityEffect:FireClient(player, "Status", "DEFENDERS CAN'T GO OUTSIDE DURING SETUP")
			end
		elseif now >= (nextReveal[player] or 0) then
			nextReveal[player] = now + REVEAL_EVERY
			for _, attacker in attackTeam:GetPlayers() do
				AbilityEffect:FireClient(attacker, "Reveal", { character }, REVEAL_EVERY + 0.3, "DEFENDER SPOTTED OUTSIDE")
			end
			AbilityEffect:FireClient(player, "Status", "YOU'RE OUTSIDE: THE ATTACKERS CAN SEE YOU")
		end
	end
end

function PerimeterService.Start()
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed >= CHECK_EVERY then
			elapsed = 0
			check()
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastInside[player] = nil
		nextReveal[player] = nil
	end)
end

return PerimeterService
