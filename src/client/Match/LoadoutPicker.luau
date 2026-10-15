-- The operator select screen (Siege's), shown during the pre-round freeze (LoadoutService sends
-- the offer). Full screen over a blurred world:
--   Top:    SELECT OPERATOR, the round and your side, and the phase timer (red, ticking, in the
--           last 5 seconds). HIDE (or Left Alt) puts it away; Left Alt / LOADOUT brings it back.
--   Left:   a grid of operator badges for your side (an emblem drawn from the gadget, the name
--           under it). Hover to look, click (or 1-6) to choose; a teammate's operator is darkened
--           with their name on it. Under the grid: the defenders' site / attackers' spawn choice
--           (SitePicker's, so its own row stays hidden while this screen is up).
--   Right:  the chosen operator: emblem, name, role, armor / speed pips, unique gadget, and the
--           loadout (pick the primary here; the knife is everyone's sidearm) with the primary
--           turning slowly in a little viewport.
--   Bottom: YOUR TEAM (who's playing whom, live) and LOCK IN (or Enter, or double-click a badge).
--           After locking in you can still swap until the pick window closes (Draft: the round
--           starting, so through the setup too); anyone who never locks in gets the badge they had
--           chosen when operator selection ends, or a random free one (LoadoutService).
--   Once you've used your gadget (defenders during setup) you're locked in, but can still change guns.
-- Random loadouts: the same screen, read-only, showing who you got while you pick a site / spawn.
-- It goes away when operator selection ends (Prep); Left Alt / LOADOUT reopens it until the round starts.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Abilities = require(ReplicatedStorage.Shared.Abilities)
local Attachments = require(ReplicatedStorage.Shared.Attachments)
local GameRules = require(ReplicatedStorage.Shared.GameRules)
local MatchConfig = require(ReplicatedStorage.Shared.MatchConfig)
local Operators = require(ReplicatedStorage.Shared.Operators)
local Skins = require(ReplicatedStorage.Shared.Skins)
local Sounds = require(ReplicatedStorage.Shared.Sounds)
local Weapons = require(ReplicatedStorage.Shared.Weapons)
local Effects = require(script.Parent.Parent.Combat.Effects)
local GunModels = require(script.Parent.Parent.Combat.GunModels)
local SoundGroups = require(script.Parent.Parent.Audio.SoundGroups)
local state = require(script.Parent.Parent.PlayerState)
local SitePicker = require(script.Parent.SitePicker)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local LoadoutOffer = Remotes:WaitForChild("LoadoutOffer") :: RemoteEvent
local DraftPick = Remotes:WaitForChild("DraftPick") :: RemoteEvent
local MatchState = ReplicatedStorage:WaitForChild("MatchState")

local player = Players.LocalPlayer

local LoadoutPicker = {}

-- Layout (design pixels; the whole screen scales to fit, phones included)
local DESIGN = Vector2.new(1180, 660)
local TOP_H = 78
local BOTTOM_H = 112
local BODY_Y = TOP_H + 14
local BODY_H = DESIGN.Y - BODY_Y - BOTTOM_H - 14
local LEFT_W = 452
local DETAIL_X = LEFT_W + 14
local DETAIL_W = DESIGN.X - DETAIL_X
local TILE, TILE_GAP, NAME_H = 128, 12, 26
local GRID_H = 2 * (TILE + NAME_H) + TILE_GAP -- two rows; more scroll
local VIEW_W, VIEW_H = 300, 196

local WHITE = Color3.fromRGB(245, 245, 240)
local GREY = Color3.fromRGB(165, 170, 180)
local DIM = Color3.fromRGB(95, 98, 106)
local BLACK = Color3.new(0, 0, 0)
local PANEL = Color3.fromRGB(18, 20, 26)
local CHIP = Color3.fromRGB(40, 43, 52)
local GOLD = Color3.fromRGB(255, 190, 60)
local GREEN = Color3.fromRGB(80, 200, 90)
local RED = Color3.fromRGB(255, 70, 60)
local GADGET_COLOR = Color3.fromRGB(120, 190, 255)
local TAKEN_COLOR = Color3.fromRGB(255, 170, 70)
local SIDE_COLOR = { Attack = Color3.fromRGB(255, 140, 50), Defend = Color3.fromRGB(70, 150, 255) }
local SIDE_NAME = { Attack = "ATTACK", Defend = "DEFENSE" }
local PICK_KEYS = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five, Enum.KeyCode.Six }
local CONFIRM_KEYS = { Enum.KeyCode.Return, Enum.KeyCode.KeypadEnter }
local DOUBLE_CLICK = 0.4 -- seconds: a second click on a badge this soon locks it in
local AUTO_LOCK = 0.8 -- seconds before operator selection ends: lock in the badge you chose
local BLUR_SIZE = 14

-- What each gadget makes you (the role line)
local ROLES: { [string]: string } = {
	BreachCharge = "SOFT BREACHER",
	HardBreach = "HARD BREACHER",
	EmpGrenade = "GADGET DENIAL",
	Flashbang = "ENTRY FRAGGER",
	SmokeGrenade = "SUPPORT",
	HeartbeatSensor = "INTEL",
	ShockWire = "ANTI HARD BREACH",
	SignalJammer = "INTEL DENIAL",
	ArmorPanel = "SITE SETUP",
	DeployableCover = "ANCHOR",
	BarbedWire = "TRAPPER",
	ImpactGrenade = "ROAMER",
}

type OfferEntry = { Id: string, Weapons: { string }, TakenBy: string? }
type Offer = {
	Side: string,
	Random: boolean,
	Deadline: number,
	Operators: { OfferEntry },
	Pick: { Operator: string, Weapon: string }?,
	Locked: boolean,
}
type Tile = {
	entry: OfferEntry,
	index: number,
	button: TextButton,
	badge: Frame,
	stroke: UIStroke,
	shade: Frame,
	flash: Frame,
	status: TextLabel,
	you: TextLabel,
	scale: UIScale,
	lastClick: number,
}
type Preview = { model: Model, center: CFrame, distance: number }

-- Screen
local gui: ScreenGui
local root: Frame -- the whole screen (backdrop)
local fit: UIScale
local content: Frame
local hint: TextLabel
local blur: BlurEffect? = nil
-- Top bar
local titleSub: TextLabel
local timerLabel: TextLabel
local timerScale: UIScale
local timerBar: Frame
local phaseLabel: TextLabel
local hideButton: TextButton
-- Grid
local sideLabel: TextLabel
local grid: ScrollingFrame
local tiles: { Tile } = {}
local siteBox: Frame
local siteTitle: TextLabel
local siteRow: Frame
local siteButtons: { [string]: TextButton } = {}
local siteKey = ""
-- Details
local detailBadge: Frame
local detailArt: Frame? = nil
local detailScale: UIScale
local detailFlash: Frame
local detailName: TextLabel
local detailRole: TextLabel
local detailBio: TextLabel
local armorDots: { Frame } = {}
local speedDots: { Frame } = {}
local gadgetName: TextLabel
local gadgetInfo: TextLabel
local primaryRow: Frame
local secondaryChip: TextLabel
local viewport: ViewportFrame
local viewCamera: Camera
local gunTitle: TextLabel
local gunStats: TextLabel
local gunInfo: TextLabel
-- Bottom
local teamRow: Frame
local teamKey = ""
local lockButton: TextButton
local lockStroke: UIStroke
local lockScale: UIScale
local lockMain: TextLabel
local lockSub: TextLabel

-- Round
local offer: Offer? = nil
local deadline = 0
local offeredAt = 0
local isDraft = false
local sawPreRound = false -- operator selection has started this round (MatchState Phase)
local lastPhase: string? = nil
local selected: string? = nil -- operator you're playing (or just locked in, until the server answers)
local focused: string? = nil -- the badge you chose (shown on the right)
local hovered: string? = nil -- the badge under the mouse (shown on the right instead)
local autoLocked = false
local touched = false -- you've chosen a badge yourself this round (only then is it locked in for you)
local teamOps: { [number]: string } = {} -- user id → operator on the team strip (to pop the slots that change)
local chosenGun: { [string]: string } = {} -- the highlighted gun for each operator
local lastPick: { [string]: string } = {} -- side → who you played last time (chosen for you next round)
local keysBound = false
local lastTick = -1
local timerEndsAt = 0
local timerTotal = 1
local shownDetail = "" -- operator + gun on the right, to skip redrawing it
local previews: { [string]: Preview } = {}
local previewModel: Model? = nil
local previewCenter = CFrame.identity

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function stroke(parent: Instance, color: Color3, thickness: number, transparency: number?): UIStroke
	local s = Instance.new("UIStroke")
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Color = color
	s.Thickness = thickness
	s.Transparency = transparency or 0
	s.Parent = parent
	return s
end

local function label(parent: Instance, text: string, size: number, font: Enum.Font, color: Color3, position: UDim2, frameSize: UDim2): TextLabel
	local l = Instance.new("TextLabel")
	l.Position = position
	l.Size = frameSize
	l.BackgroundTransparency = 1
	l.Font = font
	l.TextSize = size
	l.TextColor3 = color
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Top
	l.TextWrapped = true
	l.Text = text
	l.Parent = parent
	return l
end

local function box(parent: Instance, position: UDim2, size: UDim2, color: Color3, transparency: number?): Frame
	local f = Instance.new("Frame")
	f.Position = position
	f.Size = size
	f.BackgroundColor3 = color
	f.BackgroundTransparency = transparency or 0
	f.BorderSizePixel = 0
	f.Parent = parent
	return f
end

local function uiSound(id: string, volume: number, pitch: number)
	Effects.Sound(id, nil, volume, pitch, SoundGroups.UI)
end

-- Grows back to normal size from `from` with a little overshoot
local function pop(scale: UIScale, from: number)
	scale.Scale = from
	TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

local function flash(frame: Frame, strength: number)
	frame.BackgroundTransparency = 1 - strength
	TweenService:Create(frame, TweenInfo.new(0.45), { BackgroundTransparency = 1 }):Play()
end

local function gunName(name: string): string
	local weapon = Weapons[name]
	return string.upper(if weapon then weapon.Name elseif name == GameRules.NoGun then "Knife" else name)
end

-- ─── Emblems ───────────────────────────────────────────────────────────────────
-- Each operator's badge art, drawn from frames in a square box (positions and sizes are fractions
-- of the box, so the same emblem works at any size). Built from the gadget: a lightning bolt for
-- the shock wire, a flame for thermite, a cloud of smoke, and so on.

local function piece(art: Frame, x: number, y: number, w: number, h: number, color: Color3, rotation: number?, round: number?): Frame
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(x, y)
	f.Size = UDim2.fromScale(w, h)
	f.Rotation = rotation or 0
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	if round then
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(round, 0)
		c.Parent = f
	end
	f.Parent = art
	return f
end

-- A bar from (x1, y1) to (x2, y2)
local function bar(art: Frame, x1: number, y1: number, x2: number, y2: number, thickness: number, color: Color3): Frame
	local dx, dy = x2 - x1, y2 - y1
	local length = math.sqrt(dx * dx + dy * dy)
	return piece(art, (x1 + x2) / 2, (y1 + y2) / 2, length + thickness * 0.4, thickness, color, math.deg(math.atan2(dy, dx)))
end

-- Bars through a list of points, with round joints
local function polyline(art: Frame, points: { { number } }, thickness: number, color: Color3)
	for i = 1, #points - 1 do
		bar(art, points[i][1], points[i][2], points[i + 1][1], points[i + 1][2], thickness, color)
	end
	for _, point in points do
		piece(art, point[1], point[2], thickness, thickness, color, 0, 1)
	end
end

local function ring(art: Frame, x: number, y: number, diameter: number, color: Color3, px: number, transparency: number?): Frame
	local f = piece(art, x, y, diameter, diameter, color, 0, 1)
	f.BackgroundTransparency = 1
	stroke(f, color, math.max(1, px * 0.05), transparency)
	return f
end

-- art, main color, cut-out color, the box's size in pixels (for line widths)
type Draw = (art: Frame, w: Color3, d: Color3, px: number) -> ()
local EMBLEMS: { [string]: Draw } = {
	-- A charge on a wall, blowing out at the corners
	BreachCharge = function(art, w, d)
		piece(art, 0.5, 0.5, 0.4, 0.52, w, 0, 0.12)
		piece(art, 0.5, 0.46, 0.16, 0.16, d, 0, 1)
		piece(art, 0.5, 0.64, 0.22, 0.05, d)
		for _, s in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
			local x, y = 0.5 + s[1] * 0.25, 0.5 + s[2] * 0.31
			bar(art, x, y, x + s[1] * 0.09, y + s[2] * 0.09, 0.06, w)
		end
	end,
	-- Thermite: a flame
	HardBreach = function(art, w, d)
		piece(art, 0.5, 0.62, 0.42, 0.42, w, 0, 1)
		piece(art, 0.5, 0.47, 0.297, 0.297, w, 45)
		piece(art, 0.5, 0.69, 0.2, 0.2, d, 0, 1)
		piece(art, 0.5, 0.62, 0.141, 0.141, d, 45)
	end,
	-- EMP: a pulse rippling out
	EmpGrenade = function(art, w, _, px)
		ring(art, 0.5, 0.5, 0.74, w, px, 0.45)
		ring(art, 0.5, 0.5, 0.5, w, px)
		piece(art, 0.5, 0.5, 0.22, 0.22, w, 0, 1)
	end,
	-- Flashbang: a burst of light
	Flashbang = function(art, w)
		piece(art, 0.5, 0.5, 0.3, 0.3, w, 0, 1)
		for i = 0, 7 do
			local angle = math.rad(i * 45)
			local outer = if i % 2 == 0 then 0.4 else 0.33
			bar(art, 0.5 + math.cos(angle) * 0.23, 0.5 + math.sin(angle) * 0.23, 0.5 + math.cos(angle) * outer, 0.5 + math.sin(angle) * outer, 0.06, w)
		end
	end,
	-- Smoke: a cloud
	SmokeGrenade = function(art, w)
		piece(art, 0.34, 0.58, 0.3, 0.3, w, 0, 1)
		piece(art, 0.53, 0.47, 0.38, 0.38, w, 0, 1)
		piece(art, 0.69, 0.6, 0.26, 0.26, w, 0, 1)
		piece(art, 0.51, 0.67, 0.5, 0.12, w, 0, 0.5)
		piece(art, 0.22, 0.76, 0.1, 0.1, w, 0, 1)
	end,
	-- Heartbeat sensor: a pulse line
	HeartbeatSensor = function(art, w)
		polyline(art, { { 0.1, 0.55 }, { 0.32, 0.55 }, { 0.41, 0.3 }, { 0.52, 0.78 }, { 0.6, 0.44 }, { 0.66, 0.55 }, { 0.9, 0.55 } }, 0.07, w)
	end,
	-- Shock wire: a lightning bolt
	ShockWire = function(art, w)
		bar(art, 0.62, 0.1, 0.37, 0.5, 0.13, w)
		bar(art, 0.37, 0.5, 0.64, 0.5, 0.12, w)
		bar(art, 0.64, 0.5, 0.39, 0.9, 0.13, w)
	end,
	-- Signal jammer: an aerial, crossed out
	SignalJammer = function(art, w, d, px)
		ring(art, 0.5, 0.3, 0.34, w, px, 0.35)
		ring(art, 0.5, 0.3, 0.56, w, px, 0.65)
		bar(art, 0.5, 0.34, 0.5, 0.8, 0.07, w)
		bar(art, 0.34, 0.8, 0.66, 0.8, 0.07, w)
		piece(art, 0.5, 0.3, 0.14, 0.14, w, 0, 1)
		local slash = bar(art, 0.18, 0.84, 0.82, 0.16, 0.07, w)
		stroke(slash, d, math.max(1, px * 0.025))
	end,
	-- Armor panel: a riveted steel plate
	ArmorPanel = function(art, w, d)
		piece(art, 0.5, 0.5, 0.54, 0.66, w, 0, 0.06)
		for _, y in { 0.38, 0.5, 0.62 } do
			piece(art, 0.5, y, 0.38, 0.055, d)
		end
		for _, p in { { 0.3, 0.24 }, { 0.7, 0.24 }, { 0.3, 0.76 }, { 0.7, 0.76 } } do
			piece(art, p[1], p[2], 0.05, 0.05, d, 0, 1)
		end
	end,
	-- Deployable cover: a shield
	DeployableCover = function(art, w, d)
		piece(art, 0.5, 0.4, 0.5, 0.32, w, 0, 0.08)
		piece(art, 0.5, 0.55, 0.354, 0.354, w, 45)
		piece(art, 0.5, 0.5, 0.06, 0.42, d)
	end,
	-- Barbed wire: two strands on stakes, with barbs
	BarbedWire = function(art, w)
		bar(art, 0.12, 0.3, 0.12, 0.74, 0.06, w)
		bar(art, 0.88, 0.3, 0.88, 0.74, 0.06, w)
		bar(art, 0.12, 0.42, 0.88, 0.42, 0.05, w)
		bar(art, 0.12, 0.62, 0.88, 0.62, 0.05, w)
		for _, p in { { 0.32, 0.42 }, { 0.68, 0.42 }, { 0.5, 0.62 } } do
			piece(art, p[1], p[2], 0.2, 0.05, w, 45)
			piece(art, p[1], p[2], 0.2, 0.05, w, -45)
		end
	end,
	-- Impact grenade: a grenade with a spark
	ImpactGrenade = function(art, w, d)
		piece(art, 0.48, 0.6, 0.44, 0.44, w, 0, 1)
		piece(art, 0.48, 0.6, 0.44, 0.05, d)
		piece(art, 0.48, 0.36, 0.2, 0.12, w, 0, 0.2)
		bar(art, 0.56, 0.33, 0.68, 0.5, 0.06, w)
		piece(art, 0.74, 0.2, 0.1, 0.1, w, 45)
		bar(art, 0.74, 0.08, 0.74, 0.13, 0.035, w)
		bar(art, 0.86, 0.2, 0.81, 0.2, 0.035, w)
	end,
}

-- Draws `operator`'s emblem filling `parent` (a square about `px` pixels across)
local function emblem(parent: GuiObject, operator: Operators.Operator, px: number): Frame
	local art = Instance.new("Frame")
	art.Name = "Art"
	art.AnchorPoint = Vector2.new(0.5, 0.5)
	art.Position = UDim2.fromScale(0.5, 0.5)
	art.Size = UDim2.fromScale(0.8, 0.8)
	art.BackgroundTransparency = 1
	art.Parent = parent
	local draw = EMBLEMS[operator.Gadget]
	if draw then
		draw(art, WHITE, operator.Color:Lerp(BLACK, 0.62), px * 0.8)
	else
		-- (an operator with a gadget that has no emblem yet: their initial)
		local letter = label(art, string.sub(string.upper(operator.Name), 1, 1), math.floor(px * 0.55), Enum.Font.GothamBlack, WHITE, UDim2.new(), UDim2.fromScale(1, 1))
		letter.TextXAlignment = Enum.TextXAlignment.Center
		letter.TextYAlignment = Enum.TextYAlignment.Center
	end
	return art
end

-- A coloured square badge with `operator`'s emblem (also used on the team strip)
local function badgeFrame(parent: Instance, operator: Operators.Operator?, size: number, position: UDim2): Frame
	local badge = box(parent, position, UDim2.fromOffset(size, size), if operator then operator.Color:Lerp(BLACK, 0.45) else CHIP)
	badge.Name = "Badge"
	corner(badge, math.max(4, math.floor(size * 0.06)))
	local shine = Instance.new("UIGradient")
	shine.Rotation = 90
	shine.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(150, 150, 150))
	shine.Parent = badge
	if operator then
		emblem(badge, operator, size)
	else
		local q = label(badge, "?", math.floor(size * 0.5), Enum.Font.GothamBlack, DIM, UDim2.new(), UDim2.fromScale(1, 1))
		q.TextXAlignment = Enum.TextXAlignment.Center
		q.TextYAlignment = Enum.TextYAlignment.Center
	end
	return badge
