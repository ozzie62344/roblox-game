-- Practice bots for the lobby's practice range (PracticeRange builds the range and says when
-- someone's in it). R6 rigs (made like Dummies' targets) that walk between spots with
-- PathfindingService, sidestep a little, tuck in behind cover and peek out of it, and shoot back:
-- short, inaccurate, weak bursts, only at players inside the range ("InPracticeRange"). They're
-- ordinary humanoids, so WeaponService hits them like anyone else (Head = headshot); their kills
-- never count for anything (only player deaths in a match do: RoundService).
-- A player the bots "kill" isn't killed: they're healed and put back at the range entrance.
-- Each area keeps its number of bots alive (a dead one comes back a few seconds later) while
-- the range is active; when it goes quiet they're all cleared away (SetActive).

local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local Workspace = game:GetService("Workspace")

local PracticeBots = {}

PracticeBots.Group = "PracticeBots" -- collision group of the bots' bodies
PracticeBots.WallGroup = "PracticeBotWalls" -- invisible walls only bots bump into (PracticeRange)

export type Point = { at: Vector3, peeks: { Vector3 }? } -- on the floor; peeks: spots beside the cover
export type Area = { count: number, points: { Point } }
export type Layout = {
	areas: { Area },
	entrance: CFrame, -- on the floor, where downed players are put back
	contains: (Vector3) -> boolean, -- inside the range?
	remote: RemoteEvent, -- "Shot" (to clients in the lobby) / "Downed" (to the player)
	attribute: string, -- player attribute: in the range (set by PracticeRange)
}

type Bot = {
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	head: BasePart,
	muzzle: Attachment,
	shoulder: Motor6D?,
	shoulderC0: CFrame,
	area: Area,
	home: Vector3,
	path: Path,
	generation: number,
	holding: boolean, -- standing still (or sidestepping): free to turn and shoot
	target: Player?,
	seenAt: number?,
	nextBurst: number,
}

local BOT_HEALTH = 100
local WALK_SPEED = 9
local RESPAWN_DELAY = 4
local SIGHT_RANGE = 110
local REACTION_TIME = 0.7 -- seconds you're in view before the first burst
local BURST_SIZE = 3
local BURST_GAP = 0.13
local BURST_PAUSE_MIN, BURST_PAUSE_MAX = 1.6, 3
local AIM_ERROR = 1.6 -- studs the whole burst is off by (at most)
local SPREAD = 2.5 -- degrees each shot wanders on top of that
local DAMAGE = 6
local SHOT_RANGE = 200
local SPAWN_CLEARANCE = 18 -- studs from any player a bot (re)appears
local WALK_ANIMATION = "rbxassetid://180426354" -- Roblox's default R6 walk / idle
local IDLE_ANIMATION = "rbxassetid://180435571"

