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

### 4d. Tutorial reward set in one place
- It was 250 in both `Tutorial.luau` (shown) and `TutorialService.luau` (paid). Now it's
  `MatchConfig.Credits.Tutorial`, next to the other credit amounts, and both read it.
  `TutorialService.Reward` had no other users, so it was removed. Nothing loops over
  `MatchConfig.Credits`, so the new entry can't show up anywhere unexpected.

### 4e. Unused code deleted
- Deleted `AntiCheat.Teleported` (every teleport uses the `ServerTeleport` attribute instead; the
  header comment now only describes that) and `DBNOService.IsDowned` (no callers). Re-grepped the
  whole tree, including string references, before deleting.
- **Not deleted:** `Effects.Sound`'s positional branch. Nothing passes a position, but removing
  it means dropping the parameter from all 18 callers, and some of those are in ShopMenu's Robux
  purchase banner, which I was told not to edit. Leaving one unused branch is cheaper than
  breaking that rule. Easy follow-up: drop the `position` parameter and the `if position` branch,
  and remove `, nil` from the 18 calls.

### 4f. graphify-out removed from git
- `git rm -r --cached graphify-out` (64 files) and `graphify-out/` added to `.gitignore`. The
  `--cached` flag only stops tracking them: your local copy is still there for graphify. It was a
  generated code map from Oct 8 that no longer matched the code.

### 4g. Attachments cache capped
- `Attachments.For` caches each decoded "Attachments" text forever, and every change a player
  makes adds a new one. Decision: empty the cache once it holds 200 entries (simplest bounded
  choice; anything still in use is decoded again on its next lookup, which is cheap). An LRU
  would keep hot entries but adds code for no visible gain at this size.

## 5. Research: every weak table (`__mode`), no code changed

Background: a weak table (`setmetatable({}, { __mode = "k" })`) lets Roblox drop an entry when
nothing else in Lua holds its key. Roblox can drop entries keyed by game objects (Instances) even
while the object still exists in the game; this project has hit that once already (the drone hum
made a new sound every frame). There are 9 weak tables:

| # | Where | Keyed by | What depends on it | If an entry is dropped | Change needed |
|---|---|---|---|---|---|
| 1 | `client/Abilities/GadgetWarnings.luau:39` `lastBeep` | placed device Model | frag tick, breach-charge beep timing | nothing else holds the device in Lua, so this is the likeliest to drop: the beep plays every frame | Plain table; each update, remove entries whose device has left the Deployables folder |
| 2 | `server/FortifyService.luau:56` `reinforcements` | wall section / hatch BasePart | `RemoveReinforcement` (thermite burning through) finds the steel to remove | the steel plate stays up after a hard breach (wall still blocked) | Plain table; `table.clear` in `Prepare` (map reload); entries are already removed when the steel goes |
| 3 | `server/FortifyService.luau:57` `barricades` | doorway / window slot BasePart | "take down barricade" (Unbarricade), exterior boarding in `Prepare`, the `Destroying` clean-up | defender's Unbarricade does nothing; `Prepare` could board a slot twice | Same as 2 |
| 4 | `server/GadgetService.luau:59` `breachCharges` | Player | second press detonates a placed breach charge | the second press places a new charge (uses a charge) instead of detonating | Plain table + clear the player's entry on PlayerRemoving. Low risk today: AbilityService's strong `lastUse[player]` keeps the Player alive in Lua after any gadget use |
| 5 | `server/GadgetService.luau:60` `scanning` | Player | heartbeat sensor on/off and its loop token | the scan loop stops early, or a second press starts a new scan instead of putting it away | Same as 4 |
| 6 | `server/GadgetService.luau:888` `nitroCells` | Player | second press detonates the thrown nitro cell | same as 4 | Same as 4 |
| 7 | `server/MatchStats.luau:54` `damageTo` | Humanoid | assists (who hurt a victim before someone else killed them) | an assist isn't credited | Plain table; entries are already cleared on death and at match start; also clear on the character's `Destroying` so bodies that never die don't linger |
| 8 | `server/RoundService.luau:104` `bodies` | Player | cached avatar (HumanoidDescription) for spawning, and the MVP screen's body | an extra web call on the next spawn (can fail), or the MVP shown without a body | Plain table + clear on PlayerRemoving |
| 9 | `client/Pose/BodyAnimator.luau:98` `warned` | character Model | warn once about a rig the animator can't pose | the same warning prints again (log spam only) | Plain table + clear when the character is removed (the animator already drops its rigs then) |

