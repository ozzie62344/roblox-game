-- Custom matches: a private lobby for you and your friends (server CustomMatchService, client
-- Match/CustomMatchMenu). The host picks the map, the objective, the mode and the rules below,
-- puts everyone on a team and starts; the match server plays it with those settings
-- (RoundService: the "Custom..." MatchState attributes Apply sets) and gives no rewards at all:
-- no XP, credits, ranked, career stats, challenges, leaderboard or clan stats (MatchState "Custom").
-- What every setting can be, its default and how it reads on screen live here, so the lobby, the
-- menu and the match server agree.

local MatchConfig = require(script.Parent.MatchConfig)
local GameRules = require(script.Parent.GameRules)

export type Settings = { [string]: any }

export type Setting = {
	Key: string,
	Label: string,
	Default: any,
	Options: { any }?, -- nil = the map list (only the server knows the maps: MapService.MapNames)
}

local CustomMatch = {}

CustomMatch.CodeLength = 6
CustomMatch.CodeAlphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789" -- (no 0 / O or 1 / I to mix up)
CustomMatch.TeamSize = MatchConfig.MaxTeamSize -- (the match HUD has room for this many a side)
CustomMatch.MaxSpectators = 2
CustomMatch.MaxPlayers = CustomMatch.TeamSize * 2 + CustomMatch.MaxSpectators
CustomMatch.RandomMap = "Random"

-- `list` with `value` in it (in order), so MatchConfig's numbers are always a choice
local function including(list: { number }, value: number): { number }
	if not table.find(list, value) then
		table.insert(list, value)
		table.sort(list)
	end
	return list
end

local ruleIds = {}
for _, rules in GameRules.List do
	table.insert(ruleIds, rules.Id)
end

-- Menu order
CustomMatch.Settings = {
	{ Key = "Map", Label = "MAP", Default = CustomMatch.RandomMap },
	{ Key = "GameMode", Label = "OBJECTIVE", Default = MatchConfig.DefaultGameMode, Options = { "AttackDefend", "Elimination" } },
	{ Key = "Rules", Label = "MODE", Default = "Classic", Options = ruleIds },
	{ Key = "RoundsToWin", Label = "ROUNDS TO WIN", Default = MatchConfig.RoundsToWin, Options = including({ 1, 2, 3, 4, 5, 6 }, MatchConfig.RoundsToWin) },
	{ Key = "PrepTime", Label = "PREP TIME", Default = MatchConfig.PrepTime, Options = including({ 15, 30, 45, 60, 90 }, MatchConfig.PrepTime) },
	{ Key = "RoundTime", Label = "ACTION TIME", Default = MatchConfig.RoundTime, Options = including({ 60, 90, 120, 180, 240, 300 }, MatchConfig.RoundTime) },
	{ Key = "LoadoutMode", Label = "LOADOUTS", Default = MatchConfig.DefaultLoadoutMode, Options = { "Draft", "Random" } },
	{ Key = "Reinforcements", Label = "REINFORCEMENTS", Default = MatchConfig.Reinforcements, Options = including({ 0, 3, 6, 10, 20 }, MatchConfig.Reinforcements) },
	{ Key = "HeadshotsOnly", Label = "HEADSHOTS ONLY", Default = false, Options = { false, true } },
	{ Key = "NoDrones", Label = "NO DRONES", Default = false, Options = { false, true } },
	{ Key = "FriendlyFire", Label = "FRIENDLY FIRE", Default = false, Options = { false, true } },
} :: { Setting }

CustomMatch.ByKey = {} :: { [string]: Setting }
for _, setting in CustomMatch.Settings do
	CustomMatch.ByKey[setting.Key] = setting
end