local SKIN = Color3.fromRGB(165, 165, 170)
local VEST = Color3.fromRGB(205, 120, 50) -- (the lobby's accent, so they stand out in the dim range)
local CLOTHES = Color3.fromRGB(56, 60, 70)
local GUN = Color3.fromRGB(28, 29, 32)

local layout: Layout? = nil
local active = false
local generation = 0 -- bumped by SetActive(false): bots from before stop and don't respawn
local random = Random.new()

local function getFolder(): Folder
	local folder = Workspace:FindFirstChild("PracticeBots")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "PracticeBots"
		folder.Parent = Workspace
	end
	return folder :: Folder
end

local function alive(bot: Bot): boolean
	return bot.generation == generation and bot.humanoid.Health > 0 and bot.model.Parent ~= nil
end

local function rand(min: number, max: number): number
	return random:NextNumber(min, max)
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- Players in the range a bot may shoot at
local function targets(): { Player }
	local list = {}
	if not layout then
		return list
	end
	for _, player in Players:GetPlayers() do
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if player:GetAttribute(layout.attribute) == true and humanoid and humanoid.Health > 0 then
			table.insert(list, player)
		end
	end
	return list
end

-- A spot in the area away from the players (so nobody gets one spawned in their face)
local function spawnPoint(area: Area): Point
	local far = {}
	for _, point in area.points do
		local clear = true
		for _, player in targets() do
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root and (flat(root.Position) - flat(point.at)).Magnitude < SPAWN_CLEARANCE then
				clear = false
			end
		end
		if clear then
			table.insert(far, point)
		end
	end
	local list = if #far > 0 then far else area.points
	return list[random:NextInteger(1, #list)]
end

-- Turns the bot (and only around the vertical) to look at a point
local function face(bot: Bot, position: Vector3)
	local from = bot.root.Position
	local to = Vector3.new(position.X, from.Y, position.Z)
	if (to - from).Magnitude > 0.1 then
		bot.humanoid.AutoRotate = false
		bot.root.CFrame = CFrame.lookAt(from, to)
	end
end

-- Gun arm up (pointing ahead) or down
local function raiseArm(bot: Bot, up: boolean)
	if bot.shoulder then
		bot.shoulder.C0 = if up then bot.shoulderC0 * CFrame.Angles(0, 0, math.pi / 2) else bot.shoulderC0
	end
end

-- Walks straight to a point. False if it took too long (stuck) or the bot died / was cleared.
local function walkTo(bot: Bot, target: Vector3, timeout: number): boolean
	bot.humanoid:MoveTo(target)
	local started = os.clock()
	while alive(bot) do
		if (flat(bot.root.Position) - flat(target)).Magnitude < 1.5 then
			return true
		end
		if os.clock() - started > timeout then
			return false
		end
		task.wait(0.1)
	end
	return false
end

-- Walks to a point the long way round if need be (doorways, cover)
local function travel(bot: Bot, target: Vector3)
	bot.holding = false
	bot.humanoid.AutoRotate = true
	raiseArm(bot, false)
	local ok = pcall(function()
		bot.path:ComputeAsync(bot.root.Position, target)
	end)
	if ok and bot.path.Status == Enum.PathStatus.Success then
		for i, waypoint in bot.path:GetWaypoints() do
			if i > 1 and not walkTo(bot, waypoint.Position, 3) then
				return
			end
		end
	else
		walkTo(bot, target, 6)
	end
end

-- Stands still for a while (free to turn and shoot). Spotting someone keeps it there a bit longer.
local function hold(bot: Bot, seconds: number)
	bot.holding = true
	bot.humanoid:MoveTo(bot.root.Position) -- (stop where it is)
	local untilTime = os.clock() + seconds
	local extended = false
	while alive(bot) and os.clock() < untilTime do
		if bot.target and not extended then
			extended = true
			untilTime += rand(1, 2.5)
		end
		task.wait(0.1)
	end
end

-- A quick step to one side (still facing the same way), if there's room
local function sidestep(bot: Bot)
	if not layout then
		return
	end
	local direction = bot.root.CFrame.RightVector * (if random:NextNumber() < 0.5 then -1 else 1)
	local distance = rand(2.5, 5)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { getFolder() }
	if Workspace:Raycast(bot.root.Position, direction * (distance + 1.5), params) then
		return -- a wall
	end
	local target = bot.root.Position + direction * distance
	if layout.contains(target) then
		bot.holding = true
		bot.humanoid.AutoRotate = false
		walkTo(bot, target, 1.5)
	end
end

-- Tucked in behind the cover, then out to one side to look (and shoot), then back in
local function peekFromCover(bot: Bot, point: Point)
	local peeks = point.peeks :: { Vector3 }
	for _ = 1, random:NextInteger(1, 3) do
		face(bot, bot.root.Position - Vector3.zAxis) -- (towards the way in)
		hold(bot, rand(0.8, 1.6))
		if not alive(bot) then
			return
		end
		bot.humanoid.AutoRotate = false
		walkTo(bot, peeks[random:NextInteger(1, #peeks)], 2)
		hold(bot, rand(1.2, 2.4))
		if not alive(bot) then
			return
		end
		bot.humanoid.AutoRotate = false
		walkTo(bot, point.at, 2)
	end
end

local function patrol(bot: Bot)
	local current: Point? = nil
	while alive(bot) do
		-- Somewhere else in its area
		local nextPoint = bot.area.points[random:NextInteger(1, #bot.area.points)]
		if nextPoint == current then
			continue
		end
		travel(bot, nextPoint.at)
		if not alive(bot) then
			break
		end
		current = nextPoint
		if nextPoint.peeks then
			peekFromCover(bot, nextPoint)
		else
			hold(bot, rand(0.6, 1.6))
			sidestep(bot)
			hold(bot, rand(0.8, 2.2))
		end
	end
end

-- Whoever's nearest and in plain view (head or body)
local function findTarget(bot: Bot): Player?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { bot.model }
	local best, bestDistance = nil, SIGHT_RANGE
	for _, player in targets() do
		local character = player.Character :: Model
		for _, partName in { "Head", "HumanoidRootPart" } do
			local part = character:FindFirstChild(partName) :: BasePart?
			if not part then
				continue
			end
			local offset = part.Position - bot.head.Position
			if offset.Magnitude >= bestDistance then
				continue
			end
			local result = Workspace:Raycast(bot.head.Position, offset, params)
			if result and result.Instance:IsDescendantOf(character) then
				best, bestDistance = player, offset.Magnitude
				break
			end
		end
	end
	return best
end

-- Random direction within `degrees` of `direction`
local function wander(direction: Vector3, degrees: number): Vector3
	local spin = random:NextNumber(0, math.pi * 2)
	local tilt = math.rad(degrees) * math.sqrt(random:NextNumber())
	return (CFrame.lookAt(Vector3.zero, direction) * CFrame.Angles(0, 0, spin) * CFrame.Angles(tilt, 0, 0)).LookVector
end

-- The bots' damage. Never kills: a player who'd die is healed and put back at the entrance.
local function hurt(player: Player, damage: number, from: Vector3)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not layout or not character or not humanoid or not root or humanoid.Health <= 0 then
		return
	end
	if humanoid.Health - damage > 0 then
		humanoid.Health -= damage
		local Damaged = layout.remote.Parent and layout.remote.Parent:FindFirstChild("Damaged") :: RemoteEvent?
		if Damaged then
			Damaged:FireClient(player, from) -- (the damage indicator)
		end
		return
	end
	humanoid.Health = humanoid.MaxHealth
	local standHeight = if humanoid.RigType == Enum.HumanoidRigType.R15 then humanoid.HipHeight + root.Size.Y / 2 else 3
	character:PivotTo(layout.entrance * CFrame.new(0, standHeight, 0))
	player:SetAttribute("ServerTeleport", os.clock()) -- (so the anti-cheat doesn't put them back)
	layout.remote:FireClient(player, "Downed")
end

-- Every shot is drawn for everyone in the lobby (tracer, flash, sound), hit or miss
local function showShot(origin: Vector3, endPosition: Vector3, hitPlayer: boolean)
	if not layout then
		return
	end
	for _, player in Players:GetPlayers() do
		if player:GetAttribute("Location") == "Lobby" then
			layout.remote:FireClient(player, "Shot", origin, endPosition, hitPlayer)
		end
	end
end

local function burst(bot: Bot, player: Player)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { bot.model }
	local aimOffset = random:NextUnitVector() * AIM_ERROR * random:NextNumber()
	for _ = 1, BURST_SIZE do
		local character = player.Character
		local targetRoot = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not alive(bot) or not character or not targetRoot or not layout or player:GetAttribute(layout.attribute) ~= true then
			return
		end
		face(bot, targetRoot.Position)
		-- (from the eyes, so a muzzle poking into cover can't shoot through it)
		local origin = bot.head.Position
		local aim = targetRoot.Position + Vector3.new(0, 0.6, 0) + aimOffset
		local direction = wander((aim - origin).Unit, SPREAD)
		local result = Workspace:Raycast(origin, direction * SHOT_RANGE, params)
		local endPosition = if result then result.Position else origin + direction * SHOT_RANGE
		local hitPlayer = result ~= nil and result.Instance:IsDescendantOf(character)
		showShot(bot.muzzle.WorldPosition, endPosition, hitPlayer)
		if hitPlayer then
			hurt(player, DAMAGE, origin)
		end
		task.wait(BURST_GAP)
	end
end

-- Looks for players while standing still: turns to face them, raises the gun, fires bursts
local function fight(bot: Bot)
	while alive(bot) do
		-- Bots never leave the range (knocked out of it somehow: back home)
		if layout and not layout.contains(bot.root.Position) then
			bot.model:PivotTo(CFrame.new(bot.home + Vector3.new(0, 3, 0)))
		end
		local target = if bot.holding then findTarget(bot) else nil
		bot.target = target
		local targetRoot = target and target.Character and target.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if target and targetRoot then
			local now = os.clock()
			bot.seenAt = bot.seenAt or now
			face(bot, targetRoot.Position)
			raiseArm(bot, true)
			if now - (bot.seenAt :: number) >= REACTION_TIME and now >= bot.nextBurst then
				burst(bot, target)
				bot.nextBurst = os.clock() + rand(BURST_PAUSE_MIN, BURST_PAUSE_MAX)
			end
		else
			bot.seenAt = nil
			if bot.holding then
				raiseArm(bot, false)
			end
		end
		task.wait(0.15)
	end
end

local spawnBot: (area: Area) -> ()

local function makeBot(area: Area): Bot?
	local description = Instance.new("HumanoidDescription")
	description.HeadColor = SKIN
	description.TorsoColor = VEST
	description.LeftArmColor = CLOTHES
	description.RightArmColor = CLOTHES
	description.LeftLegColor = CLOTHES
	description.RightLegColor = CLOTHES
	local ok, model = pcall(Players.CreateHumanoidModelFromDescription, Players, description, Enum.HumanoidRigType.R6)
	if not ok or not model then
		warn("[PracticeBots] couldn't make a bot:", model)
		return nil
	end
	model.Name = "Practice Bot"
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	local head = model:FindFirstChild("Head") :: BasePart
	local arm = model:FindFirstChild("Right Arm") :: BasePart?
	local torso = model:FindFirstChild("Torso")
	if not humanoid or not root or not head or not arm then
		model:Destroy()
		return nil
	end
	humanoid.MaxHealth = BOT_HEALTH
	humanoid.Health = BOT_HEALTH
	humanoid.WalkSpeed = WALK_SPEED
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
	humanoid.NameDisplayDistance = 0
	humanoid.HealthDisplayDistance = 80
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOn

	-- A plain black gun in the right hand, pointing down the arm (ahead once the arm's raised)
	local gun = Instance.new("Part")
	gun.Name = "Gun"
	gun.Size = Vector3.new(0.35, 0.55, 2.2)
	gun.Color = GUN
	gun.Material = Enum.Material.Metal
	gun.CanCollide = false
	gun.CanQuery = false
	gun.CanTouch = false
	gun.Massless = true
	gun.Parent = model
	local grip = Instance.new("Weld")
	grip.Part0 = arm
	grip.Part1 = gun
	grip.C0 = CFrame.new(0, -1, 0) * CFrame.Angles(-math.pi / 2, 0, 0) * CFrame.new(0, 0.25, -0.7)
	grip.Parent = gun
	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.Position = Vector3.new(0, 0.1, -1.1)
	muzzle.Parent = gun

	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.CollisionGroup = PracticeBots.Group
		end
	end

	local point = spawnPoint(area)
	local shoulder = torso and torso:FindFirstChild("Right Shoulder") :: Motor6D?
	local bot: Bot = {
		model = model,
		humanoid = humanoid,
		root = root,
		head = head,
		muzzle = muzzle,
		shoulder = shoulder,
		shoulderC0 = if shoulder then shoulder.C0 else CFrame.identity,
		area = area,
		home = point.at,
		path = PathfindingService:CreatePath({ AgentRadius = 1.5, AgentHeight = 5, AgentCanJump = false }),
		generation = generation,
		holding = false,
		target = nil,
		seenAt = nil,
		nextBurst = 0,
	}
	-- Standing on its spot facing the way in (-Z)
	model:PivotTo(CFrame.lookAt(point.at + Vector3.new(0, 3, 0), point.at + Vector3.new(0, 3, -1)))
	model.Parent = getFolder()
	root:SetNetworkOwner(nil) -- (the server moves it; a nearby player's client would make it stutter)

	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = humanoid
	local function track(id: string): AnimationTrack?
		local animation = Instance.new("Animation")
		animation.AnimationId = id
		local loaded, result = pcall(animator.LoadAnimation, animator, animation)
		if loaded then
			result.Looped = true
			return result
		end
		return nil
	end
	local idle, walk = track(IDLE_ANIMATION), track(WALK_ANIMATION)
	if idle then
		idle:Play()
	end
	humanoid.Running:Connect(function(speed: number)
		if not walk then
			return
		end
		if speed > 0.75 and not walk.IsPlaying then
			walk:Play(0.2)
		elseif speed <= 0.75 and walk.IsPlaying then
			walk:Stop(0.2)
		end
	end)

	humanoid.Died:Connect(function()
		task.delay(RESPAWN_DELAY, function()
			model:Destroy()
			if active and bot.generation == generation then
				spawnBot(area)
			end
		end)
	end)
	return bot
end

spawnBot = function(area: Area)
	task.spawn(function()
		local spawnedIn = generation
		local bot = makeBot(area)
		if not bot then
			return
		end
		if spawnedIn ~= generation or not active then
			bot.model:Destroy() -- (cleared while it was being made)
			return
		end
		task.spawn(patrol, bot)
		task.spawn(fight, bot)
	end)
end

-- Bots run only while someone's in the range (PracticeRange). Off clears them all away.
function PracticeBots.SetActive(on: boolean)
	if on == active or not layout then
		return
	end
	active = on
	if on then
		for _, area in layout.areas do
			for _ = 1, area.count do
				spawnBot(area)
			end
		end
	else
		generation += 1
		getFolder():ClearAllChildren()
	end
end

function PracticeBots.Start(rangeLayout: Layout)
	layout = rangeLayout
end

return PracticeBots