Priority: 2, 3 and 1 (gameplay-visible, and the keys have nothing else holding them), then 4–6,
then 7, 8, 9.

## 6. Research: save lock and failed teleports, no code changed

Both are **already fixed** earlier today (before this branch's overnight work):
- **Save lock** (`server/PlayerData.luau`, commit 3bb3608): autosave every 60 s and always writes
  (line 70), so every autosave renews the lock; lock expiry 150 s (line 71) with an `assert` that
  it outlasts two autosaves (line 73); the final save on leaving is retried 3 times
  (`releaseSave`, line 413); an autosave still in flight after the player left writes nothing
  (`session.leaving`, lines 302 and 310).
- **Failed match teleports** (`server/Matchmaker.luau`, commit 6033b67): `TeleportInitFailed` is
  handled (`onTeleportFailed` line 214, connected line 345): one retry into the same match server,
  then `requeue` (line 130) puts the party back at the front of the queue with "MATCH COULDN'T
  START · BACK IN THE QUEUE". An immediate `ReserveServer`/`TeleportAsync` error does the same.
  CustomMatchService also handles it (line 657) and keeps the lobby open until everyone has left.
- Neither can be verified in Studio: locks are off there and teleports run in-server. Both need
  the published-game test already in REVIEW.md's earlier notes (match → lobby keeps XP/credits).

## 7. Research: Gatling spin-up and barbed-wire slowdown, no code changed

**Where they're enforced today (client only):**
- Gatling spin-up: `client/Combat/WeaponController.luau:436-450`. The barrels' `spin` value rises
  while the trigger is held, and shots are only sent once `spin >= 1` (`spunUp`, line 450). The
  server (`server/WeaponService.luau`, `onFire`) checks the fire rate against the Gatling's full
  RPM from the first shot and has no idea about spin, so a modified client can fire at full rate
  instantly.
- Barbed wire slowdown: `client/Abilities/GadgetEffects.luau:122-142` (`slowInWire`) caps your own
  velocity at `WIRE_SPEED` each physics step. The server only uses the wire for the rattle sound
  (`GadgetService.watchWires`), and AntiCheat's speed limit is the 3-speed sprint
  (`server/AntiCheat.luau:39`, `:343`) everywhere, so a modified client walks through at full speed.

**What the server would need to check instead:**
- Gatling: the server can't see the trigger, and the client sends no shots while spinning up, so
  it needs to be told when spinning starts.
  - Add a small remote: the client sends "spin start" when the Gatling's trigger is pressed and
    "spin stop" when it's released.
  - The server records `spinStartedAt[player]` and, in `onFire` for weapons with `SpinUp`,
    refuses shots until `now - spinStartedAt >= SpinUp - slack`. Slack of about 0.15 s covers
    network jitter.
  - It clears the record on spin stop, on swapping weapons and on death.
  - Optionally, apply the `SpinSlow` move penalty in AntiCheat's speed limit while spinning.
  - A cheater could send "spin start" early, but that only matches what a real player gets by
    holding the trigger, so it isn't an advantage.
- Barbed wire: `watchWires` already finds every player inside a coil's zone (for the rattle).
  - Make it also mark them (for example a server-side set, or a `InWire` attribute set and
    cleared as they enter and leave).
  - AntiCheat's speed check uses `WIRE_SPEED × slack` instead of the sprint limit while a player
    is marked, so a modified client that skips the slowdown gets put back like any speed cheat.
  - Add a short grace (about 0.3 s) after they enter, so a legit player still slowing down from a
    sprint isn't flagged on the first step.
