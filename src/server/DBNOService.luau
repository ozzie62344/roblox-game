-- DOWN BUT NOT OUT on the server (the rules and numbers: Shared/DBNO). WeaponService asks TryDown
-- before a hit lands: a lethal hit that should only down someone puts them on the floor instead.
-- Their Health becomes the small down pool, which bleeds away here; any hit while downed comes off
-- it as normal, so finishing someone off is just shooting / knifing them.
-- While downed they can't shoot, knife, use gadgets, plant, fortify, drone or watch cameras (each
-- of those checks the character's "Downed" attribute) and their own client makes them crawl.
-- Kill credit: bleeding out gives the kill to whoever downed them (LastDamagedBy is put back to
-- them first), so the kill feed, kill cam, credits and MatchStats work as for any death; a finisher
-- gets the kill instead and the downer an assist (MatchStats, from the damage they did).
-- Reviving: a teammate holds Interact (G / the phone's USE) next to them (ObjectiveController
-- offers it). Like a plant, the reviver's Interaction is "Revive" (locked in place, progress) and
-- the downed body's ReviveEndsAt / RevivedBy show it; the bleed pauses meanwhile. Moving apart, the
-- reviver taking damage or going down, or letting go of the key breaks it off.
-- A team with nobody left standing is wiped: its downed players bleed out on the spot (Siege).
-- The "DBNO" remote (made here): server → everyone ("Downed", victim, attacker) for the kill feed
-- and ("Revived", who, by); client → server ("HoldWound", holding).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local DBNO = require(ReplicatedStorage.Shared.DBNO)

local Interact = ReplicatedStorage.Remotes.Interact :: RemoteEvent
local MatchState = ReplicatedStorage.MatchState

local DBNOService = {}

type Down = { player: Player, humanoid: Humanoid, character: Model, holding: boolean }
type Revive = { target: Down, endsAt: number, health: number }

local downs: { [Humanoid]: Down } = {}
local revives: { [Player]: Revive } = {} -- by reviver
local remote: RemoteEvent

local function isLive(): boolean
	return DBNO.LivePhases[MatchState:GetAttribute("Phase")] == true
end

local function rootOf(character: Model?): BasePart?
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- In a match, alive and on their feet
local function standing(player: Player): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0 and character:GetAttribute("Downed") ~= true and player:GetAttribute("Location") == "Match"
end

local function anyoneStanding(team: Team, except: Player?): boolean
	for _, other in team:GetPlayers() do
		if other ~= except and standing(other) then
			return true
		end
	end
	return false
end

local function stopRevive(reviver: Player)
	local revive = revives[reviver]
	if not revive then
		return
	end
	revives[reviver] = nil
	if reviver:GetAttribute("Interaction") == "Revive" then
		reviver:SetAttribute("Interaction", nil)
		reviver:SetAttribute("InteractEndsAt", nil)
	end
	local character = revive.target.character
	if character:GetAttribute("RevivedBy") == reviver.UserId then
		character:SetAttribute("ReviveEndsAt", nil)
		character:SetAttribute("RevivedBy", nil)
	end
end

-- Back up (revived), dead or gone: no longer downed. WasDowned stays (a second down kills).
local function clearDown(down: Down)
	if downs[down.humanoid] == down then
		downs[down.humanoid] = nil
	end
	for reviver, revive in revives do
		if revive.target == down then
			stopRevive(reviver)
		end
	end
	for _, name in { "Downed", "DownedBy", "DownedWith", "HoldingWound", "ReviveEndsAt", "RevivedBy" } do
		down.character:SetAttribute(name, nil)
	end
end

-- Dies of the down: the kill goes to whoever put them down (RoundService reads LastDamagedBy)
local function bleedOut(down: Down)
	local humanoid, character = down.humanoid, down.character
	humanoid:SetAttribute("LastDamagedBy", character:GetAttribute("DownedBy"))
	humanoid:SetAttribute("LastHitHeadshot", false)
	humanoid:SetAttribute("LastHitWith", character:GetAttribute("DownedWith"))
	humanoid.Health = 0
end

local function goDown(player: Player, humanoid: Humanoid, character: Model)
	local attackerId = humanoid:GetAttribute("LastDamagedBy")
	humanoid.Health = DBNO.DownHealth
	character:SetAttribute("Downed", true)
	character:SetAttribute("WasDowned", true)
	character:SetAttribute("DownedBy", attackerId)
	character:SetAttribute("DownedWith", humanoid:GetAttribute("LastHitWith"))
	character:SetAttribute("HoldingWound", nil)
	-- On the floor for everyone right away (their own client keeps them there: MovementController)
	character:SetAttribute("Crouching", true)
	character:SetAttribute("Prone", true)
	-- Kicked out of the drone / off the cameras, back to the body (Siege). Plants and fortifying
	-- stop on their own (ObjectiveService / FortifyService check Downed every frame).
	player:SetAttribute("Droning", nil)
	player:SetAttribute("OnCams", nil)
	stopRevive(player)
	downs[humanoid] = { player = player, humanoid = humanoid, character = character, holding = false }
	local attacker = if typeof(attackerId) == "number" then Players:GetPlayerByUserId(attackerId) else nil
	remote:FireAllClients("Downed", player, attacker)
end

