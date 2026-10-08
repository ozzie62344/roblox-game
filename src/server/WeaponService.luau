-- Server side of shooting. Never trusts the client blindly: checks fire rate, ammo,
-- where the shot came from, and that each hit is actually possible before dealing damage.
-- Each player's current weapon is stored in their "Weapon" attribute (set by loadouts / dev panel).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Weapons = require(ReplicatedStorage.Shared.Weapons)

local Remotes = ReplicatedStorage.Remotes
local FireRemote = Remotes.Fire :: RemoteEvent
local ReloadRemote = Remotes.Reload :: RemoteEvent
local ShotFired = Remotes.ShotFired :: RemoteEvent
local HitConfirmed = Remotes.HitConfirmed :: RemoteEvent

local DEFAULT_WEAPON = "Rifle"
local MAX_ORIGIN_DISTANCE = 8 -- studs between the player's head and where they claim to shoot from
local HIT_TOLERANCE = 5 -- extra studs allowed between the claimed hit point and the part (for lag)
local RELOAD_TOLERANCE = 0.15
local MAX_BURST = 3 -- shots that can arrive bunched together because of network jitter

local WeaponService = {}

type PlayerData = {
	weapon: Weapons.Weapon,
	ammo: number,
	reloadEnd: number?,
	shotBudget: number,
	lastFire: number,
}

local playerData: { [Player]: PlayerData } = {}

local function resetData(player: Player)
	local weapon = Weapons[player:GetAttribute("Weapon") or DEFAULT_WEAPON] or Weapons[DEFAULT_WEAPON]
	playerData[player] = {
		weapon = weapon,
		ammo = weapon.MagazineSize,
		reloadEnd = nil,
		shotBudget = MAX_BURST,
		lastFire = 0,
	}
end

local function findHumanoid(part: Instance): Humanoid?
	local model = part:FindFirstAncestorOfClass("Model")
	while model do
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if humanoid then
			return humanoid
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil
end

local function damageAtDistance(weapon: Weapons.Weapon, distance: number): number
	local alpha = math.clamp((distance - weapon.FalloffStart) / (weapon.FalloffEnd - weapon.FalloffStart), 0, 1)
	return weapon.Damage * (1 + (weapon.MinDamageScale - 1) * alpha)
end

-- Is there map geometry between the shooter and the hit point?
local function isBlocked(origin: Vector3, target: Vector3, shooter: Model): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { shooter }
	local offset = target - origin
	local distance = offset.Magnitude
	if distance < 1 then
		return false
	end
	local result = Workspace:Raycast(origin, offset.Unit * (distance - 0.5), params)
	-- Hitting another character on the way is fine; hitting a wall is not
	return result ~= nil and findHumanoid(result.Instance) == nil
end

type Hit = { humanoid: Humanoid, damage: number, headshot: boolean }

-- Validates one bullet/pellet. Returns its end position (for tracers) and the hit, if any.
local function checkShot(player: Player, character: Model, weapon: Weapons.Weapon, origin: Vector3, shot: any): (Vector3?, Hit?)
	if typeof(shot) ~= "table" then
		return nil, nil
	end
	local direction, hitPart, endPosition = shot[1], shot[2], shot[3]
	if typeof(direction) ~= "Vector3" or typeof(endPosition) ~= "Vector3" then
		return nil, nil
	end
	if hitPart ~= nil and not (typeof(hitPart) == "Instance" and hitPart:IsA("BasePart")) then
		return nil, nil
	end
	if direction.Magnitude < 0.5 then
		return nil, nil
	end
	direction = direction.Unit
	local toEnd = endPosition - origin
	local distance = toEnd.Magnitude
	if distance > weapon.Range + 5 then
		return nil, nil
	end
	if distance > 1 and toEnd.Unit:Dot(direction) < 0.98 then
		return nil, nil
	end
	if not hitPart then
		return endPosition, nil
	end

	local targetHumanoid = findHumanoid(hitPart)
	if not targetHumanoid or targetHumanoid.Health <= 0 or targetHumanoid.Parent == character then
		return endPosition, nil
	end
	if (endPosition - hitPart.Position).Magnitude > hitPart.Size.Magnitude / 2 + HIT_TOLERANCE then
		return endPosition, nil
	end
	if isBlocked(origin, endPosition, character) then
		return endPosition, nil
	end
	-- No friendly fire
	local targetPlayer = Players:GetPlayerFromCharacter(targetHumanoid.Parent)
	if targetPlayer and not player.Neutral and targetPlayer.Team == player.Team then
		return endPosition, nil
	end

	local headshot = hitPart.Name == "Head"
	local damage = damageAtDistance(weapon, distance)
	if headshot then
		damage *= weapon.HeadshotMultiplier
	end
	return endPosition, { humanoid = targetHumanoid, damage = damage, headshot = headshot }
