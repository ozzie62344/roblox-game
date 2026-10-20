-- Server side of shooting. Never trusts the client blindly: checks fire rate, ammo,
-- where the shot came from, and that each hit is actually possible before dealing damage.
-- Each player's current weapon is stored in their "Weapon" attribute (set by loadouts / dev panel).
-- GameRules.NoGun ("Knife", Knives Only) means no gun: every shot and reload is refused.
-- Headshots Only (GameRules): body shots do no damage.
-- Damage rules (Siege): a bullet to the head kills (Weapons HeadshotKills; shotgun pellets don't),
-- arms and legs take 75%, armor takes body / limb damage down (1 / 2 / 3 armor: x1 / x0.9 / x0.8),
-- and every gun loses damage with range (Weapons FalloffStart / FalloffEnd / MinDamageScale).
-- A hit that would kill a player in a match can down them instead (DBNOService, Siege's down but
-- not out); downed players can't shoot or knife.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameRules = require(ReplicatedStorage.Shared.GameRules)
local Operators = require(ReplicatedStorage.Shared.Operators)
local Weapons = require(ReplicatedStorage.Shared.Weapons)
local AntiCheat = require(script.Parent.AntiCheat)
local DBNOService = require(script.Parent.DBNOService)
local DestructionService = require(script.Parent.DestructionService)
local MatchStats = require(script.Parent.MatchStats)

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
-- (anti-cheat) Fire rate allowed on average: RPM x this (the client never goes over RPM itself)
local FIRE_RATE_TOLERANCE = 1.15
-- (anti-cheat) The camera can lean / drop a little past the head (and the server's copy of the
-- head lags a moving player a little), but a shot origin this many studs beyond a solid wall
-- (seen from the head) is shooting from the other side of it
local ORIGIN_WALL_DEPTH = 2
local MAX_PENETRATIONS = 4 -- breakable surfaces one bullet can go through
-- Damage left after going through each kind of breakable surface (Siege: glass and barricades
-- give no protection; drywall loss isn't documented, 0.8 is our pick). Headshots still kill.
local PENETRATION_DAMAGE = { Glass = 1, Soft = 0.8, Barricade = 1 }
-- Body and limb damage taken by armor rating (an operator's Armor; Siege's light / medium / heavy)
local ARMOR_DAMAGE = { 1, 0.9, 0.8 }
local DEFAULT_ARMOR = 2 -- anyone without an operator (bots, dummies, a dev-panel loadout)
local LIMB_DAMAGE = 0.75 -- arms and legs (hands and feet too)
local HEADSHOT_KILL_DAMAGE = 1000 -- "kills outright" (more than anyone's health)
-- A hat / hair / helmet only counts as the head this close to it (studs past the head's box):
-- cosmetics don't make your head bigger, but a bullet clipping a helmet still kills
local ACCESSORY_REACH = 0.4
-- (anti-cheat) A headshot must land within this many studs of the head's height on the server's
-- copy of the target. Lag shifts people sideways far more than up and down, so real headshots
-- pass, but a body hit relabelled "Head" by a modified client doesn't.
local HEAD_HEIGHT_SLACK = ACCESSORY_REACH + 0.5

local WeaponService = {}

type PlayerData = {
	weapon: Weapons.Weapon,
	ammo: number,
	reloadEnd: number?,
	reloadAmmo: number, -- what the mag holds once the reload in progress is done
	shotBudget: number,
	lastFire: number,
}

local playerData: { [Player]: PlayerData } = {}

local function resetData(player: Player)
	if player:GetAttribute("Weapon") == GameRules.NoGun then
		playerData[player] = nil -- no gun: nothing to shoot or reload
		return
	end
	local weapon = Weapons[player:GetAttribute("Weapon") or DEFAULT_WEAPON] or Weapons[DEFAULT_WEAPON]
	playerData[player] = {
		weapon = weapon,
		ammo = weapon.MagazineSize + weapon.Chamber, -- (you spawn with one up the spout: 30+1)
		reloadEnd = nil,
		reloadAmmo = weapon.MagazineSize,
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

type Zone = "Head" | "Body" | "Limb"

local function zoneOf(partName: string): Zone
	if partName == "Head" then
		return "Head"
	end
	-- R15 (LeftUpperArm, RightFoot...) and R6 (Left Arm, Right Leg) limbs
	for _, limb in { "Arm", "Leg", "Hand", "Foot" } do
		if string.find(partName, limb, 1, true) then
			return "Limb"
		end
	end
	return "Body"
end

-- Which part of the body a bullet hit. Accessories (hats, hair, backpacks) count as the body
-- part they're worn on, but only right next to it: nil = it only clipped a cosmetic (no damage).
local function hitZone(hitPart: BasePart, endPosition: Vector3): Zone?
	local accessory = hitPart.Parent
	if not (accessory and accessory:IsA("Accessory")) then
		return zoneOf(hitPart.Name)
	end
	local weld = hitPart:FindFirstChild("AccessoryWeld")
	local wornOn = if weld and weld:IsA("Weld") then (if weld.Part0 == hitPart then weld.Part1 else weld.Part0) else nil
	if not wornOn then
		return nil
	end
	local localPoint = wornOn.CFrame:PointToObjectSpace(endPosition)
	local half = wornOn.Size / 2 + Vector3.one * ACCESSORY_REACH
	if math.abs(localPoint.X) > half.X or math.abs(localPoint.Y) > half.Y or math.abs(localPoint.Z) > half.Z then
		return nil
	end
	return zoneOf(wornOn.Name)
end

-- Body / limb damage multiplier for whoever got hit (their operator's armor)
local function armorScale(targetHumanoid: Humanoid): number
	local character = targetHumanoid.Parent
	local targetPlayer = Players:GetPlayerFromCharacter(character)
	local armor: any = nil
	if targetPlayer then
		local operator = Operators.ById[targetPlayer:GetAttribute("Operator") or ""]
		armor = operator and (operator :: any).Armor
	elseif character then
		armor = character:GetAttribute("Armor") -- (a bot can say)
	end
	return ARMOR_DAMAGE[armor] or ARMOR_DAMAGE[DEFAULT_ARMOR]
end

-- Range falloff: 1 up to FalloffStart, down to MinDamageScale at FalloffEnd
local function rangeScale(weapon: Weapons.Weapon, distance: number): number
	local alpha = math.clamp((distance - weapon.FalloffStart) / (weapon.FalloffEnd - weapon.FalloffStart), 0, 1)
	return 1 + (weapon.MinDamageScale - 1) * alpha
end

-- One bullet's / pellet's damage. `through` = what's left after glass / drywall on the way.
local function bulletDamage(weapon: Weapons.Weapon, distance: number, zone: Zone, targetHumanoid: Humanoid, through: number): number
	if zone == "Head" then
		if weapon.HeadshotKills then
			return HEADSHOT_KILL_DAMAGE -- (through drywall too, like Siege)
		end
		return (weapon.HeadshotDamage or weapon.Damage) * rangeScale(weapon, distance) -- (shotgun pellets)
	end
	local zoneScale = if zone == "Limb" then LIMB_DAMAGE else 1
	return weapon.Damage * rangeScale(weapon, distance) * zoneScale * armorScale(targetHumanoid) * through
end

-- Friendly fire is on, like Siege: teammates' bullets, knives and blasts hurt (and down) each
-- other. Only a custom match with friendly fire turned off (MatchState "FriendlyFire" = false)
-- protects teammates. (The lobby and practice range are protected separately: isProtected.)
local function isTeammate(attacker: Player, target: Player?): boolean
	return target ~= nil and target ~= attacker and not attacker.Neutral and target.Team == attacker.Team
		and ReplicatedStorage.MatchState:GetAttribute("FriendlyFire") == false
end

-- Players frozen in their spawn (pre-round / attackers during defender prep) can't be hurt
local function isProtected(targetHumanoid: Humanoid): boolean
	local targetPlayer = Players:GetPlayerFromCharacter(targetHumanoid.Parent)
	-- No PvP in the lobby (its practice range shoots bots only: PracticeRange / PracticeBots)
	if targetPlayer and targetPlayer:GetAttribute("Location") == "Lobby" then
		return true
	end
	local targetRoot = targetHumanoid.Parent and targetHumanoid.Parent:FindFirstChild("HumanoidRootPart") :: BasePart?
	return targetPlayer ~= nil and targetRoot ~= nil and targetRoot.Anchored
end

-- Deals damage and tells both sides: the attacker gets a hit confirm, the victim gets the
-- direction it came from (for the on-screen damage indicator). `with` is what did it (a weapon
-- name, "Knife" or "Blast"): the victim's kill cam says so (MatchStats.KillDetails).
local function applyDamage(attacker: Player, targetHumanoid: Humanoid, damage: number, headshot: boolean, from: Vector3, with: string?)
	targetHumanoid:SetAttribute("LastDamagedBy", attacker.UserId)
	targetHumanoid:SetAttribute("LastHitHeadshot", headshot)
	targetHumanoid:SetAttribute("LastHitWith", with)
	MatchStats.Damage(attacker, targetHumanoid, damage) -- (before it lands: only the health they had counts)
	-- A hit that would kill can down a player instead (their health becomes the down pool)
	local downed = DBNOService.TryDown(targetHumanoid, damage, headshot, with)
	if not downed then
		targetHumanoid:TakeDamage(damage)
	end
	-- (the 5th argument: it downed them, the attacker's hit marker says so)
	HitConfirmed:FireClient(attacker, damage, headshot, targetHumanoid.Health <= 0, downed)
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

-- (anti-cheat) Is the claimed shot origin on the far side of a solid wall from the shooter's head?
-- Only unbreakable walls count (bullets go through glass / drywall / barricades anyway), not
-- floors or ceilings (lying down drops the camera below the head), and only well past the face.
local function originBehindWall(head: BasePart, origin: Vector3, shooter: Model): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { shooter }
	local offset = origin - head.Position
	if offset.Magnitude < ORIGIN_WALL_DEPTH then
		return false
	end
	local result = Workspace:Raycast(head.Position, offset, params)
	if not result or findHumanoid(result.Instance) or result.Instance:GetAttribute("Breakable") then
		return false
	end
	return math.abs(result.Normal.Y) < 0.7 and (origin - result.Position).Magnitude > ORIGIN_WALL_DEPTH
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
		if not breakable or breakable == "Panel" or breakable == "Bulletproof" then
			return nil -- solid (armor panels and bulletproof cameras stop bullets)
		end
		multiplier *= PENETRATION_DAMAGE[breakable] or 1
		DestructionService.Hit(result.Instance :: BasePart, result.Position, hitKind)
		table.insert(ignore, result.Instance)
	end
	return nil
end

type Hit = { humanoid: Humanoid, damage: number, headshot: boolean }

-- Validates one bullet/pellet. Returns its end position (for tracers), the hit, if any, and
-- whether it ended in someone (impact effects: blood, not a bullet hole).
local function checkShot(player: Player, character: Model, weapon: Weapons.Weapon, origin: Vector3, shot: any): (Vector3?, Hit?, boolean?)
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
		if hitPart and not through and findHumanoid(hitPart) then
			AntiCheat.Suspect(player, "hit claimed through a solid wall") -- (anti-cheat, logged only)
		end
		return endPosition, nil
	end

	local targetHumanoid = findHumanoid(hitPart)
	if not targetHumanoid or targetHumanoid.Health <= 0 or targetHumanoid.Parent == character then
		return endPosition, nil, targetHumanoid ~= nil
	end
	if (endPosition - hitPart.Position).Magnitude > hitPart.Size.Magnitude / 2 + HIT_TOLERANCE then
		return endPosition, nil
	end
	-- No friendly fire (unless it's on: isTeammate)
	local targetPlayer = Players:GetPlayerFromCharacter(targetHumanoid.Parent)
	if isTeammate(player, targetPlayer) then
		return endPosition, nil, true
	end
	if isProtected(targetHumanoid) then
		return endPosition, nil, true
	end

	local zone = hitZone(hitPart, endPosition)
	if not zone then
		return endPosition, nil, true -- only clipped a hat
	end
	if zone == "Head" then
		local targetHead = (targetHumanoid.Parent :: Model):FindFirstChild("Head") :: BasePart?
		if not targetHead or math.abs(endPosition.Y - targetHead.Position.Y) > targetHead.Size.Y / 2 + HEAD_HEIGHT_SLACK then
			AntiCheat.Suspect(player, "headshot claimed away from the head") -- (logged; counts as a body hit)
			zone = "Body"
		end
	end
	local headshot = zone == "Head"
	if GameRules.Current().HeadshotsOnly and not headshot then
		return endPosition, nil, true
	end
	local damage = bulletDamage(weapon, distance, zone, targetHumanoid, through)
	return endPosition, { humanoid = targetHumanoid, damage = damage, headshot = headshot }, true
end

-- (anti-cheat) Hands busy with something else, so no gun or knife: driving a drone, watching
-- cameras, the heartbeat sensor out, or planting / disabling / fortifying / reviving. The client
-- puts the gun away for all of these; this is for clients that don't.
local function handsBusy(player: Player, character: Model): boolean
	return player:GetAttribute("Droning") ~= nil or player:GetAttribute("OnCams") ~= nil
		or player:GetAttribute("Interaction") ~= nil or character:GetAttribute("Scanning") ~= nil
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
	if not root or root.Anchored or character:GetAttribute("Deploying") or character:GetAttribute("Downed") then
		return -- frozen, hands busy deploying cover, or downed (DBNOService)
	end
	if handsBusy(player, character :: Model) then
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
		data.ammo = data.reloadAmmo
		data.reloadEnd = nil
	end
	if data.ammo <= 0 then
		AntiCheat.Suspect(player, "shot with an empty mag") -- (anti-cheat, logged only)
		return
	end

	-- Fire rate: a small budget absorbs network jitter but caps the average rate
	local interval = 60 / (weapon.RPM * FIRE_RATE_TOLERANCE)
	data.shotBudget = math.min(data.shotBudget + (now - data.lastFire) / interval, MAX_BURST)
	data.lastFire = now
	if data.shotBudget < 1 then
		AntiCheat.Suspect(player, "fire rate over RPM") -- (anti-cheat, logged only)
		return
	end
	data.shotBudget -= 1
	data.ammo -= 1

	-- Shot must start near the shooter's head
	if (origin - head.Position).Magnitude > MAX_ORIGIN_DISTANCE then
		AntiCheat.Suspect(player, "shot origin far from the head") -- (anti-cheat, logged only)
		return
	end
	-- ...and not from the other side of a wall (anti-cheat)
	if originBehindWall(head, origin, character :: Model) then
		AntiCheat.Suspect(player, "shot origin behind a wall")
		return
	end

	local endPositions = {}
	local inFlesh = {} -- (per end position: it ended in someone)
	local totals: { [Humanoid]: { damage: number, headshot: boolean } } = {}
	for i = 1, #shots do -- (only the counted pellets: extra keys in the table are ignored)
		local shot = shots[i]
		local endPosition, hit, flesh = checkShot(player, character :: Model, weapon, origin, shot)
		if endPosition then
			table.insert(endPositions, endPosition)
			table.insert(inFlesh, flesh == true)
		end
		if hit then
			local total = totals[hit.humanoid] or { damage = 0, headshot = false }
			total.damage += hit.damage
			total.headshot = total.headshot or hit.headshot
			totals[hit.humanoid] = total
		end
	end

	if #endPositions > 0 then
		ShotFired:FireAllClients(player, origin, endPositions, weapon.Name, inFlesh)
	end

	-- (anti-cheat) Kills on other players feed the aimbot heuristic: logged only, never acted on
	local aim = if typeof(shots[1]) == "table" and typeof(shots[1][1]) == "Vector3" then shots[1][1] else nil
	for targetHumanoid, total in totals do
		applyDamage(player, targetHumanoid, total.damage, total.headshot, origin, weapon.Name)
		if targetHumanoid.Health <= 0 and Players:GetPlayerFromCharacter(targetHumanoid.Parent) then
			AntiCheat.NoteKill(player, total.headshot, aim)
		end
	end
end

-- Knife (F): one hit kills. The client says who it stabbed; the server checks the target is
-- really close, in front of the attacker, alive, not a teammate, and not behind a wall.
local MELEE_RANGE = 6.5 -- studs between root parts
local MELEE_WALL_REACH = 7.5 -- studs from the head to where the knife hits a wall / barricade
local MELEE_SLACK = 0.15 -- seconds of slack on the knife cooldown for network jitter
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
	if now - (lastMelee[player] or 0) < GameRules.MeleeCooldown() - MELEE_SLACK then
		return
	end
	lastMelee[player] = now

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not character or not humanoid or humanoid.Health <= 0 or not root or root.Anchored or character:GetAttribute("Deploying") then
		return
	end
	if handsBusy(player, character) then
		return
	end
	if character:GetAttribute("Downed") then
		return -- (downed: no knife, DBNOService)
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
	if isTeammate(player, targetPlayer) then
		return
	end
	if isProtected(targetHumanoid) or isBlocked(root.Position, targetRoot.Position, character) then
		return
	end
	applyDamage(player, targetHumanoid, MELEE_DAMAGE, false, root.Position, "Knife")
end

-- Tactical reload (rounds left): the one in the chamber stays, so the mag ends up 30+1. Empty:
-- slower (the bolt / slide / pump has to be worked) and that chambers one from the new mag (30).
-- WeaponController does the same sums.
local function onReload(player: Player)
	local data = playerData[player]
	if not data or data.reloadEnd or data.ammo >= data.weapon.MagazineSize + data.weapon.Chamber then
		return
	end
	local weapon = data.weapon
	local empty = data.ammo <= 0
	local duration = if empty then weapon.EmptyReloadTime else weapon.ReloadTime
	data.reloadEnd = os.clock() + duration
	data.reloadAmmo = weapon.MagazineSize + (if empty then 0 else math.min(data.ammo, weapon.Chamber))
	ReloadStarted:FireAllClients(player, weapon.Name, duration)
end

-- An explosion (breach charge, thermite) at `center`: damage falls off with distance. Anyone on
-- `shieldedSide` (the placer's side of the wall) only takes 40%, like Siege's breach charge.
-- Teammates are spared (unless friendly fire is on: isTeammate); you can still hurt yourself.
-- Is there nothing solid between `from` and `to`? Soft things (drywall, wooden floors, glass,
-- barricades) don't count, like bullets going through them; steel, concrete and armor do.
local function softPathBetween(from: Vector3, to: Vector3, ignore: { Instance }): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local skip = table.clone(ignore)
	for _ = 1, MAX_PENETRATIONS + 1 do
		params.FilterDescendantsInstances = skip
		local result = Workspace:Raycast(from, to - from, params)
		if not result or findHumanoid(result.Instance) then
			return true
		end
		local breakable = result.Instance:GetAttribute("Breakable")
		if not breakable or breakable == "Panel" or breakable == "Bulletproof" then
			return false
		end
		table.insert(skip, result.Instance)
	end
	return false
end

-- Explosion damage around `center`, less further out. `shieldedSide`: people on that side take
-- 40% (the far side of a wall a charge is on). `softOnly`: nobody behind anything solid is hurt
-- (frags, claymores, nitro cells: through drywall and floors, not concrete).
function WeaponService.Blast(attacker: Player, center: Vector3, radius: number, maxDamage: number, shieldedSide: Vector3?, softOnly: boolean?)
	local done: { [Humanoid]: boolean } = {}
	local deployables = Workspace:FindFirstChild("Deployables")
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
		if softOnly and not softPathBetween(center, root.Position, if deployables then { humanoid.Parent :: Instance, deployables } else { humanoid.Parent :: Instance }) then
			continue
		end
		local offset = root.Position - center
		local damage = maxDamage * math.clamp(1 - offset.Magnitude / radius, 0, 1)
		if shieldedSide and offset:Dot(shieldedSide) > 0 then
			damage *= 0.4
		end
		local target = Players:GetPlayerFromCharacter(humanoid.Parent)
		local teammate = isTeammate(attacker, target)
		if damage >= 1 and not teammate and not isProtected(humanoid) then
			applyDamage(attacker, humanoid, damage, false, center, "Blast")
		end
	end
end

function WeaponService.Refill(player: Player)
	local data = playerData[player]
	if data then
		data.ammo = data.weapon.MagazineSize + data.weapon.Chamber
		data.reloadEnd = nil
	end
end

-- Gives a player a weapon (full magazine). The client follows the "Weapon" attribute.
function WeaponService.SetWeapon(player: Player, weaponName: string)
	if not Weapons[weaponName] and weaponName ~= GameRules.NoGun then
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
