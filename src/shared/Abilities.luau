-- Abilities that can show up in loadouts. The movement code checks the player's "Ability"
-- attribute. Add new abilities here (and implement them) to put them in the loadout pool.

export type Ability = {
	Name: string,
	Key: string,
	Description: string,
}

local Abilities: { [string]: Ability } = {
	Dash = {
		Name = "Dash",
		Key = "F",
		Description = "Burst in the direction you're moving. Works once in the air.",
	},
	WallJump = {
		Name = "Wall Jump",
		Key = "Space",
		Description = "Jump off walls while in the air. Bounce between two walls to climb.",
	},
}

return Abilities