end

-- shots = { { direction, hitPart, endPosition }, ... }  (one entry per pellet)
local function onFire(player: Player, origin: any, shots: any)
	if typeof(origin) ~= "Vector3" or typeof(shots) ~= "table" then
		return
	end

	local data = playerData[player]
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local head = character and character:FindFirstChild("Head") :: BasePart?
	if not data or not humanoid or humanoid.Health <= 0 or not head then
		return
	end
	-- Frozen during the pre-round countdown
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root or root.Anchored then
		return
	end
	local weapon = data.weapon
	if #shots < 1 or #shots > weapon.Pellets then
		return
	end
	local now = os.clock()

	-- Reload finishing
	if data.reloadEnd then
		if now < data.reloadEnd - RELOAD_TOLERANCE then
			return
		end
		data.ammo = weapon.MagazineSize
		data.reloadEnd = nil
	end
	if data.ammo <= 0 then
		return
	end

	-- Fire rate: a small budget absorbs network jitter but caps the average rate
	local interval = 60 / weapon.RPM
	data.shotBudget = math.min(data.shotBudget + (now - data.lastFire) / interval, MAX_BURST)
	data.lastFire = now
	if data.shotBudget < 1 then
		return
	end
	data.shotBudget -= 1
	data.ammo -= 1

	-- Shot must start near the shooter's head
	if (origin - head.Position).Magnitude > MAX_ORIGIN_DISTANCE then
		return
	end

	local endPositions = {}
	local totals: { [Humanoid]: { damage: number, headshot: boolean } } = {}
	for _, shot in shots do
		local endPosition, hit = checkShot(player, character :: Model, weapon, origin, shot)
		if endPosition then
			table.insert(endPositions, endPosition)
		end
		if hit then
			local total = totals[hit.humanoid] or { damage = 0, headshot = false }
			total.damage += hit.damage
			total.headshot = total.headshot or hit.headshot
			totals[hit.humanoid] = total
		end
	end

	if #endPositions > 0 then
		ShotFired:FireAllClients(player, origin, endPositions, weapon.Name)
	end

	for targetHumanoid, total in totals do
		targetHumanoid:SetAttribute("LastDamagedBy", player.UserId)
		targetHumanoid:SetAttribute("LastHitHeadshot", total.headshot)
		targetHumanoid:TakeDamage(total.damage)
		HitConfirmed:FireClient(player, total.damage, total.headshot, targetHumanoid.Health <= 0)
	end
end

local function onReload(player: Player)
	local data = playerData[player]
	if not data or data.reloadEnd or data.ammo >= data.weapon.MagazineSize then
		return
	end
	data.reloadEnd = os.clock() + data.weapon.ReloadTime
end

function WeaponService.Refill(player: Player)
	local data = playerData[player]
	if data then
		data.ammo = data.weapon.MagazineSize
		data.reloadEnd = nil
	end
end

-- Gives a player a weapon (full magazine). The client follows the "Weapon" attribute.
function WeaponService.SetWeapon(player: Player, weaponName: string)
	if not Weapons[weaponName] then
		return
	end
	player:SetAttribute("Weapon", weaponName)
	resetData(player)
end

function WeaponService.Start()
	local function onPlayerAdded(player: Player)
		if not player:GetAttribute("Weapon") then
			player:SetAttribute("Weapon", DEFAULT_WEAPON)
		end
		resetData(player)
		player.CharacterAdded:Connect(function()
			resetData(player)
		end)
	end
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		playerData[player] = nil
	end)

	FireRemote.OnServerEvent:Connect(onFire)
	ReloadRemote.OnServerEvent:Connect(onReload)
end

WeaponService.DefaultWeapon = DEFAULT_WEAPON

return WeaponService
