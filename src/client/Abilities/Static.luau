-- Glitchy static over a camera feed: flickering noise blocks, tearing bars and drop-outs.
-- DroneController uses it near an enemy Signal Jammer; CamsController when switching cameras or
-- one gets destroyed. Call :Set(strength 0..1, text?) every frame; 0 hides it.

local Static = {}
Static.__index = Static

local COLS, ROWS = 24, 14
local BARS = 6

export type Static = typeof(setmetatable({} :: {
	root: Frame,
	blocks: { Frame },
	bars: { Frame },
	blackout: Frame,
	label: TextLabel,
}, Static))

function Static.new(parent: Instance): Static
	local root = Instance.new("Frame")
	root.Name = "Static"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.ZIndex = 10
	root.Visible = false
	root.Parent = parent

	local blocks = {}
	for row = 0, ROWS - 1 do
		for col = 0, COLS - 1 do
			local block = Instance.new("Frame")
			block.BorderSizePixel = 0
			block.Position = UDim2.fromScale(col / COLS, row / ROWS)
			block.Size = UDim2.fromScale(1 / COLS + 0.002, 1 / ROWS + 0.002) -- (no seams)
			block.ZIndex = 10
			block.Parent = root
			table.insert(blocks, block)
		end
	end
	local bars = {}
	for _ = 1, BARS do
		local bar = Instance.new("Frame")
		bar.BorderSizePixel = 0
		bar.Size = UDim2.fromScale(1, 0.02)
		bar.ZIndex = 11
		bar.Parent = root
		table.insert(bars, bar)
	end
	local blackout = Instance.new("Frame")
	blackout.BorderSizePixel = 0
	blackout.Size = UDim2.fromScale(1, 1)
	blackout.BackgroundColor3 = Color3.new(0, 0, 0)
	blackout.ZIndex = 12
	blackout.Parent = root
	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromOffset(600, 40)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextSize = 30
	label.TextColor3 = Color3.fromRGB(255, 90, 80)
	label.TextStrokeTransparency = 0.3
	label.ZIndex = 13
	label.Parent = root

	return setmetatable({ root = root, blocks = blocks, bars = bars, blackout = blackout, label = label }, Static)
end

function Static.Set(self: Static, strength: number, text: string?)
	strength = math.clamp(strength, 0, 1)
	self.root.Visible = strength > 0.01
	if not self.root.Visible then
		return
	end
	for _, block in self.blocks do
		local grey = math.random()
		block.BackgroundColor3 = Color3.new(grey, grey, grey)
		block.BackgroundTransparency = 1 - strength * (0.25 + 0.6 * math.random())
	end
	for _, bar in self.bars do
		local white = math.random() < 0.5
		bar.BackgroundColor3 = if white then Color3.new(0.9, 0.9, 0.9) else Color3.new(0, 0, 0)
		bar.Position = UDim2.fromScale(0, math.random())
		bar.Size = UDim2.fromScale(1, 0.005 + 0.04 * math.random())
		bar.BackgroundTransparency = 1 - strength * 0.8 * math.random()
	end
	-- The stronger it gets, the more often the whole picture drops out for a frame
	self.blackout.BackgroundTransparency = if math.random() < (strength - 0.5) * 0.6 then 0.1 else 1
	self.label.Text = text or ""
	self.label.TextTransparency = if math.random() < 0.15 then 0.6 else 0 -- (flicker)
end

return Static
