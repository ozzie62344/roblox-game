# BREACHPOINT

A Rainbow Six Siege–style tactical shooter on Roblox, written in Luau and synced into Studio with
Rojo. This file describes what the code does; `PROGRESS.md` is the status report,
`docs/R6_REFERENCE.md` the Siege numbers the game is tuned against.

## Project layout

`default.project.json` maps the repo into the Roblox DataModel:

| Folder | Becomes | What's in it |
|---|---|---|
| `src/shared/` | `ReplicatedStorage.Shared` | config and pure rules both sides read: `MatchConfig`, `MovementConfig`, `Weapons`, `Operators`, `Abilities`, `Attachments`, `Skins`, `Sounds`, `Music`, `GameRules`, `Ranked`, `Progression`, `Clans`, `CustomMatch`, `DBNO`, `PlayerSettings`, `Store`, `Characters` |
| `src/server/` | `ServerScriptService.Server` | one module per service; `init.server.luau` requires each and calls `.Start()` in order |
| `src/server/Maps/` | (under Server) | code-built maps (`House`, `Warehouse`, `Bank`, `Flight9`, `Lobby`) on top of `MapBuilder`, plus `MapCleanup` |
| `src/client/` | `StarterPlayerScripts.Client` | `init.client.luau` requires each controller and calls `.Start()`; folders `Abilities`, `Audio`, `Combat`, `Dev`, `Input`, `Lean`, `Match`, `Movement`, `Pose` |
| `src/first/` | `ReplicatedFirst` | the loading screen |
| `src/Health.server.luau`, `src/Animate.client.luau`, `src/RbxCharacterSounds.client.luau` | StarterCharacterScripts / StarterPlayerScripts | empty overrides that switch off Roblox's default health regen, animation and character sounds |
| `tests/` | not synced | Lune tests (see below) |

