-- The music (tracks and slots: shared/Music). One player for the whole client: every frame it
-- works out which context fits (lobby playlist, prep bed, tension drone or nothing) from the
-- match phase and where you are, and crossfades into it. All of it goes through
-- SoundGroups.Music, so the MUSIC volume setting covers it.
--   Lobby playlist: shuffled, each track fades into the next a few seconds before it ends; quieter
--   in the practice range (state.inPractice).
--   Ducked while the kill cam or the results screen is up, and under a sting.
-- Stings: MusicController.Sting(name) from anywhere (MatchHud, MatchResults, ProgressMenu). They
-- play one at a time; one asked for while another is playing waits its turn (or is dropped if
-- that takes too long).
-- Slots with no id yet ("") are skipped quietly: until the ids are filled in this does nothing.

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Music = require(ReplicatedStorage.Shared.Music)
local state = require(script.Parent.Parent.PlayerState)
local SoundGroups = require(script.Parent.SoundGroups)

local MatchState = ReplicatedStorage:WaitForChild("MatchState")

local player = Players.LocalPlayer

local MusicController = {}

type Track = { Id: string, Volume: number, Pitch: number?, Looped: boolean?, Name: string? }
type Voice = {
	sound: Sound,
	context: string,
	track: Track,
	fade: number, -- 0..1
	target: number, -- what fade is heading for (0: fading out, then gone)
	fadeTime: number,
	startedAt: number,
	advanced: boolean, -- (playlist: the next track has already been started)
}

local LOAD_TIMEOUT = 10 -- seconds a track gets to load before the playlist skips it
local DUCK_SPEED = 4 -- how fast the duck eases in and out (per second)
local STING_REPEAT = 1 -- the same sting asked for again within this many seconds is ignored

local voices: { Voice } = {}
local currentContext: string? = nil
local contextScale = 1 -- (the practice range plays the lobby playlist quieter)
local duck = 1
local playlists: { [string]: { order: { number }, position: number, last: number? } } = {}

local stingQueue: { { name: string, at: number } } = {}
local stingSound: Sound? = nil
local stingDone = true
local stingStartedAt = 0
local lastSting: { [string]: number } = {}
local forcedTrack: number? = nil -- (dev panel: the next track to start, instead of the shuffle)
local forcedContext: string? = nil -- (dev panel: play this context whatever the game is doing; "Off" = silence)

local function playable(track: any): boolean
	return typeof(track) == "table" and typeof(track.Id) == "string" and track.Id ~= ""
end

-- The context's tracks that have ids, as indexes into Music.Contexts[name]
local function playableTracks(name: string): { number }
	local list = {}
	for i, track in Music.Contexts[name] or {} do
		if playable(track) then
			table.insert(list, i)
		end
	end
	return list
end

