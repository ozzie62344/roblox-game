-- Loads a game module from src/ in Lune, unchanged, for tests: Roblox's value types (Color3,
-- BrickColor, Vector3, Enum...) come from Lune's roblox library, `require(script.Parent.X)` finds
-- the sibling file, and `game:GetService(...)` hands back an empty stand-in (so a module can load,
-- but anything that really calls a Roblox service isn't testable here).
--   local Ranked = load("src/shared/Ranked")   -- path from the repo root, no extension

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local cache: { [string]: any } = {}
local load: (string) -> any

local game = {
	GetService = function(_self, _name: string)
		return {}
	end,
}

-- `script` for the module at `path`: script.Parent.X is the file X next to it
local function scriptFor(path: string)
	local folder = string.match(path, "^(.*)/[^/]+$") or "."
	local parent = setmetatable({}, {
		__index = function(_, name: string)
			return { __path = folder .. "/" .. name }
		end,
	})
	return { Parent = parent, Name = string.match(path, "([^/]+)$") }
end

function load(path: string): any
	if cache[path] ~= nil then
		return cache[path]
	end
	local file = if fs.isFile(path .. ".luau") then path .. ".luau" else path .. ".lua"
	local env = setmetatable({
		script = scriptFor(path),
		game = game,
		require = function(target: any)
			if type(target) == "table" and target.__path then
				return load(target.__path)
			end
			return require(target)
		end,
		Color3 = roblox.Color3,
		BrickColor = roblox.BrickColor,
		Vector3 = roblox.Vector3,
		Vector2 = roblox.Vector2,
		CFrame = roblox.CFrame,
		UDim = roblox.UDim,
		UDim2 = roblox.UDim2,
		ColorSequence = roblox.ColorSequence,
		NumberSequence = roblox.NumberSequence,
		Enum = roblox.Enum,
		Random = roblox.Random,
	}, { __index = getfenv() })
	local result = luau.load(fs.readFile(file), { debugName = path, environment = env })()
	cache[path] = result
	return result
end

return load
