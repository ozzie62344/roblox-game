-- Tests for custom match settings validation (src/shared/CustomMatch.luau), loaded unchanged.
-- (Apply / Clear / IsCustom write a Roblox instance's attributes, so they aren't tested here.)
-- Run from the repo root: lune run tests/CustomMatch.test.luau

local load = require("./roblox")
local check = require("./check")
local CustomMatch = load("src/shared/CustomMatch")
local MatchConfig = load("src/shared/MatchConfig")

local maps = { "House", "Warehouse" }

-- Defaults are the match's normal rules
local defaults = CustomMatch.Defaults()
check.equal("default rounds to win is the normal one", defaults.RoundsToWin, MatchConfig.RoundsToWin)
check.equal("default map is random", defaults.Map, CustomMatch.RandomMap)
check.equal("friendly fire is on by default", defaults.FriendlyFire, true)

-- The normal values are always a choice (including() adds them if a list misses them)
for _, key in { "RoundsToWin", "PrepTime", "RoundTime", "Reinforcements" } do
	check.ok(`{key}'s default is one of its options`, table.find(CustomMatch.Options(key, maps), CustomMatch.ByKey[key].Default) ~= nil)
end

-- Sanitize: anything missing or not an option becomes the default
local clean = CustomMatch.Sanitize({ RoundsToWin = 3, Map = "House", NoDrones = true }, maps)
check.ok("valid choices are kept", clean.RoundsToWin == 3 and clean.Map == "House" and clean.NoDrones == true)
check.equal("missing keys get the default", clean.PrepTime, MatchConfig.PrepTime)
clean = CustomMatch.Sanitize({ RoundsToWin = 999, Map = "Moon", PrepTime = "lots", FriendlyFire = "yes" }, maps)
check.ok("values that aren't options become the default", clean.RoundsToWin == MatchConfig.RoundsToWin and clean.Map == CustomMatch.RandomMap and clean.PrepTime == MatchConfig.PrepTime and clean.FriendlyFire == true)
check.equal("a map that isn't on this server's list is refused", CustomMatch.Sanitize({ Map = "Bank" }, maps).Map, CustomMatch.RandomMap)
check.equal("unknown keys are dropped", CustomMatch.Sanitize({ Cheat = true }, maps).Cheat, nil)
check.equal("not a table: all defaults", CustomMatch.Sanitize("nope", maps).RoundsToWin, MatchConfig.RoundsToWin)

-- Sizes and codes
check.equal("max players is two full teams plus spectators", CustomMatch.MaxPlayers, MatchConfig.MaxTeamSize * 2 + CustomMatch.MaxSpectators)
check.ok("the code alphabet has no 0/O or 1/I", not string.find(CustomMatch.CodeAlphabet, "[0O1I]"))
check.equal("map options are Random then the server's maps", table.concat(CustomMatch.Options("Map", maps), ","), "Random,House,Warehouse")

check.finish()
