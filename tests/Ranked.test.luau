-- Tests for ranked rating math (src/shared/Ranked.luau), loaded unchanged.
-- Run from the repo root: lune run tests/Ranked.test.luau

local load = require("./roblox")
local check = require("./check")
local Ranked = load("src/shared/Ranked")

local placed = Ranked.Placements

-- Elo expectation
check.near("even teams: 50% expected", Ranked.Expected(1000, 1000), 0.5, 1e-9)
check.near("400 MMR better: ~91% expected", Ranked.Expected(1400, 1000), 10 / 11, 1e-9)
check.ok("expectations of both sides add to 1", math.abs(Ranked.Expected(1234, 987) + Ranked.Expected(987, 1234) - 1) < 1e-9)

-- Result part: win share and round share
check.equal("even 4-0 win, average play", Ranked.Change(1000, 1000, true, 1, 0, placed), 16)
check.equal("even 4-3 win, average play", Ranked.Change(1000, 1000, true, 4 / 7, 0, placed), 11)
check.equal("even 3-4 loss, average play", Ranked.Change(1000, 1000, false, 3 / 7, 0, placed), -11)
check.equal("even 0-4 loss, average play", Ranked.Change(1000, 1000, false, 0, 0, placed), -16)
check.ok("beating a stronger team gains more", Ranked.Change(1000, 1400, true, 4 / 7, 0, placed) > Ranked.Change(1000, 1000, true, 4 / 7, 0, placed))

-- Winners always gain, losers always lose, whatever the performance
check.equal("win with the worst performance still gains", Ranked.Change(1600, 800, true, 4 / 7, -Ranked.PerformanceCap, placed), 1)
check.equal("loss with the best performance still costs", Ranked.Change(800, 1600, false, 3 / 7, Ranked.PerformanceCap, placed), -1)

-- Placements swing harder
check.ok("placement matches move more", math.abs(Ranked.Change(1000, 1000, true, 1, 0, 0)) > math.abs(Ranked.Change(1000, 1000, true, 1, 0, placed)))

-- Performance against the match average
local average = { kills = 5, deaths = 5, assists = 2, headshots = 2, objectives = 0, shots = 100, hits = 30 }
check.equal("average play is worth 0", Ranked.Performance(average, average), 0)
check.equal("one kill above average is +1.5", Ranked.Performance({ kills = 6, deaths = 5, assists = 2, headshots = 2, objectives = 0, shots = 100, hits = 30 }, average), 1.5)
check.equal("10 points better accuracy is +1.5", Ranked.Performance({ kills = 5, deaths = 5, assists = 2, headshots = 2, objectives = 0, shots = 100, hits = 40 }, average), 1.5)
check.equal("no shots fired: accuracy doesn't count", Ranked.Performance({ kills = 5, deaths = 5, assists = 2, headshots = 2, objectives = 0, shots = 0, hits = 0 }, average), 0)
check.equal("capped at +PerformanceCap", Ranked.Performance({ kills = 30, deaths = 0, assists = 0, headshots = 0, objectives = 0, shots = 10, hits = 10 }, average), Ranked.PerformanceCap)
check.equal("capped at -PerformanceCap", Ranked.Performance({ kills = 0, deaths = 30, assists = 0, headshots = 0, objectives = 0, shots = 10, hits = 0 }, average), -Ranked.PerformanceCap)

-- Ranks from MMR
check.equal("start MMR is Silver III", Ranked.RankName(Ranked.StartMmr), "SILVER III")
check.equal("0 MMR is Copper III", Ranked.RankName(0), "COPPER III")
check.equal("Champion has no division", Ranked.RankName(5000), "CHAMPION")
check.ok("rank step only goes up with MMR", Ranked.Step(1199) < Ranked.Step(1200))
check.equal("placements label", Ranked.Label(1500, 2), `PLACEMENTS 2/{Ranked.Placements}`)

check.finish()
