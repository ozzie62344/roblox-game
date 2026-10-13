-- The match loop: waiting → map vote → rounds → match over.
-- A lobby server never starts a match by itself (players queue in Matchmaker and get teleported
-- to a match server); a match server waits for everyone teleported in, plays one match and
-- sends them all back to a lobby. Devs can force a match anywhere (and in Studio, which can't
-- teleport, a full queue does that too).
-- Each round: loadout freeze → (Attack/Defend: defender prep) → action → post-round. One life per round.
--   AttackDefend: defenders guard the bombs at A and B; attackers plant a defuser on one
--                 (ObjectiveService) and defenders have to disable it. On
--                 maps with several site pairs the defenders pick the pair during the freeze, and
--                 the attackers hunt for it with drones during the setup (DroneService).
--   Elimination:  wipe the other team, or have more players alive when time runs out.
-- One team attacks, the other defends; sides swap at halftime.
-- Clients read the current state from attributes on ReplicatedStorage.MatchState.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Teams = game:GetService("Teams")
local TeleportService = game:GetService("TeleportService")
local Workspace = game:GetService("Workspace")

local GameRules = require(ReplicatedStorage.Shared.GameRules)
local MatchConfig = require(ReplicatedStorage.Shared.MatchConfig)
local AbilityService = require(script.Parent.AbilityService)
local CameraService = require(script.Parent.CameraService)
local DroneService = require(script.Parent.DroneService)
local LoadoutService = require(script.Parent.LoadoutService)
local MapService = require(script.Parent.MapService)
local MatchStats = require(script.Parent.MatchStats)
local ObjectiveService = require(script.Parent.ObjectiveService)
local PartyService = require(script.Parent.PartyService)
local ProgressService = require(script.Parent.ProgressService)
local ShopService = require(script.Parent.ShopService)

local KillFeed = ReplicatedStorage.Remotes.KillFeed :: RemoteEvent
local PickSite = ReplicatedStorage.Remotes.PickSite :: RemoteEvent
local VoteMap = ReplicatedStorage.Remotes.VoteMap :: RemoteEvent
local MatchState = ReplicatedStorage.MatchState

local RoundService = {}

-- A reserved server (one with no owner) only exists because Matchmaker made it for a match
local IS_MATCH_SERVER = game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0

local teams: { [string]: Team } = {}
local matchRunning = false
local forceStart = false
local abortMatch = false
local endRoundNow = false
-- The teams Matchmaker made (a party always plays together), for the next match: from the
-- teleport data on a match server, straight from Matchmaker in Studio
local presetTeams: { [Player]: string } = {}

local function setPhase(newPhase: string, duration: number?, banner: string?)
	MatchState:SetAttribute("Phase", newPhase)
	MatchState:SetAttribute("PhaseEndsAt", if duration then Workspace:GetServerTimeNow() + duration else 0)
	MatchState:SetAttribute("Banner", banner or "")
end

local function isFreeRoam(): boolean
	return not matchRunning
end

-- How high above the floor a character's root is when standing (in case a body ever isn't the
-- standard one: at a fixed 3 studs a tall one would start with its legs in the floor)
local function standHeight(character: Model): number
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if humanoid and root and humanoid.RigType == Enum.HumanoidRigType.R15 then
		return humanoid.HipHeight + root.Size.Y / 2
	end
	return 3
end

-- Everyone gets the same body: standard R15 parts at one fixed size, so no avatar is smaller or
-- thinner (harder to hit) than another. Clothes, colors, face and accessories stay (accessories
-- don't count as hits: onCharacterAdded). Fetched once per player; the plain default look if
-- their avatar can't be loaded (e.g. Studio's test players).
local STANDARD_BODY = {
	Head = 0, Torso = 0, LeftArm = 0, RightArm = 0, LeftLeg = 0, RightLeg = 0,
	HeightScale = 1, WidthScale = 1, DepthScale = 1, HeadScale = 1, BodyTypeScale = 0, ProportionScale = 0,
}
local bodies: { [Player]: HumanoidDescription } = setmetatable({}, { __mode = "k" }) :: any

