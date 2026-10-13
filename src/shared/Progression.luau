-- Levels, the reward track, daily login rewards and daily challenges: the numbers and rules both
-- sides share. Only the server (ProgressService) changes anything; the lobby's PROGRESS screen
-- (client Match/ProgressMenu) uses this to show it.
--
-- XP is earned in matches (MatchConfig.Xp) and from challenges. Your level follows from your total
-- XP: level 1 → 2 takes 500, each level after takes 150 more than the one before, up to 5,000 a
-- level (so the first few come quickly: about one level per half match at the start).
-- Reward track: reaching a level unlocks its reward right away (no claiming): credits, and at
-- milestones an attachment or a skin you can't buy (Skins: TrackOnly = its level). An item you
-- already own pays out its price in credits instead. Past the end of the track every level is
-- worth credits.
-- Daily reward: credits, claimed once per UTC day. Claiming on back-to-back days builds a streak
-- (bigger every day, a week long, then the week starts over); missing a day starts it over.
-- Daily challenges: 3 per player, new ones every UTC day (the same 3 on every server: they're
-- rolled from the UserId and the day), each worth credits and XP when finished.
--
-- Player attributes (PlayerData): Xp, Level, Stats (JSON {Kills, Headshots, Wins, Matches}),
-- DailyDay, DailyStreak, Challenges (JSON {Day, List = {{Id, Progress}}}).

local Attachments = require(script.Parent.Attachments)
local Skins = require(script.Parent.Skins)

local Progression = {}

-- What happens in a match that counts (ProgressService.Record)
export type Event = "Kill" | "Headshot" | "Plant" | "Disable" | "RoundWin" | "MatchWin" | "MatchPlayed"

export type Reward = {
	Kind: "Credits" | "Skin" | "Attachment",
	Id: string, -- skin / attachment id ("" for credits)
	Amount: number, -- credits (for an item: what it pays if you already own it)
}

export type Challenge = {
	Id: string,
	Text: string,
	Event: Event,
	Weapon: string?, -- only counts holding this gun (the "Weapon" attribute)
	Goal: number,
	Credits: number,
	Xp: number,
}

export type ChallengeState = { Id: string, Progress: number }

local FIRST_LEVEL_XP = 500
local LEVEL_XP_STEP = 150
local MAX_LEVEL_XP = 5000
local MAX_LEVEL = 999

Progression.TrackLength = 50 -- levels with a planned reward; after this every level pays AfterTrack
Progression.AfterTrack = 500
Progression.ChallengesPerDay = 3
-- Daily reward by day of the streak (day 8 is day 1 of the next week)
Progression.Daily = { 100, 150, 200, 250, 300, 400, 750 }

-- The UTC day number of a time (os.time() on the server, GetServerTimeNow() on a client)
function Progression.Day(time: number): number
	return math.floor(time / 86400)
end

-- XP it takes to get from `level` to the next one
function Progression.XpToNext(level: number): number
	return math.min(FIRST_LEVEL_XP + LEVEL_XP_STEP * (level - 1), MAX_LEVEL_XP)
end

-- Level for a total amount of XP, plus how far into that level you are and what the level takes
function Progression.LevelFor(xp: number): (number, number, number)
	local level = 1
	local left = math.max(0, xp)
	while level < MAX_LEVEL and left >= Progression.XpToNext(level) do
		left -= Progression.XpToNext(level)
		level += 1
	end
	return level, left, Progression.XpToNext(level)
end

-- ─── Reward track ──────────────────────────────────────────────────────────────

-- Attachments on the track (they can also be bought in the shop: owning one pays its price)
local ATTACHMENT_LEVELS = { [3] = "RedDot", [8] = "Laser", [13] = "Compensator", [18] = "Holo", [25] = "Suppressor", [35] = "Scope" }

-- Skins on the track: the ones in Skins.luau with TrackOnly
local skinLevels: { [number]: string } = {}
for _, skin in Skins.List do
	if skin.TrackOnly then
		skinLevels[skin.TrackOnly] = skin.Id
	end
end

-- The reward for reaching `level` (level 1 is where you start: nothing)
function Progression.RewardFor(level: number): Reward
	if level > Progression.TrackLength then
		return { Kind = "Credits", Id = "", Amount = Progression.AfterTrack }
	end
	local skinId = skinLevels[level]
	if skinId then
		return { Kind = "Skin", Id = skinId, Amount = Skins.ById[skinId].Price }
	end
	local attachmentId = ATTACHMENT_LEVELS[level]
	if attachmentId and Attachments.ById[attachmentId] then
		return { Kind = "Attachment", Id = attachmentId, Amount = Attachments.ById[attachmentId].Price }
	end
	-- Credits, with a bigger pile every 5 levels
	local amount = if level % 5 == 0 then 400 + 10 * level else 100 + 10 * level
	return { Kind = "Credits", Id = "", Amount = amount }
end

-- "350 CREDITS", "RED DOT", "RECRUIT SKIN"
function Progression.RewardText(reward: Reward): string
	if reward.Kind == "Skin" then
		return string.upper(Skins.ById[reward.Id].Name) .. " SKIN"
	elseif reward.Kind == "Attachment" then
		return string.upper(Attachments.ById[reward.Id].Name)
	end
	return `{reward.Amount} CREDITS`
