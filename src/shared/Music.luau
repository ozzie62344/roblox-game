-- Music and stings (client Audio/MusicController plays them, through the MUSIC volume setting).
-- Every slot below wants a Roblox audio id ("rbxassetid://<id>", from the Studio Toolbox's Audio
-- tab or your own uploads). An empty Id ("") is simply skipped, so fill them in one at a time.
--
-- The slots, and what each one wants:
--   Lobby 1         chill electronic / hip-hop, 1–3 min, loopable (lobby, main menu, arrival wait)
--   Lobby 2         upbeat synth / lo-fi groove, 1–3 min, same energy as Lobby 1
--   Lobby 3         moodier downtempo / trap beat, 1–3 min (keeps the shuffle from feeling samey)
--   Lobby 4         optional: anything in the same family, 1–3 min (leave "" for a 3-track list)
--   Prep            tense low "get ready" bed: pulsing synth / ticking percussion, no melody to
--                   speak of, 30–90 s, seamless loop (map vote, loadout pick, defenders' setup)
--   Tension         very quiet dark drone / heartbeat pad, almost no rhythm, 20–60 s, seamless
--                   loop (last 30 s of a round, or once the defuser is planted; must not cover
--                   footsteps)
--   RoundStart      short hit / riser into a thud, 1–2 s (the round goes live)
--   RoundWin        short bright 2–3 note brass / synth, 1.5–3 s
--   RoundLoss       short low falling tone, 1.5–3 s
--   MatchWin        triumphant fanfare, 3–5 s (VICTORY on the results screen)
--   MatchLoss       somber, short, not annoying, 3–5 s (DEFEAT on the results screen)
--   MVP             sparkly "spotlight" flourish, 2–3 s (you're the match MVP)
--   LevelUp         bright arpeggio / chime, 1–2 s (LEVEL UP! banner)
--   RankUp          bigger rising flourish, 2–3 s (ranked: RANK UP! / PLACED!)
--   RankDown        soft descending tone, 1.5–2.5 s (ranked: RANK DOWN)
--
-- Each entry: Id, Volume (0..1, before the player's MUSIC setting), optional Pitch (playback
-- speed, 1 = as recorded) and Looped (beds loop by default; playlist tracks move on to the next
-- one unless Looped = true; stings never loop).

local Music = {}

-- What plays where (MusicController picks one from the match phase and where you are):
--   Lobby    the lobby (and the main menu / waiting for a match server to fill): shuffled, each
--            track crossfades into the next, round and round
--   Prep     map vote, the pre-round loadout pick and the defenders' setup
--   Tension  a live round's last TensionLastSeconds, or the defuser's countdown; otherwise a live
--            round has no music at all (you need to hear footsteps)
--   (nothing) round over / match over (the stings cover those), dev free roam on the map
Music.Contexts = {
	Lobby = {
		{ Id = "", Volume = 0.45 }, -- Lobby 1
		{ Id = "", Volume = 0.45 }, -- Lobby 2
		{ Id = "", Volume = 0.45 }, -- Lobby 3
		{ Id = "", Volume = 0.45 }, -- Lobby 4 (optional)
	},
	Prep = {
		{ Id = "", Volume = 0.35, Looped = true }, -- Prep
	},
	Tension = {
		{ Id = "", Volume = 0.18, Looped = true }, -- Tension
	},
}

-- One-shots, played over everything (not positional); one at a time, the next waits its turn
Music.Stings = {
	RoundStart = { Id = "", Volume = 0.6 },
	RoundWin = { Id = "", Volume = 0.6 },
	RoundLoss = { Id = "", Volume = 0.55 },
	MatchWin = { Id = "", Volume = 0.7 },
	MatchLoss = { Id = "", Volume = 0.6 },
	MVP = { Id = "", Volume = 0.65 },
	LevelUp = { Id = "", Volume = 0.6 },
	RankUp = { Id = "", Volume = 0.7 },
	RankDown = { Id = "", Volume = 0.55 },
}

Music.CrossfadeTime = 1.5 -- seconds: one context fading into the next
Music.PlaylistCrossfade = 3 -- seconds: a lobby track fading into the next one
Music.TensionLastSeconds = 30 -- a live round's last this-many seconds get the Tension bed
Music.PracticeVolume = 0.35 -- the lobby playlist in the practice range (0 = silent there)
Music.DuckVolume = 0.5 -- music while the kill cam or the results screen is up
Music.StingDuckVolume = 0.4 -- music under a sting
Music.StingMaxWait = 6 -- seconds a sting waits behind another before it's dropped

return Music
