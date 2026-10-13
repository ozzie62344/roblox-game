-- The ranked badge (shared/Ranked): a gem in the tier's colour with the division on it ("II"),
-- a white core for Champion, a grey "?" gem during placements. Made of plain GUI frames, so it
-- scales to any size. Used by the lobby menu (next to RANKED), the in-match scoreboard and the
-- results screen.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Ranked = require(ReplicatedStorage.Shared.Ranked)
local MenuStyle = require(script.Parent.MenuStyle)

local RankBadge = {}

-- A square badge `size` pixels across for this MMR / ranked match count, named "RankBadge"
function RankBadge.New(parent: Instance, size: number, position: UDim2, anchor: Vector2?, mmr: number, matches: number): Frame
	local placed = Ranked.IsPlaced(matches)
	local color = Ranked.ColorFor(mmr, matches)
	local _, _, division = Ranked.TierFor(mmr)

	local holder = Instance.new("Frame")
	holder.Name = "RankBadge"
	holder.AnchorPoint = anchor or Vector2.zero
	holder.Position = position
	holder.Size = UDim2.fromOffset(size, size)
	holder.BackgroundTransparency = 1

	-- The gem: a square on its corner, lighter at the top, with a dark rim
	local gem = Instance.new("Frame")
	gem.AnchorPoint = Vector2.new(0.5, 0.5)
	gem.Position = UDim2.fromScale(0.5, 0.5)
	gem.Size = UDim2.fromScale(0.68, 0.68)
	gem.Rotation = 45
	gem.BackgroundColor3 = color
	gem.Parent = holder
	MenuStyle.Corner(gem, UDim.new(0.18, 0))
	MenuStyle.Rim(gem, color:Lerp(Color3.new(), 0.65), math.max(1, size / 18))
	local shine = Instance.new("UIGradient")
	shine.Rotation = 45 -- (the gem is turned 45°: this runs top to bottom on screen)
	shine.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(150, 150, 150))
	shine.Parent = gem

	if placed and not division then
		-- Champion: a white core in the gem and a ring around it
		local core = Instance.new("Frame")
		core.AnchorPoint = Vector2.new(0.5, 0.5)
		core.Position = UDim2.fromScale(0.5, 0.5)
		core.Size = UDim2.fromScale(0.42, 0.42)
		core.BackgroundColor3 = Color3.new(1, 1, 1)
		core.Parent = gem
		MenuStyle.Corner(core, UDim.new(0.2, 0))
		local ring = Instance.new("Frame")
		ring.AnchorPoint = Vector2.new(0.5, 0.5)
		ring.Position = UDim2.fromScale(0.5, 0.5)
		ring.Size = UDim2.fromScale(0.98, 0.98)
		ring.BackgroundTransparency = 1
		ring.Parent = holder
		MenuStyle.Corner(ring, UDim.new(1, 0))
		MenuStyle.Rim(ring, color, math.max(1, size / 22)).Transparency = 0.2
	else
		local text = MenuStyle.Text(holder, if placed then division :: string else "?", UDim2.fromScale(0.5, 0.36), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
		local outline = text:FindFirstChildOfClass("UIStroke") :: UIStroke
		outline.Thickness = math.max(1, size / 26)
	end
	holder.Parent = parent
	return holder
end

-- The badge for a player, from their attributes (Mmr, RankedMatches)
function RankBadge.ForPlayer(parent: Instance, who: Player, size: number, position: UDim2, anchor: Vector2?): Frame
	local mmr = who:GetAttribute("Mmr")
	local matches = who:GetAttribute("RankedMatches")
	return RankBadge.New(parent, size, position, anchor, if typeof(mmr) == "number" then mmr else Ranked.StartMmr, if typeof(matches) == "number" then matches else 0)
end

return RankBadge
