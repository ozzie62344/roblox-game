-- Siege gadgets in the ability pool (used with X; see Abilities.luau, wired up by AbilityService):
--   Attack  Breach Charge  stick it on a soft wall / floor, a hatch, barricade or armor panel, X
--                          again to blow a walk-through (or drop-through) hole (won't go off
--                          while an enemy Signal Jammer is near)
--           Hard Breach    thermite: burns 3 s, then opens a reinforced wall section or hatch (an
--                          electrified section fries it)
--           EMP Grenade    thrown; destroys enemy electronics in its radius, through walls
--   Defend  Shock Wire     battery on a reinforced section: charges put on it get fried
--           Signal Jammer  breach charges within its radius can't be set off
--           Armor Panel    bulletproof barricade on a doorway / window (10 knife hits or an explosive)
-- Devices live in Workspace.Deployables (cleared every round); armor panels live in the map, which
-- reloads every round. A device's body is Breakable = "Gadget", so a bullet or knife destroys it.
-- Electronics carry an "Electronic" attribute (what the EMP kills); "OwnerTeam" tells friend from
-- foe (while free roaming everything counts as enemy, so it can all be tried alone).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Abilities = require(ReplicatedStorage.Shared.Abilities)
local Sounds = require(ReplicatedStorage.Shared.Sounds)
local DestructionService = require(script.Parent.DestructionService)
local FortifyService = require(script.Parent.FortifyService)
local WeaponService = require(script.Parent.WeaponService)

local AbilityEffect = ReplicatedStorage.Remotes.AbilityEffect :: RemoteEvent
local DestructionEvent = ReplicatedStorage.Remotes.Destruction :: RemoteEvent

local GadgetService = {}

local REACH = 6 -- studs from the eyes to the wall / doorway you're placing on
local BREACH_WIDTH, BREACH_HEIGHT = 4.5, 7 -- walk-through hole, from the floor up
local BREACH_DAMAGE = 100
local THERMITE_DAMAGE = 60
local FRY_TIME = 1 -- a charge on an electrified wall lasts this long
local EMP_SPEED, EMP_LIFT, GRAVITY = 70, 14, 90
local DARK = Color3.fromRGB(40, 42, 46)
local EMP_BLUE = Color3.fromRGB(90, 170, 255)

type Charge = { model: Model, point: Vector3, normal: Vector3 }
local breachCharges: { [Player]: { Charge } } = setmetatable({}, { __mode = "k" }) :: any

-- ─── Helpers ───────────────────────────────────────────────────────────────────

local function deployables(): Folder
	local folder = Workspace:FindFirstChild("Deployables")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Deployables"
		folder.Parent = Workspace
	end
	return folder :: Folder
end

local function teamName(player: Player): string
	return if player.Neutral or not player.Team then "" else player.Team.Name
end

local function isEnemyDevice(device: Instance, player: Player): boolean
	local owner = device:GetAttribute("OwnerTeam")
	return owner == "" or owner ~= teamName(player)
end

local function status(player: Player, text: string)
	AbilityEffect:FireClient(player, "Status", text)
end

-- Hands / body animation that everyone sees (HandsAnimator in first person, BodyAnimator in
-- third): what was done, where (a frame on the surface, look vector out of it), and when
function GadgetService.Gesture(character: Model, name: string, target: CFrame?)
	character:SetAttribute("GestureTarget", target)
	character:SetAttribute("Gesture", name)
	character:SetAttribute("GestureAt", Workspace:GetServerTimeNow()) -- set last: clients watch this
end

