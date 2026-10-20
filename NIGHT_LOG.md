# Night log (overnight-fixes)

Decisions and reasoning for each item, in order. Nothing here was run in Studio; each change was
type-checked with luau-lsp (Roblox definitions + a Rojo sourcemap). What to test is in REVIEW.md.

## 1. Downed players, dev End Round / Stop Match, defender site pick

- **Downed players:** the server now ignores `SetCrouch` (PoseService) and `Reload`
  (WeaponService) while the character has the `Downed` attribute. A revive clears `Downed` on the
  server before the client stands up, so the client's own stand-up message after a revive still
  gets through.
- **End Round / Stop Match:** the operator-select and prep waits were single `task.wait`s, so a
  press during them was lost (End Round) or only noticed a minute later (Stop Match). They now
  use `waitPhase`, which waits in 0.2 s steps and stops early. The End Round flag is reset when a
  round starts instead of when the action phase starts, so an early press isn't wiped.
  - Decision: an End Round during select/prep skips straight to the action phase, where the
    existing loop ends the round right away (the same "time up" / "ROUND ENDED" result as
    pressing it mid-round). The prep set-up steps (bombs, defuser, drones) still run first,
    because skipping them could leave the round half set up.
- **Site pick:** "one pick per round" could mean per player or per team. Decision: **one pick
  per defender per round**, plus a **2 s cooldown for the whole team** between changes, and
  picking the site that's already chosen does nothing. Locking the team to the first pick would
  let one player overrule everyone; per-player stops the spam while teammates can still change
  it. The attackers' spawn pick wasn't asked for and is unchanged.

## 2. Test for the party team-picking code

- `pickTeams` was a local function inside Matchmaker, which can't load outside Roblox. Decision:
  move it unchanged (same body, made generic over the unit type) into `src/server/PickTeams.luau`
  so it can be tested, and have Matchmaker require it. No behaviour change.
- Test: `tests/PickTeams.test.luau` (outside `src/`, so Rojo doesn't sync it), run with
  `lune run tests/PickTeams.test.luau`. 8 checks: 1v1, not enough players, a party of 3 never
  fits 2v2, 4v4 from 2+2+1+1+1+1 with parties kept whole, 4v4 from 3+3+1+1, 3v3 from 3+2+3,
  and nobody placed twice. All pass (Lune was run locally).