-- Every value `key` can take (`maps`: MapService.MapNames, for the map)
function CustomMatch.Options(key: string, maps: { string }): { any }
	local setting = CustomMatch.ByKey[key]
	if not setting then
		return {}
	end
	if setting.Options then
		return setting.Options
	end
	local list = { CustomMatch.RandomMap }
	table.move(maps, 1, #maps, 2, list)
	return list
end

function CustomMatch.Defaults(): Settings
	local settings = {}
	for _, setting in CustomMatch.Settings do
		settings[setting.Key] = setting.Default
	end
	return settings
end

-- A full, valid set of settings from whatever `raw` is (a client's or the teleport data's):
-- anything missing or not one of the options is the default
function CustomMatch.Sanitize(raw: any, maps: { string }): Settings
	local settings = CustomMatch.Defaults()
	if typeof(raw) ~= "table" then
		return settings
	end
	for _, setting in CustomMatch.Settings do
		local value = raw[setting.Key]
		if value ~= nil and table.find(CustomMatch.Options(setting.Key, maps), value) then
			settings[setting.Key] = value
		end
	end
	return settings
end

-- How a value reads in the menu ("3:00", "BOMB", "ON")
function CustomMatch.Label(key: string, value: any): string
	if typeof(value) == "boolean" then
		return if value then "ON" else "OFF"
	elseif key == "PrepTime" or key == "RoundTime" then
		return string.format("%d:%02d", value // 60, value % 60)
	elseif key == "GameMode" then
		return if value == "AttackDefend" then "BOMB" else "ELIMINATION"
	elseif key == "Rules" then
		local rules = GameRules.ById[value]
		return string.upper(if rules then rules.Name else tostring(value))
	elseif key == "Map" and value == "Flight9" then
		return "FLIGHT 9"
	end
	return string.upper(tostring(value))
end

-- ─── Match server (RoundService) ───────────────────────────────────────────────

-- The MatchState attributes a custom match sets, so Clear can take them all off again
local ATTRIBUTES = {
	"Custom", "CustomMap", "CustomRules", "CustomRoundsToWin", "CustomSwapSidesAfterRounds", "CustomPrepTime",
	"CustomRoundTime", "CustomReinforcements", "HeadshotsOnly", "NoDrones", "FriendlyFire",
}
local before: { [string]: any }? = nil -- (Studio plays it on the lobby server: what to put back after)

-- Sets this server up to play a custom match with `raw`'s settings (checked again here: they came
-- through a teleport). RoundService reads "Custom<Name>" in place of MatchConfig.<Name>, and the
-- "Custom" attribute stops every reward.
function CustomMatch.Apply(state: Instance, raw: any, maps: { string })
	local settings = CustomMatch.Sanitize(raw, maps)
	if not before then
		before = { GameMode = state:GetAttribute("GameMode"), LoadoutMode = state:GetAttribute("LoadoutMode") }
	end
	state:SetAttribute("Custom", true)
	state:SetAttribute("CustomMap", settings.Map)
	state:SetAttribute("CustomRules", settings.Rules)
	state:SetAttribute("GameMode", settings.GameMode)
	state:SetAttribute("LoadoutMode", settings.LoadoutMode)
	state:SetAttribute("CustomRoundsToWin", settings.RoundsToWin)
	-- (halftime one round before a team could win, like MatchConfig's 4 to win / swap after 3)
	state:SetAttribute("CustomSwapSidesAfterRounds", math.max(1, settings.RoundsToWin - 1))
	state:SetAttribute("CustomPrepTime", settings.PrepTime)
	state:SetAttribute("CustomRoundTime", settings.RoundTime)
	state:SetAttribute("CustomReinforcements", settings.Reinforcements)
	state:SetAttribute("HeadshotsOnly", if settings.HeadshotsOnly then true else nil)
	state:SetAttribute("NoDrones", if settings.NoDrones then true else nil)
	state:SetAttribute("FriendlyFire", if settings.FriendlyFire then true else nil) -- (WeaponService)
end

-- The match is over: back to normal matches (only matters in Studio, where it ran on the lobby server)
function CustomMatch.Clear(state: Instance)
	if state:GetAttribute("Custom") ~= true then
		return
	end
	for _, name in ATTRIBUTES do
		state:SetAttribute(name, nil)
	end
	if before then
		state:SetAttribute("GameMode", before.GameMode)
		state:SetAttribute("LoadoutMode", before.LoadoutMode)
		before = nil
	end
end

-- Is this a custom match (no rewards of any kind)? (MatchState "Custom")
function CustomMatch.IsCustom(state: Instance?): boolean
	return state ~= nil and state:GetAttribute("Custom") == true
end

return CustomMatch
