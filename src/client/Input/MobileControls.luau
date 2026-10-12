-- On-screen buttons for phones and tablets. Each button does exactly what its key does: it runs
-- the same action handler (Actions) or controller function, so every rule (no shooting while
-- deploying, ability charges, cooldowns...) stays where it already is.
--   Playing:    FIRE (STAB in Knives Only; slide the finger holding it to look around while
--               you shoot), AIM (tap on / off), RELOAD, CROUCH (tap crouch, double tap prone,
--               hold while sprinting to slide), KNIFE, your ability (or DASH),
--               LEAN LEFT / RIGHT, DRONE / CAMS, RAPPEL, USE (hold: shows up when there's
--               something to plant, disable, barricade or reinforce), LOADOUT while you can
--               still change it
--   Drone:      the thumbstick drives, dragging looks (TouchLook), HOP, SPOT, EXIT (Roblox hides its
--               jump button while you're in the drone: your body's jumping is switched off)
--   Cameras:    < > switch camera, dragging looks, SPOT, EXIT
--   Spectating: < > who to watch, plus DRONE / CAMS
-- No sprint button: the thumbstick is analog (MovementController), all the way forward sprints.
-- Roblox's own thumbstick and jump button stay; the jump button also wall-jumps, gets you up from
-- prone and pushes off the wall while rappelling. Every button is on the right
-- half of the screen: the left half is the thumbstick's (a thumb landing on a button there
-- wouldn't move you).
-- Showing on touch screens until a key or mouse button is used (a laptop with a touch screen
-- swaps back and forth; moving the mouse alone doesn't count).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Abilities = require(ReplicatedStorage.Shared.Abilities)
local GameRules = require(ReplicatedStorage.Shared.GameRules)
local state = require(script.Parent.Parent.PlayerState)
local Hud = require(script.Parent.Parent.Combat.Hud)
local CamsController = require(script.Parent.Parent.Abilities.CamsController)
local DroneController = require(script.Parent.Parent.Abilities.DroneController)
local MenuStyle = require(script.Parent.Parent.Match.MenuStyle)
local Spectate = require(script.Parent.Parent.Match.Spectate)
local MovementController = require(script.Parent.Parent.Movement.MovementController)
local RappelController = require(script.Parent.Parent.Movement.RappelController)
local Actions = require(script.Parent.Actions)

local player = Players.LocalPlayer

local MobileControls = {}

type Mode = "Play" | "Drone" | "Cams" | "Spectate" | "Other"
type Side = "Right" | "Left" | "Center" | "TopLeft" | "TopCenter"

type Spec = {
	label: string | () -> string,
	side: Side,
	x: number, -- in units (see unit()): the button's center from that side...
	y: number, -- ...and from the bottom (from the top for the Top sides)
	size: number,
	modes: { Mode },
	press: (InputObject) -> (),
	release: ((InputObject) -> ())?,
	visible: (() -> boolean)?, -- extra condition on top of the mode
	on: (() -> boolean)?, -- lit up (toggles that are on, held leans...)
	color: Color3?,
}

local INTERACT_LABELS = {
	Plant = "PLANT",
	Disable = "DISABLE",
	Barricade = "BARRI-\nCADE",
	Unbarricade = "REMOVE",
	Reinforce = "REIN-\nFORCE",
}

local BUTTON = Color3.fromRGB(18, 20, 26)
local LIT = Color3.fromRGB(60, 150, 255)
local FIRE = Color3.fromRGB(190, 45, 45)

local gui: ScreenGui
local buttons: { { spec: Spec, button: TextButton, label: TextLabel, stroke: UIStroke, scale: UIScale } } = {}
local held: { [InputObject]: { spec: Spec, button: TextButton } } = {}
local fireDrags: { [InputObject]: Vector3 } = {} -- fingers on a FIRE button → where they were last frame
local aimOn = false
local fireHolds = 0
local lastJump = 0
local currentMode: Mode? = nil
local touchMode = UserInputService.TouchEnabled

-- Roughly a fingertip: everything is sized in these
local function unit(): number
	local viewport = Workspace.CurrentCamera.ViewportSize
	return math.clamp(math.min(viewport.X, viewport.Y) * 0.115, 36, 72)
end

local function touchActive(): boolean
	return UserInputService.TouchEnabled and touchMode
end

local function act(action: string, begin: boolean)
	Actions.Call(action, if begin then Enum.UserInputState.Begin else Enum.UserInputState.End)
end

-- A key that's held: pressing the button is pressing the key, letting go is letting go
local function hold(action: string): ((InputObject) -> (), (InputObject) -> ())
	return function()
		act(action, true)
	end, function()
		act(action, false)
	end
end

-- A key that's tapped
local function tap(action: string): (InputObject) -> ()
	return function()
		act(action, true)
		act(action, false)
	end
end

local function inMatch(): boolean
	return player:GetAttribute("Location") == "Match"
end

-- Knives Only: no gun, so FIRE stabs and there's nothing to aim or reload
local function hasGun(): boolean
	return player:GetAttribute("Weapon") ~= GameRules.NoGun
end
local function fireLabel(): string
	return if hasGun() then "FIRE" else "STAB"
end

local function setAim(on: boolean)
	if aimOn ~= on then
		aimOn = on
		act("Aim", on)
	end
end

-- Both fire buttons pull the same trigger
local function firePress()
	fireHolds += 1
	if fireHolds == 1 then
		act("Fire", true)
	end
end
local function fireRelease()
	fireHolds = math.max(0, fireHolds - 1)
	if fireHolds == 0 then
		act("Fire", false)
	end
end

-- Z: the defenders' cameras when you're allowed them, otherwise your drone
local function droneOrCams()
	act(if CamsController.IsWatching() or CamsController.Allowed() then "Cams" else "Drone", true)
end

local leanLeftPress, leanLeftRelease = hold("LeanLeft")
local leanRightPress, leanRightRelease = hold("LeanRight")
local crouchPress, crouchRelease = hold("CrouchSlide")
local usePress, useRelease = hold("Interact")

local SPECS: { Spec } = {
	-- Playing: right thumb
	{ label = fireLabel, side = "Right", x = 3.3, y = 1.75, size = 1.9, modes = { "Play" }, press = firePress, release = fireRelease, color = FIRE },
	{
		label = "AIM", side = "Right", x = 5.05, y = 1.0, size = 1.15, modes = { "Play" },
		press = function()
			setAim(not aimOn)
		end,
		on = function()
			return aimOn
		end,
		visible = hasGun,
	},
	{ label = "RELOAD", side = "Right", x = 1.35, y = 2.95, size = 1.05, modes = { "Play" }, press = tap("Reload"), visible = hasGun },
	{
		label = "CROUCH", side = "Right", x = 2.6, y = 3.85, size = 1.05, modes = { "Play" }, press = crouchPress, release = crouchRelease,
		on = function()
			return state.crouching or state.prone or state.sliding
		end,
	},
	{ label = "KNIFE", side = "Right", x = 3.95, y = 3.75, size = 1.0, modes = { "Play" }, press = tap("Melee") },
	{
		label = function()
			local ability = Abilities[player:GetAttribute("Ability") or ""]
			if not ability or ability.Kind ~= "Active" then
				return "DASH"
			end
			local charges = player:GetAttribute("AbilityCharges")
			return string.upper(ability.Name) .. (if typeof(charges) == "number" then `\n{charges}` else "")
		end,
		side = "Right", x = 5.2, y = 2.6, size = 1.1, modes = { "Play" },
		press = function()
			local ability = Abilities[player:GetAttribute("Ability") or ""]
			act(if ability and ability.Kind == "Active" then "UseAbility" else "Dash", true)
		end,
	},
	{
		label = function()
			return "HOLD\n" .. (INTERACT_LABELS[state.interactAction or ""] or "USE")
		end,
		side = "Right", x = 5.45, y = 4.3, size = 1.3, modes = { "Play" }, press = usePress, release = useRelease,
		visible = function()
			return state.interactAction ~= nil or state.interacting
		end,
		color = Color3.fromRGB(200, 120, 30),
	},
	{
		label = "LEAN\nLEFT", side = "Right", x = 2.6, y = 5.25, size = 0.95, modes = { "Play" }, press = leanLeftPress, release = leanLeftRelease,
		on = function()
			return state.lean < -0.3
		end,
	},
	{
		label = "LEAN\nRIGHT", side = "Right", x = 1.35, y = 5.25, size = 0.95, modes = { "Play" }, press = leanRightPress, release = leanRightRelease,
		on = function()
			return state.lean > 0.3
		end,
	},
	{
		label = "RAPPEL", side = "Right", x = 2.6, y = 6.5, size = 0.95, modes = { "Play" }, press = tap("Rappel"),
		on = function()
			return state.rappelling
		end,
	},

	{
		label = "LOADOUT", side = "TopCenter", x = 0, y = 2.6, size = 1.1, modes = { "Play", "Drone" },
		press = function()
			state.draftOpen = true
		end,
		visible = function()
			return state.loadoutWindow and not state.draftOpen
		end,
	},

	{
		label = "HIDE\nCARDS", side = "Center", x = 1.4, y = 0.75, size = 1.0, modes = { "Other" },
		press = function()
			state.draftOpen = false -- (look around during the setup; LOADOUT brings them back)
		end,
		visible = function()
			return state.draftOpen and state.loadoutWindow
		end,
	},

	-- Drone / defender cameras / spectating
	{
		label = function()
			if state.droning then
				return "EXIT"
			end
			return if CamsController.Allowed() then "CAMS" else "DRONE"
		end,
		side = "Right", x = 1.35, y = 6.5, size = 0.95, modes = { "Play", "Drone", "Cams", "Spectate" }, press = droneOrCams,
		visible = inMatch,
	},
	{
		label = "HOP", side = "Right", x = 1.35, y = 1.4, size = 1.3, modes = { "Drone" },
		press = function()
			DroneController.Hop()
		end,
	},
	{
		label = "SPOT", side = "Right", x = 3.3, y = 1.75, size = 1.6, modes = { "Drone", "Cams" },
		press = function()
			if CamsController.IsWatching() then
				CamsController.Spot()
			else
				DroneController.Spot()
			end
		end,
		color = FIRE,
	},
	{
		label = "<", side = "Center", x = 1.3, y = 1.4, size = 1.1, modes = { "Cams", "Spectate" },
		press = function()
			if state.droning then
				CamsController.Cycle(-1)
			else
				Spectate.Cycle(-1)
			end
		end,
	},
	{
		label = ">", side = "Center", x = 2.7, y = 1.4, size = 1.1, modes = { "Cams", "Spectate" },
		press = function()
			if state.droning then
				CamsController.Cycle(1)
			else
				Spectate.Cycle(1)
			end
		end,
	},

	-- Devs: the dev panel (P)
	{
		label = "DEV", side = "Right", x = 5.15, y = 6.5, size = 0.8, modes = { "Play", "Drone", "Cams", "Spectate", "Other" },
		press = tap("ToggleDevPanel"),
		visible = function()
			return player:GetAttribute("IsDev") == true
		end,
		color = Color3.fromRGB(110, 40, 140),
	},
}

local function currentModeNow(): Mode?
	if not touchActive() then
		return nil
	end
	if state.devPanelOpen or state.draftOpen or state.voteOpen or state.shopOpen or state.inLobby then
		return "Other" -- menus are tapped directly
	end
	if state.droning then
		return if CamsController.IsWatching() then "Cams" else "Drone"
	end
	if state.spectating then
		return "Spectate"
	end
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return "Other"
	end
	return "Play"
end

local function layout(entry, u: number)
	local spec = entry.spec
	local size = spec.size * u
	entry.button.Size = UDim2.fromOffset(size, size)
	local x, y = spec.x * u, spec.y * u
	entry.button.Position = if spec.side == "Right" then UDim2.new(1, -x, 1, -y)
		elseif spec.side == "Left" then UDim2.new(0, x, 1, -y)
		elseif spec.side == "Center" then UDim2.new(0.5, x, 1, -y)
		elseif spec.side == "TopLeft" then UDim2.new(0, x, 0, y)
		else UDim2.new(0.5, x, 0, y)
end

local function release(input: InputObject)
	local entry = held[input]
	if not entry then
		return
	end
	held[input] = nil
	fireDrags[input] = nil
	local scale = entry.button:FindFirstChildOfClass("UIScale")
	if scale then
		scale.Scale = 1 -- (pressed buttons shrink a little)
	end
	if entry.spec.release then
		entry.spec.release(input)
	end
end

local function makeButton(spec: Spec, index: number)
	local button = Instance.new("TextButton")
	-- e.g. "FIRE_Right", "AIM_Right", "Button14" (named for finding them in the explorer)
	button.Name = if spec.press == firePress then `FIRE_{spec.side}`
		elseif typeof(spec.label) == "string" then string.gsub(spec.label, "%W", "") .. "_" .. spec.side
		else `Button{index}`
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.AutoButtonColor = false
	button.Text = ""
	button.BackgroundColor3 = spec.color or BUTTON
	button.BackgroundTransparency = 0.35
	button.Visible = false
	MenuStyle.Corner(button, UDim.new(1, 0))
	local stroke = MenuStyle.Rim(button, Color3.new(1, 1, 1), 2)
	stroke.Transparency = 0.45
	local scale = Instance.new("UIScale")
	scale.Parent = button
	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(0.78, 0.5)
	label.BackgroundTransparency = 1
	label.FontFace = MenuStyle.Font
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Text = if typeof(spec.label) == "string" then spec.label else ""
	label.Parent = button
	button.Parent = gui

	button.InputBegan:Connect(function(input)
		local touch = input.UserInputType == Enum.UserInputType.Touch
		local click = input.UserInputType == Enum.UserInputType.MouseButton1 and not UserInputService.TouchEnabled
		if not (touch or click) or held[input] then
			return
		end
		held[input] = { spec = spec, button = button }
		if spec.press == firePress then
			fireDrags[input] = input.Position -- (sliding this finger aims while you shoot)
		end
		scale.Scale = 0.9
		spec.press(input)
	end)
	table.insert(buttons, { spec = spec, button = button, label = label, stroke = stroke, scale = scale })
end

local function update()
	-- A finger that's gone (lifted, or cancelled by the phone, e.g. slid off the screen) is let go
	-- of even if its "ended" event never came, so nothing stays held: a missed release on FIRE
	-- kept the gun shooting by itself
	for input in held do
		if input.UserInputState == Enum.UserInputState.End or input.UserInputState == Enum.UserInputState.Cancel then
			release(input)
		end
	end
	if fireHolds > 0 and next(fireDrags) == nil then
		fireHolds = 1
		fireRelease()
	end

	local mode = currentModeNow()
	if mode ~= currentMode then
		-- Leaving play (died, got in the drone, opened a menu): let go of everything
		if currentMode == "Play" then
			for input in held do
				release(input)
			end
			setAim(false)
		end
		state.touchControls = mode ~= nil
		Hud.SetTouchLayout(mode ~= nil)
		currentMode = mode
	end
	gui.Enabled = mode ~= nil
	if not mode then
		return
	end

	local u = unit()
	for _, entry in buttons do
		local spec = entry.spec
		local visible = table.find(spec.modes, mode) ~= nil and (spec.visible == nil or spec.visible())
		entry.button.Visible = visible
		if not visible then
			continue
		end
		layout(entry, u)
		if typeof(spec.label) == "function" then
			entry.label.Text = spec.label()
		end
		local on = spec.on ~= nil and spec.on()
		entry.button.BackgroundColor3 = if on then LIT else spec.color or BUTTON
		entry.stroke.Transparency = if on then 0 else 0.45
	end
end

function MobileControls.Start()
	gui = Instance.new("ScreenGui")
	gui.Name = "MobileControls"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 4 -- under the menus
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")
	for index, spec in SPECS do
		makeButton(spec, index)
	end

	UserInputService.LastInputTypeChanged:Connect(function(kind)
		if kind == Enum.UserInputType.Touch then
			touchMode = true
		elseif kind == Enum.UserInputType.Keyboard or kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.MouseButton2 or string.find(kind.Name, "Gamepad") then
			touchMode = false
		end
	end)

	-- A finger holding FIRE that slides turns the camera (MouseUnlock applies it like a mouse move)
	UserInputService.TouchMoved:Connect(function(touch)
		local last = fireDrags[touch]
		if last then
			local delta = touch.Position - last
			fireDrags[touch] = touch.Position
			state.lookDrag += Vector2.new(delta.X, delta.Y)
		end
	end)

	-- Letting go anywhere (the finger may slide off the button first)
	UserInputService.InputEnded:Connect(release)
	UserInputService.TouchEnded:Connect(release)

	-- Roblox's jump button: wall jumps, getting up, pushing off while rappelling, drone hops. A
	-- held button asks every frame, so only the first ask after a pause counts as a press.
	UserInputService.JumpRequest:Connect(function()
		local now = os.clock()
		local fresh = now - lastJump > 0.25
		lastJump = now
		if not fresh or not touchActive() then
			return
		end
		if DroneController.IsDriving() then
			DroneController.Hop()
		elseif state.rappelling then
			RappelController.Jump()
		else
			MovementController.JumpPressed()
		end
	end)

	player.CharacterAdded:Connect(function()
		for input in held do
			release(input)
		end
		aimOn, fireHolds = false, 0
		table.clear(fireDrags)
	end)
	RunService.RenderStepped:Connect(update)
end

return MobileControls
