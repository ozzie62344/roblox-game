-- Match and round rules. Times are in seconds.

return {
	MinPlayers = 2, -- a match starts automatically once this many players are in
	MaxTeamSize = 4,
	RoundsToWin = 4,

	StartCountdown = 5, -- "match starting" countdown
	PreRoundTime = 5, -- everyone frozen at spawn
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
