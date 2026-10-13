-- Client-side movement: sprint, crouch, prone (crawl), slide, dash, wall jump.
-- We drive horizontal velocity ourselves through a LinearVelocity so momentum
-- carries between moves. The Humanoid still handles jumping, gravity, stairs
-- and animations.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.MovementConfig)
local Weapons = require(ReplicatedStorage.Shared.Weapons)

local SetCrouch = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("SetCrouch") :: RemoteEvent

local player = Players.LocalPlayer

local MovementController = {}

local state = require(script.Parent.Parent.PlayerState)
local Actions = require(script.Parent.Parent.Input.Actions)
local MoveInput = require(script.Parent.Parent.Input.MoveInput)

local humanoid: Humanoid? = nil
local root: BasePart? = nil
local linearVelocity: LinearVelocity? = nil
local characterConnections: { RBXScriptConnection } = {}

local sprintHeld = false
local slideHeld = false -- slides only last while C / Ctrl is held
local velocity = Vector3.zero -- horizontal velocity we want
local velocityOverridden = false -- an input (slide/wall jump) set velocity since the last step
local slideTimer = 0
local slideBufferedUntil = -math.huge
local lastSlideBoostTime = -math.huge
local dashTimer = 0
local dashDirection = Vector3.zero
local lastDashTime = -math.huge
local airDashUsed = false
local wallJumpsUsed = 0
local lastWallNormal: Vector3? = nil -- the wall we last jumped off (by which way it faces)
local lastGroundedTime = 0
local standHipHeight = 2
local heightDrop = 0 -- smoothed: how far we're currently lowered (crouch / slide / prone)
local sentLowered = false
local sentProne = false
local jumpBlocked = false
local lastCrouchTap = -math.huge

local WALL_CHECK_DIRECTIONS = {}
for i = 0, 7 do
	local angle = i * math.pi / 4
	table.insert(WALL_CHECK_DIRECTIONS, Vector3.new(math.cos(angle), 0, math.sin(angle)))
end

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

-- Abilities are handed out by the server through a player attribute, e.g. Ability = "Dash"
local function hasAbility(name: string): boolean
	return Config.TestAllAbilities or player:GetAttribute("Ability") == name
end

local lastSlideEnd = -math.huge

local function endSlide()
	if state.sliding then
		lastSlideEnd = os.clock()
	end
	state.sliding = false
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
	endSlide()
	state.dashing = false
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

local function startSlide()
	if state.sliding or state.dashing then
		return
	end
	-- A short wait after each slide before the next one
	if os.clock() - lastSlideEnd < Config.SlideCooldown then
		return
	end
	if not isGrounded() then
		-- Remember the press so the slide fires the moment we land
		slideBufferedUntil = os.clock() + Config.SlideBufferTime
		return
	end
	slideBufferedUntil = -math.huge
	local speed = velocity.Magnitude
	if speed < Config.SlideMinStartSpeed then
		return
	end

	local boost = 0
	local now = os.clock()
	if now - lastSlideBoostTime >= Config.SlideBoostCooldown then
		boost = Config.SlideBoost
		lastSlideBoostTime = now
	end

	-- Never slow you down if you're already faster than the slide cap (e.g. right after a dash)
	local newSpeed = math.max(speed, math.min(speed + boost, Config.SlideMaxSpeed))
	velocity = velocity.Unit * newSpeed
	velocityOverridden = true
	slideTimer = 0
	state.sliding = true
end

local function startDash()
	if state.dashing or state.prone or not root or not hasAbility("Dash") then
		return
	end
	local now = os.clock()
	if now - lastDashTime < Config.DashCooldown then
		return
	end
	local grounded = isGrounded()
	if not grounded and airDashUsed then
		return
	end

	local direction = wishDirection()
	if direction == Vector3.zero then
		direction = lookDirection()
	end

	lastDashTime = now
	if not grounded then
		airDashUsed = true
	end
	endSlide()
	dashTimer = 0
	dashDirection = direction
	state.dashing = true
end

-- Finds the closest steep wall around the player, if any
local function findWall(): RaycastResult?
	if not root then
		return nil
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { root.Parent :: Instance }

	local closest: RaycastResult? = nil
	for _, direction in WALL_CHECK_DIRECTIONS do
		local result = Workspace:Raycast(root.Position, direction * Config.WallJumpCheckDistance, params)
		if result and math.abs(result.Normal.Y) < 0.3 then
			if not closest or result.Distance < closest.Distance then
				closest = result
			end
		end
	end
	return closest
end

