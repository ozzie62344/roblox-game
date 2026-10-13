-- On-foot pings for your team: MIDDLE MOUSE or T (phones: the PING button) marks whatever is
-- under your crosshair, up to 300 studs away.
--   An enemy: spotted for the whole team just like from a drone (the server's PingService checks
--             they're really in view and hands it to DroneService.SpotFrom).
--   Anything else (wall, floor, gadget, objective...): a marker there for your team, through
--             walls, in your team's colour, with your name and how far away it is. It pops in with
--             a soft blip and shrinks away after a few seconds; each player has at most two up (a new one
--             replaces their oldest). In free roam everyone sees everyone's.
-- Only while you're alive and on foot (not driving a drone, spectating, in the lobby or a menu).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local MatchConfig = require(ReplicatedStorage.Shared.MatchConfig)
local Sounds = require(ReplicatedStorage.Shared.Sounds)
local SoundCache = require(script.Parent.Parent.Audio.SoundCache)
local Actions = require(script.Parent.Parent.Input.Actions)
local state = require(script.Parent.Parent.PlayerState)
local MenuStyle = require(script.Parent.MenuStyle)
local DroneController = require(script.Parent.Parent.Abilities.DroneController)

local PingRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Ping") :: RemoteEvent

local player = Players.LocalPlayer

local TeamPing = {}

local RANGE = 300 -- studs from the camera
local LIFETIME = 6 -- seconds a marker stays up
local POP = 0.25 -- seconds it takes to pop in (and to shrink away at the end)
local MAX_PER_PLAYER = 2
local SPOT_COOLDOWN = 1.5 -- (the server has the same; this just saves the request)
local FREE_ROAM_COLOR = Color3.fromRGB(255, 220, 90)

type Marker = { anchor: Attachment, gui: BillboardGui, step: RBXScriptConnection }

local markers: { [Player]: { Marker } } = {}
local lastSpot = -math.huge

local function remove(marker: Marker)
	marker.step:Disconnect()
	marker.gui:Destroy()
	marker.anchor:Destroy()
end

local function forget(owner: Player, marker: Marker)
	local list = markers[owner]
	local index = list and table.find(list, marker)
	if list and index then
		table.remove(list, index)
		remove(marker)
	end
end

-- All of a player's markers
local function clear(owner: Player)
	local list = markers[owner]
	markers[owner] = nil
	if list then
		for _, marker in list do
			remove(marker)
		end
	end
end

local function teamColor(owner: Player): Color3
	local team = if owner.Team and not owner.Neutral then MatchConfig.Teams[owner.Team.Name] else nil
	return if team then team.Color.Color else FREE_ROAM_COLOR
end

local function blip()
	local sound = SoundCache.New(Sounds.Ping.Id)
	sound.Volume = Sounds.Ping.Volume
	sound.PlaybackSpeed = Sounds.Ping.Pitch
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
end

-- The marker: a diamond pin on the spot, the pinger's name and the distance above it
local function show(owner: Player, position: Vector3)
	local list = markers[owner] or {}
	markers[owner] = list
	while #list >= MAX_PER_PLAYER do
		remove(table.remove(list, 1) :: Marker)
	end

	local color = teamColor(owner)
	local anchor = Instance.new("Attachment")
	anchor.Name = "TeamPing"
	anchor.WorldPosition = position
	anchor.Parent = Workspace.Terrain
	local gui = Instance.new("BillboardGui")
	gui.Name = "TeamPing"
	gui.Adornee = anchor
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = math.huge
	gui.Size = UDim2.fromOffset(140, 70)
	gui.SizeOffset = Vector2.new(0, 0.5) -- (the pin's point sits on the spot)

	local root = Instance.new("Frame")
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Scale = 0
	scale.Parent = root

	local name = MenuStyle.Text(root, string.upper(owner.DisplayName), UDim2.fromOffset(140, 16), UDim2.fromScale(0.5, 0), Vector2.new(0.5, 0))
	name.TextColor3 = color
	local distance = MenuStyle.Text(root, "", UDim2.fromOffset(100, 13), UDim2.fromOffset(70, 17), Vector2.new(0.5, 0))
	-- The pin: a diamond with a white rim, its point on the spot
	local diamond = Instance.new("Frame")
	diamond.AnchorPoint = Vector2.new(0.5, 0.5)
	diamond.Position = UDim2.new(0.5, 0, 1, -16)
	diamond.Size = UDim2.fromOffset(20, 20)
	diamond.Rotation = 45
	diamond.BackgroundColor3 = color
	diamond.BorderSizePixel = 0
	diamond.Parent = root
	MenuStyle.Corner(diamond, UDim.new(0, 3))
	MenuStyle.Rim(diamond, Color3.new(1, 1, 1), 2)
	local dot = Instance.new("Frame")
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(0.5, 0.5)
	dot.Size = UDim2.fromOffset(6, 6)
	dot.BackgroundColor3 = Color3.new(1, 1, 1)
	dot.BorderSizePixel = 0
	dot.Parent = diamond
	gui.Parent = player:WaitForChild("PlayerGui") -- 3D GUIs don't draw inside a ScreenGui

	-- Pops in, and shrinks away at the end
	TweenService:Create(scale, TweenInfo.new(POP, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	blip()
	local born = os.clock()
	local leaving = false
	local marker: Marker
	marker = {
		anchor = anchor,
		gui = gui,
		step = RunService.RenderStepped:Connect(function()
			local age = os.clock() - born
			if age >= LIFETIME then
				forget(owner, marker)
				return
			elseif age >= LIFETIME - POP and not leaving then
				leaving = true
				TweenService:Create(scale, TweenInfo.new(POP, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0 }):Play()
			end
			local away = (Workspace.CurrentCamera.CFrame.Position - position).Magnitude
			distance.Text = `{math.floor(away + 0.5)} STUDS`
		end),
	}
	table.insert(list, marker)
end

local function canPing(): boolean
	if state.inLobby or state.devPanelOpen or state.mouseUnlocked or state.draftOpen or state.voteOpen or state.modsOpen
		or state.droning or state.spectating or state.resultsOpen then
		return false
	end
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

-- The enemy (or practice dummy) this part belongs to, if any
local function enemyOf(part: BasePart): Model?
	local model = part:FindFirstAncestorOfClass("Model")
	while model and not model:FindFirstChildOfClass("Humanoid") do
		model = model:FindFirstAncestorOfClass("Model")
	end
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	if not model or not humanoid or humanoid.Health <= 0 then
		return nil -- (a body: just mark the spot)
	end
	local other = Players:GetPlayerFromCharacter(model)
	if other then
		local enemy = other ~= player and (player.Neutral or other.Team ~= player.Team)
		return if enemy then model else nil
	end
	local dummies = Workspace:FindFirstChild("Dummies")
	return if dummies and model:IsDescendantOf(dummies) then model else nil
end

-- Ping whatever is under the crosshair
function TeamPing.Ping()
	-- (in the drone the ping key does what its click does: spot an enemy or mark the spot)
	if DroneController.IsDriving() then
		DroneController.Spot()
		return
	end
	if not canPing() then
		return
	end
	local camera = Workspace.CurrentCamera.CFrame
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { player.Character :: Model, Workspace.CurrentCamera }
	-- (see-through things like invisible walls don't count: look past them)
	local hit: RaycastResult? = nil
	for _ = 1, 4 do
		params.FilterDescendantsInstances = ignore
		hit = Workspace:Raycast(camera.Position, camera.LookVector * RANGE, params)
		if not hit or hit.Instance.Transparency < 0.95 then
			break
		end
		table.insert(ignore, hit.Instance)
		hit = nil
	end
	if not hit then
		return
	end
	local enemy = enemyOf(hit.Instance)
	if enemy then
		local now = os.clock()
		if now - lastSpot >= SPOT_COOLDOWN then
			lastSpot = now
			PingRemote:FireServer("Spot", enemy)
		end
		return
	end
	-- (a hair off the surface, so the pin isn't half inside it)
	PingRemote:FireServer("Mark", hit.Position + hit.Normal * 0.3)
end

function TeamPing.Start()
	Actions.Bind("Ping", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			TeamPing.Ping()
		end
		return Enum.ContextActionResult.Pass
	end, Enum.UserInputType.MouseButton3, Enum.KeyCode.T)

	PingRemote.OnClientEvent:Connect(function(owner: Player, position: Vector3)
		if typeof(owner) == "Instance" and owner:IsA("Player") and typeof(position) == "Vector3" then
			show(owner, position)
		end
	end)
	-- A new round (or back to free roam): old markers go
	ReplicatedStorage:WaitForChild("MatchState"):GetAttributeChangedSignal("Round"):Connect(function()
		for owner in markers do
			clear(owner)
		end
	end)
	Players.PlayerRemoving:Connect(clear)
end

return TeamPing
