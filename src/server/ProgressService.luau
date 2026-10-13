-- Levels, the reward track, daily login rewards and daily challenges (rules and numbers:
-- shared/Progression; the lobby's PROGRESS screen and the end-of-match XP card: client
-- Match/ProgressMenu).
--   ProgressService.Record(player, event)   something worth XP happened in a match (RoundService,
--                                           ObjectiveService): XP, career stats, challenges
--   Progress:FireServer("ClaimDaily")       claim today's login reward (once per UTC day)
--   Progress:FireClient(player, "Xp", amount, reason)       XP earned ("KILL", "CHALLENGE"...)
--   Progress:FireClient(player, "LevelUp", level, from)     reached `level`: the track rewards of
--                                                           levels from..level are now theirs
--   Progress:FireClient(player, "Challenge", id)            finished a daily challenge
--   Progress:FireClient(player, "Daily", streak, credits)   daily reward claimed
-- Everything lives in the player's data (PlayerData) and reaches clients as player attributes.
-- Track rewards are handed out by the server the moment a level is reached (and on joining, in
-- case a server went down in between): nothing to claim, nothing a client can ask for twice.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MatchConfig = require(ReplicatedStorage.Shared.MatchConfig)
local Progression = require(ReplicatedStorage.Shared.Progression)
local Skins = require(ReplicatedStorage.Shared.Skins)
local LeaderboardService = require(script.Parent.LeaderboardService)
local PlayerData = require(script.Parent.PlayerData)
local ShopService = require(script.Parent.ShopService)

local Progress = ReplicatedStorage.Remotes.Progress :: RemoteEvent

local ProgressService = {}

local REASONS = {
	Kill = "KILL",
	Headshot = "HEADSHOT",
	Plant = "DEFUSER PLANTED",
	Disable = "DEFUSER DISABLED",
	RoundWin = "ROUND WON",
	MatchWin = "MATCH WON",
	MatchPlayed = "MATCH COMPLETE",
}
local LOAD_WAIT = 120 -- seconds to wait for someone's data to load before giving up on them

local lastRequest: { [Player]: number } = {}

local function today(): number
	return Progression.Day(os.time())
end

local function needsChallenges(data: PlayerData.Data, day: number): boolean
	return data.ChallengeDay ~= day or #data.Challenges == 0
end

-- (inside a PlayerData.Update) New challenges once the day has changed
local function freshChallenges(data: PlayerData.Data, player: Player, day: number)
	if needsChallenges(data, day) then
		data.ChallengeDay = day
		data.Challenges = Progression.RollChallenges(player.UserId, day)
	end
end

-- Hands out the track rewards for every level reached since the last time
local function giveLevelRewards(player: Player)
	local data = PlayerData.Get(player)
	if not data then
		return
	end
	local level = Progression.LevelFor(data.Xp)
	local from = data.RewardedLevel + 1
	if level < from then
		return
	end
	local credits = 0
	PlayerData.Update(player, function(d)
		for l = from, level do
			local reward = Progression.RewardFor(l)
			if reward.Kind == "Skin" and not d.Skins[reward.Id] then
				d.Skins[reward.Id] = true
			elseif reward.Kind == "Attachment" and not d.OwnedAttachments[reward.Id] then
				d.OwnedAttachments[reward.Id] = true
			else
				credits += reward.Amount -- (credits, or an item they already had)
			end
		end
		d.RewardedLevel = level
	end, true)
	ShopService.Award(player, credits, if level > from then `LEVELS {from}-{level}` else `LEVEL {level}`)
	Progress:FireClient(player, "LevelUp", level, from)
end

local function addXp(player: Player, amount: number, reason: string)
	if amount <= 0 then
		return
	end
	local added = PlayerData.Update(player, function(d)
		d.Xp += amount
	end)
	if added then
		Progress:FireClient(player, "Xp", amount, reason)
		giveLevelRewards(player)
	end
end

-- Something worth XP happened to `player` in a match (enemy killed, headshot, defuser planted or
-- disabled, round won, match won / finished): XP, career stats and challenge progress. Challenges
-- tied to a gun count the gun they're holding (their "Weapon" attribute).
function ProgressService.Record(player: Player, event: Progression.Event)
	if not PlayerData.Get(player) then
		return
	end
	local weapon = player:GetAttribute("Weapon")
	local finished: { Progression.Challenge } = {}
	PlayerData.Update(player, function(d)
		freshChallenges(d, player, today())
		if event == "Kill" then
			d.Kills += 1
		elseif event == "Headshot" then
			d.Headshots += 1
		elseif event == "MatchWin" then
			d.Wins += 1
		elseif event == "MatchPlayed" then
			d.Matches += 1
		end
		for _, entry in d.Challenges do
			local challenge = Progression.ChallengeById[entry.Id]
			if challenge and entry.Progress < challenge.Goal and Progression.Counts(challenge, event, weapon) then
				entry.Progress += 1
				if entry.Progress >= challenge.Goal then
					table.insert(finished, challenge)
				end
			end
		end
	end)
	addXp(player, MatchConfig.Xp[event] or 0, REASONS[event] or "")
	for _, challenge in finished do
		Progress:FireClient(player, "Challenge", challenge.Id)
		ShopService.Award(player, challenge.Credits, "CHALLENGE")
		addXp(player, challenge.Xp, "CHALLENGE")
	end
	LeaderboardService.Note(player)
end

local function claimDaily(player: Player)
	local data = PlayerData.Get(player)
	local day = today()
	if not data or data.DailyDay >= day then
		return -- (already claimed today)
	end
	local streak, credits = Progression.NextDaily(data.DailyDay, data.DailyStreak, day)
	PlayerData.Update(player, function(d)
		d.DailyDay = day
		d.DailyStreak = streak
		-- Streak skins (Skins DailyOnly): yours once the streak gets there
		for _, skin in Skins.List do
			if skin.DailyOnly and streak >= skin.DailyOnly then
				d.Skins[skin.Id] = true
			end
		end
	end, true)
	ShopService.Award(player, credits, `DAY {streak} BONUS`)
	Progress:FireClient(player, "Daily", streak, credits)
end

-- Once their data is in: today's challenges, any track rewards still owed, the leaderboards
local function onPlayerAdded(player: Player)
	local waited = 0
	while player.Parent and not PlayerData.Get(player) and waited < LOAD_WAIT do
		waited += task.wait(0.5)
	end
	local data = PlayerData.Get(player)
	if not data then
		return
	end
	local day = today()
	if needsChallenges(data, day) then
		PlayerData.Update(player, function(d)
			freshChallenges(d, player, day)
		end)
	end
	giveLevelRewards(player)
	LeaderboardService.Note(player)
end

function ProgressService.Start()
	Progress.OnServerEvent:Connect(function(player, action)
		-- (one tap at a time is plenty)
		local now = os.clock()
		if now - (lastRequest[player] or 0) < 0.5 then
			return
		end
		lastRequest[player] = now
		if action == "ClaimDaily" then
			claimDaily(player)
		end
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		lastRequest[player] = nil
	end)

	-- Midnight UTC: everyone still here gets their new challenges (checked twice a minute, cheap)
	task.spawn(function()
		while true do
			task.wait(30)
			local day = today()
			for _, player in Players:GetPlayers() do
				local data = PlayerData.Get(player)
				if data and needsChallenges(data, day) then
					PlayerData.Update(player, function(d)
						freshChallenges(d, player, day)
					end)
				end
			end
		end
	end)
end

return ProgressService
