-- Who did what this match: kills, deaths, assists, headshots, objective plays (plant / disable),
-- shots fired and hit, and rounds won, and from those a score. The best score is the match MVP. At the end of a match
-- everyone gets the results (MatchResults remote → client MatchResults: the MVP and both teams'
-- scoreboard), plus a standing copy of the MVP's body for the screen to show.
-- RoundService begins / finishes it and reports deaths and round wins; WeaponService reports
-- damage (anyone who hurt a victim and didn't get the kill gets an assist); ObjectiveService
-- reports plants and disables. Nothing counts outside a match (free roam).
-- Also works out the details of a kill for the victim's KILL CAM (KillDetails, sent with the kill feed).
-- The in-match scoreboard (client Scoreboard) reads everyone's kills / deaths / assists live from
-- player attributes (MatchKills / MatchDeaths / MatchAssists: set as they change, cleared when the
-- match is over) and their Ping (ms, every couple of seconds, free roam too).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Skins = require(ReplicatedStorage.Shared.Skins)

local MatchResults = ReplicatedStorage.Remotes.MatchResults :: RemoteEvent

local MatchStats = {}

-- Points for the score (Siege-like: a kill is worth twice an assist; planting or disabling the
-- defuser as much as a kill)
local SCORE = { Kill = 100, Headshot = 25, Assist = 50, Objective = 100, RoundWin = 40 }
local ASSIST_DAMAGE = 10 -- damage you must have done to a victim for an assist
local PING_EVERY = 2 -- seconds between Ping updates
local BODY_NAME = "MvpBody"

-- The results screen: the "X WINS THE MATCH" banner shows on its own this long first, then the
-- screen stays up at least ResultsTime (RoundService keeps the match over until both have passed,
-- before everyone goes back to the lobby)
MatchStats.ResultsDelay = 2
MatchStats.ResultsTime = 10

export type Line = {
	userId: number,
	name: string,
	team: string,
	kills: number,
	deaths: number,
	assists: number,
	headshots: number,
	objectives: number,
	rounds: number,
	shots: number, -- trigger pulls with a gun (WeaponService), for accuracy
	hits: number, -- ...that hit an enemy
}

local active = false
local lines: { [number]: Line } = {} -- by UserId (kept if they leave, so the scoreboard still has them)
-- Damage each attacker did to a victim this life (for assists), forgotten when the body goes
local damageTo: { [Humanoid]: { [Player]: number } } = {} -- (plain: cleared on each death and at every match start)

-- The live numbers on the player (for the scoreboard), if they're here
local function publish(line: Line)
	local player = Players:GetPlayerByUserId(line.userId)
	if player then
		player:SetAttribute("MatchKills", line.kills)
		player:SetAttribute("MatchDeaths", line.deaths)
		player:SetAttribute("MatchAssists", line.assists)
	end
end

local function clearPublished()
	for _, player in Players:GetPlayers() do
		player:SetAttribute("MatchKills", nil)
		player:SetAttribute("MatchDeaths", nil)
		player:SetAttribute("MatchAssists", nil)
	end
end

-- Only players on a team count
local function lineFor(player: Player?): Line?
	if not active or not player or player.Neutral or not player.Team then
		return nil
	end
	local line = lines[player.UserId]
	if not line then
		line = {
			userId = player.UserId, name = player.DisplayName, team = player.Team.Name,
			kills = 0, deaths = 0, assists = 0, headshots = 0, objectives = 0, rounds = 0, shots = 0, hits = 0,
		}
		lines[player.UserId] = line
		publish(line)
	end
	line.team = player.Team.Name
	return line
end

local function score(line: Line): number
	return line.kills * SCORE.Kill + line.headshots * SCORE.Headshot + line.assists * SCORE.Assist
		+ line.objectives * SCORE.Objective + line.rounds * SCORE.RoundWin
end

-- Everyone's numbers so far, by UserId (RankedService: how each played against the average)
function MatchStats.Lines(): { [number]: Line }
	return table.clone(lines)
end

-- A new match: everyone on a team starts at zero
function MatchStats.Begin()
	table.clear(lines)
	table.clear(damageTo)
	clearPublished()
	active = true
	local old = ReplicatedStorage:FindFirstChild(BODY_NAME)
	if old then
		old:Destroy()
	end
	for _, player in Players:GetPlayers() do
		lineFor(player)
	end
end

-- The match is over (finished or stopped): stop counting
function MatchStats.Stop()
	active = false
	clearPublished()
end

-- WeaponService, before the damage is dealt (only what the victim still had counts)
function MatchStats.Damage(attacker: Player, victim: Humanoid, amount: number)
	local victimPlayer = Players:GetPlayerFromCharacter(victim.Parent)
	if not active or not victimPlayer or victimPlayer == attacker or victim.Health <= 0 then
		return
	end
	local byAttacker = damageTo[victim] or {}
	damageTo[victim] = byAttacker
	byAttacker[attacker] = (byAttacker[attacker] or 0) + math.min(amount, victim.Health)
end

-- RoundService, when a player dies. `killer` is whoever hurt them last (nil: nobody / a fall).
function MatchStats.Death(victim: Player, humanoid: Humanoid, killer: Player?, headshot: boolean)
	local hurtBy = damageTo[humanoid]
	damageTo[humanoid] = nil
	local victimLine = lineFor(victim)
	if not victimLine then
		return
	end
	victimLine.deaths += 1
	publish(victimLine)
	local killerLine = if killer and killer ~= victim and killer.Team ~= victim.Team then lineFor(killer) else nil
	if killerLine then
		killerLine.kills += 1
		killerLine.headshots += if headshot then 1 else 0
		publish(killerLine)
	end
	for attacker, amount in hurtBy or {} do
		local line = if attacker ~= killer and attacker.Parent and amount >= ASSIST_DAMAGE then lineFor(attacker) else nil
		if line and line.team ~= victimLine.team then
			line.assists += 1
			publish(line)
		end
	end
end

-- WeaponService: one trigger pull (all of a shotgun's pellets together), and whether it hit an enemy
function MatchStats.Shot(player: Player, hit: boolean)
	local line = lineFor(player)
	if line then
		line.shots += 1
		line.hits += if hit then 1 else 0
	end
end

-- ObjectiveService: planted or disabled the defuser
function MatchStats.Objective(player: Player)
	local line = lineFor(player)
	if line then
		line.objectives += 1
	end
end

-- RoundService: everyone on this team won the round
function MatchStats.RoundWon(team: Team)
	for _, player in team:GetPlayers() do
		local line = lineFor(player)
		if line then
			line.rounds += 1
		end
	end
end

-- What killed `victim`, for their kill cam (sent with the kill feed): `with` is the weapon name,
-- "Knife" or "Blast" (WeaponService's LastHitWith), `at` where they died; with a killer, `from`
-- where the killer's head is, the killer's `health` left, the `distance` and the `skin` on what
-- they used.
function MatchStats.KillDetails(victim: Player, humanoid: Humanoid, killer: Player?): { [string]: any }
	local with = humanoid:GetAttribute("LastHitWith")
	local victimRoot = victim.Character and victim.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local details: { [string]: any } = { with = if typeof(with) == "string" then with else nil }
	details.at = if victimRoot then victimRoot.Position else nil
	if killer and killer ~= victim then
		local character = killer.Character
		local head = character and character:FindFirstChild("Head") :: BasePart?
		local killerHumanoid = character and character:FindFirstChildOfClass("Humanoid")
		details.from = if head then head.Position else nil
		details.health = if killerHumanoid then math.max(0, math.ceil(killerHumanoid.Health)) else 0
		details.distance = if head and victimRoot then math.floor((head.Position - victimRoot.Position).Magnitude + 0.5) else nil
		local skin = if details.with then Skins.EquippedFor(killer, details.with) else nil
		details.skin = if skin then skin.Name else nil
	end
	return details
end

-- A standing copy of the MVP's match body (same HumanoidDescription) for the results screen.
-- Built in the workspace for a frame (far above the map, anchored) so every joint and accessory
-- settles into place, then frozen and moved to ReplicatedStorage. nil if it can't be made.
local function buildBody(description: HumanoidDescription?): Model?
	if not description then
		return nil
	end
	local ok, model = pcall(Players.CreateHumanoidModelFromDescription, Players, description, Enum.HumanoidRigType.R15)
	if not ok or not model then
		return nil
	end
	for _, item in model:GetDescendants() do
		if item:IsA("LuaSourceContainer") then
			item:Destroy() -- (no Animate / Health scripts running in a picture)
		end
	end
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		root.Anchored = true
	end
	model:PivotTo(CFrame.new(0, 5000, 0))
	model.Parent = Workspace
	RunService.Heartbeat:Wait()
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
		end
	end
	model.Name = BODY_NAME
	model.Parent = ReplicatedStorage
	return model
end

-- The match is won: pick the MVP and send everyone the results. `bodyOf` gives a player's match
-- body (RoundService's HumanoidDescriptions).
function MatchStats.Finish(winner: string, scores: { [string]: number }, bodyOf: (Player) -> HumanoidDescription?)
	for _, player in Players:GetPlayers() do
		lineFor(player) -- (anyone who joined mid-match and hasn't done anything yet)
	end
	local rows = {}
	for _, line in lines do
		table.insert(rows, {
			userId = line.userId, name = line.name, team = line.team,
			kills = line.kills, deaths = line.deaths, assists = line.assists, headshots = line.headshots,
			objectives = line.objectives, score = score(line),
		})
	end
	-- Best score first; ties go to more kills, then fewer deaths
	table.sort(rows, function(a, b)
		if a.score ~= b.score then
			return a.score > b.score
		elseif a.kills ~= b.kills then
			return a.kills > b.kills
		end
		return a.deaths < b.deaths
	end)
	local mvp = rows[1]
	local mvpPlayer = if mvp then Players:GetPlayerByUserId(mvp.userId) else nil
	local weapon = if mvpPlayer then mvpPlayer:GetAttribute("Weapon") else nil
	MatchResults:FireAllClients({
		winner = winner,
		scores = scores,
		players = rows,
		mvp = if mvp then mvp.userId else nil,
		mvpWeapon = if typeof(weapon) == "string" then weapon else nil,
		mvpBody = if mvpPlayer then buildBody(bodyOf(mvpPlayer)) else nil,
		delay = MatchStats.ResultsDelay,
	})
	active = false
end

-- Everyone's ping on them as "Ping" (ms), roughly what Roblox's own player list shows:
-- GetNetworkPing is the one-way latency in seconds, so twice it is the round trip
local function publishPings()
	for _, player in Players:GetPlayers() do
		local ok, seconds = pcall(player.GetNetworkPing, player)
		if ok and typeof(seconds) == "number" then
			player:SetAttribute("Ping", math.floor(seconds * 2000 + 0.5))
		end
	end
end

function MatchStats.Start()
	-- Back mid-match (left and rejoined): their line is still here
	Players.PlayerAdded:Connect(function(player)
		local line = lines[player.UserId]
		if active and line then
			publish(line)
		end
	end)
	task.spawn(function()
		while true do
			publishPings()
			task.wait(PING_EVERY)
		end
	end)
end

return MatchStats