end

-- ─── State helpers ─────────────────────────────────────────────────────────────

-- Used a charge of your gadget this round? Then you can't change operator (LoadoutService)
local function locked(): boolean
	if offer and offer.Locked then
		return true
	end
	local ability = Abilities[player:GetAttribute("Ability") or ""]
	local charges = player:GetAttribute("AbilityCharges")
	return ability ~= nil and ability.Charges ~= nil and typeof(charges) == "number" and charges < ability.Charges
end

local function entryFor(id: string?): OfferEntry?
	if not offer or not id then
		return nil
	end
	for _, entry in offer.Operators do
		if entry.Id == id then
			return entry
		end
	end
	return nil
end

-- Can you play `entry` right now? (nil: yes; otherwise why not)
local function blockedReason(entry: OfferEntry): string?
	if entry.TakenBy then
		return "TAKEN"
	elseif not isDraft then
		return if entry.Id == selected then nil else "RANDOM"
	elseif locked() and entry.Id ~= player:GetAttribute("Operator") then
		return "LOCKED"
	end
	return nil
end

-- The gun an operator has highlighted: the one you clicked, the one you're playing them with,
-- the one in your hands if they can take it, or their first
local function gunFor(entry: OfferEntry): string
	local chosen = chosenGun[entry.Id]
	if chosen and table.find(entry.Weapons, chosen) then
		return chosen
	end
	local holding = player:GetAttribute("Weapon")
	if typeof(holding) == "string" and table.find(entry.Weapons, holding) then
		return holding
	end
	return entry.Weapons[1] or GameRules.NoGun