local function tryWallJump()
	if not humanoid or not root or isGrounded() or not hasAbility("WallJump") then
		return
	end
	if PASSIVE_STATES[humanoid:GetState()] then
		return
	end
	if os.clock() - lastGroundedTime < Config.WallJumpMinAirTime then
		return
	end
	if wallJumpsUsed >= Config.WallJumpMaxPerAir then
		return
	end

	local wall = findWall()
	if not wall then
		return
	end
	local normal = flat(wall.Normal).Unit
	-- No jumping off the same wall twice in a row (stops climbing a single wall). Compared by the
	-- way the wall faces, because one wall is often built from several parts.
	if lastWallNormal and normal:Dot(lastWallNormal) > 0.7 then
		return
	end
	local alongWall = velocity - normal * velocity:Dot(normal)
	velocity = alongWall * Config.WallJumpKeepAlong + normal * Config.WallJumpPush
	velocityOverridden = true

	local v = root.AssemblyLinearVelocity
	root.AssemblyLinearVelocity = Vector3.new(v.X, Config.WallJumpUp, v.Z)

	wallJumpsUsed += 1
	lastWallNormal = normal
	endSlide()
	state.dashing = false
	state.lastWallJump = os.clock()
end

local function step(dt: number)
	if not humanoid or not root or not linearVelocity then
		return
	end

	local passive = PASSIVE_STATES[humanoid:GetState()] == true
	linearVelocity.Enabled = not passive
	if passive then
		velocity = flat(root.AssemblyLinearVelocity)
		endSlide()
		state.dashing = false
		return
	end

	linearVelocity.MaxForce = root.AssemblyMass * Config.MaxMoveAccel

	local fullVelocity = root.AssemblyLinearVelocity
	if fullVelocity.Y < -Config.MaxFallSpeed then
		root.AssemblyLinearVelocity = Vector3.new(fullVelocity.X, -Config.MaxFallSpeed, fullVelocity.Z)
	end

	-- If something blocked us (a wall), adopt the real velocity so we don't keep pushing into it
	local actual = flat(fullVelocity)
	if not state.dashing and not velocityOverridden and (velocity - actual).Magnitude > 2 then
		velocity = actual
	end
	velocityOverridden = false

	local grounded = isGrounded()
	if grounded then
		airDashUsed = false
		wallJumpsUsed = 0
		lastWallNormal = nil
		lastGroundedTime = os.clock()
		if slideHeld and os.clock() <= slideBufferedUntil then
			startSlide()
		end
	end

	-- Pulling up cover / planting / disabling / driving a drone: rooted in place, can't jump.
	-- Lying down: no jumping either (Space gets you up instead).
	local rooted = state.deploying or state.interacting or state.droning
	local wish = if rooted then Vector3.zero else wishDirection()
	if (rooted or state.prone) ~= jumpBlocked then
		jumpBlocked = rooted or state.prone
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, not jumpBlocked)
	end
	if rooted then
		endSlide()
	end
	local stickSprint, stickScale = stickSpeed()
	local wantsToSprint = (sprintHeld or stickSprint) and wish:Dot(lookDirection()) > 0.5
	if state.prone and wantsToSprint then
		getUp(false)
	end
	if state.crouching and wantsToSprint then
		tryStandUp()
	end
	state.sprinting = wantsToSprint
		and not state.crouching
		and not state.prone
		and not state.aiming
		and not state.leaning
		and os.clock() - state.lastShot > Config.SprintBlockAfterShot

	if state.dashing then
		dashTimer += dt
		velocity = dashDirection * Config.DashSpeed
		-- Hold height during the dash so air dashes feel snappy instead of droopy
		local v = root.AssemblyLinearVelocity
		if v.Y < 0 then
			root.AssemblyLinearVelocity = Vector3.new(v.X, 0, v.Z)
		end
		if dashTimer >= Config.DashDuration then
			state.dashing = false
			velocity = dashDirection * Config.DashExitSpeed
		end
	elseif state.sliding then
		slideTimer += dt
		local speed = math.max(velocity.Magnitude - Config.SlideFriction * dt, 0)
		local direction = if velocity.Magnitude > 0 then velocity.Unit else lookDirection()
		if wish ~= Vector3.zero then
			local steered = direction:Lerp(wish, math.clamp(Config.SlideSteer * dt, 0, 1))
			if steered.Magnitude > 1e-3 then
				direction = steered.Unit
			end
		end
		velocity = direction * speed
		local timeUp = slideTimer >= Config.SlideMaxDuration
		if not slideHeld or speed <= Config.SlideEndSpeed or timeUp or not grounded then
			endSlide()
			-- Slid under something low? Stay crouched instead of standing into it
			if grounded and not canStandUp() then
				state.crouching = true
			end
		end
	else
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
		end
		-- Heavy guns (the gatling) slow you down, sprinting too, and more again while it's spinning
		local held = Weapons[player:GetAttribute("Weapon") or ""]
		if held and held.MoveSpeedScale then
			targetSpeed *= held.MoveSpeedScale * (1 - (held.SpinSlow or 0) * state.weaponSpin)
		end
		local speed = velocity.Magnitude

		if grounded then
			if wish ~= Vector3.zero and speed > targetSpeed then
				-- Carrying extra momentum: bleed it off gradually but let the player steer
				local newSpeed = math.max(speed - Config.MomentumFriction * dt, targetSpeed)
				velocity = moveToward(velocity, wish * newSpeed, Config.GroundAccel * dt)
			else
				local accel = if wish == Vector3.zero then Config.GroundDecel else Config.GroundAccel
				velocity = moveToward(velocity, wish * targetSpeed, accel * dt)
			end
		else
			if speed > targetSpeed then
				-- Keep momentum in the air, with some steering
				local newSpeed = math.max(speed - Config.AirDrag * dt, targetSpeed)
				local direction = velocity.Unit
				local steerLocked = os.clock() - state.lastWallJump < Config.WallJumpSteerLock
				if wish ~= Vector3.zero and not steerLocked then
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
	end

	linearVelocity.PlaneVelocity = Vector2.new(velocity.X, velocity.Z)

	-- Crouching and sliding lower the whole character (hitbox included), not just the camera.
	-- Planting / disabling kneels too; barricading and reinforcing are done standing. Lying down
	-- drops it nearly to the floor (other players see the body lie flat: BodyAnimator).
	local interaction = player:GetAttribute("Interaction")
	local kneeling = state.interacting and (interaction == "Plant" or interaction == "Disable")
	local lowered = state.crouching or state.sliding or state.deploying or kneeling or state.prone
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
	humanoid, root, linearVelocity = nil, nil, nil
	velocity = Vector3.zero
	state.sliding = false
	state.dashing = false
	state.crouching = false
	state.prone = false
	state.speed = 0
	state.velocity = Vector3.zero
	heightDrop = 0
	sentLowered = false
	sentProne = false
	jumpBlocked = false
