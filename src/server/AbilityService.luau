-- Active abilities (X, and B for secondaries): Deployable Cover here, and the Siege
-- gadgets in GadgetService (breach charges, thermite, EMP, grenades, heartbeat sensor, shock wire,
-- jammer, armor panel, barbed wire, impact grenades). Your ability is your operator's gadget
-- (LoadoutService). Charges are tracked here and mirrored to the "AbilityCharges" player attribute
-- for the HUD (and "SecondaryCharges" for the B gadget, "Secondary"). Charges refill whenever you
-- spawn or that slot's gadget changes.

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

local function aliveRoot(model: Model?): BasePart?
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	local root = model and model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if humanoid and humanoid.Health > 0 and root then
		return root
	end
	return nil
end

-- `charges`: the player attribute counting this gadget's charges ("AbilityCharges" for the X gadget,
-- "SecondaryCharges" for the B one)
type Handler = (player: Player, character: Model, root: BasePart, ability: Abilities.Ability, look: Vector3, charges: string) -> boolean

local handlers: { [string]: Handler } = {
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

-- The gadget attribute of each slot (X, B) and the attribute counting its charges
local SLOTS = { Ability = "AbilityCharges", Secondary = "SecondaryCharges" }

-- Fills a slot's charges for its gadget (`only`: just that slot; otherwise both)
function AbilityService.ResetCharges(player: Player, only: string?)
	for slot, chargesAttribute in SLOTS do
		if only and slot ~= only then
			continue
		end
		local abilityName = player:GetAttribute(slot)
		local ability = if typeof(abilityName) == "string" then Abilities[abilityName] else nil
		player:SetAttribute(chargesAttribute, if ability and ability.Charges then ability.Charges else nil)
	end
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
		for slot in SLOTS do
			player:GetAttributeChangedSignal(slot):Connect(function()
				AbilityService.ResetCharges(player, slot)
			end)
		end
	end
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		lastUse[player] = nil
	end)

	-- UseAbility(look, slot): slot "Secondary" is the B gadget, anything else the X one
	UseAbility.OnServerEvent:Connect(function(player, look, slot)
		if typeof(look) ~= "Vector3" then
			return
		end
		local slotName = if slot == "Secondary" then "Secondary" else "Ability"
		local chargesAttribute = SLOTS[slotName]
		local abilityName = player:GetAttribute(slotName)
		local ability = abilityName and Abilities[abilityName]
		local handler = abilityName and handlers[abilityName]
		if not ability or not handler then
			return
		end
		local charges = player:GetAttribute(chargesAttribute) or 0
		if charges <= 0 and not ability.Detonates then -- setting off a placed breach charge is free
			return
		end
		local now = os.clock()
		if now - (lastUse[player] or 0) < SPAM_GUARD then
			return
		end

		local character = player.Character
		local root = aliveRoot(character)
		if not character or not root or root.Anchored or character:GetAttribute("Deploying") or character:GetAttribute("Downed") then
			return -- dead, frozen in the pre-round, busy deploying cover, or downed (DBNOService)
		end
		if player:GetAttribute("Droning") or player:GetAttribute("OnCams") then
			return -- (driving a drone or watching cameras: your body isn't yours to use)
		end

		if handler(player, character, root, ability, look, chargesAttribute) then
			lastUse[player] = now
			player:SetAttribute(chargesAttribute, charges - 1)
		end
	end)
end

return AbilityService