end

local function tileFor(id: string?): Tile?
	for _, tile in tiles do
		if tile.entry.Id == id then
			return tile
		end
	end
	return nil
end

-- ─── Gun preview ───────────────────────────────────────────────────────────────

-- The model for `name` with your skin and attachments on it, built once a round
local function previewFor(name: string): Preview?
	local weapon = Weapons[name]
	local skin = Skins.EquippedFor(player, if weapon then name else "Knife")
	local mods = if weapon then Attachments.For(player, name) else nil
	local key = `{name}:{if skin then skin.Id else ""}:{if mods then Attachments.Key(mods) else ""}`
	local cached = previews[key]
	if cached then
		return cached
	end
	local ok, model = pcall(function(): Model
		return if weapon then GunModels.Build(name, weapon.Look.Color, skin, mods) else GunModels.BuildKnife(skin)
	end)
	if not ok or not model then
		return nil
	end
	local bounds, size = model:GetBoundingBox()
	-- Far enough back that it fits whichever way round it's turned, a little above it
	local tanV = math.tan(math.rad(viewCamera.FieldOfView / 2))
	local long = math.max(size.X, size.Z)
	local distance = math.max(long / 2 / (tanV * VIEW_W / VIEW_H), size.Y / 2 / tanV) * 1.15 + long / 2
	local preview = { model = model, center = CFrame.new(-bounds.Position) * model:GetPivot(), distance = distance }
	previews[key] = preview
	return preview
end

-- Puts `name` in the viewport (nil: empty it)
local function showGun(name: string?)
	local preview = if name then previewFor(name) else nil
	if previewModel and (not preview or preview.model ~= previewModel) then
		previewModel.Parent = nil
		previewModel = nil
	end
	if not preview then
		return
	end
	previewModel = preview.model
	previewCenter = preview.center
	preview.model.Parent = viewport
	viewCamera.CFrame = CFrame.lookAt(Vector3.new(0, preview.distance * 0.22, preview.distance), Vector3.zero)
end

local function clearPreviews()
	for _, preview in previews do
		preview.model:Destroy()
	end
	table.clear(previews)
	previewModel = nil
end

-- ─── Drawing ───────────────────────────────────────────────────────────────────