local function loadCharacter(player: Player)
	local description = bodies[player]
	if not description then
		local ok, fetched = pcall(Players.GetHumanoidDescriptionFromUserId, Players, player.UserId)
		description = if ok and fetched then fetched else Instance.new("HumanoidDescription")
		for property, value in STANDARD_BODY do
			(description :: any)[property] = value
		end
		bodies[player] = description
	end
	if not pcall(player.LoadCharacterWithHumanoidDescription, player, description) then
		player:LoadCharacterAsync()
	end
end

-- Between matches you spawn in the lobby (third person). Devs can choose to free-roam on the map
-- instead (first person) with the dev panel; that choice is the "FreeRoamArea" attribute.
-- The "Location" attribute tells the client where you are ("Lobby", "Map" or "Match").
local function spawnFreeRoam(player: Player)
	local area = if player:GetAttribute("FreeRoamArea") == "Map" then "Map" else "Lobby"
	player:SetAttribute("Location", area)
	loadCharacter(player)
	local character = player.Character
	local spot = if area == "Lobby" then MapService.GetLobbySpawn() else MapService.GetMapSpawn()
	if character and spot then
		-- Spread people out a little so they don't spawn inside each other
		character:PivotTo(spot * CFrame.new(math.random() * 6 - 3, standHeight(character), math.random() * 6 - 3))
	end
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

-- Spawn pads live in <Map or TestArena>/TeamSpawns, each with a "Side" attribute ("Attack" / "Defend").
-- Defender pads can belong to a site pair ("Pair"): defenders spawn in the pair they're defending.
local function getSpawns(side: string): { BasePart }
	local mapRoot = Workspace:FindFirstChild("Map") or Workspace:FindFirstChild("TestArena")
	local folder = mapRoot and mapRoot:FindFirstChild("TeamSpawns")
	local spawns, inPair = {}, {}
	local sitePair = MatchState:GetAttribute("SitePair")
	if folder then
		for _, part in folder:GetChildren() do
			if part:IsA("BasePart") and part:GetAttribute("Side") == side then
				table.insert(spawns, part)
				if sitePair and part:GetAttribute("Pair") == sitePair then
					table.insert(inPair, part)
				end
			end
		end
	end
	return if #inPair > 0 then inPair else spawns
end

