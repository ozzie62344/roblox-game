-- Outlines your teammates (visible through walls) so you don't mistake them for enemies.
-- Enemies get no outline: you have to spot or hear them.

local Players = game:GetService("Players")

local player = Players.LocalPlayer

local TeamHighlights = {}

local HIGHLIGHT_NAME = "TeammateHighlight"

local function refresh()
	for _, other in Players:GetPlayers() do
		local character = other.Character
		if other == player or not character then
			continue
		end
		local isTeammate = not player.Neutral and player.Team ~= nil and other.Team == player.Team
		local existing = character:FindFirstChild(HIGHLIGHT_NAME) :: Highlight?

		if isTeammate and not existing then
			local highlight = Instance.new("Highlight")
			highlight.Name = HIGHLIGHT_NAME
			highlight.FillTransparency = 1
			highlight.OutlineTransparency = 0.2
			highlight.OutlineColor = (other.Team :: Team).TeamColor.Color
			highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			highlight.Parent = character
		elseif not isTeammate and existing then
			existing:Destroy()
		end
	end
end

function TeamHighlights.Start()
	task.spawn(function()
		while true do
			refresh()
			task.wait(0.5)
		end
	end)
end

return TeamHighlights
