-- The BREACH ROULETTE loading screen. ReplicatedFirst/Loading shows it when you join; the lobby's
-- MainMenu also gives it to Roblox as the teleport screen on the way into a match.

local TweenService = game:GetService("TweenService")

local LoadingScreen = {}

LoadingScreen.Font = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy, Enum.FontStyle.Italic)

local TIPS = {
	"Hold G inside a bomb site to plant the defuser",
	"Defenders: hold G in a doorway to barricade it, or on a wall to reinforce it",
	"Double-tap C to go prone and crawl",
	"Press V facing an outside wall to rappel up it",
	"Q / E lean around corners",
	"Every headshot kills (except single shotgun pellets)",
	"Shoot or knife soft walls to open new angles",
	"Attackers: drive your drone with Z to find the bomb site",
}

local function text(parent: Instance, content: string, size: UDim2, y: number): TextLabel
	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, y)
	label.Size = size
	label.BackgroundTransparency = 1
	label.FontFace = LoadingScreen.Font
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.RichText = true
	label.Text = content
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(15, 15, 20)
	stroke.Parent = label
	label.Parent = parent
	return label
end

function LoadingScreen.Build(status: string): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "LoadingScreen"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 100

	-- Red (attackers) fading into blue (defenders)
	local root = Instance.new("CanvasGroup")
	root.Name = "Root"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = Color3.new(1, 1, 1)
	root.Parent = gui
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(90, 18, 22)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(14, 15, 22)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(16, 34, 96)),
	})
	gradient.Rotation = 25
	gradient.Parent = root

	text(root, 'BREACH <font color="#ffb43c">ROULETTE</font>', UDim2.fromScale(0.8, 0.13), 0.4)

	local bar = Instance.new("Frame")
	bar.AnchorPoint = Vector2.new(0.5, 0.5)
	bar.Position = UDim2.fromScale(0.5, 0.56)
	bar.Size = UDim2.new(0.4, 0, 0, 14)
	bar.BackgroundColor3 = Color3.fromRGB(8, 8, 12)
	bar.BackgroundTransparency = 0.3
	bar.Parent = root
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = bar
	local sizeLimit = Instance.new("UISizeConstraint")
	sizeLimit.MinSize = Vector2.new(240, 0)
	sizeLimit.Parent = bar
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Color3.fromRGB(255, 180, 60)
	fill.Parent = bar
	corner:Clone().Parent = fill

	text(root, status, UDim2.new(0.6, 0, 0, 26), 0.62).Name = "Status"
	local tip = text(root, "TIP: " .. TIPS[math.random(#TIPS)], UDim2.new(0.8, 0, 0, 20), 0.92)
	tip.TextColor3 = Color3.fromRGB(205, 210, 220)
	return gui
end

function LoadingScreen.SetProgress(gui: ScreenGui, alpha: number)
	local fill = gui:FindFirstChild("Fill", true) :: Frame
	fill.Size = UDim2.fromScale(math.clamp(alpha, 0, 1), 1)
end

function LoadingScreen.FadeOut(gui: ScreenGui)
	local fade = TweenService:Create(gui:FindFirstChild("Root") :: CanvasGroup, TweenInfo.new(0.6), { GroupTransparency = 1 })
	fade:Play()
	fade.Completed:Wait()
	gui:Destroy()
end

return LoadingScreen
