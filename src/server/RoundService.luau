-- The match loop: waiting → match starting → rounds → match over.
-- Each round: loadout freeze → (Attack/Defend: defender prep) → action → post-round. One life per round.
--   AttackDefend: attackers plant at A or B (ObjectiveService); defenders stop or defuse it.
--   Elimination:  wipe the other team, or have more players alive when time runs out.
-- One team attacks, the other defends; sides swap at halftime.
-- Clients read the current state from attributes on ReplicatedStorage.MatchState.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Teams = game:GetService("Teams")
local Workspace = game:GetService("Workspace")

local MatchConfig = require(ReplicatedStorage.Shared.MatchConfig)
local AbilityService = require(script.Parent.AbilityService)
local LoadoutService = require(script.Parent.LoadoutService)
local ObjectiveService = require(script.Parent.ObjectiveService)

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

-- Spawn pads live in <Map or TestArena>/TeamSpawns, each with a "Side" attribute ("Attack" / "Defend")
local function getSpawns(side: string): { BasePart }
	local mapRoot = Workspace:FindFirstChild("Map") or Workspace:FindFirstChild("TestArena")
	local folder = mapRoot and mapRoot:FindFirstChild("TeamSpawns")
	local spawns = {}
	if folder then
		for _, part in folder:GetChildren() do
			if part:IsA("BasePart") and part:GetAttribute("Side") == side then
				table.insert(spawns, part)
			end
		end
	end
	return spawns
end

local function spawnTeam(teamName: string, side: string)
	local members = teams[teamName]:GetPlayers()
	local spawns = getSpawns(side)
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

local function unfreezeTeam(teamName: string)
	for _, player in teams[teamName]:GetPlayers() do
		local root = getRoot(player)
		if root then
			root.Anchored = false
		end
	end
end

local function otherTeam(teamName: string): string
	return if teamName == "Blue" then "Orange" else "Blue"
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
	AbilityService.ClearDeployables()
	for _, player in Players:GetPlayers() do
		player.Team = nil
		player.Neutral = true
		LoadoutService.Reset(player)
		task.spawn(player.LoadCharacterAsync, player)
	end
end

-- Decides the round in Attack / Defend. Returns winner team name + reason, or nil to keep going.
local function checkAttackDefend(attack: string, defend: string, attackOut: boolean, defendOut: boolean, timeUp: boolean): (string?, string?)
	local objective = ObjectiveService.GetStatus()
	if objective == "Detonated" then
		return attack, "CHARGE DETONATED"
	elseif objective == "Defused" then
		return defend, "CHARGE DEFUSED"
	elseif objective == "Planted" then
		-- Once planted, killing the attackers isn't enough: defenders have to defuse
		if defendOut then
			return attack, "DEFENDERS ELIMINATED"
		end
		return nil, nil
	end
	if attackOut then
		return defend, "ATTACKERS ELIMINATED"
	elseif defendOut then
		return attack, "DEFENDERS ELIMINATED"
	elseif timeUp then
		return defend, "TIME'S UP"
	end
	return nil, nil
end

-- Decides the round in Elimination
local function checkElimination(attack: string, defend: string, attackOut: boolean, defendOut: boolean, timeUp: boolean): (string?, string?)
	if attackOut and defendOut then
		return "Draw", "BOTH TEAMS ELIMINATED"
	elseif attackOut then
		return defend, "TEAM ELIMINATED"
	elseif defendOut then
		return attack, "TEAM ELIMINATED"
	elseif timeUp then
		local attackAlive, defendAlive = aliveCount(attack), aliveCount(defend)
		if attackAlive > defendAlive then
			return attack, "MORE PLAYERS ALIVE"
		elseif defendAlive > attackAlive then
			return defend, "MORE PLAYERS ALIVE"
		end
		return "Draw", "TIME'S UP"
	end
	return nil, nil
end

