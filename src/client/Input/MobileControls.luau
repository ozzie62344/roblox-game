-- On-screen buttons for phones and tablets. Each button does exactly what its key does: it runs
-- the same action handler (Actions) or controller function, so every rule (no shooting while
-- deploying, ability charges, cooldowns...) stays where it already is.
--   Playing:    FIRE (STAB in Knives Only; slide the finger holding it to look around while
--               you shoot), AIM (tap on / off), RELOAD, CROUCH (tap crouch, double tap prone,
--               hold while sprinting to slide), KNIFE, your ability (or DASH),
--               LEAN LEFT / RIGHT, DRONE / CAMS, RAPPEL, USE (hold: shows up when there's
--               something to plant, disable, barricade or reinforce), LOADOUT while you can
--               still change it, MODS, SCORE (the scoreboard), PING (mark for your team),
--               SETTINGS (SettingsMenu; its CONTROLS page can start EDIT BUTTONS too)
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
-- EDIT BUTTONS (top right in the lobby): drag any button anywhere, SMALLER / BIGGER the one you
-- last touched, RESET for the defaults, DONE saves it with your data (SettingsService), so it
-- follows you to every server. The drone's HOP and SPOT sit where you put AIM and FIRE.

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
local ModsMenu = require(script.Parent.Parent.Match.ModsMenu)
local SettingsMenu = require(script.Parent.Parent.Match.SettingsMenu)
local Scoreboard = require(script.Parent.Parent.Match.Scoreboard)
local Spectate = require(script.Parent.Parent.Match.Spectate)
local TeamPing = require(script.Parent.Parent.Match.TeamPing)
local MovementController = require(script.Parent.Parent.Movement.MovementController)
local RappelController = require(script.Parent.Parent.Movement.RappelController)
local Actions = require(script.Parent.Actions)

local HttpService = game:GetService("HttpService")
local SettingsRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Settings") :: RemoteEvent

local player = Players.LocalPlayer

local MobileControls = {}

type Mode = "Play" | "Drone" | "Cams" | "Spectate" | "Other" | "Edit"
type Side = "Right" | "Left" | "Center" | "TopLeft" | "TopCenter" | "TopRight"