-- Decorative part: no collisions, invisible to bullets and raycasts
local function part(name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, parent: Instance?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- A device: a model whose body can be shot / knifed to destroy it
local function device(name: string, player: Player, body: Part, electronic: boolean): Model
	local model = Instance.new("Model")
	model.Name = name
	model:SetAttribute("OwnerTeam", teamName(player))
	model:SetAttribute("Owner", player.UserId)
	if electronic then
		model:SetAttribute("Electronic", true)
	end
	body.CanQuery = true
	body:SetAttribute("Breakable", "Gadget")
	body.Parent = model
	model.PrimaryPart = body
	return model
end

-- Zapped by electricity / an EMP: sparks, a crackle, gone
local function fry(model: Model)
	local body = model.PrimaryPart
	if body then
		DestructionEvent:FireAllClients("Spark", body.Position, 1, EMP_BLUE, Enum.Material.Neon)
	end
	model:Destroy()
end

local function explosion(position: Vector3)
	local blast = Instance.new("Explosion")
	blast.Position = position
	blast.BlastRadius = 4
	blast.BlastPressure = 0 -- visual only; damage and destruction are ours
	blast.DestroyJointRadiusPercent = 0
	blast.Parent = Workspace
end

local function ignoreList(character: Model): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, deployables() }
	return params
end

-- What you're aiming at, within reach
local function aim(character: Model, look: Vector3): RaycastResult?
	local head = character:FindFirstChild("Head") :: BasePart?
	if not head or look.Magnitude < 0.5 then
		return nil
	end
	return Workspace:Raycast(head.Position, look.Unit * REACH, ignoreList(character))
end

-- A frame stuck flat on the wall (or, if allowed, the floor) that was hit: its look vector points
-- out of the surface. Ceilings and slopes don't take gadgets.
local function onSurface(hit: RaycastResult, allowFloor: boolean): CFrame?
	if hit.Normal.Y > 0.7 and allowFloor then
		local position = hit.Position + Vector3.yAxis * 0.05
		return CFrame.lookAt(position, position + Vector3.yAxis, Vector3.zAxis)
	end
	if math.abs(hit.Normal.Y) > 0.3 then
		return nil
	end
	local normal = Vector3.new(hit.Normal.X, 0, hit.Normal.Z).Unit
	local position = hit.Position + normal * 0.05
	return CFrame.lookAt(position, position + normal)
end

local function isFloorCharge(normal: Vector3): boolean
	return normal.Y > 0.7
end

-- Floor height under a spot on a wall
local function floorAt(character: Model, point: Vector3, normal: Vector3): number
	local section = FortifyService.SectionAt(point)
	if section then
		return section.Position.Y - section.Size.Y / 2
	end
	local ground = Workspace:Raycast(point + normal * 0.6, Vector3.new(0, -14, 0), ignoreList(character))
	return if ground then ground.Position.Y else point.Y - 4
end

-- ─── Attack ────────────────────────────────────────────────────────────────────

local function jammed(position: Vector3, player: Player): boolean
	local radius = Abilities.SignalJammer.Radius or 10
	for _, other in deployables():GetChildren() do
		local body = other:IsA("Model") and other.PrimaryPart
		if body and other:GetAttribute("Jammer") and isEnemyDevice(other, player) and (body.Position - position).Magnitude <= radius then
			return true
		end
	end
	return false
end

local function detonate(player: Player, character: Model)
	GadgetService.Gesture(character, "Detonate")
	local kept: { Charge } = {}
	for _, charge in breachCharges[player] or {} do
		if not charge.model.Parent then
			continue -- shot off the wall
		end
		if jammed(charge.point, player) then
			table.insert(kept, charge)
			status(player, "JAMMED: A SIGNAL JAMMER IS NEARBY")
			continue
		end
		charge.model:Destroy()
		explosion(charge.point)
		if isFloorCharge(charge.normal) then
			DestructionService.Breach(charge.point, charge.normal, BREACH_WIDTH, BREACH_WIDTH)
		else
			local floorY = floorAt(character, charge.point, charge.normal)
			local center = Vector3.new(charge.point.X, floorY + BREACH_HEIGHT / 2, charge.point.Z)
			DestructionService.Breach(center, charge.normal, BREACH_WIDTH, BREACH_HEIGHT)
		end
		WeaponService.Blast(player, charge.point, Abilities.BreachCharge.Radius or 10, BREACH_DAMAGE, charge.normal)
	end
	breachCharges[player] = if #kept > 0 then kept else nil
