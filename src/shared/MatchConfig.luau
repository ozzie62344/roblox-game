-- Match and round rules. Times are in seconds.

return {
	MinPlayers = 2, -- a match starts automatically once this many players are in
	MaxTeamSize = 4,
	RoundsToWin = 4,

	StartCountdown = 5, -- "match starting" countdown
	PreRoundTime = 5, -- everyone frozen at spawn (Random loadouts)
	DraftTime = 10, -- frozen pre-round is this long in Draft mode, to pick a loadout

	-- "Draft" = pick 1 of 3 loadouts each round, "Random" = you get a random one.
	-- (Lobby voting will choose this later.)
	DefaultLoadoutMode = "Draft",
	DraftOptions = 3,

	-- Map loaded when the server starts ("House" or "TestArena"); the dev panel can switch it
	DefaultMap = "House",

	-- "AttackDefend" = plant / defuse a charge at site A or B, "Elimination" = last team standing.
	-- (Lobby voting will choose this later.)
	DefaultGameMode = "AttackDefend",
	SwapSidesAfterRounds = 3, -- halftime: attackers and defenders switch

	-- Attack / Defend
	PrepTime = 45, -- defenders set up (barricade, reinforce) while attackers wait in spawn (Siege ranked: 45)
	PlantTime = 4, -- hold G inside a site
	DefuseTime = 6, -- hold G next to the planted charge
	FuseTime = 45, -- seconds from plant to detonation
	DefuseRange = 5, -- studs from the charge
	-- Defender fortifications (Siege numbers)
	BarricadeTime = 2.5, -- hold G to board up a doorway / window
	ReinforceTime = 4.5, -- hold G to put a steel reinforcement on a soft wall section
	ReinforcementsPerDefender = 2, -- team pool per round = this × defenders (Siege's original rule)
	RoundTime = 120,
	PostRoundTime = 5,
	MatchOverTime = 10,
	FreeRoamRespawnTime = 3, -- respawn delay between matches

	Teams = {
		Blue = { Color = BrickColor.new("Bright blue") },
		Orange = { Color = BrickColor.new("Neon orange") },
	},
	TeamOrder = { "Blue", "Orange" },
}
