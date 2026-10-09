-- Server side of shooting. Never trusts the client blindly: checks fire rate, ammo,
-- where the shot came from, and that each hit is actually possible before dealing damage.
-- Each player's current weapon is stored in their "Weapon" attribute (set by loadouts / dev panel).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Weapons = require(ReplicatedStorage.Shared.Weapons)
local DestructionService = require(script.Parent.DestructionService)

local Remotes = ReplicatedStorage.Remotes
local FireRemote = Remotes.Fire :: RemoteEvent
local ReloadRemote = Remotes.Reload :: RemoteEvent
local ShotFired = Remotes.ShotFired :: RemoteEvent
local HitConfirmed = Remotes.HitConfirmed :: RemoteEvent
local ReloadStarted = Remotes.ReloadStarted :: RemoteEvent
local Damaged = Remotes.Damaged :: RemoteEvent
local MeleeRemote = Remotes.Melee :: RemoteEvent

local DEFAULT_WEAPON = "Rifle"
local MAX_ORIGIN_DISTANCE = 8 -- studs between the player's head and where they claim to shoot from
local HIT_TOLERANCE = 5 -- extra studs allowed between the claimed hit point and the part (for lag)
local RELOAD_TOLERANCE = 0.15
local MAX_BURST = 3 -- shots that can arrive bunched together because of network jitter
local MAX_PENETRATIONS = 4 -- breakable surfaces one bullet can go through
-- Damage left after going through each kind of breakable surface (Siege: glass and barricades
-- give no protection; drywall loss isn't documented, 0.8 is our pick). Headshots still kill.
local PENETRATION_DAMAGE = { Glass = 1, Soft = 0.8, Barricade = 1 }

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

-- Body or head damage, reduced by range falloff
local function damageAtDistance(weapon: Weapons.Weapon, distance: number, headshot: boolean): number
	local alpha = math.clamp((distance - weapon.FalloffStart) / (weapon.FalloffEnd - weapon.FalloffStart), 0, 1)
	local base = if headshot then weapon.HeadshotDamage else weapon.Damage
	return base * (1 + (weapon.MinDamageScale - 1) * alpha)
end

-- Players frozen in their spawn (pre-round / attackers during defender prep) can't be hurt
local function isProtected(targetHumanoid: Humanoid): boolean
	local targetPlayer = Players:GetPlayerFromCharacter(targetHumanoid.Parent)
	local targetRoot = targetHumanoid.Parent and targetHumanoid.Parent:FindFirstChild("HumanoidRootPart") :: BasePart?
	return targetPlayer ~= nil and targetRoot ~= nil and targetRoot.Anchored
end

-- Deals damage and tells both sides: the attacker gets a hit confirm, the victim gets the
-- direction it came from (for the on-screen damage indicator)
local function applyDamage(attacker: Player, targetHumanoid: Humanoid, damage: number, headshot: boolean, from: Vector3)
	targetHumanoid:SetAttribute("LastDamagedBy", attacker.UserId)
	targetHumanoid:SetAttribute("LastHitHeadshot", headshot)
	targetHumanoid:TakeDamage(damage)
	HitConfirmed:FireClient(attacker, damage, headshot, targetHumanoid.Health <= 0)
	local victim = Players:GetPlayerFromCharacter(targetHumanoid.Parent)
	if victim then
		Damaged:FireClient(victim, from)
	end
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

-- Follows a bullet from origin to endPosition. Glass, drywall and barricades on the way take the
-- hit (holes, shattering) and let it through a bit weaker; any other wall stops it. Returns the
-- damage multiplier that reaches the end, or nil if something solid is in the way.
local function traceShot(origin: Vector3, endPosition: Vector3, shooter: Model, hitKind: DestructionService.HitKind): number?
	local offset = endPosition - origin
	local distance = offset.Magnitude
	if distance < 1 then
		return 1
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { shooter }
	local multiplier = 1
	for _ = 1, MAX_PENETRATIONS + 1 do
		params.FilterDescendantsInstances = ignore
		local result = Workspace:Raycast(origin, offset.Unit * (distance - 0.5), params)
		-- Nothing in the way, or another character (fine, like isBlocked)
		if not result or findHumanoid(result.Instance) then
			return multiplier
		end
		local breakable = result.Instance:GetAttribute("Breakable")
		if not breakable or breakable == "Panel" then
			return nil -- solid (armor panels are bulletproof)
		end
		multiplier *= PENETRATION_DAMAGE[breakable] or 1
		DestructionService.Hit(result.Instance :: BasePart, result.Position, hitKind)
		table.insert(ignore, result.Instance)
	end
	return nil
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
	-- Every bullet breaks what it passes through, hit or miss
	local through = traceShot(origin, endPosition, character, if weapon.Pellets > 1 then "Pellet" else "Bullet")
	if not hitPart or not through then
		return endPosition, nil
	end

	local targetHumanoid = findHumanoid(hitPart)
	if not targetHumanoid or targetHumanoid.Health <= 0 or targetHumanoid.Parent == character then
		return endPosition, nil
	end
	if (endPosition - hitPart.Position).Magnitude > hitPart.Size.Magnitude / 2 + HIT_TOLERANCE then
		return endPosition, nil
	end
	-- No friendly fire
	local targetPlayer = Players:GetPlayerFromCharacter(targetHumanoid.Parent)
	if targetPlayer and not player.Neutral and targetPlayer.Team == player.Team then
		return endPosition, nil
	end
	if isProtected(targetHumanoid) then
		return endPosition, nil
	end

	local headshot = hitPart.Name == "Head"
	local damage = damageAtDistance(weapon, distance, headshot) * (if headshot then 1 else through)
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
	if not root or root.Anchored or character:GetAttribute("Deploying") then
		return -- frozen, or hands busy deploying cover
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
		applyDamage(player, targetHumanoid, total.damage, total.headshot, origin)
	end
end

-- Knife (F): one hit kills. The client says who it stabbed; the server checks the target is
-- really close, in front of the attacker, alive, not a teammate, and not behind a wall.
local MELEE_RANGE = 6.5 -- studs between root parts
local MELEE_WALL_REACH = 7.5 -- studs from the head to where the knife hits a wall / barricade
local MELEE_COOLDOWN = 0.7
local MELEE_DAMAGE = 200
local lastMelee: { [Player]: number } = {}

-- Knife on a wall / barricade / window: the point must be within reach and actually on the part
local function meleeBreakable(character: Model, part: BasePart, point: any)
	local head = character:FindFirstChild("Head") :: BasePart?
	if typeof(point) ~= "Vector3" or not head or (point - head.Position).Magnitude > MELEE_WALL_REACH then
		return
	end
	local localPoint = part.CFrame:PointToObjectSpace(point)
	local half = part.Size / 2 + Vector3.one * 0.5
	if math.abs(localPoint.X) > half.X or math.abs(localPoint.Y) > half.Y or math.abs(localPoint.Z) > half.Z then
		return
	end
	if isBlocked(head.Position, point, character) then
		return -- reaching through another wall
	end
	DestructionService.Hit(part, point, "Melee")
end

local function onMelee(player: Player, targetPart: any, hitPoint: any)
	local now = os.clock()
	if now - (lastMelee[player] or 0) < MELEE_COOLDOWN then
		return
	end
	lastMelee[player] = now

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not character or not humanoid or humanoid.Health <= 0 or not root or root.Anchored or character:GetAttribute("Deploying") then
		return
	end
	if not (typeof(targetPart) == "Instance" and targetPart:IsA("BasePart")) then
		return -- a swing that hit nothing
	end
	if DestructionService.IsBreakable(targetPart) then
		meleeBreakable(character, targetPart, hitPoint)
		return
	end
	local targetHumanoid = findHumanoid(targetPart)
	local targetRoot = targetHumanoid and targetHumanoid.Parent and targetHumanoid.Parent:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not targetHumanoid or not targetRoot or targetHumanoid.Health <= 0 or targetHumanoid.Parent == character then
		return
	end
	local offset = targetRoot.Position - root.Position
	if offset.Magnitude > MELEE_RANGE then
		return
	end
	local flat = Vector3.new(offset.X, 0, offset.Z)
	if flat.Magnitude > 0.5 and root.CFrame.LookVector:Dot(flat.Unit) < 0.2 then
		return -- not in front of the attacker
	end
	local targetPlayer = Players:GetPlayerFromCharacter(targetHumanoid.Parent)
	if targetPlayer and not player.Neutral and targetPlayer.Team == player.Team then
		return
	end
	if isProtected(targetHumanoid) or isBlocked(root.Position, targetRoot.Position, character) then
		return
	end
	applyDamage(player, targetHumanoid, MELEE_DAMAGE, false, root.Position)
end

local function onReload(player: Player)
	local data = playerData[player]
	if not data or data.reloadEnd or data.ammo >= data.weapon.MagazineSize then
		return
	end
	data.reloadEnd = os.clock() + data.weapon.ReloadTime
	ReloadStarted:FireAllClients(player, data.weapon.Name)
end

-- An explosion (breach charge, thermite) at `center`: damage falls off with distance. Anyone on
-- `shieldedSide` (the placer's side of the wall) only takes 40%, like Siege's breach charge.
-- Teammates are spared; you can still hurt yourself.
function WeaponService.Blast(attacker: Player, center: Vector3, radius: number, maxDamage: number, shieldedSide: Vector3?)
	local done: { [Humanoid]: boolean } = {}
	for _, part in Workspace:GetPartBoundsInRadius(center, radius) do
		local humanoid = findHumanoid(part)
		if not humanoid or done[humanoid] or humanoid.Health <= 0 then
			continue
		end
		done[humanoid] = true
		local root = humanoid.Parent and humanoid.Parent:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then
			continue
		end
		local offset = root.Position - center
		local damage = maxDamage * math.clamp(1 - offset.Magnitude / radius, 0, 1)
		if shieldedSide and offset:Dot(shieldedSide) > 0 then
			damage *= 0.4
		end
		local target = Players:GetPlayerFromCharacter(humanoid.Parent)
		local teammate = target ~= nil and target ~= attacker and not attacker.Neutral and target.Team == attacker.Team
		if damage >= 1 and not teammate and not isProtected(humanoid) then
			applyDamage(attacker, humanoid, damage, false, center)
		end
	end
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
		lastMelee[player] = nil
	end)

	FireRemote.OnServerEvent:Connect(onFire)
	ReloadRemote.OnServerEvent:Connect(onReload)
	MeleeRemote.OnServerEvent:Connect(onMelee)
end

WeaponService.DefaultWeapon = DEFAULT_WEAPON

return WeaponService
