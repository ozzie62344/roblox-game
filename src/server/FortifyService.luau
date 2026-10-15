-- Siege defender fortifications, both on G (the same key as plant / disable):
--   Barricade  look at an empty doorway / window, hold G. Wooden boards (a doorway's leave a gap
--              at the bottom that drones fit under, like Siege) that are Breakable
--              (DestructionService): bullets chip them, 3 knife hits or ~20 bullets smash them.
--              Where they can go: invisible parts in <Map>/BarricadeSlots (Kind = "Door" /
--              "Window"). Slots with Exterior = true start every round already barricaded.
--              Defenders can take one down again (look at it, hold G: "Unbarricade") without
--              shooting it apart.
--   Reinforce  look at a soft wall, hold G. A steel plate goes up on your side of that wall
--              section and stops bullets, knives and people (only hard breachers will get
--              through, later). The defending team shares 2 per defender per round
--              (MatchConfig.Reinforcements; RoundService fills the pool).
--              Sections are cut when the map loads: every full-height soft wall is split into
--              ~10-stud pieces (<Map>/ReinforceSlots), like Siege's fixed wall sections. Hatches
--              (trapdoors) are sections too: their plate goes on top.
-- Defenders can fortify during a match (prep + action); anyone can while free roaming, for free.
-- While working, the player is locked in place through the same Interaction / InteractEndsAt
-- attributes as planting (progress bar + pose), and the slot gets Build* attributes so every
-- client can animate the plate / boards going up (FortifyEffects). Everything resets when the
-- map reloads.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local MatchConfig = require(ReplicatedStorage.Shared.MatchConfig)

local Interact = ReplicatedStorage.Remotes.Interact :: RemoteEvent
local DestructionEvent = ReplicatedStorage.Remotes.Destruction :: RemoteEvent
local MatchState = ReplicatedStorage.MatchState

local FortifyService = {}