end

local function buildBreachCharge(player: Player, cf: CFrame): Model
	local body = part("Detonator", Vector3.new(0.8, 0.55, 0.35), cf * CFrame.new(0, 0, -0.18), DARK, Enum.Material.Metal)
	local model = device("BreachCharge", player, body, false)
	-- Rope frame of explosive around the detonator
	local rope = Color3.fromRGB(78, 82, 62)
	for _, strip in { { 0, 2.4, 3, 0.25 }, { 0, -2.4, 3, 0.25 }, { -1.5, 0, 0.25, 5 }, { 1.5, 0, 0.25, 5 } } do
		part("Rope", Vector3.new(strip[3], strip[4], 0.15), cf * CFrame.new(strip[1], strip[2], -0.08), rope, Enum.Material.Fabric, model)
	end
	part("Light", Vector3.new(0.15, 0.15, 0.08), cf * CFrame.new(0.25, 0.12, -0.38), Color3.fromRGB(255, 40, 40), Enum.Material.Neon, model)
	model.Parent = deployables()
	return model
end

local function breachCharge(player: Player, character: Model, _root: BasePart, _ability: Abilities.Ability, look: Vector3): boolean
	-- Already stuck on a wall? X sets it off (free)
	local mine = breachCharges[player]
	if mine then
		for i = #mine, 1, -1 do
			if not mine[i].model.Parent then
				table.remove(mine, i)
			end
		end
		if #mine > 0 then
			detonate(player, character)
			return false
		end
	end
	if (player:GetAttribute("AbilityCharges") or 0) <= 0 then
		status(player, "NO CHARGES LEFT")
		return false
	end
	local hit = aim(character, look)
	local section = hit and FortifyService.SectionAt(hit.Position)
	if section and section:GetAttribute("Built") then
		status(player, "REINFORCED: NEEDS A HARD BREACH")
		return false
	end
	local kind = hit and hit.Instance:GetAttribute("Breakable")
	local cf = hit and onSurface(hit, true)
	if not hit or not cf or not (kind == "Soft" or kind == "Barricade" or kind == "Panel" or kind == "Hatch") then
		status(player, "AIM AT A SOFT WALL OR FLOOR, A HATCH, BARRICADE OR ARMOR PANEL")
		return false
	end
	breachCharges[player] = { { model = buildBreachCharge(player, cf), point = hit.Position, normal = cf.LookVector } }
	GadgetService.Gesture(character, "BreachCharge", cf)
	status(player, "CHARGE SET: PRESS X TO BLOW IT")
	return true
end

