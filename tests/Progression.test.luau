-- Tests for the XP / level curve, the reward track and daily rewards
-- (src/shared/Progression.luau), loaded unchanged.
-- Run from the repo root: lune run tests/Progression.test.luau

local load = require("./roblox")
local check = require("./check")
local Progression = load("src/shared/Progression")
local Skins = load("src/shared/Skins")
local Attachments = load("src/shared/Attachments")

-- XP to the next level: 500, then +150 a level, capped at 5000
check.equal("level 1 → 2 takes 500 XP", Progression.XpToNext(1), 500)
check.equal("level 2 → 3 takes 650 XP", Progression.XpToNext(2), 650)
check.equal("the step caps at 5000", Progression.XpToNext(100), 5000)

-- Level from total XP
local level, into, need = Progression.LevelFor(0)
check.ok("0 XP is level 1, 0 into it, 500 to go", level == 1 and into == 0 and need == 500, `{level}, {into}, {need}`)
check.equal("499 XP is still level 1", (Progression.LevelFor(499)), 1)
check.equal("500 XP is level 2", (Progression.LevelFor(500)), 2)
level, into = Progression.LevelFor(500 + 650 + 10)
check.ok("1160 XP is level 3, 10 into it", level == 3 and into == 10, `{level}, {into}`)
check.equal("negative XP counts as 0", (Progression.LevelFor(-50)), 1)
-- The level and the XP to reach it agree: summing XpToNext up to a level lands exactly on it
local total = 0
for l = 1, 59 do
	total += Progression.XpToNext(l)
end
check.equal("the sum of steps to level 60 is level 60", (Progression.LevelFor(total)), 60)
check.equal("one XP short of level 60 is level 59", (Progression.LevelFor(total - 1)), 59)

-- Reward track
check.equal("past the track: AfterTrack credits", Progression.RewardFor(Progression.TrackLength + 1).Amount, Progression.AfterTrack)
local attachment = Progression.RewardFor(3)
check.ok("level 3 gives the Red Dot", attachment.Kind == "Attachment" and attachment.Id == "RedDot", `{attachment.Kind} {attachment.Id}`)
check.equal("an item reward pays its price if you own it", attachment.Amount, Attachments.ById.RedDot.Price)
local trackSkins, everyLevelOk = 0, true
for l = 2, Progression.TrackLength do
	local reward = Progression.RewardFor(l)
	if reward.Kind == "Skin" then
		trackSkins += 1
		everyLevelOk = everyLevelOk and Skins.ById[reward.Id] ~= nil and Skins.ById[reward.Id].TrackOnly == l
	elseif reward.Kind == "Credits" then
		everyLevelOk = everyLevelOk and reward.Amount > 0
	end
end
check.ok("every track level has a real reward", everyLevelOk)
local expectedSkins = 0
for _, skin in Skins.List do
	if skin.TrackOnly then
		expectedSkins += 1
	end
end
check.equal("every track-only skin is on the track", trackSkins, expectedSkins)
-- (some multiples of 5 are items: check the first credits one)
local pileLevel = nil
for l = 5, Progression.TrackLength, 5 do
	if Progression.RewardFor(l).Kind == "Credits" then
		pileLevel = l
		break
	end
end
check.ok("a level divisible by 5 pays the bigger pile", pileLevel ~= nil and Progression.RewardFor(pileLevel).Amount == 400 + 10 * pileLevel, tostring(pileLevel))
check.equal("other credit levels pay the smaller pile", Progression.RewardFor(2).Amount, 120)
check.equal("next item after level 3 comes later", Progression.NextItemLevel(3) ~= nil and Progression.NextItemLevel(3) > 3, true)
check.equal("no next item past the track", Progression.NextItemLevel(Progression.TrackLength), nil)

-- Daily rewards
check.equal("day 1 of a streak pays the first amount", Progression.DailyCredits(1), Progression.Daily[1])
check.equal("day 8 starts the week again", Progression.DailyCredits(#Progression.Daily + 1), Progression.Daily[1])
local streak, credits = Progression.NextDaily(99, 3, 100)
check.ok("claiming the day after continues the streak", streak == 4 and credits == Progression.Daily[4], `{streak}, {credits}`)
streak = Progression.NextDaily(97, 3, 100)
check.equal("missing a day resets the streak to 1", streak, 1)
streak = Progression.NextDaily(0, 0, 100)
check.equal("first ever claim is day 1", streak, 1)
check.equal("Day() is whole UTC days", Progression.Day(86400 * 3 + 5), 3)

check.finish()
