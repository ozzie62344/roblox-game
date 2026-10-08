-- Dev panel (press P). Only shows for players the server marks as devs
-- (anyone in Studio, plus the game owner / DEV_USER_IDS in DevService).

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local state = require(script.Parent.Parent.PlayerState)
local WeaponController = require(script.Parent.Parent.Combat.WeaponController)

local DevAction = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("DevAction") :: RemoteEvent

local player = Players.LocalPlayer

local DevPanel = {}

local ABILITIES = { "None", "Dash", "WallJump" }
local ABILITY_LABELS = { None = "None", Dash = "Dash (F)", WallJump = "Wall Jump (Space on wall)" }

local panel: Frame
local abilityButtons: { [string]: TextButton } = {}

local function button(parent: Instance, text: string, order: number): TextButton
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(1, 0, 0, 32)
	b.LayoutOrder = order
	b.BackgroundColor3 = Color3.fromRGB(45, 48, 56)
	b.BorderSizePixel = 0
	b.Font = Enum.Font.GothamMedium
	b.TextSize = 15
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Text = text
	b.AutoButtonColor = true
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = b
	b.Parent = parent
	return b
end

local function heading(parent: Instance, text: string, order: number)
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(1, 0, 0, 22)
	l.LayoutOrder = order
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextSize = 13
	l.TextColor3 = Color3.fromRGB(160, 165, 175)
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = text
	l.Parent = parent
end

local function refreshAbilityButtons()
	local current = player:GetAttribute("Ability") or "None"
	for name, b in abilityButtons do
		b.BackgroundColor3 = if name == current then Color3.fromRGB(60, 130, 230) else Color3.fromRGB(45, 48, 56)
	end
end

local function setOpen(open: boolean)
	state.devPanelOpen = open
	panel.Visible = open
end

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "DevPanel"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 10
	gui.Parent = player:WaitForChild("PlayerGui")

	panel = Instance.new("Frame")
	panel.Size = UDim2.fromOffset(260, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.Position = UDim2.fromOffset(20, 80)
	panel.BackgroundColor3 = Color3.fromRGB(24, 26, 31)
	panel.BackgroundTransparency = 0.05
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = panel
	local padding = Instance.new("UIPadding")
	for _, side in { "PaddingTop", "PaddingBottom", "PaddingLeft", "PaddingRight" } do
		(padding :: any)[side] = UDim.new(0, 12)
	end
	padding.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = panel

	heading(panel, "DEV PANEL  (P to close)", 0)

	heading(panel, "ABILITY", 1)
	for i, name in ABILITIES do
		local b = button(panel, ABILITY_LABELS[name], 1 + i)
		b.Activated:Connect(function()
			DevAction:FireServer("SetAbility", name)
		end)
		abilityButtons[name] = b
	end

	heading(panel, "TESTING", 10)
	button(panel, "Spawn target dummy", 11).Activated:Connect(function()
		DevAction:FireServer("SpawnDummy")
	end)
	button(panel, "Heal", 12).Activated:Connect(function()
		DevAction:FireServer("Heal")
	end)
	button(panel, "Refill ammo", 13).Activated:Connect(function()
		DevAction:FireServer("RefillAmmo")
		WeaponController.Refill()
	end)
	button(panel, "Clear dummies", 14).Activated:Connect(function()
		DevAction:FireServer("ClearDummies")
	end)

	heading(panel, "MATCH", 15)
	button(panel, "Start match now (works solo)", 16).Activated:Connect(function()
		DevAction:FireServer("StartMatch")
	end)
	button(panel, "End round", 17).Activated:Connect(function()
		DevAction:FireServer("EndRound")
	end)
	button(panel, "Stop match", 18).Activated:Connect(function()
		DevAction:FireServer("StopMatch")
	end)

	-- A visible Modal button frees the mouse from first-person lock while the panel is open
	local close = button(panel, "Close", 20)
	close.Modal = true
	close.BackgroundColor3 = Color3.fromRGB(120, 50, 50)
	close.Activated:Connect(function()
		setOpen(false)
	end)

	player:GetAttributeChangedSignal("Ability"):Connect(refreshAbilityButtons)
	refreshAbilityButtons()
end

function DevPanel.Start()
	build()
	ContextActionService:BindAction("ToggleDevPanel", function(_, inputState)
		if inputState == Enum.UserInputState.Begin and player:GetAttribute("IsDev") then
			setOpen(not panel.Visible)
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.P)
end

return DevPanel
