-- Match and round rules. Times are in seconds.

return {
	MaxTeamSize = 4,
	RoundsToWin = 4,

	-- Lobby → match: in the lobby you press PLAY, tick the modes you want and queue (Matchmaker).
	-- When a queue is full, everyone in it is teleported to a private match server (a reserved
	-- server of this same place), votes on the map there, plays, and is sent back to a lobby.
	QueueModes = { "1v1", "2v2", "3v3", "4v4" }, -- players per team = the first number
	MapVoteTime = 15, -- the map vote is also the countdown before the match starts
	ArrivalTimeout = 40, -- match server: start anyway if someone still hasn't arrived by then

	PreRoundTime = 5, -- everyone frozen at spawn (Random loadouts)
	DraftTime = 10, -- frozen pre-round is this long in Draft mode, to pick a loadout

	-- "Draft" = pick 1 of 3 loadouts each round, "Random" = you get a random one.
	-- (Lobby voting will choose this later.)
	DefaultLoadoutMode = "Draft",
	DraftOptions = 3,

	-- Map loaded when the server starts ("House", "Warehouse" or "TestArena"); the dev panel can switch it
	DefaultMap = "House",

	-- "AttackDefend" = Siege's Bomb mode: defenders guard a bomb at site A and B, attackers plant
	-- a defuser on one; "Elimination" = last team standing. (Lobby voting will choose this later.)
	DefaultGameMode = "AttackDefend",
	SwapSidesAfterRounds = 3, -- halftime: attackers and defenders switch

	-- Attack / Defend
	PrepTime = 45, -- defenders set up (barricade, reinforce) while attackers wait in spawn (Siege ranked: 45)
	PlantTime = 4, -- attackers: hold G inside a bomb site to plant the defuser
	DisableTime = 6, -- defenders: hold G next to the planted defuser to disable it
	DefuserTime = 45, -- seconds from plant until the defuser has defused the bomb (attackers win)
	DisableRange = 5, -- studs from the defuser
	-- Defender fortifications (Siege numbers)
	BarricadeTime = 2.5, -- hold G to board up a doorway / window
	UnbarricadeTime = 1, -- defenders: hold G on a barricade to take it down (no shooting it apart)
	ReinforceTime = 4.5, -- hold G to put a steel reinforcement on a soft wall section
	ReinforcementsPerDefender = 2, -- team pool per round = this × defenders (Siege's original rule)
	MeleeCooldown = 1.5, -- seconds between knife swings (a stab to the body kills)
	RoundTime = 120,
	PostRoundTime = 5,
	MatchOverTime = 10,
	FreeRoamRespawnTime = 3, -- respawn delay between matches

	-- Credits: earned in matches (not in free roam), spent on skins in the lobby SHOP (Skins.luau).
	-- A full match is worth roughly 300-600.
	Credits = {
		Starting = 500, -- new players can buy a Common skin right away
		Kill = 20,
		Headshot = 10, -- on top of the kill
		Plant = 25, -- planting the defuser
		Disable = 25, -- disabling it
		RoundWin = 40, -- everyone on the team that won the round
		MatchWin = 150,
		MatchPlayed = 75, -- everyone who was there when the match finished
	},

	-- XP: earned for the same things (not in free roam), raises your level and unlocks the reward
	-- track (shared/Progression has the level curve). A won match is worth roughly 1,500, a lost
	-- one 700-900; level 2 takes 500, so the first match is worth about two levels.
	Xp = {
		Kill = 100,
		Headshot = 50, -- on top of the kill
		Plant = 150,
		Disable = 150,
		RoundWin = 100,
		MatchWin = 400,
		MatchPlayed = 300,
	},

	Teams = {
		Blue = { Color = BrickColor.new("Bright blue") },
		Orange = { Color = BrickColor.new("Neon orange") },
	},
	TeamOrder = { "Blue", "Orange" },
}