local function hardBreach(player: Player, character: Model, _root: BasePart, ability: Abilities.Ability, look: Vector3): boolean
	local hit = aim(character, look)
	local cf = hit and onSurface(hit, true)
	local section = hit and FortifyService.SectionAt(hit.Position)
	if not hit or not cf or not section or section:GetAttribute("Breached") then
		status(player, "AIM AT A WALL OR HATCH YOU CAN BREACH")
		return false
	end
	local body = part("Thermite", Vector3.new(2.6, 3.6, 0.4), cf * CFrame.new(0, 0, -0.2), Color3.fromRGB(170, 72, 40), Enum.Material.Metal)
	local model = device("HardBreach", player, body, false)
	for _, y in { 1.1, -1.1 } do
		part("Strap", Vector3.new(2.7, 0.3, 0.45), cf * CFrame.new(0, y, -0.2), DARK, Enum.Material.Fabric, model)
	end
	-- Burning: a shower of sparks, an orange glow, the hiss of the cutting
	local sparks = Instance.new("ParticleEmitter")
	sparks.Color = ColorSequence.new(Color3.fromRGB(255, 210, 110), Color3.fromRGB(255, 90, 30))
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new(0.18, 0)
	sparks.Lifetime = NumberRange.new(0.3, 0.8)
	sparks.Speed = NumberRange.new(6, 14)
	sparks.SpreadAngle = Vector2.new(70, 70)
	sparks.Acceleration = Vector3.new(0, -40, 0)
	sparks.Rate = 140
	sparks.EmissionDirection = Enum.NormalId.Front -- out of the wall
	sparks.Parent = body
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(255, 150, 60)
	glow.Range = 14
	glow.Brightness = 3
	glow.Parent = body
	local burn = Instance.new("Sound")
	burn.SoundId = Sounds.ThermiteBurn.Id
	burn.Volume = Sounds.ThermiteBurn.Volume
	burn.RollOffMaxDistance = Sounds.ThermiteBurn.Range
	burn.Looped = true
	burn.Parent = body
	model.Parent = deployables()
	burn:Play()
	GadgetService.Gesture(character, "HardBreach", cf)

	local normal = cf.LookVector
	local burnTime = ability.Duration or 3
	task.spawn(function()
		local started = os.clock()
		local electrifiedSince: number? = nil
		while model.Parent and os.clock() - started < burnTime do
			if section:GetAttribute("Electrified") then
				electrifiedSince = electrifiedSince or os.clock()
				if os.clock() - (electrifiedSince :: number) >= FRY_TIME then
					fry(model)
					status(player, "HARD BREACH FRIED BY A SHOCK WIRE")
					return
				end
			end
			task.wait(0.1)
		end
		if not model.Parent then
			return -- shot off the wall
		end
		model:Destroy()
		FortifyService.RemoveReinforcement(section)
		explosion(hit.Position)
		if isFloorCharge(normal) then
			DestructionService.Breach(hit.Position, normal, BREACH_WIDTH + 0.5, BREACH_WIDTH + 0.5)
		else
			local floorY = section.Position.Y - section.Size.Y / 2
			local center = Vector3.new(hit.Position.X, floorY + BREACH_HEIGHT / 2, hit.Position.Z)
			DestructionService.Breach(center, normal, BREACH_WIDTH + 0.5, BREACH_HEIGHT)
		end
		WeaponService.Blast(player, hit.Position, 6, THERMITE_DAMAGE, normal)
	end)
	return true
end

local function emp(player: Player, position: Vector3, radius: number)
	local fried = 0
	for _, other in deployables():GetChildren() do
		local body = other:IsA("Model") and other.PrimaryPart
		if body and other:GetAttribute("Electronic") and isEnemyDevice(other, player) and (body.Position - position).Magnitude <= radius then
			fry(other :: Model)
			fried += 1
		end
	end
	AbilityEffect:FireAllClients("Pulse", position, radius, EMP_BLUE)
	DestructionEvent:FireAllClients("Spark", position, 2, EMP_BLUE, Enum.Material.Neon)
	status(player, if fried > 0 then `EMP FRIED {fried} DEVICE{if fried == 1 then "" else "S"}` else "EMP: NOTHING IN RANGE")
end

local function empGrenade(player: Player, character: Model, _root: BasePart, ability: Abilities.Ability, look: Vector3): boolean
	local head = character:FindFirstChild("Head") :: BasePart?
	if not head or look.Magnitude < 0.5 then
		return false
	end
	local params = ignoreList(character)
	local position = head.Position + look.Unit * 1.5
	local velocity = look.Unit * EMP_SPEED + Vector3.new(0, EMP_LIFT, 0)
	GadgetService.Gesture(character, "EmpGrenade")
	local grenade = part("EmpGrenade", Vector3.new(0.45, 0.7, 0.45), CFrame.new(position), Color3.fromRGB(60, 110, 180), Enum.Material.Metal, deployables())
	part("Band", Vector3.new(0.5, 0.12, 0.5), CFrame.new(position), EMP_BLUE, Enum.Material.Neon, grenade)
	task.spawn(function()
		local thrownAt = os.clock()
		while grenade.Parent and os.clock() - thrownAt < 3 do
			local dt = RunService.Heartbeat:Wait()
			velocity += Vector3.new(0, -GRAVITY * dt, 0)
			local step = velocity * dt
			local hit = Workspace:Raycast(position, step, params)
			if hit then
				position = hit.Position + hit.Normal * 0.3
				break
			end
			position += step
			grenade.CFrame = CFrame.new(position)
		end
		grenade:Destroy()
		emp(player, position, ability.Radius or 14)
	end)
	return true
