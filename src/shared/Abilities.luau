-- Abilities that can show up in loadouts (every ability here is in the draft/random pool).
--   Movement abilities live in MovementController (Dash on F, Wall Jump on Space).
--   Active abilities are used with F, run on the server (AbilityService), and have charges per round.

export type Ability = {
	Name: string,
	Key: string,
	Description: string,
	Kind: "Movement" | "Active",
	Charges: number?, -- uses per round (active abilities)
	Duration: number?, -- seconds the effect lasts
	Radius: number?, -- studs
}

local Abilities: { [string]: Ability } = {
	Dash = {
		Name = "Dash",
		Key = "F",
		Kind = "Movement",
		Description = "Burst in the direction you're moving. Works once in the air.",
	},
	WallJump = {
		Name = "Wall Jump",
		Key = "Space",
		Kind = "Movement",
		Description = "Jump off walls while in the air. Bounce between two walls to climb.",
	},
	ReconPulse = {
		Name = "Recon Pulse",
		Key = "F",
		Kind = "Active",
		Charges = 2,
		Duration = 3,
		Radius = 60,
		Description = "Reveal nearby enemies through walls to your team. They know they've been scanned.",
	},
	GhostStep = {
		Name = "Ghost Step",
		Key = "F",
		Kind = "Active",
		Charges = 2,
		Duration = 8,
		Description = "Your footsteps, jumps and landings are silent for 8 seconds.",
	},
	DeployableCover = {
		Name = "Deployable Cover",
		Key = "F",
		Kind = "Active",
		Charges = 2,
		Duration = 1.2, -- deploy time: you can't move or shoot while pulling it up
		Description = "Pull a waist-high bulletproof shield out of the ground. Crouch behind it or shoot over it.",
	},
}

return Abilities
