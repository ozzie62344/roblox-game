# BREACHPOINT: status report

Written 2026-10-19 at commit `a746827` (78 commits, Oct 7 to Oct 15, about 48,000 lines of Luau).
Based on reading the whole `src/` tree and the git history. Nothing here was tested in a live game;
bugs marked "exploit only" only matter against a modified client.

---

## Where the project is

A Siege-style tactical FPS on Roblox. The game loop, four maps, twelve operators, destruction, and
the whole lobby/progression/social layer are built. The last finished stretch was the **R6 realism
pass**: part 1 (movement, gunplay, round flow) and part 2a (downed + revive, destruction, custom
matches). **Part 2b (gadgets + sound) is next and not started.**

Timeline:

| Dates | What landed |
|---|---|
| Oct 7–8 | Movement, gunplay, lean, rounds, loadouts, abilities, House map, animations, knife |
| Oct 9 | Destruction, fortifications, gadgets, Siege-size House, floors/hatches, drones, rappel, bomb mode, matchmaking |
| Oct 10–12 | Defender cameras, Warehouse, surface footsteps, smoke/flash, shop + skins, mobile controls, parties, attachments, Bank, operators, progression |
| Oct 13 | Flight 9 (replaced the Chalet), weather, practice range, ranked, settings, anti-cheat, tutorial, Robux store |
| Oct 14 | Music, clans, R6 realism pass part 1, R6 reference doc, operator select screen |
| Oct 15 | R6 part 2a (DBNO, destruction, custom matches), friendly fire on, tutorial button retires |

---

## Fully built

**Match**
- Lobby → queue (1v1–4v4, parties stay together) → reserved match server → map + mode vote → rounds → results → back to the lobby.
- Each round: operator select (20 s, live team picks, site and spawn choice), prep 45 s with drones, action 3:00, planted 45 s. First to 4, overtime swaps.
- Bomb mode with a carried defuser (drops on death, can be picked up), 7 s plant and disable. Team Elimination as a second mode.
- Game modes: Classic, Snipers / Shotguns / Pistols / Gatlings / Knives Only, Headshots Only.
- Custom matches: 6-character codes across servers, host controls teams and every rule, no rewards.
- Ranked from level 20: Elo, placements, Copper → Champion, leaving counts as a loss.

**Combat**
- The server checks every shot (rate, ammo, origin, line of sight, range, falloff, armor, hit zone, wall penetration). Hit markers wait for the server.
- Siege rules: headshots kill (not pellets or the Gatling), limbs 75%, armor 100/90/80%, learnable recoil, 30+1 tactical reloads, ADS times by class.
- 10 guns with hand-built models and reload animations, 6 attachments, skins, a MODS menu mid-match.
- Knife with cooldown; down-but-not-out with bleed-out, hold wound and revive.

**Movement**
- Siege speeds by speed rating, sprint-out, crouch, prone, vault and climb, lean (hold or toggle), rappel.

**Destruction and fortification**
- Soft walls (murder-hole grid), glass, barricades (3 knife hits / 20 bullets), wooden floors, hatches, armor panels.
- Team pool of 6 reinforcements, barricading and unbarricading.

**Gadgets and information**
- 12 operators, each with one gadget: breach charge, hard breach, EMP, flashbang, smoke, heartbeat sensor / shock wire, signal jammer, armor panel, deployable cover, barbed wire, impact grenade.
- Drones (2 per attacker), defender cameras on every map, spotting, team pings, the rule that reveals defenders who go outside.

**Maps**
- House, Warehouse, Bank and Flight 9: all in the vote, with cameras, spawns and four site pairs each.
- House and Warehouse furniture lives in the place file (`ServerStorage.Maps`); Bank and Flight 9 are entirely in code.

**Meta and social**
- Saved player data, credit shop (skins and attachments), exclusive and daily-streak skins.
- Levels 1–50 with a reward track, daily rewards, daily challenges, global leaderboards.
- Parties, clans (roles, requests, invites, chat tags, clan boards), scoreboard with ping.
- Practice range with bots, first-time tutorial, settings menu, music and stings, owner-only dev panel, editable mobile layout, anti-cheat basics.

---

## Half-finished

| What | Where | What's missing |
|---|---|---|
| R6 part 2b: gadgets + sound | — | Not started. Plan: secondary gadgets, grenade warning icons, electricity frying gadgets, Siege footstep ranges, audible reloads, loud event sounds |
| Robux store | `src/shared/Store.luau:59-90` | Every product and pass ID is still 0, so everything shows COMING SOON. Create them on the Roblox site and paste the IDs in |
| Game icon + thumbnails | dev board | Candidates exist; they still need the BREACHPOINT title and cropping to 1920×1080 / 512×512 |
| Placeholder sounds | `src/shared/Sounds.luau` (lines 98, 106, 115, 224, 232, 241) | Cover deploy, defuser beep, knife, hit markers and shop clicks still use Roblox's built-in sounds |
| Reload sound events | `src/client/Combat/WeaponController.luau:156` | The event name (MagOut, MagIn, SlideBack) is thrown away, so each plays a random foley sound |
| Elimination mode has no drones | `src/server/RoundService.luau:389-400` | Only bomb mode calls `DroneService.StartPrep`. Intended or not? |
| Old abilities still wired | Recon Pulse, Ghost Step (`Abilities.luau:24-42`, `AbilityService.luau:67-112`, Footsteps, MovementController) | No operator has them; only the dev panel can give them out. Remove them or make them gadgets |
| Untested outside the published game | Teleports, custom-match codes, data locks, clan sync, Robux receipts | Studio can't run these; they need a test with 2+ accounts in the live game |