end

-- ─── Defend ────────────────────────────────────────────────────────────────────

local function shockWire(player: Player, character: Model, _root: BasePart, _ability: Abilities.Ability, look: Vector3): boolean
	local hit = aim(character, look)
	local cf = hit and onSurface(hit, false)
	local section = hit and FortifyService.SectionAt(hit.Position)
	if not hit or not cf or not section or not section:GetAttribute("Built") then
		status(player, "AIM AT A REINFORCED WALL")
		return false
	end
	if section:GetAttribute("Electrified") then
		status(player, "ALREADY ELECTRIFIED")
		return false
	end
	local normal = cf.LookVector
	local floorY = section.Position.Y - section.Size.Y / 2
	local base = Vector3.new(hit.Position.X, floorY + 0.5, hit.Position.Z) + normal * 0.9
	local body = part("Battery", Vector3.new(1.3, 1, 0.8), CFrame.lookAt(base, base + normal), DARK, Enum.Material.Metal)
	local model = device("ShockWire", player, body, true)
	part("Stripe", Vector3.new(1.32, 0.25, 0.82), body.CFrame * CFrame.new(0, 0.2, 0), Color3.fromRGB(230, 190, 40), Enum.Material.SmoothPlastic, model)
	part("Cable", Vector3.new(0.1, 2.2, 0.1), CFrame.new(Vector3.new(hit.Position.X, floorY + 1.6, hit.Position.Z) + normal * 0.45), Color3.fromRGB(20, 20, 20), Enum.Material.Rubber, model)
	-- Sparks crawling over the steel
	local plateFace = Vector3.new(hit.Position.X, section.Position.Y, hit.Position.Z) + normal * 0.05
	local arcs = part("Arcs", Vector3.new(4, section.Size.Y * 0.8, 0.1), CFrame.lookAt(plateFace, plateFace + normal), DARK, Enum.Material.SmoothPlastic, model)
	arcs.Transparency = 1
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(Color3.fromRGB(200, 230, 255), EMP_BLUE)
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new(0.25, 0)
	emitter.Lifetime = NumberRange.new(0.08, 0.22)
	emitter.Speed = NumberRange.new(1, 3)
	emitter.Rate = 30
	emitter.Parent = arcs
	model.Parent = deployables()
	GadgetService.Gesture(character, "ShockWire", body.CFrame)
	section:SetAttribute("Electrified", true)
	model.Destroying:Connect(function()
		section:SetAttribute("Electrified", nil)
	end)
	DestructionEvent:FireAllClients("Spark", hit.Position, 1, EMP_BLUE, Enum.Material.Neon)
	return true
end

