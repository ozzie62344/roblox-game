-- Ranked ratings (rules and numbers: shared/Ranked). A match server knows its match is ranked
-- from the teleport data (MatchState "Ranked": RoundService); in Studio a full ranked queue sets it.
--   RankedService.Begin()        the match starts: everyone on a team is in it, at today's MMR
--   RankedService.Finish(winner) the match is won: everyone still here gets their new MMR
--   RankedService.Cancel()       the match was stopped (dev panel): nothing changes
-- Leaving a ranked match early (before Finish) is a loss, recorded right as you go
-- (PlayerData.OnLeaving runs before your data's last save). Players sent back to the lobby after
-- the match have already been settled, so the teleport out doesn't count.
--   Ranked:FireClient(player, "Result", { before, after, matches, won })   your new MMR (client
--                                                                         MatchResults shows it)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Ranked = require(ReplicatedStorage.Shared.Ranked)
local LeaderboardService = require(script.Parent.LeaderboardService)
local MatchStats = require(script.Parent.MatchStats)
local PlayerData = require(script.Parent.PlayerData)

local RankedRemote = ReplicatedStorage.Remotes.Ranked :: RemoteEvent
local MatchState = ReplicatedStorage.MatchState

local RankedService = {}

type Entry = { team: string, mmr: number, settled: boolean }

local active = false
local closing = false -- (the server shutting down kicks everyone: that's not leaving)
local entries: { [number]: Entry } = {} -- by UserId: everyone who played this match

function RankedService.IsRanked(): boolean
	-- (a custom match is never rated, whatever else says: shared/CustomMatch)
	return MatchState:GetAttribute("Ranked") == true and MatchState:GetAttribute("Custom") ~= true
end

-- (anyone on a team who isn't in yet: a late arrival)
local function track(player: Player)
	local data = PlayerData.Get(player)
	local team = player.Team
	if entries[player.UserId] or not data or player.Neutral or not team then
		return
	end
	entries[player.UserId] = { team = team.Name, mmr = data.Mmr, settled = false }
end

-- Each team's average MMR (as it was when they joined the match)
local function averages(): { [string]: number }
	local sums, counts = {}, {}
	for _, entry in entries do
		sums[entry.team] = (sums[entry.team] or 0) + entry.mmr
		counts[entry.team] = (counts[entry.team] or 0) + 1
	end
	local result = {}
	for team, sum in sums do
		result[team] = sum / counts[team]
	end
	return result
end

local function otherAverage(team: string, teamAverages: { [string]: number }): number
	for name, average in teamAverages do
		if name ~= team then
			return average
		end
	end
	return teamAverages[team] or Ranked.StartMmr
end

-- Applies one player's result. `score` / `averageScore`: their match score and the match's
-- average (a leaver gets no nudge either way). Returns what to tell them.
local function settle(player: Player, entry: Entry, won: boolean, score: number, averageScore: number): { [string]: any }?
	local data = PlayerData.Get(player)
	if entry.settled or not data then
		return nil
	end
	entry.settled = true
	local teamAverages = averages()
	local before, matches = data.Mmr, data.RankedMatches
	local change = Ranked.Change(teamAverages[entry.team] or before, otherAverage(entry.team, teamAverages), won, score, averageScore, matches)
	local after = math.max(0, before + change)
	PlayerData.Update(player, function(d)
		d.Mmr = after
		d.RankedMatches += 1
		d.RankedWins += if won then 1 else 0
	end, true)
	LeaderboardService.Note(player)
	return { before = before, after = after, matches = matches + 1, won = won }
end

function RankedService.Begin()
	table.clear(entries)
	active = RankedService.IsRanked()
	if not active then
		return
	end
	for _, player in Players:GetPlayers() do
		track(player)
	end
end

function RankedService.Finish(winner: string)
	if not active then
		return
	end
	active = false
	for _, player in Players:GetPlayers() do
		track(player)
	end
	local scores = MatchStats.Scores()
	local total, counted = 0, 0
	for _, score in scores do
		total += score
		counted += 1
	end
	local averageScore = if counted > 0 then total / counted else 0
	for _, player in Players:GetPlayers() do
		local entry = entries[player.UserId]
		if entry then
			local result = settle(player, entry, entry.team == winner, scores[player.UserId] or averageScore, averageScore)
			if result then
				RankedRemote:FireClient(player, "Result", result)
			end
		end
	end
end

function RankedService.Cancel()
	active = false
	table.clear(entries)
end

function RankedService.Start()
	-- Leaving a ranked match before it's over: a loss (no performance nudge)
	PlayerData.OnLeaving(function(player)
		if not active or closing then
			return
		end
		track(player)
		local entry = entries[player.UserId]
		if entry then
			settle(player, entry, false, 0, 0)
		end
	end)
	game:BindToClose(function()
		closing = true
	end)
end

return RankedService
