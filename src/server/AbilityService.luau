-- Active abilities (used with X): Recon Pulse, Ghost Step, Deployable Cover here, and the Siege
-- gadgets in GadgetService (breach charges, thermite, EMP, grenades, heartbeat sensor, shock wire,
-- jammer, armor panel, barbed wire, impact grenades). Your ability is your operator's gadget
-- (LoadoutService). Charges are tracked here and mirrored to the "AbilityCharges" player attribute
-- for the HUD. Charges refill whenever you spawn or your ability changes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Abilities = require(ReplicatedStorage.Shared.Abilities)
local CoverModel = require(script.Parent.CoverModel)
local GadgetService = require(script.Parent.GadgetService)

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
	ReconPulse = function(player, character, root, ability)
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
		GadgetService.Gesture(character, "ReconPulse")
		return true
	end,

	-- Silent footsteps for a while (Footsteps.luau checks the "Silent" attribute)
	GhostStep = function(player, character, _root, ability)
		local duration = ability.Duration or 8
		local token = (character:GetAttribute("SilentToken") or 0) + 1
		character:SetAttribute("SilentToken", token)
		character:SetAttribute("Silent", true)
		AbilityEffect:FireClient(player, "GhostStep", duration)
		GadgetService.Gesture(character, "GhostStep")
		task.delay(duration, function()
			if character.Parent and character:GetAttribute("SilentToken") == token then
				character:SetAttribute("Silent", false)
			end
		end)
		return true
	end,

	-- Waist-high bulletproof shield the player drags up out of the ground in front of them.
	-- Takes `Duration` seconds, during which they can't move or shoot; dying cancels it.
	DeployableCover = function(player, character, root, ability, look)
		local forward = Vector3.new(look.X, 0, look.Z)
		if forward.Magnitude < 0.1 then
			forward = root.CFrame.LookVector * Vector3.new(1, 0, 1)
		end
		forward = forward.Unit

		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { character }

		-- Don't place it inside a wall: stop short of anything in the way
		local distance = 3 -- close enough that your hands can believably reach it
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

		local size = Vector3.new(6, 4, 0.8) -- CoverModel's shield is laid out for exactly this size
		local base = ground.Position + Vector3.new(0, size.Y / 2, 0)
		local finalCFrame = CFrame.lookAt(base, base + forward)

		-- This box is the actual cover: it blocks players and bullets
		local cover = Instance.new("Part")
		cover.Name = "DeployableCover"
		cover.Size = size
		-- Starts sunk into the ground, then rises into place (see tween below)
		cover.CFrame = finalCFrame * CFrame.new(0, -size.Y, 0)
		cover.Anchored = true
		cover:SetAttribute("Owner", player.UserId)

		-- What you see is a steel shield welded onto the box (it rides along with the rise animation):
		-- armor plate, viewing window, team stripe, carry handles where the hands grab, fold-out legs
		CoverModel.Build(cover, if player.Team then player.Team.TeamColor.Color else Color3.new(1, 1, 1))

		local deployTime = ability.Duration or 1.2
		character:SetAttribute("Deploying", true)
		-- The client animates its hands on the cover's edge using the same timing as the tween below
		AbilityEffect:FireClient(player, "DeployStart", deployTime, finalCFrame, size)
		AbilityEffect:FireAllClients("CoverStart", base)

		-- A short grab, then a steady pull up out of the ground
		cover.Parent = getDeployables()
		local grabTime = deployTime * 0.2
		local rise = TweenService:Create(
			cover,
			TweenInfo.new(deployTime - grabTime, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 0, false, grabTime),
			{ CFrame = finalCFrame }
		)
		rise:Play()

		local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid
		task.spawn(function()
			local finishAt = os.clock() + deployTime
			while os.clock() < finishAt do
				if not character.Parent or humanoid.Health <= 0 then
					-- Killed mid-deploy: the cover is lost
					rise:Cancel()
					cover:Destroy()
					return
				end
				task.wait()
			end
			character:SetAttribute("Deploying", false)
			if cover.Parent then
				AbilityEffect:FireAllClients("CoverDeployed", base)
			end
		end)
		return true
	end,
}

for name, handler in GadgetService.Handlers do
	handlers[name] = handler
end

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
		if charges <= 0 and not ability.Detonates then -- setting off a placed breach charge is free
			return
		end
		local now = os.clock()
		if now - (lastUse[player] or 0) < SPAM_GUARD then
			return
		end

		local character = player.Character
		local root = aliveRoot(character)
		if not character or not root or root.Anchored or character:GetAttribute("Deploying") then
			return -- dead, frozen in the pre-round, or busy deploying cover
		end

		if handler(player, character, root, ability, look) then
			lastUse[player] = now
			player:SetAttribute("AbilityCharges", charges - 1)
		end
	end)
end

return AbilityService