local refresh: () -> ()
local lockIn: () -> ()

local function setPips(dots: { Frame }, value: number, color: Color3)
	for i, dot in dots do
		dot.BackgroundColor3 = if i <= value then color else CHIP
	end
end

-- The right-hand panel: whoever's under the mouse, or the badge you chose
local function renderDetails()
	local id = hovered or focused
	local entry = entryFor(id)
	local operator = entry and Operators.ById[entry.Id]
	if not entry or not operator then
		shownDetail = ""
		if detailArt then
			detailArt:Destroy()
			detailArt = nil
		end
		for _, child in primaryRow:GetChildren() do
			if child:IsA("TextButton") then
				child:Destroy()
			end
		end
		showGun(nil)
		detailBadge.BackgroundColor3 = CHIP
		detailName.Text = "SELECT AN OPERATOR"
		detailRole.Text = ""
		detailBio.Text = ""
		gadgetName.Text = ""
		gadgetInfo.Text = ""
		gunTitle.Text = ""
		gunStats.Text = ""
		gunInfo.Text = ""
		return
	end
	local gun = gunFor(entry)
	local key = `{entry.Id}:{gun}:{tostring(entry.TakenBy)}:{tostring(selected)}`
	if key == shownDetail then
		return
	end
	local newOperator = string.split(shownDetail, ":")[1] ~= entry.Id
	shownDetail = key

	if newOperator then
		if detailArt then
			detailArt:Destroy()
		end
		detailBadge.BackgroundColor3 = operator.Color:Lerp(BLACK, 0.45)
		detailArt = emblem(detailBadge, operator, 104)
		pop(detailScale, 0.9)
	end
	detailName.Text = string.upper(operator.Name)
	detailName.TextColor3 = WHITE
	detailRole.Text = `{if operator.Side == "Attack" then "ATTACKER" else "DEFENDER"}  ·  {ROLES[operator.Gadget] or "OPERATOR"}`
	detailRole.TextColor3 = operator.Color:Lerp(WHITE, 0.25)
	detailBio.Text = operator.Bio
	setPips(armorDots, operator.Armor or 2, WHITE)
	setPips(speedDots, operator.Speed or 2, WHITE)
	local gadget = Abilities[operator.Gadget]
	if gadget then
		local charges = if gadget.Charges then `  ×{gadget.Charges}` else ""
		gadgetName.Text = `{string.upper(gadget.Name)}{charges}  [{if state.touchControls then "GADGET" else gadget.Key}]`
		gadgetInfo.Text = gadget.Description
	else
		gadgetName.Text = ""
		gadgetInfo.Text = ""
	end

	-- Primary: one button per gun this operator can take in this mode
	for _, child in primaryRow:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
	local choosable = isDraft and blockedReason(entry) == nil
	local count = math.max(#entry.Weapons, 1)
	for i, name in entry.Weapons do
		local on = name == gun
		local button = Instance.new("TextButton")
		button.LayoutOrder = i
		button.Size = UDim2.new(1 / count, -6, 1, 0)
		button.BackgroundColor3 = if on then operator.Color else CHIP
		button.AutoButtonColor = choosable
		button.Font = Enum.Font.GothamBlack
		button.TextSize = 15
		button.TextColor3 = if on then Color3.fromRGB(15, 16, 20) elseif choosable then WHITE else GREY
		button.Text = gunName(name)
		corner(button, 6)
		if on then
			stroke(button, WHITE, 2, 0.3)
		end
		button.Activated:Connect(function()
			if not choosable or name == gunFor(entry) then
				return
			end
			chosenGun[entry.Id] = name
			focused = entry.Id
			touched = true
			uiSound(Sounds.Pick("GunFoley"), 0.45, 1.15)
			-- Already playing them: the new gun goes straight to the server
			if entry.Id == selected then
				DraftPick:FireServer(entry.Id, name)
			end
			refresh()
		end)
		button.Parent = primaryRow
	end
	secondaryChip.Text = `KNIFE  ·  MELEE  [{if state.touchControls then "KNIFE" else "F"}]`

	-- The primary on the right, turning
	showGun(gun)
	local weapon = Weapons[gun]
	gunTitle.Text = gunName(gun)
	if weapon then
		local damage = if weapon.Pellets > 1 then `{weapon.Pellets}×{weapon.Damage}` else tostring(weapon.Damage)
		gunStats.Text = `DMG {damage}   ·   {weapon.RPM} RPM   ·   MAG {weapon.MagazineSize}{if weapon.Chamber > 0 then "+" .. weapon.Chamber else ""}`
		gunInfo.Text = weapon.Description
	else
		gunStats.Text = "MELEE ONLY"
		gunInfo.Text = "No guns this match. One stab kills."
	end
end

local function refreshTiles()
	for _, tile in tiles do
		local entry = tile.entry
		local mine = entry.Id == selected
		local isFocus = entry.Id == focused
		local reason = blockedReason(entry)
		local over = entry.Id == hovered and reason ~= "RANDOM"
		tile.stroke.Thickness = if mine then 5 elseif isFocus then 3 elseif over then 2 else 1
		tile.stroke.Color = if mine then GOLD elseif isFocus or over then WHITE else BLACK
		tile.stroke.Transparency = if mine or isFocus then 0 elseif over then 0.25 else 0.5
		tile.shade.BackgroundTransparency = if reason == "TAKEN" then 0.35 elseif reason then 0.5 else 1
		tile.you.Visible = mine
		tile.status.Visible = reason == "TAKEN" or reason == "LOCKED"
		tile.status.Text = if reason == "TAKEN" then string.upper(entry.TakenBy or "") else "LOCKED"
		tile.status.TextColor3 = if reason == "TAKEN" then TAKEN_COLOR else GREY
		local name = tile.button:FindFirstChild("OperatorName") :: TextLabel?
		if name then
			name.TextColor3 = if mine then GOLD elseif reason then DIM else WHITE
		end
	end
end

-- LOCK IN and what it says
local function refreshLock()
	local entry = entryFor(focused)
	local operator = entry and Operators.ById[entry.Id]
	local main, sub, color, live = "LOCK IN", "", GOLD, true
	if not isDraft then
		main, sub, color, live = "RANDOM OPERATOR", "ASSIGNED FOR THIS ROUND", CHIP, false
	elseif not entry or not operator then
		main, sub, color, live = "SELECT AN OPERATOR", "", CHIP, false
	elseif entry.TakenBy then
		main, sub, color, live = "TAKEN", `BY {string.upper(entry.TakenBy)}`, CHIP, false
	elseif blockedReason(entry) == "LOCKED" then
		main, sub, color, live = "LOCKED", "YOU'VE USED YOUR GADGET THIS ROUND", CHIP, false
	elseif entry.Id == selected then
		main, sub, color, live = "LOCKED IN", "YOU CAN STILL SWAP UNTIL THE ROUND STARTS", GREEN, false
	elseif selected then
		main, sub = `SWAP TO {string.upper(operator.Name)}`, if state.touchControls then "TAP TO CONFIRM" else "ENTER"
	else
		sub = if state.touchControls then "TAP TO CONFIRM" else "ENTER  ·  OR DOUBLE-CLICK A BADGE"
	end
	lockMain.Text = main
	lockSub.Text = sub
	lockButton.BackgroundColor3 = color
	lockButton.AutoButtonColor = live
	lockStroke.Color = color:Lerp(BLACK, 0.55)
	local dark = color == GOLD or color == GREEN
	lockMain.TextColor3 = if dark then Color3.fromRGB(15, 16, 20) else GREY
	lockSub.TextColor3 = if dark then Color3.fromRGB(40, 36, 20) else DIM
end

function refresh()
	if not offer then
		return
	end
	refreshTiles()
	renderDetails()
	refreshLock()
end

-- You chose a badge (click / tap / number key)
local function focus(id: string)
	touched = true
	if focused == id then
		return
	end
	focused = id
	uiSound(Sounds.HitMarker.Id, 0.18, 2.2)
	local tile = tileFor(id)
	if tile then
		pop(tile.scale, 0.94)
	end
	refresh()
end

function lockIn()
	local entry = entryFor(focused)
	if not isDraft or not entry or blockedReason(entry) or entry.Id == selected then
		return
	end
	selected = entry.Id
	if offer then
		lastPick[offer.Side] = entry.Id
	end
	DraftPick:FireServer(entry.Id, gunFor(entry))
	-- Siege's little "thunk": the badge jumps and flashes
	uiSound(Sounds.Shop.Buy, Sounds.Shop.Volume, 1.25)
	uiSound(Sounds.Pick("GunFoley"), 0.5, 1)
	local tile = tileFor(entry.Id)
	if tile then
		pop(tile.scale, 1.18)
		flash(tile.flash, 0.8)
	end
	flash(detailFlash, 0.6)
	pop(lockScale, 1.08)
	refresh()
end

-- ─── Grid ──────────────────────────────────────────────────────────────────────

local function makeTile(index: number, entry: OfferEntry): Tile?
	local operator = Operators.ById[entry.Id]
	if not operator then
		return nil
	end
	local button = Instance.new("TextButton")
	button.LayoutOrder = index
	button.BackgroundTransparency = 1
	button.AutoButtonColor = false
	button.Text = ""
	local scale = Instance.new("UIScale")
	scale.Parent = button

	local badge = badgeFrame(button, operator, TILE, UDim2.new())
	local tileStroke = stroke(badge, BLACK, 1, 0.5)
	local shade = box(badge, UDim2.new(), UDim2.fromScale(1, 1), BLACK, 1)
	shade.ZIndex = 3
	corner(shade, 7)
	local flashFrame = box(badge, UDim2.new(), UDim2.fromScale(1, 1), WHITE, 1)
	flashFrame.ZIndex = 5
	corner(flashFrame, 7)

	-- A teammate's name on their operator, or LOCKED
	local status = label(badge, "", 13, Enum.Font.GothamBlack, TAKEN_COLOR, UDim2.new(0, 0, 1, -26), UDim2.new(1, 0, 0, 22))
	status.BackgroundColor3 = BLACK
	status.BackgroundTransparency = 0.25
	status.TextXAlignment = Enum.TextXAlignment.Center
	status.TextYAlignment = Enum.TextYAlignment.Center
	status.TextTruncate = Enum.TextTruncate.AtEnd
	status.ZIndex = 4
	status.Visible = false
	local you = label(badge, "YOU", 12, Enum.Font.GothamBlack, Color3.fromRGB(15, 16, 20), UDim2.fromOffset(6, 6), UDim2.fromOffset(38, 18))
	you.BackgroundColor3 = GOLD
	you.TextXAlignment = Enum.TextXAlignment.Center
	you.TextYAlignment = Enum.TextYAlignment.Center
	you.ZIndex = 4
	you.Visible = false
	corner(you, 4)
	if isDraft and not state.touchControls and index <= #PICK_KEYS then
		local key = label(badge, tostring(index), 12, Enum.Font.GothamBold, WHITE, UDim2.new(1, -22, 0, 4), UDim2.fromOffset(18, 16))
		key.TextXAlignment = Enum.TextXAlignment.Center
		key.TextTransparency = 0.35
		key.ZIndex = 4
	end

	local name = label(button, string.upper(operator.Name), 16, Enum.Font.GothamBlack, WHITE, UDim2.fromOffset(0, TILE + 4), UDim2.new(1, 0, 0, NAME_H - 6))
	name.Name = "OperatorName"
	name.TextXAlignment = Enum.TextXAlignment.Center

	local tile: Tile = {
		entry = entry,
		index = index,
		button = button,
		badge = badge,
		stroke = tileStroke,
		shade = shade,
		flash = flashFrame,
		status = status,
		you = you,
		scale = scale,
		lastClick = 0,
	}
	button.MouseEnter:Connect(function()
		hovered = entry.Id
		if blockedReason(tile.entry) ~= "RANDOM" then
			TweenService:Create(scale, TweenInfo.new(0.1), { Scale = 1.05 }):Play()
			uiSound(Sounds.HitMarker.Id, 0.06, 3)
		end
		refresh()
	end)
	button.MouseLeave:Connect(function()
		if hovered == entry.Id then
			hovered = nil
		end
		TweenService:Create(scale, TweenInfo.new(0.1), { Scale = 1 }):Play()
		refresh()
	end)
	button.Activated:Connect(function()
		if not isDraft then
			return
		end
		local now = os.clock()
		local again = focused == entry.Id and now - tile.lastClick < DOUBLE_CLICK
		tile.lastClick = now
		focus(entry.Id)
		if again then
			lockIn()
		end
	end)
	button.Parent = grid
	return tile
end

local function buildTiles()
	for _, tile in tiles do
		tile.button:Destroy()
	end
	table.clear(tiles)
	if not offer then
		return
	end
	for i, entry in offer.Operators do
		local tile = makeTile(i, entry)
		if tile then
			table.insert(tiles, tile)
		end
	end
end

-- ─── Team strip / site choice ──────────────────────────────────────────────────

local function teamMembers(): { Player }
	local team = player.Team
	local members = if team then team:GetPlayers() else { player }
	table.sort(members, function(a, b)
		if (a == player) ~= (b == player) then
			return a == player
		end
		return a.DisplayName < b.DisplayName
	end)
	return members
end

-- One slot per teammate: their operator's badge and name, or SELECTING...
local function refreshTeam()
	local members = teamMembers()
	local parts = {}
	for _, member in members do
		table.insert(parts, `{member.UserId}={member:GetAttribute("Operator") or ""}`)
	end
	local key = table.concat(parts, ",")
	if key == teamKey then
		return
	end
	teamKey = key
	for _, child in teamRow:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local width = math.min(196, (800 - (#members - 1) * 10) / math.max(#members, 1))
	for i, member in members do
		local operator = Operators.ById[member:GetAttribute("Operator") or ""]
		local me = member == player
		local slot = box(teamRow, UDim2.new(), UDim2.fromOffset(width, 88), PANEL, 0.1)
		slot.LayoutOrder = i
		corner(slot, 8)
		stroke(slot, if me then GOLD else Color3.fromRGB(60, 64, 76), if me then 2 else 1)
		badgeFrame(slot, operator, 64, UDim2.fromOffset(12, 12))
		local who = label(slot, if me then `{member.DisplayName} (YOU)` else member.DisplayName, 14, Enum.Font.GothamBold, if me then GOLD else WHITE, UDim2.fromOffset(86, 14), UDim2.new(1, -94, 0, 18))
		who.TextTruncate = Enum.TextTruncate.AtEnd
		who.TextWrapped = false
		local playing = label(slot, if operator then string.upper(operator.Name) else "SELECTING...", 17, Enum.Font.GothamBlack, if operator then operator.Color:Lerp(WHITE, 0.2) else DIM, UDim2.fromOffset(86, 36), UDim2.new(1, -94, 0, 22))
		playing.TextTruncate = Enum.TextTruncate.AtEnd
		playing.TextWrapped = false
		if operator then
			label(slot, if isDraft then "LOCKED IN" else "ASSIGNED", 11, Enum.Font.GothamBold, GREEN, UDim2.fromOffset(86, 60), UDim2.new(1, -94, 0, 14))
		end
		-- A teammate just picked: their slot jumps
		local id = if operator then operator.Id else ""
		if teamOps[member.UserId] ~= nil and teamOps[member.UserId] ~= id and operator then
			local slotScale = Instance.new("UIScale")
			slotScale.Parent = slot
			pop(slotScale, 0.9)
		end
		teamOps[member.UserId] = id
	end
end

-- The defenders' site / attackers' spawn (SitePicker's choice, shown here)
local function refreshSite()
	local choice = SitePicker.Current()
	if not choice or #choice.Options == 0 then
		siteBox.Visible = false
		return
	end
	siteBox.Visible = true
	if choice.Key ~= siteKey then
		siteKey = choice.Key
		for _, button in siteButtons do
			button:Destroy()
		end
		table.clear(siteButtons)
		siteTitle.Text = if choice.Kind == "Spawn" then "YOUR SPAWN POINT" else "SITE TO DEFEND  ·  FOR THE TEAM"
		siteTitle.TextColor3 = if choice.Kind == "Spawn" then SIDE_COLOR.Attack else SIDE_COLOR.Defend
		for i, option in choice.Options do
			local button = Instance.new("TextButton")
			button.LayoutOrder = i
			button.Size = UDim2.new(1 / #choice.Options, -6, 1, 0)
			button.BackgroundColor3 = CHIP
			button.Font = Enum.Font.GothamBlack
			button.TextSize = 13
			button.TextColor3 = WHITE
			button.TextWrapped = true
			button.RichText = true
			button.Text = if option.Detail then `{string.upper(option.Id)}\n<font size="10" color="#AAB0BC">{option.Detail}</font>` else string.upper(option.Id)
			corner(button, 6)
			stroke(button, WHITE, 2, 1).Name = "Rim"
			button.Activated:Connect(function()
				uiSound(Sounds.HitMarker.Id, 0.2, 1.8)
				SitePicker.Choose(option.Id)
			end)
			button.Parent = siteRow
			siteButtons[option.Id] = button
		end
	end
	local accent = if choice.Kind == "Spawn" then SIDE_COLOR.Attack else SIDE_COLOR.Defend
	for id, button in siteButtons do
		local on = id == choice.Picked
		button.BackgroundColor3 = if on then accent:Lerp(BLACK, 0.35) else CHIP
		local rim = button:FindFirstChild("Rim") :: UIStroke?
		if rim then
			rim.Transparency = if on then 0 else 1
		end
	end
end

-- ─── Open / close ──────────────────────────────────────────────────────────────

local function setBlur(on: boolean)
	if on and not blur then
		local effect = Instance.new("BlurEffect")
		effect.Name = "OperatorSelectBlur"
		effect.Size = 0
		effect.Parent = Lighting
		blur = effect
		TweenService:Create(effect, TweenInfo.new(0.25), { Size = BLUR_SIZE }):Play()
	elseif not on and blur then
		blur:Destroy()
		blur = nil
	end
end

local function bindKeys(on: boolean)
	if on == keysBound then
		return
	end
	keysBound = on
	if not on then
		ContextActionService:UnbindAction("OperatorSelect")
		return
	end
	local keys = table.clone(PICK_KEYS)
	for _, key in CONFIRM_KEYS do
		table.insert(keys, key)
	end
	ContextActionService:BindAction("OperatorSelect", function(_, inputState, input)
		if inputState == Enum.UserInputState.Begin and isDraft and offer then
			if table.find(CONFIRM_KEYS, input.KeyCode) then
				lockIn()
			else
				local entry = offer.Operators[table.find(PICK_KEYS, input.KeyCode) or 0]
				if entry then
					focus(entry.Id)
				end
			end
		end
		return Enum.ContextActionResult.Sink
	end, false, table.unpack(keys))
end

local function setOpen(open: boolean)
	setBlur(open)
	bindKeys(open)
	if open == root.Visible then
		return
	end
	root.Visible = open
	if open then
		hovered = nil
		shownDetail = ""
		teamKey = ""
		refresh()
		root.BackgroundTransparency = 0.6
		TweenService:Create(root, TweenInfo.new(0.25), { BackgroundTransparency = 0.18 }):Play()
	end
end

-- The pick window is over (the round started): close everything
local function close()
	setOpen(false)
	hint.Visible = false
	state.draftOpen = false
	state.loadoutWindow = false
	if previewModel then
		previewModel.Parent = nil
		previewModel = nil
	end
end

local function onOffer(newOffer: Offer)
	local newRound = newOffer.Deadline ~= deadline
	offer = newOffer
	deadline = newOffer.Deadline
	isDraft = not newOffer.Random
	if newRound then
		offeredAt = Workspace:GetServerTimeNow()
		sawPreRound = MatchState:GetAttribute("Phase") == "PreRound"
		autoLocked = false
		touched = false
		hovered = nil
		focused = nil
		siteKey = ""
		table.clear(chosenGun)
		clearPreviews() -- (skins / attachments may have changed since)
	end
	-- The server's word on who you are (it may have refused a pick: taken a moment ago)
	local before = selected
	selected = if newOffer.Pick then newOffer.Pick.Operator else nil
	if newOffer.Pick then
		chosenGun[newOffer.Pick.Operator] = newOffer.Pick.Weapon
		lastPick[newOffer.Side] = newOffer.Pick.Operator
		-- Handed one (Random, or nobody chosen when selection ended): show them
		if selected ~= before and not touched then
			focused = selected
		end
	end
	-- Start on who you're playing, or who you played last time, or the first one free
	if not entryFor(focused) then
		local remembered = entryFor(lastPick[newOffer.Side])
		if selected then
			focused = selected
		elseif remembered and not remembered.TakenBy then
			focused = remembered.Id
		else
			focused = nil
			for _, entry in newOffer.Operators do
				if not entry.TakenBy then
					focused = entry.Id
					break
				end
			end
		end
	end

	local side = newOffer.Side
	sideLabel.Text = if side == "Attack" then "ATTACKERS" else "DEFENDERS"
	sideLabel.TextColor3 = SIDE_COLOR[side] or WHITE
	if newRound then
		buildTiles()
		shownDetail = ""
	end
	refresh()
	if not newRound then
		return -- a teammate picked: just the badges change (a hidden screen stays hidden)
	end
	-- The screen needs the mouse: MouseUnlock frees it while state.draftOpen is set
	state.loadoutWindow = true
	state.draftOpen = true
end

-- ─── Build ─────────────────────────────────────────────────────────────────────

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "LoadoutPicker"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 5
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Dark over the (blurred) world; Active so clicks don't fall through to the game
	root = box(gui, UDim2.new(), UDim2.fromScale(1, 1), Color3.fromRGB(6, 8, 12), 0.18)
	root.Active = true
	root.Visible = false
	local shade = Instance.new("UIGradient")
	shade.Rotation = 90
	shade.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.25), NumberSequenceKeypoint.new(1, 0) })
	shade.Parent = root

	content = Instance.new("Frame")
	content.AnchorPoint = Vector2.new(0.5, 0.5)
	content.Position = UDim2.fromScale(0.5, 0.5)
	content.Size = UDim2.fromOffset(DESIGN.X, DESIGN.Y)
	content.BackgroundTransparency = 1
	content.Parent = root
	fit = Instance.new("UIScale")
	fit.Parent = content

	-- Top bar: title and round on the left, the timer in the middle, HIDE on the right
	label(content, "SELECT OPERATOR", 36, Enum.Font.GothamBlack, WHITE, UDim2.fromOffset(0, 2), UDim2.fromOffset(420, 42))
	titleSub = label(content, "", 17, Enum.Font.GothamBold, GREY, UDim2.fromOffset(2, 46), UDim2.fromOffset(420, 22))
	titleSub.RichText = true

	timerLabel = label(content, "0:20", 50, Enum.Font.GothamBlack, WHITE, UDim2.new(0.5, -110, 0, -4), UDim2.fromOffset(220, 54))
	timerLabel.TextXAlignment = Enum.TextXAlignment.Center
	timerScale = Instance.new("UIScale")
	timerScale.Parent = timerLabel
	local timerBack = box(content, UDim2.new(0.5, -110, 0, 52), UDim2.fromOffset(220, 4), Color3.fromRGB(45, 48, 56))
	timerBar = box(timerBack, UDim2.new(), UDim2.fromScale(1, 1), WHITE)
	phaseLabel = label(content, "", 12, Enum.Font.GothamBold, GREY, UDim2.new(0.5, -260, 0, 60), UDim2.fromOffset(520, 16))
	phaseLabel.TextXAlignment = Enum.TextXAlignment.Center

	hideButton = Instance.new("TextButton")
	hideButton.AnchorPoint = Vector2.new(1, 0)
	hideButton.Position = UDim2.new(1, 0, 0, 10)
	hideButton.Size = UDim2.fromOffset(150, 44)
	hideButton.BackgroundColor3 = CHIP
	hideButton.Font = Enum.Font.GothamBlack
	hideButton.TextSize = 15
	hideButton.TextColor3 = WHITE
	hideButton.Text = "HIDE  [ALT]"
	corner(hideButton, 6)
	stroke(hideButton, Color3.fromRGB(70, 74, 86), 1)
	hideButton.Activated:Connect(function()
		state.draftOpen = false -- (look around; Left Alt / LOADOUT brings it back)
	end)
	hideButton.Parent = content
	local rule = box(content, UDim2.fromOffset(0, TOP_H - 2), UDim2.new(1, 0, 0, 2), WHITE, 0.6)
	rule.Name = "Rule"

	-- Left: the operator grid, and the site / spawn choice under it
	local left = box(content, UDim2.fromOffset(0, BODY_Y), UDim2.fromOffset(LEFT_W, BODY_H), PANEL, 0.15)
	corner(left, 8)
	sideLabel = label(left, "", 14, Enum.Font.GothamBlack, WHITE, UDim2.fromOffset(16, 10), UDim2.new(1, -32, 0, 18))
	grid = Instance.new("ScrollingFrame")
	grid.Position = UDim2.fromOffset(16, 34)
	grid.Size = UDim2.new(1, -24, 0, GRID_H + 8)
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.ScrollBarThickness = 6
	grid.ScrollingDirection = Enum.ScrollingDirection.Y
	grid.CanvasSize = UDim2.new()
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.Parent = left
	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.fromOffset(TILE, TILE + NAME_H)
	gridLayout.CellPadding = UDim2.fromOffset(TILE_GAP, TILE_GAP)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = grid
	local gridPad = Instance.new("UIPadding")
	gridPad.PaddingTop = UDim.new(0, 4)
	gridPad.PaddingLeft = UDim.new(0, 4)
	gridPad.Parent = grid

	siteBox = box(left, UDim2.new(0, 16, 1, -70), UDim2.new(1, -32, 0, 62), PANEL, 1)
	siteBox.Visible = false
	siteTitle = label(siteBox, "", 12, Enum.Font.GothamBlack, WHITE, UDim2.new(), UDim2.new(1, 0, 0, 16))
	siteRow = box(siteBox, UDim2.fromOffset(0, 18), UDim2.new(1, 6, 0, 44), PANEL, 1)
	local siteLayout = Instance.new("UIListLayout")
	siteLayout.FillDirection = Enum.FillDirection.Horizontal
	siteLayout.SortOrder = Enum.SortOrder.LayoutOrder
	siteLayout.Padding = UDim.new(0, 6)
	siteLayout.Parent = siteRow

	-- Right: the operator in detail
	local details = box(content, UDim2.fromOffset(DETAIL_X, BODY_Y), UDim2.fromOffset(DETAIL_W, BODY_H), PANEL, 0.15)
	corner(details, 8)
	detailBadge = badgeFrame(details, nil, 104, UDim2.fromOffset(16, 16))
	local placeholder = detailBadge:FindFirstChildOfClass("TextLabel")
	if placeholder then
		placeholder:Destroy()
	end
	stroke(detailBadge, WHITE, 2, 0.6)
	detailScale = Instance.new("UIScale")
	detailScale.Parent = detailBadge
	detailFlash = box(detailBadge, UDim2.new(), UDim2.fromScale(1, 1), WHITE, 1)
	detailFlash.ZIndex = 5
	corner(detailFlash, 6)
	detailName = label(details, "", 34, Enum.Font.GothamBlack, WHITE, UDim2.fromOffset(134, 14), UDim2.fromOffset(250, 40))
	detailName.TextScaled = true
	detailRole = label(details, "", 13, Enum.Font.GothamBlack, WHITE, UDim2.fromOffset(134, 56), UDim2.fromOffset(250, 18))
	-- ARMOR ●●○ / SPEED ●○○
	for row, dots in { armorDots, speedDots } do
		local y = 58 + row * 22
		label(details, if row == 1 then "ARMOR" else "SPEED", 12, Enum.Font.GothamBold, GREY, UDim2.fromOffset(134, y), UDim2.fromOffset(60, 16))
		for i = 1, 3 do
			local dot = box(details, UDim2.fromOffset(190 + (i - 1) * 20, y + 1), UDim2.fromOffset(13, 13), CHIP)
			corner(dot, 7)
			dots[i] = dot
		end
	end
	detailBio = label(details, "", 14, Enum.Font.GothamMedium, GREY, UDim2.fromOffset(16, 130), UDim2.fromOffset(370, 38))

	label(details, "UNIQUE GADGET", 11, Enum.Font.GothamBold, DIM, UDim2.fromOffset(16, 176), UDim2.fromOffset(370, 14))
	gadgetName = label(details, "", 18, Enum.Font.GothamBlack, GADGET_COLOR, UDim2.fromOffset(16, 192), UDim2.fromOffset(370, 22))
	gadgetInfo = label(details, "", 13, Enum.Font.GothamMedium, GREY, UDim2.fromOffset(16, 216), UDim2.fromOffset(370, 52))

	label(details, "LOADOUT", 11, Enum.Font.GothamBold, DIM, UDim2.fromOffset(16, 276), UDim2.fromOffset(370, 14))
	label(details, "PRIMARY", 12, Enum.Font.GothamBlack, GREY, UDim2.fromOffset(16, 306), UDim2.fromOffset(90, 16))
	primaryRow = box(details, UDim2.fromOffset(106, 294), UDim2.fromOffset(286, 42), PANEL, 1)
	local primaryLayout = Instance.new("UIListLayout")
	primaryLayout.FillDirection = Enum.FillDirection.Horizontal
	primaryLayout.SortOrder = Enum.SortOrder.LayoutOrder
	primaryLayout.Padding = UDim.new(0, 6)
	primaryLayout.Parent = primaryRow
	label(details, "SECONDARY", 12, Enum.Font.GothamBlack, GREY, UDim2.fromOffset(16, 354), UDim2.fromOffset(90, 16))
	secondaryChip = label(details, "", 13, Enum.Font.GothamBlack, WHITE, UDim2.fromOffset(106, 346), UDim2.fromOffset(280, 32))
	secondaryChip.BackgroundColor3 = CHIP
	secondaryChip.BackgroundTransparency = 0.3
	secondaryChip.TextXAlignment = Enum.TextXAlignment.Center
	secondaryChip.TextYAlignment = Enum.TextYAlignment.Center
	corner(secondaryChip, 6)

	-- The primary, turning slowly
	local stage = box(details, UDim2.new(1, -(VIEW_W + 16), 0, 16), UDim2.fromOffset(VIEW_W, VIEW_H), Color3.fromRGB(30, 33, 42))
	stage.ClipsDescendants = true
	corner(stage, 8)
	local glow = Instance.new("UIGradient")
	glow.Rotation = 90
	glow.Color = ColorSequence.new(Color3.fromRGB(70, 76, 92), Color3.fromRGB(22, 24, 30))
	glow.Parent = stage
	viewport = Instance.new("ViewportFrame")
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.BackgroundTransparency = 1
	viewport.Ambient = Color3.fromRGB(150, 150, 160)
	viewport.LightColor = Color3.fromRGB(255, 250, 240)
	viewport.LightDirection = Vector3.new(-1, -1.4, -0.6)
	viewport.Parent = stage
	viewCamera = Instance.new("Camera")
	viewCamera.FieldOfView = 30
	viewCamera.Parent = viewport
	viewport.CurrentCamera = viewCamera
	gunTitle = label(details, "", 24, Enum.Font.GothamBlack, WHITE, UDim2.new(1, -(VIEW_W + 16), 0, VIEW_H + 24), UDim2.fromOffset(VIEW_W, 28))
	gunStats = label(details, "", 12, Enum.Font.GothamBold, GOLD, UDim2.new(1, -(VIEW_W + 16), 0, VIEW_H + 54), UDim2.fromOffset(VIEW_W, 16))
	gunInfo = label(details, "", 13, Enum.Font.GothamMedium, GREY, UDim2.new(1, -(VIEW_W + 16), 0, VIEW_H + 74), UDim2.fromOffset(VIEW_W, 52))

	-- Bottom: your team, and LOCK IN
	local bottomY = DESIGN.Y - BOTTOM_H
	label(content, "YOUR TEAM", 12, Enum.Font.GothamBlack, GREY, UDim2.fromOffset(0, bottomY), UDim2.fromOffset(300, 16))
	teamRow = box(content, UDim2.fromOffset(0, bottomY + 20), UDim2.fromOffset(800, 88), PANEL, 1)
	local teamLayout = Instance.new("UIListLayout")
	teamLayout.FillDirection = Enum.FillDirection.Horizontal
	teamLayout.SortOrder = Enum.SortOrder.LayoutOrder
	teamLayout.Padding = UDim.new(0, 10)
	teamLayout.Parent = teamRow

	lockButton = Instance.new("TextButton")
	lockButton.AnchorPoint = Vector2.new(1, 0)
	lockButton.Position = UDim2.new(1, 0, 0, bottomY + 20)
	lockButton.Size = UDim2.fromOffset(350, 88)
	lockButton.BackgroundColor3 = GOLD
	lockButton.Text = ""
	corner(lockButton, 8)
	lockStroke = stroke(lockButton, GOLD, 3)
	lockScale = Instance.new("UIScale")
	lockScale.Parent = lockButton
	lockMain = label(lockButton, "LOCK IN", 30, Enum.Font.GothamBlack, BLACK, UDim2.fromOffset(12, 14), UDim2.new(1, -24, 0, 36))
	lockMain.TextXAlignment = Enum.TextXAlignment.Center
	lockMain.TextScaled = true
	lockSub = label(lockButton, "", 12, Enum.Font.GothamBold, BLACK, UDim2.fromOffset(12, 56), UDim2.new(1, -24, 0, 16))
	lockSub.TextXAlignment = Enum.TextXAlignment.Center
	lockButton.Activated:Connect(lockIn)
	lockButton.Parent = content

	-- Shown while the screen is hidden but you can still change your mind
	hint = Instance.new("TextLabel")
	hint.AnchorPoint = Vector2.new(0.5, 0)
	hint.Position = UDim2.new(0.5, 0, 0, 262) -- (under SitePicker's row)
	hint.Size = UDim2.fromOffset(440, 24)
	hint.BackgroundColor3 = Color3.fromRGB(15, 16, 20)
	hint.BackgroundTransparency = 0.35
	hint.Font = Enum.Font.Michroma
	hint.TextSize = 13
	hint.TextColor3 = Color3.fromRGB(255, 200, 90)
	hint.Visible = false
	hint.Parent = gui
end

-- ─── Every frame ───────────────────────────────────────────────────────────────

local function update()
	local now = Workspace:GetServerTimeNow()
	local remaining = deadline - now
	-- Operator selection is over and the setup has started: the screen goes so you can get to
	-- work (Left Alt / LOADOUT still brings it back until the round starts)
	local phase = MatchState:GetAttribute("Phase")
	if phase ~= lastPhase then
		lastPhase = phase
		if phase == "PreRound" and offer then
			sawPreRound = true
		elseif phase == "Prep" then
			state.draftOpen = false
		end
	end
	if not state.loadoutWindow or not offer then
		if root.Visible then
			setOpen(false)
		end
		return
	end
	-- Closed for good: the window ran out, or the round moved on (or the match was called off)
	local over = sawPreRound and phase ~= "PreRound" and phase ~= "Prep"
	if isDraft then
		over = over or remaining <= 0
	else
		-- Random: there's nothing to change, so it's just for the operator selection itself
		over = over or remaining <= 0 or (sawPreRound and phase ~= "PreRound")
			or now - offeredAt > MatchConfig.PreRoundTime + 3
	end
	if over then
		close()
		return
	end

	local inSelection = phase == "PreRound" or not sawPreRound
	local endsAt = if phase == "PreRound" then (MatchState:GetAttribute("PhaseEndsAt") or deadline)
		elseif not sawPreRound then offeredAt + (if isDraft then MatchConfig.DraftTime else MatchConfig.PreRoundTime)
		else deadline
	local left = math.max(0, endsAt - now)

	-- Never locked in but chose someone? They're yours when selection ends (nobody chosen: the
	-- server hands out a random free one)
	if isDraft and phase == "PreRound" and touched and not selected and not autoLocked and left < AUTO_LOCK then
		autoLocked = true
		lockIn()
	end

	setOpen(state.draftOpen)
	hint.Visible = not state.draftOpen
	if not state.draftOpen then
		local how = if state.touchControls then "TAP LOADOUT" else "LEFT ALT"
		hint.Text = `{how}  ·  {if isDraft then "CHANGE OPERATOR" else "SHOW OPERATOR"}  ({math.ceil(if isDraft then remaining else left)}s)`
		return
	end

	-- Fit the screen (phones shrink it; big screens grow it a little), below Roblox's top bar
	local viewSize = Workspace.CurrentCamera.ViewportSize
	local inset = GuiService:GetGuiInset()
	fit.Scale = math.clamp(math.min((viewSize.X - 24) / DESIGN.X, (viewSize.Y - inset.Y - 16) / DESIGN.Y), 0.25, 1.4)
	content.Position = UDim2.new(0.5, 0, 0.5, inset.Y / 2)

	-- Timer: red and ticking for the last five seconds
	if math.abs(endsAt - timerEndsAt) > 0.5 then
		timerEndsAt = endsAt
		timerTotal = math.max(left, 1)
	end
	local whole = math.ceil(left)
	timerLabel.Text = string.format("%d:%02d", whole // 60, whole % 60)
	local urgent = left > 0 and left <= 5
	timerLabel.TextColor3 = if urgent then RED else WHITE
	timerBar.BackgroundColor3 = if urgent then RED else WHITE
	timerBar.Size = UDim2.fromScale(math.clamp(left / timerTotal, 0, 1), 1)
	if urgent and whole ~= lastTick then
		lastTick = whole
		uiSound(Sounds.ChargeBeep.Id, 0.35, if whole <= 1 then 1.9 else 1.5)
		pop(timerScale, 1.15)
	elseif not urgent then
		lastTick = -1
	end

	local side = offer.Side
	local round = MatchState:GetAttribute("Round") or 1
	titleSub.Text = `ROUND {round}  ·  <font color="#{(SIDE_COLOR[side] or WHITE):ToHex()}">{SIDE_NAME[side] or string.upper(side)}</font>`
	phaseLabel.Text = if not isDraft then "RANDOM LOADOUTS  ·  HERE'S WHO YOU GOT"
		elseif inSelection then "OPERATOR SELECTION"
		else "PREPARATION  ·  YOU CAN SWAP UNTIL THE ROUND STARTS"
	hideButton.Text = if state.touchControls then "HIDE" else "HIDE  [ALT]"
	local rule = content:FindFirstChild("Rule") :: Frame?
	if rule then
		rule.BackgroundColor3 = SIDE_COLOR[side] or WHITE
	end

	refreshTeam()
	refreshSite()
	if previewModel then
		previewModel:PivotTo(CFrame.Angles(0, os.clock() * 0.6, 0) * previewCenter)
	end
end

function LoadoutPicker.Start()
	build()
	LoadoutOffer.OnClientEvent:Connect(onOffer)
	RunService.RenderStepped:Connect(update)
	-- Using your gadget during setup locks your operator in: show it straight away
	player:GetAttributeChangedSignal("AbilityCharges"):Connect(function()
		if state.loadoutWindow then
			shownDetail = ""
			refresh()
		end
	end)
	-- Skins / attachments changed (MODS menu): rebuild the preview gun
	for _, attribute in { "EquippedSkins", "Attachments" } do
		player:GetAttributeChangedSignal(attribute):Connect(function()
			if state.loadoutWindow then
				clearPreviews()
				shownDetail = ""
				refresh()
			end
		end)
	end
end

return LoadoutPicker