local function signalJammer(player: Player, character: Model, root: BasePart, _ability: Abilities.Ability, look: Vector3): boolean
	local forward = Vector3.new(look.X, 0, look.Z)
	forward = if forward.Magnitude > 0.1 then forward.Unit else root.CFrame.LookVector
	local params = ignoreList(character)
	local distance = 2.5
	local blocked = Workspace:Raycast(root.Position, forward * distance, params)
	if blocked then
		distance = math.max(blocked.Distance - 0.8, 0.5)
	end
	local ground = Workspace:Raycast(root.Position + forward * distance, Vector3.new(0, -8, 0), params)
	if not ground then
		status(player, "NO FLOOR HERE")
		return false
	end
	local base = ground.Position + Vector3.new(0, 0.25, 0)
	local body = part("Jammer", Vector3.new(1.2, 0.5, 0.9), CFrame.lookAt(base, base + forward), Color3.fromRGB(50, 66, 52), Enum.Material.Metal)
	local model = device("SignalJammer", player, body, true)
	model:SetAttribute("Jammer", true)
	part("Antenna", Vector3.new(0.08, 1.6, 0.08), body.CFrame * CFrame.new(0.4, 1.05, 0.2), DARK, Enum.Material.Metal, model)
	part("Light", Vector3.new(0.2, 0.08, 0.2), body.CFrame * CFrame.new(-0.3, 0.27, -0.2), Color3.fromRGB(60, 255, 120), Enum.Material.Neon, model)
	model.Parent = deployables()
	GadgetService.Gesture(character, "SignalJammer", CFrame.lookAt(base, base + Vector3.yAxis, forward))
	return true
end

-- The doorway / window you're looking at (the same spots barricades go)
local function doorwayInView(character: Model, look: Vector3): BasePart?
	local head = character:FindFirstChild("Head") :: BasePart?
	local map = Workspace:FindFirstChild("Map")
	local slots = map and map:FindFirstChild("BarricadeSlots")
	if not head or not slots or look.Magnitude < 0.5 then
		return nil
	end
	local best, bestDot = nil, 0.6
	for _, slot in slots:GetChildren() do
		if slot:IsA("BasePart") and slot.Name == "Slot" then
			local offset = slot.Position - head.Position
			local dot = offset.Unit:Dot(look.Unit)
			if offset.Magnitude <= REACH + 2 and dot > bestDot then
				best, bestDot = slot, dot
			end
		end
	end
	return best
end

local function armorPanel(player: Player, character: Model, _root: BasePart, _ability: Abilities.Ability, look: Vector3): boolean
	local slot = doorwayInView(character, look)
	if not slot then
		status(player, "AIM AT A DOORWAY OR WINDOW")
		return false
	end
	if slot:GetAttribute("Panel") then
		status(player, "ALREADY ARMORED")
		return false
	end
	-- It replaces any wooden boards in that doorway
	for _, other in slot.Parent:GetChildren() do
		if other:IsA("Model") and other.Name == "Barricade" and (other:GetBoundingBox().Position - slot.Position).Magnitude < 2 then
			other:Destroy()
		end
	end
	local panel = Instance.new("Model")
	panel.Name = "ArmorPanel"
	local plate = part("Plate", slot.Size, slot.CFrame, Color3.fromRGB(46, 48, 54), Enum.Material.Metal, panel)
	plate.CanCollide = true
	plate.CanQuery = true
	plate:SetAttribute("Breakable", "Panel")
	local alongX = slot.Size.X > slot.Size.Z
	for _, fraction in { -0.3, 0, 0.3 } do
		local size = if alongX then Vector3.new(slot.Size.X, 0.3, slot.Size.Z + 0.12) else Vector3.new(slot.Size.X + 0.12, 0.3, slot.Size.Z)
		part("Rib", size, slot.CFrame * CFrame.new(0, slot.Size.Y * fraction, 0), Color3.fromRGB(200, 120, 40), Enum.Material.Metal, panel)
	end
	panel.Parent = slot.Parent
	GadgetService.Gesture(character, "ArmorPanel", slot.CFrame)
	slot:SetAttribute("Built", true)
	slot:SetAttribute("Panel", true)
	panel.Destroying:Connect(function()
		slot:SetAttribute("Built", nil)
		slot:SetAttribute("Panel", nil)
	end)
	return true
end

-- Ability name → handler (AbilityService calls these; true = a charge was used)
GadgetService.Handlers = {
	BreachCharge = breachCharge,
	HardBreach = hardBreach,
	EmpGrenade = empGrenade,
	ShockWire = shockWire,
	SignalJammer = signalJammer,
	ArmorPanel = armorPanel,
}

return GadgetService
