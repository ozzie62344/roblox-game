-- MODS (M, or the MODS button on a phone): swap the attachments on the gun in your hands, any
-- time, even mid-match. Only ones you own (buy more in the lobby SHOP's MODS view); the server
-- (ShopService "Attach") checks them, and WeaponController swaps the gun when they change. The
-- mouse is free and you can't shoot while it's open.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Attachments = require(ReplicatedStorage.Shared.Attachments)
local Weapons = require(ReplicatedStorage.Shared.Weapons)
local state = require(script.Parent.Parent.PlayerState)
local Actions = require(script.Parent.Parent.Input.Actions)
local MenuStyle = require(script.Parent.MenuStyle)

local Shop = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Shop") :: RemoteEvent

local player = Players.LocalPlayer

local ModsMenu = {}

local CARD = Color3.fromRGB(36, 39, 48)
local GOLD = Color3.fromRGB(255, 196, 60)

local gui: ScreenGui
local panel: Frame
local title: TextLabel
local list: Frame

local function gunName(): string?
	local name = player:GetAttribute("Weapon")
	return if typeof(name) == "string" and Weapons[name] and Attachments.SlotsFor[name] then name else nil
end

-- One row per slot: FACTORY, then every attachment you own that goes in it
local function fill()
	for _, child in list:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local gun = gunName()
	title.Text = if gun then `MODS · {string.upper(gun)}` else "MODS"
	if not gun then
		return
	end
	local slots = Attachments.SlotsFor[gun]
	local chosen = Attachments.For(player, gun)
	local order = 0
	for _, slot in Attachments.Slots do
		if not slots[slot] then
			continue
		end
		order += 1
		local row = Instance.new("Frame")
		row.LayoutOrder = order
		row.Size = UDim2.new(1, 0, 0, 52)
		row.BackgroundTransparency = 1
		row.Parent = list
		local label = MenuStyle.Text(row, Attachments.SlotNames[slot], UDim2.fromOffset(130, 24), UDim2.new(0, 0, 0.5, 0), Vector2.new(0, 0.5))
		label.TextXAlignment = Enum.TextXAlignment.Left
		local options: { { id: string?, name: string } } = { { id = nil, name = "Factory" } }
		for _, attachment in Attachments.List do
			if attachment.Slot == slot and Attachments.Owns(player, attachment.Id) then
				table.insert(options, { id = attachment.Id, name = attachment.Name })
			end
		end
		for i, option in options do
			local on = chosen[slot] == option.id
			local button = Instance.new("TextButton")
			button.AutoButtonColor = true
			button.Text = ""
			button.Position = UDim2.fromOffset(140 + (i - 1) * 124, 4)
			button.Size = UDim2.fromOffset(116, 44)
			button.BackgroundColor3 = if on then Color3.fromRGB(58, 52, 36) else CARD
			MenuStyle.Corner(button, UDim.new(0, 10))
			MenuStyle.Rim(button, if on then GOLD else Color3.fromRGB(60, 64, 76), if on then 3 else 2)
			local text = MenuStyle.Text(button, string.upper(option.name), UDim2.new(1, -12, 0, 22), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
			text.TextColor3 = if on then GOLD else Color3.new(1, 1, 1)
			button.Activated:Connect(function()
				Shop:FireServer("Attach", gun, slot, option.id)
			end)
			button.Parent = row
		end
	end
	local hint = MenuStyle.Text(list, "BUY MORE IN THE LOBBY SHOP · MODS", UDim2.new(1, 0, 0, 20), UDim2.new())
	hint.LayoutOrder = 99
	hint.TextColor3 = Color3.fromRGB(170, 176, 190)
end

function ModsMenu.SetOpen(open: boolean)
	if open and not gunName() then
		return -- (no gun: Knives Only)
	end
	state.modsOpen = open
	panel.Visible = open
	if open then
		fill()
	end
end

function ModsMenu.Toggle()
	ModsMenu.SetOpen(not state.modsOpen)
end

function ModsMenu.Start()
	gui = Instance.new("ScreenGui")
	gui.Name = "Mods"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 7
	gui.Parent = player:WaitForChild("PlayerGui")

	panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(680, 300)
	panel.BackgroundColor3 = MenuStyle.Panel
	panel.BackgroundTransparency = 0.1
	panel.Active = true
	panel.Visible = false
	panel.Parent = gui
	MenuStyle.Corner(panel, UDim.new(0, 14))
	MenuStyle.Rim(panel, Color3.fromRGB(60, 64, 76), 2)
	MenuStyle.FitToScreen(panel, Vector2.new(680, 300))

	title = MenuStyle.Text(panel, "MODS", UDim2.fromOffset(400, 34), UDim2.fromOffset(20, 14))
	title.TextXAlignment = Enum.TextXAlignment.Left
	local close = MenuStyle.Button(panel, "Close", MenuStyle.Red, UDim2.fromOffset(120, 44), UDim2.new(1, -14, 0, 10), Vector2.new(1, 0))
	close.Activated:Connect(function()
		ModsMenu.SetOpen(false)
	end)

	list = Instance.new("Frame")
	list.Position = UDim2.fromOffset(20, 66)
	list.Size = UDim2.new(1, -40, 1, -80)
	list.BackgroundTransparency = 1
	list.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	Actions.Bind("Mods", function(_, inputState)
		if inputState == Enum.UserInputState.Begin and not state.devPanelOpen then
			ModsMenu.Toggle()
		end
		return Enum.ContextActionResult.Sink
	end, Enum.KeyCode.M)

	-- Keep it current: a new gun, or the server swapped the attachment
	for _, attribute in { "Weapon", "Attachments", "OwnedAttachments" } do
		player:GetAttributeChangedSignal(attribute):Connect(function()
			if state.modsOpen then
				if gunName() then
					fill()
				else
					ModsMenu.SetOpen(false)
				end
			end
		end)
	end
	player.CharacterRemoving:Connect(function()
		ModsMenu.SetOpen(false)
	end)
end

return ModsMenu