end

-- The next level (after `level`) whose reward is an item, or nil past the end of the track
function Progression.NextItemLevel(level: number): number?
	for l = level + 1, Progression.TrackLength do
		if Progression.RewardFor(l).Kind ~= "Credits" then
			return l
		end
	end
	return nil
end

-- ─── Daily reward ──────────────────────────────────────────────────────────────

-- Credits for a day of the streak (1 = first day)
function Progression.DailyCredits(streak: number): number
	return Progression.Daily[(math.max(streak, 1) - 1) % #Progression.Daily + 1]
end

-- Claiming on `today` after last claiming on `lastDay` (0 = never) with `streak`: the new
-- streak (yesterday → one more, otherwise back to 1) and its credits
function Progression.NextDaily(lastDay: number, streak: number, today: number): (number, number)
	local newStreak = if lastDay == today - 1 then streak + 1 else 1
	return newStreak, Progression.DailyCredits(newStreak)
end

-- ─── Daily challenges ──────────────────────────────────────────────────────────

Progression.Challenges = {
	{ Id = "Kills10", Text = "Get 10 kills", Event = "Kill", Goal = 10, Credits = 200, Xp = 300 },
	{ Id = "Kills25", Text = "Get 25 kills", Event = "Kill", Goal = 25, Credits = 450, Xp = 700 },
	{ Id = "Headshots5", Text = "Get 5 headshots", Event = "Headshot", Goal = 5, Credits = 250, Xp = 350 },
	{ Id = "Plant", Text = "Plant the defuser", Event = "Plant", Goal = 1, Credits = 200, Xp = 300 },
	{ Id = "Disable", Text = "Disable the defuser", Event = "Disable", Goal = 1, Credits = 250, Xp = 350 },
	{ Id = "WinMatch", Text = "Win a match", Event = "MatchWin", Goal = 1, Credits = 300, Xp = 500 },
	{ Id = "Play3", Text = "Finish 3 matches", Event = "MatchPlayed", Goal = 3, Credits = 300, Xp = 500 },
	{ Id = "Rounds5", Text = "Win 5 rounds", Event = "RoundWin", Goal = 5, Credits = 200, Xp = 300 },
	{ Id = "GatlingRounds", Text = "Win 2 rounds with the Gatling", Event = "RoundWin", Weapon = "Gatling", Goal = 2, Credits = 300, Xp = 400 },
	{ Id = "ShotgunKills", Text = "Get 5 kills with the Shotgun", Event = "Kill", Weapon = "Shotgun", Goal = 5, Credits = 250, Xp = 400 },
	{ Id = "SniperKills", Text = "Get 3 kills with the Sniper", Event = "Kill", Weapon = "Sniper", Goal = 3, Credits = 250, Xp = 400 },
	{ Id = "RevolverKills", Text = "Get 3 kills with the Revolver", Event = "Kill", Weapon = "Revolver", Goal = 3, Credits = 250, Xp = 400 },
	{ Id = "SMGKills", Text = "Get 8 kills with the SMG", Event = "Kill", Weapon = "SMG", Goal = 8, Credits = 250, Xp = 400 },
	{ Id = "LMGRounds", Text = "Win 3 rounds with the LMG", Event = "RoundWin", Weapon = "LMG", Goal = 3, Credits = 300, Xp = 400 },
} :: { Challenge }

Progression.ChallengeById = {} :: { [string]: Challenge }
for _, challenge in Progression.Challenges do
	Progression.ChallengeById[challenge.Id] = challenge
end

-- Does this event (while holding `weapon`) move the challenge on?
function Progression.Counts(challenge: Challenge, event: Event, weapon: any): boolean
	return challenge.Event == event and (challenge.Weapon == nil or challenge.Weapon == weapon)
end

-- A player's challenges for a day: always the same ones for the same player and day. Never two of
-- the same kind (no "10 kills" with "25 kills"), at most one tied to a gun.
function Progression.RollChallenges(userId: number, day: number): { ChallengeState }
	local random = Random.new(math.abs(userId) * 7919 + day * 104729)
	local order = {}
	for i = 1, #Progression.Challenges do
		table.insert(order, i)
	end
	for i = #order, 2, -1 do
		local j = random:NextInteger(1, i)
		order[i], order[j] = order[j], order[i]
	end
	local picked: { ChallengeState } = {}
	local kinds: { [string]: boolean } = {}
	local gunPicked = false
	for _, index in order do
		local challenge = Progression.Challenges[index]
		local kind = challenge.Event .. ":" .. (challenge.Weapon or "")
		if kinds[kind] or (challenge.Weapon and gunPicked) then
			continue
		end
		kinds[kind] = true
		gunPicked = gunPicked or challenge.Weapon ~= nil
		table.insert(picked, { Id = challenge.Id, Progress = 0 })
		if #picked >= Progression.ChallengesPerDay then
			break
		end
	end
	return picked
end

return Progression