-- Returns winner ("Blue" / "Orange" / "Draw") and a reason, or nil if the match was aborted
local function runRound(round: number, mode: string, attack: string): (string?, string?)
	local defend = otherTeam(attack)
	AbilityService.ClearDeployables()
	ObjectiveService.EndRound()
	-- Players without a team (teams were full) sit the match out
	for _, player in Players:GetPlayers() do
		if player.Neutral and player.Character then
			player.Character:Destroy()
		end
	end
	spawnTeam(attack, "Attack")
	spawnTeam(defend, "Defend")
	local startedWith = {}
	for _, teamName in MatchConfig.TeamOrder do
		startedWith[teamName] = #teams[teamName]:GetPlayers()
	end

	-- Loadouts are handed out (or drafted) during the freeze
	local loadoutMode = MatchState:GetAttribute("LoadoutMode") or MatchConfig.DefaultLoadoutMode
	local freezeTime = if loadoutMode == "Draft" then MatchConfig.DraftTime else MatchConfig.PreRoundTime
	local roundPlayers = {}
	for _, teamName in MatchConfig.TeamOrder do
		for _, player in teams[teamName]:GetPlayers() do
			table.insert(roundPlayers, player)
		end
	end
	LoadoutService.StartRound(roundPlayers, loadoutMode, freezeTime)

	setPhase("PreRound", freezeTime, `ROUND {round}`)
	task.wait(freezeTime)
	LoadoutService.FinishRound()

	-- Attack / Defend: defenders get time to set up while attackers wait in spawn
	if mode == "AttackDefend" then
		unfreezeTeam(defend)
		setPhase("Prep", MatchConfig.PrepTime, "DEFENDERS ARE SETTING UP")
		task.wait(MatchConfig.PrepTime)
		if abortMatch then
			return nil, nil
		end
		ObjectiveService.BeginRound(teams[attack], teams[defend])
	end
	unfreezeTeam(attack)
	unfreezeTeam(defend)

	setPhase("Action", MatchConfig.RoundTime, if mode == "AttackDefend" then "ATTACK!" else nil)
	local deadline = os.clock() + MatchConfig.RoundTime
	local planted = false
	endRoundNow = false

	while true do
		task.wait(0.2)
		if abortMatch then
			ObjectiveService.EndRound()
			return nil, nil
		end
		-- The plant replaces the round timer with the fuse timer
		if not planted and ObjectiveService.GetStatus() == "Planted" then
			planted = true
			setPhase("Planted", MatchConfig.FuseTime, "CHARGE PLANTED")
		end

		-- A team only counts as wiped if it had players this round (lets you test solo)
		local attackOut = startedWith[attack] > 0 and aliveCount(attack) == 0
		local defendOut = startedWith[defend] > 0 and aliveCount(defend) == 0
		local timeUp = (not planted and os.clock() >= deadline) or endRoundNow

		local check = if mode == "AttackDefend" then checkAttackDefend else checkElimination
		local winner, reason = check(attack, defend, attackOut, defendOut, timeUp)
		if endRoundNow and not winner then
			winner, reason = "Draw", "ROUND ENDED"
		end
		if winner then
			ObjectiveService.EndRound()
			return winner, reason
		end
	end
end

local function runMatch()
	matchRunning = true
	abortMatch = false
	assignTeams()
	local scores = { Blue = 0, Orange = 0 }
	setScores(scores)

	local mode = MatchState:GetAttribute("GameMode") or MatchConfig.DefaultGameMode
	-- Random team attacks first
	local attack = MatchConfig.TeamOrder[math.random(2)]

	local round = 0
	local matchWinner: string? = nil
	while not abortMatch and #Players:GetPlayers() > 0 do
		round += 1
		MatchState:SetAttribute("Round", round)
		MatchState:SetAttribute("AttackTeam", attack)

		local winner, reason = runRound(round, mode, attack)
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

		local banner = if winner == "Draw" then `ROUND DRAW · {reason}` else `{string.upper(winner)} WINS · {reason}`
		setPhase("PostRound", MatchConfig.PostRoundTime, banner)
		task.wait(MatchConfig.PostRoundTime)

		if round == MatchConfig.SwapSidesAfterRounds then
			attack = otherTeam(attack)
			setPhase("PostRound", 3, "HALFTIME · SWITCHING SIDES")
			task.wait(3)
		end
	end

	if matchWinner and not abortMatch then
		setPhase("MatchOver", MatchConfig.MatchOverTime, `{string.upper(matchWinner)} WINS THE MATCH`)
		task.wait(MatchConfig.MatchOverTime)
	end

	matchRunning = false
	ObjectiveService.EndRound()
	MatchState:SetAttribute("Round", 0)
	MatchState:SetAttribute("AttackTeam", nil)
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

function RoundService.IsMatchRunning(): boolean
	return matchRunning
end

function RoundService.EndRound()
	endRoundNow = true
end

function RoundService.StopMatch()
	if matchRunning then
		abortMatch = true
	end
end

function RoundService.SetLoadoutMode(mode: string)
	if mode == "Draft" or mode == "Random" then
		MatchState:SetAttribute("LoadoutMode", mode)
	end
end

-- Takes effect at the start of the next match
function RoundService.SetGameMode(mode: string)
	if mode == "AttackDefend" or mode == "Elimination" then
		MatchState:SetAttribute("GameMode", mode)
	end
end

function RoundService.Start()
	Players.CharacterAutoLoads = false
	MatchState:SetAttribute("LoadoutMode", MatchConfig.DefaultLoadoutMode)
	MatchState:SetAttribute("GameMode", MatchConfig.DefaultGameMode)

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