type Spec = {
	id: string, -- where its moved spot is kept (EDIT BUTTONS)
	follows: string?, -- sits where this other button was moved (the drone's HOP / SPOT: AIM / FIRE)
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

-- EDIT BUTTONS: where buttons were moved ({ x, y } the middle as a share of the screen, s their
-- size), the one last touched, and the fingers dragging them
type Spot = { x: number, y: number, s: number }
local moved: { [string]: Spot } = {}
local editing = false
local selected: string? = nil
local drags: { [InputObject]: { id: string, button: TextButton, last: Vector3 } } = {}
local editBar: Frame
local dim: Frame

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
	{ id = "Fire", label = fireLabel, side = "Right", x = 2.4, y = 2.0, size = 1.9, modes = { "Play" }, press = firePress, release = fireRelease, color = FIRE },
	{
		id = "Aim", label = "AIM", side = "Right", x = 4.75, y = 1.1, size = 1.2, modes = { "Play" },
		press = function()
			setAim(not aimOn)
		end,
		on = function()
			return aimOn
		end,
		visible = hasGun,
	},
	{ id = "Reload", label = "RELOAD", side = "Right", x = 1.0, y = 4.0, size = 1.05, modes = { "Play" }, press = tap("Reload"), visible = hasGun },
	{
		id = "Crouch", label = "CROUCH", side = "Right", x = 2.6, y = 4.35, size = 1.1, modes = { "Play" }, press = crouchPress, release = crouchRelease,
		on = function()
			return state.crouching or state.prone or state.sliding
		end,
	},
	{ id = "Knife", label = "KNIFE", side = "Right", x = 4.3, y = 3.6, size = 1.0, modes = { "Play" }, press = tap("Melee") },
	{
		label = function()
			local ability = Abilities[player:GetAttribute("Ability") or ""]
			if not ability or ability.Kind ~= "Active" then
				return "DASH"
			end
			local charges = player:GetAttribute("AbilityCharges")
			return string.upper(ability.Name) .. (if typeof(charges) == "number" then `\n{charges}` else "")
		end,
		id = "Ability", side = "Right", x = 6.0, y = 2.7, size = 1.1, modes = { "Play" },
		press = function()
			local ability = Abilities[player:GetAttribute("Ability") or ""]
			act(if ability and ability.Kind == "Active" then "UseAbility" else "Dash", true)
		end,
	},
	{
		label = function()
			return "HOLD\n" .. (INTERACT_LABELS[state.interactAction or ""] or "USE")
		end,
		id = "Use", side = "Right", x = 6.2, y = 4.6, size = 1.3, modes = { "Play" }, press = usePress, release = useRelease,
		visible = function()
			return state.interactAction ~= nil or state.interacting
		end,
		color = Color3.fromRGB(200, 120, 30),
	},
	{
		id = "LeanLeft", label = "LEAN\nLEFT", side = "Right", x = 3.15, y = 6.0, size = 0.95, modes = { "Play" }, press = leanLeftPress, release = leanLeftRelease,
		on = function()
			return state.lean < -0.3
		end,
	},
	{
		id = "LeanRight", label = "LEAN\nRIGHT", side = "Right", x = 1.6, y = 6.0, size = 0.95, modes = { "Play" }, press = leanRightPress, release = leanRightRelease,
		on = function()
			return state.lean > 0.3
		end,
	},
	{
		id = "Rappel", label = "RAPPEL", side = "Right", x = 4.6, y = 5.7, size = 0.95, modes = { "Play" }, press = tap("Rappel"),
		on = function()
			return state.rappelling
		end,
	},

	{
		id = "Loadout", label = "LOADOUT", side = "TopCenter", x = 0, y = 2.6, size = 1.1, modes = { "Play", "Drone" },
		press = function()
			state.draftOpen = true
		end,
		visible = function()
			return state.loadoutWindow and not state.draftOpen
		end,
	},

	{
		id = "HideCards", label = "HIDE\nCARDS", side = "Center", x = 1.4, y = 0.75, size = 1.0, modes = { "Other" },
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
		id = "Drone", side = "Right", x = 6.2, y = 6.4, size = 0.95, modes = { "Play", "Drone", "Cams", "Spectate" }, press = droneOrCams,
		visible = inMatch,
	},
	{
		id = "Hop", follows = "Aim", label = "HOP", side = "Right", x = 4.75, y = 1.1, size = 1.3, modes = { "Drone" },
		press = function()
			DroneController.Hop()
		end,
	},
	{
		id = "Spot", follows = "Fire", label = "SPOT", side = "Right", x = 2.4, y = 2.0, size = 1.6, modes = { "Drone", "Cams" },
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
		id = "Previous", label = "<", side = "Center", x = 1.3, y = 1.4, size = 1.1, modes = { "Cams", "Spectate" },
		press = function()
			if state.droning then
				CamsController.Cycle(-1)
			else
				Spectate.Cycle(-1)
			end
		end,
	},
	{
		id = "Next", label = ">", side = "Center", x = 2.7, y = 1.4, size = 1.1, modes = { "Cams", "Spectate" },
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
		id = "Dev", label = "DEV", side = "Right", x = 6.6, y = 0.9, size = 0.8, modes = { "Play", "Drone", "Cams", "Spectate", "Other" },
		press = tap("ToggleDevPanel"),
		visible = function()
			return player:GetAttribute("IsDev") == true
		end,
		color = Color3.fromRGB(110, 40, 140),
	},

	-- Swap attachments mid-match (ModsMenu)
	{
		id = "Mods", label = "MODS", side = "TopRight", x = 1.3, y = 1.0, size = 0.95, modes = { "Play" },
		press = function()
			ModsMenu.Toggle()
		end,
		visible = hasGun,
	},

	-- The scoreboard (Tab): tap to show, tap again (or the board) to hide. Left of MODS.
	{
		id = "Score", label = "SCORE", side = "TopRight", x = 2.45, y = 1.0, size = 0.8, modes = { "Play", "Spectate" },
		press = function()
			Scoreboard.Toggle()
		end,
		on = Scoreboard.IsOpen,
	},
	-- Ping what's under the crosshair for your team (middle mouse / T). Left of SCORE.
	{
		id = "Ping", label = "PING", side = "TopRight", x = 3.55, y = 1.0, size = 0.8, modes = { "Play" },
		press = function()
			TeamPing.Ping()
		end,
		color = Color3.fromRGB(40, 110, 90),
	},

	-- The SETTINGS menu (in the lobby it has its own button). Left of PING.
	{
		id = "Settings", label = "SET-\nTINGS", side = "TopRight", x = 4.65, y = 1.0, size = 0.8, modes = { "Play", "Drone", "Cams", "Spectate" },
		press = function()
			SettingsMenu.Toggle()
		end,
		color = Color3.fromRGB(70, 76, 92),
	},

	-- Lobby: move the buttons around
	{
		id = "EditButtons", label = "EDIT\nBUTTONS", side = "TopRight", x = 1.4, y = 1.0, size = 1.1, modes = { "Other" },
		press = function()
			editing = true
		end,
		visible = function()
			return state.inLobby and not (state.shopOpen or state.modesOpen or state.devPanelOpen or (state :: any).partyOpen)
		end,
		color = Color3.fromRGB(40, 90, 160),
	},
}

local function currentModeNow(): Mode?
	if not touchActive() then
		return nil
	end
	if editing then
		return "Edit"
	end
	if state.devPanelOpen or state.draftOpen or state.voteOpen or state.shopOpen or state.modsOpen or state.settingsOpen or state.inLobby
		or state.resultsOpen or state.killCam ~= nil then
		return "Other" -- menus are tapped directly (the kill cam and match results have their own buttons)
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
	local spot = moved[spec.follows or spec.id]
	local size = spec.size * u * (if spot then spot.s else 1)
	entry.button.Size = UDim2.fromOffset(size, size)
	if spot then
		entry.button.Position = UDim2.fromScale(spot.x, spot.y)
		return
	end
	local x, y = spec.x * u, spec.y * u
	entry.button.Position = if spec.side == "Right" then UDim2.new(1, -x, 1, -y)
		elseif spec.side == "Left" then UDim2.new(0, x, 1, -y)
		elseif spec.side == "Center" then UDim2.new(0.5, x, 1, -y)
		elseif spec.side == "TopLeft" then UDim2.new(0, x, 0, y)
		elseif spec.side == "TopRight" then UDim2.new(1, -x, 0, y)
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
		if editing then
			selected = spec.id
			drags[input] = { id = spec.id, button = button, last = input.Position }
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

-- Where a button is now, as a moved spot (the middle as a share of the screen)
local function spotOf(button: TextButton): Spot
	local middle = button.AbsolutePosition + button.AbsoluteSize / 2 - gui.AbsolutePosition
	return { x = middle.X / gui.AbsoluteSize.X, y = middle.Y / gui.AbsoluteSize.Y, s = 1 }
end

-- The saved layout (PlayerData's TouchLayout attribute), unless you're in the middle of editing
local function loadLayout()
	if editing then
		return
	end
	table.clear(moved)
	local json = player:GetAttribute("TouchLayout")
	if typeof(json) ~= "string" or json == "" then
		return
	end
	local ok, decoded = pcall(HttpService.JSONDecode, HttpService, json)
	if not ok or typeof(decoded) ~= "table" then
		return
	end
	for id, spot in decoded do
		if typeof(spot) == "table" and typeof(spot.x) == "number" and typeof(spot.y) == "number" then
			moved[id] = { x = spot.x, y = spot.y, s = if typeof(spot.s) == "number" then spot.s else 1 }
		end
	end
end

-- EDIT BUTTONS from elsewhere (SettingsMenu → CONTROLS)
function MobileControls.EditButtons()
	editing = true
end

local function finishEditing()
	editing = false
	selected = nil
	table.clear(drags)
	SettingsRemote:FireServer("TouchLayout", if next(moved) then HttpService:JSONEncode(moved) else "")
end

-- SMALLER / BIGGER: the button last touched
local function resizeSelected(by: number)
	for _, entry in buttons do
		if entry.spec.id == selected and entry.button.Visible then
			local spot = moved[entry.spec.id] or spotOf(entry.button)
			spot.s = math.clamp(spot.s + by, 0.5, 2)
			moved[entry.spec.id] = spot
			return
		end
	end
end

-- The bar of controls on top while editing, over a dimmed screen (so nothing under it takes taps)
local function buildEditBar()
	dim = Instance.new("Frame")
	dim.Name = "EditDim"
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 0.55
	dim.BorderSizePixel = 0
	dim.Active = true
	dim.ZIndex = 0
	dim.Visible = false
	dim.Parent = gui

	editBar = Instance.new("Frame")
	editBar.Name = "EditBar"
	editBar.AnchorPoint = Vector2.new(0.5, 0)
	editBar.Position = UDim2.new(0.5, 0, 0, 6)
	editBar.Size = UDim2.fromOffset(470, 84)
	editBar.BackgroundTransparency = 1
	editBar.ZIndex = 5
	editBar.Visible = false
	editBar.Parent = gui
	local hint = Instance.new("TextLabel")
	hint.Size = UDim2.new(1, 0, 0, 26)
	hint.BackgroundTransparency = 1
	hint.FontFace = MenuStyle.Font
	hint.TextScaled = true
	hint.TextColor3 = Color3.new(1, 1, 1)
	hint.Text = "Drag a button to move it · SMALLER / BIGGER: the last one you touched"
	hint.ZIndex = 5
	hint.Parent = editBar
	local row = Instance.new("Frame")
	row.Position = UDim2.fromOffset(0, 34)
	row.Size = UDim2.new(1, 0, 0, 46)
	row.BackgroundTransparency = 1
	row.ZIndex = 5
	row.Parent = editBar
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Padding = UDim.new(0, 10)
	list.Parent = row
	for _, control in {
		{ "SMALLER", function() resizeSelected(-0.1) end },
		{ "BIGGER", function() resizeSelected(0.1) end },
		{ "RESET", function() table.clear(moved) end },
		{ "DONE", finishEditing },
	} do
		local b = Instance.new("TextButton")
		b.Size = UDim2.fromOffset(104, 46)
		b.BackgroundColor3 = if control[1] == "DONE" then Color3.fromRGB(50, 150, 70) else BUTTON
		b.BackgroundTransparency = 0.1
		b.AutoButtonColor = true
		b.FontFace = MenuStyle.Font
		b.TextScaled = true
		b.TextColor3 = Color3.new(1, 1, 1)
		b.Text = control[1]
		b.ZIndex = 5
		MenuStyle.Corner(b, UDim.new(0, 10))
		local padding = Instance.new("UIPadding")
		padding.PaddingTop = UDim.new(0, 10)
		padding.PaddingBottom = UDim.new(0, 10)
		padding.Parent = b
		b.Activated:Connect(control[2])
		b.Parent = row
	end
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
	-- Editing: above the lobby menus, everything else dimmed
	gui.DisplayOrder = if mode == "Edit" then 40 else 4
	dim.Visible = mode == "Edit"
	editBar.Visible = mode == "Edit"
	if not mode then
		return
	end
	for input in drags do
		if input.UserInputState == Enum.UserInputState.End or input.UserInputState == Enum.UserInputState.Cancel then
			drags[input] = nil
		end
	end

	local u = unit()
	for _, entry in buttons do
		local spec = entry.spec
		local visible = if mode == "Edit"
			then table.find(spec.modes, "Play") ~= nil and (spec.id ~= "Dev" or player:GetAttribute("IsDev") == true)
			else table.find(spec.modes, mode) ~= nil and (spec.visible == nil or spec.visible())
		entry.button.Visible = visible
		if not visible then
			continue
		end
		layout(entry, u)
		if typeof(spec.label) == "function" then
			entry.label.Text = spec.label()
		end
		if mode == "Edit" then
			-- (the one SMALLER / BIGGER changes is outlined)
			local picked = spec.id == selected
			entry.button.BackgroundColor3 = spec.color or BUTTON
			entry.stroke.Color = if picked then Color3.fromRGB(255, 210, 60) else Color3.new(1, 1, 1)
			entry.stroke.Transparency = if picked then 0 else 0.45
			continue
		end
		local on = spec.on ~= nil and spec.on()
		entry.button.BackgroundColor3 = if on then LIT else spec.color or BUTTON
		entry.stroke.Color = Color3.new(1, 1, 1)
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
	buildEditBar()
	loadLayout()
	player:GetAttributeChangedSignal("TouchLayout"):Connect(loadLayout)

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
		-- EDIT BUTTONS: the button under this finger follows it (kept on screen)
		local drag = drags[touch]
		if drag then
			local delta = touch.Position - drag.last
			drag.last = touch.Position
			local spot = moved[drag.id] or spotOf(drag.button)
			spot.x = math.clamp(spot.x + delta.X / gui.AbsoluteSize.X, 0.02, 0.98)
			spot.y = math.clamp(spot.y + delta.Y / gui.AbsoluteSize.Y, 0.02, 0.98)
			moved[drag.id] = spot
		end
	end)

	-- Letting go anywhere (the finger may slide off the button first)
	local function letGo(input: InputObject)
		drags[input] = nil
		release(input)
	end
	UserInputService.InputEnded:Connect(letGo)
	UserInputService.TouchEnded:Connect(letGo)

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
