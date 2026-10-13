-- The first-time tutorial (client Match/Tutorial): remembers who has been offered it and who has
-- finished it (PlayerData TutorialSeen / TutorialDone), and pays out its credits once.
--   Tutorial:FireServer("Seen")   offered it (started or skipped): the lobby doesn't ask again
--   Tutorial:FireServer("Done")   finished it: TutorialDone, and REWARD credits the first time only
-- The client decides when each step is done (it's only a walkthrough), so the server just makes
-- the reward hard to farm: once per account (TutorialDone is saved), lobby servers only, not in
-- the first MIN_TIME seconds after joining, and only after a visit to the practice range when this
-- server has one (most of the steps happen in there).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local PlayerData = require(script.Parent.PlayerData)
local ShopService = require(script.Parent.ShopService)

local MatchState = ReplicatedStorage:WaitForChild("MatchState")

local TutorialService = {}

TutorialService.Reward = 250 -- credits for finishing it the first time (the client shows the same figure)

local MIN_TIME = 45 -- seconds in the server before "Done" can pay (the walkthrough takes ~2 minutes)
local RANGE_ATTRIBUTE = "InPracticeRange" -- set by PracticeRange while you're in the range

local joinedAt: { [Player]: number } = {}
local visitedRange: { [Player]: boolean } = {}
local lastRequest: { [Player]: number } = {}

local function finish(player: Player)
	local data = PlayerData.Get(player)
	if not data or data.TutorialDone then
		return
	end
	if MatchState:GetAttribute("ServerKind") ~= "Lobby" or player:GetAttribute("Location") ~= "Lobby" then
		return
	end
	if os.clock() - (joinedAt[player] or os.clock()) < MIN_TIME then
		return
	end
	if Workspace:FindFirstChild("PracticeRange") and not visitedRange[player] then
		return
	end
	-- (credits first: the save queued just below then writes both)
	ShopService.Award(player, TutorialService.Reward, "TUTORIAL")
	PlayerData.Update(player, function(stored)
		stored.TutorialDone = true
		stored.TutorialSeen = true
	end, true)
end

function TutorialService.Start()
	-- (made here like PracticeRange's "Practice" remote; the client waits for it)
	local remote = Instance.new("RemoteEvent")
	remote.Name = "Tutorial"
	remote.Parent = ReplicatedStorage:WaitForChild("Remotes")

	remote.OnServerEvent:Connect(function(player, kind)
		local now = os.clock()
		if now - (lastRequest[player] or 0) < 0.5 then
			return
		end
		lastRequest[player] = now
		if kind == "Seen" then
			local data = PlayerData.Get(player)
			if data and not data.TutorialSeen then
				PlayerData.Update(player, function(stored)
					stored.TutorialSeen = true
				end, true)
			end
		elseif kind == "Done" then
			finish(player)
		end
	end)

	local function watch(player: Player)
		joinedAt[player] = os.clock()
		player:GetAttributeChangedSignal(RANGE_ATTRIBUTE):Connect(function()
			if player:GetAttribute(RANGE_ATTRIBUTE) == true then
				visitedRange[player] = true
			end
		end)
	end
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(player)
		joinedAt[player] = nil
		visitedRange[player] = nil
		lastRequest[player] = nil
	end)
end

return TutorialService
