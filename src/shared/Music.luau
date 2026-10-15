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
		{ Name = "Chill Electronic Lofi Beats", Id = "rbxassetid://126463622617576", Volume = 0.45 }, -- Lobby 1: "Chill Electronic Lofi Beats" (2:03)
		{ Name = "Lofi Electronic Chill", Id = "rbxassetid://110213863394929", Volume = 0.45 }, -- Lobby 2: "Lofi Electronic Chill" (3:15)
		{ Name = "Moving Round The Block", Id = "rbxassetid://9047105108", Volume = 0.45 }, -- Lobby 3: APM lo-fi hip hop, electric piano, instrumental (2:56)
		{ Name = "All Straight Vibing Out", Id = "rbxassetid://9046133702", Volume = 0.45 }, -- Lobby 4: APM lo-fi beat, moody synths, instrumental (1:53)
	},
	Prep = {
		{ Name = "Tension Repeat Drones 39", Id = "rbxassetid://1843739491", Volume = 0.35, Looped = true }, -- Prep: APM "Tension Repeat Drones 39" (2:09)
	},
	Tension = {
		{ Name = "Heavy Drone 25", Id = "rbxassetid://1843729378", Volume = 0.16, Looped = true }, -- Tension: APM "Heavy Drone 25" (2:05)
	},
}

-- One-shots, played over everything (not positional); one at a time, the next waits its turn
Music.Stings = {
	RoundStart = { Name = "All It Takes Sting 2", Id = "rbxassetid://9047103106", Volume = 0.5 }, -- APM "All It Takes Sting 2" (3.4 s)
	RoundWin = { Name = "Bigger Than Big 9", Id = "rbxassetid://1846901578", Volume = 0.55 }, -- APM "Bigger Than Big 9" (5.8 s)
	RoundLoss = { Name = "Mounting Consequences StingA", Id = "rbxassetid://125909120236588", Volume = 0.5 }, -- APM "Mounting Consequences StingA" (5.7 s)
	MatchWin = { Name = "1812 Overture (sting b)", Id = "rbxassetid://9045751375", Volume = 0.65 }, -- APM "1812 Overture (sting b)" (4.7 s)
	MatchLoss = { Name = "Downfall StingB", Id = "rbxassetid://115055593775910", Volume = 0.55 }, -- APM "Downfall StingB" (7 s)
	MVP = { Name = "Elated In Love", Id = "rbxassetid://1836860458", Volume = 0.6 }, -- APM "Elated In Love" horn sting (5.7 s)
	LevelUp = { Id = "rbxassetid://9042807094", Volume = 0.55 }, -- APM pop sting (3.9 s)
	RankUp = { Name = "Pride & Ambition StingB", Id = "rbxassetid://119099828605032", Volume = 0.65 }, -- APM "Pride & Ambition StingB" (6.5 s)
	RankDown = { Name = "Arch Rivalry StingB", Id = "rbxassetid://95364696869699", Volume = 0.5 }, -- APM "Arch Rivalry StingB" (6.2 s)
}

Music.CrossfadeTime = 1.5 -- seconds: one context fading into the next
Music.PlaylistCrossfade = 3 -- seconds: a lobby track fading into the next one
Music.TensionLastSeconds = 30 -- a live round's last this-many seconds get the Tension bed
Music.PracticeVolume = 0.35 -- the lobby playlist in the practice range (0 = silent there)
Music.DuckVolume = 0.5 -- music while the kill cam or the results screen is up
Music.StingDuckVolume = 0.4 -- music under a sting
Music.StingMaxWait = 6 -- seconds a sting waits behind another before it's dropped

return Music
