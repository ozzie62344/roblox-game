# Night log 2 (overnight-2)

Decisions and reasoning, item by item. Nothing was run in Roblox; every change was type-checked
with luau-lsp (Roblox definitions + a Rojo sourcemap), and Lune tests were run where noted. What to
test in Studio is in REVIEW_2.md.

## 1. Weak tables

Background (NIGHT_LOG.md item 5): a weak table can lose an entry keyed by a game object even while
that object still exists, so each was replaced with a normal table plus explicit clean-up.

### 1a. FortifyService `reinforcements` / `barricades`, GadgetWarnings `lastBeep`

Every read and write, traced before changing:
- `reinforcements` (section → steel model), `server/FortifyService.luau`:
  - written in `buildReinforcement`;
  - read and cleared in `RemoveReinforcement` (thermite, called from GadgetService.luau:358).
  - Nothing removed an entry when the map reloaded, so the fix adds the same `Destroying`
    clean-up the barricades already had.
- `barricades` (doorway → boards), `server/FortifyService.luau`:
  - read in the reach check (Unbarricade) and in `finish` (Unbarricade);
  - written in `buildBarricade`, which `Prepare` calls for exterior slots at every map load;
  - cleared by the boards' existing `Destroying` handler. Only the table type changed.
- `lastBeep` (device → time of last beep), `client/Abilities/GadgetWarnings.luau`:
  - read and written only in `update`.
  - Now pruned at the top of `update`: any device no longer in the Deployables folder is dropped
    (went off, shot, or a new round swept it away; also everything if the folder is gone).

"Cleaned up when the gadget is destroyed or the round ends": a new round reloads the map, which
destroys every plate and barricade (their `Destroying` runs) and the Deployables folder (the beep
pruning sees it gone).

### 1b. The other six weak tables (same approach clearly applied, so fixed too)
Traced each before changing; every one now has a clean-up point:
- GadgetService `breachCharges`, `scanning`, `nitroCells` (keyed by Player): read and written
  only inside the breach charge, heartbeat sensor and nitro cell handlers. Now normal tables
  emptied on `Players.PlayerRemoving` (a new module-level connection). Removing `scanning[player]`
  also ends a running scan loop, which checks its token each beat.
- RoundService `bodies` (Player → cached avatar): read in `loadCharacter` and by the MVP screen
  (`MatchStats.Finish` callback). Emptied on PlayerRemoving (connected in `RoundService.Start`).
  If the MVP has left, the body was already unavailable before this change.
- MatchStats `damageTo` (Humanoid → damage per attacker, for assists): already cleared on each
  death and at every match start, so only the table type changed. A body that despawns without
  dying (a new round respawns everyone) stays until the next match starts: bounded, small.
- BodyAnimator `warned` (character → "R6 avatar" warning shown): pruned in the same per-frame
  loop that already forgets rigs of characters that are gone.
- After this, `grep __mode` finds nothing in the project.

## 2. Small gameplay bugs: all five already fixed, no code changed

Checked git log and the current code. Each fix landed on Oct 19 and is still in place:
| Bug | Commit | Where the fix is now |
|---|---|---|
| EMP going off after the next round starts | a8c1bc9 | `server/GadgetService.luau:421` (returns if the grenade was swept away) |
| Aim pitch not resent after respawn | 65a6db9 | `client/Pose/BodyAnimator.luau:608` (`lastSentPitch` reset on CharacterAdded) |
| Toggled lean returning after a revive | ab5bb35 | `client/Lean/LeanController.luau:46` (going down clears the toggle) |
| Second thermite on a burning wall | 99714e3 | `server/GadgetService.luau:300, 335-337` (`Burning` attribute) |
| Reinforcing while also disabling the defuser | d87b5cf | `server/ObjectiveService.luau:494` (refuses while `Interaction` is set) |

## 3. No shooting while scanning, droning or on cameras: already in place, no code changed

- Added on Oct 19 in cb407e0. `server/WeaponService.luau` `handsBusy` (line 347) returns true
  while the player has `Droning` (DroneService) or `OnCams` (CameraService), is mid-hold
  (`Interaction`), or their character has `Scanning` (GadgetService heartbeat sensor, set when a
  scan starts and cleared on put-away, on finishing, and on death).
- It's checked in shot validation (`onFire`, line 370) and for the knife (line 485). That's the
  only place it lives: anti-cheat movement checks don't use it, as asked.

## 4. Lune tests for pure logic

**Decision: load the modules unchanged instead of moving functions out.** The candidates (ranked
MMR, XP curve / reward track, clan rules, custom-match settings) already live in their own
`src/shared` files. The only things stopping Lune from running them were Roblox value types
(Color3, BrickColor, Enum) and `require(script.Parent.X)`. Moving functions out would mean editing
every module that imports them; a loader means no game code changes at all.
- `tests/roblox.luau` runs a `src` module in Lune with Lune's Roblox value types,
  `script.Parent.X` requires resolved to sibling files, and an empty stand-in for
  `game:GetService` (enough to load Attachments; nothing calls a service).
- `tests/check.luau` holds tiny assertion helpers.
- Run any test from the repo root with `lune run tests/<Name>.test.luau`. All 5 files pass.

| Test | Covers | Checks |
|---|---|---|
| `Ranked.test.luau` | Elo expectation, round share, performance and its cap, win/loss floors, placements, rank names | 23 |
| `Progression.test.luau` | XP per level and its cap, level from total XP, reward track (every level real, every track skin on it, item price, credit piles), daily streak | 26 |
| `Clans.test.luau` | name / tag / text cleaning, clan types, badge fallback, role order, level and rank requirements | 22 |
| `CustomMatch.test.luau` | defaults, every default is an option, Sanitize keeps valid values and drops bad ones / unknown keys / unknown maps, sizes, code alphabet | 14 |
| `PickTeams.test.luau` (last night) | party team picking | 8 |

**Skipped:**
- **Clan role permissions** (who can kick / promote / demote / transfer). The rules live inside
  `ClanService.manage`'s DataStore update callback, mixed with record edits and the activity log.
  Moving them out means restructuring, not moving a function unchanged, so it's out of scope.
  What is tested: `Clans.Roles` ordering, which the kick rule compares.
- **`CustomMatch.Apply` / `Clear` / `IsCustom`**: they write a Roblox instance's attributes.
- **Challenges** (`Progression.RollChallenges`): seeded `Random`; Lune's `Random` may not match
  Roblox's sequence, so a test could pass here and mean nothing in game.

One test of mine was wrong on the first run: I assumed level 10 on the reward track is a credits
pile, but it's a skin. I fixed the test (it now finds the first credits level divisible by 5);
the game code was right.
