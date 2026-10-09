-- Preloads every sound the game uses and hands out ready-to-play copies.
-- Without this, each sound file only starts downloading the first time it plays, which makes
-- gunshots (and other sounds) come in late.

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Sounds = require(ReplicatedStorage.Shared.Sounds)

local SoundCache = {}

local templates: { [string]: Sound } = {}
local folder: Folder? = nil

local function getFolder(): Folder
	if not folder then
		local newFolder = Instance.new("Folder")
		newFolder.Name = "SoundCache"
		newFolder.Parent = SoundService
		folder = newFolder
	end
	return folder :: Folder
end

-- One silent template per sound id; copies of a loaded template play instantly
local function template(soundId: string): Sound
	local existing = templates[soundId]
	if existing then
		return existing
	end
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Parent = getFolder()
	templates[soundId] = sound
	return sound
end

-- A fresh Sound for this id (set its volume/pitch/parent, then :Play())
function SoundCache.New(soundId: string): Sound
	return template(soundId):Clone()
end

-- Every sound id mentioned anywhere in Sounds.luau (single ids and the random sets)
local function collectIds(value: any, out: { string })
	if typeof(value) == "string" then
		if string.sub(value, 1, 3) == "rbx" then
			table.insert(out, value)
		end
	elseif typeof(value) == "table" then
		for _, child in value do
			collectIds(child, out)
		end
	end
end

function SoundCache.PreloadAll()
	local ids = {}
	collectIds(Sounds, ids)
	local toLoad = {}
	for _, id in ids do
		table.insert(toLoad, template(id))
	end
	-- Downloads in the background; anything played before it finishes still works, just later
	task.spawn(function()
		local ok, err = pcall(ContentProvider.PreloadAsync, ContentProvider, toLoad)
		if not ok then
			warn("[SoundCache] Preload failed:", err)
		end
	end)
end

return SoundCache
