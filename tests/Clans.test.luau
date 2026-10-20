-- Tests for clan input cleaning and join requirements (src/shared/Clans.luau), loaded unchanged.
-- (Who may kick / promote / transfer lives inside ClanService's DataStore update, so it isn't
-- tested here: see NIGHT_LOG_2.md.)
-- Run from the repo root: lune run tests/Clans.test.luau

local load = require("./roblox")
local check = require("./check")
local Clans = load("src/shared/Clans")
local Ranked = load("src/shared/Ranked")

-- Names: 3-20 letters, digits and spaces, spaces trimmed and squeezed
check.equal("name is trimmed and squeezed", Clans.CleanName("  My   Clan  "), "My Clan")
check.equal("name too short", Clans.CleanName("ab"), nil)
check.equal("name too long", Clans.CleanName(string.rep("a", 21)), nil)
check.equal("name with symbols", Clans.CleanName("Bad<Name>"), nil)
check.equal("name that isn't text", Clans.CleanName(42), nil)

-- Tags: 2-4 letters or digits, upper-cased
check.equal("tag is upper-cased", Clans.CleanTag("abc"), "ABC")
check.equal("tag too short", Clans.CleanTag("a"), nil)
check.equal("tag too long", Clans.CleanTag("abcde"), nil)
check.equal("tag with a space", Clans.CleanTag("a b"), nil)

-- Free text: one line, trimmed, at most `max` characters (counting letters, not bytes)
check.equal("text is trimmed, newlines become spaces", Clans.CleanText("  hello\nthere  ", 20), "hello there")
check.equal("text over the limit", Clans.CleanText(string.rep("x", 21), 20), nil)
check.equal("multi-byte letters count once", Clans.CleanText(string.rep("é", 20), 20), string.rep("é", 20))

-- Types and badges
check.ok("Open is a clan type", Clans.IsType("Open"))
check.ok("anything else isn't", not Clans.IsType("Secret"))
check.equal("an unknown badge falls back to the first", Clans.BadgeById(999).Id, 1)

-- Roles outrank each other in order (ClanService compares these numbers for kicks)
check.ok("owner outranks officer outranks member", Clans.Roles.Owner > Clans.Roles.Officer and Clans.Roles.Officer > Clans.Roles.Member)

-- Requirements
check.equal("not placed in ranked yet counts as tier 0", Clans.TierIndex(2000, Ranked.Placements - 1), 0)
local levelOk, rankOk = Clans.Meets(10, 0, 5, 0)
check.ok("level 10 with no rank meets a level-5, no-rank clan", levelOk and rankOk)
levelOk, rankOk = Clans.Meets(4, 3, 5, 2)
check.ok("level 4 fails a level-5 clan but meets its rank", not levelOk and rankOk)
levelOk, rankOk = Clans.Meets(30, 2, 5, 4)
check.ok("tier 2 fails a tier-4 rank requirement", levelOk and not rankOk)
check.equal("rank label for no requirement", Clans.RankLabel(0), "NONE")

check.finish()