end

local function setupCharacter(character: Model)
	cleanupCharacter()

	local newHumanoid = character:WaitForChild("Humanoid") :: Humanoid
	local newRoot = character:WaitForChild("HumanoidRootPart") :: BasePart
	-- A short hop (Siege-style): Roblox's default 7 studs bonked your head on low ceilings
	newHumanoid.UseJumpPower = false
	newHumanoid.JumpHeight = Config.JumpHeight

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

	table.insert(
		characterConnections,
		newHumanoid.StateChanged:Connect(function(_, newState)
			-- Jumping out of a slide keeps all your speed (slide-hopping); jumping also stands you up
			if newState == Enum.HumanoidStateType.Jumping then
				endSlide()
				state.crouching = false
			end
		end)
	)
	table.insert(characterConnections, newHumanoid.Died:Connect(cleanupCharacter))
end

-- A fresh jump press: up from prone, or a wall jump in the air (keyboard / gamepad here, the
-- phone's jump button through MobileControls)
function MovementController.JumpPressed()
	if state.prone then
		getUp(false)
	else
		tryWallJump()
	end
end

function MovementController.Start()
	Actions.Bind("Sprint", function(_, inputState)
		sprintHeld = inputState == Enum.UserInputState.Begin
		return Enum.ContextActionResult.Pass
	end, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL3)

	-- C / Ctrl: hold to slide while sprinting (letting go ends the slide), otherwise tap to toggle
	-- crouch. Two quick taps: lie down (prone); tap again to come back up to a crouch.
	Actions.Bind("CrouchSlide", function(_, inputState)
		slideHeld = inputState == Enum.UserInputState.Begin
		if inputState ~= Enum.UserInputState.Begin or state.deploying or state.interacting then
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
		elseif state.sprinting or (not isGrounded() and sprintHeld) then
			startSlide()
		elseif state.crouching then
			tryStandUp()
		elseif isGrounded() and not state.sliding then
			state.crouching = true
		end
		return Enum.ContextActionResult.Sink
	end, Enum.KeyCode.C, Enum.KeyCode.LeftControl, Enum.KeyCode.ButtonB)

	Actions.Bind("Dash", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			startDash()
		end
		return Enum.ContextActionResult.Sink
	end, Enum.KeyCode.X, Enum.KeyCode.ButtonL1)

	-- Wall jump on a fresh jump press (the Humanoid ignores jumps while airborne, so no conflict)
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.ButtonA then
			MovementController.JumpPressed()
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
