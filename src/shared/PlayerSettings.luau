-- The player's own settings (SETTINGS menu, client SettingsMenu / ClientSettings): what each one
-- is, its default and its range. Shared so the server (SettingsService) checks what the client
-- sends against exactly the same rules, and keeps only what's listed here.
-- Saved with their data (PlayerData "Settings", JSON) so they follow them to every server.

local HttpService = game:GetService("HttpService")

export type Kind = "number" | "boolean" | "choice"
export type Def = {
	Key: string,
	Kind: Kind,
	Default: any,
	Min: number?, -- numbers: the range, and what they're rounded to
	Max: number?,
	Step: number?,
	Options: { string }?, -- choices
}

local PlayerSettings = {}

PlayerSettings.MaxJson = 2000

-- Crosshair colours (GAMEPLAY), in the order the menu shows them
PlayerSettings.CrosshairColorOrder = { "White", "Green", "Yellow", "Cyan", "Pink", "Red" }
PlayerSettings.CrosshairColors = {
	White = Color3.fromRGB(255, 255, 255),
	Green = Color3.fromRGB(90, 255, 110),
	Yellow = Color3.fromRGB(255, 230, 60),
	Cyan = Color3.fromRGB(70, 230, 255),
	Pink = Color3.fromRGB(255, 100, 210),
	Red = Color3.fromRGB(255, 70, 70),
}

PlayerSettings.List = {
	-- Controls (sensitivities are multipliers of the game's own speed: 1 = as designed)
	{ Key = "MouseSensitivity", Kind = "number", Default = 1, Min = 0.1, Max = 3, Step = 0.05 },
	{ Key = "TouchSensitivity", Kind = "number", Default = 1, Min = 0.1, Max = 3, Step = 0.05 },
	{ Key = "AdsSensitivity", Kind = "number", Default = 1, Min = 0.25, Max = 2, Step = 0.05 },
	{ Key = "InvertY", Kind = "boolean", Default = false },
	{ Key = "LeanToggle", Kind = "boolean", Default = true }, -- tap Q / E to lean (false: hold)
	-- Video
	{ Key = "Fov", Kind = "number", Default = 80, Min = 70, Max = 100, Step = 1 },
	{ Key = "PerformanceMode", Kind = "boolean", Default = false },
	{ Key = "ShowStats", Kind = "boolean", Default = false },
	-- Audio (0..1)
	{ Key = "MasterVolume", Kind = "number", Default = 1, Min = 0, Max = 1, Step = 0.05 },
	{ Key = "EffectsVolume", Kind = "number", Default = 1, Min = 0, Max = 1, Step = 0.05 },
	{ Key = "MusicVolume", Kind = "number", Default = 0.7, Min = 0, Max = 1, Step = 0.05 },
	{ Key = "UiVolume", Kind = "number", Default = 1, Min = 0, Max = 1, Step = 0.05 },
	-- Gameplay
	{ Key = "CrosshairColor", Kind = "choice", Default = "White", Options = PlayerSettings.CrosshairColorOrder },
	{ Key = "CrosshairSize", Kind = "number", Default = 1, Min = 0.5, Max = 2, Step = 0.1 },
	{ Key = "HitMarkers", Kind = "boolean", Default = true },
} :: { Def }

PlayerSettings.ByKey = {} :: { [string]: Def }
for _, def in PlayerSettings.List do
	PlayerSettings.ByKey[def.Key] = def
end

-- `value` made valid for setting `key` (numbers clamped and rounded to their step), or nil if it
-- can't be (wrong type, unknown setting or choice)
function PlayerSettings.Clean(key: string, value: any): any
	local def = PlayerSettings.ByKey[key]
	if not def then
		return nil
	end
	if def.Kind == "boolean" then
		return if typeof(value) == "boolean" then value else nil
	elseif def.Kind == "choice" then
		return if typeof(value) == "string" and table.find(def.Options :: { string }, value) then value else nil
	end
	if typeof(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return nil
	end
	local min, max, step = def.Min :: number, def.Max :: number, def.Step :: number
	local rounded = min + math.floor((math.clamp(value, min, max) - min) / step + 0.5) * step
	-- (a few decimals, so 0.1 + 0.05 * n doesn't come out as 0.15000000000000002)
	return math.clamp(math.floor(rounded * 1000 + 0.5) / 1000, min, max)
end

-- Every setting: the stored JSON's value where it has a valid one, otherwise the default
function PlayerSettings.Decode(json: any): { [string]: any }
	local values = {}
	for _, def in PlayerSettings.List do
		values[def.Key] = def.Default
	end
	if typeof(json) ~= "string" or json == "" or #json > PlayerSettings.MaxJson then
		return values
	end
	local ok, decoded = pcall(HttpService.JSONDecode, HttpService, json)
	if not ok or typeof(decoded) ~= "table" then
		return values
	end
	for key, value in decoded do
		local clean = if typeof(key) == "string" then PlayerSettings.Clean(key, value) else nil
		if clean ~= nil then
			values[key] = clean
		end
	end
	return values
end

-- The server's copy of what a client sent: only known settings, each cleaned. nil if it isn't
-- JSON at all.
function PlayerSettings.CleanJson(json: any): string?
	if typeof(json) ~= "string" or #json > PlayerSettings.MaxJson then
		return nil
	end
	if json == "" then
		return ""
	end
	local ok, decoded = pcall(HttpService.JSONDecode, HttpService, json)
	if not ok or typeof(decoded) ~= "table" then
		return nil
	end
	local clean = {}
	for _, def in PlayerSettings.List do
		local value = PlayerSettings.Clean(def.Key, decoded[def.Key])
		if value ~= nil then
			clean[def.Key] = value
		end
	end
	return HttpService:JSONEncode(clean)
end

return PlayerSettings