-- Puts a team on one of its side's pads (a random one if there are several), side by side,
-- frozen until the round starts
local function placeTeam(teamName: string, side: string)
	local members = teams[teamName]:GetPlayers()
	local spawns = getSpawns(side)
	if #spawns == 0 then
		return
	end
	local pad = spawns[math.random(#spawns)]
	for i, player in members do
		local character = player.Character
		local root = getRoot(player)
		if character and root then
			-- Spread teammates out side by side on the pad, facing the way the pad faces
			local sideOffset = (i - (#members + 1) / 2) * 4
			character:PivotTo(pad.CFrame * CFrame.new(sideOffset, standHeight(character), 0))
			root.Anchored = true
		end
	end
end

local function spawnTeam(teamName: string, side: string)
	for _, player in teams[teamName]:GetPlayers() do
		player:SetAttribute("Location", "Match")
		loadCharacter(player)
	end
	placeTeam(teamName, side)
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

local function join(player: Player, teamName: string)
	if #teams[teamName]:GetPlayers() < MatchConfig.MaxTeamSize then
		player.Neutral = false
		player.Team = teams[teamName]
	end
end

local function joinSmaller(player: Player)
	join(player, if #teams.Blue:GetPlayers() <= #teams.Orange:GetPlayers() then "Blue" else "Orange")
end

-- Players picked onto a team in the dev panel ("TeamPick") or by Matchmaker (presetTeams) go there
-- first (if it has room); the rest are shuffled onto the smaller team. Anyone left over (teams
-- full) sits the match out.
local function assignTeams()
	local players = Players:GetPlayers()
	-- Shuffle so teams are different each match
	for i = #players, 2, -1 do
		local j = math.random(i)
		players[i], players[j] = players[j], players[i]
	end
	for _, player in players do
		local pick = player:GetAttribute("TeamPick") or presetTeams[player]
		if pick and teams[pick] then
			join(player, pick)
		end
	end
	for _, player in players do
		if player.Neutral then
			joinSmaller(player)
		end
	end
end

local function resetToFreeRoam()
	AbilityService.ClearDeployables()
	for _, player in Players:GetPlayers() do
		player.Team = nil
		player.Neutral = true
		LoadoutService.Reset(player)
		task.spawn(spawnFreeRoam, player)
	end
end

-- Decides the round in Attack / Defend. Returns winner team name + reason, or nil to keep going.
local function checkAttackDefend(attack: string, defend: string, attackOut: boolean, defendOut: boolean, timeUp: boolean): (string?, string?)
	local objective = ObjectiveService.GetStatus()
	if objective == "Defused" then
		return attack, "BOMB DEFUSED"
	elseif objective == "Disabled" then
		return defend, "DEFUSER DISABLED"
	elseif objective == "Planted" then
		-- Once planted, killing the attackers isn't enough: defenders have to disable the defuser
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
	-- Fresh map every round: broken walls, glass and barricades all come back
	MapService.Load(MatchState:GetAttribute("Map") or MatchConfig.DefaultMap)
	CameraService.SetOwner(defend)
	AbilityService.ClearDeployables()
	ObjectiveService.EndRound()
	DroneService.Reset()
	-- Site pair: random until the defenders pick one during the freeze (PickSite)
	local sitePairs = ObjectiveService.GetPairs()
	MatchState:SetAttribute("SitePair", if #sitePairs > 0 then sitePairs[math.random(#sitePairs)] else nil)
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
	-- Defenders' shared wall reinforcements (FortifyService)
	MatchState:SetAttribute("Reinforcements", startedWith[defend] * MatchConfig.ReinforcementsPerDefender)

	-- Loadouts are handed out (or drafted) during the freeze
	local loadoutMode = MatchState:GetAttribute("LoadoutMode") or MatchConfig.DefaultLoadoutMode
	local freezeTime = if loadoutMode == "Draft" then MatchConfig.DraftTime else MatchConfig.PreRoundTime
	local roundPlayers = {}
	for _, teamName in MatchConfig.TeamOrder do
		for _, player in teams[teamName]:GetPlayers() do
			table.insert(roundPlayers, player)
		end
	end
	-- Loadouts can be picked (and changed) right up until the round starts, which in Attack /
	-- Defend includes the defenders' setup time
	local pickTime = freezeTime + (if mode == "AttackDefend" then MatchConfig.PrepTime else 0)
	LoadoutService.StartRound(roundPlayers, loadoutMode, pickTime)

	setPhase("PreRound", freezeTime, `ROUND {round}`)
	task.wait(freezeTime)

	-- Attack / Defend: defenders get time to set up while attackers scout with drones from spawn
	if mode == "AttackDefend" then
		unfreezeTeam(defend)
		ObjectiveService.PlaceBombs() -- the defenders' pick is final now
		setPhase("Prep", MatchConfig.PrepTime, "DEFENDERS ARE SETTING UP")
		DroneService.StartPrep(teams[attack])
		task.wait(MatchConfig.PrepTime)
		if abortMatch then
			return nil, nil
		end
		ObjectiveService.BeginRound(teams[attack], teams[defend])
	end
	LoadoutService.FinishRound() -- anyone who didn't pick gets one of their cards
	DroneService.StartAction()
	unfreezeTeam(attack)
	unfreezeTeam(defend)

	-- Attackers only know where the defenders are if a drone found it (DroneService)
	local sitePair = MatchState:GetAttribute("SitePair")
	local found = MatchState:GetAttribute("SiteFound") == true
	local actionBanner = if mode ~= "AttackDefend" then nil
		elseif sitePair and found then `ATTACK · {string.upper(sitePair)}`
		elseif sitePair then "ATTACK · FIND THE OBJECTIVE"
		else "ATTACK!"
	setPhase("Action", MatchConfig.RoundTime, actionBanner)
	local deadline = os.clock() + MatchConfig.RoundTime
	local planted = false
	endRoundNow = false

	while true do
		task.wait(0.2)
		if abortMatch then
			ObjectiveService.EndRound()
			DroneService.Reset()
			return nil, nil
		end
		-- The plant replaces the round timer with the defuser's timer
		if not planted and ObjectiveService.GetStatus() == "Planted" then
			planted = true
			setPhase("Planted", MatchConfig.DefuserTime, "DEFUSER PLANTED")
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
			DroneService.Reset()
			return winner, reason
		end
	end
end

local function runMatch()
	matchRunning = true
	abortMatch = false
	assignTeams()
	MatchStats.Begin()
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
			MatchStats.RoundWon(teams[winner])
			for _, player in teams[winner]:GetPlayers() do
				ShopService.Award(player, MatchConfig.Credits.RoundWin, "ROUND WON")
				ProgressService.Record(player, "RoundWin")
			end
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
		for _, teamName in MatchConfig.TeamOrder do
			for _, player in teams[teamName]:GetPlayers() do
				ShopService.Award(player, MatchConfig.Credits.MatchPlayed, "MATCH COMPLETE")
				ProgressService.Record(player, "MatchPlayed")
				if teamName == matchWinner then
					ShopService.Award(player, MatchConfig.Credits.MatchWin, "MATCH WON")
					ProgressService.Record(player, "MatchWin")
				end
			end
		end
		-- Long enough for the results screen too (MatchStats: the banner first, then the MVP screen)
		local overTime = math.max(MatchConfig.MatchOverTime, MatchStats.ResultsDelay + MatchStats.ResultsTime)
		setPhase("MatchOver", overTime, `{string.upper(matchWinner)} WINS THE MATCH`)
		MatchStats.Finish(matchWinner, scores, function(player)
			return bodies[player]
		end)
		task.wait(overTime)
	end

	matchRunning = false
	MatchStats.Stop()
	table.clear(presetTeams) -- (Matchmaker's teams were for this match only)
	ObjectiveService.EndRound()
	DroneService.Reset()
	MatchState:SetAttribute("Round", 0)
	MatchState:SetAttribute("AttackTeam", nil)
	MatchState:SetAttribute("SitePair", nil)
	MatchState:SetAttribute("Rules", nil) -- (free roam is always Classic)
	setScores({ Blue = 0, Orange = 0 })
	resetToFreeRoam()
end

-- Most votes in `attribute` among `options`; ties are settled at random. With no votes at all:
-- `fallback`, or a random option.
local function countVotes(attribute: string, options: { string }, fallback: string?): string
	local counts = {}
	for _, player in Players:GetPlayers() do
		local vote = player:GetAttribute(attribute)
		if vote then
			counts[vote] = (counts[vote] or 0) + 1
		end
	end
	local best, most = {}, -1
	for _, name in options do
		local count = counts[name] or 0
		if count > most then
			best, most = { name }, count
		elseif count == most then
			table.insert(best, name)
		end
	end
	if most == 0 and fallback then
		return fallback
	end
	return best[math.random(#best)]
end

-- Everyone votes for a map and a mode (GameRules: Classic, Snipers Only, Knives Only...) at the
-- same time (client MapVote). Most votes wins; no votes means a random map and Classic. The vote
-- doubles as the countdown before the match.
local function voteMap()
	for _, player in Players:GetPlayers() do
		player:SetAttribute("MapVote", nil)
		player:SetAttribute("RulesVote", nil)
	end
	local ruleIds = {}
	for _, rules in GameRules.List do
		table.insert(ruleIds, rules.Id)
	end
	MatchState:SetAttribute("VoteMaps", table.concat(MapService.MapNames, ","))
	MatchState:SetAttribute("VoteRules", table.concat(ruleIds, ","))
	MatchState:SetAttribute("VoteWinner", nil)
	MatchState:SetAttribute("RulesWinner", nil)
	setPhase("Vote", MatchConfig.MapVoteTime)
	task.wait(MatchConfig.MapVoteTime)

	local winner = countVotes("MapVote", MapService.MapNames)
	local rules = countVotes("RulesVote", ruleIds, "Classic")
	MapService.Load(winner)
	MatchState:SetAttribute("Rules", rules)
	MatchState:SetAttribute("VoteWinner", winner)
	MatchState:SetAttribute("RulesWinner", rules)
	task.wait(2.5) -- (the winning cards light up)
end

-- Match server: start once everyone teleported in has arrived (or after a wait, with whoever made
-- it). Lobby: only a dev / Studio queue starts one.
local function readyToStart(waitingSince: number): boolean
	if forceStart then
		return true
	end
	if not IS_MATCH_SERVER then
		return false
	end
	local arrived = #Players:GetPlayers()
	local expected = MatchState:GetAttribute("Expected") or math.huge
	return arrived >= expected or (arrived >= 2 and os.clock() - waitingSince > MatchConfig.ArrivalTimeout)
end

-- Match over (or it can't go ahead): everyone back to a lobby, i.e. a public server of this place.
-- The parties go along in the teleport data so they form again there (PartyService).
local function sendToLobby()
	for attempt = 1, 3 do
		local players = Players:GetPlayers()
		if #players == 0 then
			return
		end
		local options = Instance.new("TeleportOptions")
		options:SetTeleportData({ Parties = PartyService.ForTeleport(players) })
		local ok, err = pcall(TeleportService.TeleportAsync, TeleportService, game.PlaceId, players, options)
		if not ok then
			warn("Teleport back to the lobby failed:", err)
		end
		task.wait(10) -- (anyone still here after this didn't make it)
	end
	for _, player in Players:GetPlayers() do
		player:Kick("Match over! Rejoin to play again.")
	end
end

local function mainLoop()
	while true do
		forceStart = false
		setPhase("Waiting")
		local waitingSince = os.clock()
		repeat
			task.wait(0.5)
			if IS_MATCH_SERVER and not forceStart and os.clock() - waitingSince > MatchConfig.ArrivalTimeout and #Players:GetPlayers() < 2 then
				sendToLobby() -- nobody to play against
				waitingSince = os.clock()
			end
		until readyToStart(waitingSince)

		voteMap()
		runMatch()
		if IS_MATCH_SERVER then
			sendToLobby()
		end
	end
end

local function onCharacterAdded(player: Player, character: Model)
	-- Characters bump into railing guards; bullets and line-of-sight checks don't (MapService).
	-- Hats, hair, wings and the like are for show: bullets pass straight through them, so the
	-- hitbox is the same standard body for everyone (loadCharacter).
	local function joinGroup(part: Instance)
		if part:IsA("BasePart") then
			part.CollisionGroup = "Characters"
			if part.Parent and part.Parent:IsA("Accoutrement") then -- (accessories and old-style hats)
				part.CanQuery = false
				part.CanTouch = false
			end
		end
	end
	for _, part in character:GetDescendants() do
		joinGroup(part)
	end
	character.DescendantAdded:Connect(joinGroup)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	-- No floating names / Roblox health bars over heads (they'd show enemies through walls)
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.Died:Connect(function()
		local killerId = humanoid:GetAttribute("LastDamagedBy")
		local killer = if killerId then Players:GetPlayerByUserId(killerId) else nil
		local headshot = humanoid:GetAttribute("LastHitHeadshot") == true
		-- (the 4th argument is for the victim's kill cam: what did it, from where...)
		KillFeed:FireAllClients(killer, player, headshot, MatchStats.KillDetails(player, humanoid, killer))
		MatchStats.Death(player, humanoid, killer, headshot)
		-- Credits for killing an enemy in a match
		if matchRunning and killer and killer ~= player and killer.Team and killer.Team ~= player.Team then
			local credits = MatchConfig.Credits
			ShopService.Award(killer, credits.Kill + (if headshot then credits.Headshot else 0), if headshot then "HEADSHOT" else "KILL")
			-- XP, career stats, challenges (ProgressService)
			ProgressService.Record(killer, "Kill")
			if headshot then
				ProgressService.Record(killer, "Headshot")
			end
		end

		if isFreeRoam() then
			task.delay(MatchConfig.FreeRoamRespawnTime, function()
				if isFreeRoam() and player.Parent and player.Character == character then
					spawnFreeRoam(player)
				end
			end)
		end
	end)
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)

	-- Match server: Matchmaker's teleport data says the mode, who's coming and on which team
	local data = if IS_MATCH_SERVER then player:GetJoinData().TeleportData else nil
	if typeof(data) == "table" and typeof(data.Players) == "table" and not MatchState:GetAttribute("Expected") then
		MatchState:SetAttribute("Expected", math.clamp(#data.Players, 2, MatchConfig.MaxTeamSize * 2))
		MatchState:SetAttribute("QueueMode", if typeof(data.Mode) == "string" then data.Mode else nil)
	end
	if typeof(data) == "table" and typeof(data.Teams) == "table" then
		for _, name in MatchConfig.TeamOrder do
			local ids = data.Teams[name]
			if typeof(ids) == "table" and table.find(ids, player.UserId) then
				presetTeams[player] = name
			end
		end
	end

	if matchRunning then
		-- Join your team (or the smaller one); you'll spawn at the start of the next round
		if presetTeams[player] then
			join(player, presetTeams[player])
		end
		if player.Neutral then
			joinSmaller(player)
		end
	else
		spawnFreeRoam(player)
	end
end

-- Respawn a player between matches (lobby, or the map if they chose that in the dev panel)
function RoundService.SpawnFreeRoam(player: Player)
	if not matchRunning then
		task.spawn(spawnFreeRoam, player)
	end
end

-- `picks`: who plays on which team (Matchmaker in Studio, so a party plays together)
function RoundService.ForceStart(picks: { [Player]: string }?)
	forceStart = true
	if picks then
		for player, name in picks do
			presetTeams[player] = name
		end
	end
end

function RoundService.IsMatchRunning(): boolean
	return matchRunning
end

function RoundService.IsMatchServer(): boolean
	return IS_MATCH_SERVER
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
	MatchState:SetAttribute("ServerKind", if IS_MATCH_SERVER then "Match" else "Lobby")
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

	-- Defenders choosing where to defend during the freeze (SitePicker): the last pick counts, and
	-- the whole team moves to that pair's spawn right away
	PickSite.OnServerEvent:Connect(function(player, pair)
		local attackTeam = MatchState:GetAttribute("AttackTeam")
		if not matchRunning or MatchState:GetAttribute("Phase") ~= "PreRound" or not player.Team or player.Team.Name == attackTeam then
			return
		end
		if typeof(pair) ~= "string" or not table.find(ObjectiveService.GetPairs(), pair) then
			return
		end
		MatchState:SetAttribute("SitePair", pair)
		placeTeam(player.Team.Name, "Defend")
	end)

	-- VoteMap(name) votes for a map, VoteMap(id, "Rules") for a mode
	VoteMap.OnServerEvent:Connect(function(player, name, kind)
		if MatchState:GetAttribute("Phase") ~= "Vote" or MatchState:GetAttribute("VoteWinner") or typeof(name) ~= "string" then
			return
		end
		if kind == "Rules" then
			if GameRules.ById[name] then
				player:SetAttribute("RulesVote", name)
			end
		elseif table.find(MapService.MapNames, name) then
			player:SetAttribute("MapVote", name)
		end
	end)

	task.spawn(mainLoop)
end

return RoundService