---

## Known bugs

Ordered by how much they hurt real players.

1. **Progress can be lost when moving between servers.** `src/server/PlayerData.luau:70-71, 302`.
   A server only renews a player's save lock when it saves, every 180 s at best (and skips the save
   when nothing changed), but a lock counts as abandoned after 120 s. After a teleport (match → lobby),
   the new server can take the lock straight away and load old data; the old server's final save then
   sees someone else's lock and drops it. The player loses the XP, credits and stats from the last few
   minutes. **Checked by reading the code.**
2. **A failed match teleport strands players.** `src/server/Matchmaker.luau:152-165`. Nothing listens
   for `TeleportInitFailed`, and matched players were already taken out of the queue, so they sit on
   MATCH FOUND until the 30 s client timeout and are never re-queued.
3. **EMP can go off after the next round starts.** `src/server/GadgetService.luau:401-414`. When the
   map reload destroys the grenade, the loop ends and `emp()` runs anyway, so it can fry next round's
   cameras. The impact grenade and the other thrown grenades already check this.
4. **Dev panel End Round / Stop Match don't work during operator select or prep.**
   `src/server/RoundService.luau:380-416`. Dev-only.
5. **Small gameplay bugs:**
   - Your aim pitch isn't sent again after respawning (`BodyAnimator.luau:576-591`), so others see you aiming level until you look up or down.
   - A toggled lean comes back after a revive (`LeanController.luau:46-50`).
   - A second thermite can go on a wall that's already burning (`GadgetService.luau:297`), wasting a charge.
   - A defender reinforcing a wall can also start disabling the defuser (`ObjectiveService.luau:490`).
6. **Exploit only:**
   - A modified client can label a body hit within about 6 studs of the head as a headshot (`WeaponService.luau:309-321`).
   - Spamming vault, or claiming a rope that isn't there, switches off the noclip and fly checks (`AntiCheat.luau:246-366`, `PoseService.luau:55-79`).
   - The server lets you shoot while scanning, droning or on cams.
   - Match servers trust the teleport data of whoever arrives first (`RoundService.luau:739-750`), so ranked could be made unrated.
   - Gatling spin-up and barbed-wire slowdown only run on the client.

---

## Messy spots

- **Leftovers from removed movement:**
  - The `sliding` state in `PlayerState.luau:10` and `WeaponController.luau:101`.
  - The Lobby's SlideLane and WallJumpWall parts (`Maps/Lobby.luau:229-231`).
  - TestArena slide/dash/wall-jump comments.
  - "[F] Dash" and "jump buttons" in `Hud.luau`.
- **Leftovers from the old draft loadouts:** `MatchConfig.DraftOptions` is never read, and the `DraftPick` remote and comments in `GameRules`/`MatchConfig` are stale.
- **Round 1 builds the map twice** (vote, then `runRound`), including MapCleanup's passes.
- **Copy-pasted helpers:**
  - Server: `aliveRoot` (~6 files), `deployables()` (3), `isEnemy` (2), `LIVE_PHASES` (3), point-in-box tests (~5). The invite / rate-limit pattern repeats in Party, CustomMatch and Clan services.
  - Client: `inLobbyMenu` (7×), `thinOutline` (6×). Popup/panel builders repeat across ClanMenu, CustomMatchMenu and PartyMenu; they belong in `MenuStyle`.
  - Maps: the map-builder helpers (`door`, `wallX`, `sign` …) are copied into all four map files.
- **Very long files:** ClanService (1,637 lines), ClanMenu (1,432), ShopMenu (1,271), ProgressMenu (1,119), LoadoutPicker (1,472), Bank (2,358).
- **Stale names and comments:**
  - The Rojo project is still named `momentum-duels`.
  - `DevPanel.luau:1` says "everyone, for now" (it's owner-only).
  - The `GunMaterials` header mentions a texture SkinPainter no longer uses.
  - `graphify-out/` is from Oct 8 and doesn't describe the current code.

---

## Suggested next steps, in priority order

1. **Fix the save-lock data loss** (bug 1). Renew the lock on every autosave and make the expiry longer
   than the autosave interval. Small change, protects every player's progress.
2. **Handle failed match teleports** (bug 2). Re-queue players and tell them.
3. **R6 part 2b: gadgets + sound.** The plan you picked:
   - Secondary gadgets.
   - Grenade warning icons.
   - Electricity frying gadgets.
   - Siege footstep ranges.
   - Audible reloads and suppressors.
   - Loud event sounds.
4. **Quick gameplay fixes:** late EMP, aim pitch after respawn, lean after revive, double thermite, dev End Round.
5. **Go-live checklist:**
   - Create the Robux products and passes and paste their IDs.
   - Finish the icon and thumbnails.
   - Publish.
   - Test teleports, parties, custom codes and ranked with 2+ accounts.
6. **Close the exploit holes:**
   - Hit zone check.
   - Vault and rope checks.
   - No shooting during gadgets.
   - Sign or check the match teleport data.
7. **Cleanup pass:**
   - Remove slide / wall-jump / draft leftovers and Recon Pulse / Ghost Step (or turn them into gadgets).
   - Build the map once per round.
   - Move shared helpers into one module each.
   - Replace placeholder sounds.
