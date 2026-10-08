-- The match loop: waiting → match starting → rounds (pre-round freeze → action → post-round) → match over.
-- One life per round. Team elimination: wipe the other team, or have more players alive when time runs out.
-- Clients read the current state from attributes on ReplicatedStorage.MatchState.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Teams = game:GetService("Teams")
local Workspace = game:GetService("Workspace")

local MatchConfig = require(ReplicatedStorage.Shared.MatchConfig)

local KillFeed = ReplicatedStorage.Remotes.KillFeed :: RemoteEvent
local MatchState = ReplicatedStorage.MatchState

local RoundService = {}

local teams: { [string]: Team } = {}
local matchRunning = false
local forceStart = false
local abortMatch = false
local endRoundNow = false

local function setPhase(newPhase: string, duration: number?, banner: string?)
	MatchState:SetAttribute("Phase", newPhase)
	MatchState:SetAttribute("PhaseEndsAt", if duration then Workspace:GetServerTimeNow() + duration else 0)
	MatchState:SetAttribute("Banner", banner or "")
end

local function isFreeRoam(): boolean
	return not matchRunning
end

local function getRoot(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function isAlive(player: Player): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

local function aliveCount(teamName: string): number
	local count = 0
	for _, player in teams[teamName]:GetPlayers() do
		if isAlive(player) then
			count += 1
		end
	end
	return count
end

-- Team spawn pads live in <Map or TestArena>/TeamSpawns, each with a "Team" attribute
local function getSpawns(teamName: string): { BasePart }
	local mapRoot = Workspace:FindFirstChild("Map") or Workspace:FindFirstChild("TestArena")
	local folder = mapRoot and mapRoot:FindFirstChild("TeamSpawns")
	local spawns = {}
	if folder then
		for _, part in folder:GetChildren() do
			if part:IsA("BasePart") and part:GetAttribute("Team") == teamName then
				table.insert(spawns, part)
			end
		end
	end
	return spawns
end

local function spawnTeam(teamName: string)
	local members = teams[teamName]:GetPlayers()
	local spawns = getSpawns(teamName)
	for i, player in members do
		player:LoadCharacterAsync()
		local character = player.Character
		local root = getRoot(player)
		if character and root and #spawns > 0 then
			local pad = spawns[(i - 1) % #spawns + 1]
			-- Spread teammates out side by side on the pad, facing the way the pad faces
			local sideOffset = (i - (#members + 1) / 2) * 4
			character:PivotTo(pad.CFrame * CFrame.new(sideOffset, 3, 0))
			root.Anchored = true -- frozen until the round starts
		end
	end
end

local function unfreezeAll()
	for _, team in teams do
		for _, player in team:GetPlayers() do
			local root = getRoot(player)
			if root then
				root.Anchored = false
			end
		end
	end
end

local function setScores(scores: { [string]: number })
	for name, score in scores do
		MatchState:SetAttribute("Score" .. name, score)
	end
end

local function assignTeams()
	local players = Players:GetPlayers()
	-- Shuffle so teams are different each match
	for i = #players, 2, -1 do
		local j = math.random(i)
		players[i], players[j] = players[j], players[i]
	end
	for i, player in players do
		local teamName = MatchConfig.TeamOrder[(i - 1) % 2 + 1]
		if #teams[teamName]:GetPlayers() < MatchConfig.MaxTeamSize then
			player.Neutral = false
			player.Team = teams[teamName]
		end
	end
end

local function resetToFreeRoam()
	for _, player in Players:GetPlayers() do
		player.Team = nil
		player.Neutral = true
		task.spawn(player.LoadCharacterAsync, player)
	end
end

-- Returns "Blue", "Orange", "Draw", or nil if the match was aborted
local function runRound(round: number): string?
	-- Players without a team (teams were full) sit the match out
	for _, player in Players:GetPlayers() do
		if player.Neutral and player.Character then
			player.Character:Destroy()
		end
	end
	for _, teamName in MatchConfig.TeamOrder do
		spawnTeam(teamName)
	end
	local startedWith = {}
	for _, teamName in MatchConfig.TeamOrder do
		startedWith[teamName] = #teams[teamName]:GetPlayers()
	end

	setPhase("PreRound", MatchConfig.PreRoundTime, `ROUND {round}`)
	task.wait(MatchConfig.PreRoundTime)
	unfreezeAll()

	setPhase("Action", MatchConfig.RoundTime)
	local deadline = os.clock() + MatchConfig.RoundTime
	endRoundNow = false

	while true do
		task.wait(0.2)
		if abortMatch then
			return nil
		end
		local blueAlive, orangeAlive = aliveCount("Blue"), aliveCount("Orange")
		-- A team only counts as wiped if it had players this round (lets you test solo)
		local blueOut = startedWith.Blue > 0 and blueAlive == 0
		local orangeOut = startedWith.Orange > 0 and orangeAlive == 0
		if blueOut and orangeOut then
			return "Draw"
		elseif blueOut then
			return "Orange"
		elseif orangeOut then
			return "Blue"
		end
		if os.clock() >= deadline or endRoundNow then
			if blueAlive > orangeAlive then
				return "Blue"
			elseif orangeAlive > blueAlive then
				return "Orange"
			end
			return "Draw"
		end
	end
end

local function runMatch()
	matchRunning = true
	abortMatch = false
	assignTeams()
	local scores = { Blue = 0, Orange = 0 }
	setScores(scores)

	local round = 0
	local matchWinner: string? = nil
	while not abortMatch and #Players:GetPlayers() > 0 do
		round += 1
		MatchState:SetAttribute("Round", round)

		local winner = runRound(round)
		if not winner then
			break
		end
		if winner ~= "Draw" then
			scores[winner] += 1
			setScores(scores)
		end
		if scores[winner] and scores[winner] >= MatchConfig.RoundsToWin then
			matchWinner = winner
			break
		end

		local banner = if winner == "Draw" then "ROUND DRAW" else `{string.upper(winner)} WINS THE ROUND`
		setPhase("PostRound", MatchConfig.PostRoundTime, banner)
		task.wait(MatchConfig.PostRoundTime)
	end

	if matchWinner and not abortMatch then
		setPhase("MatchOver", MatchConfig.MatchOverTime, `{string.upper(matchWinner)} WINS THE MATCH`)
		task.wait(MatchConfig.MatchOverTime)
	end

	matchRunning = false
	MatchState:SetAttribute("Round", 0)
	setScores({ Blue = 0, Orange = 0 })
	resetToFreeRoam()
end

local function mainLoop()
	while true do
		forceStart = false
		setPhase("Waiting")
		repeat
			task.wait(0.5)
		until forceStart or #Players:GetPlayers() >= MatchConfig.MinPlayers

		setPhase("Starting", MatchConfig.StartCountdown, "MATCH STARTING")
		local startAt = os.clock() + MatchConfig.StartCountdown
		local cancelled = false
		while os.clock() < startAt do
			task.wait(0.25)
			if not forceStart and #Players:GetPlayers() < MatchConfig.MinPlayers then
				cancelled = true
				break
			end
		end
		if not cancelled then
			runMatch()
		end
	end
end

local function onCharacterAdded(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	humanoid.Died:Connect(function()
		local killerId = humanoid:GetAttribute("LastDamagedBy")
		local killer = if killerId then Players:GetPlayerByUserId(killerId) else nil
		KillFeed:FireAllClients(killer, player, humanoid:GetAttribute("LastHitHeadshot") == true)

		if isFreeRoam() then
			task.delay(MatchConfig.FreeRoamRespawnTime, function()
				if isFreeRoam() and player.Parent and player.Character == character then
					player:LoadCharacterAsync()
				end
			end)
		end
	end)
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)

	if matchRunning then
		-- Join the smaller team; you'll spawn at the start of the next round
		local blue, orange = teams.Blue, teams.Orange
		local smaller = if #blue:GetPlayers() <= #orange:GetPlayers() then blue else orange
		if #smaller:GetPlayers() < MatchConfig.MaxTeamSize then
			player.Neutral = false
			player.Team = smaller
		end
	else
		player:LoadCharacterAsync()
	end
end

function RoundService.ForceStart()
	forceStart = true
end

function RoundService.EndRound()
	endRoundNow = true
end

function RoundService.StopMatch()
	if matchRunning then
		abortMatch = true
	end
end

function RoundService.Start()
	Players.CharacterAutoLoads = false

	for _, name in MatchConfig.TeamOrder do
		local team = Instance.new("Team")
		team.Name = name
		team.TeamColor = MatchConfig.Teams[name].Color
		team.AutoAssignable = false
		team.Parent = Teams
		teams[name] = team
	end

	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)

	task.spawn(mainLoop)
end

return RoundService
