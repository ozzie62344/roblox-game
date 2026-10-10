-- The very first thing on your screen: our loading screen instead of Roblox's, until the game and
-- your character are ready. Arriving in a match from the lobby, it says which mode.

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local TeleportService = game:GetService("TeleportService")

local LoadingScreen = require(script.Parent:WaitForChild("LoadingScreen"))

local MIN_TIME = 2.5 -- (so it doesn't just flash by)
local MAX_TIME = 20 -- never stuck on it

local player = Players.LocalPlayer
local data = TeleportService:GetLocalPlayerTeleportData()
local mode = if typeof(data) == "table" and typeof(data.Mode) == "string" then data.Mode else nil

local gui = LoadingScreen.Build(if mode then `LOADING {mode} MATCH...` else "LOADING...")
gui.Parent = player:WaitForChild("PlayerGui")
ReplicatedFirst:RemoveDefaultLoadingScreen()

local started = os.clock()
local function ready(): boolean
	return game:IsLoaded() and ContentProvider.RequestQueueSize == 0 and player.Character ~= nil
end
local shown = 0
while os.clock() - started < MAX_TIME and not (ready() and os.clock() - started >= MIN_TIME) do
	-- Creeps toward 90% while loading, fills up once it's done
	local target = if ready() then 1 else math.min(0.9, (os.clock() - started) / 8)
	shown += (target - shown) * 0.08
	LoadingScreen.SetProgress(gui, shown)
	task.wait()
end
LoadingScreen.SetProgress(gui, 1)
task.wait(0.25)
LoadingScreen.FadeOut(gui)
