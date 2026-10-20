-- Look of the lobby menus (MainMenu, MapVote): chunky italic text with a dark outline, fat
-- rounded buttons with a darker rim, and little team-colored people on the cards.

local ReplicatedFirst = game:GetService("ReplicatedFirst")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local LoadingScreen = require(ReplicatedFirst:WaitForChild("LoadingScreen"))

local MenuStyle = {}

MenuStyle.Font = LoadingScreen.Font
MenuStyle.Green = Color3.fromRGB(80, 190, 60)
MenuStyle.Red = Color3.fromRGB(215, 60, 55)
MenuStyle.Blue = Color3.fromRGB(45, 110, 230)
MenuStyle.Gold = Color3.fromRGB(255, 190, 60)
MenuStyle.Grey = Color3.fromRGB(120, 124, 135)
MenuStyle.Panel = Color3.fromRGB(24, 26, 32)
MenuStyle.Outline = Color3.fromRGB(18, 18, 22)

function MenuStyle.Corner(parent: Instance, radius: UDim)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius
	corner.Parent = parent
end

function MenuStyle.Rim(parent: Instance, color: Color3, thickness: number): UIStroke
	local rim = Instance.new("UIStroke")
	rim.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	rim.Color = color
	rim.Thickness = thickness
	rim.Parent = parent
	return rim
end

-- White chunky outlined text that fills its box
function MenuStyle.Text(parent: Instance, text: string, size: UDim2, position: UDim2, anchor: Vector2?): TextLabel
	local label = Instance.new("TextLabel")
	label.AnchorPoint = anchor or Vector2.zero
	label.Position = position
	label.Size = size
	label.BackgroundTransparency = 1
	label.FontFace = MenuStyle.Font
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Text = text
	local outline = Instance.new("UIStroke")
	outline.Thickness = 2.5
	outline.Color = MenuStyle.Outline
	outline.Parent = label
	label.Parent = parent
	return label
end

-- A fat rounded button, lighter at the top, that grows a little under the mouse
function MenuStyle.Button(parent: Instance, text: string, color: Color3, size: UDim2, position: UDim2, anchor: Vector2?): TextButton
	local button = Instance.new("TextButton")
	button.AnchorPoint = anchor or Vector2.zero
	button.Position = position
	button.Size = size
	button.AutoButtonColor = false
	button.Text = ""
	button.BackgroundColor3 = color
	MenuStyle.Corner(button, UDim.new(0, 10))
	MenuStyle.Rim(button, color:Lerp(Color3.new(), 0.6), 3).Name = "Rim"
	local shine = Instance.new("UIGradient")
	shine.Rotation = 90
	shine.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(185, 185, 185))
	shine.Parent = button
	MenuStyle.Text(button, text, UDim2.fromScale(0.84, 0.66), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5)).Name = "Label"
	local scale = Instance.new("UIScale")
	scale.Parent = button
	button.MouseEnter:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.12), { Scale = 1.06 }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.12), { Scale = 1 }):Play()
	end)
	button.Parent = parent
	return button
end

-- Recolor a button made by MenuStyle.Button (e.g. greyed out)
function MenuStyle.SetButtonColor(button: TextButton, color: Color3)
	button.BackgroundColor3 = color;
	(button:FindFirstChild("Rim") :: UIStroke).Color = color:Lerp(Color3.new(), 0.6)
end

-- A little person (head + shoulders) standing on `bottom` (scale), centered on `x` (scale)
function MenuStyle.Figure(parent: Instance, color: Color3, x: number, bottom: number, height: number)
	local body = Instance.new("Frame")
	body.AnchorPoint = Vector2.new(0.5, 1)
	body.Position = UDim2.new(x, 0, bottom, 0)
	body.Size = UDim2.fromOffset(height * 0.62, height * 0.56)
	body.BackgroundColor3 = color
	MenuStyle.Corner(body, UDim.new(0.35, 0))
	MenuStyle.Rim(body, Color3.new(1, 1, 1), 2).Transparency = 0.55
	body.Parent = parent
	local head = Instance.new("Frame")
	head.AnchorPoint = Vector2.new(0.5, 1)
	head.Position = UDim2.new(x, 0, bottom, -height * 0.6)
	head.Size = UDim2.fromOffset(height * 0.38, height * 0.38)
	head.BackgroundColor3 = color
	MenuStyle.Corner(head, UDim.new(1, 0))
	MenuStyle.Rim(head, Color3.new(1, 1, 1), 2).Transparency = 0.55
	head.Parent = parent
end

-- A fat green tick (two bars: text check marks render as grey emoji). Named "Check".
function MenuStyle.Check(parent: Instance, position: UDim2): Frame
	local check = Instance.new("Frame")
	check.Name = "Check"
	check.AnchorPoint = Vector2.new(0.5, 0.5)
	check.Position = position
	check.Size = UDim2.fromOffset(36, 36)
	check.BackgroundTransparency = 1
	for _, bar in { { 14, 0.3, 0.62, 45 }, { 30, 0.6, 0.47, -55 } } do
		local stroke = Instance.new("Frame")
		stroke.AnchorPoint = Vector2.new(0.5, 0.5)
		stroke.Size = UDim2.fromOffset(bar[1], 7)
		stroke.Position = UDim2.fromScale(bar[2], bar[3])
		stroke.Rotation = bar[4]
		stroke.BackgroundColor3 = Color3.fromRGB(110, 255, 90)
		MenuStyle.Corner(stroke, UDim.new(1, 0))
		MenuStyle.Rim(stroke, MenuStyle.Outline, 2)
		stroke.Parent = check
	end
	check.Parent = parent
	return check
end

-- Smaller text needs a thinner outline than Text's chunky one
function MenuStyle.ThinOutline(label: TextLabel | TextBox, thickness: number)
	(label:FindFirstChildOfClass("UIStroke") :: UIStroke).Thickness = thickness
end

-- Shrinks `frame` (designed at `designSize` pixels) to fit small screens (phones)
function MenuStyle.FitToScreen(frame: GuiObject, designSize: Vector2)
	local scale = Instance.new("UIScale")
	scale.Parent = frame
	local function fit()
		local viewport = Workspace.CurrentCamera.ViewportSize
		scale.Scale = math.min(1, (viewport.X - 32) / designSize.X, (viewport.Y - 32) / designSize.Y)
	end
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	fit()
end

return MenuStyle
