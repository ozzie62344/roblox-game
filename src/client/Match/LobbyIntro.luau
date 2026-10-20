-- Arriving in the lobby: the menus come in one after another instead of all in the same frame,
-- each with a little pop, and only one popup (daily reward, NEW HERE?) is up at a time.
--   InLobby()      you're on the lobby's menu screen (not in a match or the practice range)
--   Shown(piece)   InLobby, and the intro has reached that piece (ORDER, seconds after arriving)
--   Animate(obj)   pops `obj` (or `target`) in when it appears during the intro; popups every time
--   OpenPopup / ClosePopup / PopupFree   one popup at a time, with a breath between them
-- "Arriving" is the loading screen going away (ReplicatedFirst Loading sets LoadingDone), or coming
-- back to the lobby menu after a match on the same server (Studio).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local state = require(script.Parent.Parent.PlayerState)

local MatchState = ReplicatedStorage:WaitForChild("MatchState")
local player = Players.LocalPlayer

local LobbyIntro = {}

-- Seconds after arriving that each piece comes in
local ORDER: { [string]: number } = {
	MainMenu = 0.15,
	Party = 0.4,
	Custom = 0.5,
	Tutorial = 0.6,
	Shop = 0.75,
	Clan = 0.85,
	Progress = 0.95,
	Settings = 1.05,
	DailyPopup = 1.8,
	TutorialPrompt = 2.2, -- (NEW HERE? after the daily reward, if that's up: one popup at a time)
}
local INTRO_TIME = 2.5 -- pieces appearing after this just appear (a menu closing, say)
local POPUP_GAP = 0.6 -- seconds between one popup closing and the next opening
local LOADING_TIMEOUT = 25 -- (the loading screen never said it was done: carry on anyway)
local POP_FROM = 0.86

local arrivedAt: number? = nil
local openPopup: string? = nil
local popupClosedAt = 0

function LobbyIntro.InLobby(): boolean
	return MatchState:GetAttribute("ServerKind") == "Lobby"
		and player:GetAttribute("Location") == "Lobby"
		and not state.inPractice
		and MatchState:GetAttribute("Phase") == "Waiting"
end

local function since(): number?
	return if arrivedAt then os.clock() - arrivedAt else nil
end

function LobbyIntro.Shown(piece: string): boolean
	local elapsed = since()
	return elapsed ~= nil and elapsed >= (ORDER[piece] or 0) and LobbyIntro.InLobby()
end

-- Grows `target` from a little smaller to its size with an overshoot. Uses its UIScale if it has
-- one (MenuStyle.FitToScreen), ending at that scale.
local function pop(target: GuiObject)
	local scale = target:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Name = "IntroScale"
		scale.Parent = target
	end
	local goal = scale:GetAttribute("IntroGoal") or scale.Scale -- (a pop mid-pop ends at the real size)
	scale:SetAttribute("IntroGoal", goal)
	scale.Scale = goal * POP_FROM
	local tween = TweenService:Create(scale, TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = goal })
	tween.Completed:Connect(function()
		scale:SetAttribute("IntroGoal", nil)
	end)
	tween:Play()
end

-- Pops `target` (default `object`) in whenever `object` becomes visible during the intro, or
-- every time with `always` (popups)
function LobbyIntro.Animate(object: GuiObject, target: GuiObject?, always: boolean?)
	object:GetPropertyChangedSignal("Visible"):Connect(function()
		local elapsed = since()
		if object.Visible and (always or (elapsed ~= nil and elapsed < INTRO_TIME)) then
			pop(target or object)
		end
	end)
end

-- One popup at a time: `name` may open now?
function LobbyIntro.PopupFree(name: string): boolean
	return (openPopup == nil or openPopup == name) and os.clock() - popupClosedAt >= POPUP_GAP
end

function LobbyIntro.OpenPopup(name: string)
	openPopup = name
end

function LobbyIntro.ClosePopup(name: string)
	if openPopup == name then
		openPopup = nil
		popupClosedAt = os.clock()
	end
end

function LobbyIntro.Start()
	local startedAt = os.clock()
	RunService.RenderStepped:Connect(function()
		local loaded = player:GetAttribute("LoadingDone") == true or os.clock() - startedAt > LOADING_TIMEOUT
		if loaded and LobbyIntro.InLobby() then
			arrivedAt = arrivedAt or os.clock()
		else
			arrivedAt = nil -- (next time you reach the lobby menu, it comes in again)
		end
	end)
end

return LobbyIntro
