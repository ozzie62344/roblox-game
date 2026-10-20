-- Small questions about players and their characters, asked all over the place.

local Characters = {}

-- `model`'s HumanoidRootPart if it's a living character, else nil
function Characters.AliveRoot(model: Model?): BasePart?
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	local root = model and model:FindFirstChild("HumanoidRootPart") :: BasePart?
	return if humanoid and humanoid.Health > 0 and root then root else nil
end

-- Is `other` against `player`? In a match, the other team; free roaming, everyone but yourself.
function Characters.IsEnemy(player: Player, other: Player): boolean
	return other ~= player and (player.Neutral or other.Neutral or other.Team ~= player.Team)
end

return Characters