-- WeaponService, just before `damage` lands on `humanoid`: true = it downed them instead (the hit
-- is used up). A hit only downs a player on a team in a live round, who'd die from it, if it isn't
-- a headshot, isn't a big overkill (less for a blast), isn't their second down this life, and a
-- teammate is still standing to pick them up.
function DBNOService.TryDown(humanoid: Humanoid, damage: number, headshot: boolean, with: string?): boolean
	local character = humanoid.Parent
	local player = if character then Players:GetPlayerFromCharacter(character) else nil
	if not player or not character or not character:IsA("Model") or downs[humanoid] then
		return false -- (already downed: the hit comes off the down pool)
	end
	if humanoid.Health <= 0 or damage < humanoid.Health or headshot or character:GetAttribute("WasDowned") then
		return false
	end
	if player:GetAttribute("Location") ~= "Match" or player.Neutral or not player.Team or not isLive() then
		return false
	end
	local overkill = damage - humanoid.Health
	if overkill >= (if with == "Blast" then DBNO.BlastKillOverkill else DBNO.KillOverkill) then
		return false
	end
	if not anyoneStanding(player.Team, player) then
		return false -- nobody to pick them up: the team's done
	end
	goDown(player, humanoid, character)
	return true
end

function DBNOService.IsDowned(player: Player): boolean
	local character = player.Character
	return character ~= nil and character:GetAttribute("Downed") == true
end

-- Interact "Begin" "Revive" with the downed teammate's root part
local function startRevive(reviver: Player, part: any)
	if revives[reviver] or reviver:GetAttribute("Interaction") or not isLive() then
		return
	end
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") or not part.Parent then
		return
	end
	local targetHumanoid = part.Parent:FindFirstChildOfClass("Humanoid")
	local down = targetHumanoid and downs[targetHumanoid]
	if not down or down.player == reviver or down.humanoid.Health <= 0 or down.character:GetAttribute("RevivedBy") then
		return -- (someone's already on them)
	end
	if reviver.Neutral or reviver.Team ~= down.player.Team or not standing(reviver) then
		return
	end
	local root, targetRoot = rootOf(reviver.Character), rootOf(down.character)
	local humanoid = (reviver.Character :: Model):FindFirstChildOfClass("Humanoid") :: Humanoid
	if not root or not targetRoot or root.Anchored or (root.Position - targetRoot.Position).Magnitude > DBNO.ReviveRange then
		return
	end
	local endsAt = Workspace:GetServerTimeNow() + DBNO.ReviveTime
	revives[reviver] = { target = down, endsAt = endsAt, health = humanoid.Health }
	reviver:SetAttribute("Interaction", "Revive")
	reviver:SetAttribute("InteractEndsAt", endsAt)
	down.character:SetAttribute("ReviveEndsAt", endsAt)
	down.character:SetAttribute("RevivedBy", reviver.UserId)
end

local function finishRevive(reviver: Player, revive: Revive)
	local down = revive.target
	stopRevive(reviver)
	clearDown(down)
	down.humanoid.Health = math.min(DBNO.RevivedHealth, down.humanoid.MaxHealth)
	remote:FireAllClients("Revived", down.player, reviver)
end

-- Is this revive still on? (both still there, close, the reviver unhurt and still holding)
local function reviveHolds(reviver: Player, revive: Revive): boolean
	local down = revive.target
	local character = reviver.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root, targetRoot = rootOf(character), rootOf(down.character)
	if not reviver.Parent or not humanoid or not root or not targetRoot or not standing(reviver) then
		return false
	end
	if downs[down.humanoid] ~= down or down.humanoid.Health <= 0 or reviver:GetAttribute("Interaction") ~= "Revive" then
		return false
	end
	if humanoid.Health < revive.health then
		return false -- the reviver got hit
	end
	return (root.Position - targetRoot.Position).Magnitude <= DBNO.ReviveBreakRange
end

local function update(dt: number)
	local live = isLive()
	local now = Workspace:GetServerTimeNow()
	for reviver, revive in revives do
		if not live or not reviveHolds(reviver, revive) then
			stopRevive(reviver)
		elseif now >= revive.endsAt then
			finishRevive(reviver, revive)
		end
	end

	-- Bleeding out (only while the round is live; paused while someone's picking you up)
	for humanoid, down in downs do
		if humanoid.Health <= 0 or not down.character.Parent or down.player.Character ~= down.character then
			clearDown(down) -- dead, respawned or gone
		elseif humanoid.Health > DBNO.DownHealth + 0.01 then
			clearDown(down) -- healed past the down pool (the dev panel's heal): back up
		elseif live and not down.character:GetAttribute("RevivedBy") then
			local rate = DBNO.DownHealth / DBNO.BleedTime * (if down.holding then DBNO.HoldWoundScale else 1)
			local left = humanoid.Health - rate * dt
			if left <= 0 then
				bleedOut(down)
			else
				humanoid.Health = left
			end
		end
	end

	-- Nobody left standing on a team: nobody can pick its downed up, so they're done (Siege).
	-- (only in a live round: after it they just lie there until everyone respawns)
	for humanoid, down in downs do
		local team = down.player.Team
		if live and team and humanoid.Health > 0 and not anyoneStanding(team) then
			bleedOut(down)
		end
	end
end

function DBNOService.Start()
	remote = Instance.new("RemoteEvent")
	remote.Name = "DBNO"
	remote.Parent = ReplicatedStorage.Remotes

	-- Holding your wound (F / the phone's HOLD WOUND): bleeds slower, no crawling (client)
	remote.OnServerEvent:Connect(function(player, action, holding)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local down = humanoid and downs[humanoid]
		if action == "HoldWound" and down then
			down.holding = holding == true
			down.character:SetAttribute("HoldingWound", if down.holding then true else nil)
		end
	end)

	-- G shares the remote with plant / disable (ObjectiveService) and fortifying (FortifyService)
	Interact.OnServerEvent:Connect(function(player, action, kind, target)
		if action == "End" then
			stopRevive(player)
		elseif action == "Begin" and kind == "Revive" then
			startRevive(player, target)
		end
	end)
	Players.PlayerRemoving:Connect(stopRevive)
	RunService.Heartbeat:Connect(update)
end

return DBNOService
