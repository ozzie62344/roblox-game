-- Client-side movement, Siege-style: walk, sprint, crouch, prone (crawl) and vaulting. No jumping
-- (the Humanoid's Jumping state is switched off, which also hides the phone's jump button).
-- We drive horizontal velocity ourselves through a LinearVelocity, with weighty acceleration and
-- deceleration. The Humanoid still handles gravity, stairs and falling off ledges.
--   Speeds scale with your operator's Speed rating (Operators.luau, MovementConfig.SpeedRating);
--   strafing is a little slower than forward and backing up slower still.
--   Sprinting: no aiming, no leaning, and holding fire ends it (state.fireHeld, WeaponController).
--   After a sprint (or a vault) the gun takes MovementConfig.SprintOutTime to come back up:
--   state.canFire says when you can shoot.
--   Vault (Space / gamepad A / the phone's VAULT button): facing low cover or a window sill, a
--   short scripted hop over it (quicker from a sprint), or up onto it if it's too deep to clear
--   (a crate, a ledge) — never higher than MovementConfig.VaultMaxHeight. The body is moved
--   along the arc here every physics step (PlatformStand, like the rappel); the server hears about
--   it (Vault remote → the character's "Vaulting" attribute) so others hear it and see the pose,
--   and the anti-cheat lets the hop through.
--   Downed (state.downed, DBNOController): forced flat on the floor, crawling at DBNO.CrawlSpeed
--   (still while holding the wound), no sprinting, vaulting or getting up until you're revived.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.MovementConfig)
local DBNO = require(ReplicatedStorage.Shared.DBNO)
local Operators = require(ReplicatedStorage.Shared.Operators)
local Weapons = require(ReplicatedStorage.Shared.Weapons)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local SetCrouch = Remotes:WaitForChild("SetCrouch") :: RemoteEvent
local VaultRemote = Remotes:WaitForChild("Vault") :: RemoteEvent
local ReloadStarted = Remotes:WaitForChild("ReloadStarted") :: RemoteEvent

local player = Players.LocalPlayer

local MovementController = {}

local state = require(script.Parent.Parent.PlayerState)
local Actions = require(script.Parent.Parent.Input.Actions)
local MoveInput = require(script.Parent.Parent.Input.MoveInput)
local Footsteps = require(script.Parent.Parent.Audio.Footsteps)

local humanoid: Humanoid? = nil
local root: BasePart? = nil
local linearVelocity: LinearVelocity? = nil
local characterConnections: { RBXScriptConnection } = {}

local sprintHeld = false
local lastSprintInput = false -- (a fresh sprint press stands you up from a crouch / prone)
local velocity = Vector3.zero -- horizontal velocity we want
local velocityOverridden = false -- a vault ending set velocity since the last step
local standHipHeight = 2
local heightDrop = 0 -- smoothed: how far we're currently lowered (crouch / prone)
local sentLowered = false
local sentProne = false
local lastCrouchTap = -math.huge
local sprintOutUntil = 0 -- os.clock(): the gun is back up after a sprint / vault
local reloadingUntil = 0 -- os.clock(): our own reload (ReloadStarted comes back to us too)
local wasDowned = false -- downed last step (revived: stand back up)

-- A vault / climb in progress: the root follows `points` (keyframes of where your middle is) over
-- `duration` seconds; `ends` is the share of the time each segment finishes at
type Vault = {
	points: { Vector3 },
	ends: { number },
	duration: number,
	elapsed: number,
	exitVelocity: Vector3,
	endCrouched: boolean,
	landed: boolean, -- ends on solid ground (otherwise you drop off the far side)
}
local vault: Vault? = nil
-- Space pressed a moment before you reach the cover still counts: we keep trying until then
local VAULT_BUFFER = 0.6 -- seconds (about 8 studs at a walk: third person makes the distance hard to judge)
local vaultWantedUntil = 0

-- Humanoid states where we hand control back to Roblox's default movement
local PASSIVE_STATES = {
	[Enum.HumanoidStateType.Climbing] = true,
	[Enum.HumanoidStateType.Seated] = true,
	[Enum.HumanoidStateType.Swimming] = true,
	[Enum.HumanoidStateType.PlatformStanding] = true,
	[Enum.HumanoidStateType.Dead] = true,
}

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function moveToward(current: Vector3, target: Vector3, maxDelta: number): Vector3
	local delta = target - current
	local distance = delta.Magnitude
	if distance <= maxDelta or distance == 0 then
		return target
	end
	return current + delta / distance * maxDelta
end

local function isGrounded(): boolean
	return humanoid ~= nil and humanoid.FloorMaterial ~= Enum.Material.Air
end

local function lookDirection(): Vector3
	local look = flat(Workspace.CurrentCamera.CFrame.LookVector)
	if look.Magnitude < 1e-3 then
		return Vector3.new(0, 0, -1)
	end
	return look.Unit
end

-- Phones: the thumbstick is analog. Pushed all the way forward = sprint; pushed less = slower
-- (down to 30% speed). Returns (sprint?, speed scale); keyboards and gamepads get (false, 1).
local STICK_SPRINT = 0.92 -- how far out the stick has to be to sprint
local function stickSpeed(): (boolean, number)
	if not state.touchControls then
		return false, 1
	end
	local push = MoveInput.Push()
	if not push then
		return false, 1
	end
	if push >= STICK_SPRINT then -- (sprinting also needs you to be going forward: wantsToSprint)
		return true, 1
	end
	return false, math.clamp((push - 0.1) / (STICK_SPRINT - 0.1), 0.3, 1)
end

local function wishDirection(): Vector3
	if not humanoid then
		return Vector3.zero
	end
	local direction = flat(humanoid.MoveDirection)
	if direction.Magnitude < 1e-3 then
		return Vector3.zero
	end
	return direction.Unit
end

-- Your operator's Speed rating (1-3; 2 with no operator) as a speed multiplier
local function speedRating(): number
	local operator = Operators.ById[player:GetAttribute("Operator") or ""]
	local rating = if operator and operator.Speed then operator.Speed else 2
	return Config.SpeedRating[rating] or 1
end

-- Forward is full speed, sideways StrafeScale, straight back BackpedalScale (blended between)
local function directionScale(wish: Vector3): number
	local forward = wish:Dot(lookDirection())
	if forward >= 0 then
		return Config.StrafeScale + (1 - Config.StrafeScale) * forward
	end
	return Config.StrafeScale + (Config.BackpedalScale - Config.StrafeScale) * -forward
end

-- Is there room above your head to rise this much? (don't stand up into a ceiling)
local function canRise(amount: number): boolean
	local character = root and root.Parent
	local head = character and character:FindFirstChild("Head") :: BasePart?
	if not head then
		return true
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character :: Instance }
	return Workspace:Raycast(head.Position, Vector3.new(0, amount + 0.6, 0), params) == nil
end

local function canStandUp(): boolean
	return canRise(math.max(heightDrop, Config.CrouchHeightDrop))
end

local function tryStandUp()
	if state.crouching and canStandUp() then
		state.crouching = false
	end
end

local function goProne()
	state.crouching = false
	state.prone = true
end

-- Up from lying down: to a crouch (C) or all the way up (Space / sprint), if there's room.
-- Not enough room to stand? You end up crouched.
local function getUp(toCrouch: boolean)
	if not state.prone then
		return
	end
	if not toCrouch and canRise(heightDrop) then
		state.prone, state.crouching = false, false
	elseif canRise(heightDrop - Config.CrouchHeightDrop) then
		state.prone, state.crouching = false, true
	end
end

-- ─── Vaulting ──────────────────────────────────────────────────────────────────

local HEAD_ABOVE_ROOT = 2.6 -- top of your head above your middle (R15)

-- Your middle's height above the floor when standing
local function standRootHeight(): number
	return standHipHeight + (if root then root.Size.Y / 2 else 1)
end

local function vaultParams(): RaycastParams
	local ignore: { Instance } = { Workspace.CurrentCamera }
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(ignore, other.Character)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.RespectCanCollide = true -- (open doors, see-through effects)
	return params
end

-- Works out a vault / climb over whatever is in front of you, or nil if there's nothing you can
-- get over. Distances are along `v` (straight into the cover's face) from your middle.
local function planVault(fast: boolean): Vault?
	if not root or not humanoid then
		return nil
	end
	local params = vaultParams()
	local origin = root.Position
	local standRoot = standRootHeight()
	local floor = Workspace:Raycast(origin, Vector3.new(0, -(standRoot + 1.5), 0), params)
	if not floor then
		return nil
	end
	local feetY = floor.Position.Y

	-- The cover's face: knee and shin height, in front of where you're looking
	local look = lookDirection()
	local face: RaycastResult? = nil
	for _, h in { 0.7, 1.1, 1.6 } do
		local hit = Workspace:Raycast(Vector3.new(origin.X, feetY + h, origin.Z), look * Config.VaultReach, params)
		if hit and math.abs(hit.Normal.Y) < 0.35 and (not face or hit.Distance < face.Distance) then
			face = hit
		end
	end
	if not face then
		return nil
	end
	local v = -flat(face.Normal).Unit
	if v:Dot(look) < 0.6 then
		return nil -- (more than ~50° off: you're running along it, not at it)
	end
	local frontDist = flat(face.Position - origin):Dot(v)
	local function at(distance: number, y: number): Vector3
		return Vector3.new(origin.X, y, origin.Z) + v * distance
	end

	-- Its top: the lowest height where nothing is in the way just past the face
	local topGuess: number? = nil
	local h = 0.5
	while h <= Config.VaultMaxHeight + 0.3 do
		if not Workspace:Raycast(at(0, feetY + h), v * (frontDist + 0.5), params) then
			topGuess = feetY + h
			break
		end
		h += 0.25
	end
	if not topGuess then
		return nil -- a wall (that's what the rappel is for)
	end
	local topY = topGuess - 0.125
	local onTop = Workspace:Raycast(at(frontDist + 0.35, topGuess + 0.3), Vector3.new(0, -1.2, 0), params)
	if onTop and onTop.Normal.Y > 0.6 then
		topY = onTop.Position.Y
	end
	local height = topY - feetY
	if height < Config.VaultMinHeight or height > Config.VaultMaxHeight + 0.05 then
		return nil
	end

	-- Room above it (a window's top, a shelf)
	local above = Workspace:Raycast(at(frontDist + 0.35, topY + 0.05), Vector3.new(0, 8, 0), params)
	local gap = if above then above.Distance else 8
	if gap < Config.VaultMinGap then
		return nil
	end

	-- How deep is it? Step along the top until it drops away.
	local farDist: number? = nil
	local k = 0.35
	while k <= Config.VaultMaxThickness + 0.4 do
		if not Workspace:Raycast(at(frontDist + k, topY + 0.4), Vector3.new(0, -0.9, 0), params) then
			farDist = frontDist + k - 0.2
			break
		end
		k += 0.4
	end

	-- Nothing in the way along the path at this height (your middle and both shoulders)
	local sideways = v:Cross(Vector3.yAxis)
	local function pathClear(y: number, length: number): boolean
		for _, side in { 0, 0.55, -0.55 } do
			if Workspace:Raycast(at(0, y) + sideways * side, v * length, params) then
				return false
			end
		end
		return true
	end
	-- Standing room on the floor at `spot`: nil = none, otherwise whether you'd have to crouch
	local fullHeight = standRoot + HEAD_ABOVE_ROOT
	local function roomAt(spot: Vector3): boolean?
		local ceiling = Workspace:Raycast(spot + Vector3.new(0, 0.2, 0), Vector3.new(0, fullHeight, 0), params)
		if ceiling and ceiling.Distance < fullHeight - Config.CrouchHeightDrop - 0.2 then
			return nil
		end
		return ceiling ~= nil
	end

	local exitSpeed = if fast then Config.VaultFastExitSpeed else Config.VaultExitSpeed
	if farDist then
		-- Vault over: up to just above the top, across, and down on the far side
		local landDist = farDist + 1.4
		local over = math.max(topY + math.clamp(gap - HEAD_ABOVE_ROOT - 0.15, 0.9, 1.5), origin.Y + 0.3)
		if not pathClear(over - 0.3, landDist + 0.6) or not pathClear(math.min(over + 1.3, topY + gap - 0.4), landDist + 0.6) then
			return nil
		end
		local ground = Workspace:Raycast(at(landDist, topY + 0.5), Vector3.new(0, -(height + 0.5 + Config.VaultMaxDrop), 0), params)
		local endY = over -- (a long drop on the far side: over the top and let go)
		local endCrouched = false
		if ground then
			local crouched = roomAt(ground.Position)
			if crouched == nil then
				return nil -- no room to land
			end
			endCrouched = crouched
			-- Nothing on the far side at body height either
			if Workspace:Raycast(at(farDist, ground.Position.Y + 1.2), v * (landDist - farDist + 0.6), params) then
				return nil
			end
			endY = ground.Position.Y + standRoot - (if endCrouched then Config.CrouchHeightDrop else 0)
		end
		return {
			points = { origin, at(math.max(frontDist - 0.15, 0), over), at(farDist + 0.15, over), at(landDist, endY) },
			ends = { 0.4, 0.65, 1 },
			duration = if fast then Config.VaultFastTime else Config.VaultTime,
			elapsed = 0,
			exitVelocity = v * exitSpeed,
			endCrouched = endCrouched,
			landed = ground ~= nil,
		}
	end

	-- Too deep to clear: climb up onto it (a crate, a ledge), if there's somewhere to stand
	local standDist = frontDist + 1.3
	local footing = Workspace:Raycast(at(standDist, topY + 1), Vector3.new(0, -1.5, 0), params)
	if not footing or footing.Normal.Y < 0.7 or math.abs(footing.Position.Y - topY) > 0.4 then
		return nil
	end
	local endCrouched = roomAt(footing.Position)
	if endCrouched == nil or not pathClear(footing.Position.Y + 1, standDist + 0.6) then
		return nil
	end
	local endY = footing.Position.Y + standRoot - (if endCrouched then Config.CrouchHeightDrop else 0)
	return {
		points = { origin, at(math.max(frontDist - 0.6, 0), endY + 0.2), at(standDist, endY) },
		ends = { 0.65, 1 },
		duration = Config.ClimbTime * (if fast then 0.85 else 1),
		elapsed = 0,
		exitVelocity = v * exitSpeed * 0.5,
		endCrouched = endCrouched,
		landed = true,
	}
end

-- Where your middle is `t` (0-1) of the way through the vault: each segment moves across at a
-- steady pace; going up eases out (a quick push up), coming down eases in (dropping off)
local function vaultPosition(plan: Vault, t: number): Vector3
	local startT = 0
	for i, endT in plan.ends do
		if t <= endT or i == #plan.ends then
			local a, b = plan.points[i], plan.points[i + 1]
			local u = math.clamp((t - startT) / math.max(endT - startT, 1e-3), 0, 1)
			local rise = b.Y - a.Y
			local up = if rise > 0.05 then math.sin(u * math.pi / 2)
				elseif rise < -0.05 then 1 - math.cos(u * math.pi / 2)
				else u
			local across = flat(a):Lerp(flat(b), u)
			return Vector3.new(across.X, a.Y + rise * up, across.Z)
		end
		startT = endT
	end
	return plan.points[#plan.points]
end

local function finishVault()
	local plan = vault
	vault = nil
	state.vaulting = false
	state.vaultAlpha = 0
	sprintOutUntil = os.clock() + Config.SprintOutTime
	if not plan or not humanoid or not root then
		return
	end
	local final = plan.points[#plan.points]
	root.CFrame = CFrame.lookAt(final, final + lookDirection())
	root.AssemblyLinearVelocity = plan.exitVelocity
	humanoid.PlatformStand = false
	humanoid:ChangeState(if plan.landed then Enum.HumanoidStateType.Running else Enum.HumanoidStateType.Freefall)
	velocity = plan.exitVelocity
	velocityOverridden = true
	state.crouching = plan.endCrouched
	if plan.endCrouched then
		-- (already low: don't pop up into the ceiling for a frame)
		heightDrop = Config.CrouchHeightDrop
		humanoid.HipHeight = standHipHeight - heightDrop
	end
	if plan.landed then
		Footsteps.VaultLand(final - Vector3.new(0, standRootHeight(), 0), true)
	end
end

local function cancelVault()
	if vault and humanoid and not state.rappelling then -- (the rope keeps PlatformStand on)
		humanoid.PlatformStand = false
	end
	vault = nil
	state.vaulting = false
	state.vaultAlpha = 0
end

local function tryVault()
	if vault or not humanoid or not root or humanoid.Health <= 0 or root.Anchored then
		return
	end
	if state.prone or state.aiming or state.aimAlpha > 0.2 or os.clock() < reloadingUntil then
		return -- (aiming, reloading or lying down: no vaulting)
	end
	if state.rappelling or state.deploying or state.interacting or state.droning or state.meleeing
		or state.spectating or state.devPanelOpen or state.mouseUnlocked
		or not isGrounded() or PASSIVE_STATES[humanoid:GetState()]
	then
		return
	end
	local fast = state.sprinting
	local plan = planVault(fast)
	if not plan then
		return
	end
	vault = plan
	state.vaulting = true
	state.vaultAlpha = 0
	state.sprinting = false
	state.canFire = false
	if heightDrop > 0 then -- (vaulting from a crouch: you come up as you go over)
		heightDrop = 0
		humanoid.HipHeight = standHipHeight
	end
	humanoid.PlatformStand = true
	VaultRemote:FireServer(plan.duration)
	Footsteps.VaultStart(root.Position - Vector3.new(0, standRootHeight(), 0), true)
end

-- Moves the root along the vault every physics step (true while vaulting)
local function stepVault(dt: number): boolean
	local plan = vault
	if not plan or not humanoid or not root or not linearVelocity then
		return false
	end
	if humanoid.Health <= 0 or root.Anchored or state.rappelling then
		cancelVault()
		return false
	end
	linearVelocity.Enabled = false
	plan.elapsed += dt
	local t = plan.elapsed / plan.duration
	if t >= 1 then
		finishVault()
		return false
	end
	state.vaultAlpha = t
	local position = vaultPosition(plan, t)
	local nextPosition = vaultPosition(plan, math.min(t + dt / plan.duration, 1))
	root.CFrame = CFrame.lookAt(position, position + lookDirection())
	-- (moving at the path's own speed: after this physics step the root is where the next frame wants it)
	root.AssemblyLinearVelocity = (nextPosition - position) / math.max(dt, 1e-3)
	root.AssemblyAngularVelocity = Vector3.zero
	state.velocity = flat(root.AssemblyLinearVelocity)
	state.speed = state.velocity.Magnitude
	state.sprinting = false
	state.canFire = false
	return true
end

-- ─── Every physics step ────────────────────────────────────────────────────────

local function step(dt: number)
	if not humanoid or not root or not linearVelocity then
		return
	end
	if stepVault(dt) then
		return
	end
	if os.clock() < vaultWantedUntil then
		tryVault() -- (pressed a little early: vault as soon as the cover is in reach)
		if vault then
			vaultWantedUntil = 0
		end
	end

	local passive = PASSIVE_STATES[humanoid:GetState()] == true
	linearVelocity.Enabled = not passive
	if passive then
		velocity = flat(root.AssemblyLinearVelocity)
		state.sprinting = false
		state.canFire = os.clock() >= sprintOutUntil
		return
	end

	linearVelocity.MaxForce = root.AssemblyMass * Config.MaxMoveAccel

	local fullVelocity = root.AssemblyLinearVelocity
	if fullVelocity.Y < -Config.MaxFallSpeed then
		root.AssemblyLinearVelocity = Vector3.new(fullVelocity.X, -Config.MaxFallSpeed, fullVelocity.Z)
	end

	-- If something blocked us (a wall), adopt the real velocity so we don't keep pushing into it
	local actual = flat(fullVelocity)
	if not velocityOverridden and (velocity - actual).Magnitude > 2 then
		velocity = actual
	end
	velocityOverridden = false

	local grounded = isGrounded()

	-- Downed: flat on the floor until a teammate picks you up, then back on your feet (crouched
	-- if there's no room)
	if state.downed then
		state.prone, state.crouching = true, false
	elseif wasDowned then
		getUp(false)
	end
	wasDowned = state.downed

	-- Pulling up cover / planting / disabling / reviving / driving a drone / holding your wound:
	-- rooted in place
	local rooted = state.deploying or state.interacting or state.droning or (state.downed and state.holdingWound)
	local wish = if rooted then Vector3.zero else wishDirection()
	local stickSprint, stickScale = stickSpeed()
	local sprintInput = sprintHeld or stickSprint
	local sprintPressed = sprintInput and not lastSprintInput
	lastSprintInput = sprintInput
	local wantsToSprint = sprintInput and wish:Dot(lookDirection()) > 0.5
	-- A fresh sprint press gets you up off the floor / out of a crouch (just holding it doesn't:
	-- crouch while running and you stay down until you press it again)
	if sprintPressed and wantsToSprint and not state.downed then
		if state.prone then
			getUp(false)
		end
		tryStandUp()
	end
	local wasSprinting = state.sprinting
	state.sprinting = wantsToSprint
		and grounded
		and not state.crouching
		and not state.prone
		and not state.aiming
		and not state.leaning
		and not state.fireHeld -- (pressing fire ends a sprint; the shot comes once the gun's up)
		and os.clock() - state.lastShot > Config.SprintBlockAfterShot
	if wasSprinting and not state.sprinting then
		sprintOutUntil = os.clock() + Config.SprintOutTime
	end
	state.canFire = not state.sprinting and os.clock() >= sprintOutUntil

	local targetSpeed = Config.WalkSpeed
	if state.sprinting then
		targetSpeed = Config.SprintSpeed
	else
		if state.aiming then
			targetSpeed = math.min(targetSpeed, Config.AimWalkSpeed)
		end
		if state.crouching then
			targetSpeed = math.min(targetSpeed, Config.CrouchSpeed)
		end
		if state.prone then
			targetSpeed = math.min(targetSpeed, Config.ProneSpeed)
		end
		targetSpeed *= stickScale
		if wish ~= Vector3.zero then
			targetSpeed *= directionScale(wish)
		end
	end
	-- (Siege: everyone aims in at the same speed, so 3-speed wins rotations, not gunfights)
	if not state.aiming then
		targetSpeed *= speedRating()
	end
	-- Heavy guns (the gatling) slow you down, sprinting too, and more again while it's spinning
	local held = Weapons[player:GetAttribute("Weapon") or ""]
	if held and held.MoveSpeedScale then
		targetSpeed *= held.MoveSpeedScale * (1 - (held.SpinSlow or 0) * state.weaponSpin)
	end
	if state.downed then
		targetSpeed = math.min(targetSpeed, DBNO.CrawlSpeed * stickScale) -- (a slow crawl, any operator)
	end
	local speed = velocity.Magnitude

	if grounded then
		if wish ~= Vector3.zero and speed > targetSpeed then
			-- Carrying extra momentum (a speed vault, a push off the rope): bleed it off gradually
			local newSpeed = math.max(speed - Config.MomentumFriction * dt, targetSpeed)
			velocity = moveToward(velocity, wish * newSpeed, Config.GroundAccel * dt)
		else
			local accel = if wish == Vector3.zero then Config.GroundDecel else Config.GroundAccel
			velocity = moveToward(velocity, wish * targetSpeed, accel * dt)
		end
	else
		if speed > targetSpeed then
			-- Keep momentum in the air, with a little steering
			local newSpeed = math.max(speed - Config.AirDrag * dt, targetSpeed)
			local direction = velocity.Unit
			if wish ~= Vector3.zero then
				local steered = direction:Lerp(wish, math.clamp(Config.AirSteer * dt, 0, 1))
				if steered.Magnitude > 1e-3 then
					direction = steered.Unit
				end
			end
			velocity = direction * newSpeed
		else
			velocity = moveToward(velocity, wish * targetSpeed, Config.AirAccel * dt)
		end
	end

	linearVelocity.PlaneVelocity = Vector2.new(velocity.X, velocity.Z)

	-- Crouching lowers the whole character (hitbox included), not just the camera. Planting /
	-- disabling kneels too; barricading and reinforcing are done standing. Lying down drops it
	-- nearly to the floor (other players see the body lie flat: BodyAnimator).
	local interaction = player:GetAttribute("Interaction")
	local kneeling = state.interacting and (interaction == "Plant" or interaction == "Disable" or interaction == "Revive")
	local lowered = state.crouching or state.deploying or kneeling or state.prone
	local targetDrop = if state.prone then math.max(standHipHeight - Config.ProneHipHeight, Config.CrouchHeightDrop)
		elseif lowered then Config.CrouchHeightDrop
		else 0
	heightDrop += (targetDrop - heightDrop) * (1 - math.exp(-Config.CrouchTransitionSpeed * dt))
	if heightDrop < 0.01 and not lowered then
		if heightDrop > 0 then
			heightDrop = 0
			humanoid.HipHeight = standHipHeight
		end
		standHipHeight = humanoid.HipHeight -- pick up Roblox's own value (it can change on spawn)
	else
		humanoid.HipHeight = standHipHeight - heightDrop
	end
	if lowered ~= sentLowered or state.prone ~= sentProne then
		sentLowered, sentProne = lowered, state.prone
		SetCrouch:FireServer(lowered, state.prone)
	end

	state.velocity = velocity
	state.speed = velocity.Magnitude
	state.grounded = grounded
end

local function cleanupCharacter()
	for _, connection in characterConnections do
		connection:Disconnect()
	end
	table.clear(characterConnections)
	if linearVelocity then
		linearVelocity:Destroy()
	end
	vault = nil
	humanoid, root, linearVelocity = nil, nil, nil
	velocity = Vector3.zero
	state.vaulting = false
	state.vaultAlpha = 0
	state.sprinting = false
	state.canFire = true
	state.crouching = false
	state.prone = false
	state.speed = 0
	state.velocity = Vector3.zero
	heightDrop = 0
	sentLowered = false
	sentProne = false
	sprintOutUntil = 0
	reloadingUntil = 0
	wasDowned = false
end

local function setupCharacter(character: Model)
	cleanupCharacter()

	local newHumanoid = character:WaitForChild("Humanoid") :: Humanoid
	local newRoot = character:WaitForChild("HumanoidRootPart") :: BasePart
	-- No jumping at all (Siege): you vault instead. With jumping off, Roblox hides the phone's
	-- jump button too (MobileControls has a VAULT button).
	newHumanoid.UseJumpPower = false
	newHumanoid.JumpHeight = 0
	newHumanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)

	local attachment = Instance.new("Attachment")
	attachment.Name = "MovementAttachment"
	attachment.Parent = newRoot

	local constraint = Instance.new("LinearVelocity")
	constraint.Name = "MovementVelocity"
	constraint.Attachment0 = attachment
	constraint.RelativeTo = Enum.ActuatorRelativeTo.World
	constraint.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	constraint.PrimaryTangentAxis = Vector3.xAxis
	constraint.SecondaryTangentAxis = Vector3.zAxis
	constraint.MaxForce = 0 -- set every step from the character's mass
	constraint.PlaneVelocity = Vector2.zero
	constraint.Parent = newRoot

	humanoid, root, linearVelocity = newHumanoid, newRoot, constraint
	standHipHeight = newHumanoid.HipHeight

	table.insert(characterConnections, newHumanoid.Died:Connect(cleanupCharacter))
end

-- The vault key (Space / gamepad A / the phone's VAULT button): up from prone, otherwise vault
function MovementController.VaultPressed()
	if state.droning or state.spectating or state.downed then
		return -- (Space hops the drone; downed you can't get up)
	elseif state.prone then
		getUp(false)
	else
		tryVault()
		vaultWantedUntil = if vault then 0 else os.clock() + VAULT_BUFFER
	end
end

function MovementController.Start()
	Actions.Bind("Sprint", function(_, inputState)
		sprintHeld = inputState == Enum.UserInputState.Begin
		return Enum.ContextActionResult.Pass
	end, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL3)

	-- C / Ctrl: tap to toggle crouch (crouching ends a sprint). Two quick taps: lie down (prone);
	-- tap again to come back up to a crouch. In the lobby, crouching mid-sprint slides.
	Actions.Bind("Crouch", function(_, inputState)
		if inputState ~= Enum.UserInputState.Begin or state.deploying or state.interacting or state.vaulting or state.downed then
			return Enum.ContextActionResult.Sink
		end
		local now = os.clock()
		local doubleTap = now - lastCrouchTap < Config.ProneDoubleTap
		lastCrouchTap = now
		if state.prone then
			getUp(true)
			lastCrouchTap = -math.huge -- a quick tap after this isn't another double tap
		-- (not in the lobby: your own third-person body there would lie on its collidable torso and
		-- hold you up off the floor)
		elseif doubleTap and isGrounded() and not state.rappelling and not state.inLobby then
			goProne()
			lastCrouchTap = -math.huge
		elseif state.crouching then
			tryStandUp()
		elseif isGrounded() then
			-- Lobby only: crouching out of a sprint is a slide, a burst of speed that bleeds off into a
			-- crouch-walk (the momentum friction in step). Matches stay Siege: no sliding.
			if state.inLobby and state.sprinting and velocity.Magnitude > 1 then
				velocity = velocity.Unit * Config.LobbySlideSpeed
				velocityOverridden = true
			end
			state.crouching = true
		end
		return Enum.ContextActionResult.Sink
	end, Enum.KeyCode.C, Enum.KeyCode.LeftControl, Enum.KeyCode.ButtonB)

	-- Space / A: vault (or get up). While rappelling, RappelController takes Space first (higher
	-- priority) to go in through the window / push off.
	Actions.Bind("Vault", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			MovementController.VaultPressed()
		end
		return Enum.ContextActionResult.Pass
	end, Enum.KeyCode.Space, Enum.KeyCode.ButtonA)

	-- Our own reloads (no vaulting mid-reload): the server tells everyone, us included
	ReloadStarted.OnClientEvent:Connect(function(reloader: Player, weaponName: string, duration: number?)
		local weapon = Weapons[weaponName]
		if reloader == player and weapon then
			reloadingUntil = os.clock() + (if typeof(duration) == "number" then duration else weapon.ReloadTime)
		end
	end)

	if player.Character then
		task.spawn(setupCharacter, player.Character)
	end
	player.CharacterAdded:Connect(setupCharacter)
	player.CharacterRemoving:Connect(cleanupCharacter)

	RunService.PreSimulation:Connect(step)
end

return MovementController
