-- Server-side anti-cheat basics. Conservative on purpose: rubber-banding or kicking an honest
-- player is worse than missing a cheater, so every threshold below has generous slack.
--
-- Movement is simulated on each player's own client (MovementController, RappelController), so the
-- server can only watch where their HumanoidRootPart ends up. Every CHECK_EVERY seconds:
--   Speed     horizontal distance over the last SPEED_WINDOW seconds vs the fastest legit speed
--             (a 3-speed operator's sprint, from MovementConfig) x SPEED_SLACK
--   Teleport  one huge jump between two checks
--   Flying    in the air and not falling for FLY_TIME seconds (rappelling doesn't count)
--   Noclip    moved straight through solid, unbreakable map geometry (walls, concrete floors;
--             never glass, soft walls, barricades, hatches or panels, which get holes in them)
-- A violation puts the player back where they last were legit (rubber-band), logs a warning and
-- adds strikes. Strikes fade after STRIKE_WINDOW; KICK_STRIKES inside it is a kick. Never the
-- game's owner, never in Studio: there it's only logged.
--
-- Server teleports (spawns, the defenders' perimeter push-back...) must tell us, or they'd look
-- like cheats: call AntiCheat.Teleported(player) after moving the character, or (from scripts
-- that don't require this module) set the player's "ServerTeleport" attribute to a new value,
-- e.g. player:SetAttribute("ServerTeleport", os.clock()).
--
-- Combat checks live in WeaponService (fire rate, ammo, range, line of sight); it reports what it
-- refuses here (Suspect) and every kill (NoteKill, an aimbot heuristic). Those are only logged.

local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.MovementConfig)

local AntiCheat = {}

-- Never kicked (only logged): the game's owner. Studio never kicks anyone either.
local OWNER_ID = 483786261
local CHECK_EVERY = 0.25 -- seconds between movement checks

-- Speed. The fastest legit second: a 3-speed operator sprinting (~22 studs/s; no jumps, slides or
-- dashes any more). Vaults and pushing off a rope stay under it.
local MAX_BURST_SPEED = Config.SprintSpeed * Config.SpeedRating[3]
local SPEED_SLACK = 1.5 -- x the fastest legit speed (so ~33 studs/s over the window)
local SPEED_WINDOW = 1 -- seconds the speed is averaged over
local LAG_SLACK = 16 -- extra studs for positions arriving bunched up after a network hiccup
local PING_SLACK = 2 -- plus this many seconds-of-ping worth of MAX_BURST_SPEED (high-ping players)

-- Teleport: one step between two checks (on top of the speed allowance for that time)
local TELEPORT_DISTANCE = 60 -- horizontal studs (a sprint covers ~6 in a whole check)
local TELEPORT_UP = 40 -- studs straight up (climbing onto a ledge rises VaultMaxHeight, 4.5)
local MAX_RISE_SPEED = Config.VaultMaxHeight / Config.ClimbTime * 3 -- studs/s up (a climb's quick push up, generously)

-- Flying
local FLY_TIME = 4 -- seconds in the air without falling (there's no jumping: only vaults, ~0.6)
local FALLING_SPEED = 4 -- dropping faster than this (studs/s) counts as falling
local GROUND_REACH = 6 -- studs below your feet that still count as standing on something
local RAPPEL_WALL_REACH = 4 -- a rappeller hangs within this many studs of a wall

-- Noclip
local NOCLIP_MIN_STEP = 1 -- studs: smaller moves are just jitter against a wall
local NOCLIP_DETOUR = 2.5 -- studs: the path shifted up / sideways by this much still has to be blocked
local RAPPEL_HOP = 8 -- studs: the rope moves you in through windows and up onto roofs in one go
local RAPPEL_GRACE = 1.5 -- seconds after letting go of the rope that those hops are still fine
local VAULT_HOP = 6 -- studs: a vault carries you over cover / through a window in one go...
local VAULT_GRACE = 1 -- ...while the "Vaulting" attribute is up (PoseService) and this long after
local MAX_RAY_SKIPS = 8 -- see-through things one noclip ray steps past before giving up (= fine)

-- Grace periods (no checks)
local TELEPORT_GRACE = 1.5 -- seconds after a server teleport (the client takes a moment to catch up)
local RUBBERBAND_GRACE = 0.75 -- seconds after we put someone back (plus 3x their ping)

-- Strikes
local STRIKES = { Speed = 1, Teleport = 2, Flying = 1, Noclip = 2 }
local STRIKE_WINDOW = 60 -- seconds a strike counts for
local KICK_STRIKES = 8 -- strikes inside STRIKE_WINDOW that get you kicked
local KICK_MESSAGE = "Unusual movement detected. If this was a mistake, sorry! Please rejoin."

-- Combat (logged only)
local SUSPECT_LOG_EVERY = 10 -- seconds between log lines per player and reason (the rest are counted)
local AIM_MIN_KILLS = 15 -- kills before the aimbot heuristic says anything
local AIM_HEADSHOT_RATIO = 0.8 -- this share of kills being headshots...
local AIM_SNAP_RATIO = 0.3 -- ...and this share being snaps
local SNAP_ANGLE = 90 -- degrees the body turned in the SNAP_TIME before a kill shot
local SNAP_TIME = 0.15 -- seconds
local LOOK_HISTORY = 0.5 -- seconds of body facing kept per player

type Sample = { t: number, pos: Vector3 }

type Track = {
	root: BasePart,
	samples: { Sample }, -- positions that passed every check, oldest first (the speed window)
	lastGrounded: Vector3, -- where a flyer gets put back
	airTime: number, -- seconds in the air without falling, since last on something
	settleUntil: number, -- after a rubber-band: no checks until the client has caught up
	rappelSeen: number, -- os.clock() the rope was last up
	vaultSeen: number, -- os.clock() they were last mid-vault
	teleportStamp: any, -- the "ServerTeleport" attribute when we last looked
	pendingNoclip: { from: Vector3, detail: string }?, -- seen last check, acted on this one
}

local tracks: { [Player]: Track } = {}
local allowUntil: { [Player]: number } = {} -- server teleports: re-baseline until then
local strikes: { [Player]: { number } } = {} -- one timestamp per strike
local suspicions: { [Player]: { [string]: { last: number, count: number } } } = {}
local aimStats: { [Player]: { kills: number, headshots: number, snaps: number } } = {}
local looks: { [Player]: { { t: number, look: Vector3 } } } = {}

local function isExempt(player: Player): boolean
	return RunService:IsStudio()
		or player.UserId == OWNER_ID
		or (game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId)
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function ping(player: Player): number
	local ok, value = pcall(player.GetNetworkPing, player)
	return if ok and typeof(value) == "number" then math.clamp(value, 0, 1) else 0
end

local function log(player: Player, message: string)
	warn(`[AntiCheat] {player.Name} ({player.UserId}): {message}`)
end

local function addStrikes(player: Player, count: number)
	local now = os.clock()
	local list = strikes[player] or {}
	strikes[player] = list
	while list[1] and now - list[1] > STRIKE_WINDOW do
		table.remove(list, 1)
	end
	for _ = 1, count do
		table.insert(list, now)
	end
	if #list < KICK_STRIKES then
		return
	end
	table.clear(list)
	if isExempt(player) then
		log(player, `{KICK_STRIKES} strikes in {STRIKE_WINDOW}s: would be kicked (not here: owner / Studio)`)
	else
		log(player, `{KICK_STRIKES} strikes in {STRIKE_WINDOW}s: kicked`)
		player:Kick(KICK_MESSAGE)
	end
end

-- Map geometry for the noclip check: the match map (or the test arena). Not the lobby.
local function mapRoots(): { Instance }
	local roots = {}
	for _, name in { "Map", "TestArena" } do
		local root = Workspace:FindFirstChild(name)
		if root then
			table.insert(roots, root)
		end
	end
	return roots
end

-- Solid = anchored, collidable, and nothing that can get a hole in it (DestructionService marks
-- those with a "Breakable" attribute, on the part or its barricade / device model)
local function isSolid(part: Instance): boolean
	if not part:IsA("BasePart") or not part.Anchored or not part.CanCollide then
		return false
	end
	if part:GetAttribute("Breakable") ~= nil then
		return false
	end
	local model = part:FindFirstAncestorOfClass("Model")
	return not (model and (model:GetAttribute("Breakable") ~= nil or model:FindFirstChildOfClass("Humanoid")))
end

-- The first solid map part on the line from `from` to `to`, stepping past anything else
local function solidHit(from: Vector3, to: Vector3, params: RaycastParams): RaycastResult?
	local offset = to - from
	local distance = offset.Magnitude
	if distance < 0.05 then
		return nil
	end
	local direction = offset / distance
	local travelled = 0
	for _ = 1, MAX_RAY_SKIPS do
		local result = Workspace:Raycast(from + direction * travelled, direction * (distance - travelled), params)
		if not result then
			return nil
		end
		if isSolid(result.Instance) then
			return result
		end
		travelled = (result.Position - from).Magnitude + 0.05
		if travelled >= distance then
			return nil
		end
	end
	return nil -- too cluttered to tell: assume it's fine
end

-- Did the root go straight through a wall / floor between `from` and `to`? Only if the line is
-- blocked both ways (it came out the other side, not just stuck in something) AND every nearby
-- path is blocked too: shifted up (vaulting over a sill, walking up stairs), down a little
-- (ducking under a beam) and to either side (cutting a doorway corner, curving round a pillar
-- between two checks).
local function throughWall(from: Vector3, to: Vector3): boolean
	local roots = mapRoots()
	if #roots == 0 then
		return false
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = roots
	params.RespectCanCollide = true -- (open doors / anything turned non-collidable)
	if not solidHit(from, to, params) or not solidHit(to, from, params) then
		return false
	end
	local along = flat(to - from)
	local side = if along.Magnitude > 0.1 then along.Unit:Cross(Vector3.yAxis) else Vector3.xAxis
	local up = Vector3.yAxis
	for _, shift in { up, up * 2, -up * 0.6, side, -side, side + up, -side + up } do
		local offset = shift * NOCLIP_DETOUR
		if not solidHit(from + offset, to + offset, params) then
			return false
		end
	end
	return true
end

-- Is the root standing on (or just above) anything? Everything a character can stand on counts:
-- floors, crates, gadgets, drones, other players' heads, railing guards.
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.RespectCanCollide = true
local function onSomething(character: Model, root: BasePart, humanoid: Humanoid): boolean
	groundParams.FilterDescendantsInstances = { character }
	if PhysicsService:IsCollisionGroupRegistered("Characters") then
		groundParams.CollisionGroup = "Characters" -- (railing guards only collide with characters)
	end
	local reach = humanoid.HipHeight + root.Size.Y / 2 + GROUND_REACH
	local down = Vector3.new(0, -reach, 0)
	if Workspace:Raycast(root.Position, down, groundParams) then
		return true
	end
	-- A wider box too, for standing on a ledge with your middle over the drop
	return Workspace:Blockcast(CFrame.new(root.Position), Vector3.new(3, 0.5, 3), down, groundParams) ~= nil
end

-- Rappelling: the rope is up ("RappelTop", PoseService), you hang below the knot, against a wall
local function isRappelling(character: Model, root: BasePart): boolean
	local top = character:GetAttribute("RappelTop")
	if typeof(top) ~= "number" or root.Position.Y > top + 2 then
		return false
	end
	local roots = mapRoots()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = roots
	for _, direction in { Vector3.xAxis, -Vector3.xAxis, Vector3.zAxis, -Vector3.zAxis } do
		if Workspace:Raycast(root.Position, direction * RAPPEL_WALL_REACH, params) then
			return true
		end
	end
	return false
end

local function newTrack(root: BasePart, now: number, stamp: any): Track
	return {
		root = root,
		samples = { { t = now, pos = root.Position } },
		lastGrounded = root.Position,
		airTime = 0,
		settleUntil = 0,
		rappelSeen = -math.huge,
		vaultSeen = -math.huge,
		teleportStamp = stamp,
	}
end

-- Start over from where they are now (spawned, teleported by us, frozen)
local function rebaseline(track: Track, now: number)
	local position = track.root.Position
	track.samples = { { t = now, pos = position } }
	track.lastGrounded = position
	track.airTime = 0
	track.pendingNoclip = nil
end

-- Put them back at `to`, log it and add strikes
local function violation(player: Player, track: Track, kind: string, to: Vector3, detail: string)
	local now = os.clock()
	local root = track.root
	root.AssemblyLinearVelocity = Vector3.zero
	root.CFrame = CFrame.new(to) * root.CFrame.Rotation
	track.samples = { { t = now, pos = to } }
	track.lastGrounded = to
	track.airTime = 0
	track.pendingNoclip = nil
	-- Their client keeps sending where it was until our correction reaches it: wait that out.
	-- (Samples carry on from `to` afterwards, so ignoring the correction is caught next time.)
	track.settleUntil = now + RUBBERBAND_GRACE + ping(player) * 3
	log(player, `{kind} ({detail}): put back`)
	addStrikes(player, STRIKES[kind] or 1)
end

local function checkPlayer(player: Player, now: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not character or not humanoid or not root or humanoid.Health <= 0 or not root:IsDescendantOf(Workspace) then
		tracks[player] = nil
		return
	end
	local stamp = player:GetAttribute("ServerTeleport")
	local track = tracks[player]
	if not track or track.root ~= root then
		tracks[player] = newTrack(root, now, stamp) -- a new character
		return
	end
	if stamp ~= track.teleportStamp then
		track.teleportStamp = stamp
		allowUntil[player] = math.max(allowUntil[player] or 0, now + TELEPORT_GRACE)
	end
	-- Frozen (pre-round), or just teleported by the server: wherever they are is fine
	if root.Anchored or now < (allowUntil[player] or 0) then
		rebaseline(track, now)
		return
	end
	if now < track.settleUntil then
		return
	end

	local position = root.Position
	local rappelling = isRappelling(character, root)
	if rappelling then
		track.rappelSeen = now
	end
	local previous = track.samples[#track.samples]
	local step = position - previous.pos
	local elapsed = math.max(now - previous.t, 1e-3)
	local horizontal = flat(step).Magnitude
	local speedLimit = MAX_BURST_SPEED * SPEED_SLACK
	local slack = LAG_SLACK + ping(player) * PING_SLACK * MAX_BURST_SPEED

	-- Teleport: one huge jump since the last check
	if horizontal > math.max(TELEPORT_DISTANCE, speedLimit * elapsed + slack) then
		violation(player, track, "Teleport", previous.pos, `{math.floor(horizontal)} studs in {string.format("%.2f", elapsed)}s`)
		return
	end
	if step.Y > math.max(TELEPORT_UP, MAX_RISE_SPEED * SPEED_SLACK * elapsed + slack) then
		violation(player, track, "Teleport", previous.pos, `{math.floor(step.Y)} studs up in {string.format("%.2f", elapsed)}s`)
		return
	end

	-- Noclip: straight through a wall since the last check (the rope's own hops excepted). It's
	-- only acted on one check later: stepping off a roof onto a rope can reach us a moment before
	-- the "RappelTop" attribute that explains it.
	local ropeTime = rappelling or now - track.rappelSeen < RAPPEL_GRACE
	if character:GetAttribute("Vaulting") == true then
		track.vaultSeen = now
	end
	local vaultTime = now - track.vaultSeen < VAULT_GRACE
	local pending = track.pendingNoclip
	track.pendingNoclip = nil
	if pending and not ropeTime and not vaultTime then
		violation(player, track, "Noclip", pending.from, pending.detail)
		return
	end
	local ropeHop = (ropeTime and step.Magnitude <= RAPPEL_HOP) or (vaultTime and step.Magnitude <= VAULT_HOP)
	if step.Magnitude >= NOCLIP_MIN_STEP and not ropeHop and throughWall(previous.pos, position) then
		track.pendingNoclip = { from = previous.pos, detail = `through the map, {math.floor(step.Magnitude)} studs` }
	end

	-- Speed over the window (the oldest sample kept is the last one at least a window old)
	local samples = track.samples
	while #samples >= 2 and now - samples[2].t >= SPEED_WINDOW do
		table.remove(samples, 1)
	end
	local oldest = samples[1]
	local span = now - oldest.t
	local distance = flat(position - oldest.pos).Magnitude
	if distance > speedLimit * span + slack then
		violation(player, track, "Speed", oldest.pos, `{math.floor(distance)} studs in {string.format("%.2f", span)}s`)
		return
	end

	-- Flying: in the air, not falling, for too long
	if rappelling or onSomething(character, root, humanoid) then
		track.airTime = 0
		track.lastGrounded = position
	elseif step.Y > -FALLING_SPEED * elapsed then
		track.airTime += elapsed
		if track.airTime >= FLY_TIME then
			violation(player, track, "Flying", track.lastGrounded, `{string.format("%.1f", track.airTime)}s in the air`)
			return
		end
	end

	table.insert(samples, { t = now, pos = position })
end

-- Which way each player's body faced lately (in first person it turns with the camera)
local function recordLooks(now: number)
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then
			looks[player] = nil
			continue
		end
		local list = looks[player] or {}
		looks[player] = list
		table.insert(list, { t = now, look = root.CFrame.LookVector })
		while list[1] and now - list[1].t > LOOK_HISTORY do
			table.remove(list, 1)
		end
	end
end

local function lookAt(player: Player, time: number): Vector3?
	local list = looks[player]
	if not list then
		return nil
	end
	for i = #list, 1, -1 do
		if list[i].t <= time then
			return list[i].look
		end
	end
	return nil
end

-- A server teleport just moved `player`'s character: don't count it (or anything for `seconds`)
function AntiCheat.Teleported(player: Player, seconds: number?)
	allowUntil[player] = math.max(allowUntil[player] or 0, os.clock() + (seconds or TELEPORT_GRACE))
	local track = tracks[player]
	if track then
		rebaseline(track, os.clock())
	end
end

-- WeaponService refused something (fire rate, empty mag, a hit through a wall...). Honest lag can
-- do all of these now and then, so it's only logged, at most once per SUSPECT_LOG_EVERY per reason.
function AntiCheat.Suspect(player: Player, reason: string)
	local now = os.clock()
	local byReason = suspicions[player] or {}
	suspicions[player] = byReason
	local entry = byReason[reason] or { last = -math.huge, count = 0 }
	byReason[reason] = entry
	entry.count += 1
	if now - entry.last >= SUSPECT_LOG_EVERY then
		log(player, `{reason} (x{entry.count})`)
		entry.last = now
		entry.count = 0
	end
end

-- A gun kill on another player (`direction`: where the shot went). Aimbot heuristic, logged only:
-- lots of kills, nearly all headshots, many right after the body whipped round.
function AntiCheat.NoteKill(player: Player, headshot: boolean, direction: Vector3?)
	local stats = aimStats[player] or { kills = 0, headshots = 0, snaps = 0 }
	aimStats[player] = stats
	stats.kills += 1
	if headshot then
		stats.headshots += 1
	end
	local before = lookAt(player, os.clock() - SNAP_TIME)
	local aim = if direction then flat(direction) else Vector3.zero
	if before and aim.Magnitude > 0.1 and flat(before).Magnitude > 0.1 then
		local angle = math.deg(math.acos(math.clamp(flat(before).Unit:Dot(aim.Unit), -1, 1)))
		if angle >= SNAP_ANGLE and headshot then
			stats.snaps += 1
		end
	end
	if stats.kills >= AIM_MIN_KILLS and stats.kills % 5 == 0 then
		local headshotRatio = stats.headshots / stats.kills
		local snapRatio = stats.snaps / stats.kills
		if headshotRatio >= AIM_HEADSHOT_RATIO and snapRatio >= AIM_SNAP_RATIO then
			log(player, `possible aimbot: {stats.kills} kills, {math.round(headshotRatio * 100)}% headshots, {stats.snaps} snap headshots (logged only)`)
		end
	end
end

function AntiCheat.Start()
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		local now = os.clock()
		recordLooks(now)
		elapsed += dt
		if elapsed < CHECK_EVERY then
			return
		end
		elapsed = 0
		for _, player in Players:GetPlayers() do
			local ok, err = pcall(checkPlayer, player, now)
			if not ok then
				warn(`[AntiCheat] check failed for {player.Name}: {err}`)
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		tracks[player] = nil
		allowUntil[player] = nil
		strikes[player] = nil
		suspicions[player] = nil
		aimStats[player] = nil
		looks[player] = nil
	end)
end

return AntiCheat
