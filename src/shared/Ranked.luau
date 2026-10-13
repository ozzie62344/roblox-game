-- RANKED: the rules and numbers both sides share. The server (RankedService) works out the
-- ratings; the lobby menu (client MainMenu), the in-match scoreboard, the results screen and the
-- leaderboards use this to show them (client Match/RankBadge draws the badge).
--
-- Who can play: level MinLevel or higher (a party only if every member is). Ranked has its own
-- queues (Matchmaker), so ranked players only ever play ranked players.
-- Rating: everyone has an MMR (starting at StartMmr). After a ranked match it moves Elo-style:
-- your team's average MMR against the other team's gives the chance you were expected to win,
-- and you gain or lose K × (result − expected), plus a small nudge (at most ±PerformanceNudge)
-- for how your match score compares with the match's average. Winners always gain at least 1,
-- losers always lose at least 1. Leaving a ranked match early counts as a loss.
-- Placements: the first Placements matches swing PlacementMultiplier times as much, and no rank
-- shows until they're done ("PLACEMENTS 3/5").
-- Ranks from MMR: Copper → Bronze → Silver → Gold → Platinum → Diamond, each split in three
-- divisions (III is the bottom of the tier, I the top), then Champion (no divisions).
--
-- Player attributes (PlayerData): Mmr, RankedMatches, RankedWins, Rank ("GOLD II", "" while in
-- placements), RankedPlacements (placement matches played, nil once placed).

local Ranked = {}

Ranked.MinLevel = 20
Ranked.StartMmr = 1000
Ranked.Placements = 5
Ranked.K = 32
Ranked.PlacementMultiplier = 1.5
Ranked.PerformanceNudge = 5 -- most MMR your own score can add or take
Ranked.PerformancePoints = 100 -- match score above (below) the average worth +1 (−1): a kill is 100

export type Tier = { Name: string, Min: number, Color: Color3 }

-- Lowest first. Each tier runs from its Min to the next one's; Champion is open-ended.
Ranked.Tiers = {
	{ Name = "Copper", Min = 0, Color = Color3.fromRGB(184, 98, 52) },
	{ Name = "Bronze", Min = 750, Color = Color3.fromRGB(205, 140, 80) },
	{ Name = "Silver", Min = 950, Color = Color3.fromRGB(190, 198, 210) },
	{ Name = "Gold", Min = 1200, Color = Color3.fromRGB(255, 196, 60) },
	{ Name = "Platinum", Min = 1500, Color = Color3.fromRGB(70, 210, 190) },
	{ Name = "Diamond", Min = 1900, Color = Color3.fromRGB(150, 120, 255) },
	{ Name = "Champion", Min = 2400, Color = Color3.fromRGB(255, 80, 120) },
} :: { Tier }

Ranked.PlacementColor = Color3.fromRGB(120, 124, 135)

local DIVISIONS = { "III", "II", "I" }

-- The tier (and its index) for an MMR, and the division ("III", "II", "I"; nil for Champion)
function Ranked.TierFor(mmr: number): (Tier, number, string?)
	local index = 1
	for i, tier in Ranked.Tiers do
		if mmr >= tier.Min then
			index = i
		end
	end
	local tier = Ranked.Tiers[index]
	local nextTier = Ranked.Tiers[index + 1]
	if not nextTier then
		return tier, index, nil
	end
	local step = (nextTier.Min - tier.Min) / #DIVISIONS
	local division = math.clamp(math.floor((mmr - tier.Min) / step) + 1, 1, #DIVISIONS)
	return tier, index, DIVISIONS[division]
end

-- A number that only goes up with the rank (tier, then division): to tell rank-ups from rank-downs
function Ranked.Step(mmr: number): number
	local _, index, division = Ranked.TierFor(mmr)
	return index * 10 + (if division then table.find(DIVISIONS, division) :: number else 0)
end

function Ranked.IsPlaced(matches: number): boolean
	return matches >= Ranked.Placements
end

-- "GOLD II", "CHAMPION"
function Ranked.RankName(mmr: number): string
	local tier, _, division = Ranked.TierFor(mmr)
	return string.upper(tier.Name) .. (if division then " " .. division else "")
end

-- What to show: "GOLD II", or "PLACEMENTS 3/5" until placed
function Ranked.Label(mmr: number, matches: number): string
	if not Ranked.IsPlaced(matches) then
		return `PLACEMENTS {matches}/{Ranked.Placements}`
	end
	return Ranked.RankName(mmr)
end

-- The badge colour (grey until placed)
function Ranked.ColorFor(mmr: number, matches: number): Color3
	if not Ranked.IsPlaced(matches) then
		return Ranked.PlacementColor
	end
	return (Ranked.TierFor(mmr)).Color
end

-- Chance a side rated `mine` beats one rated `theirs` (Elo)
function Ranked.Expected(mine: number, theirs: number): number
	return 1 / (1 + 10 ^ ((theirs - mine) / 400))
end

-- The MMR change for one player: their team's average vs the other's, whether they won, their
-- match score vs the match average, and how many ranked matches they'd played before this one
function Ranked.Change(teamMmr: number, otherMmr: number, won: boolean, score: number, averageScore: number, matchesBefore: number): number
	local expected = Ranked.Expected(teamMmr, otherMmr)
	local nudge = math.clamp((score - averageScore) / Ranked.PerformancePoints, -Ranked.PerformanceNudge, Ranked.PerformanceNudge)
	local change = Ranked.K * ((if won then 1 else 0) - expected) + nudge
	if not Ranked.IsPlaced(matchesBefore) then
		change *= Ranked.PlacementMultiplier
	end
	change = math.floor(change + 0.5)
	return if won then math.max(change, 1) else math.min(change, -1)
end

return Ranked
