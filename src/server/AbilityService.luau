-- Active abilities (used with F): Recon Pulse, Ghost Step, Deployable Cover.
-- Charges are tracked here and mirrored to the "AbilityCharges" player attribute for the HUD.
-- Charges refill whenever you spawn or your ability changes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Abilities = require(ReplicatedStorage.Shared.Abilities)

local Remotes = ReplicatedStorage.Remotes
local UseAbility = Remotes.UseAbility :: RemoteEvent
local AbilityEffect = Remotes.AbilityEffect :: RemoteEvent

local SPAM_GUARD = 0.4 -- seconds between ability uses

local AbilityService = {}

local lastUse: { [Player]: number } = {}

local function getDeployables(): Folder
	local folder = Workspace:FindFirstChild("Deployables")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Deployables"
		folder.Parent = Workspace
	end
	return folder :: Folder
end

-- Everyone is an enemy in free roam; in a match, the other team is
local function isEnemy(player: Player, other: Player): boolean
	if other == player then
		return false
	end
	if player.Neutral or other.Neutral then
		return true
	end
	return other.Team ~= player.Team
end

local function teamOf(player: Player): { Player }
	if player.Neutral or not player.Team then
		return { player }
	end
	return player.Team:GetPlayers()
end

local function aliveRoot(model: Model?): BasePart?
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	local root = model and model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if humanoid and humanoid.Health > 0 and root then
		return root
	end
	return nil
end

type Handler = (player: Player, character: Model, root: BasePart, ability: Abilities.Ability, look: Vector3) -> boolean

local handlers: { [string]: Handler } = {
	-- Reveal enemies within range (through walls) to the user's whole team
	ReconPulse = function(player, _character, root, ability)
		local radius = ability.Radius or 60
		local duration = ability.Duration or 3
		local revealed: { Model } = {}

		for _, other in Players:GetPlayers() do
			local otherRoot = aliveRoot(other.Character)
			if otherRoot and isEnemy(player, other) and (otherRoot.Position - root.Position).Magnitude <= radius then
				table.insert(revealed, other.Character :: Model)
				AbilityEffect:FireClient(other, "Scanned")
			end
		end
		local dummies = Workspace:FindFirstChild("Dummies")
		if dummies then
			for _, dummy in dummies:GetChildren() do
				local dummyRoot = aliveRoot(dummy :: Model)
				if dummyRoot and (dummyRoot.Position - root.Position).Magnitude <= radius then
					table.insert(revealed, dummy :: Model)
				end
			end
		end

		for _, teammate in teamOf(player) do
			AbilityEffect:FireClient(teammate, "Reveal", revealed, duration)
		end
		-- Everyone sees the pulse wave go out (a cue that someone just scanned)
		AbilityEffect:FireAllClients("Pulse", root.Position, radius)
		return true
	end,

	-- Silent footsteps for a while (Footsteps.luau checks the "Silent" attribute)
	GhostStep = function(player, character, _root, ability)
		local duration = ability.Duration or 8
		local token = (character:GetAttribute("SilentToken") or 0) + 1
		character:SetAttribute("SilentToken", token)
		character:SetAttribute("Silent", true)
		AbilityEffect:FireClient(player, "GhostStep", duration)
		task.delay(duration, function()
			if character.Parent and character:GetAttribute("SilentToken") == token then
				character:SetAttribute("Silent", false)
			end
		end)
		return true
	end,

	-- Waist-high bulletproof shield placed in front of you, facing where you look
	DeployableCover = function(player, character, root, _ability, look)
		local forward = Vector3.new(look.X, 0, look.Z)
		if forward.Magnitude < 0.1 then
			forward = root.CFrame.LookVector * Vector3.new(1, 0, 1)
		end
		forward = forward.Unit

		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { character }

		-- Don't place it inside a wall: stop short of anything in the way
		local distance = 4
		local blocked = Workspace:Raycast(root.Position, forward * distance, params)
		if blocked then
			distance = blocked.Distance - 1.5
			if distance < 1.5 then
				return false
			end
		end
		local spot = root.Position + forward * distance

		-- Find the ground under that spot
		local ground = Workspace:Raycast(spot + Vector3.new(0, 2, 0), Vector3.new(0, -10, 0), params)
		if not ground then
			return false
		end

		local size = Vector3.new(6, 4, 0.8)
		local base = ground.Position + Vector3.new(0, size.Y / 2, 0)
		local finalCFrame = CFrame.lookAt(base, base + forward)

		local cover = Instance.new("Part")
		cover.Name = "DeployableCover"
		cover.Size = size
		-- Starts sunk into the ground, then rises into place (see tween below)
		cover.CFrame = finalCFrame * CFrame.new(0, -size.Y, 0)
		cover.Anchored = true
		cover.Material = Enum.Material.DiamondPlate
		cover.Color = Color3.fromRGB(85, 90, 100)
		cover:SetAttribute("Owner", player.UserId)

		-- Welded to the cover so it rides along with the rise animation
		local stripe = Instance.new("Part")
		stripe.Name = "TeamStripe"
		stripe.Size = Vector3.new(size.X, 0.15, size.Z + 0.02)
		stripe.CFrame = cover.CFrame * CFrame.new(0, size.Y / 2 - 0.2, 0)
		stripe.Anchored = false
		stripe.Massless = true
		stripe.CanCollide = false
		stripe.CanQuery = false
		stripe.Material = Enum.Material.Neon
		stripe.Color = if player.Team then player.Team.TeamColor.Color else Color3.new(1, 1, 1)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = cover
		weld.Part1 = stripe
		weld.Parent = stripe
		stripe.Parent = cover

		cover.Parent = getDeployables()
		TweenService:Create(
			cover,
			TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ CFrame = finalCFrame }
		):Play()
		AbilityEffect:FireAllClients("CoverDeployed", base)
		return true
	end,
}

function AbilityService.ResetCharges(player: Player)
	local abilityName = player:GetAttribute("Ability")
	local ability = if typeof(abilityName) == "string" then Abilities[abilityName] else nil
	player:SetAttribute("AbilityCharges", if ability and ability.Charges then ability.Charges else nil)
end

-- Removes all placed covers (called at the start of each round and between matches)
function AbilityService.ClearDeployables()
	getDeployables():ClearAllChildren()
end

function AbilityService.Start()
	local function onPlayerAdded(player: Player)
		player.CharacterAdded:Connect(function()
			AbilityService.ResetCharges(player)
		end)
		player:GetAttributeChangedSignal("Ability"):Connect(function()
			AbilityService.ResetCharges(player)
		end)
	end
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		lastUse[player] = nil
	end)

	UseAbility.OnServerEvent:Connect(function(player, look)
		if typeof(look) ~= "Vector3" then
			return
		end
		local abilityName = player:GetAttribute("Ability")
		local ability = abilityName and Abilities[abilityName]
		local handler = abilityName and handlers[abilityName]
		if not ability or not handler then
			return
		end
		local charges = player:GetAttribute("AbilityCharges") or 0
		if charges <= 0 then
			return
		end
		local now = os.clock()
		if now - (lastUse[player] or 0) < SPAM_GUARD then
			return
		end

		local character = player.Character
		local root = aliveRoot(character)
		if not character or not root or root.Anchored then
			return -- dead, or frozen in the pre-round
		end

		if handler(player, character, root, ability, look) then
			lastUse[player] = now
			player:SetAttribute("AbilityCharges", charges - 1)
		end
	end)
end

return AbilityService