local REACH = 8 -- studs from the head to the doorway / wall (a bit more than the client's 7)
local BUILD_PHASES = { Prep = true, Action = true, Planted = true }
local SECTION_LENGTH = 10 -- studs, roughly; each wall is split into equal sections (wide, like Siege's:
-- with only 6 reinforcements a team, each one has to cover a lot of wall)
local DRONE_GAP = 0.9 -- studs left open under a barricaded door (DroneService drones are 0.7 tall)
local WOOD = Color3.fromRGB(176, 136, 92)
local STEEL = Color3.fromRGB(92, 97, 104)

type Kind = "Barricade" | "Reinforce" | "Unbarricade"
local KINDS = {
	Barricade = { folder = "BarricadeSlots", time = MatchConfig.BarricadeTime },
	Reinforce = { folder = "ReinforceSlots", time = MatchConfig.ReinforceTime },
	Unbarricade = { folder = "BarricadeSlots", time = MatchConfig.UnbarricadeTime },
}

local working: { [Player]: { kind: Kind, slot: BasePart, endsAt: number, side: number } } = {}
local reinforcements: { [BasePart]: Model } = setmetatable({}, { __mode = "k" }) :: any -- section → its steel
local barricades: { [BasePart]: Model } = setmetatable({}, { __mode = "k" }) :: any -- doorway → its boards

local function part(name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- Defenders during a match; anyone while free roaming (so it can be tried out alone)
local function mayFortify(player: Player): boolean
	if player.Neutral then
		return true
	end
	local phase = MatchState:GetAttribute("Phase")
	local attackTeam = MatchState:GetAttribute("AttackTeam")
	return BUILD_PHASES[phase] == true and player.Team ~= nil and player.Team.Name ~= attackTeam
end

local function canWork(player: Player, kind: Kind, slot: BasePart): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local head = character and character:FindFirstChild("Head") :: BasePart?
	local map = Workspace:FindFirstChild("Map")
	if not humanoid or humanoid.Health <= 0 or not root or not head or root.Anchored or not map then
		return false
	end
	if not slot:IsDescendantOf(map) or slot.Parent.Name ~= KINDS[kind].folder then
		return false
	end
	-- Building needs an empty doorway / section; taking down needs boards there
	if kind == "Unbarricade" then
		if not barricades[slot] then
			return false
		end
	elseif slot:GetAttribute("Built") then
		return false
	end
	if slot:GetAttribute("Breached") then
		return false -- a burned-through section can't be reinforced again (Siege)
	end
	if not mayFortify(player) then
		return false
	end
	if kind == "Reinforce" and not player.Neutral and (MatchState:GetAttribute("Reinforcements") or 0) <= 0 then
		return false
	end
	-- Closest point of the doorway / wall section to the head
	local localHead = slot.CFrame:PointToObjectSpace(head.Position)
	local half = slot.Size / 2
	local closest = Vector3.new(
		math.clamp(localHead.X, -half.X, half.X),
		math.clamp(localHead.Y, -half.Y, half.Y),
		math.clamp(localHead.Z, -half.Z, half.Z)
	)
	return (localHead - closest).Magnitude <= REACH
end

local function stop(player: Player)
	local info = working[player]
	if info then
		working[player] = nil
		info.slot:SetAttribute("BuildEndsAt", nil) -- ends the going-up animation (FortifyEffects)
		player:SetAttribute("Interaction", nil)
		player:SetAttribute("InteractEndsAt", nil)
	end
end

-- Where the boards go: the whole window, or a doorway minus a gap at the bottom that drones fit
-- under and people don't (Siege)
local function boardsFrame(slot: BasePart): (CFrame, Vector3)
	if slot:GetAttribute("Kind") ~= "Door" then
		return slot.CFrame, slot.Size
	end
	return slot.CFrame * CFrame.new(0, DRONE_GAP / 2, 0), slot.Size - Vector3.new(0, DRONE_GAP, 0)
end

local function buildBarricade(slot: BasePart)
	local barricade = Instance.new("Model")
	barricade.Name = "Barricade"
	local cframe, size = boardsFrame(slot)
	local boards = part("Boards", size, cframe, WOOD, Enum.Material.WoodPlanks, barricade)
	boards:SetAttribute("Breakable", "Barricade")
	barricade.Parent = slot.Parent
	slot:SetAttribute("Built", true)
	barricades[slot] = barricade
	-- Smashed or taken down? The doorway can be boarded up again
	barricade.Destroying:Connect(function()
		slot:SetAttribute("Built", nil)
		if barricades[slot] == barricade then
			barricades[slot] = nil
		end
	end)
end

-- Which side of a wall section a position is on (+1 / -1, across the wall)
local function sideOf(slot: BasePart, position: Vector3): number
	local across = if slot.Size.X > slot.Size.Z then Vector3.zAxis else Vector3.xAxis
	return if (position - slot.Position):Dot(across) >= 0 then 1 else -1
end

-- Where the steel plate goes: flat against the wall section, on the defender's side (on top of a
-- hatch, lapping over its edges)
local function plateFrame(slot: BasePart, side: number): (CFrame, Vector3)
	if slot:GetAttribute("Hatch") then
		local top = slot.Position.Y + slot.Size.Y / 2 - 0.5 -- the floor's surface (MapBuilder.Hatch)
		return CFrame.new(slot.Position.X, top + 0.15, slot.Position.Z), Vector3.new(slot.Size.X + 0.6, 0.3, slot.Size.Z + 0.6)
	end
	local alongX = slot.Size.X > slot.Size.Z
	local across = if alongX then Vector3.zAxis else Vector3.xAxis
	local wallHalf = (if alongX then slot.Size.Z else slot.Size.X) / 2 - 0.1 -- the slot is 0.2 thicker than the wall
	local length = (if alongX then slot.Size.X else slot.Size.Z) - 0.05
	local height = slot.Size.Y - 0.05
	local size = if alongX then Vector3.new(length, height, 0.3) else Vector3.new(0.3, height, length)
	return CFrame.new(slot.Position + across * side * (wallHalf + 0.15)), size
end

local function buildReinforcement(slot: BasePart, side: number)
	local hatch = slot:GetAttribute("Hatch") == true
	local alongX = hatch or slot.Size.X > slot.Size.Z
	local across = if hatch then Vector3.yAxis elseif alongX then Vector3.zAxis else Vector3.xAxis
	local plateCFrame, size = plateFrame(slot, if hatch then 1 else side)
	local center = plateCFrame.Position
	local length = if alongX then size.X else size.Z
	local spread = if hatch then size.Z else size.Y
	local model = Instance.new("Model")
	model.Name = "Reinforcement"
	part("Plate", size, plateCFrame, STEEL, Enum.Material.DiamondPlate, model)
	-- Braces, the way Siege reinforcements look (across the top of a hatch)
	for _, offset in { -spread * 0.3, 0, spread * 0.3 } do
		local braceSize = if hatch then Vector3.new(length, 0.15, 0.35) elseif alongX then Vector3.new(length, 0.35, 0.15) else Vector3.new(0.15, 0.35, length)
		local shift = if hatch then Vector3.new(0, 0, offset) else Vector3.new(0, offset, 0)
		local brace = part("Brace", braceSize, CFrame.new(center + across * (if hatch then 0.2 else side * 0.2) + shift), STEEL:Lerp(Color3.new(0, 0, 0), 0.25), Enum.Material.Metal, model)
		brace.CanCollide = false
		brace.CanQuery = false
	end
	model.Parent = slot.Parent
	slot:SetAttribute("Built", true)
	reinforcements[slot] = model
end

local function finish(player: Player, kind: Kind, slot: BasePart, side: number)
	if kind == "Barricade" then
		buildBarricade(slot)
		return
	elseif kind == "Unbarricade" then
		-- Pulled down: the boards break apart (same effect as smashing them)
		local barricade = barricades[slot]
		local boards = barricade and barricade:FindFirstChildWhichIsA("BasePart")
		if boards then
			DestructionEvent:FireAllClients("Smash", boards.Position, 2, boards.Color, boards.Material)
		end
		if barricade then
			barricade:Destroy()
		end
		return
	end
	buildReinforcement(slot, side)
	if not player.Neutral then
		MatchState:SetAttribute("Reinforcements", (MatchState:GetAttribute("Reinforcements") or 1) - 1)
	end
end

local function update()
	local now = Workspace:GetServerTimeNow()
	for player, info in working do
		if not canWork(player, info.kind, info.slot) then
			stop(player)
		elseif now >= info.endsAt then
			stop(player)
			finish(player, info.kind, info.slot, info.side)
		end
	end
end

-- The wall section (reinforce slot) at a point on or against a wall, if any (GadgetService)
function FortifyService.SectionAt(point: Vector3): BasePart?
	local map = Workspace:FindFirstChild("Map")
	local slots = map and map:FindFirstChild("ReinforceSlots")
	for _, slot in if slots then slots:GetChildren() else {} do
		if slot:IsA("BasePart") and slot.Name == "Slot" then
			local localPoint = slot.CFrame:PointToObjectSpace(point)
			local half = slot.Size / 2 + Vector3.one * 0.5 -- reaches the face of the steel plate too
			if math.abs(localPoint.X) <= half.X and math.abs(localPoint.Y) <= half.Y and math.abs(localPoint.Z) <= half.Z then
				return slot
			end
		end
	end
	return nil
end

-- A hard breach burned through: the steel is gone for good this round
function FortifyService.RemoveReinforcement(slot: BasePart)
	local model = reinforcements[slot]
	if model then
		model:Destroy()
		reinforcements[slot] = nil
	end
	slot:SetAttribute("Built", nil)
	slot:SetAttribute("Breached", true)
end

-- Called by MapService after a map is (re)loaded: cut the walls into reinforcement sections and
-- board up the outside doors / windows
function FortifyService.Prepare(map: Model)
	local barricadeSlots = map:FindFirstChild("BarricadeSlots")
	if barricadeSlots then
		for _, slot in barricadeSlots:GetChildren() do
			if slot:IsA("BasePart") and slot:GetAttribute("Exterior") then
				buildBarricade(slot)
			end
		end
	end

	-- Hatch slots come with the map (MapBuilder.Hatch); a hatch that's been broken open can't be
	-- reinforced any more (Siege)
	local sections = map:FindFirstChild("ReinforceSlots") or Instance.new("Folder")
	sections.Name = "ReinforceSlots"
	local hatches = map:FindFirstChild("Hatches")
	for _, slot in sections:GetChildren() do
		for _, cover in if hatches then hatches:GetChildren() else {} do
			local boards = cover:FindFirstChildWhichIsA("BasePart")
			if slot:GetAttribute("Hatch") and boards and (Vector3.new(boards.Position.X - slot.Position.X, 0, boards.Position.Z - slot.Position.Z)).Magnitude < 0.5 then
				cover.Destroying:Connect(function()
					if not slot:GetAttribute("Built") then
						slot:SetAttribute("Breached", true)
					end
				end)
			end
		end
	end
	for _, wall in map:GetDescendants() do
		-- Full-height soft walls only (not the strips over doorways), like Siege
		if wall:IsA("BasePart") and wall:GetAttribute("Breakable") == "Soft" and wall.Size.Y >= 8 then
			local alongX = wall.Size.X > wall.Size.Z
			local length = if alongX then wall.Size.X else wall.Size.Z
			local count = math.max(1, math.round(length / SECTION_LENGTH))
			for i = 1, count do
				local offset = -length / 2 + length * (i - 0.5) / count
				local size = if alongX
					then Vector3.new(length / count, wall.Size.Y, wall.Size.Z + 0.2)
					else Vector3.new(wall.Size.X + 0.2, wall.Size.Y, length / count)
				local slot = part("Slot", size, wall.CFrame * CFrame.new(if alongX then offset else 0, 0, if alongX then 0 else offset), STEEL, Enum.Material.SmoothPlastic, sections)
				slot.Transparency = 1
				slot.CanCollide = false
				slot.CanQuery = false
				slot.CanTouch = false
			end
		end
	end
	sections.Parent = map
end

function FortifyService.Start()
	Interact.OnServerEvent:Connect(function(player, action, kind, slot)
		if action == "End" then
			stop(player)
			return
		end
		if action ~= "Begin" or not KINDS[kind] or working[player] or player:GetAttribute("Interaction") then
			return
		end
		if typeof(slot) ~= "Instance" or not slot:IsA("BasePart") or not canWork(player, kind, slot) then
			return
		end
		if slot:GetAttribute("BuildEndsAt") then
			return -- someone else is already on it
		end
		local head = (player.Character :: Model):FindFirstChild("Head") :: BasePart
		local side = sideOf(slot, head.Position)
		local time = KINDS[kind].time
		local endsAt = Workspace:GetServerTimeNow() + time
		working[player] = { kind = kind, slot = slot, endsAt = endsAt, side = side }
		player:SetAttribute("Interaction", kind)
		player:SetAttribute("InteractEndsAt", endsAt)
		-- Everyone sees it going up (FortifyEffects): what, where, and when it's done
		local cframe, size = boardsFrame(slot)
		if kind == "Reinforce" then
			cframe, size = plateFrame(slot, side)
		end
		slot:SetAttribute("BuildKind", kind)
		slot:SetAttribute("BuildCFrame", cframe)
		slot:SetAttribute("BuildSize", size)
		slot:SetAttribute("BuildTime", time)
		slot:SetAttribute("BuildEndsAt", endsAt)
	end)
	Players.PlayerRemoving:Connect(function(player)
		working[player] = nil
	end)
	RunService.Heartbeat:Connect(update)
end

return FortifyService