`ReplicatedStorage.MatchState` (a Folder) carries round state as attributes, and
`ReplicatedStorage.Remotes` holds the RemoteEvents. Most remotes are declared in
`default.project.json`; a few services create their own (for example DBNOService's `DBNO`).
`Workspace.StreamingEnabled` is off.

Maps: `MapService.Load(name)` clones `ServerStorage.Maps.<name>` if it exists (furniture dressed
in Studio, saved only in the place file: House and Warehouse) and otherwise runs the code builder.
Every load also runs `MapCleanup`, `FortifyService.Prepare` (reinforce sections, boarded-up
outside doors and windows), `CameraService.Build` (defender cameras from its `SPOTS` table) and
`LightingService.Apply`, and sets `MatchState.Map`.

## Two kinds of server

`RoundService` decides at startup: `IS_MATCH_SERVER` is a reserved private server (`PrivateServerId`
set, no owner). `MatchState.ServerKind` is `"Match"` or `"Lobby"`.

- **Lobby server.** Players spawn in the lobby (`Location = "Lobby"`, third person). Menus: play,
  ranked, party, clans, shop, progress, settings, custom matches, tutorial, and a practice range
  with bots. `Matchmaker` keeps per-mode queues (1v1–4v4, casual and ranked). When a queue can
  make two full teams without splitting a party (`PickTeams`), it reserves a server, writes a
  `MatchTicket` (MemoryStore, keyed by the reserved server's id) and teleports everyone.
  `CustomMatchService` does the same for custom lobbies (6-character codes in MemoryStore).
- **Match server.** `RoundService` reads the ticket (falling back to teleport data, never ranked),
  waits for the expected players, runs the match, then teleports everyone back to a lobby.
- **In Studio** there are no teleports: a full queue or custom match plays on the same server.

## Match flow (`RoundService`)

`mainLoop`: `Waiting` → map vote (`Vote`, or a custom match's setup) → `runMatch` → back to
`Waiting` (a match server sends everyone to the lobby).

Each round (`runRound`), as `MatchState.Phase`:
1. `PreRound`: everyone frozen at spawn; operator select (`LoadoutService` + client
   `LoadoutPicker`: operator, gun, secondary gadget), defenders pick the site pair, attackers
   their spawn.
2. `Prep` (bomb mode only): defenders set up (reinforce, barricade, gadgets), attackers drive
   drones (`DroneService`); defenders who leave the building are snapped back (`PerimeterService`).
3. `Action`: the round. Bomb mode: one attacker carries the defuser (`ObjectiveService`), plants
   it in a site → `Planted`; defenders disable it. Elimination: last team standing, no prep and
   no drones.
4. `PostRound`, then the next round. The map reloads every round from round 2 (round 1 uses the
   one the vote built). First to `RoundsToWin` wins; sides swap at halftime, and every round in
   overtime (after 3-3).
5. `MatchOver`: results and MVP (`MatchStats`), XP and credits (`ProgressService`, `ShopService`),
   ranked ratings (`RankedService`).

The dev panel (owner only, or anyone in Studio: `DevService`) can start a match, end a round,
stop a match, switch maps and hand out gadgets, coins and levels.

## Where each system lives

| System | Server | Client | Shared |
|---|---|---|---|
| Shooting, damage, hit zones, reloads, explosions (`Blast`) | `WeaponService` | `Combat/WeaponController`, `Viewmodel`, `GunModels`, `ReloadAnimations`, `LaserSights` | `Weapons`, `Attachments` |
| Knife | `WeaponService` | `Combat/Melee` | |
| Downed / revive | `DBNOService` | `Match/DBNOController` | `DBNO` |
| Destruction (walls, glass, barricades, floors, hatches) | `DestructionService` | `Combat/DestructionEffects` | |
| Reinforce / barricade | `FortifyService` | `Match/FortifyEffects` | |
| Gadgets (X) and secondaries (B) | `AbilityService` (slots, charges), `GadgetService` (each gadget) | `Abilities/AbilityController`, `HandsAnimator`, `GadgetEffects`, `GrenadeEffects`, `GadgetWarnings` | `Abilities`, `Operators` |
| Drones / defender cameras | `DroneService`, `CameraService` | `Abilities/DroneController`, `CamsController` | |
| Movement, vault, prone, rappel, lean | `PoseService` (replicated pose), `AntiCheat` (speed / teleport / noclip) | `Movement/MovementController`, `RappelController`, `Lean/LeanController`, `Pose/BodyAnimator` | `MovementConfig` |
| Bomb / defuser | `ObjectiveService` | `Match/ObjectiveController` | `MatchConfig` |
| Player data (save locks, autosave) | `PlayerData` | | |
| Credits shop / Robux store | `ShopService`, `StoreService` | `Match/ShopMenu`, `ModsMenu` | `Skins`, `Store` |
| XP, levels, daily rewards, challenges, leaderboards | `ProgressService`, `LeaderboardService` | `Match/ProgressMenu` | `Progression` |
| Ranked | `RankedService` | `Match/RankBadge`, results screen | `Ranked` |
| Parties / clans / custom matches | `PartyService`, `ClanService`, `CustomMatchService` | `Match/PartyMenu`, `ClanMenu`, `CustomMatchMenu` | `Clans`, `CustomMatch` |
| Sound | (server sends events) | `Audio/Sound3D` (falloff + wall muffling), `Footsteps`, `MusicController` | `Sounds`, `Music` |
| Lobby menus coming in on join | | `Match/LobbyIntro`, `MainMenu` | |

## Conventions seen in the code

- **Every file starts with a comment** explaining what it does and how it connects to the rest
  (which remotes, attributes and services). Comments are plain English, often with the "why" in
  brackets. Keep that style when adding code.
- **State is shared through attributes**, not shared tables: player attributes (`Location`,
  `Operator`, `Ability` / `AbilityCharges`, `Secondary` / `SecondaryCharges`, `Interaction`,
  `Droning`, `OnCams`, `Queued`, `Credits`...), character attributes (`Downed`, `Crouching`,
  `Prone`, `Vaulting`, `LookPitch`, `Lean`, `Scanning`, `Gesture`...) and `MatchState` attributes
  (`Phase`, `AttackTeam`, `SitePair`, `Map`, `Ranked`...). Clients read them; the server sets them.
- **The server checks everything a client asks for** (shots, gadgets, picks, purchases). Client
  checks are only for feel. Our own teleports set the player's `ServerTeleport` attribute so
  `AntiCheat` doesn't flag them.
- **Tuning numbers live in `src/shared`** config tables (`MatchConfig`, `MovementConfig`,
  `Weapons`, `Abilities`, `Sounds`, `Ranked`...), not in the services.
- **Naming:** modules and their public functions are PascalCase (`GadgetService.Handlers`,
  `MapBuilder.WallX`), locals camelCase, constants UPPER_SNAKE, tabs for indentation.
- **No weak tables** (`__mode`): Roblox can drop entries keyed by game objects that still exist.
  Use a normal table and remove entries on `Destroying` / `PlayerRemoving` / round reset.
- **Self-checks:** pure rules with a branch get an `assert`-based check that runs on load (for
  example in `Ranked`, `Operators`, `PlayerData`) or a Lune test.
- **`shortcut:` comments** mark a known limit and when to upgrade it.
- **Commits** use `git -c user.name="ozzie" -c user.email="ozzie@users.noreply.local" commit -m`
  (no global git identity is set). Files are CRLF in the working copy; Git normalises them.

## Checking changes

**Lune tests** (pure logic, outside Roblox). Run from the repo root:

```bash
lune run tests/Ranked.test.luau
```

The test files are `Ranked`, `Progression`, `Clans`, `CustomMatch` and `PickTeams`; each prints
`ok` / `FAIL` per check and ends with "all passed" (or errors). `tests/roblox.luau` loads a `src`
module unchanged, supplying Roblox value types and `script.Parent` requires. It can't run
anything that calls a Roblox service. `tests/check.luau` has the assertions. Tools are pinned in
`rokit.toml` (rojo, luau-lsp, lune).

**Type checking.** `luau-lsp analyze` with Roblox definitions and a Rojo sourcemap
(`rojo sourcemap default.project.json -o sourcemap.json`). It reports a handful of existing
warnings (for example `for x in t[k] or {}` loops); compare against the previous commit rather
than expecting zero.

**In Studio.** Rojo syncs `src/` into the open place. Teleports, DataStore save locks,
MemoryStore codes and tickets, and Robux purchases only work in the published game.