-- The next track of a context: shuffled, every track once before any repeats, and never the same
-- one twice in a row
local function nextTrack(name: string): Track?
	local list = playableTracks(name)
	if #list == 0 then
		return nil
	end
	if forcedTrack and Music.Contexts[name][forcedTrack] then
		local index = forcedTrack
		forcedTrack = nil
		if playlists[name] then
			playlists[name].last = index
		end
		return Music.Contexts[name][index]
	end
	local playlist = playlists[name]
	if not playlist or playlist.position >= #playlist.order or #playlist.order ~= #list then
		local order = table.clone(list)
		for i = #order, 2, -1 do
			local j = math.random(i)
			order[i], order[j] = order[j], order[i]
		end
		local last = playlist and playlist.last
		if #order > 1 and order[1] == last then
			order[1], order[#order] = order[#order], order[1]
		end
		playlist = { order = order, position = 0, last = last }
		playlists[name] = playlist
	end
	local p = playlist :: { order: { number }, position: number, last: number? }
	p.position += 1
	p.last = p.order[p.position]
	return Music.Contexts[name][p.last]
end

local function newSound(track: Track, looped: boolean): Sound
	local sound = Instance.new("Sound")
	sound.Name = "Music"
	sound.SoundId = track.Id
	sound.Volume = 0
	sound.PlaybackSpeed = track.Pitch or 1
	sound.Looped = looped
	sound.SoundGroup = SoundGroups.Music
	sound.Parent = SoundGroups.Music -- (not in a part: heard everywhere, not positional)
	return sound
end

local function startVoice(name: string, fadeTime: number)
	local track = nextTrack(name)
	if not track then
		return
	end
	-- A bed loops; a playlist track moves on to the next one (unless it's the only one, or Looped)
	local isPlaylist = #playableTracks(name) > 1
	local looped = if track.Looped ~= nil then track.Looped else not isPlaylist
	local sound = newSound(track, looped)
	sound:Play()
	table.insert(voices, {
		sound = sound,
		context = name,
		track = track,
		fade = 0,
		target = 1,
		fadeTime = fadeTime,
		startedAt = os.clock(),
		advanced = false,
	})
end

-- Which music fits right now, and how loud (1 = as set in Music)
local function pickContext(): (string?, number)
	if forcedContext then
		return if forcedContext == "Off" then nil else forcedContext, 1
	end
	local phase = MatchState:GetAttribute("Phase") or "Waiting"
	local location = player:GetAttribute("Location")
	if phase == "Vote" then
		return "Prep", 1 -- (the map vote is on everyone's screen)
	end
	if location == "Match" or state.spectating then
		if phase == "PreRound" or phase == "Prep" then
			return "Prep", 1
		elseif phase == "Planted" then
			return "Tension", 1
		elseif phase == "Action" then
			local left = (MatchState:GetAttribute("PhaseEndsAt") or 0) - Workspace:GetServerTimeNow()
			if left > 0 and left <= Music.TensionLastSeconds then
				return "Tension", 1
			end
		end
		return nil, 1 -- live round (footsteps!), round over, match over
	end
	if location == "Map" then
		return nil, 1 -- (dev free roam on the map: plays like a match)
	end
	if MatchState:GetAttribute("ServerKind") == "Match" then
		-- A match server's own little lobby (waiting for everyone to arrive, and after the match
		-- before the teleport back) and late joiners: never the lobby playlist mid-game
		return nil, 1
	end
	-- The lobby, the main menu, and before the server has said where you are
	if state.inPractice then
		return "Lobby", Music.PracticeVolume
	end
	return "Lobby", 1
end

local function setContext(name: string?)
	if name == currentContext then
		return
	end
	currentContext = name
	local revived = false
	for _, voice in voices do
		if name and voice.context == name and not revived and not voice.advanced then
			-- Came straight back to something still fading out: fade it back in
			voice.target = 1
			voice.fadeTime = Music.CrossfadeTime
			revived = true
		else
			voice.target = 0
			voice.fadeTime = Music.CrossfadeTime
		end
	end
	if name and not revived then
		startVoice(name, Music.CrossfadeTime)
	end
end

-- ─── Stings ─────────────────────────────────────────────────────────────────────

local function playSting(entry: Track)
	local sound = newSound(entry, false)
	sound.Name = "Sting"
	sound.Volume = entry.Volume
	stingSound = sound
	stingDone = false
	stingStartedAt = os.clock()
	sound.Ended:Connect(function()
		if stingSound == sound then
			stingDone = true
		end
		sound:Destroy()
	end)
	sound:Play()
	-- (one that never loads, or never says it ended, doesn't hold the queue up for long)
	task.delay(LOAD_TIMEOUT, function()
		if stingSound == sound and not sound.IsLoaded then
			stingDone = true
			sound:Destroy()
		end
	end)
end

local function updateStings()
	local sound = stingSound
	if sound and not stingDone and sound.IsLoaded and not sound.IsPlaying and os.clock() - stingStartedAt > 0.5 then
		stingDone = true -- (finished without Ended firing)
	end
	if not stingDone then
		return
	end
	stingSound = nil
	while #stingQueue > 0 do
		local queued = table.remove(stingQueue, 1) :: { name: string, at: number }
		if os.clock() - queued.at <= Music.StingMaxWait then
			playSting(Music.Stings[queued.name])
			return
		end
	end
end

-- A one-shot (Music.Stings[name]): RoundStart, RoundWin, RoundLoss, MatchWin, MatchLoss, MVP,
-- LevelUp, RankUp, RankDown. Does nothing if that slot has no id yet.
function MusicController.Sting(name: string)
	if not playable(Music.Stings[name]) then
		return
	end
	local now = os.clock()
	if now - (lastSting[name] or -math.huge) < STING_REPEAT then
		return
	end
	lastSting[name] = now
	table.insert(stingQueue, { name = name, at = now })
	updateStings()
end

-- ─── Every frame ────────────────────────────────────────────────────────────────

local function update(dt: number)
	local name, scale = pickContext()
	setContext(name)
	contextScale += (scale - contextScale) * math.min(1, dt * DUCK_SPEED)

	updateStings()
	local duckTarget = 1
	if state.killCam ~= nil or state.resultsOpen then
		duckTarget = Music.DuckVolume
	end
	if stingSound and not stingDone then
		duckTarget = math.min(duckTarget, Music.StingDuckVolume)
	end
	duck += (duckTarget - duck) * math.min(1, dt * DUCK_SPEED)

	for i = #voices, 1, -1 do
		local voice = voices[i]
		local sound = voice.sound
		local step = dt / math.max(voice.fadeTime, 0.05)
		if voice.fade < voice.target then
			voice.fade = math.min(voice.target, voice.fade + step)
		elseif voice.fade > voice.target then
			voice.fade = math.max(voice.target, voice.fade - step)
		end
		if voice.target == 0 and voice.fade <= 0 then
			sound:Destroy()
			table.remove(voices, i)
			continue
		end
		sound.Volume = voice.track.Volume * voice.fade * contextScale * duck

		-- Playlist: start the next track a little before this one ends (or if it won't load)
		if voice.target == 1 and not voice.advanced and not sound.Looped then
			local length = sound.TimeLength / math.max(sound.PlaybackSpeed, 0.01)
			local ending = sound.IsLoaded and length > 0
				and sound.TimePosition / math.max(sound.PlaybackSpeed, 0.01) >= length - Music.PlaylistCrossfade
			local stuck = not sound.IsLoaded and os.clock() - voice.startedAt > LOAD_TIMEOUT
			local stopped = sound.IsLoaded and not sound.IsPlaying and os.clock() - voice.startedAt > 1
			if ending or stuck or stopped then
				voice.advanced = true
				voice.target = 0
				voice.fadeTime = Music.PlaylistCrossfade
				if voice.context == currentContext then
					startVoice(voice.context, Music.PlaylistCrossfade)
				end
			end
		end
	end
end

-- ─── Dev panel ─────────────────────────────────────────────────────────────────

-- The voice that's playing now (the newest one not fading out)
local function liveVoice(): Voice?
	for i = #voices, 1, -1 do
		if voices[i].target == 1 then
			return voices[i]
		end
	end
	return nil
end

-- Jump `by` tracks through the current context's list (wraps round), with a quick crossfade
function MusicController.Skip(by: number)
	local name = currentContext
	if not name then
		return
	end
	local list = playableTracks(name)
	if #list == 0 then
		return
	end
	local voice = liveVoice()
	local current = voice and table.find(Music.Contexts[name], voice.track) or list[1]
	local at = table.find(list, current) or 1
	forcedTrack = list[(at - 1 + by) % #list + 1]
	for _, other in voices do
		other.advanced = true
		other.target = 0
		other.fadeTime = 0.6
	end
	startVoice(name, 0.6)
end

-- Play a context ("Lobby" / "Prep" / "Tension" / "Off") whatever the game is doing; nil = automatic
function MusicController.Force(name: string?)
	forcedContext = name
end

function MusicController.Forced(): string?
	return forcedContext
end

-- What's playing: "Lobby 2/4 · Lofi Electronic Chill", or "silent"
function MusicController.NowPlaying(): string
	local voice = liveVoice()
	if not voice then
		return "silent"
	end
	local list = playableTracks(voice.context)
	local index = table.find(Music.Contexts[voice.context], voice.track) or 0
	local place = table.find(list, index) or 0
	return `{voice.context} {place}/{#list} · {voice.track.Name or voice.track.Id}`
end

-- Play a sting right now (skips the repeat guard)
function MusicController.Preview(name: string)
	lastSting[name] = nil
	MusicController.Sting(name)
end

function MusicController.Start()
	-- Load the stings ahead of time so they land on cue (beds just start a moment later)
	local toLoad = {}
	for _, entry in Music.Stings do
		if playable(entry) then
			local sound = Instance.new("Sound")
			sound.SoundId = entry.Id
			table.insert(toLoad, sound)
		end
	end
	if #toLoad > 0 then
		task.spawn(function()
			pcall(ContentProvider.PreloadAsync, ContentProvider, toLoad)
		end)
	end
	RunService.Heartbeat:Connect(update)
end

return MusicController
