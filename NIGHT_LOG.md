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

## 3. Build the first map once per match

- `mainLoop` always runs the map vote (or a custom match's setup) right before `runMatch`, and
  both already call `MapService.Load`. Round 1 then loaded the same map again. Decision: skip the
  load in round 1 only (`if round > 1`). Every later round still gets a fresh map.
- Considered and rejected: tracking a "fresh map" flag. Every match goes through one of those two
  loads first, so the flag would never change the outcome.
- Small risk noted: in the second or so between the vote and round 1, someone free roaming on the
  map in Studio (dev panel) could break a wall, and round 1 would keep it broken. On a real match
  server everyone waits in the lobby during the vote.

## 4. Cleanup

### 4a. Duplicated helpers into shared places
- `deployables()` (the folder placed gadgets live in) was copied in AbilityService, DroneService
  and GadgetService. Decision: keep GadgetService's and export it as `GadgetService.Deployables`;
  the other two already require GadgetService, so no new module was needed.
- The live-phase list `{ Prep, Action, Planted }` was copied in CameraService, DroneService,
  PerimeterService and CamsController. It's now `MatchConfig.LivePhases`. RappelController's list
  is different on purpose (no rappelling during prep) and was left alone.
- `aliveRoot`, `isEnemy`, `inLobbyMenu` and `thinOutline` were already merged earlier today
  (shared/Characters, LobbyIntro, MenuStyle).

### 4b. Map-building helpers shared across the four maps
- Compared each helper's body across House, Warehouse, Bank and Flight9 (hashed). Identical:
  `door`, `doubleDoor`, `window`, `arch` (all four), `block` (three), `wallX`/`wallZ` (three).
  `cosmetic` differed only in that Flight9's returns the part.
- Decision: one copy of each in MapBuilder (`Door`, `DoubleDoor`, `Window`, `Arch`, `WallX`,
  `WallZ`, `Block`, `Cosmetic`; `Cosmetic` returns the part, which the other maps ignore), and
  each map's local becomes a one-line alias (`local door = MapBuilder.Door`) so no call site
  changes. 29 copies removed.
- Bank's `wallX`/`wallZ` were left alone on purpose: they also record every wall in a list the
  Bank uses later for its detail pass, so they're not duplicates.
- Type check: the same 5 warnings as before the change (checked against the previous commit in a
  scratch copy), none new.

### 4c. Shared invite logic: SKIPPED (risky, can't be tested here)
- The three services share only a small core: store an invite with an expiry, refuse a repeat
  while one is pending, and (Party, CustomMatch) a 30 s snooze after a NO. Around it they differ:
  - PartyService: keyed invitee → inviter, value = expiry time, snooze per inviter.
  - CustomMatchService: keyed invitee → lobby code, value = { from, ends }, snooze per lobby.
  - ClanService: keyed invitee → inviter, value = { clan id, ends }, no snooze at all.
  - Each has its own clean-up when a player leaves (dropping invites they sent or received).
- Invites are referenced about 30 times across those files. A shared module would touch every
  one, and invites can only be tested with two accounts in the published game, so a mistake
  would silently break party, clan and custom-lobby invites. Saving ~30 lines isn't worth that
  overnight.
- If you want it later, the shape that fits all three: a small `Invites.new(lifetime, snooze?)`
  object with `:CanSend(invitee, key)`, `:Send(invitee, key, value)`, `:Take(invitee, key)` →
  (value, expired), `:Snooze(invitee, key)` and `:Forget(player)`, keyed by whatever each service
  uses today (inviter or lobby code). Do it with a two-account test session ready.
