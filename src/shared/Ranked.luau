-- RANKED: the rules and numbers both sides share. The server (RankedService) works out the
-- ratings; the lobby menu (client MainMenu), the in-match scoreboard, the results screen and the
-- leaderboards use this to show them (client Match/RankBadge draws the badge).
--
-- Who can play: level MinLevel or higher (a party only if every member is). Ranked has its own
-- queues (Matchmaker), so ranked players only ever play ranked players.
-- Rating: everyone has an MMR (starting at StartMmr). After a ranked match it moves in two parts:
--   Result: Elo-style. Your team's average MMR against the other team's gives the chance you
--     were expected to win; you gain or lose K × (result − expected), where the result counts the
--     win (WinWeight) and how many of the rounds your team took (the rest): a 4-0 win is worth
--     more than a 4-3 one, and a 3-4 loss costs less than a 0-4.
--   Performance: how you played against the match average (Performance): kills, deaths,
--     assists, headshots, plants / disables and accuracy, at most ±PerformanceCap.
-- Winners always gain at least 1, losers always lose at least 1. Leaving a ranked match early
-- counts as a loss with no rounds and no performance.
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
Ranked.WinWeight = 0.6 -- share of the result that's the win itself; the rest is your share of the rounds
Ranked.PerformanceCap = 12 -- most MMR how you played can add or take
-- MMR for each stat above (below) the match average: per kill, death, assist, headshot,
-- plant / disable, and per percentage point of accuracy
Ranked.PerformanceWeights = { Kill = 1.5, Death = -1, Assist = 0.5, Headshot = 0.5, Objective = 1.5, Accuracy = 0.15 }

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

export type Stats = { kills: number, deaths: number, assists: number, headshots: number, objectives: number, shots: number, hits: number }

-- Accuracy in percent (trigger pulls that hit an enemy), or nil with nothing fired
local function accuracy(stats: Stats): number?
	return if stats.shots > 0 then 100 * stats.hits / stats.shots else nil
end

-- How well `stats` played against the match `average` (the same fields, averaged over everyone
-- who played): MMR, at most ±PerformanceCap. Accuracy only counts if both fired.
function Ranked.Performance(stats: Stats, average: Stats): number
	local w = Ranked.PerformanceWeights
	local points = (stats.kills - average.kills) * w.Kill + (stats.deaths - average.deaths) * w.Death
		+ (stats.assists - average.assists) * w.Assist + (stats.headshots - average.headshots) * w.Headshot
		+ (stats.objectives - average.objectives) * w.Objective
	local mine, theirs = accuracy(stats), accuracy(average)
	if mine and theirs then
		points += (mine - theirs) * w.Accuracy
	end
	return math.clamp(points, -Ranked.PerformanceCap, Ranked.PerformanceCap)
end

-- The MMR change for one player: their team's average vs the other's, whether they won, the share
-- of the match's rounds their team took (0-1), their Performance, and how many ranked matches
-- they'd played before this one
function Ranked.Change(teamMmr: number, otherMmr: number, won: boolean, roundShare: number, performance: number, matchesBefore: number): number
	local expected = Ranked.Expected(teamMmr, otherMmr)
	local result = Ranked.WinWeight * (if won then 1 else 0) + (1 - Ranked.WinWeight) * math.clamp(roundShare, 0, 1)
	local change = Ranked.K * (result - expected) + performance
	if not Ranked.IsPlaced(matchesBefore) then
		change *= Ranked.PlacementMultiplier
	end
	change = math.floor(change + 0.5)
	return if won then math.max(change, 1) else math.min(change, -1)
end

-- (self-check, on load: the rules keep doing what the header says)
do
	local even: Stats = { kills = 5, deaths = 5, assists = 2, headshots = 2, objectives = 0, shots = 100, hits = 30 }
	local star: Stats = { kills = 12, deaths = 2, assists = 3, headshots = 6, objectives = 1, shots = 100, hits = 45 }
	local placed = Ranked.Placements
	assert(Ranked.Performance(even, even) == 0, "Ranked: average play should be worth 0")
	assert(Ranked.Performance(star, even) == Ranked.PerformanceCap, "Ranked: a great match should hit the cap")
	assert(Ranked.Performance(even, star) < 0, "Ranked: below average should cost MMR")
	assert(Ranked.Change(1000, 1000, true, 1, 0, placed) > Ranked.Change(1000, 1000, true, 4 / 7, 0, placed), "Ranked: a 4-0 should beat a 4-3")
	assert(Ranked.Change(1000, 1000, false, 3 / 7, 0, placed) > Ranked.Change(1000, 1000, false, 0, 0, placed), "Ranked: a 3-4 loss should cost less than 0-4")
	assert(Ranked.Change(1000, 1000, true, 4 / 7, -Ranked.PerformanceCap, placed) >= 1, "Ranked: a win always gains")
	assert(Ranked.Change(1000, 1000, false, 3 / 7, Ranked.PerformanceCap, placed) <= -1, "Ranked: a loss always costs")
end

return Ranked
